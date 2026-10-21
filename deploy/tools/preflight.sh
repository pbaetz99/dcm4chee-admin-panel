#!/usr/bin/env bash
# preflight.sh: read-only check of a Debian host before installing the dcm4chee admin panel; changes nothing.
# Deutsch: docs/install.de.md. Ausgabe deutsch bei LANG=de*, sonst englisch (--lang de|en erzwingt die Sprache).
#
#   bash preflight.sh [--host pacs.example.org] [--cert FILE --key FILE] [--dir /opt/ohif] [--lang de|en]
#
#   --host NAME       also check that the DNS name resolves to an address of this host
#   --cert/--key      also check a TLS certificate and its private key (match, expiry, chain order, key permissions)
#   --dir DIR         also check the compose directory of the install (layout /opt/ohif): CHANGE-ME and <placeholders> left
#                     in its compose, nginx, env and js files (5 levels deep), the nginx tree, the bind mounts and env_file of the
#                     compose file (do they exist, can the nginx user, uid 101, read them; the key in tls/ as with --key)
#
# Prints one line per check: [ OK ], [WARN] or [FAIL], for WARN/FAIL one sentence what it means and the fix command.
# Exit code: 0 = all ok, 1 = warnings only, 2 = at least one failure (or wrong usage).
# Never writes, installs or restarts anything, and never prints a line of a configuration file (they hold secrets).
# Needs bash 3.2+; a missing tool becomes a WARN or FAIL line. One self-contained file on purpose (longer than the usual
# 800 lines): the reader runs a single script, there is nothing to source.
[ -n "${BASH_VERSION:-}" ] || { echo "preflight.sh: please run this script with bash:  bash $0" >&2; exit 2; }
set -u
PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"

# ---- language, options -------------------------------------------------------------------------------------------
LANGSEL=en
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in de*) LANGSEL=de ;; esac
T() { if [ "$LANGSEL" = de ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
# DOC PAGE [ANCHOR]: a page of the guide in the language of the output: docs/modules.md#firewall or docs/modules.de.md#firewall
DOC() { if [ "$LANGSEL" = de ]; then printf 'docs/%s.de.md%s' "$1" "${2:+#$2}"; else printf 'docs/%s.md%s' "$1" "${2:+#$2}"; fi; }
# q VALUE: VALUE as one shell word (quoted only when it holds anything unusual)
q() { case $1 in ''|*[!A-Za-z0-9_./:@%+=,-]*) printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")" ;; *) printf '%s' "$1" ;; esac; }
# the basic tools every check below relies on; without them (an empty PATH) one line says so instead of a page of errors
NOBASIC=""
for t in awk sed grep tr cut sort head tail wc id dirname; do command -v "$t" >/dev/null 2>&1 || NOBASIC="$NOBASIC $t"; done
if [ -n "$NOBASIC" ]; then
  printf 'preflight.sh: %s%s (PATH=%s)\n' "$(T 'basic tools not found:' 'Grundwerkzeuge nicht gefunden:')" "$NOBASIC" "$PATH" >&2; exit 2
fi

usage() {
  T 'Usage: bash preflight.sh [--host NAME] [--cert FILE --key FILE] [--dir DIR] [--lang de|en]
  --host NAME     also check that the DNS name resolves to an address of this host
  --cert, --key   also check a TLS certificate and its private key (match, expiry, chain order, key permissions)
  --dir DIR       also check the compose directory of the install (layout /opt/ohif): CHANGE-ME and <placeholders> left in
                  its files, the nginx tree, the bind mounts and env_file of the compose file (do they exist, can nginx read them)
  --lang de|en    language of the output (default: from the LANG setting)
  Read-only check of this host before installing the admin panel; it changes nothing.
  Exit code: 0 = all ok, 1 = warnings only, 2 = at least one failure.
' 'Aufruf: bash preflight.sh [--host NAME] [--cert DATEI --key DATEI] [--dir VERZEICHNIS] [--lang de|en]
  --host NAME     prueft zusaetzlich, ob der DNS-Name auf eine Adresse dieses Rechners zeigt
  --cert, --key   prueft zusaetzlich Zertifikat und privaten Schluessel (Paar, Ablauf, Kette, Rechte des Schluessels)
  --dir VERZEICHNIS  prueft zusaetzlich das Compose-Verzeichnis der Installation (Aufbau /opt/ohif): CHANGE-ME und
                  <Platzhalter> in den Dateien, den nginx-Ordner, die Einhaenge-Pfade und env_file der Compose-Datei (gibt es
                  sie, kann nginx sie lesen)
  --lang de|en    Sprache der Ausgabe (Vorgabe: aus der LANG-Einstellung)
  Prueft diesen Rechner vor der Installation, ohne etwas zu aendern.
  Exit-Code: 0 = alles in Ordnung, 1 = nur Warnungen, 2 = mindestens ein Fehler.
'
}
usage_error() { printf 'preflight.sh: %s\n' "$1" >&2; usage >&2; exit 2; }

HOST=""; CERT=""; KEY=""; DIR=""; ORIG=""
for a in "$@"; do ORIG="$ORIG $(q "$a")"; done   # the options as typed, for the "run it again as root" hints
while [ $# -gt 0 ]; do
  case $1 in
    -h|--help) usage; exit 0 ;;
    --host|--cert|--key|--dir|--lang) [ $# -ge 2 ] || usage_error "$1 needs a value"; k=$1; v=$2; shift 2 ;;
    --host=*|--cert=*|--key=*|--dir=*|--lang=*) k=${1%%=*}; v=${1#*=}; shift ;;
    *) usage_error "unknown option: $1" ;;
  esac
  case $k in
    --host) HOST=$v ;; --cert) CERT=$v ;; --key) KEY=$v ;; --dir) DIR=$v ;;
    --lang) case $v in de|en) LANGSEL=$v ;; *) usage_error "--lang: de or en" ;; esac ;;
  esac
done
while case $DIR in ?*/) true ;; *) false ;; esac; do DIR=${DIR%/}; done   # --dir /opt/ohif/ is --dir /opt/ohif
export LC_ALL=C   # tools below are parsed in English; our own messages follow LANGSEL
SUDO_CMD="sudo bash $(q "$0")$ORIG"

# ---- output ------------------------------------------------------------------------------------------------------
N_OK=0; N_WARN=0; N_FAIL=0; SEC=0; PKGS=""
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_FAIL=$'\033[31m'; C_B=$'\033[1m'; C_0=$'\033[0m'
else
  C_OK=""; C_WARN=""; C_FAIL=""; C_B=""; C_0=""
fi
# clean: drop control characters (ESC, BEL, CR ...) from text that came from docker or the file system, so that a hostile
# container label or file name cannot drive the terminal; tab and newline stay
clean() { tr -d '\000-\010\013-\037\177'; }
# nonul: drop NUL bytes from the output of a tool before a $( ) holds it (bash 4.4 and newer print a warning for each one)
nonul() { tr -d '\000'; }
oneline() { printf '%s' "$1" | clean | tr '\n\t' '  '; }
# emit TAG COLOR MESSAGE [MEANING [FIX]]
emit() {
  printf '%s%s%s %s\n' "$2" "$1" "$C_0" "$(oneline "$3")"
  [ -z "${4:-}" ] || printf '       %s\n' "$(oneline "$4")"
  [ -z "${5:-}" ] || printf '       %s %s\n' "$(T 'Fix:' 'Abhilfe:')" "$(oneline "$5")"
  return 0
}
ok()   { N_OK=$((N_OK + 1));     emit '[ OK ]' "$C_OK" "$@"; }
warn() { N_WARN=$((N_WARN + 1)); emit '[WARN]' "$C_WARN" "$@"; }
fail() { N_FAIL=$((N_FAIL + 1)); emit '[FAIL]' "$C_FAIL" "$@"; }
section() { SEC=$((SEC + 1)); printf '\n%s== %s. %s ==%s\n' "$C_B" "$SEC" "$1" "$C_0"; }
have() { command -v "$1" >/dev/null 2>&1; }
isnum() { case $1 in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
add_pkg() { case " $PKGS " in *" $1 "*) ;; *) PKGS="$PKGS $1" ;; esac; }
# need TOOL PACKAGE fail|warn "why": one line, registers the package when the tool is missing
need() {
  if have "$1"; then ok "$1: $(command -v "$1")"; return 0; fi
  add_pkg "$2"
  if [ "$3" = fail ]; then fail "$1 $(T 'not found' 'nicht gefunden')" "$4" "apt-get install -y $2"
  else warn "$1 $(T 'not found' 'nicht gefunden')" "$4" "apt-get install -y $2"; fi
  return 1
}
# dk ARGS: docker with a time limit, so that a stuck daemon (or an unreachable DOCKER_HOST) cannot hang this script.
# The exit status is the one of docker (124: the limit was hit); NUL bytes in its output are dropped.
DK_SECS=15
dk() {
  if have timeout; then timeout "$DK_SECS" docker "$@" </dev/null; else docker "$@" </dev/null; fi | nonul
  return "${PIPESTATUS[0]}"
}

# discovered values for the "my values" table at the end
V_DIR=""; V_FILES=""; V_NET=""; V_ARC=""; V_LDAP=""; V_DB=""; V_LOG=""; V_IFACE=""; V_UID=""; V_SQL=""; V_UIDNOTE=""
O_N=""; O_I=""   # the nginx container "ohif" of the compose examples (name and image), when it exists
DEF_DIR=/opt/dcm4chee-arc; DEF_LOG=/var/local/dcm4chee-arc/wildfly/log/

# what the panel will use: the environment, else the last uncommented NAME=value line of the env file, else the default.
# Re-running after a fix then compares with the fixed configuration, not with the built-in defaults.
ENVF=/etc/default/pacs-admin
cfg() {
  local v=""
  eval "v=\${$1:-}"
  if [ -z "$v" ] && [ -r "$ENVF" ]; then
    v=$(grep "^$1=" "$ENVF" | tail -n 1 | cut -d= -f2- | tr -d '\r' | sed "s/^'\\(.*\\)'\$/\\1/; s/^\"\\(.*\\)\"\$/\\1/")
  fi
  printf '%s' "${v:-$2}"
}
EFF_DIR=$(cfg PACS_DIR "$DEF_DIR"); EFF_LOG=$(cfg ARC_LOG_DIR "$DEF_LOG"); EFF_ARC=$(cfg ARC_CONTAINER arc)
EFF_LDAP=$(cfg LDAP_CONTAINER ldap); EFF_IFACE=$(cfg FW_INTERFACE ""); EFF_SB=$(cfg STORAGE_BASE /mnt/fs); EFF_SP=$(cfg STORAGE_PREFIX PACS-Data)

printf '%s\n' "$(T 'dcm4chee admin panel: preflight check. This script only reads, it changes nothing on this host.' \
  'dcm4chee-Admin-Panel: Vorabpruefung. Das Skript liest nur und aendert nichts an diesem Rechner.')"

# ======================================================================================================================
section "$(T 'System and packages' 'System und Pakete')"

if [ "$(id -u)" = 0 ]; then ok "$(T 'running as root' 'laeuft als root')"
else warn "$(T "not root (uid $(id -u))" "nicht root (uid $(id -u))")" \
  "$(T 'Installing needs root, and some checks below (docker, iptables, files of root) may be incomplete without it.' 'Die Installation braucht root, und einige Pruefungen unten (docker, iptables, Dateien von root) sind ohne root unvollstaendig.')" \
  "$SUDO_CMD"
fi

# where this repository lives: the units and the cron file start the programs from /opt/pacs-admin
SELF=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
case ${SELF:-} in
  */deploy/tools)
    REPO=${SELF%/deploy/tools}
    if [ "$REPO" = /opt/pacs-admin ]; then ok "$(T 'repository' 'Repository'): $REPO ($(T 'where the systemd units and the cron file expect it' 'dort erwarten es die systemd-Units und die Cron-Datei'))"
    else warn "$(T 'repository' 'Repository'): $REPO ($(T 'not /opt/pacs-admin' 'nicht /opt/pacs-admin'))" \
      "$(T 'The systemd units and the cron file start the programs from /opt/pacs-admin.' 'Die systemd-Units und die Cron-Datei starten die Programme aus /opt/pacs-admin.')" \
      "$(T 'clone the repository to /opt/pacs-admin, or run the sed command from the comment in pacs-verwaltung.service' 'das Repository nach /opt/pacs-admin klonen, oder den sed-Befehl aus dem Kommentar in pacs-verwaltung.service ausfuehren')"; fi ;;
esac

SYSTEMD=0
if [ -d /run/systemd/system ] && have systemctl; then
  SYSTEMD=1; ok "$(T 'systemd is running' 'systemd laeuft')"
elif have systemctl; then
  warn "$(T 'systemctl exists, but systemd is not running (container?)' 'systemctl ist da, aber systemd laeuft nicht (Container?)')" \
    "$(T 'The helper service and the firewall are systemd units; they cannot be started here.' 'Hilfsdienst und Firewall sind systemd-Units; sie lassen sich hier nicht starten.')" \
    "$(T 'run the installation on a normal Debian host or VM' 'Installation auf einem normalen Debian-Rechner oder einer VM ausfuehren')"
else
  warn "$(T 'systemctl not found' 'systemctl nicht gefunden')" \
    "$(T 'The helper service and the firewall are systemd units; without systemd you have to start them yourself.' 'Hilfsdienst und Firewall sind systemd-Units; ohne systemd muessen sie selbst gestartet werden.')" \
    "$(T 'use a Debian host with systemd' 'Debian-Rechner mit systemd verwenden')"
fi

# ---- operating system and SQLCipher package ----
OS_ID=""; OS_VER=""; OS_NAME=""
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  OS_INFO=$( . /etc/os-release 2>/dev/null; printf '%s|%s|%s' "${ID:-}" "${VERSION_ID:-}" "${PRETTY_NAME:-}" )
  OS_ID=${OS_INFO%%|*}; OS_REST=${OS_INFO#*|}; OS_VER=${OS_REST%%|*}; OS_NAME=${OS_REST#*|}
fi
if [ -z "$OS_ID" ]; then
  warn "$(T '/etc/os-release not readable: operating system unknown' '/etc/os-release nicht lesbar: Betriebssystem unbekannt')" \
    "$(T 'The guide is written for Debian 12 and 13.' 'Die Anleitung ist fuer Debian 12 und 13 geschrieben.')" "cat /etc/os-release"
elif [ "$OS_ID" = debian ] && { [ "$OS_VER" = 12 ] || [ "$OS_VER" = 13 ]; }; then
  ok "$(T 'operating system' 'Betriebssystem'): $OS_NAME ($(T 'tested' 'getestet'))"
elif [ "$OS_ID" = ubuntu ]; then
  warn "$(T 'operating system' 'Betriebssystem'): $OS_NAME ($(T 'not tested' 'nicht getestet'))" \
    "$(T 'The guide was tested on Debian 12 and 13; Ubuntu uses the same packages but nobody has verified it.' 'Die Anleitung wurde auf Debian 12 und 13 getestet; Ubuntu hat dieselben Pakete, ist aber nicht geprueft.')" ""
else
  warn "$(T 'operating system' 'Betriebssystem'): ${OS_NAME:-$OS_ID} ($(T 'not tested' 'nicht getestet'))" \
    "$(T 'The guide was tested on Debian 12 and 13 only.' 'Die Anleitung wurde nur auf Debian 12 und 13 getestet.')" ""
fi

# libsqlcipher1 (SQLCipher 4.x, Debian 13) or libsqlcipher0 (3.x, Debian 12 and older): take the installed one, else the one apt offers
if have apt-cache; then
  SQL_INST=""; SQL_CAND=""; SQL_INST_VER=""; SQL_CAND_VER=""
  for p in libsqlcipher1 libsqlcipher0; do
    pol=$(apt-cache -o Dir::Cache::pkgcache= -o Dir::Cache::srcpkgcache= policy "$p" 2>/dev/null | nonul)
    iv=$(printf '%s\n' "$pol" | awk '/^ *Installed:/ {print $2; exit}')
    cv=$(printf '%s\n' "$pol" | awk '/^ *Candidate:/ {print $2; exit}')
    if [ -n "$iv" ] && [ "$iv" != "(none)" ] && [ -z "$SQL_INST" ]; then SQL_INST=$p; SQL_INST_VER=$iv; fi
    if [ -n "$cv" ] && [ "$cv" != "(none)" ] && [ -z "$SQL_CAND" ]; then SQL_CAND=$p; SQL_CAND_VER=$cv; fi
  done
  if [ -n "$SQL_INST" ]; then
    V_SQL=$SQL_INST; ok "SQLCipher: $SQL_INST $SQL_INST_VER $(T 'is installed' 'ist installiert')"
  elif [ -n "$SQL_CAND" ]; then
    V_SQL=$SQL_CAND; add_pkg "$SQL_CAND"
    fail "SQLCipher: $(T "package $SQL_CAND ($SQL_CAND_VER) fits this system, not installed yet" "Paket $SQL_CAND ($SQL_CAND_VER) passt zu diesem System, noch nicht installiert")" \
      "$(T 'The encrypted audit log needs this library; the helper service does not start without it.' 'Das verschluesselte Protokoll braucht diese Bibliothek; ohne sie startet der Hilfsdienst nicht.') $(DOC install audit-key)" \
      "apt-get install -y $SQL_CAND"
  else
    fail "SQLCipher: $(T 'no libsqlcipher package found in apt' 'kein libsqlcipher-Paket in apt gefunden')" \
      "$(T 'Debian 13 has libsqlcipher1, Debian 12 and older have libsqlcipher0; the package lists may be empty or old.' 'Debian 13 hat libsqlcipher1, Debian 12 und aelter libsqlcipher0; die Paketlisten sind evtl. leer oder alt.') $(DOC install audit-key)" \
      "apt-get update; apt-cache search sqlcipher"
  fi
else
  case "$OS_ID:$OS_VER" in debian:13) V_SQL=libsqlcipher1 ;; debian:*|ubuntu:*) V_SQL=libsqlcipher0 ;; esac
  warn "SQLCipher: $(T 'apt-cache not found, package not checked' 'apt-cache nicht gefunden, Paket nicht geprueft')" \
    "$(T 'This is not a Debian-style system, or apt is missing. Install the SQLCipher shared library with your package manager.' 'Das ist kein Debian-artiges System oder apt fehlt. Die SQLCipher-Bibliothek mit dem Paketmanager des Systems installieren.') $(DOC install audit-key)" \
    "$(T 'search for "sqlcipher" in your package manager' 'im Paketmanager des Systems nach "sqlcipher" suchen')"
fi

# ---- python3: the units start /usr/bin/python3 ----
PY=/usr/bin/python3
if [ -x "$PY" ]; then
  PYV=$("$PY" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null)
  if "$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 7) else 1)' 2>/dev/null; then
    ok "python3: $PY $PYV $(T '(3.7 or newer needed)' '(ab 3.7 noetig)')"
  else
    add_pkg python3
    fail "python3: $PY ${PYV:-?} $(T 'is too old' 'ist zu alt')" \
      "$(T 'The server programs need Python 3.7 or newer.' 'Die Serverprogramme brauchen Python 3.7 oder neuer.')" "apt-get install -y python3"
  fi
else
  add_pkg python3
  OTHER=$(command -v python3 2>/dev/null || true)
  fail "python3: $(T "$PY not found" "$PY nicht gefunden")${OTHER:+ ($(T 'only' 'nur') $OTHER)}" \
    "$(T 'The systemd units start exactly /usr/bin/python3; a Python in /usr/local/bin (pyenv, compiled, python: Docker images) does not count.' 'Die systemd-Units starten genau /usr/bin/python3; ein Python in /usr/local/bin (pyenv, selbst gebaut, python:-Docker-Images) zaehlt nicht.') $(DOC install helper-service)" \
    "apt-get install -y python3"
fi

# ---- tools ----
need git git fail "$(T 'Needed to download the panel (git clone, see docs/install.md).' 'Zum Herunterladen des Panels noetig (git clone, siehe docs/install.de.md).')"
need curl curl fail "$(T 'Used by the checks in the install guide.' 'Wird von den Pruefungen in der Anleitung benutzt.')"
need openssl openssl fail "$(T 'Creates the audit key, checks certificates, hashes passwords (pacs-adduser.sh).' 'Erzeugt den Protokoll-Schluessel, prueft Zertifikate, hasht Passwoerter (pacs-adduser.sh).')"
need ip iproute2 fail "$(T 'firewall.py finds the network interface with ip route; this script uses it too.' 'firewall.py findet die Netzwerkschnittstelle mit ip route; dieses Skript auch.')"

if have cron; then
  if [ "$SYSTEMD" = 1 ]; then
    if systemctl is-active --quiet cron >/dev/null 2>&1; then ok "cron: $(T 'installed and running' 'installiert und laeuft')"
    else fail "cron: $(T 'installed, but not running' 'installiert, laeuft aber nicht')" \
      "$(T 'The overview numbers (status.json) are refreshed by a cron job every 5 minutes; nothing complains when cron is off.' 'Die Zahlen der Uebersicht (status.json) kommen alle 5 Minuten aus einem Cron-Job; es meldet sich niemand, wenn cron aus ist.')" \
      "systemctl enable --now cron"; fi
  elif pidof cron >/dev/null 2>&1; then ok "cron: $(T 'installed and a cron process is running' 'installiert, ein cron-Prozess laeuft')"
  else warn "cron: $(T 'installed, running state unknown (no systemd)' 'installiert, Laufzustand unbekannt (kein systemd)')" \
    "$(T 'The overview numbers are refreshed by a cron job every 5 minutes.' 'Die Zahlen der Uebersicht kommen alle 5 Minuten aus einem Cron-Job.')" "$(T 'start the cron daemon of your system' 'cron-Dienst des Systems starten')"; fi
else
  add_pkg cron
  fail "cron $(T 'not found' 'nicht gefunden')" \
    "$(T 'Without cron the overview numbers are never refreshed, and nothing tells you (/etc/cron.d exists anyway).' 'Ohne cron werden die Zahlen der Uebersicht nie erneuert, und nichts weist darauf hin (/etc/cron.d gibt es trotzdem).')" \
    "apt-get install -y cron"
fi

if have iptables; then
  IPT=$(iptables --version 2>/dev/null | nonul | head -n 1)
  case $IPT in *nf_tables*) IPK=nft ;; *legacy*) IPK=legacy ;; *) IPK="?" ;; esac
  ok "iptables: $IPT${IPT:+ }[$IPK]"
else
  add_pkg iptables
  warn "iptables $(T 'not found' 'nicht gefunden')" \
    "$(T 'Only the Firewall tab needs it; the rest of the panel works without.' 'Nur der Reiter Firewall braucht es; der Rest des Panels geht auch ohne.') $(DOC modules firewall)" "apt-get install -y iptables"
fi
need journalctl systemd warn "$(T 'Firewall tab: connection counters per rule come from the kernel log (journalctl -k).' 'Reiter Firewall: die Verbindungszaehler je Regel kommen aus dem Kernel-Log (journalctl -k).') $(DOC modules firewall)"

# disk assistant (pacs-storage.sh): util-linux, e2fsprogs, udev
M_UL=""; M_E2=""; M_UD=""
for t in lsblk blockdev blkid wipefs findmnt mount flock unshare; do have "$t" || M_UL="$M_UL $t"; done
for t in mkfs.ext4 tune2fs resize2fs; do have "$t" || M_E2="$M_E2 $t"; done
have udevadm || M_UD=" udevadm"
if [ -z "$M_UL$M_E2$M_UD" ]; then ok "$(T 'disk assistant tools present (util-linux, e2fsprogs, udev)' 'Werkzeuge des Platten-Assistenten vorhanden (util-linux, e2fsprogs, udev)')"
else
  [ -z "$M_UL" ] || add_pkg util-linux; [ -z "$M_E2" ] || add_pkg e2fsprogs; [ -z "$M_UD" ] || add_pkg udev
  warn "$(T 'disk assistant tools missing:' 'Werkzeuge des Platten-Assistenten fehlen:')$M_UL$M_E2$M_UD" \
    "$(T 'Only the optional disk assistant (pacs-storage.sh) needs them.' 'Nur der optionale Platten-Assistent (pacs-storage.sh) braucht sie.') $(DOC modules disk-assistant)" \
    "apt-get install -y$([ -z "$M_UL" ] || printf ' util-linux')$([ -z "$M_E2" ] || printf ' e2fsprogs')$([ -z "$M_UD" ] || printf ' udev')"
fi

# ======================================================================================================================
section "$(T 'Docker and dcm4chee' 'Docker und dcm4chee')"

DOCKER_OK=0
if ! have docker; then
  fail "docker $(T 'not found' 'nicht gefunden')" \
    "$(T 'dcm4chee, nginx and the login proxy run as Docker containers.' 'dcm4chee, nginx und der Login-Proxy laufen als Docker-Container.')" \
    "apt-get install -y docker.io    $(T '(or the packages from https://docs.docker.com/engine/install/debian/)' '(oder die Pakete von https://docs.docker.com/engine/install/debian/)')"
else
  DV=$(dk version --format '{{.Server.Version}}' 2>&1); DRC=$?
  if [ "$DRC" = 0 ] && [ -n "$DV" ]; then DOCKER_OK=1; ok "docker: $(T 'daemon reachable, version' 'Dienst erreichbar, Version') $DV"
  elif [ "$DRC" = 124 ]; then
    fail "docker: $(T "installed, but the daemon did not answer within $DK_SECS seconds" "installiert, aber der Dienst antwortete nicht innerhalb von $DK_SECS Sekunden")" \
      "$(T 'Docker hangs, or DOCKER_HOST points to a machine that does not answer; the dcm4chee discovery is skipped.' 'Docker haengt, oder DOCKER_HOST zeigt auf einen Rechner, der nicht antwortet; die Suche nach dcm4chee entfaellt.')" \
      "systemctl restart docker"
  elif printf '%s' "$DV" | grep -qi 'permission denied'; then
    warn "docker: $(T 'no permission to talk to the Docker daemon' 'keine Berechtigung fuer den Docker-Dienst')" \
      "$(T 'Run this script as root (or as a member of the docker group); the dcm4chee discovery is skipped.' 'Das Skript als root starten (oder als Mitglied der Gruppe docker); die Suche nach dcm4chee entfaellt.')" "$SUDO_CMD"
  else
    fail "docker: $(T 'installed, but the daemon does not answer' 'installiert, aber der Dienst antwortet nicht')" \
      "$(T 'Docker is not running (or DOCKER_HOST points somewhere else); the dcm4chee discovery is skipped.' 'Docker laeuft nicht (oder DOCKER_HOST zeigt woandershin); die Suche nach dcm4chee entfaellt.')" \
      "systemctl enable --now docker"
  fi
  CV=$(dk compose version 2>/dev/null | head -n 1)
  if [ -n "$CV" ]; then ok "docker compose: $CV"
  elif have docker-compose; then
    warn "docker compose: $(T 'only the old docker-compose command exists' 'nur das alte Kommando docker-compose vorhanden')" \
      "$(T 'The example compose files and the guide use the plugin form: docker compose ...' 'Die Beispiel-Dateien und die Anleitung benutzen die Plugin-Form: docker compose ...')" \
      "$(T 'Debian 13: apt-get install -y docker-compose; Debian 12: package docker-compose-plugin from the Docker repository' 'Debian 13: apt-get install -y docker-compose; Debian 12: Paket docker-compose-plugin aus dem Docker-Repository')"
  else
    fail "docker compose: $(T 'plugin not found' 'Plugin nicht gefunden')" \
      "$(T 'The example compose files need the compose plugin (command: docker compose).' 'Die Beispiel-Dateien brauchen das Compose-Plugin (Kommando: docker compose).')" \
      "$(T 'Debian 13: apt-get install -y docker-compose; Debian 12: package docker-compose-plugin from the Docker repository' 'Debian 13: apt-get install -y docker-compose; Debian 12: Paket docker-compose-plugin aus dem Docker-Repository')"
  fi
fi

PS_LINES=""
if [ "$DOCKER_OK" = 1 ]; then
  # container names from the image names of the stock dcm4chee compose files
  PS_RAW=$(dk ps -a --format '{{.Names}}|{{.Image}}|{{.State}}' 2>&1); PS_RC=$?
  if [ "$PS_RC" != 0 ]; then
    DOCKER_OK=0
    fail "docker ps: $(T "failed (exit code $PS_RC)" "fehlgeschlagen (Exit-Code $PS_RC)"): $(printf '%s\n' "$PS_RAW" | head -n 1)" \
      "$(T 'The container list could not be read; the dcm4chee discovery is skipped.' 'Die Container-Liste liess sich nicht lesen; die Suche nach dcm4chee entfaellt.')" "docker ps -a"
  else
    PS_LINES=$(printf '%s\n' "$PS_RAW" | tr -d '\r' | clean)
  fi
fi

if [ "$DOCKER_OK" = 0 ]; then
  warn "$(T 'dcm4chee discovery skipped' 'Suche nach dcm4chee uebersprungen')" \
    "$(T 'Without a reachable Docker daemon this script cannot find the containers, network and log directory.' 'Ohne erreichbaren Docker-Dienst findet dieses Skript Container, Netzwerk und Log-Verzeichnis nicht.')" \
    "$(T 'see the docker lines above' 'siehe die docker-Zeilen oben')"
else
  A_N=""; A_I=""; A_S=""; A_OTHER=""; L_N=""; L_I=""; L_S=""; D_N=""; D_I=""; D_S=""
  while IFS='|' read -r n i s; do
    [ -n "$n" ] || continue
    b=${i##*/}; b=${b%%[:@]*}
    [ "$n" != ohif ] || { O_N=$n; O_I=$i; }
    case $b in
      dcm4chee-arc-*)    if [ -z "$A_N" ]; then A_N=$n; A_I=$i; A_S=$s; else A_OTHER="$A_OTHER $n"; fi ;;
      slapd-dcm4chee*)   [ -n "$L_N" ] || { L_N=$n; L_I=$i; L_S=$s; } ;;
      postgres-dcm4chee*) [ -n "$D_N" ] || { D_N=$n; D_I=$i; D_S=$s; } ;;
    esac
  done < <(printf '%s\n' "$PS_LINES")

  if [ -z "$A_N" ]; then
    fail "$(T 'no dcm4chee archive container found' 'kein dcm4chee-Archiv-Container gefunden')" \
      "$(T 'Looked for an image named dcm4che/dcm4chee-arc-psql; the panel talks to a dcm4chee archive running in Docker.' 'Gesucht wurde ein Image dcm4che/dcm4chee-arc-psql; das Panel spricht mit einem dcm4chee-Archiv, das in Docker laeuft.')" \
      "docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.State}}'"
  else
    V_ARC=$A_N
    case ${A_I##*/} in
      *-secure*)
        fail "arc: $A_N ($A_I)" \
          "$(T 'This is the variant with its own Keycloak login. The panel does not support it; it needs the plain dcm4chee-arc-psql image.' 'Das ist die Variante mit eigenem Keycloak-Login. Das Panel unterstuetzt sie nicht; es braucht das normale Image dcm4chee-arc-psql.')" \
          "$(T "run dcm4che/dcm4chee-arc-psql (without -secure), see $(DOC login)" "dcm4che/dcm4chee-arc-psql (ohne -secure) betreiben, siehe $(DOC login)")" ;;
      *dcm4chee-arc-psql*)
        if [ "$A_S" = running ]; then ok "arc: $A_N ($A_I, $A_S)"
        else warn "arc: $A_N ($A_I, $A_S)" "$(T 'The archive container is not running.' 'Der Archiv-Container laeuft nicht.')" "docker start $A_N"; fi ;;
      *)
        warn "arc: $A_N ($A_I, $A_S)" \
          "$(T 'Only the PostgreSQL variant (dcm4chee-arc-psql) is tested.' 'Getestet ist nur die PostgreSQL-Variante (dcm4chee-arc-psql).')" "" ;;
    esac
    [ -z "$A_OTHER" ] || warn "$(T 'more than one archive container:' 'mehr als ein Archiv-Container:')$A_OTHER" \
      "$(T "Using $A_N for the values below; one panel talks to one archive." "Fuer die Werte unten gilt $A_N; ein Panel spricht mit einem Archiv.")" ""
    [ "$A_N" = "$EFF_ARC" ] || warn "$(T "ARC_CONTAINER is '$EFF_ARC', but the archive container is called '$A_N'" "ARC_CONTAINER ist '$EFF_ARC', der Archiv-Container heisst aber '$A_N'")" \
      "$(T 'The disk assistant runs docker exec in the container named by ARC_CONTAINER.' 'Der Platten-Assistent fuehrt docker exec im Container aus, den ARC_CONTAINER nennt.')" "echo \"ARC_CONTAINER='$A_N'\" >> $ENVF"
  fi
  if [ -n "$L_N" ]; then
    V_LDAP=$L_N
    if [ "$L_S" = running ]; then ok "ldap: $L_N ($L_I, $L_S)"
    else warn "ldap: $L_N ($L_I, $L_S)" "$(T 'The LDAP container is not running.' 'Der LDAP-Container laeuft nicht.')" "docker start $L_N"; fi
    [ "$L_N" = "$EFF_LDAP" ] || warn "$(T "LDAP_CONTAINER is '$EFF_LDAP', but the LDAP container is called '$L_N'" "LDAP_CONTAINER ist '$EFF_LDAP', der LDAP-Container heisst aber '$L_N'")" \
      "$(T 'The disk assistant runs ldapsearch/ldapmodify in the container named by LDAP_CONTAINER.' 'Der Platten-Assistent fuehrt ldapsearch/ldapmodify im Container aus, den LDAP_CONTAINER nennt.')" "echo \"LDAP_CONTAINER='$L_N'\" >> $ENVF"
  else
    warn "$(T 'no LDAP container found (image dcm4che/slapd-dcm4chee)' 'kein LDAP-Container gefunden (Image dcm4che/slapd-dcm4chee)')" \
      "$(T 'Only the optional disk assistant needs it (it writes the storages into the archive configuration in LDAP).' 'Nur der optionale Platten-Assistent braucht ihn (er traegt Storages in die Archiv-Konfiguration in LDAP ein).') $(DOC modules disk-assistant)" \
      "docker ps -a --format 'table {{.Names}}\t{{.Image}}'"
  fi
  if [ -n "$D_N" ]; then V_DB=$D_N; ok "db: $D_N ($D_I, $D_S)"
  else warn "$(T 'no database container found (image dcm4che/postgres-dcm4chee)' 'kein Datenbank-Container gefunden (Image dcm4che/postgres-dcm4chee)')" \
    "$(T 'Informational only (the overview lists all containers of the compose project).' 'Nur zur Information (die Uebersicht zeigt alle Container des Compose-Projekts).')" ""; fi

  if [ -n "$A_N" ]; then
    # compose project directory (label), compose files
    LAB=$(dk inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}|{{index .Config.Labels "com.docker.compose.project.config_files"}}' "$A_N" 2>/dev/null | tr -d '\r' | clean)
    V_DIR=${LAB%%|*}; V_FILES=${LAB#*|}
    if [ -z "$V_DIR" ]; then
      warn "$(T 'compose project directory of arc: unknown (container was not started by docker compose)' 'Compose-Verzeichnis von arc: unbekannt (Container nicht mit docker compose gestartet)')" \
        "$(T 'PACS_DIR must name the directory with the docker-compose.yml of dcm4chee; the overview tile "Dienste" uses it.' 'PACS_DIR muss das Verzeichnis mit der docker-compose.yml von dcm4chee nennen; die Kachel "Dienste" der Uebersicht benutzt es.')" \
        "$(T 'set PACS_DIR in /etc/default/pacs-admin' 'PACS_DIR in /etc/default/pacs-admin setzen')"
    elif [ ! -d "$V_DIR" ]; then
      warn "$(T 'compose project directory of arc' 'Compose-Verzeichnis von arc'): $V_DIR ($(T 'does not exist on this host' 'gibt es auf diesem Rechner nicht'))" \
        "$(T 'Docker may talk to another machine, or the project was moved.' 'Docker spricht evtl. mit einem anderen Rechner, oder das Projekt wurde verschoben.')" "ls -ld $V_DIR"
    elif [ "${V_DIR%/}" = "${EFF_DIR%/}" ]; then ok "$(T 'compose project directory of arc' 'Compose-Verzeichnis von arc'): $V_DIR ($(T 'matches PACS_DIR' 'passt zu PACS_DIR'))"
    else
      warn "$(T 'compose project directory of arc' 'Compose-Verzeichnis von arc'): $V_DIR" \
        "$(T "The panel looks in $EFF_DIR (PACS_DIR, default $DEF_DIR), not where the compose project of arc lives." "Das Panel sucht in $EFF_DIR (PACS_DIR, Vorgabe $DEF_DIR), nicht dort, wo das Compose-Projekt von arc liegt.")" \
        "echo \"PACS_DIR='$V_DIR'\" >> $ENVF"
    fi

    # Docker network(s) of arc: the nginx container must join one of them
    # shellcheck disable=SC2016
    NETS=$(dk inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$A_N" 2>/dev/null | tr -d '\r' | clean)
    NETS=${NETS% }; V_NET=${NETS%% *}
    if [ -z "$V_NET" ]; then
      warn "$(T 'Docker network of arc: not found' 'Docker-Netzwerk von arc: nicht gefunden')" \
        "$(T 'The nginx container reaches arc through a shared Docker network.' 'Der nginx-Container erreicht arc ueber ein gemeinsames Docker-Netzwerk.')" "docker inspect $A_N"
    elif [ "$V_NET" = bridge ]; then
      warn "$(T 'Docker network of arc: bridge (the default network)' 'Docker-Netzwerk von arc: bridge (das Standardnetz)')" \
        "$(T 'Containers on the default bridge cannot reach each other by name, so nginx could not find "arc".' 'Container im Standardnetz finden sich nicht per Namen, nginx koennte "arc" nicht aufloesen.')" \
        "$(T 'start arc through a compose file (it creates its own network)' 'arc ueber eine Compose-Datei starten (sie legt ein eigenes Netzwerk an)')"
    else
      ok "$(T 'Docker network of arc' 'Docker-Netzwerk von arc'): $V_NET$([ "$NETS" = "$V_NET" ] || printf ' (%s: %s)' "$(T 'all' 'alle')" "$NETS")"
    fi

    # host directory of the wildfly log (mount of /opt/wildfly/standalone)
    MNT=$(dk inspect -f '{{range .Mounts}}{{.Source}}|{{.Destination}}{{"\n"}}{{end}}' "$A_N" 2>/dev/null | tr -d '\r' | clean)
    V_LOG=""
    while IFS='|' read -r src dst; do
      case $dst in
        /opt/wildfly/standalone)     V_LOG=${src%/}/log/ ;;
        /opt/wildfly/standalone/log) V_LOG=${src%/}/ ;;
      esac
    done < <(printf '%s\n' "$MNT")
    if [ -z "$V_LOG" ]; then
      warn "$(T 'wildfly log directory: arc has no host mount for /opt/wildfly/standalone' 'wildfly-Log-Verzeichnis: arc hat keinen Host-Mount fuer /opt/wildfly/standalone')" \
        "$(T 'The Firewall tab reads the DICOM/HL7 senders from server.log on the host; without a mount the sender lists stay empty.' 'Der Reiter Firewall liest die DICOM-/HL7-Absender aus server.log auf dem Host; ohne Mount bleiben die Absenderlisten leer.') $(DOC modules firewall)" \
        "$(T 'mount a host directory at /opt/wildfly/standalone in the dcm4chee compose file' 'ein Host-Verzeichnis nach /opt/wildfly/standalone in die dcm4chee-Compose-Datei einhaengen')"
    elif [ ! -d "$V_LOG" ]; then
      warn "$(T 'wildfly log directory' 'wildfly-Log-Verzeichnis'): $V_LOG ($(T 'does not exist on this host' 'gibt es auf diesem Rechner nicht'))" \
        "$(T 'Docker may talk to another machine, or arc has never started.' 'Docker spricht evtl. mit einem anderen Rechner, oder arc wurde nie gestartet.')" "ls -ld $V_LOG"
    elif [ "${V_LOG%/}" != "${EFF_LOG%/}" ]; then
      warn "$(T 'wildfly log directory' 'wildfly-Log-Verzeichnis'): $V_LOG" \
        "$(T "The panel reads the logs from $EFF_LOG (ARC_LOG_DIR, default $DEF_LOG); with a wrong value the journal shows an error every 5 minutes." "Das Panel liest die Logs aus $EFF_LOG (ARC_LOG_DIR, Vorgabe $DEF_LOG); bei falschem Wert steht alle 5 Minuten ein Fehler im Journal.")" \
        "echo \"ARC_LOG_DIR='$V_LOG'\" >> $ENVF"
    else ok "$(T 'wildfly log directory' 'wildfly-Log-Verzeichnis'): $V_LOG ($(T 'matches ARC_LOG_DIR' 'passt zu ARC_LOG_DIR'))"; fi
  fi

  # LDAP root password inside the ldap container (only tests that it exists, never prints it)
  if [ -n "$L_N" ] && [ "$L_S" = running ]; then
    # shellcheck disable=SC2016
    if dk exec "$L_N" sh -c '[ -n "${LDAP_ROOTPASS:-}" ] || [ -n "${LDAP_ROOTPASS_FILE:-}" ]' >/dev/null 2>&1; then
      ok "$(T "LDAP_ROOTPASS or LDAP_ROOTPASS_FILE is set in container $L_N (value not shown)" "LDAP_ROOTPASS oder LDAP_ROOTPASS_FILE ist im Container $L_N gesetzt (Wert wird nicht angezeigt)")"
    else
      warn "$(T "neither LDAP_ROOTPASS nor LDAP_ROOTPASS_FILE is set in container $L_N" "weder LDAP_ROOTPASS noch LDAP_ROOTPASS_FILE ist im Container $L_N gesetzt")" \
        "$(T 'The disk assistant logs in to LDAP with the root password of that container; without it every disk action fails.' 'Der Platten-Assistent meldet sich mit dem Root-Passwort dieses Containers an LDAP an; ohne es scheitert jede Platten-Aktion.') $(DOC modules disk-assistant)" \
        "$(T 'add LDAP_ROOTPASS (or LDAP_ROOTPASS_FILE) to the ldap service in the dcm4chee compose file' 'LDAP_ROOTPASS (oder LDAP_ROOTPASS_FILE) beim ldap-Dienst in der dcm4chee-Compose-Datei eintragen')"
    fi
  fi
fi

# ======================================================================================================================
section "$(T 'Host settings' 'Einstellungen des Rechners')"

# ---- storage mounts ----
SB=$EFF_SB; SP=$EFF_SP
if [ ! -d "$SB" ]; then
  warn "$(T "$SB does not exist" "$SB existiert nicht")" \
    "$(T 'Only the optional disk assistant needs it (default STORAGE_BASE); the archive may keep its data somewhere else.' 'Nur der optionale Platten-Assistent braucht es (Vorgabe STORAGE_BASE); das Archiv kann seine Daten woanders haben.')" "mkdir -p $SB"
elif have findmnt; then
  MNTS=$(findmnt -rn -o TARGET 2>/dev/null | awk -v b="$SB/" 'index($0, b) == 1')
  PROP=$(findmnt -T "$SB" -n -o PROPAGATION 2>/dev/null | nonul | head -n 1)
  if [ -z "$MNTS" ]; then ok "$(T "no storage disks mounted under $SB yet (normal before the first disk)" "noch keine Speicherplatten unter $SB eingehaengt (normal vor der ersten Platte)")"
  else
    NM=$(printf '%s\n' "$MNTS" | wc -l | tr -d ' ')
    NP=$(printf '%s\n' "$MNTS" | grep -c "^$SB/${SP}[0-9]")
    isnum "$NP" || NP=0
    if [ "$NP" -gt 0 ]; then ok "$(T "$NM mount(s) under $SB, $NP named ${SP}NN" "$NM Mount(s) unter $SB, davon $NP mit Namen ${SP}NN")"
    else warn "$(T "$NM mount(s) under $SB, none named ${SP}NN" "$NM Mount(s) unter $SB, keiner heisst ${SP}NN")" \
      "$(T "The disk assistant and the Storage tile only know disks named ${SP}NN (STORAGE_PREFIX)." "Der Platten-Assistent und die Kachel Speicher kennen nur Platten namens ${SP}NN (STORAGE_PREFIX).") $(DOC modules disk-assistant)" "findmnt -R $SB"; fi
  fi
  case ${PROP:-} in
    "") ;;
    *shared*|*slave*) ok "$(T "mount propagation of $SB: $PROP (new disks become visible in arc with :rslave)" "Mount-Propagation von $SB: $PROP (neue Platten werden in arc mit :rslave sichtbar)")" ;;
    *) warn "$(T "mount propagation of $SB: $PROP" "Mount-Propagation von $SB: $PROP")" \
      "$(T 'With private propagation, a volume with :rslave is refused and new disks do not show up inside arc.' 'Bei privater Propagation wird ein Volume mit :rslave abgelehnt, neue Platten erscheinen nicht in arc.')" "mount --make-rshared /" ;;
  esac
else
  warn "$(T 'findmnt not found: storage mounts not checked' 'findmnt nicht gefunden: Storage-Mounts nicht geprueft')" "" "apt-get install -y util-linux"; add_pkg util-linux
fi

# ---- uid 101 (nginx worker in the official nginx/OHIF image) ----
U101=$(getent passwd 101 2>/dev/null | cut -d: -f1 | clean)
if [ -z "$U101" ]; then V_UID=101; ok "$(T 'uid 101 (nginx in the container) is free on this host' 'uid 101 (nginx im Container) ist auf diesem Rechner frei')"
else
  V_UID=101; V_UIDNOTE=$(T "uid 101 is also the account '$U101' on this host (see the [WARN] above)" "uid 101 ist auf diesem Rechner auch das Konto '$U101' (siehe die [WARN]-Zeile oben)")
  warn "$(T "uid 101 belongs to the account '$U101' on this host" "uid 101 gehoert auf diesem Rechner dem Konto '$U101'")" \
    "$(T "The helper service gives its sockets to uid 101 so that nginx in the container can use them; every process of the account '$U101' on this host can use them too. For a plain system account (Debian 12: messagebus) that is a small risk; it matters if other people's programs run as that account." "Der Hilfsdienst gibt seine Sockets der uid 101, damit nginx im Container sie nutzen kann; jeder Prozess des Kontos '$U101' auf diesem Rechner kann sie dann auch nutzen. Bei einem reinen Systemkonto (Debian 12: messagebus) ist das ein kleines Risiko; es zaehlt, wenn fremde Programme unter diesem Konto laufen.") $(DOC install helper-service)" \
    "$(T 'nothing to do for a plain system account; otherwise keep other programs away from that account, or set PACS_SOCKET_UID to the uid of nginx in your container' 'bei einem reinen Systemkonto nichts zu tun; sonst fremde Programme von diesem Konto fernhalten, oder PACS_SOCKET_UID auf die uid von nginx im Container setzen')"
fi

# ---- ports 80 and 443 ----
if have ss; then
  for p in 80 443; do
    if ss -ltn 2>/dev/null | awk -v p=":$p" 'NR > 1 && $4 ~ (p "$") {f = 1} END {exit f ? 0 : 1}'; then
      WHO=$(ss -ltnp 2>/dev/null | awk -v p=":$p" '$4 ~ (p "$")' | sed -n 's/.*users:(("\([^"]*\)".*/\1/p' | sort -u | tr '\n' ' ' | sed 's/ $//')
      warn "$(T "port $p is already in use" "Port $p ist schon belegt")${WHO:+ ($WHO)}" \
        "$(T 'nginx cannot publish this port, unless the listener is the admin panel itself (a re-run after the installation).' 'nginx kann den Port nicht veroeffentlichen, ausser der Belegende ist das Admin-Panel selbst (erneuter Lauf nach der Installation).')" "ss -ltnp | grep ':$p '"
    else ok "$(T "port $p is free" "Port $p ist frei")"; fi
  done
else
  warn "$(T 'ss not found: ports 80 and 443 not checked' 'ss nicht gefunden: Ports 80 und 443 nicht geprueft')" "" "apt-get install -y iproute2"; add_pkg iproute2
fi

# ---- default route interface ----
if have ip; then
  V_IFACE=$(ip -o route show default 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "dev") {print $(i + 1); exit}}')
  if [ -n "$V_IFACE" ]; then ok "$(T 'default-route interface' 'Schnittstelle der Standardroute'): $V_IFACE"
  else warn "$(T 'no default route found' 'keine Standardroute gefunden')" \
    "$(T 'firewall.py needs the outside interface; set FW_INTERFACE by hand.' 'firewall.py braucht die Schnittstelle nach aussen; FW_INTERFACE von Hand setzen.') $(DOC modules firewall)" "ip -br link"; fi
fi

# ---- /etc/localtime (mounted into the containers) ----
if [ -e /etc/localtime ]; then
  TZN=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')
  ok "/etc/localtime: ${TZN:-$(T 'present' 'vorhanden')}"
else
  warn "/etc/localtime $(T 'is missing' 'fehlt')" \
    "$(T 'The compose files mount it into the containers; a missing file makes docker compose fail or creates a directory.' 'Die Compose-Dateien haengen sie in die Container ein; fehlt die Datei, scheitert docker compose oder legt ein Verzeichnis an.')" \
    "timedatectl set-timezone Europe/Berlin   $(T '(your Area/City)' '(eigenes Gebiet/Ort)')"
fi

# ---- DNS name ----
if [ -n "$HOST" ]; then
  ADDRS=$(getent ahosts "$HOST" 2>/dev/null | nonul | awk '{print $1}' | sort -u)
  if [ -z "$ADDRS" ]; then
    fail "DNS: $HOST $(T 'does not resolve' 'wird nicht aufgeloest')" \
      "$(T 'Browsers, the login redirect and the certificate all need this name to resolve.' 'Browser, die Login-Weiterleitung und das Zertifikat brauchen diesen Namen aufloesbar.')" \
      "$(T 'create the DNS record (or an /etc/hosts line for a test)' 'DNS-Eintrag anlegen (oder zum Testen eine Zeile in /etc/hosts)')"
  else
    if have ip; then LOCALS=$(ip -o addr show 2>/dev/null | awk '{print $4}' | sed 's|/.*||'); else LOCALS=$(hostname -I 2>/dev/null | tr ' ' '\n'); fi
    LOCALS=$(printf '%s\n127.0.0.1\n::1\n' "$LOCALS")
    HIT=""; for a in $ADDRS; do [ "${#a}" -le 64 ] || continue; printf '%s\n' "$LOCALS" | grep -Fxq "$a" && HIT="$HIT $a"; done   # an address has at most 45 characters
    AL=$(printf '%s' "$ADDRS" | tr '\n' ' ' | sed 's/ $//')
    if [ -n "$HIT" ]; then ok "DNS: $HOST -> $AL ($(T 'an address of this host' 'eine Adresse dieses Rechners'))"
    else warn "DNS: $HOST -> $AL ($(T 'not an address of this host' 'keine Adresse dieses Rechners'))" \
      "$(T 'Fine behind NAT, a load balancer or a front proxy. Otherwise users reach another machine.' 'In Ordnung hinter NAT, Lastverteiler oder Vorschaltproxy. Sonst erreichen die Nutzer einen anderen Rechner.')" "ip -br addr"; fi
  fi
fi

# ======================================================================================================================
# img_kind IMAGE: how the nginx master runs in that image: nonroot (uid 101: ohif/app, nginx-unprivileged), root (the plain
# nginx image), else empty
img_kind() {
  local base=${1%%[:@]*}
  case $1 in *ohif/app*|*unprivileged*) echo nonroot; return 0 ;; esac
  case $base in nginx|library/nginx|docker.io/library/nginx) echo root ;; esac
  return 0
}
# nginx_kind: which of the two, from the container "ohif" (its user, else its image), else from the image lines of the
# compose file in --dir; empty when it cannot be known (nginx on the host: the master is root)
nginx_kind() {
  local u cf imgs i k kinds=""
  if [ -n "$O_N" ] && u=$(dk inspect -f '{{.Config.User}}' "$O_N" 2>/dev/null); then
    u=$(printf '%s' "$u" | tr -d '\r\n')
    case $u in ''|0|root|0:*|root:*) echo root ;; *) echo nonroot ;; esac
    return 0
  fi
  if [ -n "$O_I" ]; then k=$(img_kind "$O_I"); [ -z "$k" ] || { echo "$k"; return 0; }; fi
  [ -n "$DIR" ] || return 0
  for cf in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    [ -r "$DIR/$cf" ] || continue
    imgs=$(sed -n 's/^[[:space:]]*image:[[:space:]]*//p' "$DIR/$cf" | sed "s/[[:space:]]*#.*//; s/[\"']//g")
    # shellcheck disable=SC2086
    for i in $imgs; do
      k=$(img_kind "$i"); [ -z "$k" ] && continue
      case " $kinds " in *" $k "*) ;; *) kinds="$kinds $k" ;; esac
    done
  done
  case $kinds in " nonroot") echo nonroot ;; " root") echo root ;; esac
  return 0
}

# key_permissions: who can read $KEY compared with who must (the user of the nginx master: root, or uid 101 in the OHIF image)
key_permissions() {
  local st mode uid gid m un gn kind r101=0 qk fo fr what
  st=$(stat -c '%a %u %g' "$KEY" 2>/dev/null) || return 0
  mode=${st%% *}; st=${st#* }; uid=${st%% *}; gid=${st#* }
  isnum "$mode" && isnum "$uid" && isnum "$gid" || return 0
  case $mode in *[89]*) return 0 ;; esac
  m=$((8#$mode))
  [ $((m & 4)) -eq 0 ] || r101=1
  [ "$gid" != 101 ] || [ $((m & 32)) -eq 0 ] || r101=1
  [ "$uid" != 101 ] || [ $((m & 256)) -eq 0 ] || r101=1
  un=$uid; [ "$uid" != 0 ] || un=root; gn=$gid; [ "$gid" != 0 ] || gn=root
  what="$un:$gn $mode"; qk=$(q "$KEY")
  fo="chown root:101 $qk && chmod 640 $qk"; fr="chown root:root $qk && chmod 600 $qk"
  kind=$(nginx_kind)
  case $kind in
    nonroot)
      if [ "$r101" = 0 ]; then
        fail "$(T "private key ($what) cannot be read by the nginx of the OHIF image" "privater Schluessel ($what) ist fuer das nginx des OHIF-Images nicht lesbar")" \
          "$(T 'The nginx master process in the OHIF image runs as uid 101 (not root), so it cannot load a key that only root may read: the container does not start.' 'Der nginx-Hauptprozess im OHIF-Image laeuft als uid 101 (nicht root) und kann einen Schluessel, den nur root lesen darf, nicht laden: der Container startet nicht.') $(DOC install tls-certificate)" "$fo"
      elif [ $((m & 4)) -ne 0 ]; then
        warn "$(T "private key is readable by everybody (mode $mode)" "privater Schluessel ist fuer alle lesbar (Modus $mode)")" \
          "$(T 'With the OHIF image only root and uid 101 (the nginx master) need access.' 'Mit dem OHIF-Image brauchen nur root und uid 101 (der nginx-Hauptprozess) Zugriff.') $(DOC install tls-certificate)" "$fo"
      else ok "$(T "private key permissions fit the OHIF image ($what, readable by uid 101 only)" "Rechte des privaten Schluessels passen zum OHIF-Image ($what, nur fuer uid 101 lesbar)")"; fi ;;
    root)
      if [ $((m & 4)) -ne 0 ]; then
        warn "$(T "private key is readable by everybody (mode $mode)" "privater Schluessel ist fuer alle lesbar (Modus $mode)")" \
          "$(T 'The nginx master process runs as root and reads the key at start-up; nobody else needs access.' 'Der nginx-Hauptprozess laeuft als root und liest den Schluessel beim Start; sonst braucht niemand Zugriff.') $(DOC install tls-certificate)" "$fr"
      elif [ $((m & 63)) -ne 0 ]; then
        warn "$(T "private key is readable by its group (mode $mode)" "privater Schluessel ist fuer seine Gruppe lesbar (Modus $mode)")" \
          "$(T 'The nginx master process runs as root and reads the key at start-up; nobody else needs access (root:root 0600; root:101 0640 is only for the OHIF image).' 'Der nginx-Hauptprozess laeuft als root und liest den Schluessel beim Start; sonst braucht niemand Zugriff (root:root 0600; root:101 0640 gilt nur fuer das OHIF-Image).') $(DOC install tls-certificate)" "$fr"
      else ok "$(T "private key permissions fit the plain nginx image ($what)" "Rechte des privaten Schluessels passen zum normalen nginx-Image ($what)")"; fi ;;
    *)
      if [ $((m & 4)) -ne 0 ]; then
        warn "$(T "private key is readable by everybody (mode $mode)" "privater Schluessel ist fuer alle lesbar (Modus $mode)")" \
          "$(T "Rights depend on the image: OHIF image (ohif/app, nginx master runs as uid 101): $fo. Plain nginx image or nginx on the host (master runs as root): $fr." "Die Rechte haengen vom Image ab: OHIF-Image (ohif/app, nginx-Hauptprozess laeuft als uid 101): $fo. Normales nginx-Image oder nginx auf dem Host (Hauptprozess laeuft als root): $fr.") $(DOC install tls-certificate)" \
          "$(T 'OHIF image: ' 'OHIF-Image: ')$fo   $(T 'plain nginx or host: ' 'normales nginx oder Host: ')$fr"
      else ok "$(T "private key: $what" "privater Schluessel: $what")" \
        "$(T "Which rights fit depends on the image: root:101 640 for the OHIF image (nginx master runs as uid 101), root:root 600 for the plain nginx image or nginx on the host (master is root). Give --dir with your compose file and this script knows which one applies." "Welche Rechte passen, haengt vom Image ab: root:101 640 fuer das OHIF-Image (nginx-Hauptprozess laeuft als uid 101), root:root 600 fuer das normale nginx-Image oder nginx auf dem Host (Hauptprozess ist root). Mit --dir und der Compose-Datei weiss dieses Skript, was gilt.")"; fi ;;
  esac
}

if [ -n "$CERT$KEY" ]; then
  section "$(T 'TLS certificate' 'TLS-Zertifikat')"
  nth_cert() { printf '%s\n' "$PEM" | awk -v n="$1" '/-----BEGIN CERTIFICATE-----/ {c++} c == n {print} /-----END CERTIFICATE-----/ && c == n {exit}'; }
  one() { local s=$1; shift; printf '%s\n' "$s" | openssl x509 -noout "$@" 2>/dev/null; }
  name_of() { sed 's/^[a-zA-Z]*=//'; }
  if ! have openssl; then
    fail "openssl $(T 'not found: certificate not checked' 'nicht gefunden: Zertifikat nicht geprueft')" "" "apt-get install -y openssl"; add_pkg openssl
  else
    PUBC=""; PUBK=""; NC=0
    if [ -n "$CERT" ]; then
      if [ ! -f "$CERT" ] || [ ! -r "$CERT" ]; then
        fail "$(T 'certificate: not a readable file' 'Zertifikat: keine lesbare Datei'): $CERT" "$(T 'Keys and certificates are often readable by root only; run this script as root.' 'Schluessel und Zertifikate darf oft nur root lesen; das Skript als root starten.')" "$SUDO_CMD"
      else
        PEM=$(tr -d '\000' < "$CERT"); NC=$(printf '%s\n' "$PEM" | grep -c -- '-----BEGIN CERTIFICATE-----')
        isnum "$NC" || NC=0
        C1=$(nth_cert 1)
        if [ "$NC" = 0 ] || ! one "$C1" >/dev/null; then
          fail "$(T 'certificate: not a PEM certificate' 'Zertifikat: keine PEM-Datei mit Zertifikat'): $CERT" \
            "$(T 'nginx wants PEM text starting with -----BEGIN CERTIFICATE-----.' 'nginx will PEM-Text, der mit -----BEGIN CERTIFICATE----- beginnt.')" \
            "openssl x509 -in $(q "$CERT") -noout -text | head   $(T '(a .crt/.cer in binary form: openssl x509 -inform der -in FILE -out cert.pem)' '(.crt/.cer in Binaerform: openssl x509 -inform der -in DATEI -out cert.pem)')"
        else
          SUBJ=$(one "$C1" -subject -nameopt RFC2253 | name_of); ISS=$(one "$C1" -issuer -nameopt RFC2253 | name_of)
          PUBC=$(one "$C1" -pubkey)
          ok "$(T 'certificate' 'Zertifikat'): $SUBJ"
          # expiry
          END=$(one "$C1" -enddate | sed 's/^notAfter=//')
          DAYS=""; EP=$(date -u -d "$END" +%s 2>/dev/null); NOW=$(date -u +%s 2>/dev/null)
          if isnum "$EP" && isnum "$NOW"; then DAYS=$(( (EP - NOW) / 86400 )); fi
          if ! one "$C1" -checkend 0 >/dev/null; then
            fail "$(T 'certificate expired' 'Zertifikat abgelaufen'): $END" "$(T 'Browsers and API clients refuse it.' 'Browser und API-Clients lehnen es ab.')" "$(T 'renew the certificate' 'Zertifikat erneuern')"
          elif ! one "$C1" -checkend 2592000 >/dev/null; then
            warn "$(T 'certificate expires soon' 'Zertifikat laeuft bald ab'): $END${DAYS:+ ($DAYS $(T 'days' 'Tage'))}" "$(T 'Less than 30 days left.' 'Weniger als 30 Tage uebrig.')" "$(T 'renew the certificate' 'Zertifikat erneuern')"
          else ok "$(T 'certificate valid until' 'Zertifikat gueltig bis'): $END${DAYS:+ ($DAYS $(T 'days' 'Tage'))}"; fi
          # names: current browsers only look at subjectAltName, never at the common name
          HAS_SAN=0; one "$C1" -text | grep -q 'Subject Alternative Name' && HAS_SAN=1
          NEWCERT="openssl req -x509 -newkey rsa:2048 -nodes -days 365 -keyout server.key -out server.crt -subj /CN=${HOST:-pacs.example.org} -addext subjectAltName=DNS:${HOST:-pacs.example.org}"
          if [ -n "$HOST" ]; then
            case $HOST in *[!0-9.]*|'') case $HOST in *:*) HOSTCHK=-checkip ;; *) HOSTCHK=-checkhost ;; esac ;; *) HOSTCHK=-checkip ;; esac
            if one "$C1" "$HOSTCHK" "$HOST" | grep -q 'does match'; then
              if [ "$HAS_SAN" = 1 ]; then ok "$(T "certificate covers $HOST" "Zertifikat gilt fuer $HOST")"
              else warn "$(T "certificate matches $HOST only by its common name: no subjectAltName" "Zertifikat passt zu $HOST nur ueber den Common Name: kein subjectAltName")" \
                "$(T 'Current browsers refuse a certificate without subjectAltName (ERR_CERT_COMMON_NAME_INVALID), also a self-signed one. Create the certificate with the name in subjectAltName.' 'Aktuelle Browser lehnen ein Zertifikat ohne subjectAltName ab (ERR_CERT_COMMON_NAME_INVALID), auch ein selbst signiertes. Das Zertifikat mit dem Namen im subjectAltName erstellen.') $(DOC install tls-certificate)" "$NEWCERT"; fi
            else fail "$(T "certificate does NOT cover $HOST" "Zertifikat gilt NICHT fuer $HOST")" \
              "$(T 'Browsers show a name mismatch error. Names in the first certificate of the file:' 'Browser zeigen eine Namens-Fehlermeldung. Namen im ersten Zertifikat der Datei:') $(NAMES=$(one "$C1" -ext subjectAltName | sed -n '2,$s/^ *//p' | tr '\n' ' '); printf '%s' "${NAMES:-$(T '(none)' '(keine)')}")" \
              "$(T 'get a certificate for this name' 'Zertifikat fuer diesen Namen beschaffen')"; fi
          elif [ "$HAS_SAN" = 0 ]; then
            warn "$(T 'certificate has no subjectAltName' 'Zertifikat hat keinen subjectAltName')" \
              "$(T 'Current browsers refuse a certificate without subjectAltName (ERR_CERT_COMMON_NAME_INVALID), also a self-signed one.' 'Aktuelle Browser lehnen ein Zertifikat ohne subjectAltName ab (ERR_CERT_COMMON_NAME_INVALID), auch ein selbst signiertes.') $(DOC install tls-certificate)" "$NEWCERT"
          fi
          # chain: server certificate first, then each issuer
          if [ "$NC" -ge 2 ]; then
            BAD=0; i=1
            while [ "$i" -lt "$NC" ]; do
              ci=$(nth_cert "$i"); cn=$(nth_cert $((i + 1)))
              [ "$(one "$ci" -issuer -nameopt RFC2253 | name_of)" = "$(one "$cn" -subject -nameopt RFC2253 | name_of)" ] || BAD=1
              i=$((i + 1))
            done
            if [ "$BAD" = 0 ]; then ok "$(T "chain: $NC certificates in the right order (server certificate first)" "Kette: $NC Zertifikate in richtiger Reihenfolge (Serverzertifikat zuerst)")"
            else warn "$(T "chain: the $NC certificates are not in order" "Kette: die $NC Zertifikate stehen nicht in der richtigen Reihenfolge")" \
              "$(T 'nginx sends the file as it is. Order: server certificate first, then the intermediate certificate(s); each one issued the one before.' 'nginx sendet die Datei unveraendert. Reihenfolge: zuerst das Serverzertifikat, dann die Zwischenzertifikate; jedes hat das davor ausgestellt.')" \
              "$(T 'rebuild the file: cat server.pem intermediate.pem > fullchain.pem' 'Datei neu bauen: cat server.pem zwischen.pem > fullchain.pem')"; fi
          elif [ "$ISS" = "$SUBJ" ]; then
            warn "$(T 'self-signed certificate' 'selbst signiertes Zertifikat')" \
              "$(T 'Browsers warn about it, and some login providers refuse it. Fine for a test.' 'Browser warnen davor, und manche Login-Anbieter lehnen es ab. Fuer einen Test in Ordnung.')" ""
          else
            warn "$(T 'chain: the file holds only the server certificate' 'Kette: die Datei enthaelt nur das Serverzertifikat')" \
              "$(T "Issued by: $ISS. If your CA uses an intermediate certificate, append it after the server certificate, or some clients cannot verify the chain." "Ausgestellt von: $ISS. Falls die CA ein Zwischenzertifikat nutzt, dieses hinter das Serverzertifikat haengen, sonst koennen manche Clients die Kette nicht pruefen.")" \
              "cat server.pem intermediate.pem > fullchain.pem"
          fi
        fi
      fi
    fi
    if [ -n "$KEY" ]; then
      if [ ! -f "$KEY" ] || [ ! -r "$KEY" ]; then
        fail "$(T 'key file: not a readable file' 'Schluesseldatei: keine lesbare Datei'): $KEY" "$(T 'A private key is readable by root only (or by uid 101 with the OHIF image); run this script as root.' 'Einen privaten Schluessel darf nur root lesen (mit dem OHIF-Image auch uid 101); das Skript als root starten.')" "$SUDO_CMD"
      elif grep -q 'ENCRYPTED' "$KEY"; then
        fail "$(T 'private key is protected by a passphrase' 'privater Schluessel ist mit einer Passphrase geschuetzt')" \
          "$(T 'nginx cannot ask for it at start-up.' 'nginx kann beim Start nicht danach fragen.')" "openssl pkey -in $(q "$KEY") -out key-plain.pem   $(T '(then protect key-plain.pem with chmod 600)' '(key-plain.pem danach mit chmod 600 schuetzen)')"
      else
        PUBK=$(openssl pkey -in "$KEY" -pubout -passin pass: 2>/dev/null </dev/null)
        if [ -z "$PUBK" ]; then fail "$(T 'private key: cannot be parsed' 'privater Schluessel: nicht lesbar')" "$(T 'Expected an unencrypted PEM key.' 'Erwartet wird ein PEM-Schluessel ohne Passphrase.')" "openssl pkey -in $(q "$KEY") -noout"
        else
          ok "$(T 'private key: readable, no passphrase' 'privater Schluessel: lesbar, ohne Passphrase') $(openssl pkey -in "$KEY" -noout -text -passin pass: 2>/dev/null </dev/null | head -n 1 | sed 's/^Private-Key: //; s/^Private key: //; s/^RSA Private-Key: //')"
          key_permissions
        fi
      fi
    fi
    if [ -n "$PUBC" ] && [ -n "$PUBK" ]; then
      if [ "$PUBC" = "$PUBK" ]; then ok "$(T 'key matches the certificate' 'Schluessel passt zum Zertifikat')"
      else
        OTHER=0; i=2; while [ "$NC" -ge "$i" ]; do [ "$(one "$(nth_cert $i)" -pubkey)" = "$PUBK" ] && OTHER=$i; i=$((i + 1)); done
        if [ "$OTHER" != 0 ]; then
          fail "$(T "key does not match the first certificate, but certificate no. $OTHER of the file" "Schluessel passt nicht zum ersten Zertifikat, aber zu Zertifikat Nr. $OTHER der Datei")" \
            "$(T 'The server certificate must come first in the file, then the intermediates.' 'Das Serverzertifikat muss in der Datei zuerst stehen, danach die Zwischenzertifikate.')" \
            "$(T 'reorder the file: server certificate first' 'Datei umsortieren: Serverzertifikat zuerst')"
        else
          fail "$(T 'key does NOT match the certificate' 'Schluessel passt NICHT zum Zertifikat')" \
            "$(T 'nginx refuses to start with such a pair.' 'nginx startet mit so einem Paar nicht.')" \
            "$(T 'use the key that was created with the certificate request' 'den Schluessel nehmen, der zur Zertifikatsanfrage gehoert')"
        fi
      fi
    fi
  fi
fi

# ======================================================================================================================
# ---- --dir: the compose directory (layout /opt/ohif): placeholders, nginx tree, bind mounts ----
DEPTH=5   # DIR/nginx/pacs/login/server.conf is level 4

# scan_file FILE: lines "CHANGE-ME|line|word", "PLACEHOLDER|line|<word>" or "EXAMPLE|line|value", at most 20 per file. Env files
# print the variable name instead of the word (the value may be a secret); nothing else of the file is ever printed.
scan_file() {
  local js=0 envf=0
  case $1 in *.js) js=1 ;; *.env) envf=1 ;; esac
  awk -v js="$js" -v envf="$envf" '
    BEGIN { re = js ? "<[A-Za-z][A-Za-z0-9]*([-_][A-Za-z0-9]+)+>" : "<[A-Za-z][A-Za-z0-9._-]*( [A-Za-z0-9_-]+)*>"
            html = " a b i u p br hr em h1 h2 h3 h4 h5 h6 ul ol li td th tr div pre img svg nav code form head html body link meta span style title input label table select option script strong button iframe noscript " }
    function hit(kind, line, word,   i, w) {
      w = word
      if (envf && (i = index(line, "=")) > 1) { w = substr(line, 1, i - 1); gsub(/[ \t]/, "", w) }
      if (++n <= 20) print kind "|" NR "|" w }
    { if (index($0, "CHANGE-ME")) hit("CHANGE-ME", $0, "CHANGE-ME")
      code = $0; sub(/^[ \t]*(#|\/\/).*/, "", code); sub(/[ \t]+(#|\/\/).*/, "", code)
      rest = code; off = 0
      while (match(rest, re)) {
        w = substr(rest, RSTART, RLENGTH); pos = off + RSTART
        pre = pos > 1 ? substr(code, pos - 1, 1) : ""
        t = tolower(substr(w, 2, length(w) - 2)); split(t, a, " ")
        if (pre != "?" && !index(html, " " a[1] " ")) hit("PLACEHOLDER", $0, w)
        off += RSTART + RLENGTH - 1; rest = substr(rest, RSTART + RLENGTH) }
      if (index(code, "example.org")) hit("EXAMPLE", $0, "example.org")
      if (index(code, "00000000-0000-0000-0000-000000000000")) hit("EXAMPLE", $0, "00000000-0000-0000-0000-000000000000") }
    END { if (n > 20) print "MORE|0|" (n - 20) }' "$1" 2>/dev/null | tr -d '\r' | clean
}

# scan_dir: every compose/nginx/env/js file up to DEPTH levels below DIR; sets NBAD (files with a placeholder)
scan_dir() {
  local files f hits badl exl nf=0 nbad=0 nunr=0 unr="" m
  files=$(find -H "$DIR" -mindepth 1 -maxdepth "$DEPTH" \( -type d -name '.*' -prune \) -o \( -type f -size -1024k \( -name '*.conf' -o -name '*.inc' -o -name '*.yml' -o -name '*.yaml' -o -name '*.env' -o -name '.env' -o -name '*.js' \) -print \) 2>/dev/null | sort)
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ ! -r "$f" ]; then nunr=$((nunr + 1)); [ -n "$unr" ] || unr=$f; continue; fi
    nf=$((nf + 1))
    case $f in *.env) # secrets live here: other accounts must not read the file
      m=$(stat -c %a "$f" 2>/dev/null)
      if isnum "$m" && case $m in *[89]*) false ;; *) true ;; esac && [ $((8#$m & 63)) -ne 0 ]; then
        warn "$f: $(T "mode $m: other accounts of this host can read it" "Modus $m: andere Konten dieses Rechners koennen sie lesen")" \
          "$(T 'It holds secrets (client secret, cookie secret).' 'Die Datei enthaelt Geheimnisse (Client-Secret, Cookie-Secret).')" "chmod 600 $(q "$f")"
      fi ;;
    esac
    hits=$(scan_file "$f")
    [ -n "$hits" ] || continue
    badl=$(printf '%s\n' "$hits" | awk -F'|' -v w="$(T 'line' 'Zeile')" -v mo="$(T 'more' 'weitere')" '$1 == "CHANGE-ME" || $1 == "PLACEHOLDER" {printf "%s%s (%s %s)", s, $3, w, $2; s = ", "} $1 == "MORE" {printf "%s... %s %s", s, $3, mo; s = ", "}')
    exl=$(printf '%s\n' "$hits" | awk -F'|' -v w="$(T 'line' 'Zeile')" '$1 == "EXAMPLE" {printf "%s%s (%s %s)", s, $3, w, $2; s = ", "}')
    if [ -n "$badl" ]; then
      nbad=$((nbad + 1))
      fail "$f: $badl" "$(T 'A placeholder is still there: this value was never filled in (CHANGE-ME marks every value you must change; delete the marker comment once the value is set).' 'Ein Platzhalter steht noch drin: dieser Wert wurde nie eingetragen (CHANGE-ME markiert jeden Wert, der geaendert werden muss; den Markierungs-Kommentar nach dem Eintragen loeschen).')" \
        "grep -noE 'CHANGE-ME|<[A-Za-z][A-Za-z0-9 ._-]*>' $(q "$f")"
    fi
    if [ -n "$exl" ]; then
      warn "$f: $(T 'example value(s) still there:' 'Beispielwert(e) noch drin:') $exl" \
        "$(T 'Probably a copied example value that was not replaced with your real name or id.' 'Vermutlich ein kopierter Beispielwert, der nicht durch den echten Namen oder die echte ID ersetzt wurde.')" "grep -n 'example.org\|00000000-0000' $(q "$f")"
    fi
  done < <(printf '%s\n' "$files")
  if [ "$nunr" -gt 0 ]; then
    warn "$DIR: $(T "$nunr file(s) not readable (for example $unr), not checked" "$nunr Datei(en) nicht lesbar (zum Beispiel $unr), nicht geprueft")" "$(T 'Run this script as root.' 'Das Skript als root starten.')" "$SUDO_CMD"
  fi
  if [ "$nf" = 0 ]; then
    [ "$nunr" -gt 0 ] || warn "$DIR: $(T "no nginx, compose, env or js files found (looked $DEPTH levels deep)" "keine nginx-, compose-, env- oder js-Dateien gefunden ($DEPTH Ebenen tief gesucht)")" \
      "$(T 'Wrong directory? The layout is /opt/ohif with docker-compose.yml, nginx/, tls/, htpasswd/, ohif-auth.env, app-config.js.' 'Falsches Verzeichnis? Der Aufbau ist /opt/ohif mit docker-compose.yml, nginx/, tls/, htpasswd/, ohif-auth.env, app-config.js.')" "ls -la $(q "$DIR")"
  elif [ "$nbad" = 0 ]; then ok "$DIR: $(T "no CHANGE-ME and no <placeholder> left in $nf file(s)" "kein CHANGE-ME und kein <Platzhalter> mehr in $nf Datei(en)")"; fi
}

# check_tree: the nginx tree (DIR/nginx, or DIR itself): every file that pacs.conf and its pieces include must exist, or nginx
# does not start ("[emerg] open() ... failed")
check_tree() {
  local root="" p rel miss="" n=0 f
  if [ -f "$DIR/nginx/pacs.conf" ]; then root=$DIR/nginx; elif [ -f "$DIR/pacs.conf" ]; then root=$DIR; fi
  if [ -z "$root" ]; then
    for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
      [ ! -r "$DIR/$f" ] || { warn "$DIR: $(T 'no nginx tree found (nginx/pacs.conf)' 'kein nginx-Ordner gefunden (nginx/pacs.conf)')" \
        "$(T 'The compose file mounts the folder nginx as /etc/nginx/conf.d; without it nginx has no configuration.' 'Die Compose-Datei haengt den Ordner nginx als /etc/nginx/conf.d ein; ohne ihn hat nginx keine Konfiguration.')" \
        "$(T 'build it as in deploy/nginx/README.md (copy commands), see docs/install.md' 'ihn wie in deploy/nginx/README.md (Kopierbefehle) bauen, siehe docs/install.de.md')"; return 0; }
    done
    return 0
  fi
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    n=$((n + 1)); rel=${p#/etc/nginx/conf.d/}
    [ -e "$root/$rel" ] || miss="$miss $rel"
  done < <(find -H "$root" -type f -name '*.conf' 2>/dev/null | while IFS= read -r f; do sed -n 's/^[[:space:]]*include[[:space:]][[:space:]]*\(\/etc\/nginx\/conf\.d\/[^;[:space:]]*\)[[:space:]]*;.*/\1/p' "$f"; done | grep -v '[*?[]' | sort -u)
  if [ -n "$miss" ]; then
    fail "$(T 'nginx tree' 'nginx-Ordner') $root: $(T 'files missing:' 'Dateien fehlen:')$miss" \
      "$(T 'pacs.conf includes these files; without them nginx does not start ([emerg] open() failed). A step of the copy commands (login, viewer, listener) was skipped.' 'pacs.conf bindet diese Dateien ein; ohne sie startet nginx nicht ([emerg] open() failed). Ein Schritt der Kopierbefehle (Login, Viewer, Listener) wurde uebersprungen.')" \
      "$(T 'copy the missing pieces as in deploy/nginx/README.md (copy commands), see docs/install.md' 'die fehlenden Teile wie in deploy/nginx/README.md (Kopierbefehle) kopieren, siehe docs/install.de.md')"
  else ok "$(T 'nginx tree' 'nginx-Ordner') $root: $(T "all $n included files exist" "alle $n eingebundenen Dateien sind da")"; fi
}

# mount_fix DESTINATION SOURCE: the command that makes a missing bind-mount source right
mount_fix() {
  case $1 in
    /etc/nginx/tls) echo "mkdir -p $(q "$2") && cp server.crt server.key $(q "$2")/   # $(DOC install tls-certificate)" ;;
    /etc/nginx/htpasswd) echo "bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh admin NAME --dir $(q "$DIR")" ;;
    /etc/nginx/conf.d) T 'build the nginx tree: deploy/nginx/README.md (copy commands)' 'nginx-Ordner bauen: deploy/nginx/README.md (Kopierbefehle)'; echo ;;
    /usr/share/nginx/html/app-config.js) echo "cp /opt/pacs-admin/deploy/app-config.js.example $(q "$2")   # $(DOC install viewer-config)" ;;
    /srv/pacs-admin/admin/config.js) echo "cp /opt/pacs-admin/web/admin/config.js $(q "$2")" ;;
    /run/pacs-admin) echo "systemctl enable --now pacs-verwaltung   # $(DOC install helper-service)" ;;
    *) echo "mkdir -p $(q "$2")" ;;
  esac
}

# access101 PATH: what uid 101 (the nginx user in the nginx and OHIF images) may do with PATH, judged from owner, group and mode
# alone: a number, 4 = read, 1 = enter a folder; prints nothing when it cannot tell
access101() {
  local st mode uid gid m a
  st=$(stat -c '%a %u %g' "$1" 2>/dev/null) || return 0
  mode=${st%% *}; st=${st#* }; uid=${st%% *}; gid=${st#* }
  isnum "$mode" && isnum "$uid" && isnum "$gid" || return 0
  case $mode in *[89]*) return 0 ;; esac
  m=$((8#$mode)); a=$((m & 7))
  [ "$gid" != 101 ] || a=$((a | ((m >> 3) & 7)))
  [ "$uid" != 101 ] || a=$((a | ((m >> 6) & 7)))
  printf '%s' "$a"
}
# unreadable_for_101 SOURCE: sets UN_N (how many entries below SOURCE, a folder or a file, uid 101 cannot read; folders: cannot enter)
# and UN_FIRST (the first one); a file named server.key is left out, the key has its own rules
UN_N=0; UN_FIRST=""
unreadable_for_101() {
  local f a
  UN_N=0; UN_FIRST=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case ${f##*/} in server.key) continue ;; esac
    a=$(access101 "$f"); [ -n "$a" ] || continue
    if [ -d "$f" ]; then [ $((a & 5)) -eq 5 ] && continue; else [ $((a & 4)) -ne 0 ] && continue; fi
    UN_N=$((UN_N + 1)); [ -n "$UN_FIRST" ] || UN_FIRST=$f
  done < <(find -H "$1" \( -type f -o -type d \) 2>/dev/null)
}
# check_101 CF SRC DST ABS: the nginx user (uid 101) must be able to read what is mounted. Files made under a strict umask (027, 077)
# belong to root alone, and nginx then does not start or answers with an error. Returns 1 when it reported something.
check_101() {
  local who fix
  unreadable_for_101 "$4"
  [ "$UN_N" -gt 0 ] || return 0
  case $3 in
    /etc/nginx/tls) fix="chmod 755 $(q "$4") && chmod 644 $(q "$4")/server.crt" ;;
    *) fix="chmod -R o+rX $(q "$4")" ;;
  esac
  case $3 in
    /etc/nginx/conf.d|/etc/nginx/tls) who=$(T 'In the OHIF image the nginx master process runs as uid 101 and reads this when it starts.' 'Im OHIF-Image laeuft der nginx-Hauptprozess als uid 101 und liest das beim Start.') ;;
    *) who=$(T 'The nginx worker processes (uid 101 in the nginx and OHIF images) read this when a page is requested.' 'Die nginx-Worker-Prozesse (uid 101 im nginx- und im OHIF-Image) lesen das, wenn eine Seite angefordert wird.') ;;
  esac
  fail "$1: $(T "mount $2 -> $3: the nginx user (uid 101) cannot read $UN_N of its files or folders, for example $UN_FIRST" "Einhaengen $2 -> $3: der nginx-Benutzer (uid 101) kann $UN_N seiner Dateien oder Ordner nicht lesen, zum Beispiel $UN_FIRST")" \
    "$who $(T 'Files made under a strict umask (027 or 077) belong to root alone: the container does not start, or the page answers with an error.' 'Dateien, die unter einer strengen umask (027 oder 077) entstanden sind, gehoeren nur root: der Container startet nicht, oder die Seite antwortet mit einem Fehler.')" "$fix"
  return 1
}

# check_htpasswd FOLDER: the lists users and admins are read by the nginx WORKERS (uid 101 in the nginx and OHIF images) at every
# request that carries a password. A file that uid 101 cannot read makes each of them fail with 500. Returns 1 when it reported something.
check_htpasswd() {
  local x f st mode uid gid m un gn r101 qf rc=0
  for x in users admins; do
    f=$1/$x; st=$(stat -c '%a %u %g' "$f" 2>/dev/null) || continue
    mode=${st%% *}; st=${st#* }; uid=${st%% *}; gid=${st#* }
    if ! { isnum "$mode" && isnum "$uid" && isnum "$gid"; }; then continue; fi
    case $mode in *[89]*) continue ;; esac
    m=$((8#$mode)); r101=0
    [ $((m & 4)) -eq 0 ] || r101=1
    [ "$uid" != 101 ] || [ $((m & 256)) -eq 0 ] || r101=1
    [ "$gid" != 101 ] || [ $((m & 32)) -eq 0 ] || r101=1
    un=$uid; [ "$uid" != 0 ] || un=root; gn=$gid; [ "$gid" != 0 ] || gn=root; qf=$(q "$f")
    if [ "$r101" = 0 ]; then
      rc=1; fail "$f: $(T "owner $un:$gn, mode $mode: the nginx worker (uid 101) cannot read it" "Besitzer $un:$gn, Modus $mode: der nginx-Worker (uid 101) kann sie nicht lesen")" \
        "$(T 'nginx reads the list at every request that carries a password; with this owner and mode each of them is answered with 500.' 'nginx liest die Liste bei jeder Anfrage mit Passwort; mit diesem Besitzer und Modus endet jede davon mit 500.') $(DOC login login-basic)" \
        "chown 101 $qf && chmod 600 $qf   $(T '(or run pacs-adduser.sh as root again)' '(oder pacs-adduser.sh noch einmal als root starten)')"
    elif [ $((m & 4)) -ne 0 ]; then
      rc=1; warn "$f: $(T "mode $mode: every account of this host can read the password hashes" "Modus $mode: jedes Konto dieses Rechners kann die Passwort-Hashes lesen")" \
        "$(T 'Only the nginx worker (uid 101) needs access.' 'Nur der nginx-Worker (uid 101) braucht Zugriff.') $(DOC login login-basic)" "chown 101 $qf && chmod 600 $qf"
    fi
  done
  return "$rc"
}

# check_mounts: bind mounts of the compose file. Docker creates a missing source as an empty directory owned by root, which
# silently breaks files (app-config.js) and empty folders (tls, htpasswd) alike.
check_mounts() {
  local cf src dst abs x n=0 bad=0 missing="" NGX_KIND
  NGX_KIND=$(nginx_kind)
  for cf in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    [ -r "$DIR/$cf" ] || continue
    while IFS='|' read -r src dst; do
      [ -n "$src" ] || continue
      case $src in *'$'*) continue ;; /*) abs=$src ;; ./*) abs=$DIR/${src#./} ;; *) abs=$DIR/$src ;; esac
      n=$((n + 1))
      if [ ! -e "$abs" ]; then
        bad=1; warn "$cf: $(T "mount source $src does not exist (for $dst)" "Einhaenge-Quelle $src gibt es nicht (fuer $dst)")" \
          "$(T 'docker compose would create an empty directory with that name, owned by root; the service behind the mount then does not work.' 'docker compose legt dann ein leeres Verzeichnis dieses Namens an (Besitzer root); der Dienst hinter dem Einhaengen funktioniert dann nicht.')" "$(mount_fix "$dst" "$abs")"
        continue
      fi
      missing=""
      case $dst in
        /etc/nginx/tls) for x in server.crt server.key; do [ -f "$abs/$x" ] || missing="$missing $x"; done ;;
        /etc/nginx/htpasswd) for x in users admins; do [ -f "$abs/$x" ] || missing="$missing $x"; done ;;
        /etc/nginx/conf.d) [ -f "$abs/pacs.conf" ] || missing=" pacs.conf" ;;
        /usr/share/nginx/html/app-config.js|/srv/pacs-admin/admin/config.js) [ -f "$abs" ] || missing=" $src ($(T 'is not a file' 'ist keine Datei'))" ;;
      esac
      if [ -n "$missing" ]; then
        bad=1; fail "$cf: $(T "mount $src -> $dst is incomplete, missing:" "Einhaengen $src -> $dst unvollstaendig, es fehlt:")$missing" \
          "$(T 'The container would start without it or fail at once; every request is answered with an error.' 'Der Container startet ohne das nicht oder scheitert sofort; jede Anfrage endet mit einem Fehler.')" "$(mount_fix "$dst" "$abs")"
      elif [ "$dst" = /etc/nginx/htpasswd ]; then
        check_htpasswd "$abs" || bad=1
      else
        case $dst in
          /srv/pacs-admin/admin|/srv/pacs-admin/status|/usr/share/nginx/html/app-config.js|/srv/pacs-admin/admin/config.js) check_101 "$cf" "$src" "$dst" "$abs" || bad=1 ;;
          /etc/nginx/conf.d|/etc/nginx/tls) [ "$NGX_KIND" != nonroot ] || check_101 "$cf" "$src" "$dst" "$abs" || bad=1 ;;
        esac
        # --dir alone: the key in tls/ gets the same check as with --key
        if [ "$dst" = /etc/nginx/tls ] && [ -z "$KEY" ] && [ -f "$abs/server.key" ]; then KEY=$abs/server.key; key_permissions; KEY=""; fi
      fi
    done < <(awk '
      /^[ \t]*-[ \t]+/ {
        s = $0; sub(/^[ \t]*-[ \t]+/, "", s); gsub(/["\047]/, "", s); sub(/[ \t]+#.*$/, "", s); sub(/[ \t]+$/, "", s)
        n = split(s, p, ":")
        if (n >= 2 && (substr(p[1], 1, 1) == "." || substr(p[1], 1, 1) == "/") && substr(p[2], 1, 1) == "/") print p[1] "|" p[2] }' "$DIR/$cf" 2>/dev/null)
  done
  if [ "$n" -gt 0 ] && [ "$bad" = 0 ]; then ok "$(T "compose bind mounts: all $n sources exist and look complete" "Compose-Einhaenge: alle $n Quellen sind da und sehen vollstaendig aus")"; fi
}

# check_envfiles: the env_file entries of the compose file must exist (compose refuses to start otherwise); for oauth2-proxy the file
# must carry its three values. Only names are printed, never a value.
check_envfiles() {
  local cf p abs x v miss empt oa n=0 bad=0
  for cf in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    [ -r "$DIR/$cf" ] || continue
    oa=0; grep -q 'oauth2-proxy' "$DIR/$cf" 2>/dev/null && oa=1
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      case $p in *'$'*) continue ;; /*) abs=$p ;; ./*) abs=$DIR/${p#./} ;; *) abs=$DIR/$p ;; esac
      n=$((n + 1))
      if [ ! -f "$abs" ]; then
        bad=1; fail "$cf: $(T "env_file $p does not exist (or is a folder)" "env_file $p gibt es nicht (oder es ist ein Ordner)")" \
          "$(T 'docker compose refuses to start without it. The compose file says at its top what the file holds.' 'docker compose startet ohne sie nicht. Die Compose-Datei nennt am Anfang, was in der Datei steht.') $(DOC login login-oauth2)" "ls -ld $(q "$abs")"
        continue
      fi
      [ -r "$abs" ] || continue   # not readable: scan_dir said so already
      [ "$oa" = 1 ] || continue
      miss=""; empt=""
      for x in OAUTH2_PROXY_CLIENT_ID OAUTH2_PROXY_CLIENT_SECRET OAUTH2_PROXY_COOKIE_SECRET; do
        if grep -q "^$x=" "$abs"; then
          v=$(grep "^$x=" "$abs" | tail -n 1 | cut -d= -f2- | tr -d '\r \t' | sed "s/^'\\(.*\\)'\$/\\1/; s/^\"\\(.*\\)\"\$/\\1/")
          [ -n "$v" ] || empt="$empt $x"
        else miss="$miss $x"; fi
      done
      if [ -n "$miss$empt" ]; then
        bad=1; fail "$p: ${miss:+$(T 'missing:' 'fehlt:')$miss}${miss:+${empt:+; }}${empt:+$(T 'empty:' 'leer:')$empt}" \
          "$(T 'oauth2-proxy does not start without its client ID, client secret and cookie secret.' 'oauth2-proxy startet ohne Client-ID, Client-Secret und Cookie-Secret nicht.') $(DOC login login-oauth2)" \
          "$(T 'one NAME=value line each, no spaces around =; cookie secret:' 'je eine Zeile NAME=wert, keine Leerzeichen um =; Cookie-Secret:') python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())'"
      fi
    done < <(awk '
      /^[ \t]*env_file:[ \t]*[^ \t#]/ {
        s = $0; sub(/^[ \t]*env_file:[ \t]*/, "", s); sub(/[ \t]+#.*$/, "", s); gsub(/["\047]/, "", s); gsub(/\[/, "", s); gsub(/\]/, "", s); inl = 0
        k = split(s, a, ","); for (i = 1; i <= k; i++) { t = a[i]; gsub(/^[ \t]+|[ \t]+$/, "", t); if (t != "") print t }
        next }
      /^[ \t]*env_file:[ \t]*(#.*)?$/ { inl = 1; next }
      inl && /^[ \t]*-[ \t]+/ { s = $0; sub(/^[ \t]*-[ \t]+/, "", s); sub(/[ \t]+#.*$/, "", s); gsub(/["\047]/, "", s); sub(/[ \t]+$/, "", s); print s; next }
      inl && !/^[ \t]*(#|$)/ { inl = 0 }' "$DIR/$cf" 2>/dev/null)
  done
  if [ "$n" -gt 0 ] && [ "$bad" = 0 ]; then ok "$(T "compose env_file: all $n file(s) exist" "Compose-env_file: alle $n Datei(en) sind da")$([ "$oa" != 1 ] || T ', the three oauth2-proxy values are set' ', die drei oauth2-proxy-Werte sind gesetzt')"; fi
}

# check_dir: everything about DIR
check_dir() {
  local nodir nunr first
  if [ "$DIR" = / ]; then
    fail "--dir /: $(T 'this is not a compose directory' 'das ist kein Compose-Verzeichnis')" "$(T 'Name the folder of your install (layout: /opt/ohif).' 'Den Ordner der Installation nennen (Aufbau: /opt/ohif).')" "bash $(q "$0") --dir /opt/ohif"
    return 0
  fi
  if [ ! -d "$DIR" ]; then fail "$(T 'directory not found' 'Verzeichnis nicht gefunden'): $DIR" "" "ls -ld $(q "$DIR")"; return 0; fi
  if [ ! -r "$DIR" ] || [ ! -x "$DIR" ]; then
    warn "$DIR: $(T 'not readable, not checked' 'nicht lesbar, nicht geprueft')" "$(T 'Run this script as root.' 'Das Skript als root starten.')" "$SUDO_CMD"; return 0
  fi
  nodir=$(find -H "$DIR" -mindepth 1 -maxdepth "$DEPTH" \( -type d -name '.*' -prune \) -o \( -type d -print \) 2>/dev/null | while IFS= read -r f; do [ -r "$f" ] && [ -x "$f" ] || printf '%s\n' "$f"; done)
  if [ -n "$nodir" ]; then
    nunr=$(printf '%s\n' "$nodir" | wc -l | tr -d ' '); first=$(printf '%s\n' "$nodir" | head -n 1)
    warn "$DIR: $(T "$nunr folder(s) not readable (for example $first), their files are not checked" "$nunr Ordner nicht lesbar (zum Beispiel $first), ihre Dateien werden nicht geprueft")" \
      "$(T 'Run this script as root.' 'Das Skript als root starten.')" "$SUDO_CMD"
  fi
  scan_dir
  check_tree
  check_mounts
  check_envfiles
}

if [ -n "$DIR" ] || [ -e "$ENVF" ]; then
  section "$(T 'Configuration files' 'Konfigurationsdateien')"

  if [ -e "$ENVF" ]; then
    if [ ! -r "$ENVF" ]; then
      warn "$ENVF: $(T 'not readable, not checked' 'nicht lesbar, nicht geprueft')" "$(T 'Only root can read it.' 'Nur root kann sie lesen.')" "$SUDO_CMD"
    else
      ERR=""
      grep -q "$(printf '\r')" "$ENVF" && ERR="$ERR $(T 'Windows line endings (CRLF);' 'Windows-Zeilenenden (CRLF);')"
      sh -n "$ENVF" >/dev/null 2>&1 || ERR="$ERR $(T 'shell syntax error;' 'Shell-Syntaxfehler;')"
      PROBL=$(tr -d '\r' < "$ENVF" | awk '
        /^[ \t]*(#|$)/ {next}
        /^[A-Z_][A-Za-z0-9_]*=/ {
          v = substr($0, index($0, "=") + 1)
          if (v !~ /^["\047]/ && v ~ /[ \t]/) print NR ": unquoted value with a space or a trailing comment (quote it)"
          if ($0 ~ /CHANGE-ME/) print NR ": CHANGE-ME left in the value"
          next }
        { print NR ": not NAME=value (export? spaces around =?)" }')
      if [ -z "$ERR" ] && [ -z "$PROBL" ]; then ok "$ENVF: $(T 'syntax ok (shell and systemd read it the same way)' 'Syntax ok (Shell und systemd lesen sie gleich)')"
      else
        fail "$ENVF: $(T 'problems' 'Probleme')${ERR:+:$ERR}" \
          "$(T 'The file is read by the shell (cron, scripts) and by systemd, which disagree on comments, spaces and CRLF. One NAME=value per line, no export, quote values with spaces.' 'Die Datei lesen die Shell (Cron, Skripte) und systemd, die bei Kommentaren, Leerzeichen und CRLF verschieden urteilen. Eine Zeile NAME=wert, kein export, Werte mit Leerzeichen in Anfuehrungszeichen.')${PROBL:+ $(T 'Lines:' 'Zeilen:') $(printf '%s' "$PROBL" | tr '\n' ';')}" \
          "sed -i 's/\\r\$//' $ENVF; sh -n $ENVF   $(T '(then correct the lines named above by hand)' '(dann die oben genannten Zeilen von Hand korrigieren)')"
      fi
    fi
  fi

  [ -z "$DIR" ] || check_dir
fi

# ======================================================================================================================
printf '\n%s== %s ==%s\n' "$C_B" "$(T 'Summary' 'Zusammenfassung')" "$C_0"
if [ "$N_FAIL" -gt 0 ]; then RES=2; RT=$(T 'NOT READY: fix the [FAIL] lines first' 'NICHT BEREIT: zuerst die [FAIL]-Zeilen beheben')
elif [ "$N_WARN" -gt 0 ]; then RES=1; RT=$(T 'READY, with warnings: read the [WARN] lines' 'BEREIT, mit Warnungen: die [WARN]-Zeilen lesen')
else RES=0; RT=$(T 'READY: all checks passed' 'BEREIT: alle Pruefungen bestanden'); fi
printf '%s: %s ok, %s %s, %s %s\n' "$(T 'Result' 'Ergebnis')" "$N_OK" "$N_WARN" "$(T 'warning(s)' 'Warnung(en)')" "$N_FAIL" "$(T 'failure(s)' 'Fehler')"
printf '%s\n' "$RT"
if [ -n "$PKGS" ]; then
  printf '\n%s\n' "$(T 'Missing packages in one go (a package that does not exist is reported and skipped):' 'Fehlende Pakete auf einmal (ein Paket, das es nicht gibt, wird gemeldet und uebersprungen):')"
  # shellcheck disable=SC2016
  printf '  for p in%s; do apt-get install -y "$p" || echo "NOT INSTALLED: $p"; done\n' "$PKGS"
fi

printf '\n%s\n' "$(T 'My values (copy them where the install guide says "my values"; "(not found)" means: look it up by hand)' 'Meine Werte (dort eintragen, wo die Anleitung "meine Werte" sagt; "(nicht gefunden)" heisst: von Hand nachsehen)')"
NF_TXT=$(T '(not found)' '(nicht gefunden)')
kv() { printf '  %-34s %-26s %s\n' "$(oneline "$1")" "$(oneline "$2")" "$(oneline "${3:-$NF_TXT}")"; }   # value last: a long path cannot break the columns
kv "$(T 'what' 'was')" "$(T 'goes into' 'kommt in')" "$(T 'value' 'Wert')"
kv "$(T 'compose project directory' 'Compose-Verzeichnis')" "PACS_DIR" "$V_DIR"
kv "$(T 'compose file(s)' 'Compose-Datei(en)')" "-" "$V_FILES"
kv "$(T 'Docker network of arc' 'Docker-Netzwerk von arc')" "$(T 'compose file: network' 'Compose-Datei: Netzwerk')" "$V_NET"
kv "$(T 'arc container' 'arc-Container')" "ARC_CONTAINER, nginx" "$V_ARC"
kv "$(T 'ldap container' 'ldap-Container')" "LDAP_CONTAINER" "$V_LDAP"
kv "$(T 'db container' 'db-Container')" "-" "$V_DB"
kv "$(T 'wildfly log directory (host)' 'wildfly-Log-Verzeichnis (Host)')" "ARC_LOG_DIR" "$V_LOG"
kv "$(T 'outside network interface' 'Netzwerkschnittstelle nach aussen')" "FW_INTERFACE" "$V_IFACE"
kv "$(T 'uid of nginx / sockets' 'uid von nginx / Sockets')" "PACS_SOCKET_UID" "$V_UID"
kv "$(T 'SQLCipher package' 'SQLCipher-Paket')" "apt-get install -y" "$V_SQL"
[ -z "$V_UIDNOTE" ] || printf '  %s\n' "$(oneline "$(T 'Note:' 'Hinweis:') $V_UIDNOTE")"

# lines still missing in /etc/default/pacs-admin: values that differ from what is configured now (FW_INTERFACE is
# suggested while it is empty: a fixed name is safer than the default-route lookup at boot)
ENVL=""
[ -z "$V_DIR" ] || [ "${V_DIR%/}" = "${EFF_DIR%/}" ] || ENVL="$ENVL  PACS_DIR=$(q "$V_DIR")
"
[ -z "$V_ARC" ] || [ "$V_ARC" = "$EFF_ARC" ] || ENVL="$ENVL  ARC_CONTAINER=$(q "$V_ARC")
"
[ -z "$V_LDAP" ] || [ "$V_LDAP" = "$EFF_LDAP" ] || ENVL="$ENVL  LDAP_CONTAINER=$(q "$V_LDAP")
"
[ -z "$V_LOG" ] || [ "${V_LOG%/}" = "${EFF_LOG%/}" ] || ENVL="$ENVL  ARC_LOG_DIR=$(q "$V_LOG")
"
[ -z "$V_IFACE" ] || [ -n "$EFF_IFACE" ] || ENVL="$ENVL  FW_INTERFACE=$(q "$V_IFACE")
"
printf '\n%s\n' "$(T "Lines still missing in $ENVF (your system differs from what is configured now; one per line, no spaces around =):" "Zeilen, die in $ENVF noch fehlen (das System weicht von der jetzigen Einstellung ab; eine je Zeile, keine Leerzeichen um =):")"
if [ -n "$ENVL" ]; then printf '%s' "$ENVL" | clean; else printf '  %s\n' "$(T '(none, the configuration matches this system)' '(keine, die Einstellungen passen zu diesem System)')"; fi

NOTCHK=""
[ -n "$HOST" ] || NOTCHK="$NOTCHK --host"
[ -n "$CERT" ] || NOTCHK="$NOTCHK --cert/--key"
[ -n "$DIR" ] || NOTCHK="$NOTCHK --dir"
[ -z "$NOTCHK" ] || printf '\n%s%s\n' "$(T 'Not checked (option not given):' 'Nicht geprueft (Option nicht angegeben):')" "$NOTCHK"
printf '%s\n' "$(T 'This script changed nothing. Run it again after every fix.' 'Dieses Skript hat nichts veraendert. Nach jeder Korrektur noch einmal starten.')"
exit "$RES"
