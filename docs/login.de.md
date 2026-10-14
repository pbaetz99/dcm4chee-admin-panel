# Anmeldung: so melden sich Benutzer an

[English](login.md) | Deutsch

nginx prüft jede Anfrage an den Viewer, an die Admin-Seite und an dcm4chee. Diese Prüfung ist die **Anmeldung**. Diese Seite
listet jede unterstützte Anmeldung, hilft bei der Wahl, richtet die gewählte Schritt für Schritt ein und nennt die Wege, die
nicht funktionieren.

Alle Befehle als root ausführen. Jeder Schritt endet mit einem **Prüfen**-Kasten, der zeigt, woran man erkennt, dass der Schritt
gewirkt hat. Ein **Warnung**-Kasten nennt, was Benutzer aussperren kann.

Ein Rezept (eine Compose-Datei und ein Satz nginx-Dateien) wählt man in [install.de.md](install.de.md). Jedes Rezept enthält
genau eine Anmeldung. Diese Seite behandelt, was zur Anmeldung gehört: Konten, Geheimnisse und Prüfungen.

- [1. Eine Anmeldung wählen](#login-choose)
- [2. Anmeldung mit oauth2-proxy: Entra ID, Keycloak, Authentik, Authelia, Zitadel, Google, GitHub](#login-oauth2)
- [3. Anmeldung mit Basic-Authentifizierung: Benutzername und Passwort in nginx](#login-basic)
- [4. Keine Anmeldung: Netzlisten](#login-none)
- [5. Andere Eingangstüren: Traefik, Caddy, Apache, Cloudflare Tunnel](#login-other)
- [6. Nicht unterstützt](#login-unsupported)
- [7. Wer was öffnen darf](#login-access)
- [8. Was das Protokoll aufzeichnet](#login-audit)

<a id="login-choose"></a>
## 1. Eine Anmeldung wählen

Jede Anmeldung kennt zwei Stufen. Ein **Viewer** darf den Viewer öffnen und nach Studien suchen. Ein **Admin** darf zusätzlich die
Admin-Seite (`/admin/`) öffnen und Daten ändern. Die Verfahren unterscheiden sich darin, wie sie die Stufe festlegen.

| Anmeldung | Single Sign-on | Zweiter Faktor (MFA) | Viewer und Admin | Kontoname im Protokoll | Abmeldung | Man braucht | Aufwand |
|---|---|---|---|---|---|---|---|
| oauth2-proxy mit Entra ID | Ja | Ja, in Entra eingestellt | Zwei Entra-Gruppen | Der Entra-Benutzername | Link oben auf der Admin-Seite (eine Einstellung) | Entra-Rechte, DNS-Name, Zertifikat, oauth2-proxy-Container | Hoch |
| oauth2-proxy mit Keycloak, Authentik, Authelia oder Zitadel | Ja | Ja, im Anbieter eingestellt | Gruppen oder Rollen des Anbieters | Benutzername, sonst E-Mail-Adresse, sonst die ID des Anbieters | Link (siehe oben) | Ein laufender Anbieter, DNS-Name, Zertifikat, oauth2-proxy-Container. Hier nicht getestet | Hoch |
| oauth2-proxy mit Google oder GitHub | Ja | Ja, bei Google oder GitHub eingestellt | Google: keine Gruppen, Admins stehen in einer Liste von E-Mail-Adressen. GitHub: Teams einer Organisation | E-Mail-Adresse (GitHub: der Login-Name, wenn es keine E-Mail-Adresse gibt) | Link (siehe oben) | Eine OAuth-App bei Google oder GitHub, DNS-Name, Zertifikat, oauth2-proxy-Container. Hier nicht getestet | Mittel |
| basic | Nein | Nein | Zwei Dateien: alle Konten und die Admins | Der Kontoname, den man angelegt hat | Keine. Den Browser schließen | TLS-Zertifikat (Pflicht), openssl | Niedrig |
| none | Keine Anmeldung | Nein | Zwei Netzlisten: Viewer-PCs und Admin-PCs | Nur die Adresse des PCs | Entfällt | Ein geschlossenes Netz mit PCs, denen man vertraut | Am niedrigsten |

**Single Sign-on** heißt, dass Benutzer sich einmal mit dem Konto ihrer Organisation anmelden und für das PACS kein neues
Passwort bekommen. **MFA** (Multi-Faktor-Authentifizierung, englisch multi-factor authentication) heißt ein zweiter Nachweis
neben dem Passwort, zum Beispiel ein Code in einer Telefon-App. oauth2-proxy macht selbst keine MFA. Das macht der
Identitätsanbieter.

### Welche passt zu mir

- Die Organisation nutzt Microsoft 365 oder Entra ID: oauth2-proxy mit Entra ID nehmen. Die Benutzer behalten ihr eigenes Passwort
  und ihren zweiten Faktor. Eine Person entfernt man, indem man sie aus einer Gruppe entfernt.
- Es läuft schon ein anderer Identitätsanbieter, der OpenID Connect spricht: oauth2-proxy mit diesem Anbieter nehmen.
- Es gibt keinen Identitätsanbieter und nur wenige Benutzer, zum Beispiel in einer kleinen Praxis oder auf einem Testsystem:
  basic nehmen. Außerhalb des Servers wird nichts gebraucht.
- Es gibt ein geschlossenes Netz, feste PCs, denen man vertraut, und keinen Wunsch nach Konten: none nehmen. Das Protokoll nennt
  dann PCs, keine Personen.
- Die Entscheidung fällt schwer: mit basic beginnen. Die Anmeldung lässt sich später ändern. Die Anmeldung besteht aus vier kleinen
  nginx-Dateien und wenigen Zeilen in der Compose-Datei ([deploy/nginx/README.de.md](../deploy/nginx/README.de.md) listet sie).

Bei jeder Anmeldung https zwischen Browser und PACS benutzen. Ohne https kann jeder auf dem Netzweg Passwörter,
Sitzungs-Cookies und Patientendaten mitlesen. Die einzige Einrichtung mit reinem http ist das Rezept `tryit`: Sein Port lauscht
nur auf 127.0.0.1, und der Browser erreicht ihn über einen SSH-Tunnel (siehe [install.de.md](install.de.md)).

<a id="login-oauth2"></a>
## 2. Anmeldung mit oauth2-proxy

### 2.1 So funktioniert es

oauth2-proxy ist ein kleines Programm, das Benutzer bei einem [Identitätsanbieter](glossary.de.md#identity-provider) anmeldet.
Ein Identitätsanbieter ist ein Dienst, der die Benutzer kennt und ihre Passwörter prüft, zum Beispiel Microsoft Entra ID,
Keycloak oder Google. oauth2-proxy spricht mit ihm über [OpenID Connect](glossary.de.md#oidc) (OIDC). Es läuft als Container
`ohif-auth`. Es hat keinen Port außerhalb des Docker-Netzes. Der Benutzer tippt das Passwort nur beim Identitätsanbieter ein,
nie beim PACS.

nginx fragt oauth2-proxy bei jeder Anfrage:

```text
 Browser            nginx (ohif)        oauth2-proxy (ohif-auth)      Identitätsanbieter
    |  GET /admin/      |                        |                          |
    |------------------>|  angemeldet? Admin?    |                          |
    |                   |----------------------->|                          |
    |                   |  keine Sitzung: 401    |                          |
    |  zur Anmeldung    |<-----------------------|                          |
    |<------------------|                        |                          |
    |  der Benutzer meldet sich beim Anbieter an                            |
    |<--------------------------------------------------------------------->|
    |  zurück zu /oauth2/callback: oauth2-proxy setzt ein Cookie            |
    |------------------>|----------------------->|                          |
    |  GET /admin/      |  angemeldet? Admin?    |                          |
    |------------------>|----------------------->|                          |
    |                   |  ja: 202 + Konto       |                          |
    |  die Seite        |<-----------------------|                          |
    |<------------------|                        |                          |
```

oauth2-proxy antwortet mit einem Statuscode. 202 heißt ja. 401 heißt, dass keine Sitzung besteht. 403 heißt, dass der Benutzer
angemeldet, aber nicht erlaubt ist. Der Identitätsanbieter teilt oauth2-proxy auch die Gruppen des Benutzers mit. Die Gruppen
entscheiden die Stufe:

- **Viewer-Stufe:** Der Benutzer ist in einer der Gruppen, die die Compose-Datei mit `--allowed-group` aufführt
  ([Jedes Konto](glossary.de.md#any-account)).
- **Admin-Stufe:** Der Benutzer ist in der einen Admin-Gruppe, die `pacs/site.conf` nennt (`$pacs_admin_group`). Die Admin-Gruppe
  ist auch eine der `--allowed-group`-Zeilen, ein Admin braucht also nur die Admin-Gruppe.

Die Admin-Gruppe muss an diesen beiden Stellen identisch geschrieben sein. Das ist der häufigste Fehler.

**Was getestet wurde.** Die Anmeldungen `basic` und `none` liefen in Docker mit den nginx-Dateien dieses Repositorys. Die
Ausgaben in [Abschnitt 3](#login-basic) und [Abschnitt 4](#login-none) stammen aus diesen Läufen. Die Anmeldung `oauth2-proxy`
wurde ohne Anbieter geprüft: `nginx -t` auf den zusammengesetzten Dateien, `docker compose config` und die Änderungsbefehle der
Schritte 8 und 9 auf Kopien der Dateien, dazu ein kleiner Ersatz vor nginx, der wie oauth2-proxy antwortet (202, 401 oder 403).
Ein echtes oauth2-proxy und ein echter Identitätsanbieter liefen nicht. Entra ID ist die Einrichtung, für die dieses Projekt
geschrieben wurde. Jeder andere Anbieter in [2.6](#login-oauth2-providers) stammt aus der Dokumentation von oauth2-proxy und des
Anbieters. Jeder davon ist mit „hier nicht getestet“ markiert. Eine Ausgabe, die nur ein echter Anbieter erzeugen kann, ist mit
„nicht gegen einen echten Anbieter ausgeführt“ markiert.

### 2.2 Vor dem Start

- Der DNS-Name des PACS (hier `pacs.example.org`) zeigt auf den Server, und das https-Zertifikat liegt bereit
  ([install.de.md#tls-certificate](install.de.md#tls-certificate)). Grund: Eine [Redirect-URI](glossary.de.md#redirect-uri) ist
  die Adresse, an die der Anbieter den Browser nach der Anmeldung zurückschickt. Anbieter akzeptieren für einen echten Host-Namen
  nur https-Adressen. Darum kommen der DNS-Name und das Zertifikat zuerst.
- Die Compose-Datei des Rezepts `oauth2-proxy` ist `/opt/ohif/docker-compose.yml`, und die nginx-Dateien dieser Anmeldung liegen
  in `/opt/ohif/nginx` ([install.de.md](install.de.md)).

> **Prüfen**
>
> ```bash
> grep -m1 -o 'Login [a-z0-9-]*' /opt/ohif/nginx/pacs/login/http.conf
> ls /opt/ohif/docker-compose.yml /opt/ohif/nginx/pacs/site.conf
> ```
>
> Erwartet:
>
> ```text
> Login oauth2-proxy
> /opt/ohif/docker-compose.yml
> /opt/ohif/nginx/pacs/site.conf
> ```
>
> Steht in der ersten Zeile `Login basic` oder `Login none`, wurden die Dateien einer anderen Anmeldung kopiert. Zurück zu
> [install.de.md](install.de.md) gehen und die Dateien der Anmeldung `oauth2-proxy` kopieren.

<a id="login-oauth2-entra"></a>
### 2.3 Entra ID, Schritt für Schritt

Man arbeitet im Entra Admin Center (https://entra.microsoft.com). Microsoft ändert das Portal von Zeit zu Zeit, darum kann eine
Schaltfläche etwas anders heißen. Die Namen von Menüs, Schaltflächen und Rollen stehen hier in Englisch, so wie die englische
Oberfläche des Portals sie zeigt. Zeigt das Portal Deutsch, heißen sie übersetzt. Die Seiten von Microsoft sind die Referenz
(beide englisch): [App registrieren](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app),
[Gruppen-Claims](https://learn.microsoft.com/en-us/entra/identity-platform/optional-claims#configure-groups-optional-claims).

**Nötige Rechte.** Die Rollen sind die, die die Microsoft-Dokumentation als Minimum nennt. Eine Person mit mehreren Rollen kann
alle Schritte ausführen. Fehlt eine Rolle, die Entra-Administration bitten, diesen Schritt zu übernehmen und die Werte der Tabelle
in Schritt 6 zu schicken.

| Aufgabe | Rolle (mindestens) |
|---|---|
| Die App registrieren (Schritt 1) | Application Developer |
| Token configuration, API permissions, Administratorzustimmung (Schritte 3 und 5) | Cloud Application Administrator |
| Gruppen anlegen und Mitglieder hinzufügen (Schritt 4) | Groups Administrator |

#### Schritt 1. Die App registrieren

Eine App-Registrierung sagt Entra, dass oauth2-proxy Benutzer anmelden darf und wohin sie danach zurückgeschickt werden.

1. Entra ID > App registrations öffnen und New registration wählen.
2. Name: `PACS`. Die Benutzer sehen diesen Namen auf der Anmeldeseite.
3. Supported account types: Single tenant only.
4. Redirect URI: Plattform Web, Wert `https://pacs.example.org/oauth2/callback`. Den eigenen Host-Namen einsetzen. Der Pfad
   `/oauth2/callback` ist fest.
5. Register wählen.

> **Prüfen**
>
> Die Seite Overview der neuen App zeigt zwei Werte: Application (client) ID (deutsch Anwendungs-ID (Client)) und Directory
> (tenant) ID (deutsch Verzeichnis-ID (Mandant)). Unter Manage > Authentication führt der Abschnitt Web
> `https://pacs.example.org/oauth2/callback` auf.
>
> Zeigt Microsoft bei der Anmeldung später den Fehler AADSTS50011, weicht die Redirect-URI von der ab, die oauth2-proxy sendet:
> siehe [Fehlersuche](troubleshooting.de.md#login-redirect-uri-mismatch).

#### Schritt 2. Das Client-Geheimnis anlegen

oauth2-proxy beweist Entra mit dem [Client-Geheimnis](glossary.de.md#client-secret), dass es die registrierte App ist. Das
Geheimnis ist ein Passwort für ein Programm.

1. Manage > Certificates & secrets > Client secrets > New client secret öffnen.
2. Description: `PACS`. Die Gültigkeitsdauer des Geheimnisses wählen.
3. Add wählen.
4. Den **Value** sofort kopieren. Das Portal zeigt ihn nur jetzt. Die Spalte Secret ID ist nicht das Geheimnis.
5. Das Ablaufdatum in einen Kalender eintragen.

> **Warnung**
>
> Läuft das Geheimnis ab, kann sich niemand mehr anmelden. Zwei Wochen vor dem Datum ein neues Geheimnis anlegen und es
> austauschen, wie in [2.5](#login-oauth2-operate) beschrieben. Wird statt des Value die Secret ID kopiert, scheitert die
> Anmeldung auf dieselbe Weise.

> **Prüfen**
>
> Die Liste unter Client secrets zeigt eine Zeile mit der eigenen Beschreibung, einem Ablaufdatum und einem Value, der verborgen
> ist. Ein späterer Anmeldefehler zum Client-Geheimnis (AADSTS7000215 oder AADSTS7000222) bedeutet ein falsches oder abgelaufenes
> Geheimnis: siehe [Fehlersuche](troubleshooting.de.md#login-client-secret).

#### Schritt 3. Den Groups-Claim hinzufügen

Ein [Claim](glossary.de.md#claim) ist eine Angabe, die Entra nach der Anmeldung in das Token schreibt. Der Claim `groups` listet
die Gruppen des Benutzers. oauth2-proxy liest ihn, um die Stufe zu entscheiden.

1. Manage > Token configuration > Add groups claim öffnen.
2. Security groups wählen.
3. Group ID für das ID token beibehalten. Entra schreibt dann die Objekt-ID (eine GUID) jeder Gruppe in das Token, nicht den
   Namen. Objekt-IDs ändern sich nie. Namen können sich ändern.
4. Save wählen.

> **Prüfen**
>
> Die Seite Token configuration listet den Claim `groups` für das ID token.
>
> Entra schreibt höchstens 200 Gruppen in ein Token. Benutzer in mehr Gruppen brauchen eine andere Einstellung: siehe
> [2.4](#login-oauth2-overage).

#### Schritt 4. Zwei Gruppen anlegen

1. Entra ID > Groups > New group öffnen. Group type: Security. Name: `PACS Viewer`. Die Personen hinzufügen, die den Viewer öffnen
   dürfen.
2. Eine zweite Sicherheitsgruppe `PACS Admin` anlegen. Die Personen hinzufügen, die auch `/admin/` öffnen dürfen.
3. Jede Gruppe öffnen. Auf ihrer Seite Overview die Object ID kopieren.

Ein Admin muss nicht in der Viewer-Gruppe sein. Jede einzelne der aufgeführten Gruppen lässt einen Benutzer ein.

> **Prüfen**
>
> Beide Gruppen zeigen eine Object ID, die so aussieht: `aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee`.

#### Schritt 5. Zustimmung

Bei der ersten Anmeldung kann Microsoft den Benutzer fragen, ob die App das Basisprofil lesen darf (Berechtigung `User.Read`, die
jede neue Registrierung hat). In den meisten Tenants dürfen Benutzer selbst zustimmen. Erlaubt der eigene Tenant das nicht,
verlangt die Anmeldeseite einen Administrator. Dann öffnet ein Administrator App registrations > PACS > API permissions und
wählt die Schaltfläche Grant admin consent for mit dem Namen des eigenen Tenants.

> **Prüfen**
>
> Unter API permissions zeigt die Spalte Status für `User.Read` „Granted for“ und den Namen des eigenen Tenants. Das wird nur
> gebraucht, wenn die Anmeldung nach einem Administrator gefragt hat.

#### Schritt 6. Wohin welcher Wert gehört

| Wert | Wo man ihn findet | Datei | Stelle |
|---|---|---|---|
| Host-Name | Der eigene DNS-Name | `docker-compose.yml`, `nginx/pacs/site.conf` | `--redirect-url` und `server_name` (und die Redirect-URI in Schritt 1) |
| Directory (tenant) ID | Overview der App-Registrierung | `docker-compose.yml` | In `--oidc-issuer-url` |
| Application (client) ID | Overview der App-Registrierung | `ohif-auth.env` | `OAUTH2_PROXY_CLIENT_ID` |
| Value des Client-Geheimnisses | Certificates & secrets (wird nur einmal gezeigt) | `ohif-auth.env` | `OAUTH2_PROXY_CLIENT_SECRET` |
| Object ID der Viewer-Gruppe | Overview der Gruppe | `docker-compose.yml` | Das erste `--allowed-group` |
| Object ID der Admin-Gruppe | Overview der Gruppe | `docker-compose.yml` und `nginx/pacs/site.conf` | Das zweite `--allowed-group` und `$pacs_admin_group`. Derselbe Wert an beiden Stellen |

Alle Dateien liegen in `/opt/ohif`.

<a id="login-oauth2-env"></a>
#### Schritt 7. ohif-auth.env anlegen

`ohif-auth.env` enthält die drei Geheimnisse von oauth2-proxy. Die Befehle unten fragen nach den zwei Werten, die aus dem Portal
kopiert wurden, und erzeugen den dritten. Kein Befehl gibt ein Geheimnis aus, und keiner lässt einen Platzhalter in der Datei.
Das Tippen des Geheimnisses bleibt unsichtbar.

Jeden der drei folgenden Blöcke einzeln einfügen und Enter drücken. Ein Block, der eine Frage stellt, würde sonst die nächste
eingefügte Zeile als Antwort nehmen.

```bash
read -r -p 'Application (client) ID: ' CLIENT_ID
```

```bash
read -r -s -p 'Client secret VALUE (typing is hidden): ' CLIENT_SECRET; echo
```

```bash
COOKIE_SECRET=$(python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())')
{
  printf 'OAUTH2_PROXY_CLIENT_ID=%s\n' "$CLIENT_ID"
  printf 'OAUTH2_PROXY_CLIENT_SECRET=%s\n' "$CLIENT_SECRET"
  printf 'OAUTH2_PROXY_COOKIE_SECRET=%s\n' "$COOKIE_SECRET"
} > /opt/ohif/ohif-auth.env
chmod 600 /opt/ohif/ohif-auth.env
unset CLIENT_ID CLIENT_SECRET COOKIE_SECRET
```

Das [Cookie-Geheimnis](glossary.de.md#cookie-secret) verschlüsselt das Sitzungs-Cookie von oauth2-proxy. Man muss es nie kennen.

> **Prüfen**
>
> ```bash
> ls -l /opt/ohif/ohif-auth.env
> cut -d= -f1 /opt/ohif/ohif-auth.env
> ```
>
> Erwartet: der Modus `-rw-------`, der Besitzer `root` und die drei Namen, ohne Werte:
>
> ```text
> OAUTH2_PROXY_CLIENT_ID
> OAUTH2_PROXY_CLIENT_SECRET
> OAUTH2_PROXY_COOKIE_SECRET
> ```
>
> Die ganze Datei nie ausgeben. Fehlt ein Name oder ist ein Wert falsch, die drei Blöcke noch einmal ausführen.

<a id="login-oauth2-edit"></a>
#### Schritt 8. Die Compose-Datei bearbeiten

Die Compose-Datei `/opt/ohif/docker-compose.yml` startet oauth2-proxy mit einer Liste von Optionen. Sechs Zeilen tragen die Marke
`CHANGE-ME`. Diese Zeilen auflisten:

```bash
grep -n 'CHANGE-M[E]' /opt/ohif/docker-compose.yml
```

Die Klammern verhindern, dass der Befehl seinen eigenen Text im Kopf der Datei findet. Die Ausgabe ist die Liste der sechs
Aufgaben:

```text
94:      - --oidc-issuer-url=https://login.microsoftonline.com/TENANT-ID/v2.0   # ENTRA: CHANGE-ME: Directory (tenant) ID
97:      - --allowed-group=VIEWER-GROUP-ID         # ENTRA: CHANGE-ME: Object ID of the group that may open the viewer
98:      - --allowed-group=ADMIN-GROUP-ID          # ENTRA: CHANGE-ME: Object ID of the admin group (also in site.conf)
114:      - --redirect-url=https://pacs.example.org/oauth2/callback   # CHANGE-ME: https://HOST/oauth2/callback
123:      - --trusted-proxy-ip=172.16.0.0/12        # CHANGE-ME: subnet of the Docker network
136:    name: dcm4chee-arc_default   # CHANGE-ME: name of that network (docker network ls; preflight.sh prints it)
```

| Zeile | Wert | Wo man ihn findet |
|---|---|---|
| 94 | Directory (tenant) ID | Overview der App-Registrierung (Schritt 1) |
| 97 | Object ID der Viewer-Gruppe | Overview der Gruppe (Schritt 4) |
| 98 | Object ID der Admin-Gruppe | Overview der Gruppe (Schritt 4) |
| 114 | Host-Name in der Redirect-URL | Der eigene DNS-Name (Schritt 1) |
| 123 | Subnetz des Docker-Netzes, das nginx und oauth2-proxy teilen | `docker network inspect NETZ -f '{{(index .IPAM.Config 0).Subnet}}'` |
| 136 | Name des Docker-Netzes von dcm4chee | `docker network ls` (preflight.sh gibt ihn aus) |

oauth2-proxy vertraut den Headern `X-Forwarded-*` nur, wenn sie aus dem Subnetz in Zeile 123 kommen. Das Netz ist das aus
Zeile 136. Der mitgelieferte Wert `172.16.0.0/12` deckt die üblichen Docker-Netze ab. Das Subnetz eintragen, das der Befehl zeigt.

Wurde der Netzname schon in der Installationsanleitung gesetzt ([Schritt 4.10](install.de.md#compose-file)), hat die Ausgabe
fünf Zeilen, und Zeile 136 fehlt. Dann `DOCKER_NETWORK` so lassen, wie es ist: Der `sed`-Ausdruck für diese Zeile findet nichts zu
ändern.

Die mit `# ENTRA` markierten Zeilen passen für Entra ID. Ein anderer Anbieter ersetzt sie ([2.6](#login-oauth2-providers)).

Die sechs Werte hinter den `=`-Zeichen setzen und den Block ausführen. Jede `-e`-Zeile ersetzt einen Wert und löscht den
Marker-Kommentar. Die Teile wie `'"$TENANT_ID"'` setzen die eigenen Werte in den Befehl ein.

```bash
TENANT_ID=CHANGE-ME-TENANT-ID
VIEWER_GROUP=CHANGE-ME-VIEWER-GROUP-ID
ADMIN_GROUP=CHANGE-ME-ADMIN-GROUP-ID
SERVER_NAME=CHANGE-ME-HOST-NAME
PROXY_SUBNET=CHANGE-ME-SUBNET
DOCKER_NETWORK=CHANGE-ME-NETWORK-NAME
sed -E -i \
  -e 's|(--oidc-issuer-url=https://login\.microsoftonline\.com/)[^/ ]+|\1'"$TENANT_ID"'|' \
  -e 's|(--allowed-group=)VIEWER-GROUP-ID|\1'"$VIEWER_GROUP"'|' \
  -e 's|(--allowed-group=)ADMIN-GROUP-ID|\1'"$ADMIN_GROUP"'|' \
  -e 's|(--redirect-url=https://)[^/ ]+(/oauth2/callback)|\1'"$SERVER_NAME"'\2|' \
  -e 's|(--trusted-proxy-ip=)[^ ]+|\1'"$PROXY_SUBNET"'|' \
  -e 's|^( +name: )[^ ]+( +# CHANGE-ME: name of that network)|\1'"$DOCKER_NETWORK"'\2|' \
  -e 's| +# ENTRA: CHANGE-ME: .*$|   # ENTRA|' \
  -e 's| +# CHANGE-ME: .*$||' /opt/ohif/docker-compose.yml
```

Die sechs Zeilen lassen sich auch von Hand bearbeiten, zum Beispiel mit `nano /opt/ohif/docker-compose.yml`. Jeden Wert ersetzen
und den Marker-Kommentar löschen. YAML nutzt Leerzeichen, nie Tabulatoren.

> **Warnung**
>
> Eine falsche Gruppe in der Compose-Datei sperrt Benutzer aus. Eine falsche Viewer-Gruppe lässt niemanden den Viewer öffnen.
> Eine falsche Admin-Gruppe lässt niemanden `/admin/` öffnen. Die Objekt-IDs aus Schritt 4 nehmen, nicht die Gruppennamen.

> **Prüfen**
>
> ```bash
> grep -n 'CHANGE-M[E]' /opt/ohif/docker-compose.yml
> docker compose -f /opt/ohif/docker-compose.yml config --quiet && echo compose file ok
> ```
>
> Erwartet: Der erste Befehl gibt nichts aus. Der zweite gibt aus:
>
> ```text
> compose file ok
> ```
>
> Eine Zeile in der Ausgabe des ersten Befehls ist ein Wert, der noch zu setzen ist. Der Text `CHANGE-ME-...` hinter einem
> `=`-Zeichen heißt, dass eine Variable oben nicht gefüllt wurde. Ein Fehler von `docker compose config` nennt die Zeile.

<a id="login-oauth2-site"></a>
#### Schritt 9. Die Admin-Gruppe in nginx setzen

`pacs/site.conf` ist die einzige nginx-Datei, die man bearbeitet. Für diese Anmeldung enthält sie den Host-Namen und die
Admin-Gruppe. Die Admin-Gruppe muss derselbe Text sein wie die Admin-Gruppe in der Compose-Datei (das zweite `--allowed-group`).

Die zwei Werte hinter den `=`-Zeichen setzen und den Block ausführen. Den Host-Namen und die Object ID aus Schritt 8 nehmen:

```bash
SERVER_NAME=CHANGE-ME-HOST-NAME
ADMIN_GROUP=CHANGE-ME-ADMIN-GROUP-ID
sed -E -i -e 's|^(server_name +)[^;]+;.*|\1'"$SERVER_NAME"';|' \
          -e 's|^(set \$pacs_admin_group +)[^;]+;.*|\1'"$ADMIN_GROUP"';|' /opt/ohif/nginx/pacs/site.conf
```

Der Befehl ersetzt beide Zeilen samt ihren Marker-Kommentaren. Eine Object ID braucht keine Sonderbehandlung. Ein Gruppenname
eines anderen Anbieters kann sie brauchen: siehe [2.6](#login-oauth2-group-names).

> **Warnung**
>
> Eine leere oder falsche Admin-Gruppe öffnet nichts aus Versehen. Ein leerer Wert gibt 500 auf `/admin/`. Ein falscher Wert gibt
> 403 für alle auf `/admin/`. Der mitgelieferte Platzhalter `00000000-0000-0000-0000-000000000000` ist so ein falscher Wert: Er
> hält `/admin/` geschlossen, bis die eigene Gruppe eingetragen ist. Eine falsche Gruppe in der Compose-Datei für die
> Viewer-Stufe ist schlimmer: Niemand kann den Viewer öffnen. Vor der Ankündigung an die Benutzer mit einem Testkonto prüfen.

> **Prüfen**
>
> ```bash
> grep -rn 'CHANGE-M[E]' /opt/ohif/nginx /opt/ohif/docker-compose.yml
> grep -n 'server_name\|pacs_admin_group' /opt/ohif/nginx/pacs/site.conf
> ```
>
> Erwartet: Der erste Befehl gibt nichts aus. Der zweite gibt die zwei eigenen Werte aus:
>
> ```text
> 4:server_name pacs.example.org;
> 20:set $pacs_admin_group aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee;
> ```
>
> Eine Zeile in der Ausgabe des ersten Befehls ist ein Wert, der noch zu setzen ist.

<a id="login-oauth2-start"></a>
#### Schritt 10. Starten und prüfen

Die Container starten. Laufen sie schon, wendet derselbe Befehl die Änderungen an.

```bash
cd /opt/ohif && docker compose up -d
docker exec ohif nginx -t
```

> **Prüfen**
>
> ```bash
> docker ps --format '{{.Names}}  {{.Status}}' | grep '^ohif'
> docker exec ohif nginx -t
> curl -sk -o /dev/null -w '%{http_code} %{redirect_url}\n' https://pacs.example.org/ | cut -d/ -f1-3
> ```
>
> Erwartet: zwei Container mit dem Status `Up`, die zwei nginx-Zeilen und eine Umleitung zu Microsoft für eine Anfrage ohne
> Sitzung. Die letzte Zeile wurde nicht gegen einen echten Anbieter ausgeführt:
>
> ```text
> ohif  Up 2 minutes
> ohif-auth  Up 2 minutes
> nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
> nginx: configuration file /etc/nginx/nginx.conf test is successful
> 302 https://login.microsoftonline.com
> ```
>
> Das `-k` heißt „ein selbstsigniertes Zertifikat akzeptieren“. Bei einem Zertifikat einer echten Zertifizierungsstelle
> weglassen. Dann prüft curl das Zertifikat auch. Das `cut` behält den Host-Namen und schneidet die lange Adresse dahinter ab.
>
> Ist `ohif-auth` nicht `Up` oder fehlt die Umleitung: siehe [Fehlersuche](troubleshooting.de.md#login-oauth2-proxy-down).
> Antwortet jede Seite mit 500: siehe [Fehlersuche](troubleshooting.de.md#every-page-500). Springt der Browser zwischen dem PACS
> und der Anmeldeseite hin und her: siehe [Fehlersuche](troubleshooting.de.md#login-loop).

Jetzt mit echten Konten in einem privaten Browserfenster testen. Ein Konto der Viewer-Gruppe und ein Konto der Admin-Gruppe
nehmen.

> **Prüfen**
>
> 1. `https://pacs.example.org/` öffnen. Microsoft verlangt die Anmeldung. Danach öffnet sich der Viewer.
> 2. `https://pacs.example.org/oauth2/userinfo` öffnen. Die Seite zeigt eine Zeile JSON-Text. Die Admin-Seite übernimmt den
>    Kontonamen oben aus den Einträgen `preferredUsername`, `email` und `user` (der erste, der nicht leer ist). Ein Eintrag
>    `groups` enthält eine Liste mit der Object ID jeder Gruppe dieses Benutzers. Diese Ausgabe wurde nicht gegen einen echten
>    Anbieter ausgeführt.
> 3. `https://pacs.example.org/admin/` mit dem **Viewer**-Konto öffnen: nginx zeigt `403 Forbidden`.
> 4. `https://pacs.example.org/admin/` mit dem **Admin**-Konto öffnen: Die Admin-Seite öffnet sich. Der Kontoname steht oben auf
>    der Seite.
>
> Schlägt Schritt 1 nach der Anmeldung mit einem 403 fehl: siehe [Fehlersuche](troubleshooting.de.md#viewer-403-after-login).
> Zeigt Schritt 4 für das Admin-Konto 403 oder 500: siehe [Fehlersuche](troubleshooting.de.md#admin-403) und
> [Fehlersuche](troubleshooting.de.md#admin-500). Jede Anfrage dieses Tests steht im Protokoll: [Abschnitt 8](#login-audit) zeigt,
> wie man es liest.

<a id="login-oauth2-signout"></a>
#### Schritt 11. Einen Abmelde-Link hinzufügen (optional)

Die Admin-Seite zeigt neben dem Kontonamen den Link `Abmelden`, wenn `abmeldenUrl` in `config.js` gesetzt ist. Dafür eine eigene
Kopie der Datei benutzen, damit ein `git pull` nicht mit der Änderung kollidiert. Die Compose-Datei kann die Kopie über das
Original einhängen, aber die Zeile für den Mount ist zunächst ein Kommentar. Diese Befehle erstellen die Kopie, setzen die Adresse
und schalten den Mount ein (der letzte löscht das `# ` vor der Mount-Zeile):

```bash
cp -n /opt/pacs-admin/web/admin/config.js /opt/ohif/config.js
sed -i "s|abmeldenUrl: ''|abmeldenUrl: '/oauth2/sign_out'|" /opt/ohif/config.js
sed -E -i 's|^( +)# (- \./config\.js:)|\1\2|' /opt/ohif/docker-compose.yml
```

Danach den Container neu erzeugen, damit er den neuen Mount sieht:

```bash
cd /opt/ohif && docker compose up -d
```

Der Link `/oauth2/sign_out` beendet nur die PACS-Sitzung. Entra kann den Benutzer sofort und ohne Passwort wieder anmelden, weil
der Benutzer bei Entra noch angemeldet ist. Um auch die Entra-Sitzung zu beenden, stattdessen diesen längeren Wert in
`abmeldenUrl` eintragen. Die Compose-Datei erlaubt die Domain schon mit `--whitelist-domain`:

```text
/oauth2/sign_out?rd=https%3A%2F%2Flogin.microsoftonline.com%2Fcommon%2Foauth2%2Fv2.0%2Flogout
```

Nach einer späteren Änderung von `config.js` in `/opt/ohif` den Befehl `docker compose restart ohif` ausführen. Der Neustart ist
nötig, weil die Compose-Datei eine einzelne Datei einhängt und eine geänderte Datei in einem laufenden Container nicht sichtbar
ist.

> **Prüfen**
>
> ```bash
> grep -o "abmeldenUrl: '[^']*'" /opt/ohif/config.js
> grep -n '^ *- \./config\.js:' /opt/ohif/docker-compose.yml
> docker compose -f /opt/ohif/docker-compose.yml config --quiet && echo compose file ok
> ```
>
> Erwartet:
>
> ```text
> abmeldenUrl: '/oauth2/sign_out'
> 78:      - ./config.js:/srv/pacs-admin/admin/config.js:ro
> compose file ok
> ```
>
> Gibt der zweite Befehl nichts aus, ist der Mount noch ein Kommentar. Den letzten `sed`-Befehl dieses Schritts noch einmal
> ausführen. Die Admin-Seite ohne Cache neu laden (Strg+F5). Der Link `Abmelden` erscheint neben dem Kontonamen. Die
> Änderungsbefehle liefen auf Kopien der Dateien. Die Abmeldung selbst wurde nicht gegen einen echten Anbieter ausgeführt.

<a id="login-oauth2-overage"></a>
### 2.4 Benutzer in vielen Gruppen (mehr als 200)

Entra schreibt höchstens 200 Gruppen in ein Token. Ist ein Benutzer in mehr Gruppen, lässt Entra alle Gruppen weg. Das heißt
Gruppen-Überlauf (englisch group overage). oauth2-proxy sieht dann für diesen Benutzer keine Gruppe und lehnt die Anmeldung ab.
Direkt nach der Microsoft-Anmeldung landet der Benutzer auf einer Seite mit dem Titel „Forbidden“ und dem Text „You do not have
permission to access this resource“. In `docker logs ohif-auth` erscheint die Logzeile
`Invalid authentication via OAuth2: unauthorized`. Ein abgelehnter Benutzer bekommt keine Sitzung, darum kann `/oauth2/userinfo`
die Gruppen dieses Benutzers nicht zeigen (es antwortet 401). Andere Benutzer sind nicht betroffen, was den Fehler schwer findbar
macht. Die Seite und die Logzeile stammen aus dem Quellcode von oauth2-proxy `v7.15.4`. Beide wurden nicht gegen einen echten
Anbieter ausgeführt.

Ein Überlauf ist wahrscheinlich, wenn ein Benutzer in den PACS-Gruppen ist, dieselbe Anmeldung bei anderen Benutzern funktioniert
und der Benutzer Mitglied von mehr als 200 Gruppen ist (Entra ID > Users > der Benutzer > Groups zeigt die Zahl).

Es gibt zwei Lösungen. Die erste ist für große Tenants besser.

**A. Nur die Gruppen ausgeben, die der Anwendung zugewiesen sind.**

1. Entra ID > Enterprise apps > All applications > `PACS` > Users and groups > Add user/group öffnen. `PACS Viewer` und
   `PACS Admin` zuweisen.
2. App registrations > `PACS` > Token configuration öffnen. Den Groups-Claim wählen und Groups assigned to the application
   auswählen. Save wählen.

Die Gruppenzuweisung braucht Microsoft Entra ID P1 oder P2. Verschachtelte Gruppen zählen nicht. Die Benutzer müssen direkte
Mitglieder der zwei Gruppen sein. In der Compose-Datei und in `site.conf` ändert sich nichts.

**B. oauth2-proxy Microsoft Graph fragen lassen.** `User.Read` in der Compose-Datei zum Scope hinzufügen:

```text
- --scope=openid email profile User.Read
```

oauth2-proxy liest dann die vollständige Gruppenliste aus Microsoft Graph. Manche Tenants verlangen, dass ein Administrator
`User.Read` zustimmt (Schritt 5). Eine lange Gruppenliste kann das Sitzungs-Cookie zu groß machen.

Beide Lösungen folgen der Dokumentation von
[oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/configuration/providers/ms_entra_id) und von
[Microsoft](https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-fed-group-claims) (beide englisch).
Beide Lösungen liefen hier nicht.

> **Prüfen**
>
> Als betroffener Benutzer anmelden. Der Viewer öffnet sich, und die „Forbidden“-Seite erscheint nicht. Dann
> `https://pacs.example.org/oauth2/userinfo` öffnen: Der Eintrag `groups` listet die Object IDs der PACS-Gruppen dieses
> Benutzers.
>
> Erscheint die „Forbidden“-Seite weiter, hat die Lösung nicht gewirkt. Jede abgelehnte Anmeldung hinterlässt eine Zeile im Log:
>
> ```bash
> docker logs ohif-auth 2>&1 | grep 'Invalid authentication' | tail -3
> ```
>
> Dann siehe [Fehlersuche](troubleshooting.de.md#viewer-403-after-login).

<a id="login-oauth2-operate"></a>
### 2.5 Alltag mit oauth2-proxy

**Das Client-Geheimnis ersetzen.** Im Portal ein neues Geheimnis anlegen (Schritt 2), bevor das alte abläuft. Die drei Blöcke aus
Schritt 7 noch einmal ausführen. Dabei ändert sich auch das Cookie-Geheimnis, also meldet sich jeder einmal neu an. Dann den
Container neu erzeugen:

```bash
cd /opt/ohif && docker compose up -d --force-recreate ohif-auth
```

> **Prüfen**
>
> ```bash
> docker ps --format '{{.Names}}  {{.Status}}' | grep '^ohif-auth'
> ```
>
> Erwartet: `ohif-auth` mit dem Status `Up` und einer kurzen Zeit. Dann einmal anmelden. Schlägt die Anmeldung fehl, siehe
> [Fehlersuche](troubleshooting.de.md#login-client-secret).

**Eine Person hinzufügen oder entfernen.** Die Gruppenmitgliedschaft in Entra ändern. oauth2-proxy liest die Gruppen bei der
Anmeldung und hält sie in der Sitzung. Die Sitzung endet nach 12 Stunden (`--cookie-expire=12h`) und wird nicht erneuert. Eine
Änderung wirkt darum bei der nächsten Anmeldung, spätestens nach 12 Stunden. Damit sie sofort wirkt, öffnet die Person
`/oauth2/sign_out` und meldet sich neu an.

**Alle Sitzungen auf einmal beenden.** Die drei Blöcke aus Schritt 7 noch einmal ausführen und `ohif-auth` neu erzeugen. Das neue
Cookie-Geheimnis macht jedes alte Sitzungs-Cookie nutzlos. Das nutzen, wenn eine Person den Zugang sofort verlieren muss.

**Die Sitzung endet bei geöffneter Admin-Seite.** Die Seite zeigt „Sitzung abgelaufen, Seite neu laden (F5)“. F5 drücken, um sich
neu anzumelden. Siehe [Fehlersuche](troubleshooting.de.md#session-expired).

**Die Admin-Gruppe ändern.** An beiden Stellen ändern (Compose-Datei und `site.conf`), dann:

```bash
cd /opt/ohif && docker compose up -d
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

<a id="login-oauth2-providers"></a>
### 2.6 Andere OIDC-Anbieter

Ein anderer Anbieter ändert in der Compose-Datei einige Optionen und in `site.conf` den Wert der Admin-Gruppe. Alles andere aus
Abschnitt 2 bleibt: Die Redirect-URI ist immer `https://pacs.example.org/oauth2/callback`, die drei Geheimnisse gehören in
`ohif-auth.env`, und die Admin-Gruppe gehört in die Compose-Datei und in `site.conf`.

**Hier nicht getestet.** Die Befehle dieses Abschnitts liefen auf Kopien der Compose-Datei und der nginx-Dateien: `docker compose
config` und `nginx -t` akzeptierten das Ergebnis. Es lief weder ein echtes oauth2-proxy noch ein echter Anbieter. Was dieser
Abschnitt über die Bildschirme, die Claims und die Optionen eines Anbieters sagt, stammt aus der Dokumentation von oauth2-proxy
`v7.15.4` und des Anbieters. Schritt E prüft das Ergebnis an der eigenen Installation.

#### Die Auswahl auf einen Blick

| Anbieter | `--provider` | Issuer-Adresse | Die Stufe kommt aus | Beispiel für die Admin-Gruppe |
|---|---|---|---|---|
| [Keycloak](#login-oauth2-keycloak) | `keycloak-oidc` | `https://idp.example.org/realms/pacs` | Gruppen oder Realm-Rollen | `pacs-admins`, oder `role:pacs-admin` für eine Rolle |
| [Authentik](#login-oauth2-authentik) | `oidc` | `https://idp.example.org/application/o/pacs/` | Gruppen | `pacs-admins` |
| [Authelia](#login-oauth2-authelia) | `oidc` | `https://auth.example.org` | Gruppen | `pacs-admins` |
| [Zitadel](#login-oauth2-zitadel) | `oidc` | `https://zitadel.example.org` | Rollen, durch eine Action in Gruppen umgewandelt | `pacs-admin` |
| [Google](#login-oauth2-google) | `google` | keine | E-Mail-Adressen | `anna@example.org,ben@example.org` |
| [GitHub](#login-oauth2-github) | `github` | keine | Teams einer Organisation | `my-org:pacs-admins` |

Die **Issuer-Adresse** nennt den Anbieter. oauth2-proxy holt dort die Regeln der Anmeldung ab. Schritt C zeigt, wie man sie
prüft.

**Active Directory.** Eine Windows-Domäne allein kann Benutzer auf diese Weise nicht anmelden, weil Active Directory kein OIDC
spricht. Es gibt zwei Wege. Die Konten mit Entra ID synchronisieren und [2.3](#login-oauth2-entra) folgen. Oder Keycloak oder
Authentik betreiben und die Konten dort aus Active Directory lesen lassen ([LDAP](glossary.de.md#ldap)-Anbindung, englisch
federation). Der zweite Weg wurde hier nicht getestet. AD FS wird nicht behandelt.

Die Schritte in dieser Reihenfolge ausführen:

| Schritt | Was man tut |
|---|---|
| [A](#login-oauth2-register) | Die Anwendung beim Anbieter registrieren |
| [B](#login-oauth2-common) | `ohif-auth.env` anlegen |
| [C](#login-oauth2-compose) | Die Compose-Datei bearbeiten |
| [D](#login-oauth2-group-names) | Die Admin-Gruppe in nginx setzen |
| [Schritt 10 in 2.3](#login-oauth2-start) | Die Container starten und prüfen (wie bei Entra ID) |
| [E](#login-oauth2-check) | Die Gruppen mit einem Testkonto prüfen |
| [F](#login-oauth2-signout-other) | Einen Abmelde-Link hinzufügen (optional) |

<a id="login-oauth2-register"></a>
#### Schritt A. Die Anwendung beim Anbieter registrieren

Der Anbieter muss oauth2-proxy kennen. Er braucht die Adresse, an die der Browser nach der Anmeldung zurückkehrt (die
Redirect-URI `https://pacs.example.org/oauth2/callback`), und er gibt eine Client-ID und ein Client-Geheimnis aus. Er braucht
außerdem die zwei Gruppen und muss die Gruppen in das Token schreiben. Den Teil für den eigenen Anbieter benutzen. Jeder Teil
endet mit den Werten, die die Schritte C und D brauchen.

<a id="login-oauth2-keycloak"></a>
##### Keycloak

[Keycloak](glossary.de.md#keycloak) ist ein kostenloser Identitätsanbieter. Die Bildschirmnamen unten folgen aktuellen
Keycloak-Versionen. Ältere Versionen nennen einige Bildschirme anders.

1. In der Admin-Konsole den Realm der eigenen Benutzer wählen. Der Realm-Name ist Teil der Issuer-Adresse (`pacs` im Beispiel).
2. Clients > Create client öffnen. Client type: OpenID Connect. Client ID: `pacs`. Next wählen.
3. Client authentication auf On schalten. Nur Standard flow angehakt lassen. Next wählen.
4. Valid redirect URIs: `https://pacs.example.org/oauth2/callback`. Save wählen.
5. Den Reiter Credentials öffnen. Das Client secret kopieren.
6. Groups > Create group öffnen. `pacs-viewers` und `pacs-admins` anlegen. Die Personen als Mitglieder hinzufügen.
7. Client scopes > Create client scope öffnen. Name: `groups`. Type: Default. Protocol: OpenID Connect. Save wählen.
8. Den neuen Scope öffnen, dann Mappers > Configure a new mapper > Group Membership. Name: `groups`. Token Claim Name: `groups`.
   Full group path: Off. Add to ID token, Add to access token und Add to userinfo: On. Save wählen.
9. Clients > `pacs` > Client scopes > Add client scope öffnen. `groups` wählen und als Default hinzufügen.

Werte für die Schritte C und D:

```text
PROVIDER=keycloak-oidc
ISSUER=https://idp.example.org/realms/pacs
SCOPE='openid email profile groups'
VIEWER_GROUP=pacs-viewers
ADMIN_GROUP=pacs-admins
```

Keycloak vor Version 17 setzt `/auth` vor `/realms` in die Issuer-Adresse. Bei Full group path On schreibt Keycloak die Gruppen
mit einem Schrägstrich am Anfang (`/pacs-viewers`). Dann den Schrägstrich auch in die Werte schreiben.

**Realm-Rollen statt Gruppen.** Der Anbieter `keycloak-oidc` reicht Realm-Rollen als Gruppen mit dem Namen `role:NAME` an nginx
weiter. Dann sind die Punkte 7 bis 9 der Liste oben nicht nötig. Die Realm-Rollen `pacs-viewer` und `pacs-admin` anlegen, den
Personen geben und diese Werte nehmen:

```text
PROVIDER=keycloak-oidc
ISSUER=https://idp.example.org/realms/pacs
SCOPE='openid email profile'
VIEWER_GROUP=role:pacs-viewer
ADMIN_GROUP=role:pacs-admin
```

> **Prüfen**
>
> Der Client `pacs` listet die Redirect-URI, und sein Reiter Credentials zeigt ein Geheimnis. Keycloak kann das Token eines
> Testbenutzers zeigen: Clients > `pacs` > Client scopes > Evaluate, den Benutzer wählen, dann den Reiter Generated ID token (die
> Namen unterscheiden sich je nach Version). Das Token enthält eine Liste `groups` mit den Gruppennamen. Wenn nicht, fehlt der
> Mapper (Punkt 8) oder der Scope am Client (Punkt 9). Schritt E prüft dasselbe über oauth2-proxy.

<a id="login-oauth2-authentik"></a>
##### Authentik

authentik ist ein kostenloser Identitätsanbieter. Die Bildschirmnamen unten folgen aktuellen Versionen und können in der eigenen
abweichen.

1. Applications > Providers > Create > OAuth2/OpenID Provider öffnen. Name: `pacs`.
2. Client type: Confidential. Redirect URIs: `https://pacs.example.org/oauth2/callback`. Manche Versionen lesen dieses Feld als
   regulären Ausdruck. Dann `https://pacs\.example\.org/oauth2/callback` schreiben.
3. Signing Key: ein Zertifikat wählen, zum Beispiel das selbstsignierte, das authentik mitbringt. Ohne Signing Key signiert
   authentik Token mit dem Client-Geheimnis (HS256), und oauth2-proxy kann diese Signatur nicht prüfen.
4. Finish wählen. Den Provider öffnen und die Client ID und das Client Secret kopieren.
5. Applications > Applications > Create öffnen. Name: `PACS`. Slug: `pacs`. Provider: `pacs`. Der Slug ist Teil der
   Issuer-Adresse.
6. Directory > Groups öffnen. `pacs-viewers` und `pacs-admins` anlegen und die Personen hinzufügen.

Der Scope `profile` von authentik trägt den Claim `groups`, also reicht die mitgelieferte Scope-Liste. Werte für die Schritte C
und D:

```text
PROVIDER=oidc
ISSUER=https://idp.example.org/application/o/pacs/
SCOPE='openid email profile'
VIEWER_GROUP=pacs-viewers
ADMIN_GROUP=pacs-admins
```

Die Issuer-Adresse von authentik endet mit einem Schrägstrich. oauth2-proxy vergleicht die Adresse Zeichen für Zeichen, also den
Schrägstrich behalten. Die Standard-Admin-Gruppe von authentik heißt `authentik Admins`, mit Leerzeichen. Schritt D zeigt, wie
man so einen Namen schreibt.

> **Prüfen**
>
> Die Liste der Anwendungen zeigt `PACS` mit dem Provider `pacs`. Die Adresse
> `https://idp.example.org/application/o/pacs/.well-known/openid-configuration` zeigt im Browser eine Seite mit JSON-Text. Die
> Provider-Seite von authentik kann das Token eines Benutzers in einer Vorschau zeigen (der Name des Reiters unterscheidet sich je
> nach Version). Das Token enthält eine Liste `groups`. Schritt E prüft dasselbe über oauth2-proxy.

<a id="login-oauth2-authelia"></a>
##### Authelia

[Authelia](https://www.authelia.com/) ist ein Anmeldeportal, das Gruppen kennt. Dieser Teil wurde nicht im Einzelnen geprüft. Die
Authelia-Seite [OpenID Connect](https://www.authelia.com/integration/openid-connect/introduction/) (englisch) ist die Referenz
für die Konfigurationsdatei.

1. In der Authelia-Konfigurationsdatei im Teil OpenID Connect einen Client hinzufügen: Client ID `pacs`, die Redirect-URI
   `https://pacs.example.org/oauth2/callback` und die Scopes `openid`, `email`, `profile` und `groups`. Die genauen Schlüssel
   hängen von der Authelia-Version ab. Authelia neu starten.
2. Authelia speichert nur einen Hash des Client-Geheimnisses. oauth2-proxy braucht den Klartext. Einen langen Zufallstext
   erzeugen, seinen Hash in die Authelia-Datei und den Klartext in `ohif-auth.env` (Schritt B) eintragen.
3. Die Gruppen kommen aus der Benutzerdatenbank von Authelia (eine Datei oder LDAP).

Werte für die Schritte C und D. Die Issuer-Adresse ist die Basisadresse des Authelia-Portals; die Prüfung in Schritt C beweist
sie:

```text
PROVIDER=oidc
ISSUER=https://auth.example.org
SCOPE='openid email profile groups'
VIEWER_GROUP=pacs-viewers
ADMIN_GROUP=pacs-admins
```

Authelia liefert die Gruppen unter Umständen nur an seinem UserInfo-Endpunkt und nicht im ID-Token. oauth2-proxy fragt auch
diesen Endpunkt, außer `--skip-claims-from-profile-url=true` ist gesetzt (in der Compose-Datei ist es nicht gesetzt). Das wurde
nicht überprüft.

> **Prüfen**
>
> Die Adresse `https://auth.example.org/.well-known/openid-configuration` zeigt eine Seite mit JSON-Text. Schritt C und Schritt E
> beweisen den Rest.

<a id="login-oauth2-zitadel"></a>
##### Zitadel

[Zitadel](https://zitadel.com/) hält die Rollen eines Benutzers im Claim `urn:zitadel:iam:org:project:roles`. Dieser Claim ist
eine Struktur, keine Liste. oauth2-proxy liest einen Gruppen-Claim nur, wenn er eine Liste von Texten ist. Darum muss eine Action
in Zitadel die Rollennamen in einen Listen-Claim `groups` kopieren. Das ist der am wenigsten geprüfte Teil dieser Anleitung. Er
beruht auf Berichten von Zitadel-Benutzern und auf der Zitadel-Seite über
[Actions](https://zitadel.com/docs/apis/actions/introduction) (englisch). Wenn möglich, einen anderen Anbieter vorziehen.

1. Ein Projekt mit den Rollen `pacs-viewer` und `pacs-admin` anlegen. In den Projekteinstellungen prüfen, dass Rollen in das
   Token geschrieben werden.
2. Im Projekt eine Anwendung anlegen: Typ Web, Flow Code, Redirect-URI `https://pacs.example.org/oauth2/callback`. Die Client ID
   und das Client Secret kopieren.
3. Den Personen die Rollen geben.
4. Im Flow Complement Token eine Action hinzufügen, die die Rollennamen in den Claim `groups` schreibt. Das Skript hängt von der
   Zitadel-Version ab. Diese Anleitung druckt keines.

Werte für die Schritte C und D:

```text
PROVIDER=oidc
ISSUER=https://zitadel.example.org
SCOPE='openid email profile'
VIEWER_GROUP=pacs-viewer
ADMIN_GROUP=pacs-admin
```

> **Prüfen**
>
> Die Adresse `https://zitadel.example.org/.well-known/openid-configuration` zeigt eine Seite mit JSON-Text. Schritt E zeigt, ob
> die Action funktioniert: Der Eintrag `groups` muss die Rollennamen auflisten.

<a id="login-oauth2-google"></a>
##### Google

Google schreibt keine Gruppen in das Token. Die zwei Stufen funktionieren anders als bei den anderen Anbietern:

- **Viewer-Stufe:** jedes Konto einer Google-Workspace-Domain (`--email-domain=example.org`).
- **Admin-Stufe:** eine Liste von E-Mail-Adressen in `pacs/site.conf`. nginx fragt oauth2-proxy dann nach einer Adresse aus der
  Liste und nicht nach einer Gruppe (Schritt D).

> **Warnung**
>
> `--email-domain=example.org` lässt jedes Konto der Domain den Viewer öffnen. Google nur benutzen, wenn das akzeptabel ist. Nicht
> mit privaten Gmail-Konten benutzen: Es gibt keine Domain, auf die man sie begrenzen könnte, und `--email-domain=*` ließe jedes
> Google-Konto den Viewer öffnen.

1. Die [Google Cloud Console](https://console.cloud.google.com/) öffnen. Ein Projekt wählen oder anlegen.
2. APIs & Services > OAuth consent screen öffnen. User type: Internal (das braucht Google Workspace). Name: `PACS`.
3. Credentials > Create credentials > OAuth client ID öffnen. Application type: Web application. Authorised redirect URI:
   `https://pacs.example.org/oauth2/callback`.
4. Die Client ID und das Client secret kopieren.

Google hat keine Issuer-Adresse, keine Scope-Liste und keine Gruppen, die man setzen müsste. Der Block aus Schritt C für Google
nutzt nicht den allgemeinen Anbieter-Block. Werte für die Schritte C und D:

```text
DOMAIN=example.org
ADMIN_LIST=anna@example.org,ben@example.org
```

Die Adressen in Kleinbuchstaben schreiben. Jede Adresse muss Buchstabe für Buchstabe zum Eintrag `email` von `/oauth2/userinfo` passen
(Schritt E). Ein Pluszeichen in einer Adresse wird in `ADMIN_LIST` als `%2B` geschrieben (Schritt D erklärt, warum).

> **Prüfen**
>
> Die Seite Credentials listet den Client mit der Redirect-URI. Schritt E zeigt die Adressen so, wie oauth2-proxy sie sieht. Die
> Anmeldung mit Google lief nicht von Anfang bis Ende. Mehr:
> [Googles Seite über Webserver-Anwendungen](https://developers.google.com/identity/protocols/oauth2/web-server) (englisch).

<a id="login-oauth2-github"></a>
##### GitHub

GitHub schreibt auch keine Gruppen in ein Token, kennt aber Teams einer Organisation. oauth2-proxy lässt die Mitglieder der
Teams ein, die man nennt, und nginx fragt nach einem Team als Admin-Team. Das braucht eine Organisation bei GitHub.

1. GitHub > Settings > Developer settings > OAuth Apps > New OAuth App öffnen. Application name: `PACS`. Homepage URL:
   `https://pacs.example.org/`. Authorization callback URL: `https://pacs.example.org/oauth2/callback`.
2. Register application wählen. Die Client ID kopieren. Generate a new client secret wählen und das Geheimnis sofort kopieren.
3. In der Organisation zwei Teams anlegen, zum Beispiel `pacs-viewers` und `pacs-admins`, und die Personen hinzufügen. Ein Team
   wird mit seinem Slug benannt (der Kurzname in der Adresse des Teams).
4. Organisationen können Apps von Drittanbietern einschränken. Dann muss ein Owner der Organisation die App freigeben, bevor
   Mitglieder sie nutzen können. Die Namen dieser Bildschirme ändern sich von Zeit zu Zeit.

Werte für die Schritte C und D. `ORG` und `TEAMS` sind die Organisation und alle Teams, die den Viewer öffnen dürfen (wer in
einem davon ist, kommt hinein). `ADMIN_GROUP` ist die Organisation, ein Doppelpunkt und der Slug des Admin-Teams:

```text
ORG=my-org
TEAMS=pacs-viewers,pacs-admins
ADMIN_GROUP=my-org:pacs-admins
```

GitHub Enterprise Server braucht außerdem die Optionen `--login-url`, `--redeem-url` und `--validate-url` mit den Adressen des
eigenen Servers. Die Compose-Datei enthält diese Optionen nicht. Siehe die Seite
[GitHub](https://oauth2-proxy.github.io/oauth2-proxy/configuration/providers/github) von oauth2-proxy (englisch).

> **Prüfen**
>
> Die Liste der OAuth Apps zeigt `PACS` mit der Callback-URL. Mehr:
> [die GitHub-Seite über OAuth Apps](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)
> (englisch). Die Anmeldung mit GitHub lief nicht von Anfang bis Ende.

<a id="login-oauth2-common"></a>
#### Schritt B. ohif-auth.env anlegen

Die drei Blöcke aus [Schritt 7](#login-oauth2-env) in 2.3 ausführen. Wo sie nach der Application (client) ID und dem geheimen
Value fragen, die Client-ID und das Client-Geheimnis des eigenen Anbieters eintippen. Der Block, der das Cookie-Geheimnis
erzeugt, bleibt gleich.

> **Prüfen**
>
> Die Prüfung aus [Schritt 7](#login-oauth2-env) gilt: der Modus `-rw-------` und die drei Namen, ohne Werte.

<a id="login-oauth2-compose"></a>
#### Schritt C. Die Compose-Datei bearbeiten

Die Compose-Datei startet oauth2-proxy mit einer Liste von Optionen. Die mit `# ENTRA` markierten Zeilen sind für Entra ID. Ein
Block auskommentierter Zeilen enthält die Optionen eines allgemeinen OIDC-Anbieters. Google und GitHub brauchen einige eigene
Zeilen. Die Befehle unten löschen die Entra-Zeilen, schalten die richtigen Optionen ein und tragen die eigenen Werte ein.

**Zuerst die Issuer-Adresse prüfen** (nicht für Google und GitHub). oauth2-proxy bricht beim Start ab, wenn die angegebene Adresse
von der Adresse abweicht, die der Anbieter über sich selbst bekanntgibt. Der Anbieter gibt sie an einer festen Stelle bekannt. Die
eigene Adresse hinter `ISSUER=` schreiben und danach fragen:

```bash
ISSUER=https://idp.example.org/realms/pacs
curl -s "${ISSUER%/}/.well-known/openid-configuration" | python3 -c 'import sys,json; print(json.load(sys.stdin)["issuer"])'
```

> **Prüfen**
>
> Erwartet: eine Zeile mit der Adresse, wie der Anbieter sie bekanntgibt. Für das Keycloak-Beispiel oben:
>
> ```text
> https://idp.example.org/realms/pacs
> ```
>
> Die ausgegebene Adresse gehört Zeichen für Zeichen hinter `--oidc-issuer-url=`. Ein Schrägstrich am Ende zählt: Die Adresse von
> authentik endet mit einem. Gibt der Befehl nichts aus, ist die Adresse falsch oder der Server erreicht den Anbieter nicht.
> Meldet Python einen Fehler, gehört die Adresse nicht zu einem OIDC-Anbieter. Bei einer falschen Adresse endet
> `docker logs ohif-auth` mit einer Meldung wie `oidc: issuer did not match the issuer returned by provider, expected "..." got
> "..."` (eine Meldung der Bibliothek, hier nicht ausgeführt): siehe
> [Fehlersuche](troubleshooting.de.md#login-oauth2-proxy-down).

**Keycloak, Authentik, Authelia, Zitadel.** Den allgemeinen Block einschalten:

```bash
sed -E -i -e '/# ENTRA/d' -e 's|^( +)# (- --)|\1\2|' /opt/ohif/docker-compose.yml
```

Der erste Ausdruck löscht die sieben Entra-Zeilen. Der zweite entfernt das `# ` vor den acht Zeilen des allgemeinen Blocks. Der
Block setzt auch `--oidc-groups-claim=groups` (der Standardname des Claims) und `--oidc-email-claim=preferred_username` (Konten
ohne E-Mail-Adresse können sich dann anmelden). Beide so lassen.

Die eigenen Werte hinter die `=`-Zeichen setzen. Die ersten fünf aus Schritt A nehmen und die letzten drei wie in
[Schritt 8](#login-oauth2-edit). Dann den Block ausführen:

```bash
PROVIDER=CHANGE-ME-PROVIDER
ISSUER=CHANGE-ME-ISSUER-ADDRESS
SCOPE='CHANGE-ME-SCOPE'
VIEWER_GROUP=CHANGE-ME-VIEWER-GROUP
ADMIN_GROUP=CHANGE-ME-ADMIN-GROUP
SERVER_NAME=CHANGE-ME-HOST-NAME
PROXY_SUBNET=CHANGE-ME-SUBNET
DOCKER_NETWORK=CHANGE-ME-NETWORK-NAME
IDP_HOST=$(echo "$ISSUER" | cut -d/ -f3)
sed -E -i \
  -e 's|(--provider=)oidc|\1'"$PROVIDER"'|' \
  -e 's|(--oidc-issuer-url=)[^ ]+|\1'"$ISSUER"'|' \
  -e 's|(--scope=)[^#]*[^# ]|\1'"$SCOPE"'|' \
  -e 's|(--allowed-group=)pacs-viewers|\1'"$VIEWER_GROUP"'|' \
  -e 's|(--allowed-group=)pacs-admins|\1'"$ADMIN_GROUP"'|' \
  -e 's|(--whitelist-domain=)[^ ]+|\1'"$IDP_HOST"'|' \
  -e 's|(--redirect-url=https://)[^/ ]+(/oauth2/callback)|\1'"$SERVER_NAME"'\2|' \
  -e 's|(--trusted-proxy-ip=)[^ ]+|\1'"$PROXY_SUBNET"'|' \
  -e 's|^( +name: )[^ ]+( +# CHANGE-ME: name of that network)|\1'"$DOCKER_NETWORK"'\2|' \
  -e 's| +# CHANGE-ME: .*$||' /opt/ohif/docker-compose.yml
```

`IDP_HOST` ist der Host-Name in der Issuer-Adresse. Er wird zu `--whitelist-domain`: Das ist die eine Domain, zu der eine
Abmeldung führen darf. Wurde der Netzname schon in der Installationsanleitung gesetzt ([Schritt 4.10](install.de.md#compose-file)),
findet der Ausdruck für die letzte Netzzeile nichts zu ändern. Ein Gruppenname mit den Zeichen `&`, `|` oder einem Backslash
zerstört diesen Block. Dann die zwei `--allowed-group`-Zeilen von Hand bearbeiten.

**Google.** Der allgemeine Block bleibt aus. Den Anbieter hinzufügen, die Viewer-Stufe auf die eigene Domain begrenzen und die drei
Werte aus [Schritt 8](#login-oauth2-edit) eintragen:

```bash
DOMAIN=CHANGE-ME-DOMAIN
SERVER_NAME=CHANGE-ME-HOST-NAME
PROXY_SUBNET=CHANGE-ME-SUBNET
DOCKER_NETWORK=CHANGE-ME-NETWORK-NAME
sed -E -i -e '/# ENTRA/d' \
  -e 's|^( +command:)$|\1\n      - --provider=google|' \
  -e 's|(--email-domain=)\*|\1'"$DOMAIN"'|' \
  -e 's|(--redirect-url=https://)[^/ ]+(/oauth2/callback)|\1'"$SERVER_NAME"'\2|' \
  -e 's|(--trusted-proxy-ip=)[^ ]+|\1'"$PROXY_SUBNET"'|' \
  -e 's|^( +name: )[^ ]+( +# CHANGE-ME: name of that network)|\1'"$DOCKER_NETWORK"'\2|' \
  -e 's| +# CHANGE-ME: .*$||' /opt/ohif/docker-compose.yml
```

**GitHub.** Der allgemeine Block bleibt aus. Den Anbieter, die Organisation und die Teams hinzufügen und die drei Werte aus
[Schritt 8](#login-oauth2-edit) eintragen. `--email-domain=*` bleibt: GitHub-Konten haben keine gemeinsame Domain, und die Teams
entscheiden, wer hineinkommt.

```bash
ORG=CHANGE-ME-ORGANISATION
TEAMS=CHANGE-ME-TEAM-SLUGS
SERVER_NAME=CHANGE-ME-HOST-NAME
PROXY_SUBNET=CHANGE-ME-SUBNET
DOCKER_NETWORK=CHANGE-ME-NETWORK-NAME
sed -E -i -e '/# ENTRA/d' \
  -e 's|^( +command:)$|\1\n      - --provider=github\n      - --github-org='"$ORG"'\n      - --github-team='"$TEAMS"'|' \
  -e 's|(--redirect-url=https://)[^/ ]+(/oauth2/callback)|\1'"$SERVER_NAME"'\2|' \
  -e 's|(--trusted-proxy-ip=)[^ ]+|\1'"$PROXY_SUBNET"'|' \
  -e 's|^( +name: )[^ ]+( +# CHANGE-ME: name of that network)|\1'"$DOCKER_NETWORK"'\2|' \
  -e 's| +# CHANGE-ME: .*$||' /opt/ohif/docker-compose.yml
```

Das `\n` im Ersatztext braucht GNU sed, das jede gängige Linux-Distribution hat.

> **Warnung**
>
> Eine falsche Gruppe in der Compose-Datei sperrt Benutzer aus, wie in Schritt 8. Großbuchstaben zählen. Die Namen genau so
> schreiben, wie Schritt A sie auflistet: bei Keycloak mit der Option Full group path On mit dem Schrägstrich am Anfang.

> **Prüfen**
>
> ```bash
> grep -n 'CHANGE-M[E]' /opt/ohif/docker-compose.yml
> docker compose -f /opt/ohif/docker-compose.yml config --quiet && echo compose file ok
> docker compose -f /opt/ohif/docker-compose.yml config | grep -E -e '- --(provider|oidc-issuer-url|scope|allowed-group|whitelist-domain|redirect-url|email-domain|github-org|github-team)='
> ```
>
> Erwartet: Der erste Befehl gibt nichts aus. Der zweite und der dritte geben `compose file ok` und die Optionen mit den eigenen
> Werten aus. Für das Keycloak-Beispiel aus Schritt A:
>
> ```text
> compose file ok
>       - --provider=keycloak-oidc
>       - --oidc-issuer-url=https://idp.example.org/realms/pacs
>       - --scope=openid email profile groups
>       - --allowed-group=pacs-viewers
>       - --allowed-group=pacs-admins
>       - --whitelist-domain=idp.example.org
>       - --redirect-url=https://pacs.example.org/oauth2/callback
>       - --email-domain=*
> ```
>
> Für Google lautet die Liste `--provider=google`, die `--redirect-url` und `--email-domain=example.org`. Für GitHub lautet sie
> `--provider=github`, `--github-org=my-org`, `--github-team=pacs-viewers,pacs-admins`, die `--redirect-url` und
> `--email-domain=*`. Eine Entra-Zeile, `TENANT-ID` oder `CHANGE-ME` in der Ausgabe heißt, dass ein Befehl oben nicht gelaufen
> ist.

<a id="login-oauth2-group-names"></a>
#### Schritt D. Die Admin-Gruppe in nginx setzen

`pacs/site.conf` enthält den Host-Namen und die Admin-Gruppe, wie in [Schritt 9](#login-oauth2-site). Die Compose-Datei nimmt einen
Gruppennamen, wie er ist. nginx nicht. Es fügt den Wert von `$pacs_admin_group` unverändert in eine Webadresse (eine URL) ein, die
es an oauth2-proxy schickt. Darum muss der Wert in `site.conf` in **Prozentform** (englisch percent-encoding) stehen: Ein Zeichen,
das eine Webadresse nicht erlaubt, wird zu einem Prozentzeichen und zwei Hexziffern. Die Objekt-IDs von Entra und die Namen in den
Beispielen oben brauchen keine Änderung. Ein Name mit Leerzeichen schon: nginx schreibt dann `auth request unexpected status: 400` ins
Log, und `/admin/` antwortet 500.

| Zeichen im Namen | In `site.conf` schreiben |
|---|---|
| Leerzeichen | `%20` |
| `&` | `%26` |
| `=` | `%3D` |
| `%` | `%25` |
| `+` | `%2B` |
| ein Buchstabe mit Akzent, zum Beispiel `ü` | seine UTF-8-Bytes, zum Beispiel `%C3%BC` |

Buchstaben, Ziffern und die Zeichen `- _ . ~ : / @` bleiben, wie sie sind. Ein Komma kann nicht Teil eines Gruppennamens sein,
weil oauth2-proxy eine Liste an Kommas trennt. Für jedes andere Zeichen den Befehl unten benutzen. Er wandelt einen ganzen Namen
um:

```bash
python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe="-_.~:/@"))' 'authentik Admins'
```

Erwartete Ausgabe:

```text
authentik%20Admins
```

Die zwei Werte setzen und den Block ausführen. `ADMIN_GROUP_ENC` ist die Admin-Gruppe in Prozentform:

```bash
SERVER_NAME=CHANGE-ME-HOST-NAME
ADMIN_GROUP_ENC=CHANGE-ME-ADMIN-GROUP
sed -E -i -e 's|^(server_name +)[^;]+;.*|\1'"$SERVER_NAME"';|' \
          -e 's|^(set \$pacs_admin_group +)[^;]+;.*|\1'"$ADMIN_GROUP_ENC"';|' /opt/ohif/nginx/pacs/site.conf
```

**Google.** Die Admin-Stufe ist eine Liste von E-Mail-Adressen. Zwei Änderungen bringen nginx dazu, oauth2-proxy nach einer
Adresse statt nach einer Gruppe zu fragen. Zuerst die Frage in der nginx-Datei ändern (ein Wort, in der einzigen Zeile, die es
enthält):

```bash
sed -i 's/allowed_groups=/allowed_emails=/' /opt/ohif/nginx/pacs/login/locations.conf
grep -n 'allowed_' /opt/ohif/nginx/pacs/login/locations.conf
```

Erwartete Ausgabe des zweiten Befehls:

```text
39:    proxy_pass $pacs_auth/oauth2/auth?allowed_emails=$pacs_admin_group;
```

Dann den Block oben ausführen, mit `ADMIN_GROUP_ENC` gesetzt auf die Liste der Adressen, durch Kommas getrennt und ohne
Leerzeichen, zum Beispiel `anna@example.org,ben@example.org`. Die Datei `locations.conf` ist nicht die Datei, die man normalerweise
bearbeitet. Eine Aktualisierung der nginx-Dateien überschreibt diese Änderung, also notieren.

> **Warnung**
>
> Die Admin-Gruppe in `site.conf` und die Admin-Gruppe in der Compose-Datei müssen dieselbe Gruppe nennen (Google: `site.conf`
> enthält die Adressen, die Compose-Datei enthält keine Admin-Gruppe). Ein falscher Wert gibt 403 für alle auf `/admin/`. Ein
> leerer Wert gibt 500. Der mitgelieferte Platzhalter `00000000-0000-0000-0000-000000000000` hält `/admin/` geschlossen, bis er
> ersetzt wird.

> **Prüfen**
>
> ```bash
> grep -rn 'CHANGE-M[E]' /opt/ohif/nginx /opt/ohif/docker-compose.yml
> grep -n 'server_name\|pacs_admin_group' /opt/ohif/nginx/pacs/site.conf
> ```
>
> Erwartet: Der erste Befehl gibt nichts aus. Der zweite gibt die zwei eigenen Werte aus, zum Beispiel:
>
> ```text
> 4:server_name pacs.example.org;
> 20:set $pacs_admin_group pacs-admins;
> ```

Jetzt die Container starten und die Prüfung aus [Schritt 10](#login-oauth2-start) ausführen. Bei einem anderen Anbieter führt die
Umleitung in ihrer letzten Zeile zum Host des eigenen Anbieters, zum Beispiel `302 https://idp.example.org`.

<a id="login-oauth2-check"></a>
#### Schritt E. Die Gruppen mit einem Testkonto prüfen

Mit echten Konten in einem privaten Browserfenster testen: ein Konto, das nur in der Viewer-Gruppe ist, und eines, das in der
Admin-Gruppe ist. Dieser Schritt beweist, dass der Anbieter die Gruppen unter den Namen schickt, die man notiert hat.

> **Prüfen**
>
> 1. Mit dem Viewer-Konto anmelden. Der Viewer öffnet sich. `https://pacs.example.org/oauth2/userinfo` öffnen. Die Seite zeigt
>    eine Zeile JSON-Text. Der Eintrag `groups` listet die Gruppen dieses Kontos so, wie der Anbieter sie schickt. Google schickt
>    keine Gruppen: stattdessen den Eintrag `email` lesen. Diese Ausgabe wurde nicht gegen einen echten Anbieter ausgeführt.
> 2. `https://pacs.example.org/admin/` mit dem Viewer-Konto öffnen: nginx zeigt `403 Forbidden`.
> 3. In einem anderen privaten Fenster mit dem Admin-Konto anmelden. Der Eintrag `groups` enthält die Admin-Gruppe, genau so
>    geschrieben wie in der Compose-Datei. Google: Der Eintrag `email` ist eine der Adressen aus `ADMIN_LIST`.
> 4. `https://pacs.example.org/admin/` mit dem Admin-Konto öffnen: Die Admin-Seite öffnet sich.
>
> Zeigt Punkt 4 für das Admin-Konto 403 oder 500, oder zeigt Punkt 2 statt 403 ein 500: siehe
> [Fehlersuche](troubleshooting.de.md#admin-403) und [Fehlersuche](troubleshooting.de.md#admin-500). Öffnet Punkt 2 die
> Admin-Seite, ist dieses Konto in der Admin-Gruppe, oder `$pacs_admin_group` nennt die Viewer-Gruppe.

Ein abgelehnter Benutzer bekommt keine Sitzung. Darum kann `/oauth2/userinfo` nicht zeigen, was der Anbieter für diesen Benutzer
geschickt hat: Es antwortet 401. Landet das Viewer-Konto direkt nach der Anmeldung auf der Seite „Forbidden“, im Log von
oauth2-proxy nachsehen:

```bash
docker logs ohif-auth 2>&1 | tail -20
```

Die Zeile `Invalid authentication via OAuth2: unauthorized` markiert eine abgelehnte Anmeldung. Entweder ist das Konto in keiner der
`--allowed-group`-Gruppen, oder der Anbieter hat keine Gruppen geschickt. Eine erfolgreiche Anmeldung hinterlässt die Zeile
`Authenticated via OAuth2:` mit der Sitzung, und die Sitzung listet die Gruppen, die der Anbieter geschickt hat. Diese Namen mit
den Namen in der Compose-Datei Buchstabe für Buchstabe vergleichen. Die Token-Vorschau des Anbieters (Keycloak: Schritt A) zeigt
die Namen ohne erfolgreiche Anmeldung. Mehr zu diesem Fehler: [Fehlersuche](troubleshooting.de.md#viewer-403-after-login). Beide
Zeilen stammen aus dem Quellcode von oauth2-proxy `v7.15.4`.

<a id="login-oauth2-signout-other"></a>
#### Schritt F. Abmelde-Link für einen anderen Anbieter (optional)

[Schritt 11](#login-oauth2-signout) hat den Link `Abmelden` mit der Adresse `/oauth2/sign_out` hinzugefügt. Zuerst Schritt 11
ausführen. Diese Adresse beendet nur die PACS-Sitzung. Die meisten Anbieter führen eine eigene Sitzung weiter, und der nächste
Klick meldet den Benutzer ohne Passwort wieder an. Viele Anbieter geben eine Abmelde-Adresse bekannt. oauth2-proxy kann den
Browser dorthin schicken, nachdem es die eigene Sitzung beendet hat. Den Anbieter nach der Adresse fragen:

```bash
ISSUER=https://idp.example.org/realms/pacs
END=$(curl -s "${ISSUER%/}/.well-known/openid-configuration" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("end_session_endpoint",""))')
echo "$END"
```

Keycloak gibt eine Adresse wie `https://idp.example.org/realms/pacs/protocol/openid-connect/logout` bekannt. Ist die Zeile leer,
hat der Anbieter keine solche Adresse. Dann `/oauth2/sign_out` behalten. Google und GitHub haben keine.

Die Adresse in `abmeldenUrl` eintragen. Die Adresse darin muss in Prozentform stehen, weil sie der Wert eines Parameters ist. Die
Befehle wandeln sie um, ändern die Zeile in `config.js` und starten den Container neu:

```bash
ENC=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$END")
sed -i "s|abmeldenUrl: '[^']*'|abmeldenUrl: '/oauth2/sign_out?rd=$ENC'|" /opt/ohif/config.js
cd /opt/ohif && docker compose restart ohif
```

Der Host-Name der Abmelde-Adresse muss der in `--whitelist-domain` sein (Schritt C setzt ihn aus der Issuer-Adresse). Liegt die
Abmelde-Adresse auf einem anderen Host, diesen Host als zweite Zeile `--whitelist-domain=HOST` in die Compose-Datei eintragen und
`docker compose up -d` ausführen.

> **Prüfen**
>
> ```bash
> grep -o "abmeldenUrl: '[^']*'" /opt/ohif/config.js
> ```
>
> Erwartete Ausgabe für das Keycloak-Beispiel (die Adresse stammt von einem Ersatz-Anbieter):
>
> ```text
> abmeldenUrl: '/oauth2/sign_out?rd=https%3A%2F%2Fidp.example.org%2Frealms%2Fpacs%2Fprotocol%2Fopenid-connect%2Flogout'
> ```
>
> Die Admin-Seite ohne Cache neu laden (Strg+F5) und `Abmelden` wählen. Der Browser sollte bei der Anmeldeseite des Anbieters
> ankommen. Nicht gegen einen echten Anbieter ausgeführt. Neuere Keycloak-Versionen können eine Bestätigungsseite zeigen oder
> einen Parameter `id_token_hint` verlangen. In diesem Fall `/oauth2/sign_out` behalten und den Benutzern sagen, dass sie das
> Browserfenster schließen sollen.

<a id="login-basic"></a>
## 3. Anmeldung mit Basic-Authentifizierung

Die Basic-Authentifizierung ist eine Anmeldung, die nginx allein erledigt. Es braucht nichts außerhalb des Servers: keinen
Identitätsanbieter und keinen zusätzlichen Container. Der Browser fragt nach einem Namen und einem Passwort, und nginx vergleicht
beides mit zwei Dateien. Dieser Abschnitt passt zu den Rezepten `basic`, `adminonly`, `proxied` und `tryit`.

**Was getestet wurde.** Die Ausgaben in diesem Abschnitt stammen aus Läufen in Docker. nginx 1.30.5 las die Kontozeilen, die das
Skript geschrieben hatte. Das Skript lief in einem Root-Container mit OpenSSL 3.5.7. Das OHIF-Image selbst lief nicht. Die eigene
Einrichtung belegt erst der Anmeldetest in [3.4](#login-basic-start).

- [3.1 So funktioniert es](#login-basic-how)
- [3.2 Vor dem Start](#login-basic-before)
- [3.3 Das erste Konto anlegen](#login-basic-first)
- [3.4 Starten und prüfen](#login-basic-start)
- [3.5 Alltag: Konten hinzufügen, ändern und entfernen](#login-basic-accounts)
- [3.6 Wenn etwas schiefgeht](#login-basic-errors)
- [3.7 Grenzen](#login-basic-limits)

<a id="login-basic-how"></a>
### 3.1 So funktioniert es

Bei der ersten Anfrage öffnet der Browser sein eigenes Anmeldefenster und fragt nach einem Namen und einem Passwort
([Basic-Authentifizierung](glossary.de.md#basic-auth)). Das Fenster gehört dem Browser, nicht dem PACS. Bei jeder weiteren
Anfrage schickt der Browser Name und Passwort erneut. nginx vergleicht sie mit zwei Dateien im Ordner `/opt/ohif/htpasswd`. Das
Format der Dateien heißt [htpasswd](glossary.de.md#htpasswd).

| Datei | Enthält | Öffnet |
|---|---|---|
| `users` | Jedes Konto | Den Viewer, die Studiensuche und das Lesen |
| `admins` | Nur die Admins | `/admin/` und jede Änderung |

Ein Admin braucht eine Zeile in **beiden** Dateien. Für die Pfade in der ersten Zeile der Tabelle liest nginx `users`. Für die
Pfade in der zweiten Zeile liest es `admins` und nicht `users`. Die Admin-Seite nutzt auch die Studiensuche, einen Pfad der
ersten Zeile. Eine Zeile sieht so aus: `anna:$6$...`: der Name, ein Doppelpunkt und der Passwort-Hash. Ein Hash ist eine
verwürfelte Form des Passworts, die niemand in das Passwort zurückverwandeln kann. Das Skript aus [3.3](#login-basic-first)
schreibt die Zeilen. Die Dateien bearbeitet man nicht von Hand.

Was der Benutzer sieht:

| Anfrage | Ergebnis |
|---|---|
| Kein Name und kein Passwort | 401. Der Browser öffnet sein Anmeldefenster |
| Richtiger Name und richtiges Passwort, Konto in `users` | Der Viewer öffnet sich |
| Falsches Passwort | 401. Das Fenster öffnet sich wieder |
| `/admin/` mit einem Konto, das nur in `users` steht | 401. Das Fenster öffnet sich wieder, weil die Basic-Authentifizierung nicht „bekannt, aber nicht erlaubt“ antworten kann |
| `/admin/` mit einem Konto in `admins` | Die Admin-Seite öffnet sich |

nginx liest beide Dateien bei jeder Anfrage. Ein neues Konto wirkt sofort, ohne Neustart. Das Protokoll nennt das Konto:
[Abschnitt 8](#login-audit) zeigt, wie.

<a id="login-basic-before"></a>
### 3.2 Vor dem Start

- Das https-Zertifikat liegt bereit ([install.de.md#tls-certificate](install.de.md#tls-certificate)). Warum: Der Browser schickt
  das Passwort bei jeder Anfrage. Ohne https kann es jeder auf dem Netzweg lesen. Das einzige Rezept mit reinem http ist `tryit`;
  es lauscht auf 127.0.0.1 und wird über einen SSH-Tunnel erreicht.
- Der Ordner der Compose-Datei, hier `/opt/ohif`, existiert und enthält die nginx-Dateien der Anmeldung `basic`.
- OpenSSL ist auf dem Server installiert. Das Skript braucht Version 1.1.1 oder neuer (`openssl version` zeigt sie).

> **Prüfen**
>
> ```bash
> grep -m1 -o 'Login [a-z0-9-]*' /opt/ohif/nginx/pacs/login/http.conf
> ls -d /opt/ohif /opt/ohif/docker-compose.yml
> ```
>
> Erwartet:
>
> ```text
> Login basic
> /opt/ohif
> /opt/ohif/docker-compose.yml
> ```
>
> Sagt die erste Zeile `Login oauth2-proxy` oder `Login none`, wurden die Dateien einer anderen Anmeldung kopiert. Zurück zu
> [install.de.md](install.de.md) gehen und die Dateien der Anmeldung `basic` kopieren.

<a id="login-basic-first"></a>
### 3.3 Das erste Konto anlegen

Das Skript `pacs-adduser.sh` erzeugt die Zeilen eines Kontos. Es fragt zweimal nach dem Passwort und blendet die Eingabe aus. Es
legt den Ordner `htpasswd` an, bildet den Hash des Passworts, schreibt die Zeilen und gibt den Dateien den Besitzer und den
Modus, die nginx braucht. Das erste Konto sollte ein Admin sein. Das Skript als root ausführen:

```bash
bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh admin anna
```

- Das erste Wort ist die Stufe. `admin` legt ein Konto für den Viewer und für `/admin/` an. `all` legt ein Konto nur für den
  Viewer an.
- Der Name besteht aus Buchstaben, Ziffern, `.`, `_` und `-`, höchstens 32 Zeichen.
- Das Passwort hat mindestens 10 Zeichen und höchstens 256 Byte. Sonderzeichen und Umlaute funktionieren.

Das Skript gibt die beiden Eingabeaufforderungen aus und dann, was es getan hat:

```text
Passwort fuer anna (mindestens 10 Zeichen, unsichtbar):
Passwort wiederholen:
Konto 'anna' (admin)
  Verzeichnis /opt/ohif/htpasswd angelegt (Modus 755)
  /opt/ohif/htpasswd/users: Zeile hinzugefuegt
  /opt/ohif/htpasswd/admins: Zeile hinzugefuegt
  Besitzer 101, Modus 600, Passwort-Hash-Typ sha512-crypt
  nginx liest die Dateien bei jeder Anfrage: kein Neustart noetig.
```

Das Skript gibt Deutsch aus, wenn die erste der Variablen `LC_ALL`, `LC_MESSAGES` und `LANG`, die gesetzt ist, mit `de` beginnt
(eine deutsche Spracheinstellung des Servers). Sonst gibt es Englisch aus. Es schreibt Umlaute als `ae`, `oe`, `ue` und `ss`.
Alle Ausgaben des Skripts in dieser Anleitung sind die deutschen. Die englische Fassung dieser Anleitung,
[login.md](login.md#login-basic-first), zeigt die englischen.

Die Dateien müssen dem Benutzer mit der Nummer 101 gehören (dem Benutzer von nginx im OHIF-Image) und den Modus 600 haben, damit
nur nginx sie lesen kann. Nur root kann diesen Besitzer setzen. Der Ordner `/opt/ohif` muss schon existieren: Das Skript legt den
Unterordner `htpasswd` darin an, nicht den Ordner selbst. Für einen anderen Ordner dient die Option `--dir`
([3.5](#login-basic-accounts)).

> **Warnung**
>
> Dateien eines anderen Besitzers kann nginx nicht lesen, und jede Anfrage mit Passwort endet mit 500. Startet man das Skript
> ohne Root-Rechte, beginnt die Zeile nach den Dateizeilen mit `Modus 600, Hash-Typ sha512-crypt. WARNUNG: nicht als root
> gestartet, der Besitzer wurde nicht auf 101 gesetzt.` Das Skript noch einmal als root ausführen.
>
> Der Hash-Typ `sha512-crypt` braucht OpenSSL 1.1.1 oder neuer. Mit einem älteren OpenSSL gibt das Skript `pacs-adduser: WARNUNG:
> dieses openssl kann keine sha512-crypt-Hashes (ab 1.1.1). Es wird apr1 benutzt, der schwaechere Hash-Typ. openssl aktualisieren
> und das Passwort erneut setzen.` aus, und die Zeile mit der Zusammenfassung endet mit `Passwort-Hash-Typ apr1`. nginx 1.30.5
> akzeptierte auch diesen Hash-Typ. OpenSSL aktualisieren und das Skript für jedes Konto noch einmal ausführen. Der Warntext und
> die Zeile mit der Zusammenfassung stammen aus einem Lauf, in dem ein Ersatzprogramm für `openssl` die Option `-6` ablehnte.
> Ein echtes OpenSSL vor 1.1.1 wurde nicht ausprobiert.

> **Prüfen**
>
> ```bash
> ls -ln /opt/ohif/htpasswd
> cd /opt/ohif/htpasswd && grep -o '^[^:]*' users admins
> ```
>
> Erwartet: zwei Dateien des Benutzers 101 (Gruppe 0) mit dem Modus `-rw-------` und der Kontoname in beiden Listen:
>
> ```text
> total 8
> -rw------- 1 101 0 112 Oct 14 07:54 admins
> -rw------- 1 101 0 112 Oct 14 07:54 users
> users:anna
> admins:anna
> ```
>
> Die Größe ist die Länge des Namens plus 108: der Name, ein Doppelpunkt, ein Hash von 106 Zeichen und ein Zeilenumbruch. Ein
> anderer Name ergibt eine andere Zahl. Die erste Zeile und das Datum stammen aus einem Lauf mit englischer Spracheinstellung; bei
> einer deutschen Spracheinstellung lauten sie anders. Der zweite Befehl gibt nur die Namen aus. Nie die ganzen Dateien ausgeben:
> Die Hashes stehen darin.
>
> Eine andere Meldung: siehe [3.6](#login-basic-errors).

<a id="login-basic-start"></a>
### 3.4 Starten und prüfen

Die Compose-Datei hängt den Ordner `htpasswd` in den Container ein. Laufen die Container noch nicht, sie wie in
[install.de.md](install.de.md#start-and-check) starten. Laufen sie, braucht nichts einen Neustart.

> **Prüfen**
>
> ```bash
> curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/
> curl -sk -u anna -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/
> curl -sk -u anna https://pacs.example.org/oauth2/userinfo
> ```
>
> Der zweite und der dritte Befehl fragen nach dem Passwort von `anna`. Erwartet: 401 ohne Passwort, 200 für die Admin-Seite und
> die Kontobezeichnung, die die Admin-Seite oben zeigt:
>
> ```text
> 401
> 200
> {"preferredUsername":"anna"}
> ```
>
> Das `-k` heißt „ein selbstsigniertes Zertifikat akzeptieren“. Bei einem Zertifikat einer echten Zertifizierungsstelle
> weglassen. Ist die erste Zahl nicht 401, oder ist die zweite 401 trotz des richtigen Passworts: siehe
> [Fehlersuche](troubleshooting.de.md#basic-login-401) und [3.6](#login-basic-errors).

Dann `https://pacs.example.org/admin/` in einem privaten Browserfenster öffnen. Der Browser fragt nach dem Namen und dem Passwort.
Nach der Anmeldung öffnet sich die Admin-Seite, und der Kontoname steht oben auf ihr.

<a id="login-basic-accounts"></a>
### 3.5 Alltag: Konten hinzufügen, ändern und entfernen

Das Skript einmal für jede Person ausführen. Es sagt, was es mit jeder Datei getan hat.

**Einen Viewer hinzufügen.** Das Konto steht nur in `users`:

```bash
bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh all ben
```

```text
Konto 'ben' (all)
  /opt/ohif/htpasswd/users: Zeile hinzugefuegt
  /opt/ohif/htpasswd/admins: keine Zeile (kein Admin)
  Besitzer 101, Modus 600, Passwort-Hash-Typ sha512-crypt
  nginx liest die Dateien bei jeder Anfrage: kein Neustart noetig.
```

**Einen Viewer zum Admin machen oder umgekehrt.** Das Skript mit der anderen Stufe und demselben Namen ausführen. Das Skript fragt
wieder nach einem Passwort und setzt es. Die Zeile in `users` wird ersetzt, die Zeile in `admins` wird hinzugefügt oder entfernt:

```bash
bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh admin ben
```

```text
Konto 'ben' (admin)
  /opt/ohif/htpasswd/users: Zeile ersetzt (das Konto gab es schon, das Passwort ist neu)
  /opt/ohif/htpasswd/admins: Zeile hinzugefuegt
  Besitzer 101, Modus 600, Passwort-Hash-Typ sha512-crypt
  nginx liest die Dateien bei jeder Anfrage: kein Neustart noetig.
```

Mit dem Wort `all` verliert der Admin das Recht sofort wieder. Das Skript gibt dann
`/opt/ohif/htpasswd/admins: Zeile entfernt (das Konto ist kein Admin mehr)` aus.

**Ein neues Passwort setzen.** Das Skript noch einmal mit derselben Stufe und demselben Namen ausführen. Die Zeile in `users`
lautet `Zeile ersetzt (das Konto gab es schon, das Passwort ist neu)`. Bei einem Admin sagt die Zeile in `admins` dasselbe.

**Ein Konto entfernen.** Die Zeile aus beiden Dateien löschen. Ein Punkt im Namen wird im Muster als `\.` geschrieben, zum
Beispiel `/^anna\.b:/d`. Der Befehl behält Besitzer und Modus der Dateien:

```bash
sed -i '/^ben:/d' /opt/ohif/htpasswd/users /opt/ohif/htpasswd/admins
```

> **Warnung**
>
> Das Konto aus beiden Dateien löschen, sonst kann ein ausgeschiedener Admin weiter den Viewer oder `/admin/` öffnen. Mindestens
> einen Admin behalten. Eine leere Datei `admins` beantwortet `/admin/` für alle mit 401.

**Die Konten auflisten**, ohne die Hashes:

```bash
cd /opt/ohif/htpasswd && grep -o '^[^:]*' users admins
```

> **Prüfen**
>
> Erwartet nach den Befehlen oben (`anna` ist Admin, `ben` ein Viewer). Dann mit dem Viewer-Konto die Admin-Seite anfordern. Die
> Anfrage darf nicht durchgehen:
>
> ```bash
> curl -sk -u ben -o /dev/null -w '%{http_code}\n' https://pacs.example.org/
> curl -sk -u ben -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/
> ```
>
> ```text
> users:anna
> users:ben
> admins:anna
> 200
> 401
> ```
>
> Der Befehl `grep` oben gibt die Namen aus. Die beiden `curl`-Befehle fragen nach dem Passwort von `ben`.

**Passwörter in Skripten.** Ist die Eingabe des Skripts kein Terminal, liest es eine Zeile als Passwort. Es fragt dann nicht
zweimal. Das Passwort nie auf die Kommandozeile schreiben, weil jeder Benutzer des Servers es dort und im Verlauf der Shell lesen
kann:

```bash
printf '%s\n' "$PW" | bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh admin anna
```

**Ein anderer Ordner, ein anderes nginx.** Die Optionen `--dir`, `--users`, `--admins`, `--owner` und `--mode` ändern, wo die
Dateien liegen und wem sie gehören. Man braucht sie für einen anderen Compose-Ordner als `/opt/ohif` und für ein nginx, das
auf dem Host installiert ist ([install.de.md#nginx-on-host](install.de.md#nginx-on-host)), wo die Worker als `www-data` laufen:

```bash
bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh admin anna --dir /srv/pacs
bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh admin anna --users /etc/nginx/htpasswd/users --admins /etc/nginx/htpasswd/admins --owner root:www-data --mode 640
```

**Von Hand.** Das Skript ist der bessere Weg. Muss man eine Zeile selbst schreiben, bildet man den Hash mit OpenSSL und hängt die
Zeile an. Das Passwort bleibt dann im Verlauf der Shell, also ein Passwort nehmen, das man danach mit dem Skript ändert:

```bash
printf '%s:%s\n' NAME "$(printf '%s' 'PASSWORD' | openssl passwd -6 -stdin)" >> /opt/ohif/htpasswd/users
```

Der Hash beginnt mit `$6$`. Für einen Admin dieselbe Zeile auch in `admins` eintragen.

<a id="login-basic-errors"></a>
### 3.6 Wenn etwas schiefgeht

Das Fehlerlog von nginx nennt das Konto und die Datei. Zuerst das Log lesen:

```bash
docker logs ohif 2>&1 | grep -E 'user "|htpasswd' | tail -5
```

Die Zeilen sehen so aus (ein Testlauf, mit den Kontonamen `clara` und `vera`):

```text
2026/10/14 07:39:56 [error] 98#98: *3 user "clara": password mismatch, client: 127.0.0.1, server: pacs.example.org, request: "GET / HTTP/2.0", host: "localhost:8443"
2026/10/14 07:39:56 [error] 100#100: *5 user "vera" was not found in "/etc/nginx/htpasswd/admins", client: 127.0.0.1, server: pacs.example.org, request: "GET /admin/ HTTP/2.0", host: "localhost:8443"
```

| Was geschieht | Zeile im Log | Ursache und Abhilfe |
|---|---|---|
| Das Anmeldefenster kommt nach dem richtigen Passwort wieder | `user "clara": password mismatch` | Das Passwort weicht ab. Es mit dem Skript neu setzen |
| Das Fenster kommt nur bei `/admin/` wieder | `user "vera" was not found in "/etc/nginx/htpasswd/admins"` | `vera` ist ein Viewer-Konto. Das Skript mit `admin vera` ausführen |
| Das Fenster kommt sofort wieder | `user "vera" was not found in "/etc/nginx/htpasswd/users"` | Das Konto gibt es nicht, oder der Name ist anders geschrieben. Das Skript ausführen |
| 403 auf den Viewer-Seiten gleich nach dem Passwort. `/admin/` öffnet sich noch | `open() "/etc/nginx/htpasswd/users" failed (2: No such file or directory)` | Die Datei `users` fehlt. Fehlt neben der Compose-Datei der Ordner `htpasswd`, hat Docker einen leeren angelegt. Das erste Konto anlegen ([3.3](#login-basic-first)) |
| 403 nur auf `/admin/` | Dieselbe Zeile mit `admins` | Die Datei `admins` fehlt. Das Skript mit `admin` für ein Konto ausführen |
| 500 auf jeder Seite nach dem Passwort | `[crit] ... open() ... failed (13: Permission denied)` | Besitzer oder Modus der Dateien stimmt nicht. Das Skript als root ausführen: Es setzt Besitzer 101 und Modus 600 |
| 401 auf `/admin/` für alle | Keine | Die Datei `admins` ist leer. Einen Admin anlegen |

Eine Anfrage ohne Namen und Passwort beantwortet nginx in jedem Fall mit 401, weil es die Dateien dann nicht öffnet. Eine fehlende
Datei zeigt sich darum erst beim ersten Anmeldeversuch. Zeilen wie `[alert] connect() failed (111: Connection refused) while
logging to syslog` stammen vom Protokoll und nicht von der Anmeldung: Der Hilfsdienst läuft nicht. (Bei `(2: No such file or
directory)` ist der Dienst seit dem Start des Servers nicht gelaufen.) Siehe [reference.de.md](reference.de.md#audit-lost).

In diesen Fällen hält das Skript mit einer Meldung an und ändert nichts:

| Das Skript gibt aus | Bedeutung |
|---|---|
| `pacs-adduser: ungueltiger Name 'anna@example.org': nur Buchstaben, Ziffern, . _ - erlaubt` | Der Name enthält ein Zeichen, das nicht erlaubt ist |
| `pacs-adduser: der Name darf keinen Doppelpunkt enthalten (er trennt Name und Passwort-Hash in der Datei): 'anna:x'` | Ein Doppelpunkt im Namen |
| `pacs-adduser: das Passwort ist kuerzer als 10 Zeichen, nichts geaendert` | Mindestens 10 Zeichen nehmen |
| `pacs-adduser: die beiden Passwoerter sind verschieden, nichts geaendert` | Die zweite Eingabe weicht von der ersten ab |
| `pacs-adduser: das Passwort ist 257 Byte lang: hoechstens 256 Byte funktionieren (der Hash umfasst nur die ersten 256, nginx wuerde das richtige Passwort ablehnen). Nichts geaendert.` | Höchstens 256 Byte nehmen |
| `pacs-adduser: Verzeichnis /nonexistent gibt es nicht (--dir VERZEICHNIS angeben)` | Der Compose-Ordner existiert nicht. Ihn anlegen oder mit `--dir` den richtigen nennen |
| `pacs-adduser: Rolle muss 'all' oder 'admin' sein, nicht 'both'` | Das erste Wort ist falsch. Nach dieser Zeile gibt das Skript seinen Aufruf aus |

Mehr: [Fehlersuche](troubleshooting.de.md#htpasswd-403-500) und [Fehlersuche](troubleshooting.de.md#basic-login-401).

<a id="login-basic-limits"></a>
### 3.7 Grenzen

- **Keine Abmeldung.** Der Browser behält Name und Passwort, bis er schließt. Zum Abmelden das Browserfenster schließen.
- **Kein zweiter Faktor.** Es gibt nur das Passwort. Ein langes Passwort und https nutzen. Wer MFA braucht, nimmt oauth2-proxy
  ([Abschnitt 2](#login-oauth2)).
- **Keine Sperre bei falschen Passwörtern.** nginx sperrt ein Konto nach Fehlversuchen nicht. Jeder Versuch steht im Protokoll
  unter dem Namen, der eingegeben wurde ([Abschnitt 8](#login-audit)).
- **Benutzer können ihr Passwort nicht ändern.** Ein Admin führt das Skript aus.
- **Ein Konto pro Person.** Das Protokoll nennt das Konto, also verbirgt ein gemeinsames Konto, wer was getan hat.
- **Absichtlich ein schneller Hash.** nginx prüft das Passwort bei jeder Anfrage. Der Hash-Typ sha512-crypt mit der
  Standardzahl an Runden hält das billig. Ein langsamerer Hash würde jede Seite verlangsamen. Der Hash-Typ bcrypt (`$2y$`) wird
  nicht von jeder C-Bibliothek gelesen, also benutzt das Skript ihn nicht. Ob das nginx des OHIF-Images `$6$`-Hashes liest, wurde
  hier nicht geprüft: Der Anmeldetest in [3.4](#login-basic-start) ist der Beweis.

<a id="login-none"></a>
## 4. Keine Anmeldung: Netzlisten

Die Anmeldung `none` hat keine Konten und keine Passwörter. nginx lässt eine Anfrage durch, wenn die Adresse des PCs auf einer Liste
steht. Die Anmeldung nutzt die Compose-Datei des Rezepts `basic` und die nginx-Dateien aus `deploy/nginx/login/none`
([install.de.md](install.de.md#nginx-files)).

> **Warnung**
>
> Das ist die schwächste Anmeldung. Jeder, der an einem PC auf einer Liste sitzt, hat den Zugang dieser Liste, und niemand muss
> sich ausweisen. Das Protokoll nennt die Adresse des PCs (`anon-192.0.2.77`) und keine Person. `none` nur in einem geschlossenen
> Netz nutzen, in dem man jedem PC auf den Listen vertraut, und beide Listen kurz halten. Für alles andere
> [basic](#login-basic) oder [oauth2-proxy](#login-oauth2) nehmen.

**Was getestet wurde.** Die Ausgaben in diesem Abschnitt stammen aus Läufen in Docker mit nginx 1.30.5. Die vollständige
Einrichtung mit der Anmeldung `none` lief in einer Testumgebung (nginx, ein Ersatz für dcm4chee und der echte
[Hilfsdienst](glossary.de.md#helper-service)). Alle 320 Anfrageprüfungen und alle 49 Prüfungen des Protokolls bestanden. Die Listen
aus [4.1](#login-none-how) liefen in allen vier Kombinationen. Die Änderungsbefehle aus [4.2](#login-none-lists) und die Logzeilen
aus [4.3](#login-none-check) stammen aus Läufen auf Kopien der Dateien. Nicht ausgeführt: ein SSH-Tunnel, ein PC hinter einem
Router mit Adressübersetzung und IPv6.

- [4.1 So funktioniert es](#login-none-how)
- [4.2 Die beiden Listen setzen](#login-none-lists)
- [4.3 Das Ergebnis prüfen](#login-none-check)
- [4.4 Grenzen](#login-none-limits)

<a id="login-none-how"></a>
### 4.1 So funktioniert es

nginx liest die Adresse des PCs aus der Verbindung. Es vergleicht die Adresse mit den Zeilen `allow` und `deny` einer Liste und
nimmt die erste Zeile, die passt. Eine Adresse, die keine Zeile `allow` nennt, trifft auf `deny all;` und bekommt die Antwort 403
(„verboten“, englisch forbidden). Der Browser zeigt eine schlichte Seite mit dem Text `403 Forbidden`.

Zwei Dateien enthalten die beiden Listen und liegen im Ordner `/opt/ohif/nginx/pacs/login/`:

| Datei | Liste | Was sie abdeckt |
|---|---|---|
| `server.conf` | Viewer-Liste | Den Viewer, die Studiensuche und jedes andere Lesen. Das ist alles, wofür es keine engere Liste gibt |
| `admin.conf` | Admin-Liste | Die Seite `/admin/`, den Abschnitt für die dcm4chee-Benutzeroberfläche, die Patientenliste, die Ansicht der abgelehnten Studien und jede Änderung |

Die Admin-Liste **ersetzt** an diesen Stellen die Viewer-Liste. nginx zählt die beiden Listen nicht zusammen. Vier Fälle zeigen,
was geschieht (getestet):

| Die Adresse des PCs steht auf | Viewer und Studiensuche | `/admin/` und Änderungen |
|---|---|---|
| keiner Liste | 403 | 403 |
| nur der Viewer-Liste | öffnet sich | 403 |
| nur der Admin-Liste | 403 | öffnet sich |
| beiden Listen | öffnet sich | öffnet sich |

Jeden Admin-PC auf **beide** Listen setzen. Die Admin-Seite sucht Studien über die Viewer-Liste. Ein PC, der nur auf der Admin-Liste
steht, öffnet die Seite, aber seine Studiensuche bekommt 403.

Es gibt keine Konten, also nennt das Protokoll den PC: `anon-` und die Adresse, zum Beispiel `anon-192.0.2.77`. Die Admin-Seite
zeigt diese Bezeichnung oben an. nginx nimmt die Adresse aus der Verbindung und liest sie nicht aus einem Header der Anfrage. Ein
Header, den ein Client schreibt, ändert die Bezeichnung nicht (getestet mit gefälschtem `Authorization`, `X-Auth-User`,
`X-Real-IP` und `X-Forwarded-For`). Der Listener `behind-proxy` ist die einzige Ausnahme: Er nimmt die Adresse aus dem Header eines
Proxys, den man nennt ([Abschnitt 5](#login-other)). [Abschnitt 8](#login-audit) zeigt die Zeilen des Protokolls.

Die Compose-Datei des Rezepts `basic` hängt den Ordner `htpasswd` ein. Bei der Anmeldung `none` liest nginx ihn nie. Den leeren
Ordner trotzdem anlegen ([install.de.md](install.de.md#login-setup)), damit Docker ihn nicht als Ordner von root anlegt.

<a id="login-none-lists"></a>
### 4.2 Die beiden Listen setzen

Die Listen in [install.de.md](install.de.md#nginx-files) setzen, nach dem Kopierblock mit `LOGIN=none` und vor dem ersten Start.
Dieselben Schritte ändern die Listen später. Jede Listendatei enthält eine Beispielzeile mit der Markierung `CHANGE-ME`. Die
Beispielnetze sind Dokumentationsnetze, die kein echter PC nutzt. Bis man sie ersetzt, kommt niemand hinein.

Zuerst entscheiden, wer auf welche Liste kommt:

- Die Viewer-Liste enthält die Netze oder die einzelnen PCs, die den Viewer öffnen dürfen.
- Die Admin-Liste enthält nur die Admin-PCs. Jeden von ihnen auch auf die Viewer-Liste setzen.

Ein Netz als `ADRESSE/LÄNGE` schreiben ([CIDR](glossary.de.md#cidr)). `192.0.2.64/26` bedeutet die 64 Adressen von 192.0.2.64 bis
192.0.2.127. Einen einzelnen PC als reine Adresse schreiben, `198.51.100.10`. Den Admin-PCs feste Adressen geben. Ein PC mit
wechselnder Adresse (DHCP) bekommt eines Tages eine andere und verliert seinen Zugang. Auf einem Windows-PC zeigt der Befehl
`ipconfig` die IPv4-Adresse, auf einem Linux-PC der Befehl `ip -4 addr`. Steht ein Router zwischen dem PC und dem Server, sieht
nginx die Adresse des Routers und nicht die des PCs ([4.4](#login-none-limits)).

> **Prüfen**
>
> ```bash
> grep -m1 -o 'Login [a-z0-9-]*' /opt/ohif/nginx/pacs/login/http.conf
> grep -n CHANGE-ME /opt/ohif/nginx/pacs/login/server.conf /opt/ohif/nginx/pacs/login/admin.conf
> ```
>
> Erwartet: der Name der Anmeldung und eine Beispielzeile je Listendatei:
>
> ```text
> Login none
> /opt/ohif/nginx/pacs/login/server.conf:4:allow 192.0.2.0/24;                                # CHANGE-ME: the network of the PCs that may open the viewer
> /opt/ohif/nginx/pacs/login/admin.conf:3:allow 198.51.100.0/24;                             # CHANGE-ME: the network or the address of the administrator PCs
> ```
>
> Sagt die erste Zeile `Login basic` oder `Login oauth2-proxy`, wurden die Dateien einer anderen Anmeldung kopiert. Zurück zu
> [install.de.md](install.de.md#nginx-files) gehen und die Dateien der Anmeldung `none` kopieren. Fehlt eine Listenzeile, hat man
> diese Liste schon gesetzt.

Die beiden Beispielzeilen ersetzen. Die Befehle schneiden die alte Zeile `allow` samt ihrem Markierungskommentar ab. In die ersten
beiden Zeilen die eigenen Werte schreiben:

```bash
VIEWER_NET=192.0.2.64/26
ADMIN_NET=198.51.100.10
sed -E -i 's|^allow [^;]+;.*|allow '"$VIEWER_NET"';|' /opt/ohif/nginx/pacs/login/server.conf
sed -E -i 's|^allow [^;]+;.*|allow '"$ADMIN_NET"';|' /opt/ohif/nginx/pacs/login/admin.conf
```

Den Admin-PC auch auf die Viewer-Liste setzen. Der Befehl fügt eine Zeile `allow` über `deny all;` ein:

```bash
sed -E -i 's|^(deny all;)|allow '"$ADMIN_NET"';\n\1|' /opt/ohif/nginx/pacs/login/server.conf
```

Für jedes weitere Netz und jeden weiteren PC denselben Befehl mit einem anderen Wert nutzen. `deny all;` muss die letzte Zeile einer
Liste bleiben, weil nginx die erste Zeile nimmt, die passt.

> **Warnung**
>
> Die beiden `sed`-Befehle des ersten Blocks nicht noch einmal ausführen, sobald eine Liste mehr als eine Zeile `allow` hat. Beide
> ersetzen **jede** Zeile `allow` der Datei durch eine. Zeilen mit dem zweiten Befehl oder in einem Editor hinzufügen.

> **Prüfen**
>
> ```bash
> grep -n -E '^(allow|deny)' /opt/ohif/nginx/pacs/login/server.conf /opt/ohif/nginx/pacs/login/admin.conf
> grep -rn CHANGE-ME /opt/ohif/nginx
> ```
>
> Erwartet: die Listen mit den eigenen Werten und keine Ausgabe vom zweiten Befehl:
>
> ```text
> /opt/ohif/nginx/pacs/login/server.conf:4:allow 192.0.2.64/26;
> /opt/ohif/nginx/pacs/login/server.conf:5:allow 198.51.100.10;
> /opt/ohif/nginx/pacs/login/server.conf:6:deny all;
> /opt/ohif/nginx/pacs/login/admin.conf:3:allow 198.51.100.10;
> /opt/ohif/nginx/pacs/login/admin.conf:4:deny all;
> ```
>
> Eine Zeile mit `CHANGE-ME` in der zweiten Ausgabe ist ein Wert, den man nicht gesetzt hat. Ihn setzen, wie
> [install.de.md](install.de.md#nginx-files) es sagt.

> **Warnung**
>
> Eine falsche Liste sperrt einen nicht vom Server aus: Man bearbeitet die Datei und lässt nginx sie neu lesen. Solange die Liste
> falsch ist, können Benutzer den Viewer nicht öffnen, oder niemand kann `/admin/` öffnen. Die Admin-Liste zweimal prüfen. Nie
> `allow all;` schreiben, weil es jeden hineinlässt, und die Netze so klein halten wie möglich.

Beim ersten Start braucht es nichts weiter. Nach einer späteren Änderung die Dateien testen und nginx sie neu lesen lassen:

```bash
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

> **Prüfen**
>
> Erwartet: zwei Zeilen des Tests und eine Zeile des Neuladens (die Zahlen weichen ab):
>
> ```text
> nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
> nginx: configuration file /etc/nginx/nginx.conf test is successful
> 2026/10/14 08:45:14 [notice] 17#17: signal process started
> ```
>
> Ein Test, der fehlschlägt, gibt `[emerg]` und die Datei mit der Zeilennummer aus, und das Neuladen läuft nicht, also bleiben die
> alten Listen in Kraft. Zwei typische Meldungen: `invalid parameter "192.0.2.0/33"` (eine Netzlänge über 32) und `invalid number
> of arguments in "allow" directive` (ein fehlendes Semikolon). Die Zeile korrigieren, die die Meldung nennt, und den Befehl noch
> einmal ausführen.

<a id="login-none-check"></a>
### 4.3 Das Ergebnis prüfen

Die Prüfungen auf den PCs selbst ausführen. Die Adresse des Servers steht auf keiner Liste, also zeigt eine Prüfung auf dem Server
nichts über die PCs. `https://pacs.example.org/` und `https://pacs.example.org/admin/` in einem Browser öffnen oder die beiden
Befehle ausführen (unter Windows `curl.exe`):

```bash
curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/
curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/
```

> **Prüfen**
>
> Erwartet, je nach Art des PCs (getestet):
>
> | PC | Erster Befehl (Viewer) | Zweiter Befehl (`/admin/`) |
> |---|---|---|
> | Admin-PC auf beiden Listen | 200 | 200 |
> | PC nur auf der Viewer-Liste | 200 | 403 |
> | PC auf keiner Liste | 403 | 403 |
>
> Das `-k` heißt „ein selbstsigniertes Zertifikat akzeptieren“. Bei einem Zertifikat einer echten Zertifizierungsstelle
> weglassen. Weicht eine Zahl ab, hat eine Liste das falsche Netz. Die Adresse im Log lesen (siehe unten) und
> [Fehlersuche](troubleshooting.de.md#none-403).

Von einem PC, der zugelassen ist, zeigt die Admin-Seite oben die Bezeichnung des PCs. Die Seite liest sie von dieser Adresse:

```bash
curl -sk https://pacs.example.org/oauth2/userinfo
```

```text
{"preferredUsername":"anon-192.0.2.77"}
```

Die Adresse ist die des PCs, der gefragt hat. Ein anderer PC zeigt seine eigene Adresse.

nginx schreibt jede abgewiesene Anfrage in sein Fehlerlog, mit der Adresse, die es gesehen hat. Das Log auf dem Server lesen:

```bash
docker logs ohif 2>&1 | grep 'access forbidden by rule' | tail -3
```

Die Zeilen sehen so aus (ein Testlauf mit reinem http und einer Dokumentationsadresse):

```text
2026/10/14 08:41:35 [error] 9#9: *1 access forbidden by rule, client: 192.0.2.99, server: pacs.example.org, request: "GET /admin/ HTTP/1.1", host: "pacs.example.org"
2026/10/14 08:41:35 [error] 9#9: *2 access forbidden by rule, client: 192.0.2.200, server: pacs.example.org, request: "GET / HTTP/1.1", host: "pacs.example.org"
```

Das Wort nach `client:` ist die Adresse, die nginx gesehen hat. Ein PC, der abgewiesen wird, aber hinein soll, braucht genau diese
Adresse auf einer Liste. Ist es nicht die Adresse des PCs, [4.4](#login-none-limits) lesen. Die Zeile zeigt auch die Seite, die
der PC angefordert hat: `/admin/` in der ersten Zeile, die Viewer-Seite in der zweiten.

<a id="login-none-limits"></a>
### 4.4 Grenzen

- **Keine Namen.** Das Protokoll nennt eine Adresse. Teilen sich mehrere Personen einen PC oder arbeiten sie auf einem
  Remotedesktop-Server, steht eine Adresse für alle. Ein PC mit wechselnder Adresse erscheint unter einer neuen Bezeichnung.
- **Jeder auf einer Liste hat den ganzen Zugang dieser Liste.** Man kann einer Person nicht weniger geben.
- **Die Adresse muss die sein, die nginx sieht.** nginx sieht die Adresse, die sich mit ihm verbindet. Hinter einem Router mit
  Adressübersetzung (NAT) oder hinter einem Proxy ist das die Adresse des Routers oder des Proxys, und die Liste gilt dann für
  jeden PC dahinter. Steht ein Proxy vor nginx, den Listener `behind-proxy` nutzen ([Abschnitt 5](#login-other)). nginx liest die
  Adresse des PCs dann aus dem Header `X-Forwarded-For`, aber nur, wenn der Proxy, der den Header schickt, in `set_real_ip_from`
  steht. Getestet: Mit dem genannten Proxy griffen die Listen auf die Adresse im Header (200 für eine Adresse auf der Liste, 403
  für jede andere). Mit einer anderen genannten Adresse bekam jede Anfrage 403, weil nginx die Adresse des Proxys sah und den
  Header ignorierte.
- **Veröffentlichte Ports und IPv6.** Die Compose-Dateien schreiben die Ports als `0.0.0.0`, das heißt nur IPv4. Über IPv6 würde
  Docker nginx seine eigene Gateway-Adresse zeigen statt der Adresse des PCs (aus den Projektdateien entnommen, hier nicht
  ausgeführt). Darum nie die Gateway-Adresse auf eine Liste eines Servers setzen, den PCs über einen veröffentlichten Port
  erreichen.
- **Eine Änderung braucht ein Neuladen.** nginx liest die Listen beim Start und beim Neuladen, nicht bei jeder Anfrage. Die
  Anmeldung `basic` arbeitet anders.
- **Die 403-Seite nennt die Liste nicht.** Der Benutzer sieht `403 Forbidden`. Den Grund findet man im Log
  ([4.3](#login-none-check)).

> **Warnung**
>
> Ein SSH-Tunnel zu einem Port, den Docker auf 127.0.0.1 veröffentlicht (das Rezept `tryit`), zeigt nginx die Adresse des
> Docker-Gateways und nicht die Adresse des eigenen PCs. Nur diese eine Adresse zulassen. Man erhält sie mit dem Befehl unten, wobei
> `NETWORK` der Name des Docker-Netzes des Containers `ohif` ist (`docker network ls` listet die Namen). Die Antwort sieht wie
> `172.18.0.1` aus, und die Listenzeile lautet `allow 172.18.0.1;`. Nie einen Bereich wie `172.16.0.0/12` zulassen, weil er jedes
> Docker-Netz des Hosts enthält. Das lief hier nicht.
>
> ```bash
> docker network inspect NETWORK -f '{{(index .IPAM.Config 0).Gateway}}'
> ```

<a id="login-other"></a>
## 5. Andere Eingangstüren

Viele Organisationen betreiben einen **Reverse-Proxy** vor allen ihren Webdiensten, zum Beispiel Traefik, Caddy, Apache oder
Cloudflare Tunnel. Ein Reverse-Proxy nimmt die https-Verbindung des Browsers an, beendet die Verschlüsselung (TLS) und gibt die
Anfrage über reines http weiter. Dieser Abschnitt behandelt die Einrichtungen, bei denen ein solcher Proxy vor nginx steht. nginx
bleibt die Eingangstür: Es behält die Anmeldung, die Sperren und das Protokoll, und der Proxy beendet nur TLS. Ein Proxy, der nginx
ersetzt, wird nicht unterstützt ([Abschnitt 6](#login-unsupported)).

| Die Einrichtung | Anmeldung in nginx | Teil |
|---|---|---|
| Der Proxy beendet TLS. nginx prüft Name und Passwort. | basic | [5.1](#login-other-proxied) |
| Der Proxy beendet TLS. nginx prüft die Adresse des PCs. | none | [5.1](#login-other-proxied) |
| Der Proxy beendet TLS. Benutzer melden sich bei einem Identitätsanbieter an. | oauth2-proxy | [5.2](#login-other-oauth2) |
| Der Proxy prüft eine eigene Anmeldung, bevor er die Anfrage weitergibt. | eine der drei oben | [5.3](#login-other-proxy-login) |

**Was getestet wurde.** Der Listener `behind-proxy` lief in Docker mit nginx 1.30.5 (Image `nginx:1.30`) und der Anmeldung `basic`.
Ein Testclient ersetzte den Proxy und schickte den Header `X-Forwarded-For`. Die Listen der Anmeldung `none` liefen ebenso
([4.4](#login-none-limits)). Das Zusammenführen der Compose-Dateien aus [5.2](#login-other-oauth2) wurde mit `docker compose
config` geprüft, die nginx-Dateien von oauth2-proxy mit dem Listener `behind-proxy` mit `nginx -t`. Traefik, Caddy, Apache,
Cloudflare und ein echtes oauth2-proxy liefen nicht.

<a id="login-other-proxied"></a>
### 5.1 Ein Proxy vor nginx, mit der Anmeldung basic oder none

[install.de.md](install.de.md#variant-proxied) nennt dieses Rezept `proxied`: die Compose-Datei
`docker-compose.proxied.example.yml`, die nginx-Dateien mit `LISTENER=behind-proxy` und ein Proxy, der den Host-Namen an
`http://ohif:8080` schickt. Den Schritten dort folgen. Dieser Teil erklärt die zwei Punkte, auf die es für die Anmeldung ankommt,
und zeigt, wie man sie prüft.

```text
 Browser ---- https ---->  Proxy ---- http ---->  nginx (Container ohif, Port 8080)  ---->  arc
                           beendet TLS            Anmeldung, Sperren, Protokoll
                           schreibt die Adresse des PCs in X-Forwarded-For
```

**Punkt 1: nginx muss die Adresse des PCs sehen.** Die Verbindung zu nginx kommt vom Proxy, also sieht nginx die Adresse des
Proxys. Der Proxy schreibt deshalb die Adresse des PCs in den Header `X-Forwarded-For`. Der Listener `behind-proxy` lässt nginx die
Adresse aus diesem Header lesen. nginx glaubt dem Header nur, wenn die Verbindung aus dem Subnetz in der Zeile `set_real_ip_from`
von `pacs/listener/server.conf` kommt. Das ist das Subnetz des Docker-Netzes, das der Proxy und nginx teilen. Die mitgelieferte
Zeile enthält die Adresse `203.0.113.1`, eine Dokumentationsadresse, die kein echter Proxy nutzt. Die Zeile vertraut niemandem: Bis man
sie ersetzt, ignoriert nginx den Header, und das Protokoll nennt bei jeder Anfrage den Proxy (getestet). Das Protokoll, die Listen
der Anmeldung `none` und die Prüfung gegen Selbstaussperrung im Reiter `Firewall` nutzen alle diese Adresse.

**Punkt 2: Nur der Proxy darf nginx erreichen.** Die Compose-Datei veröffentlicht aus diesem Grund keinen Port. Alles, was nginx aus
dem vertrauten Subnetz erreicht, kann jede Adresse in `X-Forwarded-For` schreiben. Bei der Anmeldung `none` entscheidet diese
Adresse über die Stufe. Darum ein Docker-Netz nutzen, das nur der Proxy und nginx teilen.

Die Anmeldung funktioniert wie in den Abschnitten davor. Bei `basic` fragt der Browser nach Name und Passwort, und der Proxy muss
den Header `Authorization` an nginx weitergeben. Die Konten sind die aus [Abschnitt 3](#login-basic). Bei `none` wirken die beiden
Listen aus [4.2](#login-none-lists) auf die Adresse aus dem Header.

> **Warnung**
>
> Ein falsches `set_real_ip_from` scheitert auf zwei Arten. Ein zu weiter Bereich, zum Beispiel ein Netz, das andere Container
> nutzen, lässt jeden von ihnen die eigene Adresse wählen: Bei der Anmeldung `none` kann das die Admin-Stufe öffnen. Ein Bereich,
> der den Proxy nicht enthält, und auch die mitgelieferte Adresse, lässt nginx den Header ignorieren. nginx sieht dann die Adresse
> des Proxys. Das Protokoll nennt bei jeder Anfrage den Proxy, und bei der Anmeldung `none` bekommt jede Anfrage 403 (getestet).
> Ein Client, der nicht der Proxy ist, kann seine Adresse nicht wählen: Sein Header wird ignoriert (getestet). Das Subnetz des
> einen Netzes eintragen, das der Proxy und nginx teilen, keinen größeren Bereich.

> **Prüfen**
>
> `https://pacs.example.org/` auf einem PC öffnen und anmelden. Dann die neuesten Zeilen des Protokolls `zugriffe` auf dem Server
> lesen ([8.3](#login-audit-read) erklärt den Befehl):
>
> ```bash
> python3 /opt/pacs-admin/server/pacsdb.py protokoll zugriffe "$(date +%F)" | tail -n 3
> ```
>
> Erwartet: In jeder Zeile der eigenen Anfrage ist `ip` die Adresse des PCs und nicht die Adresse des Proxys. Diese Zeile stammt
> aus dem Test mit der PC-Adresse 192.0.2.77 (Anmeldung `basic`):
>
> ```text
> {"t":"2026-10-14T09:00:26+00:00","u":"vera","sub":"vera","ip":"192.0.2.77","r":"/","status":200}
> ```
>
> Eine Anfrage ohne den Header zeigt die Adresse des Proxys. Im Test war das `127.0.0.1`, die Adresse des Testclients. Zeigen alle
> Zeilen den Proxy, liest nginx den Header nicht. Zuerst die Zeile mit `grep -n set_real_ip_from
> /opt/ohif/nginx/pacs/listener/server.conf` prüfen: Die Zeile darf nicht die mitgelieferte `203.0.113.1` enthalten. Dann siehe
> [Fehlersuche](troubleshooting.de.md#proxy-wrong-address).

<a id="login-other-oauth2"></a>
### 5.2 oauth2-proxy hinter dem eigenen Proxy

Single Sign-on funktioniert auch hinter einem Proxy. Die Compose-Datei `docker-compose.proxied.example.yml` hat keinen Dienst
`ohif-auth`, also kopiert man diesen Dienst aus der Compose-Datei für oauth2-proxy. Zuerst [Abschnitt 2](#login-oauth2) lesen. Die
Seite des Anbieters (die Schritte 1 bis 6 in [2.3](#login-oauth2-entra) oder [2.6](#login-oauth2-providers)) und die Geheimnisse
(Schritt 7) bleiben, wie geschrieben. Die Liste unten nennt nur, was abweicht. Die Punkte in dieser Reihenfolge ausführen:

1. **Die Redirect-URI registrieren** `https://pacs.example.org/oauth2/callback`, mit dem Host-Namen, den der Browser am Proxy nutzt.
   Der Proxy muss den Header `Host` unverändert weitergeben und jeden Pfad, auch `/oauth2/`, an nginx schicken.
2. **Die nginx-Dateien bauen** mit `LOGIN=oauth2-proxy; VIEWER=ohif; LISTENER=behind-proxy` in
   [Schritt 4.9 der Installationsanleitung](install.de.md#nginx-files). `set_real_ip_from` wie in [5.1](#login-other-proxied) setzen.
3. **Beide Netzwerknamen setzen** in `/opt/ohif/docker-compose.yml`: das Netzwerk von dcm4chee und das Netzwerk des Proxys. Die
   Installationsanleitung tut das in [Schritt 4.10](install.de.md#compose-file) und in dem Teil über die Variante
   [`proxied`](install.de.md#variant-proxied).
4. **`ohif-auth.env` anlegen** mit Schritt 7 aus [2.3](#login-oauth2-env).
5. **Den Dienst `ohif-auth` in die Compose-Datei einfügen** (nächster Block).
6. **Die fünf Werte setzen** mit [Schritt 8](#login-oauth2-edit), dann die Admin-Gruppe mit [Schritt 9](#login-oauth2-site).
7. **Starten und prüfen** mit [Schritt 10](#login-oauth2-start).

Punkt 5 kopiert den Block des Dienstes `ohif-auth` aus der oauth2-Datei (vom Kommentar `# Login: nginx asks this container` bis zum
Kommentar `# The Docker network`) in die eigene Datei, über die Zeile `networks:`. Dann entfernt er das Einhängen des Ordners
`htpasswd`, weil diese Anmeldung keine Passwortdateien hat.

```bash
cd /opt/ohif
awk 'FNR==NR { if (/^  # Login: nginx asks this container/) p=1; if (/^# The Docker network/) p=0; if (p) blk = blk $0 "\n"; next } /^networks:/ { printf "%s", blk } { print }' /opt/pacs-admin/deploy/compose/docker-compose.oauth2.example.yml docker-compose.yml > docker-compose.merged.yml
mv docker-compose.merged.yml docker-compose.yml
sed -i '\|^ *- \./htpasswd:/etc/nginx/htpasswd:ro|d' docker-compose.yml
```

Man kann auch von Hand zusammenführen. Beide Dateien öffnen. In der oauth2-Datei die Zeilen von
`  # Login: nginx asks this container ...` bis zur Zeile vor `# The Docker network of your dcm4chee project` kopieren und über
der Zeile `networks:` der eigenen Datei einfügen. Die Zeile `- ./htpasswd:/etc/nginx/htpasswd:ro` löschen.

> **Prüfen**
>
> ```bash
> grep -n 'CHANGE-M[E]' /opt/ohif/docker-compose.yml
> docker compose -f /opt/ohif/docker-compose.yml config --services
> ```
>
> Erwartet: fünf Markierungszeilen (die Tenant-ID, die beiden Gruppen, die Redirect-URL und das Subnetz) und die beiden Dienste. Die
> Zeilennummern können um einige Zeilen abweichen. Der zweite Befehl braucht die Datei `ohif-auth.env` aus Punkt 4. Diese Zeilen
> stammen aus dem Test:
>
> ```text
> 87:      - --oidc-issuer-url=https://login.microsoftonline.com/TENANT-ID/v2.0   # ENTRA: CHANGE-ME: Directory (tenant) ID
> 90:      - --allowed-group=VIEWER-GROUP-ID         # ENTRA: CHANGE-ME: Object ID of the group that may open the viewer
> 91:      - --allowed-group=ADMIN-GROUP-ID          # ENTRA: CHANGE-ME: Object ID of the admin group (also in site.conf)
> 107:      - --redirect-url=https://pacs.example.org/oauth2/callback   # CHANGE-ME: https://HOST/oauth2/callback
> 116:      - --trusted-proxy-ip=172.16.0.0/12        # CHANGE-ME: subnet of the Docker network
> ohif
> ohif-auth
> ```
>
> Eine sechste Markierungszeile am Ende der Datei (`name of the network of your proxy`) heißt, dass der Name des Proxy-Netzwerks
> noch nicht gesetzt ist. Ihn vor [Schritt 8](#login-oauth2-edit) setzen: Der letzte `sed`-Ausdruck von Schritt 8 würde die
> Markierung löschen und den mitgelieferten Namen `proxy_default` stehen lassen. Hat das Zusammenführen nichts kopiert, fehlt der
> Dienst `ohif-auth` in der Ausgabe des zweiten Befehls: von Hand zusammenführen.

> **Warnung**
>
> In [Schritt 8](#login-oauth2-edit) das Subnetz des **Netzwerks von dcm4chee** in `--trusted-proxy-ip` schreiben, nicht das Subnetz
> des Proxy-Netzwerks. nginx und oauth2-proxy sprechen im Netzwerk von dcm4chee miteinander, und oauth2-proxy glaubt den
> `X-Forwarded-*`-Headern nur von dort. Die zusammengeführte Datei setzt `ohif-auth` nur in dieses Netzwerk, also kann der Proxy es
> nicht erreichen. Der Befehl `docker network inspect NAME -f '{{(index .IPAM.Config 0).Subnet}}'` mit dem Namen dieses Netzwerks
> zeigt das Subnetz.

Nach dem Start einmal von einem PC aus anmelden und das Protokoll wie in [5.1](#login-other-proxied) lesen: `ip` muss die Adresse
des PCs sein. Ob die Anmeldung durch einen Proxy von Anfang bis Ende funktioniert, lief nicht, weil hier weder ein echtes
oauth2-proxy noch ein echter Anbieter lief.

<a id="login-other-proxy-login"></a>
### 5.3 Eine Anmeldung am Proxy

Manche Proxys prüfen eine Anmeldung, bevor sie eine Anfrage weitergeben, zum Beispiel Cloudflare Access oder ein Forward-Auth-Dienst
neben Traefik oder Caddy. Eine solche Prüfung kann als zusätzliche Schicht vor nginx stehen, ersetzt aber die Anmeldung in nginx
nicht. nginx legt die Stufe (Viewer oder Admin) fest und nennt das Konto im Protokoll. Es nimmt den Namen nur aus der eigenen
Anmeldung: den Namen im Header `Authorization` bei `basic`, die Antwort von oauth2-proxy bei `oauth2-proxy` und die Adresse des
PCs bei `none`. Es liest keinen Namen aus einem Header, den der Proxy setzt.

Darum eine Anmeldung aus den Abschnitten 2 bis 4 wählen und beibehalten. Die Prüfung am Proxy und die Anmeldung in nginx arbeiten
dann nacheinander. Nutzt die Prüfung am Proxy ebenfalls HTTP-Basic-Authentifizierung, sie nicht mit der Anmeldung `basic`
kombinieren: Eine Anfrage trägt einen Header `Authorization`, und beide Anmeldungen lesen ihn. Diese Einrichtung wurde nicht
getestet.

<a id="login-unsupported"></a>
## 6. Nicht unterstützt

Diese Einrichtungen funktionieren nicht, oder niemand hat sie getestet. [reference.de.md](reference.de.md#front-door-contract) legt
fest, was eine Eingangstür leisten muss.

<a id="login-unsupported-keycloak"></a>
### 6.1 dcm4chee mit der eigenen Keycloak-Anmeldung

dcm4chee liefert Images mit einer Keycloak-Anmeldung (ihre Namen enden auf `-secure` oder `-secure-ui`) und Images ohne eine. Die
Admin-Seite und nginx schicken kein Anmelde-Token an das Archiv, also muss das Archiv ohne Keycloak laufen: das Image
`dcm4chee-arc-psql`. Das Archiv hat dann keine eigene Anmeldung. Die Anmeldung dieser Seite ist die einzige, und nginx ist die
einzige Tür.

> **Warnung**
>
> Wer Port 8080 oder 8443 des Containers `arc` erreicht, kann das Archiv ohne Anmeldung nutzen. Beide Ports von außen schließen: in
> der Firewall sperren ([modules.de.md](modules.de.md#firewall-block)) oder nur auf `127.0.0.1` veröffentlichen. Die
> Voraussetzungen der optionalen dcm4chee-Benutzeroberfläche wiederholen das ([modules.de.md](modules.de.md#dcm4chee-ui)).

<a id="login-unsupported-front"></a>
### 6.2 Ein anderes Programm statt nginx

Traefik, Caddy und Cloudflare Access können nginx nicht ersetzen. Niemand hat es getestet. Die Sperren auf den Pfaden, der Header
`X-PACS-Admin`, das Protokoll und die Verbindung zum Hilfsdienst sind Eigenschaften der nginx-Dateien, und die Protokollzeilen
brauchen einen Sender, der sie an den Hilfsdienst schickt ([reference.de.md](reference.de.md#audit-feed)). Stattdessen diese
Produkte vor nginx stellen ([Abschnitt 5](#login-other)). Ein Programm, das den ganzen Vertrag aus
[reference.de.md](reference.de.md#front-door-contract) erfüllt, kann funktionieren, aber dieses Repository liefert und testet keines.

<a id="login-unsupported-more"></a>
### 6.3 Anmeldungen, die die nginx-Dateien nicht enthalten

- **Zwei Anmeldungen gleichzeitig**, zum Beispiel oauth2-proxy für Viewer und basic für Admins. Man kopiert die Dateien eines
  Verfahrens nach `pacs/login/`. Eine Mischung braucht eigene nginx-Dateien.
- **Active Directory ohne Entra ID.** Eine Windows-Domäne allein spricht kein OIDC. Siehe [2.6](#login-oauth2-providers).
- **Ein Anbieter, der nur SAML spricht.** oauth2-proxy spricht OpenID Connect und OAuth 2.0, nicht SAML.
- **Integrierte Windows-Anmeldung (Kerberos oder NTLM).** nginx bietet sie nicht an.

<a id="login-access"></a>
## 7. Wer was öffnen darf

Die Anmeldung sagt nginx, wer fragt. nginx entscheidet dann, was dieses Konto öffnen darf. Es gibt zwei Stufen: [jedes
Konto](glossary.de.md#any-account) (die Viewer-Stufe aus [Abschnitt 1](#login-choose)) und [Admin](glossary.de.md#admin-account).
Die Sperren auf den Pfaden sind bei jeder Anmeldung dieselben. Nur der Weg zur Stufe ist verschieden.

<a id="login-access-levels"></a>
### 7.1 Wie jede Anmeldung die Stufe festlegt

| Anmeldung | Jedes Konto | Admin |
|---|---|---|
| oauth2-proxy | Der Benutzer steht in einer der Gruppen aus den Zeilen `--allowed-group` der Compose-Datei. | Der Benutzer steht in der Gruppe `$pacs_admin_group` aus `pacs/site.conf`. |
| basic | Das Konto steht in der Datei `users`. | Das Konto steht in der Datei `admins`. |
| none | Die Adresse des PCs steht in der Liste aus `pacs/login/server.conf`. | Die Adresse des PCs steht in der Liste aus `pacs/login/admin.conf`. |

Ein Admin ist auch ein Viewer. Die drei Anmeldungen stellen das auf verschiedene Weise sicher:

- **oauth2-proxy:** Die Admin-Gruppe ist eine der Zeilen `--allowed-group`. Mehr ist nicht nötig. Bei Google ist die Admin-Stufe
  statt einer Gruppe eine Liste von E-Mail-Adressen ([2.6](#login-oauth2-google)).
- **basic:** Das Skript `pacs-adduser.sh` schreibt einen Admin in beide Dateien ([3.5](#login-basic-accounts)). Die Viewer-Seiten
  lesen `users`, und `/admin/` liest `admins`.
- **none:** Ein Admin-PC muss auf beiden Listen stehen. Die Admin-Liste ersetzt die Viewer-Liste für `/admin/` und für die
  Änderungen ([4.2](#login-none-lists)).

Eine Admin-Gruppe, die leer oder noch ein Platzhalter ist, sperrt die Admin-Stufe. Ein leeres `$pacs_admin_group` ergibt 500 auf
`/admin/`. Der mitgelieferte Platzhalter `00000000-0000-0000-0000-000000000000` ergibt 403 für alle, also ist niemand Admin
([Schritt 9](#login-oauth2-site) für Entra ID, [Schritt D](#login-oauth2-group-names) für andere Anbieter).

<a id="login-access-paths"></a>
### 7.2 Was jede Stufe öffnet

| Was | Pfad | Stufe | Header `X-PACS-Admin` |
|---|---|---|---|
| Startseite des Viewers und ihre Dateien (Viewer-Modus `ohif`) | `/`, `/index.html`, `/app-config.js` | jedes Konto | nein |
| Studiensuche des Viewers und der Admin-Seite | `GET /dcm4chee-arc/aets/DCM4CHEE/rs/studies` | jedes Konto | nein |
| Lesezugriffe des Viewers: Studien, Serien, Instanzen, WADO | `GET` unterhalb von `/dcm4chee-arc/aets/DCM4CHEE/` | jedes Konto | nein |
| Kontoname oben auf der Admin-Seite | `/oauth2/userinfo` | jedes Konto | nein |
| Admin-Seite und ihre Zahlen | `/admin/`, `/admin/daten/` | Admin | nein |
| Hilfsdienst der Admin-Seite: Platten, Firewall, Protokoll | `/admin/dienst/` | Admin | jedes `POST` und die `GET`-Aufrufe `platten` und `firewall?neu=1` |
| Patientenliste und Ansicht der abgelehnten Studien | `GET .../rs/patients`, `GET .../IOCM_QUALITY/rs/studies` | Admin | nein |
| Jede Änderung an Studien und Patienten: bearbeiten, verschieben, ablehnen, zurückholen, zusammenführen, löschen | `POST`, `PUT` oder `DELETE` auf genau die Pfade aus `pacs.conf` | Admin | ja |
| Die optionale dcm4chee-Benutzeroberfläche | `/dcm4chee-arc/ui2/` | Admin | nein |

Der Header `X-PACS-Admin` trägt einen kurzen Text zur Aktion. Nur die Admin-Seite setzt ihn. Eine Änderung ohne ihn bekommt 403,
auch von einem Admin. Eine fremde Webseite kann den Browser eines Admins nicht dazu bringen, den Header zu senden. Der Header ist
keine Anmeldung. Das Protokoll bewahrt seinen Text auf ([Abschnitt 8](#login-audit)).

Weitere Sperren bewahren einen Admin vor einem falschen Klick: Eine Studienänderung nennt genau eine Studie, eine
Patientenbearbeitung führt nie zusammen, und Löschen geht nur bei abgelehnten Studien.
[reference.de.md](reference.de.md#contract-paths) listet sie auf. Beim Viewer-Modus `none` gibt es keinen Viewer: `/` leitet auf
`/admin/` um, und die Lesezugriffe des Viewers antworten 404.

> **Warnung**
>
> Die optionale dcm4chee-Benutzeroberfläche hat keine dieser Sperren. Wer sie öffnen darf, kann Studien löschen und die
> Konfiguration des Archivs ändern. Die Admin-Stufe nur Personen geben, denen man auch diese Oberfläche anvertrauen würde, oder
> die Oberfläche abschalten ([modules.de.md](modules.de.md#dcm4chee-ui-off)). [modules.de.md](modules.de.md#dcm4chee-ui)
> beschreibt sie.

<a id="login-access-public"></a>
### 7.3 Antworten, die keine Anmeldung brauchen

Einige Antworten enthalten keine Daten. nginx gibt sie, bevor es die Anmeldung prüft, also funktionieren sie für alle:

- `/admin` antwortet 301 und verweist auf `/admin/`.
- Ein Pfad, der vor einem `?` ein Semikolon, einen Backslash oder `%5c` enthält, antwortet 400. Das Archiv könnte diese
  Schreibweisen als Weg aus einem erlaubten Pfad heraus lesen, darum weist nginx sie ab.
- Eine Änderung, die eine der Sperren abweist, antwortet 403, auch ohne Anmeldung: eine Änderung ohne den Header `X-PACS-Admin`,
  eine Änderung oder Verschiebung einer Studie mit einer anderen Query, als die Admin-Seite sendet, und eine Patientenbearbeitung
  mit `merge`. Eine Änderung, die die Sperren besteht, antwortet ohne Anmeldung 401 (getestet mit der Anmeldung `basic`).
- Jeder andere Pfad unterhalb von `/dcm4chee-arc/`, den die Tabelle in 7.2 nicht nennt, antwortet 404.
- Mit der optionalen dcm4chee-Benutzeroberfläche: `/dcm4chee` antwortet 301, `/dcm4chee-arc/ui2/` antwortet ein Skript mit drei
  Zeilen, und zwei Dateien namens `keycloak.json` antworten `{}`.
- Beim Viewer-Modus `none`: `/` antwortet 302 und verweist auf `/admin/`, und jeder unbekannte Pfad antwortet 404.
- Bei der Anmeldung oauth2-proxy: Die Pfade unterhalb von `/oauth2/` gehören zur Anmeldung. Als Weg hinein
  brauchen diese Pfade keine Sitzung.

<a id="login-access-refused"></a>
### 7.4 Was ein abgewiesener Benutzer sieht

| Die Anfrage | oauth2-proxy | basic | none |
|---|---|---|---|
| Keine Sitzung, kein Name oder ein PC auf keiner Liste | 302 zur Anmeldeseite des Anbieters | 401, der Browser fragt nach Name und Passwort | 403 |
| Ein bekanntes Konto auf einer Stufe, die es nicht hat, zum Beispiel ein Viewer auf `/admin/` | 403 | 401, der Browser fragt erneut | 403 |
| Eine Änderung ohne den Header `X-PACS-Admin` | 403 | 403 | 403 |

Bei `basic` ist die Antwort immer 401, weil die Basic-Authentifizierung nicht sagen kann „bekannt, aber nicht erlaubt“. Der
Browser fragt dann erneut, und ein Viewer, der das Passwort noch einmal eingibt, trifft wieder auf 401. Bei `none` sieht der
Benutzer die Seite `403 Forbidden`, und der Grund steht im Log von nginx ([4.3](#login-none-check)). Eine Änderung ohne den Header
wird zuerst abgewiesen, noch bevor die Anmeldung läuft, also bekommt auch eine Person ohne Anmeldung 403.

> **Prüfen**
>
> Vier Pfade von einem PC ohne Anmeldung abfragen. `-k` nur bei einem selbstsignierten Zertifikat benutzen.
>
> ```bash
> for p in / /admin/ /dcm4chee-arc/aets/DCM4CHEE/rs/studies /dcm4chee-arc/aets/DCM4CHEE/rs/patients; do
>   printf '%s  ' "$p"; curl -sk -o /dev/null -w '%{http_code}\n' "https://pacs.example.org$p"
> done
> ```
>
> Erwartet: viermal dieselbe Zahl. Bei `basic` ist es `401`, bei `none` (der PC steht auf keiner Liste) `403`, und bei
> oauth2-proxy `302`. Ausgabe des Tests mit `basic`:
>
> ```text
> /  401
> /admin/  401
> /dcm4chee-arc/aets/DCM4CHEE/rs/studies  401
> /dcm4chee-arc/aets/DCM4CHEE/rs/patients  401
> ```
>
> Eine `200` heißt, dass ein Pfad ohne Anmeldung aufgeht. Anhalten und die nginx-Dateien aus
> [install.de.md](install.de.md#nginx-files) prüfen. Eine `404` oder `502` heißt, dass der Container nicht das ist, was man
> denkt: siehe [Fehlersuche](troubleshooting.de.md#every-page-500).

**Was getestet wurde.** In den Läufen der Anmeldungen `basic` und `none` ist ein Skript durch alle 26 Locations der nginx-Dateien
gegangen. Jede Location verlangt entweder die Anmeldung oder gehört zu den Antworten aus 7.3 (26 von 26). Das Skript gehört nicht
zu diesem Repository. Die Prüfung oben lief mit `basic` und `none` in Docker. Die `302` für oauth2-proxy stammt aus einem Lauf mit
einem Ersatz, der wie oauth2-proxy antwortet, nicht aus einem echten oauth2-proxy.

<a id="login-audit"></a>
## 8. Was das Protokoll aufzeichnet

Das Protokoll hält fest, wer gesucht hat, wer was geöffnet hat und wer was geändert hat. nginx schreibt für jede Anfrage eine
Zeile. Der [Hilfsdienst](glossary.de.md#helper-service) speichert die Zeilen in einer verschlüsselten Datenbank, und der Reiter
`Protokoll` der Admin-Seite zeigt sie. Was eine Zeile über die Person sagt, hängt von der Anmeldung ab. Dieser Abschnitt zeigt die
Zeilen jeder Anmeldung und wie man sie liest. [reference.de.md](reference.de.md#audit-log) enthält die vollständigen Regeln.

<a id="login-audit-fields"></a>
### 8.1 Was jede Anmeldung in eine Zeile schreibt

Eine Zeile ist ein JSON-Objekt mit den Feldern `t`, `u`, `sub`, `ip`, `r` und `status`. Die Anmeldung bestimmt die Felder `u` und
`sub`:

| Feld | Bedeutung | oauth2-proxy | basic | none |
|---|---|---|---|---|
| `u` | Der Kontoname. Der Reiter zeigt ihn. | Der Claim `preferred_username`. Ist er leer: die E-Mail-Adresse, dann die ID des Kontos, dann `anon-` und die Adresse des PCs. | Der Name, den der Client gesendet hat, auch bei falschem Passwort. `anon-` und die Adresse, wenn der Client keinen Namen gesendet hat. | Immer `anon-` und die Adresse des PCs. |
| `sub` | Die ID, die die Anmeldung meldet. | Der Header `X-Auth-Request-User` von oauth2-proxy. Er ist leer, wenn die Prüfung die Anfrage abgewiesen hat: keine Sitzung, oder ein Konto ohne Berechtigung. | Dasselbe wie `u`. | Dasselbe wie `u`. |

`sub` ist nur der Name des Feldes. Was oauth2-proxy in `X-Auth-Request-User` schreibt, hängt von dessen Einstellungen und vom Anbieter ab; es ist nicht zwingend der Claim `sub` des ID-Tokens.

Die übrigen Felder hängen nicht von der Anmeldung ab. `t` ist die Zeit mit dem Offset des Servers. `ip` ist die Adresse des PCs.
nginx nimmt sie aus der Verbindung, und der Listener `behind-proxy` nimmt sie aus dem Header des eigenen Proxys
([5.1](#login-other-proxied)). `r` ist der Pfad der Anfrage samt Query, und `status` ist die Antwort von nginx.

Jede Zeile trägt einen Syslog-Tag. Der Syslog-Tag bestimmt, wo die Zeile gespeichert wird:

| Syslog-Tag | Was er enthält |
|---|---|
| `zugriffe` | Jede Anfrage, auch die abgewiesenen und die statischen Dateien des Viewers. |
| `ereignisse` | Die `GET`-Anfragen, die Menschen interessieren: Suchen, geöffnete Studien und geöffnete Befunde. |
| `admin` | Jede Anfrage auf einen Pfad, der Daten ändert, und jedes `POST` auf `/admin/dienst/`. |

Eine Änderung über die Admin-Seite schreibt zwei Zeilen, eine unter `zugriffe` und eine unter `admin`. Die Zeile unter `admin`
hat vier weitere Felder: `m` (die Methode), `uri` (die vollständige Adresse), `k` (die Beschreibung, die die Seite im Header
`X-PACS-Admin` sendet, URL-kodiert) und `body` (was die Änderung gesendet hat). Das Feld `r` enthält dort immer das Wort `admin`.

<a id="login-audit-rows"></a>
### 8.2 Beispielzeilen je Anmeldung

Die Zeilen unten stammen aus Tests in Docker mit nginx 1.30.5 und den aktuellen nginx-Dateien. Die Zeit endet auf `+00:00` (UTC),
weil der Test-Container keine Zeitzone hatte. Auf einem Server zeigt `t` den Offset des Servers, weil die mitgelieferten
Compose-Dateien `/etc/localtime` einbinden. Die Studiennummer und die übrigen Werte sind Testdaten.

**Anmeldung basic.** Der Test-PC hat die Adresse 192.0.2.77. Ein Viewer sucht Studien. Der Syslog-Tag ist `ereignisse`, und
dieselbe Zeile steht auch unter `zugriffe`:

```text
{"t":"2026-10-14T09:29:27+00:00","u":"viewer.user","sub":"viewer.user","ip":"192.0.2.77","r":"/dcm4chee-arc/aets/DCM4CHEE/rs/studies?limit=1","status":200}
```

Derselbe Viewer fragt `/admin/` ab und trifft auf 401. Die Zeile nennt das Konto, weil der Browser den Namen gesendet hat:

```text
{"t":"2026-10-14T09:29:29+00:00","u":"viewer.user","sub":"viewer.user","ip":"192.0.2.77","r":"/admin/","status":401}
```

Eine Anfrage ohne Namen bekommt 401, und der Name ist `anon-` mit der Adresse:

```text
{"t":"2026-10-14T09:29:30+00:00","u":"anon-192.0.2.77","sub":"anon-192.0.2.77","ip":"192.0.2.77","r":"/dcm4chee-arc/aets/DCM4CHEE/rs/studies","status":401}
```

Ein falsches Passwort bekommt ebenfalls 401. Die Zeile trägt den Namen, der eingegeben wurde. Eine 401-Zeile zu einem Namen heißt
also nicht, dass diese Person etwas getan hat:

```text
{"t":"2026-10-14T09:29:32+00:00","u":"viewer.user","sub":"viewer.user","ip":"192.0.2.77","r":"/dcm4chee-arc/aets/DCM4CHEE/rs/studies?limit=1","status":401}
```

Ein Admin ändert eine Studie. Diese Zeile steht unter dem Syslog-Tag `admin`. `k` ist die Beschreibung, die die Seite gesendet hat
(hier `Testaktion · Studie`), und `body` sind die Daten der Änderung:

```text
{"t":"2026-10-14T09:29:33+00:00","u":"admin.user","sub":"admin.user","ip":"192.0.2.77","r":"admin","m":"POST","uri":"/dcm4chee-arc/aets/DCM4CHEE/rs/studies/update?reasonForModification=CORRECT&StudyInstanceUID=1.2.840.1.2","status":200,"k":"Testaktion%20%C2%B7%20Studie","body":"{\"00100010\":{\"vr\":\"PN\"}}"}
```

Eine Änderung ohne den Header `X-PACS-Admin` bekommt 403, auch bei einem Admin. Hier hat ein Admin ein `POST` an den Hilfsdienst
ohne den Header gesendet. Die Zeile zeigt das Konto, und `k` ist leer:

```text
{"t":"2026-10-14T09:29:43+00:00","u":"admin.user","sub":"admin.user","ip":"192.0.2.77","r":"admin","m":"POST","uri":"/admin/dienst/freigeben","status":403,"k":"","body":""}
```

**Anmeldung none.** Jede Zeile nennt eine Adresse. Im Test hat der Viewer-PC die Adresse 192.0.2.202, der Admin-PC hat 192.0.2.201,
und ein dritter PC, 192.0.2.203, steht auf keiner Liste. Der Viewer-PC sucht Studien:

```text
{"t":"2026-10-14T09:30:10+00:00","u":"anon-192.0.2.202","sub":"anon-192.0.2.202","ip":"192.0.2.202","r":"/dcm4chee-arc/aets/DCM4CHEE/rs/studies?limit=1","status":200}
```

Der PC auf keiner Liste fragt `/admin/` ab und bekommt 403. Das Log von nginx nennt die Regel, die ihn abgewiesen hat
([4.3](#login-none-check)):

```text
{"t":"2026-10-14T09:30:15+00:00","u":"anon-192.0.2.203","sub":"anon-192.0.2.203","ip":"192.0.2.203","r":"/admin/","status":403}
```

Der Admin-PC ändert eine Studie:

```text
{"t":"2026-10-14T09:30:19+00:00","u":"anon-192.0.2.201","sub":"anon-192.0.2.201","ip":"192.0.2.201","r":"admin","m":"POST","uri":"/dcm4chee-arc/aets/DCM4CHEE/rs/studies/update?reasonForModification=CORRECT&StudyInstanceUID=1.2.840.1.2","status":200,"k":"Testaktion%20%C2%B7%20Studie","body":"{\"00100010\":{\"vr\":\"PN\"}}"}
```

**Anmeldung oauth2-proxy.** Es gibt keine aufgezeichnete Zeile, weil kein echter Identitätsanbieter an den Tests beteiligt war.
Eine Zeile hat diese Form. Die Wörter in Großbuchstaben stehen für die Werte der Anmeldung (`TIME` ist die Zeit, `USER NAME` der
Anmeldename, `USER ID` die ID des Benutzers, `ADDRESS OF THE PC` die Adresse des PCs):

```text
{"t":"TIME","u":"USER NAME","sub":"USER ID","ip":"ADDRESS OF THE PC","r":"/","status":200}
```

`u` ist meist der Anmeldename des Benutzers. Bei Entra ID ist das ein Name der Form `name@domain`. Zwei Arten von Anfragen
tragen kein Konto. In beiden Zeilen zeigt `u` die Zeichen `anon-` und die Adresse, und `sub` ist leer:

- Eine Anfrage ohne Sitzung bekommt Status 302. nginx schickt den Browser zur Anmeldeseite des Anbieters.
- Ein Benutzer, der angemeldet, aber nicht berechtigt ist, zum Beispiel ein Viewer auf `/admin/`, bekommt Status 403. Die
  fehlgeschlagene Prüfung sendet kein Konto, also nennt die Zeile den Benutzer nicht.

Ein Test mit einem Ersatz für oauth2-proxy hat diese beiden Zeilen erzeugt. Der Ersatz sendet die Header des Kontos nur bei einer
angenommenen Prüfung, und der Quelltext von oauth2-proxy macht es genauso. Der PC war der Test-Container mit der Adresse 127.0.0.1:

```text
{"t":"2026-10-14T11:33:43+00:00","u":"anon-127.0.0.1","sub":"","ip":"127.0.0.1","r":"/","status":302}
{"t":"2026-10-14T11:33:43+00:00","u":"anon-127.0.0.1","sub":"","ip":"127.0.0.1","r":"/admin/","status":403}
```

**Was eine Zeile beweist.** Die Zeile nennt das Konto, und die Anmeldung bestimmt, wie viel das bedeutet:

- **oauth2-proxy:** Eine Person hat sich beim Identitätsanbieter angemeldet. Es gelten die Regeln des Anbieters, zum Beispiel ein
  zweiter Faktor.
- **basic:** Jemand, der das Passwort des Kontos kannte. Ein gemeinsames Konto verbirgt, wer was getan hat.
- **none:** Ein PC, keine Person. An einem PC können mehrere Menschen arbeiten.
- **Eine abgewiesene Anfrage:** Kein geprüftes Konto. `ip` und die Zeit mit den anderen Zeilen desselben PCs vergleichen.

<a id="login-audit-read"></a>
### 8.3 Das Protokoll lesen

**In der Admin-Seite.** Der Reiter `Protokoll` listet die Zeilen der Syslog-Tags `ereignisse` und `admin` für die gewählten Tage,
die neueste zuerst. Die Spalten heißen `Zeit`, `Wer`, `Was`, `Patient` und `Studie`. `Wer` zeigt das Konto ohne den Teil nach dem
`@` und darunter den PC. Der Filter `Konto` (das Feld sagt `Teil der Anmeldung`) sucht im vollen Namen und ignoriert Groß- und
Kleinschreibung. Der Filter `Art` hat den Eintrag `nur Abgelehntes und Fehler`, der die abgewiesenen und fehlgeschlagenen
Anfragen listet. Die Schaltfläche `Als CSV speichern` speichert die Liste mit den vollen Kontonamen. Der Reiter zeigt den
Syslog-Tag `zugriffe` nicht.

**Auf dem Server.** Als root gibt das Programm `pacsdb.py` des Hilfsdienstes die gespeicherten Zeilen eines Syslog-Tags aus. Es
liest alle drei Syslog-Tags, zeigt also auch `zugriffe`. Die Argumente sind der Syslog-Tag und optional der erste und der letzte
Tag als `YYYY-MM-DD`. Der letzte Tag ist eingeschlossen. Die Zeilen kommen so heraus, wie sie gespeichert sind, die neueste zuletzt:

```bash
python3 /opt/pacs-admin/server/pacsdb.py protokoll zugriffe "$(date +%F)" | tail -n 5
```

Um einen PC zu verfolgen, die Zeilen mit `grep` filtern. Für einen Kontonamen geht dasselbe:

```bash
python3 /opt/pacs-admin/server/pacsdb.py protokoll zugriffe "$(date +%F)" | grep -F '"ip":"192.0.2.77"'
```

Wurde `PROTOKOLL_DB` oder `PROTOKOLL_KEY` in `/etc/default/pacs-admin` geändert, zuerst die Datei laden mit
`set -a; . /etc/default/pacs-admin; set +a`. Ein falscher Pfad zur Datenbank legt eine leere Datenbank an, eine leere Ausgabe kann
also einen falschen Pfad bedeuten. [reference.de.md](reference.de.md#audit-read) listet alle Optionen und zeigt, wie man dieselben
Zeilen über den Socket des Hilfsdienstes liest.

> **Prüfen**
>
> Sich an einem PC anmelden, den Viewer öffnen und die neuesten Zeilen lesen:
>
> ```bash
> python3 /opt/pacs-admin/server/pacsdb.py protokoll zugriffe "$(date +%F)" | tail -n 3
> ```
>
> Erwartet: Die eigenen Anfragen sind die letzten Zeilen. `u` nennt das eigene Konto (Anmeldung basic und oauth2-proxy) oder den
> eigenen PC (`anon-` und seine Adresse, Anmeldung none), und `ip` ist die Adresse des eigenen PCs. Die Zeilen aus
> [8.2](#login-audit-rows) sind das Muster. Ist die Ausgabe leer oder fehlen die eigenen Anfragen, nach verlorenen Zeilen suchen:
>
> ```bash
> docker logs ohif 2>&1 | grep 'to syslog'
> ```
>
> Keine Ausgabe heißt, dass nginx keine Zeile verloren hat. Zeilen mit `to syslog` heißen, dass nginx den Hilfsdienst nicht
> erreicht hat. [reference.de.md](reference.de.md#audit-lost) nennt die Meldungen und die Ursache. Hat nginx keine Zeile verloren
> und fehlen die eigenen Anfragen trotzdem, siehe [Fehlersuche](troubleshooting.de.md#audit-lines-missing).

> **Warnung**
>
> Das Protokoll enthält Patienten-IDs und Namen, entnommen aus Suchadressen und aus den Daten der Änderungen. Nichts löscht alte
> Zeilen, und das Protokoll wächst mit jeder Anfrage. Es wie Patientendaten behandeln: den Zugriff auf den Server und auf den
> Ordner `/var/lib/pacs-protokoll/` beschränken, eine Kopie des Schlüssels aufbewahren ([install.de.md](install.de.md#backup-audit-key))
> und festlegen, wie lange die Zeilen bleiben ([reference.de.md](reference.de.md#audit-retention)).
