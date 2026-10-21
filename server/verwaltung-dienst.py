#!/usr/bin/env python3
# Hilfsdienst fuer die Verwaltungsseite /admin/ auf dem Host, laeuft als root (systemd: pacs-verwaltung.service).
# Helper service for the admin panel (disks, firewall, audit log). Listens on unix sockets only, never on a TCP port.
# Hoert nur auf dem Unix-Socket PACS_SOCKET (Standard /run/pacs-admin/verwaltung.sock). Das Verzeichnis ist in den
# nginx-Container gemountet, der Socket gehoert PACS_SOCKET_UID (Standard 101 = nginx im offiziellen Image), Rechte 0600.
# nginx laesst nur die berechtigte Gruppe durch, verlangt fuer POST die Kopfzeile X-PACS-Admin, gibt das Konto in
# X-Auth-User und den PC in X-Real-IP mit und schreibt POSTs mit Konto ins Verwaltungsprotokoll. Der Dienst kann genau das:
#   GET  /admin/dienst/platten      nach neuen Platten suchen (SCSI neu einlesen), Uebersicht neu (dashboard-status.py)
#   POST /admin/dienst/einrichten   {"geraet": "/dev/sdX", "groesse": Bytes, "name": "PACS-DataNN"}: pacs-storage.sh
#                                   add GERAET ja im Hintergrund, nur wenn die Platte gerade genau so als leer erkannt
#                                   ist und NAME die naechste Nummer (= genau das, was der Admin bestaetigt hat).
#                                   Nur ganze Platten: /dev/sdX, /dev/vdX, /dev/xvdX, /dev/nvmeNnM
#   GET  /admin/dienst/auftrag      Stand und Ausgabe des letzten Einrichtens (steht auch im Log von pacs-storage.sh)
#   POST /admin/dienst/freigeben    {"platte": "PACS-DataNN"}: Markierung "voll" entfernen (pacs-storage.sh freigeben)
#   POST /admin/dienst/anhaengen    {"platte": "PACS-DataNN"}: hinten an die Schreibliste (pacs-storage.sh anhaengen)
#                                   beide nur ab STORAGE_FREE_GB frei (Standard 50), das prueft pacs-storage.sh selbst
#                                   und meldet es mit diesem Wert (HALT-Zeile, kommt als "fehler" zurueck)
#   POST /admin/dienst/abhaengen    {"platte": "PACS-DataNN"}: aus der Schreibliste nehmen (pacs-storage.sh abhaengen),
#                                   nie die letzte nicht volle Platte, das prueft pacs-storage.sh selbst
#                                   Plattennamen: STORAGE_PREFIX (Standard PACS-Data) plus Ziffern
#   GET  /admin/dienst/protokoll    Protokollzeilen aus der verschluesselten Datenbank (pacsdb.py), je Zeile ein JSON.
#                                   ?quelle=zugriffe,ereignisse,admin (Standard ereignisse,admin) &von=&bis=JJJJ-MM-TT
#                                   (Standard 30 Tage) oder &letzte=N (hoechstens 1000)
#   GET  /admin/dienst/firewall     Regeln, Zaehler, abgewiesene Versuche, DICOM-/HL7-Absender (firewall.py status),
#                                   ?neu=1 liest vorher neue Absender aus dem server.log (sonst alle 5 Minuten) und sucht
#                                   Client-PCs im DNS (sonst stuendlich)
#   POST /admin/dienst/firewall     alle Regeln {aktiv, schnittstelle, regeln}: pruefen, sichern, anwenden (firewall.py).
#                                   Abgelehnt, wenn der eigene PC (X-Real-IP von nginx) danach den https-Port (erster
#                                   von FW_WEB_PORTS, Standard 443) nicht mehr erreicht (nicht geprueft fuer Adressen
#                                   aus den Docker-Netzen: ueber IPv6 kommt der PC als Docker-Gateway an)
#                                   Fehler der Firewall (z. B. FW_DEFAULT_RULES ungueltig) kommen als 500 mit Grund
# Dazu nimmt er auf PACS_LOG_SOCKET (Standard /run/pacs-admin/protokoll.sock, Datagramme) die Protokollzeilen von nginx
# an (access_log syslog, Kennung zugriffe|ereignisse|admin) und legt sie alle 2 Sekunden gesammelt in der Datenbank ab.
# pacs-storage.sh und dashboard-status.py liegen im selben Verzeichnis wie dieses Skript.
# Start: both sockets are bound and handed to PACS_SOCKET_UID first, the worker threads start afterwards. Every startup
# error (library missing, bad number in the environment, socket path too long, not root, a second instance already
# listening on the socket) ends with ONE line on stderr and exit code 1, no traceback. Do not start the service by hand
# while pacs-verwaltung.service runs: the second instance refuses to start instead of taking over the socket.
import datetime, http.server, json, os, pwd, queue, re, signal, socket, socketserver, subprocess, sys, threading, time, urllib.parse
try:
    import firewall, pacsdb
except ImportError as e:   # z. B. libsqlcipher fehlt: die Meldung nennt die Pakete
    sys.exit("verwaltung-dienst.py: %s" % e)


def umgebung_int(name, vorgabe):
    wert = os.environ.get(name) or str(vorgabe)
    if not re.fullmatch(r"0|[1-9][0-9]{0,9}", wert):   # int() naehme auch "+5", " 5", "1_0", "007" und andere Ziffernschriften an
        sys.exit("verwaltung-dienst.py: %s=%s ist keine ganze Zahl ohne fuehrende Null mit hoechstens 10 Stellen (/etc/default/pacs-admin)" % (name, wert))
    return int(wert)


SOCK = os.environ.get("PACS_SOCKET") or "/run/pacs-admin/verwaltung.sock"
PROTOKOLL_SOCK = os.environ.get("PACS_LOG_SOCKET") or "/run/pacs-admin/protokoll.sock"
SOCKET_UID = umgebung_int("PACS_SOCKET_UID", 101)
if not 0 <= SOCKET_UID < 2 ** 32 - 1:
    sys.exit("verwaltung-dienst.py: PACS_SOCKET_UID=%d ist keine gueltige uid (/etc/default/pacs-admin)" % SOCKET_UID)
BIN = os.path.dirname(os.path.abspath(__file__))
STORAGE = ["/bin/bash", os.path.join(BIN, "pacs-storage.sh")]
DASHBOARD = [sys.executable, os.path.join(BIN, "dashboard-status.py")]
ZEIT = 300   # Sekunden, die pacs-storage.sh (ausser add) und dashboard-status.py je Aufruf bekommen
RC_NICHT_NEU_GELADEN = 3   # Exit-Code von pacs-storage.sh: im LDAP geaendert, das Archiv hat die Konfiguration aber nicht neu geladen
GERAET =re.compile(r"/dev/(sd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme[0-9]+n[0-9]+)")   # ganze Platten, keine Partitionen
PLATTE = re.compile(re.escape(os.environ.get("STORAGE_PREFIX") or "PACS-Data") + r"[0-9]+")   # \d liesse auch andere Ziffernschriften zu
QUELLEN = ("zugriffe", "ereignisse", "admin")
SYSLOG = re.compile(r"<\d+>.{15} (zugriffe|ereignisse|admin): (.*)", re.S)   # nginx: <PRI>Mmm dd hh:mm:ss TAG: MSG
auftrag = {}
sperre = threading.Lock()
eingang = queue.Queue()


def laeuft_schon(pfad, typ):
    """Nimmt ein Prozess auf dem Socket Verbindungen an? Eine liegengebliebene Datei ohne Prozess antwortet mit Fehler."""
    s = socket.socket(socket.AF_UNIX, typ)
    s.settimeout(2)
    try:
        s.connect(pfad)
        return True
    except socket.timeout:   # Warteschlange voll: da lauscht jemand
        return True
    except OSError:
        return False
    finally:
        s.close()


def socket_frei(pfad, typ, name):
    """Verzeichnis anlegen (0755, nginx im Container muss hinein), alten Socket entfernen. Lauscht noch ein Dienst auf
    dem Socket, bricht der Start ab: dessen Socket wird nicht entfernt."""
    if len(os.fsencode(pfad)) > 107:   # sun_path fasst 108 Bytes
        sys.exit("verwaltung-dienst.py: %s=%s ist zu lang (%d Bytes, Unix-Sockets erlauben hoechstens 107)"
                 % (name, pfad, len(os.fsencode(pfad))))
    os.makedirs(os.path.dirname(os.path.abspath(pfad)), mode=0o755, exist_ok=True)
    if os.path.lexists(pfad):
        if laeuft_schon(pfad, typ):
            sys.exit("verwaltung-dienst.py: laeuft schon, auf %s lauscht ein Dienst (systemctl status pacs-verwaltung). "
                     "Nicht von Hand starten, solange der Dienst laeuft." % pfad)
        os.unlink(pfad)


def socket_fuer_nginx(pfad):
    os.chown(pfad, SOCKET_UID, -1)   # nur nginx im Container (und root)
    os.chmod(pfad, 0o600)


def empfangen(s):
    while True:
        m = SYSLOG.match(s.recv(1 << 20).decode("utf-8", "replace"))
        if m:
            eingang.put((m.group(1), m.group(2).strip()))


def zeit_von(zeile):
    try:
        return pacsdb.zeitpunkt(json.loads(zeile).get("t"))
    except (ValueError, AttributeError):
        return time.time()


def ablegen():
    while True:
        zeilen = [eingang.get()]
        time.sleep(2)
        while not eingang.empty():
            zeilen.append(eingang.get_nowait())
        while True:   # Datenbank gesperrt o. ae.: Zeilen behalten und neu versuchen
            try:
                with pacsdb.Db() as db:
                    db.viele("insert into protokoll (quelle, zeit, zeile) values (?, ?, ?)",
                             [(q, zeit_von(z), z) for q, z in zeilen])
                break
            except Exception as e:
                print("Protokoll nicht abgelegt (%d Zeilen), neuer Versuch in 10 s: %s" % (len(zeilen), e), file=sys.stderr, flush=True)
                time.sleep(10)


def versuchen(schritt, *args):   # Fehler nur ins Log (journal), der Rest laeuft weiter
    try:
        schritt(*args)
    except Exception as e:
        print("%s: %s" % (schritt.__name__, e), file=sys.stderr, flush=True)


def absender_takt():   # alle 5 Minuten: neue DICOM-/HL7-Absender, neue Docker-Ports unter den Firewall-Standard,
    while True:          # stuendlich Client-PCs (nur mit FW_CLIENT_NAMES)
        for schritt in (firewall.absender_sammeln, firewall.nachziehen, firewall.clients_suchen):
            versuchen(schritt)
        time.sleep(300)


def jetzt():
    return time.strftime("%Y-%m-%dT%H:%M:%S")


def lauf(argv, zeit):
    """Wie subprocess.run(argv, capture_output=True, encoding="utf-8", timeout=zeit), nur ohne den Haenger von Python 3.7
    (Debian 10, bpo-37424): run() wartet nach dem Abbruch, bis auch ein Enkelprozess (docker exec, tee) die Pipes schliesst,
    und haelt den Thread bis dahin fest. Darum eigene Sitzung und SIGKILL an die ganze Gruppe. Dieselbe Funktion steht
    in dashboard-status.py."""
    p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8",
                         errors="replace", start_new_session=True)
    try:
        aus, fehler = p.communicate(timeout=zeit)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:   # schon beendet
            pass
        p.stdout.close()   # kein zweites communicate(): ein Enkel ausserhalb der Gruppe haelt die Pipes sonst weiter offen
        p.stderr.close()
        try:
            p.wait(5)
        except subprocess.TimeoutExpired:   # haengt im Kernel (Zustand D, z. B. eine Platte): nicht darauf warten
            pass
        raise subprocess.TimeoutExpired(argv, zeit)
    return subprocess.CompletedProcess(argv, p.returncode, aus, fehler)


def kandidaten():
    """Leere Platten und naechster Name aus pacs-storage.sh. Bricht das Skript ab (HALT, z. B. wegen eines Fehlers in
    /etc/default/pacs-admin), kommt dessen Grund als RuntimeError statt einer leeren Liste."""
    platten, name = [], ""
    r = lauf(STORAGE + ["kandidaten"], ZEIT)
    if r.returncode:
        halt = re.search(r"HALT: (.*)", r.stdout)
        raise RuntimeError(halt.group(1) if halt else "pacs-storage.sh kandidaten ist fehlgeschlagen")
    for z in r.stdout.splitlines():
        f = z.split()
        if f[:1] == ["kandidat"] and len(f) >= 3 and f[2].isdigit():
            platten.append((f[1], int(f[2])))
        elif f[:1] == ["naechste"] and len(f) == 2:
            name = f[1]
    return platten, name


def einrichten(geraet):
    try:
        p = subprocess.Popen(STORAGE + ["add", geraet, "ja"], stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, encoding="utf-8", errors="replace")
        for z in p.stdout:
            auftrag["ausgabe"] += z
        auftrag["rc"] = p.wait()
        subprocess.run(DASHBOARD, timeout=ZEIT)   # neue Platte gleich in der Uebersicht
    except Exception as e:
        auftrag["ausgabe"] += "\nFEHLER im Dienst: %s\n" % e
        auftrag.setdefault("rc", 1)
    finally:
        auftrag.update(laeuft=False, ende=jetzt())


class Anfrage(http.server.BaseHTTPRequestHandler):
    timeout = 30   # Sekunden Wartezeit auf Daten: ein Client, der Header oder Body nie fertig schickt, haelt sonst einen Thread fest

    def senden(self, code, daten):
        b = daten if isinstance(daten, bytes) else json.dumps(daten, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path.startswith("/admin/dienst/protokoll?") or self.path == "/admin/dienst/protokoll":
            return self.protokoll(urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query))
        if self.path == "/admin/dienst/platten":
            r = lauf(DASHBOARD, ZEIT)
            if r.returncode:   # z. B. eine ungueltige Zahl in /etc/default/pacs-admin: der Grund (letzte Zeile) geht an die Seite
                return self.senden(500, {"ok": False, "fehler": (r.stderr.strip().splitlines() or ["dashboard-status.py ist fehlgeschlagen"])[-1]})
            return self.senden(200, {"ok": True})
        if self.path == "/admin/dienst/auftrag":
            return self.senden(200, dict(auftrag))
        if self.path in ("/admin/dienst/firewall", "/admin/dienst/firewall?neu=1"):
            if self.path.endswith("neu=1"):   # server.log fehlt, DNS-Muster ungueltig o. ae.: Status trotzdem
                versuchen(firewall.absender_sammeln)
                versuchen(firewall.clients_suchen, 0)
            try:   # z. B. FW_DEFAULT_RULES fehlt oder ist ungueltig: Grund an die Seite statt abgebrochener Verbindung
                antwort = 200, firewall.status()
            except Exception as e:
                antwort = 500, {"fehler": "Firewall: %s" % e}
            return self.senden(*antwort)
        self.senden(404, {"fehler": "unbekannt"})

    def do_POST(self):
        grenze = 65536 if self.path == "/admin/dienst/firewall" else 4096
        try:
            a = json.loads(self.rfile.read(max(0, min(int(self.headers.get("Content-Length") or 0), grenze))))   # negativ hiesse: bis EOF lesen
            if self.path in ("/admin/dienst/freigeben", "/admin/dienst/anhaengen", "/admin/dienst/abhaengen"):
                platte = a["platte"]
            elif self.path == "/admin/dienst/einrichten":
                geraet, groesse, name = a["geraet"], a["groesse"], a["name"]
            elif self.path != "/admin/dienst/firewall":
                return self.senden(404, {"fehler": "unbekannt"})
        except (ValueError, KeyError, TypeError):
            return self.senden(400, {"fehler": "Anfrage unvollständig"})
        if self.path == "/admin/dienst/firewall":
            try:
                neu, fehler = firewall.speichern(a, wer=self.headers.get("X-Auth-User", ""), client=self.headers.get("X-Real-IP"))
                antwort = (400, {"fehler": " · ".join(fehler)}) if fehler else (200, firewall.status())
            except Exception as e:
                antwort = 500, {"fehler": "Firewall: %s" % e}
            return self.senden(*antwort)
        if self.path != "/admin/dienst/einrichten":
            return self.storage(self.path.rsplit("/", 1)[1], platte)
        if not GERAET.fullmatch(str(geraet)):
            return self.senden(400, {"fehler": "kein Plattengerät"})
        with sperre:
            if auftrag.get("laeuft"):
                return self.senden(409, {"fehler": "Es wird gerade schon eine Platte eingerichtet."})
            try:
                platten, naechste = kandidaten()
            except RuntimeError as e:   # pacs-storage.sh bricht ab (HALT): der Grund statt "nicht mehr als leer erkannt"
                return self.senden(409, {"fehler": str(e)})
            if (geraet, groesse) not in platten or name != naechste:
                return self.senden(409, {"fehler": "Die Platte ist nicht mehr genau so als leer erkannt. Bitte neu suchen."})
            auftrag.clear()
            auftrag.update(laeuft=True, wer=self.headers.get("X-Auth-User", ""), geraet=geraet, name=name, start=jetzt(),
                           ausgabe="")
            threading.Thread(target=einrichten, args=(geraet,), daemon=True).start()
        self.senden(202, dict(auftrag))

    def storage(self, modus, platte):   # modus: freigeben | anhaengen | abhaengen
        if not PLATTE.fullmatch(str(platte)):
            return self.senden(400, {"fehler": "keine PACS-Platte"})
        r = lauf(STORAGE + [modus, platte, "ja"], ZEIT)
        subprocess.run(DASHBOARD, timeout=ZEIT)
        if r.returncode == RC_NICHT_NEU_GELADEN:   # steht im LDAP, gilt im Archiv aber erst nach "Neu laden": nicht als "nichts getan" melden
            achtung = re.search(r"ACHTUNG: (.*)", r.stdout)
            return self.senden(500, {"fehler": achtung.group(1) if achtung else "Das Archiv hat die Konfiguration nicht neu geladen, siehe Log von pacs-storage.sh"})
        if r.returncode:
            halt = re.search(r"HALT: (.*)", r.stdout)
            return self.senden(409, {"fehler": halt.group(1) if halt else "nicht ausgeführt, siehe Log von pacs-storage.sh"})
        self.senden(200, {"ok": True})

    def protokoll(self, q):
        quellen = [x for x in q.get("quelle", ["ereignisse,admin"])[0].split(",") if x in QUELLEN]
        try:
            heute = datetime.date.today()
            von = datetime.date.fromisoformat(q["von"][0]) if "von" in q else heute - datetime.timedelta(days=30)
            bis = datetime.date.fromisoformat(q["bis"][0]) if "bis" in q else heute
            letzte = max(0, min(int(q.get("letzte", ["0"])[0]), 1000))   # negativ hiesse in SQLite: alle
            ab, vor = time.mktime(von.timetuple()), time.mktime((bis + datetime.timedelta(days=1)).timetuple())   # bis=9999-12-31: OverflowError
        except (ValueError, OverflowError):
            return self.senden(400, {"fehler": "Datum JJJJ-MM-TT, letzte als Zahl"})
        if not quellen:
            return self.senden(400, {"fehler": "unbekannte Quelle"})
        wo = "quelle in (%s)" % ",".join("?" * len(quellen))
        try:
            with pacsdb.Db() as db:
                if letzte:
                    zeilen = db.abfrage("select zeile from (select zeile, zeit, id from protokoll where %s order by zeit desc, id desc "
                                        "limit ?) order by zeit, id" % wo, quellen + [letzte])
                else:
                    zeilen = db.abfrage("select zeile from protokoll where %s and zeit >= ? and zeit < ? order by zeit, id" % wo,
                                        quellen + [ab, vor])
        except (ValueError, RuntimeError, OSError) as e:   # Schluessel oder Datenbank unbrauchbar: Antwort statt abgebrochener Verbindung
            return self.senden(503, {"fehler": "Protokoll: %s" % e})
        b = "\n".join(z for (z,) in zeilen).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def handle_one_request(self):
        try:
            super().handle_one_request()
        except subprocess.TimeoutExpired as e:   # pacs-storage.sh oder dashboard-status.py haengt: Antwort statt abgebrochener Verbindung
            self.senden(504, {"fehler": "%s antwortet nicht (nach %d s abgebrochen), Zustand pruefen" % (os.path.basename(str(e.cmd[1])), e.timeout)})

    def log_message(self, *args):   # nginx protokolliert jede Anfrage mit Konto
        pass


class Dienst(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


def sockets_binden():
    """Beide Sockets anlegen und an PACS_SOCKET_UID uebergeben, bevor ein Thread startet (ein Fehler beendet dann nur
    den Hauptthread, auf Python 3.13 sonst mit "Fatal Python error" und Core-Dump). Ergebnis: (Protokoll-Socket, Dienst)."""
    s = None
    try:
        socket_frei(SOCK, socket.SOCK_STREAM, "PACS_SOCKET")   # erst beide pruefen (lebt ein Dienst, bricht der Start ab; liegengebliebene Dateien werden geraeumt), dann binden
        socket_frei(PROTOKOLL_SOCK, socket.SOCK_DGRAM, "PACS_LOG_SOCKET")
        s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 << 20)
        s.bind(PROTOKOLL_SOCK)
        socket_fuer_nginx(PROTOKOLL_SOCK)
        dienst = Dienst(SOCK, Anfrage)
        socket_fuer_nginx(SOCK)
    except PermissionError as e:
        if s:
            s.close()
        sys.exit("verwaltung-dienst.py: keine Berechtigung (%s: %s). Der Dienst muss als root laufen (pacs-verwaltung.service)."
                 % (e.strerror, e.filename or os.path.dirname(PROTOKOLL_SOCK)))
    except OSError as e:
        if s:
            s.close()
        sys.exit("verwaltung-dienst.py: Socket nicht anlegbar: %s" % e)
    return s, dienst


def main():
    # Die Sockets schuetzt nur die uid. Gehoert sie auf dem Host einem Konto, erreicht jeder Prozess dieses Kontos den Dienst.
    try:
        print("Achtung: PACS_SOCKET_UID %d ist auf dem Host das Konto %s. Jeder Prozess dieses Kontos kann das Protokoll lesen "
              "und die Firewall aendern. Ist das nicht nginx, siehe docs/install.de.md#helper-service."
              % (SOCKET_UID, pwd.getpwuid(SOCKET_UID).pw_name), file=sys.stderr, flush=True)
    except KeyError:
        pass
    empfangssocket, dienst = sockets_binden()
    try:   # Schluessel fehlt oder passt nicht: gleich melden, nicht erst bei der ersten Protokollzeile (Dienst laeuft trotzdem)
        with pacsdb.Db():
            pass
    except Exception as e:
        print("Achtung: Protokoll-Datenbank nicht nutzbar, die Zeilen von nginx werden zurueckgehalten und alle 10 s neu "
              "abgelegt: %s" % e, file=sys.stderr, flush=True)
    threading.Thread(target=empfangen, args=(empfangssocket,), daemon=True).start()
    threading.Thread(target=ablegen, daemon=True).start()
    threading.Thread(target=absender_takt, daemon=True).start()
    print("pacs-verwaltung bereit: %s (HTTP) und %s (Protokoll), Besitzer uid %d" % (SOCK, PROTOKOLL_SOCK, SOCKET_UID), flush=True)
    try:
        dienst.serve_forever()
    except KeyboardInterrupt:   # Threads laufen noch: normales Beenden loest auf Python 3.13 "Fatal Python error" aus
        for pfad in (SOCK, PROTOKOLL_SOCK):
            if os.path.lexists(pfad):
                os.unlink(pfad)
        os._exit(0)


if __name__ == "__main__":
    main()
