#!/usr/bin/env bash
# set-aet.sh: change the AE titles DCM4CHEE and IOCM_QUALITY in the nginx files, app-config.js and config.js of a directory.
# Deutsch: docs/install.de.md#viewer-config. Ausgabe deutsch bei LANG=de*, sonst englisch.
#
#   bash set-aet.sh <new-archive-aet> [<new-rejection-aet>] [--dir DIR] [--dry-run] [--yes]
#                   [--from OLD-ARCHIVE-AET] [--from-rejection OLD-REJECTION-AET]
#
#   new-archive-aet     replaces DCM4CHEE, the AE title of your dcm4chee archive
#   new-rejection-aet   replaces IOCM_QUALITY (the AE of the "rejected studies" view); leave it out to keep IOCM_QUALITY
#   --dir DIR           where your viewer files live, default /opt/ohif (looked at up to 5 levels deep; "." and a symbolic
#                       link are fine)
#   --dry-run           only show what would change
#   --yes               do not ask for confirmation
#   --from / --from-rejection   the titles currently in the files, when they are not DCM4CHEE / IOCM_QUALITY any more
#
# Only whole words are replaced: DCM4CHEE inside 99DCM4CHEE (the DICOM coding scheme of "revoke rejection"), DCM4CHEE2 or
# MY_DCM4CHEE stays as it is, and so does lower-case dcm4chee (/dcm4chee-arc/ is a path, not an AE title). Files are found by
# their content (nginx location/map lines, window.config, window.PACS_ADMIN), not by name. Originals are copied to
# DIR/.set-aet-backup-<time>/ first. Files are rewritten in place, so single-file bind mounts into containers keep working.
# Nothing is changed unless every file can be written (otherwise: run it with sudo).
# This script changes the viewer side only: the AE title itself is defined in dcm4chee (LDAP).
[ -n "${BASH_VERSION:-}" ] || { echo "set-aet.sh: please run this script with bash:  bash $0" >&2; exit 1; }
set -eu

LANGSEL=en
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in de*) LANGSEL=de ;; esac
T() { if [ "$LANGSEL" = de ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
# q VALUE: VALUE as one shell word (quoted only when it holds anything unusual)
q() { case $1 in ''|*[!A-Za-z0-9_./:@%+=,-]*) printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")" ;; *) printf '%s' "$1" ;; esac; }
die() { printf 'set-aet: %s\n' "$1" >&2; exit 1; }
usage() {
  T 'Usage: bash set-aet.sh <new-archive-aet> [<new-rejection-aet>] [--dir DIR] [--dry-run] [--yes]
                      [--from OLD-ARCHIVE-AET] [--from-rejection OLD-REJECTION-AET]
  Replaces DCM4CHEE (and IOCM_QUALITY) in the nginx files, app-config.js and config.js under DIR (default /opt/ohif,
  up to 5 levels deep). Whole words only: 99DCM4CHEE and DCM4CHEE2 stay. Shows what changes and asks first (--yes skips
  the question, --dry-run only shows). Originals go to DIR/.set-aet-backup-<time>/. AE title: 1-16 letters, digits, _ or -.
  Run it with sudo when the files belong to root: nothing is changed unless every file can be written.
' 'Aufruf: bash set-aet.sh <neuer-archiv-aet> [<neuer-ablehnungs-aet>] [--dir VERZEICHNIS] [--dry-run] [--yes]
                      [--from ALTER-ARCHIV-AET] [--from-rejection ALTER-ABLEHNUNGS-AET]
  Ersetzt DCM4CHEE (und IOCM_QUALITY) in den nginx-Dateien, app-config.js und config.js unter VERZEICHNIS (Vorgabe
  /opt/ohif, bis zu 5 Ebenen tief). Nur ganze Woerter: 99DCM4CHEE und DCM4CHEE2 bleiben. Zeigt die Aenderungen und fragt
  vorher (--yes ueberspringt die Frage, --dry-run zeigt nur). Originale kommen nach VERZ/.set-aet-backup-<Zeit>/.
  AE-Titel: 1-16 Buchstaben, Ziffern, _ oder -. Mit sudo starten, wenn die Dateien root gehoeren: ohne Schreibrecht
  auf alle Dateien wird nichts geaendert.
'
}
bad() { printf 'set-aet: %s\n' "$1" >&2; usage >&2; exit 1; }

ORIG=""
for a in "$@"; do ORIG="$ORIG $(q "$a")"; done   # the arguments as typed, for the "run it again with sudo" hint
SUDO_CMD="sudo bash $(q "$0")$ORIG"

DEPTH=5   # levels below DIR: DIR/nginx/pacs/login/server.conf is level 4
DIR=/opt/ohif; DRY=0; YES=0; FROM1=DCM4CHEE; FROM2=IOCM_QUALITY; NEW1=""; NEW2=""
setopt() {   # setopt OPTION VALUE
  case $1 in --dir) DIR=$2 ;; --from) FROM1=$2 ;; --from-rejection) FROM2=$2 ;; esac
}
while [ $# -gt 0 ]; do
  case $1 in
    -h|--help) usage; exit 0 ;;
    --dry-run) DRY=1; shift ;;
    --yes|-y) YES=1; shift ;;
    --dir|--from|--from-rejection)
      [ $# -ge 2 ] || bad "$(T "$1 needs a value" "$1 braucht einen Wert")"
      setopt "$1" "$2"; shift 2 ;;
    --dir=*|--from=*|--from-rejection=*) setopt "${1%%=*}" "${1#*=}"; shift ;;
    -*) bad "$(T "unknown option: $1" "unbekannte Option: $1")" ;;
    *) if [ -z "$NEW1" ]; then NEW1=$1; elif [ -z "$NEW2" ]; then NEW2=$1; else bad "$(T 'too many arguments' 'zu viele Argumente')"; fi; shift ;;
  esac
done
[ -n "$NEW1" ] || { usage >&2; exit 1; }

# AE titles: 1 to 16 characters; only letters, digits, _ and - are accepted here (they are used inside nginx regular expressions)
for v in "$NEW1" "$NEW2" "$FROM1" "$FROM2"; do
  [ -z "$v" ] && continue
  case $v in *[!A-Za-z0-9_-]*) die "$(T "invalid AE title '$v': letters, digits, _ and - only" "ungueltiger AE-Titel '$v': nur Buchstaben, Ziffern, _ und -")" ;; esac
  [ "${#v}" -le 16 ] || die "$(T "AE title '$v' is longer than 16 characters" "AE-Titel '$v' ist laenger als 16 Zeichen")"
done
FINAL1=$NEW1; FINAL2=${NEW2:-$FROM2}
[ "$FINAL1" != "$FINAL2" ] || die "$(T "archive and rejection AE title must differ (both would be '$FINAL1')" "Archiv- und Ablehnungs-AE-Titel muessen verschieden sein (beide waeren '$FINAL1')")"
[ -z "$NEW2" ] || [ "$NEW2" != "$FROM2" ] || NEW2=""   # same title as before: nothing to rename for the rejection AE
if [ "$NEW1" = "$FROM1" ] && [ -z "$NEW2" ]; then
  printf '%s\n' "$(T 'nothing to do: the new titles equal the old ones' 'nichts zu tun: die neuen Titel sind die alten')"; exit 0
fi

# the folder: no trailing slash, then an absolute path ("." and ".." work, the start folder may be hidden or a symbolic link)
while case $DIR in ?*/) true ;; *) false ;; esac; do DIR=${DIR%/}; done
[ -d "$DIR" ] || die "$(T "directory '$DIR' does not exist (use --dir DIR)" "Verzeichnis '$DIR' gibt es nicht (--dir VERZEICHNIS angeben)")"
ABS=$(cd -- "$DIR" 2>/dev/null && pwd) || die "$(T "cannot enter the directory '$DIR'" "kann das Verzeichnis '$DIR' nicht betreten")"
DIR=$ABS
[ "$DIR" != / ] || die "$(T 'refusing to search the whole file system: name the folder with your nginx files (--dir DIR)' 'das ganze Dateisystem wird nicht durchsucht: den Ordner mit den nginx-Dateien nennen (--dir VERZEICHNIS)')"

# the titles that really change (ACT1 empty = archive title stays, ACT2 empty = rejection title stays)
ACT1=""; [ "$NEW1" = "$FROM1" ] || ACT1=$FROM1
ACT2=""; [ -z "$NEW2" ] || ACT2=$FROM2
TITLES=$ACT1; [ -z "$ACT1" ] || [ -z "$ACT2" ] || TITLES="$ACT1 $(T 'or' 'oder') $ACT2"; [ -n "$ACT1" ] || TITLES=$ACT2

# whole-word replacement: a word is a run of [A-Za-z0-9_-]; exact case; one pass, so swaps cannot collide.
# retoken FILE REPORT: new content on stdout, "line TAB -/+ TAB text" for every changed line appended to REPORT
retoken() {
  awk -v o1="$ACT1" -v n1="$NEW1" -v o2="$ACT2" -v n2="$NEW2" -v rep="$2" '
    { rest = $0; out = ""; ch = 0
      while (match(rest, /[A-Za-z0-9_-]+/)) {
        tok = substr(rest, RSTART, RLENGTH); out = out substr(rest, 1, RSTART - 1); rest = substr(rest, RSTART + RLENGTH)
        if (o1 != "" && tok == o1) { tok = n1; ch = 1 } else if (o2 != "" && tok == o2) { tok = n2; ch = 1 }
        out = out tok }
      out = out rest
      if (ch) printf "%d\t-\t%s\n%d\t+\t%s\n", NR, $0, NR, out >> rep
      print out }' "$1"
}
has_old() {
  awk -v o1="$ACT1" -v o2="$ACT2" '
    { rest = $0
      while (match(rest, /[A-Za-z0-9_-]+/)) { tok = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
        if ((o1 != "" && tok == o1) || (o2 != "" && tok == o2)) { f = 1; exit } } }
    END { exit f ? 0 : 1 }' "$1"
}

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/set-aet.XXXXXX") || die "$(T 'cannot create a temporary directory' 'kann kein temporaeres Verzeichnis anlegen')"
trap 'rm -rf "$TMPD"' EXIT
: > "$TMPD/changed.list"; : > "$TMPD/skipped.list"; : > "$TMPD/links.list"
N=0; CONFIG_IN_DIR=0

# -mindepth 1: the start folder itself is never tested (a hidden or "." start folder would be pruned); -H: a symbolic link
# given as DIR is followed. Hidden folders below DIR (the backups of earlier runs) are skipped.
FILES=$(find -H "$DIR" -mindepth 1 -maxdepth "$DEPTH" \( -type d -name '.*' -prune \) -o \( -type f -size -1024k ! -name '*.bak' ! -name '*.orig' ! -name '*.old' ! -name '*~' ! -name '*.swp' ! -name '*.save' -print \) | sort)
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -Iq . "$f" 2>/dev/null || continue                       # binary or empty
  has_old "$f" || continue
  # context: DICOMweb path, nginx lines, OHIF config or admin config (otherwise the word may mean something else)
  # shellcheck disable=SC2016
  if grep -Eq 'aets/|window\.(PACS_ADMIN|config)|\$pacs_|^[[:space:]]*(location|map|upstream|server)[[:space:]]' "$f"; then
    N=$((N + 1)); : > "$TMPD/$N.rep"
    retoken "$f" "$TMPD/$N.rep" > "$TMPD/$N.new"
    printf '%s\t%s\n' "$N" "$f" >> "$TMPD/changed.list"
    if grep -q 'window\.PACS_ADMIN' "$f"; then CONFIG_IN_DIR=1; fi
  else
    printf '%s\n' "$f" >> "$TMPD/skipped.list"
  fi
done <<EOF
$FILES
EOF

# symbolic links are never rewritten (the target may lie outside DIR); one that points to a file with the title is listed
LINKS=$(find -H "$DIR" -mindepth 1 -maxdepth "$DEPTH" \( -type d -name '.*' -prune \) -o \( -type l -print \) | sort)
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if [ -f "$f" ] && grep -Iq . "$f" 2>/dev/null && has_old "$f"; then printf '%s\n' "$f" >> "$TMPD/links.list"; fi
done <<EOF
$LINKS
EOF
show_links() {
  [ -s "$TMPD/links.list" ] || return 0
  printf '\n%s\n' "$(T "NOT changed (symbolic link to a file that contains $TITLES: change the file it points to, or run this script on the folder that holds that file):" "NICHT geaendert (symbolischer Link auf eine Datei, die $TITLES enthaelt: die Datei dahinter aendern, oder das Skript fuer den Ordner starten, der diese Datei enthaelt):")"
  sed 's/^/  /' "$TMPD/links.list"
}

if [ "$N" = 0 ]; then
  show_links >&2
  die "$(T "no nginx file, app-config.js or config.js under $DIR contains the title $TITLES. Wrong --dir, or the titles were changed before (then name the current ones with --from)." "unter $DIR enthaelt keine nginx-Datei, app-config.js oder config.js den Titel $TITLES. Falsches --dir, oder die Titel wurden schon geaendert (dann die aktuellen mit --from nennen).")"
fi

# ---- summary first ----
printf '%s\n' "$(T "AE title change under $DIR:" "AE-Titel-Aenderung unter $DIR:")"
[ -z "$ACT1" ] || printf '  %s -> %s\n' "$ACT1" "$NEW1"
[ -z "$ACT2" ] || printf '  %s -> %s\n' "$ACT2" "$NEW2"
TOTAL=0
while IFS="$(printf '\t')" read -r i f; do
  c=$(( $(wc -l < "$TMPD/$i.rep") / 2 )); TOTAL=$((TOTAL + c))
  printf '\n%s: %s\n' "$f" "$(T "$c line(s)" "$c Zeile(n)")"
  awk -F'\t' '{ if (++n <= 40) printf "  %5d %s %s\n", $1, $2, substr($3, 1, 150) } END { if (n > 40) printf "  ... %d more\n", n - 40 }' "$TMPD/$i.rep"
done < "$TMPD/changed.list"
if [ -s "$TMPD/skipped.list" ]; then
  printf '\n%s\n' "$(T "NOT changed (contains $TITLES but does not look like an nginx, app-config.js or config.js file; check by hand):" "NICHT geaendert (enthaelt $TITLES, sieht aber nicht nach nginx-, app-config.js- oder config.js-Datei aus; von Hand pruefen):")"
  sed 's/^/  /' "$TMPD/skipped.list"
fi
show_links
printf '\n%s\n' "$(T "$N file(s), $TOTAL line(s). Words like 99$FROM1 or ${FROM1}2 are never touched." "$N Datei(en), $TOTAL Zeile(n). Woerter wie 99$FROM1 oder ${FROM1}2 werden nie angefasst.")"

if [ "$DRY" = 1 ]; then printf '%s\n' "$(T 'Dry run: nothing was changed.' 'Probelauf: nichts wurde geaendert.')"; exit 0; fi

# nothing is touched unless the folder (for the backup) and every file can be written: a half-renamed tree is worse than none
NOWRITE=""
[ -w "$DIR" ] || NOWRITE=$DIR
if [ -z "$NOWRITE" ]; then
  while IFS="$(printf '\t')" read -r i f; do
    [ -w "$f" ] || { NOWRITE=$f; break; }
  done < "$TMPD/changed.list"
fi
if [ -n "$NOWRITE" ]; then
  die "$(T "cannot write $NOWRITE, so nothing was changed. Run the script with sudo:  $SUDO_CMD" "kein Schreibrecht auf $NOWRITE, deshalb wurde nichts geaendert. Skript mit sudo starten:  $SUDO_CMD")"
fi

if [ "$YES" != 1 ]; then
  printf '%s' "$(T 'Apply these changes? [y/N] ' 'Diese Aenderungen anwenden? [j/N] ')" >&2
  ANS=""; read -r ANS || true
  case $ANS in y|Y|yes|YES|j|J|ja|JA) ;; *) die "$(T 'aborted, nothing was changed' 'abgebrochen, nichts wurde geaendert')" ;; esac
fi

# ---- apply: backup, then write in place ----
# a backup folder per second; a second run in the same second gets -2, -3, ...: an earlier backup is never overwritten
STAMP=$(date +%Y%m%d-%H%M%S); BK=$DIR/.set-aet-backup-$STAMP; K=1
until mkdir "$BK" 2>/dev/null; do
  [ -e "$BK" ] || die "$(T "cannot create the backup folder $BK, nothing was changed" "kann den Sicherungsordner $BK nicht anlegen, nichts wurde geaendert")"
  K=$((K + 1)); BK=$DIR/.set-aet-backup-$STAMP-$K
done
DONE=0
while IFS="$(printf '\t')" read -r i f; do
  rel=${f#"$DIR"/}
  { mkdir -p "$BK/$(dirname -- "$rel")" && cp -p "$f" "$BK/$rel"; } || die "$(T "cannot copy $f to the backup folder $BK: stopped, $DONE file(s) were changed before this one (their originals are in the backup folder)" "kann $f nicht in den Sicherungsordner $BK kopieren: abgebrochen, vor dieser Datei wurden $DONE Datei(en) geaendert (ihre Originale liegen im Sicherungsordner)")"
  cat "$TMPD/$i.new" > "$f" || die "$(T "cannot write $f (disk full?): stopped, $DONE file(s) were changed before this one. Restore the originals from $BK with:  cp -p $(q "$BK/$rel") $(q "$f")" "kann $f nicht schreiben (Platte voll?): abgebrochen, vor dieser Datei wurden $DONE Datei(en) geaendert. Originale aus $BK zurueckholen mit:  cp -p $(q "$BK/$rel") $(q "$f")")"
  DONE=$((DONE + 1))
done < "$TMPD/changed.list"
printf '\n%s\n' "$(T "Done: $N file(s), $TOTAL line(s) changed. Originals: $BK/" "Fertig: $N Datei(en), $TOTAL Zeile(n) geaendert. Originale: $BK/")"

# ---- what is left to do by hand ----
CUR=$(grep -s '^ARC_AET=' /etc/default/pacs-admin | tail -n 1 || true)
printf '\n%s\n' "$(T 'Still to do by hand:' 'Noch von Hand zu tun:')"
printf '  1. %s\n' "$(T "dcm4chee itself must have an AE with the title $FINAL1 (this script changes the viewer side only)." "dcm4chee selbst muss einen AE mit dem Titel $FINAL1 haben (dieses Skript aendert nur die Viewer-Seite).")"
if [ "$CONFIG_IN_DIR" = 1 ]; then
  printf '  2. %s\n' "$(T "config.js in $DIR was updated (aet, iocmAet). If your admin page uses another config.js, edit aet: and iocmAet: there too." "config.js in $DIR wurde angepasst (aet, iocmAet). Nutzt die Admin-Seite eine andere config.js, dort aet: und iocmAet: ebenfalls aendern.")"
else
  printf '  2. %s\n' "$(T "config.js (admin page): set aet: '$FINAL1' and iocmAet: '$FINAL2' (no config.js found under $DIR)." "config.js (Admin-Seite): aet: '$FINAL1' und iocmAet: '$FINAL2' eintragen (unter $DIR wurde keine config.js gefunden).")"
fi
printf '  3. %s\n' "$(T "/etc/default/pacs-admin: ARC_AET=$FINAL1${CUR:+   (now: $CUR)}   then: systemctl restart pacs-verwaltung" "/etc/default/pacs-admin: ARC_AET=$FINAL1${CUR:+   (jetzt: $CUR)}   danach: systemctl restart pacs-verwaltung")"
printf '  4. %s\n' "$(T "Make nginx read the files again: cd $DIR && docker compose restart   (or: docker exec NGINX-CONTAINER nginx -s reload)" "nginx die Dateien neu lesen lassen: cd $DIR && docker compose restart   (oder: docker exec NGINX-CONTAINER nginx -s reload)")"
printf '  5. %s\n' "$(T 'Reload the browser without cache (Ctrl+F5): the viewer caches app-config.js.' 'Browser ohne Cache neu laden (Strg+F5): der Viewer merkt sich app-config.js.')"
