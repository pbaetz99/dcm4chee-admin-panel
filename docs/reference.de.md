# Referenz

[English](reference.md) | Deutsch

Diese Seite listet Fakten: Einstellungen, Werkzeuge, Dateien, Ports, den Vertrag der Eingangstür und das Format des Protokolls. Schritte enthält sie nicht. Schritte stehen in der [Installationsanleitung](install.de.md). Die Anmeldeverfahren stehen unter [Anmeldung](login.de.md). Der Platten-Assistent und die Firewall haben eine eigene Seite: [Module](modules.de.md). Fehler stehen unter [Fehlersuche](troubleshooting.de.md). Das [Glossar](glossary.de.md) erklärt die Begriffe.

1. [Konfiguration](#configuration)
2. [Werkzeuge und Pakete](#tools-and-packages)
3. [Dateien, Dienste, Ports, Sockets und Mounts](#files-ports-sockets)
4. [nginx-Rezepte und der AE-Titel](#nginx-recipes)
5. [Vertrag der Eingangstür](#front-door-contract)
6. [Protokoll](#audit-log)

Drei Wörter kommen an vielen Stellen vor. Die **Eingangstür** ist der Webserver vor der Seite, dem Hilfsdienst und dcm4chee. In diesem Repository ist das nginx. **Jedes Konto** meint jedes Konto, das die Anmeldung durchlässt. **Admin** meint ein Konto, das `/admin/` öffnen und Daten ändern darf. Siehe [Glossar](glossary.de.md#front-door).

<a id="configuration"></a>
## 1. Konfiguration

Fünf Stellen enthalten Einstellungen.

| Ort | Inhalt | Wer ändert es |
|---|---|---|
| `/etc/default/pacs-admin` | Einstellungen des Hilfsdienstes, der Firewall, des Platten-Assistenten und des Cron-Jobs | von Hand |
| `web/admin/config.js` | Titel, AE-Titel, Links und Kontoname der Seite | von Hand |
| `app-config.js` des OHIF-Viewers | wo der Viewer das Archiv findet | von Hand, für den AE-Titel mit `set-aet.sh` |
| `pacs/site.conf` in den nginx-Dateien | Hostname, Upstream-Namen, Zertifikat, Admin-Gruppe | von Hand, siehe [Abschnitt 4](#nginx-recipes) |
| `PACS_DIR/firewall.json` | die Firewall-Regeln | der Reiter Firewall |

<a id="config-variables"></a>
### 1.1 Einstellungsdatei /etc/default/pacs-admin

Die Datei `deploy/pacs-admin.env.example` listet jede Variable mit ihrer Vorgabe, auskommentiert. Die Datei nach `/etc/default/pacs-admin` kopieren und nur das einkommentieren, was auf dem Server abweicht. Eine fehlende oder leere Variable nutzt ihre Vorgabe.

Vier Programme lesen die Datei:

- systemd lädt sie für beide Units (`EnvironmentFile=-`, eine fehlende Datei ist also kein Fehler, und die Vorgaben gelten).
- Der Cron-Job lädt sie als Shell-Datei.
- `pacs-storage.sh` lädt sie selbst, bei jedem Start. Die Datei gewinnt gegen die Umgebung, die das Skript erbt.
- Die Python-Programme lesen nur ihre Umgebung. Wer eines von Hand startet, lädt die Datei zuerst:

```
set -a; . /etc/default/pacs-admin; set +a
```

<a id="env-file-rules"></a>
#### Regeln für die Datei

Die Shell und systemd lesen dieselbe Datei, verstehen aber Kommentare hinter einem Wert, Leerzeichen und CRLF-Zeilenenden verschieden. Man bleibt bei dem, was beide verstehen.

- Eine Variable pro Zeile als `NAME=Wert` schreiben, ohne Leerzeichen um `=`.
- Einfache Anführungszeichen um einen Wert mit Leerzeichen, geschweiften Klammern oder JSON setzen: `FW_PORT_NAMES='{"104": "DICOM (old)"}'`.
- Zahlen nur als Ziffern schreiben: `STORAGE_MIN_GB=100`.
- LF-Zeilenenden nutzen. Eine unter Windows gespeicherte Datei hat CRLF: `sed -i 's/\r$//' /etc/default/pacs-admin`.
- Kein `export` schreiben.
- Keine Leerzeichen um `=` schreiben.
- Keinen Kommentar hinter einen Wert schreiben: `FW_INTERFACE=eth0  # outside` ist falsch.
- In Werten keine `$VARIABLEN` und keine Befehle in Backquotes nutzen. Nur die Shell würde sie auflösen.

Die Syntax nach jeder Änderung prüfen:

```
sh -n /etc/default/pacs-admin && echo syntax ok
```

`preflight.sh` prüft die Datei ebenfalls ([Abschnitt 2.3](#command-preflight)). Ein Syntaxfehler stoppt den Cron-Job. Die Fehlermeldung geht nach `/var/log/pacs-dashboard.log`. `pacs-storage.sh` führt zuerst `bash -n` auf der Datei aus und stoppt bei einem Syntaxfehler mit `HALT: /etc/default/pacs-admin hat einen Syntaxfehler (Meldung davor)`. Die Meldung von `bash` steht in der Zeile darüber.

**Zahlenwerte.** Ganze Zahlen ohne Einheit, Vorzeichen, Leerzeichen und führende Null schreiben: `STORAGE_FREE_GB=50`, nicht `50GB`, nicht `050`. Das gilt für `PACS_SOCKET_UID`, `STORAGE_MIN_GB`, `STORAGE_FREE_GB` und `STORAGE_WARN_GB`. Die drei `STORAGE_*`-Werte haben höchstens 6 Stellen (bis 999999 GB). Längere Zahlen lassen die Rechnung in bash in `pacs-storage.sh` überlaufen, darum lehnt `dashboard-status.py` sie ebenfalls ab. `PACS_SOCKET_UID` hat höchstens 10 Stellen. Ein Wert, der keine ganze Zahl ist oder zu viele Stellen hat, stoppt das Programm mit einer Zeile, die die Variable nennt. Jedes Programm hat seinen eigenen Wortlaut:

| Programm | Geprüfte Variablen | Meldung |
|---|---|---|
| verwaltung-dienst.py | `PACS_SOCKET_UID` | `verwaltung-dienst.py: PACS_SOCKET_UID=abc ist keine ganze Zahl ohne fuehrende Null mit hoechstens 10 Stellen (/etc/default/pacs-admin)`. Eine Zahl mit bis zu 10 Stellen außerhalb von 0 bis 4294967294 ergibt `ist keine gueltige uid`. |
| dashboard-status.py | `STORAGE_FREE_GB`, `STORAGE_WARN_GB` | `dashboard-status.py: STORAGE_WARN_GB=300GB ist keine ganze Zahl ohne fuehrende Null mit hoechstens 6 Stellen (/etc/default/pacs-admin)` |
| pacs-storage.sh | `STORAGE_MIN_GB`, `STORAGE_FREE_GB` | `HALT: STORAGE_FREE_GB='50GB' ist keine ganze Zahl ohne fuehrende Null mit hoechstens 6 Stellen (/etc/default/pacs-admin)` |

Der Grund für die Regel mit der führenden Null ist bash: Es liest `08` als ungültige Oktalzahl und `010` als 8. Die Meldung landet im Journal von `pacs-verwaltung`, in `/var/log/pacs-dashboard.log` beim Cron-Job und auf dem Bildschirm bei `pacs-storage.sh`.

Ein falscher Wert in `FW_WEB_PORTS`, `FW_DICOM_PORTS` oder `FW_HL7_PORTS` stoppt nichts: Das Programm ignoriert ihn, schreibt eine Zeile mit dem Variablennamen ins Journal und nutzt die Vorgabe.

**Eine Änderung anwenden.**

- `systemctl restart pacs-verwaltung` lässt den Hilfsdienst die Datei neu lesen. Das gilt für jede Variable, die der Hilfsdienst liest, auch über `firewall.py` und `pacsdb.py`. Nicht neu starten, solange die Seite zeigt, dass eine Platte eingerichtet wird: Der Auftrag endet mit dem Dienst.
- Der Cron-Job und `pacs-storage.sh` lesen die Datei bei jedem Lauf. Ein geänderter `STORAGE_*`-Wert erreicht die Übersicht mit dem nächsten Cron-Lauf (alle 5 Minuten).
- Auch nach einer Änderung von `PACS_DIR`, `PACS_ADMIN_VAR`, `STORAGE_*` oder `DASHBOARD_CONTAINERS` den Hilfsdienst neu starten. Der Knopf „Jetzt suchen“ und jede Platten-Aktion starten `dashboard-status.py` aus dem Hilfsdienst, und das Programm nutzt die Umgebung des Dienstes, nicht die Datei. Ohne Neustart zeigt die Übersicht nach jedem Klick die alten Werte, bis der nächste Cron-Lauf die neuen schreibt.
- `pacs-firewall.service` liest die `FW_*`-Variablen und `PACS_DIR` beim Start. Um einen geänderten Wert ohne Lücke anzuwenden, `firewall.py start` mit geladenen Einstellungen ausführen (siehe [Abschnitt 2.2](#server-commands)). `systemctl restart pacs-firewall` entfernt zuerst den Sprung in die Firewall-Kette, daher sind kurz alle Ports offen.

#### Variablen

„Gelesen von“ nennt das Programm, das die Variable liest. Die Vorgaben sind gegen den Code geprüft.

Allgemein:

| Variable | Vorgabe | Gelesen von | Bedeutung |
|---|---|---|---|
| `PACS_DIR` | `/opt/dcm4chee-arc` | firewall.py, dashboard-status.py | Verzeichnis des dcm4chee-Compose-Projekts, desjenigen mit seiner `docker-compose.yml`. `firewall.json` und der Ordner `firewall/` liegen hier. Die Kachel „Dienste“ listet die Container, deren Compose-Label `com.docker.compose.project.working_dir` diesem Pfad entspricht. |
| `PACS_ADMIN_VAR` | `/var/lib/pacs-admin` | dashboard-status.py | Arbeitsverzeichnis. Die Datei `status/status.json` darunter wird als `/admin/daten/status.json` ausgeliefert. |
| `PACS_SOCKET` | `/run/pacs-admin/verwaltung.sock` | verwaltung-dienst.py | HTTP-Socket des Hilfsdienstes. nginx erwartet ihn unter `/run/pacs-admin/verwaltung.sock` in seinem Container. Höchstens 107 Byte. |
| `PACS_LOG_SOCKET` | `/run/pacs-admin/protokoll.sock` | verwaltung-dienst.py | Datagramm-Socket für die Logzeilen von nginx. Gleiches Verzeichnis wie `PACS_SOCKET`. Höchstens 107 Byte. |
| `PACS_SOCKET_UID` | `101` | verwaltung-dienst.py | Besitzer beider Sockets: die uid der nginx-Worker-Prozesse. Die uid ist 101 in den Images `nginx` und OHIF und 33 (`www-data`) bei nginx unter Debian. Im Idealfall hat kein anderes Konto auf dem Host diese uid, siehe [Abschnitt 3.6](#permissions). |
| `PROTOKOLL_DB` | `/var/lib/pacs-protokoll/protokoll.db` | pacsdb.py | Die verschlüsselte Protokoll-Datenbank. |
| `PROTOKOLL_KEY` | `/etc/pacs-protokoll.key` | pacsdb.py | Schlüsseldatei: 64 hexadezimale Zeichen in Kleinbuchstaben. Siehe [Abschnitt 6.6](#audit-key-format). |

dcm4chee:

| Variable | Vorgabe | Gelesen von | Bedeutung |
|---|---|---|---|
| `ARC_URL` | `http://127.0.0.1:8080` | pacs-storage.sh | REST-Adresse von dcm4chee, wie der Host sie sieht. Der Platten-Assistent ruft sie ohne Token auf, um die Archivkonfiguration neu zu laden. Der arc-Container muss diesen Port auf dem Host veröffentlichen. |
| `ARC_AET` | `DCM4CHEE` | pacs-storage.sh | AE-Titel des Archivs, dessen Schreibliste der Assistent ändert. Er muss mit dem AE-Titel in den nginx-Dateien, in `app-config.js` und in `config.js` übereinstimmen, siehe [Abschnitt 4.3](#ae-title). |
| `ARC_DEVICE` | `dcm4chee-arc` | pacs-storage.sh | Gerätename von dcm4chee in LDAP (`dicomDeviceName`). |
| `ARC_LOG_DIR` | `/var/local/dcm4chee-arc/wildfly/log/` | firewall.py | Verzeichnis des WildFly-`server.log` auf dem Host. Es ist die Host-Seite des Mounts von `/opt/wildfly/standalone` im arc-Container, plus `/log`. Ein falscher Wert lässt die Absenderlisten für DICOM und HL7 leer, und das Journal zeigt alle paar Minuten einen Fehler `absender_sammeln`. |
| `ARC_CONTAINER` | `arc` | pacs-storage.sh | Name des arc-Containers. Der Assistent führt darin `docker exec` aus, um zu prüfen, dass arc eine neue Platte sieht und beschreiben kann. |
| `LDAP_CONTAINER` | `ldap` | pacs-storage.sh | Name des LDAP-Containers. `ldapsearch` und `ldapmodify` laufen darin, mit dessen eigenem Root-Passwort. |
| `LDAP_BASE_DN` | `dc=dcm4che,dc=org` | pacs-storage.sh | Base DN der dcm4chee-Konfiguration in LDAP. |

Speicher (Platten-Assistent und Übersicht):

| Variable | Vorgabe | Gelesen von | Bedeutung |
|---|---|---|---|
| `STORAGE_BASE` | `/mnt/fs` | pacs-storage.sh, dashboard-status.py | Verzeichnis mit den Mountpunkten der Archivplatten. Ein Schrägstrich am Ende wird ignoriert. |
| `STORAGE_PREFIX` | `PACS-Data` | pacs-storage.sh, dashboard-status.py, verwaltung-dienst.py | Name der Platten: Präfix plus Nummer, zum Beispiel `PACS-Data01`. Derselbe Name ist das Dateisystem-Label, das Mount-Verzeichnis und die Speicher-ID. Das Präfix besteht aus einem Buchstaben, dann Buchstaben, Ziffern, `-` und `_`, höchstens 14 Zeichen (ein ext4-Label fasst mit der Nummer 16 Zeichen). Sonst bricht `pacs-storage.sh` ab. Der Hilfsdienst akzeptiert nur dieses Präfix plus Ziffern. Platten mit anderen Namen erscheinen nicht in der Übersicht. Die Übersicht zeigt Plattennamen ohne das Präfix (`prefix` in `status.json`). |
| `STORAGE_OWNER` | `1023:1023` | pacs-storage.sh | Besitzer eines neuen Dateisystems als uid:gid. Es ist das Konto von WildFly im dcm4chee-Image. |
| `STORAGE_MIN_GB` | `100` | pacs-storage.sh | Kleinste Platte, die der Assistent anbietet, in GiB (1024 x 1024 x 1024 Byte). |
| `STORAGE_FREE_GB` | `50` | pacs-storage.sh, dashboard-status.py | Freier Platz in GB (10^9 Byte), der nötig ist, um die Markierung „voll“ zu entfernen oder eine Platte in die Schreibliste aufzunehmen. Die Seite erhält den Wert als `frei_gb` in `status.json` und zeigt die beiden Knöpfe erst ab diesem Wert. |
| `STORAGE_WARN_GB` | `300` | dashboard-status.py | Bleiben auf den Platten der Schreibliste weniger als so viele GB bis zur Schwelle, fordert die Übersicht eine neue Platte an. Die Seite erhält den Wert als `warn_gb`. |
| `STORAGE_LOG` | `/var/log/pacs-storage.log` | pacs-storage.sh | Log des Platten-Assistenten. |

Firewall:

| Variable | Vorgabe | Gelesen von | Bedeutung |
|---|---|---|---|
| `FW_INTERFACE` | leer | firewall.py | Netzwerkschnittstelle, über die die Clients kommen. Leer bedeutet: die Schnittstelle der Standardroute (beim Boot wartet `firewall.py start` bis zu 60 Sekunden darauf). Der Name hat 2 bis 15 Zeichen: Kleinbuchstaben, Ziffern, `_`, `.` und `-`, beginnend mit einem Buchstaben. Das erste Speichern im Reiter Firewall legt die Schnittstelle in `firewall.json` ab (`schnittstelle`); dieser Wert hat dann Vorrang vor der Variable. Um die Schnittstelle später zu ändern, `schnittstelle` in `firewall.json` bearbeiten oder löschen. |
| `FW_WEB_PORTS` | `443,80` | firewall.py | Host-Ports des Webservers, durch Kommas getrennt. Der erste ist der https-Port: Ein Speichern im Reiter Firewall wird abgelehnt, wenn der speichernde PC den Zugang dazu verlieren würde. Im eingebauten Regelsatz sind alle offen, und die Seite fragt nach, bevor sie einen sperrt. |
| `FW_DICOM_PORTS` | `11112,2762` | firewall.py | Host-Ports für DICOM. Der erste erhält die Vorschläge unter „Neu erkannt“, die Prüfung des Client-PCs und den Probelauf im eingebauten Regelsatz. Die Absenderliste liest für diese Ports das dcm4chee-Log, übersetzt über `docker ps` auf den Container-Port (zum Beispiel `104:11112`). |
| `FW_HL7_PORTS` | `2575,12575` | firewall.py | Dasselbe für HL7. Die drei Portlisten dürfen keinen Port gemeinsam haben. Sonst fallen alle drei Listen auf ihre Vorgaben zurück. |
| `FW_DEFAULT_RULES` | leer | firewall.py | JSON-Datei im Format von `firewall.json` ([Abschnitt 1.4](#firewall-json)). Die Datei gilt, solange keine `firewall.json` existiert. Leer bedeutet: der eingebaute Regelsatz. Eine fehlende oder ungültige Datei stoppt `firewall.py start`, und der Reiter Firewall zeigt den Fehler. |
| `FW_PORT_NAMES` | leer | firewall.py | Eigene Portnamen als JSON-Objekt, zum Beispiel `'{"104": "DICOM (old)"}'`. Diese Namen ersetzen die eingebauten Namen. Ein Name hat höchstens 60 Zeichen. Text, der kein JSON-Objekt ist, wird ignoriert, und das Journal sagt das. |
| `FW_CLIENT_NAMES` | leer | firewall.py | Namensmuster von Client-PCs für DNS-Abfragen, durch Kommas getrennt. `{a..b}` zählt von a bis b wie in bash. Hat eine Grenze eine führende Null, werden alle Zahlen mit Nullen auf die Breite der Grenzen aufgefüllt. Beispiel: `'pc{01..20},ws{001..040}'` ergibt pc01 bis pc20 und ws001 bis ws040. Höchstens 100000 Namen pro Muster. Die Abfragen laufen höchstens einmal pro Stunde, und der Knopf „Jetzt suchen“ im Reiter Firewall startet eine sofort. Leer bedeutet: keine Abfragen, und die Karte ist ausgeblendet. |

Übersicht:

| Variable | Vorgabe | Gelesen von | Bedeutung |
|---|---|---|---|
| `DASHBOARD_CONTAINERS` | leer | dashboard-status.py | Container für die Kachel „Dienste“, durch Kommas oder Leerzeichen getrennt. Leer bedeutet: alle Container des Compose-Projekts in `PACS_DIR`. Gestoppte Container erscheinen rot. |

**Nur für Tests.** `FSTAB` (Vorgabe `/etc/fstab`) und `PACS_STORAGE_TEST` (wenn gesetzt, sind Loop-Geräte erlaubt) gibt es für die Tests von `pacs-storage.sh`. Auf einem Server nicht setzen.

**Variablen des LDAP-Containers.** Der Platten-Assistent meldet sich mit dem Root-Konto des LDAP-Containers an LDAP an. Das Passwort bleibt in diesem Container: `LDAP_ROOTPASS` oder `LDAP_ROOTPASS_FILE` (ein Pfad im Container). `LDAP_ROOTDN` nennt das Root-Konto. Ohne `LDAP_ROOTDN` lautet das Konto `cn=admin,` plus die Base DN des Containers. Diese Variablen gehören zum LDAP-Container, nicht zu `/etc/default/pacs-admin`. So prüft man, dass das Passwort existiert, ohne es auszugeben (der Container heißt `ldap`):

```
docker exec ldap sh -c 'test -n "$LDAP_ROOTPASS$LDAP_ROOTPASS_FILE" && echo ok'
```

<a id="config-js"></a>
### 1.2 Seiteneinstellungen: web/admin/config.js

Die Datei `web/admin/config.js` wird als `/admin/config.js` ausgeliefert. Nur Werte ändern. Damit `git pull` ohne Konflikte bleibt, die Datei nach `/opt/ohif/config.js` kopieren und die Kopie in der Compose-Datei über `/srv/pacs-admin/admin/config.js` mounten. Die Seite liest die Datei bei jedem Laden, daher die Seite nach einer Änderung neu laden.

| Schlüssel | Vorgabe | Bedeutung |
|---|---|---|
| `titel` | `'PACS-Verwaltung'` | Seitentitel und Text ganz oben. |
| `aet` | `'DCM4CHEE'` | AE-Titel des Archivs für Suche und Änderungen (`/dcm4chee-arc/aets/AET/rs`). |
| `iocmAet` | `'IOCM_QUALITY'` | AE-Titel der Ansicht abgelehnter Studien (zurückholen, endgültig löschen). Der Reiter Protokoll nutzt ihn auch, um Suchen in dieser Ansicht zu erkennen. |
| `dcm4cheeUrl` | `'/dcm4chee-arc/ui2/'` | Ziel des Links „dcm4chee“ ganz oben. Leer blendet den Link aus. |
| `viewerUrl` | `'/'` | Ziel des Links „Viewer“ ganz oben. Leer blendet den Link aus. Auf leer setzen, wenn der Viewer-Modus `none` ist: `/` leitet dann zurück nach `/admin/`. |
| `logo` | `''` | Logo für einen dunklen Hintergrund. Es muss von derselben Adresse kommen wie die Seite: `/admin/` sendet `Cross-Origin-Embedder-Policy: require-corp`, daher lädt ein Bild von einem anderen Server nicht. Eine Datei in `web/admin/` wird unter `/admin/` ausgeliefert, zum Beispiel `'/admin/logo.svg'`. Mit dem Viewer `ohif` kann man die Datei auch unter `/usr/share/nginx/html/pacs-logo.svg` mounten und `'/pacs-logo.svg'` eintragen ([Abschnitt 3.5](#mounts)). Leer zeigt nur den Titel. |
| `locale` | `'de-DE'` | Sprachkennung für Zahlen und Zeitstempel, zum Beispiel `de-AT` oder `de-CH`. DICOM-Daten (Studiendatum, Geburtsdatum) erscheinen immer als TT.MM.JJJJ. Eine ungültige Kennung fällt auf `de-DE` zurück. Die Texte bleiben deutsch. |
| `kontoUrl` | `'/oauth2/userinfo'` | Adresse, die JSON mit dem Kontonamen in `preferredUsername` liefert (die Seite akzeptiert auch `email` und `user`). Die Seite zeigt den Namen ganz oben. Beim Anmeldeverfahren oauth2-proxy beantwortet oauth2-proxy diese Adresse. Bei den Verfahren basic und none beantwortet nginx sie in derselben Form, daher funktioniert die Vorgabe. Leer zeigt keinen Namen und stellt keine Anfrage. Jede andere Antwort (404, eine HTML-Seite, eine Weiterleitung zu einem anderen Server) lässt den Namen ohne Meldung leer, und die Seite funktioniert. |
| `abmeldenUrl` | `''` | Ziel des Links „Abmelden“ neben dem Kontonamen. Leer blendet den Link aus. Bei oauth2-proxy `'/oauth2/sign_out'` eintragen, siehe [Anmeldung](login.de.md#login-oauth2). Das Anmeldeverfahren basic hat keine Abmeldung: Der Browser behält das Passwort, bis man ihn schließt. |

Wenn die Sitzung endet, zeigt die Seite „Sitzung abgelaufen, Seite neu laden (F5)“ statt eines Netzwerkfehlers. Die Seite tut das, wenn ein Aufruf eine Weiterleitung (die Anmeldeseite eines anderen Servers) oder den Status 401 erhält.

<a id="app-config-js"></a>
### 1.3 OHIF-Viewer: app-config.js

Nur beim Viewer-Modus `ohif` nötig. `deploy/app-config.js.example` nach `/opt/ohif/app-config.js` kopieren. Die Compose-Datei mountet sie über `/usr/share/nginx/html/app-config.js` des OHIF-Images, und nginx liefert sie als `/app-config.js` aus. Ohne die Datei läuft der Viewer mit der Vorgabe des Images, die das eigene Archiv nicht kennt. Die Datei enthält keinen Hostnamen: Jede Adresse entsteht aus `window.location`, daher funktioniert dieselbe Datei für https, einfaches http und einen SSH-Tunnel. Siehe [Installationsanleitung](install.de.md#viewer-config).

Im Browser prüfen: `https://pacs.example.org/app-config.js` öffnen (ohne Cache neu laden). Die Seite muss den Text der eigenen Datei zeigen. In der Browser-Konsole der Viewer-Seite muss `window.config.dataSources[0].configuration.qidoRoot` die eigene Adresse mit `/dcm4chee-arc/aets/DCM4CHEE/rs` ausgeben.

Das darf man ändern:

- Den AE-Titel `DCM4CHEE` in der Zeile `const arc = ...`. Er muss `aet` in `config.js` und `ARC_AET` entsprechen. Statt von Hand zu ändern `set-aet.sh` nutzen ([Abschnitt 4.3](#ae-title)).
- `name` und `friendlyName`: die Bezeichnung der Datenquelle, freier Text.
- `maxNumberOfWebWorkers` (CPU-Kerne für das Dekodieren von Bildern) und `maxNumRequests` (parallele Bildanfragen).

Das darf man nicht ändern:

- Die Adressen, die aus `window.location` gebaut werden.
- `supportsReject: false` und `dicomUploadEnabled: false`. Die Admin-Seite lehnt Studien ab und löscht sie, und nginx blockiert schreibende Anfragen des Viewers.
- Den Block `bulkDataURI`. dcm4chee schreibt absolute Bulk-Data-Links mit `http://` und dem Hostnamen ohne Port. Auf einer https-Seite blockiert der Browser solche Links, daher schreibt der Block sie auf die Adresse der Seite um.

<a id="firewall-json"></a>
### 1.4 Firewall-Regeln: firewall.json

Der Reiter Firewall schreibt `PACS_DIR/firewall.json` (Modus 0640). `FW_DEFAULT_RULES` nutzt dasselbe Format. Der Dienst bewahrt jede frühere Version in `PACS_DIR/firewall/` auf.

| Schlüssel | Bedeutung |
|---|---|
| `aktiv` | `true` oder `false`: Die Regeln gelten oder nicht. Vorgabe `true`. |
| `schnittstelle` | Die Schnittstelle, über die die Clients kommen. Leer oder fehlend: `FW_INTERFACE`, sonst die Standardroute. |
| `standard` | Modus für Ports ohne Regel: `offen`, `probelauf` oder `gesperrt`. Vorgabe `offen`. |
| `regeln` | Liste der Regeln. Eine Regel pro Port. |
| `ausgeblendet` | Quellen, die unter „Neu erkannt“ ausgeblendet sind, jede als `PORT QUELLE`, zum Beispiel `11112 192.0.2.50`. |
| `geaendert` | Wer die Regeln zuletzt gespeichert hat (`wer`) und wann (`zeit`). Der Dienst schreibt es. |

Eine Regel hat diese Schlüssel:

| Schlüssel | Bedeutung |
|---|---|
| `port` | Host-Port, 1 bis 65535, einmal pro Datei. Port 22 wird abgelehnt. |
| `name` | Bezeichnung, höchstens 60 Zeichen. |
| `modus` | `offen` (alle kommen durch), `probelauf` (alle kommen durch, Quellen außerhalb der Liste werden protokolliert) oder `gesperrt` (nur die Liste kommt durch). Eine Regel ohne `modus` bedeutet `gesperrt`. |
| `protokollieren` | `true`: Verbindungen protokollieren, die die Liste erlaubt (höchstens 10 Zeilen pro Minute und Regel). |
| `erlaubt` | Liste von `{"quelle": "192.0.2.0/24", "notiz": "text"}`. Eine Quelle ist eine IPv4-Adresse oder ein IPv4-Netz. Eine Notiz hat höchstens 80 Zeichen. |

Beispiel:

```json
{"aktiv": true, "standard": "probelauf", "regeln": [
  {"port": 443, "name": "Viewer und Verwaltung", "modus": "offen"},
  {"port": 8080, "name": "dcm4chee REST (http)", "modus": "gesperrt"}
]}
```

<a id="tools-and-packages"></a>
## 2. Werkzeuge und Pakete

<a id="packages"></a>
### 2.1 Pakete

Die Paketnamen gelten für Debian 12 und 13. Ubuntu nutzt dieselben Namen und ist nicht getestet. `preflight.sh` prüft all das und gibt den Installationsbefehl für Fehlendes aus.

| Werkzeug | Debian-Paket | Genutzt von |
|---|---|---|
| Python 3.7 oder neuer unter `/usr/bin/python3` | `python3` | alle Programme in `server/` und beide Units. Die Units starten genau `/usr/bin/python3`: Ein Python in `/usr/local/bin` zählt nicht. |
| SQLCipher-Bibliothek | `libsqlcipher1` unter Debian 13 (SQLCipher 4.x), `libsqlcipher0` unter Debian 12 und älter (SQLCipher 3.x) | pacsdb.py. Den Namen für die eigene Version findet man mit `apt-cache search sqlcipher`. |
| `git` | `git` | Klonen und Aktualisieren |
| `curl` | `curl` | pacs-storage.sh (ruft arc auf), die Prüfungen in den Anleitungen |
| `openssl` | `openssl` | Protokollschlüssel, Zertifikatsprüfungen, pacs-adduser.sh (ab Version 1.1.1 für den sha512-Hash), preflight.sh |
| `cron` | `cron` | `/etc/cron.d/pacs-dashboard` (Zahlen der Übersicht) |
| `ip`, `ss` | `iproute2` | firewall.py (Standardroute), preflight.sh |
| `iptables`, `iptables-restore` | `iptables` | firewall.py (Variante nft oder legacy) |
| `journalctl`, `systemctl` | `systemd` | firewall.py (Kernel-Log), pacs-storage.sh |
| `hostname` | `hostname` | firewall.py (`hostname -I`: die Adressen des Servers) |
| Docker-Engine und Compose-Plugin | Debian 13: `docker.io` und `docker-compose` (Version 2, ein Plugin). Debian 12: `docker.io` und das Paket `docker-compose-plugin` aus dem Docker-Repository. | firewall.py, dashboard-status.py, pacs-storage.sh, die Compose-Beispiele |
| `lsblk`, `blockdev`, `blkid`, `wipefs`, `findmnt`, `flock`, `unshare` | `util-linux` | pacs-storage.sh |
| `mount`, `losetup`, `swapon` | `mount` | pacs-storage.sh |
| `mkfs.ext4`, `tune2fs`, `resize2fs` | `e2fsprogs` | pacs-storage.sh |
| `udevadm` | `udev` | pacs-storage.sh |
| `cmp` | `diffutils` | pacs-storage.sh |
| `bash` 3.2 oder neuer, `awk`, `sed`, `grep`, `df`, `sort`, `tr`, `date`, `id`, `stat` | `bash`, `mawk`, `sed`, `grep`, `coreutils` | pacs-storage.sh und die Skripte in `deploy/tools/`. Immer installiert. |
| `logger` | `bsdutils` | optional: sendet Protokollzeilen aus einem anderen Programm, siehe [Abschnitt 5.7](#audit-feed) |
| `sqlcipher` | `sqlcipher` | optional: öffnet die Protokoll-Datenbank von Hand |
| `nginx` | `nginx` | nur für nginx auf dem Host. Für `http2 on` ist Version 1.25.1 oder neuer nötig. Debian 13 hat 1.26. Debian 12 hat 1.22 und braucht eine Änderung, siehe [deploy/nginx/README.de.md](../deploy/nginx/README.de.md#listener). |

`ldapsearch` und `ldapmodify` laufen im LDAP-Container. Der Host braucht dafür nichts.

Zu Debian 12: Das Debian-Paket `docker-compose` ist dort die alte Version 1 (`docker-compose` mit Bindestrich). Die Anleitungen nutzen die Plugin-Form `docker compose`.

Images: Der Container `ohif` führt nginx 1.25.1 oder neuer aus. Das Image `nginx` (getestet mit 1.30) und das OHIF-Image erfüllen das. Die Compose-Beispiele nennen die Tags des OHIF-Images und von oauth2-proxy.

<a id="server-commands"></a>
### 2.2 Befehle der Server-Programme

Die Python-Programme als root starten, mit geladenen Einstellungen (siehe [Abschnitt 1.1](#config-variables)).

| Befehl | Was er tut |
|---|---|
| `python3 /opt/pacs-admin/server/pacsdb.py test` | Selbsttest der Bibliothek für die Protokoll-Datenbank. Er nutzt einen temporären Schlüssel und eine temporäre Datenbank und berührt die Schlüsseldatei nicht. Er gibt eine Zeile aus, die mit `Selbsttest ok` beginnt. |
| `python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse 2026-10-01` | Gibt Zeilen des Protokolls als JSON-Zeilen aus, siehe [Abschnitt 6.7](#audit-read). |
| `python3 /opt/pacs-admin/server/firewall.py start` | Wendet die Regeln an. Wartet bis zu 60 Sekunden auf die Standardroute. Eine fehlerhafte Regeldatei stoppt den Befehl sofort. |
| `python3 /opt/pacs-admin/server/firewall.py stop` | Entfernt den Sprung aus `DOCKER-USER`. Alle Ports sind offen. |
| `python3 /opt/pacs-admin/server/firewall.py status` | Regeln, Zähler, Schnittstelle und ob die Regeln wirken (mit dem Grund, wenn nicht). Ohne Argument führt `firewall.py` `status` aus. |
| `python3 /opt/pacs-admin/server/firewall.py absender` | Liest die neuen Zeilen von `server.log` (DICOM- und HL7-Absender). |
| `python3 /opt/pacs-admin/server/firewall.py nachholen` | Liest einmal die rotierten Logs, danach die aktuelle Datei von Anfang an. |
| `python3 /opt/pacs-admin/server/firewall.py clients` | Fragt die Namen der Client-PCs (`FW_CLIENT_NAMES`) jetzt ab. |
| `python3 /opt/pacs-admin/server/firewall.py test` | Selbsttest. Er braucht weder iptables noch docker. Er gibt `Selbsttest ok` aus. |
| `python3 /opt/pacs-admin/server/dashboard-status.py` | Schreibt `status.json` jetzt. Er führt auch `pacs-storage.sh kandidaten` aus, das die SCSI-Hosts neu absucht. Scheitert das Skript, wird `status.json` trotzdem geschrieben und der Exit-Code ist 1, siehe die Exit-Codes weiter unten. |
| `bash /opt/pacs-admin/server/pacs-storage.sh scan` | Sucht die Platten neu ab. Listet Speicher, leere Platten, gewachsene Platten und Mountpunkte ohne `NO_MOUNT`. |
| `bash /opt/pacs-admin/server/pacs-storage.sh add /dev/sdb` | Plan für eine neue Platte. Mit `ja` als letztem Argument formatiert, mountet und registriert er die Platte. |
| `python3 /opt/pacs-admin/server/verwaltung-dienst.py` | Der Hilfsdienst. systemd startet ihn. Nicht von Hand starten, solange die Unit läuft: Die zweite Instanz weigert sich zu starten (`laeuft schon`). |

Befehle von `pacs-storage.sh`: `scan`, `auto`, `add DEVICE`, `activate ID`, `grow DEVICE`, `nomount`, `kandidaten`, `freigeben ID`, `anhaengen ID`, `abhaengen ID`. Jeder Befehl, der etwas ändert, gibt nur seinen Plan aus, solange das letzte Argument nicht `ja` ist. Alle Befehle außer `kandidaten` und `nomount` prüfen zuerst, dass LDAP lesbar ist, und stoppen sonst mit einer Zeile `HALT: ...` und dem Exit-Code 1. `scan` und `kandidaten` suchen die SCSI-Hosts neu ab, was nach `/sys` schreibt. Einzelheiten: [Module](modules.de.md#disk-assistant).

**Exit-Codes der Python-Programme.**

- `firewall.py` mit einem unbekannten Befehl gibt die Liste der Befehle aus und endet mit 1. Ein Fehlschlag (ein Programm fehlt, die Regeldatei ist kaputt, `iptables` lehnt ab) gibt eine Zeile `firewall.py BEFEHL: Grund` aus und endet mit 1. Erfolg endet mit 0.
- `pacsdb.py` mit einem unbekannten Befehl gibt seine Aufrufzeile aus und endet mit 1. Ein Problem mit der Bibliothek, dem Schlüssel oder der Datenbank gibt eine Zeile `pacsdb.py: Grund` aus und endet mit 1.
- `verwaltung-dienst.py` und `dashboard-status.py` geben eine Zeile aus, die mit dem Programmnamen beginnt, und enden mit 1, wenn eine Einstellung falsch ist (siehe die Tabelle in [Abschnitt 1.1](#env-file-rules)) oder, beim Hilfsdienst, wenn er nicht starten kann (`laeuft schon`, ein fehlendes Recht, ein Socket, der sich nicht anlegen lässt).
- `dashboard-status.py` endet außerdem mit 1, wenn `pacs-storage.sh kandidaten` mit einem Fehler stoppt oder nicht innerhalb von 200 Sekunden antwortet. Er schreibt `status.json` vorher, mit `schreibliste_bekannt` auf `false`, und die letzte Zeile auf stderr nennt den Grund, zum Beispiel den `HALT:`-Text des Skripts. Der Cron-Job legt diese Zeile in `/var/log/pacs-dashboard.log` ab: Ein kaputtes Skript fügt alle 5 Minuten eine Zeile hinzu, bis es repariert ist.

<a id="storage-exit-codes"></a>
**Exit-Codes von `pacs-storage.sh`.**

- `0`: erledigt. Ohne `ja` als letztes Argument heißt es, dass der Plan ausgegeben und nichts geändert wurde.
- `1`: gestoppt, nichts geändert. Die letzte Zeile, die mit `HALT:` beginnt, nennt den Grund. Ein unbekannter Befehl gibt den Hilfetext aus und endet ebenfalls mit 1.
- `3`: Die Änderung steht im LDAP, aber das Archiv hat seine Konfiguration nicht neu geladen. Das Skript fragt dreimal im Abstand von 5 Sekunden an und wertet die HTTP-Antworten 204 und 200 als Erfolg. Die Zeile `ACHTUNG: Archiv-Konfiguration nicht neu geladen (Antwort 000). ...` sagt das. Das gilt für `activate` (also auch für `add DEVICE ja`), `grow`, `freigeben`, `anhaengen` und `abhaengen`. Das Archiv arbeitet mit seiner alten Konfiguration weiter, bis jemand in der Archiv-Oberfläche unter **Konfiguration** auf **Neu laden** klickt. Den Befehl nicht wiederholen, um das zu reparieren: Der zweite Lauf findet die Änderung im LDAP, sagt das (`ist nicht als voll markiert`, `steht schon in der Schreibliste` oder `steht in keiner Schreibliste`), endet mit 0 und versucht das Neuladen nicht noch einmal.

Der Hilfsdienst macht aus den Codes Antworten, siehe [Abschnitt 5.1](#contract-paths).

<a id="command-preflight"></a>
### 2.3 preflight.sh

Prüfung eines Hosts vor der Installation, nur lesend. Das Skript ändert nichts, installiert nichts und startet nichts neu.

```
sudo -i
bash /opt/pacs-admin/deploy/tools/preflight.sh --host pacs.example.org --cert /opt/ohif/tls/server.crt --key /opt/ohif/tls/server.key --dir /opt/ohif
```

| Option | Bedeutung |
|---|---|
| `--host pacs.example.org` | Prüft zusätzlich, dass der DNS-Name auflöst, und zwar auf eine Adresse dieses Hosts. Mit `--cert` prüft es zusätzlich, dass das Zertifikat den Namen abdeckt. |
| `--cert DATEI` und `--key DATEI` | Prüft zusätzlich ein TLS-Zertifikat und seinen Schlüssel. Jede Option funktioniert allein. |
| `--dir /opt/ohif` | Prüft zusätzlich den Ordner der eigenen Compose-Datei (bis zu 5 Ebenen tief, versteckte Ordner ausgelassen). Siehe die Liste unten. |
| `--lang de` oder `--lang en` | Sprache der Ausgabe. Ohne die Option entscheidet die erste nicht leere Variable von `LC_ALL`, `LC_MESSAGES` und `LANG`: Ein Wert, der mit `de` beginnt, ergibt Deutsch, sonst Englisch. |
| `-h` oder `--help` | Gibt die Aufrufhilfe aus und endet mit 0. |

Jede Option funktioniert auch als `--host=pacs.example.org`. Das Skript mit `bash` starten: `sh` lehnt es ab. Ein abschließender `/` im Wert von `--dir` wird ignoriert. Jeder Docker-Aufruf hat ein Zeitlimit von 15 Sekunden, daher kann ein hängender Daemon das Skript nicht blockieren.

Jede Prüfung gibt eine Zeile aus: `[ OK ]`, `[WARN]` oder `[FAIL]`. Eine Warnung oder ein Fehler fügt einen Satz zur Bedeutung und den genauen Befehl zur Abhilfe hinzu. Die Ausgabe enthält nie eine Zeile einer Konfigurationsdatei und nie einen geheimen Wert. Das Beispiel zeigt die englische Ausgabe. Mit `--lang de` lautet derselbe Text deutsch, ohne Umlaute.

```
[FAIL] SQLCipher: package libsqlcipher1 (4.6.1-2) fits this system, not installed yet
       The encrypted audit log needs this library; the helper service does not start without it. docs/install.md#audit-key
       Fix: apt-get install -y libsqlcipher1
```

| Exit-Code | Bedeutung |
|---|---|
| 0 | Alle Prüfungen bestanden. |
| 1 | Nur Warnungen. |
| 2 | Mindestens ein Fehler, oder eine falsche Option. |

Was geprüft wird:

- System und Pakete: root, der Ort des Repositorys (eine Warnung, wenn er nicht `/opt/pacs-admin` ist), systemd, das Betriebssystem (Debian 12 und 13 bestehen, Ubuntu und alles andere ergibt die Warnung „nicht getestet“), das SQLCipher-Paket, das zur Version passt, `python3` unter `/usr/bin/python3` ab Version 3.7, git, curl, openssl, ip, cron (installiert und laufend), iptables, journalctl und die Werkzeuge des Platten-Assistenten.
- Docker und dcm4chee: der Docker-Daemon und das Compose-Plugin, dann die Container von arc, LDAP und der Datenbank, gefunden am Image-Namen (`dcm4chee-arc-*`, `slapd-dcm4chee*`, `postgres-dcm4chee*`). Ein arc-Image mit `-secure` ist ein Fehler: Es wird nicht unterstützt. Ferner das Compose-Verzeichnis und das Docker-Netzwerk von arc, das WildFly-Logverzeichnis auf dem Host und ob der LDAP-Container ein Root-Passwort hat (der Wert wird nie gelesen oder ausgegeben).
- Host-Einstellungen: Mounts unter `STORAGE_BASE` und ihre Mount-Propagation, ob die uid 101 frei ist, die Ports 80 und 443, die Schnittstelle der Standardroute, `/etc/localtime` und mit `--host` der DNS-Name.
- TLS-Zertifikat, mit `--cert` oder `--key`: PEM-Format, Ablauf (eine Warnung unter 30 Tagen), `subjectAltName`, der Hostname, die Reihenfolge der Kette, ein Schlüssel ohne Passphrase, der Schlüssel passt zum Zertifikat, und der Modus der Schlüsseldatei für das verwendete Image ([Abschnitt 3.6](#permissions)). Mit `--dir` und ohne `--key` bekommt auch der Schlüssel in `tls/` die Modusprüfung.
- Konfigurationsdateien: die Syntax von `/etc/default/pacs-admin`, sobald die Datei existiert (CRLF, `sh -n`, ein Wert mit Leerzeichen ohne Anführungszeichen, eine Zeile, die nicht `NAME=Wert` ist, `CHANGE-ME` in einem Wert). Mit `--dir` prüft das Skript auch den Ordner der Compose-Datei:
  - `CHANGE-ME` und `<Platzhalter>` in den Dateien `*.conf`, `*.inc`, `*.yml`, `*.yaml`, `*.env` und `*.js` (ein Fehler) und Beispielwerte wie `example.org` (eine Warnung). Die Marke `CHANGE-ME` zählt auch in einem Kommentar: den Kommentar mit der Marke löschen, sobald der Wert gesetzt ist.
  - Jede Datei, die die nginx-Dateien aus `/etc/nginx/conf.d/` einbinden, existiert, damit nginx starten kann (ein Fehler). Ein Ordner mit Compose-Datei, aber ohne `nginx/pacs.conf` ergibt eine Warnung.
  - Jeder Bind-Mount der Compose-Datei. Eine Quelle, die nicht existiert, ist eine Warnung: Docker würde einen leeren Ordner mit root als Besitzer anlegen. Eine unvollständige Quelle ist ein Fehler: `server.crt` und `server.key` fehlen in `tls/`, `users` oder `admins` fehlen in `htpasswd/`, `pacs.conf` fehlt in `nginx/`, oder `app-config.js` oder `config.js` ist keine Datei.
  - Zugriff des nginx-Benutzers (uid 101) auf das Gemountete: die Admin-Seite, der Status-Ordner, `app-config.js` und `config.js` (ein Fehler, wenn uid 101 sie nicht lesen kann). Beim OHIF-Image zusätzlich `nginx/` und `tls/`. Die Listen in `htpasswd/`: Der Worker muss sie lesen können (sonst ein Fehler), aber nicht jedes Konto (eine Warnung, wenn es kann).
  - Jede `env_file` der Compose-Datei existiert (sonst ein Fehler). In einer Compose-Datei mit oauth2-proxy enthält sie außerdem die drei Werte Client-ID, Client-Secret und Cookie-Secret, keiner leer (sonst ein Fehler).
  - Eine `*.env`-Datei, auf die andere Konten zugreifen können (eine Warnung).

  Das Skript gibt Dateinamen und Zeilennummern aus. Bei einem Platzhalter gibt es das Wort aus (`CHANGE-ME` oder `<name>`), bei einer `*.env`-Datei nur den Variablennamen. Es gibt nie eine ganze Zeile und nie einen Wert aus.

Am Ende gibt das Skript die Zusammenfassung aus, eine `apt-get`-Schleife für alle fehlenden Pakete (ein Paket, das es nicht gibt, wird gemeldet, und der Rest wird trotzdem installiert) und eine Tabelle „Meine Werte“. Die Tabelle zeigt die Zeilen so, wie die deutsche Ausgabe sie beschriftet:

| Zeile | Kommt in |
|---|---|
| Compose-Verzeichnis | `PACS_DIR` |
| Compose-Datei(en) | Information |
| Docker-Netzwerk von arc | das externe Netzwerk in der Compose-Datei |
| arc-Container | `ARC_CONTAINER` und der nginx-Upstream |
| ldap-Container | `LDAP_CONTAINER` |
| db-Container | Information |
| wildfly-Log-Verzeichnis (Host) | `ARC_LOG_DIR` |
| Netzwerkschnittstelle nach aussen | `FW_INTERFACE` |
| uid von nginx / Sockets | `PACS_SOCKET_UID` |
| SQLCipher-Paket | `apt-get install -y` |

„(nicht gefunden)“ in der Wertspalte heißt: von Hand nachsehen. Unter der Tabelle listet das Skript die Zeilen für `/etc/default/pacs-admin`, deren Wert von der aktuellen Einstellung abweicht: `PACS_DIR`, `ARC_CONTAINER`, `LDAP_CONTAINER`, `ARC_LOG_DIR` und `FW_INTERFACE`, solange es leer ist (ein fester Name ist sicherer als die Suche der Standardroute beim Boot). Die letzten Zeilen nennen die Optionen, die nicht angegeben wurden (`Nicht geprueft (Option nicht angegeben)`). Das Skript nach jeder Korrektur erneut starten.

<a id="command-adduser"></a>
### 2.4 pacs-adduser.sh

Legt ein Konto für das Anmeldeverfahren `basic` (HTTP-Basic-Authentifizierung von nginx) an oder ändert es. Das Skript braucht nur bash und openssl.

```
sudo bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh admin anna
sudo bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh all vera
```

| Argument | Bedeutung |
|---|---|
| `admin` oder `all` | `all`: Das Konto darf den Viewer nutzen. Seine Zeile kommt in die Liste aller Konten. `admin`: Das Konto darf zusätzlich `/admin/` nutzen. Seine Zeile kommt in beide Listen. |
| `anna` | Kontoname: Buchstaben, Ziffern, `.`, `_` und `-`, höchstens 32 Zeichen. Jedes andere Zeichen wird abgelehnt, daher funktioniert `anna@example.org` nicht. |

| Option | Bedeutung |
|---|---|
| `--dir /opt/ohif` | Ordner der eigenen Compose-Datei (Vorgabe `/opt/ohif`). Die Listen sind `htpasswd/users` und `htpasswd/admins` darunter. Der Ordner selbst muss vorhanden sein, sonst stoppt das Skript. Das Skript legt den Ordner `htpasswd` darunter an (Modus 755), wenn er fehlt. Ist `htpasswd` eine einfache Datei, stoppt das Skript und gibt den `mv`-Befehl aus, der das behebt. `--file` ist ein älterer Name dieser Option. |
| `--users DATEI` und `--admins DATEI` | Beide Listendateien selbst nennen. Beide angeben. Gilt vor `--dir`. |
| `--owner 101` | Besitzer der Dateien als `UID` oder `UID:GID`, gesetzt, wenn man als root arbeitet. Vorgabe 101, der nginx-Worker in den Images `nginx` und OHIF. Für nginx auf dem Host `--owner root:www-data` nutzen. |
| `--mode 600` | Modus der Dateien, drei Oktalziffern. Vorgabe 600. Für nginx auf dem Host `--mode 640` nutzen. Das Skript lehnt einen Modus ab, bei dem die Gruppe oder andere schreiben dürfen. |

Das Passwort wird nie von der Kommandozeile genommen. Das Skript fragt zweimal mit verdeckter Eingabe oder liest eine Zeile von stdin, wenn stdin kein Terminal ist: `printf '%s\n' 'CHANGE-ME-PASSWORD' | sudo bash pacs-adduser.sh admin anna`. Ein Passwort braucht mindestens 10 Zeichen und höchstens 256 Byte. openssl hasht nur die ersten 256 Byte, ein längeres Passwort könnte also nie passen, und das Skript lehnt es ab.

Ein vorhandenes Konto wird ersetzt und, wie die Rolle es sagt, zwischen den Listen verschoben: Die Rolle `all` entfernt seine Zeile aus `admins`. Um ein Konto zu entfernen, seine Zeile aus beiden Dateien löschen. Die Dateien werden an Ort und Stelle geschrieben, daher bleibt ein Bind-Mount einer einzelnen Datei gültig. Zwei Läufe im selben Moment warten aufeinander, wenn `flock` installiert ist (der zweite wartet bis zu 30 Sekunden). nginx liest die Dateien bei jeder Anfrage: Ein Neustart ist nicht nötig.

Der Passwort-Hash ist sha512-crypt (`$6$`) mit den voreingestellten 5000 Runden. nginx prüft den Hash bei jeder Anfrage, daher hält das Skript den Aufwand klein und hat keine Option für mehr Runden. Das Skript braucht dafür openssl 1.1.1 oder neuer. Mit einem älteren openssl gibt es eine Warnung aus, benutzt apr1 (den schwächeren Typ) und schreibt die Zeile trotzdem. Dann openssl aktualisieren und das Passwort neu setzen.

Das Skript als root starten. Bevor es etwas schreibt, prüft es, dass eine neue Datei den Besitzer und den Modus bekommen kann. Ohne root warnt es, dass der Besitzer nicht gesetzt wurde. Dateien, die der nginx-Worker nicht lesen kann, ergeben 500 bei jeder Anfrage, die ein Passwort mitschickt. Eine fehlende Datei ergibt 403.

| Exit-Code | Bedeutung |
|---|---|
| 0 | Die Listen wurden geschrieben, oder `-h` hat die Aufrufhilfe ausgegeben. |
| 1 | Falsche Argumente, falsche Passworteingabe, ein fehlendes `openssl`, Dateien, die sich nicht schreiben lassen, oder ein anderer Fehler. |

<a id="command-set-aet"></a>
### 2.5 set-aet.sh

Ändert die AE-Titel in den Dateien, die sie enthalten, siehe [Abschnitt 4.3](#ae-title). Es ändert nur die Viewer-Seite: Der AE-Titel selbst wird in dcm4chee festgelegt.

```
sudo bash /opt/pacs-admin/deploy/tools/set-aet.sh MYARC MYARC_REJ --dir /opt/ohif
```

| Argument oder Option | Bedeutung |
|---|---|
| `MYARC` | Neuer AE-Titel des Archivs. Er ersetzt `DCM4CHEE`. |
| `MYARC_REJ` | Neuer AE-Titel der Ansicht abgelehnter Studien. Er ersetzt `IOCM_QUALITY`. Weglassen, um `IOCM_QUALITY` zu behalten. |
| `--dir /opt/ohif` | Ordner mit den eigenen Dateien (Vorgabe `/opt/ohif`). Das Skript sieht alle Textdateien darunter an, bis zu 5 Ebenen tief, und wählt sie nach dem Inhalt, nicht nach dem Namen. Es überspringt versteckte Ordner (die Sicherungen früherer Läufe), Dateien ab 1 MiB und Namen, die auf `.bak`, `.orig`, `.old`, `.save`, `.swp` oder `~` enden. Es lehnt `/` ab. |
| `--dry-run` | Nur zeigen, was sich ändern würde. |
| `--yes` oder `-y` | Nicht um Bestätigung fragen. |
| `--from ALTER-ARCHIV-AET` und `--from-rejection ALTER-ABLEHNUNGS-AET` | Die Titel, die die Dateien jetzt enthalten, wenn es nicht mehr `DCM4CHEE` und `IOCM_QUALITY` sind. Für eine zweite Umbenennung nötig. |

Ein Titel hat 1 bis 16 Zeichen: Buchstaben, Ziffern, `_` und `-`. Die beiden Titel müssen sich unterscheiden.

Das Skript ersetzt nur ganze Wörter, mit Unterscheidung von Groß- und Kleinschreibung. `99DCM4CHEE` (das Codierungsschema von „Ablehnung zurücknehmen“), `DCM4CHEE2` und `MY_DCM4CHEE` bleiben, wie sie sind, ebenso das kleingeschriebene `/dcm4chee-arc/` in Pfaden. Eine Datei ändert sich nur, wenn sie den Titel enthält und wie eine nginx-, OHIF- oder Admin-Seiten-Datei aussieht, also eines von diesen enthält: `aets/`, `window.config`, `window.PACS_ADMIN`, eine Variable `$pacs_...` oder eine Zeile, die mit `location`, `map`, `upstream` oder `server` beginnt. Andere Dateien, die das Wort enthalten, werden als „NICHT geaendert“ aufgelistet, damit man sie von Hand prüft. Ein symbolischer Link wird nie umgeschrieben. Das Skript listet ihn auf, mit dem Rat, die Datei zu ändern, auf die er zeigt.

Das Skript zeigt jede geänderte Zeile und fragt `Diese Aenderungen anwenden? [j/N]`. Kann es eine der Dateien nicht schreiben, stoppt es, bevor es etwas ändert: mit `sudo` starten. Dann kopiert es die Originale nach `VERZ/.set-aet-backup-ZEIT/` und schreibt die Dateien an Ort und Stelle um (gleiche Inode, gleicher Modus, gleicher Besitzer).

Am Ende listet es auf, was von Hand noch zu tun ist: dcm4chee braucht einen AE mit dem neuen Titel, `config.js` (wenn das Skript sie nicht unter dem Verzeichnis fand), `ARC_AET` in `/etc/default/pacs-admin` gefolgt von `systemctl restart pacs-verwaltung`, ein Neuladen von nginx (`docker compose restart` im Ordner der Compose-Datei) und ein Neuladen des Browsers ohne Cache.

| Exit-Code | Bedeutung |
|---|---|
| 0 | Fertig, oder `--dry-run`, oder die neuen Titel entsprechen den alten. |
| 1 | Ein Fehler, nichts gefunden (falsches `--dir`, oder die Titel wurden schon geändert: `--from` nutzen), eine Datei, die sich nicht schreiben lässt, oder die Antwort war nein. |

<a id="files-ports-sockets"></a>
## 3. Dateien, Dienste, Ports, Sockets und Mounts

### 3.1 Dateien auf dem Server

Die Verzeichnisstruktur ist die, die die Anleitung, die Compose-Beispiele und die Werkzeuge nutzen.

| Pfad | Was es ist |
|---|---|
| `/opt/pacs-admin/` | Das geklonte Repository. Die Units und die Cron-Datei erwarten diesen Pfad. |
| `/etc/default/pacs-admin` | Einstellungen, siehe [Abschnitt 1.1](#config-variables). Keine Geheimnisse. |
| `/etc/pacs-protokoll.key` | Schlüssel der Protokoll-Datenbank: 64 hexadezimale Zeichen in Kleinbuchstaben. Besitzer root, Modus 0600. |
| `/var/lib/pacs-protokoll/protokoll.db` | Die verschlüsselte Protokoll-Datenbank (und `-wal`, `-shm`). Verzeichnis 0700, Dateien 0600. Der Dienst legt sie an, wenn er sie zum ersten Mal öffnet. |
| `/var/lib/pacs-admin/status/status.json` | Zahlen für die Übersicht, siehe unten. Modus 0644. |
| `/var/lib/pacs-admin/status/rechner.json` | Optional, von Hand erstellt: ein JSON-Objekt, das IP-Adressen auf PC-Namen abbildet, zum Beispiel `{"192.0.2.50": "WS0050"}`. Der Reiter Protokoll zeigt den Namen neben der IP. Nichts in diesem Repository schreibt die Datei. |
| `/run/pacs-admin/` | Die beiden Sockets, siehe [Abschnitt 3.4](#sockets). Der Dienst legt das Verzeichnis an (Modus 0755). |
| `/etc/systemd/system/pacs-verwaltung.service`, `pacs-firewall.service` | Die beiden Units. |
| `/etc/cron.d/pacs-dashboard` | Der Cron-Job. |
| `/var/log/pacs-storage.log` | Log des Platten-Assistenten (`STORAGE_LOG`). |
| `/var/log/pacs-dashboard.log` | Fehler des Cron-Jobs. |
| `/opt/dcm4chee-arc/` | Vorgabe für `PACS_DIR`: das dcm4chee-Compose-Projekt. |
| `PACS_DIR/firewall.json` | Die Firewall-Regeln (Modus 0640). |
| `PACS_DIR/firewall/` | Frühere Versionen (`firewall-YYYYMMDD-HHMMSS.json`) sowie `absender.json`, `clients.json`, `angewendet.json`. |
| `/mnt/fs/PACS-Data01`, ... | Mountpunkte der Archivplatten (`STORAGE_BASE`, `STORAGE_PREFIX`). Unter jedem liegt eine schreibgeschützte Datei `NO_MOUNT`. |
| `/etc/fstab`, `/etc/fstab.bak-ZEIT` | Der Assistent fügt pro Platte eine Zeile hinzu und behält vor der Änderung eine Kopie der Datei. |
| `/run/pacs-storage.lock` | Sperre des Platten-Assistenten. |

Das Compose-Verzeichnis (Vorgabe `/opt/ohif`):

| Pfad | Was es ist |
|---|---|
| `docker-compose.yml` | Eine Kopie eines der Compose-Beispiele in `deploy/compose/`. |
| `nginx/` | Der nginx-Baum: `pacs.conf` und der Ordner `pacs/`. Als ein Ordner nach `/etc/nginx/conf.d` gemountet, nur lesend. |
| `tls/server.crt`, `tls/server.key` | Volle Kette (Serverzertifikat zuerst) und Schlüssel. Nur Listener `tls`. |
| `htpasswd/users`, `htpasswd/admins` | Nur Anmeldeverfahren `basic`. Von `pacs-adduser.sh` geschrieben. |
| `ohif-auth.env` | Nur Anmeldeverfahren `oauth2-proxy`: Client-ID, Client-Secret, Cookie-Secret. `chmod 600`. |
| `app-config.js` | Nur Viewer `ohif`: eine Kopie von `deploy/app-config.js.example`. |
| `config.js` | Optionale Kopie von `web/admin/config.js`. |
| `logo.svg` | Optionales Logo, nur Viewer `ohif`. |
| `.set-aet-backup-ZEIT/` | Von `set-aet.sh` gesicherte Originale. |

**status.json.** `dashboard-status.py` schreibt die Datei. Er ersetzt die Datei in einem Schritt, daher liest die Seite nie eine halb geschriebene Datei. Die Seite zeigt, was vorhanden ist, und blendet aus, was fehlt.

| Schlüssel | Bedeutung |
|---|---|
| `stand` | Zeitpunkt des Laufs, ISO 8601 mit Offset. |
| `prefix`, `frei_gb`, `warn_gb` | Die Einstellungen `STORAGE_PREFIX`, `STORAGE_FREE_GB` und `STORAGE_WARN_GB` für die Seite. |
| `platten` | Ein Eintrag pro Verzeichnis `STORAGE_BASE/STORAGE_PREFIX` plus Ziffern. Eine gemountete Platte hat `name`, `groesse` und `frei` (Byte), `voll` (Markierung „voll“), `in_liste` (in der Schreibliste), `neue_bilder` und `reihe`. `neue_bilder` ist `jetzt` für die Platte, die die neuen Bilder erhält, `danach` für die Platten dahinter in der Schreibliste, sonst leer. `reihe` ist die Position unter den Platten der Schreibliste, die nicht als voll markiert sind: 1 erhält die neuen Bilder jetzt, 0 heißt nicht in der Schreibliste oder als voll markiert. Eine Platte, die nicht gemountet ist, hat nur `name` und `fehlt: true`. |
| `schreibliste_bekannt` | `false`, wenn LDAP nicht gelesen werden konnte oder `pacs-storage.sh kandidaten` fehlgeschlagen ist ([Exit-Codes](#server-commands)). Die Seite sagt dann „Schreibliste nicht lesbar“ und was zu prüfen ist, statt zu behaupten, keine Platte nehme neue Bilder an. |
| `neue_platten` | `kandidaten` (leere Platten, jede mit `geraet`, `groesse` in Byte und `modell`), `name` (der Name der nächsten Platte), `vorlage` (der Speicher, dessen Einstellungen die neue übernimmt) und `schwelle` (dessen Schwelle). |
| `dienste` | Ein Objekt, das einen Containernamen auf `true` (läuft) oder `false` abbildet. Leer, wenn Docker nicht installiert ist. |

### 3.2 Dienste und Container

| Name | Was er tut |
|---|---|
| `pacs-verwaltung.service` | Der Hilfsdienst. Beschreibung: „PACS admin: helper service for /admin/ (unix sockets, see verwaltung-dienst.py)“. Er führt `/usr/bin/python3 /opt/pacs-admin/server/verwaltung-dienst.py` als root aus, mit `Restart=always` und `RestartSec=5`, nach `docker.service`. Er bindet zuerst beide Sockets und startet dann drei Aufträge: Er speichert alle 2 Sekunden Logzeilen, alle 5 Minuten liest er neue DICOM- und HL7-Absender und neue Docker-Ports, und jede Stunde fragt er Client-Namen ab. Beim Start gibt er `pacs-verwaltung bereit: ...` ins Journal aus. Er hat absichtlich kein `RuntimeDirectory=`: systemd würde `/run/pacs-admin` bei jedem Stopp löschen, und der Mount im Container zeigte ins Leere. |
| `pacs-firewall.service` | Die Firewall. Beschreibung: „PACS firewall: filter the Docker-published ports from outside (firewall.py, tab Firewall in /admin/)“. Eine Unit vom Typ oneshot mit `RemainAfterExit`, `Requires=docker.service` und `PartOf=docker.service`. `multi-user.target` und `docker.service` ziehen die Unit ein (`WantedBy`), daher kehren die Regeln nach jedem Start von Docker zurück. `ExecStart` führt `firewall.py start` aus, `ExecStop` führt `firewall.py stop` aus. **Notbremse:** `systemctl stop pacs-firewall` entfernt den Sprung in die Kette `PACS-SPERRE`, und alle Ports sind wieder offen. |
| `/etc/cron.d/pacs-dashboard` | Läuft als root alle 5 Minuten: lädt `/etc/default/pacs-admin`, führt `dashboard-status.py` aus und schreibt Fehler nach `/var/log/pacs-dashboard.log`. |
| Container `ohif` | nginx (das Image `nginx` oder das OHIF-Image). |
| Container `ohif-auth` | oauth2-proxy. Nur mit Anmeldeverfahren `oauth2-proxy`. |

Die Units und die Cron-Datei erwarten das Repository unter `/opt/pacs-admin`. Die Units starten genau `/usr/bin/python3`. Die Cron-Datei startet `python3` aus ihrem `PATH`. Um das Repository zu verschieben, zum Beispiel nach `/srv/pacs-admin`, einmal nach dem Kopieren der Dateien Folgendes ausführen und dasselbe Verzeichnis in der Compose-Datei mounten:

```
sed -i 's|/opt/pacs-admin|/srv/pacs-admin|g' /etc/systemd/system/pacs-*.service /etc/cron.d/pacs-dashboard && systemctl daemon-reload
```

### 3.3 Ports

| Port | Wer lauscht | Hinweise |
|---|---|---|
| 80 und 443 auf dem Host | Der Container `ohif`: nginx auf 8080 und 8443 im Container | Listener `tls`. Veröffentlicht als `0.0.0.0:80:8080` und `0.0.0.0:443:8443`. Port 80 leitet nur auf https um. |
| `127.0.0.1:8080` auf dem Host | Der Container `ohif`: nginx auf 8080 | Listener `plain`. Für einen SSH-Tunnel. Nie in einem Netz veröffentlichen. |
| keiner | Der Container `ohif`: nginx auf 8080 | Listener `behind-proxy`. Der Container tritt dem Docker-Netzwerk des Proxys bei. Nur der Proxy darf ihn erreichen. |
| 4180 | oauth2-proxy | Nur im Docker-Netzwerk erreichbar. Nicht veröffentlicht. |
| 8080, 8443 | dcm4chee-arc, REST | Keine eigene Anmeldung. Nur auf `127.0.0.1` veröffentlichen. nginx erreicht arc über das Docker-Netzwerk. Der Platten-Assistent ruft `ARC_URL` auf dem Host auf. |
| 9990, 9993 | dcm4chee-arc, WildFly-Verwaltung | Nur auf `127.0.0.1` veröffentlichen. |
| 11112, 2762 | DICOM (`FW_DICOM_PORTS`) | Für die Modalitäten veröffentlicht. |
| 2575, 12575 | HL7 (`FW_HL7_PORTS`) | Für die sendenden Systeme veröffentlicht. |
| keiner | Der Hilfsdienst | Er lauscht nur auf Unix-Sockets, nie auf einem TCP-Port. |

Der Reiter Firewall filtert die Ports, die Docker veröffentlicht. Er filtert nicht nginx auf dem Host.

Die Ports von nginx nur auf IPv4 veröffentlichen, als `0.0.0.0` (die Compose-Beispiele tun das). Über IPv6 nimmt der Docker-Proxy die Verbindung an, und nginx sieht dann als Client-Adresse nur das Docker-Gateway. Das Protokoll zeigt das Gateway, die Prüfung der Firewall gegen Selbstaussperrung greift nicht ([Abschnitt 5.8](#contract-client-ip)), und die Firewall des Admin-Panels, die nur IPv4 behandelt, filtert den Port nicht.

<a id="sockets"></a>
### 3.4 Sockets

| Socket | Typ | Pfad | Genutzt für |
|---|---|---|---|
| `verwaltung.sock` | Stream, HTTP/1.0 | `PACS_SOCKET`, Vorgabe `/run/pacs-admin/verwaltung.sock` | nginx reicht `/admin/dienst/` an ihn weiter. |
| `protokoll.sock` | Datagramm | `PACS_LOG_SOCKET`, Vorgabe `/run/pacs-admin/protokoll.sock` | nginx sendet die Protokollzeilen an ihn. |

Beide Sockets gehören `PACS_SOCKET_UID` und haben den Modus 0600. Die Pfade im nginx-Container stehen fest in den nginx-Dateien: `/run/pacs-admin/verwaltung.sock` und `/run/pacs-admin/protokoll.sock`. Das Verzeichnis `/run/pacs-admin` in den nginx-Container mounten und in keinen anderen Container. Nur lesend genügt. Wird das Verzeichnis nach dem Start des Containers neu angelegt, sieht der Container es erst nach einem Neustart: `docker restart ohif`.

<a id="mounts"></a>
### 3.5 Mounts im nginx-Container

Die Container-Pfade stehen fest, die nginx-Dateien beziehen sich auf sie. Die Host-Pfade sind Beispiele.

| Im Container | Inhalt | Host-Pfad | Modus | Wann |
|---|---|---|---|---|
| `/etc/nginx/conf.d` | der Ordner mit `pacs.conf` und `pacs/` | `/opt/ohif/nginx` | `:ro` | immer |
| `/etc/nginx/tls` | `server.crt` und `server.key` | `/opt/ohif/tls` | `:ro` | Listener `tls` |
| `/etc/nginx/htpasswd` | die Dateien `users` und `admins` | `/opt/ohif/htpasswd` | `:ro` | Anmeldeverfahren `basic` |
| `/srv/pacs-admin/admin` | `web/admin` des Repositorys | `/opt/pacs-admin/web/admin` | `:ro` | immer |
| `/srv/pacs-admin/admin/config.js` | optionale Kopie von `config.js` | `/opt/ohif/config.js` | `:ro` | optional |
| `/srv/pacs-admin/status` | der Ordner mit `status.json` | `/var/lib/pacs-admin/status` | `:ro` | immer |
| `/run/pacs-admin` | die beiden Sockets | `/run/pacs-admin` | `:ro` | immer |
| `/usr/share/nginx/html/app-config.js` | OHIF-Konfiguration | `/opt/ohif/app-config.js` | `:ro` | Viewer `ohif` |
| `/usr/share/nginx/html/pacs-logo.svg` | Logo für die Seite (`logo: '/pacs-logo.svg'` in `config.js`) | `/opt/ohif/logo.svg` | `:ro` | optional, Viewer `ohif` |
| `/etc/localtime` | Ortszeit für das Protokoll | `/etc/localtime` | `:ro` | empfohlen |

Für `conf.d` und `htpasswd` Ordner mounten, nicht einzelne Dateien. Eine einzelne Datei, die ersetzt wird (`sed -i`, `mv`), kann im Container ihren alten Inhalt behalten. Ein Ordner zeigt die neue Datei sofort. Ein Ordner über `/etc/nginx/conf.d` ersetzt die `default.conf` des Images. Das Startskript des Images gibt dann `default.conf is not a file or does not exist` aus. Die Meldung ist harmlos.

`app-config.js`, `config.js` und das Logo sind Mounts einzelner Dateien. Nach einer Änderung `docker compose restart` im Ordner der Compose-Datei ausführen, damit der Container den neuen Inhalt sieht.

Beim Viewer `none` (das Image `nginx`) kein Logo mounten. Docker kann in dem schreibgeschützten Ordner `/srv/pacs-admin/admin` keine neue Datei anlegen, und der Container würde nicht starten. Stattdessen das Logo nach `web/admin/logo.svg` im Repository kopieren und `logo: '/admin/logo.svg'` in `config.js` setzen.

<a id="permissions"></a>
### 3.6 Besitzer, Modi und die uid 101

| Objekt | Gelesen von | Besitzer und Modus | Warum |
|---|---|---|---|
| Die beiden Sockets | nginx-Worker-Prozesse | `PACS_SOCKET_UID`, 0600 (vom Hilfsdienst gesetzt) | Die uid und der Modus sind der einzige Schutz des Hilfsdienstes, siehe unten. |
| `htpasswd/users`, `htpasswd/admins` | nginx-Worker-Prozesse, bei jeder Anfrage | Container: Besitzer 101, Modus 600. nginx auf dem Host: `root:www-data`, Modus 640. `pacs-adduser.sh` setzt das. | Eine Datei, die der Worker nicht lesen kann, ergibt 500 bei jeder Anfrage, die Name und Passwort mitschickt (Error-Log: `open() ... failed (13: Permission denied)`). Die Passwortabfrage erscheint trotzdem zuerst. Eine fehlende Datei ergibt 403 (`failed (2: No such file or directory)`). |
| TLS-Schlüssel `server.key` | der nginx-Master-Prozess, beim Start | Image `nginx` und nginx auf dem Host: `root:root`, 0600. OHIF-Image: `chown root:101 server.key && chmod 640 server.key`. | Im OHIF-Image läuft der Master als uid 101 und könnte einen Schlüssel, der nur root gehört, nicht lesen. |
| `ohif-auth.env` | Docker Compose, als root | root, 0600 | Die Datei enthält das Client-Secret. |
| Protokollschlüssel | der Hilfsdienst, als root | root, 0600 | Ohne den Schlüssel kann niemand das Protokoll lesen. |
| `status.json` | nginx-Worker-Prozesse | 0644, Verzeichnis 0755 | Die Datei enthält keine Patientendaten. |

Herausfinden, welcher Fall für den TLS-Schlüssel gilt:

```
docker exec ohif id
```

`uid=101(nginx)` heißt, dass der Master als uid 101 läuft (OHIF-Image). `uid=0(root)` heißt, dass er als root läuft (Image `nginx`).

**Die uid der Sockets.** Die nginx-Worker verbinden sich mit den Sockets, daher gehören die Sockets der uid der Worker: 101 in den Images `nginx` und OHIF, 33 (`www-data`) bei nginx unter Debian. Eine Abweichung ergibt 502 auf `/admin/dienst/` und stillschweigend verlorene Protokollzeilen. Die uid und der Modus 0600 sind der einzige Schutz des Hilfsdienstes. Jeder Prozess mit dieser uid kann ihn als root nutzen: das Protokoll lesen, die Firewall abschalten, Platten einrichten. Deshalb sollte im Idealfall kein Konto auf dem Host diese uid haben:

```
getent passwd 101
```

Der Befehl sollte nichts ausgeben. Unter Debian gehört die uid 101 oft einem Systemkonto, zum Beispiel `messagebus`. Bei einem reinen Systemkonto ist das Risiko klein, und der Dienst startet trotzdem: Er gibt eine Warnung ins Journal aus, wenn die uid zu einem Konto gehört. Siehe [Installationsanleitung](install.de.md#helper-service).

<a id="nginx-recipes"></a>
## 4. nginx-Rezepte und der AE-Titel

### 4.1 Die drei Entscheidungen

Die nginx-Konfiguration besteht aus einer Kerndatei, die man nie ändert, und je einem kleinen Satz Dateien für drei Entscheidungen:

- **Anmeldeverfahren** (`login/`): `oauth2-proxy`, `basic` oder `none`. Siehe [Anmeldung](login.de.md).
- **Viewer** (`viewer/`): `ohif` (der OHIF-Viewer und die Lesezugriffe, die er braucht) oder `none` (nur das Admin-Panel: `/` leitet auf `/admin/` um).
- **Listener** (`listener/`): `tls` (https auf diesem nginx), `plain` (reines http, für einen SSH-Tunnel nach `127.0.0.1`) oder `behind-proxy` (reines http hinter einem Proxy, der TLS beendet).

Jedes Rezept ändert die Datei `pacs/site.conf`. Darin stehen `server_name`, die Upstream-Namen, die Zertifikatspfade und, beim Anmeldeverfahren `oauth2-proxy`, die Admin-Gruppe. Zwei Entscheidungen bringen weitere Werte zum Ändern mit:

- Anmeldeverfahren `none`: die `allow`-Zeilen in `pacs/login/server.conf` (die PCs, die den Viewer öffnen dürfen) und in `pacs/login/admin.conf` (die Administrator-PCs).
- Listener `behind-proxy`: `set_real_ip_from` in `pacs/listener/server.conf` (die Adresse des Proxys; die mitgelieferte `203.0.113.1` vertraut niemandem).

Jeder Wert, der geändert werden muss, trägt in seiner Zeile die Markierung `CHANGE-ME`. Den Wert ersetzen und den Markierungskommentar löschen. Danach gibt `grep -rn CHANGE-ME /opt/ohif/nginx` nichts aus. Ein vergessener Platzhalter besteht `nginx -t` trotzdem, daher den grep ausführen. Die Kopierbefehle stehen in [deploy/nginx/README.de.md](../deploy/nginx/README.de.md#copy-commands). Die Liste aller Platzhalter steht in [deploy/nginx/README.de.md](../deploy/nginx/README.de.md#placeholders).

### 4.2 Rezepte

Ein Rezept ist eine Wahl aus Anmeldeverfahren, Viewer und Listener. Im Testlabor des Projekts heißen die Rezepte `login-viewer-listener`, zum Beispiel `oauth2-ohif-tls` ([deploy/nginx/README.de.md](../deploy/nginx/README.de.md#lab)).

| Ich will | Anmeldeverfahren | Viewer | Listener | Compose-Beispiel in `deploy/compose/` |
|---|---|---|---|---|
| Microsoft Entra ID oder einen anderen OIDC-Anbieter, OHIF-Viewer, https auf diesem Server | `oauth2-proxy` | `ohif` | `tls` | `docker-compose.oauth2.example.yml` |
| Dasselbe, nur das Admin-Panel | `oauth2-proxy` | `none` | `tls` | vom oauth2-Beispiel ausgehen, das Image `nginx` nehmen |
| Kein OAuth-Proxy: Benutzername und Passwort in nginx, OHIF-Viewer, https | `basic` | `ohif` | `tls` | `docker-compose.basic.example.yml` |
| Dasselbe, nur das Admin-Panel | `basic` | `none` | `tls` | `docker-compose.adminonly.example.yml` |
| Ein erster Blick auf 127.0.0.1 durch einen SSH-Tunnel, ohne TLS | `basic` | `none` (oder `ohif`) | `plain` | `docker-compose.tryit.example.yml` |
| Ein TLS-Proxy (Traefik, Caddy, Apache, Cloudflare Tunnel) bleibt davor, nginx behält Anmeldung und Sperren | beliebig | beliebig | `behind-proxy` | `docker-compose.proxied.example.yml` |
| Keine Anmeldung, nur eine Liste von Netzen | `none` | beliebig | beliebig | vom nächstliegenden Beispiel ausgehen |
| nginx auf dem Host statt in einem Container | beliebig | `none` | `tls` | keines: die Schritte für den Host stehen in [deploy/nginx/README.de.md](../deploy/nginx/README.de.md#host-nginx) |

Jedes Compose-Beispiel legt eine Kombination aus Anmeldeverfahren, Viewer und Listener fest:

| Beispiel in `deploy/compose/` | Anmeldeverfahren | Viewer | Listener |
|---|---|---|---|
| `docker-compose.oauth2.example.yml` | `oauth2-proxy` | `ohif` | `tls` |
| `docker-compose.basic.example.yml` | `basic` | `ohif` | `tls` |
| `docker-compose.adminonly.example.yml` | `basic` | `none` | `tls` |
| `docker-compose.tryit.example.yml` | `basic` | `none` | `plain` |
| `docker-compose.proxied.example.yml` | `basic` | `ohif` | `behind-proxy` |

Der Kopf jedes Beispiels nennt die Zeilen, die für die anderen Kombinationen zu ändern sind.

Nicht unterstützt: dcm4chee mit eigenem Keycloak (die `-secure`-Images) und der Ersatz von nginx durch Traefik, Caddy oder Cloudflare Access. Diese Produkte können vor nginx stehen (Listener `behind-proxy`).

<a id="ae-title"></a>
### 4.3 Der AE-Titel

Die AE-Titel `DCM4CHEE` (Archiv) und `IOCM_QUALITY` (Ansicht der abgelehnten Studien) müssen an jeder Stelle gleich sein, die sie enthält:

| Ort | Enthält | Geändert durch |
|---|---|---|
| `nginx/pacs.conf` | die Ereignis-Map und die Locations | `set-aet.sh` |
| `nginx/pacs/viewer.conf` | die Lesezugriffe des Viewers (nur Viewer `ohif`) | `set-aet.sh` |
| `app-config.js` | die Datenquelle (nur Viewer `ohif`) | `set-aet.sh` |
| `config.js`: `aet` und `iocmAet` | die Seite | `set-aet.sh`, wenn unter dem Verzeichnis eine Kopie von `config.js` liegt. Sonst von Hand. |
| `/etc/default/pacs-admin`: `ARC_AET` | der Platten-Assistent | von Hand, danach `systemctl restart pacs-verwaltung` |
| dcm4chee (LDAP) | der AE selbst | dcm4chee |

`99DCM4CHEE` ist ein Coding-Schema, kein AE-Titel. Es bleibt. Nicht mit Suchen und Ersetzen arbeiten: `set-aet.sh` lässt es unverändert. [Abschnitt 2.5](#command-set-aet) beschreibt das Skript.

<a id="front-door-contract"></a>
## 5. Vertrag der Eingangstür

Dieser Abschnitt legt fest, was die Seite und der Hilfsdienst von einer Eingangstür erwarten. Er ist wichtig für alle, die die nginx-Dateien ändern, eine andere Eingangstür bauen oder Protokollzeilen aus einem anderen Programm senden. Die nginx-Dateien in `deploy/nginx` erfüllen jeden Punkt.

Dieses Repository liefert und testet nur nginx als Eingangstür. Eine andere Eingangstür funktioniert, wenn sie diesen Vertrag erfüllt. Der Ersatz von nginx durch Traefik, Caddy oder Cloudflare Access wird nicht unterstützt: Niemand hat ihn getestet, und die Protokollzeilen brauchen einen Shipper ([Abschnitt 5.7](#audit-feed)). Diese Produkte stattdessen vor nginx stellen.

Eine Eingangstür muss:

1. Die Seite und die Statusdatei unter festen Pfaden an der Wurzel des Origin ausliefern, ohne die Pfade umzuschreiben ([5.1](#contract-paths), [5.9](#contract-same-origin)).
2. Die Anmeldung bei jeder Anfrage prüfen, mit zwei Stufen: jedes Konto und Admin ([5.1](#contract-paths)).
3. `/admin/dienst/` unverändert an den Unix-Socket weitergeben und `X-Auth-User` und `X-Real-IP` selbst setzen ([5.2](#contract-headers)).
4. Den Schutz durch `X-PACS-Admin` durchsetzen ([5.3](#contract-guard)).
5. Die aufgeführten dcm4chee-Aufrufe ohne Token an arc weitergeben und alles andere mit 404 beantworten ([5.5](#contract-dcm4chee)).
6. `Authorization` und `Cookie` aus Aufrufen an arc und an den Hilfsdienst entfernen ([5.2](#contract-headers)).
7. Dem Hilfsdienst die echte Client-Adresse geben ([5.8](#contract-client-ip)).
8. Die Protokollzeilen im Wire-Format in den Log-Socket schreiben ([5.6](#audit-wire-format)).

<a id="contract-paths"></a>
### 5.1 Pfade, Methoden und Stufen

Jeder Pfad ist absolut und liegt auf demselben Origin wie die Seite. Die Seite liegt unter `/admin/`.

Die Stufe „Admin“ meint ein Admin-Konto. Die Stufe „jedes Konto“ meint jedes Konto, das die Anmeldung durchlässt.

| Pfad | Methode | Stufe | Braucht `X-PACS-Admin` | Beantwortet von | Verwendet für |
|---|---|---|---|---|---|
| `/admin` | GET | Admin | nein | Eingangstür | Umleitung auf `/admin/` (die Seite ruft sie nicht auf) |
| `/admin/`, `/admin/admin.css`, `/admin/config.js` | GET | Admin | nein | statische Dateien aus `web/admin` | die Seite |
| `/admin/daten/status.json` | GET | Admin | nein | statische Datei, von `dashboard-status.py` geschrieben | Zahlen für die Übersicht. Keine Patientendaten. |
| `/admin/daten/rechner.json` | GET | Admin | nein | statische Datei, optional | PC-Namen. Ein 404 ist in Ordnung. |
| `/admin/dienst/firewall` | GET | Admin | nein | Hilfsdienst | Regeln, Zähler, Absender |
| `/admin/dienst/firewall?neu=1` | GET | Admin | ja | Hilfsdienst | dasselbe, nachdem er neue Absender aus `server.log` von arc (`ARC_LOG_DIR`) gelesen und die Namen von `FW_CLIENT_NAMES` im DNS nachgeschlagen hat |
| `/admin/dienst/firewall` | POST | Admin | ja | Hilfsdienst | alle Regeln speichern: JSON `{aktiv, schnittstelle, standard, regeln, ausgeblendet}`, höchstens 64 KB |
| `/admin/dienst/protokoll` | GET | Admin | nein | Hilfsdienst | das Protokoll lesen, siehe [Abschnitt 6.7](#audit-read) |
| `/admin/dienst/auftrag` | GET | Admin | nein | Hilfsdienst | Stand und Ausgabe des letzten Einrichtens einer Platte (`{}` vor dem ersten seit dem Start des Hilfsdienstes) |
| `/admin/dienst/platten` | GET | Admin | ja | Hilfsdienst | die Platten erneut einlesen und `status.json` auffrischen |
| `/admin/dienst/einrichten` | POST | Admin | ja | Hilfsdienst | eine Platte einrichten: JSON `{geraet, groesse, name}` |
| `/admin/dienst/freigeben`, `/admin/dienst/anhaengen`, `/admin/dienst/abhaengen` | POST | Admin | ja | Hilfsdienst | die Markierung „voll“ löschen, in die Schreibliste aufnehmen, aus der Schreibliste entfernen: JSON `{platte}` |
| `/oauth2/userinfo` | GET | jedes Konto | nein | Eingangstür oder oauth2-proxy | der Kontoname oben (`kontoUrl`). Optional. |
| `/dcm4chee-arc/aets/DCM4CHEE/rs/...` | siehe [5.5](#contract-dcm4chee) | | siehe 5.5 | arc | Studien und Patienten |

Der Hilfsdienst antwortet mit diesen Statuscodes:

| Code | Bedeutung |
|---|---|
| 200 | Erledigt. Der Body ist JSON, außer bei `protokoll` (eine JSON-Zeile pro Eintrag, `application/x-ndjson`). |
| 202 | Das Einrichten einer Platte hat begonnen. |
| 400 | Die Anfrage ist falsch. Der Body ist `{"fehler": "..."}`. Ursachen: ein POST-Body, der fehlt, kein JSON oder unvollständig ist; ein Geräte- oder Plattenname, der nicht passt; ein Datum oder eine Quelle von `protokoll`, die nicht gültig ist; Firewall-Regeln, die die Prüfung nicht bestehen. |
| 404 | `{"fehler": "unbekannt"}`: jeder andere Pfad. |
| 409 | Ein Plattenauftrag kann nicht laufen: Es läuft noch eine andere Einrichtung, die Platte wird nicht mehr genau so als leer erkannt, oder `pacs-storage.sh` ist mit dem Exit-Code 1 gestoppt. Der Body ist `{"fehler": "..."}` mit dem Grund; nach einem Stopp des Skripts ist es der Text hinter `HALT: `. |
| 500 | Ein interner Fehler. `firewall` antwortet `{"fehler": "Firewall: ..."}`, zum Beispiel wenn `docker` nicht installiert ist, weil der Status die Docker-Netze braucht. `platten` antwortet `{"ok": false, "fehler": "..."}` mit der letzten Zeile der Fehlermeldung von `dashboard-status.py`, zum Beispiel einer ungültigen Zahl in `/etc/default/pacs-admin`. `freigeben`, `anhaengen` und `abhaengen` antworten `{"fehler": "Archiv-Konfiguration nicht neu geladen (Antwort 000). ..."}`, wenn `pacs-storage.sh` mit 3 endet ([Exit-Codes](#storage-exit-codes)): Die Änderung steht im LDAP und nur das Neuladen ist fehlgeschlagen, darum ist die Antwort kein 409 („nicht ausgeführt“). Der Text ist die Zeile hinter `ACHTUNG: ` und sagt, dass in der Archiv-Oberfläche auf **Neu laden** zu klicken ist. Der Auftrag `einrichten` endet im selben Fall mit `rc` 3 in `GET /admin/dienst/auftrag`; die Kachel `Neue Festplatte` zeigt dann den gelben Kasten „Archiv nicht neu geladen“ mit derselben Zeile. |
| 501 | Eine andere Methode als GET und POST. Der Body ist die Standard-Fehlerseite von Python, kein JSON. |
| 503 | Nur `protokoll`: Der Protokollschlüssel oder die Datenbank ist nicht nutzbar. Der Body ist `{"fehler": "Protokoll: ..."}`. |
| 504 | `platten`, `freigeben`, `anhaengen` und `abhaengen`: `pacs-storage.sh` oder `dashboard-status.py` wurde innerhalb von 300 Sekunden nicht fertig, und der Hilfsdienst hat es abgebrochen. `einrichten` antwortet nur dann mit 504, wenn die Prüfung vor dem Start (`pacs-storage.sh kandidaten`) nicht fertig wird; dann wird keine Einrichtung gestartet. Das Skript der Einrichtung selbst läuft im Hintergrund ohne Zeitgrenze. Der Body ist `{"fehler": "pacs-storage.sh antwortet nicht (nach 300 s abgebrochen), Zustand pruefen"}`; bei `platten` lautet der Name `dashboard-status.py`. Nach einer Schaltfläche ist der Zustand unbekannt: vor einem neuen Versuch die Platten auf dem Server und `/var/log/pacs-storage.log` ansehen. |

Der Hilfsdienst liest den Body eines POST bis zu einer Grenze: 65536 Byte für die Firewall, 4096 Byte für jeden anderen POST. Er parst den Body als JSON, bevor er den Pfad ansieht. Ein POST mit einem Body, der kein JSON ist, bekommt daher auch auf einem Pfad, der nicht existiert, die Antwort 400. Der Hilfsdienst spricht HTTP/1.0 und schließt die Verbindung nach jeder Antwort. Ein Client, der seine Kopfzeilen oder seinen Body nicht innerhalb von 30 Sekunden fertig sendet, wird ohne Antwort getrennt. Die Plattenaufrufe und das erneute Einlesen laufen lange: 300 Sekunden für die Antwort einplanen. Die nginx-Dateien setzen `proxy_read_timeout 300s`.

Der Hilfsdienst vergleicht den Pfadtext wörtlich und vollständig. `/admin/dienst/platten?x=1`, `/admin/dienst/firewall?neu=0` und ein Pfad mit Schrägstrich am Ende bekommen alle 404. Nur `protokoll` nimmt weitere Query-Parameter an. Den Pfad nicht umschreiben.

<a id="contract-headers"></a>
### 5.2 Header

| Header | Richtung | Regel |
|---|---|---|
| `X-Auth-User` | Eingangstür an Hilfsdienst | Der Kontoname. Aus der geprüften Anmeldung setzen, nie aus der Anfrage des Browsers. Der Hilfsdienst speichert ihn als Namen dessen, der die Firewall gespeichert hat, und dessen, der das Einrichten einer Platte gestartet hat. Fehlt er, ist der Name leer. Er dient nur der Zuordnung, nie der Berechtigung. |
| `X-Real-IP` | Eingangstür an Hilfsdienst | Die Adresse des Client-PCs. Der Hilfsdienst nutzt sie für die Prüfung gegen Selbstaussperrung der Firewall ([5.8](#contract-client-ip)). |
| `X-PACS-Admin` | Browser an Eingangstür | Der Schutz aus [5.3](#contract-guard). Der Hilfsdienst liest den Header nie. Die Eingangstür muss ihn entfernen, bevor sie die Anfrage weiterreicht. |
| `Authorization`, `Cookie` | Browser an Eingangstür | Nicht an arc und nicht an den Hilfsdienst weitergeben. Ein Basic-Auth-Passwort oder ein Sitzungs-Cookie darf andere Komponenten nicht erreichen. |
| `X-Forwarded-For` | Eingangstür an arc | Auf die Client-Adresse setzen. Die Kette des Browsers nicht weitergeben. |

Der Hilfsdienst liest `X-Auth-User`, `X-Real-IP` und `Content-Length`. Alle anderen Header ignoriert er, auch `Host` und `Content-Type`.

**Die Berechtigung des Hilfsdienstes ist der Socket.** Der Hilfsdienst entscheidet nicht, wer was darf. Alles, was sich mit `verwaltung.sock` verbinden kann, kann alles tun, was die Seite kann, als root. Der Socket gehört `PACS_SOCKET_UID` und hat den Modus 0600. Ein Client, der sich verbinden kann, kann in `X-Auth-User` jeden beliebigen Namen setzen: Der gespeicherte Name ist nur so vertrauenswürdig wie die Eingangstür.

Die nginx-Dateien setzen diese Header in jeder Location, die mit arc oder dem Hilfsdienst spricht (`common/proxy.conf`):

```
proxy_set_header Host              $host;
proxy_set_header X-Forwarded-For   $remote_addr;
proxy_set_header X-Forwarded-Proto $pacs_scheme;
proxy_set_header X-Real-IP         $remote_addr;
proxy_set_header X-Auth-User       $pacs_user;
proxy_set_header X-PACS-Admin      "";
proxy_set_header Authorization     "";
proxy_set_header Cookie            "";
```

<a id="contract-guard"></a>
### 5.3 Der Schutz durch X-PACS-Admin (harte Anforderung)

Die Seite setzt den Header `X-PACS-Admin` bei jedem Aufruf, der etwas ändert. Sein Wert ist eine lesbare Beschreibung der Änderung, URL-kodiert, und das Protokoll speichert ihn. Eine Seite einer anderen Website kann ohne CORS-Preflight keinen eigenen Header setzen, daher hält der Schutz Cross-Site-Anfragen und versehentliche Anfragen auf. Der Hilfsdienst prüft den Header nicht. Der Schutz existiert nur in der Eingangstür, daher muss jede Eingangstür ihn umsetzen:

1. Einen `POST` an `/admin/dienst/` mit `403` beantworten, wenn `X-PACS-Admin` fehlt oder leer ist.
2. `GET /admin/dienst/platten` und `GET /admin/dienst/firewall?neu=1` ohne den Header mit `403` beantworten. Beide haben Nebenwirkungen (ein erneutes Einlesen der Platten, ein Lesen des Logs von arc). Die Seite sendet den Header bei beiden. Das rohe Request-Target vergleichen, genau wie der Hilfsdienst ([5.1](#contract-paths)), und unverändert weitergeben.
3. Jeden ändernden dcm4chee-Aufruf aus [5.5](#contract-dcm4chee) ohne den Header mit `403` beantworten.
4. Den Header entfernen, bevor die Anfrage an arc oder an den Hilfsdienst geht.
5. Auf `/admin/dienst/` nur `GET` und `POST` zulassen. `OPTIONS` und jede andere Methode mit `403` beantworten und keine CORS-Header senden. (`limit_except GET POST` von nginx lässt `HEAD` zusammen mit `GET` durch. Der Hilfsdienst beantwortet es mit 501.)

Beim Anmeldeverfahren `basic` sendet der Browser das zwischengespeicherte Passwort bei jeder Anfrage an die Website, auch bei einer Anfrage, die eine andere Website auslöst. Der Cross-Site-Schutz eines Sitzungs-Cookies (`SameSite`) fehlt dort, daher ist der Header der einzige Schutz. (Das folgt aus der Funktionsweise von Basic-Authentifizierung. Mit einem Browser wurde es nicht getestet.)

<a id="contract-minimal-nginx"></a>
### 5.4 Minimale nginx-Konfiguration für eine reine Admin-Seite

Diese Konfiguration liefert die Seite, die Statusdatei und den Hilfsdienst aus, mit dem Anmeldeverfahren basic. Übersicht, Firewall und Protokoll (Änderungen) funktionieren. Studien und Patienten brauchen die dcm4chee-Aufrufe aus [5.5](#contract-dcm4chee) und zeigen ohne sie „abgelehnt (HTTP 404)“. Die Datei nach `/etc/nginx/conf.d/default.conf` legen (sie steht im Block `http`). `/srv/pacs-admin/admin` (der Ordner `web/admin`), `/srv/pacs-admin/status` und `/run/pacs-admin` wie in [Abschnitt 3.5](#mounts) mounten.

```nginx
log_format pacs       escape=json '{"t":"$time_iso8601","u":"$pacs_user","sub":"$pacs_user","ip":"$remote_addr","r":"$request_uri","status":$status}';
log_format pacs_admin escape=json '{"t":"$time_iso8601","u":"$pacs_user","sub":"$pacs_user","ip":"$remote_addr","r":"admin","m":"$request_method","uri":"$request_uri","status":$status,"k":"$http_x_pacs_admin","body":"$request_body"}';

# the account name is never empty
map $remote_user $pacs_user { "" "anon-$remote_addr"; default $remote_user; }
# guard: a POST without X-PACS-Admin gets 403
map "$request_method:$http_x_pacs_admin" $pacs_post_ohne_admin { "POST:" 1; default 0; }
map $request_method $pacs_ist_post { POST 1; default 0; }
# guard: two GET calls change something and need the header too (raw target, as the helper compares it)
map "$request_method $request_uri" $pacs_dienst_get_wirkt {
    "~^GET /admin/dienst/platten$"          1;
    "~^GET /admin/dienst/firewall\?neu=1$"  1;
    default                                 0;
}
map "$pacs_dienst_get_wirkt:$http_x_pacs_admin" $pacs_dienst_get_ohne_admin { "1:" 1; default 0; }

server {
    listen 443 ssl;
    server_name pacs.example.org;
    ssl_certificate     /etc/nginx/tls/server.crt;
    ssl_certificate_key /etc/nginx/tls/server.key;
    absolute_redirect off;

    auth_basic "PACS";
    auth_basic_user_file /etc/nginx/htpasswd/admins;

    location = /admin { return 301 /admin/; }
    location /admin/ {
        alias /srv/pacs-admin/admin/;
        add_header Cache-Control no-cache;
    }
    location /admin/daten/ {
        alias /srv/pacs-admin/status/;
        add_header Cache-Control no-store always;
    }
    location ^~ /admin/dienst/ {
        limit_except GET POST { deny all; }
        if ($pacs_post_ohne_admin) { return 403; }
        if ($pacs_dienst_get_ohne_admin) { return 403; }
        client_max_body_size 64k;
        client_body_buffer_size 64k;
        access_log syslog:server=unix:/run/pacs-admin/protokoll.sock,nohostname,tag=zugriffe pacs;
        access_log syslog:server=unix:/run/pacs-admin/protokoll.sock,nohostname,tag=admin pacs_admin if=$pacs_ist_post;
        proxy_pass http://unix:/run/pacs-admin/verwaltung.sock:;
        proxy_http_version 1.0;
        proxy_read_timeout 300s;
        proxy_set_header X-Auth-User $pacs_user;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-PACS-Admin "";
        proxy_set_header Authorization "";
        proxy_set_header Cookie "";
        add_header Cache-Control no-store always;
    }
}
```

Die Datei schreibt Protokollzeilen nur für die Aufrufe von `/admin/dienst/`. Für den Rest des Servers hat sie kein `access_log`.

In Docker geprüft mit dem Image `nginx:1.30` (Debian 13), vor dem echten Hilfsdienst (Python 3.13, libsqlcipher 4):

- Ohne Namen und Passwort ergeben die Seite und der Pfad zum Hilfsdienst `401`. Ein falsches Passwort ergibt ebenfalls `401`. Mit einer richtigen Anmeldung ergeben die Seite, `config.js` und `status.json` `200`.
- Ein POST ohne `X-PACS-Admin` oder mit leerem Header ergibt `403`. Dasselbe gilt für `GET /admin/dienst/platten` und `GET /admin/dienst/firewall?neu=1` ohne den Header. Mit dem Header antwortet der Hilfsdienst mit seinem eigenen Status: `400` bei einem Body, der kein gültiges JSON ist oder dem Felder fehlen, `404` bei einem unbekannten Pfad.
- `PUT`, `DELETE` und `OPTIONS` ergeben `403`. `HEAD` kommt durch nginx, und der Hilfsdienst antwortet `501`. Ein Body von 70 KB ergibt `413`.
- 24 Anfragen an `/admin/dienst/` hinterließen 24 Zeilen `zugriffe` und 6 Zeilen `admin`: eine Zeile `admin` pro POST, die abgewiesenen eingeschlossen.
- Eine Attrappe, die die Anfrage zurückgibt, zeigte, was der Hilfsdienst empfängt. `X-Auth-User` und `X-Real-IP` kommen von nginx (gefälschte Werte des Browsers werden ersetzt). `X-PACS-Admin`, `Authorization` und `Cookie` kommen nicht an. `Host` ist `localhost`. Andere Header des Browsers, etwa `X-Forwarded-For`, werden durchgereicht. Der Hilfsdienst liest nur `X-Auth-User`, `X-Real-IP` und `Content-Length`.

Hier nicht nötig: der OHIF-Viewer, die Cross-Origin-Header, die oauth2-Locations, HTTP/2, gzip und ein Resolver. `auth_basic` lässt sich durch eine Netzliste (`allow` und `deny`) oder durch eine andere Anmeldung ersetzen. Die Namensregel beibehalten: `$pacs_user` darf nicht leer sein.

<a id="contract-dcm4chee"></a>
### 5.5 REST-Aufrufe an dcm4chee

Die Beispiele nutzen die Vorgabe-AE-Titel `DCM4CHEE` und `IOCM_QUALITY`. Die AE-Titel folgen `aet` und `iocmAet` aus `config.js`. Die Studien-UID in den Beispielen ist `1.2.3`.

Aufrufe der Admin-Seite:

| Aufruf | Stufe | `X-PACS-Admin` | Verwendet für |
|---|---|---|---|
| `GET /dcm4chee-arc/aets/DCM4CHEE/rs/studies?PatientID=...` | jedes Konto | nein | die Studiensuche (QIDO) des Reiters Studien. Die Parameter sind `PatientID`, `PatientName` (die Seite hängt ein `*` an), `AccessionNumber`, `StudyDate` (`YYYYMMDD-YYYYMMDD`), `includefield`, `limit=200` und `orderby`. |
| `GET /dcm4chee-arc/aets/DCM4CHEE/rs/studies?StudyInstanceUID=1.2.3,...` | jedes Konto | nein | die Abfragen des Reiters Protokoll: Studien einer Patientennummer (`PatientID`, `limit=1000`), eines Namens (`PatientName` mit `*` und `fuzzymatching=false`, `limit=1000`) und über Listen von bis zu 40 `StudyInstanceUID` (`limit=100`). Alle mit `includefield`. |
| `GET /dcm4chee-arc/aets/DCM4CHEE/rs/patients?...` | Admin | nein | die Patientensuche des Reiters Patienten (`PatientID`, `PatientName` mit `*`, `includefield=all`, `limit=100`) und die Abfrage des Zielpatienten, wenn man eine Studie verschiebt (`PatientID`, `includefield`) |
| `GET /dcm4chee-arc/aets/IOCM_QUALITY/rs/studies?...` | Admin | nein | die Ansicht der abgelehnten Studien (dieselben Parameter wie bei der Studiensuche) |
| `POST /dcm4chee-arc/aets/DCM4CHEE/rs/studies/1.2.3/reject/113001%5EDCM` | Admin | ja | eine Studie ablehnen |
| `POST /dcm4chee-arc/aets/IOCM_QUALITY/rs/studies/1.2.3/reject/REVOKE_REJECTION%5E99DCM4CHEE` | Admin | ja | eine abgelehnte Studie wiederherstellen |
| `DELETE /dcm4chee-arc/aets/IOCM_QUALITY/rs/studies/1.2.3` | Admin | ja | eine abgelehnte Studie endgültig löschen |
| `POST /dcm4chee-arc/aets/DCM4CHEE/rs/studies/update?reasonForModification=CORRECT&StudyInstanceUID=1.2.3` | Admin | ja | Studienattribute ändern (JSON-Body) |
| `POST /dcm4chee-arc/aets/DCM4CHEE/rs/studies/1.2.3/patient?PatientID=P1&IssuerOfPatientID=I1&updatePolicy=PRESERVE` | Admin | ja | eine Studie zu einem anderen Patienten verschieben |
| `POST /dcm4chee-arc/aets/DCM4CHEE/rs/patients/P1/merge/P2` | Admin | ja | zwei Patienten zusammenführen |
| `PUT /dcm4chee-arc/aets/DCM4CHEE/rs/patients/P1` | Admin | ja | einen Patienten ändern (der ganze Datensatz als JSON) |

Aufrufe des OHIF-Viewers (Viewer-Modus `ohif`): `GET` unterhalb von `/dcm4chee-arc/aets/DCM4CHEE/rs/studies`, `rs/series`, `rs/instances` und `/wado`, Stufe jedes Konto. OHIF sendet kein `orderby`, und dcm4chee listet dann die älteste Studie zuerst. Daher hängt nginx an jede Studiensuche ohne `orderby` den Parameter `orderby=-StudyDate,-StudyTime` an.

Sperren, die die nginx-Dateien zusätzlich setzen. Eine Eingangstür, die denselben Schutz will, bildet sie nach:

- Eine Studie nur mit genau der Abfrage `reasonForModification=NAME&StudyInstanceUID=UID` ändern, wobei `UID` aus Ziffern und Punkten besteht, mit Unterscheidung von Groß- und Kleinschreibung (ohne `StudyInstanceUID` ändert dcm4chee alle Studien). Diese eine Form zulassen, statt schlechte Formen zu sperren: Eine zweite `StudyInstanceUID` oder eine Kommaliste in einer wählt mehrere Studien aus, und arc liest den Schlüssel auch in anderen Schreibweisen (die Hex-Form `0020000D`), eine Liste verbotener Formen wäre also nie vollständig.
- Eine Studie nur mit `PatientID=ID`, wahlweise `&IssuerOfPatientID=ID`, und `&updatePolicy=PRESERVE` verschieben, in dieser Reihenfolge und sonst nichts (sonst überschreibt dcm4chee den Zielpatienten).
- Einen Patienten nie mit `merge` ändern und ein Prozentzeichen in einem Parameternamen ablehnen.
- Nur über `IOCM_QUALITY` endgültig löschen, wo dcm4chee nur abgelehnte Studien löscht.
- Einen Pfad, der `;`, einen kodierten Backslash (`%5c`) oder einen rohen Backslash enthält, mit `400` beantworten: nginx normalisiert Pfadparameter nicht, der Upstream möglicherweise schon.
- Die Sperren auf die Abfrage und der Schutz für den Pfad antworten vor der Anmeldeprüfung, eine falsche Anfrage bekommt also auch ohne Anmeldung 403 oder 400.
- Jeden anderen Pfad unterhalb von `/dcm4chee-arc/` mit `404` beantworten.

**dcm4chee muss ohne Keycloak laufen.** Die Seite und nginx senden kein Token an arc. Auch `pacs-storage.sh` ruft arc auf dem Host ohne Token auf: `POST ARC_URL/dcm4chee-arc/ctrl/reload` und `GET ARC_URL/dcm4chee-arc/storage`. Neben REST braucht der Platten-Assistent `docker exec` in den arc-Container und in den LDAP-Container. Die `-secure`-Images von dcm4chee (eigene Keycloak-Anmeldung) werden nicht unterstützt.

<a id="audit-wire-format"></a>
### 5.6 Protokollzeilen: Wire-Format

Die Eingangstür sendet pro Zeile ein Datagramm an den Unix-Datagram-Socket `PACS_LOG_SOCKET`. nginx tut das mit `access_log syslog:`. Ein Datagramm besteht aus diesen Teilen, ohne Zeilenumbruch:

| Teil | Wert |
|---|---|
| `<PRI>` | `<`, Ziffern, `>`, zum Beispiel `<190>` (nginx) oder `<13>` (`logger`). Die Zahl wird ignoriert. |
| Zeit | Genau 15 Zeichen, zum Beispiel `Oct  1 10:58:23`. Der Hilfsdienst ignoriert den Inhalt. |
| Leerzeichen | ein Leerzeichen |
| Syslog-Tag | `zugriffe`, `ereignisse` oder `admin`, in Kleinbuchstaben |
| Trenner | ein Doppelpunkt und ein Leerzeichen |
| Nachricht | ein JSON-Objekt in einer Zeile |

Beispiel:

```
<190>Oct  1 10:58:23 ereignisse: {"t":"2026-10-01T10:58:23+02:00","u":"anna","sub":"anna","ip":"192.0.2.10","r":"/dcm4chee-arc/aets/DCM4CHEE/rs/studies/1.2.3/series","status":200}
```

Der Hilfsdienst vergleicht jedes Datagramm mit diesem Muster, mit `re.match` und dem Flag `re.S`:

```
<\d+>.{15} (zugriffe|ereignisse|admin): (.*)
```

Ein Datagramm, das nicht passt, wird ohne Meldung verworfen. Typische Fehler sind ein Hostname zwischen Zeit und Syslog-Tag (nginx ohne `nohostname`), ein Syslog-Tag in anderer Groß- und Kleinschreibung und ein fehlendes `<PRI>`. Ein Zeilenumbruch am Ende wird akzeptiert. Ein Datagramm ist eine Zeile: keinen Zeilenumbruch ins JSON setzen. Der Hilfsdienst liest Datagramme bis 1 MiB. nginx-Zeilen von etwa 20 KB kamen vollständig an.

Jede Nachricht ist ein JSON-Objekt. Der Hilfsdienst speichert den Text unverändert. Die Zeit der Zeile nimmt er aus dem Feld `t`, und er nimmt die Ankunftszeit, wenn `t` fehlt oder nicht lesbar ist. Die Seite liest diese Felder:

| Feld | Syslog-Tags | Bedeutung |
|---|---|---|
| `t` | alle | Zeit der Anfrage in ISO 8601 mit einem numerischen Offset mit Doppelpunkt, zum Beispiel `2026-10-01T10:58:23+02:00` (nginx `$time_iso8601`). Python 3.7 bis 3.10 liest `+0200` und `Z` nicht: Der Hilfsdienst speichert dann die Ankunftszeit. Die Seite parst `t` selbst mit dem Browser: Eine Zeile ohne ein `t`, das der Browser liest, wird übersprungen und gezählt. |
| `u` | alle | Kontoname. Er sollte nicht leer sein. Ein leeres oder fehlendes `u` erscheint als „(ohne Konto)“. |
| `sub` | alle | ID des Kontos, wie die Anmeldung sie meldet. Die Seite liest sie nicht. Siehe [Abschnitt 6.2](#audit-account). |
| `ip` | alle | Adresse des Client-PCs. Die Seite zeigt sie als „PC“. Mit `rechner.json` zeigt sie auch den PC-Namen. |
| `r` | `zugriffe`, `ereignisse` | Die Request-URI, wie der Browser sie gesendet hat, mit der Query. Die Seite leitet die Aktion daraus ab. Bei `admin` ist der Wert der Text `admin`. |
| `status` | alle | HTTP-Status als Zahl. Ein Wert ab 400 erscheint als „(HTTP nnn)“. |
| `m` | `admin` | Methode. Optional. |
| `uri` | `admin` | Request-URI. Optional. Die Seite nimmt die Studiennummer daraus. |
| `k` | `admin` | Beschreibung von der Seite (der Wert von `X-PACS-Admin`, URL-kodiert). Optional. |
| `body` | `admin` | Request-Body. Die Seite liest ihn nicht. |

Die Syslog-Tags:

- `zugriffe`: jede Anfrage. Felder `t`, `u`, `sub`, `ip`, `r`, `status`. Nur `pacsdb.py` liest diesen Syslog-Tag. Der Reiter Protokoll liest ihn nicht.
- `ereignisse`: Anfragen, die für Anwender zählen: Suchen, geöffnete Studien und Befunde. Dieselben Felder. Der Reiter leitet die Aktion aus `r` ab.
- `admin`: Änderungen. Felder `t`, `u`, `sub`, `ip`, `r` (immer `admin`), `m`, `uri`, `status`, `k`, `body`.

Was der Reiter Protokoll mit einer Zeile macht: Er fragt den Hilfsdienst nach den Syslog-Tags `ereignisse` und `admin` für die gewählten Tage. Danach gilt:

- Eine Zeile, die kein JSON-Objekt ist, wird übersprungen und gezählt.
- Eine Zeile ohne ein `t`, das der Browser lesen kann, wird übersprungen und gezählt.
- Ein `r`, das der Browser nicht als Adresse lesen kann, wird übersprungen und gezählt. Der Reiter zeigt die Zahl unter der Liste: „N unlesbare Zeilen übersprungen“ (bei einer Zeile: „1 unlesbare Zeile übersprungen“).
- Eine Zeile ohne `r` oder mit einem `r`, das keine Studiensuche, keine Patientensuche, keine geöffnete Studie und kein geöffneter Befund ist, wird ohne Zählung übersprungen. Eine Suche, deren einziger Filter `StudyInstanceUID` ist, wird ebenfalls übersprungen: OHIF und die Seite selbst senden sie, wenn sie eine Studie öffnen.
- Ein fehlendes oder leeres `u` erscheint als „(ohne Konto)“.
- Eine Zeile `admin` zeigt den Text von `k`, oder `m` und `uri`, wenn `k` fehlt, oder „Änderung“, wenn alle drei fehlen, gefolgt von „(Verwaltung)“. Der Reiter nimmt die Studiennummer aus `uri`.
- Ein fehlender `status` zählt als kein Fehler. Ein Wert ab 400 erscheint als „(HTTP nnn)“.
- Der Reiter zeigt höchstens 2000 Zeilen, die neuesten zuerst. Dasselbe Konto mit derselben Studie oder Suche innerhalb von 30 Minuten zählt als eine Zeile, und jede Wiederholung startet die 30 Minuten neu. Zeilen `admin` werden nie zusammengefasst.

Der Name und die Studiendetails einer Zeile kommen zur Anzeigezeit aus dem Archiv: Der Reiter fragt `rs/studies` nach den Studiennummern oder nach der Patientennummer oder dem Namen, die man im Filter eingegeben hat ([5.5](#contract-dcm4chee)).

Die Übersicht zeigt die letzten 15 Zeilen `admin` mit `t`, `u`, `k` (oder `m` und `uri`) und `status`. Ein `status` unter 300 erscheint als „erledigt“, alles andere als „HTTP nnn“. Beide Ansichten fragen den Hilfsdienst nach den Zeilen. Antwortet er mit einem Fehler, zeigt der Reiter Protokoll „Fehler: Protokoll: HTTP nnn“.

<a id="audit-feed"></a>
### 5.7 Das Protokoll aus einem anderen Programm füttern

Eine andere Eingangstür oder ein Log-Shipper kann die Datagramme selbst schreiben. Der Socket gehört `PACS_SOCKET_UID` und hat den Modus 0600: Das Programm muss als root oder als diese uid laufen oder im nginx-Container. Mit `logger` aus dem Paket `bsdutils`:

```
logger -u /run/pacs-admin/protokoll.sock -t zugriffe '{"t":"2026-10-01T12:00:00+02:00","u":"anna","sub":"anna","ip":"192.0.2.10","r":"/admin/","status":200}'
```

`logger` sendet `<13>Oct  2 07:44:42 zugriffe: {...}`, und der Hilfsdienst akzeptiert das. Ein Shipper in Python, der JSON-Zeilen von stdin liest:

```python
import socket, sys, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
for line in sys.stdin:
    line = line.strip()
    if line:
        s.sendto(("<13>%s zugriffe: %s" % (time.strftime("%b %e %H:%M:%S"), line)).encode(), "/run/pacs-admin/protokoll.sock")
```

Der Hilfsdienst speichert die Zeilen binnen etwa 2 Sekunden. Das Ergebnis prüfen:

```
python3 /opt/pacs-admin/server/pacsdb.py protokoll zugriffe $(date +%F)
```

Grenzen:

- Der Reiter Protokoll liest nur `ereignisse` und `admin`. Ein Shipper, der nur `zugriffe` schreibt, füllt die Datenbank, und der Reiter bleibt leer. Um den Reiter zu füllen, die Anfragen selbst einordnen: `ereignisse` für Suchen und geöffnete Studien, `admin` für Änderungen (mit `m`, `uri`, `k`).
- Nur nginx hat die Maps und `$request_body` für Zeilen `ereignisse` und `admin`.
- Caddy und Traefik schreiben JSON nach stdout oder in eine Datei und brauchen einen Shipper wie den obigen. oauth2-proxy, Authelia, Authentik und Cloudflare Access sehen nur die Anmeldeanfrage und können die Zeilen deshalb nicht schreiben.

Apache 2.4 kann `zugriffe` über ein `CustomLog` mit Pipe füttern. Dieses Format lieferte gültige Zeilen (getestet mit Apache 2.4.68 und `logger` aus `bsdutils`):

```
LogFormat "{\"t\":\"%{%Y-%m-%dT%H:%M:%S%z}t\",\"u\":\"%u\",\"sub\":\"%u\",\"ip\":\"%a\",\"r\":\"%U%q\",\"status\":%>s}" pacs
CustomLog "|/usr/bin/logger -u /run/pacs-admin/protokoll.sock -t zugriffe" pacs
```

Drei Unterschiede zu nginx:

- `u` ist `-` bei einer Anfrage ohne Anmeldung. Apache kennt keine Regel wie `anon-` plus die Adresse.
- `%z` schreibt den Offset ohne Doppelpunkt, zum Beispiel `+0200`. Python vor 3.11 kann das nicht lesen, daher speichert der Hilfsdienst solche Zeilen mit der Ankunftszeit. (Python 3.13 las es. Python 3.7 bis 3.10 wurde nicht ausgeführt.)
- `%U` ist der dekodierte Pfad, und Apache schreibt ein Steuerzeichen als `\x01`, das kein gültiges JSON ist. Ein Anführungszeichen oder ein Backslash wird richtig maskiert.

<a id="contract-client-ip"></a>
### 5.8 Die echte Client-Adresse

Die Eingangstür muss die echte Adresse des Client-PCs in `X-Real-IP` weitergeben und diese Adresse im Feld `ip` der Protokollzeilen verwenden. Der Hilfsdienst nutzt `X-Real-IP` für die Prüfung gegen Selbstaussperrung der Firewall: Ein Speichern wird abgelehnt, wenn der speichernde PC den Zugriff auf den https-Port verlöre (den ersten von `FW_WEB_PORTS`). Die Prüfung gilt nur für IPv4-Adressen. Adressen in Docker-Netzen, auf dem Server selbst und auf Loopback sind ausgenommen. Fehlt der Header oder ist er keine IPv4-Adresse, entfällt die Prüfung, und die Änderung wird akzeptiert.

Hinter einem anderen Proxy ist die Adresse der Verbindung die Adresse des Proxys, meist in einem Docker-Netz. Das Protokoll und die Spalte „PC“ zeigen dann den Proxy, und die Prüfung gegen Selbstaussperrung bewirkt nichts. Steht nginx hinter einem Proxy, die echte Adresse aus dem Header des Proxys setzen. Der Listener `behind-proxy` tut das:

```
set_real_ip_from 203.0.113.1;   # CHANGE-ME: die Adresse des eigenen Proxys
real_ip_header X-Forwarded-For;
real_ip_recursive on;
```

Die mitgelieferte Datei trägt `203.0.113.1`, eine Adresse aus dem Dokumentationsbereich, die niemandem vertraut. Diese Adresse durch die des eigenen Proxys ersetzen, höchstens durch das Netz, das nginx mit ihm teilt, und nur den Proxy nginx erreichen lassen. Von überall sonst ist `X-Forwarded-For` eine Fälschung.

<a id="contract-same-origin"></a>
### 5.9 Gleicher Origin und absolute Pfade

Die Seite liegt unter `/admin/` an der Wurzel des Origin und ruft `/admin/daten/`, `/admin/dienst/` und `/dcm4chee-arc/aets/AET/rs` mit absoluten Pfaden auf demselben Origin auf. Der Hilfsdienst vergleicht den Pfadtext wörtlich. Eine Eingangstür, die einen Pfad umschreibt, ein Präfix entfernt, die Seite unter einem Unterpfad ausliefert oder die Seite und die REST-Aufrufe auf verschiedene Hosts oder Ports verteilt, funktioniert nicht, ohne dass man `index.html` ändert. Die Seite liest nie Cookies. Die Aufrufe der Seite verwenden die Cookies oder das Passwort, die der Browser für denselben Origin hält.

Wenn die Sitzung endet, sollte die Eingangstür einen Aufruf mit einer Umleitung (auf die Anmeldeseite) oder mit dem Status 401 beantworten. Die Seite behandelt beides als abgelaufene Sitzung und zeigt „Sitzung abgelaufen, Seite neu laden (F5)“. Die Seite folgt keinen Umleitungen und behandelt daher jede Umleitung so, auch eine auf denselben Origin. Aufrufe nicht aus anderen Gründen umleiten, zum Beispiel um einen Schrägstrich am Ende anzuhängen.

<a id="audit-log"></a>
## 6. Protokoll

Das Protokoll hält fest, wer gesucht, wer was geöffnet und wer was geändert hat. nginx sendet die Zeilen, der Hilfsdienst speichert sie in einer verschlüsselten Datenbank, und der Reiter Protokoll zeigt sie an. Das Wire-Format steht in [Abschnitt 5.6](#audit-wire-format).

<a id="audit-tags"></a>
### 6.1 Was unter welchem Syslog-Tag protokolliert wird

| Syslog-Tag | Was | Wo nginx es schreibt |
|---|---|---|
| `zugriffe` | jede Anfrage: statische Dateien, Suchen, Änderungen und abgewiesene Anfragen | der Server-Block von `pacs.conf`. Die schreibenden Locations, `/admin/dienst/` und der Abschnitt für die dcm4chee-Oberfläche wiederholen es, weil ein `access_log` in einer Location die des Server-Blocks ersetzt. |
| `ereignisse` | nur `GET`: eine Studiensuche (`rs/studies`), eine Patientensuche (`rs/patients`), eine Suche in der Ansicht der abgelehnten Studien (`IOCM_QUALITY/rs/studies`), die Serienliste einer Studie (das heißt „Studie geöffnet“), die Metadaten einer Instanz und WADO-URI (das heißt „Befund geöffnet“) | der Server-Block, für den Viewer und die Seite. Der Abschnitt für die dcm4chee-Oberfläche schreibt es auch, für dieselben Aufrufe. |
| `admin` | jede Anfrage an eine schreibende Location, auch eine abgewiesene; jeder `POST` an `/admin/dienst/`; jede Anfrage des Abschnitts für die dcm4chee-Oberfläche außer `GET`, `HEAD` und `OPTIONS` | `common/audit-write.conf` (in die schreibenden Locations eingebunden), die Location `/admin/dienst/`, der Abschnitt für die dcm4chee-Oberfläche |

Eine Änderung über die Seite schreibt also zwei Zeilen, eine `zugriffe` und eine `admin`. Ein `GET` an `/admin/dienst/` schreibt eine Zeile, `zugriffe`. Eine Studiensuche schreibt `zugriffe` und `ereignisse`.

Nichts geht nach `docker logs`, weil die URLs Patientendaten enthalten. Für eine Debug-Sitzung eine Zeit lang `access_log /dev/stdout pacs;` in den Server-Block setzen. Das erfasst nur die Locations ohne eigenes `access_log`.

<a id="audit-account"></a>
### 6.2 Der Kontoname

Das Feld `u` ist nie leer. nginx füllt es so:

| Anmeldeverfahren | `u` |
|---|---|
| `oauth2-proxy` | der Claim `preferred_username`; ist er leer, die E-Mail-Adresse; dann die Benutzer-ID, die oauth2-proxy meldet (der Wert von `sub`); dann `anon-` plus die Client-Adresse |
| `basic` | der Name, den der Client gesendet hat (der behauptete Name, auch bei falschem Passwort); `anon-` plus die Client-Adresse, wenn kein Name gesendet wurde |
| `none` | immer `anon-` plus die Client-Adresse. Es gibt keine Konten. |

`sub` trägt die ID, die die Anmeldung meldet. Bei `oauth2-proxy` ist es der Header `X-Auth-Request-User` von oauth2-proxy (leer, wenn keine Sitzung geprüft wurde). Bei `basic` und `none` ist es gleich `u`. `sub` ist nur der Name des Feldes: Was oauth2-proxy in diesen Header schreibt, hängt von dessen Einstellungen und vom Anbieter ab, und es ist nicht zwingend der Claim `sub` des ID-Tokens.

<a id="audit-refused"></a>
### 6.3 Abgewiesene Anfragen haben kein geprüftes Konto

nginx weist einige Anfragen ab, bevor die Anmeldeprüfung lief: ein fehlendes `X-PACS-Admin`, ein Verstoß gegen eine Sperre, ein `;` im Pfad. Bei den Anmeldeverfahren `oauth2-proxy` und `none` weist die Anmeldeprüfung einen Nicht-Admin auf `/admin/` ab, und sie setzt bei einem Fehlschlag kein Konto. Alle diese Zeilen tragen `anon-` plus die Client-Adresse. Beim Anmeldeverfahren `basic` tragen sie den Namen, den der Client gesendet hat. Eine abgewiesene Zeile zeigt den PC und die Zeit, keine geprüfte Person. Um die Person zu finden, die `ip` und die Zeit mit den Zeilen `zugriffe` desselben PCs vergleichen.

Auch eine Anfrage ohne Sitzung wird protokolliert. Mit oauth2-proxy bekommt sie den Status 302 und das `u` `anon-ADRESSE`. Eine Such-URL, die ohne Sitzung angefragt wurde, erscheint im Reiter daher als Suche von `anon-ADRESSE`. Beim Anmeldeverfahren `basic` zeigt eine fehlgeschlagene Anmeldung den behaupteten Namen und den Status 401, daher heißt eine Zeile mit 401 für `vera` nicht, dass Vera etwas getan hat. Das Fehlerlog von nginx hält zusätzlich `user "vera": password mismatch` fest.

Zeilen mit einem Status ab 400 erscheinen als „(HTTP nnn)“. Der Filter „nur Abgelehntes und Fehler“ listet sie auf.

<a id="audit-lost"></a>
### 6.4 Verlorene Zeilen

nginx sendet die Zeilen als Datagramme und wartet nicht. Solange der Hilfsdienst steht oder neu startet, geht jede Zeile verloren. Nach einem Neustart hat der Hilfsdienst eine neue Socket-Datei, und auch die erste Zeile jedes nginx-Workers geht verloren. Die Anwender arbeiten weiter, und nichts zeigt einen Fehler, aber ein Aufruf von `/admin/dienst/` antwortet mit 502.

Das Fehlerlog von nginx zeigt beides. Für jede verlorene Zeile enthält es bis zu drei Meldungen, alle mit `to syslog`:

```
[error] send() failed (111: Connection refused) while logging to syslog, server: unix:/run/pacs-admin/protokoll.sock
[alert] connect() failed (111: Connection refused) while logging to syslog, server: unix:/run/pacs-admin/protokoll.sock
[warn] send() to syslog failed while logging request, ...
```

Für das 502 enthält es `connect() to unix:/run/pacs-admin/verwaltung.sock failed (111: Connection refused) while connecting to upstream`. Die verlorenen Zeilen auflisten:

```
docker logs ohif 2>&1 | grep 'to syslog'
```

`pacs-verwaltung` selten und außerhalb der Arbeitszeit neu starten.

Kann der Hilfsdienst die Datenbank nicht schreiben (Schlüssel fehlt oder ist falsch, Platte voll), behält er die Zeilen im Arbeitsspeicher und versucht es alle 10 Sekunden erneut. Ein Neustart des Dienstes verwirft diese Zeilen. Das Journal nennt den Grund, zum Beispiel `Protokoll nicht abgelegt (5 Zeilen), neuer Versuch in 10 s: [Errno 2] No such file or directory: '/etc/pacs-protokoll.key'`. Solange die Datenbank nicht nutzbar ist, bekommen `GET /admin/dienst/protokoll` und der Reiter Protokoll den Status 503. Beim nächsten Versuch, nachdem der Schlüssel oder die Platte repariert ist, speichert der Hilfsdienst die behaltenen Zeilen.

<a id="audit-retention"></a>
### 6.5 Aufbewahrung

Das Protokoll wird nie bereinigt. Kein Programm in diesem Repository entfernt Zeilen. Die Datenbank wächst mit jeder Anfrage, weil `zugriffe` pro Anfrage eine Zeile enthält, statische Dateien eingeschlossen. Den Plattenplatz von `/var/lib/pacs-protokoll/` und eigene Aufbewahrungsregeln einplanen. Das Protokoll enthält Patienten-IDs und Namen aus Such-URLs und aus dem Body von Änderungen. Es wie Patientendaten behandeln.

<a id="audit-key-format"></a>
### 6.6 Schlüssel und Datenbankformat

**Schlüssel.** Die Datenbank ist mit SQLCipher verschlüsselt. Der Schlüssel ist ein roher 256-Bit-Schlüssel: 64 hexadezimale Zeichen in Kleinbuchstaben in `PROTOKOLL_KEY`. Er ist keine Passphrase und hat keine Schlüsselableitung. Den Schlüssel erzeugen, prüfen und eine Kopie offline aufbewahren (zum Beispiel im Passwort-Safe). Ohne den Schlüssel kann niemand das Protokoll lesen, auch der Betreiber nicht.

```
(umask 077; openssl rand -hex 32 > /etc/pacs-protokoll.key)
grep -Eq '^[0-9a-f]{64}$' /etc/pacs-protokoll.key && echo key ok
```

`pacsdb.py test` nutzt einen temporären Schlüssel und öffnet die Schlüsseldatei nie. Um den echten Schlüssel zu prüfen, die echte Datenbank lesen: `python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse`. Bei einer leeren Datenbank gibt das Programm nichts aus. Siehe [Installationsanleitung](install.de.md#audit-key).

**Dateiformat.** SQLCipher 3.x und 4.x schreiben verschiedene Dateiformate. Neue Datenbanken bekommen Format 3 (`PRAGMA cipher_compatibility = 3`, Seitengröße 1024), das beide Bibliotheksversionen öffnen. Version 3.x ignoriert das Pragma, weil Format 3 dort die Vorgabe ist. Beim Öffnen einer Datei versucht `pacsdb.py` zuerst Format 3, dann die Vorgabe der Bibliothek (Format 4 bei 4.x).

| Datei | Öffnet sich mit libsqlcipher 3.x | Öffnet sich mit libsqlcipher 4.x |
|---|---|---|
| Format 3, geschrieben mit 3.x | ja | ja |
| Format 3, geschrieben mit 4.x (von dieser Version) | ja | ja |
| Format 4, geschrieben mit 4.x von einer älteren Version von `pacsdb.py` | nein | ja |

Alle Zeilen wurden mit libsqlcipher 3.4.1 (Debian 10 und 12) und 4.6.1 (Debian 13) getestet. Andere Versionen sind nicht getestet. Nach einem Upgrade des Betriebssystems (Debian 12 auf 13) bleibt die Datei lesbar. Eine Datei im Format 4 lässt sich auf einem Host mit libsqlcipher 3.x nicht öffnen. SQLCipher gibt bei drei Ursachen dieselbe Antwort: ein falscher Schlüssel, eine Datei, die keine SQLCipher-Datei ist, und eine Datei im Format 4 auf 3.x. Daher nennt der Fehler alle drei und die Version der Bibliothek. Er beginnt mit dem Pfad und dem SQLite-Text (`file is not a database` oder `file is encrypted or is not a database`) und endet so: `Schluessel falsch, keine SQLCipher-Datei oder eine Datei im Format von SQLCipher 4, die libsqlcipher 3.x nicht oeffnet (hier SQLCipher 3.4.1), siehe docs/install.de.md#audit-key`. Ein fehlgeschlagenes Öffnen ändert nichts an der Datei. Einen Konverter gibt es nicht. Entweder die Datei auf einem Host mit 4.x lesen (`pacsdb.py protokoll` gibt JSON-Zeilen aus), oder die Datei beiseite legen und den Dienst eine neue Datei im Format 3 mit demselben Schlüssel anlegen lassen.

Von Hand, mit dem Programm `sqlcipher`:

```
sqlcipher /var/lib/pacs-protokoll/protokoll.db
PRAGMA key = "x'CHANGE-ME-64-HEX-CHARACTERS'";
PRAGMA cipher_compatibility = 3;
select count(*) from protokoll;
```

Die Zeile `PRAGMA cipher_compatibility = 3;` ist für eine Datei im Format 3 auf SQLCipher 4.x nötig und wird auf 3.x ignoriert. Die Tabelle ist `protokoll(id, quelle, zeit, zeile)`: `quelle` ist der Syslog-Tag, `zeit` die Zeit als Anzahl Sekunden, `zeile` die JSON-Zeile.

<a id="audit-read"></a>
### 6.7 Das Protokoll auf der Kommandozeile lesen

Auf dem Server, als root:

```
python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse 2026-10-01 2026-10-02
```

Die Argumente sind der Syslog-Tag (`zugriffe`, `ereignisse` oder `admin`) und optional ein erster und ein letzter Tag als `YYYY-MM-DD`. Der letzte Tag ist eingeschlossen. Die Tage beginnen um Mitternacht in der Zeitzone des Servers. Das Programm gibt pro Zeile der Datenbank eine JSON-Zeile aus, nach Zeit sortiert. Ein unbekannter Syslog-Tag ergibt keine Ausgabe und keinen Fehler. Ein Datum, das es nicht lesen kann, zählt als die aktuelle Zeit: kein Fehler und meist keine Ausgabe.

Das Programm nutzt `PROTOKOLL_DB` und `PROTOKOLL_KEY`. Wurden sie in `/etc/default/pacs-admin` geändert, zuerst die Datei laden:

```
set -a; . /etc/default/pacs-admin; set +a
```

Existiert die Datenbankdatei nicht, legt das Programm sie leer an, zusammen mit ihrem Ordner (Ordner mit Modus 700, Datei mit Modus 600). Daher bei leerer Ausgabe den Pfad prüfen. Bei einem Problem (Schlüssel fehlt oder ist falsch, Bibliothek fehlt, falsches Format) gibt das Programm eine Zeile `pacsdb.py: ...` aus und endet mit 1. Ohne Argumente gibt es seine Aufrufhilfe aus und endet mit 1.

Der Hilfsdienst liefert dieselben Zeilen über seinen Socket (als root, ohne nginx):

```
curl -s --unix-socket /run/pacs-admin/verwaltung.sock 'http://localhost/admin/dienst/protokoll?quelle=admin&letzte=15'
```

| Parameter | Bedeutung |
|---|---|
| `quelle` | Ein oder mehrere Syslog-Tags, durch Kommas getrennt. Vorgabe `ereignisse,admin`. Unbekannte Namen werden ignoriert. Die Antwort ist 400, wenn keiner übrig bleibt. |
| `von`, `bis` | Erster und letzter Tag als `YYYY-MM-DD`, der letzte Tag eingeschlossen. Vorgabe: die letzten 30 Tage. Die Tagesgrenzen liegen um Mitternacht in der Zeitzone des Servers. Ein ungültiges Datum ergibt 400. Ein umgekehrter Bereich ergibt eine leere Antwort. |
| `letzte` | Die letzten N Zeilen, höchstens 1000, unabhängig von den Daten. 0 oder eine negative Zahl heißt: den Datumsbereich verwenden. Eine Nicht-Zahl ergibt 400. |

Die Antwort hat den Typ `application/x-ndjson`: eine JSON-Zeile pro Zeile der Datenbank, durch Zeilenumbrüche getrennt, nach Zeit sortiert. Auch die Seite und die nginx-Zeilen nutzen Zeitzonen: `t` trägt den Offset von nginx (`/etc/localtime` in den Container mounten), die Tagesgrenzen des Hilfsdienstes nutzen die Zeitzone des Servers, und die Seite nutzt die Zeitzone des Browsers. Server, Container und Browser in derselben Zeitzone halten.
