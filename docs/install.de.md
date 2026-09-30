# Installation

[English](install.md) | Deutsch

Die Anleitung geht von Folgendem aus:

- das Repo liegt in `/opt/pacs-admin` (die systemd-Units und die Cron-Datei erwarten diesen Pfad)
- das Compose-Projekt von dcm4chee liegt in `/opt/dcm4chee-arc` (`PACS_DIR`), mit den Containern `arc` und `ldap`
  im Docker-Netz `dcm4chee_default`
- OHIF und oauth2-proxy laufen in einem eigenen Compose-Projekt, hier `/opt/ohif`
- der Rechnername ist `pacs.example.org`

Alle Befehle als root. Andere Pfade oder Namen stellt man in `/etc/default/pacs-admin` (Schritt 3) und in den beiden
Beispieldateien (Schritt 9) ein. Liegt das Repo nicht in `/opt/pacs-admin`, auch `ExecStart` in beiden Units und die
Cron-Datei anpassen.

## 1. Voraussetzungen prüfen

```
python3 --version                                   # 3.7 oder neuer
docker version --format '{{.Server.Version}}'
docker compose version
iptables --version                                  # "(nf_tables)" heißt iptables-nft
docker inspect -f '{{.Config.Image}}' arc           # dcm4chee-arc-psql, kein -secure-Image
apt install libsqlcipher0 util-linux e2fsprogs curl
```

Das Archiv muss ohne Keycloak laufen. nginx ruft die REST-Schnittstelle von dcm4chee ohne Token auf.

## 2. Dateien ablegen

```
git clone https://github.com/pbaetz99/dcm4chee-admin-panel.git /opt/pacs-admin
```

Man kann das Verzeichnis auch kopieren. Die Skripte werden über `python3` und `/bin/bash` gestartet, fehlende
Ausführungsrechte stören also nicht.

## 3. Einstellungen

```
cp /opt/pacs-admin/deploy/pacs-admin.env.example /etc/default/pacs-admin
```

Jede Zeile der Datei ist auskommentiert und zeigt die Vorgabe. Nur einkommentieren und ändern, was am eigenen Standort
anders ist. Meist sind das `PACS_DIR`, `ARC_AET`, `ARC_CONTAINER`, `LDAP_CONTAINER`, `STORAGE_PREFIX`,
`FW_CLIENT_NAMES` und `DASHBOARD_CONTAINERS`. Alle Variablen stehen unter [Einstellungen](#einstellungen).

Die systemd-Units und der Cron-Job laden die Datei, `pacs-storage.sh` liest sie selbst. Die Python-Skripte kennen nur
ihre Umgebung. Wer eines von Hand aufruft, lädt die Datei vorher:

```
set -a; . /etc/default/pacs-admin; set +a
```

## 4. Schlüssel für das Protokoll

```
(umask 077; openssl rand -hex 32 > /etc/pacs-protokoll.key)
python3 /opt/pacs-admin/server/pacsdb.py test
```

Der Test meldet `Selbsttest ok: ...`. Er prüft, dass libsqlcipher gefunden wird und in der Datenbankdatei kein
Klartext steht.

Der Schlüssel besteht aus 64 kleinen Hex-Zeichen, gehört root und hat die Rechte 0600. Eine Kopie offline
aufbewahren, etwa im Passwort-Tresor. Ohne Schlüssel kann niemand mehr das Protokoll lesen.

Die Datenbank legt der Hilfsdienst beim ersten Schreiben an: `/var/lib/pacs-protokoll/protokoll.db` (Verzeichnis 0700,
Datei 0600).

## 5. Archiv für den Platten-Assistenten vorbereiten

Der Assistent trägt einen Speicher erst ein, wenn der arc-Container den neuen Mount sieht. Dafür braucht arc
`STORAGE_BASE` als Volume mit Mount-Propagation. In `/opt/dcm4chee-arc/docker-compose.yml`:

```
  arc:
    volumes:
      - /mnt/fs:/mnt/fs:rslave
```

arc neu erzeugen. Das Archiv ist dabei etwa 30 Sekunden nicht erreichbar.

```
cd /opt/dcm4chee-arc && docker compose up -d arc
```

Speicher-ID, Label und Mountpunkt tragen denselben Namen: `STORAGE_PREFIX` plus zweistellige Nummer, also etwa
Speicher `PACS-Data01` auf `/mnt/fs/PACS-Data01`. Die Übersicht zeigt nur Mountpunkte nach diesem Muster. Was der
Assistent sieht:

```
bash /opt/pacs-admin/server/pacs-storage.sh scan
```

Die Ausgabe listet gemountete Speicher, leere Platten, vergrößerte Platten und Mountpunkte ohne `NO_MOUNT`. `NO_MOUNT`
ist eine schreibgeschützte Datei unter dem Mountpunkt. Sie ist nur sichtbar, wenn die Platte nicht eingehängt ist,
gedacht für den „Check Mount File Path“ von dcm4chee. `bash /opt/pacs-admin/server/pacs-storage.sh nomount` zeigt den
Plan, `bash /opt/pacs-admin/server/pacs-storage.sh nomount ja` legt die Datei an, wo sie fehlt.

Jeder ändernde Befehl von `pacs-storage.sh` zeigt nur den Plan, solange das letzte Argument nicht `ja` ist. Das Log
steht in `/var/log/pacs-storage.log`.

Der Assistent richtet nur ganze leere Platten ein, nie Partitionen. Die Übersicht bietet nur die Platten an, die
`pacs-storage.sh kandidaten` listet (leer, nicht in Benutzung, mindestens `STORAGE_MIN_GB`). Der Hilfsdienst nimmt
diese Gerätenamen an: `/dev/sd[a-z]+`, `/dev/vd[a-z]+`, `/dev/xvd[a-z]+` und `/dev/nvme[0-9]+n[0-9]+`.

## 6. Hilfsdienst

```
cp /opt/pacs-admin/deploy/systemd/pacs-verwaltung.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now pacs-verwaltung
ls -l /run/pacs-admin/
```

Erwartet: zwei Sockets, Besitzer 101 (nginx im OHIF-Image), Rechte `srw-------`.

```
srw------- 1 101 root 0 ... protokoll.sock
srw------- 1 101 root 0 ... verwaltung.sock
```

Die Sockets und in Schritt 9 der TLS-Schlüssel sind allein durch diese uid geschützt. Kein Konto auf dem Host darf sie
haben:

```
getent passwd 101
```

Der Befehl darf nichts ausgeben. Unter Debian gehört uid 101 oft einem Systemkonto, das ein Paket angelegt hat. Jeder
Prozess dieses Kontos könnte dann über den Socket das Protokoll lesen und die Firewall abschalten. Der Dienst schreibt
in dem Fall eine Warnung ins Journal. Zwei Auswege: `userns-remap` von Docker, dann ist uid 101 im Container auf dem
Host eine freie, hohe uid, oder `user:` in der Compose-Datei mit einer uid, die auf dem Host frei ist (prüfen, ob
nginx im Image dann noch startet). `PACS_SOCKET_UID` auf die uid setzen, die der Host sieht, und dieser uid den
TLS-Schlüssel geben.

Test ohne nginx:

```
curl -s --unix-socket /run/pacs-admin/verwaltung.sock http://localhost/admin/dienst/auftrag
```

Die Antwort ist `{}`, solange noch keine Platte eingerichtet wurde.

## 7. Zahlen für die Übersicht (cron)

```
cp /opt/pacs-admin/deploy/cron/pacs-dashboard /etc/cron.d/pacs-dashboard
set -a; . /etc/default/pacs-admin; set +a
python3 /opt/pacs-admin/server/dashboard-status.py
cat /var/lib/pacs-admin/status/status.json
```

Der Cron-Job läuft alle 5 Minuten und schreibt Fehler nach `/var/log/pacs-dashboard.log`.

Neben Platten, leeren Platten und Containern enthält `status.json` drei Einstellungen für die Seite: `prefix`
(`STORAGE_PREFIX`, die Übersicht zeigt die Plattennamen ohne ihn), `frei_gb` (`STORAGE_FREE_GB`, die Übersicht zeigt
„Markierung entfernen“ und „In Schreibliste aufnehmen“ nur bei Platten mit mindestens so vielen GB frei) und
`warn_gb` (`STORAGE_WARN_GB`, darunter mahnt die Übersicht eine neue Platte an). Nach einer Änderung in
`/etc/default/pacs-admin` `pacs-verwaltung` neu starten und den Job noch einmal laufen lassen.

Die Kachel Dienste zeigt ohne weitere Einstellung die Container des Compose-Projekts in `PACS_DIR`. OHIF und
oauth2-proxy laufen in einem eigenen Projekt. Sollen sie mit auf die Kachel, alle Container aufzählen:
`DASHBOARD_CONTAINERS=arc,ldap,db,ohif,ohif-auth`.

## 8. App-Registrierung in Entra ID

Im Entra Admin Center:

1. App-Registrierungen, Neue Registrierung. Name etwa „PACS“. Unterstützte Kontotypen: nur dieses
   Organisationsverzeichnis. Umleitungs-URI: Plattform Web, `https://pacs.example.org/oauth2/callback`.
2. Übersicht: Anwendungs-ID (Client) und Verzeichnis-ID (Mandant) notieren.
3. Zertifikate & Geheimnisse, Neuer geheimer Clientschlüssel. Den Wert kopieren, nicht die geheime ID. Ablaufdatum
   notieren: ist der Schlüssel abgelaufen, kann sich niemand mehr anmelden.
4. Tokenkonfiguration, Gruppenanspruch hinzufügen: Sicherheitsgruppen, im ID-Token als Gruppen-ID.
5. Zwei Sicherheitsgruppen anlegen, etwa „PACS Viewer“ und „PACS Admin“, und ihre Objekt-IDs notieren. Die
   Viewer-Gruppe darf den Viewer öffnen. Die Admin-Gruppe darf den Viewer und `/admin/` öffnen.

Wohin die Werte gehören:

| Wert | Datei | Stelle |
|---|---|---|
| Verzeichnis-ID (Mandant) | `docker-compose.yml` | `TENANT-ID` in `--oidc-issuer-url` |
| Anwendungs-ID (Client) | `ohif-auth.env` | `OAUTH2_PROXY_CLIENT_ID` |
| Wert des Clientschlüssels | `ohif-auth.env` | `OAUTH2_PROXY_CLIENT_SECRET` |
| Objekt-ID der Viewer-Gruppe | `docker-compose.yml` | `VIEWER-GRUPPEN-ID` |
| Objekt-ID der Admin-Gruppe | `docker-compose.yml` und `nginx.conf` | `ADMIN-GRUPPEN-ID` (beide Stellen) |

Anderer OIDC-Anbieter: `--provider=oidc` mit dessen `--oidc-issuer-url` setzen und die Gruppennamen so eintragen, wie
sie im Claim `groups` stehen. Das Protokoll nennt das Konto nach `preferred_username`. Schickt der Anbieter diesen
Claim nicht (etwa Google), nimmt nginx die E-Mail-Adresse.

## 9. nginx und Compose für OHIF

```
mkdir -p /opt/ohif/tls
cp /opt/pacs-admin/deploy/docker-compose.example.yml /opt/ohif/docker-compose.yml
cp /opt/pacs-admin/deploy/nginx.conf.example /opt/ohif/nginx.conf
```

Geheimnisse für oauth2-proxy. Die beiden Platzhalter danach in der Datei ersetzen:

```
cat > /opt/ohif/ohif-auth.env <<EOF
OAUTH2_PROXY_CLIENT_ID=<Anwendungs-ID>
OAUTH2_PROXY_CLIENT_SECRET=<Wert des Clientschlüssels>
OAUTH2_PROXY_COOKIE_SECRET=$(python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())')
EOF
chmod 600 /opt/ohif/ohif-auth.env
```

Zertifikat mit Zwischenzertifikaten und Schlüssel. nginx läuft im OHIF-Image als uid 101 (oder mit der uid aus
Schritt 6):

```
cp server.crt server.key /opt/ohif/tls/
chown 101 /opt/ohif/tls/server.key && chmod 600 /opt/ohif/tls/server.key
```

Standortwerte sind in beiden Dateien mit `ANPASSEN` markiert:

```
grep -n ANPASSEN /opt/ohif/nginx.conf /opt/ohif/docker-compose.yml
```

- `nginx.conf`: `server_name`, Zertifikatspfade, `$arc` (Containername und http-Port von arc), `$auth`,
  `ADMIN-GRUPPEN-ID`. Heißt die Archiv-AE nicht `DCM4CHEE`, an allen Stellen `DCM4CHEE` und `IOCM_QUALITY` ersetzen
  (`grep -n 'DCM4CHEE\|IOCM_QUALITY' /opt/ohif/nginx.conf`). `99DCM4CHEE` ist ein Codierschema, kein AE-Titel, und
  bleibt stehen.
- `docker-compose.yml`: eine feste Version von `ohif/app` (nginx 1.25.1 oder neuer), der Pfad zu `web/admin`,
  `TENANT-ID`, `--redirect-url`, beide Gruppen-IDs, `--trusted-proxy-ip` (Subnetz des Docker-Netzes, anzeigen mit
  `docker network inspect dcm4chee_default -f '{{(index .IPAM.Config 0).Subnet}}'`) und der Name des Netzes.
- Andere AE-Titel gehören auch in `aet` und `iocmAet` in `web/admin/config.js` und in `ARC_AET`. `config.js` aus dem
  Repo kopieren (`cp /opt/pacs-admin/web/admin/config.js /opt/ohif/config.js`), die Kopie anpassen und die
  auskommentierte Volume-Zeile `./config.js:/srv/pacs-admin/admin/config.js:ro` aktivieren. Dann kommt `git pull` den
  eigenen Änderungen nicht in die Quere.
- Der Abschnitt für die dcm4chee-Oberfläche in `nginx.conf` ist optional. Wer ihn nicht braucht, löscht den Block von
  der Zeile `# ---- OPTIONAL dcm4chee-UI: dcm4chee-Oberflaeche ueber dieselbe Anmeldung` bis
  `# ---- Ende OPTIONAL dcm4chee-UI` und den dreizeiligen Block `if ($pacs_dcm4chee_ui)` im `server`. Die beiden maps
  oben dürfen bleiben. In `config.js` `dcm4cheeUrl: ''` setzen, dann verschwindet der Verweis.
- Mit dem Abschnitt erkennt nginx die Aufrufe der dcm4chee-Oberfläche an einem `Referer`
  `https://<Host>/dcm4chee-arc/ui2/`, dessen Host dem Host der Anfrage entspricht, ohne Port. Browser lassen den
  Standardport 443 weg. Erreichen die Clients nginx auf einem anderen Port, diesen in der map eintragen (Zeile mit
  `ANPASSEN`). Ein Proxy vor nginx muss die Kopfzeile `Host` unverändert weitergeben, sonst bekommt die Oberfläche auf
  ihre Aufrufe 404.

Wer OHIF schon hinter einem eigenen nginx betreibt, übernimmt die Volumes und locations aus den Beispielen in die
eigene Konfiguration. Die Socket-Pfade im Container stehen fest in `nginx.conf`: `/run/pacs-admin/verwaltung.sock`
und `/run/pacs-admin/protokoll.sock`.

Die Container nach dem Hilfsdienst (Schritt 6) starten, damit `/run/pacs-admin` schon da ist:

```
cd /opt/ohif && docker compose up -d
docker exec ohif nginx -t
docker exec ohif ls -l /run/pacs-admin/
```

## 10. Firewall, erster Start im Probelauf

Die Firewall filtert nur IPv4. Docker bindet jeden veröffentlichten Port ohne weitere Angabe auch an `[::]`.
IPv6-Verbindungen laufen dann über `docker-proxy` an der Firewall vorbei, und nginx sieht als Client-Adresse das
Docker-Gateway. Der Reiter Firewall markiert solche Ports mit „IPv6 nicht gefiltert“. Die Ports nur über IPv4
veröffentlichen. In `/opt/dcm4chee-arc/docker-compose.yml` die REST- und Verwaltungsports von arc an den Host binden
(nginx erreicht arc über das Docker-Netz, `ARC_URL` nimmt 127.0.0.1), DICOM und HL7 an `0.0.0.0`:

```
  arc:
    ports:
      - "127.0.0.1:8080:8080"
      - "127.0.0.1:8443:8443"
      - "127.0.0.1:9990:9990"
      - "127.0.0.1:9993:9993"
      - "0.0.0.0:11112:11112"
      - "0.0.0.0:2762:2762"
      - "0.0.0.0:2575:2575"
      - "0.0.0.0:12575:12575"
```

Danach `cd /opt/dcm4chee-arc && docker compose up -d arc`. Das Compose-Beispiel für OHIF veröffentlicht 80 und 443
schon nur auf `0.0.0.0`. Bei anderen Containern mit veröffentlichten Ports (Kibana, Portainer) genauso. Der andere Weg:
IPv6 auf dem Host abschalten (`net.ipv6.conf.all.disable_ipv6 = 1` in `/etc/sysctl.d/`, danach Docker neu starten).
Die Sperrregeln für 8080, 8443, 9990 und 9993 in jedem Fall stehen lassen.

Ohne `PACS_DIR/firewall.json` nimmt `firewall.py` die Datei aus `FW_DEFAULT_RULES` oder den eingebauten Regelsatz: die
Viewer-Ports (`FW_WEB_PORTS`, Vorgabe 443 und 80) offen, DICOM und HL7 (der erste Port aus `FW_DICOM_PORTS` und
`FW_HL7_PORTS`, Vorgabe 11112 und 2575) im Probelauf, 8080, 8443, 9990, 9993, 5601, 8000 und 9443 gesperrt, alle
anderen Ports offen. Der eingebaute Satz sperrt die REST- und Verwaltungsports von dcm4chee also sofort von außen.

Die Regeln gelten für Host-Ports. Kommen DICOM oder HL7 auf einem anderen Host-Port an, etwa mit `104:11112` in der
Compose-Datei von dcm4chee, `FW_DICOM_PORTS=104` (bzw. `FW_HL7_PORTS`) setzen. Für die Absenderlisten setzt
`firewall.py` den Host-Port über `docker ps` in den Port im Container um. Liegt der Viewer nicht auf 443, seinen
https-Port als ersten in `FW_WEB_PORTS` eintragen.

Für den ersten Start alles durchlassen und nur protokollieren, außer den REST- und Verwaltungsports von dcm4chee, die
gesperrt bleiben:

```
cat > /etc/pacs-admin-firewall-start.json <<'EOF'
{"aktiv": true, "standard": "probelauf", "regeln": [
  {"port": 80, "name": "Viewer und Verwaltung (http)", "modus": "offen"},
  {"port": 443, "name": "Viewer und Verwaltung", "modus": "offen"},
  {"port": 11112, "name": "DICOM", "modus": "probelauf"},
  {"port": 2575, "name": "HL7", "modus": "probelauf"},
  {"port": 8080, "name": "dcm4chee REST (http)", "modus": "gesperrt"},
  {"port": 8443, "name": "dcm4chee REST (https)", "modus": "gesperrt"},
  {"port": 9990, "name": "WildFly-Verwaltung", "modus": "gesperrt"},
  {"port": 9993, "name": "WildFly-Verwaltung (https)", "modus": "gesperrt"}
]}
EOF
echo 'FW_DEFAULT_RULES=/etc/pacs-admin-firewall-start.json' >> /etc/default/pacs-admin
set -a; . /etc/default/pacs-admin; set +a
python3 /opt/pacs-admin/server/firewall.py status
```

`status` zeigt die Regeln und die Schnittstelle. Das muss die Schnittstelle sein, über die die Clients kommen. Ist sie
falsch oder leer, `FW_INTERFACE` setzen. Fehlt die Datei aus `FW_DEFAULT_RULES` oder ist sie ungültig, bricht `status`
mit dem Fehler ab, `pacs-firewall` startet nicht und der Reiter Firewall zeigt den Fehler. Die Datei korrigieren oder
einmal im Reiter Firewall speichern: das schreibt `firewall.json`, die dann gilt.

```
cp /opt/pacs-admin/deploy/systemd/pacs-firewall.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now pacs-firewall
systemctl restart pacs-verwaltung
iptables -S DOCKER-USER
```

Erwartet wird die Zeile `-A DOCKER-USER -i ens192 -j PACS-SPERRE` (mit der eigenen Schnittstelle).

Einmal die älteren, gepackten Logs von dcm4chee einlesen, damit die Listen der DICOM- und HL7-Absender nicht leer
anfangen:

```
python3 /opt/pacs-admin/server/firewall.py nachholen
```

Den Probelauf eine Weile laufen lassen. Im Reiter Firewall zeigen „Neu erkannt“ und „Verbindungen an Regeln“, wer
welchen Port anspricht. Das Kernel-Log bekommt je Regel höchstens 10 Zeilen pro Minute, auf viel genutzten Ports
tauchen seltene Quellen deshalb spät auf. Bekannte Quellen erlauben, dann Port für Port auf gesperrt stellen. Das erste
„Speichern“ schreibt `PACS_DIR/firewall.json`, danach spielt `FW_DEFAULT_RULES` keine Rolle mehr. Jedes Speichern
sichert die vorige Fassung in `PACS_DIR/firewall/`.

`systemctl stop pacs-firewall` entfernt den Sprung aus `DOCKER-USER` bis zum nächsten Start von Docker oder zum
nächsten Speichern im Reiter Firewall. Dauerhaft aus: im Reiter Firewall „eingeschaltet“ abwählen und speichern.

## 11. Prüfen

```
systemctl status pacs-verwaltung pacs-firewall --no-pager
journalctl -u pacs-verwaltung -n 50 --no-pager
python3 /opt/pacs-admin/server/firewall.py test
cat /var/log/pacs-dashboard.log
```

- Im Journal steht kein `Protokoll nicht abgelegt` und kein Fehler `absender_sammeln:`.
- `firewall.py test` meldet `Selbsttest ok`.
- https://pacs.example.org/ fragt nach der Anmeldung und öffnet den Viewer.
- https://pacs.example.org/admin/ zeigt mit einem Admin-Konto Platten und Container. Ein Konto nur in der
  Viewer-Gruppe bekommt 403.
- Eine Studie im Viewer öffnen. Im Reiter Protokoll zeigt „Heute“ dann „Studie geöffnet“. Auf dem Host:
  `python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse $(date +%F)`.

## 12. Aktualisieren

```
cd /opt/pacs-admin
git pull
git diff ORIG_HEAD -- deploy/
systemctl restart pacs-verwaltung
```

- Die Seite kommt direkt aus `/opt/pacs-admin/web/admin`. Browser laden die neue Fassung beim nächsten Neuladen.
- Änderungen in `deploy/` in `/opt/ohif/nginx.conf`, `/opt/ohif/docker-compose.yml` und `/etc/default/pacs-admin`
  nachziehen. Nach einer Änderung an `nginx.conf`: `docker exec ohif nginx -t && docker exec ohif nginx -s reload`.
- Hat sich eine Unit oder die Cron-Datei geändert, neu kopieren und `systemctl daemon-reload`.
- `pacs-verwaltung` lädt beim Neustart das neue `firewall.py`, `pacs-firewall.service` nimmt es beim nächsten Start von
  Docker. Wer die Regeln sofort mit dem neuen Code setzen will, ruft mit geladenen Einstellungen
  `python3 /opt/pacs-admin/server/firewall.py start` auf. `iptables-restore` ersetzt die Kette in einem Schritt, ohne
  Lücke.

## 13. Entfernen

```
systemctl disable --now pacs-verwaltung
systemctl disable --now pacs-firewall          # entfernt den Sprung aus DOCKER-USER, alle Ports offen
iptables -F PACS-SPERRE
iptables -X PACS-SPERRE
rm /etc/systemd/system/pacs-firewall.service /etc/systemd/system/pacs-verwaltung.service /etc/cron.d/pacs-dashboard
systemctl daemon-reload
```

In `nginx.conf` die locations für `/admin/` und die Zeilen `access_log syslog:` entfernen, in `docker-compose.yml` die
Volumes für `/srv/pacs-admin` und `/run/pacs-admin`. Danach in `/opt/ohif` `docker compose up -d`.

Was zurückbleibt:

- `/var/lib/pacs-protokoll/` und `/etc/pacs-protokoll.key`: das Protokoll. Beides so lange aufheben, wie die
  Aufbewahrungsfristen es verlangen.
- `/var/lib/pacs-admin/`, `PACS_DIR/firewall.json`, `PACS_DIR/firewall/`, `/etc/default/pacs-admin`,
  `/etc/pacs-admin-firewall-start.json`, `/var/log/pacs-storage.log`, `/var/log/pacs-dashboard.log`, `/opt/pacs-admin`:
  löschen, wenn nicht mehr gebraucht.
- Platten, die der Assistent eingerichtet hat, bleiben normale Speicher von dcm4chee mit ihren Einträgen in
  `/etc/fstab`.

## Einstellungen

Alle Variablen stehen in `/etc/default/pacs-admin`, je Zeile `NAME=wert`, ohne `export`. Werte mit Leerzeichen oder
JSON in einfache Anführungszeichen setzen. Nach einer Änderung: `systemctl restart pacs-verwaltung pacs-firewall`.

| Variable | Vorgabe | Gelesen von | Bedeutung |
|---|---|---|---|
| `PACS_DIR` | `/opt/dcm4chee-arc` | firewall.py, dashboard-status.py | Compose-Projekt von dcm4chee. Dort liegen `firewall.json` und `firewall/` (Sicherungen, Absender- und Client-Listen). |
| `PACS_ADMIN_VAR` | `/var/lib/pacs-admin` | dashboard-status.py | Arbeitsverzeichnis. `status/status.json` erscheint als `/admin/daten/status.json`. |
| `PACS_SOCKET` | `/run/pacs-admin/verwaltung.sock` | verwaltung-dienst.py | HTTP-Socket des Hilfsdienstes. nginx erwartet ihn im Container als `/run/pacs-admin/verwaltung.sock`. |
| `PACS_LOG_SOCKET` | `/run/pacs-admin/protokoll.sock` | verwaltung-dienst.py | Datagramm-Socket für die syslog-Zeilen von nginx. Gleiches Verzeichnis wie `PACS_SOCKET`. |
| `PACS_SOCKET_UID` | `101` | verwaltung-dienst.py | Besitzer beider Sockets: uid von nginx im OHIF-Container. Kein Konto auf dem Host darf diese uid haben (Schritt 6). |
| `PROTOKOLL_DB` | `/var/lib/pacs-protokoll/protokoll.db` | pacsdb.py | Verschlüsselte Protokoll-Datenbank. |
| `PROTOKOLL_KEY` | `/etc/pacs-protokoll.key` | pacsdb.py | Schlüsseldatei, 64 kleine Hex-Zeichen. |
| `ARC_URL` | `http://127.0.0.1:8080` | pacs-storage.sh | REST von dcm4chee vom Host aus, zum Neuladen der Archiv-Konfiguration. |
| `ARC_AET` | `DCM4CHEE` | pacs-storage.sh | Archiv-AE, deren Schreibliste der Assistent ändert. Muss zu `aet` in `config.js` und zu `nginx.conf` passen. |
| `ARC_DEVICE` | `dcm4chee-arc` | pacs-storage.sh | Gerätename von dcm4chee im LDAP (`dicomDeviceName`). |
| `ARC_LOG_DIR` | `/var/local/dcm4chee-arc/wildfly/log/` | firewall.py | Verzeichnis auf dem Host mit dem `server.log` von wildfly, Quelle der DICOM- und HL7-Absender. |
| `ARC_CONTAINER` | `arc` | pacs-storage.sh | Name des arc-Containers. Damit prüft der Assistent, ob arc eine neue Platte sieht und beschreiben kann. |
| `LDAP_CONTAINER` | `ldap` | pacs-storage.sh | Name des LDAP-Containers. `ldapsearch` und `ldapmodify` laufen darin mit dessen eigenem `LDAP_ROOTPASS`. |
| `LDAP_BASE_DN` | `dc=dcm4che,dc=org` | pacs-storage.sh | Basis-DN der dcm4chee-Konfiguration. |
| `STORAGE_BASE` | `/mnt/fs` | pacs-storage.sh, dashboard-status.py | Verzeichnis mit den Mountpunkten der Platten. |
| `STORAGE_PREFIX` | `PACS-Data` | pacs-storage.sh, dashboard-status.py, verwaltung-dienst.py | Name neuer Platten: Präfix plus zweistellige Nummer, zugleich Label, Mountpunkt und Speicher-ID. Ein Buchstabe, dann Buchstaben, Ziffern, `-` und `_`, höchstens 14 Zeichen (das ext4-Label fasst 16 mit Nummer), sonst bricht `pacs-storage.sh` ab. Der Hilfsdienst nimmt nur dieses Präfix plus Ziffern an. Die Übersicht bekommt es als `prefix` in `status.json` und zeigt die Namen ohne Präfix. |
| `STORAGE_OWNER` | `1023:1023` | pacs-storage.sh | Besitzer eines neuen Dateisystems, uid:gid von wildfly im dcm4chee-Image. |
| `STORAGE_MIN_GB` | `100` | pacs-storage.sh | Kleinste Platte in GiB, die der Assistent anbietet. |
| `STORAGE_FREE_GB` | `50` | pacs-storage.sh, dashboard-status.py | So viele GB müssen frei sein, um „voll“ zu entfernen oder eine Platte in die Schreibliste aufzunehmen. Die Übersicht bekommt den Wert als `frei_gb` in `status.json` und zeigt die beiden Knöpfe erst ab diesem Wert. |
| `STORAGE_WARN_GB` | `300` | dashboard-status.py | Ist auf den Platten der Schreibliste bis zur Schwelle weniger als so viele GB frei, mahnt die Übersicht eine neue Platte an. Die Seite bekommt den Wert als `warn_gb` in `status.json`. |
| `STORAGE_LOG` | `/var/log/pacs-storage.log` | pacs-storage.sh | Log des Assistenten. |
| `FW_INTERFACE` | Schnittstelle der Standardroute | firewall.py | Schnittstelle, über die die Clients kommen. Das erste Speichern im Reiter Firewall legt sie in `firewall.json` ab (`schnittstelle`), danach gilt dieser Wert. |
| `FW_WEB_PORTS` | `443,80` | firewall.py | Host-Ports des Viewers, durch Komma getrennt. Der erste ist der https-Port: Speichern im Reiter Firewall wird abgelehnt, wenn der speichernde PC ihn verlöre. Im eingebauten Regelsatz sind alle offen, vor dem Sperren fragt die Seite nach. |
| `FW_DICOM_PORTS` | `11112,2762` | firewall.py | Host-Ports für DICOM. Der erste bekommt die Vorschläge unter „Neu erkannt“, die Prüfung der Client-PCs und im eingebauten Regelsatz den Probelauf. Die Absenderliste liest das Log von dcm4chee für diese Ports, über `docker ps` in den Port im Container umgesetzt (etwa `104:11112`). |
| `FW_HL7_PORTS` | `2575,12575` | firewall.py | Dasselbe für HL7. Die drei Listen dürfen keinen Port gemeinsam haben, sonst gelten für alle drei die Vorgaben. |
| `FW_DEFAULT_RULES` | leer | firewall.py | JSON-Datei im Format von `firewall.json`, gilt solange es keine `firewall.json` gibt. Leer: eingebauter Regelsatz. |
| `FW_PORT_NAMES` | leer | firewall.py | Eigene Portnamen als JSON, etwa `'{"104": "DICOM (alt)"}'`, über die eingebauten Namen gelegt. |
| `FW_CLIENT_NAMES` | leer | firewall.py | Namensmuster der Client-PCs für die Suche im DNS, durch Komma getrennt. `{a..b}` zählt wie in bash von a bis b. Hat eine Grenze eine Null vorne, werden alle Zahlen mit Nullen auf die Breite der Grenzen gebracht. Beispiel: `'PC{001..250},WS{0001..0400}'` ergibt PC001 bis PC250 und WS0001 bis WS0400. Höchstens 100000 Namen je Muster. Suche stündlich. Leer: keine Suche. |
| `DASHBOARD_CONTAINERS` | leer | dashboard-status.py | Container für die Kachel Dienste, durch Komma oder Leerzeichen getrennt. Leer: alle Container des Compose-Projekts in `PACS_DIR`, gestoppte rot. |

`pacs-storage.sh` versteht außerdem seine älteren Namen: `BASE`, `PREFIX`, `OWNER`, `MIN_GB`, `FREI_GB`, `LOG`, `AE`,
`C_ARC`, `C_LDAP`. Die neuen Namen haben Vorrang, also diese setzen. `dashboard-status.py` liest ebenfalls `FREI_GB`.
`FSTAB` (Vorgabe `/etc/fstab`) und `PACS_STORAGE_TEST` (gesetzt: Loop-Geräte erlaubt) sind für Tests da.

Die Seite liest ihre Einstellungen aus `web/admin/config.js`: `titel`, `aet`, `iocmAet`, `dcm4cheeUrl`, `viewerUrl`,
`logo`, `locale`. Eine leere Adresse blendet den Verweis aus, ein leeres `logo` zeigt nur den Titel. Das Logo muss
vom selben Ursprung kommen wie die Seite: `/admin/` schickt `Cross-Origin-Embedder-Policy: require-corp`, ein Bild von
einem anderen Server lädt nicht. Das Compose-Beispiel hat eine auskommentierte Volume-Zeile, die es als
`/pacs-logo.svg` ausliefert. `locale` (Vorgabe `de-DE`) bestimmt das Format von Zahlen und Zeitpunkten, etwa `de-CH`.
DICOM-Datumsangaben (Studiendatum, Geburtsdatum) stehen immer als TT.MM.JJJJ da. Eine ungültige Angabe fällt auf
`de-DE` zurück. Die Texte bleiben deutsch.

Optional: `/var/lib/pacs-admin/status/rechner.json`, ein JSON-Objekt IP zu PC-Name, etwa `{"192.0.2.50": "WS0050"}`.
Liegt die Datei da, zeigt der Reiter Protokoll den PC-Namen neben der IP. Nichts in diesem Repo schreibt sie.

## Fehlersuche

### Die Übersicht meldet „Kein Status vorhanden“

`/admin/daten/status.json` fehlt. Den Job von Hand starten und die Ausgabe ansehen:

```
set -a; . /etc/default/pacs-admin; set +a
python3 /opt/pacs-admin/server/dashboard-status.py
cat /var/log/pacs-dashboard.log
docker exec ohif ls -l /srv/pacs-admin/status/
```

Liegt die Datei auf dem Host, aber nicht im Container, zeigt das Volume für `/srv/pacs-admin/status` auf das falsche
Verzeichnis. Platten, die nicht zu `STORAGE_BASE/STORAGE_PREFIX<Nummer>` passen, fehlen in der Liste.

### Firewall und Protokoll melden „HTTP 502“

nginx erreicht den Socket des Hilfsdienstes nicht. Beide Seiten prüfen:

```
systemctl status pacs-verwaltung --no-pager
ls -l /run/pacs-admin/
docker exec ohif ls -l /run/pacs-admin/
docker logs ohif 2>&1 | grep verwaltung.sock | tail
```

- `No such file or directory` im Container, obwohl der Socket auf dem Host liegt: das Verzeichnis wurde nach dem Start
  des Containers neu angelegt. Abhilfe: `docker restart ohif`.
- `Permission denied`: der Besitzer des Sockets passt nicht zur uid von nginx im Container. `PACS_SOCKET_UID` setzen
  und `pacs-verwaltung` neu starten.

### Das Protokoll bleibt leer

`pacs-verwaltung` startet nicht und im Journal steht `libsqlcipher nicht gefunden`: `libsqlcipher0` installieren.

Im Journal steht `Protokoll nicht abgelegt (N Zeilen), neuer Versuch in 10 s:`, dahinter

- `No such file or directory: '/etc/pacs-protokoll.key'`: die Schlüsseldatei fehlt (Schritt 4).
- `ist nicht 64 Hex-Zeichen (kleingeschrieben)`: der Schlüssel hat das falsche Format.
- `file is not a database`: der Schlüssel gehört nicht zur vorhandenen Datenbank. Den richtigen zurückspielen.

Der Dienst hält die wartenden Zeilen im Speicher und versucht es alle 10 Sekunden neu. Ein Neustart des Dienstes
verwirft sie.

### /admin/ meldet 403, der Viewer geht

oauth2-proxy findet die Admin-Gruppe nicht im Token.

- In der Tokenkonfiguration der App-Registrierung steht der Gruppenanspruch, als Gruppen-ID.
- Die Objekt-ID in `nginx.conf` (`allowed_groups=`) ist dieselbe wie in der zweiten Zeile `--allowed-group`.
- Nach einer Änderung der Gruppen unter `https://pacs.example.org/oauth2/sign_out` abmelden und neu anmelden. Die
  Gruppen werden bei der Anmeldung gelesen.

### Eine neue Platte bricht bei „arc sieht ... nicht“ ab

Die Seite zeigt „Abgebrochen“ mit `HALT: arc sieht /mnt/fs/PACS-Data06 nicht, Archiv NICHT geaendert`. Die Platte ist
dann schon formatiert, eingehängt und in `/etc/fstab`, aber arc sieht den Mount nicht, und am Archiv hat sich nichts
geändert. Das Volume aus Schritt 5 eintragen, arc neu erzeugen und den Schritt von Hand abschließen:

```
cd /opt/dcm4chee-arc && docker compose up -d arc
bash /opt/pacs-admin/server/pacs-storage.sh activate PACS-Data06 ja
```
