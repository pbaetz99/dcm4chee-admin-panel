#!/usr/bin/env python3
# Zahlen fuer die Uebersicht in /admin/: Platten des Archivs (dazu neue, leere Platten: pacs-storage.sh kandidaten) und
# laufende Container. Keine Patientendaten. Aufruf als root, Cron alle 5 Min (/etc/cron.d/pacs-dashboard), ausserdem
# "Jetzt suchen" in /admin/ (verwaltung-dienst.py). Scheitert pacs-storage.sh kandidaten (HALT, Zeitgrenze), wird der Stand
# trotzdem geschrieben (Platten und Dienste frisch, Schreibliste unbekannt) und das Skript endet danach mit Exit 1 und dem
# Grund auf stderr (Cron-Log, Antwort auf "Jetzt suchen").
# Writes PACS_ADMIN_VAR/status/status.json for the overview tab (disks, new disks, containers).
#   PACS_ADMIN_VAR        Standard /var/lib/pacs-admin, Ausgabe in status/status.json (nginx: /admin/daten/status.json)
#   STORAGE_BASE, STORAGE_PREFIX   Mountpunkte der Platten, Standard /mnt/fs/PACS-DataNN; "prefix" im JSON, damit
#                         die Seite die Namen kuerzen kann. pacs-storage.sh liegt im selben Verzeichnis wie dieses Skript.
#   STORAGE_FREE_GB       Standard 50: "frei_gb" im JSON, ab so viel freiem Platz bietet die Seite "Markierung entfernen"
#                         und "In Schreibliste aufnehmen" an (pacs-storage.sh prueft mit demselben Wert)
#   STORAGE_WARN_GB       Standard 300: "warn_gb" im JSON, darunter (Platz bis zur Schwelle auf der Schreibliste)
#                         mahnt die Uebersicht eine neue Platte an
#   DASHBOARD_CONTAINERS  Container fuer die Kachel Dienste (Komma oder Leerzeichen), leer = alle des Compose-Projekts
#                         in PACS_DIR (Standard /opt/dcm4chee-arc)
import datetime, glob, json, os, re, shutil, signal, subprocess, sys


def umgebung_int(name, vorgabe):
    wert = os.environ.get(name) or str(vorgabe)
    if not re.fullmatch(r"0|[1-9][0-9]{0,5}", wert):   # wie pacs-storage.sh: kein Minus, keine Leerzeichen, keine fuehrende Null, hoechstens 6 Stellen
        sys.exit("dashboard-status.py: %s=%s ist keine ganze Zahl ohne fuehrende Null mit hoechstens 6 Stellen (/etc/default/pacs-admin)" % (name, wert))
    return int(wert)


VAR = os.environ.get("PACS_ADMIN_VAR") or "/var/lib/pacs-admin"
ZIEL = os.path.join(VAR, "status", "status.json")
BIN = os.path.dirname(os.path.abspath(__file__))
STORAGE_BASE = os.environ.get("STORAGE_BASE") or "/mnt/fs"
STORAGE_PREFIX = os.environ.get("STORAGE_PREFIX") or "PACS-Data"
PACS_DIR = (os.environ.get("PACS_DIR") or "/opt/dcm4chee-arc").rstrip("/")
STORAGE_FREE_GB = umgebung_int("STORAGE_FREE_GB", 50)
STORAGE_WARN_GB = umgebung_int("STORAGE_WARN_GB", 300)
CONTAINER = [c for c in re.split(r"[,\s]+", os.environ.get("DASHBOARD_CONTAINERS", "")) if c]
KANDIDATEN_ZEIT = 200   # Sekunden fuer pacs-storage.sh kandidaten (wartet bis 120 s auf die Sperre); mit DOCKER_ZEIT unten bleibt der Lauf unter den 300 s, die verwaltung-dienst.py ihm gibt


def lauf(argv, zeit):
    """Wie subprocess.run(argv, capture_output=True, encoding="utf-8", timeout=zeit), nur ohne den Haenger von Python 3.7
    (Debian 10, bpo-37424): run() wartet nach dem Abbruch, bis auch ein Enkelprozess (docker exec, tee) die Pipes schliesst.
    Darum eigene Sitzung und SIGKILL an die ganze Gruppe. Dieselbe Funktion steht in verwaltung-dienst.py."""
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


# Platten: Schreibliste der AE (Reihenfolge = Reihenfolge des Beschreibens), als voll gekennzeichnete,
# leere neue Platten. Neue Bilder gehen auf die erste nicht volle Platte der Schreibliste.
# Zeilen koennen leer sein (keine Schreibliste, keine Vorlage): dann gelten die Vorgaben hier. Fehlt die Zeile
# schreibliste (LDAP nicht lesbar, Skript abgebrochen oder haengt), ist "schreibliste_bekannt" false: die Seite meldet
# das, statt "keine Platte nimmt neue Bilder an".
k = {"kandidat": [], "naechste": [""], "vorlage": ["", ""], "schreibliste": [], "voll": []}
FEHLER = []   # Grund, wenn pacs-storage.sh kandidaten scheitert: der Rest des Standes wird trotzdem geschrieben, danach endet das Skript mit Fehler
try:
    r = lauf(["/bin/bash", os.path.join(BIN, "pacs-storage.sh"), "kandidaten"], KANDIDATEN_ZEIT)
    aus = r.stdout
    if r.returncode:   # HALT (z. B. Fehler in /etc/default/pacs-admin) oder Absturz: dann fehlen alle Zeilen unten
        halt = re.search(r"HALT: (.*)", aus)
        FEHLER.append(halt.group(1) if halt else "Exit-Code %d: %s" % (r.returncode, (r.stderr.strip().splitlines() or ["ohne Meldung"])[-1]))
except subprocess.TimeoutExpired:
    aus = ""
    FEHLER.append("antwortet nicht (nach %d s abgebrochen)" % KANDIDATEN_ZEIT)
bekannt = False
for z in aus.splitlines():
    f = z.split()
    if f and f[0] == "kandidat" and len(f) >= 3 and f[2].isdigit():
        k["kandidat"].append({"geraet": f[1], "groesse": int(f[2]), "modell": " ".join(f[3:]).replace("_", " ")})
    elif f and f[0] in k and f[0] != "kandidat":
        k[f[0]] = f[1:]
        bekannt = bekannt or f[0] == "schreibliste"
schreibt = [p for p in k["schreibliste"] if p not in k["voll"]]
platten = []
NAME = re.compile(re.escape(STORAGE_PREFIX) + r"[0-9]+")   # wie verwaltung-dienst.py und pacs-storage.sh: nur Praefix plus Ziffern 0-9
for p in sorted(n for n in (os.path.basename(d) for d in glob.glob(os.path.join(STORAGE_BASE, glob.escape(STORAGE_PREFIX) + "[0-9]*")))
                if NAME.fullmatch(n)):
    mp = os.path.join(STORAGE_BASE, p)
    if not os.path.ismount(mp):
        platten.append({"name": p, "fehlt": True})   # Platte nicht eingehaengt (NO_MOUNT schuetzt davor, darunter zu schreiben)
        continue
    u = shutil.disk_usage(mp)
    platten.append({"name": p, "groesse": u.total, "frei": u.free, "voll": p in k["voll"], "in_liste": p in k["schreibliste"],
                    "neue_bilder": "jetzt" if schreibt[:1] == [p] else "danach" if p in schreibt else "",
                    "reihe": schreibt.index(p) + 1 if p in schreibt else 0})   # 1 = bekommt jetzt die neuen Bilder

# Dienste: laufen die Container? Ohne DASHBOARD_CONTAINERS alle des Compose-Projekts (auch gestoppte, die dann rot)
DOCKER_ZEIT = 60   # Sekunden je docker-Aufruf; haengt docker, soll nicht auch der Cron-Lauf (alle 5 Minuten) haengen
dienste = {}
try:
    if CONTAINER:
        for d in CONTAINER:
            r = subprocess.run(["docker", "inspect", "-f", "{{.State.Running}}", d], capture_output=True, encoding="utf-8",
                               timeout=DOCKER_ZEIT)
            dienste[d] = r.stdout.strip() == "true"
    else:
        r = subprocess.run(["docker", "ps", "-a", "--filter", "label=com.docker.compose.project.working_dir=" + PACS_DIR,
                            "--format", "{{.Names}}\t{{.Status}}"], capture_output=True, encoding="utf-8", timeout=DOCKER_ZEIT)
        for z in sorted(r.stdout.splitlines()):
            name, _, st = z.partition("\t")
            dienste[name] = st.startswith("Up") and "(Paused)" not in st
except FileNotFoundError:   # ohne docker bleibt die Kachel Dienste leer (die Seite blendet sie dann aus)
    dienste = {}
    print("dashboard-status.py: docker nicht gefunden, die Kachel Dienste bleibt leer (Docker installieren)", file=sys.stderr)
except subprocess.TimeoutExpired:
    dienste = {}
    print("dashboard-status.py: docker antwortet nicht (nach %d s abgebrochen), die Kachel Dienste bleibt leer" % DOCKER_ZEIT, file=sys.stderr)

status = {
    "stand": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    "prefix": STORAGE_PREFIX,
    "frei_gb": STORAGE_FREE_GB,
    "warn_gb": STORAGE_WARN_GB,
    "platten": platten,
    "schreibliste_bekannt": bekannt,
    "neue_platten": {"kandidaten": k["kandidat"], "name": (k["naechste"] + [""])[0], "vorlage": (k["vorlage"] + [""])[0],
                     "schwelle": (k["vorlage"] + ["", ""])[1]},
    "dienste": dienste,
}
os.makedirs(os.path.dirname(ZIEL), mode=0o755, exist_ok=True)
neu = "%s.%d" % (ZIEL, os.getpid())   # Cron und "Jetzt suchen" koennen gleichzeitig laufen
with open(neu, "w", encoding="utf-8") as f:
    json.dump(status, f, ensure_ascii=False)
os.chmod(neu, 0o644)   # keine Patientendaten; nginx im Container liest die Datei ueber den Bind-Mount
os.replace(neu, ZIEL)
if FEHLER:   # erst nach dem Schreiben: die Seite zeigt den Stand mit "Schreibliste nicht lesbar", Cron-Log und "Jetzt suchen" nennen den Grund
    sys.exit("dashboard-status.py: pacs-storage.sh kandidaten: " + FEHLER[0])
