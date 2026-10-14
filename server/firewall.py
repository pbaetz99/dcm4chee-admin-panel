#!/usr/bin/env python3
# Firewall fuer die von Docker veroeffentlichten Ports, bearbeitbar in /admin/ (Reiter Firewall).
# iptables filter for the ports Docker publishes (chain PACS-SPERRE via DOCKER-USER), edited in the admin panel.
# Regeln in PACS_DIR/firewall.json, je Port eine Liste erlaubter Quellen (IPv4-Adresse oder Netz) und ein Modus:
#   gesperrt   nur die Liste kommt durch, alle anderen werden abgewiesen und protokolliert (Kernel-Log pacs-sperre)
#   probelauf  alle kommen durch, wer nicht auf der Liste steht, wird protokolliert (pacs-probe): wen traefe die Sperre?
#   offen      alle kommen durch
# Ports ohne Regel folgen dem Standard (offen, probelauf oder gesperrt = Default-Deny, Kernel-Log pacs-standard).
# Ohne firewall.json gilt FW_DEFAULT_RULES (JSON-Datei) oder der eingebaute Satz ohne erlaubte Quellen (Viewer offen,
# DICOM und HL7 Probelauf, REST, Verwaltung, Kibana, Portainer gesperrt).
# Dienstports (Host-Ports, je Liste der erste = Hauptport): FW_WEB_PORTS (443,80), FW_DICOM_PORTS (11112,2762),
# FW_HL7_PORTS (2575,12575).
# Geprueft werden nur neue Verbindungen: Pakete bestehender (auch der von arc selbst aufgebauten, z. B. C-MOVE an ein Geraet
# mit Port 11112) gehen vorher durch. Nur fuer Verkehr von aussen ueber die Schnittstelle ("schnittstelle" in
# firewall.json, sonst FW_INTERFACE, sonst die der Standardroute), nicht fuer den Host und die Docker-Netze. Nur IPv4:
# was Docker auch an [::] bindet, laeuft ueber docker-proxy an der Kette vorbei (veroeffentlicht meldet es als ipv6).
# Die Regeln stehen in der Kette PACS-SPERRE, die DOCKER-USER anspringt. iptables-restore ersetzt sie in einem Schritt,
# ohne Luecke. systemd pacs-firewall setzt sie nach jedem Start von Docker. Speichern sichert die vorige Fassung in
# firewall/, geht das Anwenden schief, gilt die vorige weiter.
# Dazu: wer spricht DICOM und HL7 mit dem PACS? Alle 5 Minuten aus dem server.log von arc (Dienst
# pacs-verwaltung ruft absender_sammeln), Ergebnis in firewall/absender.json. Und welche Client-PCs gibt es? Stuendlich
# per DNS ueber die Namensmuster in FW_CLIENT_NAMES (leer = keine Suche), Ergebnis in firewall/clients.json. Was erkannt,
# aber fuer seinen Port nicht erlaubt ist, zeigt /admin/ unter "Neu erkannt" (vorschlaege) zum Erlauben oder Ausblenden.
#   firewall.py start | stop | status | absender | nachholen | clients | test
import collections, contextlib, datetime, glob, gzip, io, ipaddress, itertools, json, os, re, shutil, socket, subprocess, sys, threading, time
from concurrent.futures import ThreadPoolExecutor, wait

D = os.environ.get("PACS_DIR") or "/opt/dcm4chee-arc"
KONFIG = os.path.join(D, "firewall.json")
ABLAGE = os.path.join(D, "firewall", "")
ABSENDER = ABLAGE + "absender.json"
CLIENTS = ABLAGE + "clients.json"
LOGS = os.path.join(os.environ.get("ARC_LOG_DIR") or "/var/local/dcm4chee-arc/wildfly/log/", "")
CLIENT_MUSTER = os.environ.get("FW_CLIENT_NAMES", "").strip()
STANDARD_DATEI = os.environ.get("FW_DEFAULT_RULES", "").strip()
KETTE = "PACS-SPERRE"


def portliste(name, vorgabe):
    """Host-Ports aus der Umgebung, durch Komma getrennt, der erste ist der Hauptport. Ungueltig: Vorgabe, mit Meldung."""
    try:
        p = tuple(dict.fromkeys(int(x) for x in re.split(r"[,\s]+", os.environ.get(name) or vorgabe) if x))
        if p and all(1 <= x <= 65535 for x in p):
            return p
    except ValueError:
        pass
    print("%s ignoriert, keine Liste von Ports: %s" % (name, os.environ.get(name)), file=sys.stderr)
    return tuple(int(x) for x in vorgabe.split(","))


def dienstports():
    """[WEB, DICOM, HL7] aus der Umgebung. Teilen sich zwei Listen einen Port, gelten fuer alle drei die Vorgaben."""
    vorgabe = (("FW_WEB_PORTS", "443,80"), ("FW_DICOM_PORTS", "11112,2762"), ("FW_HL7_PORTS", "2575,12575"))
    p = [portliste(n, v) for n, v in vorgabe]
    if len(set(sum(p, ()))) < len(sum(p, ())):
        print("FW_WEB_PORTS, FW_DICOM_PORTS und FW_HL7_PORTS ignoriert, ein Port steht in mehreren: %s" % p, file=sys.stderr)
        p = [tuple(int(x) for x in v.split(",")) for _, v in vorgabe]
    return p


# Viewer (erster = https, fuer die Pruefung gegen Aussperren), DICOM und HL7 (erster = ohne TLS, fuer Vorschlaege)
WEB, DICOM, HL7 = dienstports()
PORTNAMEN = {8080: "dcm4chee REST (http)", 8443: "dcm4chee REST (https)", 9990: "WildFly-Verwaltung",
             9993: "WildFly-Verwaltung (https)", 8843: "Keycloak", 5601: "Kibana", 8000: "Portainer (Edge)", 9443: "Portainer"}
for _liste, _namen in ((WEB, ("Viewer und Verwaltung", "Viewer und Verwaltung (http)")), (DICOM, ("DICOM", "DICOM-TLS")),
                       (HL7, ("HL7", "HL7-TLS"))):
    PORTNAMEN.update({p: _namen[min(i, 1)] for i, p in enumerate(_liste)})
try:   # FW_PORT_NAMES: {"104": "DICOM (alt)", ...} ueber die eingebauten Namen
    PORTNAMEN.update({int(p): str(n)[:60] for p, n in json.loads(os.environ.get("FW_PORT_NAMES") or "{}").items()})
except (ValueError, AttributeError) as e:
    print("FW_PORT_NAMES ignoriert, kein JSON-Objekt Port -> Name: %s" % e, file=sys.stderr)
# Dienste, deren Sperre den Betrieb trifft: Rueckfrage in /admin/, abgewiesene Versuche kommen unter "Neu erkannt"
KRITISCH = {p: PORTNAMEN[p] for p in WEB + (DICOM[0], HL7[0])}
MODI = ("offen", "probelauf", "gesperrt")
WIRKT = ("aktiv", "schnittstelle", "standard", "regeln")   # was iptables betrifft
# eingebauter Regelsatz; die Dienstports gehen vor, falls einer auf einer der gesperrten Nummern liegt
STANDARD = dict.fromkeys((8080, 8443, 9990, 9993, 5601, 8000, 9443), "gesperrt")
STANDARD.update(dict.fromkeys(WEB, "offen"))
STANDARD.update({DICOM[0]: "probelauf", HL7[0]: "probelauf"})
sperre = threading.Lock()


# Hinweis fuer Programme, die auf dem Host fehlen koennen (Debian-Pakete)
HINWEIS = {"iptables": "apt install iptables", "iptables-restore": "apt install iptables", "ip": "apt install iproute2",
           "docker": "Docker installieren, z. B. apt install docker.io", "journalctl": "apt install systemd"}


LAUF_ZEIT = 120   # Sekunden; ein haengendes iptables oder docker haelt sonst den Dienst und die Sperre fuer immer fest


def lauf(args, **kw):
    """subprocess.run mit Text-Ausgabe und Zeitgrenze. Fehlt das Programm oder antwortet es nicht, kommt eine
    verstaendliche Zeile (RuntimeError) statt eines Tracebacks oder eines haengenden Dienstes."""
    kw.setdefault("timeout", LAUF_ZEIT)
    try:
        return subprocess.run(args, capture_output=True, encoding="utf-8", errors="replace", **kw)
    except FileNotFoundError:
        raise RuntimeError("%s nicht gefunden: %s (docs/modules.de.md#firewall)" % (args[0], HINWEIS.get(args[0], "installieren")))
    except subprocess.TimeoutExpired:
        raise RuntimeError("%s antwortet nicht (nach %d s abgebrochen)" % (args[0], kw["timeout"]))
    except OSError as e:
        raise RuntimeError("%s nicht ausfuehrbar: %s" % (args[0], e))


def iptables(*args, eingabe=None):
    r = lauf(["iptables-restore", "--noflush"] if eingabe is not None else ["iptables"] + list(args), input=eingabe)
    if r.returncode:
        raise RuntimeError((r.stderr or r.stdout).strip().splitlines()[-1] if (r.stderr or r.stdout).strip() else "iptables fehlgeschlagen")
    return r.stdout


# ---------------------------------------------------------------- Schnittstelle
def standardroute(text):
    """Schnittstelle aus "ip route show default", z. B. "default via 192.0.2.1 dev ens192 proto static" -> ens192."""
    m = re.search(r"^default\b.*?\sdev (\S+)", text, re.M)
    return m.group(1) if m else ""


def schnittstelle_standard():
    """FW_INTERFACE (leer gilt als nicht gesetzt), sonst die Schnittstelle der Standardroute, sonst leer (dann meldet
    pruefen/anwenden den Fehler). Fehlt das Programm ip, kommt eine Zeile mit dem Hinweis."""
    if os.environ.get("FW_INTERFACE", "").strip():
        return os.environ["FW_INTERFACE"].strip()
    try:
        return standardroute(lauf(["ip", "route", "show", "default"]).stdout)
    except RuntimeError as e:
        raise RuntimeError("%s. Oder FW_INTERFACE in /etc/default/pacs-admin setzen" % e)


def json_laden(pfad):
    """JSON-Datei lesen. Ist der Inhalt kein JSON, nennt der Fehler (ValueError) die Datei."""
    with open(pfad, encoding="utf-8") as f:
        try:
            return json.load(f)
        except ValueError as e:
            raise ValueError("%s: %s" % (pfad, e))


# ---------------------------------------------------------------- Regeln
def standard_regeln():
    """Regeln ohne firewall.json: FW_DEFAULT_RULES (gleiches Format wie firewall.json) oder der eingebaute Satz."""
    if STANDARD_DATEI:
        try:
            k, fehler = pruefen(json_laden(STANDARD_DATEI))
        except (OSError, ValueError) as e:   # Datei fehlt oder ist kein JSON
            raise ValueError("FW_DEFAULT_RULES: %s" % e)
        if fehler:
            raise ValueError("FW_DEFAULT_RULES %s: %s" % (STANDARD_DATEI, " · ".join(fehler)))
        return k
    return {"aktiv": True, "standard": "offen", "regeln": [
        {"port": p, "name": PORTNAMEN.get(p, ""), "modus": m, "protokollieren": False, "erlaubt": []}
        for p, m in sorted(STANDARD.items())]}


def laden():
    try:
        k = json_laden(KONFIG)
        regeln = k.get("regeln", []) if isinstance(k, dict) else None
        if not isinstance(regeln, list) or not all(isinstance(r, dict) for r in regeln):
            raise ValueError("%s: kein JSON-Objekt mit einer Liste regeln" % KONFIG)
        k = dict({"aktiv": True, "regeln": []}, **k)
    except FileNotFoundError:
        k = standard_regeln()
    if not k.get("schnittstelle"):
        k["schnittstelle"] = schnittstelle_standard()
    return k


def schreiben(k, pfad=KONFIG):
    tmp = pfad + ".neu"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o640)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        os.fchmod(fd, 0o640)   # vor dem ersten Byte: eine liegengebliebene .neu behaelt sonst ihren alten Modus
        json.dump(k, f, ensure_ascii=False, indent=1)
    os.replace(tmp, pfad)


def pruefen(k, client=None, innen=()):
    """Regeln aus der Seite pruefen und vereinheitlichen. Ergebnis (Regeln, Fehlerliste). innen: Netze aus intern()."""
    if not isinstance(k, dict) or not isinstance(k.get("regeln"), list):
        return None, ["Regeln fehlen"]
    fehler, regeln, ports = [], [], set()
    schnitt = str(k.get("schnittstelle") or schnittstelle_standard())
    if not re.fullmatch(r"[a-z][a-z0-9_.-]{1,14}", schnitt):
        fehler.append("Schnittstelle „%s“ ungültig (FW_INTERFACE setzen)" % schnitt)
    for r in k["regeln"]:
        try:
            port = int(r["port"])
        except (KeyError, TypeError, ValueError):
            fehler.append("Port fehlt oder ist keine Zahl")
            continue
        if not 1 <= port <= 65535 or port in ports:
            fehler.append("Port %s ungültig oder doppelt" % port)
            continue
        ports.add(port)
        if port == 22:
            fehler.append("Port 22 (SSH) ist kein Docker-Port und hier nicht einstellbar")
        modus = r.get("modus", "gesperrt")
        if modus not in MODI:
            fehler.append("Port %d: Modus „%s“ unbekannt" % (port, modus))
        erlaubt, gesehen = [], set()
        for e in r.get("erlaubt") or []:
            q = str(e.get("quelle", "") if isinstance(e, dict) else e).strip()
            try:
                netz = ipaddress.IPv4Network(q, strict=False)
            except ValueError:
                fehler.append("Port %d: „%s“ ist keine IPv4-Adresse und kein Netz" % (port, q))
                continue
            q = str(netz.network_address) if netz.prefixlen == 32 else str(netz)
            if q not in gesehen:
                gesehen.add(q)
                erlaubt.append({"quelle": q, "notiz": str(e.get("notiz", "") if isinstance(e, dict) else "")[:80]})
        regeln.append({"port": port, "name": str(r.get("name", ""))[:60], "modus": modus,
                       "protokollieren": bool(r.get("protokollieren")), "erlaubt": erlaubt})
    standard = k.get("standard", "offen")
    if standard not in MODI:
        fehler.append("Standard „%s“ unbekannt" % standard)
    aus = {str(x) for x in k.get("ausgeblendet") or [] if re.fullmatch(r"\d{1,5} \d{1,3}(\.\d{1,3}){3}(/\d{1,2})?", str(x))}
    neu = {"aktiv": bool(k.get("aktiv", True)), "schnittstelle": schnitt, "standard": standard,
           "regeln": sorted(regeln, key=lambda r: r["port"]), "ausgeblendet": sorted(aus)[:1000]}
    # nicht selbst aussperren: der eigene PC muss den https-Port (WEB[0]) weiter erreichen (Regel oder Standard).
    # Adressen aus innen nicht: ueber IPv6 sieht nginx das Docker-Gateway, diese Verbindung laeuft nicht durch die Kette
    try:
        ip = ipaddress.IPv4Address(client or "")
        if neu["aktiv"] and not any(ip in ipaddress.IPv4Network(n) for n in innen) and not zugelassen(neu, WEB[0], ip):
            fehler.append("Port %d: dein PC (%s) wäre danach selbst ausgesperrt. Erst ihn oder sein Netz eintragen." % (WEB[0], client))
    except ValueError:
        pass
    return neu, fehler


def zugelassen(k, port, ip):
    """Kommt eine neue Verbindung von ip auf port durch (gesperrt = nur Liste, sonst ja)?"""
    r = next((x for x in k["regeln"] if x["port"] == port), None)
    modus = r["modus"] if r else k.get("standard", "offen")
    return modus != "gesperrt" or bool(r and any(ip in ipaddress.IPv4Network(e["quelle"]) for e in r["erlaubt"]))


def regelsatz(k, ports=()):
    """Kette PACS-SPERRE fuer iptables-restore. Kommentare "pacs PORT ..." ordnen die Zaehler zu. ports: veroeffentlichte
    Ports ohne eigene Regel, die bekommen den Standard mit ihrem Port im Log."""
    z = ["*filter", ":%s - [0:0]" % KETTE,
         # bestehende Verbindungen (auch Antworten auf ausgehende von arc) nicht pruefen, nur neue
         "-A %s -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN" % KETTE]
    neu = "-m conntrack --ctstate NEW"
    grenze = "-m limit --limit 10/min"
    for r in k["regeln"]:
        p = r["port"]
        m = "-p tcp -m conntrack --ctorigdstport %d" % p
        if r["modus"] == "offen":
            z.append('-A %s %s %s -m comment --comment "pacs %d offen"' % (KETTE, m, neu, p))
            z.append("-A %s %s -j RETURN" % (KETTE, m))
            continue
        for e in r["erlaubt"]:
            z.append('-A %s -s %s %s %s -m comment --comment "pacs %d verb %s"' % (KETTE, e["quelle"], m, neu, p, e["quelle"]))
            if r["protokollieren"]:
                z.append('-A %s -s %s %s %s %s -j LOG --log-prefix "pacs-erlaubt %d: "' % (KETTE, e["quelle"], m, neu, grenze, p))
            z.append("-A %s -s %s %s -j RETURN" % (KETTE, e["quelle"], m))
        z.append('-A %s %s %s -m comment --comment "pacs %d fremd"' % (KETTE, m, neu, p))
        if r["modus"] == "gesperrt":
            z.append('-A %s %s %s %s -j LOG --log-prefix "pacs-sperre %d: "' % (KETTE, m, neu, grenze, p))
            z.append("-A %s %s -j REJECT --reject-with tcp-reset" % (KETTE, m))
        else:
            z.append('-A %s %s %s %s -j LOG --log-prefix "pacs-probe %d: "' % (KETTE, m, neu, grenze, p))
    # Ports ohne Regel: Standard. Bekannte mit ihrem Port, danach alle anderen (auch kuenftig veroeffentlichte, bis zum
    # naechsten Anwenden, im Log steht dann der Port im Container als DPT=)
    if k.get("standard", "offen") != "offen":
        eigene = {r["port"] for r in k["regeln"]}
        for p in sorted(set(ports) - eigene):
            m = "-p tcp -m conntrack --ctorigdstport %d" % p
            z.append('-A %s %s %s -m comment --comment "pacs %d std"' % (KETTE, m, neu, p))
            z.append('-A %s %s %s %s -j LOG --log-prefix "pacs-standard %d: "' % (KETTE, m, neu, grenze, p))
            if k["standard"] == "gesperrt":
                z.append("-A %s %s -j REJECT --reject-with tcp-reset" % (KETTE, m))
        for proto, ab in (("tcp", "--reject-with tcp-reset"), ("udp", "--reject-with icmp-port-unreachable")):
            z.append('-A %s -p %s %s -m comment --comment "pacs standard %s"' % (KETTE, proto, neu, proto))
            z.append('-A %s -p %s %s %s -j LOG --log-prefix "pacs-standard 0: "' % (KETTE, proto, neu, grenze))
            if k["standard"] == "gesperrt":
                z.append("-A %s -p %s %s -j REJECT %s" % (KETTE, proto, neu, ab))
    return "\n".join(z + ["COMMIT", ""])


def spruenge():
    return [z for z in iptables("-S", "DOCKER-USER").splitlines() if z.endswith("-j " + KETTE)]


def anwenden(k):
    if k["aktiv"] and not k.get("schnittstelle"):
        raise RuntimeError("Schnittstelle unbekannt: FW_INTERFACE in /etc/default/pacs-admin setzen")
    ports = [v["port"] for v in veroeffentlicht()]
    iptables(eingabe=regelsatz(k, ports))
    soll = "-A DOCKER-USER -i %s -j %s" % (k["schnittstelle"], KETTE) if k["aktiv"] else None
    da = spruenge()
    if soll and soll not in da:
        iptables("-I", "DOCKER-USER", "-i", k["schnittstelle"], "-j", KETTE)
    for z in da:
        if z != soll:
            iptables(*(["-D"] + z.split()[1:]))
    os.makedirs(ABLAGE, exist_ok=True)
    schreiben({"zeit": time.strftime("%Y-%m-%dT%H:%M:%S"), "ports": ports}, ABLAGE + "angewendet.json")


def angewendet():
    """Was beim letzten Anwenden galt ({"zeit", "ports"}); leer, wenn unbekannt."""
    try:
        return json_laden(ABLAGE + "angewendet.json")
    except (OSError, ValueError):
        return {}


def nachziehen():
    """Alle 5 Minuten (pacs-verwaltung): neue oder weggefallene Docker-Ports -> Regeln neu, damit der Standard
    auch fuer neue Ports mit ihrem Port im Log greift."""
    with sperre:
        a = angewendet()
        vorher = a.get("ports", []) if a else None
        k = laden()
        if k.get("standard", "offen") != "offen" and vorher != [v["port"] for v in veroeffentlicht()]:
            anwenden(k)
            return True
    return False


def speichern(k, wer="", client=None):
    neu, fehler = pruefen(k, client, intern() if client else ())
    if fehler:
        return None, fehler
    with sperre:
        try:
            alt = laden()
        except (OSError, ValueError):   # firewall.json oder FW_DEFAULT_RULES unlesbar: der neue Satz ersetzt sie
            alt = None
        neu["geaendert"] = {"wer": wer, "zeit": time.strftime("%Y-%m-%dT%H:%M:%S")}
        os.makedirs(ABLAGE, exist_ok=True)
        kopie = None
        if os.path.exists(KONFIG):
            kopie = ABLAGE + "firewall-%s.json" % time.strftime("%Y%m%d-%H%M%S")
            shutil.copy2(KONFIG, kopie)
        schreiben(neu)
        if alt and [neu.get(x) for x in WIRKT] == [alt.get(x) for x in WIRKT]:
            return neu, []
        try:
            anwenden(neu)
        except Exception as e:
            if alt is None:   # keine lesbaren vorigen Regeln: nur die Datei zurueck
                if kopie:
                    shutil.copy2(kopie, KONFIG)
                else:
                    os.remove(KONFIG)
                return None, ["Nicht übernommen: %s" % e]
            schreiben(alt)
            anwenden(alt)
            return None, ["Nicht übernommen, die vorigen Regeln gelten weiter: %s" % e]
    return neu, []


# ---------------------------------------------------------------- Anzeige
def zaehler():
    """Neue Verbindungen: {port: {"verb": {quelle: n}, "fremd": n, "offen": n}, "standard": {"tcp": n, "udp": n}}"""
    z = {"standard": {}}
    try:
        text = iptables("-L", KETTE, "-nvx")
    except RuntimeError:
        return z
    for zeile in text.splitlines():
        m = re.match(r"\s*(\d+)\s+\d+\s.*/\* pacs (\S+) (\S+) ?(\S*) \*/", zeile)
        if not m:
            continue
        n, wo, was, quelle = int(m.group(1)), m.group(2), m.group(3), m.group(4)
        if wo == "standard":
            z["standard"][was] = n
            continue
        e = z.setdefault(wo, {"verb": {}, "fremd": 0, "offen": 0})
        if was == "verb":
            e["verb"][quelle] = n
        elif was in ("fremd", "offen", "std"):
            e[was] = n
    return z


def ports_lesen(text):
    """Ausgabe von docker ps (Name TAB Ports) -> [{port, ziel, container, ipv6}]. port = Host-Port (darauf pruefen die
    Regeln), ziel = Port im Container, ipv6 = auch an eine IPv6-Adresse gebunden: diese Verbindungen nimmt docker-proxy
    an, sie laufen an der IPv4-Kette vorbei. Bereiche (2575-2576->2575-2576) einzeln. An loopback (127.0.0.1, [::1])
    gebundene Ports sind von aussen nicht erreichbar und fehlen."""
    ports = {}
    for zeile in text.splitlines():
        name, _, liste = zeile.partition("\t")
        for eintrag in liste.split(", "):
            m = re.fullmatch(r"(\[[0-9a-fA-F:.]*\]|[0-9.]+|::):(\d+)(?:-(\d+))?->(\d+)(?:-(\d+))?/tcp", eintrag.strip())
            try:
                if not m or ipaddress.ip_address(m.group(1).strip("[]")).is_loopback:
                    continue
            except ValueError:
                continue
            von, bis, ziel = int(m.group(2)), int(m.group(3) or m.group(2)), int(m.group(4))
            for i in range(bis - von + 1):
                e = ports.setdefault(von + i, {"port": von + i, "ziel": ziel + i if m.group(5) else ziel, "container": set(), "ipv6": False})
                e["container"].add(name)
                e["ipv6"] = e["ipv6"] or ":" in m.group(1)
    return [dict(e, container=", ".join(sorted(e["container"]))) for _, e in sorted(ports.items())]


def veroeffentlicht():
    """Von aussen erreichbare Docker-Ports, siehe ports_lesen"""
    return ports_lesen(lauf(["docker", "ps", "--format", "{{.Names}}\t{{.Ports}}"]).stdout)


def versuche(tage=7, pub=(), text=None):
    """Kernel-Log: abgewiesen (sperre), Probelauf nicht auf der Liste (probe), erlaubt protokolliert (erlaubt), Standard.
    Die Sammelregel (pacs-standard 0) kennt nur den Port im Container (DPT=): port = der Host-Port, der als einziger
    dorthin fuehrt (pub: veroeffentlicht()), sonst 0 und ziel = Port im Container. text: Log statt journalctl (Test)."""
    if text is None:
        text = lauf(["journalctl", "-k", "--since", "%d days ago" % tage, "-o", "short-iso", "--no-pager"]).stdout
    v = {}
    for zeile in text.splitlines():
        m = re.match(r"(\S+) \S+ kernel: .*?pacs-(sperre|probe|erlaubt|standard) (\d+): .*?SRC=([0-9.]+)", zeile)
        if m:
            port, ziel = int(m.group(3)), 0
            if m.group(2) == "standard" and port == 0:   # Sammelregel, siehe regelsatz
                d = re.search(r" DPT=(\d+)", zeile)
                ziel = int(d.group(1)) if d else 0
                host = [x["port"] for x in pub if x["ziel"] == ziel]
                port, ziel = (host[0], 0) if len(host) == 1 else (0, ziel)
            e = v.setdefault((m.group(2), port, ziel, m.group(4)), {"anzahl": 0, "zuletzt": ""})
            e["anzahl"] += 1
            e["zuletzt"] = max(e["zuletzt"], m.group(1)[:19])
    return [{"art": a, "port": p, "ziel": z, "quelle": q, **e}
            for (a, p, z, q), e in sorted(v.items(), key=lambda x: x[1]["zuletzt"], reverse=True)]


_dns = {}
def namen(ips):
    """Rechnernamen zu IPs, hoechstens 2 s insgesamt, gemerkt fuer eine Stunde."""
    jetzt = time.time()
    fehlt = [ip for ip in set(ips) if ip not in _dns or jetzt - _dns[ip][1] > 3600]
    if fehlt:
        def merken(ip, a):
            _dns[ip] = ("" if a.exception() else a.result()[0].split(".")[0], time.time())
        pool = ThreadPoolExecutor(8)
        auftraege = [pool.submit(socket.gethostbyaddr, ip) for ip in fehlt]
        for ip, a in zip(fehlt, auftraege):
            a.add_done_callback(lambda a, ip=ip: merken(ip, a))   # langsame Antworten gelten beim naechsten Mal
        wait(auftraege, timeout=2)
        pool.shutdown(wait=False)
    return {ip: _dns[ip][0] for ip in set(ips) if ip in _dns and _dns[ip][0]}


def wirkung(k, spruenge_liste):
    """Warum die Regeln nicht wirken (Text), sonst leer. spruenge_liste: Zeilen von spruenge()."""
    soll = "-A DOCKER-USER -i %s -j %s" % (k.get("schnittstelle"), KETTE)
    if soll in spruenge_liste:
        return ""
    if not k.get("aktiv", True):
        return "in /admin/ (Reiter Firewall) ausgeschaltet"
    if spruenge_liste:
        return "der Sprung nach %s gilt fuer eine andere Schnittstelle als %s (firewall.py start)" % (KETTE, k.get("schnittstelle"))
    return "kein Sprung von DOCKER-USER nach %s, die Regeln sind nicht angewendet (systemctl status pacs-firewall)" % KETTE


def status():
    k = laden()
    try:
        grund = wirkung(k, spruenge())
    except RuntimeError as e:   # iptables fehlt oder ist nicht erlaubt (z. B. nicht als root): der Grund steht im Ergebnis
        grund = str(e) + (" (die Kette DOCKER-USER legt Docker beim Start an: laeuft Docker?)"
                          if "No chain" in str(e) or "Operation not supported" in str(e) else "")
    seit = angewendet().get("zeit", "")
    a = absender_lesen()
    pub = veroeffentlicht()
    v = versuche(pub=pub)
    c = clients_lesen() if CLIENT_MUSTER else {"stand": "", "pcs": []}
    c["muster"] = CLIENT_MUSTER
    innen = intern()
    ips = [e["quelle"] for r in k.get("regeln", []) for e in r.get("erlaubt", []) if "/" not in e["quelle"]]
    ips += [x["quelle"] for x in v] + [x["ip"] for teil in ("dicom", "hl7", "ohne_ae") for x in a.get(teil, {}).values()]
    return {"konfig": k, "wirksam": not grund, "wirksam_grund": grund, "zaehler_seit": seit, "zaehler": zaehler(), "veroeffentlicht": pub,
            "versuche": v, "absender": {t: sorted(a.get(t, {}).values(), key=lambda x: x["zuletzt"], reverse=True)
                                        for t in ("dicom", "hl7", "ohne_ae")},
            "absender_stand": a.get("stand", ""), "clients": c, "intern": innen,
            "vorschlaege": vorschlaege(k, a, v, c["pcs"], innen), "namen": namen(ips), "kritisch": KRITISCH,
            "dienstports": {"web": list(WEB), "dicom": DICOM[0], "hl7": HL7[0]}}


def intern():
    """Netze, deren Verkehr die Firewall nie sieht: Docker, der Server selbst, loopback. Ohne Shell und mit Zeitgrenze (lauf);
    fehlt docker oder hostname, kommt die Zeile von lauf als RuntimeError."""
    ids = lauf(["docker", "network", "ls", "-q"]).stdout.split()
    text = lauf(["hostname", "-I"]).stdout
    if ids:
        text += " " + lauf(["docker", "network", "inspect", "-f", "{{range .IPAM.Config}}{{.Subnet}} {{end}}"] + ids).stdout
    netze = {"127.0.0.0/8"}
    for x in text.split():
        try:
            netze.add(str(ipaddress.IPv4Network(x, strict=False)))
        except ValueError:
            pass   # IPv6
    return sorted(netze)


def vorschlaege(k, a, v, pcs, innen=()):
    """Erkannt, aber fuer seinen Port nicht erlaubt und nicht ausgeblendet: Client-Netze (je /24 der Client-PCs, fuer DICOM),
    DICOM-Geraete und HL7-Absender aus dem Log von dcm4chee, im Probelauf nicht eingetragene Verbindungen, abgewiesene an
    DICOM, HL7 und Viewer. Abgewiesene an bewusst geschlossenen Ports (Kibana usw.) nicht, die stehen nur unter Verbindungen."""
    aus = set(k.get("ausgeblendet", []))
    innen = [ipaddress.IPv4Network(n) for n in innen]
    liste = {}

    def frei(port, quelle):
        r = next((x for x in k["regeln"] if x["port"] == port), None)
        n = ipaddress.IPv4Network(quelle)
        return (r["modus"] if r else k.get("standard", "offen")) == "offen" or any(n.subnet_of(i) for i in innen) or \
            bool(r and any(n.subnet_of(ipaddress.IPv4Network(e["quelle"])) for e in r["erlaubt"]))

    def dazu(port, quelle, art, notiz="", anzahl=0, zuletzt=""):
        if "%d %s" % (port, quelle) in aus or frei(port, quelle):
            return
        e = liste.setdefault((port, quelle), {"port": port, "quelle": quelle, "art": art, "notiz": "", "anzahl": 0, "zuletzt": ""})
        if notiz and notiz not in e["notiz"].split(", "):
            e["notiz"] = (e["notiz"] + ", " if e["notiz"] else "") + notiz
        e["anzahl"] += anzahl
        e["zuletzt"] = max(e["zuletzt"], zuletzt)

    netze = collections.defaultdict(list)
    for p in pcs:
        if not frei(DICOM[0], p["ip"]):
            netze[str(ipaddress.IPv4Network(p["ip"] + "/24", strict=False))].append(p["name"])
    for n, pc in sorted(netze.items()):
        dazu(DICOM[0], n, "clients", "%d Client-PC%s: %s" % (len(pc), "" if len(pc) == 1 else "s",
                                                             ", ".join(sorted(pc)[:4]) + (" …" if len(pc) > 4 else "")))
    for x in a.get("dicom", {}).values():
        dazu(DICOM[0], x["ip"], "dicom", x["ae"], x["anzahl"], x["zuletzt"])
    for x in a.get("hl7", {}).values():
        dazu(HL7[0], x["ip"], "hl7", "", x["anzahl"], x["zuletzt"])
    for x in v:
        if x["art"] == "probe" or (x["art"] in ("sperre", "standard") and x["port"] in KRITISCH):
            dazu(x["port"], x["quelle"], "versuch-" + x["art"], "", x["anzahl"], x["zuletzt"].replace("T", " "))
    # Client-Netze zuerst, sonst neueste zuerst
    return sorted(liste.values(), key=lambda e: (e["art"] == "clients", e["zuletzt"]), reverse=True)


# ---------------------------------------------------------------- Client-PCs per DNS
def client_namen(muster=None):
    """Namen aus FW_CLIENT_NAMES: Muster durch Komma getrennt, Bereiche wie in bash, z. B. pc{01..20},ws{001..040}.
    Hat eine Grenze eine fuehrende Null, wird auf die Breite der Grenzen aufgefuellt. Leer = keine Namen."""
    namen = []
    for m in (CLIENT_MUSTER if muster is None else muster).split(","):
        t = re.split(r"\{(\d+)\.\.(\d+)\}", m.strip())   # [text, von, bis, text, von, bis, text]
        if not m.strip():
            continue
        teile, anzahl = [[t[0]]], 1
        for i in range(1, len(t), 3):
            a, b = t[i], t[i + 1]
            breite = max(len(a), len(b)) if any(len(x) > 1 and x[0] == "0" for x in (a, b)) else 0
            schritt = 1 if int(b) >= int(a) else -1
            teile += [[str(n).zfill(breite) for n in range(int(a), int(b) + schritt, schritt)], [t[i + 2]]]
            anzahl *= abs(int(b) - int(a)) + 1
            if anzahl > 100000:
                raise ValueError("FW_CLIENT_NAMES: „%s“ ergibt mehr als 100000 Namen" % m.strip())
        namen += ["".join(x) for x in itertools.product(*teile)]
    return list(dict.fromkeys(namen))


def clients_lesen():
    try:
        with open(CLIENTS, encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, ValueError):
        return {"stand": "", "pcs": []}


def clients_suchen(alter=3600):
    """Alle Namen aus FW_CLIENT_NAMES im DNS nachschlagen (8 gleichzeitig, einige tausend Namen in wenigen Sekunden).
    pacs-verwaltung ruft alle 5 Minuten, gesucht wird nur, wenn der letzte Stand aelter als alter Sekunden ist. Findet der
    DNS gar nichts (Ausfall), bleibt der alte Stand. FW_CLIENT_NAMES leer: keine Suche, Ergebnis None."""
    if not CLIENT_MUSTER:
        return None
    try:
        if time.time() - os.path.getmtime(CLIENTS) < alter:
            return None
    except OSError:
        pass

    def suchen(n):
        try:
            return {"name": n, "ip": socket.gethostbyname(n)}
        except OSError:
            return None
    with ThreadPoolExecutor(8) as pool:
        pcs = [p for p in pool.map(suchen, client_namen()) if p]
    if pcs or not os.path.exists(CLIENTS):
        os.makedirs(ABLAGE, exist_ok=True)
        schreiben({"stand": time.strftime("%Y-%m-%dT%H:%M:%S"), "pcs": pcs}, CLIENTS)
    else:
        os.utime(CLIENTS)
    return len(pcs)


# ---------------------------------------------------------------- Absender aus dem server.log
ANNAHME = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d,\d{3}) .*Accept connection Socket\[addr=/([0-9.]+),port=\d+,localport=(\d+)\]")
VERBINDUNG = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d,\d{3}) \S+\s+\[[^\]]*\] \([^)]*\) "
                        r"(?:([^<>()/]{1,16})<-([^<>()]{1,16})|/[0-9.]+:\d+<-/([0-9.]+):\d+)\((\d+)\)")
START = re.compile(r"WFLYSRV0025")   # arc neu gestartet: Verbindungsnummern beginnen wieder bei 1


def zeitpunkt(t):
    return datetime.datetime.strptime(t, "%Y-%m-%d %H:%M:%S,%f")


def absender_lesen():
    try:
        with open(ABSENDER, encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, ValueError):
        return {"dicom": {}, "hl7": {}, "ohne_ae": {}, "wartend": [], "gesehen": {}}


def zaehlen(tabelle, schluessel, t, **felder):
    e = tabelle.setdefault(schluessel, dict(felder, anzahl=0, erst=t))
    e["anzahl"] += 1
    e["zuletzt"] = t


def lauschports(ziel=None):
    """Ports im Container von arc (localport im server.log) fuer DICOM und HL7: die Ports aus FW_DICOM_PORTS und
    FW_HL7_PORTS und, wo Docker einen davon auf eine andere Nummer im Container legt (z. B. 104:11112), diese Nummer.
    ziel: {Host-Port: Port im Container}, ohne Angabe aus docker ps."""
    if ziel is None:
        try:
            ziel = {v["port"]: v["ziel"] for v in veroeffentlicht()}
        except (OSError, RuntimeError):   # ohne docker: gleiche Nummern
            ziel = {}
    return [set(p) | {ziel[x] for x in p if x in ziel} for p in (DICOM, HL7)]


def auswerten(a, zeilen, ports=None):
    """Neue Logzeilen einrechnen. Die IP steht nur in der Annahme-Zeile, AE-Titel und laufende Nummer in den Zeilen
    der Verbindung. Nummern vergibt dcm4che in Annahme-Reihenfolge: die erste Zeile einer neuen Nummer gehoert zur
    fruehesten noch offenen Annahme davor (hoechstens 10 s). Annahmen ohne Verbindung (Portpruefungen) -> ohne_ae.
    ports: (DICOM, HL7) als Ports im Container (lauschports), Standard FW_DICOM_PORTS und FW_HL7_PORTS."""
    dicom, hl7 = ports or (DICOM, HL7)
    wartend = [(zeitpunkt(t), ip) for t, ip in a.get("wartend", [])]
    gesehen = a.get("gesehen", {})
    zuletzt = ""   # Zeitstempel der letzten Zeile ueberhaupt: so weit ist das Log gelesen
    for z in zeilen:
        if z[:2] == "20" and z[4:5] == "-":
            zuletzt = z[:23]
        if START.search(z):
            gesehen = {}
        m = ANNAHME.match(z)
        if m:
            t, ip, port = m.group(1), m.group(2), int(m.group(3))
            if port in hl7:
                zaehlen(a["hl7"], ip, t[:19], ip=ip)
            elif port in dicom:
                wartend.append((zeitpunkt(t), ip))
            continue
        m = VERBINDUNG.match(z)
        if not m or m.group(5) in gesehen:
            continue
        t, gerufen, rufer, ip_fehler, nr = m.groups()
        gesehen[nr] = t
        tz = zeitpunkt(t)
        treffer = next((i for i, (ta, _) in enumerate(wartend) if tz - datetime.timedelta(seconds=10) <= ta <= tz), None)
        if treffer is None:
            continue
        ip = wartend.pop(treffer)[1]
        if rufer:
            zaehlen(a["dicom"], rufer.strip() + "|" + ip, t[:19], ae=rufer.strip(), an=gerufen.strip(), ip=ip)
        else:
            zaehlen(a["ohne_ae"], ip, t[:19], ip=ip)
    try:
        letzte = zeitpunkt(zuletzt)
    except ValueError:
        letzte = datetime.datetime.now()
    grenze = letzte - datetime.timedelta(seconds=10)
    for ta, ip in [w for w in wartend if w[0] < grenze]:
        zaehlen(a["ohne_ae"], ip, ta.strftime("%Y-%m-%d %H:%M:%S"), ip=ip)
    a["wartend"] = [(ta.strftime("%Y-%m-%d %H:%M:%S,%f")[:23], ip) for ta, ip in wartend if ta >= grenze]
    alt = letzte - datetime.timedelta(minutes=30)
    a["gesehen"] = {n: t for n, t in gesehen.items() if zeitpunkt(t) >= alt}


def zeilen_aus(pfad, ab=0):
    with (gzip.open(pfad, "rb") if pfad.endswith(".gz") else open(pfad, "rb")) as f:
        f.seek(ab)
        daten = f.read()
    ende = daten.rfind(b"\n") + 1
    return daten[:ende].decode("utf-8", "replace").splitlines(), ab + ende


def absender_sammeln():
    """Neue Zeilen seit dem letzten Lauf. Nach dem naechtlichen Wechsel erst den Rest der alten Datei (gepackt)."""
    ports = lauschports()
    with sperre:
        a = absender_lesen()
        pfad = LOGS + "server.log"
        try:
            st = os.stat(pfad)
        except OSError as e:
            raise RuntimeError("%s: %s. ARC_LOG_DIR in /etc/default/pacs-admin auf das Log-Verzeichnis von wildfly setzen "
                               "(docker inspect arc: der Mount von /opt/wildfly/standalone, darin log/)" % (pfad, e.strerror))
        datei = a.get("datei", {})
        if datei and datei.get("inode") != st.st_ino:
            alt = glob.glob(LOGS + "server.log." + datei.get("datum", "") + "*")
            if alt:
                zeilen, _ = zeilen_aus(sorted(alt)[0], datei.get("offset", 0))
                auswerten(a, zeilen, ports)
            datei = {}
        ab = datei.get("offset", 0) if datei.get("offset", 0) <= st.st_size else 0
        zeilen, ende = zeilen_aus(pfad, ab)
        auswerten(a, zeilen, ports)
        datum = next((z[:10] for z in reversed(zeilen) if re.match(r"\d{4}-\d\d-\d\d ", z)), datei.get("datum", time.strftime("%Y-%m-%d")))
        a["datei"] = {"inode": st.st_ino, "offset": ende, "datum": datum}
        a["stand"] = time.strftime("%Y-%m-%dT%H:%M:%S")
        os.makedirs(ABLAGE, exist_ok=True)
        schreiben(a, ABSENDER)
        return len(zeilen)


def nachholen():
    """Einmalig: alle gepackten Logs, danach die laufende Datei von vorn."""
    ports = lauschports()
    with sperre:
        a = {"dicom": {}, "hl7": {}, "ohne_ae": {}, "wartend": [], "gesehen": {}}
        for f in sorted(glob.glob(LOGS + "server.log.*.gz")):
            zeilen, _ = zeilen_aus(f)
            auswerten(a, zeilen, ports)
            print(os.path.basename(f), len(zeilen), "Zeilen")
        os.makedirs(ABLAGE, exist_ok=True)
        schreiben(a, ABSENDER)
    print("laufende Datei:", absender_sammeln(), "Zeilen")


def selbsttest():
    if not os.environ.get("FW_INTERFACE", "").strip():   # auch leer gesetzt (FW_INTERFACE= in /etc/default/pacs-admin)
        os.environ["FW_INTERFACE"] = "eth0"   # Regeln ohne "schnittstelle", unabhaengig von der Route hier
    W, D, H = WEB[0], DICOM[0], HL7[0]   # Dienstports wie eingestellt (Vorgabe 443, 11112, 2575)
    X, Y, Z = [p for p in [8080, 5601] + list(range(65001, 65536)) if p not in WEB + DICOM + HL7][:3]   # sonstige Ports
    k, f = pruefen({"regeln": [{"port": 8080, "modus": "gesperrt", "erlaubt": [{"quelle": "10.1.2.3/24"}, {"quelle": "x"}]}]})
    assert f and k["regeln"][0]["erlaubt"] == [{"quelle": "10.1.2.0/24", "notiz": ""}], (k, f)
    k, f = pruefen({"regeln": [{"port": W, "modus": "gesperrt", "erlaubt": [{"quelle": "10.9.9.9"}]}]}, client="10.1.1.1")
    assert any("ausgesperrt" in x for x in f), f
    # ueber IPv6 kommt der eigene PC als Docker-Gateway an, an der Kette vorbei: kein Aussperren
    k, f = pruefen({"regeln": [{"port": W, "modus": "gesperrt", "erlaubt": [{"quelle": "10.9.9.9"}]}]}, client="172.18.0.1",
                   innen=["127.0.0.0/8", "172.18.0.0/16"])
    assert not f, f
    k, f = pruefen({"regeln": [{"port": 11112, "modus": "probelauf", "erlaubt": [{"quelle": "10.1.1.1"}]}]})
    assert not f and "REJECT" not in regelsatz(k) and "pacs-probe 11112" in regelsatz(k), f
    k["regeln"][0]["modus"] = "gesperrt"
    rs = regelsatz(k)
    assert rs.splitlines()[2].endswith("--ctstate RELATED,ESTABLISHED -j RETURN") and "REJECT" in rs, rs   # Antworten zuerst
    assert ":PACS-SPERRE - [0:0]" in rs and '"pacs 11112 verb 10.1.1.1"' in rs and "pacs-sperre 11112" in rs, rs
    # Default-Deny: https-Port offen, Rest gesperrt; eigener PC muss den https-Port behalten
    k, f = pruefen({"standard": "gesperrt", "regeln": [{"port": W, "modus": "offen"}]}, client="10.1.1.1")
    assert not f and zugelassen(k, W, ipaddress.IPv4Address("10.9.9.9")) and not zugelassen(k, X, ipaddress.IPv4Address("10.9.9.9")), f
    rs = regelsatz(k, [W, X, Y])
    assert "pacs %d offen" % W in rs and "pacs-standard %d:" % X in rs and "pacs-standard %d:" % Y in rs and "pacs-standard %d:" % W not in rs, rs
    assert rs.count("REJECT") == 4, rs   # X, Y, Sammelregel tcp und udp
    k, f = pruefen({"standard": "gesperrt", "regeln": []}, client="10.1.1.1")
    assert any("ausgesperrt" in x for x in f), f
    k, f = pruefen({"standard": "probelauf", "regeln": []}, client="10.1.1.1")
    assert not f and "REJECT" not in regelsatz(k, [443]) and "pacs-standard 443" in regelsatz(k, [443]), f
    # Schnittstelle: aus der Standardroute, ungueltige abgewiesen
    assert standardroute("default via 192.0.2.1 dev ens192 proto static metric 100\n") == "ens192"
    assert standardroute("192.0.2.0/24 dev eth1 proto kernel scope link\ndefault dev wg0 scope link\n") == "wg0"
    assert standardroute("192.0.2.0/24 dev eth1 proto kernel scope link\n") == ""
    assert pruefen({"regeln": []})[0]["schnittstelle"] == os.environ["FW_INTERFACE"]
    assert any("Schnittstelle" in x for x in pruefen({"schnittstelle": "eth0; reboot", "regeln": []})[1])
    # eingebauter Standard: keine erlaubten Quellen, DICOM/HL7 nur Probelauf, eigener PC behaelt den https-Port
    k, f = pruefen(standard_regeln(), client="192.0.2.10") if not STANDARD_DATEI else (None, [])
    assert not f and (k is None or all(not r["erlaubt"] for r in k["regeln"])), f
    # Dienstports aus der Umgebung (z. B. DICOM auf 104), Umsetzung Host-Port -> Port im Container, IPv6 aus docker ps
    alt = {n: os.environ.get(n) for n in ("FW_WEB_PORTS", "FW_DICOM_PORTS", "FW_HL7_PORTS")}
    os.environ.update(FW_WEB_PORTS="8443", FW_DICOM_PORTS="104, 11113,104", FW_HL7_PORTS="2576")
    assert dienstports() == [(8443,), (104, 11113), (2576,)], dienstports()
    os.environ["FW_HL7_PORTS"] = "11113"   # Port in zwei Listen: alle drei Vorgaben
    with contextlib.redirect_stderr(io.StringIO()) as meldung:
        assert dienstports() == [(443, 80), (11112, 2762), (2575, 12575)]
    assert "mehreren" in meldung.getvalue(), meldung.getvalue()
    for n, w in alt.items():
        if w is None:
            del os.environ[n]
        else:
            os.environ[n] = w
    assert lauschports({D: Z, X: X}) == [set(DICOM) | {Z}, set(HL7)]
    v = ports_lesen("arc\t0.0.0.0:104->11112/tcp, [::]:104->11112/tcp, 127.0.0.1:8080->8080/tcp, 2575/tcp\n"
                    "ohif\t0.0.0.0:443->8443/tcp, 0.0.0.0:80->8080/tcp\nweb\t:::8081->80/tcp, [::1]:8082->80/tcp\n")
    assert v == [{"port": 80, "ziel": 8080, "container": "ohif", "ipv6": False},
                 {"port": 104, "ziel": 11112, "container": "arc", "ipv6": True},
                 {"port": 443, "ziel": 8443, "container": "ohif", "ipv6": False},
                 {"port": 8081, "ziel": 80, "container": "web", "ipv6": True}], v
    # an eine bestimmte Adresse gebunden, Bereiche; 10.0.0.0 ist nicht 0.0.0.0, ungueltige Adresse faellt weg
    v = ports_lesen("arc\t192.0.2.10:104->11112/tcp, 0.0.0.0:2575-2576->2575-2576/tcp, [2001:db8::1]:443->8443/tcp\n"
                    "x\t10.0.0.0:8081->80/tcp, [fe80::]:8082->80/tcp, 999.1.1.1:8083->80/tcp, 127.0.0.1:8084-8085->80-81/tcp\n")
    assert [(x["port"], x["ziel"], x["ipv6"]) for x in v] == [(104, 11112, False), (443, 8443, True), (2575, 2575, False),
                                                           (2576, 2576, False), (8081, 80, False), (8082, 80, True)], v
    # Sammelregel: Port im Container zurueck auf den Host-Port, nur wenn genau einer dorthin fuehrt
    pub = ports_lesen("ohif\t0.0.0.0:443->8443/tcp\narc\t0.0.0.0:8443->8443/tcp, 0.0.0.0:2575->2575/tcp\n")
    L = "2025-01-15T12:00:00+0100 pacs kernel: pacs-%s: IN=eth0 OUT=br-1 SRC=10.4.4.4 DST=172.18.0.5 PROTO=TCP SPT=5000 DPT=%d\n"
    v = versuche(pub=pub, text=L % ("standard 0", 8443) + L % ("standard 0", 2575) + L % ("standard 8443", 8443) + L % ("sperre 443", 8443))
    assert sorted((x["art"], x["port"], x["ziel"]) for x in v) == [
        ("sperre", 443, 0), ("standard", 0, 8443), ("standard", 2575, 0), ("standard", 8443, 0)], v
    # Namensmuster der Client-PCs
    assert client_namen("R{1..2}-{001..002}, WS{0009..0010},pc7") == \
        ["R1-001", "R1-002", "R2-001", "R2-002", "WS0009", "WS0010", "pc7"], client_namen("R{1..2}-{001..002}, WS{0009..0010},pc7")
    assert client_namen("PC{1..3}") == ["PC1", "PC2", "PC3"] and client_namen("{01..100}")[:2] == ["001", "002"]
    assert client_namen("R{3..1}") == ["R3", "R2", "R1"] and client_namen("") == [] and client_namen(" , ") == []
    n = client_namen("PC{0001..5000},WS{01..20}")
    assert len(n) == 5020 and n[0] == "PC0001" and n[4999] == "PC5000" and n[-1] == "WS20", n[:3]
    assert client_namen("A{1..2},A{2..3}") == ["A1", "A2", "A3"]
    try:
        client_namen("{1..1000}{1..1000}")
        raise AssertionError("zu viele Namen angenommen")
    except ValueError:
        pass
    a = {"dicom": {}, "hl7": {}, "ohne_ae": {}, "wartend": [], "gesehen": {}}
    L = "2025-01-15 12:00:%s INFO  [org.dcm4che3.net.%s] (EE-Thread-%d) %s"
    auswerten(a, [L % ("00,100", "Connection", 2, "Accept connection Socket[addr=/10.1.1.1,port=5000,localport=11112]"),
                  L % ("00,101", "Connection", 1, "Accept connection Socket[addr=/10.2.2.2,port=5001,localport=2575]"),
                  L % ("00,120", "Association", 9, "DCM4CHEE<-MOD 1(5) >> A-ASSOCIATE-RQ"),
                  L % ("00,130", "Association", 9, "DCM4CHEE<-MOD 1(5) << A-ASSOCIATE-AC"),
                  L % ("01,000", "Connection", 2, "Accept connection Socket[addr=/10.3.3.3,port=5002,localport=11112]"),
                  L % ("30,000", "Association", 8, "DCM4CHEE->STORESCP(6) << A-ASSOCIATE-RQ")], ({11112}, {2575}))
    assert a["dicom"]["MOD 1|10.1.1.1"]["anzahl"] == 1 and a["hl7"]["10.2.2.2"]["anzahl"] == 1, a
    assert "10.3.3.3" in a["ohne_ae"] and not a["wartend"], a   # Portpruefung ohne Verbindung
    # Vorschlaege: Client-Netz nur, wenn ein PC nicht erlaubt ist; intern, ausgeblendet und erlaubt fallen weg
    k, f = pruefen({"standard": "gesperrt", "ausgeblendet": ["%d 10.9.9.9" % H, "x"], "regeln": [
        {"port": D, "modus": "probelauf", "erlaubt": [{"quelle": "10.1.1.0/24"}]}, {"port": W, "modus": "offen"},
        {"port": H, "modus": "gesperrt", "erlaubt": []}]})
    assert not f and k["ausgeblendet"] == ["%d 10.9.9.9" % H], (k, f)
    pcs = [{"name": "WS0041", "ip": "10.1.1.5"}, {"name": "WS0101", "ip": "10.2.2.7"}, {"name": "WS0102", "ip": "10.2.2.8"},
           {"name": "WS0007", "ip": "172.18.0.23"}]
    a = {"dicom": {"CT|10.3.3.3": {"ae": "CT", "ip": "10.3.3.3", "anzahl": 4, "zuletzt": "2025-01-15 12:00:00"},
                   "STORESCP|172.18.0.12": {"ae": "STORESCP", "ip": "172.18.0.12", "anzahl": 9, "zuletzt": "2025-01-15 12:00:00"}},
         "hl7": {"10.9.9.9": {"ip": "10.9.9.9", "anzahl": 1, "zuletzt": "2025-01-15 11:00:00"}}}
    v = [{"art": "sperre", "port": Y, "quelle": "10.4.4.4", "anzahl": 1, "zuletzt": "2025-01-15T12:00:00"},
         {"art": "sperre", "port": H, "quelle": "10.5.5.5", "anzahl": 2, "zuletzt": "2025-01-15T12:30:00"},
         {"art": "probe", "port": D, "quelle": "10.2.2.7", "anzahl": 3, "zuletzt": "2025-01-15T12:40:00"}]
    vs = vorschlaege(k, a, v, pcs, ["172.18.0.0/16", "127.0.0.0/8"])
    assert [(x["port"], x["quelle"], x["art"]) for x in vs] == [(D, "10.2.2.0/24", "clients"), (D, "10.2.2.7", "versuch-probe"),
        (H, "10.5.5.5", "versuch-sperre"), (D, "10.3.3.3", "dicom")], vs
    assert vs[0]["notiz"] == "2 Client-PCs: WS0101, WS0102", vs
    next(r for r in k["regeln"] if r["port"] == D)["erlaubt"].append({"quelle": "10.2.2.0/24"})
    vs = vorschlaege(k, a, v, pcs, ["172.18.0.0/16"])
    assert [x["quelle"] for x in vs] == ["10.5.5.5", "10.3.3.3"], vs
    fehlertest()
    print("Selbsttest ok")


def fehlertest():
    """Fehlende Programme, leere Umgebungswerte, kaputtes JSON: eine verstaendliche Meldung, kein Traceback."""
    import tempfile
    # fehlendes Programm: Name und Hinweis; ohne ip und ohne FW_INTERFACE nennt die Meldung beides
    try:
        lauf(["pacs-gibt-es-nicht"])
        raise AssertionError("fehlendes Programm nicht gemeldet")
    except RuntimeError as e:
        assert "pacs-gibt-es-nicht nicht gefunden" in str(e), e
    # haengender Aufruf: nach der Zeitgrenze eine Zeile statt eines Dienstes, der fuer immer wartet
    try:
        lauf([sys.executable, "-c", "import time; time.sleep(30)"], timeout=1)
        raise AssertionError("haengender Aufruf nicht abgebrochen")
    except RuntimeError as e:
        assert "antwortet nicht (nach 1 s abgebrochen)" in str(e), e
    alt = {n: os.environ.get(n) for n in ("PATH", "FW_INTERFACE")}
    try:
        os.environ["PATH"] = os.path.join(tempfile.gettempdir(), "pacs-ohne-programme")
        os.environ["FW_INTERFACE"] = " eth7 "
        assert schnittstelle_standard() == "eth7"   # Leerzeichen weg, ip wird nicht gebraucht
        os.environ["FW_INTERFACE"] = " "
        try:
            schnittstelle_standard()
            raise AssertionError("fehlendes ip nicht gemeldet")
        except RuntimeError as e:
            assert "ip nicht gefunden: apt install iproute2" in str(e) and "FW_INTERFACE" in str(e), e
        try:
            iptables("-S")
            raise AssertionError("fehlendes iptables nicht gemeldet")
        except RuntimeError as e:
            assert "iptables nicht gefunden: apt install iptables" in str(e), e
    finally:
        for n, w in alt.items():
            if w is None:
                os.environ.pop(n, None)
            else:
                os.environ[n] = w
    # kaputtes JSON in firewall.json und in FW_DEFAULT_RULES: die Meldung nennt die Datei
    d = tempfile.mkdtemp()
    g = globals()
    alt = {n: g[n] for n in ("KONFIG", "STANDARD_DATEI")}
    try:
        g["KONFIG"], g["STANDARD_DATEI"] = d + "/firewall.json", d + "/standard.json"
        for inhalt in ("{kaputt", "[]", '{"regeln": 5}', '{"regeln": [1]}'):   # JSON kaputt, keine Liste, Regel ohne Objekt
            with open(g["KONFIG"], "w") as f:
                f.write(inhalt)
            try:
                laden()
                raise AssertionError("kaputte firewall.json angenommen: " + inhalt)
            except ValueError as e:
                assert g["KONFIG"] in str(e), e
        os.remove(g["KONFIG"])   # ohne firewall.json gilt FW_DEFAULT_RULES
        for inhalt in ("{kaputt", "{}", None):   # None: Datei fehlt
            if inhalt is None:
                os.remove(g["STANDARD_DATEI"])
            else:
                with open(g["STANDARD_DATEI"], "w") as f:
                    f.write(inhalt)
            try:
                laden()
                raise AssertionError("kaputte FW_DEFAULT_RULES angenommen: %s" % inhalt)
            except ValueError as e:
                assert "FW_DEFAULT_RULES" in str(e) and g["STANDARD_DATEI"] in str(e), e
    finally:
        g.update(alt)
        for p in os.listdir(d):
            os.unlink(os.path.join(d, p))
        os.rmdir(d)
    # warum die Regeln nicht wirken
    k = {"aktiv": True, "schnittstelle": "eth0"}
    assert wirkung(k, ["-A DOCKER-USER -i eth0 -j " + KETTE]) == ""
    assert "andere Schnittstelle" in wirkung(k, ["-A DOCKER-USER -i eth1 -j " + KETTE])
    assert "kein Sprung" in wirkung(k, []) and "ausgeschaltet" in wirkung(dict(k, aktiv=False), [])


def befehl(was):
    if was == "start":
        # beim Booten kommt die Standardroute evtl. erst nach Docker: bis 60 s auf die Schnittstelle warten
        for _ in range(30):
            try:
                k = laden()
                if k.get("schnittstelle") or not k.get("aktiv", True):
                    break
            except ValueError as e:   # FW_DEFAULT_RULES ohne "schnittstelle" meldet die fehlende Route als Fehler: warten
                if "Schnittstelle" not in str(e):
                    raise   # sonst ist die Datei kaputt, Warten hilft nicht
            time.sleep(2)
        anwenden(laden())
        print("Firewall %s, %d Regeln" % ("wirksam" if laden()["aktiv"] else "aus (Regeln geladen)", len(laden()["regeln"])))
    elif was == "stop":
        for z in spruenge():
            iptables(*(["-D"] + z.split()[1:]))
        print("Sprung nach %s entfernt, alle Ports offen" % KETTE)
    elif was == "absender":
        print(absender_sammeln(), "neue Zeilen")
    elif was == "nachholen":
        nachholen()
    elif was == "clients":
        n = clients_suchen(0)
        print("Client-Suche aus (FW_CLIENT_NAMES leer)" if n is None else "%d Client-PCs" % n)
    elif was == "status":
        s = status()
        for r in s["konfig"]["regeln"]:
            zl = s["zaehler"].get(str(r["port"]), {})
            print("%5d %-10s %-28s erlaubt: %s  fremd: %s" % (r["port"], r["modus"], r["name"][:28],
                  ", ".join("%s (%d)" % (e["quelle"], zl.get("verb", {}).get(e["quelle"], 0)) for e in r["erlaubt"]) or "-", zl.get("fremd", 0)))
        print("Schnittstelle:", s["konfig"]["schnittstelle"] or "-", " wirksam:", s["wirksam"], " Zähler seit:", s["zaehler_seit"])
        if s["wirksam_grund"]:
            print("Nicht wirksam, weil:", s["wirksam_grund"])


if __name__ == "__main__":
    was = sys.argv[1] if len(sys.argv) > 1 else "status"
    if was == "test":
        selbsttest()
    elif was in ("start", "stop", "status", "absender", "nachholen", "clients"):
        try:
            befehl(was)
        except (RuntimeError, ValueError, OSError) as e:   # Programm fehlt, JSON kaputt, Datei fehlt: eine Zeile statt Traceback
            sys.exit("firewall.py %s: %s" % (was, e))
    else:
        print("firewall.py start | stop | status | absender | nachholen | clients | test")
        sys.exit(1)
