# dcm4chee-admin-panel

[English](README.md) | Deutsch

<a id="what-it-is"></a>
## Was es ist

Das Admin-Panel ist eine einzelne Webseite für ein dcm4chee-arc-light-Archiv, das unter Docker Compose läuft. Es zeigt Platten und Dienste, sucht und bearbeitet Studien und Patienten, steuert die Firewall der Docker-Ports und führt ein verschlüsseltes Protokoll. nginx liefert die Seite aus und prüft die Anmeldung, und ein kleiner Hilfsdienst auf dem Host erledigt, was ein Browser nicht kann: Platten hinzufügen, iptables-Regeln setzen und das Protokoll schreiben.

Die Seite ist auf Deutsch. Die Anleitungen und die Installationswerkzeuge gibt es auf Englisch und Deutsch. Eine Demo mit erfundenen Daten läuft auf jedem PC in 5 Minuten ([Weg A](#choose-your-path)).

<a id="screenshots"></a>
## Bildschirmfotos

![Übersicht: Platten, Schreibliste, Container, Firewall](docs/screenshots/overview.png)

![Firewall: Ports, Modi, neu erkannte Quellen](docs/screenshots/firewall.png)

![Protokoll: Zugriffe und Änderungen mit Filtern](docs/screenshots/protokoll.png)

![Studien: suchen und bearbeiten](docs/screenshots/studien.png)

<a id="features"></a>
## Funktionen

<a id="feature-overview"></a>
### Übersicht

- Die Platten des Archivs mit Füllstand und freiem Platz. Die Seite zeigt, welche Platte jetzt neue Bilder bekommt und welche Platten folgen. Die Reihenfolge ist die [Schreibliste](docs/glossary.de.md#write-list) der Archiv-AE (`dcmObjectStorageID` und `dcmMetadataStorageID`). Fällt der Platz bis zur Schwelle, ab der die Platten als voll zählen, unter `STORAGE_WARN_GB` (Vorgabe 300 GB), bittet die Seite um eine neue Platte.
- Schreibliste:
  - `In Schreibliste aufnehmen` hängt eine Platte ans Ende der Liste.
  - `Aus Schreibliste nehmen` nimmt eine Platte aus der Liste. Die Bilder darauf bleiben lesbar. Die Seite blendet die Schaltfläche bei der letzten Platte aus, die neue Bilder annimmt, und `pacs-storage.sh` lehnt es ab, den letzten Speicher zu entfernen, der nicht als voll markiert ist.
  - `Markierung entfernen` löscht die Markierung „voll“ (`dcmStorageThresholdExceeded`), die dcm4chee an der Schwelle setzt.
  - Aufnehmen und Markierung löschen brauchen mindestens `STORAGE_FREE_GB` freien Platz auf der Platte (Vorgabe 50 GB). Die Seite zeigt diese beiden Schaltflächen nur bei Platten mit mindestens so viel freiem Platz (`frei_gb` in `status.json`), und `pacs-storage.sh` prüft noch einmal.
- Neue Festplatte: dem Server (oder der VM) eine leere Platte geben. Die Platte erscheint innerhalb von 5 Minuten, oder sofort mit `Jetzt suchen`. Nach der Bestätigung formatiert `pacs-storage.sh` sie als ext4, hängt sie unter `STORAGE_BASE` ein, trägt sie in `/etc/fstab` ein, legt den Speicher in LDAP als Kopie des aktuellen an und hängt ihn an die Schreibliste an. Die Seite zeigt jeden Schritt und die Ausgabe des Skripts.
- Die Container des Compose-Projekts von dcm4chee, laufend oder gestoppt.
- Kachel Firewall: ein oder aus, Modus für Ports ohne Regel, Modus des DICOM-Ports, Anzahl der Client-PCs, IPv6-Warnung und Anzahl der neu erkannten Quellen.
- Die letzten 15 Änderungen über die Seite, mit Konto.

<a id="feature-studies"></a>
### Studien

- Suche nach Patienten-ID, Name, Accession-Nummer und Datumsbereich (`Von`, `Bis`). Zur Wahl stehen aktive und abgelehnte Studien. Die neuesten Studien kommen zuerst, bis zu 200 Treffer.
- Beschreibung, Accession-Nummer, Studiendatum und Zuweiser bearbeiten. dcm4chee hält die alten Werte in der Original Attributes Sequence fest.
- Eine Studie zu einem anderen Patienten verschieben. Name und Geburtsdatum des Zielpatienten bleiben, wie sie sind.
- Eine Studie ablehnen (`113001^DCM`). In der Ansicht der abgelehnten Studien eine Studie zurückholen oder endgültig löschen. Vor dem Löschen muss man die Accession-Nummer (oder die Patienten-ID) eintippen.

<a id="feature-patients"></a>
### Patienten

- Suche nach Patienten-ID und Name, bis zu 100 Treffer.
- Name, Geburtsdatum und Geschlecht bearbeiten. Die Seite schickt den ganzen Datensatz zurück, deshalb bleiben Adresse und andere Attribute erhalten.
- Zwei Patienteneinträge zusammenführen.
- Ein Hinweis warnt, dass die nächste HL7-ADT-Nachricht Änderungen bei Patienten überschreibt, die das Krankenhausinformationssystem liefert.

<a id="feature-firewall"></a>
### Firewall

- iptables-Regeln für jeden Port, den Docker veröffentlicht. Jeder Port hat einen Modus: `offen` (alle kommen durch), `Probelauf` (alle kommen durch, Quellen, die nicht auf der Liste stehen, landen im Log) oder `gesperrt` (nur aufgelistete IPv4-Adressen und Netze).
- Ein Modus für Ports ohne eigene Regel. Er gilt auch für Ports, die Docker erst später veröffentlicht.
- Ports, die Docker auch über IPv6 veröffentlicht, erhalten das Badge `IPv6 nicht gefiltert`, siehe [Einschränkungen](#limitations).
- Die Web-, DICOM- und HL7-Ports sind Einstellungen (`FW_WEB_PORTS`, `FW_DICOM_PORTS`, `FW_HL7_PORTS`), für Installationen, die DICOM auf 104 oder den Viewer auf einem anderen Port veröffentlichen.
- `Neu erkannt` listet Quellen, die gesehen wurden, aber für ihren Port nicht erlaubt sind. Jeder Eintrag hat die Schaltflächen `Erlauben` und `Ausblenden`. Die Quellen stammen aus dem `server.log` von dcm4chee (DICOM- und HL7-Absender, alle 5 Minuten gelesen), aus dem Kernel-Log (Verbindungen, die die Regeln mitgeschrieben haben, letzte 7 Tage) und aus der Client-PC-Erkennung.
- Die Client-PC-Erkennung fragt DNS-Namen ab, die aus Mustern wie `pc{01..20},ws{001..040}` entstehen (`FW_CLIENT_NAMES`). Pro Gruppe von PCs schlägt die Erkennung ein /24-Netz für den ersten DICOM-Port vor. Ein leeres Muster heißt: keine Abfragen, und die Karte bleibt verborgen.
- Zähler für neue Verbindungen pro Port und Quelle.
- `Speichern` wendet die Änderungen an. Der Dienst lehnt einen Regelsatz ab, der den speichernden PC vom ersten Web-Port (https) aussperren würde. Er behält die vorige Fassung in `PACS_DIR/firewall/` und kehrt zu ihr zurück, wenn das Anwenden scheitert.

<a id="feature-audit"></a>
### Protokoll

- Wer nach Studien oder Patienten gesucht hat, wer welche Studie oder welchen Bericht geöffnet hat (im Viewer, auf dieser Seite oder im Abschnitt für die dcm4chee-Oberfläche) und jede Änderung über die Seite, mit Konto, PC und Zeit.
- Filter: Zeitraum (`Von`, `Bis`, `Heute`, `7 Tage`, `30 Tage`), Patienten-ID, Patientenname, Konto, PC, Art des Eintrags und freier Text. Dasselbe Konto mit derselben Studie oder Suche innerhalb von 30 Minuten zählt als ein Eintrag. Jede Wiederholung startet die 30 Minuten neu, und Änderungen werden nie zusammengefasst. Die Seite zeigt die 2000 neuesten Einträge.
- CSV-Export für Excel (Semikolon, UTF-8 mit BOM).
- Verschlüsselt mit SQLCipher auf dem Server gespeichert. Auch jede einzelne Anfrage wird gespeichert (Quelle `zugriffe`) und lässt sich mit `server/pacsdb.py` lesen.

<a id="feature-settings"></a>
### Kopfzeile und Seiteneinstellungen

Die Kopfzeile enthält Links auf die Oberfläche von dcm4chee und auf den Viewer, den Kontonamen des angemeldeten Benutzers und, wenn eine Abmelde-Adresse gesetzt ist, den Link `Abmelden`. Titel, AE-Titel, Links, ein optionales Logo, die Adresse, die den Kontonamen liefert (`kontoUrl`), der Abmelde-Link (`abmeldenUrl`) und die Sprachkennung für Zahlen und Zeitstempel stammen aus `web/admin/config.js` ([Referenz](docs/reference.de.md#config-js)). Endet die Anmelde-Sitzung, zeigt die Seite `Sitzung abgelaufen, Seite neu laden (F5)` statt einer Fehlermeldung des Browsers.

<a id="choose-your-path"></a>
## Den Weg wählen

| Weg | Wofür | Was man braucht | Start |
|---|---|---|---|
| **A. Demo** | Ein erster Blick in 5 Minuten | Python 3.7 oder neuer auf einem beliebigen PC | [Demo](docs/install.de.md#demo) |
| **B. Echte Installation mit Single Sign-on** | Alltag mit Microsoft Entra ID oder einem anderen OpenID-Connect-Anbieter | Server, DNS-Name, TLS-Zertifikat und das Recht, beim Anbieter eine App zu registrieren | [Echte Installation](docs/install.de.md#real-install), [Anmeldung mit oauth2-proxy](docs/login.de.md#login-oauth2), [Entra ID](docs/login.de.md#login-oauth2-entra) |
| **C. Echte Installation ohne OAuth-Proxy** | Alltag mit Konten, die nginx führt, oder ein geschlossenes Netz | Server, DNS-Name und TLS-Zertifikat | [Echte Installation](docs/install.de.md#real-install), [Anmeldung basic](docs/login.de.md#login-basic), [Anmeldung none](docs/login.de.md#login-none) |

Die Installationsanleitung vergleicht die Wege unter [Den Weg wählen](docs/install.de.md#pick-path). Wer sich nicht für eine Anmeldung entscheiden kann, liest [Eine Anmeldung wählen](docs/login.de.md#login-choose).

Die Demo startet die echte Seite mit erfundenen Daten und braucht kein dcm4chee, keine Anmeldung und keine root-Rechte.

```bash
git clone https://github.com/pbaetz99/dcm4chee-admin-panel.git
cd dcm4chee-admin-panel
python3 demo/serve.py
```

`http://127.0.0.1:8000/admin/` öffnen. Die Optionen der Demo stehen in der Anleitung ([Weg A](docs/install.de.md#demo)).

Varianten der echten Installation:

- [Nur das Admin-Panel](docs/install.de.md#variant-adminonly), ohne den OHIF-Viewer.
- [Hinter dem eigenen TLS-Proxy](docs/install.de.md#variant-proxied) wie Traefik, Caddy, Apache oder Cloudflare Tunnel.
- [nginx auf dem Host](docs/install.de.md#nginx-on-host) statt in einem Container.
- [Ein erster Blick durch einen SSH-Tunnel](docs/install.de.md#variant-tryit), ohne TLS.

Die Basisinstallation ändert das dcm4chee-Projekt nicht und startet es nicht neu. Die beiden optionalen Module, der Platten-Assistent und die Firewall, ändern seine Compose-Datei und erzeugen den Container `arc` neu. Dafür ein Wartungsfenster einplanen ([optionale Module](docs/install.de.md#optional-modules)).

<a id="how-it-works"></a>
## So funktioniert es

```text
Browser --https--> nginx, die Eingangstür (Container ohif)
                     |
                     +-- Anmeldeprüfung --> oauth2-proxy (Container ohif-auth) --> Entra ID oder anderer OIDC-Anbieter
                     |                      (oder Benutzerdateien von nginx: Login basic, oder Netzlisten: Login none)
                     +-- /                der OHIF-Viewer (optional)
                     +-- /admin/          statische Seite (web/admin, nur lesend eingehängt)
                     +-- /admin/daten/    status.json, geschrieben von dashboard-status.py (Cron, alle 5 Minuten)
                     +-- /admin/dienst/   Unix-Socket --> verwaltung-dienst.py (root, auf dem Host)
                     |                                      +-- pacs-storage.sh  Platten, LDAP
                     |                                      +-- firewall.py      iptables
                     |                                      +-- pacsdb.py        Protokoll (SQLCipher)
                     +-- /dcm4chee-arc/   nur erlaubte REST-Aufrufe --> dcm4chee-arc
                     +-- Zugriffsprotokoll als Syslog --> Unix-Socket --> verwaltung-dienst.py --> Protokoll
```

- Die Seite besteht aus reinem HTML, JavaScript und CSS, ohne Build-Schritt, ohne CDN und ohne externe Schriften. nginx liefert sie direkt aus dem Verzeichnis des Repositorys aus.
- Eingangstür: nginx prüft jede Anfrage ([Glossar](docs/glossary.de.md#front-door)). Drei Teile sind austauschbar: die Anmeldung (`oauth2-proxy`, `basic` oder `none`), der Viewer (`ohif` oder `none`) und der Listener (`tls`, `plain` oder `behind-proxy`). Die nginx-Dateien liegen in `deploy/nginx`. Fünf Compose-Dateien in `deploy/compose` kombinieren sie zu Rezepten ([Rezepte](deploy/nginx/README.de.md#recipes), [Tabelle](docs/reference.de.md#nginx-recipes)).
- Zwei Stufen: Jedes Konto, das die Anmeldung durchlässt, darf den Viewer öffnen und lesen. Ein Admin darf zusätzlich `/admin/` öffnen und Daten ändern.
- REST-Schnittstelle von dcm4chee: nginx lässt nur die Aufrufe durch, die der Viewer und die Seite nutzen. Alles andere unter `/dcm4chee-arc/` beantwortet nginx mit 404. Änderungen brauchen die Stufe Admin und den Header `X-PACS-Admin`, den die Seite mit einer lesbaren Beschreibung für das Protokoll setzt. nginx fügt Sperren hinzu, siehe [Sicherheitshinweise](#security-notes).
- Hilfsdienst: `server/verwaltung-dienst.py` läuft als root auf dem Host (Unit `pacs-verwaltung`) und lauscht nur auf zwei Unix-Sockets. nginx reicht das Konto in `X-Auth-User` und die Adresse des Clients in `X-Real-IP` weiter. Der Dienst startet `pacs-storage.sh` für Platten und `firewall.py` für iptables und liest das Protokoll ([Glossar](docs/glossary.de.md#helper-service)).
- Protokoll: nginx schickt pro Anfrage eine JSON-Zeile per Syslog an den zweiten Unix-Socket. Der Dienst sammelt die Zeilen und schreibt sie alle 2 Sekunden in die SQLCipher-Datenbank. Die Syslog-Tags heißen `zugriffe` (jede Anfrage), `ereignisse` (Studien- und Patientensuchen, geöffnete Studien) und `admin` (Änderungen, mit Beschreibung und neuen Werten).
- `server/dashboard-status.py` läuft alle 5 Minuten per cron und schreibt `status.json`: Platten, leere Platten, Container. Die Datei enthält keine Patientendaten.
- `server/firewall.py` hält seine Regeln in der Kette `PACS-SPERRE`, zu der `DOCKER-USER` für die eingehende Schnittstelle springt. `pacs-firewall.service` wendet sie nach jedem Start von Docker an.
- Optional: Die Datei `optional/dcm4chee-ui.conf` liefert die Oberfläche von dcm4chee über dieselbe Anmeldung aus, ohne Keycloak, nur für die Stufe Admin. Änderungen, die dort gemacht werden, landen im Protokoll. Die Datei löschen, um den Abschnitt abzuschalten.

<a id="requirements"></a>
## Voraussetzungen

- dcm4chee-arc-light unter Docker Compose, ohne Keycloak laufend. Die `-secure`-Images werden nicht unterstützt. nginx übernimmt die Zugriffskontrolle.
- Ein Linux-Host mit systemd und root-Zugriff. Getestet wurden Debian 12 und Debian 13. Ubuntu nutzt dieselben Pakete und wurde nicht getestet.
- Python 3.7 oder neuer unter `/usr/bin/python3`. Die Serverprogramme nutzen nur die Standardbibliothek.
- Docker mit dem Compose-Plugin (`docker compose`), iptables und cron.
- nginx 1.25.1 oder neuer. Die Docker-Images bringen es mit. Für nginx auf dem Host siehe [nginx auf dem Host](deploy/nginx/README.de.md#host-nginx).
- Die SQLCipher-Bibliothek für das Protokoll: `libsqlcipher1` auf Debian 13, `libsqlcipher0` auf Debian 12 und älter.
- Für den Platten-Assistenten: `util-linux`, `e2fsprogs` und `curl`. Der LDAP-Container braucht sein root-Passwort in der eigenen Umgebung (`LDAP_ROOTPASS` oder `LDAP_ROOTPASS_FILE`). Der arc-Container braucht `STORAGE_BASE` mit `:rslave` eingehängt ([Platten-Assistent](docs/modules.de.md#disk-assistant)).
- Für Weg B: ein OpenID-Connect-Anbieter und der Container oauth2-proxy, den die Compose-Datei einrichtet.

Die [Paketliste](docs/reference.de.md#packages) nennt jedes Werkzeug und jedes Paket. `deploy/tools/preflight.sh` prüft einen Host vor dem Start. Das Skript liest nur und ändert nichts.

<a id="tested"></a>
## Was getestet wurde und wie

Die nginx-Rezepte, die Werkzeuge und der geänderte Servercode wurden in lokalen Docker-Containern auf einem PC getestet, mit Attrappen für die Teile, die nicht zur Hand waren. Kein installierter PACS-Server, kein echter Identitätsanbieter und kein echtes dcm4chee-arc nahmen teil.

Getestet:

- **nginx-Rezepte.** Ein Labor aus Wegwerf-Containern ließ den echten Hilfsdienst laufen, dazu eine Attrappe für dcm4chee-arc, die zurückgibt, was bei ihr ankommt, eine Attrappe für oauth2-proxy, den nginx unter Test und einen Client mit etwa 370 Prüfungen pro Rezept. Die Prüfungen decken jede Sperre ab, die Referer-Regel, das Entfernen von Headern und das Protokoll von der Anfrage bis zur Datenbank. `nginx -t` lief für alle 18 Kombinationen aus Anmeldung, Viewer und Listener, mit und ohne die Datei für die dcm4chee-Oberfläche. nginx aus den Paketen von Debian 13 (1.26) lief mit dem echten Hilfsdienst. Auf Debian 12 (nginx 1.22) liefen nur `nginx -t`, eine HTTP/2-Anfrage und die Weiterleitung. Einzelheiten: [Testlabor](deploy/nginx/README.de.md#lab).
- **Werkzeuge.** `preflight.sh`, `pacs-adduser.sh` und `set-aet.sh` liefen in Containern mit Debian 12 und Debian 13, mit Attrappen für `docker`, `systemctl` und andere Befehle. `preflight.sh` lief auch gegen eine echte Docker-Engine (Docker Desktop unter Windows).
- **Protokoll.** `pacsdb.py` öffnete Datenbanken mit `libsqlcipher0` 3.4.1 (Debian 12) und `libsqlcipher1` 4.6.1 (Debian 13), geschrieben von der einen oder der anderen Bibliothek.
- **Python.** Die Serverprogramme liefen mit Python 3.7 (in einem Debian-10-Chroot), 3.11 und 3.12.
- **Seite.** Die Seite und die Demo liefen in einem Browser auf Basis von Chromium.
- **Frühere Version.** Die erste Version der Seite, des Hilfsdienstes, des Platten-Assistenten und der Firewall lief im Alltag mit dcm4chee-arc-light 5.35.1, Docker 26 und iptables-nft auf Debian 10, im nginx des OHIF-Images hinter oauth2-proxy und Microsoft Entra ID. Die nginx-Rezepte dieser Version sind neu.

Nicht getestet:

- Ein echter Identitätsanbieter wie Microsoft Entra ID und ein echter oauth2-proxy. Die Attrappe antwortet wie oauth2-proxy (202, 401, 403 und die Header `X-Auth-Request-*`). Kein echter Anmeldeablauf im Browser lief: Anmelden, Abmelden, Weiterleitungen und Cookies.
- Ein echtes dcm4chee-arc mit WildFly. Die Attrappe gibt nur zurück, was bei ihr ankommt, und die Muster der Studien-Sperren liefen gegen sie. Lesende Suchen an einem echten arc (Version 5.35) zeigten, dass eine zweite `StudyInstanceUID` und eine Kommaliste mehrere Studien auswählen; deshalb lassen die Sperren genau eine Form zu. Der Aufruf zum Ändern selbst lief damit nicht. Nicht gegen ein echtes arc bestätigt: dass der Schutz gegen `;`, `%5c` und einen rohen Backslash stoppt, was er stoppen soll, und dass der Abschnitt für die dcm4chee-Oberfläche ohne das Cookie funktioniert.
- Das OHIF-Image. Die Rezepte mit dem Viewer `ohif` liefen auf dem einfachen `nginx`-Image. Die Schlüsselregel für das OHIF-Image (nginx-Master als uid 101) wurde mit einem Master getestet, der als uid 101 startete.
- Echtes systemd. Die Units wurden mit `systemd-analyze verify` geprüft und nicht gestartet.
- Der Platten-Assistent mit echten Platten und einem echten LDAP nach den Änderungen dieser Version. Nur der Plan und die frühen Prüfungen liefen, mit Attrappen.
- Ubuntu, Firefox, Safari, Docker auf einem Linux-Host (das Labor lief auf Docker Desktop) und ein echter Traefik, Caddy, Apache oder Cloudflare Tunnel vor nginx (ein zweiter nginx spielte den Proxy).

<a id="limitations"></a>
## Einschränkungen

- Die Seite und die Serverprogramme sprechen nur Deutsch. Die Anleitungen und die Werkzeuge `preflight.sh`, `pacs-adduser.sh` und `set-aet.sh` sprechen Englisch und Deutsch.
- Ein Archiv-AE-Titel pro Installation (Vorgabe `DCM4CHEE`). [set-aet.sh](docs/reference.de.md#command-set-aet) benennt ihn um.
- dcm4chee muss ohne Keycloak laufen. Die `-secure`-Images werden nicht unterstützt. Traefik, Caddy und Cloudflare können nginx nicht ersetzen. Vor nginx können sie aber stehen ([Rezept hinter dem eigenen TLS-Proxy](docs/install.de.md#variant-proxied)).
- Die Firewall erfasst nur Ports, die Docker veröffentlicht, für IPv4-Verkehr, der über eine Schnittstelle hereinkommt (`FW_INTERFACE`, Vorgabe: die Schnittstelle der Standardroute). SSH, andere Dienste des Hosts (nginx auf dem Host eingeschlossen), Verkehr des Hosts selbst und Verkehr aus Docker-Netzen erfasst sie nicht.
- Mit den Voreinstellungen von Docker wird ein veröffentlichter Port auch an `[::]` gebunden. IPv6-Verbindungen erreichen den Container dann über `docker-proxy`, an der Firewall vorbei, was immer der Reiter Firewall für diesen Port anzeigt. Der Reiter kennzeichnet solche Ports mit `IPv6 nicht gefiltert`. Die Ports nur auf IPv4 veröffentlichen oder IPv6 auf dem Host abschalten ([Firewall-Modul](docs/modules.de.md#firewall)).
- Die Client-PC-Erkennung arbeitet nur mit einem Muster für DNS-Namen. PCs ohne vorhersagbaren Namen erscheinen nur durch ihre Verbindungen.
- Die Listen der DICOM- und HL7-Absender stammen aus dem `server.log` von dcm4chee, für die Ports in `FW_DICOM_PORTS` und `FW_HL7_PORTS` (Vorgabe 11112, 2762, 2575 und 12575). Der Dienst übersetzt sie über `docker ps` auf den Port des Containers.
- Der Platten-Assistent formatiert ganze Platten als ext4, nie Partitionen. Die Seite bietet nur die leeren Platten an, die `pacs-storage.sh kandidaten` auflistet, und der Hilfsdienst akzeptiert nur die Gerätenamen `/dev/sd*`, `/dev/vd*`, `/dev/xvd*` und `/dev/nvme*n*`. Speicher-ID, Dateisystem-Label und Einhängeverzeichnis tragen einen gemeinsamen Namen (`STORAGE_PREFIX` plus Nummer, Vorgabe `PACS-Data`). Speicher mit anderen Namen erscheinen nicht in der Übersicht.
- Das Protokoll wird nie bereinigt. Platz und Aufbewahrung selbst planen. Zeilen gehen verloren, während der Hilfsdienst neu startet. Eine Anfrage, die nginx abweist, hat kein geprüftes Konto ([Protokoll](docs/reference.de.md#audit-account)).
- Die Anmeldung `basic` setzt keine Grenze für Fehlversuche. Die Anmeldung `none` kennt nur die Netzwerkadresse eines PCs. Keine von beiden bietet einen zweiten Faktor. Beim Single Sign-on liefert ihn der Identitätsanbieter.

<a id="security-notes"></a>
## Sicherheitshinweise

- Der Hilfsdienst läuft als root. Wer sich mit seinen Sockets verbinden kann, kann alles tun, was die Seite tun kann. Die Sockets gehören `PACS_SOCKET_UID` (Vorgabe 101) und haben den Modus 0600. Dieser Besitzer und dieser Modus sind die einzige Autorisierung, kein Header. Das Socket-Verzeichnis nur in den nginx-Container einbinden. Kein Konto auf dem Host darf diese uid haben: `getent passwd 101` darf nichts ausgeben, und `preflight.sh` prüft es ([Hilfsdienst](docs/install.de.md#helper-service)).
- nginx setzt `X-Auth-User` (das Konto) und `X-Real-IP` (die Adresse des Clients) aus der geprüften Anmeldung und der Verbindung und verwirft die Werte, die ein Browser mitschickt. Der Hilfsdienst nutzt sie für das Protokoll und für die Aussperr-Prüfung der Firewall, nie um zu entscheiden, wer was darf. `Authorization` und `Cookie` erreichen weder arc noch den Hilfsdienst.
- Eine Änderung braucht den Header `X-PACS-Admin`. Ohne ihn beantwortet nginx jeden POST an `/admin/dienst/`, die beiden GET-Aufrufe mit Nebenwirkung (`platten` und `firewall?neu=1`) und jeden ändernden dcm4chee-Aufruf mit 403. nginx entfernt den Header, bevor es eine Anfrage weitergibt. `/admin/dienst/` akzeptiert nur GET und POST. Die aufgelisteten dcm4chee-Locations lehnen `OPTIONS` ab, und nginx sendet keine CORS-Header. Eine Seite einer anderen Website kann ohne CORS-Preflight keinen eigenen Header setzen und deshalb keine Änderung auslösen.
- nginx lässt nur die dcm4chee-Aufrufe durch, die der Viewer und die Seite nutzen. Änderungen brauchen die Stufe Admin, und nginx fügt diese Sperren hinzu:
  - Studie ändern nur mit genau der Abfrage, die die Admin-Seite sendet: `reasonForModification=` und eine `StudyInstanceUID` aus Ziffern und Punkten (ohne UID ändert dcm4chee alle Studien)
  - zu einem anderen Patienten verschieben nur mit `PatientID`, wahlweise `IssuerOfPatientID`, und `updatePolicy=PRESERVE` (sonst überschreibt dcm4chee den Zielpatienten)
  - Patient ändern nie mit `merge` und nie mit einem Prozentzeichen in einem Parameternamen
  - endgültig löschen nur über den AE `IOCM_QUALITY`, bei dem dcm4chee nur abgelehnte Studien löscht
- Die beiden Studien-Sperren nennen, was erlaubt ist, und weisen alles andere ab, weil eine Liste des Verbotenen nie vollständig wäre: Eine zweite `StudyInstanceUID` oder eine Kommaliste in einer kann mehrere Studien auswählen. Die Sperren antworten vor der Anmeldeprüfung, eine falsche Abfrage bekommt also auch ohne Anmeldung 403.
- nginx gibt einen Pfad unverändert weiter, und ein Anwendungsserver kann `;`, `%5c` und einen rohen Backslash in einem Pfad anders behandeln. Deshalb beantwortet nginx einen solchen Pfad mit 400, auch vor der Anmeldeprüfung, und er erreicht arc nie. Das wurde nicht gegen ein echtes arc bestätigt.
- Der optionale Abschnitt für die dcm4chee-Oberfläche schickt jede Anfrage unter `/dcm4chee-arc/`, deren `Referer` die Oberfläche dieses Hosts ist, an die volle dcm4chee-API. Der `Referer` muss für die Listener `tls` und `behind-proxy` `https://HOST/dcm4chee-arc/ui2/` lauten (ohne Port, weil Browser 443 weglassen) und für den Listener `plain` `http://HOST:8080/dcm4chee-arc/ui2/`. Dort gelten die Sperren und die Prüfung auf `X-PACS-Admin` nicht. Die Anmeldung und die Stufe Admin gelten. Eine Anfrage mit einem `Referer` eines anderen Hosts, mit einem Port, den die Regel nicht nennt, mit dem falschen Schema oder ganz ohne `Referer` bleibt auf den gesperrten Locations. Browser lassen eine Seite nur einen `Referer` des eigenen Ursprungs senden. Ein anderer Dienst unter demselben Hostnamen, zum Beispiel Portainer auf Port 9443, ist ein anderer Ursprung, und sein `Referer` trägt den Port. Ein angemeldeter Admin kann mit `curl` jeden `Referer` setzen und erhält denselben Zugriff wie über die dcm4chee-Oberfläche. Ohne die Datei erreichen nur die aufgelisteten Aufrufe dcm4chee, und jeder Aufruf der dcm4chee-Oberfläche beantwortet nginx mit 404.
- dcm4chee läuft ohne eigene Anmeldung. Wer arc direkt auf Port 8080 oder 8443 erreicht, kann alles lesen und ändern. Diese Ports nur auf `127.0.0.1` veröffentlichen (nginx erreicht arc über das Docker-Netz), von außen gesperrt halten (der eingebaute Regelsatz des Firewall-Moduls sperrt beide Ports) und aus anderen Netzen heraushalten. Ein Port, den Docker auch an `[::]` bindet, ist über IPv6 offen, siehe [Einschränkungen](#limitations).
- Die Protokoll-Datenbank ist mit SQLCipher verschlüsselt. Der Schlüssel besteht aus 64 hexadezimalen Zeichen in der Datei, die `PROTOKOLL_KEY` nennt (Vorgabe `/etc/pacs-protokoll.key`). Die Datei nur für root lesbar halten (Modus 0600) und eine Offline-Kopie aufbewahren. Ohne den Schlüssel kann niemand das Protokoll lesen. Das Protokoll enthält Patienten-IDs und Namen aus den URLs von Suchen und ist deshalb wie Patientendaten zu behandeln. Aus demselben Grund schreibt nginx kein Zugriffslog nach `docker logs`.
- Der Modus des TLS-Schlüssels hängt vom Image ab. Viewer `ohif` (der nginx-Master läuft als uid 101): `chown root:101 server.key` und `chmod 640 server.key`. Das einfache `nginx`-Image und nginx auf dem Host (der Master läuft als root): Besitzer `root:root` und Modus 600. Ein Konto auf dem Host mit uid 101 kann den Schlüssel der ersten Art lesen ([TLS-Zertifikat](docs/install.de.md#tls-certificate)).
- Zwischen Browser und PACS bei jeder Anmeldung https nutzen. Die Anmeldung `basic` schickt das Passwort mit jeder Anfrage.
- Die oauth2-Compose-Datei setzt `--trusted-proxy-ip` von oauth2-proxy auf `172.16.0.0/12`. Den Wert auf das Subnetz des eigenen Docker-Netzes verengen (Marker `CHANGE-ME`). Sitzungen enden nach 12 Stunden (`--cookie-expire`) und werden nicht erneuert.
- Die Anmeldung `none` vertraut der Netzwerkadresse. Beide Listen (Viewer-PCs und Admin-PCs) klein halten.
- Die Aussperr-Prüfung beim Speichern der Firewall erfasst nur den speichernden PC und den ersten Web-Port (https). Adressen in den Docker-Netzen überspringt sie: Über IPv6 sieht nginx das Docker-Gateway, nicht den PC.

<a id="docs-map"></a>
## Dokumentationsübersicht

| Dokument | Lesen, um |
|---|---|
| [docs/install.de.md](docs/install.de.md) | das Admin-Panel Schritt für Schritt zu installieren: Demo, echte Installation, Varianten, Aktualisieren, Entfernen |
| [docs/login.de.md](docs/login.de.md) | eine Anmeldung zu wählen und einzurichten: Entra ID und andere OpenID-Connect-Anbieter, Basic-Authentifizierung, Netzlisten |
| [docs/modules.de.md](docs/modules.de.md) | die optionalen Module zu nutzen: Platten-Assistent, Firewall und Abschnitt für die dcm4chee-Oberfläche |
| [docs/reference.de.md](docs/reference.de.md) | Einstellungen, Werkzeuge und Pakete, Dateien, Ports und Sockets, die nginx-Rezepte, den Vertrag der Eingangstür und das Protokoll nachzuschlagen |
| [docs/troubleshooting.de.md](docs/troubleshooting.de.md) | die Ursache zu finden, wenn etwas scheitert |
| [docs/glossary.de.md](docs/glossary.de.md) | einen Begriff nachzuschlagen |
| [deploy/nginx/README.de.md](deploy/nginx/README.de.md) | die nginx-Dateien für ein Rezept zu bauen und über das Testlabor zu lesen |

<a id="license"></a>
## Lizenz

MIT, siehe [LICENSE](LICENSE).
