# Glossar

[English](glossary.md) | Deutsch

Diese Seite erklärt die Wörter, die die [Installationsanleitung](install.de.md), die [Anleitung zur Anmeldung](login.de.md) und die [Referenz](reference.de.md)
benutzen. Jeder Eintrag ist mit Absicht kurz. Wo es eine längere Erklärung gibt, verweist der Eintrag darauf.

Gruppen:
[die Teile des Systems](#terms-system) |
[Anmeldung](#terms-login) |
[Docker und Linux](#terms-linux) |
[Zertifikate](#terms-certificates) |
[DICOM und Speicher](#terms-dicom) |
[Wörter auf dem Bildschirm](#screen-labels)

<a id="terms-system"></a>
## 1. Die Teile des Systems

<a id="pacs"></a>
### PACS

PACS steht für Picture Archiving and Communication System (Bildarchivierungs- und Kommunikationssystem). Es speichert
medizinische Bilder und zeigt sie dem ärztlichen Personal. Hier ist das PACS das Archiv dcm4chee-arc. Dieses Repository setzt
dem Archiv eine Admin-Seite, eine Anmeldung und ein Protokoll vor.

<a id="arc"></a>
### arc

`arc` ist der Name des Containers, in dem dcm4chee-arc läuft, das Archiv. So heißt er in der Standard-Compose-Datei von
dcm4chee. nginx erreicht das Archiv im Docker-Netz unter diesem Namen. Heißt der eigene Container anders, `$arc` in
`site.conf` ändern.

<a id="ohif"></a>
### ohif und ohif-auth

`ohif` ist der Name des nginx-Containers in den Compose-Dateien dieses Repositorys. Er behält den Namen, auch wenn kein Viewer
installiert ist. `ohif-auth` ist der Name des Containers von [oauth2-proxy](#oauth2-proxy).

<a id="viewer"></a>
### Viewer

Der Viewer ist die Webseite, die Bilder im Browser zeigt. Dieses Repository nutzt OHIF. Der Viewer ist optional: Die
Admin-Seite funktioniert auch ohne ihn.

<a id="front-door"></a>
### Eingangstür

Die Eingangstür ist der Webserver vor der Admin-Seite, dem Hilfsdienst, dem Viewer und dcm4chee. In diesem Repository ist das
nginx, im Container `ohif`. Er prüft die Anmeldung, wendet die Sperren an, die falsche Änderungen fernhalten, und schreibt das
Protokoll. Die nginx-Dateien setzen sich aus kleinen Teilen zusammen: ein [Anmeldeverfahren](#login-method), ein Viewer-Modus
und ein [Listener](#listener).

<a id="any-account"></a>
### Jedes Konto

Jedes Konto ist jedes Konto, das die Anmeldung durchlässt. Es darf den Viewer öffnen.

<a id="admin-account"></a>
### Admin

Ein Admin ist ein Konto, das `/admin/` öffnen und Daten ändern darf. Bei der Anmeldung `oauth2-proxy` entscheidet die
Admin-Gruppe des [Identitätsanbieters](#identity-provider). Bei der Anmeldung `basic` entscheidet die Datei `admins`.

<a id="login-method"></a>
### Anmeldeverfahren

Das Anmeldeverfahren legt fest, wie Benutzer nachweisen, wer sie sind. Es gibt drei. `oauth2-proxy` meldet Benutzer bei einem
Identitätsanbieter an. `basic` prüft Benutzernamen und Passwörter in Dateien. `none` hat keine Anmeldung und lässt nur
aufgelistete Netze durch. Anleitung: [login.de.md](login.de.md).

<a id="listener"></a>
### Listener

Der Listener ist der Teil der nginx-Dateien, der festlegt, wie nginx Verbindungen annimmt. Es gibt drei. `tls` bedient HTTPS
auf Port 443 und leitet Port 80 um. `plain` bedient HTTP nur auf 127.0.0.1, für einen ersten Blick durch einen SSH-Tunnel.
`behind-proxy` bedient HTTP für einen anderen Webserver, der das TLS beendet.

<a id="helper-service"></a>
### Hilfsdienst

Der Hilfsdienst ist ein kleines Python-Programm (`server/verwaltung-dienst.py`), das als root auf dem Server läuft. Er erledigt,
was nginx nicht tun darf: die Firewall ändern, eine neue Platte einrichten und das Protokoll speichern. nginx spricht mit ihm
über zwei [Unix-Sockets](#unix-socket). Er läuft als [systemd-Unit](#systemd-unit) `pacs-verwaltung`.
Installationsschritte: [install.de.md#helper-service](install.de.md#helper-service).

<a id="audit-log"></a>
### Protokoll (audit log)

Das Protokoll hält fest, wer gesucht hat, welche Studie oder welcher Bericht geöffnet wurde und was in der Admin-Seite geändert
wurde. nginx schreibt eine Zeile pro Anfrage und schickt sie über [syslog](#syslog) an den Hilfsdienst. Der Hilfsdienst
speichert die Zeilen in einer verschlüsselten Datenbank ([SQLCipher](#sqlcipher)). Nichts wird gelöscht. Der Reiter heißt
Protokoll. Referenz: [reference.de.md#audit-log](reference.de.md#audit-log).

<a id="status-json"></a>
### status.json

`status.json` ist die Datei mit den Zahlen des Reiters Übersicht: Dienste, Platten und eine neue Platte. Das Skript
`dashboard-status.py` schreibt sie alle 5 Minuten, gestartet von [cron](#cron).

<a id="wildfly"></a>
### WildFly

WildFly ist der Java-Anwendungsserver im Container `arc`. dcm4chee-arc läuft darin. Das Firewall-Modul liest sein Log
(`server.log`), um die Absender von Bildern zu finden. Die Einstellung `ARC_LOG_DIR` nennt den Ordner.

<a id="ldap"></a>
### LDAP

LDAP ist ein Verzeichnisdienst. dcm4chee-arc hält darin seine Konfiguration: Geräte, [AE-Titel](#ae-title) und
[Speicher](#storage). Der Container `ldap` betreibt ihn. Der Platten-Assistent liest und ändert dort die
[Schreibliste](#write-list).

<a id="terms-login"></a>
## 2. Anmeldung

<a id="identity-provider"></a>
### Identitätsanbieter (identity provider)

Ein Identitätsanbieter ist ein Dienst, der die Benutzer kennt und ihre Passwörter prüft. Beispiele sind Microsoft Entra ID,
Keycloak, Authentik, Authelia, Zitadel und Google. Oft heißt er IdP. Der Benutzer tippt das Passwort nur beim
Identitätsanbieter ein, nie beim PACS.

<a id="oidc"></a>
### OpenID Connect (OIDC)

OpenID Connect ist ein Standard für die Anmeldung. Der Identitätsanbieter prüft das Passwort und gibt der Anwendung ein
signiertes Token mit [Claims](#claim) über den Benutzer. Die Anwendung sieht das Passwort nie.
[oauth2-proxy](#oauth2-proxy) spricht OIDC mit dem Identitätsanbieter.

<a id="oauth2-proxy"></a>
### oauth2-proxy

oauth2-proxy ist ein kleines Open-Source-Programm, das Benutzer bei einem [Identitätsanbieter](#identity-provider) anmeldet und
die Sitzung in einem Cookie hält. nginx fragt es bei jeder Anfrage ([auth_request](#auth-request)). Es läuft als Container
`ohif-auth` und hat keinen Port außerhalb des Docker-Netzes. Anleitung: [login.de.md#login-oauth2](login.de.md#login-oauth2).

<a id="auth-request"></a>
### auth_request

`auth_request` ist eine Funktion von nginx. Bevor nginx eine Anfrage beantwortet, schickt es eine kleine eigene Anfrage an eine
andere Adresse. Antwort 2xx lässt die Anfrage durch. Antwort 401 schickt den Benutzer zur Anmeldung. Antwort 403 lehnt ab. In
diesem Repository fragt nginx oauth2-proxy.

<a id="entra-id"></a>
### Microsoft Entra ID

Microsoft Entra ID ist der Cloud-Dienst von Microsoft für Benutzerkonten und Anmeldung. Sein früherer Name war Azure Active
Directory (Azure AD). Anleitung: [login.de.md#login-oauth2-entra](login.de.md#login-oauth2-entra).

<a id="tenant"></a>
### Tenant (Mandant)

Ein Tenant ist der eigene Teil von Entra ID, der zur eigenen Organisation gehört. Er hat eine ID, die Verzeichnis-ID (Mandant),
englisch Directory (tenant) ID. Die ID ist eine GUID, zum Beispiel `11111111-2222-3333-4444-555555555555`. Die ID ist Teil der
Issuer-Adresse `https://login.microsoftonline.com/<tenant-id>/v2.0` in den Einstellungen von oauth2-proxy.

<a id="object-id"></a>
### Objekt-ID (object ID)

Entra gibt jedem Benutzer und jeder Gruppe eine Objekt-ID, eine GUID. Die ID ändert sich nie. Der Name einer Gruppe kann sich
ändern. Die Compose-Datei und `site.conf` nutzen die Objekt-ID der Viewer-Gruppe und der Admin-Gruppe.

<a id="client-id"></a>
### Client-ID

Die Client-ID (Entra: Anwendungs-ID (Client), englisch Application (client) ID) ist der öffentliche Name der App, die man beim
Identitätsanbieter registriert. Die Client-ID steht in der ersten Zeile von `ohif-auth.env`.

<a id="client-secret"></a>
### Client-Geheimnis (client secret)

Das Client-Geheimnis ist das Passwort der registrierten App. Damit beweist oauth2-proxy dem Identitätsanbieter, dass es die
registrierte App ist. Der Anbieter zeigt den Wert nur einmal, beim Anlegen. Das Geheimnis läuft an einem Datum ab, das man selbst
wählt, und an diesem Tag hört die Anmeldung auf zu funktionieren. Es steht in der zweiten Zeile von `ohif-auth.env`.

<a id="cookie-secret"></a>
### Cookie-Geheimnis (cookie secret)

Das Cookie-Geheimnis ist eine Zufallszeichenfolge, mit der oauth2-proxy das Sitzungs-Cookie schützt. Für jede Installation ein
neues erzeugen, mit dem Befehl in der Compose-Datei. Es steht in der dritten Zeile von `ohif-auth.env`.

<a id="redirect-uri"></a>
### Redirect-URI (Umleitungs-URI)

Die Redirect-URI ist die Adresse, an die der Identitätsanbieter den Browser nach der Anmeldung zurückschickt, zum Beispiel
`https://pacs.example.org/oauth2/callback`. Man registriert sie beim Anbieter. Die Redirect-URI muss mit der Adresse in der
oauth2-proxy-Einstellung `--redirect-url` Zeichen für Zeichen übereinstimmen. Die meisten Anbieter akzeptieren nur
https-Adressen.

<a id="claim"></a>
### Claim

Ein Claim ist eine Angabe, die der Identitätsanbieter nach der Anmeldung in das signierte Token schreibt, zum Beispiel der Name,
die E-Mail-Adresse oder die Gruppen des Benutzers.

<a id="groups-claim"></a>
### Groups-Claim

Der Groups-Claim ist der Claim `groups`. Er listet die Gruppen des Benutzers. Entra schreibt die [Objekt-IDs](#object-id) der
Gruppen hinein, wenn die Token-Konfiguration das verlangt. Andere Anbieter schreiben Gruppennamen. oauth2-proxy liest den
Claim, um zu entscheiden, wer den Viewer öffnen darf und wer [Admin](#admin-account) ist.

<a id="basic-auth"></a>
### Basic-Authentifizierung (basic authentication)

Die Basic-Authentifizierung ist das älteste Anmeldeverfahren des Webs. Der Browser zeigt ein Fenster für Benutzername und
Passwort und schickt sie mit jeder Anfrage mit. nginx prüft sie gegen [htpasswd](#htpasswd)-Dateien. Es gibt keine Abmeldung,
keinen zweiten Faktor und keine Grenze für falsche Passwörter. Anleitung: [login.de.md#login-basic](login.de.md#login-basic).

<a id="htpasswd"></a>
### htpasswd

Eine htpasswd-Datei ist eine Textdatei mit einer Zeile pro Konto: dem Benutzernamen und einem Hash des Passworts. nginx liest sie
für die Basic-Authentifizierung. Dieses Repository nutzt zwei Dateien in `/opt/ohif/htpasswd`: `users` (alle Konten) und
`admins` (die Administratoren). Das Werkzeug `deploy/tools/pacs-adduser.sh` schreibt sie.

<a id="keycloak"></a>
### Keycloak

Keycloak ist ein Open-Source-Identitätsanbieter. Er kann der Identitätsanbieter für oauth2-proxy sein. Die dcm4chee-Images mit
`-secure` im Namen bringen ein eigenes Keycloak und eine eigene Anmeldung mit. Dieses Repository unterstützt diesen Aufbau nicht.

<a id="terms-linux"></a>
## 3. Docker und Linux

<a id="compose-project"></a>
### Compose-Projekt

Ein Compose-Projekt ist eine Gruppe von Containern, die eine Compose-Datei startet. Der Name des Projekts ist der Name des
Ordners, der die Datei enthält, sofern die Datei keinen anderen setzt. Der Befehl `docker compose` wirkt auf das Projekt des
Ordners, in dem man steht. Der Projektname ist der erste Teil des Namens seiner Netze, zum Beispiel `dcm4chee-arc_default`.

<a id="external-network"></a>
### Externes Netz (external network)

Ein externes Netz ist ein Docker-Netz, das eine Compose-Datei nicht anlegt, sondern ihm beitritt. Die Compose-Dateien dieses
Repositorys treten dem Netz des dcm4chee-Projekts bei (letzter Block der Datei, `external: true`). So erreicht nginx `arc` über
den Namen.

<a id="bind-mount"></a>
### Bind-Mount

Ein Bind-Mount zeigt einen Ordner oder eine Datei des Servers im Inneren eines Containers. Die Compose-Dateien dieses
Repositorys mounten Ordner und keine einzelnen Dateien. Ein Werkzeug, das eine einzelne Datei ersetzt, lässt dem Container die
alte Datei. Ein Ordner zeigt die neue Datei sofort.

<a id="uid"></a>
### uid

Eine uid ist die Nummer eines Kontos in Linux. Programme in Containern nutzen die Nummern des Servers, nicht ihre eigenen
Kontonamen. Die nginx-Worker-Prozesse im Image `nginx` und im OHIF-Image laufen als uid 101. Die Sockets des Hilfsdienstes
gehören der uid in `PACS_SOCKET_UID` (Vorgabe 101), damit nginx sie nutzen kann. Auf dem Server kann die uid 101 zu einem anderen
Konto gehören: `getent passwd 101` zeigt es.

<a id="unix-socket"></a>
### Unix-Socket

Ein Unix-Socket ist eine Datei, über die zwei Programme auf demselben Computer miteinander sprechen. Er ersetzt einen
Netzwerk-Port. In `ls -l` beginnt er mit `s`, zum Beispiel `srw-------`. Der Hilfsdienst hat zwei:
`/run/pacs-admin/verwaltung.sock` (Aufrufe der Admin-Seite) und `/run/pacs-admin/protokoll.sock` (Protokollzeilen). Der
nginx-Container sieht sie über einen Mount des Ordners `/run/pacs-admin`.

<a id="mount-propagation"></a>
<a id="rslave"></a>
### Mount-Propagation (rslave)

Eine Platte, die der Server nach dem Start eines Containers einhängt, ist in diesem Container normalerweise unsichtbar. Das
Flag `:rslave` an einem Bind-Mount ändert das: Der Container erhält die Mounts, die der Server später unterhalb dieses Ordners
macht. Der Platten-Assistent braucht es für den Ordner `/mnt/fs` des Containers `arc`
([modules.de.md#disk-assistant](modules.de.md#disk-assistant)).

<a id="systemd-unit"></a>
### systemd-Unit

Eine systemd-Unit ist eine Datei, die Linux sagt, wie ein Dienst läuft: welches Programm, mit welchem Konto, ob es neu gestartet
wird. Die Units dieses Repositorys sind `pacs-verwaltung.service` und `pacs-firewall.service` in `/etc/systemd/system/`.
Nützliche Befehle sind `systemctl status NAME`, `systemctl restart NAME` und `journalctl -u NAME -n 20 --no-pager`.

<a id="cron"></a>
### cron

cron ist der Aufgabenplaner von Linux. Er führt die Datei `/etc/cron.d/pacs-dashboard` alle 5 Minuten aus. Die Aufgabe schreibt
[status.json](#status-json). cron braucht ein eigenes Paket, `cron`.

<a id="syslog"></a>
### syslog

Syslog ist ein Standard für Logmeldungen. nginx schickt jede Zeile des [Protokolls](#audit-log) als Syslog-Meldung über den
[Unix-Socket](#unix-socket) `protokoll.sock` an den Hilfsdienst.

<a id="docker-proxy"></a>
### docker-proxy

`docker-proxy` ist das Programm, in dem Docker eine Verbindung auf einem veröffentlichten Port annimmt, bevor es sie an den
Container weitergibt. Über IPv6 verdeckt es die echte Adresse des Clients: nginx sieht nur das Docker-Gateway. Aus diesem Grund
veröffentlichen die Compose-Dateien die Ports als `0.0.0.0:80:8080`, das nur IPv4 ist.

<a id="iptables"></a>
<a id="docker-user"></a>
### iptables und DOCKER-USER

iptables ist der Paketfilter des Linux-Kernels. Docker fügt Regeln für jeden Port hinzu, den es veröffentlicht. Die Kette
`DOCKER-USER` ist der Platz für eigene Regeln: Docker prüft sie vor seinen eigenen Regeln. Docker baut die Kette bei jedem Start
neu auf. Die Firewall der Admin-Seite hält ihre Regeln in der Kette `PACS-SPERRE` und springt von `DOCKER-USER` dorthin. Der
Dienst `pacs-firewall` setzt den Sprung nach jedem Start von Docker neu. Die Firewall filtert nur IPv4 und nur Ports, die Docker
veröffentlicht. Anleitung: [modules.de.md#firewall](modules.de.md#firewall).

<a id="cidr"></a>
### CIDR

CIDR ist eine kurze Schreibweise für ein Netz: eine Adresse, ein Schrägstrich und die Zahl der festen Bits. `192.0.2.0/24`
bedeutet die 256 Adressen von 192.0.2.0 bis 192.0.2.255. `192.0.2.17/32` bedeutet genau diese eine Adresse.

<a id="terms-certificates"></a>
## 4. Zertifikate

<a id="tls-certificate"></a>
### TLS-Zertifikat

Ein TLS-Zertifikat lässt den Browser prüfen, ob er mit dem echten Server spricht, und schaltet https ein. Es gehört zu einem
Hostnamen, zum Beispiel `pacs.example.org`. Es kommt mit einem privaten Schlüssel. Der Schlüssel bleibt geheim auf dem Server.
Wie man eines beschafft und installiert: [install.de.md#tls-certificate](install.de.md#tls-certificate).

<a id="ca"></a>
### Zertifizierungsstelle (CA)

Eine Zertifizierungsstelle ist eine Organisation, die Zertifikate signiert. Beispiele sind Let's Encrypt und die CA der eigenen
Organisation. Browser vertrauen den öffentlichen Stellen. Eine eigene CA funktioniert nur auf PCs, die so eingerichtet wurden,
dass sie ihr vertrauen.

<a id="certificate-chain"></a>
### Zertifikatskette

Die Zertifikatskette ist das Server-Zertifikat, gefolgt von den Zertifikaten der Stellen, die es signiert haben. nginx braucht
sie in einer Datei, `server.crt`, mit dem Server-Zertifikat zuerst. Ohne die Zwischenzertifikate lehnen manche Clients die
Verbindung ab.

<a id="intermediate-certificate"></a>
### Zwischenzertifikat

Ein Zwischenzertifikat steht zwischen dem Root-Zertifikat der Stelle und dem Server-Zertifikat. Man bekommt es von der Stelle
zusammen mit dem eigenen Zertifikat.

<a id="pem"></a>
### PEM

PEM ist ein Textformat für Zertifikate und Schlüssel. Eine PEM-Datei beginnt mit einer Zeile wie
`-----BEGIN CERTIFICATE-----`. nginx liest nur PEM.

<a id="pfx"></a>
### PFX

Eine PFX-Datei (`.pfx` oder `.p12`) ist eine einzige Binärdatei, die Zertifikat, Kette und privaten Schlüssel enthält,
geschützt durch ein Passwort. Windows-Server exportieren dieses Format. nginx kann es nicht lesen. Mit `openssl pkcs12`
umwandeln, siehe [install.de.md#tls-certificate](install.de.md#tls-certificate).

<a id="subject-alt-name"></a>
### Subject Alternative Name (SAN)

Der Subject Alternative Name (alternativer Antragstellername) ist die Liste der Hostnamen in einem Zertifikat. Aktuelle Browser
prüfen den Hostnamen gegen diese Liste und ignorieren das ältere Feld CN. Ein Zertifikat ohne SAN wird abgelehnt, auch ein
selbstsigniertes.

<a id="self-signed"></a>
### Selbstsigniertes Zertifikat

Ein selbstsigniertes Zertifikat ist mit seinem eigenen Schlüssel signiert. Keine Stelle bürgt dafür, deshalb zeigen Browser eine
Warnung. Es taugt für einen Test, nicht für den Alltag.

<a id="terms-dicom"></a>
## 5. DICOM und Speicher

<a id="dicom"></a>
### DICOM

DICOM ist der Standard für medizinische Bilder und dafür, wie Geräte sie über das Netz senden. Ein Gerät, das Bilder erzeugt, ist
eine [Modalität](#modality). Das Archiv hört auf DICOM an einem eigenen Port.

<a id="hl7"></a>
### HL7

HL7 ist ein Standard für Nachrichten zwischen Krankenhaus-Systemen, zum Beispiel Patienten- und Aufnahmedaten. Das Archiv hört
auf HL7 an einem eigenen Port.

<a id="modality"></a>
### Modalität

Eine Modalität ist ein Gerät, das Bilder erzeugt, zum Beispiel ein CT, ein Ultraschallgerät oder ein Röntgengerät. Die Spalte
Mod. in der Liste der Studien zeigt ihr Kürzel.

<a id="ae-title"></a>
### AE-Titel

Ein AE-Titel (Application Entity Title) ist der Name eines DICOM-Geräts. Er hat bis zu 16 Zeichen. Eine Modalität und das Archiv
kennen sich unter diesen Namen. Der AE-Titel des Archivs ist standardmäßig `DCM4CHEE`. Er steht in `config.js` (`aet`), in
`/etc/default/pacs-admin` (`ARC_AET`) und in den nginx-Dateien. Das Werkzeug `deploy/tools/set-aet.sh` benennt ihn an allen
Stellen um, die zu diesem Repository gehören. Referenz: [reference.de.md#ae-title](reference.de.md#ae-title).

<a id="iocm-quality"></a>
### IOCM_QUALITY und 113001^DCM

IOCM steht für Imaging Object Change Management, einen DICOM-Weg, Bilder auszublenden, ohne sie zu löschen. Wenn die Admin-Seite
eine Studie ablehnt, speichert dcm4chee-arc einen Ablehnungsvermerk mit dem Code `113001^DCM` (Rejected for Quality Reasons) und
blendet die Studie aus. `IOCM_QUALITY` ist der AE-Titel der Ansicht, die die abgelehnten Studien zeigt. Dort kann die
Admin-Seite eine Studie zurückholen oder endgültig löschen. Die Einstellung heißt `iocmAet` in `config.js`.

<a id="coding-scheme-99dcm4chee"></a>
### 99DCM4CHEE

`99DCM4CHEE` ist der Name eines DICOM-Coding-Schemes, einer Tabelle von Codes. Er ist kein AE-Titel. Er ist Teil des Aufrufs,
der eine abgelehnte Studie zurückholt. Beim Umbenennen des AE-Titels unverändert lassen.

<a id="storage"></a>
### Speicher (storage)

Ein Speicher (englisch storage) ist ein Ort, an dem dcm4chee-arc Bilddateien ablegt. In diesem Aufbau ist jeder Speicher eine
Platte, die unterhalb von `/mnt/fs` unter einem Namen wie `PACS-Data01` oder `PACS-Data02` eingehängt ist (Einstellungen
`STORAGE_BASE` und `STORAGE_PREFIX`). Jeder Speicher ist auch ein Eintrag in der Konfiguration des Archivs in [LDAP](#ldap).
Jeder Speicher hat eine Schwelle: den freien Platz, der bleiben muss. Unterhalb der Schwelle zählt das Archiv den Speicher als
voll.

<a id="write-list"></a>
### Schreibliste (write list)

Die Schreibliste ist die geordnete Liste der Speicher, die neue Bilder erhalten. Neue Bilder gehen an den ersten Speicher der
Liste. Ist er voll, gehen sie an den nächsten. Der Reiter Übersicht zeigt die Reihenfolge (`neue Bilder jetzt`,
`neue Bilder als 2.`). Anleitung: [modules.de.md#disk-assistant](modules.de.md#disk-assistant).

<a id="sqlcipher"></a>
### SQLCipher

SQLCipher ist SQLite mit Verschlüsselung. Das Protokoll liegt in einer solchen Datenbank, in
`/var/lib/pacs-protokoll/protokoll.db`. Der Schlüssel liegt in der Datei `/etc/pacs-protokoll.key`. Der Hilfsdienst braucht die
Bibliothek: das Paket `libsqlcipher1` auf Debian 13 und `libsqlcipher0` auf Debian 12 und älter. Den Schlüssel sichern: Ohne
ihn sind die gespeicherten Zeilen nicht lesbar. Schritte: [install.de.md#audit-key](install.de.md#audit-key).

<a id="screen-labels"></a>
## 6. Wörter auf dem Bildschirm

Die Admin-Seite ist auf Deutsch. Diese Tabellen listen die Beschriftungen, die die Anleitungen nennen, und sagen, was sie
bedeuten. Die Anleitungen schreiben die Beschriftung in `code`.

<a id="screen-tabs"></a>
### Reiter und Links in der oberen Leiste

| Beschriftung | Bedeutung |
|---|---|
| `Übersicht` | Dienste, Zusammenfassung der Firewall, Platten, letzte Änderungen |
| `Studien` | Suchen, bearbeiten, verschieben, ablehnen |
| `Patienten` | Suchen, korrigieren, zusammenführen |
| `Firewall` | Wer welchen Port des Servers erreichen darf |
| `Protokoll` | Wer was gesucht, geöffnet oder geändert hat |
| `dcm4chee` | Link zur Benutzeroberfläche von dcm4chee |
| `Viewer` | Link zum OHIF-Viewer |
| `Abmelden` | Abmelden (nur sichtbar, wenn `abmeldenUrl` gesetzt ist) |

<a id="screen-overview"></a>
### Reiter Übersicht

| Beschriftung | Bedeutung |
|---|---|
| `Dienste` | Ein Badge pro Container; `aus` hinter dem Namen heißt: Der Container läuft nicht |
| `Speicher` | Die Platten mit dem freien Platz |
| `Letzte Änderungen` | Die letzten Änderungen, die über die Admin-Seite gemacht wurden |
| `neue Bilder jetzt` | Neue Bilder gehen jetzt an diese Platte |
| `neue Bilder als 2.` | Neue Bilder gehen an diese Platte, wenn die Platten davor voll sind (hier: an zweiter Stelle) |
| `als voll markiert` | Die Platte gilt als voll |
| `Markierung entfernen` | Die Markierung „voll“ entfernen |
| `In Schreibliste aufnehmen` | Die Platte in die [Schreibliste](#write-list) aufnehmen |
| `Aus Schreibliste nehmen` | Die Platte aus der Schreibliste nehmen |
| `nicht eingehängt, bitte prüfen` | Die Platte ist nicht eingehängt. Prüfen, ob der Server sie sieht |
| `Neue Festplatte` | Erscheint, wenn der Server eine leere Platte gefunden hat |
| `Als PACS-Data02 einrichten …` | Die neue Platte als PACS-Data02 einrichten |
| `Formatieren und einrichten` | Die Platte formatieren und einrichten |
| `Jetzt suchen` | Sofort nach einer leeren Platte suchen, ohne auf den nächsten Lauf von cron zu warten |
| `Kein Status vorhanden (dashboard-status.py läuft per cron alle 5 Minuten).` | Es gibt noch keinen Status (das Statusskript läuft per cron alle 5 Minuten) |
| `Sitzung abgelaufen, Seite neu laden (F5)` | Die Sitzung ist abgelaufen. Die Seite mit F5 neu laden |

<a id="screen-firewall"></a>
### Reiter Firewall

<a id="probelauf"></a>
<a id="offen"></a>
<a id="gesperrt"></a>

Jeder Port hat einen von drei Modi. Die Einstellung `Ports ohne eigene Regel` gibt den Modus für alle Ports ohne eigene Regel
an, auch für Ports, die Docker erst später veröffentlicht.

| Beschriftung | Bedeutung |
|---|---|
| `gesperrt` | Nur die aufgelisteten Hosts und Netze kommen durch. Alle anderen werden abgewiesen. |
| `Probelauf` | Alle kommen durch. Eine Quelle, die nicht aufgelistet ist, erscheint unter `Neu erkannt`. Vor dem Sperren nutzen. |
| `offen` | Alle kommen durch. |
| `Ports ohne eigene Regel` | Der Modus für alle anderen Ports |
| `eingeschaltet` | Das Kontrollkästchen, das die ganze Firewall einschaltet |
| `wirksam` / `nicht wirksam` / `ausgeschaltet` | Die Regeln gelten / die Firewall ist eingeschaltet, aber die Regeln gelten nicht (der Grund steht dabei) / die Firewall ist ausgeschaltet |
| `Neu erkannt` | Geräte, Absender und Verbindungen, die noch keine Regel auflistet |
| `Erlauben` | Die Quelle in die Regel ihres Ports eintragen |
| `Ausblenden` | Den Eintrag aus der Liste nehmen, bis man `Wieder anzeigen` wählt |
| `Wieder anzeigen` | Ausgeblendete Einträge wieder zeigen |
| `Speichern` | Alle Änderungen auf einmal anwenden |
| `Verwerfen` | Die Änderungen verwerfen, die noch nicht gespeichert sind |
| `Neu laden` | Die Daten der Firewall neu vom Server holen |
| `Hinzufügen` | Einen Host oder ein Netz in die Liste eines Ports eintragen |
| `IPv6 nicht gefiltert` | Docker veröffentlicht den Port auch über IPv6, und die Firewall filtert nur IPv4 |

<a id="screen-audit"></a>
### Reiter Protokoll

| Beschriftung | Bedeutung |
|---|---|
| `Von` / `Bis` | Datum von / bis |
| `Heute`, `7 Tage`, `30 Tage` | Schnellwahl für den Zeitraum: heute, die letzten 7 Tage, die letzten 30 Tage |
| `Anzeigen` | Die Zeilen für den gewählten Zeitraum zeigen |
| `Als CSV speichern` | Die Zeilen als CSV-Datei speichern |
| `Patienten-ID` | Zeigt nur die Zeilen zu diesem Patienten |
| `Patientenname` | Zeigt nur die Zeilen zu Patienten mit diesem Namen. Der Anfang des Namens genügt. Das Feld zeigt den Hinweis `Nachname` |
| `Konto` | Das Konto, das die Anfrage gestellt hat. Ein Teil der Anmeldung genügt. Das Feld zeigt den Hinweis `Teil der Anmeldung` |
| `(ohne Konto)` | Zeilen ohne Konto |
| `PC` | Der PC, von dem die Anfrage kam. Ein Teil des Namens oder der IP-Adresse genügt. Das Feld zeigt den Hinweis `Name oder IP` |
| `Art` | Art der Zeile: `alle` (alle Zeilen), `Studie geöffnet`, `Bericht geöffnet`, `Suche`, `Verwaltung` (Änderungen in der Admin-Seite), `nur Abgelehntes und Fehler` (nur abgelehnte Anfragen und Fehler) |
| `Text in Aktion und Details` | Zeigt nur die Zeilen, die diesen Text in der Aktion, in den Details oder in der Studie enthalten. Das Feld zeigt den Hinweis `z. B. Accession, Beschreibung` |
| `Zeit` | Spalte der Tabelle: die Uhrzeit. Der Tag steht in einer eigenen Zeile über den Einträgen dieses Tages |
| `Wer` | Spalte der Tabelle: das Konto ohne den Teil nach dem `@`, darunter der PC |
| `Was` | Spalte der Tabelle: die Aktion als farbiges Badge (Änderungen und abgelehnte Anfragen fallen auf), darunter eine Zeile je Detail |
| `Patient` | Spalte der Tabelle: der Name des Patienten, darunter die Patienten-ID |
| `Studie` | Spalte der Tabelle: Datum, Modalität und Accession Number der Studie, oder die Study-UID, wenn das Archiv die Studie nicht kennt |
