# Admin-Panel installieren

[English](install.md) | Deutsch

Diese Anleitung installiert das Admin-Panel Schritt für Schritt neben einem laufenden dcm4chee-Archiv. Geschrieben ist sie für
Systemadministratoren, die Windows und die Grundlagen von Linux kennen und Docker Compose schon benutzt haben. Neue Wörter
werden dort erklärt, wo sie zum ersten Mal vorkommen. Das [Glossar](glossary.de.md) listet sie alle.

- [1. Einstieg](#start-here)
- [2. Weg A: die Demo ausprobieren](#demo)
- [3. Vor dem Start](#prerequisites)
- [4. Die echte Installation](#real-install): [4.1 Dateien](#get-files), [4.2 Preflight](#preflight), [4.3 Pakete](#packages),
  [4.4 Einstellungen](#settings-file), [4.5 Protokollschlüssel](#audit-key), [4.6 Hilfsdienst](#helper-service),
  [4.7 Übersichts-Job](#overview-cron), [4.8 Zertifikat](#tls-certificate), [4.9 nginx-Dateien](#nginx-files),
  [4.10 Compose-Datei](#compose-file), [4.11 Viewer und Seiteneinstellungen](#viewer-config), [4.12 Anmeldung](#login-setup),
  [4.13 Start](#start-and-check), [4.14 erster Test](#first-test), [4.15 optionale Module](#optional-modules)
- [5. Varianten im Detail](#variants-detail)
- [6. Betrieb im Alltag](#operate)

<a id="start-here"></a>
## 1. Einstieg

<a id="what-changes"></a>
### 1.1 Was die Installation ändert

Das Admin-Panel ist eine Webseite unter `/admin/`. Es zeigt Dienste und Platten, sucht Studien und Patienten, steuert eine
Firewall und zeigt ein Protokoll. Es hat drei Teile:

- Die **Eingangstür** ist nginx im Container `ohif`. nginx prüft die Anmeldung, wendet Sperren an und schreibt das Protokoll. Mit
  Single Sign-on hilft ihr ein zweiter Container, `ohif-auth` ([Glossar](glossary.de.md#front-door)).
- Der **Hilfsdienst** `pacs-verwaltung` läuft auf dem Host unter systemd. Er erledigt die Arbeit, die ein Container nicht tun
  darf, zum Beispiel schreibt er die verschlüsselte Protokoll-Datenbank ([Glossar](glossary.de.md#helper-service)).
- Ein **Cron-Job** schreibt alle 5 Minuten die Datei `status.json`. Der Reiter `Übersicht` zeigt sie.

Die Basisinstallation fügt die Dinge unten hinzu. Dabei bleibt das dcm4chee-Projekt unverändert, und `arc`, `ldap` und `db` werden
nicht neu gestartet.

| Was | Wo |
|---|---|
| Programmdateien | `/opt/pacs-admin` |
| Compose-Datei, nginx-Dateien, Zertifikat, Konten | `/opt/ohif` |
| Einstellungen und Protokollschlüssel | `/etc/default/pacs-admin`, `/etc/pacs-protokoll.key` |
| Dienst und Cron-Job | `/etc/systemd/system/pacs-verwaltung.service`, `/etc/cron.d/pacs-dashboard` |
| Daten und Sockets | `/var/lib/pacs-protokoll`, `/var/lib/pacs-admin`, `/run/pacs-admin` |
| Container und Ports | `ohif` (und `ohif-auth`), Host-Ports 80 und 443 |

Von den optionalen Modulen starten nur der Platten-Assistent und die Firewall `arc` neu ([4.15](#optional-modules)).

<a id="pick-path"></a>
### 1.2 Den Weg wählen

| Weg | Wofür | Was man braucht | Ergebnis |
|---|---|---|---|
| **A. Demo** | Ein erster Blick | Python 3 auf einem beliebigen PC | Die Bildschirme mit erfundenen Daten. Kein dcm4chee, keine Anmeldung |
| **B. Echte Installation mit Single Sign-on** | Alltag mit Microsoft Entra ID oder einem anderen OpenID-Connect-Anbieter | Server, DNS-Name, TLS-Zertifikat, das Recht, beim Anbieter eine App zu registrieren | Viewer und Admin-Panel über https. Die Benutzer melden sich beim Anbieter an |
| **C. Echte Installation ohne OAuth-Proxy** | Alltag mit Konten, die nginx führt, ein geschlossenes Netz oder ein erster Test | Server, DNS-Name, TLS-Zertifikat (nicht für `tryit`) | Viewer und Admin-Panel mit Benutzername und Passwort oder mit Netzlisten |

Ein **Rezept** ist eine Compose-Datei plus ein Satz nginx-Dateien. Die nginx-Dateien haben drei Teile, die man austauscht: das
[Anmeldeverfahren](glossary.de.md#login-method), den Viewer und den [Listener](glossary.de.md#listener). Jeder Weg nutzt diese
Rezepte:

| Rezept | Weg | Compose-Datei in `deploy/compose/` | Anmeldung | Viewer | Listener |
|---|---|---|---|---|---|
| `oauth2` | B | `docker-compose.oauth2.example.yml` | oauth2-proxy | OHIF | tls |
| `basic` | C | `docker-compose.basic.example.yml` | basic | OHIF | tls |
| `adminonly` | C | `docker-compose.adminonly.example.yml` | basic | keiner | tls |
| `proxied` | C | `docker-compose.proxied.example.yml` | basic | OHIF | behind-proxy |
| `tryit` | C | `docker-compose.tryit.example.yml` | basic | keiner | plain |

Unklar, welche Anmeldung passt? [login.de.md](login.de.md#login-choose) lesen. Eine dritte Anmeldung, `none` (Netzlisten statt
Konten), nutzt die Compose-Datei von `basic` ([login.de.md](login.de.md#login-none)). Die Anmeldung lässt sich später wechseln.

<a id="variants"></a>
### 1.3 Varianten und was nicht unterstützt wird

- Nur das Admin-Panel, ohne den OHIF-Viewer: Rezept `adminonly` ([5.1](#variant-adminonly)).
- Hinter dem eigenen TLS-Proxy wie Traefik, Caddy, Apache oder Cloudflare Tunnel: Rezept `proxied` ([5.2](#variant-proxied)).
  Der Proxy beendet TLS. nginx behält die Anmeldung und die Sperren.
- nginx auf dem Host statt in einem Container: [5.3](#nginx-on-host).
- Ein erster Blick auf dem Server selbst durch einen SSH-Tunnel, ohne TLS: Rezept `tryit` ([5.4](#variant-tryit)).

Nicht unterstützt:

- dcm4chee mit eigener Keycloak-Anmeldung (die `-secure`-Images). Die Eingangstür ruft die REST-Schnittstelle von dcm4chee ohne
  Token auf. Das Archiv muss ohne Keycloak laufen.
- Traefik, Caddy oder Cloudflare **statt** nginx. Vor nginx können diese Produkte stehen (Rezept `proxied`). Die Sperren, das Protokoll und
  die Verbindung zum Hilfsdienst sind Funktionen von nginx.

<a id="how-to-read"></a>
### 1.4 So sind die Schritte zu lesen

- Jeden Befehl als root ausführen. Einmal mit `sudo -i` eine root-Shell öffnen und darin bleiben.
- Jeden Codeblock als Ganzes einfügen. Blöcke, die eine Frage stellen, sagen es.
- Ein Wert, der zu ändern ist, ist mit `CHANGE-ME` markiert oder ein Beispiel: `pacs.example.org` (Hostname), `192.0.2.10`
  (Adresse), `anna` (Konto). Jedes Beispiel durch den eigenen Wert ersetzen.
- Das Admin-Panel spricht Deutsch. Beschriftungen auf dem Bildschirm stehen in `code`, zum Beispiel `Protokoll`. Das
  [Glossar](glossary.de.md#screen-labels) erklärt sie.
- Ein **Prüfen**-Kasten zeigt den Befehl, die erwartete Ausgabe und wo man nachsieht, wenn die Ausgabe abweicht. Vergleichen,
  bevor es weitergeht.
- Ein **Warnung**-Kasten steht vor einem riskanten Schritt. Er nennt, was kaputtgehen kann, wie lange es dauert und wie man
  zurückgeht.

<a id="demo"></a>
## 2. Weg A: die Demo ausprobieren

Die Demo startet die echte Admin-Seite mit erfundenen Daten auf dem eigenen PC. Die Demo braucht Python 3.7 oder neuer, aber
kein dcm4chee, keine Anmeldung und keine root-Rechte, und nichts verlässt den Browser. Diesen Abschnitt überspringen, wenn die
echte Installation gewünscht ist.

Die Dateien mit git holen oder die ZIP-Datei von der Projektseite laden (Schaltfläche `Code`, dann `Download ZIP`) und
entpacken.

```bash
git clone https://github.com/pbaetz99/dcm4chee-admin-panel.git
cd dcm4chee-admin-panel
python3 demo/serve.py
```

Unter Windows den letzten Befehl als `python demo\serve.py` starten. Für einen anderen Port als 8000 eine Portnummer anhängen,
zum Beispiel `python3 demo/serve.py 8081`. Strg+C beendet die Demo.

> **Prüfen**
>
> Das Terminal gibt eine Zeile aus:
>
> ```text
> Demo: http://127.0.0.1:8000/admin/   (Strg+C beendet)
> ```
>
> Diese Adresse im Browser öffnen. Das Admin-Panel öffnet sich mit den Reitern `Übersicht`, `Studien`, `Patienten`, `Firewall`
> und `Protokoll`. Meldet das Terminal einen Fehler zum Port, die Demo mit einer anderen Portnummer starten.

Vier Optionen ändern die Demo-Seite. Diese Optionen an die Adresse anhängen:

- `?demo=platte` zeigt eine neue, leere Platte.
- `?demo=ohne` zeigt einen Status ohne Platten.
- `?demo=offen` öffnet alle Karten im Reiter `Firewall`.
- `?demo=abgelaufen` lässt jeden Aufruf wie eine abgelaufene Sitzung antworten. Die Seite zeigt `Sitzung abgelaufen`.

<a id="prerequisites"></a>
## 3. Vor dem Start

Zuerst diese Dinge zusammentragen. Jedes einzelne stoppt die Installation, wenn es fehlt.

- [ ] **Ein Server** mit Debian 13 oder Debian 12 (Ubuntu wurde nicht getestet), root-Zugriff, und das dcm4chee-Archiv läuft in
  Docker Compose.
- [ ] **Ein Wartungsfenster.** Die Basisinstallation startet dcm4chee nicht neu, belegt aber die Ports 80 und 443, und die
  optionalen Module starten `arc` neu.
- [ ] **Ein DNS-Name** für das PACS, zum Beispiel `pacs.example.org`, der auf diesen Server zeigt. Das Netzwerkteam fragen.
- [ ] **Ein TLS-Zertifikat** für diesen Namen oder Zeit, eines zu beschaffen ([4.8](#tls-certificate)). Nur das Rezept `tryit`
  kommt ohne aus.
- [ ] **Freie Ports 80 und 443** auf dem Server ([4.2](#preflight) prüft sie).
- [ ] **Internetzugang** zu GitHub (die Dateien), Docker Hub (die Images) und, für Weg B, `quay.io` (oauth2-proxy).
- [ ] **Nur Weg B:** eine Person, die in Microsoft Entra ID eine App registrieren und Gruppen anlegen darf, oder dasselbe Recht
  beim eigenen Anbieter. Früh fragen. Das kann Tage dauern.

Vor jeder Änderung Kopien der Compose-Dateien anlegen. Zuerst den Ordner des dcm4chee-Projekts finden:

```bash
docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' arc
```

Die Compose-Datei aus diesem Ordner kopieren. Gibt es schon eine OHIF-Compose-Datei, auch sie kopieren:

```bash
cp -a /opt/dcm4chee-arc/docker-compose.yml /root/dcm4chee-compose.$(date +%F).yml
[ -f /opt/ohif/docker-compose.yml ] && cp -a /opt/ohif/docker-compose.yml /root/ohif-compose.$(date +%F).yml
```

> **Warnung**
>
> Ein Webserver oder Container, der Port 80 oder 443 nutzt, blockiert die neue Eingangstür. Ihn in einem geplanten Schritt
> ersetzen: den alten stoppen, den neuen starten ([4.13](#start-and-check)). Dazwischen haben die Benutzer keinen Zugang, meist
> einige Minuten. Zum Zurückgehen `ohif` stoppen (`cd /opt/ohif && docker compose down`) und den alten Dienst aus der Kopie
> seiner Compose-Datei starten.

> **Prüfen**
>
> ```bash
> for h in github.com registry-1.docker.io quay.io; do printf '%s ' "$h"; curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 "https://$h/"; done
> ```
>
> Erwartet: eine Zeile pro Host mit einer Zahl. Jede Zahl außer `000` beweist, dass der Server den Host erreicht. `000` heißt:
> keine Verbindung. Einen Proxy oder eine Firewall-Regel beantragen und den Proxy auch für Docker setzen (siehe die
> Docker-Dokumentation).

<a id="real-install"></a>
## 4. Die echte Installation

Die Schritte der Reihe nach abarbeiten. Die Wege B und C teilen sich die Schritte. Wo sie sich unterscheiden, sagt es der
Schritt.

<a id="get-files"></a>
### 4.1 Die Dateien holen

Die Programmdateien kommen nach `/opt/pacs-admin`. Die systemd-Unit und die Cron-Datei erwarten genau diesen Ordner.

```bash
apt-get install -y git
git clone https://github.com/pbaetz99/dcm4chee-admin-panel.git /opt/pacs-admin
```

Ohne git die ZIP-Datei von der Projektseite laden, entpacken und den Ordner in `/opt/pacs-admin` umbenennen. Die Skripte laufen
mit `bash skript` und `python3 skript`, fehlende Ausführungsrechte spielen also keine Rolle.

> **Prüfen**
>
> ```bash
> ls -1 /opt/pacs-admin/deploy/tools
> ```
>
> Erwartet:
>
> ```text
> pacs-adduser.sh
> preflight.sh
> set-aet.sh
> ```
>
> Fehlt der Ordner, ist der Klon fehlgeschlagen. Die Fehlermeldung lesen; sie nennt ein Netzwerk- oder ein Rechteproblem.

<a id="preflight"></a>
### 4.2 Den Preflight-Check ausführen

`preflight.sh` ist ein Skript, das nur liest. Es ändert nichts. Es prüft Pakete, Docker, dcm4chee, Ports und DNS. Am Ende gibt es
den Block **Meine Werte** aus (im englischen Lauf **My values**): Namen und Pfade des eigenen Systems, die spätere Schritte
brauchen. Das Skript jetzt und nach jeder Korrektur ausführen.

```bash
bash /opt/pacs-admin/deploy/tools/preflight.sh --host pacs.example.org
```

`--host` prüft zusätzlich, ob der DNS-Name auf diesen Server zeigt. Spätere Schritte fügen `--cert` und `--key`
([4.8](#tls-certificate)) und `--dir /opt/ohif` ([4.13](#start-and-check)) hinzu. Die Ausgabe ist deutsch, wenn `LANG` mit `de`
beginnt. `--lang en` erzwingt Englisch.

Ein echter Lauf auf einem System, das bereit ist (lange Folgen von `[ OK ]`-Zeilen sind mit `...` gekürzt). Das Beispiel ist
englisch, so wie `--lang en` es ausgibt. Im deutschen Lauf stehen dieselben Zeilen auf Deutsch. Die Reihenfolge und die Marken
`[ OK ]`, `[WARN]` und `[FAIL]` bleiben gleich:

```text
dcm4chee admin panel: preflight check. This script only reads, it changes nothing on this host.

== 1. System and packages ==
[ OK ] running as root
[ OK ] repository: /opt/pacs-admin (where the systemd units and the cron file expect it)
[ OK ] operating system: Debian GNU/Linux 13 (trixie) (tested)
[ OK ] SQLCipher: libsqlcipher1 4.6.1-2 is installed
...
== 2. Docker and dcm4chee ==
[ OK ] docker: daemon reachable, version 27.5.1
[ OK ] docker compose: Docker Compose version v2.32.0
[ OK ] arc: arc (dcm4che/dcm4chee-arc-psql:5.35.1, running)
...
[ OK ] compose project directory of arc: /opt/dcm4chee-arc (matches PACS_DIR)
[ OK ] Docker network of arc: dcm4chee-arc_default
...
== 3. Host settings ==
[WARN] mount propagation of /mnt/fs: private
       With private propagation, a volume with :rslave is refused and new disks do not show up inside arc.
       Fix: mount --make-rshared /
[ OK ] uid 101 (nginx in the container) is free on this host
[ OK ] port 80 is free
[ OK ] port 443 is free
...
[ OK ] DNS: pacs.example.org -> 127.0.0.1 (an address of this host)

== Summary ==
Result: 30 ok, 1 warning(s), 0 failure(s)
READY, with warnings: read the [WARN] lines

My values (copy them where the install guide says "my values"; "(not found)" means: look it up by hand)
  what                               goes into                  value
  compose project directory          PACS_DIR                   /opt/dcm4chee-arc
  compose file(s)                    -                          /opt/dcm4chee-arc/docker-compose.yml
  Docker network of arc              compose file: network      dcm4chee-arc_default
  arc container                      ARC_CONTAINER, nginx       arc
  ldap container                     LDAP_CONTAINER             ldap
  db container                       -                          db
  wildfly log directory (host)       ARC_LOG_DIR                /var/local/dcm4chee-arc/wildfly/log/
  outside network interface          FW_INTERFACE               eth0
  uid of nginx / sockets             PACS_SOCKET_UID            101
  SQLCipher package                  apt-get install -y         libsqlcipher1
```

So ist die Ausgabe zu lesen:

- `[ OK ]` braucht nichts. `[WARN]` braucht Aufmerksamkeit, und seine Zeile `Fix:` (deutsch `Abhilfe:`) zeigt einen Befehl.
  `[FAIL]` stoppt die Installation: zuerst beheben. Der Exit-Code ist 0 (alles ok), 1 (Warnungen) oder 2 (Fehler).
- Die Warnung zur Mount-Propagation gehört zum Platten-Assistenten ([modules.de.md](modules.de.md#disk-assistant)) und kann
  ignoriert werden, solange der Assistent nicht genutzt wird.
- Die DNS-Zeile zeigt die Adresse des eigenen Servers, nicht `127.0.0.1`.
- Ein fehlendes Paket erscheint als `[FAIL]` oder `[WARN]`. Schritt 4.3 installiert es.
- Der Block „Lines still missing in /etc/default/pacs-admin“ (deutsch „Zeilen, die in /etc/default/pacs-admin noch fehlen“)
  listet Zeilen für Schritt 4.4.

> **Prüfen**
>
> Erwartet: Die letzten Zeilen der Zusammenfassung lauten `Result: ... 0 failure(s)` (deutsch `Ergebnis: ... 0 Fehler`) und
> eine der Zeilen `READY: all checks passed` oder `READY, with warnings: read the [WARN] lines` (deutsch
> `BEREIT: alle Pruefungen bestanden` oder `BEREIT, mit Warnungen: die [WARN]-Zeilen lesen`).
> `NOT READY: fix the [FAIL] lines first` (deutsch `NICHT BEREIT: zuerst die [FAIL]-Zeilen beheben`) heißt, dass eine
> `[FAIL]`-Zeile etwas nennt, das zu beheben ist. Beheben, das Skript noch einmal ausführen und, wenn die Zeile bleibt, die
> [Fehlersuche](troubleshooting.de.md#preflight-fails) lesen.

<a id="packages"></a>
### 4.3 Die Pakete installieren

Der Hilfsdienst braucht SQLCipher, eine Verschlüsselungsbibliothek für die Protokoll-Datenbank
([Glossar](glossary.de.md#sqlcipher)). Der Paketname hängt vom Debian-Release ab. Docker Compose muss Version 2 sein.

| Release | SQLCipher-Paket | Docker-Pakete |
|---|---|---|
| Debian 13 (trixie) | `libsqlcipher1` | `docker.io`, `docker-compose` (das ist Compose v2) |
| Debian 12 (bookworm) | `libsqlcipher0` | `docker.io`, `docker-compose-plugin` aus dem Docker-Repository (das Debian-Paket `docker-compose` ist Compose v1 und funktioniert nicht) |
| Ubuntu | nicht getestet | das Paket mit `apt-cache search sqlcipher` finden |

Die Pakete installieren, die der Preflight als fehlend gemeldet hat. Dieser Block installiert die Werkzeuge für Debian 13. Auf
Debian 12 `libsqlcipher0` nehmen.

```bash
apt-get update
apt-get install -y libsqlcipher1 git curl cron openssl iproute2 iptables util-linux e2fsprogs udev
```

Der Preflight gibt auch eine Schleife unter „Missing packages in one go“ (deutsch „Fehlende Pakete auf einmal“) aus. Die Schleife
installiert die Pakete einzeln und meldet ein Paket, das es nicht gibt.

> **Prüfen**
>
> ```bash
> bash /opt/pacs-admin/deploy/tools/preflight.sh | grep -E '^\[(WARN|FAIL)\]'
> ```
>
> Erwartet: keine `[FAIL]`-Zeile. Warnungen zur Mount-Propagation oder zu Ports sind an dieser Stelle erlaubt.

<a id="settings-file"></a>
### 4.4 Die Einstellungsdatei anlegen

Die Datei `/etc/default/pacs-admin` sagt dem Hilfsdienst, dem Cron-Job und den Werkzeugen, wo auf dem eigenen Server was liegt.
Jede Zeile des Beispiels ist auskommentiert und zeigt die eingebaute Vorgabe. Bei einem Standard-Layout von dcm4chee ändert man
wenig oder nichts.

```bash
cp /opt/pacs-admin/deploy/pacs-admin.env.example /etc/default/pacs-admin
```

Den Block **Meine Werte** aus Schritt 4.2 mit den Vorgaben vergleichen. Bei jedem abweichenden Wert das `#` vor der Zeile
entfernen und den eigenen Wert schreiben. Die Datei in einem Editor öffnen, zum Beispiel `nano /etc/default/pacs-admin`. Die
dritte Spalte nennt die Zeile des Blocks, wie der deutsche Lauf sie beschriftet. Diese Einstellungen können nötig sein:

| Name | Ändern, wenn | Wert aus „Meine Werte“ |
|---|---|---|
| `PACS_DIR` | der Ordner des dcm4chee-Projekts nicht `/opt/dcm4chee-arc` ist | `Compose-Verzeichnis` |
| `ARC_LOG_DIR` | das WildFly-Log woanders liegt | `wildfly-Log-Verzeichnis (Host)` |
| `ARC_CONTAINER`, `LDAP_CONTAINER` | die Container nicht `arc` und `ldap` heißen | `arc-Container`, `ldap-Container` |
| `DASHBOARD_CONTAINERS` | die Kachel `Dienste` auch `ohif` und `ohif-auth` zeigen soll | `arc,ldap,db,ohif,ohif-auth` |
| `PACS_SOCKET_UID` | uid 101 vergeben ist oder nginx auf dem Host läuft ([4.6](#helper-service), [5.3](#nginx-on-host)) | `uid von nginx / Sockets` |
| `FW_INTERFACE` | das Firewall-Modul genutzt wird | `Netzwerkschnittstelle nach aussen` |

Die Datei folgt strengen Regeln, weil die Shell und systemd sie beide lesen: eine Zeile `NAME=Wert` pro Einstellung, keine
Leerzeichen um `=`, kein `export`, kein Kommentar hinter einem Wert, ganze Zahlen für numerische Einstellungen und LF-Zeilenenden.
Alle Variablen stehen in der [Referenz](reference.de.md#config-variables), die Regeln unter
[Regeln für die Datei](reference.de.md#env-file-rules).

> **Prüfen**
>
> ```bash
> sh -n /etc/default/pacs-admin && echo syntax ok
> grep -c $'\r' /etc/default/pacs-admin
> ```
>
> Erwartet:
>
> ```text
> syntax ok
> 0
> ```
>
> Eine Zahl über 0 heißt Windows-Zeilenenden. Diese mit `sed -i 's/\r$//' /etc/default/pacs-admin` beheben.

<a id="audit-key"></a>
### 4.5 Den Protokollschlüssel anlegen

Das [Protokoll](glossary.de.md#audit-log) hält fest, wer gesucht, eine Studie geöffnet oder Daten geändert hat. Der Hilfsdienst
speichert es in einer verschlüsselten Datenbank. Der Schlüssel ist eine Datei mit 64 Hex-Zeichen. Nur root darf sie lesen. Der
Befehl unten erzeugt sie:

```bash
(umask 077; openssl rand -hex 32 > /etc/pacs-protokoll.key)
```

> **Warnung**
>
> Den Schlüssel nur einmal anlegen. Ein zweiter Lauf ersetzt ihn, und die bisher geschriebenen Ereignisse sind nicht mehr
> lesbar. Ohne den Schlüssel kann sie niemand wiederherstellen. Den Schlüssel jetzt sichern ([6.5](#backup-audit-key)).

Der Dienst legt die Datenbank `/var/lib/pacs-protokoll/protokoll.db` an, wenn er zum ersten Mal startet
([4.6](#helper-service)). Neue Dateien nutzen das SQLCipher-Format 3 (Seitengröße 1024), das Debian 12 und Debian 13 beide
öffnen. Eine Datei im SQLCipher-4-Format öffnet sich mit `libsqlcipher` 3.x (Debian 12) nicht, und es gibt keinen Konverter.
Meldet ein Werkzeug `file is not a database` (Debian 10 und 12: `file is encrypted or is not a database`), traf es auf einen
falschen Schlüssel, eine fremde Datei oder eine Datei im Format 4.

> **Prüfen**
>
> ```bash
> ls -l /etc/pacs-protokoll.key
> python3 /opt/pacs-admin/server/pacsdb.py test
> ```
>
> Erwartet: Die Datei hat 65 Bytes (64 Zeichen und ein Zeilenumbruch), den Besitzer `root` und den Modus `-rw-------`. Der
> Selbsttest nutzt eine Wegwerf-Datenbank, nicht den eigenen Schlüssel. Auf Debian 13 gibt er aus:
>
> ```text
> -rw------- 1 root root 65 Oct 13 14:50 /etc/pacs-protokoll.key
> Selbsttest ok: schreiben, lesen, Datei ohne Klartext, falscher Schluessel und fremde Datei abgewiesen, Format 3 (Seitengroesse 1024) und Bibliotheksstandard (4096) lesbar, SQLCipher 4.6.1 community
> ```
>
> `Selbsttest ok` heißt, dass der Selbsttest bestanden ist. Auf Debian 12 endet die Zeile mit
> `Bibliotheksstandard (1024) lesbar, SQLCipher 3.4.1`. Nennt sie eine fehlende Bibliothek, siehe die
> [Fehlersuche](troubleshooting.de.md#libsqlcipher-missing).
> Meldet ein Werkzeug später einen falschen Schlüssel, siehe die [Fehlersuche](troubleshooting.de.md#audit-key-mismatch).

<a id="helper-service"></a>
### 4.6 Den Hilfsdienst starten

Der [Hilfsdienst](glossary.de.md#helper-service) ist ein kleines Python-Programm, das als root unter systemd läuft. Er erledigt
die Arbeit, die nginx in einem Container nicht tun darf: Er schreibt das Protokoll, ändert Firewall-Regeln und führt den
Platten-Assistenten aus. nginx und der Dienst sprechen über zwei [Unix-Sockets](glossary.de.md#unix-socket) in
`/run/pacs-admin/`. Ein Unix-Socket ist eine Datei, die innerhalb eines Rechners wie ein Netzwerk-Port arbeitet. Der Dienst gibt
beide Sockets an die [uid](glossary.de.md#uid) von nginx im Container, das ist 101. Eine uid ist die Nummer, die Linux für ein
Konto nutzt.

Auf dem Host sollte kein Konto die uid 101 haben, weil jedes Programm eines solchen Kontos die Sockets nutzen könnte. Beide
Befehle unten sollten nichts ausgeben:

```bash
getent passwd 101
getent group 101
```

Gibt einer eine Zeile aus, siehe die [Fehlersuche](troubleshooting.de.md#uid-101-taken). Bei einem reinen Systemkonto (unter
Debian 12 oft `messagebus`) ist das Risiko klein, und der Dienst startet trotzdem mit einer Warnung. Danach die Unit installieren
und starten:

```bash
cp /opt/pacs-admin/deploy/systemd/pacs-verwaltung.service /etc/systemd/system/
systemctl enable --now pacs-verwaltung
```

`enable --now` startet den Dienst und startet ihn bei jedem Boot erneut. Das Skript nicht von Hand starten, solange die Unit
läuft. Es antwortet `laeuft schon`.

> **Prüfen**
>
> ```bash
> systemctl is-active pacs-verwaltung
> ls -l /run/pacs-admin/
> journalctl -u pacs-verwaltung -n 20 --no-pager
> curl -s --unix-socket /run/pacs-admin/verwaltung.sock http://localhost/admin/dienst/auftrag
> ```
>
> Erwartet: `active`, zwei Sockets mit dem Besitzer `101` und dem Modus `srw-------`, eine Bereit-Zeile im Journal und `{}` vom
> Dienst (das Datum weicht ab, und die Journal-Zeile beginnt mit Datum, Host und Programmname):
>
> ```text
> active
> total 0
> srw------- 1 101 root 0 Oct 13 14:50 protokoll.sock
> srw------- 1 101 root 0 Oct 13 14:50 verwaltung.sock
> pacs-verwaltung bereit: /run/pacs-admin/verwaltung.sock (HTTP) und /run/pacs-admin/protokoll.sock (Protokoll), Besitzer uid 101
> {}
> ```
>
> Eine Journal-Zeile mit `absender_sammeln` heißt, dass `ARC_LOG_DIR` falsch ist ([4.4](#settings-file)). Diese Zeile stoppt den Dienst
> nicht. Ist der Dienst nicht `active` oder fehlen die Sockets, siehe die
> [Fehlersuche](troubleshooting.de.md#no-sockets).

<a id="overview-cron"></a>
### 4.7 Den Übersichts-Job installieren

Der Reiter `Übersicht` braucht die Datei `status.json`. Ein [cron](glossary.de.md#cron)-Job schreibt sie alle 5 Minuten: Platten,
Container und den Stand der Schreibliste. Cron ist der Zeitplaner von Linux. Er läuft aus dem Paket `cron`.

```bash
cp /opt/pacs-admin/deploy/cron/pacs-dashboard /etc/cron.d/pacs-dashboard
```

Nicht auf den ersten Lauf warten. Den Job einmal von Hand starten. Er liest die Einstellungsdatei genauso wie der Cron-Job:

```bash
bash -c 'set -a; . /etc/default/pacs-admin; set +a; python3 /opt/pacs-admin/server/dashboard-status.py'
```

Liegt das Repository in einem anderen Ordner als `/opt/pacs-admin`, den Pfad in den kopierten Dateien einmal ändern:

```bash
sed -i 's|/opt/pacs-admin|/srv/pacs-admin|g' /etc/systemd/system/pacs-*.service /etc/cron.d/pacs-dashboard
systemctl daemon-reload && systemctl restart pacs-verwaltung
```

> **Prüfen**
>
> ```bash
> systemctl is-active cron
> ls -l /var/lib/pacs-admin/status/status.json
> ```
>
> Erwartet: `active`, dann eine Zeile für `status.json` mit dem Besitzer `root` und dem Modus `-rw-r--r--`. Größe und Datum
> weichen ab. Der manuelle Lauf gibt nichts aus, wenn er funktioniert. Gibt er `docker nicht gefunden` aus, ist Docker nicht
> installiert oder nicht im Pfad von root. Ist `cron` nicht `active`, siehe die
> [Fehlersuche](troubleshooting.de.md#cron-not-running).

<a id="tls-certificate"></a>
### 4.8 Das TLS-Zertifikat besorgen

Ein [TLS-Zertifikat](glossary.de.md#tls-certificate) lässt Browser dem Server vertrauen und verschlüsselt den Verkehr. nginx
braucht zwei Dateien in `/opt/ohif/tls/`: `server.crt` (das Zertifikat, gefolgt von seiner
[Kette](glossary.de.md#certificate-chain)) und `server.key` (der private Schlüssel). Dieser Schritt entfällt für die Rezepte
`proxied` (der eigene Proxy hält das Zertifikat) und `tryit` (kein TLS).

```bash
mkdir -p /opt/ohif/tls
```

**Von der eigenen IT-Abteilung oder einer Zertifizierungsstelle ([CA](glossary.de.md#ca)).** Ein Zertifikat für
`pacs.example.org` im [PEM](glossary.de.md#pem)-Format anfordern. Man bekommt es in einer von zwei Formen. Zwei PEM-Dateien
(Server-Zertifikat und Zwischenzertifikat): sie zusammenfügen, das Server-Zertifikat zuerst, und den Schlüssel kopieren.

```bash
cat server.pem intermediate.pem > /opt/ohif/tls/server.crt
cp server-key.pem /opt/ohif/tls/server.key
```

Eine [PFX](glossary.de.md#pfx)-Datei (`.pfx` oder `.p12`): umwandeln. `openssl` fragt nach dem Passwort der Datei.

```bash
openssl pkcs12 -in pacs.pfx -nocerts -nodes -out /opt/ohif/tls/server.key
openssl pkcs12 -in pacs.pfx -nokeys -out /opt/ohif/tls/server.crt
```

Die Ausgabedateien enthalten harmlose `Bag Attributes`-Zeilen. Eine alte PFX-Datei scheitert mit
`Error outputting keys and certificates`. Dann `-legacy` an beide Befehle anhängen.

**Let's Encrypt.** Dieser Dienst stellt kostenlose Zertifikate aus. Sein Werkzeug `certbot` muss beweisen, dass der Name einem
gehört, durch eine Datei auf Port 80 dieses Servers oder durch einen DNS-Eintrag. Ein Server, den das Internet nicht erreicht,
braucht den DNS-Weg. Diese Anleitung hat diesen Weg nicht getestet. `/etc/letsencrypt/live/pacs.example.org/fullchain.pem` nach
`server.crt` und `privkey.pem` nach `server.key` kopieren und das Kopieren nach jeder Erneuerung wiederholen
([6.3](#renew-certificate)).

**Selbstsigniert, für einen Test.** Ein Befehl erzeugt beide Dateien. Browser warnen vor einem solchen Zertifikat, und manche
Anmeldeanbieter lehnen es ab.

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 825 -keyout /opt/ohif/tls/server.key -out /opt/ohif/tls/server.crt \
  -subj "/CN=pacs.example.org" -addext "subjectAltName=DNS:pacs.example.org"
```

**Die Rechte setzen.** nginx liest den Schlüssel beim Start, und wer ihn lesen darf, hängt vom Image ab. Das OHIF-Image (Rezepte
`oauth2`, `basic`) führt den nginx-Hauptprozess als uid 101 aus, der Schlüssel muss also für 101 lesbar sein. Das normale
nginx-Image `nginx:1.30` (Rezept `adminonly`) und nginx auf dem Host führen ihn als root aus. Den passenden Block ausführen:

```bash
chown root:101 /opt/ohif/tls/server.key && chmod 640 /opt/ohif/tls/server.key
```

```bash
chown root:root /opt/ohif/tls/server.key && chmod 600 /opt/ohif/tls/server.key
```

Den Ordner `tls/` auf dem Modus 755 lassen. Ein geschlossener Ordner (700) stoppt den Container ebenfalls. Den Schlüssel nie per
E-Mail schicken und nie in ein Ticket oder in git legen.

> **Prüfen**
>
> ```bash
> bash /opt/pacs-admin/deploy/tools/preflight.sh --lang en --host pacs.example.org --cert /opt/ohif/tls/server.crt --key /opt/ohif/tls/server.key | sed -n '/== 4. TLS certificate/,/^$/p'
> ```
>
> Erwartet, hier für ein selbstsigniertes Zertifikat mit dem ersten Schlüsselmodus (die Daten weichen ab):
>
> ```text
> == 4. TLS certificate ==
> [ OK ] certificate: CN=pacs.example.org
> [ OK ] certificate valid until: Jan 15 15:27:00 2029 GMT (824 days)
> [ OK ] certificate covers pacs.example.org
> [WARN] self-signed certificate
>        Browsers warn about it, and some login providers refuse it. Fine for a test.
> [ OK ] private key: readable, no passphrase (2048 bit, 2 primes)
> [ OK ] private key: root:101 640
>        Which rights fit depends on the image: root:101 640 for the OHIF image (nginx master runs as uid 101), root:root 600 for the plain nginx image or nginx on the host (master is root). Give --dir with your compose file and this script knows which one applies.
> [ OK ] key matches the certificate
> ```
>
> Ein Zertifikat von einer CA zeigt keine `[WARN]`-Zeile. Eine `[FAIL]`-Zeile nennt das Problem und ein `Fix:`. Ohne `--dir`
> kennt der Preflight das nginx-Image nicht. Er nennt die Rechte des Schlüssels und warnt nur, wenn jeder ihn lesen kann; ein
> Schlüssel mit `root:root 600` (Rezept `adminonly`) besteht also ebenfalls. Schritt 4.13 führt die Prüfung mit `--dir` noch
> einmal aus und beurteilt die Rechte dann für das verwendete Image. Für einen Schlüssel, den nginx nicht lesen kann, siehe die
> [Fehlersuche](troubleshooting.de.md#tls-key-unreadable).

<a id="nginx-files"></a>
### 4.9 Die nginx-Dateien bauen

Die Eingangstür liest ihre Einstellungen aus einem Ordner mit kleinen Dateien, `/opt/ohif/nginx`. Man baut ihn aus dem
Repository in `deploy/nginx`. Er hat drei Teile, die man austauscht: das [Anmeldeverfahren](glossary.de.md#login-method), den
Viewer und den [Listener](glossary.de.md#listener) (wie nginx Verbindungen annimmt). Die Kerndatei `pacs.conf` bleibt, wie sie
ist. Bearbeitet wird nur `pacs/site.conf`. Jedes Detail steht in `deploy/nginx/README.de.md` und in der
[Referenz](reference.de.md#nginx-recipes).

Die drei Werte des eigenen Rezepts aus dieser Tabelle nehmen:

| Rezept | `LOGIN` | `VIEWER` | `LISTENER` |
|---|---|---|---|
| `oauth2` | `oauth2-proxy` | `ohif` | `tls` |
| `basic` | `basic` | `ohif` | `tls` |
| `adminonly` | `basic` | `none` | `tls` |
| `proxied` | `basic` | `ohif` | `behind-proxy` |
| `tryit` | `basic` | `none` | `plain` |

Die Anmeldung `none` (Netzlisten, [login.de.md](login.de.md#login-none)) nimmt `LOGIN=none` und sonst die Werte von `basic`. Die
eigenen Werte in die erste Zeile schreiben und den Block ausführen:

```bash
LOGIN=basic; VIEWER=ohif; LISTENER=tls
N=/opt/pacs-admin/deploy/nginx; T=/opt/ohif/nginx
mkdir -p $T/pacs/login $T/pacs/listener $T/pacs/optional
cp $N/pacs.conf $T/pacs.conf
cp $N/site.conf.example $T/pacs/site.conf
cp $N/common/*.conf $T/pacs/
cp $N/optional/dcm4chee-ui.conf $T/pacs/optional/
cp $N/login/$LOGIN/*.conf $T/pacs/login/
cp $N/viewer/$VIEWER.conf $T/pacs/viewer.conf
cp $N/listener/$LISTENER/*.conf $T/pacs/listener/
```

Die Zeile mit `optional/dcm4chee-ui.conf` kopiert den optionalen Abschnitt für die dcm4chee-Benutzeroberfläche
([modules.de.md](modules.de.md#dcm4chee-ui)). Wer den Abschnitt nicht will, lässt diese Zeile weg. Die Zahl in der Prüfung
unten ist dann `12`.

Jetzt `site.conf` bearbeiten. Zuerst den Namen eintragen, den die Benutzer im Browser tippen:

```bash
HOST=pacs.example.org
sed -E -i "s/^(server_name +)[^;]+;.*/\1${HOST};/" /opt/ohif/nginx/pacs/site.conf
```

Bei `basic` oder `none` entscheidet die Datei `admins`, wer Administrator ist, also die Zeile der Admin-Gruppe löschen. Bei
`oauth2-proxy` bleibt sie: Schritt 4.12 setzt sie.

```bash
sed -i '/^set \$pacs_admin_group/d' /opt/ohif/nginx/pacs/site.conf
```

Rezept `proxied`: jetzt den Adressbereich des eigenen Proxys setzen ([5.2](#variant-proxied)). Anmeldung `none`: jetzt ihre
beiden Zulassungslisten setzen ([login.de.md](login.de.md#login-none)).

> **Prüfen**
>
> ```bash
> find /opt/ohif/nginx -type f | wc -l
> grep -rn CHANGE-ME /opt/ohif/nginx
> ```
>
> Erwartet: `13` Dateien für jede Kombination und keine Ausgabe von `grep`. Diese Marker bleiben bis zu einem späteren Schritt:
> `oauth2` behält die Zeile `pacs_admin_group` (Schritt 4.12), `proxied` die Zeile `set_real_ip_from` ([5.2](#variant-proxied)),
> die Anmeldung `none` ihre Zulassungslisten. Weicht die Anzahl ab, hat eine der drei `cp`-Zeilen einen falschen Wert genutzt;
> den Block noch einmal ausführen.

Die Dateien vor dem ersten Start testen. Ein Wegwerf-Container prüft die Syntax und verschwindet danach wieder. Bei `tryit` und
`proxied` die zweite `-v`-Option weglassen, weil diese Rezepte keinen Ordner `tls` haben.

```bash
docker run --rm -v /opt/ohif/nginx:/etc/nginx/conf.d:ro -v /opt/ohif/tls:/etc/nginx/tls:ro nginx:1.30 nginx -t
```

> **Prüfen**
>
> Erwartet: diese letzten beiden Zeilen. Meldungen zu `default.conf` und zu IPv6 davor sind harmlos.
>
> ```text
> nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
> nginx: configuration file /etc/nginx/nginx.conf test is successful
> ```
>
> `cannot load certificate` heißt, dass `tls/server.crt` oder `server.key` fehlt (Schritt 4.8). Jede andere `[emerg]`-Zeile nennt
> die Datei und die Zeile. Siehe die [Fehlersuche](troubleshooting.de.md#nginx-wont-start).

<a id="compose-file"></a>
### 4.10 Die Compose-Datei kopieren und die Werte eintragen

Die Compose-Datei in `/opt/ohif` definiert den Container `ohif` (und für Single Sign-on `ohif-auth`). Die Datei des eigenen
Rezepts kopieren:

```bash
RECIPE=basic
cp /opt/pacs-admin/deploy/compose/docker-compose.$RECIPE.example.yml /opt/ohif/docker-compose.yml
```

Das Docker-Netzwerk des dcm4chee-Projekts eintragen, damit nginx `arc` über den Namen erreicht. Der Name steht im Block
**Meine Werte** (Schritt 4.2) und in der Ausgabe von `docker network ls`.

```bash
NETWORK=dcm4chee-arc_default
sed -i -E "s|^(    name: ).*# CHANGE-ME: name of that network.*|\1${NETWORK}|" /opt/ohif/docker-compose.yml
```

Jedes Rezept braucht andere Einträge im Ordner `/opt/ohif`. Für jeden fehlenden Eintrag legt Docker einen leeren Ordner an, der
root gehört, und der Dienst dahinter fällt aus. Die Schritte in Klammern erzeugen die Einträge.

| Rezept | `tls/` (4.8) | `htpasswd/` (4.12) | `app-config.js` (4.11) | `config.js` (4.11) | `ohif-auth.env` (4.12) |
|---|---|---|---|---|---|
| `oauth2` | ja | | ja | optional | ja |
| `basic` | ja | ja | ja | optional | |
| `adminonly` | ja | ja | | nötig | |
| `proxied` | | ja | ja | optional | |
| `tryit` | | ja | | nötig | |

> **Prüfen**
>
> ```bash
> grep -n 'CHANGE-M[E]' /opt/ohif/docker-compose.yml
> docker compose -f /opt/ohif/docker-compose.yml config --quiet && echo "compose file ok"
> ```
>
> Erwartet: keine Ausgabe von `grep` (die Klammern halten den Kopfkommentar der Datei aus dem Ergebnis), dann `compose file ok`.
> In zwei Rezepten bleiben weitere Marker: `proxied` behält die Zeile für das Proxy-Netzwerk ([5.2](#variant-proxied)), und
> `oauth2` behält fünf Zeilen (Tenant, zwei Gruppen, Redirect-URI, Proxy-Subnetz), die Schritt 4.12 füllt. Den zweiten Befehl
> für `oauth2` erst nach Schritt 4.12 ausführen, weil er `ohif-auth.env` braucht. Ein YAML-Fehler nennt die Zeile, die zu
> korrigieren ist.

<a id="viewer-config"></a>
### 4.11 Den Viewer und die Seiteneinstellungen einrichten

Zwei kleine Dateien passen an, was die Benutzer sehen. Die Compose-Datei bindet sie in den Container ein.

**Rezepte mit Viewer (`oauth2`, `basic`, `proxied`): `app-config.js`.** Die Datei sagt dem OHIF-Viewer, wo das Archiv liegt (die
Adresse der Seite selbst, AE-Titel `DCM4CHEE`), und schaltet Funktionen ab, die die Eingangstür nicht erlaubt.

```bash
cp /opt/pacs-admin/deploy/app-config.js.example /opt/ohif/app-config.js
```

Die Datei so lassen, wie sie ist. `supportsReject: false`, `dicomUploadEnabled: false` und den bulkDataURI-Block nie ändern: Die
Sperren der Eingangstür verlassen sich darauf. Für einen anderen AE-Titel `set-aet.sh` nutzen
([Referenz](reference.de.md#command-set-aet)). Jede Zeile erklärt die [Referenz](reference.de.md#app-config-js). Nach einer
Änderung `docker compose restart` in `/opt/ohif` ausführen, weil der Container eine eingebundene Einzeldatei nur beim Start liest.

**Rezepte ohne Viewer (`adminonly`, `tryit`): `config.js` ist nötig.** Die Datei blendet den Link `Viewer` in der oberen Leiste aus.
Kopieren, `viewerUrl: ''` setzen und das `# ` vor der Mount-Zeile in der Compose-Datei entfernen:

```bash
cp /opt/pacs-admin/web/admin/config.js /opt/ohif/config.js
sed -i "s|^\( *viewerUrl: \)'/',|\1'',|" /opt/ohif/config.js
sed -i -E 's|^( +)# (- \./config\.js:)|\1\2|' /opt/ohif/docker-compose.yml
```

**Rezepte mit Viewer: `config.js` ist optional.** Die Datei setzt den Seitentitel, die AE-Titel, die Links und die Sprache (Schlüssel
`titel`, `aet`, `iocmAet`, `dcm4cheeUrl`, `viewerUrl`, `logo`, `locale`, `kontoUrl`, `abmeldenUrl`; siehe
[Referenz](reference.de.md#config-js)). Um sie zu nutzen, den Befehl `cp` und den letzten Befehl `sed` von oben ausführen, die
Kopie bearbeiten und nach jeder Änderung `docker compose restart` in `/opt/ohif` ausführen.

> **Warnung**
>
> Die Kopie in `/opt/ohif` bearbeiten, nie `/opt/pacs-admin/web/admin/config.js`. `git pull` bricht bei einer geänderten Datei mit
> einem Konflikt ab ([6.1](#update)). Um einen Fehler in der Kopie rückgängig zu machen, sie löschen und das Original noch einmal
> kopieren.

> **Prüfen**
>
> ```bash
> grep -n 'viewerUrl' /opt/ohif/config.js
> grep -n '^ *- \./config\.js' /opt/ohif/docker-compose.yml
> ```
>
> Erwartet für ein Rezept ohne Viewer (das Beispiel zeigt `adminonly`; die Zeile des Mounts hat dort die Nummer 71, bei `tryit` die Nummer 67):
>
> ```text
> 8:  viewerUrl: '',                       // Verweis "Viewer" im Kopf, leer = ausblenden
> 71:      - ./config.js:/srv/pacs-admin/admin/config.js:ro
> ```
>
> Die Datei `app-config.js` prüft der Preflight-Lauf in Schritt 4.13. Nach dem Start lässt sich auch
> `https://pacs.example.org/app-config.js` öffnen: Der Skripttext erscheint.

<a id="login-setup"></a>
### 4.12 Die Anmeldung einrichten

Das Kapitel zur Anmeldung des eigenen Rezepts schließt die Einrichtung ab. Den passenden Teil nutzen.

**Single Sign-on (`oauth2`).** [login.de.md](login.de.md#login-oauth2-entra), Schritte 1 bis 9 befolgen. Diese Schritte
registrieren die App in Microsoft Entra ID, schreiben `ohif-auth.env`, füllen die fünf übrigen Marker-Zeilen der Compose-Datei und
tragen die Admin-Gruppe in `site.conf` ein. Vor Schritt 10 aufhören, denn er startet die Container. Schritt 4.13 startet sie ebenfalls, und
ein zweites `docker compose up -d` schadet nicht. Die Schritte 4.9 und 4.10 haben den Host-Namen und den Netzwerknamen schon
gesetzt. login.de.md setzt sie noch einmal, was nicht schadet, und sein Schritt 8 listet dann fünf Marker-Zeilen statt sechs.
Für einen anderen Anbieter siehe [login.de.md](login.de.md#login-oauth2-providers).

**Konten, die nginx führt (`basic`, `adminonly`, `proxied`, `tryit`).** Das erste Konto mit dem Hilfsskript anlegen. `admin`
lässt das Konto das Admin-Panel und den Viewer nutzen. `all` lässt es nur den Viewer nutzen. Das Skript fragt zweimal nach dem
Passwort (mindestens 10 Zeichen) und legt `/opt/ohif/htpasswd/users` (alle Konten) und `admins` an.

```bash
bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh admin anna
```

nginx liest die beiden Dateien bei jeder Anfrage, neue Konten gelten also sofort. Den Befehl für jede Person erneut ausführen.
Derselbe Name mit einem neuen Passwort ersetzt das alte Passwort. Um ein Konto zu entfernen, seine Zeile aus beiden Dateien
löschen und mindestens einen Administrator behalten:

```bash
sed -i '/^anna:/d' /opt/ohif/htpasswd/users /opt/ohif/htpasswd/admins
```

Grenzen dieser Anmeldung (keine Abmeldung, kein zweiter Faktor, keine Begrenzung für falsche Passwörter):
[login.de.md](login.de.md#login-basic).

> **Prüfen**
>
> ```bash
> ls -ln /opt/ohif/htpasswd
> ```
>
> Erwartet: Das Skript hat diese Zeilen ausgegeben (für `admin`, hier in der englischen Ausgabe; mit `LANG=de_DE.UTF-8` stehen sie
> auf Deutsch, die Zusammenfassung lautet dann `Besitzer 101, Modus 600, Passwort-Hash-Typ sha512-crypt`), und die beiden Dateien
> gehören der uid 101 mit dem Modus 600:
>
> ```text
> account 'anna' (admin)
>   directory /opt/ohif/htpasswd created (mode 755)
>   /opt/ohif/htpasswd/users: line added
>   /opt/ohif/htpasswd/admins: line added
>   owner 101, mode 600, password hash type sha512-crypt
>   nginx reads the files at every request: no restart needed.
> ```
>
> ```text
> -rw------- 1 101 0 112 Oct 13 15:31 admins
> -rw------- 1 101 0 112 Oct 13 15:31 users
> ```
>
> Die Größe in Byte ist die Länge des Namens plus 108 (Name, Doppelpunkt, Hash aus 106 Zeichen, Zeilenumbruch), ein anderer
> Name ergibt also eine andere Zahl. `the password is shorter than 10 characters` und `invalid name` (deutsch:
> `das Passwort ist kuerzer als 10 Zeichen` und `ungueltiger Name`) stoppen das Skript ohne Änderung. Die Zeile
> `WARNING: this openssl cannot make sha512-crypt hashes` (deutsch: `WARNUNG: dieses openssl kann keine sha512-crypt-Hashes`)
> bedeutet, dass OpenSSL älter als 1.1.1 ist: Das Skript nimmt stattdessen den schwächeren Hash-Typ `apr1`, und die
> Zusammenfassung nennt `password hash type apr1`. OpenSSL aktualisieren und den Befehl erneut ausführen. Fehlen die beiden
> Dateien oder kann der nginx-Worker sie nicht lesen, fragt der Browser nach einem Passwort und zeigt dann eine Fehlerseite:
> 403 bei einer fehlenden Datei, 500 bei einer nicht lesbaren ([Fehlersuche](troubleshooting.de.md#htpasswd-403-500)).

**Keine Anmeldung (`none`).** Nur Netzlisten begrenzen den Zugang. Den leeren Ordner anlegen, den die Compose-Datei einbindet,
und dann [login.de.md](login.de.md#login-none) folgen:

```bash
mkdir -p /opt/ohif/htpasswd
```

<a id="start-and-check"></a>
### 4.13 Die Eingangstür starten und prüfen

Beim ersten Start lädt Docker die Images herunter. Das dauert eine Minute oder länger.

> **Warnung**
>
> Der Start übernimmt die Ports 80 und 443 (`tryit`: 8080 auf 127.0.0.1; `proxied`: kein Port). Benutzer einer alten Eingangstür
> verlieren in diesem Moment den Zugang. Antwortet Docker mit `address already in use`, hält ein anderes Programm den Port noch:
> dieses zuerst beenden (Abschnitt 3). `arc`, `ldap` und `db` bleiben unberührt. Um zurückzugehen,
> `cd /opt/ohif && docker compose down` ausführen und die alte Eingangstür aus der eigenen Kopie ihrer Compose-Datei starten.

```bash
cd /opt/ohif && docker compose up -d
```

Docker gibt je Container ein paar Zeilen aus und endet mit `Started`:

```text
 Container ohif Creating
 Container ohif Created
 Container ohif Starting
 Container ohif Started
```

> **Prüfen**
>
> ```bash
> docker ps --format '{{.Names}}  {{.Status}}' | grep '^ohif'
> docker exec ohif nginx -t
> docker logs ohif 2>&1 | grep -c emerg
> curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/
> ```
>
> Erwartet (`oauth2` listet auch `ohif-auth`):
>
> ```text
> ohif  Up 7 seconds
> nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
> nginx: configuration file /etc/nginx/nginx.conf test is successful
> 0
> 401
> ```
>
> Die letzte Zahl hängt von der Anmeldung ab, ohne Passwort abgefragt: `oauth2` antwortet `302` (zur Anmeldeseite), `basic` `401`,
> `none` `403` von einem PC außerhalb der Zulassungsliste. Löst sich der Name noch nicht auf,
> `--resolve pacs.example.org:443:127.0.0.1` an `curl` anhängen. Bei `basic` muss dieser Aufruf `200` liefern (`curl` fragt nach
> dem Passwort): `curl -sk -u anna -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/`.
> Ein Status `Restarting`, eine Anzahl über `0` oder eine andere Zahl: `docker logs ohif` lesen und die
> [Fehlersuche](troubleshooting.de.md#nginx-wont-start) ansehen. Für `proxied` und `tryit` statt des `curl`-Aufrufs die
> Prüfungen in Abschnitt 5 nutzen.

Den Preflight-Check noch einmal ausführen, jetzt mit Ordner, Zertifikat und Schlüssel:

```bash
bash /opt/pacs-admin/deploy/tools/preflight.sh --host pacs.example.org --cert /opt/ohif/tls/server.crt --key /opt/ohif/tls/server.key --dir /opt/ohif
```

> **Prüfen**
>
> Erwartet: keine `[FAIL]`-Zeile. Zwei Warnungen sind jetzt normal, `[WARN] port 80 is already in use`
> (deutsch: `Port 80 ist schon belegt`) und dieselbe für Port 443, weil der eigene Container die Ports hält. Die letzte Gruppe
> zeigt (englische Ausgabe, die Zahlen hängen vom Rezept ab):
>
> ```text
> == 5. Configuration files ==
> [ OK ] /etc/default/pacs-admin: syntax ok (shell and systemd read it the same way)
> [ OK ] /opt/ohif: no CHANGE-ME and no <placeholder> left in 15 file(s)
> [ OK ] nginx tree /opt/ohif/nginx: all 11 included files exist
> [ OK ] compose bind mounts: all 8 sources exist and look complete
> ```
>
> Eine `[WARN]`- oder `[FAIL]`-Zeile in dieser Gruppe nennt die Datei und einen `Fix:`-Befehl (deutsch `Abhilfe:`).

<a id="first-test"></a>
### 4.14 Im Browser testen

1. `https://pacs.example.org/admin/` öffnen und anmelden. Bei `basic` fragt der Browser nach einem Benutzernamen und einem
   Passwort. Bei `oauth2` öffnet er die Seite des Identitätsanbieters.
2. Die obere Leiste zeigt die Reiter `Übersicht`, `Studien`, `Patienten`, `Firewall` und `Protokoll` und die Links `dcm4chee`
   und `Viewer`. `Abmelden` erscheint bei oauth2-proxy ([login.de.md](login.de.md#login-oauth2-operate)).
3. Der Reiter `Übersicht` zeigt die Kacheln `Dienste`, `Speicher` und `Letzte Änderungen`. Sagt die Kachel
   `Kein Status vorhanden`, den Job aus Schritt 4.7 von Hand starten. Die Kachel `Dienste` listet die Container des
   dcm4chee-Projekts. Um `ohif` und `ohif-auth` zu ergänzen, `DASHBOARD_CONTAINERS=arc,ldap,db,ohif,ohif-auth` setzen
   ([4.4](#settings-file)).
4. Den Link `Viewer` und eine Studie öffnen (Rezepte mit Viewer). Dann den Reiter `Protokoll` öffnen, `Heute` wählen und auf
   `Anzeigen` klicken. Die Liste zeigt eine Zeile `Studie geöffnet` mit dem eigenen Konto.

![Der Reiter Übersicht](screenshots/overview.png)

> **Prüfen**
>
> ```bash
> journalctl -u pacs-verwaltung -n 50 --no-pager | grep -c 'Protokoll nicht abgelegt'
> ```
>
> Erwartet: `0`. Eine Zahl über 0 heißt, dass der Hilfsdienst Protokollzeilen nicht ablegen konnte: siehe die
> [Fehlersuche](troubleshooting.de.md#audit-key-mismatch). Ein `502` auf der Admin-Seite: siehe die
> [Fehlersuche](troubleshooting.de.md#admin-dienst-502).

<a id="optional-modules"></a>
### 4.15 Optionale Module

Die Basisinstallation ist vollständig. Drei Module bringen mehr. Jedes hat ein eigenes Kapitel in
[modules.de.md](modules.de.md) und ist für das Admin-Panel nicht nötig:

- Der **Platten-Assistent** bereitet neue Platten für den dcm4chee-Speicher vor
  ([modules.de.md](modules.de.md#disk-assistant)).
- Die **Firewall** begrenzt, welche Rechner die DICOM-Ports des Archivs erreichen ([modules.de.md](modules.de.md#firewall)).
- Die **dcm4chee-Benutzeroberfläche** gibt Administratoren die Weboberfläche von dcm4chee selbst hinter derselben Anmeldung
  ([modules.de.md](modules.de.md#dcm4chee-ui)). Schritt 4.9 hat ihre nginx-Datei schon kopiert.

> **Warnung**
>
> Der Platten-Assistent und die Firewall ändern die Compose-Datei des dcm4chee-Projekts und erzeugen den Container `arc`
> neu. Das Archiv ist unerreichbar, bis `arc` wieder läuft. Das in einem Wartungsfenster tun. Mit `docker compose ps` und
> `docker logs arc` im dcm4chee-Ordner prüfen. Um zurückzugehen, die Kopie der Compose-Datei aus Abschnitt 3 zurückspielen
> (`cp /root/dcm4chee-compose.DATE.yml /opt/dcm4chee-arc/docker-compose.yml`) und dort `docker compose up -d` ausführen.

<a id="variants-detail"></a>
## 5. Varianten im Detail

Jede Variante ändert ein paar Schritte aus Abschnitt 4. Dieser Abschnitt nennt nur die Unterschiede. Alles andere bleibt, wie
beschrieben.

<a id="variant-adminonly"></a>
### 5.1 Nur das Admin-Panel (`adminonly`)

Es gibt keinen OHIF-Viewer, und nginx läuft im normalen Image `nginx:1.30`. Schritt 4.8: Der Schlüssel bekommt `root:root 600`
(der zweite Block). Schritt 4.9: `LOGIN=basic; VIEWER=none; LISTENER=tls`. Schritt 4.10: `docker-compose.adminonly.example.yml`
kopieren. Schritt 4.11: kein `app-config.js`, aber `config.js` mit `viewerUrl: ''` ist nötig. Schritt 4.12: Konten wie bei
`basic`.

> **Prüfen**
>
> ```bash
> curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/
> bash /opt/pacs-admin/deploy/tools/preflight.sh --lang en --host pacs.example.org --cert /opt/ohif/tls/server.crt --key /opt/ohif/tls/server.key --dir /opt/ohif | grep 'private key permissions'
> ```
>
> Erwartet: Die Startseite leitet zum Admin-Panel weiter, und der Schlüsselmodus passt zum normalen Image.
>
> ```text
> 302
> [ OK ] private key permissions fit the plain nginx image (root:root 600)
> ```

<a id="variant-proxied"></a>
### 5.2 Hinter dem eigenen TLS-Proxy (`proxied`)

Ein Proxy, der schon läuft (Traefik, Caddy, Apache, Cloudflare Tunnel), beendet TLS und gibt den Verkehr über einfaches http an
den Container `ohif` weiter. nginx behält die Anmeldung, die Sperren und das Protokoll. Der Container veröffentlicht keinen Port,
und nur der Proxy darf ihn erreichen. Sonst könnte jeder eine falsche Client-Adresse in `X-Forwarded-For` schreiben, und das
Protokoll würde sie glauben.

- Schritt 4.8 entfällt. Schritt 4.9: `LOGIN=basic; VIEWER=ohif; LISTENER=behind-proxy`. Schritt 4.10:
  `docker-compose.proxied.example.yml` kopieren. Schritt 4.12: Konten wie bei `basic`. Für Single Sign-on hinter einem Proxy
  siehe [login.de.md](login.de.md#login-other).
- Das Docker-Netzwerk benennen, das der Proxy und `ohif` teilen. Am besten eignet sich ein Netzwerk, das nur diese beiden nutzen.
  Sitzt der Proxy im dcm4chee-Netzwerk selbst, stattdessen den Block `proxy:` und die Zeile `- proxy` in der Compose-Datei
  löschen.
- nginx das Subnetz dieses Netzwerks nennen, denn nur dieses Netzwerk darf Client-Adressen melden. Der mitgelieferte Wert `203.0.113.1` vertraut niemandem; der letzte Befehl ersetzt ihn.

```bash
PROXY_NETWORK=proxy_default
sed -i -E "s|^(    name: ).*# CHANGE-ME: name of the network of your proxy.*|\1${PROXY_NETWORK}|" /opt/ohif/docker-compose.yml
PROXY_NET=$(docker network inspect $PROXY_NETWORK -f '{{(index .IPAM.Config 0).Subnet}}')
sed -E -i "s|^(set_real_ip_from +)[^;]+;.*|\1${PROXY_NET};|" /opt/ohif/nginx/pacs/listener/server.conf
```

Im Proxy den Host-Namen an `http://ohif:8080` schicken (Container-Name und Container-Port). Den `Host`-Header unverändert
weitergeben (Apache: `ProxyPreserveHost On`) und die Client-Adresse in `X-Forwarded-For` (Traefik, Caddy und Cloudflare Tunnel
tun das). Lauscht der Proxy auf einem anderen Port als 443, diesen Port in das Muster in `pacs/listener/http.conf` eintragen.

> **Prüfen**
>
> ```bash
> grep -n set_real_ip_from /opt/ohif/nginx/pacs/listener/server.conf
> curl -s -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/
> ```
>
> Erwartet: Die Zeile zeigt das eigene Subnetz, zum Beispiel `5:set_real_ip_from 172.23.0.0/16;`, und der Aufruf über den Proxy
> antwortet `401`. Den zweiten Befehl auf einem PC ausführen, nicht auf dem Server, wenn der Proxy auf einem anderen Host läuft.
> Ein `502` oder `504` kommt vom Proxy: den Netzwerknamen und das Ziel `http://ohif:8080` prüfen.

<a id="nginx-on-host"></a>
### 5.3 nginx auf dem Host

nginx kann auch als Paket auf dem Host laufen. Diese Variante hat keinen OHIF-Viewer, weil das Debian-Paket die OHIF-Dateien
nicht enthält. Gebraucht wird nginx 1.25.1 oder neuer. Debian 13 hat 1.26. Debian 12 hat 1.22 (siehe den letzten Block dieses
Teils). Die Schritte 4.1 bis 4.7 bleiben. Der Container `ohif` kommt nicht vor, deshalb entfallen die Schritte 4.10, 4.11
(`app-config.js`) und 4.13. Das vollständige Rezept steht im Abschnitt `host-nginx` von `deploy/nginx/README.de.md`.

1. nginx installieren. Die Standard-Site entfernen, sonst meldet nginx einen doppelten Default-Server.

   ```bash
   apt-get install -y nginx openssl
   rm -f /etc/nginx/sites-enabled/default
   ```

2. Die nginx-Dateien wie in Schritt 4.9 bauen, mit `T=/etc/nginx/conf.d`, `VIEWER=none`, `LISTENER=tls` und dem eigenen `LOGIN`.
   Dann die Host-Ports nutzen und nginx auf das Archiv an der Loopback-Adresse zeigen lassen.

   ```bash
   T=/etc/nginx/conf.d
   sed -i -e 's/8080/80/g' -e 's/8443/443/g' $T/pacs/listener/*.conf
   sed -i -e 's#^set \$arc .*#set $arc http://127.0.0.1:8080;#' -e '/^resolver /d' $T/pacs/site.conf
   ```

3. Die Admin-Seite und die Statusdatei dorthin legen, wo `pacs.conf` sie erwartet.

   ```bash
   mkdir -p /srv/pacs-admin /var/lib/pacs-admin/status
   ln -sfn /opt/pacs-admin/web/admin /srv/pacs-admin/admin
   ln -sfn /var/lib/pacs-admin/status /srv/pacs-admin/status
   ```

4. Die nginx-Worker laufen als `www-data` (uid 33). Der Hilfsdienst muss seine Sockets an diese uid geben
   ([4.6](#helper-service)).

   ```bash
   sed -i 's/^#PACS_SOCKET_UID=.*/PACS_SOCKET_UID=33/' /etc/default/pacs-admin
   systemctl restart pacs-verwaltung
   ```

   Der Dienst warnt, dass `www-data` geteilt wird. Läuft PHP oder eine andere Webanwendung als `www-data`, bekommt nginx besser
   ein eigenes Konto: `useradd -r -s /usr/sbin/nologin pacsweb`, die Zeile `user pacsweb;` in `/etc/nginx/nginx.conf` und die
   uid dieses Kontos in `PACS_SOCKET_UID`.

5. Die Konten in `/etc/nginx/htpasswd/` anlegen, mit Besitzer und Modus, die zu den Workern passen.

   ```bash
   mkdir -p /etc/nginx/htpasswd
   bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh admin anna --users /etc/nginx/htpasswd/users --admins /etc/nginx/htpasswd/admins --owner root:www-data --mode 640
   ```

6. In `/etc/nginx/conf.d/pacs/site.conf` `server_name` wie in Schritt 4.9 setzen. Die letzten beiden Zeilen von
   `/etc/nginx/conf.d/pacs/listener/server.conf` sind die Zeilen `ssl_certificate`; diese müssen auf die eigenen Dateien zeigen
   (bei Let's Encrypt: `/etc/letsencrypt/live/pacs.example.org/fullchain.pem` und `privkey.pem`). Der Schlüssel bekommt
   `root:root 600`, weil der nginx-Hauptprozess root ist.
7. Das Archiv muss auf `127.0.0.1:8080` lauschen. Zeigt die Prüfung unten nichts, die Zeile `ports` von `arc` in der
   Compose-Datei des dcm4chee-Projekts auf `127.0.0.1:8080:8080` ändern und `arc` neu erzeugen.

> **Warnung**
>
> Beim Neuerzeugen von `arc` ist das Archiv unerreichbar, bis es wieder läuft. Mit `docker compose ps` und `docker logs arc` im
> dcm4chee-Ordner prüfen. Um zurückzugehen, die Kopie der Compose-Datei aus Abschnitt 3 zurückspielen und
> `docker compose up -d` ausführen.

Unter Debian 12 (nginx 1.22) den Listener vor dem ersten Start ändern, sonst bricht nginx mit `unknown directive "http2"` ab.
Diese Änderung wurde unter Debian 12 mit nginx 1.22.1 geprüft: `nginx -t` meldet keinen Fehler, HTTP/2 funktioniert, und Port 80
leitet auf https um.

```bash
sed -i -e '/^http2 on;/d' -e 's/^listen 443 ssl default_server;/listen 443 ssl http2 default_server;/' /etc/nginx/conf.d/pacs/listener/server.conf
```

> **Prüfen**
>
> ```bash
> ss -ltn | grep '127.0.0.1:8080'
> nginx -t && systemctl reload nginx
> curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/
> ```
>
> Erwartet: eine `LISTEN`-Zeile für `127.0.0.1:8080`, dann `syntax is ok` und `test is successful`, und `401` (`basic`) oder
> `302` (`oauth2-proxy`). Startet nginx nicht, siehe die [Fehlersuche](troubleshooting.de.md#nginx-wont-start).

Der Reiter `Firewall` filtert nur Docker-Verkehr, deckt also die Ports 80 und 443 des Hosts nicht ab. nginx sollte nach dem
Hilfsdienst starten, sonst gehen Protokollzeilen verloren, bis die Sockets existieren: Ein systemd-Drop-in für `nginx.service`
mit `Wants=` und `After=pacs-verwaltung.service` erledigt das (nicht getestet).

<a id="variant-tryit"></a>
### 5.4 Ein erster Blick durch einen SSH-Tunnel (`tryit`)

nginx lauscht auf `127.0.0.1:8080` des Servers, ohne TLS. Aus dem Netz erreicht es niemand, und es braucht kein Zertifikat. Zum
Testen nutzen, nicht für die tägliche Arbeit. Schritt 4.8 entfällt. Schritt 4.9: `LOGIN=basic; VIEWER=none; LISTENER=plain`. Schritt 4.10: `docker-compose.tryit.example.yml` kopieren. Schritt 4.11: `config.js`
ist nötig. Schritt 4.12: Konten wie bei `basic`. Weil nginx nur das Docker-Gateway als Client sieht, zeigt das Protokoll für
alle Benutzer dieselbe Adresse.

Vom eigenen PC aus den Tunnel öffnen. An beiden Enden denselben Port nutzen: Der Browser schreibt den Port in den Referer, und
eine Regel des Abschnitts für die dcm4chee-Oberfläche nennt `:8080`.

```bash
ssh -L 8080:127.0.0.1:8080 USER@SERVER
```

Dann auf dem eigenen PC `http://localhost:8080/admin/` aufrufen.

> **Prüfen**
>
> ```bash
> curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/admin/
> curl -s -u anna -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/admin/
> ```
>
> Erwartet auf dem Server: `401` ohne Anmeldung, dann `200` mit dem Konto `anna` (`curl` fragt nach dem Passwort). Die Startseite
> `/` antwortet `302` auf `/admin/`.

<a id="operate"></a>
## 6. Betrieb im Alltag

Diese Aufgaben kommen nach der Installation immer wieder: aktualisieren, eine geänderte Einstellung anwenden, das Zertifikat
erneuern, ein Passwort ändern, den Protokollschlüssel sichern und das Panel entfernen.

<a id="update"></a>
### 6.1 Auf eine neue Version aktualisieren

Die Programme liegen im git-Ordner `/opt/pacs-admin`. Die eigenen Einstellungen liegen außerhalb, `git pull` überschreibt sie
also nicht. Auch die eigenen Kopien der nginx-Dateien, der Compose-Datei und der Einstellungsdatei bleiben, wie sie sind. Man
vergleicht sie mit den neuen Beispielen (Tabelle unten). Zuerst die aktuelle Version notieren, denn diese Version ist der Weg zurück.

```bash
cd /opt/pacs-admin
git rev-parse --short HEAD
git pull
```

`git pull` listet die geänderten Dateien auf. Bricht es mit „Your local changes ... would be overwritten“ ab, wurde eine Datei im
Ordner bearbeitet. Diese Datei an einen anderen Ort kopieren, `git checkout -- DATEI` ausführen, erneut pullen und ab jetzt die
Kopie nutzen.

| Geänderter Pfad | Was zu tun ist |
|---|---|
| `web/admin/`, `server/dashboard-status.py`, `server/pacs-storage.sh`, `deploy/tools/` | Nichts. Der Container liest `web/admin/` direkt (im Browser Strg+F5 drücken). Die anderen Dateien lädt jeder Lauf neu. |
| `server/verwaltung-dienst.py`, `server/pacsdb.py`, `deploy/systemd/pacs-verwaltung.service` | Hat sich die Unit-Datei geändert, sie erneut kopieren ([4.6](#helper-service)) und `systemctl daemon-reload` ausführen. Dann den Dienst neu starten (unten). |
| `deploy/cron/pacs-dashboard` | Erneut kopieren ([4.7](#overview-cron)). |
| `server/firewall.py`, `deploy/systemd/pacs-firewall.service` | Nur mit dem Firewall-Modul. Die Unit erneut kopieren, wenn sie sich geändert hat. Den neuen Code ohne Lücke anwenden: `set -a; . /etc/default/pacs-admin; set +a; python3 /opt/pacs-admin/server/firewall.py start`. Nie `systemctl restart pacs-firewall` ausführen: Es öffnet für einen Moment alle Ports. |
| `deploy/nginx/` | Den Kopierblock aus [4.9](#nginx-files) mit `T=/opt/ohif/nginx.new` und den eigenen Werten erneut ausführen. Dann `diff -r /opt/ohif/nginx /opt/ohif/nginx.new`. Die eigenen Werte in `site.conf` erscheinen als Unterschiede, jeder andere Unterschied ist neu. Diese in `/opt/ohif/nginx` übernehmen und nginx neu laden ([6.2](#change-settings)). |
| `deploy/compose/` | `diff /opt/pacs-admin/deploy/compose/docker-compose.$RECIPE.example.yml /opt/ohif/docker-compose.yml` mit `RECIPE` wie in [4.10](#compose-file). Die Zeilen mit den eigenen Werten weichen ab, der Rest ist neu. Die neuen Zeilen ergänzen und `docker compose up -d` ausführen. |
| `deploy/pacs-admin.env.example`, `deploy/app-config.js.example` | Genauso mit den eigenen Kopien per `diff` vergleichen. Die neuen Zeilen ergänzen und wie in [6.2](#change-settings) anwenden. |

Die Compose-Dateien legen ihre Image-Versionen fest. Ein Tag wie `nginx:1.30` bekommt weiterhin Korrekturen. Um sie zu laden,
`cd /opt/ohif && docker compose pull && docker compose up -d` ausführen. Das erzeugt `ohif` neu und unterbricht die Benutzer für
ein paar Sekunden. Für eine neue Version des OHIF-Images oder von oauth2-proxy zuerst den Tag in der eigenen Compose-Datei ändern.

> **Warnung**
>
> Ein Neustart von `pacs-verwaltung` dauert ein paar Sekunden. In dieser Zeit kann nginx keine Protokollzeilen schreiben, sie gehen
> verloren ([Referenz](reference.de.md#audit-lost)), und das Admin-Panel antwortet `502`. Außerhalb der Arbeitszeit neu starten
> und nie, während der Platten-Assistent eine Einrichtung ausführt: Der Neustart bricht sie mittendrin ab. Startet der Dienst nach
> einem Update nicht, zurückgehen: `git reset --hard NUMMER` in `/opt/pacs-admin` (die oben notierte Nummer; es verwirft auch
> Änderungen in diesem Ordner), die Unit-Datei erneut kopieren, wenn sie sich geändert hat, dann
> `systemctl daemon-reload && systemctl restart pacs-verwaltung`.

```bash
systemctl restart pacs-verwaltung
```

> **Prüfen**
>
> ```bash
> systemctl is-active pacs-verwaltung
> journalctl -u pacs-verwaltung -n 3 --no-pager
> ```
>
> Erwartet: `active` und die Bereit-Zeile `pacs-verwaltung bereit: ...` wie in [4.6](#helper-service). Sonst siehe die
> [Fehlersuche](troubleshooting.de.md#no-sockets).

<a id="change-settings"></a>
### 6.2 Eine geänderte Einstellung anwenden

Nach der Bearbeitung einer Datei lässt ein einzelner Befehl die Änderung wirken. Der falsche Befehl tut nichts oder startet mehr
neu als nötig.

| Geändert | Ausführen |
|---|---|
| `/etc/default/pacs-admin` | `systemctl restart pacs-verwaltung` (Warnung in [6.1](#update)). Der Cron-Job liest die Datei bei jedem Lauf. Firewall-Werte brauchen `firewall.py start` wie in 6.1. |
| eine Datei in `/opt/ohif/nginx/` | `docker exec ohif nginx -t && docker exec ohif nginx -s reload` |
| `/opt/ohif/docker-compose.yml` | `cd /opt/ohif && docker compose up -d` |
| `/opt/ohif/config.js` oder `app-config.js` | `cd /opt/ohif && docker compose restart ohif`, dann Strg+F5 im Browser |
| `/opt/ohif/htpasswd/` | Nichts. nginx liest die Dateien bei jeder Anfrage. |
| `/opt/ohif/tls/server.crt` oder `server.key` | nginx neu laden wie in der zweiten Zeile ([6.3](#renew-certificate)). |

`nginx -t` testet die Dateien zuerst. Gibt es einen Fehler aus, stoppt das `&&` das Neuladen, und nginx behält seine alten
Dateien, ein Tippfehler richtet also keinen Schaden an. Mit nginx auf dem Host `nginx -t && systemctl reload nginx` nutzen.

<a id="renew-certificate"></a>
### 6.3 Das TLS-Zertifikat erneuern

Ein Zertifikat endet an einem festen Datum. Danach zeigt jeder Browser eine Warnung. Das Enddatum ansehen und 30 Tage davor eine
Erinnerung setzen:

```bash
openssl x509 -in /opt/ohif/tls/server.crt -noout -enddate
```

Beim Rezept `proxied` hält der eigene Proxy das Zertifikat: dort erneuern. Für die anderen Rezepte:

1. Das neue Zertifikat wie in [4.8](#tls-certificate) besorgen: die volle Kette, das Server-Zertifikat zuerst. Will die CA einen
   neuen Schlüssel, den neuen Schlüssel mit dem neuen Zertifikat nutzen.
2. Die alten Dateien behalten, bis die Prüfung besteht.

   ```bash
   cp -a /opt/ohif/tls /root/ohif-tls.$(date +%F)
   ```

3. Die neuen Dateien über `server.crt` und `server.key` in `/opt/ohif/tls/` kopieren. Besitzer und Modus noch einmal mit dem
   Block aus 4.8 setzen, der zum eigenen Image passt. Bei Let's Encrypt nach jeder Erneuerung die beiden `cp`-Befehle aus 4.8
   wiederholen. Ein Skript in `/etc/letsencrypt/renewal-hooks/deploy/` kann das und das Neuladen übernehmen (hier nicht getestet).
4. nginx neu laden. Es liest Zertifikat und Schlüssel neu, und offene Verbindungen bleiben bestehen.

   ```bash
   docker exec ohif nginx -t && docker exec ohif nginx -s reload
   ```

> **Prüfen**
>
> ```bash
> openssl x509 -in /opt/ohif/tls/server.crt -noout -enddate
> echo | openssl s_client -connect pacs.example.org:443 -servername pacs.example.org 2>/dev/null | openssl x509 -noout -enddate
> ```
>
> Erwartet: Beide Zeilen zeigen dasselbe neue Enddatum, zum Beispiel `notAfter=Jan 15 15:27:00 2029 GMT`. Zeigt die zweite Zeile
> das alte Datum, hat nginx nicht neu geladen (die Ausgabe von `nginx -t` lesen). Lässt sich der Schlüssel nicht lesen, siehe die
> [Fehlersuche](troubleshooting.de.md#tls-key-unreadable). Um zurückzugehen, `/root/ohif-tls.DATE` über `/opt/ohif/tls` kopieren
> und nginx neu laden.

<a id="rotate-secrets"></a>
### 6.4 Passwörter und Geheimnisse ändern

| Geheimnis | So ändern |
|---|---|
| Client-Geheimnis und Cookie-Geheimnis (`oauth2-proxy`) | [login.de.md](login.de.md#login-oauth2-operate). Alle melden sich neu an. |
| Passwort eines Kontos mit `basic` | `pacs-adduser.sh` mit demselben Namen und derselben Liste erneut ausführen: `admin` für einen Administrator, `all` für alle anderen (`all` nimmt einen Administrator aus der Admin-Liste). Das Skript fragt zweimal nach dem neuen Passwort und ersetzt die Zeile. Das neue Passwort gilt sofort. nginx auf dem Host braucht die zusätzlichen Optionen aus [5.3](#nginx-on-host). |
| TLS-Schlüssel | Einen neuen Schlüssel und ein neues Zertifikat zusammen erzeugen, dann beide Dateien ersetzen ([6.3](#renew-certificate)). |
| Protokollschlüssel | Das Repository hat kein Werkzeug, das die Datenbank neu verschlüsselt. Den Schlüssel behalten und sichern ([6.5](#backup-audit-key)). |

<a id="backup-audit-key"></a>
### 6.5 Den Protokollschlüssel und die Protokoll-Datenbank sichern

Ohne den Schlüssel kann niemand das Protokoll je wieder lesen, auch der Administrator nicht. Eine Kopie außerhalb dieses Servers
aufbewahren, im Passwort-Safe und getrennt von der Sicherung der Datenbank. Ein Schlüssel, der neben den Daten liegt, schützt
nichts.

```bash
cat /etc/pacs-protokoll.key
```

Die 64 Zeichen in den Safe kopieren. Dann beweisen, dass die Kopie stimmt. `read -rs` fragt nach dem Text, zeigt nichts an und hält
ihn aus der Shell-History heraus. Den Schlüssel aus dem Safe einfügen und Enter drücken:

```bash
read -rs KEYCOPY; echo
[ "$KEYCOPY" = "$(cat /etc/pacs-protokoll.key)" ] && echo "key copy matches"
```

Die Datenbank ist der Ordner `/var/lib/pacs-protokoll/`. Das Protokoll wird nie bereinigt und enthält Patienten-IDs
([Referenz](reference.de.md#audit-retention)). Den Ordner wie Patientendaten in die Serversicherung aufnehmen. Alle seine Dateien
zusammen aufbewahren: `protokoll.db` und, solange der Dienst läuft, auch `protokoll.db-wal` und `protokoll.db-shm`. Eine Kopie,
die während eines Schreibvorgangs entsteht, kann beschädigt sein. Deshalb jede Sicherung einmal mit dem aktuellen Schlüssel lesen:

```bash
PROTOKOLL_DB=/mnt/backup/pacs-protokoll/protokoll.db python3 /opt/pacs-admin/server/pacsdb.py protokoll zugriffe | wc -l
```

> **Prüfen**
>
> Erwartet: `key copy matches`, dann eine Zahl über 0 (die gespeicherten Zugriffe). Die Zeile
> `pacsdb.py: ... not a database` heißt: falscher Schlüssel oder beschädigte Kopie
> ([Fehlersuche](troubleshooting.de.md#audit-key-mismatch)). Eine `0` heißt: falscher Pfad (das Programm legt dort dann eine leere
> Datenbank an) oder noch niemand hat das Panel benutzt. Um auf einem neuen Server wiederherzustellen, den Schlüssel unter
> `/etc/pacs-protokoll.key` (Modus 600) und den Ordner unter `/var/lib/pacs-protokoll/` ablegen, bevor der Dienst startet.

<a id="uninstall"></a>
### 6.6 Das Admin-Panel entfernen

> **Warnung**
>
> Das entfernt die Anmeldung, die Sperren und das Protokoll vor dem Archiv. Der Viewer und das Admin-Panel funktionieren nicht
> mehr. Das dcm4chee-Archiv läuft weiter. In `/opt/ohif` wird nichts gelöscht. Um zurückzugehen,
> `cd /opt/ohif && docker compose up -d` ausführen und die Schritte [4.6](#helper-service) und [4.7](#overview-cron) wiederholen.

**1. Container.** Der Ordner `/opt/ohif`, die Images und die dcm4chee-Container bleiben.

```bash
cd /opt/ohif && docker compose down
```

**2. Hilfsdienst und Cron-Job.**

```bash
systemctl disable --now pacs-verwaltung
rm /etc/systemd/system/pacs-verwaltung.service /etc/cron.d/pacs-dashboard
systemctl daemon-reload
```

**3. Firewall-Modul, nur falls es im Einsatz ist.**

> **Warnung**
>
> Der erste Befehl entfernt den Sprung in die Kette `PACS-SPERRE`. Ab dann ist jeder Port, den Docker veröffentlicht, für alle
> Netzwerke offen, die den Server erreichen. Sicherstellen, dass eine andere Firewall diese Ports schützt. Um zurückzugehen,
> `pacs-firewall.service` erneut kopieren und `systemctl enable --now pacs-firewall` ausführen
> ([modules.de.md](modules.de.md#firewall)).

```bash
systemctl disable --now pacs-firewall
iptables -F PACS-SPERRE
iptables -X PACS-SPERRE
rm /etc/systemd/system/pacs-firewall.service
systemctl daemon-reload
```

**4. Änderungen im dcm4chee-Projekt, nur falls ein Modul im Einsatz war.** Der Platten-Assistent und die Firewall haben die
Compose-Datei von dcm4chee geändert. Diese Änderungen so zurücknehmen, wie [modules.de.md](modules.de.md#disk-assistant) und
[modules.de.md](modules.de.md#firewall) es beschreiben.

> **Warnung**
>
> Das erzeugt `arc` neu. Das Archiv ist unerreichbar, bis `arc` wieder läuft. In einem Wartungsfenster ausführen. Mit
> `docker compose ps` und `docker logs arc` im dcm4chee-Ordner prüfen. Um zurückzugehen, die Kopie der Compose-Datei zurückspielen,
> die vor der Änderung entstanden ist, und dort `docker compose up -d` ausführen.

> **Prüfen**
>
> ```bash
> docker ps -a --format '{{.Names}}' | grep -c '^ohif'
> ls /etc/systemd/system/pacs-verwaltung.service /etc/cron.d/pacs-dashboard
> ```
>
> Erwartet: `0`, dann zwei Zeilen `ls: cannot access '...': No such file or directory` (auf einem deutschen System
> `ls: Zugriff auf '...' nicht möglich: Datei oder Verzeichnis nicht gefunden`).

Das bleibt absichtlich bestehen, bis man es selbst löscht:

- `/var/lib/pacs-protokoll/` und `/etc/pacs-protokoll.key`: das Protokoll und sein Schlüssel. Das Protokoll enthält Patienten-IDs.
  Beides so lange aufbewahren, wie die eigenen Aufbewahrungsregeln es verlangen, und beides zusammen löschen.
- `/etc/default/pacs-admin`, `/opt/pacs-admin`, `/opt/ohif`, `/var/lib/pacs-admin/`, `/var/log/pacs-dashboard.log`.
- Mit den Modulen: `firewall.json` und der Ordner `firewall/` im dcm4chee-Ordner, die Datei, die `FW_DEFAULT_RULES` nennt,
  `/var/log/pacs-storage.log` und die Platten, die der Assistent eingerichtet hat. Diese Platten enthalten Studien und sind
  normale dcm4chee-Speicher mit Einträgen in `/etc/fstab`.
