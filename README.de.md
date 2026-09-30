# dcm4chee-admin-panel

[English](README.md) | Deutsch

Eine Verwaltungsseite für ein dcm4chee-arc-light-PACS unter Docker Compose. Es ist eine einzige statische Seite. Sie
kommt aus demselben nginx, der den OHIF-Viewer ausliefert, und liegt hinter oauth2-proxy. Ein kleiner Hilfsdienst auf
dem Host erledigt, was der Browser nicht kann: Platten ins Archiv einbinden, iptables-Regeln für die Docker-Ports
setzen und ein verschlüsseltes Protokoll führen.

Die Oberfläche ist auf Deutsch.

## Bilder

![Übersicht: Platten, Schreibliste, Container, Firewall](docs/screenshots/overview.png)

![Firewall: Ports, Modi, neu erkannte Quellen](docs/screenshots/firewall.png)

![Protokoll: Zugriffe und Änderungen mit Filtern](docs/screenshots/protokoll.png)

![Studien: suchen und bearbeiten](docs/screenshots/studien.png)

## Was die Seite kann

### Übersicht

- Die Platten des Archivs mit Füllstand und freiem Platz. Dazu, welche Platte gerade die neuen Bilder bekommt und
  welche danach dran sind. Die Reihenfolge ist die Schreibliste der Archiv-AE (`dcmObjectStorageID` und
  `dcmMetadataStorageID`). Bleiben bis zur Schwelle weniger als `STORAGE_WARN_GB` (Vorgabe 300 GB), mahnt die Seite
  eine neue Platte an.
- Schreibliste:
  - „In Schreibliste aufnehmen“ hängt eine Platte hinten an die Liste.
  - „Aus Schreibliste nehmen“ nimmt eine Platte aus der Liste. Ihre Bilder bleiben lesbar. Bei der letzten Platte,
    die neue Bilder annimmt, zeigt die Seite den Knopf nicht. `pacs-storage.sh` verweigert außerdem, den letzten
    Speicher ohne Markierung „voll“ herauszunehmen.
  - „Markierung entfernen“ löscht die Markierung „voll“ (`dcmStorageThresholdExceeded`), die dcm4chee an der
    Schwelle setzt.
  - Aufnehmen und Markierung entfernen gehen nur mit mindestens `STORAGE_FREE_GB` frei (Vorgabe 50 GB). Die Seite
    zeigt die beiden Knöpfe nur bei Platten mit so viel freiem Platz (`frei_gb` in `status.json`), `pacs-storage.sh`
    prüft noch einmal.
- Neue Festplatte: dem Server (oder der VM) eine leere Platte geben. Sie erscheint innerhalb von 5 Minuten, mit
  „Jetzt suchen“ sofort. Nach der Bestätigung formatiert `pacs-storage.sh` sie mit ext4, hängt sie unter
  `STORAGE_BASE` ein, trägt sie in `/etc/fstab` ein, legt den Speicher im LDAP als Kopie des aktuellen an und hängt
  ihn hinten an die Schreibliste. Die Seite zeigt jeden Schritt und die Ausgabe des Skripts.
- Die Container des dcm4chee-Compose-Projekts, laufend oder gestoppt.
- Kachel Firewall: ein oder aus, Standard für Ports ohne Regel, Zahl der neu erkannten Quellen.
- Die letzten 15 Änderungen über die Seite, mit Konto.

### Studien

- Suche nach Patienten-Nr., Name, Accession-Nr. und Zeitraum. Neueste zuerst, höchstens 200 Treffer.
- Beschreibung, Accession-Nr., Studiendatum und Zuweiser ändern. Die alten Werte hält dcm4chee in der Original
  Attributes Sequence fest.
- Studie zu einem anderen Patienten verschieben. Name und Geburtsdatum des Zielpatienten bleiben unverändert.
- Studie ablehnen (`113001^DCM`). In der Ansicht der abgelehnten Studien: zurückholen oder endgültig löschen. Vor dem
  Löschen muss man die Accession-Nr. (oder die Patienten-Nr.) eintippen.

### Patienten

- Suche nach Patienten-Nr. und Name, höchstens 100 Treffer.
- Name, Geburtsdatum und Geschlecht ändern. Die Seite schickt den ganzen Datensatz zurück, Adresse und andere Angaben
  bleiben erhalten.
- Zwei Patienteneinträge zusammenführen.

### Firewall

- iptables-Regeln für jeden Port, den Docker veröffentlicht. Je Port ein Modus: offen (alle), Probelauf (alle kommen
  durch, wer nicht eingetragen ist, wird protokolliert) oder gesperrt (nur eingetragene IPv4-Adressen und Netze).
- Ein Standard für Ports ohne eigene Regel. Er gilt auch für Ports, die später dazukommen.
- Ports, die Docker auch über IPv6 veröffentlicht, bekommen die Marke „IPv6 nicht gefiltert“, siehe [Grenzen](#grenzen).
- DICOM-, HL7- und Viewer-Ports sind Einstellungen (`FW_DICOM_PORTS`, `FW_HL7_PORTS`, `FW_WEB_PORTS`), für Standorte
  mit DICOM auf 104 oder dem Viewer auf einem anderen Port.
- „Neu erkannt“ listet Quellen, die gesehen wurden, für ihren Port aber nicht eingetragen sind, mit „Erlauben“ und
  „Ausblenden“. Die Quellen kommen aus dem `server.log` von dcm4chee (DICOM- und HL7-Absender), aus dem Kernel-Log
  (von den Regeln protokollierte Verbindungen der letzten 7 Tage) und aus der Suche nach Client-PCs.
- Die Suche nach Client-PCs fragt den DNS nach Namen aus Mustern wie `WS{0001..0400}` (`FW_CLIENT_NAMES`) und schlägt
  je Netz ein /24 für DICOM vor. Ohne Muster gibt es keine Suche und die Karte ist ausgeblendet.
- Zähler der neuen Verbindungen je Port und Quelle.
- Änderungen gelten nach „Speichern“. Der Dienst lehnt Regeln ab, die den speichernden PC vom https-Port (443)
  aussperren würden. Er sichert die vorige Fassung in `PACS_DIR/firewall/` und kehrt zu ihr zurück, wenn das Anwenden
  scheitert.

### Protokoll

- Wer nach Studien oder Patienten gesucht und wer welche Studie oder welchen Bericht geöffnet hat (im Viewer, auf
  dieser Seite oder im Abschnitt für die dcm4chee-Oberfläche), dazu jede Änderung über die Seite, jeweils mit Konto,
  PC und Zeit.
- Filter: Zeitraum, Patienten-ID, Patientenname, Konto, PC, Art, Freitext. Dasselbe Konto mit derselben Studie oder
  Suche innerhalb von 30 Minuten ist ein Eintrag.
- Export als CSV für Excel (Semikolon, UTF-8 mit BOM).
- Verschlüsselt mit SQLCipher auf dem Server gespeichert. Jede einzelne Anfrage steht ebenfalls darin (Quelle
  `zugriffe`) und lässt sich mit `server/pacsdb.py` lesen.

Im Kopf stehen Verweise auf die dcm4chee-Oberfläche und den Viewer. Titel, AE-Titel, Verweise, ein optionales Logo
und das Format für Zahlen und Zeitpunkte (`locale`) kommen aus `web/admin/config.js`.

## Aufbau

```
Browser --https--> nginx im OHIF-Container --auth_request--> oauth2-proxy --> Entra ID oder anderer OIDC-Anbieter
                     |
                     +-- /admin/          statische Seite (web/admin, nur lesend eingebunden)
                     +-- /admin/daten/    status.json von dashboard-status.py (cron, alle 5 Minuten)
                     +-- /admin/dienst/   Unix-Socket --> verwaltung-dienst.py (root, auf dem Host)
                     |                                      +-- pacs-storage.sh  Platten, LDAP
                     |                                      +-- firewall.py      iptables
                     |                                      +-- pacsdb.py        Protokoll (SQLCipher)
                     +-- /dcm4chee-arc/   freigegebene REST-Aufrufe --> dcm4chee-arc
                     +-- access_log syslog --> Unix-Socket --> verwaltung-dienst.py --> Protokoll
```

- Die Seite ist reines HTML, JavaScript und CSS. Kein Build, kein CDN, keine fremden Schriften. nginx liefert sie
  direkt aus dem Verzeichnis des Repos aus.
- Anmeldung: jede Anfrage geht per `auth_request` an oauth2-proxy. Für den Viewer reicht eine der erlaubten Gruppen.
  `/admin/` und jeder ändernde dcm4chee-Aufruf verlangen die Admin-Gruppe.
- dcm4chee-REST: nginx lässt nur die Aufrufe durch, die Viewer und Seite brauchen. Alles andere unter
  `/dcm4chee-arc/` bekommt 404. Änderungen brauchen die Admin-Gruppe und die Kopfzeile `X-PACS-Admin`, in die die
  Seite eine lesbare Beschreibung fürs Protokoll schreibt. Dazu sperrt nginx:
  - Studie ändern nur mit `StudyInstanceUID` (ohne ändert dcm4chee alle Studien)
  - Studie verschieben nur mit `updatePolicy=PRESERVE` (sonst überschreibt dcm4chee den Zielpatienten)
  - Patient ändern nie mit `merge`
  - endgültig löschen nur über die AE `IOCM_QUALITY`, dort löscht dcm4chee nur abgelehnte Studien
- Hilfsdienst: `server/verwaltung-dienst.py` läuft als root auf dem Host und hört nur auf einem Unix-Socket. nginx
  gibt das Konto in `X-Auth-User` und die IP des PCs in `X-Real-IP` mit. Der Dienst ruft `pacs-storage.sh` für die
  Platten und `firewall.py` für iptables auf und liest das Protokoll.
- Protokoll: nginx schickt je Anfrage eine JSON-Zeile per syslog an einen zweiten Unix-Socket. Der Dienst sammelt die
  Zeilen und schreibt sie alle 2 Sekunden in die SQLCipher-Datenbank. Quellen: `zugriffe` (jede Anfrage mit Konto),
  `ereignisse` (Studien- und Patientensuchen, geöffnete Studien), `admin` (Änderungen mit Beschreibung und neuen
  Werten).
- `server/dashboard-status.py` läuft alle 5 Minuten per cron und schreibt `status.json`: Platten, leere Platten,
  Container. Keine Patientendaten.
- `server/firewall.py` legt seine Regeln in die Kette `PACS-SPERRE`, die `DOCKER-USER` für die Schnittstelle nach
  außen anspringt. `pacs-firewall.service` setzt sie nach jedem Start von Docker.
- Optional: ein Abschnitt im nginx-Beispiel liefert die dcm4chee-Oberfläche über dieselbe Anmeldung aus, ohne
  Keycloak und nur für die Admin-Gruppe. Änderungen dort landen im Protokoll.

## Voraussetzungen

- dcm4chee-arc-light unter Docker Compose, ohne Keycloak (Image `dcm4chee-arc-psql`, nicht die `-secure`-Varianten).
  Die Zugangskontrolle machen nginx und oauth2-proxy.
- Linux mit systemd, Python 3.7 oder neuer (nur Standardbibliothek), Docker mit Compose-Plugin, iptables, cron.
- `libsqlcipher0` (Paket in Debian und Ubuntu) für das Protokoll.
- Für den Platten-Assistenten: util-linux, e2fsprogs, curl. Der LDAP-Container braucht sein Root-Passwort in der
  eigenen Umgebung (`LDAP_ROOTPASS` oder `LDAP_ROOTPASS_FILE`). Der arc-Container braucht `STORAGE_BASE` als Volume
  mit `:rslave`.
- Das OHIF-Image (nginx 1.25.1 oder neuer) und oauth2-proxy. Das Compose-Beispiel richtet beide ein.
- Ein OIDC-Anbieter mit Claim `groups`. Erprobt mit Microsoft Entra ID.

## Schnellstart

[docs/install.de.md](docs/install.de.md) beschreibt jeden Schritt. Kurz:

1. Repo nach `/opt/pacs-admin` klonen, `deploy/pacs-admin.env.example` nach `/etc/default/pacs-admin` kopieren.
2. `libsqlcipher0` installieren und den Schlüssel für das Protokoll erzeugen.
3. `pacs-verwaltung.service` und den Cron-Job einrichten.
4. App in Entra ID registrieren, Compose- und nginx-Beispiel ausfüllen, OHIF-Container starten.
5. Firewall im Probelauf starten, die REST- und Verwaltungsports von dcm4chee gesperrt, und später im Reiter Firewall
   schärfer stellen.

## Demo

```
python demo/serve.py
```

Dann http://localhost:8000/admin/ öffnen. Die Demo liefert `web/` aus und lädt `demo/mock.js`. Das beantwortet jede
Anfrage der Seite mit erfundenen Daten im Browser. dcm4chee, nginx und der Hilfsdienst sind nicht nötig. Änderungen
gelten bis zum Neuladen.

- `python demo/serve.py 8080` nimmt einen anderen Port.
- `http://localhost:8000/admin/?demo=platte` zeigt eine leere Platte, bereit zum Einrichten.
- `http://localhost:8000/admin/?demo=offen#firewall` klappt im Reiter Firewall alle Karten auf.

## Grenzen

- Die Oberfläche gibt es nur auf Deutsch. Die Doku gibt es auf Englisch und Deutsch.
- Erprobt mit dcm4chee-arc-light 5.35.1, Debian 10, Docker 26 und iptables-nft.
- Die Firewall gilt nur für Ports, die Docker veröffentlicht, und nur für IPv4-Verkehr, der über eine Schnittstelle
  hereinkommt. SSH, andere Dienste des Hosts, Zugriffe vom Host selbst und aus Docker-Netzen erfasst sie nicht.
- Docker bindet einen veröffentlichten Port ohne weitere Angabe auch an `[::]`. IPv6-Verbindungen erreichen den
  Container dann über `docker-proxy` an der Firewall vorbei, egal was der Reiter Firewall für den Port anzeigt. Der
  Reiter markiert solche Ports mit „IPv6 nicht gefiltert“. Ports nur über IPv4 veröffentlichen oder IPv6 auf dem Host
  abschalten ([Installation, Schritt 10](docs/install.de.md#10-firewall-erster-start-im-probelauf)).
- Client-PCs findet die Suche nur über Namensmuster im DNS. PCs, deren Namen keinem Muster folgen, tauchen
  erst über ihre Verbindungen auf.
- Die Listen der DICOM- und HL7-Absender lesen das `server.log` von dcm4chee für die Ports aus `FW_DICOM_PORTS` und
  `FW_HL7_PORTS` (Vorgabe 11112, 2762, 2575 und 12575), über `docker ps` in den Port im Container umgesetzt.
- Der Platten-Assistent formatiert ganze Platten mit ext4, nie Partitionen. Die Seite bietet nur die leeren Platten
  an, die `pacs-storage.sh kandidaten` listet, und der Hilfsdienst nimmt nur die Gerätenamen `/dev/sd*`, `/dev/vd*`,
  `/dev/xvd*` und `/dev/nvme*n*` an. Speicher-ID, Label und Mountpunkt tragen denselben Namen (`STORAGE_PREFIX` plus
  Nummer). Anders benannte Speicher erscheinen nicht in der Übersicht.
- Eine Archiv-AE je Installation.
- Das Protokoll löscht nie etwas. Platz und Aufbewahrungsfristen muss man selbst planen.

## Sicherheit

- Der Hilfsdienst läuft als root und vertraut den Kopfzeilen `X-Auth-User` und `X-Real-IP`. Nur nginx darf seinen
  Socket erreichen. Der Dienst legt beide Sockets mit Besitzer `PACS_SOCKET_UID` und Rechten 0600 an. Das
  Socket-Verzeichnis gehört nur in den nginx-Container. Die uid ist der einzige Schutz der Sockets und des
  TLS-Schlüssels, kein Konto auf dem Host darf sie haben: `getent passwd 101` darf nichts ausgeben
  ([Installation, Schritt 6](docs/install.de.md#6-hilfsdienst)).
- nginx ersetzt `X-Auth-User` und `X-Real-IP` aus dem Browser, bevor es eine Anfrage an den Hilfsdienst gibt, und
  entfernt `X-PACS-Admin`, bevor es eine Änderung weitergibt. Eine Änderung über `/admin/dienst/` oder über die
  freigegebenen dcm4chee-Aufrufe ohne `X-PACS-Admin` bekommt 403. Fremde Seiten können diese Kopfzeile nicht setzen,
  weil nginx auf diesen Pfaden keine CORS-Vorabfrage beantwortet.
- Der optionale Abschnitt für die dcm4chee-Oberfläche schickt jede Anfrage unter `/dcm4chee-arc/`, deren `Referer` mit
  `https://<Host der Anfrage>/dcm4chee-arc/ui2/` beginnt (ohne Port, also 443), an die volle dcm4chee-Schnittstelle.
  Dort gelten die Sperren aus [Aufbau](#aufbau) und die Prüfung auf `X-PACS-Admin` nicht, die Prüfung auf die
  Admin-Gruppe schon. Die map vergleicht den Host im `Referer` mit `$host`. Ein `Referer` mit anderem Host, mit Port,
  über http oder gar kein `Referer` führt zu den gesperrten locations. Browser lassen eine Seite nur einen `Referer`
  ihres eigenen Ursprungs (Schema, Host und Port) schicken. Ein anderer Dienst unter demselben Rechnernamen, etwa
  Portainer auf 9443, ist ein anderer Ursprung, sein `Referer` trägt den Port. Ein angemeldeter Admin kann mit curl
  jeden `Referer` setzen und hat damit denselben Zugriff wie über die dcm4chee-Oberfläche. Ohne den Abschnitt (Block
  `if ($pacs_dcm4chee_ui)` gelöscht) erreichen nur die freigegebenen Aufrufe dcm4chee.
- dcm4chee läuft ohne eigene Anmeldung. Wer arc direkt auf 8080 oder 8443 erreicht, kann alles lesen und ändern.
  Diese Ports nur an 127.0.0.1 veröffentlichen (nginx erreicht arc über das Docker-Netz), von außen gesperrt halten
  (der eingebaute Regelsatz tut das) und aus anderen Netzen heraushalten. Ein Port, den Docker auch an `[::]` bindet,
  ist über IPv6 offen, siehe [Grenzen](#grenzen).
- Die Protokoll-Datenbank ist mit dem 256-Bit-Schlüssel aus `PROTOKOLL_KEY` verschlüsselt. Die Schlüsseldatei nur
  für root lesbar halten (0600) und eine Kopie offline aufbewahren. Ohne Schlüssel ist das Protokoll verloren. Es
  enthält Patienten-IDs und Namen aus Suchadressen und ist wie Patientendaten zu behandeln.
- nginx schreibt kein Zugriffslog nach `docker logs`, weil die Adressen Patientendaten enthalten.
- `--trusted-proxy-ip` bei oauth2-proxy auf das Subnetz des Docker-Netzes eingrenzen. Sitzungen enden nach 12 Stunden
  (`--cookie-expire`) und werden nicht verlängert.
- Die Prüfung gegen Aussperren beim Speichern der Firewall gilt nur für den speichernden PC und den https-Port (den
  ersten aus `FW_WEB_PORTS`). Adressen aus den Docker-Netzen prüft sie nicht: über IPv6 sieht nginx das Docker-Gateway,
  nicht den PC.

## Lizenz

MIT, siehe [LICENSE](LICENSE).
