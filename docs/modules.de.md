# Optionale Module

[English](modules.md) | Deutsch

Die Basisinstallation ([install.de.md](install.de.md)) lässt das dcm4chee-Archiv, wie es ist. Diese Seite beschreibt drei optionale Module.
Jedes Modul steht für sich. Man kann keines, eines oder alle nutzen.

Alle Befehle als root ausführen. Jeder Schritt endet mit einem **Prüfen**-Kasten, der zeigt, woran man erkennt, dass der Schritt gewirkt hat.
Ein **Warnung**-Kasten nennt, was kaputtgehen kann, wie lange es dauert und wie man zurückgeht.

- [1. Die drei Module](#modules-overview)
- [2. Die Compose-Datei von dcm4chee einmal ändern](#recreate-arc)
- [3. Platten-Assistent](#disk-assistant)
- [4. Firewall](#firewall)
- [5. Die Benutzeroberfläche von dcm4chee über die Eingangstür](#dcm4chee-ui)

<a id="modules-overview"></a>
## 1. Die drei Module

| Modul | Wer es braucht | Was es ändert | Ausfall |
|---|---|---|---|
| [Platten-Assistent](#disk-assistant) | Man fügt dem Archiv Platten hinzu und will das auf der Admin-Seite erledigen, ohne LDAP-Befehle zu tippen. | Die Compose-Datei von dcm4chee. Für jede neue Platte: ein Dateisystem, eine Zeile in `/etc/fstab` und ein [Speicher](glossary.de.md#storage) in der Konfiguration von dcm4chee. | `arc` startet einmal neu, wegen der Compose-Änderung. |
| [Firewall](#firewall) | Viele Netze erreichen den Server, und man will begrenzen, wer die Ports für DICOM, HL7 und die Verwaltung erreichen darf. | Die Compose-Datei von dcm4chee, Regeln im Paketfilter des Kernels, eine systemd-Unit. | `arc` startet einmal neu, wegen der Compose-Änderung. |
| [dcm4chee-Benutzeroberfläche](#dcm4chee-ui) | Admins nutzen die Weboberfläche von dcm4chee selbst und wollen sie über die Eingangstür erreichen. | Eine nginx-Datei. | Keiner. nginx lädt neu. |

Begriffe auf dieser Seite:

- **`arc`** ist der Container des dcm4chee-Archivs. `ldap` ist sein Konfigurationsserver. Siehe [LDAP](glossary.de.md#ldap).
- Die **Compose-Datei von dcm4chee** ist die `docker-compose.yml` des eigenen dcm4chee-Projekts. Diese Seite schreibt den Ordner als
  `/opt/dcm4chee-arc`. Den eigenen Ordner nutzen ([Compose-Projekt](glossary.de.md#compose-project)).
- Die **Eingangstür** ist der Webserver vor der Admin-Seite, dem Viewer und dcm4chee ([Glossar](glossary.de.md#front-door)).
- Der **Repository-Ordner** enthält die Dateien dieses Projekts auf dem Server. Diese Seite schreibt ihn als `/opt/pacs-admin`
  ([install.de.md](install.de.md#get-files)). Weicht der eigene Ordner ab, diesen nutzen.

Vor dem Start:

- Die Basisinstallation läuft. Die Admin-Seite öffnet sich, und der Reiter `Übersicht` zeigt seine Kacheln
  ([install.de.md](install.de.md#first-test)).
- Ein kurzer Ausfall des Archivs lässt sich einplanen. Der Platten-Assistent und die Firewall erzeugen `arc` beide neu.

<a id="recreate-arc"></a>
## 2. Die Compose-Datei von dcm4chee einmal ändern

Der Platten-Assistent und die Firewall brauchen beide eine Änderung in der Compose-Datei von dcm4chee. Eine geänderte Compose-Datei lässt
Docker den Container `arc` neu erzeugen. Docker stoppt den alten Container, entfernt ihn und startet einen neuen. Vom Stopp an ist das
Archiv nicht erreichbar, bis dcm4chee wieder gestartet ist. Das Skript des Platten-Assistenten schätzt 30 Sekunden. Ein großes Archiv
kann länger brauchen.

Alle Änderungen für die gewünschten Module in einer Sitzung machen und einmal neu erzeugen. Dann steht das Archiv einmal still, nicht
einmal pro Modul. Wer nur die dcm4chee-Benutzeroberfläche will ([Abschnitt 5](#dcm4chee-ui)), überspringt diesen Abschnitt.

<a id="edits-overview"></a>
### 2.1 Die drei Änderungen

| Änderung | Was sie in der Compose-Datei ändert | Gebraucht von |
|---|---|---|
| A | Fügt dem Dienst `arc` das Volume `/mnt/fs:/mnt/fs:rslave` hinzu. | Platten-Assistent |
| B | Schreibt die Ports des Dienstes `arc` mit der Adresse `0.0.0.0`. | Firewall |
| C | Fügt der Umgebung des Dienstes `ldap` das Passwort des LDAP-Root-Kontos hinzu. | Platten-Assistent, nur wenn die Prüfung in Schritt 6 `missing` ausgibt |

<a id="edits-steps"></a>
### 2.2 Schritt für Schritt

#### Schritt 1. Die Compose-Datei kopieren

Die Compose-Datei finden und eine Kopie anlegen. Die Kopie ist der Weg zurück.

```bash
docker inspect -f '{{index .Config.Labels "com.docker.compose.project.config_files"}}' arc
```

Beispielausgabe: `/opt/dcm4chee-arc/docker-compose.yml`. Nennt das Label mehrere Dateien, durch Kommas getrennt, alle kopieren und
jede Änderung in der Datei machen, die den Dienst definiert.

```bash
cp -a /opt/dcm4chee-arc/docker-compose.yml /root/dcm4chee-compose.before-modules.yml
```

> **Prüfen**
>
> ```bash
> ls -l /root/dcm4chee-compose.before-modules.yml
> ```
>
> Erwartet: eine Zeile, die die Datei mit der Größe der eigenen Compose-Datei zeigt. Fehlt die Datei, nicht weitermachen.

#### Schritt 2. Prüfen, ob das Projekt läuft

Von einem funktionierenden Zustand ausgehen. Dann kommt jedes Problem nach der Änderung von der Änderung.

```bash
cd /opt/dcm4chee-arc
docker compose ps
```

> **Prüfen**
>
> Erwartet: `arc`, `ldap` und `db` zeigen `Up` am Anfang der Spalte `STATUS`. Zeigt einer sie nicht, zuerst das beheben.
> Ein defektes Projekt bleibt nach der Änderung defekt.

#### Schritt 3. Mount-Propagation prüfen (nur Änderung A)

Das Volume der Änderung A nutzt das Flag `:rslave`. Damit erscheint eine Platte, die der Server später einhängt, auch in `arc`. Docker
akzeptiert das Flag nur, wenn der Server den Mount von `/` zum Teilen eingerichtet hat ([Mount-Propagation](glossary.de.md#mount-propagation)).
Das vor der Änderung prüfen. Der Ordner muss existieren, weil `findmnt` für einen nicht vorhandenen Ordner nichts ausgibt.

```bash
mkdir -p /mnt/fs
findmnt -T /mnt/fs -o TARGET,PROPAGATION
```

> **Prüfen**
>
> Erwartet: eine Kopfzeile und eine Zeile, deren zweite Spalte `shared` oder `slave` lautet. Beispiel:
>
> ```text
> TARGET PROPAGATION
> /      shared
> ```
>
> Die meisten Server mit systemd zeigen `shared`. Steht in der zweiten Spalte `private`, den Root-Mount auf geteilt stellen:
>
> ```bash
> mount --make-rshared /
> findmnt -T /mnt/fs -o TARGET,PROPAGATION
> ```

> **Warnung**
>
> `mount --make-rshared /` hält bis zum nächsten Neustart. Nach dem ersten Neustart des Servers den Befehl `findmnt` erneut ausführen.
> Steht dort wieder `private`, die Änderung auf dem Weg dauerhaft machen, den das System bietet (zum Beispiel eine kleine systemd-Unit, die
> den Befehl beim Start ausführt). Um jetzt zurückzugehen, `mount --make-rprivate /` ausführen. Schlägt der Befehl fehl, die Compose-Datei
> nicht ändern: Docker würde das Volume ablehnen, und `arc` bliebe gestoppt.

#### Schritt 4. Änderung A: das Volume hinzufügen (Platten-Assistent)

Die Compose-Datei im gewohnten Editor öffnen (zum Beispiel `nano /opt/dcm4chee-arc/docker-compose.yml`). Im Dienst `arc` eine Zeile zur
Liste `volumes:` hinzufügen. Die vorhandenen Zeilen bleiben.

```yaml
  arc:
    volumes:
      # the existing lines stay as they are
      - /mnt/fs:/mnt/fs:rslave
```

Ist `STORAGE_BASE` in `/etc/default/pacs-admin` auf einen anderen Ordner gesetzt, diesen Ordner auf beiden Seiten des Doppelpunkts
schreiben. Die Einrückung der anderen Zeilen beibehalten. YAML akzeptiert keine Tabulatoren.

> **Warnung**
>
> Sobald der Platten-Assistent seinen ersten Speicher angelegt hat, trägt dieses Volume die Bilder. Wird es wieder entfernt, kann dcm4chee
> die Bilder auf den neuen Platten nicht lesen, und neue Bilder landen im Container. Nur vor der ersten Platte zurückgehen
> ([2.3](#recreate-rollback)).

#### Schritt 5. Änderung B: die Ports mit der Adresse schreiben (Firewall)

Docker veröffentlicht einen Port ohne Adresse auf allen IPv4-Adressen und oft auch auf allen IPv6-Adressen. Die Firewall filtert nur
IPv4. Ein Port, der auch über IPv6 offen ist, kommt an der Firewall vorbei. Die Adresse `0.0.0.0` lässt Docker nur auf IPv4 veröffentlichen.
Die Admin-Seite zeigt das Badge `IPv6 nicht gefiltert` bei einem Port, den Docker noch über IPv6 veröffentlicht.

Im Dienst `arc` die ganze Liste `ports:` **ersetzen**. Keine zweite Liste anlegen und keine Zeilen neben die alten setzen. Für jeden Port
einen Eintrag behalten. Den Host-Port schreiben, den die Datei jetzt hat. Das ist die übliche Liste von dcm4chee:

```yaml
  arc:
    ports:
      - "0.0.0.0:8080:8080"
      - "0.0.0.0:8443:8443"
      - "0.0.0.0:9990:9990"
      - "0.0.0.0:9993:9993"
      - "0.0.0.0:11112:11112"
      - "0.0.0.0:2762:2762"
      - "0.0.0.0:2575:2575"
      - "0.0.0.0:12575:12575"
```

- Ein Port, den die Datei auf einen anderen Host-Port abbildet, behält diesen Host-Port. Zum Beispiel wird `"104:11112"` zu
  `"0.0.0.0:104:11112"`. Dann `FW_DICOM_PORTS` setzen ([4.10](#firewall-settings)).
- Ein Port, den die Datei schon an eine Adresse bindet, zum Beispiel `"127.0.0.1:8080:8080"`, bleibt, wie er ist.
- Ports anderer Container (LDAP `389`, Kibana `5601`, Portainer `8000` und `9443`) bekommen dasselbe Präfix in der Compose-Datei, die sie
  veröffentlicht.
- In diesem Schritt keine Ports schließen. Die Änderung betrifft nur, wie Docker sie veröffentlicht. Wer sie erreichen darf, entscheidet sich
  später, in [Abschnitt 4](#firewall).

> **Warnung**
>
> Clients, die diese Ports über eine IPv6-Adresse erreichen, verlieren nach dem Neuerzeugen die Verbindung. DICOM-Geräte und HL7-Sender
> nutzen normalerweise IPv4-Adressen. Das vor dem Neuerzeugen in [4.2](#firewall-inventory) prüfen. Um zurückzugehen, die Kopie aus
> Schritt 1 zurückspielen.

#### Schritt 6. Änderung C: den Assistenten am LDAP anmelden lassen (Platten-Assistent)

Der Assistent ändert die Konfiguration von dcm4chee im LDAP-Server. Er führt `ldapsearch` und `ldapmodify` im Container `ldap` aus und
liest das Root-Passwort aus der Umgebung dieses Containers. Der Host speichert kein Passwort. Der Container braucht `LDAP_ROOTPASS` (das
Passwort) oder `LDAP_ROOTPASS_FILE` (den Pfad einer Datei im Container, die es enthält). Dieser Befehl sagt, ob eines von beiden gesetzt
ist, und gibt es nicht aus:

```bash
docker exec ldap sh -c 'if [ -n "${LDAP_ROOTPASS:-}${LDAP_ROOTPASS_FILE:-}" ]; then echo set; else echo missing; fi'
```

Lautet die Antwort `set`, in diesem Schritt nichts tun. Lautet sie `missing`, die Zeile unten zum Dienst `ldap` hinzufügen, in dessen Liste
`environment:`. Das Root-Passwort schreiben, das der LDAP-Server jetzt hat. Der Assistent liest diesen Wert nur. Er ändert das Passwort des
Servers nicht.

```yaml
  ldap:
    environment:
      # the existing lines stay as they are
      LDAP_ROOTPASS: CHANGE-ME-ldap-root-password
```

Die Schreibweise der Nachbarzeilen übernehmen: Stehen dort `NAME=Wert` in einer Liste, `- LDAP_ROOTPASS=...` schreiben. Heißt der
LDAP-Container im Projekt anders als `ldap`, diesen Namen im Befehl oben nutzen und `LDAP_CONTAINER` setzen
([3.2](#disk-prepare)).

> **Warnung**
>
> Die Compose-Datei enthält jetzt das LDAP-Passwort im Klartext. Die Datei auf root beschränken (`chmod 600`) und nicht an einen Ort
> kopieren, den andere lesen. Eine Änderung in der Umgebung erzeugt auch `ldap` neu: dcm4chee kann seine Konfiguration einen Moment lang
> nicht lesen. Um zurückzugehen, die Kopie aus Schritt 1 zurückspielen.

#### Schritt 7. Die Datei prüfen und die Änderung vorab ansehen

```bash
cd /opt/dcm4chee-arc
docker compose config --quiet
```

> **Prüfen**
>
> Erwartet: keine Ausgabe. Eine Fehlermeldung nennt die Zeile des YAML-Problems. Den Fehler beheben und den Befehl erneut ausführen.
> Dann die Datei noch einmal öffnen und die eigenen Änderungen lesen: Nur die Zeilen von A, B und C weichen von der Kopie ab.
>
> ```bash
> diff /root/dcm4chee-compose.before-modules.yml /opt/dcm4chee-arc/docker-compose.yml
> ```

Neuere Versionen von Docker Compose haben die Option `--dry-run`. Mit dieser Option listet `docker compose up -d --dry-run` auf, was Docker
neu erzeugen würde, und erzeugt nichts neu. Erwartet: eine Zeile mit `Recreate` für `arc`, und für `ldap` nur, wenn Änderung C gemacht wurde.

#### Schritt 8. Einmal neu erzeugen

> **Warnung**
>
> Das stoppt `arc` und startet einen neuen Container. Das Archiv ist unerreichbar, bis dcm4chee wieder gestartet ist, 30 Sekunden oder
> länger. DICOM-Geräte, die in dieser Zeit senden, bekommen einen Fehler und versuchen es später erneut oder nicht, je nach Gerät. Das
> in einem Wartungsfenster tun. Um zurückzugehen, die Kopie aus Schritt 1 zurückspielen und `docker compose up -d` erneut ausführen
> ([2.3](#recreate-rollback)).

Keinen Dienst nennen. Dann erzeugt Docker jeden Dienst mit geänderter Konfiguration in einem Lauf neu.

```bash
cd /opt/dcm4chee-arc
docker compose up -d
```

Docker gibt für jeden Container und jede Aktion eine Zeile aus: ` Container arc  Recreate`, dann `Recreated`, `Starting`, `Started`.
Ein Container ohne Änderung zeigt `Running`.

> **Prüfen**
>
> Warten, bis dcm4chee gestartet ist. Das Log eines neu erzeugten Containers beginnt leer, darum beweist diese Zeile den neuen Start:
>
> ```bash
> docker logs arc 2>&1 | grep WFLYSRV0025
> ```
>
> Erwartet: eine Zeile mit `WFLYSRV0025`, die mit `started in` und einer Zeit endet. Gibt es noch keine Zeile, warten und den Befehl
> erneut ausführen. Nach 5 Minuten das Ende des Logs mit `docker logs arc 2>&1 | tail -n 50` lesen.
>
> Wurde Änderung A gemacht, prüfen, dass das Volume mit dem richtigen Flag angekommen ist:
>
> ```bash
> docker inspect -f '{{range .Mounts}}{{.Destination}} {{.Propagation}}{{"\n"}}{{end}}' arc | grep '^/mnt/fs '
> ```
>
> Erwartet: `/mnt/fs rslave`.
>
> Wurde Änderung B gemacht, die Ports prüfen:
>
> ```bash
> docker ps --format 'table {{.Names}}\t{{.Ports}}'
> ```
>
> Erwartet: Für `arc` erscheint jeder Port als `0.0.0.0:PORT->PORT/tcp` ohne zweiten Eintrag `[::]:PORT->PORT/tcp`.

Bricht `docker compose up -d` mit `it is not a shared or slave mount` ab, hat Docker das alte `arc` schon entfernt. Es hat das neue
angelegt und konnte es nicht starten. `arc` ist aus. Siehe die [Fehlersuche](troubleshooting.de.md#arc-rslave-refused).

<a id="recreate-rollback"></a>
### 2.3 Zurückgehen

Die Kopie zurückspielen und noch einmal neu erzeugen. Das macht alle Änderungen auf einmal rückgängig.

```bash
cp -a /root/dcm4chee-compose.before-modules.yml /opt/dcm4chee-arc/docker-compose.yml
cd /opt/dcm4chee-arc
docker compose up -d
```

> **Warnung**
>
> Das erzeugt `arc` noch einmal neu: ein weiterer Ausfall, so lang wie in Schritt 8. Zwei Ausnahmen:
>
> - Hat der Platten-Assistent einen Speicher angelegt, Änderung A behalten. Ohne das Volume kann dcm4chee die Bilder auf den neuen Platten
>   nicht lesen. Die Datei zurückspielen, die Volume-Zeile wieder hinzufügen und `docker compose up -d` ausführen.
> - Ist die Firewall an, wendet sie ihre Regeln innerhalb von 5 Minuten nach der Änderung der Ports erneut an. Das ist normal.

> **Prüfen**
>
> ```bash
> cd /opt/dcm4chee-arc && docker compose ps
> docker logs arc 2>&1 | grep WFLYSRV0025
> ```
>
> Erwartet: alle Dienste `Up` und eine Zeile `WFLYSRV0025`, wie in Schritt 8.

<a id="disk-assistant"></a>
## 3. Platten-Assistent

**Wer es braucht.** Dem Archiv kommen mit der Zeit Platten hinzu, zum Beispiel eine neue virtuelle Platte im Hypervisor. Jede neue Platte
soll sich über die Admin-Seite einrichten lassen. Ohne den Assistenten legt man das Dateisystem, den Mount, die Zeile in `/etc/fstab` und
den [Speicher](glossary.de.md#storage) in der LDAP-Konfiguration von dcm4chee von Hand an.

**Was es ändert.** Für jede neue Platte formatiert der Assistent die Platte mit ext4, hängt sie unter `/mnt/fs` ein und fügt `/etc/fstab`
eine Zeile hinzu. Er legt in der Konfiguration von dcm4chee einen Speicher an und setzt ihn ans Ende der
[Schreibliste](glossary.de.md#write-list). Dann weist er `arc` an, die Konfiguration neu zu lesen. Er startet `arc` nicht neu und
verschiebt kein Bild.

> **Warnung**
>
> Formatieren zerstört alle Daten auf einer Platte und lässt sich nicht rückgängig machen. Der Assistent formatiert nur eine leere Platte:
> keine Partition, kein Dateisystem, keine Signatur, nicht eingehängt, nicht in `/etc/fstab`, und ein erstes MiB, das nur Nullen
> enthält. Er prüft das direkt vor dem Formatieren noch einmal. Er kann nicht wissen, welche leere Platte für einen anderen Zweck gedacht
> ist. Vor dem Bestätigen die Größe und das Modell im Bestätigungstext lesen.
>
> Der Assistent braucht vorher die Änderung aus [Abschnitt 2](#recreate-arc) (Änderung A und, wenn die Prüfung es verlangt, Änderung C).
> Diese Änderung stoppt `arc` für 30 Sekunden oder länger. Um vor der ersten Platte zurückzugehen, gilt [2.3](#recreate-rollback). Nach der
> ersten Platte gilt [3.6](#disk-rollback).

<a id="disk-what"></a>
### 3.1 Wie er arbeitet

- **Namen.** Jeder Speicher ist eine Platte. Sein Name besteht aus dem Präfix `PACS-Data` und einer zweistelligen Zahl: `PACS-Data01`,
  `PACS-Data02`. Die Platte ist unter `/mnt/fs/PACS-Data01` eingehängt. Derselbe Name ist das ext4-Label, und `/etc/fstab` hängt die
  Platte über dieses Label ein. Ein Gerätename wie `/dev/sdc` kann sich nach einem Neustart ändern. Das Label nicht. Der Assistent
  nimmt die höchste Nummer, die er in den Speichern von LDAP, in den Ordnern von `/mnt/fs` und in den `LABEL=`-Einträgen von
  `/etc/fstab` findet, und addiert eins.
- **Vorlage.** Der neue Speicher kopiert die Einstellungen eines vorhandenen Speichers: des ersten Speichers der Schreibliste oder, wenn
  die Liste leer ist, des Speichers mit der höchsten Nummer, die mit dem Präfix beginnt. Er kopiert alle Einstellungen, zum Beispiel die
  Schwelle (den freien Platz, der bleiben muss), aber nicht den Namen, den Pfad und die Markierung „voll“. Findet er keine Vorlage,
  bricht er mit `kein Vorlage-Storage gefunden` ab.
- **Schreibliste.** dcm4chee schreibt neue Bilder in den ersten Speicher der Liste, der nicht als voll markiert ist. Fällt der freie Platz
  dieses Speichers unter seine Schwelle, markiert dcm4chee ihn als voll und macht mit dem nächsten Speicher weiter. dcm4chee entfernt
  die Markierung nie selbst. Der Assistent hängt einen neuen Speicher ans Ende der Liste. Er bekommt Bilder, wenn die Speicher vor ihm
  voll sind. Die Seite zeigt die Reihenfolge ([3.5](#disk-operate)).
- **Erst der Plan.** Ein Befehl, der etwas ändert, gibt nur einen Plan aus, solange sein letztes Wort nicht `ja` lautet. Zum Beispiel zeigt
  `add /dev/sdc` den Plan, und `add /dev/sdc ja` erledigt die Arbeit. Die Schaltflächen der Seite übergeben immer `ja`, nachdem man
  bestätigt hat.
- **Log und Sperre.** Jeder Aufruf gibt auf dem Bildschirm aus. Jeder Aufruf außer `kandidaten` hängt außerdem an
  `/var/log/pacs-storage.log` (`STORAGE_LOG`) an. Eine Zeile wie `=== 2026-10-14 10:15:03 pacs-storage.sh add /dev/sdc ja` eröffnet
  jeden Aufruf im Log. Die ersten Prüfungen (die Einstellungsdatei, das Präfix, root, die Sperre) laufen, bevor das Logging beginnt,
  darum stehen ihre `HALT:`-Zeilen auf dem Bildschirm und nicht im Log. Es läuft immer nur ein Aufruf. Ein zweiter Aufruf wartet
  30 Sekunden und gibt dann `laeuft schon` aus. Das Skript läuft nur als root.
- **Schutzdatei.** Unter jedem Mountpunkt legt der Assistent die Datei `NO_MOUNT` ab. Man sieht sie nur, solange dort keine Platte
  eingehängt ist, darum fällt eine fehlende Platte leicht auf.

Das Skript `pacs-storage.sh` im Ordner `server` des Repositorys hat diese Befehle:

| Befehl | Was er tut |
|---|---|
| `scan` | Lässt den Kernel nach neuen und vergrößerten Platten suchen. Listet die Speicher, die leeren Platten, die vergrößerten Platten und die Mountpunkte ohne `NO_MOUNT` auf. Ändert nichts. |
| `add /dev/sdX [ja]` | Formatiert die leere Platte, hängt sie ein, schreibt die Zeile in `/etc/fstab` und führt dann `activate` aus. |
| `auto [ja]` | Führt `scan` aus, dann `add` für die eine leere Platte. Bei keiner oder mehreren leeren Platten sagt es nur das. |
| `activate ID [ja]` | Nimmt eine eingehängte Platte ins Archiv auf, ans Ende der Schreibliste. `add` ruft es auf. Allein ausführen, nachdem die Compose-Datei korrigiert ist ([3.4](#disk-first)). |
| `freigeben ID [ja]` | Entfernt die Markierung „voll“. Die Schaltfläche der Seite heißt `Markierung entfernen`. Die Platte braucht `STORAGE_FREE_GB` frei. |
| `anhaengen ID [ja]` | Setzt einen Speicher ans Ende der Schreibliste und entfernt seine Markierung „voll“. Die Schaltfläche der Seite heißt `In Schreibliste aufnehmen`. Die Platte braucht `STORAGE_FREE_GB` frei. |
| `abhaengen ID [ja]` | Nimmt einen Speicher aus der Schreibliste. Die Bilder bleiben lesbar. Die Schaltfläche der Seite heißt `Aus Schreibliste nehmen`. |
| `grow /dev/sdX [ja]` | Vergrößert das Dateisystem, nachdem die Platte vergrößert wurde. Es funktioniert, während die Platte in Benutzung ist. Nur auf der Kommandozeile. |
| `nomount [ja]` | Legt die Datei `NO_MOUNT` unter jedem Mountpunkt an, dem sie fehlt. |
| `kandidaten` | Dieselben Angaben wie `scan` in einer Form, die Programme lesen. `dashboard-status.py` nutzt es. |

<a id="disk-prepare"></a>
### 3.2 Vorbereiten

#### Schritt 1. Die Einstellungen prüfen

Der Assistent arbeitet mit den Standardwerten einer üblichen dcm4chee-Installation. Einen Wert nur ändern, wenn die eigene Installation
abweicht. Alle Einstellungen sind Zeilen in `/etc/default/pacs-admin` ([Regeln für diese Datei](reference.de.md#env-file-rules)). Jeder
Wert ist eine ganze Zahl ohne führende Null oder ein Text ohne Leerzeichen. `STORAGE_MIN_GB`, `STORAGE_FREE_GB` und `STORAGE_WARN_GB`
nehmen höchstens 6 Ziffern. Ein Wert wie `50GB` oder `08` stoppt das Programm, das ihn liest. Die Meldung geht weiter mit
`ist keine ganze Zahl ohne fuehrende Null mit hoechstens 6 Stellen`.

Das Skript führt `bash -n` auf die Datei aus, bevor es sie liest. Ein Syntaxfehler stoppt das Skript mit
`HALT: /etc/default/pacs-admin hat einen Syntaxfehler (Meldung davor)`. Die Meldung von `bash` steht in der Zeile darüber. Die Bedeutung
jeder Meldung steht in der [Fehlersuche](troubleshooting.de.md#disk-halt).

| Einstellung | Standard | Bedeutung |
|---|---|---|
| `STORAGE_BASE` | `/mnt/fs` | Ordner, unter dem die Platten eingehängt werden. Auf beiden Seiten des Volumes aus Änderung A denselben Ordner nutzen. |
| `STORAGE_PREFIX` | `PACS-Data` | Name einer Platte ohne die Nummer. Er beginnt mit einem Buchstaben und hat bis zu 14 Buchstaben, Ziffern, `-` oder `_`. |
| `STORAGE_OWNER` | `1023:1023` | Benutzer und Gruppe (uid:gid), denen eine neue Platte gehört. Das ist das Konto, unter dem WildFly im Image dcm4chee-arc läuft. |
| `STORAGE_MIN_GB` | `100` | Kleinste Platte, die der Assistent anbietet, in GiB. |
| `STORAGE_FREE_GB` | `50` | Freier Platz in GB, den eine Platte braucht, bevor die Schaltflächen `Markierung entfernen` und `In Schreibliste aufnehmen` funktionieren. |
| `STORAGE_WARN_GB` | `300` | Die Übersicht verlangt eine neue Platte, wenn der Platz bis zu den Schwellen unter diesem Wert liegt, in GB. |
| `STORAGE_LOG` | `/var/log/pacs-storage.log` | Logdatei des Skripts. |
| `ARC_CONTAINER` | `arc` | Name des Archiv-Containers. |
| `LDAP_CONTAINER` | `ldap` | Name des LDAP-Containers. |
| `ARC_AET` | `DCM4CHEE` | [AE-Titel](glossary.de.md#ae-title) des Archivs. |
| `ARC_DEVICE` | `dcm4chee-arc` | Name des Archiv-Geräts in LDAP. |
| `ARC_URL` | `http://127.0.0.1:8080` | REST-Adresse des Archivs, aufgerufen vom Server selbst. Ändern, wenn Port 8080 auf einer anderen Adresse veröffentlicht wird. |
| `LDAP_BASE_DN` | `dc=dcm4che,dc=org` | Basis der dcm4chee-Konfiguration in LDAP. |

Alle Einstellungen und ihre Wirkung stehen in [reference.de.md](reference.de.md#config-variables). Nach einer Änderung
`systemctl restart pacs-verwaltung` ausführen, aber nicht, während eine Platte eingerichtet wird ([3.5](#disk-operate)). Das Skript liest
die Datei bei jedem Start. Der Cron-Job liest sie bei seinem nächsten Lauf.

> **Prüfen**
>
> ```bash
> grep -E '^(STORAGE_|ARC_|LDAP_)' /etc/default/pacs-admin
> ```
>
> Erwartet: die Zeilen, die geändert wurden, oder keine Ausgabe, wenn alle Standardwerte gelten.

#### Schritt 2. Prüfen, ob `arc` den Ordner sieht

Dieser Schritt beweist, dass Änderung A funktioniert.

```bash
docker exec arc ls -ld /mnt/fs
```

> **Prüfen**
>
> Erwartet: eine Zeile, die mit `d` beginnt und mit `/mnt/fs` endet. Lautet die Antwort `No such file or directory`, fehlt das Volume:
> zurück zu [Schritt 4 von Abschnitt 2](#edits-steps).

#### Schritt 3. Den Besitzer der Dateien prüfen

```bash
docker exec arc id wildfly
```

> **Prüfen**
>
> Erwartet: eine Zeile mit den Nummern des Kontos, zum Beispiel `uid=1023(wildfly) gid=1023(wildfly) groups=1023(wildfly)`.
> Weichen die Nummern ab, `STORAGE_OWNER=UID:GID` mit den eigenen Nummern setzen. Meldet der Befehl, dass der Benutzer nicht existiert,
> das Konto finden, unter dem WildFly im eigenen Image läuft, und dessen Nummern nutzen.

<a id="disk-scan"></a>
### 3.3 Den Server mit `scan` ansehen

`scan` ist der sichere erste Aufruf. Er ändert keine Platte und keine Konfiguration. Bevor er etwas auflistet, prüft er, dass Docker
existiert und dass er den AE des Archivs aus dem LDAP-Server lesen kann. Das beweist Änderung C und die Einstellungen `ARC_AET`,
`ARC_DEVICE`, `LDAP_BASE_DN` und `LDAP_CONTAINER`.

```bash
bash /opt/pacs-admin/server/pacs-storage.sh scan
```

> **Prüfen**
>
> Erwartet auf einem Server, der noch keine PACS-Platte hat. Der Text unter `--- Storages` ist vor der ersten Platte normal:
>
> ```text
> === 2026-10-14 10:15:03 pacs-storage.sh scan
> --- Storages
>   keine Storages unter /mnt/fs gefunden: gesucht werden eingehaengte Platten mit den Namen PACS-Data01, PACS-Data02 ... Das ist vor der ersten Platte normal (docs/modules.de.md#disk-assistant).
> --- Leere Platten (add)
>   keine
> --- Vergroesserte Platten (grow)
>   keine
> --- NO_MOUNT fehlt unter dem Mountpunkt (nomount)
>   keine
> ```
>
> Existiert der Ordner `/mnt/fs` nicht, sagt eine weitere Zeile `/mnt/fs gibt es nicht: mkdir -p /mnt/fs`. Eine Zeile, die mit
> `  HALT:` beginnt, heißt, dass der Assistent nicht arbeiten kann. Den Text dieser Zeile in der
> [Fehlersuche](troubleshooting.de.md#disk-halt) nachlesen.

Die vier Abschnitte:

| Abschnitt | Bedeutung |
|---|---|
| `--- Storages` | Die Platten, die unter `/mnt/fs` mit dem Präfix eingehängt sind. Jede Zeile zeigt den Namen, das Gerät, die Größe, den freien Platz und das Wort `Schreibliste` für eine Platte in der Schreibliste. |
| `--- Leere Platten (add)` | Platten, die der Assistent formatieren darf. Jede Zeile zeigt das Gerät, die Größe und das Modell. |
| `--- Vergroesserte Platten (grow)` | Platten, die größer sind als das Dateisystem darauf. Siehe `grow` in [3.5](#disk-operate). |
| `--- NO_MOUNT fehlt unter dem Mountpunkt (nomount)` | Mountpunkte ohne die Schutzdatei. `nomount ja` legt sie an. |

Beispiel für den ersten Abschnitt auf einem Server mit zwei Platten (die Zahlen sind ein Beispiel):

```text
--- Storages
  PACS-Data01  /dev/sdb    2048 GiB gesamt   312 GiB frei   Schreibliste
  PACS-Data02  /dev/sdc    2048 GiB gesamt  1980 GiB frei
```

<a id="disk-first"></a>
### 3.4 Eine Platte einrichten

Zuerst die Schritte aus [Abschnitt 2](#recreate-arc) für Änderung A (und bei Bedarf Änderung C) ausführen. Dann muss `scan` ohne `HALT`
laufen.

#### Schritt 1. Dem Server eine leere Platte geben

Bei einer virtuellen Maschine im Hypervisor eine neue virtuelle Platte hinzufügen. Bei einem physischen Server die Platte anschließen.
Keine Partition anlegen, die Platte nicht formatieren und nicht einhängen. Die Platte braucht mindestens `STORAGE_MIN_GB` GiB
(standardmäßig 100 GiB).

#### Schritt 2. Die Seite die Platte finden lassen

Die Admin-Seite und den Reiter `Übersicht` öffnen. Die Kachel `Neue Festplatte` sagt `Keine leere Platte gefunden.`, bis der Server die
Platte gefunden hat. Das Status-Skript sucht alle 5 Minuten. Um sofort zu suchen, `Jetzt suchen` wählen.

> **Prüfen**
>
> Erwartet: Die Kachel wechselt zu `Neue Festplatte erkannt` mit dem Text `leer, bereit zum Einrichten`. Darin stehen das Gerät, die Größe und
> das Modell der Platte und die Schaltfläche `Als PACS-Data01 einrichten …`. Wechselt die Kachel nicht, siehe die
> [Fehlersuche](troubleshooting.de.md#disk-not-offered). Zeigt `Jetzt suchen` eine rote Meldung, die mit `(HTTP 500)` endet, ist das
> Status-Skript fehlgeschlagen. Die Meldung enthält die letzte Zeile seines Fehlers, zum Beispiel eine ungültige Zahl in
> `/etc/default/pacs-admin`.

#### Schritt 3. Bestätigen

> **Warnung**
>
> Das formatiert die Platte. Das Gerät, die Größe und das Modell mit der Platte vergleichen, die dem Server gegeben wurde. Während der
> Einrichtung `pacs-verwaltung` nicht neu starten und den Server nicht neu booten. Eine Einrichtung, die mittendrin stoppt, kann eine
> formatierte Platte hinterlassen, die das Archiv noch nicht kennt. Die [Fehlersuche](troubleshooting.de.md#disk-half-done) zeigt, wie man
> sie abschließt oder rückgängig macht.

`Als PACS-Data01 einrichten …` wählen. Ein Fenster nennt die Platte und listet auf, was geschieht:

1. Ein Dateisystem ext4 mit dem Namen der Platte, ohne die Reserve für root.
2. Die Platte wird eingehängt, und `/etc/fstab` bekommt eine Zeile.
3. Der Speicher erscheint im Archiv, mit den Einstellungen der Vorlage. Das Fenster nennt die Vorlage und ihre Schwelle.
4. Der Speicher kommt ans Ende der Schreibliste. Neue Bilder kommen zu ihm, wenn die Platten vor ihm voll sind.

Zeigt das Fenster `Schwelle ?`, hat der Vorlage-Speicher keine Schwelle, und der neue Speicher hat auch keine. Vor dem Weitermachen in der
dcm4chee-Benutzeroberfläche eine Schwelle am Vorlage-Speicher setzen.

`Formatieren und einrichten` wählen. `Abbrechen` schließt das Fenster und ändert nichts. Die Kachel `Neue Festplatte PACS-Data01` zeigt
jetzt, während das Skript läuft, die Schritte `Platte prüfen`, `Formatieren und einhängen`, `Archiv sieht die Platte`,
`Im Archiv eintragen` und `Fertig`.

#### Schritt 4. Das Ergebnis prüfen

> **Prüfen**
>
> Erwartet: Die Kachel sagt `PACS-Data01 ist eingerichtet.` und `eingerichtet` mit der Uhrzeit. Die Kachel `Speicher` zeigt einen neuen
> Balken. Sein Name ist `01`, weil die Kachel das Präfix weglässt. Dann den Server prüfen:
>
> ```bash
> findmnt /mnt/fs/PACS-Data01
> grep PACS-Data01 /etc/fstab
> tail -n 12 /var/log/pacs-storage.log
> ```
>
> Erwartet: `findmnt` zeigt den Mount mit dem Dateisystem `ext4`. `grep` zeigt die Zeile
> `LABEL=PACS-Data01 /mnt/fs/PACS-Data01 ext4 nosuid,nodev,nofail 0 0`. Das Ende des Logs schließt mit einer Zeile `fertig.`

Zeigt die Kachel `Abgebrochen`, nennt sie die erste `HALT`-Zeile. Für den vollen Text `Ausgabe des Skripts` öffnen. Die Bedeutung
jeder `HALT`-Zeile steht in der [Fehlersuche](troubleshooting.de.md#disk-halt).

Endet eine rote Meldung unten rechts mit `(HTTP 504)`, hat ein Skript nicht innerhalb von 300 Sekunden geendet, und der Hilfsdienst hat es
gestoppt. Nach `Formatieren und einrichten` heißt das: Die Prüfung vor dem Start ist abgelaufen, und es wurde keine Einrichtung
gestartet. Vor einem neuen Versuch die Platten auf dem Server und `/var/log/pacs-storage.log` ansehen
([Fehlersuche](troubleshooting.de.md#disk-half-done)).

Sagt die Kachel `eingerichtet` mit der Uhrzeit und `Archiv nicht neu geladen`, und ist ein gelber Kasten mit demselben Titel offen, ist die
Einrichtung in der LDAP-Konfiguration vollständig, aber `arc` hat sie nicht neu geladen. `arc` behält die alte Konfiguration, bis es neu
lädt. Der Kasten wiederholt den Text nach `ACHTUNG:` in der Ausgabe des Skripts. Die Schritte zum Neuladen stehen in der
[Fehlersuche](troubleshooting.de.md#disk-half-done).

**Dasselbe auf der Kommandozeile.** Das nutzen, um zuerst den Plan zu sehen, oder wenn die Seite nicht verfügbar ist.

```bash
bash /opt/pacs-admin/server/pacs-storage.sh scan
bash /opt/pacs-admin/server/pacs-storage.sh add /dev/sdc
```

Der zweite Befehl gibt nur den Plan aus. So sieht der Plan aus. Die Namen hängen vom Archiv ab:

```text
--- Plan
  Platte:  /dev/sdc, 1024 GiB, MODEL, leer
  Format:  ext4, Label PACS-Data02, ohne root-Reserve (-m 0)
  Mount:   /mnt/fs/PACS-Data02, fstab: LABEL=PACS-Data02 /mnt/fs/PACS-Data02 ext4 nosuid,nodev,nofail 0 0
  Archiv:  Storage PACS-Data02 wie PACS-Data01, Schreibliste DCM4CHEE danach: PACS-Data01 PACS-Data02
Trockenlauf. Ausfuehren: /opt/pacs-admin/server/pacs-storage.sh add /dev/sdc ja
```

Bei einem neuen Archiv ist die Vorlage der Speicher, den dcm4chee selbst angelegt hat. Sein Name hängt von der Installation ab, darum kann
die Zeile `Archiv:` lauten `wie fs1, Schreibliste DCM4CHEE danach: fs1 PACS-Data01`. Die neue Platte bekommt dann erst Bilder, wenn `fs1`
voll ist ([3.5](#disk-operate) zeigt, wie man das ändert).

Zum Formatieren und Einrichten denselben Befehl mit `ja` am Ende ausführen. So sieht die Ausgabe aus. Das Beispiel ist aus dem Text des Skripts
abgeleitet und wurde nicht an einer echten Platte aufgezeichnet:

```text
--- Platte
  ok    ext4 PACS-Data02 auf /dev/sdc
  ok    gemountet /mnt/fs/PACS-Data02, fstab ergaenzt (vorher /etc/fstab.bak-20261014-101503), NO_MOUNT darunter
--- Sichtbar im Container arc?
  ok    Container sieht die Platte und kann schreiben
--- Archiv
  ok    Storage PACS-Data02 angelegt: ...
  ok    Schreibliste DCM4CHEE: PACS-Data01 PACS-Data02 / Metadaten: PACS-Data01 PACS-Data02
  ok    Archiv-Konfiguration neu geladen
  ok    Archiv kennt PACS-Data02
fertig. PACS-Data02 wird beschrieben, sobald PACS-Data01 die Schwelle erreicht.
```

Stoppt das Skript im Schritt `Sichtbar im Container arc?` mit `HALT: arc sieht /mnt/fs/PACS-Data02 nicht`, ist die Platte formatiert und
eingehängt, aber das Archiv kennt sie nicht. `arc` hat kein Volume `/mnt/fs:/mnt/fs:rslave`, oder es wurde nach der Änderung nicht neu
erzeugt. [Abschnitt 2](#recreate-arc) ausführen (Änderung A und das Neuerzeugen), dann `activate` mit dem Namen aus der Meldung
ausführen:

```bash
bash /opt/pacs-admin/server/pacs-storage.sh activate PACS-Data02 ja
```

<a id="disk-operate"></a>
### 3.5 Tägliche Arbeit

Die Kachel `Speicher` des Reiters `Übersicht` zeigt einen Balken für jede Platte in `/mnt/fs`. Die Zahlen kommen aus `status.json`, die
der Cron-Job alle 5 Minuten erneuert und jede Plattenaktion sofort erneuert.

| Hinweis am Balken | Bedeutung |
|---|---|
| `neue Bilder jetzt` | Neue Bilder gehen jetzt auf diese Platte. |
| `neue Bilder als 2.` | Neue Bilder gehen auf diese Platte, wenn die Platten davor voll sind. Die Zahl ist der Platz in der Schreibliste. |
| `als voll markiert` | dcm4chee hat die Platte als voll markiert. Es überspringt die Platte. |
| `nicht eingehängt, bitte prüfen` | Der Ordner existiert, aber dort ist keine Platte eingehängt. Siehe die [Fehlersuche](troubleshooting.de.md#disk-not-mounted). |

Die Zeile unter den Balken sagt, ob der Platz reicht:

| Zeile | Bedeutung und Maßnahme |
|---|---|
| `Neue Bilder gehen auf 01, danach 02. Platz bis zur Schwelle: …` | Die Reihenfolge der Schreibliste (Beispiel) und der Platz bis zu den Schwellen. Keine Maßnahme. |
| Dieselbe Zeile, endend mit `Bald dem Server eine neue Platte geben.` | Der Platz liegt unter `STORAGE_WARN_GB`. Eine Platte hinzufügen ([3.4](#disk-first)). |
| `Keine Platte nimmt neue Bilder an. Sofort dem Server eine neue Platte geben.` | Keine Platte der Liste ist für neue Bilder frei. Eine Platte hinzufügen oder Platz schaffen und die Schaltflächen unten nutzen. |
| `Schreibliste nicht lesbar (LDAP-Container und pacs-storage.sh kandidaten prüfen). Welche Platte neue Bilder bekommt, ist gerade unbekannt.` | Das Status-Skript konnte die Schreibliste nicht lesen. `scan` ausführen und die `HALT`-Zeile lesen ([Fehlersuche](troubleshooting.de.md#disk-halt)). |
| `Keine Daten zu den Platten (status.json nennt keine; STORAGE_BASE und STORAGE_PREFIX prüfen).` | Kein Ordner `STORAGE_BASE/STORAGE_PREFIX` plus eine Zahl. Vor der ersten Platte normal. Sonst beide Einstellungen prüfen. |
| `Kein Status vorhanden (dashboard-status.py läuft per cron alle 5 Minuten).` | Keine Status-Datei. Siehe die [Fehlersuche](troubleshooting.de.md#cron-not-running). |

Drei Schaltflächen ändern die Schreibliste. Jede fragt zuerst um eine Bestätigung und schreibt eine Zeile ins Protokoll:

| Schaltfläche | Sichtbar, wenn | Was sie tut |
|---|---|---|
| `Markierung entfernen` | Die Platte ist als voll markiert und hat `STORAGE_FREE_GB` frei. | Entfernt die Markierung „voll“. Ist die Platte in der Schreibliste, bekommt sie neue Bilder, wenn die Platten davor voll sind. Findet dcm4chee die Platte wieder voll, markiert es sie erneut. |
| `In Schreibliste aufnehmen` | Die Platte ist nicht in der Schreibliste und hat `STORAGE_FREE_GB` frei. | Setzt die Platte ans Ende der Liste und entfernt die Markierung „voll“. |
| `Aus Schreibliste nehmen` | Die Platte ist in der Liste, und eine andere Platte, die nicht voll ist, bleibt darin. | Die Platte bekommt keine neuen Bilder. Die Bilder darauf bleiben lesbar. |

Das Skript prüft die Bedingungen erneut. Schlägt eine Schaltfläche fehl, nennt die Meldung den Grund. Die Texte stehen in der
[Fehlersuche](troubleshooting.de.md#disk-halt). Eine Meldung, die mit `Archiv-Konfiguration nicht neu geladen` beginnt und mit `(HTTP 500)`
endet, heißt, dass die Änderung in der LDAP-Konfiguration steht, aber `arc` sie nicht neu geladen hat. Eine Meldung, die mit `(HTTP 504)`
endet, heißt, dass das Skript nicht innerhalb von 300 Sekunden geendet hat. Beide Fälle stehen in der
[Fehlersuche](troubleshooting.de.md#disk-half-done).

**Neue Bilder sofort auf eine neue Platte schicken.** Eine neue Platte steht am Ende der Liste. Um sie jetzt zum Ziel zu machen, die
Platten davor mit `Aus Schreibliste nehmen` aus der Schreibliste nehmen. Das Fenster nennt die Platte, die die neuen Bilder bekommt. Um
zurückzugehen, bei der alten Platte `In Schreibliste aufnehmen` nutzen. Die Platte steht dann am Ende der Liste. Das gilt für Platten mit dem
Namen `PACS-Data` plus einer Zahl. Für andere Namen siehe den letzten Absatz dieses Abschnitts.

> **Prüfen**
>
> Erwartet: Der Hinweis `neue Bilder jetzt` wandert zu der Platte, die gemeint war. Auf der Kommandozeile zeigt `scan` das Wort
> `Schreibliste` nur hinter Platten, die in der Liste sind.

**Eine Platte vergrößern.** Die Platte im Hypervisor vergrößern, dann die Kommandozeile nutzen. `scan` listet die Platte unter
`--- Vergroesserte Platten (grow)` auf.

```bash
bash /opt/pacs-admin/server/pacs-storage.sh grow /dev/sdc
bash /opt/pacs-admin/server/pacs-storage.sh grow /dev/sdc ja
```

Der erste Aufruf zeigt den Plan. Der zweite Aufruf vergrößert das Dateisystem, und die Platte bleibt in Benutzung. Ist die Platte nicht in
der Schreibliste, setzt `grow` sie ans Ende. Eine Markierung „voll“ kann bleiben. Dann `Markierung entfernen` wählen.

> **Warnung**
>
> `pacs-verwaltung` nicht neu starten, solange die Kachel `Neue Festplatte` `läuft seit …` sagt. Der Neustart stoppt die laufende
> Einrichtung mittendrin. Das Ende abwarten, dann neu starten. Der Hilfsdienst schreibt keine Protokollzeile, während er neu startet
> ([Fehlersuche](troubleshooting.de.md#audit-lines-missing)).

**Speicher mit anderen Namen.** dcm4chee nutzt einen Speicher mit anderem Namen weiter, zum Beispiel einen, den dcm4chee selbst angelegt
hat. Die Kachel und die Befehle `freigeben`, `anhaengen` und `grow` behandeln nur die Platten `PACS-Data` plus eine Zahl unter `/mnt/fs`.
`abhaengen` akzeptiert jeden Namen, aber kein Werkzeug dieses Repositorys setzt einen solchen Speicher wieder in die Liste.

<a id="disk-rollback"></a>
### 3.6 Zurückgehen

- **Vor der ersten Platte:** die Compose-Datei zurückspielen wie in [2.3](#recreate-rollback).
- **Nach der ersten Platte:** Änderung A behalten. Ohne das Volume kann dcm4chee die Bilder auf den neuen Platten nicht lesen.
- **Eine Platte, die keine Bilder mehr bekommen soll:** sie aus der Schreibliste nehmen (`Aus Schreibliste nehmen`). Die Platte eingehängt lassen.
  Der Assistent hat keine Funktion, um eine Platte oder einen Speicher zu entfernen. Wird eine Platte entfernt, die Bilder enthält,
  lassen sich diese Bilder nicht mehr lesen.
- **Eine Einrichtung, die mittendrin stoppte:** siehe die [Fehlersuche](troubleshooting.de.md#disk-half-done).
- **Das ganze Produkt entfernen:** die Schritte stehen in [install.de.md](install.de.md#uninstall). Das umfasst das Volume, die Ports und
  die Passwortzeile der Compose-Datei.

<a id="firewall"></a>
## 4. Firewall

Die Firewall entscheidet, welche Rechner eine Verbindung zu den Docker-Ports dieses Servers öffnen dürfen: DICOM, HL7, die
REST-Schnittstelle von dcm4chee und die Verwaltungsports. Dazu nutzt sie [iptables](glossary.de.md#iptables)-Regeln, die man im Reiter
`Firewall` der Admin-Seite verwaltet ([Beschriftungen auf dem Bildschirm](glossary.de.md#screen-firewall)). Zuerst die Notbremse lesen.

<a id="firewall-brake"></a>
> **Warnung**
>
> **Notbremse.** Eine falsche Regel kann eine Modalität, einen HL7-Sender oder einen Benutzer sofort abschneiden. Auch die
> Admin-Seite kann sie abschneiden. SSH funktioniert weiter, weil die Firewall es nie berührt. Über SSH anmelden (oder die Konsole der virtuellen
> Maschine öffnen) und als root ausführen:
>
> ```bash
> systemctl stop pacs-firewall
> ```
>
> Der Befehl entfernt den Sprung zur Regelkette `PACS-SPERRE`. Alle Docker-Ports sind sofort wieder offen. Er löscht keine Regel und
> keine Datei. So sieht man, dass es gewirkt hat:
>
> ```bash
> iptables -S DOCKER-USER
> ```
>
> Erwartet: keine Zeile, die `PACS-SPERRE` enthält.
>
> Die Bremse hält nur eine Weile. Die Regeln kommen zurück, wenn
>
> - der Server neu startet,
> - jemand im Reiter `Firewall` einen geänderten Regelsatz speichert, oder
> - sich die Liste der veröffentlichten Docker-Ports ändert (zum Beispiel, wenn `arc` neu erzeugt wird) und `Ports ohne eigene Regel`
>   nicht `offen` ist. Der Hilfsdienst prüft das alle 5 Minuten.
>
> Um die Firewall dauerhaft auszuschalten, im Reiter `eingeschaltet` abwählen, `Speichern` wählen und
> `systemctl disable --now pacs-firewall` ausführen. Eine Änderung nicht mit `systemctl restart pacs-firewall` anwenden: Das öffnet für
> einen Moment alle Ports ([4.10](#firewall-settings) zeigt den Weg ohne Lücke).

**Wer sie braucht.** Viele Netze erreichen den Server, und man will entscheiden, wer sich mit den DICOM- und HL7-Ports und mit den
Verwaltungsports verbinden darf. Erreichen den Server nur wenige vertrauenswürdige Rechner, kann die Firewall des eigenen Netzes genügen.

**Was sie ändert.**

- Die Compose-Datei von dcm4chee: Änderung B ([Abschnitt 2](#edits-overview)) schreibt die Ports mit einer Adresse. `arc` startet einmal
  neu.
- Der Paketfilter: eine Kette `PACS-SPERRE` mit den eigenen Regeln und ein Sprung dorthin aus der Kette `DOCKER-USER`.
- Eine systemd-Unit, `pacs-firewall`, die die Regeln bei jedem Start des Servers und von Docker neu setzt.
- Dateien im Ordner `PACS_DIR` (Standard `/opt/dcm4chee-arc`): `firewall.json` enthält die eigenen Regeln, und der Ordner `firewall/`
  enthält Sicherungen davon und die Listen, die die Seite sammelt.
- Eine Zeile `FW_DEFAULT_RULES` in `/etc/default/pacs-admin` für den ersten Start ([4.4](#firewall-start)).

Die Firewall ändert keine Einstellung von dcm4chee, nginx oder dem Viewer.

> **Warnung**
>
> Eine Regel, die einen Port sperrt, schneidet jeden ab, der ihn nutzt, und niemand meldet es, bis ein Gerät oder ein Benutzer sich
> beschwert. Keinen Port sperren, bevor bekannt ist, wer ihn nutzt. Im Probelauf starten ([4.4](#firewall-start)), die Ergebnisse lesen
> ([4.5](#firewall-read)), jeweils einen Port sperren ([4.7](#firewall-block)) und jeden Schritt von einem zweiten Rechner aus testen.
> Während der Arbeit eine SSH-Sitzung offen halten.

In dieser Reihenfolge arbeiten:

1. [Herausfinden, wer welchen Port nutzt](#firewall-inventory) (4.2).
2. [Die Ports nur auf IPv4 veröffentlichen](#firewall-ports) (4.3).
3. [Die Firewall im Probelauf starten](#firewall-start) (4.4) und etwa eine Woche sammeln lassen ([4.5](#firewall-read)).
4. [Die bekannten Quellen erlauben](#firewall-allow) (4.6), dann [Port für Port sperren](#firewall-block) (4.7).
5. [Einen Neustart testen](#firewall-reboot) (4.8).

Die Abschnitte 4.9 bis 4.12 sind Optionen und Nachschlagewerk: [Client-PCs](#firewall-clients), [Einstellungen](#firewall-settings),
[die Aussperr-Prüfung](#firewall-lockout) und [das Entfernen](#firewall-uninstall).

<a id="firewall-scope"></a>
### 4.1 Was die Firewall abdeckt

Die Firewall prüft **neue Verbindungen**, die von außen zu einem Port kommen, den Docker auf einer IPv4-Adresse veröffentlicht. Docker
schickt diese Verbindungen durch die Kette `DOCKER-USER`, und die Firewall hängt sich dort ein ([Glossar](glossary.de.md#docker-user)).

Die Firewall deckt ab:

- neue Verbindungen von außen zu den Ports, die ein Container auf IPv4 veröffentlicht: DICOM, HL7, die REST-Ports 8080 und 8443, die
  Web-Ports 443 und 80 und die Verwaltungsports. Das gilt für jeden Container, nicht nur für `arc`.

Die Firewall deckt nicht ab:

- SSH (Port 22) und jeden Dienst, der auf dem Host selbst läuft, außerhalb von Docker.
- Verbindungen über IPv6, die Docker über `docker-proxy` annimmt. Diese Verbindungen passieren die Firewall. Der Reiter zeigt bei einem solchen Port das
  Badge `IPv6 nicht gefiltert` ([4.3](#firewall-ipv6)).
- Verbindungen, die ein Container selbst öffnet, zum Beispiel `arc`, das Bilder an eine Modalität sendet. Die Firewall lässt den Verkehr
  bestehender Verbindungen durch. Eine Verbindung, die beim Speichern einer Regel schon besteht, bleibt offen, bis sie endet.
- Den Verkehr des Servers zu sich selbst (`127.0.0.1`). Ein Port, den Docker nur an `127.0.0.1` bindet, steht nicht in der Liste: Von
  außen erreicht ihn niemand.
- Verkehr, der über eine andere Netzwerkschnittstelle hereinkommt als die, die die Firewall überwacht (Schritt 1 von
  [4.4](#firewall-start)).

Jeder Port hat einen von drei Modi. Die Einstellung `Ports ohne eigene Regel` gibt den Modus für alle anderen Ports vor, auch für Ports,
die Docker später veröffentlicht.

| Modus | Was mit einer neuen Verbindung geschieht |
|---|---|
| `offen` | Die Verbindung passiert. |
| `Probelauf` | Die Verbindung passiert. Steht die Quelle nicht auf der Liste des Ports, schreibt der Kernel eine Logzeile, und die Quelle erscheint unter `Neu erkannt`. |
| `gesperrt` | Die Verbindung passiert nur von einem Rechner oder Netz auf der Liste des Ports. Jede andere Quelle wird abgewiesen: Der Client bekommt „connection refused“. Der Kernel schreibt eine Logzeile. |

Eine Liste enthält IPv4-Adressen (`192.0.2.18`) und IPv4-Netze in [CIDR](glossary.de.md#cidr)-Schreibweise (`192.0.2.0/24`).

<a id="firewall-inventory"></a>
### 4.2 Herausfinden, wer welchen Port nutzt

> **Warnung**
>
> Der eingebaute Regelsatz der Firewall sperrt sieben Ports **sofort**, wenn die Unit zum ersten Mal startet: 8080, 8443, 9990, 9993,
> 5601, 8000 und 9443. Einen Port in der Compose-Datei an `127.0.0.1` zu binden, hat für diesen Port dieselbe Wirkung. Jeder, der einen
> solchen Port von einem anderen Rechner aus nutzt, bekommt dann „connection refused“. Der Start in [4.4](#firewall-start) umgeht den
> eingebauten Satz. Zuerst die Bestandsaufnahme unten machen.

| Port | Dienst | Wer ihn nutzt | Was ausfällt, wenn man ihn sperrt |
|---|---|---|---|
| `443`, `80` | Eingangstür: Viewer und Admin-Seite | Alle Mitarbeitenden | Der Viewer und die Admin-Seite öffnen sich nicht. Die eingebauten Regeln lassen beide offen. |
| `11112` | DICOM | Modalitäten, andere Archive und Arbeitsplätze, die Bilder senden oder abfragen | Bilder werden nicht gespeichert. Das Gerät meldet einen fehlgeschlagenen Versand. |
| `2762` | DICOM über TLS | Dieselben Geräte, wenn sie TLS nutzen | Dasselbe. |
| `2575` | HL7 | Das KIS (Krankenhausinformationssystem) oder RIS, das Aufträge und Patientennachrichten sendet | Nachrichten werden nicht zugestellt. |
| `12575` | HL7 über TLS | Derselbe Sender, wenn er TLS nutzt | Dasselbe. |
| `8080`, `8443` | REST-Schnittstelle und Benutzeroberfläche von dcm4chee (http, https) | Personen, die die dcm4chee-Benutzeroberfläche direkt öffnen, Programme, die WADO, QIDO oder STOW aufrufen, Überwachung | Der Aufrufer bekommt „connection refused“. Der Viewer und die Admin-Seite funktionieren weiter: Beide erreichen `arc` über das Docker-Netz und über `127.0.0.1`. |
| `9990`, `9993` | Verwaltungskonsole von WildFly (http, https) | Administratoren, selten | Die Konsole öffnet sich nicht. |
| `5601` | Kibana, falls es läuft | Administratoren | Kibana öffnet sich nicht. |
| `8000`, `9443` | Portainer, falls es läuft | Administratoren | Portainer öffnet sich nicht. |

Andere Container können weitere Ports veröffentlichen. Die Kachel `Ports` des Reiters `Firewall` listet jeden veröffentlichten Port auf
und nennt seinen Container.

**Wer sich jetzt verbindet.** Der Kernel führt eine Tabelle der Verbindungen, die jetzt bestehen. Die Tabelle als root lesen. Der Befehl zählt die
Verbindungen je Quelle und Port aus der Tabelle oben:

```bash
awk '
  $1 == "ipv4" && $3 == "tcp" {
    src = ""; port = ""
    for (i = 6; i <= NF; i++) {
      split($i, kv, "=")
      if (kv[1] == "src" && src == "") src = kv[2]
      if (kv[1] == "dport" && port == "") port = kv[2]
    }
    if (port ~ /^(8080|8443|9990|9993|5601|8000|9443)$/) count[port " " src]++
  }
  END { for (key in count) print count[key], key }
' /proc/net/nf_conntrack | sort -k2,2n -k3,3
```

> **Prüfen**
>
> Erwartet: eine Zeile je Quelle und Port, mit der Zahl der Verbindungen, dem Port und der Quelladresse. Beispiel:
>
> ```text
> 2 8080 192.0.2.50
> 1 8443 192.0.2.77
> ```
>
> Keine Ausgabe heißt, dass diese Ports im Moment niemand nutzt. Das heißt nicht, dass sie überhaupt niemand nutzt. Meldet der Fehler,
> dass die Datei nicht existiert, hat der Kernel das Connection-Tracking noch nicht geladen: `modprobe nf_conntrack` ausführen.

Verbindungen über IPv6 und Verbindungen zu Programmen auf dem Host selbst stehen nicht in dieser Tabelle. Diese Verbindungen mit `ss` auflisten. Eine
Gegenstellenadresse mit Doppelpunkten in eckigen Klammern ist ein IPv6-Client:

```bash
ss -tn state established '( sport = :8080 or sport = :8443 or sport = :9990 or sport = :9993 or sport = :5601 or sport = :8000 or sport = :9443 )'
```

Eine Momentaufnahme ist keine Vollerhebung. Eine Modalität verbindet sich vielleicht einmal am Tag, ein HL7-Sender einmal pro Stunde und
ein Administrator einmal im Monat. Der Probelauf in [4.4](#firewall-start) ist die verlässliche Bestandsaufnahme: Er protokolliert jede
neue Verbindung von einer Quelle, die auf keiner Liste steht. Außerdem die Kolleginnen und Kollegen fragen:

- Wer öffnet die dcm4chee-Benutzeroberfläche auf Port 8080 oder 8443? Diese Personen brauchen [Abschnitt 5](#dcm4chee-ui), bevor die
  beiden Ports gesperrt werden.
- Welche Überwachungswerkzeuge und Skripte rufen die REST-Schnittstelle auf?

<a id="firewall-ports"></a>
### 4.3 Die Ports nur auf IPv4 veröffentlichen

Die Firewall filtert nur IPv4. Ein Port ohne Adresse in der Compose-Datei wird auf IPv4 und bei vielen Installationen auch auf IPv6
veröffentlicht. Docker nimmt die IPv6-Verbindungen in `docker-proxy` an ([Glossar](glossary.de.md#docker-proxy)), und diese Verbindungen
laufen an der Firewall vorbei. Änderung B aus [Abschnitt 2](#edits-steps) schreibt jeden Port von `arc` als `0.0.0.0:PORT:PORT`. Docker
veröffentlicht dann nur auf IPv4. Änderung B im selben Neuerzeugen machen wie Änderung A. Bei den Ports anderer Container (LDAP, Kibana,
Portainer) `0.0.0.0:` in der Compose-Datei ergänzen, die sie veröffentlicht.

Nach dem Neuerzeugen ansehen, was Docker veröffentlicht:

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

> **Prüfen**
>
> Erwartet: Jeder veröffentlichte Port von `arc` erscheint einmal, als `0.0.0.0:11112->11112/tcp` (Beispiel). Ein Eintrag wie
> `[::]:11112->11112/tcp` daneben heißt, dass der Port auch über IPv6 offen und nicht gefiltert ist. Der Reiter markiert einen solchen
> Port mit dem Badge `IPv6 nicht gefiltert`. Ein Port, der nur `127.0.0.1:` zeigt, ist von außen nicht erreichbar.

<a id="firewall-ipv6"></a>
#### Wenn ein Port über IPv6 offen bleibt

Es gibt zwei Möglichkeiten. Wenn möglich, die erste wählen.

**Möglichkeit 1: die Compose-Datei korrigieren.** `0.0.0.0:` vor den Port schreiben, wie in Änderung B. `127.0.0.1:` schreiben, wenn
niemand den Port von einem anderen Rechner braucht. Den Container noch einmal neu erzeugen.

**Möglichkeit 2: IPv6 auf dem Server ausschalten.** Das nur nutzen, wenn kein Dienst des Servers IPv6 braucht.

> **Warnung**
>
> Das stoppt SSH und jeden anderen Dienst auf IPv6-Adressen. Wer über eine IPv6-Adresse arbeitet, schneidet die eigene Sitzung ab. Die
> Konsole des Servers bereithalten. Docker nicht neu starten, um die Einstellung anzuwenden: Ein Neustart von Docker stoppt alle
> Container, außer `live-restore` ist an. Wie Docker Ports veröffentlicht, wenn IPv6 aus ist, hängt von seiner Version ab, darum die Ports
> nach dem Neustart prüfen. Um zurückzugehen, die Datei unten löschen und neu booten.

```bash
cat > /etc/sysctl.d/90-pacs-no-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
sysctl --system
```

Den Server in einem Wartungsfenster neu booten, dann die Ports noch einmal ansehen.

> **Prüfen**
>
> ```bash
> sysctl net.ipv6.conf.all.disable_ipv6
> docker ps --format 'table {{.Names}}\t{{.Ports}}'
> ```
>
> Erwartet: `net.ipv6.conf.all.disable_ipv6 = 1` und kein Eintrag, der mit `[::]:` beginnt. Bleibt ein Eintrag, für diesen Port
> Möglichkeit 1 nutzen.

<a id="firewall-start"></a>
### 4.4 Erster Start im Probelauf

Die Firewall mit jedem Port im Probelauf starten. Im Probelauf wird niemand gesperrt, und die Firewall protokolliert jede Quelle, die
keine Liste nennt. Der eingebaute Regelsatz würde sieben Ports sofort sperren ([4.2](#firewall-inventory)), darum ihn für den ersten Start
ersetzen.

#### Schritt 1. Die Programme und die Netzwerkschnittstelle prüfen

Die Firewall braucht die Programme `iptables` und `ip`. Die Firewall überwacht den Verkehr, der über eine Netzwerkschnittstelle hereinkommt, die
Schnittstelle der Standardroute.

```bash
command -v iptables ip
ip route show default
```

> **Prüfen**
>
> Erwartet: zwei Pfade, einer für `iptables` und einer für `ip`, und eine Routenzeile wie `default via 192.0.2.1 dev eth0 proto static`
> (Beispiel). Das Wort nach `dev` ist die Schnittstelle. Fehlt ein Programm, `apt-get install -y iptables iproute2` ausführen.
>
> Zeigt die Ausgabe keine Route oder mehrere Routen, oder erreichen die Clients den Server über eine andere Netzwerkkarte, die
> Schnittstelle von Hand nennen: die Zeile `FW_INTERFACE=eth0` (mit dem eigenen Schnittstellennamen) zu `/etc/default/pacs-admin`
> hinzufügen.

#### Schritt 2. Den Regelsatz für den ersten Start schreiben

Die Datei unten hat das Format von `firewall.json` ([Referenz](reference.de.md#firewall-json)). Die Ports 443 und 80 bleiben offen. Die
Ports 11112 (DICOM), 2575 (HL7), 8080, 8443, 9990 und 9993 bekommen den Modus `probelauf`. `standard` ist der Modus für alle anderen
Ports, ebenfalls `probelauf`. Den Host-Port nutzen, die Zahl links vom Doppelpunkt in der Compose-Datei: Senden die Geräte an `104`,
`104` schreiben.

```bash
cat > /etc/pacs-admin-firewall-start.json <<'EOF'
{
  "aktiv": true,
  "standard": "probelauf",
  "regeln": [
    {"port": 443,   "name": "Viewer und Verwaltung",        "modus": "offen"},
    {"port": 80,    "name": "Viewer und Verwaltung (http)", "modus": "offen"},
    {"port": 11112, "name": "DICOM",                        "modus": "probelauf"},
    {"port": 2575,  "name": "HL7",                          "modus": "probelauf"},
    {"port": 8080,  "name": "dcm4chee REST (http)",         "modus": "probelauf"},
    {"port": 8443,  "name": "dcm4chee REST (https)",        "modus": "probelauf"},
    {"port": 9990,  "name": "WildFly-Verwaltung",           "modus": "probelauf"},
    {"port": 9993,  "name": "WildFly-Verwaltung (https)",   "modus": "probelauf"}
  ]
}
EOF
```

Der Firewall sagen, dass sie diese Datei nutzt, solange keine `firewall.json` existiert. Nach dem ersten `Speichern` im Reiter übernimmt
`firewall.json`, und diese Datei wird nicht mehr gelesen.

> **Warnung**
>
> `>>` schreiben (zwei Zeichen). Ein einzelnes `>` ersetzt die ganze Datei `/etc/default/pacs-admin` und entfernt alle Einstellungen.
> Passiert das, die Einstellungen aus den eigenen Notizen oder aus `deploy/pacs-admin.env.example` wiederherstellen.

```bash
echo 'FW_DEFAULT_RULES=/etc/pacs-admin-firewall-start.json' >> /etc/default/pacs-admin
```

#### Schritt 3. Den Hilfsdienst neu starten und die Firewall starten

Der Hilfsdienst liest `FW_DEFAULT_RULES` beim Start, darum ihn einmal neu starten.

> **Warnung**
>
> `pacs-verwaltung` nicht neu starten, solange eine Platteneinrichtung läuft ([3.5](#disk-operate)). Der Hilfsdienst schreibt keine
> Protokollzeile, während er neu startet. Dieser Schritt sperrt niemanden: Jeder Port ist offen oder im Probelauf.

```bash
systemctl restart pacs-verwaltung
```

Die Unit installieren und starten. Liegt das Repository nicht in `/opt/pacs-admin`, zuerst den Pfad in der Unit ändern, wie
[install.de.md](install.de.md#helper-service) es für die andere Unit zeigt.

```bash
cp /opt/pacs-admin/deploy/systemd/pacs-firewall.service /etc/systemd/system/
systemctl enable --now pacs-firewall
```

#### Schritt 4. Prüfen, ob die Regeln wirken

> **Prüfen**
>
> ```bash
> systemctl is-active pacs-firewall
> iptables -S DOCKER-USER
> set -a; . /etc/default/pacs-admin; set +a
> python3 /opt/pacs-admin/server/firewall.py status
> ```
>
> Erwartet: `active`, dann drei Zeilen (die Schnittstelle ist die eigene):
>
> ```text
> -N DOCKER-USER
> -A DOCKER-USER -i eth0 -j PACS-SPERRE
> -A DOCKER-USER -j RETURN
> ```
>
> Dann eine Zeile je Regel und eine letzte Zeile mit `wirksam: True`. Beispiel:
>
> ```text
>    80 offen      Viewer und Verwaltung (http) erlaubt: -  fremd: 0
>   443 offen      Viewer und Verwaltung        erlaubt: -  fremd: 0
>  2575 probelauf  HL7                          erlaubt: -  fremd: 0
>  8080 probelauf  dcm4chee REST (http)         erlaubt: -  fremd: 0
>  8443 probelauf  dcm4chee REST (https)        erlaubt: -  fremd: 0
>  9990 probelauf  WildFly-Verwaltung           erlaubt: -  fremd: 0
>  9993 probelauf  WildFly-Verwaltung (https)   erlaubt: -  fremd: 0
> 11112 probelauf  DICOM                        erlaubt: -  fremd: 0
> Schnittstelle: eth0  wirksam: True  Zähler seit: 2026-10-14T10:30:12
> ```
>
> Der Reiter `Firewall` zeigt das Badge `wirksam`. Den Viewer einmal öffnen, um zu sehen, dass er noch funktioniert. Sagt das Badge
> `nicht wirksam`, nennt es den Grund: siehe die [Fehlersuche](troubleshooting.de.md#firewall-not-effective).
>
> Zeigt die Seite eine rote Meldung, die mit `Firewall laden: Firewall:` beginnt und mit `(HTTP 500)` endet, konnte der Hilfsdienst den
> Status nicht lesen. Eine Ursache ist, dass `docker` nicht installiert ist, weil der Status die Docker-Netze liest. Siehe die
> [Fehlersuche](troubleshooting.de.md#firewall-tools-missing).

<a id="firewall-read"></a>
### 4.5 Sammeln lassen und die Ergebnisse lesen

Die Firewall etwa eine Woche im Probelauf lassen, oder länger als den längsten Zyklus der eigenen Geräte. Manche Geräte senden einmal
pro Nacht, manche einmal pro Woche. Der Reiter liest nur das Kernel-Log des aktuellen Boots, darum in dieser Zeit nicht neu starten.

| Wo im Reiter | Was er zeigt | Nutzen |
|---|---|---|
| Badge ganz oben | `wirksam`, `nicht wirksam` mit dem Grund oder `ausgeschaltet`. Außerdem die Schnittstelle, die Zeit, seit der die Zahlen zählen, und wer die Regeln zuletzt geändert hat. | Steht dort `nicht wirksam`, zuerst den Grund lesen. |
| Kachel `Ports`, Spalte `Andere` | Die Zahl neuer Verbindungen von Quellen, die nicht auf der Liste des Ports stehen: `N nicht eingetragen` im Probelauf, `N abgewiesen` bei gesperrtem Port. Die Zahlen sind exakt und beginnen nach jedem Speichern, das Regeln ändert, wieder bei null. | Ein Port ohne eine solche Zahl hatte keine fremde Verbindung. |
| Kachel `Neu erkannt` | Quellen, die noch keine Liste nennt: Client-Netze, DICOM-Geräte, HL7-Sender und Quellen aus dem Probelauf. | In [4.6](#firewall-allow) abarbeiten. |
| Kacheln `DICOM-Absender` und `HL7-Absender` | Geräte, die Daten an das Archiv gesendet haben. Der Hilfsdienst liest sie alle 5 Minuten aus dem Log von dcm4chee. Ein Badge sagt `intern, nicht betroffen`, `eingetragen` oder `nicht eingetragen`. | Zeigt Absender, die im Kernel-Log still bleiben. |
| Details `Verbindungen an Regeln` | Quellen, die auf eine Regel trafen, aus dem Kernel-Log: `abgewiesen`, `Probelauf: nicht eingetragen`, `erlaubt, protokolliert`, `Standard: abgewiesen`. | Der Beleg für jeden Eintrag. |

Grenzen der Daten:

- Der Kernel schreibt je Regel höchstens 10 Logzeilen pro Minute. Eine aktive Quelle kann innerhalb einer Minute eine seltene Quelle
  verdecken. Über eine Woche erscheint jede Quelle, die sich mindestens einmal am Tag verbindet.
- Die Absender-Kacheln brauchen das Log von dcm4chee. Der Hilfsdienst findet es über `ARC_LOG_DIR` ([4.10](#firewall-settings)).
- `firewall.py nachholen` liest die gepackten Logs von dcm4chee und dann das laufende Log von seinem Anfang an. Es ersetzt die
  Absenderlisten, die die Seite bisher gesammelt hat. Einmal nutzen, um die Absender früherer Tage in den Listen zu haben
  ([4.10](#firewall-settings)).

> **Prüfen**
>
> Erwartet: nach höchstens 10 Minuten listen die Kacheln `DICOM-Absender` und `HL7-Absender` die Geräte, die Daten gesendet haben. Steht
> in einer Kachel `Noch keine Absender erfasst.`, obwohl Geräte senden, siehe die [Fehlersuche](troubleshooting.de.md#arc-log-dir).

<a id="firewall-allow"></a>
### 4.6 Die bekannten Quellen erlauben

Nach der Woche des Sammelns jede Quelle eintragen, die einen Grund hat, einen Port zu erreichen. Ein Port, den man später sperrt, lässt
nur die Quellen auf seiner Liste durch. Jede andere Quelle wird abgewiesen.

#### Schritt 1. `Neu erkannt` abarbeiten

Die Kachel `Neu erkannt` steht oben im Reiter. Die Tabelle darin listet jede Quelle, die noch keine Liste ihres Ports nennt. Die Spalten
sind `Was`, `Quelle`, `Name`, `Port`, `Verbindungen` und `zuletzt`. Die Kachel zeigt keine Quelle für einen Port im Modus `offen`.

| `Was` | Bedeutung |
|---|---|
| `Client-PCs` | Ein /24-Netz mit Rechnern, die die DNS-Suche gefunden hat ([4.9](#firewall-clients)). Die Zeile gilt für den ersten DICOM-Port. |
| `DICOM-Gerät` | Ein Gerät, das Daten an das Archiv gesendet hat. `Name` zeigt seinen [AE-Titel](glossary.de.md#ae-title). |
| `HL7-Absender` | Ein Sender von HL7-Nachrichten. |
| `Probelauf: nicht eingetragen` | Eine Quelle, die sich mit einem Port im Probelauf verbunden hat und auf keiner Liste steht. |
| `abgewiesen` | Eine Quelle, die an einem Web-Port, am ersten DICOM-Port oder am ersten HL7-Port abgewiesen wurde. |

Jede Zeile entscheiden:

- Der Rechner oder das Gerät gehört zum eigenen Haus und braucht den Port: `Erlauben` wählen.
- Die Quelle ist unbekannt: die Spalte `Name` lesen, die Besitzerin oder den Besitzer des Geräts fragen und warten. Nichts erlauben, was
  sich nicht benennen lässt.
- Die Quelle darf sich nicht verbinden und soll nicht mehr erscheinen: `Ausblenden` wählen. Die Zeile bleibt weg, bis man im Fuß der
  Kachel `Wieder anzeigen` wählt.

`Erlauben` und `Ausblenden` ändern auf dem Server noch nichts. Beide sammeln die Änderungen in einer Leiste am unteren Rand des Reiters:
`N Änderungen`. Ein Port ohne eigene Regel bekommt eine neue Regel. Die Regel startet im Modus von `Ports ohne eigene Regel`, oder im
`Probelauf`, wenn diese Einstellung `offen` ist.

> **Warnung**
>
> Eine Zeile der Art `Client-PCs` erlaubt für den DICOM-Port das ganze /24-Netz, nicht nur die Rechner, die die Suche gefunden hat.
> `Alle N erlauben` trägt jede Zeile auf einmal ein, auch die ungelesenen. Es erst nutzen, nachdem man jede Zeile gelesen hat. Vor dem
> Speichern verwirft `Verwerfen` alle ausstehenden Änderungen.

#### Schritt 2. Eine Quelle von Hand ergänzen

Das gilt für ein Gerät, das sich noch nicht verbunden hat, zum Beispiel eine neue Modalität. In der Kachel `Ports` die Zeile des Ports
suchen.

1. Ein Port, der noch dem Standard folgt, zeigt `niemand (Standard)` und keine Eingabefelder. Zuerst in der Spalte `Zugang` einen Modus
   wählen, zum Beispiel `Probelauf`. Die Spalte `Erlaubte Rechner und Netze` zeigt dann zwei Felder und eine Schaltfläche.
2. In `IP oder Netz` die IPv4-Adresse des Geräts oder sein Netz in [CIDR](glossary.de.md#cidr)-Schreibweise eintragen, zum Beispiel
   `192.0.2.18` oder `192.0.2.0/24`. In `Notiz` den Namen des Geräts und den Namen der Besitzerin oder des Besitzers eintragen.
3. `Hinzufügen` wählen.

Die Liste nimmt nur IPv4 an. Bei allem anderen sagt die Seite
`Bitte eine IPv4-Adresse oder ein Netz eingeben, z. B. 192.0.2.18 oder 192.0.2.0/24`. Um einen Eintrag zu entfernen, das `×` daran wählen.

Um zu sehen, wie oft sich ein eingetragenes Gerät verbindet, in der Zeile `protokollieren` ankreuzen. Der Kernel protokolliert dann auch
seine neuen Verbindungen, höchstens 10 Zeilen pro Minute. Diese Zeilen erscheinen unter `Verbindungen an Regeln` als `erlaubt, protokolliert`.

#### Schritt 3. Speichern

In der Leiste `Speichern` wählen. Die Seite zeigt die Änderungen in einem Fenster. Das Fenster beginnt mit `Firewall ändern:` und endet
mit `Gilt sofort.` Die Liste lesen und bestätigen.

Der Hilfsdienst schreibt die Regeln in `firewall.json`, sichert jede frühere Version im Ordner `firewall/` unter `PACS_DIR` und lädt die
Regeln in den Kernel. Lehnt der Kernel die Regeln ab, bleiben die früheren Regeln bestehen, und die Seite sagt
`Nicht übernommen, die vorigen Regeln gelten weiter:` gefolgt vom Grund. Das eigene Konto und die Liste der Änderungen gehen ins
Protokoll (Reiter `Protokoll`).

> **Prüfen**
>
> Erwartet: Die Leiste verschwindet. Hat man jede Zeile entschieden, steht in `Neu erkannt`
> `Nichts Neues: alles Erkannte ist eingetragen.` `Jetzt suchen` wählen, um die Logs sofort zu lesen. Die Logs werden ohnehin alle
> 5 Minuten gelesen. Zeilen können später wiederkommen: Ein Gerät, das sich einmal pro Woche verbindet, erscheint in der Woche danach.

<a id="firewall-block"></a>
### 4.7 Port für Port sperren

Die Ports in dieser Reihenfolge sperren und nach jedem Port von einem zweiten Rechner aus testen:

1. Die Verwaltungsports, die niemand nutzt: 9990, 9993, 5601, 8000 und 9443.
2. Die REST-Ports 8080 und 8443. Das erst tun, wenn die Personen, die die Benutzeroberfläche von dcm4chee nutzen, auf
   [Abschnitt 5](#dcm4chee-ui) umgezogen sind und die Programme, die die REST-Schnittstelle aufrufen, auf den Listen stehen.
3. Die HL7- und DICOM-Ports: 2575, 12575, 11112 und 2762.
4. Als Letztes die Einstellung `Ports ohne eigene Regel`.

443 und 80 auf `offen` lassen, außer nur bekannte Netze dürfen den Viewer und die Admin-Seite öffnen.

> **Warnung**
>
> Ein gesperrter Port weist jede Quelle ab, die nicht auf seiner Liste steht. Ein Gerät, das nicht auf der Liste steht, bekommt
> „connection refused“ und meldet einen fehlgeschlagenen Versand. Sonst meldet sich niemand. Einen Port erst sperren, nachdem man für ihn
> jede Zeile von `Neu erkannt` entschieden hat. Die SSH-Sitzung offen halten. Um für einen Port zurückzugehen, ihn auf `offen` setzen
> und speichern: Die Änderung wirkt sofort. Bei einem großen Ausfall die [Notbremse](#firewall-brake) nutzen.

#### Schritt 1. Einen Port sperren

In der Kachel `Ports` in der Spalte `Zugang` des Ports `gesperrt` wählen. Bei den Web-Ports, dem ersten DICOM-Port und dem ersten
HL7-Port fragt die Seite zuerst:
`Port N (Name) sperren? Danach kommen nur noch die eingetragenen Rechner durch, alle anderen werden abgewiesen.`
Bei einem Port im Probelauf kommt dazu:
`Vorher im Probelauf prüfen: unten darf niemand mehr als „nicht eingetragen“ stehen.`
Bestätigen, dann wie in [4.6](#firewall-allow), Schritt 3, `Speichern` wählen.

#### Schritt 2. Von einem zweiten Rechner aus testen

Einen Rechner nutzen, der nicht auf der Liste des Ports steht und nicht der Rechner ist, an dem man arbeitet. Den Test gegen einen Port
ausführen, dessen Dienst läuft: Auch ein gestoppter Dienst verweigert Verbindungen. Unter Windows in PowerShell:

```powershell
Test-NetConnection -ComputerName pacs.example.org -Port 9990
```

Unter Linux:

```bash
curl -sS -m 5 -o /dev/null http://pacs.example.org:9990/
```

> **Prüfen**
>
> Erwartet von einem Rechner, der **nicht** auf der Liste steht: PowerShell zeigt `TcpTestSucceeded : False`, und `curl` endet mit
> `curl: (7)`.
>
> Erwartet von einem Rechner, der **auf** der Liste steht: PowerShell zeigt `TcpTestSucceeded : True`, und `curl` gibt eine Antwort oder
> einen anderen Fehler als `(7)` aus. Die Verbindung kam zustande, also hat die Firewall sie durchgelassen.
>
> Kommt ein Rechner außerhalb der Liste durch, ist der Port nicht gesperrt. Das Badge oben im Reiter lesen und die
> [Fehlersuche](troubleshooting.de.md#firewall-not-effective) ansehen.

Der Test zeigt nur, dass der Port sich öffnet. Bei einem DICOM-Gerät zusätzlich das DICOM-Echo (C-ECHO, ein „Ping“ für DICOM) vom Gerät
oder aus seinem Servicemenü ausführen. Bei einem HL7-Sender eine Testnachricht senden.

#### Schritt 3. Die abgewiesene Verbindung ansehen

Das Kernel-Log und der Reiter halten beide den Test aus Schritt 2 fest.

```bash
journalctl -k --since "10 minutes ago" --no-pager | grep 'pacs-sperre 9990'
```

> **Prüfen**
>
> Erwartet: mindestens eine Zeile mit `pacs-sperre 9990:` und nach `SRC=` die Adresse des Testrechners. Im Reiter zeigt die Zeile des
> Ports `N abgewiesen` in der Spalte `Andere`, und die Kachel `Verbindungen an Regeln` listet die Adresse mit der Art `abgewiesen`. Die
> Zahlen beginnen nach jedem Speichern wieder bei null.

#### Schritt 4. Den Standard schließen

Hat jeder Port, der wichtig ist, eine eigene Regel, `Ports ohne eigene Regel` (oben im Reiter) auf `gesperrt` setzen. Jeder andere
veröffentlichte Port ist dann von außen geschlossen, auch der Port eines Containers, den man später startet. Die Seite fragt
`Standard „gesperrt“: alle Ports ohne eigene Regel sind danach von außen zu, auch künftig veröffentlichte.` und listet die Ports, die
heute keine Regel haben.

> **Warnung**
>
> Sicherstellen, dass 443 und 80 eine Regel `offen` haben, oder die Netze eintragen, die sie nutzen dürfen, wie die Seite es sagt.
> Ein Port im `Probelauf` bleibt für alle offen, auch beim Standard `gesperrt`. Der Standard weist auch neuen UDP-Verkehr zu
> Container-Ports ab. Nach dem Start eines neuen Containers, der einen Port veröffentlicht, eine Regel für den Port ergänzen, sonst
> erreicht ihn von außen niemand. Um zurückzugehen, den Standard auf `Probelauf` oder `offen` setzen und speichern.

Noch einmal vom zweiten Rechner aus testen: Der Viewer muss sich öffnen, und ein Port ohne Regel muss die Verbindung verweigern.

<a id="firewall-reboot"></a>
### 4.8 Einen Neustart testen

Die Regeln leben im Kernel. Ein Neustart entfernt sie, und die Unit `pacs-firewall` lädt sie beim Start des Servers wieder. Das einmal
in einem Wartungsfenster beweisen, bevor man sich auf die Firewall verlässt.

> **Warnung**
>
> Der Neustart stoppt das Archiv, den Viewer und die Admin-Seite, bis alles wieder gestartet ist. Nach dem Start von Docker laufen die
> Container unter Umständen einige Sekunden, bevor die Unit die Regeln setzt. In dieser Zeit können die Ports offen sein. Den Test
> ausführen, wenn das vertretbar ist.

```bash
reboot
```

Wenn der Server wieder läuft, per SSH anmelden:

```bash
systemctl is-active pacs-firewall
iptables -S DOCKER-USER
```

> **Prüfen**
>
> Erwartet: `active`, und unter den Zeilen des zweiten Befehls `-A DOCKER-USER -i eth0 -j PACS-SPERRE` (mit der eigenen Schnittstelle).
> Der Reiter `Firewall` zeigt `wirksam`. Den Test aus [4.7](#firewall-block), Schritt 2, für einen gesperrten Port wiederholen. Ist die
> Unit nicht aktiv oder sagt das Badge `nicht wirksam`, siehe die [Fehlersuche](troubleshooting.de.md#firewall-not-effective).

<a id="firewall-clients"></a>
### 4.9 Client-PCs (optional)

Diesen Abschnitt überspringen, wenn die Mitarbeitenden den Viewer nur im Browser nutzen: Der Viewer erreicht den Server auf Port 443. Ihn
nutzen, wenn Arbeitsplätze DICOM-Verbindungen zum Archiv öffnen, zum Beispiel um Bilder abzufragen oder abzurufen. Der Server schlägt dann
die Namen der Arbeitsplätze im DNS nach, gruppiert sie nach Netz und schlägt einen Eintrag je Netz für den ersten DICOM-Port vor.

Das Namensschema der Arbeitsplätze als Muster angeben. Muster trennt man durch Kommas. Ein Bereich `{a..b}` zählt wie in bash von a bis
b. Hat eine Grenze eine führende Null, werden die Zahlen mit Nullen auf die Breite der Grenzen aufgefüllt. Je Muster sind höchstens
100000 Namen erlaubt. Das Muster `pc{01..20},ws{001..040}` ergibt `pc01` bis `pc20` und `ws001` bis `ws040`. Ergänzt der Resolver des
Servers die eigene Domain nicht, den vollen Namen schreiben: `pc{01..20}.example.org`.

#### Schritt 1. Das Muster setzen

Das Beispielmuster durch das Schema der eigenen Arbeitsplätze ersetzen. `>>` schreiben (zwei Zeichen), damit die Einstellungen erhalten
bleiben. Die einfachen Anführungszeichen verhindern, dass die Shell die geschweiften Klammern ändert
([Regeln für die Einstellungsdatei](reference.de.md#env-file-rules)).

```bash
echo "FW_CLIENT_NAMES='pc{01..20},ws{001..040}'" >> /etc/default/pacs-admin
```

#### Schritt 2. Den Hilfsdienst neu starten und suchen

> **Warnung**
>
> `pacs-verwaltung` nicht neu starten, solange eine Platteneinrichtung läuft ([3.5](#disk-operate)). Der Hilfsdienst schreibt keine
> Protokollzeile, während er neu startet.

```bash
systemctl restart pacs-verwaltung
```

Im Reiter `Firewall` in der Kachel `Neu erkannt` `Jetzt suchen` wählen. Oder die Suche auf der Kommandozeile ausführen:

```bash
set -a; . /etc/default/pacs-admin; set +a
python3 /opt/pacs-admin/server/firewall.py clients
```

> **Prüfen**
>
> Erwartet: eine Zeile wie `37 Client-PCs` (Beispiel): die Zahl der Namen aus dem Muster, die das DNS auflösen konnte. Die Zeile
> `Client-Suche aus (FW_CLIENT_NAMES leer)` heißt, dass die Einstellung leer ist oder nicht geladen wurde: die Zeile in
> `/etc/default/pacs-admin` prüfen.
>
> Der Reiter zeigt eine Kachel `Client-PCs`: `N im DNS (Muster …) in N Netzen`. Die Tabelle darin hat eine Zeile je /24-Netz mit den
> Spalten `Netz`, `PCs`, `Namen` und `DICOM (11112)`. Die letzte Spalte sagt `eingetragen`, `N nicht eingetragen` oder
> `überschneidet Docker-Netz, erreicht das PACS nicht`.

Der letzte Text heißt, dass jede Adresse dieser Zeile in einem Netz liegt, das Docker auf dem Server nutzt (oder eine Adresse des Servers
ist). Der Server leitet den Verkehr für solche Adressen in sein Docker-Netz, nicht in das eigene Netz, darum erreichen diese Rechner das
Archiv nicht. Die Firewall verursacht das nicht. Den Adressbereich des Docker-Netzes ändern.

Der Server schlägt die Namen höchstens einmal pro Stunde nach, mit 8 Abfragen gleichzeitig. Findet das DNS nichts (zum Beispiel, wenn der
DNS-Server ausfällt), behält der Server das frühere Ergebnis. `Jetzt suchen` führt die Suche sofort aus.

<a id="firewall-settings"></a>
### 4.10 Einstellungen und Befehle

Die Einstellungen stehen in `/etc/default/pacs-admin` ([alle Einstellungen](reference.de.md#config-variables)). Die Firewall liest diese:

| Variable | Standard | Was sie festlegt |
|---|---|---|
| `FW_INTERFACE` | leer: die Schnittstelle der Standardroute | Die Netzwerkschnittstelle, die die Firewall überwacht. Das erste `Speichern` legt die Schnittstelle in `firewall.json` ab, und der gespeicherte Wert hat von da an Vorrang. |
| `FW_WEB_PORTS` | `443,80` | Host-Ports der Eingangstür. Der erste ist der https-Port, den die Aussperr-Prüfung schützt ([4.11](#firewall-lockout)). |
| `FW_DICOM_PORTS` | `11112,2762` | Host-Ports für DICOM (unverschlüsselt und TLS). Der erste Port ist der Hauptport: Die Vorschläge in `Neu erkannt` nutzen ihn. |
| `FW_HL7_PORTS` | `2575,12575` | Host-Ports für HL7 (unverschlüsselt und TLS). Der erste Port ist der Hauptport, wie bei DICOM. |
| `FW_DEFAULT_RULES` | leer | Eine JSON-Datei im Format von `firewall.json`. Die Datei gilt, solange keine `firewall.json` existiert ([4.4](#firewall-start)). |
| `FW_PORT_NAMES` | leer | Eigene Portnamen als JSON-Objekt, zum Beispiel `'{"104": "DICOM (alt)"}'`. |
| `FW_CLIENT_NAMES` | leer | Namensmuster der Client-PCs ([4.9](#firewall-clients)). |
| `ARC_LOG_DIR` | `/var/local/dcm4chee-arc/wildfly/log/` | Der Ordner mit dem Log `server.log` von dcm4chee, auf dem Server. |
| `PACS_DIR` | `/opt/dcm4chee-arc` | Der Ordner, der `firewall.json` und den Ordner `firewall/` enthält. |

Ein Port darf nur in einer der drei Portlisten stehen. Steht ein Port in zwei Listen, ignoriert die Firewall alle drei Einstellungen,
nutzt die Standardwerte und schreibt die Meldung `FW_WEB_PORTS, FW_DICOM_PORTS und FW_HL7_PORTS ignoriert, ein Port steht in mehreren`
ins Journal.

**Eine Änderung anwenden.** Der Hilfsdienst liest die Einstellungen beim Start, darum ihn neu starten. Um die Regeln ohne Lücke wieder in
den Kernel zu laden, `firewall.py start` mit geladenen Einstellungen ausführen. Dafür nicht `systemctl restart pacs-firewall` nutzen: Der
Neustart entfernt zuerst die Regeln, und jeder Port ist offen, bis sie wieder geladen sind.

```bash
systemctl restart pacs-verwaltung
set -a; . /etc/default/pacs-admin; set +a
python3 /opt/pacs-admin/server/firewall.py start
```

> **Prüfen**
>
> Erwartet: Der letzte Befehl gibt `Firewall wirksam, 8 Regeln` aus (mit der Zahl der eigenen Regeln). `Firewall aus (Regeln geladen)`
> heißt, dass die Firewall in den Regeln ausgeschaltet ist: Die Regeln sind geladen, aber nichts springt dorthin.

**`ARC_LOG_DIR` finden.** Der Hilfsdienst liest die Absender von DICOM und HL7 aus dem Log von dcm4chee. Das Log liegt auf dem Server in
dem Ordner, den `arc` als `/opt/wildfly/standalone` einhängt, im Unterordner `log/`. Die Standard-Compose-Datei von dcm4chee hängt
`/var/local/dcm4chee-arc/wildfly` ein, darum passt der Standardwert. Um den eigenen Mount zu sehen:

```bash
docker inspect -f '{{range .Mounts}}{{if eq .Destination "/opt/wildfly/standalone"}}{{.Source}}{{end}}{{end}}' arc
ls -l /var/local/dcm4chee-arc/wildfly/log/server.log
```

Den Ordner aus dem ersten Befehl, gefolgt von `/log/`, im zweiten Befehl und in der Einstellung `ARC_LOG_DIR` verwenden. Ist die
Einstellung falsch, bleiben die Absender-Kacheln leer. Siehe die [Fehlersuche](troubleshooting.de.md#arc-log-dir).

**Befehle.** Alle Befehle laufen als root. Zuerst die Einstellungen laden, wie im Block oben, sonst zeigt das Programm seine Standardwerte.

| Befehl | Was er tut | Ausgabe (Beispiele) |
|---|---|---|
| `python3 /opt/pacs-admin/server/firewall.py status` | Zeigt jede Regel, ihre Zähler und ob die Regeln wirken. Das ist der Befehl ohne Argument. | Siehe [4.4](#firewall-start). Wirken die Regeln nicht, beginnt die letzte Zeile mit `Nicht wirksam, weil:`. |
| `... firewall.py start` | Lädt die Regeln und setzt den Sprung. Die Unit führt ihn bei jedem Start aus. Er wartet bis zu 60 Sekunden auf die Netzwerkschnittstelle. | `Firewall wirksam, 8 Regeln` |
| `... firewall.py stop` | Entfernt den Sprung. Die Unit führt ihn beim Stoppen aus. Das ist die Notbremse. | `Sprung nach PACS-SPERRE entfernt, alle Ports offen` |
| `... firewall.py absender` | Liest die neuen Zeilen des Logs von dcm4chee in die Absenderlisten. Der Hilfsdienst tut das alle 5 Minuten. | `12 neue Zeilen` |
| `... firewall.py nachholen` | Liest die gepackten Logs, dann das laufende Log von seinem Anfang an, und ersetzt die Absenderlisten. Einmal ausführen, um die Absender früherer Tage zu bekommen. | `server.log.2026-10-13.gz 1234 Zeilen`, dann `laufende Datei: 567 Zeilen` |
| `... firewall.py clients` | Schlägt die Namen der Client-PCs jetzt nach. | `37 Client-PCs` |
| `... firewall.py test` | Prüft das Programm mit temporären Daten. Es ändert auf dem Server nichts. | `Selbsttest ok` |

Ein Fehler erscheint als eine Zeile `firewall.py BEFEHL: Grund`, und der Exit-Code ist 1.

<a id="firewall-lockout"></a>
### 4.11 Was die Aussperr-Prüfung schützt

Beim Speichern prüft der Hilfsdienst, dass man den eigenen Rechner nicht von der Admin-Seite abschneidet. Er nutzt die Adresse, die die
Eingangstür für den eigenen Rechner meldet (der Header `X-Real-IP`). Er lehnt das Speichern ab, wenn alles Folgende zutrifft:

- Die Firewall ist in den neuen Regeln eingeschaltet.
- Die eigene Adresse ist eine IPv4-Adresse und keine Adresse des Servers oder eines Docker-Netzes.
- Die neuen Regeln sperren den ersten Web-Port (443 bei einer Standardinstallation), und die eigene Adresse steht nicht auf seiner Liste.

Die Seite zeigt dann diese Meldung (die Adresse ist ein Beispiel):

```text
Port 443: dein PC (192.0.2.50) wäre danach selbst ausgesperrt. Erst ihn oder sein Netz eintragen.
```

Den eigenen Rechner oder sein Netz in die Liste des Ports eintragen, dann noch einmal speichern.

Die Prüfung schützt **nicht**:

- Andere Benutzer. Eine Kollegin oder ein Kollege in einem anderen Netz kann den Viewer und die Admin-Seite verlieren.
- Jeden anderen Port als den ersten Web-Port: DICOM, HL7 und jeden weiteren Port.
- Benutzer hinter einem Reverse-Proxy. Die Firewall sieht die Adresse des Proxys, nicht die Adresse des Benutzers.
- Benutzer auf IPv6 und Speichervorgänge, die ohne den Header ankommen.

Die Prüfung ersetzt also nicht den Test von einem zweiten Rechner aus in [4.7](#firewall-block). Die
[Notbremse](#firewall-brake) in Reichweite halten.

<a id="firewall-uninstall"></a>
### 4.12 Die Firewall entfernen

Die Firewall in dieser Reihenfolge entfernen. Die Reihenfolge zählt: Der Hilfsdienst setzt die Regeln innerhalb von 5 Minuten wieder,
wenn er sie noch eingeschaltet hat.

> **Warnung**
>
> Ab dem Schritt `systemctl disable --now pacs-firewall` sind alle Docker-Ports für alle offen. Die Firewall nur entfernen, wenn man das
> hinnimmt. Die Änderungen an der Compose-Datei bleiben, wie sie sind, weil sie ohne die Firewall keinen Schaden anrichten.

1. Im Reiter `Firewall` das Häkchen bei `eingeschaltet` entfernen, `Speichern` wählen und bestätigen. Das Fenster nennt
   `Firewall AUSGESCHALTET`.
2. Die Unit stoppen und entfernen:

   ```bash
   systemctl disable --now pacs-firewall
   iptables -F PACS-SPERRE
   iptables -X PACS-SPERRE
   rm /etc/systemd/system/pacs-firewall.service
   systemctl daemon-reload
   ```

3. Den Regelsatz für den ersten Start entfernen, falls man in [4.4](#firewall-start) einen angelegt hat:

   ```bash
   sed -i '/^FW_DEFAULT_RULES=/d' /etc/default/pacs-admin
   rm -f /etc/pacs-admin-firewall-start.json
   ```

4. Den Hilfsdienst neu starten. Er liest die Einstellungen neu. Das nicht während einer Platteneinrichtung tun ([3.5](#disk-operate)).

   ```bash
   systemctl restart pacs-verwaltung
   ```

> **Prüfen**
>
> ```bash
> iptables -S DOCKER-USER
> iptables -S PACS-SPERRE
> ```
>
> Erwartet: Der erste Befehl gibt keine Zeile mit `PACS-SPERRE` aus. Der zweite gibt `iptables: No chain/target/match by that name.`
> aus. Der Reiter `Firewall` zeigt `ausgeschaltet`. `eingeschaltet` nicht wieder ankreuzen: Der Hilfsdienst würde die Regeln wieder setzen.

`firewall.json` und der Ordner `firewall/` bleiben in `PACS_DIR`. Richtet man die Firewall später wieder ein, ist sie in der gespeicherten
Datei ausgeschaltet. Dann `eingeschaltet` wieder ankreuzen. Das vollständige Entfernen der Admin-Seite steht in
[install.de.md](install.de.md#uninstall).

<a id="dcm4chee-ui"></a>
## 5. Die Benutzeroberfläche von dcm4chee über die Eingangstür

dcm4chee hat eine eigene Weboberfläche, die `ui2` des Archivs. Dieses Modul lässt Admins sie über die Eingangstür öffnen, hinter demselben
Login wie die Admin-Seite. Die Admins brauchen dann die Ports 8080 oder 8443 des Archivs nicht.

**Wer es braucht.** Admins, die die Oberfläche von dcm4chee nutzen, zum Beispiel um Studien anzusehen, zu verschieben oder die
Konfiguration zu ändern. Nutzt sie niemand, diesen Abschnitt überspringen.

**Was es ändert.** Eine nginx-Datei, `pacs/optional/dcm4chee-ui.conf`, im Ordner der Eingangstür. Sonst ändert sich nichts: weder die
Compose-Datei noch das Archiv noch die Admin-Seite. nginx lädt ohne Ausfall neu.

**Voraussetzungen.**

- Das Archiv läuft ohne Keycloak. Das heißt das Image `dcm4chee-arc-psql`, nicht ein Image `-secure` oder `-secure-ui`.
- Die Ports 8080 und 8443 von `arc` sind von außen geschlossen: in der Firewall gesperrt ([4.7](#firewall-block)) oder in der
  Compose-Datei an `127.0.0.1` gebunden. Sonst erreichen Personen die Oberfläche am direkten Port ohne Login.
- Die Datei `pacs/optional/dcm4chee-ui.conf` liegt im Ordner der Eingangstür. Schritt 4.9 der Installation kopiert sie
  ([install.de.md](install.de.md#nginx-files)).

**Woran nginx die Aufrufe der Oberfläche erkennt.** Die Oberfläche ruft viele Adressen unter `/dcm4chee-arc/` auf. nginx lässt diese
Aufrufe nur dann zum Archiv durch, wenn der Header `Referer` des Browsers die Oberfläche als die Seite nennt, von der sie kommen:
`https://`, derselbe Hostname wie in der Anfrage, kein Port und der Pfad `/dcm4chee-arc/ui2/`. Jeder andere Aufruf unter
`/dcm4chee-arc/` behält die Sperren der Admin-Seite.

Die Regel ist kein Login. Jeder Aufruf braucht weiterhin ein Admin-Konto. Außerdem muss der eigene Hostname bei jedem Aufruf gleich in der
Adressleiste stehen. Die Regel ändern, wenn man das PACS auf anderem Weg öffnet:

| Wie Benutzer das PACS öffnen | Was zu tun ist |
|---|---|
| `https://pacs.example.org/` (Listener `tls`, der Standard) | Nichts. Die Regel passt. |
| `https://pacs.example.org:8443/` (anderer Port) | Den Port in das Muster schreiben: `https://\1:8443/dcm4chee-arc/ui2/`. |
| Über einen SSH-Tunnel zu `http://127.0.0.1:8080/` (Listener `plain`) | An beiden Enden des Tunnels denselben Port nutzen. Das mitgelieferte Muster nennt `:8080`. |
| Hinter einem Reverse-Proxy (Listener `behind-proxy`) | Der Proxy muss den Header `Host` unverändert weitergeben (Apache: `ProxyPreserveHost On`). Lauscht der Proxy an einem anderen Port als 443, den Port in das Muster schreiben. |

Das Muster steht in der Datei `/opt/ohif/nginx/pacs/listener/http.conf`, im Block `map "$host $http_referer" $pacs_dcm4chee_ui`.
Nach einer Änderung die Konfiguration testen und nginx neu laden, wie im ersten Schritt unten.

> **Warnung**
>
> Die Oberfläche von dcm4chee hat keine Sperren. Wer sie öffnen darf, kann Studien löschen und die Konfiguration des Archivs ändern. Die
> Sperren und der Header `X-PACS-Admin` der Admin-Seite gelten hier nicht. nginx schreibt jede Änderung (alle Aufrufe außer GET, HEAD und
> OPTIONS) mit dem Konto ins Protokoll und hält kleine Änderungen mit ihrem Inhalt fest. Das Protokoll zeigt, was geschehen ist. Es macht
> es nicht rückgängig. Zugang nur Personen geben, denen man auch das Werkzeug des Herstellers anvertrauen würde.

#### Schritt 1. Die Datei an ihren Platz legen

Diesen Schritt überspringen, wenn der Ordner die Datei schon enthält.

```bash
ls /opt/ohif/nginx/pacs/optional/
```

Listet die Ausgabe `dcm4chee-ui.conf` nicht, die Datei kopieren, die Konfiguration testen und nginx neu laden:

```bash
cp /opt/pacs-admin/deploy/nginx/optional/dcm4chee-ui.conf /opt/ohif/nginx/pacs/optional/
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

> **Prüfen**
>
> Erwartet: `nginx -t` gibt `syntax is ok` und `test is successful` aus. nginx lädt ohne Ausfall neu. Gibt `nginx -t` einen Fehler aus,
> behält nginx die alte Konfiguration: den Fehler beheben, dann neu laden. Die Meldung `unknown "pacs_dcm4chee_ui" variable` heißt, dass
> die Listener-Dateien nicht kopiert wurden ([Fehlersuche](troubleshooting.de.md#nginx-wont-start)).

#### Schritt 2. Die Oberfläche öffnen

Mit einem Admin-Konto anmelden und den Link `dcm4chee` in der Kopfzeile der Admin-Seite wählen. Oder
`https://pacs.example.org/dcm4chee-arc/ui2/` öffnen. Die Einstiegsseite löscht die Keycloak-Einstellungen, die der Browser sich
merkt, und öffnet dann die Oberfläche auf Deutsch, außer der Browser merkt sich eine andere Sprache.

```bash
curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/dcm4chee
```

> **Prüfen**
>
> Erwartet: `301` vom Befehl (eine Weiterleitung nach `/dcm4chee-arc/ui2/`, die keinen Login braucht). Im Browser: Die Oberfläche zeigt
> ihre Liste der Studien. Zeigt der Browser `404` oder eine leere Seite, siehe die
> [Fehlersuche](troubleshooting.de.md#dcm4chee-ui-404). Fehlt der Link `dcm4chee` in der Kopfzeile, ist die Einstellung `dcm4cheeUrl` in
> `config.js` leer ([Referenz](reference.de.md#config-js)).

<a id="dcm4chee-ui-off"></a>
#### Abschalten

Die Datei löschen und nginx neu laden. Sonst ändert sich nichts.

```bash
rm /opt/ohif/nginx/pacs/optional/dcm4chee-ui.conf
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

> **Prüfen**
>
> ```bash
> curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/dcm4chee
> ```
>
> Erwartet: nicht `301`. Jeder Aufruf der Oberfläche gibt jetzt `404`. Um den Link `dcm4chee` in der Kopfzeile der Admin-Seite zu
> verbergen, `dcm4cheeUrl: ''` in `config.js` setzen.
