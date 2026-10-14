# nginx für das PACS-Admin-Panel

[English](README.md) | Deutsch

nginx ist die Eingangstür des Admin-Panels. nginx prüft, wer hereinkommen darf, liefert die Seite aus, gibt Aufrufe an den
Hilfsdienst und an dcm4chee-arc weiter, mit Sperren, die falsche Änderungen fernhalten, und schreibt das Protokoll. Die
Konfiguration besteht aus **einer Kerndatei, die nie bearbeitet wird**, und einigen kleinen Dateien, die ausgewählt werden:
ein **Anmeldeverfahren**, ein **Viewer-Modus** und ein **Listener**. Bearbeitet wird genau eine kleine Datei (`site.conf`),
mit den eigenen Werten.

- [Rezepte: Ich will X, diese Dateien kopieren](#recipes)
- [Kopierbefehle](#copy-commands)
- [Platzhalter (CHANGE-ME)](#placeholders)
- [Mount-Punkte für die Compose-Datei](#mount-points)
- [Die Auswahl im Einzelnen](#choices): [Anmeldeverfahren](#login), [Viewer](#viewer), [Listener](#listener), [Abschnitt für die dcm4chee-Oberfläche](#dcm4chee-ui)
- [nginx auf dem Host statt in einem Container](#host-nginx)
- [AE-Titel](#ae-titles)
- [Änderungen gegenüber der alten Einzeldatei](#upgrade)
- [Was die Konfiguration garantiert](#guarantees)
- [Prüfungen und Fehlersuche](#checks)
- [Testlabor](#lab)

## Aufbau der Dateien

```
deploy/nginx/
  pacs.conf               Kern: Logformate, Maps, der Server-Block mit jeder Location und jeder Sperre (wird nie bearbeitet)
  site.conf.example       die eigenen Werte: nach pacs/site.conf kopieren und bearbeiten (die einzige Datei, die bearbeitet wird, bei nginx 1.25.1 oder neuer)
  common/                 gemeinsame Teile, unverändert kopiert: proxy.conf  headers.conf  audit-write.conf
  login/oauth2-proxy/     Anmeldung mit oauth2-proxy (Entra ID, Keycloak, Authentik, Google, GitHub ...)
  login/basic/            Anmeldung mit HTTP-Basic-Authentifizierung (zwei htpasswd-Dateien: alle Konten / Admins)
  login/none/             keine Anmeldung, nur eine Liste erlaubter Netze
                          jeder der drei hat vier Dateien: http.conf  server.conf  locations.conf  admin.conf
  viewer/ohif.conf        OHIF-Viewer plus die DICOMweb-Lesezugriffe, die nur der Viewer braucht
  viewer/none.conf        nur das Admin-Panel: "/" leitet auf /admin/ um
  listener/tls/           https auf diesem nginx (und Umleitung von http auf https)       zwei Dateien: http.conf  server.conf
  listener/plain/         unverschlüsseltes http, für einen ersten Blick durch einen SSH-Tunnel
  listener/behind-proxy/  unverschlüsseltes http hinter einem Proxy, der TLS beendet (Traefik, Caddy, Apache, Cloudflare Tunnel)
  optional/dcm4chee-ui.conf   die dcm4chee-Oberfläche hinter derselben Anmeldung (optional)
```

Das wird gebaut und in den nginx-Container gemountet (der Ordner `/opt/ohif/nginx` ist nur ein Beispiel):

```
/opt/ohif/nginx/              nur lesend gemountet als /etc/nginx/conf.d
  pacs.conf                   der Kern
  pacs/
    site.conf                 die eigenen Werte
    proxy.conf  headers.conf  audit-write.conf            gemeinsame Teile
    viewer.conf                                           der gewählte Viewer
    login/    http.conf server.conf locations.conf admin.conf   das gewählte Anmeldeverfahren
    listener/ http.conf server.conf                       der gewählte Listener
    optional/dcm4chee-ui.conf                             diese Datei löschen, um den Abschnitt abzuschalten
```

So passen die Teile zusammen: `pacs.conf` bindet `login/http.conf` und `listener/http.conf` im http-Block ein (Kontoname für das
Protokoll, Umleitung von http auf https, Referer-Regel) und `site.conf`, `listener/server.conf`, `login/server.conf`,
`login/locations.conf`, `optional/*.conf` und `viewer.conf` im Server-Block. Jede Location, die nur für Admins gilt, bindet
**eine** Datei ein, `login/admin.conf`, als ihre Anmeldeprüfung: Diese Datei enthält den ganzen Unterschied zwischen „Admin“ und
„jedes Konto“, für jedes Anmeldeverfahren. Locations für jedes Konto nutzen die Prüfung aus `login/server.conf`, die sie erben.

<a id="recipes"></a>
## Rezepte: Ich will X, diese Dateien kopieren

| Ich will | Anmeldung | Viewer | Listener | außerdem nötig |
|---|---|---|---|---|
| Entra ID (oder Keycloak, Authentik, Authelia, Zitadel, Google, GitHub) mit oauth2-proxy, OHIF-Viewer, https auf diesem Server | `oauth2-proxy` | `ohif` | `tls` | oauth2-proxy-Container, Zertifikat, Admin-Gruppe in `site.conf` |
| dasselbe, nur das Admin-Panel (kein Viewer, Standard-Image `nginx`) | `oauth2-proxy` | `none` | `tls` | wie oben |
| kein OAuth-Proxy: Benutzername und Passwort in nginx (zwei htpasswd-Dateien), OHIF-Viewer, https | `basic` | `ohif` | `tls` | Zertifikat, htpasswd-Dateien `users` und `admins` |
| dasselbe, nur das Admin-Panel | `basic` | `none` | `tls` | wie oben |
| ein erster Blick auf 127.0.0.1 ohne TLS durch einen SSH-Tunnel | `basic` | `none` (oder `ohif`) | `plain` | htpasswd-Dateien; den Port nur auf 127.0.0.1 veröffentlichen |
| ein vorhandener TLS-Proxy (Traefik, Caddy, Apache, Cloudflare Tunnel) bleibt davor, nginx behält Anmeldung und Sperren | beliebig | beliebig | `behind-proxy` | Netz des Proxys in `listener/server.conf`; nginx nur vom Proxy aus erreichbar machen |
| gar keine Anmeldung, nur eine Liste von PCs, die hereinkommen dürfen | `none` | beliebig | beliebig | die beiden Netzlisten von `login/none/` |
| nginx auf dem Host statt in einem Container | beliebig | `none` (die OHIF-Dateien kommen mit dem OHIF-Image) | `tls` | [Schritte für den Host](#host-nginx) |

Nicht unterstützt: dcm4chee mit eigenem Keycloak (die `-secure`-Images: nginx schickt kein Token an arc) und der Ersatz von nginx
durch Traefik, Caddy oder Cloudflare Access (die Sperren, der Socket des Hilfsdienstes und das Protokoll erledigt nginx; diese
Produkte können nur davor stehen, Rezept `behind-proxy`).

<a id="copy-commands"></a>
## Kopierbefehle

Schritt 1 ist für jedes Rezept gleich. `N` ist dieser Ordner des Repositorys, `T` ist die eigene Kopie, der Ordner, den die
Compose-Datei als `/etc/nginx/conf.d` mountet.

<!-- lab:fixed -->
```bash
N=/opt/pacs-admin/deploy/nginx
T=/opt/ohif/nginx
mkdir -p $T/pacs/login $T/pacs/listener $T/pacs/optional
cp $N/pacs.conf $T/pacs.conf
cp $N/site.conf.example $T/pacs/site.conf
cp $N/common/*.conf $T/pacs/
cp $N/optional/dcm4chee-ui.conf $T/pacs/optional/
```

Die letzte Zeile kopiert den optionalen Abschnitt für die dcm4chee-Oberfläche. Zum Abschalten die Zeile weglassen oder später
`rm $T/pacs/optional/dcm4chee-ui.conf` ausführen.

Schritt 2: das Anmeldeverfahren. Genau eines der drei kopieren.

<!-- lab:login=oauth2-proxy -->
```bash
cp $N/login/oauth2-proxy/*.conf $T/pacs/login/
```

<!-- lab:login=basic -->
```bash
cp $N/login/basic/*.conf $T/pacs/login/
```

<!-- lab:login=none -->
```bash
cp $N/login/none/*.conf $T/pacs/login/
```

Schritt 3: der Viewer. Genau einen kopieren.

<!-- lab:viewer=ohif -->
```bash
cp $N/viewer/ohif.conf $T/pacs/viewer.conf
```

<!-- lab:viewer=none -->
```bash
cp $N/viewer/none.conf $T/pacs/viewer.conf
```

Schritt 4: der Listener. Genau einen kopieren.

<!-- lab:listener=tls -->
```bash
cp $N/listener/tls/*.conf $T/pacs/listener/
```

<!-- lab:listener=plain -->
```bash
cp $N/listener/plain/*.conf $T/pacs/listener/
```

<!-- lab:listener=behind-proxy -->
```bash
cp $N/listener/behind-proxy/*.conf $T/pacs/listener/
```

Schritt 5: `$T/pacs/site.conf` bearbeiten (und die Dateien, die unter [Platzhalter](#placeholders) genannt sind), dann prüfen. Die
beiden Werte von `site.conf` lassen sich in einem Zug setzen (die Zeilen werden samt ihrem Markierungskommentar ersetzt; den
eigenen Namen und die eigene Gruppen-ID einsetzen):

```bash
sed -E -i -e 's/^(server_name +)[^;]+;.*/\1pacs.yourdomain.example;/' \
          -e 's/^(set \$pacs_admin_group +)[^;]+;.*/\1YOUR-ADMIN-GROUP-ID;/' $T/pacs/site.conf
```

Danach prüfen. Die erste Zeile muss nichts ausgeben, die zweite meldet bei laufendem Container `syntax is ok` und
`test is successful`:

```bash
grep -rn CHANGE-ME $T          # must print nothing
docker exec ohif nginx -t      # once the container runs: "syntax is ok" and "test is successful"
```

Vor dem ersten Start funktioniert dieselbe Prüfung in einem Wegwerf-Container (Listener `tls`; bei `plain` oder `behind-proxy`
die zweite Option `-v` weglassen):
`docker run --rm -v $T:/etc/nginx/conf.d:ro -v /opt/ohif/tls:/etc/nginx/tls:ro nginx:1.30 nginx -t`.

Die Befehle nach einer Änderung der Dateien sind `docker exec ohif nginx -t` und `docker exec ohif nginx -s reload` (der
Containername `ohif` ist der aus dem Compose-Beispiel). Im Container wird nichts bearbeitet: Der Ordner ist nur lesend gemountet.

<a id="placeholders"></a>
## Platzhalter (CHANGE-ME)

Jeder Wert, der geändert werden muss, trägt die Markierung `CHANGE-ME` in einem Kommentar auf derselben Zeile. Den Wert ersetzen
**und den Kommentar mit der Markierung löschen**; danach darf `grep -rn CHANGE-ME $T` nichts ausgeben. Ein vergessener Platzhalter
besteht `nginx -t` trotzdem (jeder Beispielwert ist wohlgeformt), daher mit dem grep prüfen. Die Beispiel-Admin-Gruppe und die
Beispielnetze des Anmeldeverfahrens `none` geben nichts frei: Über sie kommt niemand herein. Die mitgelieferte Zeile `set_real_ip_from 203.0.113.1` trägt eine Adresse aus dem Dokumentationsbereich (RFC 5737) und vertraut
niemandem: Solange sie bleibt, gilt die Adresse der Verbindung als Adresse des Clients, und das Protokoll zeigt für jeden Client den
Proxy. Dort die Adresse des eigenen Proxy-Containers eintragen (`docker inspect PROXY`), höchstens das Subnetz, das nginx mit ihm teilt.

| Datei in `pacs/` | Was | Nötig für |
|---|---|---|
| `site.conf` | `server_name`: der Name, den die Benutzer im Browser eintippen | immer |
| `site.conf` | `set $pacs_admin_group`: Objekt-ID der Admin-Gruppe in Entra ID oder der Gruppenname eines anderen OIDC-Anbieters | Anmeldeverfahren `oauth2-proxy` (bei `basic` und `none` die Zeile ignorieren oder samt ihrer Markierung löschen) |
| `login/server.conf` | `allow`: Netz der PCs, die den Viewer öffnen dürfen | Anmeldeverfahren `none` |
| `login/admin.conf` | `allow`: Netz oder Adresse der Administrator-PCs | Anmeldeverfahren `none` |
| `listener/server.conf` | `set_real_ip_from`: die Adresse des vorgeschalteten Proxys oder sein Docker-Netz | Listener `behind-proxy` |

Werte, die meist bleiben, wie sie sind, die man aber einmal ansehen sollte (`site.conf`, ohne Markierung):

| Wert | Vorgabe | Ändern, wenn |
|---|---|---|
| `set $arc` | `http://arc:8080` | der dcm4chee-arc-Container einen anderen Namen oder http-Port hat (`docker ps`); nginx auf dem Host: `http://127.0.0.1:8080` |
| `resolver` | `127.0.0.11` (DNS von Docker) | nginx auf dem Host mit einer IP-Adresse oben: die Zeile löschen |
| `set $pacs_auth` | `http://ohif-auth:4180` | der Dienst oauth2-proxy einen anderen Namen oder Port hat |

Die Zertifikatspfade stehen nicht in `site.conf`: `ssl_certificate` und `ssl_certificate_key` sind die letzten beiden Zeilen von
`listener/server.conf` des Listeners `tls` (`/etc/nginx/tls/server.crt` und `server.key`; ändern, wenn das Zertifikat woanders liegt,
bei nginx auf dem Host: die Pfade von Let's Encrypt). Die Listener `plain` und `behind-proxy` haben solche Zeilen nicht und brauchen
keinen Ordner `tls`.

<a id="mount-points"></a>
## Mount-Punkte für die Compose-Datei

Pfade im nginx-Container: Diese sind fest, die Dateien oben verweisen auf sie; die Pfade auf dem Host sind Beispiele.

| Im Container | Inhalt | Pfad auf dem Host (Beispiel) | Mount | Wann |
|---|---|---|---|---|
| `/etc/nginx/conf.d` | der Ordner `$T` mit `pacs.conf` und `pacs/` | `/opt/ohif/nginx` | `:ro` | immer |
| `/etc/nginx/tls` | `server.crt` (volle Kette) und `server.key` | `/opt/ohif/tls` | `:ro` | Listener `tls` |
| `/etc/nginx/htpasswd` | die Dateien `users` (alle Konten) und `admins` | `/opt/ohif/htpasswd` | `:ro` | Anmeldeverfahren `basic` |
| `/srv/pacs-admin/admin` | `web/admin` dieses Repositorys | `/opt/pacs-admin/web/admin` | `:ro` | immer |
| `/srv/pacs-admin/status` | `status.json` von `dashboard-status.py` | `/var/lib/pacs-admin/status` | `:ro` | immer |
| `/run/pacs-admin` | die Sockets `verwaltung.sock` und `protokoll.sock` des Hilfsdienstes | `/run/pacs-admin` | `:ro` | immer |
| `/usr/share/nginx/html/app-config.js` | OHIF-Konfiguration | `/opt/ohif/app-config.js` | `:ro` | Viewer `ohif` |
| `/etc/localtime` | Ortszeit im Protokoll | `/etc/localtime` | `:ro` | empfohlen |

- Die **Ordner** `conf.d` und `htpasswd` mounten, keine einzelnen Dateien: Eine Datei, die ersetzt wird (`sed -i`, `mv`), kann im
  Container ihren alten Inhalt behalten, wenn sie als einzelne Datei gemountet wurde; ein Ordner zeigt die neue Datei sofort.
- Veröffentlichte Ports: Der Listener `tls` veröffentlicht `80:8080` und `443:8443`; der Listener `plain` nur `127.0.0.1:8080:8080`;
  der Listener `behind-proxy` veröffentlicht nichts und tritt dem Docker-Netz des Proxys bei.
- Ein Ordner über `/etc/nginx/conf.d` ersetzt die `default.conf` des Images, und das ist gewollt. Das Startskript des nginx-Images
  gibt dann `default.conf is not a file or does not exist` aus; diese Meldung ist harmlos.
- Die Sockets gehören der `PACS_SOCKET_UID` (Hilfsdienst); deren Wert muss die uid der nginx-Worker-Prozesse sein: 101 im Image
  `nginx` und im OHIF-Image. Bei einer Abweichung zeigen sich 502 auf `/admin/dienst/` und fehlende Protokollzeilen.
- nginx 1.25.1 oder neuer (`http2 on`); das Image braucht die Module `http_ssl`, `http_v2`, `http_realip` (Listener `behind-proxy`),
  `http_auth_request` (Anmeldeverfahren `oauth2-proxy`) und `http_gunzip` / `http_gzip_static` (Viewer `ohif`). Das offizielle Image
  `nginx` hat alle.

<a id="choices"></a>
## Die Auswahl im Einzelnen

<a id="login"></a>
### Anmeldeverfahren

Alle drei geben nginx einen Kontonamen für das Protokoll (`u`) und für den Hilfsdienst (`X-Auth-User`), nie leer: Eine Anfrage, die
abgewiesen wird, bevor die Anmeldeprüfung lief (eine Sperre, ein fehlendes `X-PACS-Admin`, ein `;` im Pfad), wird bei oauth2-proxy
und bei `none` als `anon-<Client-Adresse>` protokolliert und bei `basic` mit dem Namen, den der Client gesendet hat.

**oauth2-proxy** (`login/oauth2-proxy/`). nginx fragt oauth2-proxy bei jeder Anfrage (`auth_request`). oauth2-proxy muss mit
`--set-xauthrequest=true` und `--reverse-proxy=true` laufen. Stufe Viewer = jedes Konto, das oauth2-proxy durchlässt (seine
`--allowed-group`-Optionen); Stufe Admin = die Gruppe in `site.conf` (`$pacs_admin_group`, an genau einer Stelle benutzt, der Location
`/oauth2/auth-admin` in `login/locations.conf`). Eine leere Gruppe wird abgewiesen, statt „alle“ zu bedeuten. Für einen Anbieter
ohne Gruppen (Google) den Namen der Abfrage in dieser einen Zeile auf `allowed_emails=` ändern und die kommagetrennten
E-Mail-Adressen in `$pacs_admin_group` eintragen (nicht durchgehend getestet). Die Seite zeigt den Kontonamen aus
`/oauth2/userinfo` (diesen Aufruf gibt nginx weiter).

**basic** (`login/basic/`). nginx prüft Benutzername und Passwort selbst (`auth_basic`), mit zwei Dateien in
`/etc/nginx/htpasswd/`: `users` enthält jedes Konto (auch die Admins), `admins` nur die Administratoren. Ein Konto, das nur in
`users` steht, kann den Viewer benutzen; auf `/admin/` bekommt es wieder 401, und der Browser fragt noch einmal nach dem Passwort
(die Basic-Authentifizierung kann nicht mit 403 antworten). Die Dateien mit `bash deploy/tools/pacs-adduser.sh` anlegen oder von Hand:
`printf '%s:%s\n' NAME "$(printf '%s' 'PASSWORD' | openssl passwd -6 -stdin)" >> users`
(Admins: in beide Dateien). Beide schreiben sha512-crypt (`$6$`, braucht OpenSSL 1.1.1 oder neuer; das Skript weicht mit einer
Warnung auf apr1 aus, wenn `-6` fehlt). nginx prüft den Hash bei jeder Anfrage, daher die Vorgabe für die Rundenzahl behalten: Eine
hohe Zahl bremst jede Anfrage. nginx liest die Dateien bei jeder Anfrage: Ein neues Konto gilt sofort, ohne Reload. Der
nginx-Worker muss sie lesen können (Container: Besitzer uid 101 und Modus 0600 funktionieren, nginx auf dem Host: `root:www-data`
und `0640`); eine fehlende Datei lässt jede Anfrage, die ein Passwort mitschickt, mit 403 antworten, eine nicht lesbare lässt sie
mit 500 antworten (das nginx-Log meldet `open() ... failed`); eine Anfrage ohne Passwort bekommt zuerst 401. Ein Kontoname mit `"`
oder `\` funktioniert, erscheint aber als `?` oben auf der Admin-Seite. Grenzen: keine Abmeldung (den Browser schließen), kein
zweiter Faktor, keine Grenze für falsche Passwörter; eine falsche Anmeldung wird unter dem Namen protokolliert, der getippt wurde.
`auth_basic` ist im Server-Block und in den Admin-Locations selbst gesetzt; es funktioniert nicht in einer
`auth_request`-Unteranfrage (jeder käme herein).

**none** (`login/none/`). Keine Anmeldung, nur Netze. `login/server.conf` nennt, wer den Viewer und alles andere benutzen darf,
`login/admin.conf` die engere Liste für `/admin/`, den Abschnitt für die dcm4chee-Oberfläche und jede Änderung; alle anderen
bekommen 403. Das Protokoll nennt dann den PC (`anon-<Adresse>`), nie eine Person, und jeder innerhalb einer Liste kann alles, was
diese Liste erlaubt. Hinter einem SSH-Tunnel zu einem auf 127.0.0.1 veröffentlichten Port sieht nginx die Adresse des
Docker-Gateways, nicht die des eigenen PCs: nur diese Adresse erlauben
(`docker network inspect NETWORK -f '{{(index .IPAM.Config 0).Gateway}}'`, zum Beispiel `allow 172.18.0.1;`), nie einen Bereich
wie `172.16.0.0/12`, der jedes Docker-Netz des Hosts enthält. Die Seite zeigt oben `anon-<Adresse>`.

<a id="viewer"></a>
### Viewer

**ohif**: liefert die OHIF-Dateien des Images aus (`/usr/share/nginx/html`, `app-config.js` aus dem eigenen Mount) und erlaubt die
DICOMweb-Lesezugriffe, die der Viewer braucht (Studien, Serien, Instanzen, WADO), nur mit GET. **none**: `/` leitet auf `/admin/` um,
Serien, Instanzen und WADO geben 404 (die Admin-Seite braucht nur die Studiensuche, die Patientenliste und die Ansicht abgelehnter
Studien, die beide Modi haben). In `web/admin/config.js` `viewerUrl: ''` setzen, um den Link `Viewer` auszublenden.

<a id="listener"></a>
### Listener

**tls**: `listen 8443 ssl` mit `http2 on` (nginx 1.25.1 oder neuer; bei einem älteren nginx, zum Beispiel Debian 12 mit 1.22, diese
Zeile löschen und `ssl http2` in die Zeile `listen` schreiben; geprüft auf 1.22: `nginx -t`, HTTP/2 und die Umleitung), TLS 1.2 und
1.3 und ein zweiter Server auf 8080, der http auf https umleitet. Zertifikat und Schlüssel (`ssl_certificate`, `ssl_certificate_key`, die letzten beiden Zeilen von `listener/server.conf`) liest der nginx-Master-Prozess beim
Start, daher hängen die Rechte des Schlüssels vom Image ab. Viewer `ohif` (das OHIF-Image, sein nginx-Master läuft als uid 101):
`chown root:101 server.key && chmod 640 server.key`. Viewer `none` (Standard-Image `nginx`) und nginx auf dem Host (der Master ist
root): `chown root:root server.key && chmod 600 server.key`. `docker exec ohif id` zeigt, welcher Fall vorliegt. Standardmäßig
kein HSTS; die optionale Zeile steht am Ende von `common/headers.conf` (nur mit einem echten Zertifikat).

**plain**: `listen 8080`, kein TLS, nur für einen ersten Blick durch einen SSH-Tunnel (`ssh -L 8080:127.0.0.1:8080 user@server`,
auf beiden Seiten **derselbe** Port: Der Browser setzt ihn in den Referer, und die Regel des Abschnitts für die
dcm4chee-Oberfläche nennt `:8080`). Auf jedem anderen Weg wären Passwörter und Patientendaten lesbar; nie in einem Netz
veröffentlichen.

**behind-proxy**: `listen 8080` plus `set_real_ip_from <Adresse oder Netz des Proxys>`, `real_ip_header X-Forwarded-For`,
`real_ip_recursive on`. Der Proxy beendet TLS und muss `Host` unverändert weitergeben (Apache: `ProxyPreserveHost On`) und die
Client-Adresse in `X-Forwarded-For` (Traefik, Caddy und Cloudflare Tunnel tun das). nginx darf **nur** vom Proxy aus erreichbar
sein (kein veröffentlichter Port, ein Docker-Netz, das mit dem Proxy geteilt wird): Von überall sonst wäre `X-Forwarded-For` eine
Fälschung. Die mitgelieferte Adresse `203.0.113.1` vertraut niemandem, bis sie ersetzt ist. Das Protokoll, `X-Real-IP` für den Hilfsdienst (Prüfung der Firewall gegen Aussperren), die Netzlisten des
Anmeldeverfahrens `none` und die Aufrufe an oauth2-proxy nutzen dann die echte Client-Adresse. Lauscht der Proxy auf einem anderen
Port als 443, diesen in die Referer-Regel in `listener/http.conf` eintragen.

<a id="dcm4chee-ui"></a>
### Abschnitt für die dcm4chee-Oberfläche (optional)

`optional/dcm4chee-ui.conf` macht die Benutzeroberfläche von dcm4chee (`/dcm4chee-arc/ui2/`) für Admins hinter derselben Anmeldung
nutzbar, ohne Keycloak. Dafür wird ein arc ohne Keycloak gebraucht (nicht die `-secure`-Images). nginx erkennt Aufrufe der
Oberfläche am Referer `<Schema>://<Host>/dcm4chee-arc/ui2/` (derselbe Host, kein anderer Port, siehe die Listener-Dateien) und
schickt sie in eine Location, in der alles erlaubt ist; die Sperren der Admin-Seite gelten dort nicht. Änderungen, die dort gemacht
werden, stehen mit dem Konto im Protokoll. Abschalten: `rm $T/pacs/optional/dcm4chee-ui.conf` und neu laden; ohne die Datei gibt
jeder Aufruf der Oberfläche 404.

<a id="host-nginx"></a>
## nginx auf dem Host statt in einem Container

Dieselben Dateien, andere Pfade. Der Hilfsdienst und nginx müssen sich über die uid der nginx-Worker einig sein: Auf Debian ist das
`www-data` (33), also `PACS_SOCKET_UID=33` in `/etc/default/pacs-admin`, danach `systemctl restart pacs-verwaltung`. Der Hilfsdienst
warnt, dass `www-data` mit anderen Programmen geteilt wird; läuft PHP oder eine andere Webanwendung als `www-data`, stattdessen
nginx ein eigenes Konto zuweisen (`useradd -r -s /usr/sbin/nologin pacsweb`, `user pacsweb;` in `nginx.conf`,
`PACS_SOCKET_UID=<seine uid>`). arc muss auf `127.0.0.1:8080` veröffentlicht sein. Die OHIF-Dateien gehören nicht zum nginx der
Distribution: den Viewer `none` nutzen oder die Dateien selbst aus dem OHIF-Image kopieren. Es braucht nginx 1.25.1 oder neuer
(Debian 13 hat 1.26; Debian 12 hat 1.22: siehe die Zeile `http2` beim Listener `tls`).

<!-- lab:host -->
```bash
apt-get install -y nginx openssl            # as root; Debian 13: nginx 1.26, user www-data
rm -f /etc/nginx/sites-enabled/default      # else "a duplicate default server for 0.0.0.0:80"
N=/opt/pacs-admin/deploy/nginx
T=/etc/nginx/conf.d
mkdir -p $T/pacs/login $T/pacs/listener $T/pacs/optional
cp $N/pacs.conf $T/pacs.conf
cp $N/site.conf.example $T/pacs/site.conf
cp $N/common/*.conf $T/pacs/
cp $N/optional/dcm4chee-ui.conf $T/pacs/optional/
cp $N/login/basic/*.conf $T/pacs/login/                 # or oauth2-proxy (then set $pacs_auth to http://127.0.0.1:4180)
cp $N/viewer/none.conf $T/pacs/viewer.conf
cp $N/listener/tls/*.conf $T/pacs/listener/
sed -i -e 's/8080/80/g' -e 's/8443/443/g' $T/pacs/listener/*.conf      # host ports instead of the container ports
sed -i -e 's#^set \$arc .*#set $arc http://127.0.0.1:8080;#' -e '/^resolver /d' $T/pacs/site.conf
mkdir -p /srv/pacs-admin /var/lib/pacs-admin/status                     # the page and status.json where pacs.conf looks
ln -sfn /opt/pacs-admin/web/admin /srv/pacs-admin/admin
ln -sfn /var/lib/pacs-admin/status /srv/pacs-admin/status
```

Danach `site.conf` bearbeiten (`server_name`, die Admin-Gruppe für oauth2-proxy), die Zertifikatsdateien dorthin legen, wohin
`listener/server.conf` zeigt (der Schlüssel `root:root 0600`: Der Master-Prozess ist root), die htpasswd-Dateien in `/etc/nginx/htpasswd/`
anlegen (`chown root:www-data`, `chmod 640`) und `nginx -t && systemctl reload nginx` ausführen. Die Ports 80 und 443 des Hosts
filtert der Reiter Firewall der Admin-Seite nicht (er filtert Docker). Startreihenfolge: `pacs-verwaltung` sollte vor nginx
laufen, sonst gehen Protokollzeilen verloren, bis die Sockets existieren (`Wants=` und `After=pacs-verwaltung.service` in einem
Drop-in von `nginx.service`; nicht getestet).

<a id="ae-titles"></a>
## AE-Titel

Die AE-Titel `DCM4CHEE` (Archiv) und `IOCM_QUALITY` (Ansicht abgelehnter Studien) stehen in genau zwei Dateien ausgeschrieben, und
nur dort: `pacs.conf` (die Ereignis-Map und die Locations) und `pacs/viewer.conf` (nur Viewer `ohif`; der Viewer `none` hat keine).
`99DCM4CHEE` ist ein Coding-Scheme, kein AE-Titel, und muss bleiben. Umbenennen (das tut `bash deploy/tools/set-aet.sh`):

```bash
for f in $T/pacs.conf $T/pacs/viewer.conf; do
  sed -E -i -e 's/99DCM4CHEE/@@CODING@@/g' -e 's/DCM4CHEE/MYARC/g' -e 's/IOCM_QUALITY/MYARC_REJ/g' -e 's/@@CODING@@/99DCM4CHEE/g' $f
done
```

Die Namen müssen zu `aet` und `iocmAet` in `web/admin/config.js` und zu `ARC_AET` in `/etc/default/pacs-admin` passen.

<a id="upgrade"></a>
## Änderungen gegenüber der alten Einzeldatei `deploy/nginx.conf.example`

Wer die alte Datei betreibt: Das Compose-Volume `./nginx.conf:/etc/nginx/conf.d/default.conf:ro` wird zu
`./nginx:/etc/nginx/conf.d:ro` (der Ordner dieser Anleitung), die Werte, die in der alten Datei bearbeitet wurden, wandern in
`pacs/site.conf` und in die Dateien, die unter [Platzhalter](#placeholders) genannt sind, und die Rechte des Schlüssels folgen dem
Listener `tls` (OHIF-Image `root:101 0640`, Standard-Image `nginx` oder Host `root:root 0600`).
Neues Verhalten: Eine Studie ändern und eine Studie verschieben geht nur noch mit genau der Abfrage, die die Admin-Seite sendet, ein
Pfad mit `;`, einem kodierten oder einem rohen Backslash gibt 400, `Authorization` und `Cookie` erreichen arc und den Hilfsdienst nicht mehr, Uploads über den Abschnitt für
die dcm4chee-Oberfläche funktionieren über 1 MB (die Unteranfrage von `auth_request` bekam `client_max_body_size 0`), das Konto im
Protokoll ist nie leer, `Server` zeigt keine Version.

<a id="guarantees"></a>
## Was die Konfiguration garantiert

- Jede schreibende Anfrage hat eine Sperre (siehe die Kommentare in `pacs.conf`). Eine Studienänderung nimmt genau die Abfrage
  an, die die Admin-Seite sendet: `reasonForModification=` und eine `StudyInstanceUID` aus Ziffern und Punkten, sonst nichts. Eine
  Studienverschiebung nimmt genau `PatientID`, wahlweise `IssuerOfPatientID`, und `updatePolicy=PRESERVE` an. Eine
  Patientenänderung trägt nie `merge` und nie ein Prozentzeichen in einem Parameternamen. Endgültig gelöscht wird nur über
  `IOCM_QUALITY`, abgelehnt, zurückgeholt und zusammengeführt nur über die aufgelisteten Aufrufe. Jede Änderung braucht den Header
  `X-PACS-Admin`, den nur die Admin-Seite setzt. Die beiden Studien-Sperren nennen, was erlaubt ist, weil eine Liste des Verbotenen
  nie vollständig wäre: Eine zweite `StudyInstanceUID` oder eine Kommaliste in einer kann mehrere Studien auswählen.
  `studyinstanceuid=`, eine zweite `StudyInstanceUID`, eine Kommaliste, die Hex-Form `0020000D=`, `Study%49nstanceUID`, `merge=0`
  und jeder andere zusätzliche Parameter geben alle 403. Die Sperren antworten vor der Anmeldeprüfung: Eine falsche Abfrage
  bekommt auch ohne Anmeldung 403.
- Ein `;`, ein kodierter oder ein roher Backslash im Pfad gibt 400 (nginx normalisiert Pfadparameter nicht, der Upstream unter
  Umständen schon). Auch diese Antwort kommt vor der Anmeldeprüfung.
- `Authorization` und `Cookie` des Browsers erreichen arc und den Hilfsdienst nie; `X-Forwarded-For`, `X-Real-IP`, `X-Auth-User` und
  `X-PACS-Admin` zu ihnen hin setzt nginx, ein gefälschter Wert vom Browser wird ersetzt. Die Unteranfrage von `auth_request` und die
  Aufrufe an oauth2-proxy bekommen `X-Forwarded-For` und `X-Real-IP` von der verbindenden Adresse, nicht vom Browser.
- Das Protokoll hat die drei Tags `zugriffe`, `ereignisse`, `admin` mit den Feldnamen, die der Hilfsdienst und die Seite lesen (`t`,
  `u`, `sub`, `ip`, `r`, bei `admin` zusätzlich `m`, `uri`, `status`, `k`, `body`); `u` ist nie leer. Nach `docker logs` wird nichts
  geschrieben. Solange der Hilfsdienst steht oder neu startet, gehen Protokollzeilen verloren (auch die erste Zeile jedes
  nginx-Workers nach einem Neustart).
- Header für die Cross-Origin-Isolation (`COOP`, `COEP`, `CORP`) auf der Seite, dem Viewer und den Admin-Aufrufen;
  `server_tokens off`; standardmäßig kein HSTS.
- Locations, die vor jeder Anmeldeprüfung mit einem festen Text antworten (die Umleitung `/admin`, die Umleitung `/dcm4chee`, das 404
  von `/dcm4chee-arc/`, das Einstiegsskript und `keycloak.json` des Abschnitts für die dcm4chee-Oberfläche, `/` beim Viewer `none`,
  die Anmelde-Endpunkte von oauth2-proxy), sind absichtlich öffentlich und enthalten keine Daten.

<a id="checks"></a>
## Prüfungen und Fehlersuche

```bash
grep -rn CHANGE-ME /opt/ohif/nginx        # must print nothing
docker exec ohif nginx -t                 # syntax ok / test successful
docker exec ohif nginx -T | grep -n 'location '    # the loaded locations
docker logs ohif 2>&1 | tail              # why the container does not start
curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/            # no login: oauth2-proxy 302, basic 401, none 403 (outside the list)
curl -sk -u anna -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/    # login basic, an admin account: 200
```

Die Kommentare im Block, übersetzt: Der `grep` darf nichts ausgeben. `nginx -t` meldet `syntax is ok` und `test is successful`.
`nginx -T | grep` zeigt die geladenen Locations. `docker logs` zeigt, warum der Container nicht startet. Das erste `curl` (ohne
Anmeldung) liefert bei `oauth2-proxy` 302, bei `basic` 401 und bei `none` 403 (außerhalb der Liste), das zweite (Anmeldeverfahren
`basic`, ein Admin-Konto) liefert 200.

| Symptom | Ursache und Behebung |
|---|---|
| Container startet nicht, `[emerg] open() "/etc/nginx/conf.d/pacs/..." failed` | ein Ordner oder eine Datei aus Schritt 1 bis 4 wurde nicht kopiert |
| `unknown directive "http2"` | nginx älter als 1.25.1: siehe Listener `tls` |
| `no "ssl_certificate" is defined` / `cannot load certificate` | Zertifikatsdateien fehlen oder die Pfade am Ende von `listener/server.conf` sind falsch, oder der Master-Prozess darf den Schlüssel nicht lesen (nur der Master liest ihn), siehe Listener `tls` |
| `unknown "pacs_dcm4chee_ui" variable` | der Ordner des Listeners wurde nicht kopiert (`listener/http.conf`) |
| jede Seite antwortet mit 500, das Log sagt `could not be resolved` | der Name in `set $arc` / `set $pacs_auth` ist falsch, oder der Container ist nicht in diesem Docker-Netz |
| Anmeldeverfahren `basic`: eine Anfrage mit Passwort antwortet 403 oder 500 | `/etc/nginx/htpasswd/users` oder `admins` fehlt (403) oder ist für den Worker nicht lesbar (500); Log: `open() ... failed` |
| Anmeldeverfahren `oauth2-proxy`: `/admin/` ist für einen Admin 403 | die Gruppe in `site.conf` ist nicht die im Token (`/oauth2/userinfo` ansehen), oder der Platzhalter steht noch da |
| 502 auf `/admin/dienst/`, Protokollzeilen fehlen | der Hilfsdienst läuft nicht, oder `PACS_SOCKET_UID` ist nicht die uid der nginx-Worker |
| Upload über die dcm4chee-Oberfläche scheitert über 1 MB mit 500 | alte Einzeldatei-Konfiguration: Die Unteranfrage von `auth_request` hatte ein eigenes Größenlimit für den Body (hier behoben) |
| die dcm4chee-Oberfläche gibt bei jedem Aufruf 404 | der Referer passt nicht: anderer Hostname oder Port, als der Listener erwartet, oder die optionale Datei fehlt |

<a id="lab"></a>
## Testlabor

Die Konfiguration wurde mit einem Wegwerf-Labor aus Containern geprüft (die Laborskripte bleiben bei den Betreuern des Projekts und
werden auf keinem PACS-Server installiert): der echte Hilfsdienst, eine Attrappe für arc, die zurückgibt, was bei ihr ankommt, eine
Attrappe für oauth2-proxy, der nginx unter Test, ein zweiter nginx, dessen Socket zum Hilfsdienst ein Echo ist, ein Proxy davor für
`behind-proxy` und ein Client, der eine Testmatrix abarbeitet (etwa 370 Prüfungen pro Rezept: jede Sperre, die Referer-Regel, das
Entfernen von Headern, das Protokoll von der Anfrage bis zur Datenbank, die Anzeige des Kontonamens und eine Prüfung, dass jede
Location aus `nginx -T` eine Anmeldepflicht hat oder auf der öffentlichen Liste steht). Die Rezepte heißen `login-viewer-listener`:
`run.sh oauth2-ohif-tls`, `basic-ohif-tls`, `basic-none-plain`, `none-none-plain`, `oauth2-ohif-proxy` und die anderen
Kombinationen, dazu `run.sh nginx-t` (`nginx -t` und die Prüfung auf CHANGE-ME für alle 18 Kombinationen, mit und ohne die Datei für
die dcm4chee-Oberfläche), `host` und `debian12` (nginx der Distribution), `keymode` (wer den TLS-Schlüssel lesen können muss), `aet`
(Umbenennung des AE-Titels) und `oauth2-group` (Platzhalter oder leere Admin-Gruppe). Ein Rezept baut auf, testet und räumt alles
wieder ab; alles, was es anlegt, heißt `pacsadm-nginx-*`.
