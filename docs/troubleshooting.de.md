# Fehlersuche

[English](troubleshooting.md) | Deutsch

<a id="troubleshooting"></a>
Diese Seite hilft, wenn etwas nicht funktioniert. Die Einträge sind nach dem geordnet, was man sieht: eine Meldung auf dem Bildschirm,
eine Zeile in einem Log, eine Seite, die leer bleibt. Das passende Symptom in [Kapitel 1](#symptom-index) suchen, den Eintrag öffnen
und ihm folgen. Jeder Eintrag hat dieselben Teile: **Was man sieht**, **Ursache**, **Abhilfe** und einen **Prüfen**-Kasten, der zeigt,
woran man erkennt, dass die Abhilfe gewirkt hat.

Alle Befehle als root ausführen. Ein **Warnung**-Kasten nennt, was ein Schritt kaputtmachen kann, wie lange es dauert und wie man zurückgeht.

Drei Hinweise zu den Meldungen:

- Der Hilfsdienst und die Skripte dieses Projekts geben die meisten Meldungen auf Deutsch aus. Diese Seite zitiert sie genau.
  `preflight.sh` gibt Englisch oder Deutsch aus; diese Seite zitiert den deutschen Text. Er kommt ohne Umlaute aus (ae, oe, ue, ss).
- Die Admin-Seite ist deutsch. Namen von Reitern, Schaltflächen und Badges stehen in `code`. Die Liste steht im
  [Glossar](glossary.de.md#screen-labels).
- Meldungen anderer Programme (nginx, Docker, oauth2-proxy, der Identitätsanbieter) können sich mit der Version ändern. Diese Seite
  nennt eine solche Meldung „typisch“, wenn sie für diese Seite nicht ausgeführt wurde.

- [1. Das Symptom finden](#symptom-index)
- [2. Wo die Logs liegen](#log-locations)
- [3. Installation, Pakete und Hilfsdienst](#trouble-install)
- [4. Eingangstür (nginx)](#trouble-front-door)
- [5. Anmeldung](#trouble-login)
- [6. Viewer und Archiv](#trouble-viewer)
- [7. Admin-Seite und Protokoll](#trouble-admin-page)
- [8. Platten-Assistent](#trouble-disk)
- [9. Firewall](#trouble-firewall)

<a id="symptom-index"></a>
## 1. Das Symptom finden

Den Text suchen, der zu sehen ist. Eine zitierte Meldung ist genau. Ein `...` steht für einen Teil, der von Fall zu Fall verschieden
ist. Die Tabellen sind nach dem Ort geordnet, an dem das Problem auftritt.

### 1.1 In einem Terminal, während der Installation

| Was man sieht | Eintrag |
|---|---|
| Eine `[FAIL]`- oder `[WARN]`-Zeile von `preflight.sh` | [3.1](#preflight-fails) |
| `libsqlcipher nicht gefunden` oder `SQLCipher library not found` | [3.2](#libsqlcipher-missing) |
| `file is not a database` oder `file is encrypted or is not a database` | [3.3](#audit-key-mismatch) |
| `Schluessel in /etc/pacs-protokoll.key ist nicht 64 Hex-Zeichen (kleingeschrieben)` | [3.3](#audit-key-mismatch) |
| `Achtung: Protokoll-Datenbank nicht nutzbar` oder `Protokoll nicht abgelegt` im Journal | [3.3](#audit-key-mismatch) |
| Der Selbsttest `pacsdb.py test` endet mit `AssertionError` | [3.4](#pacsdb-selftest) |
| `getent passwd 101` gibt eine Zeile aus, oder `Achtung: PACS_SOCKET_UID 101 ist auf dem Host das Konto ...` | [3.5](#uid-101-taken) |
| `/run/pacs-admin/` ist leer, oder `pacs-verwaltung` ist nicht `active` | [3.6](#no-sockets) |
| `laeuft schon`, `keine Berechtigung`, `ist keine ganze Zahl`, `status=203/EXEC` | [3.6](#no-sockets) |
| `network ... declared as external, but could not be found` | [3.7](#external-network-missing) |
| `docker compose` funktioniert nicht, oder `docker compose: plugin not found` | [3.8](#compose-version) |

### 1.2 Die ganze Seite im Browser

| Was man sieht | Eintrag |
|---|---|
| Der Browser warnt vor dem Zertifikat (`ERR_CERT_COMMON_NAME_INVALID`, Namensfehler, abgelaufen) | [3.1](#preflight-fails) |
| Die Seite öffnet sich nicht. `docker ps` zeigt `Restarting` für den Container `ohif` | [4.1](#tls-key-unreadable), [4.2](#nginx-wont-start) |
| `[emerg]` in `docker logs ohif` | [4.2](#nginx-wont-start) |
| Jede Seite antwortet mit 500. Das Log sagt `could not be resolved` | [4.3](#every-page-500) |
| Jeder Pfad antwortet mit 404 oder 502 | [4.3](#every-page-500) |
| Die Anmeldung `basic` zeigt 403 oder 500 statt der Passwortabfrage | [4.4](#htpasswd-403-500) |
| Das Protokoll zeigt für jeden Benutzer die Adresse des Proxys | [4.5](#proxy-wrong-address) |

### 1.3 Anmeldung

| Was man sieht | Eintrag |
|---|---|
| `AADSTS50011` auf der Microsoft-Anmeldeseite | [5.1](#login-redirect-uri-mismatch) |
| `AADSTS7000215` oder `AADSTS7000222` | [5.2](#login-client-secret) |
| Kein Sprung zur Anmeldeseite, oder der Container `ohif-auth` ist nicht `Up` | [5.3](#login-oauth2-proxy-down) |
| Der Browser springt immer wieder zwischen dem PACS und der Anmeldeseite hin und her | [5.4](#login-loop) |
| Die Seite „Forbidden“ oder ein 403 direkt nach der Anmeldung, im Viewer | [5.5](#viewer-403-after-login) |
| Ein 403 bei `/admin/` für ein Konto, das Admin sein soll | [5.6](#admin-403) |
| Ein 500 bei `/admin/` | [5.7](#admin-500) |
| `Sitzung abgelaufen, Seite neu laden (F5)` | [5.8](#session-expired) |
| Die Anmeldung `basic` fragt immer wieder, oder antwortet mit 401 | [5.9](#basic-login-401) |
| Anmeldung `none`: 403 für alle | [5.10](#none-403) |

### 1.4 Viewer und Archiv

| Was man sieht | Eintrag |
|---|---|
| Der Viewer öffnet sich, aber die Studienliste ist leer | [6.1](#viewer-no-studies) |
| Die Benutzeroberfläche von dcm4chee antwortet mit 404 | [6.2](#dcm4chee-ui-404) |
| Ein Upload in der Benutzeroberfläche von dcm4chee scheitert | [6.3](#dcm4chee-ui-upload) |
| `arc` bleibt nach der Änderung der Compose-Datei aus | [6.4](#arc-rslave-refused) |
| `absender_sammeln: ... No such file or directory` im Journal | [6.5](#arc-log-dir) |

### 1.5 Admin-Seite und Protokoll

| Was man sieht | Eintrag |
|---|---|
| Die Zeile `Kein Status vorhanden (dashboard-status.py läuft per cron alle 5 Minuten).` unter dem Titel des Reiters `Übersicht` | [7.2](#cron-not-running) |
| Eine Zeile, die mit `dashboard-status.py:` beginnt, in `/var/log/pacs-dashboard.log` oder nach `Nach neuen Platten suchen:` | [7.2](#cron-not-running) |
| Die Kachel `Speicher` sagt `Keine Daten zu den Platten (...)`, oder die Kachel `Dienste` fehlt | [7.2](#cron-not-running) |
| `abgelehnt (HTTP 502)` oder `Fehler: Protokoll: HTTP 502` | [7.1](#admin-dienst-502) |
| `Protokoll: HTTP 503` | [3.3](#audit-key-mismatch) |
| Dem Reiter `Protokoll` fehlen Zeilen, die man erwartet | [7.3](#audit-lines-missing) |
| Die Zeiten im Reiter `Protokoll` weichen von der Uhr ab | [7.4](#audit-timezone) |
| `Sitzung abgelaufen, Seite neu laden (F5)` | [5.8](#session-expired) |

### 1.6 Platten-Assistent

| Was man sieht | Eintrag |
|---|---|
| Ein roter Kasten `Abgebrochen` mit einer Zeile, die mit `HALT:` beginnt, oder `nicht ausgeführt, siehe Log von pacs-storage.sh` | [8.1](#disk-halt) |
| `HALT: /etc/default/pacs-admin hat einen Syntaxfehler (Meldung davor)` oder `HALT: NAME='wert' ist keine ganze Zahl ohne fuehrende Null mit hoechstens 6 Stellen (/etc/default/pacs-admin)` | [8.1](#disk-halt) |
| `HALT: laeuft schon, ...` oder `Es wird gerade schon eine Platte eingerichtet.` | [8.1](#disk-halt) |
| `Die Platte ist nicht mehr genau so als leer erkannt. Bitte neu suchen.` | [8.1](#disk-halt), [8.2](#disk-not-offered) |
| Die Kachel `Neue Festplatte` sagt `Keine leere Platte gefunden.` | [8.2](#disk-not-offered) |
| Die Kachel `Speicher` sagt `Schreibliste nicht lesbar (LDAP-Container und pacs-storage.sh kandidaten prüfen).` | [8.2](#disk-not-offered), [7.2](#cron-not-running) |
| Eine Platten-Aktion ist auf halbem Weg stehen geblieben | [8.3](#disk-half-done) |
| Der gelbe Kasten `Archiv nicht neu geladen` oder `Archiv-Konfiguration nicht neu geladen ... (HTTP 500)` | [8.3](#disk-half-done) |
| `pacs-storage.sh antwortet nicht (nach 300 s abgebrochen), Zustand pruefen (HTTP 504)` | [8.3](#disk-half-done) |
| Das Badge `nicht eingehängt, bitte prüfen` oder `nicht gemountet` | [8.4](#disk-not-mounted) |

### 1.7 Firewall

| Was man sieht | Eintrag |
|---|---|
| Der Server ist nach dem Speichern von Regeln nicht mehr erreichbar | [9.1](#firewall-lockout-brake) |
| Das Badge `nicht wirksam` | [9.2](#firewall-not-effective) |
| Das Badge `IPv6 nicht gefiltert` oder die Zeile `N Ports über IPv6 nicht gefiltert` | [9.3](#ipv6-not-filtered) |
| Eine Meldung wie `iptables nicht gefunden: ...` oder `Firewall laden: Firewall: ... (HTTP 500)` | [9.4](#firewall-tools-missing) |
| `Firewall speichern: ... (HTTP 400)` oder eine Meldung mit `FW_DEFAULT_RULES` oder `firewall.json` | [9.5](#firewall-save-failed) |
| `Nicht übernommen, die vorigen Regeln gelten weiter: ...` | [9.5](#firewall-save-failed) |
| `Port 443: dein PC (...) wäre danach selbst ausgesperrt. Erst ihn oder sein Netz eintragen.` | [9.5](#firewall-save-failed) |
| `firewall.py start: Schnittstelle unbekannt: FW_INTERFACE in /etc/default/pacs-admin setzen` | [9.2](#firewall-not-effective) |

<a id="log-locations"></a>
## 2. Wo die Logs liegen

Die meisten Einträge verlangen, ein Log zu lesen. Diese Tabelle listet die Logs und den Befehl für jedes. Die Containernamen `ohif`,
`ohif-auth` und `arc` sind die Namen aus den Beispieldateien. Weichen die eigenen Namen ab, lassen sie sich mit
`docker ps --format '{{.Names}}'` auflisten.

| Log | Befehl | Inhalt |
|---|---|---|
| Hilfsdienst | `journalctl -u pacs-verwaltung -n 50 --no-pager` | Startfehler, Warnungen, die Bereitschaftszeile und die Wiederholungszeilen des Protokolls. |
| Firewall-Unit | `journalctl -u pacs-firewall -n 50 --no-pager` | Start und Stopp der Firewall-Regeln, beim Booten und später. |
| Übersichts-Job | `tail -n 20 /var/log/pacs-dashboard.log` | Fehlerausgabe von `dashboard-status.py`. Die Datei bleibt leer, solange alles in Ordnung ist. |
| Cron | `journalctl -u cron -n 50 --no-pager` | Ob cron den Übersichts-Job gestartet hat. |
| Platten-Assistent | `tail -n 50 /var/log/pacs-storage.log` | Die vollständige Ausgabe jedes Laufs von `pacs-storage.sh`. Der Dateiname ist die Einstellung `STORAGE_LOG`. |
| Eingangstür | `docker logs --tail 50 ohif` | Startfehler (`[emerg]`), `[error]`-Zeilen und die Zeilen zum Protokoll (`to syslog`). |
| nginx-Test | `docker exec ohif nginx -t` | Ein Syntaxtest der nginx-Konfiguration. Der Container muss laufen. |
| Login-Proxy | `docker logs --tail 50 ohif-auth` | Das Ergebnis jeder Anmeldung. |
| dcm4chee | `docker logs --tail 50 arc` | Der Start von WildFly und seine Fehler. |
| Firewall-Abweisungen | `journalctl -k --grep=pacs-sperre` | Kernel-Zeilen mit dem Präfix `pacs-sperre PORT:`. Nur der aktuelle Boot. |
| Dienste | `systemctl status pacs-verwaltung pacs-firewall --no-pager` | Der Zustand beider Units. |

Die Datei `server.log` von dcm4chee liegt in dem Ordner, den die Einstellung `ARC_LOG_DIR` in `/etc/default/pacs-admin` nennt. Die
Vorgabe ist `/var/local/dcm4chee-arc/wildfly/log/`. Die Admin-Seite liest die Absenderlisten aus dieser Datei.

Das Protokoll ist eine verschlüsselte Datenbank. Man liest sie mit dem Programm, das sie geschrieben hat:

```bash
set -a; . /etc/default/pacs-admin; set +a
python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse
```

Die erste Zeile lädt die Einstellungen, damit `PROTOKOLL_DB` und `PROTOKOLL_KEY` gelten, wenn sie geändert wurden. Das Programm gibt
für eine leere Datenbank nichts aus. Die Quellen sind `zugriffe` (Zugriffe), `ereignisse` (Ereignisse) und `admin`
([reference.de.md](reference.de.md#audit-read)).

<a id="trouble-install"></a>
## 3. Installation, Pakete und Hilfsdienst

Dieses Kapitel behandelt die Grundinstallation ([install.de.md](install.de.md)): die Prüfung mit `preflight.sh`, die Pakete, den
Protokoll-Schlüssel, den [Hilfsdienst](glossary.de.md#helper-service) und die Docker-Voraussetzungen.

<a id="preflight-fails"></a>
### 3.1 Die Prüfung preflight meldet [FAIL] oder [WARN]

**Was man sieht.** `preflight.sh` ([install.de.md](install.de.md#preflight)) endet mit `NICHT BEREIT: zuerst die [FAIL]-Zeilen beheben`
oder mit `BEREIT, mit Warnungen: die [WARN]-Zeilen lesen`.

**Ursache.** Das Skript hat auf dem Server etwas gefunden, das die Installation braucht und nicht findet, oder etwas, das falsch
aussieht. Das Skript liest nur. Es ändert nichts auf dem Server.

**So ist die Ausgabe zu lesen.** Das Skript gibt je Prüfung eine Zeile aus. `[ OK ]` braucht nichts. `[WARN]` braucht Aufmerksamkeit.
`[FAIL]` hält die Installation an: zuerst beheben. Unter einer `[WARN]`- oder `[FAIL]`-Zeile stehen ein Satz, der sagt, was die Zeile
bedeutet, und eine Zeile, die mit `Abhilfe:` beginnt. Der Exit-Code ist 0 (alles in Ordnung), 1 (nur Warnungen) oder 2 (mindestens ein
Fehler). Der Block „Meine Werte“ am Ende ist kein Problembericht: Er listet Namen und Pfade, die spätere Schritte brauchen.

**Abhilfe.** Das Skript als root ausführen. Die Optionen angeben, die zur Installation passen, damit es mehr prüft:

```bash
bash /opt/pacs-admin/deploy/tools/preflight.sh --lang de --host pacs.example.org
```

| Option | Was sie zusätzlich prüft |
|---|---|
| `--host NAME` | Ob der DNS-Name aufgelöst wird, und zwar zu einer Adresse dieses Servers. |
| `--cert FILE --key FILE` | Das TLS-Zertifikat und seinen Schlüssel: Zusammenpassen, Ablauf, Reihenfolge der Kette, Name, Rechte des Schlüssels. |
| `--dir /opt/ohif` | Den Ordner der Eingangstür: Platzhalter in den Dateien, die nginx-Dateien, die Mounts und die `env_file`-Einträge der Compose-Datei. |
| `--lang en` oder `--lang de` | Die Sprache der Ausgabe. Die Vorgabe folgt der Einstellung `LANG`. |

Das Skript gliedert die Prüfungen in Abschnitte: `System und Pakete`, `Docker und dcm4chee`, `Einstellungen des Rechners`, dann
`TLS-Zertifikat` (mit `--cert` und `--key`) und `Konfigurationsdateien` (mit `--dir`, oder wenn `/etc/default/pacs-admin` existiert).
Die Abschnittsnummern hängen von den angegebenen Optionen ab. Die eigene Zeile in den Tabellen suchen, tun, was die rechte Spalte sagt,
und das Skript noch einmal ausführen. Nach jeder Korrektur erneut ausführen.

**Abschnitt „System und Pakete“**

| Die Zeile beginnt mit | Was zu tun ist |
|---|---|
| `[WARN] nicht root` | Das Skript als root ausführen. Als anderer Benutzer kann es Docker, `iptables` und die Dateien von root nicht prüfen. |
| `[WARN] Repository: ... nicht /opt/pacs-admin` | Die systemd-Units und die Cron-Datei starten die Programme aus `/opt/pacs-admin`. Das Repository in diesen Ordner klonen oder den Pfad in den kopierten Dateien ändern ([3.6](#no-sockets) zeigt den Befehl). |
| `[WARN] systemctl ist da, aber systemd laeuft nicht (Container?)`, `[WARN] systemctl nicht gefunden` | Der Hilfsdienst und die Firewall sind systemd-Units. Die Installation auf einem normalen Debian-Server oder einer virtuellen Maschine ausführen. |
| `[WARN] /etc/os-release nicht lesbar`, `[WARN] Betriebssystem ... nicht getestet` | Die Anleitung ist auf Debian 12 und 13 getestet. Ubuntu hat dieselben Pakete, aber das hat niemand geprüft. Weitermachen und beheben, was die anderen Zeilen melden. |
| `[FAIL] SQLCipher: Paket ... passt zu diesem System, noch nicht installiert`, `[FAIL] SQLCipher: kein libsqlcipher-Paket in apt gefunden`, `[WARN] SQLCipher: apt-cache nicht gefunden` | Siehe [3.2](#libsqlcipher-missing). |
| `[FAIL] python3: /usr/bin/python3 ... ist zu alt` | Die Serverprogramme brauchen Python 3.7 oder neuer. Debian 12 und 13 haben es. |
| `[FAIL] python3: /usr/bin/python3 nicht gefunden (nur /usr/local/bin/python3)` | Die systemd-Units starten genau `/usr/bin/python3`. Ein Python in `/usr/local/bin` zählt nicht. Das Debian-Paket installieren: `apt-get install -y python3`. |
| `[FAIL] git nicht gefunden`, `curl`, `openssl` oder `ip` | Das Paket installieren, das die Zeile `Abhilfe:` nennt. Der Befehl `ip` steckt im Paket `iproute2`. |
| `[FAIL] cron: installiert, laeuft aber nicht`, `[FAIL] cron nicht gefunden` | Siehe [7.2](#cron-not-running). |
| `[WARN] iptables nicht gefunden`, `[WARN] journalctl nicht gefunden` | Nur der Reiter `Firewall` braucht sie. Siehe [9.4](#firewall-tools-missing). |
| `[WARN] Werkzeuge des Platten-Assistenten fehlen: ...` | Nur der optionale Platten-Assistent braucht sie. Die Pakete aus der Zeile `Abhilfe:` installieren, bevor man ihn benutzt. |

**Abschnitt „Docker und dcm4chee“**

| Die Zeile beginnt mit | Was zu tun ist |
|---|---|
| `[FAIL] docker nicht gefunden` | dcm4chee, nginx und der Login-Proxy laufen als Docker-Container. Docker installieren. Die Zeile `Abhilfe:` nennt das Debian-Paket und die Docker-Dokumentation. |
| `[FAIL] docker: installiert, aber der Dienst antwortete nicht innerhalb von 15 Sekunden`, `[FAIL] docker: installiert, aber der Dienst antwortet nicht`, `[WARN] docker: keine Berechtigung fuer den Docker-Dienst` | Docker starten (`systemctl start docker`), prüfen, dass `DOCKER_HOST` auf diesen Server zeigt, und das Skript als root ausführen. Das Skript überspringt die Prüfungen von dcm4chee, bis Docker antwortet. |
| `[WARN] docker compose: nur das alte Kommando docker-compose vorhanden`, `[FAIL] docker compose: Plugin nicht gefunden` | Siehe [3.8](#compose-version). |
| `[FAIL] kein dcm4chee-Archiv-Container gefunden` | Das Skript sucht ein Image namens `dcm4che/dcm4chee-arc-psql`. Die eigenen Container auflisten mit `docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.State}}'`. |
| `[FAIL] arc: NAME (IMAGE)` mit `-secure` im Image-Namen | Die Variante mit eigenem Keycloak-Login wird nicht unterstützt. Das Panel braucht das normale Image `dcm4che/dcm4chee-arc-psql`. |
| `[WARN] arc: NAME (IMAGE, exited)` | Der Archiv-Container läuft nicht. Starten: `docker start arc`. |
| `[WARN] mehr als ein Archiv-Container:` | Ein Panel spricht mit einem Archiv. Das Skript nimmt für die Werte, die es ausgibt, den ersten Container. |
| `[WARN] ARC_CONTAINER ist 'X', der Archiv-Container heisst aber 'Y'`, `[WARN] LDAP_CONTAINER ist ...` | Den echten Namen in `/etc/default/pacs-admin` eintragen. Die Zeile `Abhilfe:` gibt den Befehl. Danach `systemctl restart pacs-verwaltung` ausführen. |
| `[WARN] Compose-Verzeichnis von arc: unbekannt ...`, `[WARN] Compose-Verzeichnis von arc ... gibt es auf diesem Rechner nicht` | `PACS_DIR` in `/etc/default/pacs-admin` auf den Ordner setzen, der die `docker-compose.yml` von dcm4chee enthält. Die Kachel `Dienste` benutzt ihn. |
| `[WARN] Docker-Netzwerk von arc: nicht gefunden`, `[WARN] Docker-Netzwerk von arc: bridge (das Standardnetz)` | Siehe [3.7](#external-network-missing). |
| `[WARN] wildfly-Log-Verzeichnis: arc hat keinen Host-Mount fuer /opt/wildfly/standalone` | Der Reiter `Firewall` liest die Absenderlisten aus `server.log` auf dem Server. Ohne Mount bleiben die Listen leer. Siehe [6.5](#arc-log-dir). |
| `[WARN] wildfly-Log-Verzeichnis ... ARC_LOG_DIR` | Die Einstellung `ARC_LOG_DIR` nennt einen anderen Ordner als den, den `arc` benutzt. Siehe [6.5](#arc-log-dir). |
| `[WARN] weder LDAP_ROOTPASS noch LDAP_ROOTPASS_FILE ist im Container ldap gesetzt` | Nur der Platten-Assistent braucht das Passwort. Es als Änderung C eintragen ([modules.de.md](modules.de.md#edits-overview)). |
| `[WARN] kein LDAP-Container gefunden`, `[WARN] ldap: NAME (IMAGE, exited)` | Nur der Platten-Assistent braucht LDAP. |
| `[WARN] kein Datenbank-Container gefunden` | Nur zur Information. |

**Abschnitt „Einstellungen des Rechners“**

| Die Zeile beginnt mit | Was zu tun ist |
|---|---|
| `[WARN] /mnt/fs existiert nicht` | Nur der Platten-Assistent braucht den Ordner. Das Archiv kann seine Daten woanders halten. |
| `[WARN] N Mount(s) unter /mnt/fs, keiner heisst PACS-DataNN` | Der Platten-Assistent und die Kachel `Speicher` kennen nur Platten, deren Name aus der Einstellung `STORAGE_PREFIX` und zwei Ziffern besteht. |
| `[WARN] Mount-Propagation von /mnt/fs: private` | Nur der Platten-Assistent braucht einen geteilten Mount. Siehe [6.4](#arc-rslave-refused). |
| `[WARN] uid 101 gehoert auf diesem Rechner dem Konto '...'` | Siehe [3.5](#uid-101-taken). |
| `[WARN] Port 80 ist schon belegt`, `[WARN] Port 443 ist schon belegt` | nginx kann keinen Port veröffentlichen, den ein anderes Programm hält. Den Halter mit `ss -ltnp` finden. Die Warnung ist harmlos, wenn der Halter die Eingangstür dieses Panels selbst ist (ein zweiter Lauf nach der Installation). |
| `[WARN] keine Standardroute gefunden` | `firewall.py` braucht die Netzwerkschnittstelle nach außen. `FW_INTERFACE` in `/etc/default/pacs-admin` setzen ([9.2](#firewall-not-effective)). |
| `[WARN] /etc/localtime fehlt` | Die Compose-Dateien hängen die Datei in die Container ein. Die Zeitzone setzen: `timedatectl set-timezone Europe/Berlin` (das eigene Gebiet und den eigenen Ort nehmen). |
| `[FAIL] DNS: pacs.example.org wird nicht aufgeloest` | Browser, die Anmelde-Weiterleitung und das Zertifikat brauchen den Namen. Den DNS-Eintrag anlegen. Für einen Test eine Zeile in `/etc/hosts` ergänzen. |
| `[WARN] DNS: ... keine Adresse dieses Rechners` | In Ordnung hinter NAT, einem Lastverteiler oder einem Vorschaltproxy. Sonst erreichen die Benutzer einen anderen Rechner. |

**Abschnitt „TLS-Zertifikat“** (mit `--cert` und `--key`)

| Die Zeile beginnt mit | Was zu tun ist |
|---|---|
| `[FAIL] privater Schluessel (...) ist fuer das nginx des OHIF-Images nicht lesbar`, `[WARN] privater Schluessel ist fuer alle lesbar`, `[WARN] privater Schluessel ist fuer seine Gruppe lesbar` | Siehe [4.1](#tls-key-unreadable). |
| `[FAIL] Zertifikat: keine lesbare Datei`, `[FAIL] Schluesseldatei: keine lesbare Datei` | Das Skript als root ausführen. Schlüssel und Zertifikate darf oft nur root lesen. |
| `[FAIL] Zertifikat: keine PEM-Datei mit Zertifikat` | nginx will [PEM](glossary.de.md#pem)-Text, der mit `-----BEGIN CERTIFICATE-----` beginnt. Eine binäre `.crt`- oder `.cer`-Datei umwandeln: `openssl x509 -inform der -in FILE -out cert.pem`. |
| `[FAIL] Zertifikat abgelaufen`, `[WARN] Zertifikat laeuft bald ab` | Browser und API-Clients lehnen ein abgelaufenes Zertifikat ab. Es erneuern ([install.de.md](install.de.md#renew-certificate)). |
| `[FAIL] Zertifikat gilt NICHT fuer pacs.example.org` | Browser zeigen einen Namensfehler. Die Zeile nennt die Namen im ersten Zertifikat der Datei. Ein Zertifikat für den eigenen Namen beschaffen. |
| `[WARN] Zertifikat passt zu ... nur ueber den Common Name: kein subjectAltName`, `[WARN] Zertifikat hat keinen subjectAltName` | Aktuelle Browser lehnen ein Zertifikat ohne [subjectAltName](glossary.de.md#subject-alt-name) ab und zeigen `ERR_CERT_COMMON_NAME_INVALID`. Auch ein selbst signiertes Zertifikat braucht ihn. Das Zertifikat mit dem Namen im `subjectAltName` erstellen. |
| `[WARN] Kette: die N Zertifikate stehen nicht in der richtigen Reihenfolge` | nginx sendet die Datei unverändert. Zuerst das Serverzertifikat, dann die Zwischenzertifikate. Die Datei neu bauen: `cat server.pem intermediate.pem > fullchain.pem`. |
| `[WARN] Kette: die Datei enthaelt nur das Serverzertifikat` | Nutzt die CA ein [Zwischenzertifikat](glossary.de.md#intermediate-certificate), dieses hinter das Serverzertifikat hängen. Ohne es können manche Clients die Kette nicht prüfen. |
| `[WARN] selbst signiertes Zertifikat` | Browser warnen davor, und manche Identitätsanbieter lehnen es ab. Für einen Test ist es in Ordnung. |
| `[FAIL] privater Schluessel ist mit einer Passphrase geschuetzt` | nginx kann beim Start nicht nach einer Passphrase fragen. Die Passphrase entfernen: `openssl pkey -in KEY -out key-plain.pem`, danach `chmod 600 key-plain.pem`. |
| `[FAIL] privater Schluessel: nicht lesbar` | nginx erwartet einen unverschlüsselten Schlüssel im PEM-Format. |
| `[FAIL] Schluessel passt NICHT zum Zertifikat` | nginx startet mit so einem Paar nicht. Den Schlüssel nehmen, der zur Zertifikatsanfrage gehört. |
| `[FAIL] Schluessel passt nicht zum ersten Zertifikat, aber zu Zertifikat Nr. N der Datei` | Das Serverzertifikat muss in der Datei das erste sein. Die Datei umsortieren. |

**Abschnitt „Konfigurationsdateien“**

| Die Zeile beginnt mit | Was zu tun ist |
|---|---|
| `[FAIL] /etc/default/pacs-admin: Probleme: ...` | Die Shell (cron, Skripte) und systemd lesen die Datei und urteilen bei Kommentaren, Leerzeichen und Windows-Zeilenenden verschieden. Eine Zeile `NAME=wert` je Einstellung schreiben, kein `export`, und einen Wert mit Leerzeichen in Anführungszeichen setzen. Die Zeile `Abhilfe:` entfernt die Windows-Zeilenenden. Ein Syntaxfehler hält den Cron-Job an (die Meldung geht nach `/var/log/pacs-dashboard.log`, [7.2](#cron-not-running)). `pacs-storage.sh` führt zuerst `bash -n` für die Datei aus und bricht mit `HALT: /etc/default/pacs-admin hat einen Syntaxfehler (Meldung davor)` ab ([8.1](#disk-halt)). Siehe [reference.de.md](reference.de.md#env-file-rules). |
| `[FAIL] DATEI: ... CHANGE-ME` oder ein `<Platzhalter>` | Ein Wert wurde nie eingetragen. `CHANGE-ME` markiert jeden Wert, der geändert werden muss. Den Markierungs-Kommentar nach dem Eintragen löschen. |
| `[WARN] DATEI: Beispielwert(e) noch drin:` | Vermutlich ein kopierter Beispielwert, zum Beispiel `pacs.example.org`, der nicht durch den eigenen Namen oder die eigene ID ersetzt wurde. |
| `[WARN] ... keine nginx-, compose-, env- oder js-Dateien gefunden` | Falscher Ordner. Der Aufbau ist `/opt/ohif` mit `docker-compose.yml`, `nginx/`, `tls/`, `htpasswd/`, `ohif-auth.env` und `app-config.js`. |
| `[WARN] kein nginx-Ordner gefunden (nginx/pacs.conf)`, `[FAIL] nginx-Ordner ...: Dateien fehlen: ...` | Siehe [4.2](#nginx-wont-start). |
| `[FAIL] DATEI: Einhaengen QUELLE -> ZIEL: der nginx-Benutzer (uid 101) kann N seiner Dateien oder Ordner nicht lesen` | Dateien, die unter einer strengen `umask` (027 oder 077) entstanden sind, gehören nur root. Dann startet der Container nicht, oder die Seite antwortet mit einem Fehler. Den Befehl in der Zeile `Abhilfe:` ausführen. Er lautet `chmod -R o+rX ORDNER`, und für den TLS-Ordner `chmod 755 ORDNER && chmod 644 ORDNER/server.crt`. |
| `[FAIL] .../htpasswd/users: Besitzer root:root, Modus 600: der nginx-Worker (uid 101) kann sie nicht lesen`, `[WARN] ...: Modus M: jedes Konto dieses Rechners kann die Passwort-Hashes lesen` | Siehe [4.4](#htpasswd-403-500). |
| `[WARN] DATEI: Einhaenge-Quelle ... gibt es nicht (fuer ...)` | `docker compose` würde einen leeren Ordner dieses Namens anlegen, Besitzer root. Der Dienst hinter dem Mount funktioniert dann nicht. Die Datei anlegen oder den Pfad in der Compose-Datei korrigieren. |
| `[FAIL] DATEI: Einhaengen QUELLE -> ZIEL unvollstaendig, es fehlt: ...` | Der Container würde ohne diesen Inhalt starten oder sofort scheitern. Jede Anfrage würde mit einem Fehler enden. Die fehlenden Teile kopieren ([install.de.md](install.de.md#nginx-files)). |
| `[FAIL] DATEI: env_file ... gibt es nicht (oder es ist ein Ordner)` | `docker compose` startet ohne sie nicht. Die Compose-Datei nennt am Anfang, was in der Datei steht. |
| `[FAIL] ...: fehlt: ...` oder `leer: ...` für `ohif-auth.env` | `oauth2-proxy` startet ohne Client-ID, Client-Geheimnis und Cookie-Geheimnis nicht. Je eine Zeile `NAME=wert` schreiben, ohne Leerzeichen um `=` ([login.de.md](login.de.md#login-oauth2-env)). |
| `[WARN] ...env: Modus M: andere Konten dieses Rechners koennen sie lesen` | Die Datei enthält Geheimnisse (Client-Geheimnis, Cookie-Geheimnis). `chmod 600` dafür ausführen. |

> **Prüfen**
>
> ```bash
> bash /opt/pacs-admin/deploy/tools/preflight.sh --lang de --host pacs.example.org | tail -n 4
> echo "exit code: ${PIPESTATUS[0]}"
> ```
>
> Erwartet: Die Zusammenfassung lautet `Ergebnis: ... 0 Fehler` und eine der Zeilen `BEREIT: alle Pruefungen bestanden` oder
> `BEREIT, mit Warnungen: die [WARN]-Zeilen lesen`. Der Exit-Code ist 0 oder 1. Beispiel (die Zahlen weichen ab):
>
> ```text
> Ergebnis: 30 ok, 1 Warnung(en), 0 Fehler
> BEREIT, mit Warnungen: die [WARN]-Zeilen lesen
> exit code: 1
> ```
>
> Die letzten Zeilen der echten Ausgabe nennen auch die Optionen, die nicht angegeben wurden. Bleibt eine `[FAIL]`-Zeile stehen, die
> zugehörige Zeile oben noch einmal durcharbeiten.

<a id="libsqlcipher-missing"></a>
### 3.2 Die SQLCipher-Bibliothek fehlt

**Was man sieht.** Eines von diesen:

- Ein Programm gibt diese Zeile aus und endet mit dem Exit-Status 1. Ein Programm, das man von Hand startet, gibt sie hinter
  seinem eigenen Namen aus, hier `pacsdb.py:`.

```text
pacsdb.py: libsqlcipher nicht gefunden. Debian 13: apt install libsqlcipher1, Debian 12 und aelter: apt install libsqlcipher0 (Release: cat /etc/os-release, Paketname: apt-cache search sqlcipher; docs/install.de.md#audit-key). SQLCipher library not found: install libsqlcipher1 (Debian 13) or libsqlcipher0 (Debian 12 and older)
```

- Der Hilfsdienst gibt denselben Text hinter `verwaltung-dienst.py:` in seinem Journal aus. Er endet, und systemd startet ihn alle
  5 Sekunden neu. Die Sockets in `/run/pacs-admin/` bleiben nicht bestehen, und die Admin-Seite antwortet für `/admin/dienst/` mit 502.
- `preflight.sh` gibt `[FAIL] SQLCipher: Paket libsqlcipher1 (VERSION) passt zu diesem System, noch nicht installiert` aus.

**Ursache.** Das [Protokoll](glossary.de.md#audit-log) liegt in einer verschlüsselten Datenbank. [SQLCipher](glossary.de.md#sqlcipher)
ist die Bibliothek, die sie verschlüsselt. Die Programme `verwaltung-dienst.py` und `pacsdb.py` laden sie beim Start. Das
Debian-Paket heißt je nach Release anders.

**Abhilfe.** Das eigene Release feststellen, die Paketnamen ansehen und das passende Paket installieren:

```bash
. /etc/os-release; echo "$PRETTY_NAME"
apt-cache search sqlcipher
```

Debian 13 nutzt `libsqlcipher1`. Debian 12 und älter nutzen `libsqlcipher0`.

```bash
apt-get install -y libsqlcipher1
systemctl restart pacs-verwaltung
```

Auf Debian 12 `libsqlcipher0` statt `libsqlcipher1` schreiben. Findet `apt-cache search` kein Paket, zuerst `apt-get update` ausführen.

> **Prüfen**
>
> ```bash
> python3 /opt/pacs-admin/server/pacsdb.py test
> systemctl is-active pacs-verwaltung
> ```
>
> Erwartet: Die Zeile des Selbsttests beginnt mit `Selbsttest ok` (Selbsttest bestanden), und der Dienst ist `active`. Beispielausgabe
> auf Debian 13 (die Version weicht ab):
>
> ```text
> Selbsttest ok: schreiben, lesen, Datei ohne Klartext, falscher Schluessel und fremde Datei abgewiesen, Format 3 (Seitengroesse 1024) und Bibliotheksstandard (4096) lesbar, SQLCipher 4.6.1 community
> active
> ```
>
> Schlägt der Selbsttest weiterhin fehl, siehe [3.4](#pacsdb-selftest).

<a id="audit-key-mismatch"></a>
### 3.3 Der Protokoll-Schlüssel oder die Protokoll-Datenbank passt nicht

**Was man sieht.** Ein Programm, das man von Hand startet, gibt eine dieser Zeilen aus und endet mit dem Exit-Status 1. Der Text
hinter `pacsdb.py:` ist die Meldung.

| Meldung | Bedeutung |
|---|---|
| `/var/lib/pacs-protokoll/protokoll.db: file is not a database. Schluessel falsch, keine SQLCipher-Datei oder eine Datei im Format von SQLCipher 4, die libsqlcipher 3.x nicht oeffnet (hier SQLCipher 3.4.1), siehe docs/install.de.md#audit-key` | Die Datenbank lässt sich mit diesem Schlüssel und dieser Bibliothek nicht öffnen. Bei SQLCipher 3.x lautet der erste Teil `file is encrypted or is not a database`. |
| `Schluessel in /etc/pacs-protokoll.key ist nicht 64 Hex-Zeichen (kleingeschrieben)` | Die Schlüsseldatei enthält nicht genau 64 Zeichen aus `0` bis `9` und `a` bis `f`. |
| `[Errno 2] No such file or directory: '/etc/pacs-protokoll.key'` | Die Schlüsseldatei fehlt, oder die Einstellung `PROTOKOLL_KEY` nennt einen anderen Pfad. |
| `[Errno 13] Permission denied: '/etc/pacs-protokoll.key'` | Das Programm läuft nicht als root. Nur root darf den Schlüssel lesen. |

Der Hilfsdienst läuft weiter, wenn die Datenbank nicht nutzbar ist. Er hält die Zeilen, die nginx sendet, im Arbeitsspeicher und
versucht es alle 10 Sekunden erneut. Das Journal zeigt diese zwei Zeilen. `<error>` steht für eine der Meldungen oben.

```text
Achtung: Protokoll-Datenbank nicht nutzbar, die Zeilen von nginx werden zurueckgehalten und alle 10 s neu abgelegt: <error>
Protokoll nicht abgelegt (5 Zeilen), neuer Versuch in 10 s: <error>
```

Die erste Zeile sagt: Die Protokoll-Datenbank ist nicht nutzbar, die Zeilen von nginx werden zurückgehalten und alle 10 Sekunden
neu abgelegt. Die zweite Zeile sagt, dass 5 Zeilen nicht abgelegt wurden und der nächste Versuch in 10 Sekunden folgt. Solange die
Datenbank nicht nutzbar ist, zeigt der Reiter `Protokoll` die Meldung `Protokoll: HTTP 503`.

**Ursache.** Eine von diesen:

1. Die Schlüsseldatei wurde ersetzt oder ging verloren. Ein zweiter Lauf von `openssl rand` schreibt einen neuen Schlüssel, eine
   Wiederherstellung von `/etc` kann die Datei auslassen, und eine Kopie von einem anderen Server bringt einen anderen Schlüssel mit.
   Die Datenbank ist mit dem alten Schlüssel verschlüsselt.
2. Die Schlüsseldatei hat die falsche Form. Die Programme ignorieren Leerraum und Zeilenumbrüche an beiden Enden. Einen Schlüssel
   mit Großbuchstaben, anderen Zeichen oder anderer Länge weisen sie ab.
3. Die Datenbankdatei liegt im Format von SQLCipher 4, und dieser Server hat `libsqlcipher` 3.x (Debian 12). Das passiert, wenn
   eine Datei von einem Debian-13-Server wiederhergestellt wird oder wenn man auf ein älteres Release zurückgeht. Neue Dateien
   nutzen das Format 3, das beide Versionen öffnen. Ein Upgrade von Debian 12 auf Debian 13 funktioniert weiter. Einen Umwandler
   zwischen den Formaten gibt es nicht.
4. Die Datei ist keine SQLCipher-Datenbank oder ist beschädigt.

**Abhilfe.** Zuerst die Schlüsseldatei ansehen. Die eigenen Einstellungen laden, damit die Befehle die eigenen Pfade nutzen:

```bash
set -a; . /etc/default/pacs-admin; set +a
ls -l /etc/pacs-protokoll.key
grep -Eq '^[0-9a-f]{64}$' /etc/pacs-protokoll.key && echo key ok
```

Die Datei sollte 65 Bytes haben, den Besitzer `root` und den Modus `-rw-------`. `key ok` sollte erscheinen. Ein Schlüssel, der unter
Windows bearbeitet wurde, kann auf einen Wagenrücklauf (Carriage Return) enden. Die Programme akzeptieren das, der Test mit `grep`
nicht. Entfernen mit `sed -i 's/\r$//' /etc/pacs-protokoll.key`.

Dann den passenden Fall wählen:

- **Es gibt eine Sicherung des Schlüssels** ([install.de.md](install.de.md#backup-audit-key)). Den Schlüssel zurückspielen. Der Hilfsdienst
  findet beim nächsten Versuch den richtigen Schlüssel, innerhalb von 10 Sekunden und ohne Neustart. Danach legt er die Zeilen ab,
  die er zurückgehalten hat.

  ```bash
  (umask 077; cat /path/to/saved-key > /etc/pacs-protokoll.key)
  ```

- **Die Datei hat das Format 4, und dieser Server hat `libsqlcipher` 3.x.** Die Datei auf einem Server mit Debian 13 lesen. Die Datei
  und den Schlüssel dorthin kopieren und ausführen:

  ```bash
  PROTOKOLL_DB=/path/to/protokoll.db PROTOKOLL_KEY=/path/to/key python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse
  ```

  Für diesen Server braucht man eine neue Datenbank ([neue Dateien beginnen](#audit-key-new), unten).

- <a id="audit-key-new"></a>**Der Schlüssel ist verloren, und es gibt keine Sicherung.** Niemand kann die alten Ereignisse lesen. Die
  alten Dateien aufheben und neue mit einem neuen Schlüssel beginnen. Die drei Befehle in dieser Reihenfolge ausführen, damit der
  Hilfsdienst nie neue Zeilen mit dem falschen Schlüssel in die alte Datei schreibt:

  ```bash
  mkdir -p /root/protokoll-alt
  mv /etc/pacs-protokoll.key /root/protokoll-alt/pacs-protokoll.key
  (umask 077; openssl rand -hex 32 > /etc/pacs-protokoll.key)
  mv /var/lib/pacs-protokoll/protokoll.db* /root/protokoll-alt/
  ```

  Das `*` verschiebt die Datenbank und ihre Hilfsdateien `protokoll.db-wal` und `protokoll.db-shm`. Beim nächsten Versuch legt der
  Hilfsdienst eine neue Datenbank mit dem neuen Schlüssel an und legt die zurückgehaltenen Zeilen darin ab.

> **Warnung**
>
> Die alten Ereignisse bleiben in `/root/protokoll-alt`. Niemand kann sie ohne den zugehörigen Schlüssel lesen, deshalb den Ordner
> aufbewahren. `pacs-verwaltung` nicht neu starten, solange der Dienst Zeilen zurückhält: Ein Neustart verwirft sie. Der neue
> Schlüssel braucht sofort eine Sicherung ([install.de.md](install.de.md#backup-audit-key)). Zum Zurückgehen den alten Schlüssel und
> die alten Dateien an ihre Plätze zurückschieben. Die Zeilen, die die neue Datenbank enthält, gehen dann verloren, deshalb vorher
> die neuen Dateien wegkopieren.

> **Prüfen**
>
> ```bash
> set -a; . /etc/default/pacs-admin; set +a
> grep -Eq '^[0-9a-f]{64}$' /etc/pacs-protokoll.key && echo key ok
> python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse > /dev/null && echo "key and database ok"
> journalctl -u pacs-verwaltung -n 5 --no-pager
> ```
>
> Erwartet: `key ok` und `key and database ok`. Das Journal zeigt keine neue Zeile `Protokoll nicht abgelegt`. Das Programm gibt für
> eine leere Datenbank nichts aus. Nennt `PROTOKOLL_DB` einen falschen Pfad, legt das Programm dort eine neue leere Datenbank an und
> meldet ebenfalls `key and database ok`. Deshalb auch den Pfad in der Einstellungsdatei prüfen.

<a id="pacsdb-selftest"></a>
### 3.4 Der Selbsttest von pacsdb.py schlägt fehl

**Was man sieht.** `python3 /opt/pacs-admin/server/pacsdb.py test` gibt keine Zeile aus, die mit `Selbsttest ok` beginnt. Stattdessen
erscheint ein Python-Traceback. Die letzte Zeile nennt den Fehler.

**Was der Selbsttest ist.** Er schreibt in einem temporären Ordner eine Wegwerf-Datenbank mit einem Wegwerf-Schlüssel. Er liest die
Daten zurück und prüft, dass die Bibliothek wirklich verschlüsselt, einen falschen Schlüssel und eine fremde Datei abweist und die
Formate 3 und 4 öffnet. Er berührt nie die Schlüsseldatei oder die Datenbank des Servers. Er sagt also etwas über die Bibliothek,
nicht über den Schlüssel. Zum Schlüssel siehe [3.3](#audit-key-mismatch).

**Ursache und Abhilfe.** Die letzte Zeile des Tracebacks lesen:

| Letzte Zeile | Ursache und Abhilfe |
|---|---|
| `AssertionError: Datei nicht verschluesselt` | Die Datei zeigt den Text der Daten oder den Kopf einer einfachen SQLite-Datei. Die Bibliothek ignoriert den Schlüssel, ist also kein SQLCipher. Das Debian-Paket erneut installieren (`apt-get install --reinstall libsqlcipher1`, auf Debian 12 `libsqlcipher0`) und eine selbst gebaute Bibliothek dieses Namens entfernen. |
| `AssertionError: falscher Schluessel oder fremde Datei wurde angenommen: ...` | Die Bibliothek hat eine Datei mit einem falschen Schlüssel geöffnet. Die Bibliothek verschlüsselt nicht, dieselbe Ursache wie in der Zeile darüber. |
| `AssertionError: Format 3 und Format 4 lassen sich nicht unterscheiden` | Die Bibliothek unterscheidet die zwei Dateiformate nicht, wie es SQLCipher 4 tut. Das Debian-Paket des eigenen Releases nutzen. |
| `AssertionError: ungueltiger Schluessel wurde angenommen` | Das Programm hat einen Schlüssel angenommen, der nicht aus 64 Hex-Zeichen besteht. Die Datei `pacsdb.py` wurde geändert oder ist beschädigt. Mit dem Repository vergleichen: `git -C /opt/pacs-admin status`. |
| `AssertionError` ohne Text oder mit zwei Zahlen in Klammern | Die Bibliothek verhält sich auf eine Weise, die diese Seite nicht kennt. Die ganze Ausgabe und die Ausgabe von `apt-cache policy libsqlcipher1 libsqlcipher0` aufbewahren und melden. |
| `PermissionError` oder `OSError` mit einem Pfad in `/tmp` | Das Programm kann seinen temporären Ordner nicht anlegen. Den freien Platz und die Rechte von `/tmp` prüfen. |

> **Prüfen**
>
> ```bash
> python3 /opt/pacs-admin/server/pacsdb.py test
> ```
>
> Erwartet: eine Zeile, die mit `Selbsttest ok` beginnt. Beispiel auf Debian 12 (das Zeilenende hängt von der Version ab):
>
> ```text
> Selbsttest ok: schreiben, lesen, Datei ohne Klartext, falscher Schluessel und fremde Datei abgewiesen, Format 3 (Seitengroesse 1024) und Bibliotheksstandard (1024) lesbar, SQLCipher 3.4.1
> ```
>
> Auf Debian 13 endet die Zeile mit `SQLCipher 4.6.1 community`, und die Zahl in der zweiten Klammer ist dort `4096`.

<a id="uid-101-taken"></a>
### 3.5 Ein Konto auf dem Server hat die uid 101

**Was man sieht.** Eines von diesen:

- `getent passwd 101` oder `getent group 101` gibt eine Zeile aus. Die Installationsanleitung erwartet keine Ausgabe
  ([install.de.md](install.de.md#helper-service)).
- Das Journal des Hilfsdienstes enthält diese Warnung. Der Dienst startet trotzdem.

  ```text
  Achtung: PACS_SOCKET_UID 101 ist auf dem Host das Konto <name>. Jeder Prozess dieses Kontos kann das Protokoll lesen und die Firewall aendern. Ist das nicht nginx, siehe docs/install.de.md#helper-service.
  ```

- `preflight.sh` gibt `[WARN] uid 101 gehoert auf diesem Rechner dem Konto '<name>'` aus.

**Ursache.** nginx im Container führt seine Worker-Prozesse mit der [uid](glossary.de.md#uid) 101 aus. Der Hilfsdienst übergibt seine
zwei [Unix-Sockets](glossary.de.md#unix-socket) an diese uid, damit nginx sie nutzen kann. Der Modus 0600 und die uid sind der
einzige Schutz des Dienstes. Jeder Prozess mit dieser uid kann den Dienst wie root nutzen: das Protokoll lesen, die Firewall
ausschalten und Platten einrichten. Auf dem Server kann die uid 101 einem anderen Konto gehören. Auf Debian 12 ist es oft ein
Systemkonto wie `messagebus`. Die Warnung oben meldet diesen Fall und hält den Dienst nicht an.

**Abhilfe.** Zuerst nachsehen, welches Konto es ist und ob es Programme ausführt:

```bash
getent passwd 101
ps -u 101 -o pid,user,comm
```

Dann entscheiden:

1. **Ein einfaches Systemkonto.** Niemand meldet sich damit an, und kein Programm anderer Leute läuft darunter. Das Risiko ist
   klein. Die Warnung hinnehmen und nichts ändern.
2. **Andere Programme laufen unter dem Konto.** Die Programme von dem Konto fernhalten oder das Konto mit den üblichen Werkzeugen auf eine
   andere uid verlegen. Der Hilfsdienst übergibt die Sockets an `PACS_SOCKET_UID`. `PACS_SOCKET_UID` nur dann auf einen anderen Wert
   setzen, wenn die Worker-Prozesse von nginx wirklich diese uid nutzen. Für nginx auf dem Server selbst (Debian) ist die uid 33
   (`www-data`) ([reference.de.md](reference.de.md#permissions)). Eine falsche uid ergibt ein 502 auf `/admin/dienst/`.

Nach einer Änderung von `PACS_SOCKET_UID` in `/etc/default/pacs-admin` den Dienst neu starten:

```bash
systemctl restart pacs-verwaltung
```

> **Prüfen**
>
> ```bash
> ls -ln /run/pacs-admin/
> ```
>
> Erwartet: zwei Sockets. Die dritte Spalte zeigt die gewählte uid, zum Beispiel `101`. Beispiel:
>
> ```text
> total 0
> srw------- 1 101 0 0 Oct 13 14:50 protokoll.sock
> srw------- 1 101 0 0 Oct 13 14:50 verwaltung.sock
> ```
>
> Die Form `ls -l` zeigt dieselben zwei Zeilen mit dem Kontonamen und dem Gruppennamen statt der Zahlen.

<a id="no-sockets"></a>
### 3.6 Der Hilfsdienst startet nicht, oder der Ordner /run/pacs-admin ist leer

**Was man sieht.** `systemctl is-active pacs-verwaltung` gibt nicht `active` aus, oder `ls -l /run/pacs-admin/` zeigt keine Sockets.
Die Admin-Seite antwortet unter `/admin/dienst/` mit 502 ([7.1](#admin-dienst-502)).

**Ursache.** Der Dienst bricht beim Start ab und nennt den Grund in einer Zeile seines Journals. Das Journal lesen:

```bash
journalctl -u pacs-verwaltung -n 30 --no-pager
```

Jede Zeile beginnt mit dem Programmnamen `verwaltung-dienst.py:`. Der Text danach nennt die Ursache:

| Meldung | Ursache und Abhilfe |
|---|---|
| `libsqlcipher nicht gefunden. ...` | Siehe [3.2](#libsqlcipher-missing). |
| `PACS_SOCKET_UID=abc ist keine ganze Zahl ohne fuehrende Null mit hoechstens 10 Stellen (/etc/default/pacs-admin)` | Der Hilfsdienst liest beim Start eine Zahl: `PACS_SOCKET_UID`. Der Wert muss eine ganze Zahl ohne führende Null und mit höchstens 10 Stellen sein. Die Zeile in `/etc/default/pacs-admin` korrigieren ([reference.de.md](reference.de.md#env-file-rules)). |
| `PACS_SOCKET_UID=N ist keine gueltige uid (/etc/default/pacs-admin)` | Die uid muss eine ganze Zahl von 0 bis 4294967294 sein. |
| `NAME=path ist zu lang (N Bytes, Unix-Sockets erlauben hoechstens 107)` | Der Pfad eines Sockets ist länger als 107 Bytes. Einen kürzeren Pfad nehmen. |
| `laeuft schon, auf PATH lauscht ein Dienst (systemctl status pacs-verwaltung). Nicht von Hand starten, solange der Dienst laeuft.` | Eine zweite Kopie des Programms läuft, gestartet von der Unit oder von Hand. Das Programm nicht von Hand starten, solange die Unit läuft. Die Kopie mit `pgrep -af verwaltung-dienst.py` finden und die beenden, die nicht von der Unit stammt. |
| `keine Berechtigung (...). Der Dienst muss als root laufen (pacs-verwaltung.service).` | Das Programm läuft nicht als root. Es mit `systemctl start pacs-verwaltung` starten, nicht aus der Shell als anderer Benutzer. |
| `Socket nicht anlegbar: ...` | Das Programm kann die Socket-Datei nicht anlegen. Der Text nach dem Doppelpunkt nennt den Grund, zum Beispiel ein schreibgeschütztes Dateisystem. |

Die drei Einstellungen `STORAGE_MIN_GB`, `STORAGE_FREE_GB` und `STORAGE_WARN_GB` halten den Hilfsdienst nicht an. Jede nimmt eine
ganze Zahl ohne führende Null und mit höchstens 6 Stellen. Enthält eine etwas anderes, bricht `dashboard-status.py` oder
`pacs-storage.sh` mit einer Meldung ab, die mit `ohne fuehrende Null mit hoechstens 6 Stellen` weitergeht. Beispiel:

```text
dashboard-status.py: STORAGE_WARN_GB=300GB ist keine ganze Zahl ohne fuehrende Null mit hoechstens 6 Stellen (/etc/default/pacs-admin)
```

Der Platten-Assistent gibt denselben Text hinter `HALT:` aus ([8.1](#disk-halt)). Der Cron-Job schreibt ihn nach
`/var/log/pacs-dashboard.log` ([7.2](#cron-not-running)).

Zwei weitere Ursachen haben keine solche Zeile:

- `systemctl status pacs-verwaltung` zeigt `status=203/EXEC`. systemd kann `/usr/bin/python3` nicht starten. Ein Python in
  `/usr/local/bin` zählt nicht. `command -v python3` muss `/usr/bin/python3` ausgeben. Das Debian-Paket `python3` installieren.
- Das Repository liegt in einem anderen Ordner als `/opt/pacs-admin`. Die Units und die Cron-Datei nennen den alten Pfad. Python
  meldet dann, dass es das Skript nicht öffnen kann. Den Pfad einmal in den kopierten Dateien ändern:

  ```bash
  sed -i 's|/opt/pacs-admin|/srv/pacs-admin|g' /etc/systemd/system/pacs-*.service /etc/cron.d/pacs-dashboard
  systemctl daemon-reload && systemctl restart pacs-verwaltung
  ```

  Denselben Ordner in der Compose-Datei von nginx als Mount eintragen. Ohne die Änderung schlägt `systemctl stop pacs-firewall`
  fehl, und die Notbremse der Firewall wirkt nicht ([9.1](#firewall-lockout-brake)).

Ist der Dienst `active` und sind die Sockets vorhanden, antwortet nginx aber weiter mit 502, dann wurde der Container gestartet,
bevor der Ordner existierte. Ein Container sieht einen Ordner nicht, der nach seinem Start angelegt wurde:

```bash
docker restart ohif
```

Nach einem Neustart des Servers ist der Ordner `/run/pacs-admin` leer, bis der Dienst gestartet ist. Das ist normal.

> **Prüfen**
>
> ```bash
> systemctl is-active pacs-verwaltung
> ls -l /run/pacs-admin/
> journalctl -u pacs-verwaltung -n 5 --no-pager
> ```
>
> Erwartet: `active`, zwei Sockets mit der uid `101` (oder der eigenen `PACS_SOCKET_UID`) als Besitzer und dem Modus `srw-------` und
> eine Bereit-Zeile im Journal. Die Journalzeile beginnt mit Datum, Rechnername und Programmname. Beispiel:
>
> ```text
> active
> total 0
> srw------- 1 101 root 0 Oct 13 14:50 protokoll.sock
> srw------- 1 101 root 0 Oct 13 14:50 verwaltung.sock
> pacs-verwaltung bereit: /run/pacs-admin/verwaltung.sock (HTTP) und /run/pacs-admin/protokoll.sock (Protokoll), Besitzer uid 101
> ```

<a id="external-network-missing"></a>
### 3.7 Docker findet das Netz von dcm4chee nicht

**Was man sieht.** `docker compose up -d` im Ordner der Eingangstür (hier `/opt/ohif`) bricht mit diesem Fehler ab. Der Name ist der
aus der eigenen Compose-Datei.

```text
network dcm4chee-arc_default declared as external, but could not be found
```

`preflight.sh` kann früher warnen: `[WARN] Docker-Netzwerk von arc: nicht gefunden` oder `[WARN] Docker-Netzwerk von arc: bridge (das
Standardnetz)`.

**Ursache.** Die Compose-Datei der Eingangstür tritt dem Docker-Netz des dcm4chee-Projekts bei. Das Netz ist für diese Datei
[extern](glossary.de.md#external-network): Ein anderes Projekt besitzt es. Es muss existieren, bevor nginx startet, und der Name in
der Compose-Datei muss genau stimmen. Die Gründe sind: dcm4chee ist nicht gestartet, der Name in der Datei weicht vom echten Namen
ab, oder `docker compose down` im dcm4chee-Ordner hat das Netz entfernt. Wurde `arc` mit `docker run` gestartet, liegt er im
Standardnetz `bridge`. Container darin finden einander nicht über den Namen, deshalb findet nginx `arc` nicht.

**Abhilfe.** dcm4chee starten, falls er aus ist:

```bash
cd /opt/dcm4chee-arc
docker compose up -d
```

Den echten Namen des Netzes von `arc` nachsehen:

```bash
docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' arc
```

Der Befehl gibt den Namen aus, oder mehrere Namen, durch ein Leerzeichen getrennt. Den Namen in die Compose-Datei der Eingangstür
schreiben, in die Zeile mit der Markierung `CHANGE-ME`:

```yaml
networks:
  default:
    name: dcm4chee-arc_default   # the name that the command printed
    external: true
```

Liegt `arc` im Netz `bridge`, dcm4chee über seine Compose-Datei starten. Die Datei legt ein eigenes Netz an.

> **Prüfen**
>
> ```bash
> cd /opt/ohif
> docker compose up -d
> docker ps --format '{{.Names}}  {{.Status}}' | grep '^ohif'
> ```
>
> Erwartet: `docker compose up -d` endet ohne den Fehler, und `ohif` zeigt `Up`. Beispiel (die Zeit weicht ab):
>
> ```text
> ohif  Up 5 seconds
> ```

<a id="compose-version"></a>
### 3.8 Docker Compose fehlt oder ist zu alt

**Was man sieht.** `preflight.sh` gibt `[FAIL] docker compose: Plugin nicht gefunden` aus oder `[WARN] docker compose: nur das alte
Kommando docker-compose vorhanden`. Oder `docker compose` funktioniert auf dem Server gar nicht.

**Ursache.** Die Beispieldateien und alle Befehle dieser Anleitung nutzen die Form `docker compose` (mit Leerzeichen). Das ist das
Plugin Compose v2. Der alte Befehl `docker-compose` (mit Bindestrich) ist Compose v1. Er ist ein eigenes Programm, und die
Anleitung unterstützt ihn nicht. Die Namen der Debian-Pakete unterscheiden sich je nach Release.

**Abhilfe.** Compose v2 installieren:

| Release | Was zu installieren ist |
|---|---|
| Debian 13 | `apt-get install -y docker-compose` (dieses Paket ist Compose v2) |
| Debian 12 | Das Paket `docker-compose-plugin` aus dem Docker-Repository ([Docker-Dokumentation für Debian](https://docs.docker.com/engine/install/debian/)). Das Debian-Paket `docker-compose` ist Compose v1 und funktioniert nicht. |

> **Prüfen**
>
> ```bash
> docker compose version
> ```
>
> Erwartet: eine Zeile, die mit `Docker Compose version v2` beginnt. Beispiel (die Version weicht ab):
>
> ```text
> Docker Compose version v2.32.0
> ```
>
> Beginnt die Zeile mit `v1` oder ist der Befehl unbekannt, ist der alte Befehl weiterhin der einzige auf dem Server.

<a id="trouble-front-door"></a>
## 4. Eingangstür (nginx)

Dieses Kapitel behandelt den nginx-Container `ohif` und seine Dateien ([install.de.md](install.de.md#nginx-files)): Startfehler, den
TLS-Schlüssel, die Passwortdateien der Anmeldung `basic` und die Client-Adresse hinter einem Proxy. Probleme mit der Anmeldung bei
einem Identitätsanbieter stehen in [Kapitel 5](#trouble-login).

<a id="tls-key-unreadable"></a>
### 4.1 nginx kann den TLS-Schlüssel oder das Zertifikat nicht lesen

**Was man sieht.** Die Seite öffnet sich nicht. `docker ps` zeigt `Restarting` für den Container `ohif`. `docker logs --tail 20 ohif`
wiederholt eine dieser Zeilen. Jede Zeile beginnt mit Datum und Uhrzeit, und die Zahlen nach `[emerg]` weichen ab. Ein `...` steht
für das Ende einer langen Zeile.

```text
[emerg] 1#1: cannot load certificate key "/etc/nginx/tls/server.key": BIO_new_file() failed (SSL: error:8000000D:system library::Permission denied:calling fopen(/etc/nginx/tls/server.key, r) ...
[emerg] 1#1: cannot load certificate "/etc/nginx/tls/server.crt": BIO_new_file() failed (SSL: error:8000000D:system library::Permission denied:calling fopen(/etc/nginx/tls/server.crt, r) ...
[emerg] 1#1: cannot load certificate "/etc/nginx/tls/server.crt": BIO_new_file() failed (SSL: error:80000002:system library::No such file or directory:calling fopen(/etc/nginx/tls/server.crt, r) error:10000080:BIO routines::no such file)
```

Die erste Zeile sagt, dass nginx den Schlüssel nicht lesen darf. Die zweite Zeile sagt dasselbe für das Zertifikat oder für den Ordner
`tls/`. Die dritte Zeile sagt, dass die Datei nicht existiert.

**Ursache.** nginx liest das Zertifikat und den Schlüssel einmal, wenn sein Hauptprozess startet. Im OHIF-Image läuft dieser Prozess
nicht als root, sondern mit der [uid](glossary.de.md#uid) 101. Ein Schlüssel, den nur root lesen kann, hält ihn an. Das einfache Image
`nginx:1.30` und nginx auf dem Server starten den Hauptprozess als root, und root kann jede Datei lesen. Auch der Ordner `tls/` muss
lesbar sein. Eine Datei, die nicht existiert, hat andere Gründe: Der Name ist nicht genau `server.crt` oder `server.key`, oder die
Compose-Datei hängt den Ordner nicht ein. Für eine Mount-Quelle, die nicht existiert, legt Docker einen leeren Ordner an.

| Image | Rezepte | Der Hauptprozess läuft als | Ein Schlüssel, der funktioniert | Ein Schlüssel, der nginx anhält |
|---|---|---|---|---|
| OHIF-Image `ohif/app` | `oauth2`, `basic` | uid 101 | Besitzer `root`, Gruppe 101, Modus 640 | `root:root` mit Modus 600 oder 640 |
| Einfaches Image `nginx:1.30`, nginx auf dem Server | `adminonly`, nginx auf dem Host | root | `root:root` mit Modus 600 | keiner |

**Abhilfe.** Das eigene Image in der Compose-Datei finden. Das Rezept `oauth2` oder `basic` nutzt `ohif/app`. Das Rezept `adminonly`
nutzt `nginx`.

```bash
grep -n 'image:' /opt/ohif/docker-compose.yml
```

Für das OHIF-Image den Schlüssel der Gruppe 101 geben:

```bash
chown root:101 /opt/ohif/tls/server.key && chmod 640 /opt/ohif/tls/server.key
```

Für das einfache Image und für nginx auf dem Server den Schlüssel root allein vorbehalten:

```bash
chown root:root /opt/ohif/tls/server.key && chmod 600 /opt/ohif/tls/server.key
```

Für jedes Image müssen der Ordner und das Zertifikat lesbar sein. Auch ein Ordner mit dem Modus 700 hält das OHIF-Image an:

```bash
chmod 755 /opt/ohif/tls && chmod 644 /opt/ohif/tls/server.crt
```

Docker startet den Container von selbst neu. Ein Neustart von Hand macht den nächsten Versuch sofort:

```bash
docker restart ohif
```

Ist die dritte Zeile des Logs der eigene Fall, die Dateien an ihren Platz legen ([install.de.md](install.de.md#tls-certificate)). Sagt
das Log stattdessen `no "ssl_certificate" is defined` (eine typische Meldung, für diese Seite nicht ausgeführt), fehlen die zwei Zeilen
`ssl_certificate` am Ende von `pacs/listener/server.conf`.

> **Warnung**
>
> Mit der Gruppe 101 und dem Modus 640 kann jedes Konto des Servers in einer Gruppe mit der gid 101 den Schlüssel lesen.
> `getent group 101` ausführen. Es sollte nichts ausgeben oder eine Gruppe, der man vertraut. Dasselbe gilt für die uid 101
> ([3.5](#uid-101-taken)). Zum Zurückgehen `chown` und `chmod` des einfachen Images ausführen. Das OHIF-Image startet dann nicht mehr.

> **Prüfen**
>
> ```bash
> bash /opt/pacs-admin/deploy/tools/preflight.sh --lang de --dir /opt/ohif --cert /opt/ohif/tls/server.crt --key /opt/ohif/tls/server.key | grep 'Schluessel'
> docker ps --format '{{.Names}}  {{.Status}}' | grep '^ohif'
> docker logs --tail 5 ohif
> ```
>
> Erwartet: keine `[FAIL]`-Zeile für den Schlüssel, der Container `ohif` ist `Up`, und das Log zeigt keine `[emerg]`-Zeile. Das Skript
> liest das Image aus dem Container oder aus der Compose-Datei. Beispiel für das OHIF-Image (die Schlüsselzeile hängt vom eigenen
> Schlüssel ab):
>
> ```text
> [ OK ] privater Schluessel: lesbar, ohne Passphrase (2048 bit, 2 primes)
> [ OK ] Rechte des privaten Schluessels passen zum OHIF-Image (root:101 640, nur fuer uid 101 lesbar)
> ohif  Up 12 seconds
> ```
>
> Für das einfache Image lautet die zweite Zeile `Rechte des privaten Schluessels passen zum normalen nginx-Image (root:root 600)`.

<a id="nginx-wont-start"></a>
### 4.2 nginx meldet [emerg] und startet nicht

**Was man sieht.** Der Container `ohif` startet immer wieder neu, oder der Test von nginx bricht ab. `docker logs --tail 20 ohif` zeigt
eine Zeile mit `[emerg]`. Der Testlauf von Installationsschritt 4.9 ([install.de.md](install.de.md#nginx-files)) zeigt dieselbe Zeile
mit dem Präfix `nginx: [emerg]`.

**Ursache.** nginx liest beim Start alle seine Dateien. Es hält beim ersten Fehler an und nennt die Datei und die Zeilennummer. Nur
die erste `[emerg]`-Zeile lesen. Dieselbe Zeile kommt bei jedem Neustart wieder.

| Die Zeile sagt | Ursache |
|---|---|
| `cannot load certificate key ...` oder `cannot load certificate ...` | Die TLS-Dateien. Siehe [4.1](#tls-key-unreadable). |
| `unknown directive "http2" in /etc/nginx/conf.d/pacs/listener/server.conf:5` | Das nginx ist älter als 1.25.1 und kennt `http2 on;` nicht. Siehe Abhilfe A. |
| `unknown "pacs_dcm4chee_ui" variable` | Die Datei `pacs/listener/http.conf` fehlt. Siehe Abhilfe B. |
| `open() "/etc/nginx/conf.d/pacs/login/http.conf" failed (2: No such file or directory) in /etc/nginx/conf.d/pacs.conf:40` | Eine Datei der nginx-Dateien fehlt. Die Zeile nennt sie. Siehe Abhilfe B. |
| `Bind for 0.0.0.0:443 failed: port is already allocated` oder `address already in use` | Ein typischer Docker-Fehler, für diese Seite nicht ausgeführt. Der Container startet nie. Ein anderes Programm hält den Port 80 oder 443. Es mit `ss -ltnp` finden und beenden. |

**Abhilfe A, nginx ist zu alt.** Das Image der Beispiel-Compose-Dateien hat ein neueres nginx. Die Meldung erscheint, wenn nginx auf
dem Server mit Debian 12 läuft (es hat 1.22) oder wenn ein anderes Image genutzt wird. Die Version prüfen:

```bash
nginx -v
```

Beispielausgabe: `nginx version: nginx/1.22.1`. Bei einem Container `docker exec ohif nginx -v` nutzen. Bei einem nginx älter als 1.25.1
die Zeile `http2 on;` in der Datei löschen, die die Meldung nennt. `http2` in die Zeile darüber schreiben. Der zweite Befehl zeigt das
Ergebnis:

```bash
sed -i -e '/^http2 on;/d' -e 's/^listen \(.*\) ssl default_server;/listen \1 ssl http2 default_server;/' /etc/nginx/conf.d/pacs/listener/server.conf
grep -n 'listen\|http2' /etc/nginx/conf.d/pacs/listener/server.conf
```

Das `grep` gibt eine `listen`-Zeile aus, die `ssl http2 default_server` enthält. Es gibt keine Zeile aus, die mit `http2` beginnt. Die
Portnummer kann abweichen (`443` auf dem Server, `8443` im Container).

**Abhilfe B, eine Datei fehlt.** Der Baum in `/opt/ohif/nginx` enthält 13 Dateien (12 ohne die optionale Datei für die
Benutzeroberfläche von dcm4chee). Jede Datei hat eine Quelle in `/opt/pacs-admin/deploy/nginx`:

| Datei im eigenen Baum | Quelle im Repository |
|---|---|
| `pacs.conf` | `pacs.conf` |
| `pacs/site.conf` | `site.conf.example` (die eigene Datei enthält die eigenen Werte: nur kopieren, wenn sie fehlt) |
| `pacs/audit-write.conf`, `pacs/headers.conf`, `pacs/proxy.conf` | `common/` |
| `pacs/login/admin.conf`, `http.conf`, `locations.conf`, `server.conf` | `login/LOGIN/` |
| `pacs/viewer.conf` | `viewer/VIEWER.conf` |
| `pacs/listener/http.conf`, `server.conf` | `listener/LISTENER/` |
| `pacs/optional/dcm4chee-ui.conf` | `optional/dcm4chee-ui.conf` |

`LOGIN`, `VIEWER` und `LISTENER` sind die Werte des eigenen Rezepts ([install.de.md](install.de.md#nginx-files) enthält die Tabelle).
Die fehlende Datei kopieren. Dieses Beispiel kopiert die Datei aus der Meldung oben für die Anmeldung `basic`:

```bash
cp /opt/pacs-admin/deploy/nginx/login/basic/http.conf /opt/ohif/nginx/pacs/login/http.conf
```

> **Warnung**
>
> Den ganzen Kopierblock von Installationsschritt 4.9 nicht noch einmal ausführen, nachdem `pacs/site.conf` bearbeitet wurde. Seine
> zweite Zeile kopiert `site.conf.example` über die eigene Datei, und der Servername und die Admin-Gruppe sind weg. Nur einzelne
> Dateien kopieren. Vor jeder größeren Änderung eine Kopie von `pacs/site.conf` aufbewahren.

> **Prüfen**
>
> ```bash
> docker run --rm -v /opt/ohif/nginx:/etc/nginx/conf.d:ro -v /opt/ohif/tls:/etc/nginx/tls:ro nginx:1.30 nginx -t
> find /opt/ohif/nginx -type f | wc -l
> docker restart ohif
> docker ps --format '{{.Names}}  {{.Status}}' | grep '^ohif'
> ```
>
> Erwartet: die letzten zwei Zeilen des Tests, dann die Zahl der Dateien, dann der Container `Up`. Meldungen über `default.conf` und
> über IPv6 davor sind harmlos. Die Rezepte `proxied` und `tryit` haben keinen Ordner `tls`: die zweite Option `-v` weglassen. Nginx
> auf dem Server: `nginx -t` und `systemctl reload nginx` ausführen.
>
> ```text
> nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
> nginx: configuration file /etc/nginx/nginx.conf test is successful
> 13
> ohif  Up 6 seconds
> ```

<a id="every-page-500"></a>
### 4.3 Jede Seite antwortet mit 500, 502 oder 404

**Was man sieht.** Jeder Pfad der Website scheitert, auch `/`. Die Antwort ist 500 (interner Serverfehler), 502 (Bad Gateway) oder
404 (nicht gefunden). Bei der Anmeldung mit oauth2-proxy enthält `docker logs ohif` Zeilen wie diese, aus einem Testlauf. Der Name
vor `could not be resolved` ist der aus den eigenen Dateien:

```text
[error] 28#28: *1 no-such-auth could not be resolved (3: Host not found), server: pacs.example.org, request: "GET / HTTP/2.0", subrequest: "/oauth2/auth", host: "127.0.0.1:8443"
```

**Ursache.** Es gibt zwei verschiedene Fälle.

1. **500, und das Log sagt `could not be resolved`.** nginx sucht bei jeder Anfrage zwei Namen im Docker-DNS: den Login-Container
   (`set $pacs_auth`) und das Archiv (`set $arc`) in `pacs/site.conf`. Bei der Anmeldung mit oauth2-proxy fragt nginx bei jeder
   Anfrage zuerst den Login-Container. Findet nginx diesen Namen nicht, antwortet jede Seite mit 500, auch `/`. Die Gründe sind: Der
   Name in `site.conf` ist nicht der Name des Containers, der Container läuft nicht, oder er liegt nicht im selben Docker-Netz wie
   `ohif`. Ein falscher Archivname bricht nur die Pfade unter `/dcm4chee-arc/`. Der Viewer öffnet sich dann mit einer leeren Liste
   ([6.1](#viewer-no-studies)). Eine typische Antwort für diese Pfade ist 502.
2. **404 oder 502 ohne `could not be resolved`.** Die Anfrage erreicht die nginx-Dateien dieses Panels nicht. Ein anderes Programm
   antwortet unter dieser Adresse, zum Beispiel ein Rechner, auf den der DNS-Name irrtümlich zeigt. Oder ein Proxy vor `ohif` erreicht
   ihn nicht und antwortet selbst mit 502. Oder der Container läuft ohne den Ordner `/etc/nginx/conf.d`, sodass nginx seine
   Standardseite zeigt.

**Abhilfe.** Fall 1. Die Namen lesen, die nginx nutzt, die laufenden Container und die Container im Netz. Den Netznamen aus dem
letzten Block der eigenen Compose-Datei nehmen:

```bash
grep -E '^set +\$(arc|pacs_auth) ' /opt/ohif/nginx/pacs/site.conf
docker ps --format '{{.Names}}'
docker network inspect dcm4chee-arc_default -f '{{range .Containers}}{{.Name}} {{end}}'
```

Der erste Befehl gibt die zwei `set`-Zeilen aus. Der Rechnername hinter `http://` ist der Name, den nginx nachschlägt. Jeder dieser
Namen muss in der Ausgabe der anderen zwei Befehle erscheinen. Dann auf das reagieren, was fehlt:

- **Der Name ist falsch.** Die Zeile in `pacs/site.conf` auf den Namen aus `docker ps` korrigieren, dann
  `docker exec ohif nginx -t && docker exec ohif nginx -s reload` ausführen.
- **Der Container läuft nicht.** Ihn starten: `cd /opt/ohif && docker compose up -d`. Für `arc` dcm4chee in seinem Ordner starten.
- **Der Container liegt nicht im Netz.** `ohif` und `ohif-auth` bekommen das Netz aus dem letzten Block der Compose-Datei der
  Eingangstür ([3.7](#external-network-missing)). Ein Login-Container, der in einem anderen Compose-Projekt läuft, muss demselben
  Netz beitreten.

Fall 2. Die Eingangstür vom Server selbst aus fragen. Der Befehl umgeht DNS und jeden Proxy. Die Rezepte `proxied` und `tryit` haben
kein TLS: stattdessen `http://` und den veröffentlichten Port oder das Ziel des Proxys nutzen.

```bash
curl -sk --resolve pacs.example.org:443:127.0.0.1 -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/
docker exec ohif ls /etc/nginx/conf.d
```

Ist diese Antwort richtig und die Antwort vom eigenen PC falsch, liegt das Problem beim DNS-Namen oder beim Proxy. Den Namen mit
`preflight.sh --host pacs.example.org` prüfen und das Ziel des Proxys (`http://ohif:8080`). Zeigt das `ls` nicht `pacs` und
`pacs.conf`, hängt die Compose-Datei den falschen Ordner ein ([install.de.md](install.de.md#compose-file)).

> **Warnung**
>
> Für eine Änderung von `site.conf` `nginx -s reload` nutzen, keinen Neustart. Ein Neustart von `ohif` unterbricht die Benutzer für
> einige Sekunden, und das Protokoll verliert danach die erste Zeile jedes nginx-Workers.

> **Prüfen**
>
> ```bash
> curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/
> ```
>
> Erwartet: `302` bei der Anmeldung mit oauth2-proxy (der Sprung zur Anmeldeseite), `401` bei `basic`, `403` bei `none`, wenn der
> eigene PC auf keiner Liste steht. Die Zahlen 500, 502 und 404 bedeuten, dass die Ursache noch da ist. `-k` nur bei einem selbst
> signierten Zertifikat nutzen.

<a id="htpasswd-403-500"></a>
### 4.4 Die Anmeldung basic antwortet nach dem Passwort mit 403 oder 500

**Was man sieht.** Das Rezept nutzt die Anmeldung `basic`. Der Browser fragt nach Name und Passwort. Nach einem richtigen Passwort
zeigt er 403 (verboten) oder 500 (interner Serverfehler) statt der Seite. Eine Anfrage ohne Passwort antwortet weiter mit 401, weil
nginx die Passwortdateien nur öffnet, wenn eine Anfrage ein Passwort mitbringt. Eine fehlende Datei zeigt sich deshalb erst bei der
ersten Anmeldung. Dieser Befehl zeigt die Ursache:

```bash
docker logs ohif 2>&1 | grep -E 'user "|htpasswd' | tail -n 5
```

Die Zeilen sehen so aus (ein Testlauf). Das `...` steht für Client, Server und Anfrage am Ende der Zeile:

```text
[error] 21#21: *2 open() "/etc/nginx/htpasswd/admins" failed (2: No such file or directory), client: 172.22.0.2, ...
[crit] 32#32: *73 open() "/etc/nginx/htpasswd/admins" failed (13: Permission denied), ...
```

**Ursache.** nginx liest die Dateien `users` und `admins` in `/opt/ohif/htpasswd` bei jeder Anfrage, die ein Passwort mitbringt. Die
nginx-Worker-Prozesse laufen mit der [uid](glossary.de.md#uid) 101.

| Antwort | Log | Ursache |
|---|---|---|
| 403 | `[error]` und `failed (2: No such file or directory)` | Die Datei existiert nicht. Fehlt der Ordner `htpasswd` neben der Compose-Datei, hat Docker einen leeren angelegt. |
| 500 | `[crit]` und `failed (13: Permission denied)` | Die Datei existiert, aber uid 101 darf sie nicht lesen, zum Beispiel Besitzer `root` und Modus 600. |

Eine fehlende Datei `users` bricht die Viewer-Seiten. Eine fehlende Datei `admins` bricht `/admin/` und jede Änderung. Eine Zeile mit
`password mismatch` oder `was not found in` ist ein anderes Problem: siehe [5.9](#basic-login-401).

**Abhilfe.** Für 403 das erste Konto anlegen. Das Skript legt den Ordner und beide Dateien mit dem richtigen Besitzer und Modus an:

```bash
bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh admin anna
```

Für 500 den Besitzer und den Modus korrigieren. Der Befehl nutzt `users` und `admins` im Ordner neben der eigenen Compose-Datei:

```bash
chown 101 /opt/ohif/htpasswd/users /opt/ohif/htpasswd/admins
chmod 600 /opt/ohif/htpasswd/users /opt/ohif/htpasswd/admins
```

`preflight.sh --dir /opt/ohif` findet beide Fehler vor dem Start. Hinter nginx auf dem Server laufen die Worker als `www-data`: das
Skript mit `--owner root:www-data --mode 640` aufrufen ([login.de.md](login.de.md#login-basic-accounts)).

> **Warnung**
>
> Einen 500 nicht mit dem Modus 644 „beheben“. Dann kann jedes Konto des Servers die Passwort-Hashes lesen, und `preflight.sh` warnt
> davor. `pacs-adduser.sh` nicht für einen vorhandenen Namen aufrufen, um die Rechte zu reparieren: Das Skript setzt dafür ein neues
> Passwort.

> **Prüfen**
>
> ```bash
> ls -ln /opt/ohif/htpasswd
> curl -sk -u anna -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/
> ```
>
> Erwartet: zwei Dateien des Benutzers 101 mit dem Modus `-rw-------` und `200` für einen Administrator, nachdem das Passwort von
> `anna` eingegeben wurde. Beispiel (die Größen und die Zeiten weichen ab):
>
> ```text
> -rw------- 1 101 0 112 Oct 14 07:54 admins
> -rw------- 1 101 0 112 Oct 14 07:54 users
> 200
> ```

<a id="proxy-wrong-address"></a>
### 4.5 Das Protokoll zeigt für jeden Benutzer die Adresse des Proxys

**Was man sieht.** Das Rezept `proxied` betreibt nginx hinter einem eigenen TLS-Proxy. Im Protokoll, im CSV-Export und in der
Prüfung des Reiters `Firewall` gegen das Aussperren hat jeder PC dieselbe Adresse: den Proxy. Bei der Anmeldung `none` antwortet jede
Anfrage mit 403, weil keine Liste den Proxy enthält.

**Ursache.** nginx sieht die Verbindung des Proxys und liest die Adresse des PCs aus dem Header `X-Forwarded-For`. Das tut es nur bei
einer Verbindung aus dem Subnetz in der Zeile `set_real_ip_from` von `pacs/listener/server.conf`. Der mitgelieferte Wert ist
`203.0.113.1`. Das ist eine Dokumentationsadresse, die kein Proxy nutzt. Der Wert vertraut also niemandem, und nginx ignoriert den
Header. Dasselbe passiert, wenn das Subnetz den Proxy nicht enthält oder wenn der Proxy den Header nicht sendet. Eine weitere Ursache
bei den Rezepten mit TLS: Docker nimmt eine Verbindung über IPv6 an, und nginx sieht nur die Adresse des Docker-Gateways. Die
Beispiel-Compose-Dateien veröffentlichen die Ports aus diesem Grund auf `0.0.0.0` (nur IPv4). Das nicht ändern.

**Abhilfe.** Das Subnetz des Docker-Netzes setzen, das nur der Proxy und nginx teilen. `proxy_default` ist der Beispielname aus der
Compose-Datei. Der Name steht im letzten Block der Compose-Datei, in der Zeile mit dem zweiten `name:`.

```bash
PROXY_NET=$(docker network inspect proxy_default -f '{{(index .IPAM.Config 0).Subnet}}')
echo "$PROXY_NET"
sed -E -i "s|^(set_real_ip_from +)[^;]+;.*|\1${PROXY_NET};|" /opt/ohif/nginx/pacs/listener/server.conf
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

Das `echo` gibt das Subnetz aus, zum Beispiel `172.23.0.0/16`. Sendet der Proxy `X-Forwarded-For` nicht, ihn im Proxy einschalten
([install.de.md](install.de.md#variant-proxied) nennt die Einstellungen der üblichen Proxys).

> **Warnung**
>
> Das Subnetz des einen Netzes eintragen, das Proxy und nginx teilen, nichts Breiteres. Jeder Client im vertrauten Subnetz kann eine
> beliebige Adresse in den Header schreiben. Bei der Anmeldung `none` entscheidet diese Adresse über die Zugriffsstufe. In diesem
> Rezept keinen Port von `ohif` auf dem Host veröffentlichen.

> **Prüfen**
>
> ```bash
> grep -n set_real_ip_from /opt/ohif/nginx/pacs/listener/server.conf
> python3 /opt/pacs-admin/server/pacsdb.py protokoll zugriffe "$(date +%F)" | tail -n 3
> ```
>
> Zuerst auf einem PC `https://pacs.example.org/` öffnen. Erwartet: Die erste Zeile zeigt das eigene Subnetz und nicht
> `203.0.113.1`. In den Zeilen des zweiten Befehls ist das Feld `ip` die Adresse des PCs. Eine Anfrage ohne den Header (ein Aufruf vom
> Proxy-Rechner) zeigt die Adresse des Proxys. Beispielzeile (die PC-Adresse ist `192.0.2.77`):
>
> ```text
> {"t":"2026-10-14T09:00:26+00:00","u":"vera","sub":"vera","ip":"192.0.2.77","r":"/","status":200}
> ```

<a id="trouble-login"></a>
## 5. Anmeldung

Dieses Kapitel behandelt die Anmeldung. Die Einträge 5.1 bis 5.8 gehören zur Anmeldung mit oauth2-proxy (Single Sign-on mit einem
Identitätsanbieter wie Microsoft Entra ID). Eintrag 5.9 gehört zur Anmeldung `basic`, Eintrag 5.10 zur Anmeldung `none`.
[login.de.md](login.de.md#login-choose) erklärt, wie man jede Anmeldung einrichtet. Die Meldungen von Microsoft und von oauth2-proxy
sind aus deren Dokumentation und Quellcode zitiert und wurden nicht gegen einen echten Anbieter ausgeführt.

<a id="login-redirect-uri-mismatch"></a>
### 5.1 Microsoft zeigt AADSTS50011 (Redirect-URI)

**Was man sieht.** Der Benutzer wählt auf der Microsoft-Seite das Konto. Microsoft zeigt dann eine Fehlerseite mit dem Code
`AADSTS50011`. Der Text sagt, dass die Redirect-URI in der Anfrage nicht zu den Redirect-URIs passt, die für die Anwendung
eingetragen sind. Die Seite nennt die Adresse, die Microsoft erhalten hat.

**Ursache.** oauth2-proxy sendet die Adresse der Option `--redirect-url` an Microsoft. Microsoft vergleicht sie Zeichen für Zeichen
mit den Redirect-URIs der App-Registrierung. Ein anderer Rechnername, `http` statt `https`, eine Portnummer oder ein Schrägstrich am
Ende machen daraus eine andere Adresse.

**Abhilfe.** Die Adresse lesen, die oauth2-proxy sendet:

```bash
grep -n -e '--redirect-url' /opt/ohif/docker-compose.yml
```

Entra ID > App registrations > `PACS` > Manage > Authentication öffnen. Der Abschnitt Web muss genau diese Adresse auflisten. Der
Rechnername ist der, den die Benutzer eintippen (die Zeile `server_name` in `pacs/site.conf`). Die falsche Seite korrigieren:

- **Die Compose-Datei ist falsch.** Die Zeile bearbeiten, dann `cd /opt/ohif && docker compose up -d` ausführen. Der Befehl legt
  `ohif-auth` mit der neuen Adresse neu an.
- **Die Liste im Portal ist falsch.** Add URI wählen, `https://pacs.example.org/oauth2/callback` eintippen und Save wählen.

> **Warnung**
>
> Nur die eine Adresse des eigenen Servers eintragen. Die Redirect-URI sagt Microsoft, wohin das Ergebnis einer Anmeldung geschickt
> wird. Nicht die Adresse eines Rechners eintragen, den man nicht kontrolliert.

> **Prüfen**
>
> ```bash
> docker compose -f /opt/ohif/docker-compose.yml config | grep -e '--redirect-url'
> ```
>
> Erwartet: eine Zeile mit der eigenen Adresse. Beispiel (der Rechnername weicht ab):
>
> ```text
>       - --redirect-url=https://pacs.example.org/oauth2/callback
> ```
>
> Dann in einem privaten Browserfenster erneut anmelden. Microsoft zeigt die Anmeldeseite ohne Fehlercode, und der Viewer öffnet sich.

<a id="login-client-secret"></a>
### 5.2 Microsoft zeigt AADSTS7000215 oder AADSTS7000222 (Client-Geheimnis)

**Was man sieht.** Der Benutzer meldet sich bei Microsoft an, aber der Browser kehrt nicht zum PACS zurück. Er zeigt eine Fehlerseite
von oauth2-proxy. Das Log von oauth2-proxy enthält eine Zeile mit einem der beiden Codes:

```bash
docker logs ohif-auth 2>&1 | grep AADSTS | tail -n 3
```

**Ursache.** Der Code `AADSTS7000215` sagt, dass das Client-Geheimnis falsch ist. Der übliche Grund ist, dass die Secret ID statt
des Values kopiert wurde ([login.de.md](login.de.md#login-oauth2-entra), Schritt 2). Der Code `AADSTS7000222` sagt, dass das
Geheimnis abgelaufen ist. Das Portal zeigt das Ablaufdatum jedes Geheimnisses. Ein dritter Grund ist ein Container, der noch das
alte Geheimnis nutzt: Docker liest `ohif-auth.env`, wenn es den Container anlegt, und `docker compose restart` liest die Datei nicht
neu.

**Abhilfe.** Ein neues Geheimnis anlegen und dem Container geben. Zuerst Entra ID > App registrations > `PACS` > Manage >
Certificates & secrets > Client secrets > New client secret öffnen und den **Value** sofort kopieren. Dann die drei Blöcke aus
[login.de.md, Schritt 7](login.de.md#login-oauth2-env) ausführen. Die Blöcke schreiben eine neue `ohif-auth.env` und ein neues
Cookie-Geheimnis, deshalb melden sich alle einmal neu an. Dann den Container neu anlegen:

```bash
cd /opt/ohif && docker compose up -d --force-recreate ohif-auth
```

> **Warnung**
>
> Das alte Geheimnis erst im Portal löschen, wenn die Prüfung unten bestanden ist. Das Ablaufdatum des neuen Geheimnisses in einen
> Kalender eintragen. An diesem Tag kann sich niemand mehr anmelden ([login.de.md](login.de.md#login-oauth2-operate), Abschnitt 2.5).

> **Prüfen**
>
> ```bash
> docker ps --format '{{.Names}}  {{.Status}}' | grep '^ohif-auth'
> docker logs ohif-auth 2>&1 | grep AADSTS | tail -n 3
> ```
>
> Zwischen den zwei Befehlen einmal anmelden. Erwartet: `ohif-auth` ist `Up`, der Viewer öffnet sich nach der Anmeldung, und der
> zweite Befehl gibt nichts aus. Beispiel (die Zeit weicht ab):
>
> ```text
> ohif-auth  Up 40 seconds
> ```

<a id="login-oauth2-proxy-down"></a>
### 5.3 Der Container ohif-auth läuft nicht, oder der Sprung zur Anmeldeseite fehlt

**Was man sieht.** `docker ps` listet `ohif-auth` nicht auf, oder es zeigt `Restarting`. Eine Anfrage ohne Sitzung springt nicht zur
Anmeldeseite, und jede Seite antwortet mit 500 ([4.3](#every-page-500)). Das Ende des Logs nennt den Grund:

```bash
docker logs --tail 20 ohif-auth
```

**Ursache.** oauth2-proxy prüft beim Start seine Einstellungen und fragt den Anbieter nach dessen Konfiguration. Es hält an, wenn
eines davon scheitert. Die letzten Zeilen des Logs sagen, welches:

| Die letzten Zeilen sagen | Ursache |
|---|---|
| `oidc: issuer did not match the issuer returned by provider, expected "..." got "..."` | Die Adresse hinter `--oidc-issuer-url=` weicht von der Adresse ab, die der Anbieter mitteilt. Ein Schrägstrich am Ende zählt mit. |
| Eine Zeile mit `dial tcp`, `lookup` oder `i/o timeout` (typisch, nicht ausgeführt) | Der Server erreicht den Anbieter nicht. DNS oder eine Firewall des Netzes blockiert die Verbindung. |
| `missing setting: ...` oder `cookie_secret must be 16, 24, or 32 bytes ...` (typisch, nicht ausgeführt) | `ohif-auth.env` ist leer, es fehlt ein Name, oder die Datei enthält ein Cookie-Geheimnis der falschen Länge. |

`docker compose up -d` kann auch scheitern, bevor der Container startet. Zwei typische Meldungen, nicht ausgeführt:
`env file ... ohif-auth.env not found` (die Datei existiert nicht) und ein Fehler beim Laden des Images
`quay.io/oauth2-proxy/oauth2-proxy:v7.15.4` (der Server erreicht `quay.io` nicht).

**Abhilfe.** Auf die gefundene Zeile reagieren.

**Issuer.** Den Anbieter nach der Adresse fragen, die er mitteilt. Die ausgegebene Adresse Zeichen für Zeichen hinter
`--oidc-issuer-url=` in die Compose-Datei schreiben ([login.de.md, Schritt C](login.de.md#login-oauth2-compose) nennt die
Einzelheiten):

```bash
ISSUER=CHANGE-ME-ISSUER-ADDRESS
curl -s "${ISSUER%/}/.well-known/openid-configuration" | python3 -c 'import sys,json; print(json.load(sys.stdin)["issuer"])'
```

**Anbieter nicht erreichbar.** Das `curl` oben auf dem Server ausführen. Gibt es nichts aus oder scheitert es, hat der Server keinen
Weg zum Anbieter. Die Personen, die DNS und die Firewall des Netzes betreiben, bitten, den Rechner des Anbieters freizugeben.

**Env-Datei.** Die Datei mit den drei Blöcken aus [login.de.md, Schritt 7](login.de.md#login-oauth2-env) neu anlegen.

**Image.** `quay.io` für den Server freigeben. Oder das Image auf einem anderen Rechner laden und mit `docker save` und
`docker load` herüberbringen.

Dann die Änderung anwenden:

```bash
cd /opt/ohif && docker compose up -d
```

> **Prüfen**
>
> ```bash
> docker ps --format '{{.Names}}  {{.Status}}' | grep '^ohif'
> curl -sk -o /dev/null -w '%{http_code} %{redirect_url}\n' https://pacs.example.org/ | cut -d/ -f1-3
> ```
>
> Erwartet: `ohif` und `ohif-auth` sind `Up`, und eine Anfrage ohne Sitzung wird zum Anbieter umgeleitet. Beispiel für Entra ID (die
> letzte Zeile wurde nicht gegen einen echten Anbieter ausgeführt):
>
> ```text
> ohif  Up 2 minutes
> ohif-auth  Up 2 minutes
> 302 https://login.microsoftonline.com
> ```

<a id="login-loop"></a>
### 5.4 Der Browser springt zwischen dem PACS und der Anmeldeseite hin und her

**Was man sieht.** Der Benutzer meldet sich an. Der Browser kehrt zum PACS zurück, springt wieder zur Anmeldeseite und wiederholt
das, bis er mit einer Meldung über zu viele Weiterleitungen aufgibt. Der Wortlaut hängt vom Browser ab.

**Ursache.** Nach einer guten Anmeldung setzt oauth2-proxy ein Sitzungs-Cookie (Standardname `_oauth2_proxy`). Sendet der Browser
das Cookie nicht zurück, sieht nginx keine Sitzung und schickt den Benutzer erneut zum Anbieter. Diese Gründe sind typisch. Keiner
wurde gegen einen echten Anbieter ausgeführt:

| Grund | Woran man es erkennt |
|---|---|
| Der Benutzer hat die Website mit einem anderen Namen geöffnet als dem Rechnernamen aus `--redirect-url`, zum Beispiel mit der IP-Adresse oder einem Kurznamen. Das Cookie gehört zum Rechnernamen der Redirect-URL. | Die Adressleiste zeigt einen anderen Namen als `server_name` in `pacs/site.conf`. |
| Die Uhr des Servers geht um mehr als die Sitzungsdauer von 12 Stunden falsch. Das Cookie läuft dann sofort ab. | `timedatectl` zeigt eine andere Zeit als eine verlässliche Uhr oder `System clock synchronized: no`. |
| Ein Proxy vor nginx ändert den Header `Host`. | Das Rezept `proxied` ist im Einsatz ([login.de.md](login.de.md#login-other-oauth2), Punkt 1). |
| Der Browser blockiert Cookies für die Website. | Nach der Anmeldung listen die Entwicklerwerkzeuge des Browsers (F12, Seite Application oder Storage) kein Cookie `_oauth2_proxy` für die Website. |

**Abhilfe.** Den Benutzern sagen, die Website nur mit dem Rechnernamen aus `server_name` zu öffnen. Die Zeitquelle des Servers mit
den Werkzeugen der eigenen Organisation korrigieren. Den Proxy so einstellen, dass er `Host` unverändert weiterreicht und jeden Pfad,
`/oauth2/` eingeschlossen, an nginx schickt. Cookies für die Website im Browser erlauben.

> **Prüfen**
>
> ```bash
> timedatectl | grep -e 'Local time' -e 'synchronized'
> ```
>
> Erwartet: eine Zeit, die zu einer verlässlichen Uhr passt, und `System clock synchronized: yes`. Dann
> `https://pacs.example.org/` in einem privaten Browserfenster öffnen und anmelden. Der Viewer öffnet sich, und die Adressleiste
> bleibt beim Viewer. Beispiel für den ersten Befehl (die Zeit weicht ab):
>
> ```text
>                Local time: Wed 2026-10-14 09:30:12 CEST
> System clock synchronized: yes
> ```

<a id="viewer-403-after-login"></a>
### 5.5 Die Seite „Forbidden“ erscheint direkt nach der Anmeldung

**Was man sieht.** Die Anmeldung beim Anbieter funktioniert. Der Browser zeigt dann eine Seite mit dem Titel „Forbidden“ und dem Text
„You do not have permission to access this resource“. Andere Benutzer können sich anmelden. Das Log von oauth2-proxy enthält je eine
Zeile für jede abgewiesene Anmeldung:

```bash
docker logs ohif-auth 2>&1 | grep -E 'Invalid authentication|Authenticated via' | tail -n 5
```

Die Zeile `Invalid authentication via OAuth2: unauthorized` kennzeichnet eine abgewiesene Anmeldung. Die Zeile
`Authenticated via OAuth2:` kennzeichnet eine gute und zeigt die Sitzung mit den Gruppen, die der Anbieter gesendet hat. Beide Zeilen
stammen aus dem Quellcode von oauth2-proxy `v7.15.4` und wurden nicht gegen einen echten Anbieter ausgeführt.

**Ursache.** oauth2-proxy lässt einen Benutzer nur ein, wenn er in mindestens einer Gruppe der Optionen `--allowed-group` ist. Ein
abgewiesener Benutzer bekommt keine Sitzung, deshalb antwortet `/oauth2/userinfo` für ihn mit 401. Die Gründe:

| Grund | Woran man es erkennt |
|---|---|
| Der Benutzer ist weder Mitglied der Viewer-Gruppe noch der Admin-Gruppe. | Die Mitgliederliste der Gruppe im Portal. |
| Der Anbieter sendet keine Gruppen. Entra ID: Die Token-Konfiguration hat keinen Groups-Claim. Andere Anbieter: Der Scope `groups` oder der Mapper fehlt. | Ein Benutzer, der sich anmelden kann, hat in `/oauth2/userinfo` einen leeren Eintrag `groups`. |
| Die Namen weichen ab: eine Object ID gegen einen Namen, Großbuchstaben oder bei Keycloak ein fehlender Schrägstrich am Anfang. | `/oauth2/userinfo` eines Benutzers, der sich anmelden kann, Buchstabe für Buchstabe mit den Zeilen `--allowed-group` vergleichen. |
| Der Benutzer ist in mehr als 200 Gruppen (Entra ID). | [login.de.md, 2.4](login.de.md#login-oauth2-overage). |
| Google: Die Adresse des Benutzers liegt nicht in der Domäne von `--email-domain`. GitHub: Der Benutzer ist nicht in der Organisation oder im Team. | [login.de.md, 2.6](login.de.md#login-oauth2-providers). |

**Abhilfe.** Die Gruppen zeigen, die die Compose-Datei erlaubt:

```bash
grep -n -e '--allowed-group' /opt/ohif/docker-compose.yml
```

`https://pacs.example.org/oauth2/userinfo` mit einem Konto öffnen, das sich anmelden kann. Der Eintrag `groups` zeigt, wie der Anbieter
Gruppennamen schreibt. Den Benutzer zu einer Gruppe hinzufügen oder die Namen in der Compose-Datei korrigieren, dann
`cd /opt/ohif && docker compose up -d` ausführen. oauth2-proxy liest die Gruppen bei der Anmeldung und behält sie für die Sitzung,
die 12 Stunden dauert. Ein Benutzer, der zu einer Gruppe hinzugefügt wurde, öffnet `/oauth2/sign_out` und meldet sich neu an.

> **Warnung**
>
> Die Zeilen `--allowed-group` nicht zum Testen löschen. Die mitgelieferte Datei hat `--email-domain=*`. Ohne Gruppenprüfung lässt
> oauth2-proxy dann jedes Konto des Anbieters ein, und bei Entra ID ist das jeder Benutzer des Mandanten.

> **Prüfen**
>
> Mit dem Konto in einem privaten Browserfenster anmelden. Erwartet: Der Viewer öffnet sich. Das Log zeigt die Zeile
> `Authenticated via OAuth2:` für das Konto:
>
> ```bash
> docker logs ohif-auth 2>&1 | grep 'Authenticated via' | tail -n 1
> ```

<a id="admin-403"></a>
### 5.6 /admin/ antwortet mit 403 für ein Konto, das Admin sein soll

**Was man sieht.** Der Benutzer meldet sich an und öffnet den Viewer. `/admin/` zeigt die einfache Seite `403 Forbidden`. Ein
Viewer-Benutzer, der kein Admin ist, sieht dieselbe Seite, und das ist richtig. Bei der Anmeldung `basic` ist die Antwort für einen
solchen Benutzer 401 ([5.9](#basic-login-401)). Bei der Anmeldung `none` ist die Antwort aus einem anderen Grund 403
([5.10](#none-403)).

**Ursache.** Für `/admin/` und für jede Änderung fragt nginx oauth2-proxy, ob der Benutzer in der Admin-Gruppe ist. Die Admin-Gruppe
ist der Wert von `$pacs_admin_group` in `pacs/site.conf`. oauth2-proxy antwortet mit 403, wenn der Benutzer nicht in dieser Gruppe
ist.

| Grund | Woran man es erkennt |
|---|---|
| `$pacs_admin_group` enthält den mitgelieferten Wert `00000000-0000-0000-0000-000000000000` oder einen Wert, der vom Gruppennamen des Anbieters abweicht. | Der Befehl unten gibt den Wert aus. |
| Der Benutzer ist der Admin-Gruppe vor kurzer Zeit beigetreten. oauth2-proxy behält die Gruppen aus der Anmeldung bis zu 12 Stunden. | Die Gruppenliste im Portal zeigt den Benutzer, aber `/oauth2/userinfo` listet die Gruppe nicht. |
| Der Wert in `site.conf` weicht vom zweiten `--allowed-group` der Compose-Datei ab. | Die beiden Werte Buchstabe für Buchstabe vergleichen. |

**Abhilfe.** Den Wert zeigen, den nginx nutzt:

```bash
grep -n 'pacs_admin_group' /opt/ohif/nginx/pacs/site.conf
```

`https://pacs.example.org/oauth2/userinfo` mit einem Konto öffnen, das sich anmelden kann. Der Eintrag `groups` zeigt, wie der Anbieter
einen Gruppennamen schreibt. Denselben Text in `site.conf` setzen und nginx die Datei neu lesen lassen:

```bash
ADMIN_GROUP=CHANGE-ME-ADMIN-GROUP
sed -E -i 's|^(set \$pacs_admin_group +)[^;]+;.*|\1'"$ADMIN_GROUP"';|' /opt/ohif/nginx/pacs/site.conf
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

Ein Gruppenname mit einem Leerzeichen oder einem anderen Sonderzeichen braucht die Prozentform ([5.7](#admin-500)). Ein Benutzer, der
der Gruppe kürzlich beigetreten ist, öffnet `/oauth2/sign_out` und meldet sich neu an.

> **Warnung**
>
> Die Admin-Gruppe nicht auf die Viewer-Gruppe setzen, damit es funktioniert. Dann ist jeder Viewer-Benutzer ein Admin, und ein Admin
> kann Studien bearbeiten, ablehnen und löschen.

> **Prüfen**
>
> ```bash
> grep -n 'pacs_admin_group' /opt/ohif/nginx/pacs/site.conf
> ```
>
> Erwartet: eine Zeile mit der eigenen Gruppe. Dann `https://pacs.example.org/admin/` mit dem Admin-Konto in einem privaten Fenster
> öffnen. Die Admin-Seite öffnet sich, und der Kontoname steht oben. Beispiel für die Zeile (die Gruppe weicht ab):
>
> ```text
> 20:set $pacs_admin_group aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee;
> ```

<a id="admin-500"></a>
### 5.7 /admin/ antwortet mit 500

**Was man sieht.** Bei der Anmeldung mit oauth2-proxy zeigt `/admin/` `500 Internal Server Error`, auch für einen Admin. Der Viewer
kann weiter funktionieren. Antwortet jede Seite mit 500, zuerst [4.3](#every-page-500) lesen.

**Ursache.** nginx fragt oauth2-proxy nach der Admin-Gruppe (5.6). Die Antwort wird in zwei Fällen zu 500:

| Grund | Was das Log von nginx zeigt |
|---|---|
| `$pacs_admin_group` in `pacs/site.conf` ist leer. nginx lehnt absichtlich ab, weil eine leere Gruppe jedes angemeldete Konto einlassen würde. | Keine zusätzliche Zeile. |
| Der Gruppenname enthält ein Zeichen, das eine Webadresse nicht erlaubt, zum Beispiel ein Leerzeichen. nginx fügt den Wert unverändert in eine Adresse ein, und oauth2-proxy antwortet mit 400. | `auth request unexpected status: 400` |

```bash
docker logs ohif 2>&1 | grep -E 'auth request unexpected status|could not be resolved' | tail -n 3
grep -n 'pacs_admin_group' /opt/ohif/nginx/pacs/site.conf
```

**Abhilfe.** Ein leerer Wert: die Gruppe wie in [5.6](#admin-403) setzen. Ein Sonderzeichen: den Wert in `site.conf` in der
Prozentform schreiben. Dieser Befehl wandelt einen ganzen Namen um (der Beispielname ist `authentik Admins`):

```bash
python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe="-_.~:/@"))' 'authentik Admins'
```

Erwartete Ausgabe:

```text
authentik%20Admins
```

Den ausgegebenen Text mit dem `sed`-Befehl aus [5.6](#admin-403) in `site.conf` eintragen und nginx die Datei neu lesen lassen. Die
Compose-Datei behält den einfachen Namen. [login.de.md, Schritt D](login.de.md#login-oauth2-group-names) listet die Zeichen und ihre
Formen.

> **Prüfen**
>
> `https://pacs.example.org/admin/` mit dem Admin-Konto in einem privaten Fenster öffnen. Erwartet: Die Admin-Seite öffnet sich, und
> der erste Befehl dieses Eintrags gibt keine neue Zeile `unexpected status` aus.

<a id="session-expired"></a>
### 5.8 Die Admin-Seite zeigt „Sitzung abgelaufen, Seite neu laden (F5)“

**Was man sieht.** Eine rote Meldung unten rechts auf der Admin-Seite sagt `Sitzung abgelaufen, Seite neu laden (F5)`. Derselbe Text
ersetzt in der Übersicht die Zeile `Kein Status vorhanden ...` und in der Liste der Änderungen die Zeile
`Noch keine Änderungen über diese Seite.`

**Ursache.** Die Seite fragt den Server im Hintergrund nach dem Status, dem Protokoll und den Platten. Ist die Anmeldesitzung
beendet, beantwortet nginx so einen Aufruf mit einer Weiterleitung zur Anmeldeseite (oauth2-proxy) oder mit 401 (`basic`). Die Seite
folgt einer Weiterleitung nicht. Eine Weiterleitung und ein 401 zählen als beendete Sitzung. Eine oauth2-proxy-Sitzung
dauert 12 Stunden (`--cookie-expire=12h`) und wird nicht verlängert ([login.de.md](login.de.md#login-oauth2-operate)). Bei der
Anmeldung `basic` behält der Browser das Passwort, bis er geschlossen wird. Die Meldung erscheint auch, nachdem ein Administrator das
Konto entfernt oder ein neues Passwort gesetzt hat.

**Abhilfe.** F5 drücken. Bei oauth2-proxy geht der Browser zum Anbieter. Lebt die Sitzung beim Anbieter noch, kehrt der Benutzer
zurück, ohne etwas einzutippen. Bei `basic` fragt der Browser nach Name und Passwort. Eine Änderung, die der Benutzer in diesem
Moment gestartet hat, wurde an der Eingangstür abgewiesen, bevor sie das Archiv erreichte. Die Änderung noch einmal starten.

Kommt die Meldung nach F5 sofort wieder, [5.4](#login-loop) (oauth2-proxy) oder [5.9](#basic-login-401) (`basic`) lesen.

> **Prüfen**
>
> F5 drücken und anmelden. Erwartet: Die rote Meldung ist weg, die Kacheln laden, und der Kontoname steht oben auf der Seite.

<a id="basic-login-401"></a>
### 5.9 Anmeldung `basic`: Das Passwortfenster kommt wieder

**Was man sieht.** Der Browser fragt nach Name und Passwort, nimmt die Eingabe an und fragt erneut. Oder `curl -u` gibt `401` für ein
Passwort aus, das stimmt. Eine Anfrage ganz ohne Passwort antwortet in jedem Fall mit 401. Das Fehlerlog von nginx nennt das Konto
und den Grund:

```bash
docker logs ohif 2>&1 | grep -E 'user "|htpasswd' | tail -n 5
```

Die Zeilen sehen so aus (ein Testlauf). Die `...` stehen für Client, Server und Anfrage am Ende der Zeile:

```text
2026/10/14 07:39:56 [error] 98#98: *3 user "clara": password mismatch, client: 127.0.0.1, ...
2026/10/14 07:39:56 [error] 100#100: *5 user "vera" was not found in "/etc/nginx/htpasswd/admins", client: 127.0.0.1, ...
```

**Ursache.**

| Das Log sagt | Ursache | Abhilfe |
|---|---|---|
| `user "clara": password mismatch` | Das Passwort weicht ab, oder der Hash in der Datei hat einen Typ, den nginx nicht lesen kann. | Das Passwort mit dem Skript neu setzen. |
| `user "vera" was not found in ".../admins"` | `vera` ist ein Viewer-Konto. `/admin/` braucht eine Zeile in `admins`. | Das Skript mit `admin vera` ausführen. |
| `user "vera" was not found in ".../users"` | Das Konto existiert nicht, oder der Name ist anders geschrieben. | Das Skript mit `all vera` ausführen. |
| Keine solche Zeile, und `/admin/` antwortet für alle mit 401 | Die Datei `admins` ist leer. | Mit dem Skript einen Administrator anlegen. |

Ein `password mismatch` trotz richtigem Passwort hat diese Gründe:

- **Ein Hash anderen Typs.** Das Skript schreibt den Hash-Typ sha512-crypt (`$6$`) mit der Standardzahl von Runden. nginx prüft den
  Hash bei jeder Anfrage, deshalb verlangsamt eine hohe Rundenzahl jede Seite, und das Skript hat dafür keine Option. Ein Hash vom
  Typ bcrypt (`$2y$`, erzeugt mit `htpasswd -B`) wird nicht von jeder C-Bibliothek gelesen. Zeilen, die ein anderes Werkzeug
  geschrieben hat, können von so einem Typ sein.
- **Ein altes openssl.** Bei openssl älter als 1.1.1 schreibt das Skript den Typ apr1 und gibt `pacs-adduser: WARNING: this
  openssl cannot make sha512-crypt hashes (it needs 1.1.1 or newer). Using apr1, the weaker hash type. Update openssl and set
  the password again.` aus. Beide Typen funktionieren mit nginx.
- **Ein Passwort von mehr als 256 Bytes.** Der Hash deckt nur die ersten 256 Bytes ab, deshalb lehnt nginx das richtige Passwort
  ab. Das Skript lehnt so ein Passwort ab.
- **Ein gespeichertes Passwort.** Der Browser sendet ein altes Passwort, das er für den Namen gespeichert hat. Den gespeicherten
  Eintrag löschen.

**Abhilfe.** Das Passwort neu setzen. Das Skript fragt zweimal und behält die Rechte der Dateien:

```bash
bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh all clara
```

Für einen Administrator `admin` statt `all` nutzen. Der Befehl muss als root laufen. Ohne root-Rechte setzt das Skript keinen
Eigentümer und gibt eine Warnung aus: nginx antwortet dann mit 500 ([4.4](#htpasswd-403-500)).

> **Warnung**
>
> Das Skript ersetzt das Passwort eines Kontos, das schon existiert. Es nur für die Person ausführen, die ein neues Passwort braucht.
> Die Dateien nicht von Hand bearbeiten: Ein falscher Eigentümer oder Modus gibt 500, und eine Zeile mit falschem Hash-Typ gibt 401.

> **Prüfen**
>
> ```bash
> curl -sk -u clara -o /dev/null -w '%{http_code}\n' https://pacs.example.org/
> ```
>
> Der Befehl fragt nach dem Passwort von `clara`. Erwartet: `200`. Dann die Website in einem privaten Browserfenster öffnen und
> anmelden. Ist die Zahl nicht `200`, [login.de.md, 3.6](login.de.md#login-basic-errors) lesen.
>
> ```text
> 200
> ```

<a id="none-403"></a>
### 5.10 Anmeldung `none`: Ein PC bekommt 403 Forbidden

**Was man sieht.** Der Browser zeigt die einfache Seite `403 Forbidden` bei `/`, bei `/admin/` oder bei beiden, für einen PC, der
Zugriff haben soll. Die Seite nennt keine Liste.

**Ursache.** nginx vergleicht die Adresse des PCs mit den Zeilen `allow` von zwei Listen: `pacs/login/server.conf` (Viewer) und
`pacs/login/admin.conf` (Admin). Eine Adresse, die keine Zeile `allow` nennt, bekommt 403. Die üblichen Gründe:

| Grund | Ergebnis |
|---|---|
| Die Adresse, die nginx sieht, ist nicht die Adresse des PCs, zum Beispiel weil ein Router mit Adressumsetzung oder ein Proxy dazwischen sitzt. | 403 für den PC. Eine Liste für die Routeradresse öffnet die Website für jeden PC dahinter. |
| Der PC bekommt seine Adresse per DHCP, und die Adresse hat sich geändert. | Der Zugriff endet an dem Tag, an dem sich die Adresse ändert. |
| Ein Admin-PC steht nur auf der Admin-Liste. Die Admin-Liste ersetzt für `/admin/` die Viewer-Liste, aber die Admin-Seite sucht Studien über die Viewer-Liste. | `/admin/` öffnet sich, und die Studiensuche bekommt 403. |
| Die Listen enthalten noch die Beispielnetze mit der Markierung `CHANGE-ME`. | Niemand kommt hinein. |

**Abhilfe.** Die Adresse lesen, die nginx gesehen hat. Das Wort nach `client:` ist diese Adresse:

```bash
docker logs ohif 2>&1 | grep 'access forbidden by rule' | tail -n 3
```

Die Zeilen sehen so aus (ein Testlauf mit einfachem http, mit einer Dokumentationsadresse):

```text
2026/10/14 08:41:35 [error] 9#9: *1 access forbidden by rule, client: 192.0.2.99, server: pacs.example.org, request: "GET /admin/ HTTP/1.1", host: "pacs.example.org"
```

Die Zeile zeigt auch die Seite, die der PC angefragt hat (hier `/admin/`). Genau diese Adresse oder ein kleines Netz, das sie
enthält, auf die richtige Liste setzen ([login.de.md, 4.2](login.de.md#login-none-lists) hat die Befehle). Jeden Admin-PC auf beide
Listen setzen. Dann die Dateien testen und nginx neu lesen lassen:

```bash
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

Ist die Adresse im Log die Adresse eines Routers oder eines Proxys, kann eine Liste die PCs nicht unterscheiden. Bei einem eigenen
Proxy vor nginx den Listener `behind-proxy` nutzen ([4.5](#proxy-wrong-address)).

> **Warnung**
>
> Nie `allow all;` schreiben, denn das lässt jeden hinein. Jedes Netz so klein halten, wie es geht. `deny all;` als letzte Zeile
> einer Liste behalten: nginx nutzt die erste Zeile, die passt.

> **Prüfen**
>
> Diese Befehle auf dem PC selbst ausführen (unter Windows `curl.exe` nutzen). Der Server steht auf keiner Liste, deshalb sagt ein
> Lauf auf dem Server nichts über den PC.
>
> ```bash
> curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/
> curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/
> ```
>
> Erwartet: `200` und `200` für einen Admin-PC auf beiden Listen, `200` und `403` für einen PC nur auf der Viewer-Liste, `403` und
> `403` für einen PC auf keiner Liste. `-k` nur mit einem selbst signierten Zertifikat nutzen.

<a id="trouble-viewer"></a>
## 6. Viewer und Archiv

Dieses Kapitel behandelt den [Viewer](glossary.de.md#viewer), die Benutzeroberfläche von dcm4chee und die Verbindung zwischen nginx
und dem Archiv-Container `arc`. Zwei Einträge nutzen die Entwicklerwerkzeuge des Browsers. F12 drücken (Chrome, Edge und Firefox)
und den Reiter `Network` öffnen.

<a id="viewer-no-studies"></a>
### 6.1 Der Viewer öffnet sich, aber die Studienliste ist leer

**Was man sieht.** Der Viewer startet und zeigt seine Studienliste, aber die Liste bleibt leer. Oder der Viewer zeigt für die Suche
einen Fehler. Man weiß, dass das Archiv Studien enthält.

**Ursache.** Der Viewer fragt nginx nach `/dcm4chee-arc/aets/AE-TITLE/rs/studies`. Der [AE-Titel](glossary.de.md#ae-title) in dieser
Adresse muss der AE-Titel des Archivs sein, und nginx muss ihn kennen. Fünf Stellen halten den Titel, und das Archiv hält ihn auch
([reference.de.md, 4.3](reference.de.md#ae-title)). Eine Stelle mit einem anderen Titel bricht eine Funktion:

| Stelle | Genutzt für | Wenn der Titel abweicht |
|---|---|---|
| `/opt/ohif/app-config.js` | Die Adresse, die der Viewer anfragt. | Der Viewer fragt nach einem Titel, den nginx oder das Archiv nicht kennt, und die Studienliste bleibt leer. |
| `/opt/ohif/nginx/pacs.conf` | Die Studiensuche, die Änderungen der Admin-Seite und die Protokoll-Ereignisse. | Die Admin-Seite kann Studien nicht suchen oder ändern (404), und im Protokoll fehlen die Suchen. |
| `/opt/ohif/nginx/pacs/viewer.conf` | Das Lesen von Serien, Bildern und Befunden für den Viewer. | Die Liste kann Studien zeigen, aber eine Studie öffnet sich nicht. |
| `config.js`: `aet` und `iocmAet` | Die Admin-Seite. | Der Reiter `Studien` findet nichts. |
| `ARC_AET` in `/etc/default/pacs-admin` | Der Platten-Assistent. | Der Assistent hält mit `HALT: AE ... steht nicht im LDAP` an ([8.1](#disk-halt)). |
| Das Archiv (LDAP) | dcm4chee selbst. | Jeder Aufruf mit diesem Titel antwortet mit 404. |

**Ursache finden.** Den Status der Suche im Browser lesen:

1. Den Viewer öffnen. F12 drücken und den Reiter `Network` öffnen.
2. Strg+F5 drücken, um die Seite neu zu laden.
3. Die Zeile anklicken, deren Name mit `studies?` beginnt.
4. Den Statuscode dieses Aufrufs lesen.

| Status von `studies?...` | Bedeutung | Weiter bei |
|---|---|---|
| `404` | nginx oder das Archiv kennt den AE-Titel in der Adresse nicht. | Abhilfe A |
| `500` oder `502` | nginx erreicht das Archiv nicht. | [4.3](#every-page-500) |
| `401`, oder `302` und dann die Anmeldeseite | Die Anmeldesitzung ist beendet. | [5.8](#session-expired), [5.9](#basic-login-401) |
| `403` | Das Konto oder der PC ist nicht erlaubt. | [5.5](#viewer-403-after-login), [5.10](#none-403) |
| `200` mit `[]`, oder `204` | Das Archiv antwortet und findet für diese Suche keine Studie. | Abhilfe C |
| Keine Zeile `studies?...`, oder ein Aufruf an einen anderen Server | Der Viewer nutzt die eigene `app-config.js` nicht. | Abhilfe B |

**Abhilfe A: ein AE-Titel an allen Stellen.** Zuerst die AE-Titel lesen, die das Archiv kennt. Der Befehl läuft auf dem Server und
fragt das Archiv direkt:

```bash
curl -s http://127.0.0.1:8080/dcm4chee-arc/aets | grep -o '"dicomAETitle" *: *"[^"]*"'
```

Erwartet: eine Zeile für jeden AE-Titel des Archivs. Eine Standardinstallation listet mehrere Titel, darunter `DCM4CHEE` und
`IOCM_QUALITY`. Das ist die übliche Antwort von dcm4chee. Die Antwort wurde nicht aus einem Lauf aufgezeichnet.

Die Dateien müssen dem Archiv folgen. Die Beispiele unten nutzen den Titel `MYARC`. Den eigenen Titel schreiben. Der erste Aufruf
zeigt nur, was sich ändern würde:

```bash
bash /opt/pacs-admin/deploy/tools/set-aet.sh MYARC --dir /opt/ohif --dry-run
```

Enthalten die Dateien jetzt einen anderen Titel als `DCM4CHEE`, `--from OLDARC` mit diesem Titel ergänzen. Das Skript ersetzt nur
ganze Wörter. Es lässt `99DCM4CHEE` unverändert, weil dieses Wort ein Codierschema und kein AE-Titel ist. Ist die Liste der
Änderungen richtig, den Befehl noch einmal ohne `--dry-run` ausführen. Das Skript zeigt jede geänderte Zeile und fragt
`Apply these changes? [y/N]`. Es behält Kopien der Originale in `/opt/ohif/.set-aet-backup-TIME/`.

```bash
bash /opt/pacs-admin/deploy/tools/set-aet.sh MYARC --dir /opt/ohif
```

Das Skript kann zwei Stellen nicht ändern. Diese von Hand ändern:

- `aet` (und `iocmAet`, falls auch dieser Titel umbenannt wurde) in der `config.js`, die die Admin-Seite nutzt. Das ist
  `/opt/pacs-admin/web/admin/config.js` oder die eigene Kopie `/opt/ohif/config.js`, wenn die Compose-Datei eine einbindet. Eine
  Kopie unterhalb von `/opt/ohif` ändert das Skript selbst.
- `ARC_AET=MYARC` in `/etc/default/pacs-admin`. Dann `systemctl restart pacs-verwaltung` ausführen. Den Dienst nicht neu starten,
  solange die Kachel `Neue Festplatte` `läuft seit ...` sagt: Der Neustart stoppt eine laufende Einrichtung der Platte.

Zuletzt die Eingangstür neu starten, damit sie die einzelnen Dateien neu liest, und die Seite ohne Cache laden:

```bash
cd /opt/ohif && docker compose restart ohif
```

Im Browser Strg+F5 drücken.

**Abhilfe B: Der Viewer nutzt die eigene `app-config.js` nicht.** Ohne die eigene Datei läuft der Viewer mit der Konfiguration des
Images, die nichts über das eigene Archiv weiß. `https://pacs.example.org/app-config.js` im Browser öffnen. Die Seite muss die eigene
Datei zeigen. Oder die ersten Zeilen im Container lesen und mit der Datei auf dem Server vergleichen:

```bash
ls -l /opt/ohif/app-config.js
docker exec ohif head -n 3 /usr/share/nginx/html/app-config.js
```

Erwartet: Die Datei existiert, und der Container zeigt die ersten Zeilen dieser Datei. Die Datei des Repositorys beginnt mit
`// OHIF viewer configuration for a dcm4chee-arc PACS behind the nginx of this repository.`

- Fehlt die Datei auf dem Server, mit `cp /opt/pacs-admin/deploy/app-config.js.example /opt/ohif/app-config.js` kopieren. Den
  AE-Titel wie in Abhilfe A setzen. Die Compose-Datei der Eingangstür muss die Datei mit der Zeile
  `- ./app-config.js:/usr/share/nginx/html/app-config.js:ro` einbinden.
- Zeigt der Container anderen Text als die Datei, hält der Container eine alte Kopie. Eine eingebundene Einzeldatei wird gelesen,
  wenn der Container startet. `cd /opt/ohif && docker compose restart ohif` ausführen und Strg+F5 drücken.

**Abhilfe C: Das Archiv findet keine Studie.** Ein Archiv ohne Studien ist kein Fehler. Das Archiv direkt nach einer Studie fragen:

```bash
curl -s -o /dev/null -w '%{http_code}\n' 'http://127.0.0.1:8080/dcm4chee-arc/aets/DCM4CHEE/rs/studies?limit=1'
```

Erwartet: `200`, wenn das Archiv mindestens eine Studie enthält. Die übliche Antwort für keine Studie ist `204`; sie wurde nicht aus
einem Lauf aufgezeichnet. `404` heißt, dass das Archiv den Titel nicht kennt: Abhilfe A nutzen. Listet der Reiter `Studien` der
Admin-Seite Studien und der Viewer nicht, die Filter der Studienliste im Viewer löschen.

**Eine leere Seite.** Eine leere Seite statt der leeren Liste heißt, dass die Sitzung endete, während die Seite offen blieb. Die
Startseite lädt ihre Skripte ohne Sitzung und bekommt nur Weiterleitungen. Strg+F5 drücken und neu anmelden
([5.8](#session-expired)).

> **Warnung**
>
> Die Dateien dem Archiv angleichen. Den AE-Titel im Archiv nicht den Dateien angleichen: Jedes DICOM-Gerät, das an den alten Titel
> sendet, würde abgewiesen. Kein Suchen und Ersetzen in einem Editor nutzen, denn `99DCM4CHEE` muss bleiben.

> **Prüfen**
>
> Den Viewer öffnen und Strg+F5 drücken. Erwartet: Die Studienliste zeigt die Studien, und der Aufruf `studies?...` im Reiter
> `Network` hat den Status `200`. Eine Studie öffnen. Erwartet: Die Bilder laden. Der Reiter `Studien` der Admin-Seite listet
> dieselben Studien.

<a id="dcm4chee-ui-404"></a>
### 6.2 Die dcm4chee-Oberfläche antwortet mit 404

**Was man sieht.** Der Link `dcm4chee` in der Kopfzeile der Admin-Seite oder die Adresse `https://pacs.example.org/dcm4chee-arc/ui2/`
öffnet eine Seite mit `404`. Oder die Oberfläche öffnet sich, aber ihre Listen bleiben leer, und der Reiter `Network` des Browsers
zeigt `404` für die meisten Aufrufe unterhalb von `/dcm4chee-arc/`.

**Ursache.** Die Oberfläche ist ein optionales Modul ([modules.de.md, Abschnitt 5](modules.de.md#dcm4chee-ui)). Zwei Dinge können
scheitern:

| Was scheitert | Ergebnis |
|---|---|
| Die Datei `pacs/optional/dcm4chee-ui.conf` liegt nicht im Ordner der Eingangstür. | Die Adresse der Oberfläche und jeder Aufruf darunter antworten mit 404. |
| Der Header `Referer` eines Aufrufs passt nicht zum Muster in `pacs/listener/http.conf`. | Die Seite der Oberfläche lädt, aber ihre Aufrufe gehen an gesperrte Pfade, und die meisten antworten mit 404. |

Zuerst die Datei testen. Der erste Befehl listet den Ordner, der zweite fragt die Einstiegsadresse an:

```bash
ls /opt/ohif/nginx/pacs/optional/
curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/dcm4chee
```

Erwartet: Die Liste zeigt `dcm4chee-ui.conf`, und die Zahl ist `301`. Fehlt die Datei, sie kopieren und nginx neu lesen lassen:

```bash
cp /opt/pacs-admin/deploy/nginx/optional/dcm4chee-ui.conf /opt/ohif/nginx/pacs/optional/
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

Ist die Datei da, die Regel für `Referer` testen. nginx lässt einen Aufruf der Oberfläche nur durch, wenn der Header `Referer` die
Oberfläche nennt: `https://`, den Rechnernamen der Anfrage, keinen Port und den Pfad `/dcm4chee-arc/ui2/`.

1. Die Oberfläche öffnen. F12 drücken, den Reiter `Network` öffnen und Strg+F5 drücken.
2. Einen Aufruf mit dem Status `404` anklicken und den Request-Header `Referer` lesen.
3. Ihn mit dem Muster auf dem Server vergleichen:

```bash
grep -n -A3 'map "\$host \$http_referer"' /opt/ohif/nginx/pacs/listener/http.conf
```

Die Zeilen sehen so aus (Listener `tls`; die Zeilennummern können abweichen):

```text
14:map "$host $http_referer" $pacs_dcm4chee_ui {
15-    "~^(\S+) https://\1/dcm4chee-arc/ui2/"  1;
16-    default                                 0;
17-}
```

Die Regel scheitert aus diesen Gründen. Der letzte Grund ist typisch und wurde nicht getestet.

| Grund | Abhilfe |
|---|---|
| Benutzer öffnen das PACS mit einem Port, zum Beispiel `https://pacs.example.org:8443/`. | Den Port in das Muster schreiben: `https://\1:8443/dcm4chee-arc/ui2/`. |
| Der Listener ist `plain`, und der SSH-Tunnel nutzt an seinen zwei Enden verschiedene Ports. | An beiden Enden denselben Port nutzen. Das mitgelieferte Muster nennt `:8080`. |
| Ein Reverse-Proxy vor nginx ändert den Header `Host`. | Den Proxy so einstellen, dass er `Host` unverändert weitergibt (Apache: `ProxyPreserveHost On`). Lauscht der Proxy auf einem anderen Port als 443, den Port in das Muster schreiben. |
| Ein Proxy, ein Browser-Add-on oder eine Richtlinie entfernt den `Referer` oder kürzt ihn auf den Rechnernamen. | Den Header mit dem vollen Pfad durchlassen. Die Regel kann ohne ihn nicht funktionieren. |

Nach einer Änderung des Musters die Konfiguration testen und nginx neu lesen lassen:

```bash
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

> **Warnung**
>
> Nur den Teil des Musters ändern, der den Port nennt. Ein lockereres Muster lässt Aufrufe von anderen Seiten die Sperren der
> Admin-Seite umgehen. Die Oberfläche von dcm4chee hat keine eigenen Sperren ([modules.de.md, Abschnitt 5](modules.de.md#dcm4chee-ui)).

> **Prüfen**
>
> ```bash
> curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/dcm4chee
> ```
>
> Erwartet: `301`. Dann die Oberfläche als Admin im Browser öffnen. Erwartet: Die Listen zeigen Daten, und der Reiter `Network` hat
> kein `404` für die Aufrufe unterhalb von `/dcm4chee-arc/`.

<a id="dcm4chee-ui-upload"></a>
### 6.3 Ein Upload in der dcm4chee-Oberfläche scheitert

**Was man sieht.** Ein Admin sendet DICOM-Dateien über die Oberfläche von dcm4chee. Der Upload endet mit einem Fehler, oder er
funktioniert nur für kleine Dateien.

Der Viewer und die Admin-Seite laden absichtlich nicht hoch. Der Viewer ist auf `dicomUploadEnabled: false` gesetzt, und nginx weist
schreibende Aufrufe vom Viewer ab. Nur die Oberfläche von dcm4chee lädt hoch ([6.2](#dcm4chee-ui-404) listet, was sie braucht).

**Ursache.** Den fehlgeschlagenen Aufruf im Reiter `Network` des Browsers finden (ein roter Status) und seinen Statuscode lesen:

| Status | Ursache | Abhilfe |
|---|---|---|
| `403` | Die Regel für `Referer` passt nicht ([6.2](#dcm4chee-ui-404)). Der Aufruf landet bei der gesperrten Studiensuche, die nur GET erlaubt. | Die Regel wie in 6.2 korrigieren. |
| `413` | Eine Grenze für die Größe des Bodys. Das nginx dieses Repositorys setzt keine Grenze für die Oberfläche, deshalb begrenzt ein Proxy davor die Größe. | Die Grenze im Proxy erhöhen. |
| `500` | Die Anmeldung mit oauth2-proxy in einer älteren Version: Die Prüfung der Anmeldung (der Auth-Subrequest) hatte eine Body-Grenze von 1 MB. | Siehe unten. |
| `504` | Das Archiv braucht mehr als 600 Sekunden für die Antwort (`proxy_read_timeout 600s`). | Weniger Dateien auf einmal hochladen. |
| `502` | nginx erreicht das Archiv nicht. | [4.3](#every-page-500) |

Die Gründe für `403`, `413` und `504` stammen aus den nginx-Dateien und wurden nicht getestet. Der Eintrag `500` folgt dem Hinweis in
`deploy/nginx/README.md`.

Bei `500` die Grenzen in den Dateien der Anmeldung zählen:

```bash
grep -c 'client_max_body_size 0' /opt/ohif/nginx/pacs/login/locations.conf
```

Erwartet bei der Anmeldung mit oauth2-proxy: `2` (eine für `= /oauth2/auth`, eine für `= /oauth2/auth-admin`). Ist die Zahl kleiner,
die Zeile `client_max_body_size 0;` unter die Zeile `internal;` in jedem der beiden `location`-Blöcke schreiben. Mit
`/opt/pacs-admin/deploy/nginx/login/oauth2-proxy/locations.conf` vergleichen. Dann testen und neu laden:

```bash
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

Das Protokoll listet die Änderungen, die durch die Oberfläche gingen. Den Reiter `Protokoll` öffnen, bei `Art` den Wert `Verwaltung`
wählen und `Anzeigen` drücken. Jede Änderung erscheint mit dem Konto des Admins.

> **Prüfen**
>
> In der Oberfläche eine kleine DICOM-Datei hochladen, dann eine Datei von mehr als 1 MB. Erwartet: Die Oberfläche meldet Erfolg für
> beide, und die Studien erscheinen im Reiter `Studien` der Admin-Seite.

<a id="arc-rslave-refused"></a>
### 6.4 `arc` bleibt nach der Änderung der Compose-Datei unten

**Was man sieht.** `docker compose up -d` im dcm4chee-Ordner hält mit einem Fehler wie diesem an. Die Pfade in der eigenen Meldung
weichen ab. Der erste Pfad ist der Ordner des Volumes, der zweite ist der Mount, der ihn enthält. Die Zeilen unten stammen aus einem
Testlauf auf Docker Desktop mit dem Pfad `/tmp`; der Containername ist zu `arc` gekürzt.

```text
 Container arc Recreate
 Container arc Recreated
 Container arc Starting
Error response from daemon: path /tmp is mounted on /tmp but it is not a shared or slave mount
```

`docker compose ps -a` listet `arc` mit dem Status `Created`. Das Archiv ist unten: DICOM-Geräte bekommen Fehler, und der Viewer
zeigt nichts.

**Ursache.** Änderung A aus [modules.de.md, 2.2](modules.de.md#edits-steps) hat die Volume-Zeile `- /mnt/fs:/mnt/fs:rslave`
ergänzt. Docker akzeptiert die Option [rslave](glossary.de.md#rslave) nur, wenn der Mount, der den Ordner enthält, die
[Mount-Propagation](glossary.de.md#mount-propagation) `shared` oder `slave` hat. Auf diesem Server ist sie `private`. Docker hatte
den alten Container schon entfernt, den neuen angelegt und konnte ihn nicht starten. Schritt 3 dieses Abschnitts prüft die
Propagation vor der Änderung, und `preflight.sh` warnt vor diesem Zustand: `[WARN] Mount-Propagation von /mnt/fs: private`.

**Abhilfe.** Die Propagation des Ordners lesen. Anstelle von `/mnt/fs` den ersten Pfad der Fehlermeldung nutzen:

```bash
findmnt -T /mnt/fs -o TARGET,PROPAGATION
```

Sagt die zweite Spalte `private`, den Root-Mount auf shared stellen, dann `arc` starten:

```bash
mount --make-rshared /
findmnt -T /mnt/fs -o TARGET,PROPAGATION
cd /opt/dcm4chee-arc
docker compose up -d
```

Erwartet vom zweiten Befehl: Die zweite Spalte sagt `shared`. Der letzte Befehl startet den Container, der im Zustand `Created` ist.
dcm4chee braucht 30 Sekunden oder länger zum Start.

`mount --make-rshared /` gilt bis zum nächsten Neustart. Es dauerhaft machen auf die Weise, die das System bietet, zum Beispiel mit
einer kleinen systemd-Unit, die den Befehl beim Booten ausführt ([modules.de.md, Schritt 3](modules.de.md#edits-steps)).

Lässt sich die Propagation jetzt nicht korrigieren, zur alten Compose-Datei zurückgehen
([modules.de.md, 2.3](modules.de.md#recreate-rollback)). Das startet `arc` ohne das neue Volume:

```bash
cp -a /root/dcm4chee-compose.before-modules.yml /opt/dcm4chee-arc/docker-compose.yml
cd /opt/dcm4chee-arc
docker compose up -d
```

> **Warnung**
>
> Beide Wege brauchen einen zweiten Start von `arc`: Das Archiv bleibt 30 Sekunden oder länger unerreichbar. Änderung A behalten, wenn
> der Platten-Assistent einen Speicher angelegt hat. Ohne das Volume kann dcm4chee die Bilder auf den neuen Platten nicht lesen.

> **Prüfen**
>
> ```bash
> cd /opt/dcm4chee-arc && docker compose ps
> docker logs arc 2>&1 | grep WFLYSRV0025
> docker inspect -f '{{range .Mounts}}{{.Destination}} {{.Propagation}}{{"\n"}}{{end}}' arc | grep '^/mnt/fs '
> ```
>
> Erwartet: `arc` zeigt `Up`. Der zweite Befehl gibt eine Zeile mit `WFLYSRV0025` aus, die mit `started in` und einer Zeit endet. Nach
> dem Start gibt der letzte Befehl `/mnt/fs rslave` aus. Gibt der zweite Befehl nichts aus, warten und ihn noch einmal ausführen.

<a id="arc-log-dir"></a>
### 6.5 `absender_sammeln: ... No such file or directory` im Journal

**Was man sieht.** Die Kacheln mit den Absendern im Reiter `Firewall` bleiben leer. Das Journal des Hilfsdienstes bekommt alle
5 Minuten eine Zeile wie diese. Der Pfad und der erste Teil der Zeile hängen vom eigenen Aufbau ab. Der Text stammt vom Programm; er
wurde nicht aus einem Lauf aufgezeichnet:

```text
absender_sammeln: /var/local/dcm4chee-arc/wildfly/log/server.log: No such file or directory. ARC_LOG_DIR in /etc/default/pacs-admin auf das Log-Verzeichnis von wildfly setzen (docker inspect arc: der Mount von /opt/wildfly/standalone, darin log/)
```

Die Zeile sagt, was zu tun ist: `ARC_LOG_DIR` in `/etc/default/pacs-admin` auf den Log-Ordner von wildfly setzen. Den Ordner zeigt der
Mount von `/opt/wildfly/standalone` in `docker inspect arc`; darin liegt der Ordner `log/`.

```bash
journalctl -u pacs-verwaltung --since '1 hour ago' | grep absender_sammeln | tail -n 3
```

**Ursache.** Der Hilfsdienst liest die DICOM- und HL7-Absender aus der Datei `server.log` von dcm4chee. Er sucht die Datei im Ordner
`ARC_LOG_DIR` ([modules.de.md, 4.10](modules.de.md#firewall-settings)). Der Standard ist `/var/local/dcm4chee-arc/wildfly/log/`.
Dieser Ordner existiert nur, wenn die Compose-Datei von dcm4chee `/var/local/dcm4chee-arc/wildfly` als `/opt/wildfly/standalone`
einbindet. Bei einem anderen Mount liegt die Datei woanders. Der Rest der Firewall funktioniert; nur die Absender fehlen.

**Abhilfe.** Den Ordner auf dem Server finden, den `arc` als `/opt/wildfly/standalone` einbindet:

```bash
docker inspect -f '{{range .Mounts}}{{if eq .Destination "/opt/wildfly/standalone"}}{{.Source}}{{end}}{{end}}' arc
```

Der Befehl gibt den Ordner aus, zum Beispiel `/srv/dcm4chee/wildfly`. Gibt er nichts aus, hat `arc` keinen Mount für diesen Ordner.
Der Hilfsdienst kann das Log dann nicht lesen, und die Absender-Kacheln bleiben leer. Den Mount in die Compose-Datei von dcm4chee
eintragen, bevor man weitermacht.

Prüfen, dass die Logdatei im Unterordner `log/` dieses Ordners liegt:

```bash
ls -l /srv/dcm4chee/wildfly/log/server.log
```

`/etc/default/pacs-admin` im gewohnten Editor öffnen. Den Ordner, gefolgt von `/log/`, ohne Leerzeichen um `=` schreiben:

```text
ARC_LOG_DIR=/srv/dcm4chee/wildfly/log/
```

Den Hilfsdienst die Datei lesen lassen, dann einmal die Logs früherer Tage lesen:

```bash
systemctl restart pacs-verwaltung
set -a; . /etc/default/pacs-admin; set +a
python3 /opt/pacs-admin/server/firewall.py nachholen
```

> **Warnung**
>
> `pacs-verwaltung` nicht neu starten, solange die Kachel `Neue Festplatte` `läuft seit ...` sagt. Der Neustart stoppt die laufende
> Einrichtung mittendrin. Der Dienst schreibt keine Protokollzeile, während er neu startet ([7.3](#audit-lines-missing)).

> **Prüfen**
>
> ```bash
> set -a; . /etc/default/pacs-admin; set +a
> python3 /opt/pacs-admin/server/firewall.py absender
> ```
>
> Erwartet: eine Zeile wie `12 neue Zeilen` (die Zahl weicht ab). Das Journal bekommt keine neue Fehlerzeile `absender_sammeln`, und
> der Reiter `Firewall` füllt die Kacheln mit Absendern nach einigen Minuten.

<a id="trouble-admin-page"></a>
## 7. Admin-Seite und Protokoll

Dieses Kapitel behandelt die Seite unter `/admin/`, den Job, der den Reiter `Übersicht` füllt, und den Reiter `Protokoll`. Probleme
mit der Anmeldung stehen in [Kapitel 5](#trouble-login). Ein falscher oder verlorener Protokoll-Schlüssel steht in
[3.3](#audit-key-mismatch).

Die Seite zeigt nur einen kurzen Text, wenn ein Aufruf scheitert, weil sie die Fehlerseite von nginx nicht lesen kann. Ein 502 erscheint
deshalb als `abgelehnt (HTTP 502)`, ohne Grund. Den Grund nennt ein Log ([Kapitel 2](#log-locations)).

<a id="admin-dienst-502"></a>
### 7.1 `abgelehnt (HTTP 502)` auf der Admin-Seite

**Was man sieht.** Eines davon, auf einer Seite, die vorher funktionierte:

- Der rote Text `abgelehnt (HTTP 502)` in der Kachel `Firewall` des Reiters `Übersicht`, oder hinter dem Namen einer Aktion, zum
  Beispiel `Nach neuen Platten suchen: abgelehnt (HTTP 502)`.
- Die Infozeile des Reiters `Protokoll` sagt `Fehler: Protokoll: HTTP 502`.
- Die Kachel `Letzte Änderungen` sagt `Noch keine Änderungen über diese Seite.`, obwohl Änderungen gemacht wurden. Diese Kachel
  verbirgt jeden Fehler. Der Text beweist nicht, dass niemand etwas geändert hat.

Der Rest der Website funktioniert. Antwortet jeder Pfad mit 502 oder 404, [4.3](#every-page-500) lesen.

**Ursache.** nginx gibt jeden Aufruf an `/admin/dienst/` über den [Unix-Socket](glossary.de.md#unix-socket)
`/run/pacs-admin/verwaltung.sock` an den [Hilfsdienst](glossary.de.md#helper-service) weiter. Der Status 502 heißt, dass nginx nicht
mit dem Socket sprechen konnte. Das Fehlerlog von nginx nennt den Grund:

```bash
docker logs --tail 200 ohif 2>&1 | grep 'verwaltung.sock'
```

Diese drei Zeilen wurden in einem Test mit dem Image `nginx:1.30` aufgezeichnet und sind gekürzt. Der Anfang jeder Zeile (Datum und
Prozessnummer) weicht im eigenen Log ab:

```text
[crit] ... connect() to unix:/run/pacs-admin/verwaltung.sock failed (2: No such file or directory) while connecting to upstream, ...
[error] ... connect() to unix:/run/pacs-admin/verwaltung.sock failed (111: Connection refused) while connecting to upstream, ...
[crit] ... connect() to unix:/run/pacs-admin/verwaltung.sock failed (13: Permission denied) while connecting to upstream, ...
```

Der Text in der Klammer hinter `failed` nennt den Grund:

| Im Log | Bedeutung |
|---|---|
| `(2: No such file or directory)` | Der Container sieht keine Socket-Datei. Der Hilfsdienst läuft nicht oder lief nie, oder der Container startete, bevor der Ordner `/run/pacs-admin` wieder angelegt wurde. |
| `(111: Connection refused)` | Die Socket-Datei existiert, aber niemand lauscht darauf. Das ist der Zustand nach `systemctl stop pacs-verwaltung`: Der Dienst entfernt seine Socket-Dateien nicht, wenn systemd ihn anhält. |
| `(13: Permission denied)` | Der Socket gehört einer anderen uid als die der nginx-Worker-Prozesse. |

**Abhilfe.** Drei Prüfungen der Reihe nach durchgehen. Bei der ersten stoppen, die scheitert.

1. Der Dienst läuft, und beide Sockets sind da:

   ```bash
   systemctl is-active pacs-verwaltung
   ls -ln /run/pacs-admin/
   ```

   Erwartet: `active` und zwei Sockets, `protokoll.sock` und `verwaltung.sock`. Wenn nicht, weiter bei [3.6](#no-sockets).

2. Der Dienst antwortet. Der nächste Aufruf geht an nginx vorbei:

   ```bash
   curl -s --unix-socket /run/pacs-admin/verwaltung.sock http://localhost/admin/dienst/auftrag
   ```

   Erwartet: ein kurzer JSON-Text. Es ist `{}`, wenn seit dem Start des Dienstes keine Einrichtung einer Platte gelaufen ist. Gibt
   curl nichts oder einen Fehler aus, antwortet der Dienst nicht. Weiter bei [3.6](#no-sockets).

3. Der Eigentümer der Sockets ist die uid der nginx-Worker. Die dritte Spalte von `ls -ln` zeigt den Eigentümer. `docker top` listet
   die Prozesse des Containers mit ihrer uid:

   ```bash
   docker top ohif -eo uid,pid,comm
   ```

   Beispiel aus einem Test mit dem Image `nginx:1.30`. Der Master-Prozess läuft als root und die Worker als uid 101. Die Zahl der
   Worker hängt von den CPUs ab:

   ```text
   UID                 PID                 COMMAND
   0                   91748               nginx
   101                 91794               nginx
   101                 91795               nginx
   ```

   Im Image `ohif/app` läuft der Master-Prozess ebenfalls als unprivilegierter Benutzer ([reference.de.md](reference.de.md#permissions)).
   Die uid der Worker-Zeilen nehmen. Weicht sie vom Eigentümer der Sockets ab, `PACS_SOCKET_UID` in `/etc/default/pacs-admin` auf diese
   uid setzen und den Dienst neu starten:

   ```bash
   systemctl restart pacs-verwaltung
   ```

Bestehen alle drei Prüfungen und nginx meldet trotzdem `(2: No such file or directory)`, sieht der Container den Ordner nicht. Ein
Container behält den Ordner, der beim Start existierte ([reference.de.md](reference.de.md#sockets)). Ihn neu starten:

```bash
docker restart ohif
```

> **Warnung**
>
> Solange der Hilfsdienst unten ist oder neu startet, verliert nginx jede Protokollzeile. Nach einem Neustart geht auch die erste
> Zeile jedes nginx-Workers verloren ([reference.de.md](reference.de.md#audit-lost)). Die Benutzer arbeiten weiter, und nichts zeigt
> den Verlust. `pacs-verwaltung` selten und außerhalb der Arbeitszeit neu starten. Ein Neustart von `ohif` trennt die Verbindungen
> zum Viewer für kurze Zeit.

> **Prüfen**
>
> Die Admin-Seite mit F5 neu laden. Dann ausführen:
>
> ```bash
> docker logs --since 1m ohif 2>&1 | grep 'verwaltung.sock'
> ```
>
> Erwartet: keine Ausgabe. Die Kachel `Firewall` zeigt ihre Zahlen. Die Kachel `Letzte Änderungen` listet die eigenen Änderungen, oder
> sie sagt `Noch keine Änderungen über diese Seite.`, weil es keine gab.

<a id="cron-not-running"></a>
### 7.2 `Kein Status vorhanden` im Reiter `Übersicht`

**Was man sieht.** Die Zeile unter dem Titel des Reiters `Übersicht` sagt:

```text
Kein Status vorhanden (dashboard-status.py läuft per cron alle 5 Minuten).
```

Die Kacheln `Dienste`, `Speicher` und `Neue Festplatte` sind verborgen. Im Normalzustand sagt die Zeile
`Stand <Datum und Uhrzeit>, neu alle 5 Minuten`. Ist dieses Datum mehr als 10 Minuten alt, ist der Job stehen geblieben. Dann gilt
dieser Eintrag auch.

**Ursache.** Die Seite liest die Datei `status.json` aus `/admin/daten/status.json`. Der [cron](glossary.de.md#cron)-Job
`/etc/cron.d/pacs-dashboard` schreibt die Datei alle 5 Minuten mit `dashboard-status.py`. nginx liest sie aus dem Ordner
`/var/lib/pacs-admin/status` des Servers. Die Seite zeigt die Zeile, wenn nginx die Datei nicht liefert. Es gibt zwei Arten von
Gründen: Der Job schreibt die Datei nicht, oder nginx sieht sie nicht.

**Abhilfe.** Drei Schritte durchgehen.

**Schritt 1. Cron läuft und kennt den Job.**

```bash
systemctl is-active cron
ls -l /etc/cron.d/pacs-dashboard
```

Erwartet: `active` und eine Zeile für die Datei mit dem Eigentümer `root`. Ein minimales Debian hat kein cron. Installieren und
starten:

```bash
apt install cron
systemctl enable --now cron
```

Fehlt die Datei, sie noch einmal kopieren ([install.de.md, 4.7](install.de.md#overview-cron)). Den Namen `pacs-dashboard` ohne Punkt
behalten. Den Eigentümer `root` behalten und niemand anderem Schreibzugriff geben. Cron ignoriert eine Datei, die diese Regeln bricht
(eine typische Regel von Debian; für diese Seite nicht ausgeführt). `journalctl -u cron -n 20 --no-pager` zeigt, was cron zur Datei
sagt.

**Schritt 2. Der Job läuft ohne Fehler.** Die nächsten Befehle tun, was die Cron-Zeile tut, und zeigen die Fehlerausgabe auf dem
Bildschirm:

```bash
sh -c '{ set -a; [ ! -r /etc/default/pacs-admin ] || . /etc/default/pacs-admin; set +a; python3 /opt/pacs-admin/server/dashboard-status.py >/dev/null; }'
echo "exit code: $?"
```

Erwartet: nur die Zeile `exit code: 0`. Der Cron-Job schreibt alles, was der Befehl auf stderr ausgibt, in
`/var/log/pacs-dashboard.log`. Die Datei bleibt leer, solange alles gut ist:

```bash
tail -n 20 /var/log/pacs-dashboard.log
```

Eine Meldung aus dem Lauf von Hand oder aus dem Log nennt die Ursache:

| Meldung | Ursache und Abhilfe |
|---|---|
| `/bin/sh: 3: /etc/default/pacs-admin: Syntax error: Unterminated quoted string` | Die Einstellungsdatei hat einen Syntaxfehler, hier ein Anführungszeichen, das nie geschlossen wird. Die Shell hält an, und Python startet nicht. Die Zahl ist die Zeile, an der die Shell aufgegeben hat. Ein Lauf von Hand beginnt die Zeile mit `sh:`. Die fehlerhafte Zeile finden und korrigieren. `sh -n /etc/default/pacs-admin` prüft die Datei, ohne sie auszuführen. |
| `sh: 2: /etc/default/pacs-admin: DICOM (old)}: not found` | Ein Wert mit Leerzeichen oder geschweiften Klammern hat keine Anführungszeichen. Das ist die Meldung für die Zeile `FW_PORT_NAMES={"104": "DICOM (old)"}`. Die Shell nimmt den Teil hinter dem ersten Leerzeichen als Befehl. Der Job läuft weiter, aber die Variable ist beschädigt. Den Wert in einfache Anführungszeichen setzen ([reference.de.md](reference.de.md#env-file-rules)). |
| `dashboard-status.py: STORAGE_WARN_GB=300GB ist keine ganze Zahl ohne fuehrende Null mit hoechstens 6 Stellen (/etc/default/pacs-admin)` | `STORAGE_FREE_GB` und `STORAGE_WARN_GB` nehmen nur Ziffern, ohne führende Null und mit höchstens 6 Stellen. Diese Werte scheitern: `300GB`, `0050`, `1234567`. Der Name und der Wert in der eigenen Meldung weichen ab. |
| `dashboard-status.py: pacs-storage.sh kandidaten: <Grund>` | Der Job fragt den Platten-Assistenten nach der Schreibliste und nach leeren Platten, und dieser Aufruf ist gescheitert. Der Job schreibt `status.json` trotzdem zuerst und endet danach mit dem Exit-Code 1. Die Kachel `Speicher` sagt dann `Schreibliste nicht lesbar (LDAP-Container und pacs-storage.sh kandidaten prüfen).` Der `<Grund>` ist der Text einer `HALT:`-Zeile, oder `Exit-Code N: <letzte Zeile der Fehlerausgabe>`, oder `antwortet nicht (nach 200 s abgebrochen)`. Eintrag [8.1](#disk-halt) erklärt die `HALT:`-Zeilen. |
| `python3: can't open file '/opt/pacs-admin/server/dashboard-status.py': [Errno 2] No such file or directory` | Das Repository liegt nicht in `/opt/pacs-admin`. Den Pfad in der Cron-Datei mit dem `sed`-Befehl in [3.6](#no-sockets) ändern. |

Zwei weitere Meldungen halten den Job nicht an. Der Job schreibt die Datei trotzdem, und nur die Kachel `Dienste` bleibt verborgen:

```text
dashboard-status.py: docker nicht gefunden, die Kachel Dienste bleibt leer (Docker installieren)
dashboard-status.py: docker antwortet nicht (nach 60 s abgebrochen), die Kachel Dienste bleibt leer
```

Die erste Meldung heißt, dass `docker` nicht im Pfad des Jobs liegt. Docker ist nicht installiert, oder sein Ordner steht nicht in der
Zeile `PATH` der Cron-Datei. Die zweite Meldung heißt, dass der Docker-Daemon 60 Sekunden lang nicht geantwortet hat.

Die Schaltfläche `Jetzt suchen` der Kachel `Neue Festplatte` führt dasselbe Skript über den Hilfsdienst aus. Scheitert das Skript,
zeigt die Seite die letzte Zeile seiner Fehlerausgabe und `(HTTP 500)`. Das gilt für jede Meldung der Tabelle oben:

```text
Nach neuen Platten suchen: dashboard-status.py: STORAGE_WARN_GB=300GB ist keine ganze Zahl ohne fuehrende Null mit hoechstens 6 Stellen (/etc/default/pacs-admin) (HTTP 500)
```

Der Hilfsdienst liest `/etc/default/pacs-admin` nur beim Start. Cron liest die Datei bei jedem Lauf. Nach der Korrektur der Datei ist
der nächste Cron-Lauf sofort gut. Die Schaltfläche behält die alten Werte, bis der Dienst neu startet.

Die Kachel `Speicher` kann auch `Keine Daten zu den Platten (status.json nennt keine; STORAGE_BASE und STORAGE_PREFIX prüfen).` sagen.
Die Datei existiert, aber ihre Liste der Platten ist leer. Der Job listet die Ordner im Ordner `STORAGE_BASE`, deren Name die
Einstellung `STORAGE_PREFIX` plus Ziffern ist. Die Standardwerte sind `PACS-Data` und `/mnt/fs`, also ist eine Platte
`/mnt/fs/PACS-Data01`. Kein Ordner passt. Die Ordner und die zwei Einstellungen ansehen:

```bash
ls -d /mnt/fs/PACS-Data*
grep -E '^(STORAGE_BASE|STORAGE_PREFIX)=' /etc/default/pacs-admin
```

Der zweite Befehl gibt nichts aus, wenn die Standardwerte gelten. Die Einstellungen korrigieren oder die Mount-Punkte anlegen
([modules.de.md, 3.2](modules.de.md#disk-prepare)). Der nächste Cron-Lauf zeigt die Platten.

**Schritt 3. nginx sieht die Datei.**

```bash
ls -l --time-style=full-iso /var/lib/pacs-admin/status/status.json
docker exec ohif ls -l /srv/pacs-admin/status/
```

Erwartet: Beide Befehle listen `status.json`. Listet der erste Befehl die Datei und zeigt der zweite einen leeren Ordner oder einen
Fehler, sieht der Container den Ordner nicht. Es gibt drei Gründe:

- Die Compose-Datei hat keinen Mount für `/var/lib/pacs-admin/status`. Ihn ergänzen ([reference.de.md](reference.de.md#mounts)).
- Der Container startete, bevor der Ordner existierte, oder jemand hat den Ordner gelöscht und neu angelegt. Den Container neu
  starten: `docker restart ohif`.
- `PACS_ADMIN_VAR` ist gesetzt. Der Job schreibt dann nach `$PACS_ADMIN_VAR/status/`, und die Compose-Datei muss diesen Ordner
  einbinden.

> **Warnung**
>
> `pacs-verwaltung` nur neu starten, wenn eine Einstellung geändert wurde, die der Dienst nutzt, zum Beispiel `PACS_SOCKET_UID`. Die
> Übersicht braucht das nicht, weil cron `/etc/default/pacs-admin` bei jedem Lauf liest. Ein Neustart stoppt eine laufende Einrichtung
> einer Platte und verliert Protokollzeilen ([reference.de.md](reference.de.md#audit-lost)).

> **Prüfen**
>
> ```bash
> ls -l --time-style=full-iso /var/lib/pacs-admin/status/status.json
> date
> ```
>
> Erwartet: Die Datei hat den Eigentümer `root` und den Modus `-rw-r--r--`. Die Zeit der Datei ist weniger als 5 Minuten älter als die Zeit,
> die `date` ausgibt. `/var/log/pacs-dashboard.log` bekommt keine neue Zeile. Die Seite mit F5 neu laden. Die Zeile unter dem Titel
> sagt `Stand <Datum und Uhrzeit>, neu alle 5 Minuten`, und die Kacheln `Speicher` und `Neue Festplatte` sind zurück. Die Kachel
> `Dienste` kommt zurück, wenn Docker für den Job funktioniert.

<a id="audit-lines-missing"></a>
### 7.3 Der Reiter `Protokoll` zeigt Zeilen nicht, die man erwartet

**Was man sieht.** Man hat gesucht, eine Studie oder einen Befund geöffnet oder auf der Admin-Seite etwas geändert. Der Reiter
`Protokoll` listet es nicht. Oder der Reiter sagt `Keine Einträge in diesem Zeitraum.` für einen Tag mit Aktivität.

**Ursache.** Eine Zeile kann auf ihrem Weg verloren gehen, oder der Reiter kann sie verbergen. Die Datenbank sagt, was zutrifft. Man fragt
sie nach dem Datum und dem Syslog-Tag. Das Tag `ereignisse` enthält Suchen und geöffnete Studien und Befunde. Das Tag `admin`
enthält Änderungen auf der Admin-Seite. Das Datum ersetzen:

```bash
set -a; . /etc/default/pacs-admin; set +a
python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse 2026-10-14 2026-10-14 | tail -n 5
```

Das Programm gibt je Zeile der Datenbank eine JSON-Zeile aus. Beispiel einer Zeile ([reference.de.md](reference.de.md#audit-wire-format)):

```text
{"t":"2026-10-14T10:58:23+02:00","u":"anna","sub":"anna","ip":"192.0.2.10","r":"/dcm4chee-arc/aets/DCM4CHEE/rs/studies/1.2.3/series","status":200}
```

- Die Zeile ist da: Der Reiter verbirgt sie. Weiter mit Schritt 2.
- Die Zeile ist nicht da: Die Zeile ging verloren. Weiter mit Schritt 1.

**Abhilfe.**

**Schritt 1. Die Zeile ging verloren.** Nach den zwei bekannten Gründen suchen:

```bash
docker logs ohif 2>&1 | grep 'to syslog'
journalctl -u pacs-verwaltung --since '1 day ago' --no-pager | grep 'Protokoll nicht abgelegt'
```

- Zeilen mit `to syslog` im Log von nginx: nginx konnte die Zeile nicht übergeben, weil der Hilfsdienst unten war oder neu startete.
  Diese Zeilen sind endgültig verloren. Den Zeitpunkt der Lücke mit `journalctl -u pacs-verwaltung` finden. Den Dienst starten, wenn
  er unten ist ([3.6](#no-sockets)).
- Zeilen `Protokoll nicht abgelegt (N Zeilen), neuer Versuch in 10 s: ...` im Journal: Der Dienst konnte die Datenbank nicht
  schreiben. Er hält die Zeilen im Arbeitsspeicher und versucht es alle 10 Sekunden erneut. Der Text hinter dem Doppelpunkt nennt den
  Grund, zum Beispiel die Schlüsseldatei oder eine volle Platte. Den Grund beheben ([3.3](#audit-key-mismatch)). Der Dienst speichert
  die Zeilen beim nächsten Versuch.
- Keines von beiden: Die Anfrage lief nicht über nginx. Das Protokoll hält keinen Aufruf an einen veröffentlichten HTTP-Port von
  dcm4chee selbst fest und auch keine DICOM- oder HL7-Verbindung.

**Schritt 2. Der Reiter verbirgt die Zeile.** Der Reiter zeigt nur einen Teil dessen, was die Datenbank enthält:

| Regel des Reiters | Was sie verbirgt |
|---|---|
| Er lädt nur die Tags `ereignisse` und `admin`. | Jede andere Anfrage. Das Tag `zugriffe` enthält alle Anfragen, aber der Reiter zeigt es nie. |
| Er kennt fünf Arten von Zeilen: Studiensuche, Patientensuche, geöffnete Studie, geöffneter Befund und Änderung. | Anfragen nach Bildern, Vorschaubildern oder statischen Dateien. |
| Er überspringt eine Suche, deren einziger Filter `StudyInstanceUID` ist. | OHIF und die Seite senden so eine Suche, wenn sie eine Studie öffnen. Die Zeile `Studie geöffnet` hält das Öffnen fest. |
| Dasselbe Konto mit derselben Aktion auf derselben Studie oder Suche innerhalb von 30 Minuten ergibt eine Zeile. | Die Wiederholungen. `admin`-Zeilen werden nie zusammengefasst. |
| Er zeigt höchstens 2000 Zeilen, die neuesten zuerst. | Die älteren Zeilen. Die Infozeile sagt `N Einträge, nur die neuesten 2000, Filter enger setzen`. |
| Er überspringt eine Zeile ohne lesbares `t` oder `r` und zählt sie. | Die Infozeile ergänzt `N unlesbare Zeilen übersprungen`. |
| Die Filter `Patienten-ID` und `Patientenname` fragen dcm4chee nach den Studien. | Zeilen einer Studie, die dcm4chee nicht mehr hält, zum Beispiel einer gelöschten Studie. |
| Er lädt die Tage von `Von` bis `Bis`. Der Standard sind die letzten 30 Tage. | Tage außerhalb dieses Bereichs. Um Mitternacht weichen die Tage zwischen Server und Browser ab ([7.4](#audit-timezone)). |

`Art` auf `alle` stellen, alle anderen Filter leeren und einen Bereich wählen, der den Tag davor und den Tag danach einschließt.
`Anzeigen` drücken. Die Infozeile zeigt die Zahl der Zeilen.

> **Warnung**
>
> Die Datenbank ist der Nachweis. Der Reiter ist nur eine Ansicht davon. Eine in Schritt 1 verlorene Zeile lässt sich nicht
> wiederherstellen. `pacs-verwaltung` nicht neu starten, solange sein Journal `Protokoll nicht abgelegt` sagt: Die Zeilen im
> Arbeitsspeicher sind nach dem Neustart weg.

> **Prüfen**
>
> In der Studienliste des Viewers nach einer Studie suchen. 5 Sekunden warten. Dann ausführen:
>
> ```bash
> set -a; . /etc/default/pacs-admin; set +a
> python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse $(date +%F) | tail -n 1
> ```
>
> Erwartet: eine JSON-Zeile mit dem eigenen Konto in `u` und der Zeit der Suche in `t`. Im Reiter `Protokoll` zeigen `Heute` und
> `Anzeigen` die Suche als Zeile `Suche` ganz oben.

<a id="audit-timezone"></a>
### 7.4 Die Zeiten im Reiter `Protokoll` weichen von der Uhr ab

**Was man sieht.** Eines davon:

- Eine Zeile zeigt eine Zeit, die um ein oder zwei Stunden von der Zeit der Aktion abweicht.
- Zeilen von kurz nach Mitternacht fehlen, wenn man einen einzelnen Tag wählt, oder sie erscheinen unter dem Vortag.

**Ursache.** Drei Zeitzonen sind beteiligt. Das Protokoll speichert in jedem Fall den richtigen Zeitpunkt. Die Tagesgrenzen hängen
von der Zone ab:

| Wo | Welche Zone | Was sie tut |
|---|---|---|
| nginx im Container | Die Zone von `/etc/localtime` im Container. Ohne den Mount: UTC. | Schreibt die Zeit jeder Anfrage mit ihrem Versatz, zum Beispiel `2026-10-14T10:58:23+02:00` (Feld `t`). |
| Der Hilfsdienst auf dem Server | Die Zeitzone des Servers | Schneidet die Tage `Von` und `Bis` an der Mitternacht des Servers. |
| Der Browser | Die Zeitzone des PCs | Zeigt die Zeiten und schneidet die Tage noch einmal an der eigenen Mitternacht. |

Eine Zeile mit dem Versatz `+00:00` ist trotzdem der richtige Zeitpunkt, und der Browser zeigt sie in seiner eigenen Zone. Das
Problem sind die Tagesgrenzen. Bei einem Server in UTC und einem Browser auf `+02:00` gehören die Zeilen zwischen 00:00 und 02:00
des Browsertags für den Hilfsdienst zum Vortag, und er lädt sie nicht.

**Abhilfe.** Server, Container und Browser in dieselbe Zone bringen. Zuerst die Versätze lesen:

```bash
date +%z
docker exec ohif date +%z
```

Beide Befehle müssen denselben Versatz ausgeben, zum Beispiel `+0200`. Weicht der Container ab, `/etc/localtime` schreibgeschützt in
ihn einbinden. Die Compose-Beispiele haben diese Zeile bei den Volumes von `ohif`:

```text
      - /etc/localtime:/etc/localtime:ro
```

Den Container im Ordner seiner Compose-Datei neu anlegen:

```bash
cd /opt/ohif
docker compose up -d
```

Ein Container liest die Zeitzone beim Start (typisches Verhalten; für diese Seite nicht ausgeführt). Nach einer Änderung der Zone des
Hosts den Container neu starten: `docker restart ohif`. Bis die Zonen übereinstimmen, in `Von` einen Tag früher und in `Bis` einen Tag
später wählen.

> **Warnung**
>
> Zeilen, die schon gespeichert sind, behalten ihren Versatz. Der Zeitpunkt dieser Zeilen ist richtig, und sie brauchen keine Reparatur. Die
> Datenbank nicht bearbeiten.

> **Prüfen**
>
> ```bash
> date +%z
> docker exec ohif date +%z
> ```
>
> Erwartet: zweimal derselbe Versatz. Eine neue Zeile trägt diesen Versatz in `t`:
>
> ```bash
> set -a; . /etc/default/pacs-admin; set +a
> python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse $(date +%F) | tail -n 1
> ```
>
> Erwartet: `t` endet mit dem Versatz des Servers, zum Beispiel `+02:00`.

<a id="trouble-disk"></a>
## 8. Platten-Assistent

Dieses Kapitel behandelt die Kacheln `Speicher` und `Neue Festplatte` des Reiters `Übersicht` und das Skript `pacs-storage.sh`
dahinter ([modules.de.md, Abschnitt 3](modules.de.md#disk-assistant)). Das Skript hängt die Ausgabe jedes Aufrufs an
`/var/log/pacs-storage.log` an (die Einstellung `STORAGE_LOG`). Der Aufruf `kandidaten` schreibt kein Log. Die ersten Prüfungen des
Skripts (die Einstellungen und die Sperre) laufen, bevor das Logging beginnt. Die `HALT:`-Zeilen dieser Prüfungen erscheinen auf dem
Bildschirm und auf der Seite, aber nicht im Log. Das Log ist die erste Stelle zum Nachsehen:

```bash
tail -n 40 /var/log/pacs-storage.log
```

Scheitert eine Prüfung, gibt das Skript eine Zeile aus, die mit `HALT:` beginnt, und hält an. Eine fehlgeschlagene Aktion zeigt auf
der Admin-Seite in Rot `<Aktion>: <Grund> (HTTP <Status>)`. Die Statusnummer nennt die Art des Fehlers:

| Status | Bedeutung |
|---|---|
| 409 | Das Skript oder der Hilfsdienst hat die Aktion abgelehnt. Der Grund ist der Text der Zeile `HALT:` ohne das Wort `HALT:`. Siehe [8.1](#disk-halt). |
| 500 | Die Änderung steht in der LDAP-Konfiguration, aber `arc` hat sie nicht neu geladen. Der Grund beginnt mit `Archiv-Konfiguration nicht neu geladen`. Oder das Status-Skript ist gescheitert, und der Grund ist die letzte Zeile seiner Fehlerausgabe. Siehe [8.3](#disk-half-done) und [7.2](#cron-not-running). |
| 504 | Ein Skript lief länger als 300 Sekunden, und der Hilfsdienst hat es gestoppt. Siehe [8.3](#disk-half-done). |
| 400 | Der Hilfsdienst hat die Anfrage nicht angenommen. Die Seite mit F5 neu laden. Siehe [8.1](#disk-halt). |

Die Exit-Codes des Skripts (0, 1 und 3) stehen in [reference.de.md](reference.de.md#storage-exit-codes).

<a id="disk-halt"></a>
### 8.1 Eine `HALT:`-Zeile beim Einrichten oder Ändern einer Platte

**Was man sieht.** Eines davon:

- Der rote Kasten `Abgebrochen` in der Kachel `Neue Festplatte <Name>` zeigt eine Zeile, die mit `HALT:` beginnt. Der Text unter
  `Ausgabe des Skripts` enthält die ganze Ausgabe. Hat die Ausgabe keine Zeile `HALT:`, steht im Kasten `siehe Ausgabe`.
- Eine rote Meldung hinter dem Namen einer Aktion, zum Beispiel `Platte einrichten: <Grund> (HTTP 409)`. Bei den Schaltflächen der
  Kachel `Speicher` ist der Name der Erfolgstext der Schaltfläche und der Kurzname der Platte, zum Beispiel
  `Markierung voll entfernt: 02: <Grund> (HTTP 409)`. Der Grund ist der Text der Zeile `HALT:`.
- `nicht ausgeführt, siehe Log von pacs-storage.sh`. Das Skript endete mit einem Fehler, gab aber keine Zeile `HALT:` aus. Die
  letzten Zeilen des Logs zeigen die Ursache.
- Eine der Meldungen des Hilfsdienstes in der letzten Tabelle dieses Eintrags.

**Ursache.** Das Skript prüft vor und während jedes Schritts die Einstellungen, die Platte und das Archiv. Scheitert eine Prüfung,
gibt es `HALT:` mit dem Grund aus und hält an. Die Schritte vor dieser Zeile sind gelaufen. Die `ok`-Zeilen im Log zeigen, welche
das sind ([8.3](#disk-half-done) listet sie auf).

**Abhilfe.** Das Skript von Hand starten, um die Zeile `HALT:` auf dem Bildschirm zu sehen. Der Befehl `scan` ändert nichts. Er lässt
den Kernel nach neuen Platten suchen und listet auf, was das Skript findet:

```bash
bash /opt/pacs-admin/server/pacs-storage.sh scan
```

Die Meldung in den Tabellen unten suchen. Die Tabellen folgen der Reihenfolge der Prüfungen. Ein Name oder eine Zahl in der eigenen
Meldung weicht vom Beispiel ab.

**A. Am Anfang jedes Aufrufs.**

| Meldung | Ursache und Abhilfe |
|---|---|
| `als root aufrufen` | Das Skript lief als normaler Benutzer. Vor dieser Zeile steht kein `HALT:`. Mit `sudo -i` eine Root-Shell öffnen und den Befehl noch einmal starten. |
| `HALT: /etc/default/pacs-admin hat einen Syntaxfehler (Meldung davor)` | Die Einstellungsdatei hat einen Fehler, den bash nicht lesen kann, zum Beispiel ein Anführungszeichen, das nie geschlossen wird. Die Meldung von bash steht in der Zeile darüber, zum Beispiel ``/etc/default/pacs-admin: line 1: unexpected EOF while looking for matching `"'``. Die Zeile suchen und berichtigen. `bash -n /etc/default/pacs-admin` prüft die Datei, ohne sie auszuführen. |
| `HALT: STORAGE_MIN_GB='100GB' ist keine ganze Zahl ohne fuehrende Null mit hoechstens 6 Stellen (/etc/default/pacs-admin)` | `STORAGE_MIN_GB` und `STORAGE_FREE_GB` nehmen nur Ziffern an, ohne Einheit. Diese Werte scheitern: `100GB`, `0100`, `1234567`. Name und Wert in der eigenen Meldung weichen ab. Die Zeile berichtigen. Der nächste Aufruf liest die Datei neu. Für `STORAGE_WARN_GB` gilt dieselbe Regel. Der Status-Job prüft sie ([7.2](#cron-not-running)). |
| `HALT: STORAGE_PREFIX 'PACS Data' ungueltig (Buchstabe, dann Buchstaben, Ziffern, - und _, hoechstens 14 Zeichen: ext4-Label max. 16)` | Der Name einer Platte ist das Präfix plus zwei Ziffern, und ein ext4-Label hat höchstens 16 Zeichen. `STORAGE_PREFIX` berichtigen. Das Präfix nur ändern, bevor die erste Platte existiert. Platten mit dem alten Präfix würden sonst nicht mehr passen. |
| `HALT: laeuft schon, ein anderer Aufruf von pacs-storage.sh haelt die Sperre /run/pacs-storage.lock seit ueber 30 s` | Es läuft immer nur ein Aufruf. Die Wartezeit beträgt 30 Sekunden, für den Status-Job 120 Sekunden. Warten, bis der andere Aufruf endet, dann noch einmal versuchen. Die Schleife unten zeigt den Halter. |

Eine Zeile mit einem losen Wort, zum Beispiel `STORAGE_MIN_GB=100 GB`, besteht die Prüfung `bash -n`. Beim Einlesen der Datei gibt
bash `line 1: GB: command not found` aus, und die Einstellung bleibt ungesetzt. Das Skript nimmt dann den Standardwert, ohne eine
Zeile `HALT:`. Die Einstellungen der Datei zeigt `grep -E '^(STORAGE_|ARC_|LDAP_)' /etc/default/pacs-admin`. Jede Zeile genau
lesen.

Die nächste Schleife listet die Prozesse auf, die die Sperre halten, mit Prozessnummer und Kommandozeile. Dazu nutzt sie nur Werkzeuge,
die jedes Debian hat. Ein Kindprozess des Skripts, zum Beispiel `mkfs.ext4`, hält die Sperre auch dann noch, wenn das Skript selbst
schon beendet ist:

```bash
for p in /proc/[0-9]*; do ls -l $p/fd 2>/dev/null | grep -q /run/pacs-storage.lock && echo "${p#/proc/} $(tr '\0' ' ' < $p/cmdline)"; done
```

Auf das Ende des Halters warten. Ihn nur stoppen, wenn er hängt ([G](#disk-halt) unten). Die Datei `/run/pacs-storage.lock` nicht
löschen.

**B. Docker und LDAP.** Die Befehle `scan`, `auto`, `add`, `activate`, `grow`, `freigeben`, `anhaengen` und `abhaengen` prüfen diese
Punkte zuerst. Diese Befehle lesen den AE des Archivs vom LDAP-Server, halten also an, bevor sie etwas ändern. Der Befehl `kandidaten` macht
diese Prüfung nicht.

| Meldung | Ursache und Abhilfe |
|---|---|
| `HALT: docker nicht gefunden (Docker installieren, z. B. apt install docker.io)` | Das Skript findet keinen Befehl `docker`. Es braucht Docker, um die Konfiguration des Archivs zu lesen. Docker installieren oder dafür sorgen, dass `docker` im Pfad des Benutzers liegt, der das Skript startet. |
| `HALT: AE 'DCM4CHEE' (Geraet 'dcm4chee-arc') steht nicht im LDAP von 'ldap'. ARC_AET, ARC_DEVICE und LDAP_BASE_DN in /etc/default/pacs-admin pruefen (docs/modules.de.md#disk-assistant)` | Die drei Einstellungen passen nicht zum eigenen Archiv. Die nächsten zwei Befehle zeigen den AE-Titel und den Gerätenamen. Beide in `ARC_AET` und `ARC_DEVICE` eintragen. Auch `LDAP_BASE_DN` prüfen (Standard `dc=dcm4che,dc=org`). |
| `HALT: LDAP nicht lesbar (Container 'ldap'): <letzte Zeile>. Pruefen: docker ps (Name = LDAP_CONTAINER), LDAP_ROOTPASS oder LDAP_ROOTPASS_FILE in der Umgebung des LDAP-Containers (docs/modules.de.md#disk-assistant)` | Das Skript startet `ldapsearch` im LDAP-Container. `<letzte Zeile>` ist die letzte Zeile des Fehlers. Die nächste Tabelle listet die üblichen auf. |

```bash
curl -s http://127.0.0.1:8080/dcm4chee-arc/aets | grep -o '"dicomAETitle" *: *"[^"]*"'
curl -s http://127.0.0.1:8080/dcm4chee-arc/devices | grep -o '"dicomDeviceName" *: *"[^"]*"'
```

Der erste Befehl ist derselbe wie in [6.1](#viewer-no-studies). Der zweite Befehl ist typisch für dcm4chee-arc. Er wurde für diese
Seite nicht ausgeführt. Statt `http://127.0.0.1:8080` die `ARC_URL` der eigenen Installation nehmen.

| Letzte Zeile des Fehlers | Ursache und Abhilfe |
|---|---|
| `Error response from daemon: No such container: ldap` | Der Containername ist falsch. Dieser Text wurde mit Docker 29.8.0 aufgezeichnet. `docker ps --format '{{.Names}}'` listet die Namen auf. Den Namen des LDAP-Containers in `LDAP_CONTAINER` eintragen. |
| `Error response from daemon: container <64 Hex-Zeichen> is not running` | Der LDAP-Container ist gestoppt. Dieser Text wurde mit Docker 29.8.0 aufgezeichnet. Mit `docker start ldap` starten. `docker logs --tail 50 ldap` zeigt, warum er gestoppt ist. |
| `LDAP_ROOTPASS im LDAP-Container nicht gesetzt` | Das Skript liest das Root-Passwort aus der Umgebung des LDAP-Containers. Der Container hat weder `LDAP_ROOTPASS` noch `LDAP_ROOTPASS_FILE`. Eines davon in die Compose-Datei eintragen (Änderung C in [modules.de.md](modules.de.md#edits-overview)). |
| `ldap_bind: Invalid credentials (49)` | Der LDAP-Server hat das Root-Konto des Containers nicht angenommen. Typischer Wortlaut von OpenLDAP; für diese Seite nicht ausgeführt. `LDAP_ROOTDN` und das Passwort in der Compose-Datei prüfen. |
| `ldap_sasl_bind(SIMPLE): Can't contact LDAP server (-1)` | Der LDAP-Server läuft noch nicht oder nicht mehr. Typischer Wortlaut von OpenLDAP; für diese Seite nicht ausgeführt. `docker logs --tail 50 ldap` zeigt seinen Zustand. |

**C. Eine neue Platte formatieren (`add`).**

| Meldung | Ursache und Abhilfe |
|---|---|
| `HALT: Aufruf: add /dev/sdX [ja]` | Auf der Kommandozeile fehlt das Gerät. Die Befehle `activate`, `grow`, `freigeben`, `anhaengen` und `abhaengen` geben eine Zeile derselben Art aus. Die Seite sendet das Argument immer mit. |
| `HALT: /dev/sdc wird nicht formatiert: <Gründe>` | Das Skript formatiert nur eine leere Platte. Die Gründe stehen hinter dem Doppelpunkt, durch `;` verbunden. Die nächste Tabelle erklärt jeden einzelnen. |
| `HALT: /mnt/fs/PACS-Data02 existiert und ist nicht leer`, `HALT: Label PACS-Data02 gibt es schon` oder `HALT: PACS-Data02 steht schon im LDAP` | Diese Prüfungen schlagen selten an. Das Skript nimmt die nächste Nummer aus den Speichern im LDAP, den Ordnern unter `/mnt/fs` und den Labels in `/etc/fstab`. Ein Treffer heißt, dass etwas den Namen schon trägt: ein Ordner mit Inhalt (`ls -A /mnt/fs/PACS-Data02`), ein Dateisystem mit diesem Label, das nicht eingehängt ist (`blkid -L PACS-Data02`), oder ein Speicher im Archiv. Klären, was es ist. Es kann eine PACS-Platte sein, die ihren Mount verloren hat ([8.4](#disk-not-mounted)). Keine andere Platte unter demselben Namen formatieren. |
| `HALT: mkfs fehlgeschlagen` | `mkfs.ext4` ist gescheitert. Seine Meldung steht in der Zeile darüber. Sonst hat sich nichts geändert. Lautet sie `mkfs.ext4: command not found`, `e2fsprogs` mit `apt install e2fsprogs` installieren (typisch; nicht ausgeführt). Hat `mkfs.ext4` vor dem Fehler einen Teil der Platte beschrieben, hält der nächste Aufruf mit `Signatur` oder `erstes MiB nicht leer` an. Die Platte wie unten beschrieben löschen. |
| `HALT: mount fehlgeschlagen. fstab-Zeile steht, Sicherung /etc/fstab.bak-20261014-101503` | Die Platte ist formatiert, und die Zeile steht in `/etc/fstab`, aber das Einhängen ist gescheitert. Die Meldung von `mount` steht in der Zeile darüber. Das Datum im Dateinamen weicht ab. Weiter bei [8.3](#disk-half-done). |
| `HALT: /mnt/fs/PACS-Data02 ist nicht /dev/sdc` | Der Ordner ist eingehängt, aber dort ist ein anderes Gerät eingehängt. Weiter bei [8.3](#disk-half-done). |

Die Gründe hinter `wird nicht formatiert`:

| Grund | Bedeutung und Abhilfe |
|---|---|
| `kein Blockgeraet` | Der Pfad ist keine Platte. Den Namen mit `lsblk` prüfen. |
| `Typ part`, `Typ loop`, `Typ lvm` | Das Gerät ist keine ganze Platte. Die ganze Platte angeben (`/dev/sdc`), nicht eine Partition (`/dev/sdc1`). |
| `schreibgeschuetzt` | Die Platte ist schreibgeschützt. Den Schutz im Hypervisor oder an der Hardware aufheben. |
| `hat Partitionen` | Die Platte hat eine Partitionstabelle mit Partitionen. |
| `in Benutzung (LVM/RAID)` | LVM oder RAID nutzt die Platte. Eine andere Platte nehmen oder diese mit den Werkzeugen von LVM oder RAID freigeben. |
| `Signatur ext4` | Die Platte trägt eine Markierung einer früheren Nutzung. Weitere Beispiele sind `swap` und `LVM2_member`. Auch eine Partitionstabelle kann zählen, mit `gpt` oder `dos` (typischer Wortlaut; nicht ausgeführt). |
| `Dateisystem ext4` | Auf der Platte liegt ein Dateisystem. |
| `gemountet` | Die Platte ist eingehängt. `findmnt -S /dev/sdc` zeigt, wo. Prüfen, ob das richtige Gerät genannt wurde. |
| `steht in /etc/fstab` | Eine Zeile in `/etc/fstab` nennt dieses Gerät. Gerätenamen wie `/dev/sdc` können sich nach einem Neustart ändern, die Zeile kann also zu einer anderen Platte gehören. `grep -w /dev/sdc /etc/fstab` zeigt sie. Das Skript entfernt nie selbst eine Zeile. |
| `Swap` | Die Platte wird als Swap-Bereich genutzt. |
| `kleiner als 100 GiB` | Die Platte ist kleiner als `STORAGE_MIN_GB`. Die Zahl in der eigenen Meldung ist der eigene Wert. Eine größere Platte nehmen oder `STORAGE_MIN_GB` senken, wenn eine kleinere gewollt ist. |
| `erstes MiB nicht leer` | Das erste Megabyte der Platte enthält Daten, die nicht null sind. |

**Eine Platte löschen, die gelöscht werden darf.** Die Gründe `hat Partitionen`, `Signatur`, `Dateisystem` und `erstes MiB nicht leer`
bedeuten, dass jemand die Platte schon benutzt hat. Steht fest, dass es die richtige Platte ist und sie nichts enthält, was gebraucht
wird, kann man sie löschen.

> **Warnung**
>
> Die nächsten zwei Befehle zerstören die Daten auf der Platte sofort. Nichts holt sie zurück. Den Gerätenamen zweimal prüfen.
> `lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINT` zeigt Größe, Modell und Seriennummer jeder Platte. Ein falscher Name löscht eine
> Platte des Systems oder des Archivs. Nie eine Platte löschen, die eingehängt ist oder in `/etc/fstab` steht. Nie eine Prüfung
> des Skripts abschwächen, um eine Platte zu formatieren, die es ablehnt.

```bash
wipefs -a /dev/sdc
dd if=/dev/zero of=/dev/sdc bs=1M count=1
```

`wipefs -a` entfernt die Markierungen (Signaturen) früherer Dateisysteme und Tabellen. Das erste MiB leert es nicht. `dd` schreibt
Nullen hinein. Beide Schritte wurden an einer Datei getestet, die eine Swap-Signatur trug. Nach `wipefs -a` war die Signatur weg, und
das erste MiB war noch nicht leer. Nach `dd` war das erste MiB leer. Der ext4-Fall folgt der Handbuchseite von `wipefs` und wurde
nicht ausgeführt. Zeigt `lsblk` unter der Platte noch Partitionen, den Kernel die Tabelle neu lesen lassen mit
`blockdev --rereadpt /dev/sdc` (typisch; nicht ausgeführt). Dann `Jetzt suchen` wählen oder bis zu 5 Minuten warten.

**D. Eine Platte ins Archiv aufnehmen (`activate`; `add` führt es am Ende aus).**

| Meldung | Ursache und Abhilfe |
|---|---|
| `HALT: /mnt/fs/PACS-Data02 ist nicht gemountet` | Dort ist keine Platte eingehängt. Siehe [8.4](#disk-not-mounted). |
| `HALT: kein Vorlage-Storage gefunden` | Der neue Speicher übernimmt die Einstellungen eines vorhandenen. Das Skript nimmt den ersten Speicher der Schreibliste des AE, sonst den Speicher mit der höchsten Nummer, der mit `STORAGE_PREFIX` beginnt. Es fand keinen oder nur den neuen. Dem AE in der dcm4chee-Oberfläche einen ersten Speicher geben, dann die Einrichtung noch einmal starten (typisch; nicht ausgeführt). |
| `HALT: arc sieht /mnt/fs/PACS-Data02 nicht, Archiv NICHT geaendert. arc braucht '- /mnt/fs:/mnt/fs:rslave' in Compose und` | Die Meldung hat zwei Zeilen. Die zweite Zeile lautet `einmal neu erzeugen (Ausfall ~30 s). Danach: <Skript> activate PACS-Data02 ja`. Die Seite zeigt nur die erste Zeile. Die zweite steht unter `Ausgabe des Skripts` und im Log. Der Container `arc` sieht den neuen Mount nicht, weil seinem Volume die Option `rslave` fehlt ([Glossar](glossary.de.md#rslave)). Die Änderung aus [modules.de.md, Abschnitt 2](modules.de.md#recreate-arc) ausführen. Bleibt `arc` danach ausgefallen, siehe [6.4](#arc-rslave-refused). Dann `bash /opt/pacs-admin/server/pacs-storage.sh activate PACS-Data02 ja` ausführen. Die Platte ist schon formatiert und eingehängt, `activate` formatiert also nichts. |
| `HALT: arc kann in /mnt/fs/PACS-Data02 nicht schreiben, Archiv NICHT geaendert` | Die Testdatei ließ sich in `arc` nicht als Benutzer `STORAGE_OWNER` schreiben. Der Eigentümer des Ordners ist falsch. `docker exec arc id wildfly` zeigt die Nummern des Kontos, unter dem WildFly läuft ([modules.de.md, Schritt 3](modules.de.md#disk-prepare)). Die Nummern als `UID:GID` in `STORAGE_OWNER` eintragen. Den Eigentümer des Ordners setzen: `chown 1023:1023 /mnt/fs/PACS-Data02 && chmod 755 /mnt/fs/PACS-Data02` (die eigenen Nummern nehmen). Dann `activate PACS-Data02 ja` ausführen. |
| `HALT: Storage PACS-Data02 nicht angelegt`, `HALT: dcmObjectStorageID nicht ergaenzt` oder `HALT: dcmMetadataStorageID nicht ergaenzt` | Die Änderung im LDAP ist gescheitert. Die Meldung von `ldapmodify` steht über der Zeile `HALT:`. `docker logs --tail 50 ldap` kann helfen. Die Schritte davor sind gelaufen. Weiter bei [8.3](#disk-half-done). |
| `ACHTUNG: Archiv-Konfiguration nicht neu geladen (Antwort 000). Die Aenderung steht im LDAP, ...` | Diese Zeile beginnt mit `ACHTUNG:`, nicht mit `HALT:`. Der Exit-Code ist 3. Weiter bei [8.3](#disk-half-done). |
| `ACHTUNG: PACS-Data02 nicht in http://127.0.0.1:8080/dcm4chee-arc/storage` | Die Einrichtung endete mit Exit-Code 0, aber die Liste der Speicher des Archivs zeigt den neuen Namen nicht. Die Kachel kann trotzdem `eingerichtet` sagen. Weiter bei [8.3](#disk-half-done), zur Prüfung im Fall C. |

**E. Schaltflächen der Kachel `Speicher` (`freigeben`, `anhaengen`, `abhaengen`).**

| Meldung | Ursache und Abhilfe |
|---|---|
| `HALT: /mnt/fs/PACS-Data02 ist nicht gemountet` | Siehe [8.4](#disk-not-mounted). |
| `HALT: PACS-Data02 hat nur 12 GiB frei, unter 50 GB bleibt die Markierung` oder `... unter 50 GB nicht in die Schreibliste` | Die Platte hat weniger freien Platz als `STORAGE_FREE_GB`. Die Grenze gilt in GB (1 000 000 000 Byte), der freie Platz steht in GiB (1 073 741 824 Byte), 50 GB sind also etwa 47 GiB. Die Seite bietet die Schaltflächen nach den Zahlen aus `status.json` an, die 5 Minuten alt sein können. Platz auf der Platte schaffen, sie vergrößern (`grow` in [modules.de.md](modules.de.md#disk-operate)) oder eine Platte hinzufügen. |
| `HALT: PACS-Data02 steht nicht im Archiv, mit activate eintragen` | Die Platte ist eingehängt, aber das Archiv hat keinen Speicher dieses Namens. Eintragen mit `bash /opt/pacs-admin/server/pacs-storage.sh activate PACS-Data02 ja` (ohne `ja` zeigt der Befehl nur an, was er tun würde). |
| `HALT: PACS-Data01 ist in dcmObjectStorageID die letzte Platte, die nicht voll ist. Erst eine andere aufnehmen.` | Das Archiv braucht in jeder Liste einen Speicher, der nicht voll ist. `dcmObjectStorageID` ist die Liste für die Bilddateien, `dcmMetadataStorageID` die Liste für die Metadaten. Zuerst eine andere Platte mit Platz in die Liste aufnehmen (`In Schreibliste aufnehmen`). Dann diese herausnehmen. |
| `HALT: Markierung bei PACS-Data02 nicht entfernt`, `HALT: dcmObjectStorageID nicht geaendert` oder eine Zeile, die auf `nicht ergaenzt` endet | Die Änderung im LDAP ist gescheitert. Die Meldung von `ldapmodify` steht über der Zeile `HALT:`. Dieselbe Aktion noch einmal ausführen. Die Aktion überspringt, was schon erledigt ist. Ist eine Liste geändert und die andere nicht, beendet der erneute Lauf die Arbeit. |

**F. Eine Platte vergrößern (`grow`, nur auf der Kommandozeile).**

| Meldung | Ursache und Abhilfe |
|---|---|
| `HALT: /dev/sdc ist kein gemounteter Storage unter /mnt/fs` | Das Gerät gehört nicht zu einer eingehängten PACS-Platte. Die zweite Spalte unter `--- Storages` in der Ausgabe von `scan` zeigt das richtige Gerät. |
| `HALT: resize2fs fehlgeschlagen` | Die Meldung von `resize2fs` steht in der Zeile darüber. Das Dateisystem ist unverändert. |

**G. Meldungen des Hilfsdienstes.** Diese Meldungen kommen nicht vom Skript.

| Meldung | Ursache und Abhilfe |
|---|---|
| `Es wird gerade schon eine Platte eingerichtet.` (HTTP 409) | Der Hilfsdienst erlaubt eine Einrichtung zugleich. Die Kachel `Neue Festplatte <Name>` zeigt den Auftrag mit `läuft seit <Zeit>`. Auf sein Ende warten. Als Faustregel dauert eine Einrichtung Minuten, nicht Stunden. Steht in der Kachel `läuft seit` deutlich länger als 10 Minuten, zeigen die Befehle unter der Tabelle die Prozesse und das Log. Ein hängendes Skript behält den Eintrag. `systemctl restart pacs-verwaltung` löscht den Eintrag, stoppt aber auch eine laufende Einrichtung. Vorher die Warnung in [7.2](#cron-not-running) lesen. |
| `Die Platte ist nicht mehr genau so als leer erkannt. Bitte neu suchen.` (HTTP 409) | Bevor der Hilfsdienst startet, fragt er das Skript noch einmal nach den leeren Platten. Das Gerät, die Größe oder der nächste Name weicht von dem ab, was die Seite zeigte, oder die Platte ist nicht mehr leer. `Jetzt suchen` wählen (oder F5 drücken), das Angebot mit `lsblk` vergleichen und noch einmal bestätigen. Ist das Angebot verschwunden, siehe [8.2](#disk-not-offered). |
| `kein Plattengerät`, `Anfrage unvollständig` (HTTP 400) | Der Dienst nimmt nur ganze Platten mit Namen wie `/dev/sdc`, `/dev/vdb`, `/dev/xvdb` oder `/dev/nvme0n1` an. Die Seite sendet nur Namen aus ihrem Angebot, die Seite kann also veraltet sein. Mit F5 neu laden. Eine Platte anderer Art, zum Beispiel `/dev/mmcblk0`, geht nur über `add` auf der Kommandozeile. |
| `keine PACS-Platte` (HTTP 400) | Der Name der Platte ist nicht `STORAGE_PREFIX` plus Ziffern. Der Hilfsdienst liest `STORAGE_PREFIX` nur beim Start. Wurde das Präfix geändert, den Dienst neu starten, wenn keine Einrichtung läuft. |
| `FEHLER im Dienst: <Text>` am Ende von `Ausgabe des Skripts` | Der Hilfsdienst ist beim Ausführen des Skripts gescheitert, zum Beispiel weil eine Datei fehlt (`[Errno 2] No such file or directory: ...`), oder weil die Aktualisierung der Übersicht länger als 300 Sekunden lief. Der Text nennt den Fehler. Enden die Zeilen darüber mit `fertig.`, ist die Einrichtung selbst abgeschlossen. |

Die Befehle für die hängende Einrichtung aus der ersten Zeile der Tabelle (das Paket `procps` liefert `pgrep`):

```bash
pgrep -af pacs-storage.sh
pgrep -af dashboard-status.py
tail -n 20 /var/log/pacs-storage.log
```

Jede Zeile von `pgrep` zeigt die Prozessnummer und die Kommandozeile eines laufenden Skripts. Keine Ausgabe heißt, dass das Skript
nicht läuft.

> **Prüfen**
>
> ```bash
> bash /opt/pacs-admin/server/pacs-storage.sh scan
> ```
>
> Erwartet: die vier Abschnitte `--- Storages`, `--- Leere Platten (add)`, `--- Vergroesserte Platten (grow)` und
> `--- NO_MOUNT fehlt unter dem Mountpunkt (nomount)`, und keine Zeile, die mit `  HALT:` beginnt. Dann die Aktion auf der
> Seite wiederholen.

<a id="disk-not-offered"></a>
### 8.2 Die Kachel `Neue Festplatte` bietet die neue Platte nicht an

**Was man sieht.** Dem Server wurde eine neue, leere Platte gegeben. Die Kachel `Neue Festplatte` sagt trotzdem
`Keine leere Platte gefunden.`. Außerdem zeigt sie drei Schritte und die Schaltfläche `Jetzt suchen`.

**Ursache.** Die Liste der leeren Platten kommt aus dem Aufruf `pacs-storage.sh kandidaten`. Der Status-Job startet ihn alle 5
Minuten und schreibt das Ergebnis nach `status.json` ([Glossar](glossary.de.md#status-json)). `Jetzt suchen` startet denselben Job
sofort. Eine Platte fehlt in der Liste aus einem dieser Gründe:

- Der Server sieht die Platte nicht. Die Ursache liegt dann im Hypervisor, im Kabel oder im Controller.
- Das Skript lehnt die Platte ab, zum Beispiel weil sie eine Partitionstabelle oder ein Dateisystem trägt ([8.1](#disk-halt)).
- Der Name des Geräts gehört nicht zu den Namen, die die Seite annimmt.
- Der Status-Job ist gescheitert, oder die Seite zeigt alte Zahlen ([7.2](#cron-not-running)).
- Eine Einrichtung, die vor weniger als 30 Minuten endete, verbirgt die Liste. Die Kachel zeigt stattdessen das Ergebnis dieser
  Einrichtung.

**Abhilfe.** Vier Prüfungen durchgehen. Statt `/dev/sdc` den Namen der eigenen Platte nehmen.

1. Der Server sieht die Platte. `lsblk` zeigt sie als Zeile vom Typ `disk`, mit ihrer Größe, ohne Partitionen darunter und ohne
   Mountpunkt:

   ```bash
   lsblk -o NAME,SIZE,TYPE,MODEL,MOUNTPOINT
   ```

   Fehlt die Platte in der Liste, liegt die Ursache außerhalb des Servers. Das Skript bittet den Kernel bei jedem Aufruf, nach neuen
   Platten zu suchen, der Server braucht also keinen Neustart.

2. Das Skript nimmt die Platte an. Der nächste Aufruf hat kein `ja` am Ende, formatiert also nichts:

   ```bash
   bash /opt/pacs-admin/server/pacs-storage.sh add /dev/sdc
   ```

   Erwartet bei einer leeren Platte: der Abschnitt `--- Plan` und die letzte Zeile
   `Trockenlauf. Ausfuehren: /opt/pacs-admin/server/pacs-storage.sh add /dev/sdc ja`. Jetzt kein `ja` anhängen. Lautet die Ausgabe
   `HALT: /dev/sdc wird nicht formatiert: ...`, erklärt die Tabelle in [8.1](#disk-halt), Gruppe C, die Gründe. Ein `HALT:` zu
   Docker oder LDAP steht in Gruppe B.

3. Die Liste des Skripts enthält die Platte:

   ```bash
   bash /opt/pacs-admin/server/pacs-storage.sh kandidaten
   ```

   Erwartet: eine Zeile `kandidat <Gerät> <Bytes> <Modell>` für jede leere Platte, dann die Zeilen `naechste`, `vorlage`,
   `schreibliste` und `voll`. Dies ist ein Beispiel für eine Platte mit 100 GiB. Die Werte weichen auf dem eigenen Server ab, und
   die Zeile `voll` ist leer, wenn kein Speicher als voll markiert ist:

   ```text
   kandidat /dev/sdc 107374182400 QEMU HARDDISK
   naechste PACS-Data02
   vorlage PACS-Data01 10GB
   schreibliste PACS-Data01
   voll
   ```

   Gibt es keine Zeile `kandidat`, obwohl `add` einen Plan ausgab, nimmt die Seite den Gerätenamen nicht an. Die Liste enthält nur
   ganze Platten mit Namen wie `/dev/sdc`, `/dev/vdb`, `/dev/xvdb` oder `/dev/nvme0n1`. Eine Platte anderer Art, zum Beispiel
   `/dev/mmcblk0`, geht nur über `add` auf der Kommandozeile.

   Fehlt die Zeile `schreibliste`, kann das Skript den AE nicht vom LDAP-Server lesen. Die Kachel `Speicher` sagt dann
   `Schreibliste nicht lesbar (LDAP-Container und pacs-storage.sh kandidaten prüfen).`. Der Aufruf `scan` zeigt den Grund als Zeile
   `HALT:` (Gruppe B in [8.1](#disk-halt)).

4. Die Seite zeigt aktuelle Zahlen. Die Zeile unter dem Titel des Reiters `Übersicht` zeigt die Zeit des letzten Status.
   `Jetzt suchen` wählen. Meldet es einen Fehler, weiter bei [7.2](#cron-not-running).

Eine Einrichtung, die vor weniger als 30 Minuten endete, hält die Kachel bei ihrem Ergebnis. Der Titel lautet dann
`Neue Festplatte PACS-Data02`. Die Liste der leeren Platten kehrt nach 30 Minuten zurück. Um früher eine weitere Platte
einzurichten, die Kommandozeile nehmen ([modules.de.md, Abschnitt 3.1](modules.de.md#disk-what)). Der Hilfsdienst hält den Eintrag
der Einrichtung nur im Arbeitsspeicher, ein Neustart des Dienstes zeigt die Liste also wieder. Ihn nur neu starten, wenn keine
Einrichtung läuft (siehe die Warnung in [7.2](#cron-not-running)).

> **Prüfen**
>
> ```bash
> bash /opt/pacs-admin/server/pacs-storage.sh kandidaten
> ```
>
> Erwartet: eine Zeile `kandidat /dev/sdc <Bytes> <Modell>` für die neue Platte. Nach `Jetzt suchen`, oder nach höchstens 5
> Minuten, hat die Kachel den Titel `Neue Festplatte erkannt` und den Text `leer, bereit zum Einrichten`. Darunter stehen das Gerät,
> die Größe, das Modell und die Schaltfläche `Als PACS-Data02 einrichten …`.

<a id="disk-half-done"></a>
### 8.3 Eine Einrichtung oder Änderung einer Platte blieb auf halbem Weg stehen

**Was man sieht.** Eines davon:

- Die Kachel `Neue Festplatte PACS-Data02` sagt `abgebrochen <Zeit>` und zeigt den roten Kasten `Abgebrochen`. Die Liste der
  Schritte endet nach `Formatieren und einhängen` oder später. Der Kasten zeigt die Zeile `HALT:`. Er sagt `siehe Ausgabe`, wenn
  die Ausgabe keine solche Zeile hat.
- Die Kachel sagt `eingerichtet <Zeit>, Archiv nicht neu geladen` und zeigt den gelben Kasten `Archiv nicht neu geladen`. Der Kasten
  wiederholt den Text nach `ACHTUNG:` in der Ausgabe. Die Kachel behält diese Ansicht 30 Minuten nach dem Ende der Einrichtung,
  auch nachdem das Archiv neu geladen wurde. Die Ansicht ist der Eintrag dieses Laufs, nicht der Live-Zustand.
- Eine Schaltfläche der Kachel `Speicher` scheitert mit einer Meldung, die mit `Archiv-Konfiguration nicht neu geladen` beginnt und
  mit `(HTTP 500)` endet. Der Text dazwischen lautet: `(Antwort 000). Die Aenderung steht im LDAP, das Archiv arbeitet bis zum
  Neuladen mit der alten Konfiguration. In der Oberflaeche des Archivs unter Konfiguration auf Neu laden klicken.` Die Zahl hinter
  `Antwort` ist die Antwort des Archivs und weicht ab.
- Die Meldung `pacs-storage.sh antwortet nicht (nach 300 s abgebrochen), Zustand pruefen (HTTP 504)`. Der Name kann auch
  `dashboard-status.py` sein. nginx kann nach 300 Sekunden selbst antworten. Die Seite zeigt dann `abgelehnt (HTTP 504)`.
- Die Kachel sagte `läuft seit <Zeit>`, und dann wurde der Server neu gestartet, oder jemand hat den Dienst `pacs-verwaltung` neu
  gestartet. Der Dienst hält den Eintrag einer Einrichtung nur im Arbeitsspeicher, die Seite zeigt die Einrichtung also nicht mehr.

**Ursache.** Die Einrichtung hat keinen automatischen Rückweg. Das Skript hält am ersten Schritt an, der scheitert, und lässt die
früheren Schritte stehen. Das Log zeigt den letzten Schritt, der lief. Den Lauf in `/var/log/pacs-storage.log` suchen. Eine Zeile
wie `=== 2026-10-14 10:15:03 pacs-storage.sh add /dev/sdc ja` beginnt jeden Lauf. Die nächste Tabelle listet, was die letzten Zeilen
vor dem Halt bedeuten. Das Skript gibt den Exit-Code 3 aus, wenn nur das Neuladen des Archivs scheiterte
([reference.de.md](reference.de.md#storage-exit-codes)).

| Letzte Zeile vor dem Halt | Was sich geändert hat |
|---|---|
| `--- Plan` | Nichts. Das Skript hat nur geprüft. |
| `--- Platte` | `mkfs.ext4` wurde gestartet. Ist es gescheitert, kann ein Teil der Platte beschrieben sein. |
| `ok    ext4 PACS-Data02 auf /dev/sdc` | Die Platte ist formatiert. Sonst hat sich nichts geändert. |
| `ok    gemountet /mnt/fs/PACS-Data02, fstab ergaenzt (vorher /etc/fstab.bak-20261014-101503), NO_MOUNT darunter` | Der Ordner mit der Datei `NO_MOUNT` existiert. Die Zeile steht in `/etc/fstab`, mit einer Sicherung. Die Platte ist eingehängt, und der Eigentümer ist gesetzt. Das Archiv ist unverändert. |
| `--- Sichtbar im Container arc?` oder `ok    Container sieht die Platte und kann schreiben` | Nur eine Testdatei wurde geschrieben und entfernt. Das Archiv ist unverändert. |
| `ok    Storage PACS-Data02 angelegt: ...` | Der Speicher existiert in der LDAP-Konfiguration. Er steht noch nicht in der Schreibliste. |
| `ok    Schreibliste DCM4CHEE: ...` | Der Speicher steht in der Schreibliste in der LDAP-Konfiguration. `arc` arbeitet mit der alten Konfiguration, bis es sie neu lädt. |
| `ok    Archiv-Konfiguration neu geladen` | Die Einrichtung ist abgeschlossen. Es folgen nur noch die Prüfung `ok    Archiv kennt PACS-Data02` und die letzte Zeile `fertig.`. |

Eine neue Platte enthält noch keine Bilder. Das Archiv schreibt erst auf eine neue Platte, wenn die Speicher davor voll sind
([modules.de.md, Abschnitt 3.1](modules.de.md#disk-what)).

**Abhilfe.**

Schritt 1. Das Ende des Logs und den Zustand der Platte lesen. `PACS-Data02` durch den Namen der eigenen Platte ersetzen:

```bash
tail -n 60 /var/log/pacs-storage.log
bash /opt/pacs-admin/server/pacs-storage.sh scan
findmnt /mnt/fs/PACS-Data02
grep PACS-Data02 /etc/fstab
```

`findmnt` gibt nichts aus, wenn die Platte nicht eingehängt ist. `grep` gibt nichts aus, wenn `/etc/fstab` keine Zeile für die Platte
hat. Mit der Tabelle oben einen der Fälle A bis D wählen.

Schritt 2. Die Einrichtung abschließen.

**Fall A. Die Platte ist formatiert, aber nicht eingehängt.** Die letzte Zeile ist `ok    ext4 ...`, oder das Log endet mit
`HALT: mount fehlgeschlagen` oder mit `HALT: /mnt/fs/PACS-Data02 ist nicht /dev/sdc`. Zuerst die Meldung von `mount` in der Zeile
über der Zeile `HALT:` lesen und ihre Ursache beseitigen. Dann prüfen, ob das Label existiert:

```bash
blkid -L PACS-Data02
```

Gibt `blkid -L` nichts aus, ist die Formatierung nicht fertig geworden. Die Platte wie in [8.1](#disk-halt), Gruppe C, beschrieben
löschen und die Einrichtung von der Seite aus neu starten. Gibt `blkid -L` das Gerät aus, die Arbeit von Hand beenden. Die nächsten
Befehle tun, was das Skript tut. Die Befehle sind aus dem Skript abgeleitet und wurden nicht auf echter Hardware ausgeführt. Den
eigenen Namen, Pfad und Eigentümer nehmen. Der Eigentümer ist die Einstellung `STORAGE_OWNER`, standardmäßig `1023:1023`:

```bash
mkdir -p /mnt/fs/PACS-Data02
touch /mnt/fs/PACS-Data02/NO_MOUNT
chmod 444 /mnt/fs/PACS-Data02/NO_MOUNT
cp -p /etc/fstab /etc/fstab.bak-$(date +%Y%m%d-%H%M%S)
grep -q '^LABEL=PACS-Data02 ' /etc/fstab || echo 'LABEL=PACS-Data02 /mnt/fs/PACS-Data02 ext4 nosuid,nodev,nofail 0 0' >> /etc/fstab
systemctl daemon-reload
mount /mnt/fs/PACS-Data02
```

Gibt `mount` einen Fehler aus, anhalten und ihn lesen. Gibt `mount` nichts aus, den Eigentümer setzen und die Platte ins Archiv
aufnehmen:

```bash
chown 1023:1023 /mnt/fs/PACS-Data02
chmod 755 /mnt/fs/PACS-Data02
bash /opt/pacs-admin/server/pacs-storage.sh activate PACS-Data02 ja
```

**Fall B. Das Log endet mit einer Zeile `HALT:` nach `ok    gemountet`.** Die Zeile nennt die Ursache: `arc sieht ... nicht`,
`arc kann in ... nicht schreiben`, `kein Vorlage-Storage gefunden` oder eine gescheiterte LDAP-Änderung. Die Ursache wie in
[8.1](#disk-halt), Gruppe D, beschrieben beseitigen. Dann `activate` für die Platte ausführen. Der Befehl überspringt die Schritte,
die erledigt sind, und gibt zum Beispiel `ok    Storage PACS-Data02 steht schon im LDAP` aus:

```bash
bash /opt/pacs-admin/server/pacs-storage.sh activate PACS-Data02 ja
```

`add` nicht noch einmal für eine formatierte Platte ausführen. Der Befehl lehnt ab, weil die Platte nicht mehr leer ist.

**Fall C. Das Archiv hat seine Konfiguration nicht neu geladen.** Die Änderung steht in der LDAP-Konfiguration. `arc` arbeitet mit
der alten. `arc` bitten, sie neu zu laden. Das ist der Aufruf, den das Skript macht. Statt `http://127.0.0.1:8080` die `ARC_URL` der
eigenen Installation nehmen:

```bash
curl -s -m 30 -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8080/dcm4chee-arc/ctrl/reload
```

Das Skript wertet die Antworten `204` und `200` als Erfolg. Die Antwort `000` heißt, dass das Archiv nicht geantwortet hat.
`docker ps` und `docker logs --tail 50 arc` zeigen, warum. Alternativ in der dcm4chee-Oberfläche unter `Konfiguration` auf
`Neu laden` klicken, wie der Text des Skripts sagt. Dann prüfen, ob das Archiv den Speicher kennt. Das Skript macht dieselbe
Prüfung:

```bash
curl -s http://127.0.0.1:8080/dcm4chee-arc/storage | grep -o '"PACS-Data02"'
```

Erwartet: `"PACS-Data02"`. Bei einer gescheiterten Schaltflächen-Aktion (`In Schreibliste aufnehmen`, `Aus Schreibliste nehmen` oder
`Markierung entfernen`) dasselbe Neuladen ausführen und F5 drücken.

**Fall D. Nach der Antwort 504 oder nach einem Neustart.** Ein Skript, das länger als 300 Sekunden läuft, wird mit allen
Kindprozessen gestoppt und hat seine späteren Schritte nicht beendet. Nach `Formatieren und einrichten` heißt die Antwort 504:
Die Prüfung vor dem Start ist abgelaufen, es wurde also keine Einrichtung gestartet. Ein Neustart von `pacs-verwaltung` stoppt
eine laufende Einrichtung. Die letzte Zeile des Laufs im Log suchen. Die Tabelle oben nutzen, dann bei Fall A, B oder C
weitermachen. Bei einer Schaltflächen-Aktion ist der Zustand der LDAP-Konfiguration unbekannt. Dieselbe Aktion noch einmal
ausführen. Die Aktion überspringt die Schritte, die erledigt sind.

Schritt 3. Die Einrichtung rückgängig machen, nur wenn die Platte nicht mehr gewollt ist. Das nur tun, wenn das Log keine Zeile
`ok    Storage PACS-Data02 angelegt` hat. Nach dieser Zeile stattdessen die Einrichtung beenden, weil der Assistent keinen Speicher
löschen kann. Die nächsten Befehle entfernen die Zeile aus `/etc/fstab`, hängen die Platte aus und entfernen den Ordner. Die Befehle
sind aus dem Skript abgeleitet und wurden nicht auf echter Hardware ausgeführt:

```bash
cp -p /etc/fstab /etc/fstab.bak-$(date +%Y%m%d-%H%M%S)
sed -i '\|^LABEL=PACS-Data02 |d' /etc/fstab
umount /mnt/fs/PACS-Data02
systemctl daemon-reload
rm -f /mnt/fs/PACS-Data02/NO_MOUNT
rmdir /mnt/fs/PACS-Data02
```

Sagt `umount`, dass die Platte nicht eingehängt ist, mit dem nächsten Befehl weitermachen. Die Platte behält das Dateisystem und das
Label. Das Skript bietet sie erst wieder an, wenn sie gelöscht ist ([8.1](#disk-halt), Gruppe C).

> **Warnung**
>
> Die Option `nofail` in der Zeile von `/etc/fstab` behalten. Ohne sie startet ein Server mit fehlender Platte nicht. Die Dateien
> `/etc/fstab.bak-*` nicht löschen. Diese Dateien sind der Weg zurück zum Zustand vor der Einrichtung. Jeden manuellen Befehl vor dem
> Ausführen mit dem eigenen Log abgleichen.

> **Prüfen**
>
> ```bash
> findmnt /mnt/fs/PACS-Data02
> bash /opt/pacs-admin/server/pacs-storage.sh scan
> ```
>
> Erwartet: `findmnt` gibt eine Zeile mit dem Ziel `/mnt/fs/PACS-Data02`, dem Gerät und dem Typ `ext4` aus. `scan` listet die
> Platte unter `--- Storages` mit dem Wort `Schreibliste` am Ende ihrer Zeile und `keine` unter
> `--- NO_MOUNT fehlt unter dem Mountpunkt (nomount)`. Nach `Jetzt suchen`, oder nach höchstens 5 Minuten, zeigt die Kachel
> `Speicher` den Balken der Platte.

<a id="disk-not-mounted"></a>
### 8.4 Das Badge `nicht eingehängt, bitte prüfen`

**Was man sieht.** Eines davon:

- Eine Platte in der Kachel `Speicher` zeigt das rote Badge `nicht eingehängt, bitte prüfen` statt des Balkens. Die Kachel zeigt
  den Namen ohne das Präfix, zum Beispiel `01` für `PACS-Data01`. Eine Platte mit diesem Badge hat keine Schaltfläche.
- Eine Schaltfläche oder das Skript meldet `HALT: /mnt/fs/PACS-Data01 ist nicht gemountet`.

**Ursache.** Der Ordner `/mnt/fs/PACS-Data01` existiert, aber dort ist nichts eingehängt. Der Status-Job prüft, ob der Ordner ein
Mountpunkt ist. Die üblichen Gründe:

- Die Platte ist weg. Hypervisor, Kabel und Controller ansehen.
- Das Einhängen scheiterte beim Start des Servers. Die Option `nofail` lässt den Server ohne die Platte starten.
- Die Zeile für die Platte fehlt in `/etc/fstab`.
- Jemand hat `umount` ausgeführt.

Das Archiv kann die Bilder auf dieser Platte nicht lesen. Der Viewer kann die Studien nicht zeigen, die auf dieser Platte liegen.
Der Ordner unter dem Mountpunkt gehört root, hat den Modus 755 und enthält die Datei `NO_MOUNT` (Modus 444). Die Datei zeigt, dass
die Platte fehlt. Was dcm4chee mit neuen Bildern macht, solange ein Speicher der Schreibliste fehlt, wurde nicht getestet.

**Abhilfe.** Klären, was der Server sieht:

```bash
lsblk -f
blkid -L PACS-Data01
grep PACS-Data01 /etc/fstab
dmesg | tail -n 30
```

| Was man sieht | Bedeutung und Abhilfe |
|---|---|
| `blkid -L` gibt nichts aus | Der Server sieht keine Platte mit diesem Label. Die Platte im Hypervisor neu anbinden oder das Kabel prüfen. `dmesg` kann Fehler der Platte zeigen (typisch; nicht ausgeführt). Dann `bash /opt/pacs-admin/server/pacs-storage.sh scan` ausführen, das den Kernel erneut nach Platten suchen lässt. |
| `blkid -L` gibt ein Gerät aus, und `grep` gibt keine Zeile aus | Die Zeile in `/etc/fstab` fehlt. `/etc/fstab` sichern, dann die Zeile `LABEL=PACS-Data01 /mnt/fs/PACS-Data01 ext4 nosuid,nodev,nofail 0 0` anhängen. `ls -l /etc/fstab.bak-*` listet die Sicherungen auf, die der Assistent gemacht hat. Dann `systemctl daemon-reload` ausführen und die Platte einhängen (nächste Zeile). |
| Beide geben etwas aus | Die Platte mit `mount /mnt/fs/PACS-Data01` einhängen. Die Meldung lesen. |

Meldet `mount` ein beschädigtes Dateisystem, die Platte nicht formatieren. Zuerst nur lesend mit `fsck.ext4 -n /dev/sdc` prüfen
(typisch; nicht ausgeführt). Mit dem Eigentümer der Daten klären, wie es weitergeht.

Nach dem Einhängen der Platte drei Dinge prüfen:

```bash
findmnt /mnt/fs/PACS-Data01
bash /opt/pacs-admin/server/pacs-storage.sh scan
docker exec arc ls /mnt/fs/PACS-Data01 | head
```

`scan` muss die Platte unter `--- Storages` listen. Listet `scan` die Platte unter `--- NO_MOUNT fehlt unter dem Mountpunkt (nomount)`,
`bash /opt/pacs-admin/server/pacs-storage.sh nomount ja` ausführen. Der Aufruf `docker exec` muss die Ordner des Archivs zeigen,
nicht nur `NO_MOUNT`. Ein Mount, der auf dem Host nach dem Start von `arc` erscheint, wird durch die Option `rslave` an `arc`
weitergegeben. Zeigt `arc` nur `NO_MOUNT`, Änderung A in [modules.de.md](modules.de.md#edits-overview) prüfen.

**Kann die Platte nicht bald zurückkehren,** sie aus der Schreibliste nehmen, damit neue Bilder auf eine andere Platte gehen. Die
Seite hat keine Schaltfläche für eine fehlende Platte, also die Kommandozeile nehmen. Der erste Aufruf gibt den Plan aus. Der zweite
Aufruf macht die Änderung und bittet `arc`, seine Konfiguration neu zu laden:

```bash
bash /opt/pacs-admin/server/pacs-storage.sh abhaengen PACS-Data01
bash /opt/pacs-admin/server/pacs-storage.sh abhaengen PACS-Data01 ja
```

Das Skript lehnt ab, wenn keine andere Platte mit Platz in der Liste bleibt. Die Meldung lautet
`HALT: PACS-Data01 ist in dcmObjectStorageID die letzte Platte, die nicht voll ist. Erst eine andere aufnehmen.` (Gruppe E in
[8.1](#disk-halt)). Ist die Platte zurück und eingehängt, nimmt die Schaltfläche `In Schreibliste aufnehmen` sie wieder in die Liste
auf.

> **Warnung**
>
> Keine Dateien im Ordner `/mnt/fs/PACS-Data01` anlegen, solange dort keine Platte eingehängt ist. Eine Datei in diesem Ordner
> verschwindet unter dem Mount, sobald die Platte zurückkehrt, und belegt Platz der Systemplatte.

> **Prüfen**
>
> ```bash
> findmnt /mnt/fs/PACS-Data01
> ```
>
> Erwartet: eine Zeile mit dem Ziel `/mnt/fs/PACS-Data01`, dem Gerät und dem Typ `ext4`. Nach `Jetzt suchen`, oder nach höchstens
> 5 Minuten, zeigt die Kachel `Speicher` den Balken und die Größe der Platte statt des Badges.

<a id="trouble-firewall"></a>
## 9. Firewall

Dieses Kapitel behandelt die Firewall: den Reiter `Firewall` der Admin-Seite
([Wörter auf dem Bildschirm](glossary.de.md#screen-firewall)), die Unit `pacs-firewall` und das Programm `firewall.py`
([modules.de.md, Abschnitt 4](modules.de.md#firewall)). Drei Stellen zeigen ihren Zustand:

- Das Badge oben im Reiter `Firewall`: `wirksam`, `nicht wirksam` oder `ausgeschaltet`.
- Die Kachel `Firewall` des Reiters `Übersicht`.
- Der Befehl `firewall.py status`. Er liest die `FW_`-Einstellungen aus `/etc/default/pacs-admin`, deshalb laden die Befehle dieses
  Kapitels zuerst diese Datei.

Die Firewall berührt SSH (Port 22) nie. Eine SSH-Sitzung offen halten, solange die Firewall bearbeitet wird.

<a id="firewall-lockout-brake"></a>
### 9.1 Kein Zugriff mehr, nachdem Firewall-Regeln gespeichert wurden

**Was man sieht.** Nach dem Speichern von Regeln im Reiter `Firewall` oder nach dem ersten Start der Firewall eines davon:

- Eine Modalität oder ein HL7-Sender meldet einen fehlgeschlagenen Versand.
- Ein Kollege kann den Viewer oder die Admin-Seite nicht öffnen. Der Browser meldet eine abgelehnte Verbindung (typisch).
- Ein Programm, das die REST-Schnittstelle von dcm4chee aufruft, bekommt "connection refused".

SSH funktioniert weiter. Funktioniert SSH auch nicht, liegt die Ursache nicht an dieser Firewall. Die Konsole der virtuellen
Maschine nehmen.

**Ursache.** Ein Port im Modus `gesperrt` weist jede neue Verbindung von einer Quelle ab, die nicht in der Liste des Ports steht.
Der Client bekommt "connection refused". Vor dem Speichern prüft die Seite nur eines: Der eigene Rechner muss den ersten Web-Port
weiter erreichen (443 in einer Standardinstallation). Die Prüfung schützt keine anderen Benutzer, keine anderen Ports, keine
Benutzer über IPv6 und keine Benutzer hinter einem Reverse-Proxy ([modules.de.md, 4.11](modules.de.md#firewall-lockout)). Der
eingebaute Regelsatz gilt, solange keine `firewall.json` existiert und `FW_DEFAULT_RULES` leer ist. Er sperrt sieben Ports auf
einmal ([modules.de.md, 4.2](modules.de.md#firewall-inventory)).

**Abhilfe.** In dieser Reihenfolge vorgehen.

Schritt 1. Die Notbremse ziehen. Der Befehl gibt nichts aus. Er entfernt den Sprung zur Regelkette `PACS-SPERRE`, sodass alle
Docker-Ports sofort wieder offen sind. Er löscht keine Regel und keine Datei.

```bash
systemctl stop pacs-firewall
iptables -S DOCKER-USER
```

Der zweite Befehl darf keine Zeile ausgeben, die `PACS-SPERRE` enthält. Meldet `systemctl stop` einen Fehler, ihn mit
`journalctl -u pacs-firewall -n 20 --no-pager` lesen. Eine Ursache ist eine Unit, die auf einen falschen Pfad des Repositorys zeigt
([modules.de.md, 4.4](modules.de.md#firewall-start), Schritt 3). Dann den Sprung von Hand entfernen. Der erste Befehl unten listet
ihn auf, zum Beispiel als `-A DOCKER-USER -i eth0 -j PACS-SPERRE`. Diese Zeile in den zweiten Befehl übernehmen und `-D` statt
`-A` setzen:

```bash
iptables -S DOCKER-USER
iptables -D DOCKER-USER -i eth0 -j PACS-SPERRE
```

Schritt 2. Die Regel finden, die die Verbindung gekappt hat. Der Kernel protokolliert abgewiesene Verbindungen, höchstens 10 Zeilen
pro Minute für jede Regel. Das Wort nach `pacs-` ist die Art, die Zahl ist der Port, und `SRC=` nennt den Absender:

```bash
journalctl -k --since "1 hour ago" --no-pager | grep -E 'pacs-(sperre|standard) '
```

Eine Zeile mit `pacs-sperre 9990:` stammt von der Regel des Ports 9990. Eine Zeile mit `pacs-standard` stammt von der Einstellung
`Ports ohne eigene Regel`, wenn sie `gesperrt` ist. Der Befehl liest nur den Zeitraum seit dem letzten Start des Servers. Die Kachel
`Verbindungen an Regeln` des Reiters `Firewall` listet die Quellen der letzten 7 Tage mit den Arten `abgewiesen` und
`Standard: abgewiesen`.

Schritt 3. Die Regel berichtigen. Den Reiter `Firewall` öffnen. Der Reiter öffnet sich wieder, weil die Bremse alle Ports geöffnet
hat. Das Badge sagt `nicht wirksam`. Das ist richtig: Die Regeln sind jetzt nicht angewendet. Eines davon tun, dann `Speichern`
wählen:

- Die Quelle in die Liste des Ports eintragen. Dazu die Schaltfläche `Erlauben` in der Kachel `Neu erkannt` oder in der Kachel
  `Verbindungen an Regeln` nutzen oder die Adresse oder das Netz in die Liste des Ports tippen
  ([modules.de.md, 4.6](modules.de.md#firewall-allow)).
- Den Port auf `offen` oder auf `Probelauf` setzen (Probelauf: alle kommen durch, und der Kernel protokolliert die Quellen, die nicht
  in der Liste stehen).

Ein Speichern, das Regeln ändert, lädt sie neu in den Kernel. Um die alten Regeln ohne Änderung zurückzubekommen,
`systemctl start pacs-firewall` ausführen.

> **Warnung**
>
> Die Bremse hält nicht für immer. Die Regeln kommen beim nächsten Start des Servers zurück, beim nächsten Speichern, das Regeln
> ändert, und innerhalb von 5 Minuten, nachdem sich die Liste der veröffentlichten Docker-Ports ändert, solange
> `Ports ohne eigene Regel` nicht `offen` ist. Die Regel berichtigen, bevor eines davon geschieht, sonst kehrt die Aussperrung
> zurück. Um die Firewall aus zu lassen, bis Zeit dafür ist, siehe die [Notbremse](modules.de.md#firewall-brake). Solange die Bremse
> hält, wird nichts gefiltert.

> **Prüfen**
>
> ```bash
> iptables -S DOCKER-USER
> ```
>
> Erwartet direkt nach der Bremse: keine Zeile mit `PACS-SPERRE`. Das Gerät kann sich wieder verbinden. Der Reiter `Firewall` zeigt
> das Badge `nicht wirksam` mit dem Grund `kein Sprung von DOCKER-USER nach PACS-SPERRE, die Regeln sind nicht angewendet (systemctl
> status pacs-firewall)`.
>
> Erwartet, nachdem die Regel berichtigt und gespeichert wurde: Das Badge sagt `wirksam`, die Zeile
> `-A DOCKER-USER -i eth0 -j PACS-SPERRE` ist zurück (die eigene Schnittstelle), und das Gerät verbindet sich. Einen gesperrten
> Port von einem zweiten Rechner testen wie in [modules.de.md, 4.7](modules.de.md#firewall-block), Schritt 2.

<a id="firewall-not-effective"></a>
### 9.2 Das Badge `nicht wirksam`, oder die Regeln sperren nicht

**Was man sieht.** Eines davon:

- Das rote Badge `nicht wirksam` oben im Reiter `Firewall`. Die Infozeile daneben beginnt mit `Nicht wirksam:` und nennt den Grund.
  Der Grund erscheint auch, wenn der Zeiger auf dem Badge ruht.
- Das rote Badge `ausgeschaltet`. Das Kästchen `eingeschaltet` ist nicht angehakt.
- Die Kachel `Firewall` des Reiters `Übersicht` sagt in Rot `Ausgeschaltet` statt `Wirksam`. Die Kachel nutzt dieses Wort für jeden
  Grund in der Tabelle unten, auch wenn die Regeln nur nicht angewendet sind.
- `firewall.py status` endet mit `wirksam: False` und einer Zeile `Nicht wirksam, weil: ...`.
- Ein Port im Modus `gesperrt` lässt einen Rechner durch, der nicht in seiner Liste steht. Der Test aus
  [modules.de.md, 4.7](modules.de.md#firewall-block), Schritt 2, schlägt fehl.

**Ursache.** Die Regeln leben im Kernel und wirken nur, solange die Kette `DOCKER-USER` einen Sprung zur Regelkette `PACS-SPERRE`
für die Netzwerkschnittstelle der Regeln hat. Die Seite fragt den Kernel bei jedem Laden nach diesem Sprung. Der Grund im Badge
sagt, welcher Teil fehlt:

| Grund wie angezeigt | Bedeutung | Abhilfe |
|---|---|---|
| `in /admin/ (Reiter Firewall) ausgeschaltet` | Die gespeicherten Regeln haben das Kästchen `eingeschaltet` aus. | `eingeschaltet` anhaken und `Speichern` wählen. Wurde die Unit wie in [modules.de.md, 4.12](modules.de.md#firewall-uninstall) entfernt, sie zuerst wieder installieren ([4.4](modules.de.md#firewall-start), Schritt 3). |
| `kein Sprung von DOCKER-USER nach PACS-SPERRE, die Regeln sind nicht angewendet (systemctl status pacs-firewall)` | Der Kernel hat keinen Sprung. Die Unit läuft nicht oder ist gescheitert, oder jemand hat die [Bremse](modules.de.md#firewall-brake) gezogen. | Die Unit wie unten gezeigt lesen, dann die Regeln laden. |
| `der Sprung nach PACS-SPERRE gilt fuer eine andere Schnittstelle als eth0 (firewall.py start)` | Der Sprung wurde für eine andere Netzwerkschnittstelle gesetzt als die, die die Regeln jetzt nennen. Die Standardroute hat sich verschoben, oder `FW_INTERFACE` hat sich geändert. | Die Regeln mit `firewall.py start` neu laden, wie unten gezeigt. |
| `iptables: No chain/target/match by that name. (die Kette DOCKER-USER legt Docker beim Start an: laeuft Docker?)` | Die Kette `DOCKER-USER` existiert nicht, Docker läuft also nicht. Der Text vor der Klammer ist die letzte Zeile des `iptables`-Fehlers und weicht je nach Version ab (typisch). | Docker starten: `systemctl start docker`. Die Unit startet dabei mit. |
| `iptables nicht gefunden: apt install iptables (docs/modules.de.md#firewall)` | Das Programm `iptables` fehlt. | Siehe [9.4](#firewall-tools-missing). |

**Abhilfe.** Die Unit, die Meldungen der Unit und den Kernel ansehen:

```bash
systemctl status pacs-firewall --no-pager
journalctl -u pacs-firewall -b --no-pager | tail -n 20
iptables -S DOCKER-USER
```

Erwartet, wenn alles in Ordnung ist: `Active: active (exited)` in der ersten Ausgabe (typisch für diese Art Unit) und eine
Sprungzeile wie `-A DOCKER-USER -i eth0 -j PACS-SPERRE` in der dritten. Ein Startfehler erscheint im Journal als eine Zeile, die mit
`firewall.py start:` beginnt. Typische Zeilen:

| Zeile im Journal | Bedeutung |
|---|---|
| `firewall.py start: Schnittstelle unbekannt: FW_INTERFACE in /etc/default/pacs-admin setzen` | Das Programm fand innerhalb von 60 Sekunden keine Standardroute. Die Schnittstelle mit `FW_INTERFACE` nennen ([modules.de.md, 4.4](modules.de.md#firewall-start), Schritt 1). |
| `firewall.py start: iptables-restore nicht gefunden: apt install iptables (docs/modules.de.md#firewall)` | Ein Programm fehlt: [9.4](#firewall-tools-missing). |
| `firewall.py start: FW_DEFAULT_RULES: ...` | Die Datei mit den Regeln für den ersten Start ist falsch: [9.5](#firewall-save-failed). |

Dann die Regeln laden. Ist die Unit nicht `active`, sie starten:

```bash
systemctl start pacs-firewall
```

Ist die Unit `active`, aber der Sprung fehlt oder gehört zu einer anderen Schnittstelle, die Regeln ohne Lücke neu laden. Die erste
Zeile lädt die eigenen Einstellungen:

```bash
set -a; . /etc/default/pacs-admin; set +a
python3 /opt/pacs-admin/server/firewall.py start
```

Das Programm gibt `Firewall wirksam, 8 Regeln` aus (die Zahl der eigenen Regeln). Existiert die Unit nicht
(`Unit pacs-firewall.service could not be found`), sie installieren ([modules.de.md, 4.4](modules.de.md#firewall-start), Schritt 3).

> **Warnung**
>
> `systemctl restart pacs-firewall` nicht nutzen, um die Regeln neu zu laden. Der Neustart entfernt zuerst den Sprung, und alle
> Docker-Ports sind offen, bis die Regeln zurück sind ([modules.de.md, 4.10](modules.de.md#firewall-settings)). Das Programm
> `firewall.py status` zeigt seine Standardwerte, wenn die erste Zeile vergessen wird: Es sucht dann die Schnittstelle der
> Standardroute und kann einen Widerspruch melden, den es auf der Seite nicht gibt.

> **Prüfen**
>
> ```bash
> systemctl is-active pacs-firewall
> iptables -S DOCKER-USER
> set -a; . /etc/default/pacs-admin; set +a
> python3 /opt/pacs-admin/server/firewall.py status | tail -n 1
> ```
>
> Erwartet: `active`, eine Zeile `-A DOCKER-USER -i eth0 -j PACS-SPERRE` (die eigene Schnittstelle) und eine letzte Zeile, die
> `wirksam: True` enthält. Im Reiter `Firewall` `Neu laden` wählen: Das Badge sagt `wirksam`.

<a id="ipv6-not-filtered"></a>
### 9.3 Das Badge `IPv6 nicht gefiltert`

**Was man sieht.** Eines davon:

- Das rote Badge `IPv6 nicht gefiltert` hinter dem Modus eines Ports in der Kachel `Ports` des Reiters `Firewall`. Ruht der Zeiger
  darauf, sagt der Text, dass Docker den Port auch über IPv6 veröffentlicht und dass diese Verbindungen an der Firewall vorbeilaufen.
- Die Kachel `Firewall` des Reiters `Übersicht` sagt in Rot `N Port über IPv6 nicht gefiltert` oder `N Ports über IPv6 nicht gefiltert`.
  Die Kachel zählt nur, solange die Regeln wirksam sind, und nur Ports, die nicht `offen` sind.
- `docker ps` zeigt für den Port einen Eintrag, der mit `[::]:` beginnt.

**Ursache.** Die Firewall filtert nur IPv4. Veröffentlicht Docker einen Port auch auf einer IPv6-Adresse, nimmt es diese
Verbindungen in `docker-proxy` an ([Glossar](glossary.de.md#docker-proxy)). Diese Verbindungen durchlaufen die Kette `DOCKER-USER`
nicht. Eine Quelle, die die Liste des Ports über IPv4 abweist, kann sich trotzdem über IPv6 verbinden. Ein Port im Modus `offen`
zeigt kein Badge, weil nichts zu filtern ist.

**Abhilfe.** Den Port nur über IPv4 veröffentlichen. Den Container finden, der ihn veröffentlicht. Die Kachel `Ports` nennt ihn unter
dem Portnamen. Oder alle Ports auflisten:

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

Die Compose-Datei dieses Containers öffnen ([modules.de.md, 2.2](modules.de.md#edits-steps), Schritt 1, zeigt, wie man sie findet).
`0.0.0.0:` vor den Host-Port des Eintrags schreiben, zum Beispiel `"0.0.0.0:11112:11112"`. Stattdessen `127.0.0.1:` schreiben, wenn
niemand den Port von einem anderen Rechner braucht. Änderung B in [modules.de.md, Abschnitt 2](modules.de.md#edits-overview) macht
das für die Ports von `arc`. Dann den Container im Ordner der Compose-Datei neu erzeugen:

```bash
cd /opt/dcm4chee-arc
docker compose up -d
```

> **Warnung**
>
> Docker stoppt und entfernt einen Container, dessen Compose-Eintrag sich geändert hat, und startet einen neuen. Bei `arc` ist das
> Archiv ausgefallen, bis dcm4chee wieder gestartet ist, meist eine Minute oder länger. Das in einem Wartungsfenster tun. Der andere
> Weg, IPv6 auf dem ganzen Server abzuschalten, kann die eigene SSH-Sitzung kappen: zuerst
> [modules.de.md, 4.3](modules.de.md#firewall-ipv6) lesen.

> **Prüfen**
>
> ```bash
> docker ps --format 'table {{.Names}}\t{{.Ports}}'
> ```
>
> Erwartet: Der Port erscheint als `0.0.0.0:11112->11112/tcp` (Beispiel), und kein Eintrag `[::]:11112->11112/tcp` bleibt. Im Reiter
> `Firewall` `Neu laden` wählen: Das Badge ist weg.

<a id="firewall-tools-missing"></a>
### 9.4 Eine Meldung wie `iptables nicht gefunden: ...`

**Was man sieht.** Eines davon:

- Eine rote Meldung oben auf der Admin-Seite. Beispiel: `Firewall laden: Firewall: docker nicht gefunden: Docker installieren,
  z. B. apt install docker.io (docs/modules.de.md#firewall) (HTTP 500)`. Ein gescheitertes Speichern zeigt
  `Firewall speichern: Firewall: ... (HTTP 500)` auf dieselbe Weise.
- Die Kachel `Firewall` des Reiters `Übersicht` zeigt denselben Text in Rot, ohne die Wörter `Firewall laden:`.
- Das Badge `nicht wirksam` mit einem Grund, der mit `iptables nicht gefunden:` beginnt.
- `firewall.py` und die Unit geben eine Zeile `firewall.py BEFEHL: ... nicht gefunden: ...` aus.

**Ursache.** Der Hilfsdienst und die Unit starten die Programme `iptables`, `iptables-restore`, `ip`, `docker` und `journalctl`.
Wird eines davon nicht gefunden, hält das Programm mit einer Zeile an, die das fehlende Programm und das Paket nennt. Die Seite
zeigt den Statusfehler als HTTP 500 mit dem Präfix `Firewall:`. Nur ein fehlendes `iptables` lässt die Seite benutzbar: Das Badge
zeigt dann den Grund. Die Meldungen und die Pakete:

| Meldung | Bedeutung | Abhilfe |
|---|---|---|
| `iptables nicht gefunden: apt install iptables (docs/modules.de.md#firewall)` | `iptables` ist nicht installiert. | `apt-get install -y iptables` |
| `iptables-restore nicht gefunden: apt install iptables (docs/modules.de.md#firewall)` | Das Programm zum Laden der Regeln fehlt. Es kommt mit demselben Paket. | `apt-get install -y iptables` |
| `ip nicht gefunden: apt install iproute2 (docs/modules.de.md#firewall). Oder FW_INTERFACE in /etc/default/pacs-admin setzen` | `ip` fehlt. Das Programm braucht es, um die Standardroute zu finden. | `apt-get install -y iproute2` oder `FW_INTERFACE` setzen ([modules.de.md, 4.4](modules.de.md#firewall-start), Schritt 1). |
| `docker nicht gefunden: Docker installieren, z. B. apt install docker.io (docs/modules.de.md#firewall)` | `docker` wird nicht gefunden. Der Status braucht es, um die veröffentlichten Ports und die Docker-Netze aufzulisten. | Docker installieren oder den Hinweis unter der Tabelle lesen. |
| `journalctl nicht gefunden: apt install systemd (docs/modules.de.md#firewall)` | `journalctl` fehlt, das Programm kann das Kernel-Log also nicht lesen. | `apt-get install -y systemd` |
| `hostname nicht gefunden: installieren (docs/modules.de.md#firewall)` | Ein Programm ohne Paket-Hinweis fehlt. | Das Programm installieren, das die Meldung nennt. |
| `docker antwortet nicht (nach 120 s abgebrochen)` | Das Programm existiert, lief aber länger als 120 Sekunden. Der Text beginnt mit dem Namen des Programms. | Docker hängt. `systemctl status docker` ansehen und `docker ps` von Hand ausführen. |
| `iptables nicht ausfuehrbar: ...` | Die Datei existiert, aber das System kann sie nicht ausführen. Der Text endet mit dem Grund des Systems. | Die Datei ansehen: `ls -l "$(command -v iptables)"`. |

Gibt `command -v docker` in der eigenen Shell einen Pfad aus, die Meldung sagt aber `docker nicht gefunden`, liegt das Programm in
einem Ordner, den systemd für den Hilfsdienst und die Unit nicht durchsucht. Docker aus einem Snap-Paket ist ein typischer Fall
(`/snap/bin/docker`). Stattdessen die Docker-Pakete der Distribution oder das eigene Repository von Docker nutzen.

**Abhilfe.** Das Paket aus der Tabelle installieren. Nichts neu starten: Der nächste Aufruf der Seite startet das Programm erneut.

```bash
apt-get install -y iptables iproute2
command -v iptables iptables-restore ip docker journalctl
```

Ist die Unit beim Start des Servers wegen des fehlenden Programms gescheitert, sie noch einmal starten:

```bash
systemctl start pacs-firewall
```

> **Prüfen**
>
> Erwartet von `command -v`: ein Pfad für jedes Programm. Dann im Reiter `Firewall` `Neu laden` wählen. Die rote Meldung ist weg,
> und das Badge sagt `wirksam`. Sagt das Badge `nicht wirksam`, weiter bei [9.2](#firewall-not-effective).

<a id="firewall-save-failed"></a>
### 9.5 `Firewall speichern: ...` oder `Firewall laden: ...` zeigt einen Fehler

**Was man sieht.** Eine rote Meldung oben auf der Admin-Seite. Der Teil nach dem Doppelpunkt ist der Grund. Die Zahl am Ende ist der
HTTP-Status:

- `Firewall speichern: <Grund> (HTTP 400)`: Der Hilfsdienst hat die Regeln nicht angenommen, oder der Kernel hat sie abgelehnt.
  Nichts hat sich geändert, oder die früheren Regeln sind zurückgekommen.
- `Firewall speichern: Firewall: <Grund> (HTTP 500)` oder `Firewall laden: Firewall: <Grund> (HTTP 500)`: Der Hilfsdienst konnte die
  Arbeit nicht tun. Der Reiter bleibt leer, oder das Speichern findet nicht statt.

Mehrere Gründe in einer Meldung sind durch ` · ` verbunden.

**Ursache.** Der Hilfsdienst prüft die Regeln vor dem Speichern, schreibt die Datei `firewall.json`, behält eine Kopie der früheren
Version und lädt die Regeln in den Kernel. Jeder dieser Schritte hat eigene Meldungen. Die Seite sendet bei jedem Speichern alle
Regeln der Datei zurück. Ein falscher Eintrag in einer von Hand bearbeiteten Datei stoppt daher jedes Speichern.

**A. Der Hilfsdienst hat die Regeln abgelehnt.** Der Name oder die Zahl in der eigenen Meldung weicht vom Beispiel ab:

| Meldung | Bedeutung | Abhilfe |
|---|---|---|
| `Port 443: dein PC (192.0.2.50) wäre danach selbst ausgesperrt. Erst ihn oder sein Netz eintragen.` | Die Aussperr-Prüfung ([modules.de.md, 4.11](modules.de.md#firewall-lockout)): Nach dem Speichern könnte der eigene Rechner den ersten Web-Port nicht mehr erreichen. | Den eigenen Rechner oder sein Netz in die Liste des Ports eintragen, dann noch einmal speichern. Ist die Adresse in der Meldung nicht die Adresse des eigenen Rechners, sieht die Eingangstür einen Proxy: siehe [4.5](#proxy-wrong-address). |
| `Schnittstelle „Ethernet“ ungültig (FW_INTERFACE setzen)` | Der Schnittstellenname ist nicht gültig. Ein gültiger Name hat 2 bis 15 Zeichen, beginnt mit einem Kleinbuchstaben und enthält nur Kleinbuchstaben, Ziffern, `_`, `.` und `-`. Ein leerer Name (`„“`) heißt, dass die Standardroute keine Schnittstelle ergab. | Den Namen mit `ip route show default` finden (das Wort nach `dev`). `FW_INTERFACE` in `/etc/default/pacs-admin` setzen und `pacs-verwaltung` neu starten ([modules.de.md, 4.10](modules.de.md#firewall-settings)). |
| `Port 70000 ungültig oder doppelt` | Die Portnummer liegt außerhalb von 1 bis 65535, oder der Port steht zweimal in der Datei. | Die Datei berichtigen (siehe unten). |
| `Port fehlt oder ist keine Zahl` | Eine Regel hat keine Portnummer. | Die Datei berichtigen. |
| `Port 22 (SSH) ist kein Docker-Port und hier nicht einstellbar` | Die Datei enthält eine Regel für Port 22. Die Firewall filtert SSH nie. | Diese Regel aus der Datei löschen. |
| `Port 8080: Modus „zu“ unbekannt` | Die Modi sind `offen`, `probelauf` und `gesperrt`. | Die Datei berichtigen. |
| `Standard „zu“ unbekannt` | Dasselbe für die Einstellung `standard`. | Die Datei berichtigen. |
| `Port 8080: „192.0.2.300“ ist keine IPv4-Adresse und kein Netz` | Eine Liste enthält einen falschen Eintrag. Die Seite prüft die Einträge, die man tippt, das weist also auf eine von Hand bearbeitete Datei hin. | Die Datei berichtigen. |
| `Regeln fehlen` | Die Anfrage enthält keine Liste von Regeln. Die Seite sendet nie eine solche Anfrage. | Die Seite mit F5 neu laden und es noch einmal versuchen. |

**B. Der Kernel hat die Regeln abgelehnt.** Die Seite zeigt `Nicht übernommen, die vorigen Regeln gelten weiter: <Grund>`. Der
Hilfsdienst hat die früheren Regeln wieder geladen. Konnte er keine früheren Regeln lesen, lautet die Meldung
`Nicht übernommen: <Grund>`, und nur die Datei wurde zurückgesetzt. In beiden Fällen ist `<Grund>` die letzte Zeile des Fehlers von
`iptables` (typisch: `iptables: No chain/target/match by that name.` oder `iptables-restore: line 7 failed`). Die üblichen Ursachen
prüfen:

```bash
systemctl is-active docker
iptables -S DOCKER-USER
```

Ist Docker nicht `active`, oder gibt der zweite Befehl `No chain/target/match by that name` aus, zuerst Docker starten. Funktionieren
beide, fehlt dem Kernel ein Teil des Regelsatzes. Die Regeln nutzen die Matches `conntrack`, `comment` und `limit`, das Log-Ziel und
das Ziel `REJECT`. Ein Kernel ohne eines davon kann diese Firewall nicht betreiben (typisch für einen abgespeckten Kernel; nicht
nachgestellt). Die Person fragen, die die Maschine betreibt.

**C. Der Reiter lädt nicht, oder ein Speichern endet mit HTTP 500.** Die Meldung beginnt mit `Firewall:`. Ein fehlendes Programm ist
[9.4](#firewall-tools-missing). Die Meldungen zur Datei:

| Meldung | Bedeutung |
|---|---|
| `Firewall: /opt/dcm4chee-arc/firewall.json: Expecting ',' delimiter: line 7 column 3 (char 112)` | `firewall.json` ist kein gültiges JSON. Das Ende der Zeile ist der Fehler des JSON-Lesers und weicht je nach Fall ab. |
| `Firewall: /opt/dcm4chee-arc/firewall.json: kein JSON-Objekt mit einer Liste regeln` | Die Datei ist JSON, hat aber nicht das Format, das das Programm erwartet ([reference.de.md](reference.de.md#firewall-json)). |
| `Firewall: FW_DEFAULT_RULES: [Errno 2] No such file or directory: '/etc/pacs-admin-firewall-start.json'` | Die Einstellung `FW_DEFAULT_RULES` nennt eine Datei, die nicht existiert. Die Einstellung zählt nur, solange keine `firewall.json` existiert. |
| `Firewall: FW_DEFAULT_RULES /etc/pacs-admin-firewall-start.json: Port 443: Modus „zu“ unbekannt` | Die Datei, die `FW_DEFAULT_RULES` nennt, enthält einen Eintrag, den Gruppe A ablehnt. |

Bei einer beschädigten `firewall.json` die letzte Kopie zurückspielen. Der Hilfsdienst legt für jedes Speichern eine Kopie im Ordner
`firewall/` unter `PACS_DIR` ab (Standard `/opt/dcm4chee-arc`). Die neueste Kopie ist die Version vor dem letzten Speichern.
Diese Kopie zurückkopieren und testen, ob die Datei gültiges JSON ist. Der Test gibt nichts aus, wenn die Datei gültig ist:

```bash
ls -t /opt/dcm4chee-arc/firewall/firewall-*.json | head -n 5
cp -p /opt/dcm4chee-arc/firewall/firewall-20261014-103012.json /opt/dcm4chee-arc/firewall.json
python3 -m json.tool /opt/dcm4chee-arc/firewall.json > /dev/null
```

Statt des Beispiels einen Dateinamen aus dem ersten Befehl nehmen. Bei einer falschen `FW_DEFAULT_RULES`-Datei sie mit demselben
Befehl `json.tool` testen und berichtigen oder die Zeile `FW_DEFAULT_RULES=...` aus `/etc/default/pacs-admin` löschen.
`pacs-verwaltung` nach der Änderung dieser Zeile neu starten ([modules.de.md, 4.10](modules.de.md#firewall-settings)). Der
Hilfsdienst liest `firewall.json` bei jedem Aufruf, eine zurückgespielte `firewall.json` braucht also keinen Neustart.

> **Warnung**
>
> Eine zurückgespielte oder berichtigte Datei ändert, was die Seite zeigt. Den Kernel ändert sie nur beim Speichern oder bei
> `firewall.py start`. Zuerst die Regeln im Reiter lesen. Regeln, die man lädt, können Ports sofort sperren, deshalb die
> [Notbremse](modules.de.md#firewall-brake) in Reichweite halten. `pacs-verwaltung` nicht neu starten, solange eine Einrichtung
> einer Platte läuft ([modules.de.md, 3.5](modules.de.md#disk-operate)).

> **Prüfen**
>
> ```bash
> python3 -m json.tool /opt/dcm4chee-arc/firewall.json > /dev/null; echo "exit code $?"
> ```
>
> Erwartet: `exit code 0`. Im Reiter `Firewall` `Neu laden` wählen: Es erscheint keine rote Meldung. Eine Änderung speichern: Die
> Meldung `Firewall speichern: erledigt` erscheint, und das Badge sagt `wirksam`.
