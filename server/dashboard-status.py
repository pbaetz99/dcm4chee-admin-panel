#!/usr/bin/env python3
# Zahlen fuer die Uebersicht in /admin/: Platten des Archivs (dazu neue, leere Platten: pacs-storage.sh kandidaten) und
# laufende Container. Keine Patientendaten. Aufruf als root, Cron alle 5 Min (/etc/cron.d/pacs-dashboard), ausserdem
# "Jetzt suchen" in /admin/ (verwaltung-dienst.py).
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
import datetime, glob, json, os, re, shutil, subprocess

VAR = os.environ.get("PACS_ADMIN_VAR") or "/var/lib/pacs-admin"
ZIEL = os.path.join(VAR, "status", "status.json")
BIN = os.path.dirname(os.path.abspath(__file__))
BASE = os.environ.get("STORAGE_BASE") or "/mnt/fs"
PREFIX = os.environ.get("STORAGE_PREFIX") or "PACS-Data"
PACS_DIR = (os.environ.get("PACS_DIR") or "/opt/dcm4chee-arc").rstrip("/")
FREI_GB = int(os.environ.get("STORAGE_FREE_GB") or os.environ.get("FREI_GB") or 50)   # FREI_GB: alter Name wie in pacs-storage.sh
WARN_GB = int(os.environ.get("STORAGE_WARN_GB") or 300)
CONTAINER = [c for c in re.split(r"[,\s]+", os.environ.get("DASHBOARD_CONTAINERS", "")) if c]

# Platten: Schreibliste der AE (Reihenfolge = Reihenfolge des Beschreibens), als voll gekennzeichnete,
# leere neue Platten. Neue Bilder gehen auf die erste nicht volle Platte der Schreibliste.
# Zeilen koennen leer sein (keine Schreibliste, keine Vorlage): dann gelten die Vorgaben hier. Fehlt die Zeile
# schreibliste (LDAP nicht lesbar, Skript abgebrochen oder haengt), ist "schreibliste_bekannt" false: die Seite meldet
# das, statt "keine Platte nimmt neue Bilder an".
k = {"kandidat": [], "naechste": [""], "vorlage": ["", ""], "schreibliste": [], "voll": []}
try:
    aus = subprocess.run(["/bin/bash", os.path.join(BIN, "pacs-storage.sh"), "kandidaten"], capture_output=True,
                         encoding="utf-8", timeout=300).stdout
except subprocess.TimeoutExpired:
    aus = ""
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
NAME = re.compile(re.escape(PREFIX) + r"\d+")   # wie verwaltung-dienst.py und pacs-storage.sh: nur Praefix plus Ziffern
for p in sorted(n for n in (os.path.basename(d) for d in glob.glob(os.path.join(BASE, glob.escape(PREFIX) + "[0-9]*")))
                if NAME.fullmatch(n)):
    mp = os.path.join(BASE, p)
    if not os.path.ismount(mp):
        platten.append({"name": p, "fehlt": True})   # Platte nicht eingehaengt (NO_MOUNT schuetzt davor, darunter zu schreiben)
        continue
    u = shutil.disk_usage(mp)
    platten.append({"name": p, "groesse": u.total, "frei": u.free, "voll": p in k["voll"], "in_liste": p in k["schreibliste"],
                    "neue_bilder": "jetzt" if schreibt[:1] == [p] else "danach" if p in schreibt else "",
                    "reihe": schreibt.index(p) + 1 if p in schreibt else 0})   # 1 = bekommt jetzt die neuen Bilder

# Dienste: laufen die Container? Ohne DASHBOARD_CONTAINERS alle des Compose-Projekts (auch gestoppte, die dann rot)
dienste = {}
if CONTAINER:
    for d in CONTAINER:
        r = subprocess.run(["docker", "inspect", "-f", "{{.State.Running}}", d], capture_output=True, encoding="utf-8")
        dienste[d] = r.stdout.strip() == "true"
else:
    r = subprocess.run(["docker", "ps", "-a", "--filter", "label=com.docker.compose.project.working_dir=" + PACS_DIR,
                        "--format", "{{.Names}}\t{{.Status}}"], capture_output=True, encoding="utf-8")
    for z in sorted(r.stdout.splitlines()):
        name, _, st = z.partition("\t")
        dienste[name] = st.startswith("Up") and "(Paused)" not in st

status = {
    "stand": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    "prefix": PREFIX,
    "frei_gb": FREI_GB,
    "warn_gb": WARN_GB,
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
