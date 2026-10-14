#!/usr/bin/env bash
# pacs-adduser.sh: add or change a login for the "basic" variant (nginx HTTP basic auth); needs only bash and openssl.
# Deutsch: docs/login.de.md#login-basic. Messages are German if the first non-empty of LC_ALL, LC_MESSAGES, LANG starts with de.
#
#   sudo bash pacs-adduser.sh <all|admin> <name> [--dir DIR] [--owner UID[:GID]] [--mode MODE] [--users FILE --admins FILE]
#
#   all     the account may use the viewer: its line goes into the list of ALL accounts
#   admin   the account may also use /admin/: the same line also goes into the list of ADMINS
#   name    letters, digits, . _ - (at most 32). The password is asked twice, hidden (min. 10 characters, at most 256 bytes), or read as one line
#           from stdin when stdin is not a terminal:  printf '%s\n' "$PW" | sudo bash pacs-adduser.sh admin anna
#           It is never taken from the command line (it would show up in "ps" and in the shell history).
#   --dir   folder of your compose file, default /opt/ohif. The two lists are DIR/htpasswd/users and DIR/htpasswd/admins
#           (the folder htpasswd is created, mode 755, when it is missing); the compose files mount that folder at
#           /etc/nginx/htpasswd. "--file" is an older name of this option.
#   --users, --admins   name both list files yourself (overrides --dir)
#   --owner owner of the files when run as root, default 101 = the nginx worker in the official nginx and OHIF images
#           (it reads the files at every request that carries a password; a root-only file makes each of them fail with 500).
#           nginx installed on the host (Debian):  --owner root:www-data --mode 640
#   --mode  file mode, 3 octal digits, default 600; group and others must not be able to write
#
# An existing account of the same name is replaced (also moved between the two lists). To remove an account, delete its
# line from both files. The files are overwritten in place (not replaced), so a bind mount of a single file keeps working.
# Runs started at the same moment wait for each other when flock (util-linux) is installed. Needs the folder to be writable:
# run it as root.
[ -n "${BASH_VERSION:-}" ] || { echo "pacs-adduser.sh: please run this script with bash:  bash $0" >&2; exit 1; }
set -eu
umask 077

LANGSEL=en
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in de*) LANGSEL=de ;; esac
T() { if [ "$LANGSEL" = de ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
# q VALUE: VALUE as one shell word (quoted only when it holds anything unusual)
q() { case $1 in ''|*[!A-Za-z0-9_./:@%+=,-]*) printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")" ;; *) printf '%s' "$1" ;; esac; }
die() { printf 'pacs-adduser: %s\n' "$1" >&2; exit 1; }
usage() {
  T 'Usage: sudo bash pacs-adduser.sh <all|admin> <name> [--dir DIR] [--owner UID[:GID]] [--mode MODE] [--users FILE --admins FILE]
  all = viewer only, admin = viewer and /admin/. name: letters, digits, . _ - (at most 32).
  --dir DIR        folder of your compose file (default /opt/ohif); lists: DIR/htpasswd/users and DIR/htpasswd/admins
  --users, --admins   name both list files yourself (overrides --dir)
  --owner, --mode  owner (default 101) and mode (default 600) of the files; host nginx on Debian: --owner root:www-data --mode 640
  The password is asked twice (hidden), or read as one line from stdin: at least 10 characters, at most 256 bytes. Run as
  root so the files get the right owner.
' 'Aufruf: sudo bash pacs-adduser.sh <all|admin> <name> [--dir VERZEICHNIS] [--owner UID[:GID]] [--mode MODUS] [--users DATEI --admins DATEI]
  all = nur Viewer, admin = Viewer und /admin/. name: Buchstaben, Ziffern, . _ - (hoechstens 32).
  --dir VERZEICHNIS   Ordner der Compose-Datei (Vorgabe /opt/ohif); Listen: VERZ/htpasswd/users und VERZ/htpasswd/admins
  --users, --admins   beide Listen-Dateien selbst nennen (gilt vor --dir)
  --owner, --mode     Besitzer (Vorgabe 101) und Modus (Vorgabe 600) der Dateien; nginx auf dem Host (Debian): --owner root:www-data --mode 640
  Das Passwort wird zweimal abgefragt (unsichtbar) oder als eine Zeile von stdin gelesen: mindestens 10 Zeichen, hoechstens
  256 Byte. Als root starten, damit die Dateien den richtigen Besitzer bekommen.
'
}
bad() { printf 'pacs-adduser: %s\n' "$1" >&2; usage >&2; exit 1; }

ORIG=""
for a in "$@"; do ORIG="$ORIG $(q "$a")"; done   # the arguments as typed (never a password), for the "run it again with sudo" hint
SUDO_CMD="sudo bash $(q "$0")$ORIG"

DIR=/opt/ohif; OWNER=101; MODE=600; ROLE=""; NAME=""; HT=""; HA=""
setopt() {   # setopt OPTION VALUE
  case $1 in --owner) OWNER=$2 ;; --mode) MODE=$2 ;; --users) HT=$2 ;; --admins) HA=$2 ;; *) DIR=$2 ;; esac
}
positional() {   # positional ARGUMENT: the role first, then the name
  if [ -z "$ROLE" ]; then ROLE=$1; elif [ -z "$NAME" ]; then NAME=$1; else bad "$(T 'too many arguments' 'zu viele Argumente')"; fi
}
while [ $# -gt 0 ]; do
  case $1 in
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;   # everything after it is a role or a name, even when it starts with a dash
    --dir|--file|--owner|--mode|--users|--admins)
      [ $# -ge 2 ] || bad "$(T "$1 needs a value" "$1 braucht einen Wert")"
      setopt "$1" "$2"; shift 2 ;;
    --dir=*|--file=*|--owner=*|--mode=*|--users=*|--admins=*) setopt "${1%%=*}" "${1#*=}"; shift ;;
    -*) bad "$(T "unknown option: $1" "unbekannte Option: $1")" ;;
    *) positional "$1"; shift ;;
  esac
done
while [ $# -gt 0 ]; do positional "$1"; shift; done
if [ -z "$ROLE" ] || [ -z "$NAME" ]; then usage >&2; exit 1; fi

case $ROLE in all|admin) ;; *) bad "$(T "role must be 'all' or 'admin', not '$ROLE'" "Rolle muss 'all' oder 'admin' sein, nicht '$ROLE'")" ;; esac
case $NAME in
  *:*) die "$(T "the name must not contain a colon (it separates name and password hash in the file): '$NAME'" "der Name darf keinen Doppelpunkt enthalten (er trennt Name und Passwort-Hash in der Datei): '$NAME'")" ;;
esac
case $NAME in
  *[!A-Za-z0-9._-]*|"") die "$(T "invalid name '$NAME': use letters, digits, . _ - only" "ungueltiger Name '$NAME': nur Buchstaben, Ziffern, . _ - erlaubt")" ;;
esac
[ "${#NAME}" -le 32 ] || die "$(T 'the name is longer than 32 characters' 'der Name ist laenger als 32 Zeichen')"
case $OWNER in -*|*[!A-Za-z0-9._:-]*|"") die "--owner: UID[:GID] $(T 'expected' 'erwartet')" ;; esac
case $MODE in
  [0-7][0-7][0-7]|0[0-7][0-7][0-7]) ;;
  *) die "--mode: $(T 'three octal digits like 600 expected (no setuid or sticky bit)' 'drei oktale Ziffern wie 600 erwartet (kein setuid- oder sticky-Bit)')" ;;
esac
M3=${MODE: -3}
case ${M3#?} in *[2367]*) die "--mode $MODE: $(T 'group or others could write the list of passwords; use 600, or 640 for nginx on the host' 'Gruppe oder andere duerften die Passwortliste schreiben; 600 nehmen, fuer nginx auf dem Host 640')" ;; esac
command -v openssl >/dev/null 2>&1 || die "$(T 'openssl not found' 'openssl nicht gefunden'): apt-get install -y openssl"

# ---- the two lists: explicit, or DIR/htpasswd/users and DIR/htpasswd/admins (the folder is made when it is missing) ----
MADE=""; PROBE=""
if [ -z "$HT" ] && [ -z "$HA" ]; then
  while case $DIR in ?*/) true ;; *) false ;; esac; do DIR=${DIR%/}; done   # --dir /opt/ohif/ is --dir /opt/ohif
  [ -d "$DIR" ] || die "$(T "directory $DIR does not exist (use --dir DIR)" "Verzeichnis $DIR gibt es nicht (--dir VERZEICHNIS angeben)")"
  HT=$DIR/htpasswd/users; HA=$DIR/htpasswd/admins
  if [ -e "$DIR/htpasswd" ] && [ ! -d "$DIR/htpasswd" ]; then
    die "$(T "$DIR/htpasswd is a file, but the compose files mount a folder htpasswd (with the files users and admins). Fix: mv $(q "$DIR/htpasswd") $(q "$DIR/htpasswd.old"), run this script again." "$DIR/htpasswd ist eine Datei, die Compose-Dateien haengen aber einen Ordner htpasswd ein (mit den Dateien users und admins). Abhilfe: mv $(q "$DIR/htpasswd") $(q "$DIR/htpasswd.old"), dieses Skript noch einmal starten.")"
  fi
  PROBE=$DIR/htpasswd; [ -d "$PROBE" ] || PROBE=$DIR
fi
if [ -z "$HT" ] || [ -z "$HA" ]; then die "$(T '--users and --admins must be given together' '--users und --admins nur zusammen angeben')"; fi
for f in "$HT" "$HA"; do
  if [ -L "$f" ] && [ ! -e "$f" ]; then   # writing through it would create a file somewhere else
    die "$(T "$f is a symbolic link to a file that does not exist: remove the link, or make its target" "$f ist ein symbolischer Link auf eine Datei, die es nicht gibt: den Link entfernen oder das Ziel anlegen")"
  fi
  if [ -d "$f" ]; then
    die "$(T "$f is a directory. Docker creates a directory when a file that is bind-mounted does not exist yet. Fix: rmdir $f, run this script again, then restart the compose project (docker compose up -d)." "$f ist ein Verzeichnis. Docker legt ein Verzeichnis an, wenn eine eingehaengte Datei noch nicht existiert. Abhilfe: rmdir $f, dieses Skript noch einmal starten, dann das Compose-Projekt neu starten (docker compose up -d).")"
  fi
  if [ -e "$f" ]; then [ -w "$f" ] || die "$(T "cannot write $f: run this script as root:  $SUDO_CMD" "kein Schreibrecht auf $f: Skript als root starten:  $SUDO_CMD")"
  elif [ -n "$PROBE" ]; then [ -w "$PROBE" ] || die "$(T "cannot create files in $PROBE: run this script as root:  $SUDO_CMD" "kann in $PROBE keine Dateien anlegen: Skript als root starten:  $SUDO_CMD")"
  else [ -w "$(dirname -- "$f")" ] || die "$(T "cannot create $f: directory missing or not writable (run as root, or create the directory first)" "kann $f nicht anlegen: Verzeichnis fehlt oder ist nicht beschreibbar (als root starten oder das Verzeichnis zuerst anlegen)")"; fi
done

# can new files get this owner and mode? A throw-away file shows it now, before anything is written (a typo in --owner
# would otherwise leave lists that nginx cannot read)
probe_dir() {   # probe_dir FOLDER
  local p
  p=$(mktemp "$1/.pacs-adduser.XXXXXX") || return 1
  if [ "$(id -u)" = 0 ]; then chown -- "$OWNER" "$p" || { rm -f "$p"; return 1; }; fi
  chmod "$MODE" "$p" || { rm -f "$p"; return 1; }
  rm -f "$p"
}
if [ -n "$PROBE" ]; then probe_dir "$PROBE" || die "$(T "cannot give new files in $PROBE the owner $OWNER and mode $MODE (see the message above); nothing was changed" "neue Dateien in $PROBE lassen sich nicht auf Besitzer $OWNER und Modus $MODE setzen (siehe die Meldung oben); nichts wurde geaendert")"
else
  for f in "$HT" "$HA"; do
    probe_dir "$(dirname -- "$f")" || die "$(T "cannot give new files in $(dirname -- "$f") the owner $OWNER and mode $MODE (see the message above); nothing was changed" "neue Dateien in $(dirname -- "$f") lassen sich nicht auf Besitzer $OWNER und Modus $MODE setzen (siehe die Meldung oben); nichts wurde geaendert")"
  done
fi

# ---- password: hidden prompt twice, or one line from stdin when it is not a terminal ----
if [ -t 0 ]; then
  printf '%s' "$(T "Password for $NAME (min. 10 characters, hidden): " "Passwort fuer $NAME (mindestens 10 Zeichen, unsichtbar): ")" >&2
  IFS= read -rs PW || { printf '\n' >&2; die "$(T 'no password entered, nothing changed' 'kein Passwort eingegeben, nichts geaendert')"; }
  printf '\n' >&2
  printf '%s' "$(T 'Repeat the password: ' 'Passwort wiederholen: ')" >&2
  IFS= read -rs PW2 || { printf '\n' >&2; die "$(T 'no password entered, nothing changed' 'kein Passwort eingegeben, nichts geaendert')"; }
  printf '\n' >&2
  [ "$PW" = "$PW2" ] || die "$(T 'the two passwords differ, nothing changed' 'die beiden Passwoerter sind verschieden, nichts geaendert')"
else
  PW=""; IFS= read -r PW || [ -n "$PW" ] || die "$(T 'no password on stdin' 'kein Passwort auf stdin')"
  PW=${PW%$'\r'}
fi
[ "${#PW}" -ge 10 ] || die "$(T 'the password is shorter than 10 characters, nothing changed' 'das Passwort ist kuerzer als 10 Zeichen, nichts geaendert')"
# openssl hashes only the first 256 bytes of a password: with more, nginx would refuse the right password, and nothing says so
PWBYTES=$(printf '%s' "$PW" | wc -c | tr -d ' ')
[ "$PWBYTES" -le 256 ] || die "$(T "the password is $PWBYTES bytes long: at most 256 bytes work (the hash covers only the first 256, so nginx would refuse the right password). Nothing changed." "das Passwort ist $PWBYTES Byte lang: hoechstens 256 Byte funktionieren (der Hash umfasst nur die ersten 256, nginx wuerde das richtige Passwort ablehnen). Nichts geaendert.")"

# nginx checks the hash at EVERY request, so it must stay cheap: sha512-crypt with the default rounds (nginx hands the hash to the C library,
# glibc reads it; musl is untested). Not bcrypt ($2y$: not every C library reads it), not a high round count (it slows down every request).
# The password goes through stdin, never through the command line.
HTYPE=sha512-crypt
HASH=$(printf '%s\n' "$PW" | openssl passwd -6 -stdin 2>/dev/null) || HASH=""
# shellcheck disable=SC2016
case $HASH in
  '$6$'*) ;;
  *)  # openssl older than 1.1.1 has no -6: apr1 (Apache MD5) is the next best type that nginx reads itself
      HTYPE=apr1
      printf 'pacs-adduser: %s\n' "$(T 'WARNING: this openssl cannot make sha512-crypt hashes (it needs 1.1.1 or newer). Using apr1, the weaker hash type. Update openssl and set the password again.' 'WARNUNG: dieses openssl kann keine sha512-crypt-Hashes (ab 1.1.1). Es wird apr1 benutzt, der schwaechere Hash-Typ. openssl aktualisieren und das Passwort erneut setzen.')" >&2
      HASH=$(printf '%s\n' "$PW" | openssl passwd -apr1 -stdin) || die "$(T 'openssl could not hash the password' 'openssl konnte das Passwort nicht hashen')"
      case $HASH in '$apr1$'*) ;; *) die "$(T 'openssl did not return an apr1 hash' 'openssl lieferte keinen apr1-Hash')" ;; esac ;;
esac
PW=""; PW2=""

TMP=$(mktemp) || die "$(T 'cannot create a temporary file' 'kann keine temporaere Datei anlegen')"
trap 'rm -f "$TMP"' EXIT

# runs started at the same moment take turns (without flock they cannot, and one of two accounts may get lost)
if [ -n "$PROBE" ]; then LOCKD=$DIR; else LOCKD=$(dirname -- "$HT"); fi   # always the same folder, also while htpasswd is made
if command -v flock >/dev/null 2>&1; then
  if [ -d "$LOCKD" ] && [ -r "$LOCKD" ]; then
    exec 9< "$LOCKD"
    flock -w 30 9 || die "$(T 'another run of this script has held the lock for 30 seconds; try again' 'ein anderer Lauf dieses Skripts haelt die Sperre seit 30 Sekunden; spaeter noch einmal versuchen')"
  fi
fi
if [ -n "$PROBE" ] && [ ! -d "$DIR/htpasswd" ]; then
  # mode 755: the folder is mounted into the container, where the nginx worker (uid 101) must be able to enter it
  mkdir -m 755 "$DIR/htpasswd" || die "$(T "cannot create $DIR/htpasswd (run as root, or create the folder first)" "kann $DIR/htpasswd nicht anlegen (als root starten oder den Ordner zuerst anlegen)")"
  MADE=$DIR/htpasswd
fi

# set_line FILE 1|0: drop every line of NAME, then add the new one when $2 = 1. Sets RES to added|replaced|removed|none.
# The comparison is by string ("007" is not "7"); lines that are not accounts (comments) are kept as they are. Every step is
# checked on its own: "set -e" does not work inside a function that is called with ||.
RES=""
set_line() {
  local f=$1 want=$2 had=0
  if [ -f "$f" ] && awk -F: -v n="$NAME" '($1 "") == (n "") {f = 1} END {exit f ? 0 : 1}' "$f"; then had=1; fi
  if [ -f "$f" ]; then awk -F: -v n="$NAME" '($1 "") != (n "")' "$f" > "$TMP" || return 1; else : > "$TMP" || return 1; fi
  if [ "$want" = 1 ]; then printf '%s:%s\n' "$NAME" "$HASH" >> "$TMP" || return 1; fi
  [ -e "$f" ] || : > "$f" || return 1   # a new file takes its owner and mode before it holds a hash
  if [ "$(id -u)" = 0 ]; then chown -- "$OWNER" "$f" || return 1; fi
  chmod "$MODE" "$f" || return 1
  cat "$TMP" > "$f" || return 1          # in place: keeps the inode, so a single-file bind mount into a container stays valid
  if [ "$want" = 1 ]; then if [ "$had" = 1 ]; then RES=replaced; else RES=added; fi
  elif [ "$had" = 1 ]; then RES=removed; else RES=none; fi
}
FAILED=$(T "could not write the list (see the message above). The lists may be out of step: run the same command again once the cause is fixed." "die Liste liess sich nicht schreiben (siehe die Meldung oben). Die Listen koennen auseinanderlaufen: denselben Befehl noch einmal starten, wenn die Ursache behoben ist.")
set_line "$HT" 1 || die "$HT: $FAILED"
R_ALL=$RES
if [ "$ROLE" = admin ]; then set_line "$HA" 1 || die "$HA: $FAILED"; else set_line "$HA" 0 || die "$HA: $FAILED"; fi
R_ADM=$RES

describe() {
  case $1 in
    added) T 'line added' 'Zeile hinzugefuegt' ;;
    replaced) T 'line replaced (the account existed, the password is new)' 'Zeile ersetzt (das Konto gab es schon, das Passwort ist neu)' ;;
    removed) T 'line removed (the account is no longer an admin)' 'Zeile entfernt (das Konto ist kein Admin mehr)' ;;
    none) T 'no line (not an admin)' 'keine Zeile (kein Admin)' ;;
  esac
}
printf '%s\n' "$(T "account '$NAME' ($ROLE)" "Konto '$NAME' ($ROLE)")"
[ -z "$MADE" ] || printf '  %s\n' "$(T "directory $MADE created (mode 755)" "Verzeichnis $MADE angelegt (Modus 755)")"
printf '  %s: %s\n' "$HT" "$(describe "$R_ALL")"
printf '  %s: %s\n' "$HA" "$(describe "$R_ADM")"
if [ "$(id -u)" = 0 ]; then
  printf '  %s\n' "$(T "owner $OWNER, mode $MODE, password hash type $HTYPE" "Besitzer $OWNER, Modus $MODE, Passwort-Hash-Typ $HTYPE")"
else
  printf '  %s\n' "$(T "mode $MODE, hash type $HTYPE. WARNING: not run as root, the owner was not set to $OWNER. Files of another owner are unreadable for the nginx worker: every request with a password fails with 500. Run again as root:  $SUDO_CMD" "Modus $MODE, Hash-Typ $HTYPE. WARNUNG: nicht als root gestartet, der Besitzer wurde nicht auf $OWNER gesetzt. Dateien eines anderen Besitzers kann der nginx-Worker nicht lesen: jede Anfrage mit Passwort endet mit 500. Als root noch einmal starten:  $SUDO_CMD")"
fi
printf '  %s\n' "$(T 'nginx reads the files at every request: no restart needed.' 'nginx liest die Dateien bei jeder Anfrage: kein Neustart noetig.')"
