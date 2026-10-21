#!/bin/bash
# Platten-Assistent fuer dcm4chee-arc: leere Platte formatieren, mounten, als Storage im Archiv eintragen.
# Disk assistant for dcm4chee-arc: formats a blank disk, mounts it and adds it as storage to the archive (LDAP).
#
#   pacs-storage.sh scan                  Platten neu einlesen (SCSI-Rescan), Storages, leere und vergroesserte Platten
#   pacs-storage.sh auto [ja]             scan, dann add fuer genau eine leere Platte
#   pacs-storage.sh add /dev/sdX [ja]     ohne ja nur der Plan. Mit ja: ext4 mit Label PACS-DataNN, Mount unter
#                                         STORAGE_BASE, fstab, danach activate
#   pacs-storage.sh activate ID [ja]      gemounteten Storage im Archiv eintragen, hinten an die Schreibliste
#   pacs-storage.sh grow /dev/sdX [ja]    Dateisystem nach Vergroesserung der Platte online erweitern
#   pacs-storage.sh nomount [ja]          Schutzdatei NO_MOUNT unter allen Mountpunkten anlegen, online
#   pacs-storage.sh kandidaten            scan maschinenlesbar, ohne Log (fuer dashboard-status.py)
#   pacs-storage.sh freigeben ID [ja]     Markierung "voll" (dcmStorageThresholdExceeded) entfernen, nur ab STORAGE_FREE_GB
#   pacs-storage.sh anhaengen ID [ja]     Storage mit Platz hinten an die Schreibliste
#   pacs-storage.sh abhaengen ID [ja]     Storage aus der Schreibliste nehmen (keine neuen Bilder, alte bleiben lesbar)
#
# Exit 0 = erledigt, 1 = HALT oder anderer Fehler (Grund in der Zeile "HALT: ..."), 3 = im LDAP geaendert, aber das Archiv
# hat die Konfiguration nicht neu geladen (Zeile "ACHTUNG: ...": in der Oberflaeche des Archivs "Neu laden" klicken).
#
# Einstellungen aus der Umgebung oder /etc/default/pacs-admin, Vorgabe:
#   STORAGE_BASE /mnt/fs                   STORAGE_PREFIX PACS-Data             STORAGE_OWNER 1023:1023
#   STORAGE_MIN_GB 100                     STORAGE_FREE_GB 50                   STORAGE_LOG /var/log/pacs-storage.log
#   ARC_DEVICE dcm4chee-arc                ARC_AET DCM4CHEE                     ARC_URL http://127.0.0.1:8080
#   ARC_CONTAINER arc                      LDAP_CONTAINER ldap                  LDAP_BASE_DN dc=dcm4che,dc=org
# STORAGE_PREFIX: Buchstabe, dann Buchstaben, Ziffern, - und _, hoechstens 14 Zeichen (ext4-Label max. 16 mit Nummer).
# Nur fuer Tests: FSTAB (Vorgabe /etc/fstab), PACS_STORAGE_TEST (gesetzt: Loop-Geraete erlaubt).
#
# Schreibliste = dcmObjectStorageID/dcmMetadataStorageID der AE, Schreibzaehler 1. Das Archiv fuellt den ersten
# Storage bis zur Schwelle (dcmStorageThreshold), nimmt ihn dann selbst aus der Liste und schreibt auf dem
# naechsten weiter. Ein neuer Storage kommt deshalb hinten dran und wird ab diesem Wechsel benutzt.
#
# Formatiert nur eine Platte ohne Partition, ohne Signatur, nicht gemountet, nicht in fstab, erstes MiB nur
# Nullen. Ins Archiv kommt ein Storage erst, wenn der arc-Container das Dateisystem sieht und beschreiben kann,
# sonst landen Objekte im Container statt auf der Platte. Dafuer braucht arc '- STORAGE_BASE:STORAGE_BASE:rslave'.
#
# LDAP: ldapsearch/ldapmodify laufen im LDAP-Container mit dessen eigenem Root-Zugang (LDAP_ROOTPASS oder
# LDAP_ROOTPASS_FILE, Root-DN LDAP_ROOTDN oder cn=admin,LDAP_BASE_DN des Containers). Auf dem Host liegt kein Passwort.
# Alle Befehle ausser kandidaten und nomount pruefen zuerst, ob LDAP lesbar ist: sonst HALT mit Grund und Exit 1 (scan
# meldet "keine Platten" und "LDAP nicht erreichbar" so nie gleich). kandidaten bleibt tolerant (leere Felder).
if [ -r /etc/default/pacs-admin ]; then
    # bash -n zuerst: ein Syntaxfehler (z. B. offenes Anfuehrungszeichen) bricht sonst nur diesen einen Aufruf kommentarlos ab
    bash -n /etc/default/pacs-admin || { echo "  HALT: /etc/default/pacs-admin hat einen Syntaxfehler (Meldung davor)"; exit 1; }
    set -a; . /etc/default/pacs-admin; set +a
fi
set -u
STORAGE_BASE=${STORAGE_BASE:-/mnt/fs}; STORAGE_PREFIX=${STORAGE_PREFIX:-PACS-Data}; FSTAB=${FSTAB:-/etc/fstab}
STORAGE_BASE=${STORAGE_BASE%/}   # "/mnt/fs/" ergaebe "//" in den Pfaden, die dann nicht zu den fstab-Zeilen passen
ARC_CONTAINER=${ARC_CONTAINER:-arc}; LDAP_CONTAINER=${LDAP_CONTAINER:-ldap}; ARC_AET=${ARC_AET:-DCM4CHEE}
ARC_URL=${ARC_URL:-http://127.0.0.1:8080}; ARC_DEVICE=${ARC_DEVICE:-dcm4chee-arc}
LDAP_BASE_DN=${LDAP_BASE_DN:-dc=dcm4che,dc=org}
STORAGE_MIN_GB=${STORAGE_MIN_GB:-100}; STORAGE_FREE_GB=${STORAGE_FREE_GB:-50}; TEST=${PACS_STORAGE_TEST:-}
STORAGE_LOG=${STORAGE_LOG:-/var/log/pacs-storage.log}
STORAGE_OWNER=${STORAGE_OWNER:-1023:1023}   # uid:gid von wildfly im dcm4chee-arc-Image
# Zahlen werden gerechnet: "50GB" wuerde sonst mit einer Meldung von bash abbrechen, und "08" oder "010" gelten in bash als
# Oktalzahl (08 bricht ab, 010 wird zu 8). Darum nur 0 oder Ziffernfolge ohne fuehrende Null, wie dashboard-status.py, und
# hoechstens 6 Stellen (999999 GB reichen; mit 20 Stellen laeuft die Rechnung in bash ueber und liefert negative Zahlen).
for v in STORAGE_MIN_GB STORAGE_FREE_GB; do
    [[ ${!v} =~ ^(0|[1-9][0-9]{0,5})$ ]] || { echo "  HALT: $v='${!v}' ist keine ganze Zahl ohne fuehrende Null mit hoechstens 6 Stellen (/etc/default/pacs-admin)"; exit 1; }
done
# STORAGE_PREFIX steht ungeschuetzt in Regex (awk, sed, grep) und wird mit der Nummer zum ext4-Label (hoechstens 16 Zeichen)
[[ $STORAGE_PREFIX =~ ^[A-Za-z][A-Za-z0-9_-]{0,13}$ ]] || { echo "  HALT: STORAGE_PREFIX '$STORAGE_PREFIX' ungueltig (Buchstabe, dann Buchstaben, Ziffern, - und _, hoechstens 14 Zeichen: ext4-Label max. 16)"; exit 1; }
DEV_DN="dicomDeviceName=$ARC_DEVICE,cn=Devices,cn=DICOM Configuration,$LDAP_BASE_DN"
AE_DN="dicomAETitle=$ARC_AET,$DEV_DN"
GiB=$((1024*1024*1024))
TS=$(date +%Y%m%d-%H%M%S)

[ "$(id -u)" = 0 ] || { echo "als root aufrufen"; exit 1; }
exec 9>/run/pacs-storage.lock
if [ "${1:-}" = kandidaten ]; then   # regelmaessig aus dem Cron: wartet, bis ein laufendes add fertig ist
    flock -w 120 9 || { echo "  HALT: laeuft schon, ein anderer Aufruf von pacs-storage.sh haelt die Sperre /run/pacs-storage.lock seit ueber 120 s"; exit 1; }
else
    flock -w 30 9 || { echo "  HALT: laeuft schon, ein anderer Aufruf von pacs-storage.sh haelt die Sperre /run/pacs-storage.lock seit ueber 30 s"; exit 1; }
    exec > >(tee -a "$STORAGE_LOG") 2>&1
    echo "=== $(date '+%F %T') pacs-storage.sh $*"
fi

halt() { echo "  HALT: $*"; exit 1; }
ok()   { echo "  ok    $*"; }
gib()  { awk -v b=$1 'BEGIN{printf "%.0f GiB", b/2^30}'; }
# Laeuft im LDAP-Container: $1 = ldapsearch|ldapmodify, Rest = Argumente. Passwort aus dessen Umgebung, per -y aus einer
# Datei (0600, danach geloescht), nie mit -w auf der Befehlszeile: die stuende in der Prozessliste des Hosts.
LDAP_SH='if [ -n "${LDAP_ROOTPASS_FILE:-}" ]; then pw=$(cat "$LDAP_ROOTPASS_FILE"); else pw=${LDAP_ROOTPASS:-}; fi
[ -n "$pw" ] || { echo "LDAP_ROOTPASS im LDAP-Container nicht gesetzt" >&2; exit 1; }
f=$(mktemp) || exit 1; printf %s "$pw" > "$f"
c=$1; shift; "$c" -x -H ldap://localhost -D "${LDAP_ROOTDN:-cn=admin,$LDAP_BASE_DN}" -y "$f" "$@"; rc=$?; rm -f "$f"; exit $rc'
lsearch() { docker exec $LDAP_CONTAINER sh -c "$LDAP_SH" sh ldapsearch -LLL -o ldif-wrap=no "$@"; }
lmodify() { docker exec -i $LDAP_CONTAINER sh -c "$LDAP_SH" sh ldapmodify >/dev/null; }
ae_list() { lsearch -b "$AE_DN" -s base $1 | sed -n "s/^$1: //p"; }             # Reihenfolge wie im LDAP
storage_ids() { lsearch -b "$DEV_DN" -s one '(objectClass=dcmStorage)' dcmStorageID | sed -n 's/^dcmStorageID: //p'; }
mounted() { findmnt -rn -o TARGET,SOURCE | awk -v p="^$STORAGE_BASE/${STORAGE_PREFIX}[0-9]+$" '$1 ~ p {n=split($1,a,"/"); print a[n], $2}'; }
fs_bytes() { tune2fs -l "$1" | awk -F: '/^Block count/{c=$2} /^Block size/{s=$2} END{printf "%.0f", c*s}'; }

# LDAP lesbar? Sonst Abbruch mit klarer Meldung (Exit 1) statt leerer Abschnitte: ohne Antwort sehen "keine Platten" und
# "LDAP nicht erreichbar" gleich aus, und add haette die Platte schon formatiert, wenn activate danach scheitert.
ldap_pruefen() {
    local out rc
    command -v docker >/dev/null || halt "docker nicht gefunden (Docker installieren, z. B. apt install docker.io)"
    out=$(lsearch -b "$AE_DN" -s base dicomAETitle 2>&1); rc=$?
    case $rc in
        0)  return 0 ;;
        32) halt "AE '$ARC_AET' (Geraet '$ARC_DEVICE') steht nicht im LDAP von '$LDAP_CONTAINER'. ARC_AET, ARC_DEVICE und LDAP_BASE_DN in /etc/default/pacs-admin pruefen (docs/modules.de.md#disk-assistant)" ;;
        *)  halt "LDAP nicht lesbar (Container '$LDAP_CONTAINER'): $(printf %s "$out" | tail -n 1). Pruefen: docker ps (Name = LDAP_CONTAINER), LDAP_ROOTPASS oder LDAP_ROOTPASS_FILE in der Umgebung des LDAP-Containers (docs/modules.de.md#disk-assistant)" ;;
    esac
}

# Gruende, warum ein Geraet NICHT formatiert werden darf. Leer = darf.
not_blank() {
    local d=$1 t
    [ -b "$d" ] || { echo "kein Blockgeraet"; return; }
    t=$(lsblk -dno TYPE $d)
    [ "$t" = disk ] || { [ -n "$TEST" ] && [ "$t" = loop ]; } || echo "Typ $t"
    [ "$(lsblk -dno RO $d | tr -d ' ')" = 0 ] || echo "schreibgeschuetzt"
    [ "$(lsblk -no NAME $d | wc -l)" = 1 ] || echo "hat Partitionen"
    [ -z "$(ls "/sys/class/block/$(basename "$d")/holders" 2>/dev/null)" ] || echo "in Benutzung (LVM/RAID)"
    t=$(wipefs --no-act --noheadings --output TYPE $d 2>/dev/null | paste -sd ' '); [ -z "$t" ] || echo "Signatur $t"
    t=$(blkid -p -o value -s TYPE $d 2>/dev/null); [ -z "$t" ] || echo "Dateisystem $t"
    findmnt -S $d >/dev/null && echo "gemountet"
    grep -qw "$d" $FSTAB && echo "steht in $FSTAB"
    swapon --show=NAME --noheadings | grep -qx "$d" && echo "Swap"
    [ "$(blockdev --getsize64 $d)" -ge $((STORAGE_MIN_GB*GiB)) ] || echo "kleiner als $STORAGE_MIN_GB GiB"
    cmp -s -n 1048576 $d /dev/zero || echo "erstes MiB nicht leer"
}

# Neue Platten (SCSI-Hosts) und neue Groessen einlesen; virtio-Platten melden neue Groessen selbst
rescan() {
    local f
    for f in /sys/class/scsi_host/*/scan; do [ -e $f ] && echo "- - -" > $f; done           # neue Platten
    for f in /sys/class/block/sd*/device/rescan; do [ -e $f ] && echo 1 > $f; done        # neue Groessen
    [ -n "$TEST" ] && for f in $(losetup -n -O NAME); do losetup -c $f; done
    udevadm settle
}

candidates() {
    local d
    for d in $(lsblk -dno NAME,TYPE | awk '$2=="disk" || $2=="loop" {print "/dev/"$1}'); do
        [ -z "$(not_blank $d)" ] && echo $d
    done
}

next_id() {
    local n
    n=$( { storage_ids; ls $STORAGE_BASE; grep -oE "LABEL=${STORAGE_PREFIX}[0-9]+" $FSTAB | cut -d= -f2; } 2>/dev/null \
        | sed -n "s/^$STORAGE_PREFIX\([0-9]\+\)$/\1/p" | sed 's/^0*//' | sort -n | tail -1)
    printf "%s%02d" $STORAGE_PREFIX $(( ${n:-0} + 1 ))
}

# Verzeichnis unter einem Mountpunkt (vom Mount verdeckt): Bind von / in eigenem Mount-Namespace,
# nichts davon wird nach aussen oder in Container propagiert. $2 = Befehl, {} = Pfad darunter.
peek_under() {
    local r=/run/pacs-storage-peek rc
    mkdir -p $r
    unshare --mount --propagation private sh -c "mount --bind / $r && ${2//\{\}/$r$1}"; rc=$?
    rmdir $r; return $rc
}

reload_arc() {
    local c
    for _ in 1 2 3; do
        c=$(curl -s -m 30 -o /dev/null -w '%{http_code}' -X POST $ARC_URL/dcm4chee-arc/ctrl/reload)
        [ "$c" = 204 ] || [ "$c" = 200 ] && { ok "Archiv-Konfiguration neu geladen"; return 0; }
        sleep 5
    done
    # Die Aenderung steht dann schon im LDAP: Exit 3 statt 1 ("nichts getan"), damit verwaltung-dienst.py und die Seite beides trennen
    echo "  ACHTUNG: Archiv-Konfiguration nicht neu geladen (Antwort $c). Die Aenderung steht im LDAP, das Archiv arbeitet bis zum Neuladen mit der alten Konfiguration. In der Oberflaeche des Archivs unter Konfiguration auf Neu laden klicken."
    exit 3
}

# Storage hinten an die Schreibliste der AE, Objekte und Metadaten
append_to_ae() {
    local id=$1 a
    for a in dcmObjectStorageID dcmMetadataStorageID; do
        ae_list $a | grep -qx "$id" && continue
        printf 'dn: %s\nchangetype: modify\nadd: %s\n%s: %s\n' "$AE_DN" $a $a "$id" | lmodify || halt "$a nicht ergaenzt"
    done
    ok "Schreibliste $ARC_AET: $(ae_list dcmObjectStorageID | tr '\n' ' ')/ Metadaten: $(ae_list dcmMetadataStorageID | tr '\n' ' ')"
}

# Gibt es keinen Storage, sagt das jeder Befehl, der welche braucht (statt leerer Abschnitte oder eines falschen "ok")
keine_storages() {
    echo "  keine Storages unter $STORAGE_BASE gefunden: gesucht werden eingehaengte Platten mit den Namen ${STORAGE_PREFIX}01," \
         "${STORAGE_PREFIX}02 ... Das ist vor der ersten Platte normal (docs/modules.de.md#disk-assistant)."
    [ -d "$STORAGE_BASE" ] || echo "  $STORAGE_BASE gibt es nicht: mkdir -p $STORAGE_BASE"
}

scan() {
    local id dev sz av used c out
    rescan
    used=" $(ae_list dcmObjectStorageID | tr '\n' ' ') "
    echo "--- Storages"
    [ -n "$(mounted)" ] || keine_storages
    mounted | sort | while read -r id dev; do
        read -r sz av <<< "$(df -B1 --output=size,avail "$STORAGE_BASE/$id" | tail -1)"
        printf '  %-12s %-10s %9s gesamt %9s frei%s\n' "$id" "$dev" "$(gib "$sz")" "$(gib "$av")" \
            "$(case "$used" in *" $id "*) echo "   Schreibliste";; esac)"
    done
    echo "--- Leere Platten (add)"
    c=$(candidates); [ -n "$c" ] || echo "  keine"
    for dev in $c; do echo "  $dev $(gib "$(blockdev --getsize64 "$dev")") $(lsblk -dno MODEL "$dev")"; done
    echo "--- Vergroesserte Platten (grow)"
    out=$(mounted | while read -r id dev; do
        [ $(( $(blockdev --getsize64 "$dev") - $(fs_bytes "$dev") )) -gt $GiB ] \
            && echo "  $dev $id: Platte $(gib "$(blockdev --getsize64 "$dev")"), Dateisystem $(gib "$(fs_bytes "$dev")")"
    done)
    echo "${out:-  keine}"
    echo "--- NO_MOUNT fehlt unter dem Mountpunkt (nomount)"
    out=$(mounted | sort | while read -r id dev; do peek_under "$STORAGE_BASE/$id" "[ -e {}/NO_MOUNT ]" || echo "  $id"; done)
    echo "${out:-  keine}"
}

add() {
    local d=${1:-} ja=${2:-} r id mp
    [ -n "$d" ] || halt "Aufruf: add /dev/sdX [ja]"
    rescan
    r=$(not_blank $d); [ -z "$r" ] || halt "$d wird nicht formatiert: $(echo "$r" | paste -sd ';')"
    id=$(next_id); mp=$STORAGE_BASE/$id
    [ ! -e $mp ] || [ -z "$(ls -A $mp)" ] || halt "$mp existiert und ist nicht leer"
    [ -z "$(blkid -L $id 2>/dev/null)" ] || halt "Label $id gibt es schon"
    storage_ids | grep -qx $id && halt "$id steht schon im LDAP"
    echo "--- Plan"
    echo "  Platte:  $d, $(gib "$(blockdev --getsize64 "$d")"), $(lsblk -dno MODEL "$d"), leer"
    echo "  Format:  ext4, Label $id, ohne root-Reserve (-m 0)"
    echo "  Mount:   $mp, fstab: LABEL=$id $mp ext4 nosuid,nodev,nofail 0 0"
    echo "  Archiv:  Storage $id wie $(ae_list dcmObjectStorageID | head -1), Schreibliste $ARC_AET danach:" \
         "$(ae_list dcmObjectStorageID | tr '\n' ' ')$id"
    [ "$ja" = ja ] || { echo "Trockenlauf. Ausfuehren: $0 add $d ja"; exit 0; }

    echo "--- Platte"
    mkfs.ext4 -q -L $id -m 0 $d || halt "mkfs fehlgeschlagen"
    ok "ext4 $id auf $d"
    mkdir -p $mp && touch $mp/NO_MOUNT && chmod 444 $mp/NO_MOUNT      # liegt unter dem Mount, sichtbar nur ohne Platte
    cp -p $FSTAB $FSTAB.bak-$TS
    echo "LABEL=$id $mp ext4 nosuid,nodev,nofail 0 0" >> $FSTAB
    [ -n "$TEST" ] || systemctl daemon-reload
    udevadm settle
    mount -T $FSTAB $mp || halt "mount fehlgeschlagen. fstab-Zeile steht, Sicherung $FSTAB.bak-$TS"
    [ "$(findmnt -n -o SOURCE $mp)" = "$d" ] || halt "$mp ist nicht $d"
    chown $STORAGE_OWNER $mp && chmod 755 $mp
    ok "gemountet $mp, fstab ergaenzt (vorher $FSTAB.bak-$TS), NO_MOUNT darunter"
    activate $id ja
}

activate() {
    local id=${1:-} ja=${2:-} mp tmpl t0 ldif
    [ -n "$id" ] || halt "Aufruf: activate ID [ja]"
    mp=$STORAGE_BASE/$id
    mounted | awk '{print $1}' | grep -qx "$id" || halt "$mp ist nicht gemountet"
    tmpl=$(ae_list dcmObjectStorageID | head -1); [ -n "$tmpl" ] || tmpl=$(storage_ids | grep "^$STORAGE_PREFIX" | sort | tail -1)
    [ -n "$tmpl" ] && [ "$tmpl" != "$id" ] || halt "kein Vorlage-Storage gefunden"
    if [ "$ja" != ja ]; then
        echo "  Storage $id wie $tmpl anlegen (falls neu), hinten an die Schreibliste von $ARC_AET"
        echo "Trockenlauf. Ausfuehren: $0 activate $id ja"; exit 0
    fi
    echo "--- Sichtbar im Container $ARC_CONTAINER?"
    t0=$TS-$$; echo $t0 > $mp/.pacs-storage-check
    [ "$(docker exec $ARC_CONTAINER cat $mp/.pacs-storage-check 2>/dev/null)" = "$t0" ] || { rm -f $mp/.pacs-storage-check
        halt "$ARC_CONTAINER sieht $mp nicht, Archiv NICHT geaendert. arc braucht '- $STORAGE_BASE:$STORAGE_BASE:rslave' in Compose und
        einmal neu erzeugen (Ausfall ~30 s). Danach: $0 activate $id ja"; }
    rm -f $mp/.pacs-storage-check
    docker exec -u $STORAGE_OWNER $ARC_CONTAINER sh -c "touch $mp/.w && rm $mp/.w" || halt "$ARC_CONTAINER kann in $mp nicht schreiben, Archiv NICHT geaendert"
    ok "Container sieht die Platte und kann schreiben"

    echo "--- Archiv"
    if storage_ids | grep -qx $id; then
        ok "Storage $id steht schon im LDAP"
    else
        # Schwelle, Cluster, Pruefsumme wie die Vorlage, aber nie deren Kennzeichen "voll"
        ldif=$(lsearch -b "dcmStorageID=$tmpl,$DEV_DN" -s base | grep -vE '^(dn|dcmStorageID|dcmURI|dcmStorageThresholdExceeded):|^$')
        printf 'dn: dcmStorageID=%s,%s\nchangetype: add\ndcmStorageID: %s\ndcmURI: file://%s\n%s\n' \
            $id "$DEV_DN" $id $mp "$ldif" | lmodify || halt "Storage $id nicht angelegt"
        ok "Storage $id angelegt: $(lsearch -b "dcmStorageID=$id,$DEV_DN" -s base | grep -vE '^(dn|objectClass):|^$' | paste -sd ' ')"
    fi
    append_to_ae $id
    reload_arc
    sleep 2
    curl -s -m 30 $ARC_URL/dcm4chee-arc/storage | grep -q "\"$id\"" && ok "Archiv kennt $id" \
        || echo "  ACHTUNG: $id nicht in $ARC_URL/dcm4chee-arc/storage"
    echo "fertig. $id wird beschrieben, sobald $(ae_list dcmObjectStorageID | head -1) die Schwelle erreicht."
}

grow() {
    local d=${1:-} ja=${2:-} id disk fs
    [ -n "$d" ] || halt "Aufruf: grow /dev/sdX [ja]"
    rescan
    id=$(mounted | awk -v d=$d '$2==d {print $1}'); [ -n "$id" ] || halt "$d ist kein gemounteter Storage unter $STORAGE_BASE"
    disk=$(blockdev --getsize64 $d); fs=$(fs_bytes $d)
    [ $((disk - fs)) -gt $GiB ] || { ok "$id: Dateisystem nutzt die Platte schon ($(gib $fs))"; exit 0; }
    echo "--- Plan"
    echo "  $id auf $d: Dateisystem $(gib $fs) -> $(gib $disk), online mit resize2fs"
    ae_list dcmObjectStorageID | grep -qx $id || echo "  $id steht nicht in der Schreibliste von $ARC_AET (war voll): hinten anfuegen"
    [ "$ja" = ja ] || { echo "Trockenlauf. Ausfuehren: $0 grow $d ja"; exit 0; }
    resize2fs $d || halt "resize2fs fehlgeschlagen"
    ok "$id jetzt $(gib "$(fs_bytes "$d")"), frei $(df -h --output=avail $STORAGE_BASE/$id | tail -1 | tr -d ' ')"
    ae_list dcmObjectStorageID | grep -qx $id || { append_to_ae $id; reload_arc; }
}

# dcm4chee setzt dcmStorageThresholdExceeded, wenn weniger als die Schwelle frei ist, und nimmt es nie selbst weg.
# Wieder beschrieben wird die Platte danach nur, wenn sie in einer Schreibliste steht; ist sie wieder voll, markiert
# dcm4chee sie neu.
freigeben() {
    local id=${1:-} ja=${2:-} av
    [ -n "$id" ] || halt "Aufruf: freigeben ID [ja]"
    mounted | awk '{print $1}' | grep -qx "$id" || halt "$STORAGE_BASE/$id ist nicht gemountet"
    lsearch -b "dcmStorageID=$id,$DEV_DN" -s base dcmStorageThresholdExceeded | grep -q '^dcmStorageThresholdExceeded:' \
        || { ok "$id ist nicht als voll markiert"; exit 0; }
    av=$(df -B1 --output=avail $STORAGE_BASE/$id | tail -1)
    [ "$av" -ge $((STORAGE_FREE_GB * 1000 ** 3)) ] || halt "$id hat nur $(gib $av) frei, unter $STORAGE_FREE_GB GB bleibt die Markierung"
    echo "  $id: Markierung voll entfernen, $(gib $av) frei, $(ae_list dcmObjectStorageID | grep -qx $id \
        && echo "steht in der Schreibliste von $ARC_AET: wird wieder beschrieben, sobald die Platten davor voll sind" \
        || echo "steht in keiner Schreibliste von $ARC_AET: bekommt keine neuen Bilder")"
    [ "$ja" = ja ] || { echo "Trockenlauf. Ausfuehren: $0 freigeben $id ja"; exit 0; }
    markierung_weg $id
    reload_arc
}

markierung_weg() {
    lsearch -b "dcmStorageID=$1,$DEV_DN" -s base dcmStorageThresholdExceeded | grep -q '^dcmStorageThresholdExceeded:' || return 0
    printf 'dn: dcmStorageID=%s,%s\nchangetype: modify\ndelete: dcmStorageThresholdExceeded\n' $1 "$DEV_DN" | lmodify \
        || halt "Markierung bei $1 nicht entfernt"
    ok "Markierung voll bei $1 entfernt"
}

# Storage mit Platz hinten an die Schreibliste (Objekte und Metadaten), z. B. eine Platte, auf der wieder Platz frei
# geworden ist. Neue Bilder kommen darauf, sobald die Platten davor voll sind.
anhaengen() {
    local id=${1:-} ja=${2:-} av
    [ -n "$id" ] || halt "Aufruf: anhaengen ID [ja]"
    mounted | awk '{print $1}' | grep -qx "$id" || halt "$STORAGE_BASE/$id ist nicht gemountet"
    storage_ids | grep -qx "$id" || halt "$id steht nicht im Archiv, mit activate eintragen"
    ae_list dcmObjectStorageID | grep -qx "$id" && { ok "$id steht schon in der Schreibliste"; exit 0; }
    av=$(df -B1 --output=avail $STORAGE_BASE/$id | tail -1)
    [ "$av" -ge $((STORAGE_FREE_GB * 1000 ** 3)) ] || halt "$id hat nur $(gib $av) frei, unter $STORAGE_FREE_GB GB nicht in die Schreibliste"
    echo "  $id, $(gib $av) frei, hinten an die Schreibliste von $ARC_AET: $(ae_list dcmObjectStorageID | paste -sd ' ') $id"
    [ "$ja" = ja ] || { echo "Trockenlauf. Ausfuehren: $0 anhaengen $id ja"; exit 0; }
    markierung_weg $id
    append_to_ae $id
    reload_arc
}

# Storage aus der Schreibliste (Objekte und Metadaten) nehmen: bekommt keine neuen Bilder mehr, die Bilder darauf bleiben
# lesbar. In jeder Liste, in der er steht, muss ein anderer Storage bleiben, der nicht als voll markiert ist, sonst haette
# das Archiv keinen Platz fuer neue Bilder bzw. Metadaten.
abhaengen() {
    local id=${1:-} ja=${2:-} a voll rest drin=""
    [ -n "$id" ] || halt "Aufruf: abhaengen ID [ja]"
    voll=$(lsearch -b "$DEV_DN" -s one '(dcmStorageThresholdExceeded=*)' dcmStorageID | sed -n 's/^dcmStorageID: //p')
    for a in dcmObjectStorageID dcmMetadataStorageID; do
        ae_list $a | grep -qx "$id" || continue
        drin="$drin $a"
        rest=$(ae_list $a | grep -vx "$id" | grep -vxF "${voll:-@@keine@@}")
        [ -n "$rest" ] || halt "$id ist in $a die letzte Platte, die nicht voll ist. Erst eine andere aufnehmen."
    done
    [ -n "$drin" ] || { ok "$id steht in keiner Schreibliste"; exit 0; }
    echo "  $id aus der Schreibliste von $ARC_AET nehmen: bekommt keine neuen Bilder mehr, vorhandene bleiben lesbar." \
         "Danach: $(ae_list dcmObjectStorageID | grep -vx "$id" | paste -sd ' ')"
    [ "$ja" = ja ] || { echo "Trockenlauf. Ausfuehren: $0 abhaengen $id ja"; exit 0; }
    for a in $drin; do
        printf 'dn: %s\nchangetype: modify\ndelete: %s\n%s: %s\n' "$AE_DN" $a $a "$id" | lmodify || halt "$a nicht geaendert"
    done
    ok "Schreibliste $ARC_AET: $(ae_list dcmObjectStorageID | tr '\n' ' ')/ Metadaten: $(ae_list dcmMetadataStorageID | tr '\n' ' ')"
    reload_arc
}

nomount() {
    local ja=${1:-} id miss=""
    [ -n "$(mounted)" ] || { keine_storages; exit 0; }
    for id in $(mounted | awk '{print $1}' | sort); do peek_under $STORAGE_BASE/$id "[ -e {}/NO_MOUNT ]" || miss="$miss $id"; done
    [ -n "$miss" ] || { ok "NO_MOUNT liegt unter allen Mountpunkten"; exit 0; }
    echo "  fehlt unter:$miss"
    [ "$ja" = ja ] || { echo "Trockenlauf. Ausfuehren: $0 nomount ja"; exit 0; }
    for id in $miss; do peek_under $STORAGE_BASE/$id "touch {}/NO_MOUNT && chmod 444 {}/NO_MOUNT" && ok "$id"; done
}

case "${1:-}" in
    scan|auto|add|activate|grow|freigeben|anhaengen|abhaengen) ldap_pruefen ;;
esac
case "${1:-}" in
    scan)     scan ;;
    auto)     rescan; c=$(candidates)
              case $(echo "$c" | grep -c .) in
                  0) echo "  keine leere Platte. Platte an die VM oder den Server anhaengen, dann erneut." ;;
                  1) add $c "${2:-}" ;;
                  *) echo "  mehrere leere Platten, einzeln mit add:"; echo "$c" | sed 's/^/    /' ;;
              esac ;;
    add)      add "${2:-}" "${3:-}" ;;
    activate) activate "${2:-}" "${3:-}" ;;
    grow)     grow "${2:-}" "${3:-}" ;;
    nomount)  nomount "${2:-}" ;;
    freigeben) freigeben "${2:-}" "${3:-}" ;;
    anhaengen) anhaengen "${2:-}" "${3:-}" ;;
    abhaengen) abhaengen "${2:-}" "${3:-}" ;;
    kandidaten)  # je Zeile: kandidat GERAET BYTES MODELL | naechste ID | vorlage ID SCHWELLE | schreibliste IDs | voll IDs
              # Leere Felder moeglich (LDAP nicht erreichbar, keine Vorlage). Die Zeile schreibliste fehlt, wenn die AE
              # im LDAP nicht lesbar ist (sonst saehe das aus wie eine leere Schreibliste). Nur Geraetenamen, die
              # verwaltung-dienst.py annimmt (sd, vd, xvd, nvme), andere Platten (loop, mmcblk, nbd ...) nur von Hand mit add
              rescan
              for d in $(candidates); do
                  [[ $d =~ ^/dev/(sd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme[0-9]+n[0-9]+)$ ]] || continue
                  echo "kandidat $d $(blockdev --getsize64 $d) $(lsblk -dno MODEL $d)"
              done
              t=$(ae_list dcmObjectStorageID | head -1)
              echo "naechste $(next_id)"
              echo "vorlage $t $(lsearch -b "dcmStorageID=$t,$DEV_DN" -s base dcmStorageThreshold | sed -n 's/^dcmStorageThreshold: //p')"
              l=$(lsearch -b "$AE_DN" -s base dcmObjectStorageID) \
                  && echo "schreibliste $(sed -n 's/^dcmObjectStorageID: //p' <<<"$l" | paste -sd ' ')"
              echo "voll $(lsearch -b "$DEV_DN" -s one '(dcmStorageThresholdExceeded=*)' dcmStorageID | sed -n 's/^dcmStorageID: //p' | paste -sd ' ')" ;;
    *) sed -n '5,26p' $0; exit 1 ;;
esac
