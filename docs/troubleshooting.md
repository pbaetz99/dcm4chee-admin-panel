# Troubleshooting

English | [Deutsch](troubleshooting.de.md)

<a id="troubleshooting"></a>
This page helps when something does not work. It is sorted by what you see: a message on the screen, a line in a log, a page
that stays empty. Find your symptom in [chapter 1](#symptom-index), open the entry and follow it. Every entry has the same
parts: **What you see**, **Cause**, **Fix** and a **Check** box that shows how to see that the fix worked.

Run all commands as root. A **Warning** box names what a step can break, how long it lasts and how to go back.

Three notes on the messages:

- The helper service and the scripts of this project print most of their messages in German. This page quotes them exactly and
  gives the English meaning. `preflight.sh` prints English or German; this page quotes the English text.
- The admin page is in German. Names of tabs, buttons and badges stand in `code`, with an English meaning at the first use, for
  example the tab `Übersicht` (overview). The list is in the [glossary](glossary.md#screen-labels).
- Messages of other programs (nginx, Docker, oauth2-proxy, the identity provider) can differ with the version. This page calls
  such a message "typical" when it was not run for this page.

- [1. Find your symptom](#symptom-index)
- [2. Where the logs are](#log-locations)
- [3. Install, packages and helper service](#trouble-install)
- [4. Front door (nginx)](#trouble-front-door)
- [5. Login](#trouble-login)
- [6. Viewer and archive](#trouble-viewer)
- [7. Admin page and audit log](#trouble-admin-page)
- [8. Disk assistant](#trouble-disk)
- [9. Firewall](#trouble-firewall)

<a id="symptom-index"></a>
## 1. Find your symptom

Look for the text that you see. A quoted message is exact. A `...` stands for a part that differs from case to case. The tables
are grouped by the place where you see the problem.

### 1.1 In a terminal, during the install

| What you see | Entry |
|---|---|
| A `[FAIL]` or `[WARN]` line of `preflight.sh` | [3.1](#preflight-fails) |
| `libsqlcipher nicht gefunden` or `SQLCipher library not found` | [3.2](#libsqlcipher-missing) |
| `file is not a database` or `file is encrypted or is not a database` | [3.3](#audit-key-mismatch) |
| `Schluessel in /etc/pacs-protokoll.key ist nicht 64 Hex-Zeichen (kleingeschrieben)` | [3.3](#audit-key-mismatch) |
| `Achtung: Protokoll-Datenbank nicht nutzbar` or `Protokoll nicht abgelegt` in the journal | [3.3](#audit-key-mismatch) |
| The self-test `pacsdb.py test` ends in `AssertionError` | [3.4](#pacsdb-selftest) |
| `getent passwd 101` prints a line, or `Achtung: PACS_SOCKET_UID 101 ist auf dem Host das Konto ...` | [3.5](#uid-101-taken) |
| `/run/pacs-admin/` is empty, or `pacs-verwaltung` is not `active` | [3.6](#no-sockets) |
| `laeuft schon`, `keine Berechtigung`, `ist keine ganze Zahl`, `status=203/EXEC` | [3.6](#no-sockets) |
| `network ... declared as external, but could not be found` | [3.7](#external-network-missing) |
| `docker compose` does not work, or `docker compose: plugin not found` | [3.8](#compose-version) |

### 1.2 The whole site in the browser

| What you see | Entry |
|---|---|
| The browser warns about the certificate (`ERR_CERT_COMMON_NAME_INVALID`, name mismatch, expired) | [3.1](#preflight-fails) |
| The site does not open. `docker ps` shows `Restarting` for the container `ohif` | [4.1](#tls-key-unreadable), [4.2](#nginx-wont-start) |
| `[emerg]` in `docker logs ohif` | [4.2](#nginx-wont-start) |
| Every page answers 500. The log says `could not be resolved` | [4.3](#every-page-500) |
| Every path answers 404 or 502 | [4.3](#every-page-500) |
| The basic login shows 403 or 500 instead of a password prompt | [4.4](#htpasswd-403-500) |
| The audit log shows the address of the proxy for every user | [4.5](#proxy-wrong-address) |

### 1.3 Login

| What you see | Entry |
|---|---|
| `AADSTS50011` on the Microsoft sign-in page | [5.1](#login-redirect-uri-mismatch) |
| `AADSTS7000215` or `AADSTS7000222` | [5.2](#login-client-secret) |
| No jump to the sign-in page, or the container `ohif-auth` is not `Up` | [5.3](#login-oauth2-proxy-down) |
| The browser jumps between the PACS and the login page again and again | [5.4](#login-loop) |
| The page "Forbidden" or a 403 right after the sign-in, at the viewer | [5.5](#viewer-403-after-login) |
| A 403 at `/admin/` for an account that should be an admin | [5.6](#admin-403) |
| A 500 at `/admin/` | [5.7](#admin-500) |
| `Sitzung abgelaufen, Seite neu laden (F5)` | [5.8](#session-expired) |
| The basic login asks again and again, or answers 401 | [5.9](#basic-login-401) |
| Login `none`: 403 for everybody | [5.10](#none-403) |

### 1.4 Viewer and archive

| What you see | Entry |
|---|---|
| The viewer opens, but the study list is empty | [6.1](#viewer-no-studies) |
| The dcm4chee user interface answers 404 | [6.2](#dcm4chee-ui-404) |
| An upload in the dcm4chee user interface fails | [6.3](#dcm4chee-ui-upload) |
| `arc` stays down after the change of the compose file | [6.4](#arc-rslave-refused) |
| `absender_sammeln: ... No such file or directory` in the journal | [6.5](#arc-log-dir) |

### 1.5 Admin page and audit log

| What you see | Entry |
|---|---|
| The line `Kein Status vorhanden (dashboard-status.py läuft per cron alle 5 Minuten).` under the title of the tab `Übersicht` | [7.2](#cron-not-running) |
| A line that starts with `dashboard-status.py:` in `/var/log/pacs-dashboard.log`, or after `Nach neuen Platten suchen:` | [7.2](#cron-not-running) |
| The tile `Speicher` says `Keine Daten zu den Platten (...)`, or the tile `Dienste` is missing | [7.2](#cron-not-running) |
| `abgelehnt (HTTP 502)` or `Fehler: Protokoll: HTTP 502` | [7.1](#admin-dienst-502) |
| `Protokoll: HTTP 503` | [3.3](#audit-key-mismatch) |
| The tab `Protokoll` misses lines that you expect | [7.3](#audit-lines-missing) |
| The times in the tab `Protokoll` differ from your clock | [7.4](#audit-timezone) |
| `Sitzung abgelaufen, Seite neu laden (F5)` | [5.8](#session-expired) |

### 1.6 Disk assistant

| What you see | Entry |
|---|---|
| A red box `Abgebrochen` with a line that starts with `HALT:`, or `nicht ausgeführt, siehe Log von pacs-storage.sh` | [8.1](#disk-halt) |
| `HALT: /etc/default/pacs-admin hat einen Syntaxfehler (Meldung davor)`, or `HALT: NAME='wert' ist keine ganze Zahl ohne fuehrende Null mit hoechstens 6 Stellen (/etc/default/pacs-admin)` | [8.1](#disk-halt) |
| `HALT: laeuft schon, ...` or `Es wird gerade schon eine Platte eingerichtet.` | [8.1](#disk-halt) |
| `Die Platte ist nicht mehr genau so als leer erkannt. Bitte neu suchen.` | [8.1](#disk-halt), [8.2](#disk-not-offered) |
| The tile `Neue Festplatte` says `Keine leere Platte gefunden.` | [8.2](#disk-not-offered) |
| The tile `Speicher` says `Schreibliste nicht lesbar (LDAP-Container und pacs-storage.sh kandidaten prüfen).` | [8.2](#disk-not-offered), [7.2](#cron-not-running) |
| A disk action stopped half way | [8.3](#disk-half-done) |
| The yellow box `Archiv nicht neu geladen`, or `Archiv-Konfiguration nicht neu geladen ... (HTTP 500)` | [8.3](#disk-half-done) |
| `pacs-storage.sh antwortet nicht (nach 300 s abgebrochen), Zustand pruefen (HTTP 504)` | [8.3](#disk-half-done) |
| The badge `nicht eingehängt, bitte prüfen`, or `nicht gemountet` | [8.4](#disk-not-mounted) |

### 1.7 Firewall

| What you see | Entry |
|---|---|
| You cannot reach the server any more after you saved rules | [9.1](#firewall-lockout-brake) |
| The badge `nicht wirksam` | [9.2](#firewall-not-effective) |
| The badge `IPv6 nicht gefiltert`, or the line `N Ports über IPv6 nicht gefiltert` | [9.3](#ipv6-not-filtered) |
| A message like `iptables nicht gefunden: ...`, or `Firewall laden: Firewall: ... (HTTP 500)` | [9.4](#firewall-tools-missing) |
| `Firewall speichern: ... (HTTP 400)`, or a message with `FW_DEFAULT_RULES` or `firewall.json` | [9.5](#firewall-save-failed) |
| `Nicht übernommen, die vorigen Regeln gelten weiter: ...` | [9.5](#firewall-save-failed) |
| `Port 443: dein PC (...) wäre danach selbst ausgesperrt. Erst ihn oder sein Netz eintragen.` | [9.5](#firewall-save-failed) |
| `firewall.py start: Schnittstelle unbekannt: FW_INTERFACE in /etc/default/pacs-admin setzen` | [9.2](#firewall-not-effective) |

<a id="log-locations"></a>
## 2. Where the logs are

Most entries ask you to read a log. This table lists the logs and the command for each one. The container names `ohif`,
`ohif-auth` and `arc` are the names in the example files. If your names differ, list them with `docker ps --format '{{.Names}}'`.

| Log | Command | What it holds |
|---|---|---|
| Helper service | `journalctl -u pacs-verwaltung -n 50 --no-pager` | Start errors, warnings, the ready line and the retry lines of the audit log. |
| Firewall unit | `journalctl -u pacs-firewall -n 50 --no-pager` | Start and stop of the firewall rules, at boot and later. |
| Overview job | `tail -n 20 /var/log/pacs-dashboard.log` | Error output of `dashboard-status.py`. The file stays empty while all is well. |
| Cron | `journalctl -u cron -n 50 --no-pager` | Whether cron started the overview job. |
| Disk assistant | `tail -n 50 /var/log/pacs-storage.log` | The complete output of every run of `pacs-storage.sh`. The file name is the setting `STORAGE_LOG`. |
| Front door | `docker logs --tail 50 ohif` | Start errors (`[emerg]`), `[error]` lines and the lines about the audit log (`to syslog`). |
| nginx test | `docker exec ohif nginx -t` | A syntax test of the nginx configuration. The container must run. |
| Login proxy | `docker logs --tail 50 ohif-auth` | The result of every sign-in. |
| dcm4chee | `docker logs --tail 50 arc` | The start of WildFly and its errors. |
| Firewall rejects | `journalctl -k --grep=pacs-sperre` | Kernel lines with the prefix `pacs-sperre PORT:`. Only the current boot. |
| Services | `systemctl status pacs-verwaltung pacs-firewall --no-pager` | The state of both units. |

The file `server.log` of dcm4chee lies in the folder named by the setting `ARC_LOG_DIR` in `/etc/default/pacs-admin`. The default
is `/var/local/dcm4chee-arc/wildfly/log/`. The admin page reads the sender lists from this file.

The audit log is an encrypted database. Read it with the program that wrote it:

```bash
set -a; . /etc/default/pacs-admin; set +a
python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse
```

The first line loads your settings, so that `PROTOKOLL_DB` and `PROTOKOLL_KEY` apply when you changed them. The program prints
nothing for an empty database. The sources are `zugriffe` (access), `ereignisse` (events) and `admin`
([reference.md](reference.md#audit-read)).

<a id="trouble-install"></a>
## 3. Install, packages and helper service

This chapter covers the base install ([install.md](install.md)): the preflight check, the packages, the audit key, the
[helper service](glossary.md#helper-service) and the Docker prerequisites.

<a id="preflight-fails"></a>
### 3.1 The preflight check reports [FAIL] or [WARN]

**What you see.** `preflight.sh` ([install.md](install.md#preflight)) ends with `NOT READY: fix the [FAIL] lines first` or with
`READY, with warnings: read the [WARN] lines`.

**Cause.** The script found something on the server that the install needs and does not find, or something that looks wrong.
The script only reads. It changes nothing on the server.

**How to read the output.** The script prints one line per check. `[ OK ]` needs nothing. `[WARN]` needs your attention.
`[FAIL]` stops the install: fix it first. Under a `[WARN]` or `[FAIL]` line you find one sentence that says what the line
means, and a line that starts with `Fix:`. The exit code is 0 (all ok), 1 (warnings only) or 2 (at least one failure). The
block "My values" at the end is not a problem report: it lists names and paths that later steps need.

**Fix.** Run the script as root. Add the options that fit your install, so that it checks more:

```bash
bash /opt/pacs-admin/deploy/tools/preflight.sh --lang en --host pacs.example.org
```

| Option | What it checks in addition |
|---|---|
| `--host NAME` | That the DNS name resolves, and to an address of this server. |
| `--cert FILE --key FILE` | The TLS certificate and its key: match, expiry, chain order, name, rights of the key. |
| `--dir /opt/ohif` | The folder of the front door: placeholders left in the files, the nginx files, the mounts and the `env_file` entries of the compose file. |
| `--lang en` or `--lang de` | The language of the output. The default follows the setting `LANG`. |

The script groups the checks in sections: `System and packages`, `Docker and dcm4chee`, `Host settings`, then `TLS certificate`
(with `--cert` and `--key`) and `Configuration files` (with `--dir`, or when `/etc/default/pacs-admin` exists). The section
numbers depend on the options that you give. Find your line in the tables, do what the right column says, and run the script
again. Run it again after every fix.

**Section "System and packages"**

| The line starts with | What to do |
|---|---|
| `[WARN] not root` | Run the script as root. As another user it cannot check Docker, `iptables` and the files of root. |
| `[WARN] repository: ... not /opt/pacs-admin` | The systemd units and the cron file start the programs from `/opt/pacs-admin`. Clone the repository to this folder, or change the path in the copied files ([3.6](#no-sockets) shows the command). |
| `[WARN] systemctl exists, but systemd is not running (container?)`, `[WARN] systemctl not found` | The helper service and the firewall are systemd units. Run the install on a normal Debian server or virtual machine. |
| `[WARN] /etc/os-release not readable`, `[WARN] operating system ... not tested` | The guide is tested on Debian 12 and 13. Ubuntu uses the same packages, but nobody has verified it. Go on, and fix what the other lines report. |
| `[FAIL] SQLCipher: package ... fits this system, not installed yet`, `[FAIL] SQLCipher: no libsqlcipher package found in apt`, `[WARN] SQLCipher: apt-cache not found` | See [3.2](#libsqlcipher-missing). |
| `[FAIL] python3: /usr/bin/python3 ... is too old` | The server programs need Python 3.7 or newer. Debian 12 and 13 have it. |
| `[FAIL] python3: /usr/bin/python3 not found (only /usr/local/bin/python3)` | The systemd units start exactly `/usr/bin/python3`. A Python in `/usr/local/bin` does not count. Install the Debian package: `apt-get install -y python3`. |
| `[FAIL] git not found`, `curl`, `openssl` or `ip` | Install the package named in the `Fix:` line. The command `ip` is in the package `iproute2`. |
| `[FAIL] cron: installed, but not running`, `[FAIL] cron not found` | See [7.2](#cron-not-running). |
| `[WARN] iptables not found`, `[WARN] journalctl not found` | Only the tab `Firewall` needs them. See [9.4](#firewall-tools-missing). |
| `[WARN] disk assistant tools missing: ...` | Only the optional disk assistant needs them. Install the packages in the `Fix:` line before you use it. |

**Section "Docker and dcm4chee"**

| The line starts with | What to do |
|---|---|
| `[FAIL] docker not found` | dcm4chee, nginx and the login proxy run as Docker containers. Install Docker. The `Fix:` line names the Debian package and the Docker documentation. |
| `[FAIL] docker: installed, but the daemon did not answer within 15 seconds`, `[FAIL] docker: installed, but the daemon does not answer`, `[WARN] docker: no permission to talk to the Docker daemon` | Start Docker (`systemctl start docker`), check that `DOCKER_HOST` points to this server, and run the script as root. The script skips the checks of dcm4chee until Docker answers. |
| `[WARN] docker compose: only the old docker-compose command exists`, `[FAIL] docker compose: plugin not found` | See [3.8](#compose-version). |
| `[FAIL] no dcm4chee archive container found` | The script looks for an image named `dcm4che/dcm4chee-arc-psql`. List your containers with `docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.State}}'`. |
| `[FAIL] arc: NAME (IMAGE)` with `-secure` in the image name | The variant with its own Keycloak login is not supported. The panel needs the normal image `dcm4che/dcm4chee-arc-psql`. |
| `[WARN] arc: NAME (IMAGE, exited)` | The archive container does not run. Start it: `docker start arc`. |
| `[WARN] more than one archive container` | One panel talks to one archive. The script uses the first container for the values it prints. |
| `[WARN] ARC_CONTAINER is 'X', but the archive container is called 'Y'`, `[WARN] LDAP_CONTAINER is ...` | Put the real name in `/etc/default/pacs-admin`. The `Fix:` line gives the command. Then run `systemctl restart pacs-verwaltung`. |
| `[WARN] compose project directory of arc: unknown ...`, `[WARN] compose project directory of arc ... does not exist on this host` | Set `PACS_DIR` in `/etc/default/pacs-admin` to the folder that holds the `docker-compose.yml` of dcm4chee. The tile `Dienste` (services) uses it. |
| `[WARN] Docker network of arc: not found`, `[WARN] Docker network of arc: bridge (the default network)` | See [3.7](#external-network-missing). |
| `[WARN] wildfly log directory: arc has no host mount for /opt/wildfly/standalone` | The tab `Firewall` reads the sender lists from `server.log` on the server. Without a mount the lists stay empty. See [6.5](#arc-log-dir). |
| `[WARN] wildfly log directory ... ARC_LOG_DIR` | The setting `ARC_LOG_DIR` names another folder than the one that `arc` uses. See [6.5](#arc-log-dir). |
| `[WARN] neither LDAP_ROOTPASS nor LDAP_ROOTPASS_FILE is set in container ldap` | Only the disk assistant needs the password. Add it as edit C in [modules.md](modules.md#edits-overview). |
| `[WARN] no LDAP container found`, `[WARN] ldap: NAME (IMAGE, exited)` | Only the disk assistant needs LDAP. |
| `[WARN] no database container found` | Information only. |

**Section "Host settings"**

| The line starts with | What to do |
|---|---|
| `[WARN] /mnt/fs does not exist` | Only the disk assistant needs it. The archive can keep its data somewhere else. |
| `[WARN] N mount(s) under /mnt/fs, none named PACS-DataNN` | The disk assistant and the tile `Speicher` (storage) know only disks that are named like the setting `STORAGE_PREFIX` followed by two digits. |
| `[WARN] mount propagation of /mnt/fs: private` | Only the disk assistant needs a shared mount. See [6.4](#arc-rslave-refused). |
| `[WARN] uid 101 belongs to the account '...' on this host` | See [3.5](#uid-101-taken). |
| `[WARN] port 80 is already in use`, `[WARN] port 443 is already in use` | nginx cannot publish a port that another program holds. Find the holder with `ss -ltnp`. The warning is harmless when the holder is the front door of this panel itself (a second run after the install). |
| `[WARN] no default route found` | `firewall.py` needs the network interface to the outside. Set `FW_INTERFACE` in `/etc/default/pacs-admin` ([9.2](#firewall-not-effective)). |
| `[WARN] /etc/localtime is missing` | The compose files mount the file into the containers. Set the time zone: `timedatectl set-timezone Europe/Berlin` (use your own Area/City). |
| `[FAIL] DNS: pacs.example.org does not resolve` | Browsers, the login redirect and the certificate need the name. Create the DNS record. For a test, add a line to `/etc/hosts`. |
| `[WARN] DNS: ... not an address of this host` | Fine behind NAT, a load balancer or a front proxy. Otherwise the users reach another machine. |

**Section "TLS certificate"** (with `--cert` and `--key`)

| The line starts with | What to do |
|---|---|
| `[FAIL] private key (...) cannot be read by the nginx of the OHIF image`, `[WARN] private key is readable by everybody`, `[WARN] private key is readable by its group` | See [4.1](#tls-key-unreadable). |
| `[FAIL] certificate: not a readable file`, `[FAIL] key file: not a readable file` | Run the script as root. Keys and certificates are often readable by root only. |
| `[FAIL] certificate: not a PEM certificate` | nginx wants [PEM](glossary.md#pem) text that starts with `-----BEGIN CERTIFICATE-----`. Convert a binary `.crt` or `.cer` file: `openssl x509 -inform der -in FILE -out cert.pem`. |
| `[FAIL] certificate expired`, `[WARN] certificate expires soon` | Browsers and API clients refuse an expired certificate. Renew it ([install.md](install.md#renew-certificate)). |
| `[FAIL] certificate does NOT cover pacs.example.org` | Browsers show a name mismatch. The line names the names in the first certificate of the file. Get a certificate for your name. |
| `[WARN] certificate matches ... only by its common name: no subjectAltName`, `[WARN] certificate has no subjectAltName` | Current browsers refuse a certificate without a [subjectAltName](glossary.md#subject-alt-name) and show `ERR_CERT_COMMON_NAME_INVALID`. A self-signed certificate needs it too. Create the certificate with the name in `subjectAltName`. |
| `[WARN] chain: the N certificates are not in order` | nginx sends the file as it is. Put the server certificate first, then the intermediate certificates. Rebuild the file: `cat server.pem intermediate.pem > fullchain.pem`. |
| `[WARN] chain: the file holds only the server certificate` | If your CA uses an [intermediate certificate](glossary.md#intermediate-certificate), append it behind the server certificate. Without it some clients cannot verify the chain. |
| `[WARN] self-signed certificate` | Browsers warn about it, and some login providers refuse it. It is fine for a test. |
| `[FAIL] private key is protected by a passphrase` | nginx cannot ask for a passphrase when it starts. Remove it: `openssl pkey -in KEY -out key-plain.pem`, then `chmod 600 key-plain.pem`. |
| `[FAIL] private key: cannot be parsed` | nginx expects an unencrypted key in PEM form. |
| `[FAIL] key does NOT match the certificate` | nginx refuses to start with such a pair. Use the key that belongs to the certificate request. |
| `[FAIL] key does not match the first certificate, but certificate no. N of the file` | The server certificate must be the first one in the file. Reorder the file. |

**Section "Configuration files"**

| The line starts with | What to do |
|---|---|
| `[FAIL] /etc/default/pacs-admin: problems: ...` | The shell (cron, scripts) and systemd read the file and disagree on comments, spaces and Windows line endings. Write one `NAME=value` per line, no `export`, and quote a value that holds a space. The `Fix:` line removes Windows line endings. A syntax error stops the cron job (the message goes to `/var/log/pacs-dashboard.log`, [7.2](#cron-not-running)). `pacs-storage.sh` runs `bash -n` on the file first and stops with `HALT: /etc/default/pacs-admin hat einen Syntaxfehler (Meldung davor)` ([8.1](#disk-halt)). See [reference.md](reference.md#env-file-rules). |
| `[FAIL] FILE: ... CHANGE-ME` or a `<placeholder>` | A value was never filled in. `CHANGE-ME` marks every value that you must change. Delete the marker comment after you set the value. |
| `[WARN] FILE: example value(s) still there:` | Probably a copied example value, for example `pacs.example.org`, that you did not replace with your own name or id. |
| `[WARN] ... no nginx, compose, env or js files found` | Wrong folder. The layout is `/opt/ohif` with `docker-compose.yml`, `nginx/`, `tls/`, `htpasswd/`, `ohif-auth.env` and `app-config.js`. |
| `[WARN] no nginx tree found (nginx/pacs.conf)`, `[FAIL] nginx tree: files missing: ...` | See [4.2](#nginx-wont-start). |
| `[FAIL] mount SRC -> DST: the nginx user (uid 101) cannot read N of its files or folders` | Files made under a strict `umask` (027 or 077) belong to root alone. Then the container does not start, or the page answers with an error. Run the command in the `Fix:` line. It is `chmod -R o+rX FOLDER`, and for the TLS folder `chmod 755 FOLDER && chmod 644 FOLDER/server.crt`. |
| `[FAIL] .../htpasswd/users: owner root:root, mode 600: the nginx worker (uid 101) cannot read it`, `[WARN] ... every account of this host can read the password hashes` | See [4.4](#htpasswd-403-500). |
| `[WARN] mount source ... does not exist (for ...)` | `docker compose` would create an empty folder with that name, owned by root. The service behind the mount then does not work. Create the file, or correct the path in the compose file. |
| `[FAIL] mount SRC -> DST is incomplete, missing: ...` | The container would start without that content or fail at once. Every request would end in an error. Copy the missing parts ([install.md](install.md#nginx-files)). |
| `[FAIL] env_file ... does not exist (or is a folder)` | `docker compose` does not start without it. The compose file says at its top what the file holds. |
| `[FAIL] ... missing: ...` or `empty: ...` for `ohif-auth.env` | `oauth2-proxy` does not start without its client ID, client secret and cookie secret. Write one `NAME=value` line each, with no spaces around `=` ([login.md](login.md#login-oauth2-env)). |
| `[WARN] ...env: mode M: other accounts of this host can read it` | The file holds secrets (client secret, cookie secret). Run `chmod 600` on it. |

> **Check**
>
> ```bash
> bash /opt/pacs-admin/deploy/tools/preflight.sh --lang en --host pacs.example.org | tail -n 4
> echo "exit code: ${PIPESTATUS[0]}"
> ```
>
> Expected: the summary reads `Result: ... 0 failure(s)` and one of `READY: all checks passed` or
> `READY, with warnings: read the [WARN] lines`. The exit code is 0 or 1. Example (the numbers differ):
>
> ```text
> Result: 30 ok, 1 warning(s), 0 failure(s)
> READY, with warnings: read the [WARN] lines
> exit code: 1
> ```
>
> The last lines of the real output also name the options that you did not give. If a `[FAIL]` line stays, work through its
> row above again.

<a id="libsqlcipher-missing"></a>
### 3.2 The SQLCipher library is missing

**What you see.** One of these:

- A tool prints this line and stops with exit status 1. A tool that you start by hand prints it after its own name, here
  `pacsdb.py:`.

```text
pacsdb.py: libsqlcipher nicht gefunden. Debian 13: apt install libsqlcipher1, Debian 12 und aelter: apt install libsqlcipher0 (Release: cat /etc/os-release, Paketname: apt-cache search sqlcipher; docs/install.de.md#audit-key). SQLCipher library not found: install libsqlcipher1 (Debian 13) or libsqlcipher0 (Debian 12 and older)
```

- The helper service prints the same text after `verwaltung-dienst.py:` in its journal. It stops, and systemd starts it again
  every 5 seconds. The sockets in `/run/pacs-admin/` do not stay, and the admin page answers 502 for `/admin/dienst/`.
- `preflight.sh` prints `[FAIL] SQLCipher: package libsqlcipher1 (VERSION) fits this system, not installed yet`.

**Cause.** The [audit log](glossary.md#audit-log) lives in an encrypted database. [SQLCipher](glossary.md#sqlcipher) is the
library that encrypts it. The programs `verwaltung-dienst.py` and `pacsdb.py` load it at start. The Debian package has a
different name per release.

**Fix.** Find out your release, look at the package names, and install the one that fits:

```bash
. /etc/os-release; echo "$PRETTY_NAME"
apt-cache search sqlcipher
```

Debian 13 uses `libsqlcipher1`. Debian 12 and older use `libsqlcipher0`.

```bash
apt-get install -y libsqlcipher1
systemctl restart pacs-verwaltung
```

Write `libsqlcipher0` instead of `libsqlcipher1` on Debian 12. If `apt-cache search` finds no package, run `apt-get update` first.

> **Check**
>
> ```bash
> python3 /opt/pacs-admin/server/pacsdb.py test
> systemctl is-active pacs-verwaltung
> ```
>
> Expected: the self-test line starts with `Selbsttest ok` (self-test passed), and the service is `active`. Example output on
> Debian 13 (the version differs):
>
> ```text
> Selbsttest ok: schreiben, lesen, Datei ohne Klartext, falscher Schluessel und fremde Datei abgewiesen, Format 3 (Seitengroesse 1024) und Bibliotheksstandard (4096) lesbar, SQLCipher 4.6.1 community
> active
> ```
>
> If the self-test still fails, see [3.4](#pacsdb-selftest).

<a id="audit-key-mismatch"></a>
### 3.3 The audit key or the audit database does not fit

**What you see.** A tool that you start by hand prints one of these lines and stops with exit status 1. The text after
`pacsdb.py:` is the message.

| Message | What it means |
|---|---|
| `/var/lib/pacs-protokoll/protokoll.db: file is not a database. Schluessel falsch, keine SQLCipher-Datei oder eine Datei im Format von SQLCipher 4, die libsqlcipher 3.x nicht oeffnet (hier SQLCipher 3.4.1), siehe docs/install.de.md#audit-key` | The database does not open with this key and this library. On SQLCipher 3.x the first part reads `file is encrypted or is not a database`. |
| `Schluessel in /etc/pacs-protokoll.key ist nicht 64 Hex-Zeichen (kleingeschrieben)` | The key file does not hold exactly 64 characters from `0` to `9` and `a` to `f`. |
| `[Errno 2] No such file or directory: '/etc/pacs-protokoll.key'` | The key file is missing, or the setting `PROTOKOLL_KEY` names another path. |
| `[Errno 13] Permission denied: '/etc/pacs-protokoll.key'` | You are not root. Only root may read the key. |

The helper service keeps running when the database is not usable. It holds the lines that nginx sends in memory and tries again
every 10 seconds. The journal shows these two lines. `<error>` stands for one of the messages above.

```text
Achtung: Protokoll-Datenbank nicht nutzbar, die Zeilen von nginx werden zurueckgehalten und alle 10 s neu abgelegt: <error>
Protokoll nicht abgelegt (5 Zeilen), neuer Versuch in 10 s: <error>
```

The first line means "Attention: audit database not usable, the lines from nginx are held back and stored again every 10
seconds". The second line means "audit lines not stored (5 lines), new try in 10 s". While the database is not usable, the tab
`Protokoll` shows `Protokoll: HTTP 503`.

**Cause.** One of these:

1. The key file was replaced or lost. A second run of `openssl rand` writes a new key, a restore of `/etc` can miss the file,
   and a copy from another server brings another key. The database is encrypted with the old key.
2. The key file has the wrong form. The programs ignore white space and line breaks at both ends. They refuse a key with upper
   case letters, other characters or another length.
3. The database file is in the SQLCipher 4 format, and this server has `libsqlcipher` 3.x (Debian 12). This happens when you
   restore a file from a Debian 13 server, or when you go back to an older release. New files use the format 3, which both
   versions open. An upgrade from Debian 12 to Debian 13 keeps working. There is no converter between the formats.
4. The file is not a SQLCipher database, or it is damaged.

**Fix.** Look at the key file first. Load your settings, so that the commands use your paths:

```bash
set -a; . /etc/default/pacs-admin; set +a
ls -l /etc/pacs-protokoll.key
grep -Eq '^[0-9a-f]{64}$' /etc/pacs-protokoll.key && echo key ok
```

The file should have 65 bytes, the owner `root` and the mode `-rw-------`. `key ok` should print. A key that was edited on
Windows can end in a carriage return. The programs accept it, but the `grep` test does not. Remove it with
`sed -i 's/\r$//' /etc/pacs-protokoll.key`.

Then choose the case that fits:

- **You have a backup of the key** ([install.md](install.md#backup-audit-key)). Put it back. The helper service finds the
  right key at its next try, within 10 seconds, without a restart. It then stores the lines that it held.

  ```bash
  (umask 077; cat /path/to/saved-key > /etc/pacs-protokoll.key)
  ```

- **The file is in the format 4 and this server has `libsqlcipher` 3.x.** Read the file on a server with Debian 13. Copy the
  file and the key there, and run:

  ```bash
  PROTOKOLL_DB=/path/to/protokoll.db PROTOKOLL_KEY=/path/to/key python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse
  ```

  For this server you need a new database ([start new files](#audit-key-new), below).

- <a id="audit-key-new"></a>**The key is lost and there is no backup.** Nobody can read the old events. Keep the old files, and
  start new ones with a new key. Do the three commands in this order, so that the helper service never writes new lines into the
  old file with the wrong key:

  ```bash
  mkdir -p /root/protokoll-alt
  mv /etc/pacs-protokoll.key /root/protokoll-alt/pacs-protokoll.key
  (umask 077; openssl rand -hex 32 > /etc/pacs-protokoll.key)
  mv /var/lib/pacs-protokoll/protokoll.db* /root/protokoll-alt/
  ```

  The `*` moves the database and its helper files `protokoll.db-wal` and `protokoll.db-shm`. At its next try the helper service
  creates a new database with the new key and stores the held lines in it.

> **Warning**
>
> The old events stay in `/root/protokoll-alt`. Nobody can read them without the key that belongs to them, so keep the folder.
> Do not restart `pacs-verwaltung` while it holds lines: a restart drops them. The new key needs a backup at once
> ([install.md](install.md#backup-audit-key)). To go back, move the old key and the old files back to their places. The lines
> that the new database holds are lost then, so copy the new files away first.

> **Check**
>
> ```bash
> set -a; . /etc/default/pacs-admin; set +a
> grep -Eq '^[0-9a-f]{64}$' /etc/pacs-protokoll.key && echo key ok
> python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse > /dev/null && echo "key and database ok"
> journalctl -u pacs-verwaltung -n 5 --no-pager
> ```
>
> Expected: `key ok` and `key and database ok`. The journal shows no new line `Protokoll nicht abgelegt`. The program prints
> nothing for an empty database. If `PROTOKOLL_DB` names a wrong path, the program creates a new empty database there and says
> `key and database ok` too. So check the path in your settings file as well.

<a id="pacsdb-selftest"></a>
### 3.4 The self-test of pacsdb.py fails

**What you see.** `python3 /opt/pacs-admin/server/pacsdb.py test` does not print a line that starts with `Selbsttest ok`. It
prints a Python traceback instead. The last line names the error.

**What the self-test is.** It writes a throw-away database with a throw-away key in a temporary folder. It reads the data back and
checks that the library really encrypts, rejects a wrong key and a foreign file, and opens the formats 3 and 4. It never
touches your key file or your database. So it tells you about the library, not about your key. For your key see
[3.3](#audit-key-mismatch).

**Cause and fix.** Read the last line of the traceback:

| Last line | Cause and fix |
|---|---|
| `AssertionError: Datei nicht verschluesselt` | The file shows the text of the data, or the header of a plain SQLite file. The library ignores the key, so it is not SQLCipher. Install the Debian package again (`apt-get install --reinstall libsqlcipher1`, on Debian 12 `libsqlcipher0`) and remove a self-built library of that name. |
| `AssertionError: falscher Schluessel oder fremde Datei wurde angenommen: ...` | The library opened a file with a wrong key. It does not encrypt, the same cause as the row above. |
| `AssertionError: Format 3 und Format 4 lassen sich nicht unterscheiden` | The library does not tell the two file formats apart, as SQLCipher 4 does. Use the Debian package of your release. |
| `AssertionError: ungueltiger Schluessel wurde angenommen` | The program accepted a key that is not 64 hex characters. The file `pacsdb.py` was changed or is damaged. Compare it with the repository: `git -C /opt/pacs-admin status`. |
| `AssertionError` without text, or with two numbers in brackets | The library behaves in a way that this page does not know. Keep the whole output and the output of `apt-cache policy libsqlcipher1 libsqlcipher0`, and report them. |
| `PermissionError` or `OSError` with a path in `/tmp` | The program cannot create its temporary folder. Check the free space and the rights of `/tmp`. |

> **Check**
>
> ```bash
> python3 /opt/pacs-admin/server/pacsdb.py test
> ```
>
> Expected: one line that starts with `Selbsttest ok`. Example on Debian 12 (the end of the line differs by version):
>
> ```text
> Selbsttest ok: schreiben, lesen, Datei ohne Klartext, falscher Schluessel und fremde Datei abgewiesen, Format 3 (Seitengroesse 1024) und Bibliotheksstandard (1024) lesbar, SQLCipher 3.4.1
> ```
>
> The line ends with `SQLCipher 4.6.1 community` on Debian 13, and the number in the second brackets is `4096` there.

<a id="uid-101-taken"></a>
### 3.5 An account on the server has the uid 101

**What you see.** One of these:

- `getent passwd 101` or `getent group 101` prints a line. The install guide expects no output ([install.md](install.md#helper-service)).
- The journal of the helper service holds this warning. The service still starts.

  ```text
  Achtung: PACS_SOCKET_UID 101 ist auf dem Host das Konto <name>. Jeder Prozess dieses Kontos kann das Protokoll lesen und die Firewall aendern. Ist das nicht nginx, siehe docs/install.de.md#helper-service.
  ```

- `preflight.sh` prints `[WARN] uid 101 belongs to the account '<name>' on this host`.

**Cause.** nginx in the container runs its worker processes as the [uid](glossary.md#uid) 101. The helper service gives its two
[unix sockets](glossary.md#unix-socket) to this uid, so that nginx can use them. Mode 0600 and the uid are the only protection
of the service. Every process with that uid can use it as root: read the audit log, switch the firewall off and set up disks.
On the server, the uid 101 can belong to another account. On Debian 12 it is often a system account such as `messagebus`.
The warning above tells you that this is the case. It does not stop the service.

**Fix.** First see which account it is and whether it runs programs:

```bash
getent passwd 101
ps -u 101 -o pid,user,comm
```

Then decide:

1. **A plain system account.** Nobody logs in as it, and no program of other people runs under it. The risk is small. Accept
   the warning and change nothing.
2. **Other programs run under the account.** Keep them away from the account, or move the account to another uid with your
   usual tools. The helper service gives the sockets to `PACS_SOCKET_UID`. Set `PACS_SOCKET_UID` to a different value only
   when the nginx worker processes really use that uid. For nginx on the server itself (Debian) the uid is 33 (`www-data`)
   ([reference.md](reference.md#permissions)). A wrong uid gives a 502 on `/admin/dienst/`.

After you changed `PACS_SOCKET_UID` in `/etc/default/pacs-admin`, restart the service:

```bash
systemctl restart pacs-verwaltung
```

> **Check**
>
> ```bash
> ls -ln /run/pacs-admin/
> ```
>
> Expected: two sockets. The third column shows the uid that you chose, for example `101`. Example:
>
> ```text
> total 0
> srw------- 1 101 0 0 Oct 13 14:50 protokoll.sock
> srw------- 1 101 0 0 Oct 13 14:50 verwaltung.sock
> ```
>
> The `ls -l` form shows the same two lines with the account name and group name instead of the numbers.

<a id="no-sockets"></a>
### 3.6 The helper service does not start, or the folder /run/pacs-admin is empty

**What you see.** `systemctl is-active pacs-verwaltung` does not print `active`, or `ls -l /run/pacs-admin/` shows no sockets.
The admin page answers 502 at `/admin/dienst/` ([7.1](#admin-dienst-502)).

**Cause.** The service stops at start and says why in one line of its journal. Read the journal:

```bash
journalctl -u pacs-verwaltung -n 30 --no-pager
```

Each line starts with the program name `verwaltung-dienst.py:`. The text after it tells the cause:

| Message | Cause and fix |
|---|---|
| `libsqlcipher nicht gefunden. ...` | See [3.2](#libsqlcipher-missing). |
| `PACS_SOCKET_UID=abc ist keine ganze Zahl ohne fuehrende Null mit hoechstens 10 Stellen (/etc/default/pacs-admin)` | The helper service reads one number at start: `PACS_SOCKET_UID`. The value must be a whole number without a leading zero and with at most 10 digits. Correct the line in `/etc/default/pacs-admin` ([reference.md](reference.md#env-file-rules)). |
| `PACS_SOCKET_UID=N ist keine gueltige uid (/etc/default/pacs-admin)` | The uid must be a whole number from 0 to 4294967294. |
| `NAME=path ist zu lang (N Bytes, Unix-Sockets erlauben hoechstens 107)` | The path of a socket is longer than 107 bytes. Use a shorter path. |
| `laeuft schon, auf PATH lauscht ein Dienst (systemctl status pacs-verwaltung). Nicht von Hand starten, solange der Dienst laeuft.` | A second copy of the program runs, started by the unit or by hand. Do not start it by hand while the unit runs. Find the copy with `pgrep -af verwaltung-dienst.py` and stop the one that the unit did not start. |
| `keine Berechtigung (...). Der Dienst muss als root laufen (pacs-verwaltung.service).` | The program does not run as root. Start it with `systemctl start pacs-verwaltung`, not from your shell as another user. |
| `Socket nicht anlegbar: ...` | The program cannot create the socket file. The text after the colon names the reason, for example a read-only file system. |

The three storage numbers `STORAGE_MIN_GB`, `STORAGE_FREE_GB` and `STORAGE_WARN_GB` do not stop the helper service. Each takes
a whole number without a leading zero and with at most 6 digits. If one holds something else, `dashboard-status.py` or
`pacs-storage.sh` stops with a message that continues with `ohne fuehrende Null mit hoechstens 6 Stellen`. Example:

```text
dashboard-status.py: STORAGE_WARN_GB=300GB ist keine ganze Zahl ohne fuehrende Null mit hoechstens 6 Stellen (/etc/default/pacs-admin)
```

The disk assistant prints the same text behind `HALT:` ([8.1](#disk-halt)). The cron job writes it to
`/var/log/pacs-dashboard.log` ([7.2](#cron-not-running)).

Two more causes have no such line:

- `systemctl status pacs-verwaltung` shows `status=203/EXEC`. systemd cannot start `/usr/bin/python3`. A Python in
  `/usr/local/bin` does not count. `command -v python3` must print `/usr/bin/python3`. Install the Debian package `python3`.
- The repository lies in another folder than `/opt/pacs-admin`. The units and the cron file name the old path. Python then
  reports that it cannot open the script. Change the path once in the copied files:

  ```bash
  sed -i 's|/opt/pacs-admin|/srv/pacs-admin|g' /etc/systemd/system/pacs-*.service /etc/cron.d/pacs-dashboard
  systemctl daemon-reload && systemctl restart pacs-verwaltung
  ```

  Mount the same folder in the compose file of nginx. Without the change, `systemctl stop pacs-firewall` fails and the emergency
  brake of the firewall does not work ([9.1](#firewall-lockout-brake)).

If the service is `active` and the sockets exist, but nginx still answers 502, the container started before the folder existed.
A container does not see a folder that was created after it started:

```bash
docker restart ohif
```

After a reboot the folder `/run/pacs-admin` is empty until the service has started. This is normal.

> **Check**
>
> ```bash
> systemctl is-active pacs-verwaltung
> ls -l /run/pacs-admin/
> journalctl -u pacs-verwaltung -n 5 --no-pager
> ```
>
> Expected: `active`, two sockets owned by the uid `101` (or your `PACS_SOCKET_UID`) with the mode `srw-------`, and a ready
> line in the journal. The journal line starts with the date, the host and the program name. Example:
>
> ```text
> active
> total 0
> srw------- 1 101 root 0 Oct 13 14:50 protokoll.sock
> srw------- 1 101 root 0 Oct 13 14:50 verwaltung.sock
> pacs-verwaltung bereit: /run/pacs-admin/verwaltung.sock (HTTP) und /run/pacs-admin/protokoll.sock (Protokoll), Besitzer uid 101
> ```

<a id="external-network-missing"></a>
### 3.7 Docker does not find the network of dcm4chee

**What you see.** `docker compose up -d` in the folder of the front door (here `/opt/ohif`) stops with this error. The name is
the one in your compose file.

```text
network dcm4chee-arc_default declared as external, but could not be found
```

`preflight.sh` can warn earlier: `[WARN] Docker network of arc: not found`, or `[WARN] Docker network of arc: bridge (the
default network)`.

**Cause.** The compose file of the front door joins the Docker network of your dcm4chee project. The network is
[external](glossary.md#external-network) for this file: another project owns it. It must exist before nginx starts, and the name
in the compose file must be exact. The reasons are: dcm4chee is not started, the name in the file differs from the real name, or
`docker compose down` in the dcm4chee folder removed the network. If `arc` was started with `docker run`, it sits in the default
network `bridge`. Containers in it do not find each other by name, so nginx cannot find `arc`.

**Fix.** Start dcm4chee, if it is down:

```bash
cd /opt/dcm4chee-arc
docker compose up -d
```

Look up the real name of the network of `arc`:

```bash
docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' arc
```

The command prints the name, or several names separated by a space. Write the name into the compose file of the front door, in
the line that carries the marker `CHANGE-ME`:

```yaml
networks:
  default:
    name: dcm4chee-arc_default   # the name that the command printed
    external: true
```

If `arc` is in the network `bridge`, start dcm4chee through its compose file. The file creates its own network.

> **Check**
>
> ```bash
> cd /opt/ohif
> docker compose up -d
> docker ps --format '{{.Names}}  {{.Status}}' | grep '^ohif'
> ```
>
> Expected: `docker compose up -d` ends without the error, and `ohif` shows `Up`. Example (the time differs):
>
> ```text
> ohif  Up 5 seconds
> ```

<a id="compose-version"></a>
### 3.8 Docker Compose is missing or too old

**What you see.** `preflight.sh` prints `[FAIL] docker compose: plugin not found`, or `[WARN] docker compose: only the old
docker-compose command exists`. Or `docker compose` does not work at all on your server.

**Cause.** The example files and all commands of this guide use the form `docker compose` (with a space). It is the plugin
Compose v2. The old command `docker-compose` (with a hyphen) is Compose v1. It is a separate program, and the guide does not
support it. The Debian package names differ per release.

**Fix.** Install Compose v2:

| Release | What to install |
|---|---|
| Debian 13 | `apt-get install -y docker-compose` (this package is Compose v2) |
| Debian 12 | The package `docker-compose-plugin` from the Docker repository ([Docker documentation for Debian](https://docs.docker.com/engine/install/debian/)). The Debian package `docker-compose` is Compose v1 and does not work. |

> **Check**
>
> ```bash
> docker compose version
> ```
>
> Expected: one line that starts with `Docker Compose version v2`. Example (the version differs):
>
> ```text
> Docker Compose version v2.32.0
> ```
>
> If the line starts with `v1`, or the command is unknown, the old command is still the only one on the server.

<a id="trouble-front-door"></a>
## 4. Front door (nginx)

This chapter covers the nginx container `ohif` and its files ([install.md](install.md#nginx-files)): start errors, the TLS key,
the password files of the basic login and the client address behind a proxy. Problems with the sign-in at an identity provider
are in [chapter 5](#trouble-login).

<a id="tls-key-unreadable"></a>
### 4.1 nginx cannot read the TLS key or the certificate

**What you see.** The site does not open. `docker ps` shows `Restarting` for the container `ohif`. `docker logs --tail 20 ohif`
repeats one of these lines. Each line starts with a date and a time, and the numbers after `[emerg]` differ. A `...` stands for
the end of a long line.

```text
[emerg] 1#1: cannot load certificate key "/etc/nginx/tls/server.key": BIO_new_file() failed (SSL: error:8000000D:system library::Permission denied:calling fopen(/etc/nginx/tls/server.key, r) ...
[emerg] 1#1: cannot load certificate "/etc/nginx/tls/server.crt": BIO_new_file() failed (SSL: error:8000000D:system library::Permission denied:calling fopen(/etc/nginx/tls/server.crt, r) ...
[emerg] 1#1: cannot load certificate "/etc/nginx/tls/server.crt": BIO_new_file() failed (SSL: error:80000002:system library::No such file or directory:calling fopen(/etc/nginx/tls/server.crt, r) error:10000080:BIO routines::no such file)
```

The first line says that nginx may not read the key. The second line says the same for the certificate, or for the folder
`tls/`. The third line says that the file does not exist.

**Cause.** nginx reads the certificate and the key once, when its main process starts. In the OHIF image this process does not
run as root but as the [uid](glossary.md#uid) 101. A key that only root can read stops it. The plain image `nginx:1.30` and
nginx on the server start the main process as root, and root can read every file. The folder `tls/` must be readable too. A file
that does not exist has other reasons: the name is not exactly `server.crt` or `server.key`, or the compose file does not mount
the folder. For a mount source that does not exist, Docker makes an empty folder.

| Image | Recipes | The main process runs as | A key that works | A key that stops nginx |
|---|---|---|---|---|
| OHIF image `ohif/app` | `oauth2`, `basic` | uid 101 | owner `root`, group 101, mode 640 | `root:root` with mode 600 or 640 |
| Plain image `nginx:1.30`, nginx on the server | `adminonly`, nginx on the host | root | `root:root` with mode 600 | none |

**Fix.** Find your image in the compose file. The recipe `oauth2` or `basic` uses `ohif/app`. The recipe `adminonly` uses
`nginx`.

```bash
grep -n 'image:' /opt/ohif/docker-compose.yml
```

For the OHIF image give the key to the group 101:

```bash
chown root:101 /opt/ohif/tls/server.key && chmod 640 /opt/ohif/tls/server.key
```

For the plain image and for nginx on the server keep the key private to root:

```bash
chown root:root /opt/ohif/tls/server.key && chmod 600 /opt/ohif/tls/server.key
```

For every image the folder and the certificate must be readable. A folder with the mode 700 stops the OHIF image as well:

```bash
chmod 755 /opt/ohif/tls && chmod 644 /opt/ohif/tls/server.crt
```

Docker starts the container again by itself. A restart makes the next try immediate:

```bash
docker restart ohif
```

If the third line of the log is your case, put the files in place ([install.md](install.md#tls-certificate)). If the log says
`no "ssl_certificate" is defined` instead (a typical message, not run for this page), the two `ssl_certificate` lines at the end
of `pacs/listener/server.conf` are missing.

> **Warning**
>
> With the group 101 and the mode 640, every account of the server in a group with the gid 101 can read the key. Run
> `getent group 101`. It should print nothing, or a group that you trust. The same holds for the uid 101 ([3.5](#uid-101-taken)).
> To go back, run the `chown` and `chmod` of the plain image. The OHIF image then does not start again.

> **Check**
>
> ```bash
> bash /opt/pacs-admin/deploy/tools/preflight.sh --lang en --dir /opt/ohif --cert /opt/ohif/tls/server.crt --key /opt/ohif/tls/server.key | grep 'private key'
> docker ps --format '{{.Names}}  {{.Status}}' | grep '^ohif'
> docker logs --tail 5 ohif
> ```
>
> Expected: no `[FAIL]` line for the key, the container `ohif` is `Up` and the log shows no `[emerg]` line. The script reads the
> image from the container or from the compose file. Example for the OHIF image (the key line depends on your key):
>
> ```text
> [ OK ] private key: readable, no passphrase (2048 bit, 2 primes)
> [ OK ] private key permissions fit the OHIF image (root:101 640, readable by uid 101 only)
> ohif  Up 12 seconds
> ```
>
> For the plain image the second line reads `private key permissions fit the plain nginx image (root:root 600)`.

<a id="nginx-wont-start"></a>
### 4.2 nginx reports [emerg] and does not start

**What you see.** The container `ohif` restarts again and again, or the test of nginx stops. `docker logs --tail 20 ohif` shows
a line with `[emerg]`. The test run of install step 4.9 ([install.md](install.md#nginx-files)) shows the same line with the
prefix `nginx: [emerg]`.

**Cause.** nginx reads all its files when it starts. It stops at the first error and names the file and the line number. Read
the first `[emerg]` line only. The same line comes back at every restart.

| The line says | Cause |
|---|---|
| `cannot load certificate key ...` or `cannot load certificate ...` | The TLS files. See [4.1](#tls-key-unreadable). |
| `unknown directive "http2" in /etc/nginx/conf.d/pacs/listener/server.conf:5` | The nginx is older than 1.25.1 and does not know `http2 on;`. See fix A. |
| `unknown "pacs_dcm4chee_ui" variable` | The file `pacs/listener/http.conf` is missing. See fix B. |
| `open() "/etc/nginx/conf.d/pacs/login/http.conf" failed (2: No such file or directory) in /etc/nginx/conf.d/pacs.conf:40` | A file of the nginx files is missing. The line names it. See fix B. |
| `Bind for 0.0.0.0:443 failed: port is already allocated` or `address already in use` | A typical Docker error, not run for this page. The container never starts. Another program holds the port 80 or 443. Find it with `ss -ltnp` and stop it. |

**Fix A, the nginx is too old.** The image of the example compose files has a newer nginx. The message appears when you run
nginx on the server with Debian 12 (it has 1.22), or when you use another image. Check the version:

```bash
nginx -v
```

Example output: `nginx version: nginx/1.22.1`. On a container use `docker exec ohif nginx -v`. For an nginx older than 1.25.1
delete the line `http2 on;` in the file that the message names. Write `http2` into the line above it. The second command
shows the result:

```bash
sed -i -e '/^http2 on;/d' -e 's/^listen \(.*\) ssl default_server;/listen \1 ssl http2 default_server;/' /etc/nginx/conf.d/pacs/listener/server.conf
grep -n 'listen\|http2' /etc/nginx/conf.d/pacs/listener/server.conf
```

The `grep` prints one `listen` line that holds `ssl http2 default_server`. It prints no line that starts with `http2`. Your
port number can differ (`443` on the server, `8443` in the container).

**Fix B, a file is missing.** The tree in `/opt/ohif/nginx` holds 13 files (12 without the optional file for the dcm4chee user
interface). Every file has a source in `/opt/pacs-admin/deploy/nginx`:

| File in your tree | Source in the repository |
|---|---|
| `pacs.conf` | `pacs.conf` |
| `pacs/site.conf` | `site.conf.example` (your file holds your values: copy it only when it is missing) |
| `pacs/audit-write.conf`, `pacs/headers.conf`, `pacs/proxy.conf` | `common/` |
| `pacs/login/admin.conf`, `http.conf`, `locations.conf`, `server.conf` | `login/LOGIN/` |
| `pacs/viewer.conf` | `viewer/VIEWER.conf` |
| `pacs/listener/http.conf`, `server.conf` | `listener/LISTENER/` |
| `pacs/optional/dcm4chee-ui.conf` | `optional/dcm4chee-ui.conf` |

`LOGIN`, `VIEWER` and `LISTENER` are the values of your recipe ([install.md](install.md#nginx-files) has the table). Copy the
missing file. This example copies the file of the message above for the login `basic`:

```bash
cp /opt/pacs-admin/deploy/nginx/login/basic/http.conf /opt/ohif/nginx/pacs/login/http.conf
```

> **Warning**
>
> Do not run the whole copy block of install step 4.9 again after you edited `pacs/site.conf`. Its second line copies
> `site.conf.example` over your file, and your server name and your admin group are gone. Copy single files only. Keep a copy
> of `pacs/site.conf` before any larger change.

> **Check**
>
> ```bash
> docker run --rm -v /opt/ohif/nginx:/etc/nginx/conf.d:ro -v /opt/ohif/tls:/etc/nginx/tls:ro nginx:1.30 nginx -t
> find /opt/ohif/nginx -type f | wc -l
> docker restart ohif
> docker ps --format '{{.Names}}  {{.Status}}' | grep '^ohif'
> ```
>
> Expected: the last two lines of the test, then the number of files, then the container `Up`. Messages about `default.conf`
> and about IPv6 before them are harmless. The recipes `proxied` and `tryit` have no `tls` folder: leave out the second `-v`
> option. Nginx on the server: run `nginx -t` and `systemctl reload nginx`.
>
> ```text
> nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
> nginx: configuration file /etc/nginx/nginx.conf test is successful
> 13
> ohif  Up 6 seconds
> ```

<a id="every-page-500"></a>
### 4.3 Every page answers 500, 502 or 404

**What you see.** Every path of the site fails, including `/`. The answer is 500 (internal server error), 502 (bad gateway) or
404 (not found). With the login oauth2-proxy `docker logs ohif` holds lines like this one, from a test run. The name before
`could not be resolved` is the one in your files:

```text
[error] 28#28: *1 no-such-auth could not be resolved (3: Host not found), server: pacs.example.org, request: "GET / HTTP/2.0", subrequest: "/oauth2/auth", host: "127.0.0.1:8443"
```

**Cause.** There are two different cases.

1. **500, and the log says `could not be resolved`.** nginx looks up two names in the Docker DNS at every request: the login
   container (`set $pacs_auth`) and the archive (`set $arc`) in `pacs/site.conf`. With the login oauth2-proxy, nginx asks the
   login container about every request first. If nginx does not find that name, every page answers 500, also `/`. The reasons
   are: the name in `site.conf` is not the name of the container, the container does not run, or it is not in the same Docker
   network as `ohif`. A wrong archive name breaks only the paths below `/dcm4chee-arc/`. The viewer then opens with an empty list
   ([6.1](#viewer-no-studies)). A typical answer for these paths is 502.
2. **404 or 502 without `could not be resolved`.** The request does not reach the nginx files of this panel. Another program
   answers at this address, for example a machine that the DNS name points to by mistake. Or a proxy in front of `ohif` cannot
   reach it and answers 502 itself. Or the container runs without the folder `/etc/nginx/conf.d`, so nginx shows its default
   site.

**Fix.** Case 1. Read the names that nginx uses, the running containers and the containers in the network. Use the network name
from the last block of your compose file:

```bash
grep -E '^set +\$(arc|pacs_auth) ' /opt/ohif/nginx/pacs/site.conf
docker ps --format '{{.Names}}'
docker network inspect dcm4chee-arc_default -f '{{range .Containers}}{{.Name}} {{end}}'
```

The first command prints the two `set` lines. The host name after `http://` is the name that nginx looks up. Each of these names
must appear in the output of the other two commands. Then act on what is missing:

- **The name is wrong.** Correct the line in `pacs/site.conf` to the name from `docker ps`, then run
  `docker exec ohif nginx -t && docker exec ohif nginx -s reload`.
- **The container does not run.** Start it: `cd /opt/ohif && docker compose up -d`. For `arc` start dcm4chee in its folder.
- **The container is not in the network.** `ohif` and `ohif-auth` get the network from the last block of the compose file
  of the front door ([3.7](#external-network-missing)). A login container that you run in another compose project must join the
  same network.

Case 2. Ask the front door from the server itself. The command skips DNS and every proxy. The recipe `proxied` and `tryit` have
no TLS: use `http://` and the published port or the target of the proxy instead.

```bash
curl -sk --resolve pacs.example.org:443:127.0.0.1 -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/
docker exec ohif ls /etc/nginx/conf.d
```

If this answer is right and the answer from your PC is wrong, the DNS name or the proxy is the problem. Check the name with
`preflight.sh --host pacs.example.org` and the target of the proxy (`http://ohif:8080`). If the `ls` does not show `pacs` and
`pacs.conf`, the compose file mounts the wrong folder ([install.md](install.md#compose-file)).

> **Warning**
>
> Use `nginx -s reload` and not a restart for a change of `site.conf`. A restart of `ohif` interrupts the users for some
> seconds, and the audit log loses the first line of every nginx worker after it.

> **Check**
>
> ```bash
> curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/
> ```
>
> Expected: `302` with the login oauth2-proxy (the jump to the sign-in page), `401` with `basic`, `403` with `none` when your PC
> is not on a list. The numbers 500, 502 and 404 mean that the cause is still there. Use `-k` only with a self-signed
> certificate.

<a id="htpasswd-403-500"></a>
### 4.4 The basic login answers 403 or 500 after the password

**What you see.** The recipe uses the login `basic`. The browser asks for a name and a password. After a correct password it shows
403 (forbidden) or 500 (internal server error) instead of the page. A request without a password still answers 401, because
nginx opens the password files only when a request carries a password. A missing file therefore shows only after the first
sign-in. This command shows the cause:

```bash
docker logs ohif 2>&1 | grep -E 'user "|htpasswd' | tail -n 5
```

The lines look like this (a test run). The `...` stands for the client, server and request at the end of the line:

```text
[error] 21#21: *2 open() "/etc/nginx/htpasswd/admins" failed (2: No such file or directory), client: 172.22.0.2, ...
[crit] 32#32: *73 open() "/etc/nginx/htpasswd/admins" failed (13: Permission denied), ...
```

**Cause.** nginx reads the files `users` and `admins` in `/opt/ohif/htpasswd` at every request that carries a password. The
nginx worker processes run as the [uid](glossary.md#uid) 101.

| Answer | Log | Cause |
|---|---|---|
| 403 | `[error]` and `failed (2: No such file or directory)` | The file does not exist. If the folder `htpasswd` is missing next to the compose file, Docker made an empty one. |
| 500 | `[crit]` and `failed (13: Permission denied)` | The file exists, but uid 101 may not read it, for example owner `root` and mode 600. |

A missing `users` file breaks the viewer pages. A missing `admins` file breaks `/admin/` and every change. A line with
`password mismatch` or `was not found in` is another problem: see [5.9](#basic-login-401).

**Fix.** For 403 make the first account. The script creates the folder and both files with the right owner and mode:

```bash
bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh admin anna
```

For 500 correct the owner and the mode. The command uses `users` and `admins` of the folder next to your compose file:

```bash
chown 101 /opt/ohif/htpasswd/users /opt/ohif/htpasswd/admins
chmod 600 /opt/ohif/htpasswd/users /opt/ohif/htpasswd/admins
```

`preflight.sh --dir /opt/ohif` finds both faults before you start. Behind nginx on the server the workers run as `www-data`:
call the script with `--owner root:www-data --mode 640` ([login.md](login.md#login-basic-accounts)).

> **Warning**
>
> Do not "fix" a 500 with the mode 644. Then every account of the server can read the password hashes, and `preflight.sh`
> warns about it. Do not call `pacs-adduser.sh` for a name that exists to repair the rights: it sets a new password for that
> name.

> **Check**
>
> ```bash
> ls -ln /opt/ohif/htpasswd
> curl -sk -u anna -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/
> ```
>
> Expected: two files of the user 101 with the mode `-rw-------`, and `200` for an administrator after you type the password of
> `anna`. Example (the sizes and the times differ):
>
> ```text
> -rw------- 1 101 0 112 Oct 14 07:54 admins
> -rw------- 1 101 0 112 Oct 14 07:54 users
> 200
> ```

<a id="proxy-wrong-address"></a>
### 4.5 The audit log shows the address of the proxy for every user

**What you see.** The recipe `proxied` runs nginx behind your own TLS proxy. In the audit log, in the CSV export and in the
check against locking yourself out of the tab `Firewall`, every PC has the same address: the proxy. With the login `none` every
request answers 403, because no list holds the proxy.

**Cause.** nginx sees the connection of the proxy and reads the address of the PC from the header `X-Forwarded-For`. It does so
only for a connection from the subnet in the line `set_real_ip_from` of `pacs/listener/server.conf`. The shipped value is
`203.0.113.1`. This is a documentation address that no proxy uses, so it trusts nobody. nginx then ignores the header. The same
happens when the subnet does not hold the proxy, or when the proxy does not send the header. Another cause for the recipes with
TLS: Docker accepts a connection over IPv6 and nginx sees only the address of the Docker gateway. The example compose files
publish the ports on `0.0.0.0` (IPv4 only) for this reason. Do not change that.

**Fix.** Set the subnet of the Docker network that only the proxy and nginx share. `proxy_default` is the example name from the
compose file. The name stands in its last block, in the line with the second `name:`.

```bash
PROXY_NET=$(docker network inspect proxy_default -f '{{(index .IPAM.Config 0).Subnet}}')
echo "$PROXY_NET"
sed -E -i "s|^(set_real_ip_from +)[^;]+;.*|\1${PROXY_NET};|" /opt/ohif/nginx/pacs/listener/server.conf
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

The `echo` prints the subnet, for example `172.23.0.0/16`. If your proxy does not send `X-Forwarded-For`, switch it on in the
proxy ([install.md](install.md#variant-proxied) names the settings of the usual proxies).

> **Warning**
>
> Write the subnet of the one network that the proxy and nginx share, nothing wider. Every client in the trusted subnet can
> write any address into the header. With the login `none` that address decides the access level. Do not publish a port of
> `ohif` on the host in this recipe.

> **Check**
>
> ```bash
> grep -n set_real_ip_from /opt/ohif/nginx/pacs/listener/server.conf
> python3 /opt/pacs-admin/server/pacsdb.py protokoll zugriffe "$(date +%F)" | tail -n 3
> ```
>
> Open `https://pacs.example.org/` on a PC first. Expected: the first line shows your subnet and not `203.0.113.1`. In the rows
> of the second command the field `ip` is the address of the PC. A request without the header (a call from the proxy host) shows
> the address of the proxy. Example row (the PC address is `192.0.2.77`):
>
> ```text
> {"t":"2026-10-14T09:00:26+00:00","u":"vera","sub":"vera","ip":"192.0.2.77","r":"/","status":200}
> ```

<a id="trouble-login"></a>
## 5. Login

This chapter covers the sign-in. The entries 5.1 to 5.8 belong to the login oauth2-proxy (single sign-on with an identity
provider such as Microsoft Entra ID). Entry 5.9 belongs to the login `basic`, entry 5.10 to the login `none`.
[login.md](login.md#login-choose) explains how to set up each login. The messages of Microsoft and of oauth2-proxy are quoted
from their documentation and source code. They were not run against a real provider.

<a id="login-redirect-uri-mismatch"></a>
### 5.1 Microsoft shows AADSTS50011 (redirect URI)

**What you see.** The user chooses the account on the Microsoft page. Microsoft then shows an error page with the code
`AADSTS50011`. The text says that the redirect URI in the request does not match the redirect URIs that are configured for the
application. The page names the address that Microsoft received.

**Cause.** oauth2-proxy sends the address of the flag `--redirect-url` to Microsoft. Microsoft compares it, character by
character, with the redirect URIs of the app registration. Another host name, `http` instead of `https`, a port number or a
slash at the end makes it a different address.

**Fix.** Read the address that oauth2-proxy sends:

```bash
grep -n -e '--redirect-url' /opt/ohif/docker-compose.yml
```

Open Entra ID > App registrations > `PACS` > Manage > Authentication. The section Web must list exactly this address. The host
name is the one that users type (the line `server_name` in `pacs/site.conf`). Correct the side that is wrong:

- **The compose file is wrong.** Edit the line, then run `cd /opt/ohif && docker compose up -d`. The command creates
  `ohif-auth` again with the new address.
- **The list in the portal is wrong.** Select Add URI, type `https://pacs.example.org/oauth2/callback` and select Save.

> **Warning**
>
> Register only the one address of your own server. The redirect URI tells Microsoft where to send the result of a sign-in. Do
> not add the address of a host that you do not control.

> **Check**
>
> ```bash
> docker compose -f /opt/ohif/docker-compose.yml config | grep -e '--redirect-url'
> ```
>
> Expected: one line with your address. Example (the host name differs):
>
> ```text
>       - --redirect-url=https://pacs.example.org/oauth2/callback
> ```
>
> Then sign in again in a private browser window. Microsoft shows the sign-in page without an error code, and the viewer opens.

<a id="login-client-secret"></a>
### 5.2 Microsoft shows AADSTS7000215 or AADSTS7000222 (client secret)

**What you see.** The user signs in at Microsoft, but the browser does not come back to the PACS. It shows an error page of
oauth2-proxy. The log of oauth2-proxy holds a line with one of the two codes:

```bash
docker logs ohif-auth 2>&1 | grep AADSTS | tail -n 3
```

**Cause.** The code `AADSTS7000215` says that the client secret is wrong. The usual reason is that the Secret ID was copied
instead of the Value ([login.md](login.md#login-oauth2-entra), step 2). The code `AADSTS7000222` says that the secret has
expired. The portal shows the expiry date of each secret. A third reason is a container that still uses the old secret: Docker
reads `ohif-auth.env` when it creates the container, and `docker compose restart` does not read it again.

**Fix.** Make a new secret and give it to the container. First open Entra ID > App registrations > `PACS` > Manage >
Certificates & secrets > Client secrets > New client secret, and copy the **Value** at once. Then run the three blocks of
[login.md, step 7](login.md#login-oauth2-env). They write a new `ohif-auth.env` and a new cookie secret, so everybody signs in
once more. Then create the container again:

```bash
cd /opt/ohif && docker compose up -d --force-recreate ohif-auth
```

> **Warning**
>
> Delete the old secret in the portal only after the check below passed. Write the expiry date of the new secret into a
> calendar. On that day nobody can sign in ([login.md](login.md#login-oauth2-operate), section 2.5).

> **Check**
>
> ```bash
> docker ps --format '{{.Names}}  {{.Status}}' | grep '^ohif-auth'
> docker logs ohif-auth 2>&1 | grep AADSTS | tail -n 3
> ```
>
> Sign in once between the two commands. Expected: `ohif-auth` is `Up`, the viewer opens after the sign-in, and the second
> command prints nothing. Example (the time differs):
>
> ```text
> ohif-auth  Up 40 seconds
> ```

<a id="login-oauth2-proxy-down"></a>
### 5.3 The container ohif-auth does not run, or the jump to the sign-in page is missing

**What you see.** `docker ps` does not list `ohif-auth`, or it shows `Restarting`. A request without a session does not jump
to the sign-in page, and every page answers 500 ([4.3](#every-page-500)). The end of the log names the reason:

```bash
docker logs --tail 20 ohif-auth
```

**Cause.** oauth2-proxy checks its settings and asks the provider for its configuration when it starts. It stops when one of
these fails. The last lines of the log tell which one:

| The last lines say | Cause |
|---|---|
| `oidc: issuer did not match the issuer returned by provider, expected "..." got "..."` | The address after `--oidc-issuer-url=` differs from the address that the provider announces. A slash at the end counts. |
| A line with `dial tcp`, `lookup` or `i/o timeout` (typical, not run) | The server cannot reach the provider. DNS or a firewall of the network blocks it. |
| `missing setting: ...` or `cookie_secret must be 16, 24, or 32 bytes ...` (typical, not run) | `ohif-auth.env` is empty, lacks a name or holds a cookie secret of the wrong length. |

`docker compose up -d` can also fail before the container starts. Two typical messages, not run: `env file ... ohif-auth.env not
found` (the file does not exist) and an error while the image `quay.io/oauth2-proxy/oauth2-proxy:v7.15.4` is pulled (the server
cannot reach `quay.io`).

**Fix.** Act on the line that you found.

**Issuer.** Ask the provider for the address that it announces. Write the printed address, character for character, after
`--oidc-issuer-url=` in the compose file ([login.md, step C](login.md#login-oauth2-compose) has the details):

```bash
ISSUER=CHANGE-ME-ISSUER-ADDRESS
curl -s "${ISSUER%/}/.well-known/openid-configuration" | python3 -c 'import sys,json; print(json.load(sys.stdin)["issuer"])'
```

**Provider not reachable.** Run the `curl` above on the server. If it prints nothing or fails, the server has no path to the
provider. Ask the people who run DNS and the firewall of the network to allow the host of the provider.

**Env file.** Make it again with the three blocks of [login.md, step 7](login.md#login-oauth2-env).

**Image.** Allow `quay.io` for the server. Or pull the image on another machine and bring it over with `docker save` and
`docker load`.

Then apply the change:

```bash
cd /opt/ohif && docker compose up -d
```

> **Check**
>
> ```bash
> docker ps --format '{{.Names}}  {{.Status}}' | grep '^ohif'
> curl -sk -o /dev/null -w '%{http_code} %{redirect_url}\n' https://pacs.example.org/ | cut -d/ -f1-3
> ```
>
> Expected: `ohif` and `ohif-auth` are `Up`, and a request without a session redirects to the provider. Example for Entra ID
> (the last line was not run against a real provider):
>
> ```text
> ohif  Up 2 minutes
> ohif-auth  Up 2 minutes
> 302 https://login.microsoftonline.com
> ```

<a id="login-loop"></a>
### 5.4 The browser jumps between the PACS and the login page

**What you see.** The user signs in. The browser returns to the PACS, jumps to the login page again and repeats this until it
stops with a message about too many redirects. The wording depends on the browser.

**Cause.** After a good sign-in, oauth2-proxy sets a session cookie (default name `_oauth2_proxy`). If the browser does not
send the cookie back, nginx sees no session and sends the user to the provider again. These reasons are typical. None was run
against a real provider:

| Reason | How to tell |
|---|---|
| The user opened the site with another name than the host name of `--redirect-url`, for example the IP address or a short name. The cookie belongs to the host name of the redirect URL. | The address bar shows another name than `server_name` in `pacs/site.conf`. |
| The clock of the server is wrong by more than the session time of 12 hours. The cookie then expires at once. | `timedatectl` shows another time than a reliable clock, or `System clock synchronized: no`. |
| A proxy in front of nginx changes the header `Host`. | The recipe `proxied` is in use ([login.md](login.md#login-other-oauth2), item 1). |
| The browser blocks cookies for the site. | After the sign-in, the developer tools of the browser (F12, page Application or Storage) list no cookie `_oauth2_proxy` for the site. |

**Fix.** Tell users to open the site with the host name of `server_name` only. Correct the time source of the server with the
tools of your organisation. Set the proxy to pass `Host` unchanged and to send every path, `/oauth2/` included, to nginx. Allow
cookies for the site in the browser.

> **Check**
>
> ```bash
> timedatectl | grep -e 'Local time' -e 'synchronized'
> ```
>
> Expected: a time that matches a reliable clock, and `System clock synchronized: yes`. Then open
> `https://pacs.example.org/` in a private browser window and sign in. The viewer opens, and the address bar stays on the
> viewer. Example of the first command (the time differs):
>
> ```text
>                Local time: Wed 2026-10-14 09:30:12 CEST
> System clock synchronized: yes
> ```

<a id="viewer-403-after-login"></a>
### 5.5 The page "Forbidden" appears right after the sign-in

**What you see.** The sign-in at the provider works. The browser then shows a page with the title "Forbidden" and the text
"You do not have permission to access this resource". Other users can sign in. The log of oauth2-proxy holds one line for each
refused sign-in:

```bash
docker logs ohif-auth 2>&1 | grep -E 'Invalid authentication|Authenticated via' | tail -n 5
```

The line `Invalid authentication via OAuth2: unauthorized` marks a refused sign-in. The line `Authenticated via OAuth2:` marks a good
one and shows the session, with the groups that the provider sent. Both lines come from the source code of oauth2-proxy
`v7.15.4` and were not run against a real provider.

**Cause.** oauth2-proxy lets a user in only when the user is in at least one group of the flags `--allowed-group`. A refused
user gets no session, so `/oauth2/userinfo` answers 401 for that user. The reasons:

| Reason | How to tell |
|---|---|
| The user is not a member of the viewer group or of the admin group. | The member list of the group in the portal. |
| The provider sends no groups. Entra ID: the token configuration has no groups claim. Other providers: the scope `groups` or the mapper is missing. | A user who can sign in has an empty entry `groups` in `/oauth2/userinfo`. |
| The names differ: an Object ID against a name, capital letters, or with Keycloak a missing leading slash. | Compare `/oauth2/userinfo` of a user who can sign in with the `--allowed-group` lines, letter by letter. |
| The user is in more than 200 groups (Entra ID). | [login.md, 2.4](login.md#login-oauth2-overage). |
| Google: the address of the user is not in the domain of `--email-domain`. GitHub: the user is not in the organisation or the team. | [login.md, 2.6](login.md#login-oauth2-providers). |

**Fix.** Show the groups that the compose file allows:

```bash
grep -n -e '--allowed-group' /opt/ohif/docker-compose.yml
```

Open `https://pacs.example.org/oauth2/userinfo` with an account that can sign in. The entry `groups` shows how the provider
writes group names. Add the user to a group, or correct the names in the compose file, then run
`cd /opt/ohif && docker compose up -d`. oauth2-proxy reads the groups at the sign-in and keeps them for the session, which lasts
12 hours. A user who was added to a group opens `/oauth2/sign_out` and signs in again.

> **Warning**
>
> Do not delete the `--allowed-group` lines to test. The shipped file has `--email-domain=*`. Without a group check,
> oauth2-proxy then lets every account of the provider in, and with Entra ID that is every user of the tenant.

> **Check**
>
> Sign in with the account in a private browser window. Expected: the viewer opens. The log shows the line
> `Authenticated via OAuth2:` for the account:
>
> ```bash
> docker logs ohif-auth 2>&1 | grep 'Authenticated via' | tail -n 1
> ```

<a id="admin-403"></a>
### 5.6 /admin/ answers 403 for an account that should be an admin

**What you see.** The user signs in and opens the viewer. `/admin/` shows the plain page `403 Forbidden`. A viewer who is not
an admin sees the same page, and that is correct. With the login `basic` the answer for such a user is 401
([5.9](#basic-login-401)). With the login `none` the answer is 403 for another reason ([5.10](#none-403)).

**Cause.** For `/admin/` and for every change, nginx asks oauth2-proxy whether the user is in the admin group. The admin group
is the value of `$pacs_admin_group` in `pacs/site.conf`. oauth2-proxy answers 403 when the user is not in that group.

| Reason | How to tell |
|---|---|
| `$pacs_admin_group` holds the shipped value `00000000-0000-0000-0000-000000000000`, or a value that differs from the group name the provider sends. | The command below prints the value. |
| The user joined the admin group a short time ago. oauth2-proxy keeps the groups from the sign-in for up to 12 hours. | The group list in the portal shows the user, but `/oauth2/userinfo` does not list the group. |
| The value in `site.conf` differs from the second `--allowed-group` of the compose file. | Compare the two values, letter by letter. |

**Fix.** Show the value that nginx uses:

```bash
grep -n 'pacs_admin_group' /opt/ohif/nginx/pacs/site.conf
```

Open `https://pacs.example.org/oauth2/userinfo` with an account that can sign in. The entry `groups` shows how the provider
writes a group name. Set the same text in `site.conf` and let nginx read the file again:

```bash
ADMIN_GROUP=CHANGE-ME-ADMIN-GROUP
sed -E -i 's|^(set \$pacs_admin_group +)[^;]+;.*|\1'"$ADMIN_GROUP"';|' /opt/ohif/nginx/pacs/site.conf
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

A group name with a space or another special character needs the percent form ([5.7](#admin-500)). A user who joined the group
recently opens `/oauth2/sign_out` and signs in again.

> **Warning**
>
> Do not set the admin group to the viewer group to make it work. Then every viewer is an admin, and an admin can edit,
> reject and delete studies.

> **Check**
>
> ```bash
> grep -n 'pacs_admin_group' /opt/ohif/nginx/pacs/site.conf
> ```
>
> Expected: one line with your group. Then open `https://pacs.example.org/admin/` with the admin account in a private window.
> The admin page opens, and the account name stands at its top. Example of the line (the group differs):
>
> ```text
> 20:set $pacs_admin_group aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee;
> ```

<a id="admin-500"></a>
### 5.7 /admin/ answers 500

**What you see.** With the login oauth2-proxy, `/admin/` shows `500 Internal Server Error`, also for an admin. The viewer can
still work. If every page answers 500, see [4.3](#every-page-500) first.

**Cause.** nginx asks oauth2-proxy about the admin group (5.6). The answer becomes 500 in two cases:

| Reason | What the log of nginx shows |
|---|---|
| `$pacs_admin_group` in `pacs/site.conf` is empty. nginx refuses on purpose, because an empty group would let every signed-in account in. | No extra line. |
| The group name holds a character that a web address does not allow, for example a space. nginx pastes the value unchanged into an address, and oauth2-proxy answers 400. | `auth request unexpected status: 400` |

```bash
docker logs ohif 2>&1 | grep -E 'auth request unexpected status|could not be resolved' | tail -n 3
grep -n 'pacs_admin_group' /opt/ohif/nginx/pacs/site.conf
```

**Fix.** An empty value: set the group as in [5.6](#admin-403). A special character: write the value of `site.conf` in the
percent form. This command converts a whole name (the example name is `authentik Admins`):

```bash
python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe="-_.~:/@"))' 'authentik Admins'
```

Expected output:

```text
authentik%20Admins
```

Put the printed text into `site.conf` with the `sed` command of [5.6](#admin-403) and let nginx read the file again. The compose
file keeps the plain name. [login.md, step D](login.md#login-oauth2-group-names) lists the characters and their forms.

> **Check**
>
> Open `https://pacs.example.org/admin/` with the admin account in a private window. Expected: the admin page opens, and the
> first command of this entry prints no new `unexpected status` line.

<a id="session-expired"></a>
### 5.8 The admin page shows "Sitzung abgelaufen, Seite neu laden (F5)"

**What you see.** A red message at the bottom right of the admin page says `Sitzung abgelaufen, Seite neu laden (F5)` (session
ended, reload the page with F5). The same text replaces the line `Kein Status vorhanden ...` in the overview and the line
`Noch keine Änderungen über diese Seite.` in the list of changes.

**Cause.** The page asks the server in the background for the status, the audit log and the disks. When the login session has
ended, nginx answers such a call with a redirect to the sign-in page (oauth2-proxy) or with 401 (`basic`). The page does not
follow a redirect. It treats a redirect and a 401 as an ended session. An oauth2-proxy session lasts 12 hours
(`--cookie-expire=12h`) and is not renewed ([login.md](login.md#login-oauth2-operate)). With the login `basic` the browser keeps
the password until it closes. The message also appears after an administrator removed the account or set a new password.

**Fix.** Press F5. With oauth2-proxy the browser goes to the provider. If the session at the provider is still alive, the user
returns without typing. With `basic` the browser asks for the name and the password. A change that the user started at that
moment was refused at the front door before it reached the archive. Start it again.

If the message comes back at once after F5, see [5.4](#login-loop) (oauth2-proxy) or [5.9](#basic-login-401) (`basic`).

> **Check**
>
> Press F5 and sign in. Expected: the red message is gone, the tiles load, and the account name stands at the top of the page.

<a id="basic-login-401"></a>
### 5.9 Basic login: the password window comes back

**What you see.** The browser asks for the name and the password, accepts the entry and asks again. Or `curl -u` prints `401`
for a password that is right. A request without any password answers 401 in every case. The error log of nginx names the
account and the reason:

```bash
docker logs ohif 2>&1 | grep -E 'user "|htpasswd' | tail -n 5
```

The lines look like this (a test run). The `...` stands for the client, server and request at the end of the line:

```text
2026/10/14 07:39:56 [error] 98#98: *3 user "clara": password mismatch, client: 127.0.0.1, ...
2026/10/14 07:39:56 [error] 100#100: *5 user "vera" was not found in "/etc/nginx/htpasswd/admins", client: 127.0.0.1, ...
```

**Cause.**

| The log says | Cause | Fix |
|---|---|---|
| `user "clara": password mismatch` | The password differs, or the hash in the file has a type that nginx cannot read. | Set the password again with the script. |
| `user "vera" was not found in ".../admins"` | `vera` is a viewer account. `/admin/` needs a line in `admins`. | Run the script with `admin vera`. |
| `user "vera" was not found in ".../users"` | The account does not exist, or the name has another spelling. | Run the script with `all vera`. |
| No such line, and `/admin/` answers 401 for everybody | The file `admins` is empty. | Make one administrator with the script. |

A password mismatch with the right password has these reasons:

- **A hash of another type.** The script writes the hash type sha512-crypt (`$6$`) with the default number of rounds. nginx
  checks the hash at every request, so a high number of rounds slows down every page, and the script has no option for it. A
  hash of the type bcrypt (`$2y$`, made with `htpasswd -B`) is not read by every C library. Lines that another tool wrote can be
  of such a type.
- **An old openssl.** With openssl older than 1.1.1 the script writes the type apr1 and prints `pacs-adduser: WARNING: this
  openssl cannot make sha512-crypt hashes (it needs 1.1.1 or newer). Using apr1, the weaker hash type. Update openssl and set
  the password again.` Both types work with nginx.
- **A password of more than 256 bytes.** The hash covers only the first 256 bytes, so nginx refuses the right password. The
  script refuses such a password.
- **A saved password.** The browser sends an old password that it saved for the name. Delete the saved entry.

**Fix.** Set the password again. The script asks twice and keeps the rights of the files:

```bash
bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh all clara
```

For an administrator use `admin` instead of `all`. The command must run as root. Without root rights the script sets no owner
and prints a warning: nginx then answers 500 ([4.4](#htpasswd-403-500)).

> **Warning**
>
> The script replaces the password of an account that exists. Run it only for the person who needs a new password. Do not edit
> the files by hand: a wrong owner or mode gives 500, and a line with a wrong hash type gives 401.

> **Check**
>
> ```bash
> curl -sk -u clara -o /dev/null -w '%{http_code}\n' https://pacs.example.org/
> ```
>
> The command asks for the password of `clara`. Expected: `200`. Then open the site in a private browser window and sign in.
> If the number is not `200`, read [login.md, 3.6](login.md#login-basic-errors).
>
> ```text
> 200
> ```

<a id="none-403"></a>
### 5.10 Login none: a PC gets 403 Forbidden

**What you see.** The browser shows the plain page `403 Forbidden` at `/`, at `/admin/` or at both, for a PC that should have
access. The page does not name a list.

**Cause.** nginx compares the address of the PC with the lines `allow` of two lists: `pacs/login/server.conf` (viewer) and
`pacs/login/admin.conf` (admin). An address that no `allow` line names gets 403. The usual reasons:

| Reason | Result |
|---|---|
| The address that nginx sees is not the address of the PC, for example because a router with address translation or a proxy sits between them. | 403 for the PC. A list for the router address opens the site for every PC behind it. |
| The PC gets its address by DHCP, and the address changed. | The access ends on the day the address changes. |
| An administrator PC is on the admin list only. The admin list replaces the viewer list for `/admin/`, but the admin page searches studies through the viewer list. | `/admin/` opens and the study search gets 403. |
| The lists still hold the example networks with the marker `CHANGE-ME`. | Nobody gets in. |

**Fix.** Read the address that nginx saw. The word after `client:` is that address:

```bash
docker logs ohif 2>&1 | grep 'access forbidden by rule' | tail -n 3
```

The lines look like this (a test run on plain http, with a documentation address):

```text
2026/10/14 08:41:35 [error] 9#9: *1 access forbidden by rule, client: 192.0.2.99, server: pacs.example.org, request: "GET /admin/ HTTP/1.1", host: "pacs.example.org"
```

The line also shows the page that the PC asked for (`/admin/` here). Put exactly this address, or a small network that holds
it, on the right list ([login.md, 4.2](login.md#login-none-lists) has the commands). Put every administrator PC on both lists.
Then test the files and let nginx read them again:

```bash
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

If the address in the log is the address of a router or of a proxy, a list cannot tell the PCs apart. With your own proxy in
front of nginx use the listener `behind-proxy` ([4.5](#proxy-wrong-address)).

> **Warning**
>
> Never write `allow all;`, because it lets everybody in. Keep every network as small as you can. Keep `deny all;` as the last
> line of a list: nginx uses the first line that matches.

> **Check**
>
> Run these commands on the PC itself (on Windows use `curl.exe`). The server is on no list, so a run on the server shows nothing
> about the PC.
>
> ```bash
> curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/
> curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/
> ```
>
> Expected: `200` and `200` for an administrator PC on both lists, `200` and `403` for a PC on the viewer list only, `403` and
> `403` for a PC on no list. Use `-k` only with a self-signed certificate.

<a id="trouble-viewer"></a>
## 6. Viewer and archive

This chapter covers the [viewer](glossary.md#viewer), the user interface of dcm4chee and the link between nginx and the
archive container `arc`. Two entries use the developer tools of the browser. Press F12 (Chrome, Edge and Firefox) and open the
tab `Network`.

<a id="viewer-no-studies"></a>
### 6.1 The viewer opens, but the study list is empty

**What you see.** The viewer starts and shows its study list, but the list stays empty. Or the viewer shows an error for the
search. You know that the archive holds studies.

**Cause.** The viewer asks nginx for `/dcm4chee-arc/aets/AE-TITLE/rs/studies`. The [AE title](glossary.md#ae-title) in this
address must be the AE title of the archive, and nginx must know it. Five places hold the title, and the archive holds it too
([reference.md, 4.3](reference.md#ae-title)). A place with another title breaks one function:

| Place | Used for | If the title differs |
|---|---|---|
| `/opt/ohif/app-config.js` | The address that the viewer asks. | The viewer asks for a title that nginx or the archive does not know, and the study list stays empty. |
| `/opt/ohif/nginx/pacs.conf` | The study search, the changes of the admin page and the audit events. | The admin page cannot search or change studies (404), and the audit log misses the searches. |
| `/opt/ohif/nginx/pacs/viewer.conf` | The reads of series, images and reports for the viewer. | The list can show studies, but a study does not open. |
| `config.js`: `aet` and `iocmAet` | The admin page. | The tab `Studien` (studies) finds nothing. |
| `ARC_AET` in `/etc/default/pacs-admin` | The disk assistant. | The assistant stops with `HALT: AE ... steht nicht im LDAP` ([8.1](#disk-halt)). |
| The archive (LDAP) | dcm4chee itself. | Every call with this title answers 404. |

**Find the cause.** Read the status of the search in the browser:

1. Open the viewer. Press F12 and open the tab `Network`.
2. Press Ctrl+F5 to load the page again.
3. Click the line whose name starts with `studies?`.
4. Read the status code of this call.

| Status of `studies?...` | Meaning | Go to |
|---|---|---|
| `404` | nginx or the archive does not know the AE title in the address. | Fix A |
| `500` or `502` | nginx does not reach the archive. | [4.3](#every-page-500) |
| `401`, or `302` and then the sign-in page | The login session has ended. | [5.8](#session-expired), [5.9](#basic-login-401) |
| `403` | The account or the PC is not allowed. | [5.5](#viewer-403-after-login), [5.10](#none-403) |
| `200` with `[]`, or `204` | The archive answers and finds no study for this search. | Fix C |
| No line `studies?...`, or a call to another server | The viewer does not use your `app-config.js`. | Fix B |

**Fix A: one AE title in all places.** First read the AE titles that the archive knows. The command runs on the server and
asks the archive directly:

```bash
curl -s http://127.0.0.1:8080/dcm4chee-arc/aets | grep -o '"dicomAETitle" *: *"[^"]*"'
```

Expected: one line for each AE title of the archive. A standard install lists several titles, among them `DCM4CHEE` and
`IOCM_QUALITY`. This is the usual answer of dcm4chee. It was not recorded from a run.

The files must follow the archive. The examples below use the title `MYARC`. Write your own title. The first call only shows
what would change:

```bash
bash /opt/pacs-admin/deploy/tools/set-aet.sh MYARC --dir /opt/ohif --dry-run
```

If the files hold another title than `DCM4CHEE` now, add `--from OLDARC` with that title. The script replaces whole words
only. It leaves `99DCM4CHEE`, because that word is a coding scheme and not an AE title. When the list of changes is right, run
the command again without `--dry-run`. The script shows every changed line and asks `Apply these changes? [y/N]`. It keeps
copies of the originals in `/opt/ohif/.set-aet-backup-TIME/`.

```bash
bash /opt/pacs-admin/deploy/tools/set-aet.sh MYARC --dir /opt/ohif
```

The script cannot change two places. Change them by hand:

- `aet` (and `iocmAet`, if you renamed that title too) in the `config.js` that your admin page uses. This is
  `/opt/pacs-admin/web/admin/config.js`, or your copy `/opt/ohif/config.js` when the compose file mounts one. The script changes
  a copy below `/opt/ohif` itself.
- `ARC_AET=MYARC` in `/etc/default/pacs-admin`. Then run `systemctl restart pacs-verwaltung`. Do not restart the service while
  the tile `Neue Festplatte` says `läuft seit ...`: the restart stops a running disk setup.

Last, restart the front door, so that it reads the single files again, and load the page without the cache:

```bash
cd /opt/ohif && docker compose restart ohif
```

Press Ctrl+F5 in the browser.

**Fix B: the viewer does not use your `app-config.js`.** Without your file the viewer runs with the configuration of the
image, which knows nothing about your archive. Open `https://pacs.example.org/app-config.js` in the browser. The page must show
your file. Or read the first lines inside the container and compare them with the file on the server:

```bash
ls -l /opt/ohif/app-config.js
docker exec ohif head -n 3 /usr/share/nginx/html/app-config.js
```

Expected: the file exists, and the container shows the first lines of this file. The file of the repository starts with
`// OHIF viewer configuration for a dcm4chee-arc PACS behind the nginx of this repository.`

- If the file is missing on the server, copy it with `cp /opt/pacs-admin/deploy/app-config.js.example /opt/ohif/app-config.js`.
  Set the AE title as in Fix A. The compose file of the front door must mount the file with the line
  `- ./app-config.js:/usr/share/nginx/html/app-config.js:ro`.
- If the container shows other text than the file, the container holds an old copy. A mounted single file is read when the
  container starts. Run `cd /opt/ohif && docker compose restart ohif` and press Ctrl+F5.

**Fix C: the archive finds no study.** An archive without studies is no error. Ask the archive directly for one study:

```bash
curl -s -o /dev/null -w '%{http_code}\n' 'http://127.0.0.1:8080/dcm4chee-arc/aets/DCM4CHEE/rs/studies?limit=1'
```

Expected: `200` when the archive holds at least one study. The usual answer for no study is `204`; it was not recorded from a run.
`404` means that the archive does not know the title: use Fix A. If the tab `Studien` of the admin page lists studies and the
viewer does not, clear the filters of the study list in the viewer.

**A blank page.** A blank page instead of the empty list means that the session ended while the page stayed open. The start
page loads its scripts without a session and gets only redirects. Press Ctrl+F5 and sign in again ([5.8](#session-expired)).

> **Warning**
>
> Change the files to match the archive. Do not rename the AE title in the archive to match the files: every DICOM device that
> sends to the old title would be refused. Do not use search and replace in an editor, because `99DCM4CHEE` must stay.

> **Check**
>
> Open the viewer and press Ctrl+F5. Expected: the study list shows the studies, and the call `studies?...` in the tab
> `Network` has the status `200`. Open one study. Expected: the images load. The tab `Studien` of the admin page lists the same
> studies.

<a id="dcm4chee-ui-404"></a>
### 6.2 The dcm4chee user interface answers 404

**What you see.** The link `dcm4chee` in the header of the admin page, or the address
`https://pacs.example.org/dcm4chee-arc/ui2/`, opens a page with `404`. Or the interface opens, but its lists stay empty, and the
tab `Network` of the browser shows `404` for most calls below `/dcm4chee-arc/`.

**Cause.** The interface is an optional module ([modules.md, section 5](modules.md#dcm4chee-ui)). Two things can fail:

| What fails | Result |
|---|---|
| The file `pacs/optional/dcm4chee-ui.conf` is not in the folder of the front door. | The address of the interface and every call below it answer 404. |
| The header `Referer` of a call does not match the pattern in `pacs/listener/http.conf`. | The page of the interface loads, but its calls go to the locked locations, and most of them answer 404. |

First test the file. The first command lists the folder, the second asks for the entry address:

```bash
ls /opt/ohif/nginx/pacs/optional/
curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/dcm4chee
```

Expected: the list shows `dcm4chee-ui.conf`, and the number is `301`. If the file is missing, copy it and let nginx read it:

```bash
cp /opt/pacs-admin/deploy/nginx/optional/dcm4chee-ui.conf /opt/ohif/nginx/pacs/optional/
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

If the file is there, test the `Referer` rule. nginx lets a call of the interface through only when the header `Referer`
names the interface: `https://`, the host name of the request, no port and the path `/dcm4chee-arc/ui2/`.

1. Open the interface. Press F12, open the tab `Network` and press Ctrl+F5.
2. Click a call with the status `404` and read the request header `Referer`.
3. Compare it with the pattern on the server:

```bash
grep -n -A3 'map "\$host \$http_referer"' /opt/ohif/nginx/pacs/listener/http.conf
```

The lines look like this (listener `tls`; the line numbers can differ):

```text
14:map "$host $http_referer" $pacs_dcm4chee_ui {
15-    "~^(\S+) https://\1/dcm4chee-arc/ui2/"  1;
16-    default                                 0;
17-}
```

The rule fails for these reasons. The last reason is typical and was not tested.

| Reason | Fix |
|---|---|
| Users open the PACS with a port, for example `https://pacs.example.org:8443/`. | Put the port into the pattern: `https://\1:8443/dcm4chee-arc/ui2/`. |
| The listener is `plain` and the SSH tunnel uses different ports at its two ends. | Use the same port at both ends. The delivered pattern names `:8080`. |
| A reverse proxy in front of nginx changes the header `Host`. | Make the proxy pass `Host` unchanged (Apache: `ProxyPreserveHost On`). If the proxy listens on another port than 443, put the port into the pattern. |
| A proxy, a browser add-on or a policy removes the `Referer` or cuts it to the host name. | Let the header pass with the full path. The rule cannot work without it. |

After a change of the pattern, test the configuration and let nginx read it:

```bash
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

> **Warning**
>
> Change only the part of the pattern that names the port. A looser pattern lets calls from other pages skip the locks of the
> admin page. The interface of dcm4chee has no locks of its own ([modules.md, section 5](modules.md#dcm4chee-ui)).

> **Check**
>
> ```bash
> curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/dcm4chee
> ```
>
> Expected: `301`. Then open the interface as an admin in the browser. Expected: the lists show data, and the tab `Network` has
> no `404` for the calls below `/dcm4chee-arc/`.

<a id="dcm4chee-ui-upload"></a>
### 6.3 An upload in the dcm4chee user interface fails

**What you see.** An admin sends DICOM files through the interface of dcm4chee. The upload ends with an error, or it works
for small files only.

The viewer and the admin page do not upload on purpose. The viewer is set to `dicomUploadEnabled: false`, and nginx refuses
writing calls from the viewer. Only the interface of dcm4chee uploads ([6.2](#dcm4chee-ui-404) lists what it needs).

**Cause.** Find the failed call in the tab `Network` of the browser (a red status) and read its status code:

| Status | Cause | Fix |
|---|---|---|
| `403` | The `Referer` rule does not match ([6.2](#dcm4chee-ui-404)). The call lands on the locked study search, which allows GET only. | Fix the rule as in 6.2. |
| `413` | A limit for the size of the body. nginx of this repository sets no limit for the interface, so a proxy in front of it limits the size. | Raise the limit in the proxy. |
| `500` | The login `oauth2-proxy` of an older version: the check of the login (the auth subrequest) had a body limit of 1 MB. | See below. |
| `504` | The archive needs more than 600 seconds to answer (`proxy_read_timeout 600s`). | Upload fewer files at a time. |
| `502` | nginx does not reach the archive. | [4.3](#every-page-500) |

The reasons for `403`, `413` and `504` come from the nginx files and were not tested. The `500` entry follows the note in
`deploy/nginx/README.md`.

For `500` count the limits in the login files:

```bash
grep -c 'client_max_body_size 0' /opt/ohif/nginx/pacs/login/locations.conf
```

Expected with the login `oauth2-proxy`: `2` (one for `= /oauth2/auth`, one for `= /oauth2/auth-admin`). If the number is
lower, add the line `client_max_body_size 0;` below the line `internal;` of each of the two locations. Compare with
`/opt/pacs-admin/deploy/nginx/login/oauth2-proxy/locations.conf`. Then test and reload:

```bash
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

The audit log lists the changes that passed through the interface. Open the tab `Protokoll`, choose `Art` = `Verwaltung`
(administration) and press `Anzeigen`. Every change appears with the account of the admin.

> **Check**
>
> Upload a small DICOM file in the interface, then a file of more than 1 MB. Expected: the interface reports success for both,
> and the studies appear in the tab `Studien` of the admin page.

<a id="arc-rslave-refused"></a>
### 6.4 `arc` stays down after the change of the compose file

**What you see.** `docker compose up -d` in the dcm4chee folder stops with an error like this one. The paths in your message
differ. The first path is the folder of the volume, the second is the mount that holds it. The lines below come from a test run
on Docker Desktop with the path `/tmp`; the container name is shortened to `arc`.

```text
 Container arc Recreate
 Container arc Recreated
 Container arc Starting
Error response from daemon: path /tmp is mounted on /tmp but it is not a shared or slave mount
```

`docker compose ps -a` lists `arc` with the status `Created`. The archive is down: DICOM devices get errors, and the viewer
shows nothing.

**Cause.** Edit A of [modules.md, 2.2](modules.md#edits-steps) added the volume line `- /mnt/fs:/mnt/fs:rslave`. Docker accepts
the flag [rslave](glossary.md#rslave) only when the mount that holds the folder has the
[propagation](glossary.md#mount-propagation) `shared` or `slave`. On this server it is `private`. Docker had already removed the
old container, created the new one and could not start it. Step 3 of that section checks the propagation before the change, and
`preflight.sh` warns about this state: `[WARN] mount propagation of /mnt/fs: private`.

**Fix.** Read the propagation of the folder. Use the first path of the error message in place of `/mnt/fs`:

```bash
findmnt -T /mnt/fs -o TARGET,PROPAGATION
```

If the second column says `private`, make the root mount shared, then start `arc`:

```bash
mount --make-rshared /
findmnt -T /mnt/fs -o TARGET,PROPAGATION
cd /opt/dcm4chee-arc
docker compose up -d
```

Expected from the second command: the second column says `shared`. The last command starts the container that is in the state
`Created`. dcm4chee needs 30 seconds or more to start.

`mount --make-rshared /` holds until the next reboot. Make it permanent in the way your system provides, for example with a
small systemd unit that runs the command at boot ([modules.md, step 3](modules.md#edits-steps)).

If you cannot fix the propagation now, go back to the old compose file ([modules.md, 2.3](modules.md#recreate-rollback)). This
starts `arc` without the new volume:

```bash
cp -a /root/dcm4chee-compose.before-modules.yml /opt/dcm4chee-arc/docker-compose.yml
cd /opt/dcm4chee-arc
docker compose up -d
```

> **Warning**
>
> Both ways need a second start of `arc`: the archive stays unreachable for 30 seconds or more. Keep edit A if the disk
> assistant has created a storage. Without the volume, dcm4chee cannot read the images on the new disks.

> **Check**
>
> ```bash
> cd /opt/dcm4chee-arc && docker compose ps
> docker logs arc 2>&1 | grep WFLYSRV0025
> docker inspect -f '{{range .Mounts}}{{.Destination}} {{.Propagation}}{{"\n"}}{{end}}' arc | grep '^/mnt/fs '
> ```
>
> Expected: `arc` shows `Up`. The second command prints one line with `WFLYSRV0025`, which ends with `started in` and a time. After the
> start, the last command prints `/mnt/fs rslave`. If the second command prints nothing, wait and run it again.

<a id="arc-log-dir"></a>
### 6.5 `absender_sammeln: ... No such file or directory` in the journal

**What you see.** The tiles with the senders in the tab `Firewall` stay empty. The journal of the helper service gets a line
like this one every 5 minutes. The path and the first part of the line depend on your setup. The text comes from the program;
it was not recorded from a run:

```text
absender_sammeln: /var/local/dcm4chee-arc/wildfly/log/server.log: No such file or directory. ARC_LOG_DIR in /etc/default/pacs-admin auf das Log-Verzeichnis von wildfly setzen (docker inspect arc: der Mount von /opt/wildfly/standalone, darin log/)
```

The line means: "set `ARC_LOG_DIR` in `/etc/default/pacs-admin` to the log folder of wildfly (look at the mount of
`/opt/wildfly/standalone` with `docker inspect arc`, the folder `log/` lies in it)".

```bash
journalctl -u pacs-verwaltung --since '1 hour ago' | grep absender_sammeln | tail -n 3
```

**Cause.** The helper service reads the DICOM and HL7 senders from the file `server.log` of dcm4chee. It looks for the file in
the folder `ARC_LOG_DIR` ([modules.md, 4.10](modules.md#firewall-settings)). The default is
`/var/local/dcm4chee-arc/wildfly/log/`. This folder exists only when the compose file of dcm4chee mounts
`/var/local/dcm4chee-arc/wildfly` as `/opt/wildfly/standalone`. With another mount the file is somewhere else. The rest of the
firewall works; only the senders are missing.

**Fix.** Find the folder on the server that `arc` mounts as `/opt/wildfly/standalone`:

```bash
docker inspect -f '{{range .Mounts}}{{if eq .Destination "/opt/wildfly/standalone"}}{{.Source}}{{end}}{{end}}' arc
```

The command prints the folder, for example `/srv/dcm4chee/wildfly`. If it prints nothing, `arc` has no mount for this folder.
The helper service cannot read the log then, and the sender tiles stay empty. Add the mount to the compose file of dcm4chee
before you go on.

Check that the log file is in the subfolder `log/` of that folder:

```bash
ls -l /srv/dcm4chee/wildfly/log/server.log
```

Open `/etc/default/pacs-admin` in the editor you use. Write the folder, followed by `/log/`, without spaces around `=`:

```text
ARC_LOG_DIR=/srv/dcm4chee/wildfly/log/
```

Let the helper service read the file, then read the logs of earlier days once:

```bash
systemctl restart pacs-verwaltung
set -a; . /etc/default/pacs-admin; set +a
python3 /opt/pacs-admin/server/firewall.py nachholen
```

> **Warning**
>
> Do not restart `pacs-verwaltung` while the tile `Neue Festplatte` says `läuft seit ...`. The restart stops a running disk
> setup in the middle. The service writes no audit line while it restarts ([7.3](#audit-lines-missing)).

> **Check**
>
> ```bash
> set -a; . /etc/default/pacs-admin; set +a
> python3 /opt/pacs-admin/server/firewall.py absender
> ```
>
> Expected: one line like `12 neue Zeilen` (the number differs). The journal gets no new `absender_sammeln` error line, and
> the tab `Firewall` fills the tiles with senders after a few minutes.

<a id="trouble-admin-page"></a>
## 7. Admin page and audit log

This chapter covers the page at `/admin/`, the job that fills the tab `Übersicht` (overview) and the tab `Protokoll` (audit
log). Login problems are in [chapter 5](#trouble-login). A wrong or lost audit key is in [3.3](#audit-key-mismatch).

The page shows only a short text when a call fails. It cannot read the error page of nginx. A 502 therefore shows as
`abgelehnt (HTTP 502)` ("rejected"), without a reason. The reason stands in a log ([chapter 2](#log-locations)).

<a id="admin-dienst-502"></a>
### 7.1 `abgelehnt (HTTP 502)` on the admin page

**What you see.** One of these, on a page that worked before:

- The red text `abgelehnt (HTTP 502)` in the tile `Firewall` of the tab `Übersicht`, or behind the name of an action, for
  example `Nach neuen Platten suchen: abgelehnt (HTTP 502)`.
- The info line of the tab `Protokoll` says `Fehler: Protokoll: HTTP 502`.
- The tile `Letzte Änderungen` (latest changes) says `Noch keine Änderungen über diese Seite.` ("no changes through this page
  yet") although changes were made. This tile hides every error. The text does not prove that nobody changed anything.

The rest of the site works. If every path answers 502 or 404, see [4.3](#every-page-500).

**Cause.** nginx passes every call to `/admin/dienst/` to the [helper service](glossary.md#helper-service) through the
[unix socket](glossary.md#unix-socket) `/run/pacs-admin/verwaltung.sock`. The status 502 means that nginx could not talk to
the socket. The error log of nginx names the reason:

```bash
docker logs --tail 200 ohif 2>&1 | grep 'verwaltung.sock'
```

These three lines were recorded in a test with the image `nginx:1.30`. They are shortened. The start of each line (date and
process number) differs in your log:

```text
[crit] ... connect() to unix:/run/pacs-admin/verwaltung.sock failed (2: No such file or directory) while connecting to upstream, ...
[error] ... connect() to unix:/run/pacs-admin/verwaltung.sock failed (111: Connection refused) while connecting to upstream, ...
[crit] ... connect() to unix:/run/pacs-admin/verwaltung.sock failed (13: Permission denied) while connecting to upstream, ...
```

The text in the brackets behind `failed` tells the reason:

| In the log | Meaning |
|---|---|
| `(2: No such file or directory)` | The container sees no socket file. The helper service does not run or has never run, or the container started before the folder `/run/pacs-admin` was created again. |
| `(111: Connection refused)` | The socket file exists, but nobody listens on it. This is the state after `systemctl stop pacs-verwaltung`: the service does not remove its socket files when systemd stops it. |
| `(13: Permission denied)` | The socket belongs to another uid than the one of the nginx worker processes. |

**Fix.** Work through three checks. Stop at the first one that fails.

1. The service runs and both sockets are there:

   ```bash
   systemctl is-active pacs-verwaltung
   ls -ln /run/pacs-admin/
   ```

   Expected: `active` and two sockets, `protokoll.sock` and `verwaltung.sock`. If not, go to [3.6](#no-sockets).

2. The service answers. The next call goes around nginx:

   ```bash
   curl -s --unix-socket /run/pacs-admin/verwaltung.sock http://localhost/admin/dienst/auftrag
   ```

   Expected: a short JSON text. It is `{}` when no disk setup has run since the service started. If curl prints nothing or an
   error, the service does not answer. Go to [3.6](#no-sockets).

3. The owner of the sockets is the uid of the nginx workers. The third column of `ls -ln` shows the owner. `docker top` lists
   the processes of the container with their uid:

   ```bash
   docker top ohif -eo uid,pid,comm
   ```

   Example from a test with the image `nginx:1.30`. The master process runs as root and the workers as uid 101. The number of
   workers depends on the CPUs:

   ```text
   UID                 PID                 COMMAND
   0                   91748               nginx
   101                 91794               nginx
   101                 91795               nginx
   ```

   In the image `ohif/app` the master process runs as the unprivileged user too ([reference.md](reference.md#permissions)).
   Take the uid of the worker lines. If it differs from the owner of the sockets, set `PACS_SOCKET_UID` in
   `/etc/default/pacs-admin` to that uid and restart the service:

   ```bash
   systemctl restart pacs-verwaltung
   ```

If all three checks pass and nginx still reports `(2: No such file or directory)`, the container does not see the folder. A
container keeps the folder that existed when it started ([reference.md](reference.md#sockets)). Restart it:

```bash
docker restart ohif
```

> **Warning**
>
> While the helper service is down or restarting, nginx loses every audit line. After a restart, the first line of each nginx
> worker is lost too ([reference.md](reference.md#audit-lost)). Users keep working, and nothing shows the loss. Restart
> `pacs-verwaltung` rarely and outside working hours. A restart of `ohif` cuts the connections to the viewer for a short time.

> **Check**
>
> Reload the admin page with F5. Then run:
>
> ```bash
> docker logs --since 1m ohif 2>&1 | grep 'verwaltung.sock'
> ```
>
> Expected: no output. The tile `Firewall` shows its numbers. The tile `Letzte Änderungen` lists your changes, or it says
> `Noch keine Änderungen über diese Seite.` because there were none.

<a id="cron-not-running"></a>
### 7.2 `Kein Status vorhanden` in the tab `Übersicht`

**What you see.** The line under the title of the tab `Übersicht` says:

```text
Kein Status vorhanden (dashboard-status.py läuft per cron alle 5 Minuten).
```

The line means: "no status available; `dashboard-status.py` runs every 5 minutes through cron". The tiles `Dienste` (services),
`Speicher` (storage) and `Neue Festplatte` (new disk) are hidden. In the normal state the line says
`Stand <date and time>, neu alle 5 Minuten` ("state of ..., renewed every 5 minutes"). If that date is more than 10 minutes
old, the job has stopped. This entry applies then too.

**Cause.** The page reads the file `status.json` from `/admin/daten/status.json`. The [cron](glossary.md#cron) job
`/etc/cron.d/pacs-dashboard` writes the file every 5 minutes with `dashboard-status.py`. nginx reads it from the folder
`/var/lib/pacs-admin/status` of the server. The page shows the line when nginx does not return the file. There are two kinds
of reason: the job does not write the file, or nginx does not see it.

**Fix.** Work through three steps.

**Step 1. Cron runs and knows the job.**

```bash
systemctl is-active cron
ls -l /etc/cron.d/pacs-dashboard
```

Expected: `active`, and one line for the file with the owner `root`. A minimal Debian has no cron. Install and start it:

```bash
apt install cron
systemctl enable --now cron
```

If the file is missing, copy it again ([install.md, 4.7](install.md#overview-cron)). Keep the name `pacs-dashboard` without a dot.
Keep the owner `root` and give nobody else write access. Cron ignores a file that breaks these rules (a typical rule of
Debian; not run for this page). `journalctl -u cron -n 20 --no-pager` shows what cron says about the file.

**Step 2. The job runs without an error.** The next commands do what the cron line does and show the error output on the
screen:

```bash
sh -c '{ set -a; [ ! -r /etc/default/pacs-admin ] || . /etc/default/pacs-admin; set +a; python3 /opt/pacs-admin/server/dashboard-status.py >/dev/null; }'
echo "exit code: $?"
```

Expected: only the line `exit code: 0`. The cron job writes everything that the command prints on stderr into
`/var/log/pacs-dashboard.log`. The file stays empty while all is well:

```bash
tail -n 20 /var/log/pacs-dashboard.log
```

A message from the by-hand run or from the log tells the cause:

| Message | Cause and fix |
|---|---|
| `/bin/sh: 3: /etc/default/pacs-admin: Syntax error: Unterminated quoted string` | The settings file has a syntax error, here a quote that is never closed. The shell stops, and Python does not start. The number is the line where the shell gave up. A by-hand run starts the line with `sh:`. Find the faulty line and correct it. `sh -n /etc/default/pacs-admin` checks the file without running it. |
| `sh: 2: /etc/default/pacs-admin: DICOM (old)}: not found` | A value with spaces or braces has no quotes. This is the message for the line `FW_PORT_NAMES={"104": "DICOM (old)"}`. The shell takes the part behind the first space as a command. The job goes on, but the variable is damaged. Put single quotes around the value ([reference.md](reference.md#env-file-rules)). |
| `dashboard-status.py: STORAGE_WARN_GB=300GB ist keine ganze Zahl ohne fuehrende Null mit hoechstens 6 Stellen (/etc/default/pacs-admin)` | The message says: "is not a whole number without a leading zero and with at most 6 digits". `STORAGE_FREE_GB` and `STORAGE_WARN_GB` take digits only. These values fail: `300GB`, `0050`, `1234567`. The name and the value in your message differ. |
| `dashboard-status.py: pacs-storage.sh kandidaten: <reason>` | The job asks the disk assistant for the write list and for blank disks, and that call failed. The job still writes `status.json` first and ends with exit code 1 after that. The tile `Speicher` then says `Schreibliste nicht lesbar (LDAP-Container und pacs-storage.sh kandidaten prüfen).` ("write list not readable ..."). The `<reason>` is the text of a `HALT:` line, or `Exit-Code N: <last line of the error>`, or `antwortet nicht (nach 200 s abgebrochen)` ("does not answer, stopped after 200 s"). Entry [8.1](#disk-halt) explains the `HALT:` lines. |
| `python3: can't open file '/opt/pacs-admin/server/dashboard-status.py': [Errno 2] No such file or directory` | The repository does not lie in `/opt/pacs-admin`. Change the path in the cron file with the `sed` command in [3.6](#no-sockets). |

Two more messages do not stop the job. The job still writes the file, and only the tile `Dienste` stays hidden ("Kachel" is
German for "tile"):

```text
dashboard-status.py: docker nicht gefunden, die Kachel Dienste bleibt leer (Docker installieren)
dashboard-status.py: docker antwortet nicht (nach 60 s abgebrochen), die Kachel Dienste bleibt leer
```

The first message means that `docker` is not in the path of the job. Docker is not installed, or its folder is not in the
`PATH` line of the cron file. The second message means that the Docker daemon did not answer for 60 seconds.

The button `Jetzt suchen` (search now) of the tile `Neue Festplatte` runs the same script through the helper service. If the
script fails, the page shows the last line of its error and `(HTTP 500)`. This holds for every message of the table above:

```text
Nach neuen Platten suchen: dashboard-status.py: STORAGE_WARN_GB=300GB ist keine ganze Zahl ohne fuehrende Null mit hoechstens 6 Stellen (/etc/default/pacs-admin) (HTTP 500)
```

The helper service reads `/etc/default/pacs-admin` only when it starts. Cron reads it at every run. After you correct the file,
the next cron run is good at once. The button keeps the old values until the service restarts.

The tile `Speicher` can also say `Keine Daten zu den Platten (status.json nennt keine; STORAGE_BASE und STORAGE_PREFIX prüfen).`
("no data on the disks; status.json names none; check STORAGE_BASE and STORAGE_PREFIX"). The file exists, but its list of disks
is empty. The job lists the folders whose name is the setting `STORAGE_PREFIX` plus digits in the folder `STORAGE_BASE`. The
defaults are `PACS-Data` and `/mnt/fs`, so a disk is `/mnt/fs/PACS-Data01`. No folder matches. Look at the folders and at the
two settings:

```bash
ls -d /mnt/fs/PACS-Data*
grep -E '^(STORAGE_BASE|STORAGE_PREFIX)=' /etc/default/pacs-admin
```

The second command prints nothing when you use the defaults. Correct the settings or create the mount points
([modules.md, 3.2](modules.md#disk-prepare)). The next cron run shows the disks.

**Step 3. nginx sees the file.**

```bash
ls -l --time-style=full-iso /var/lib/pacs-admin/status/status.json
docker exec ohif ls -l /srv/pacs-admin/status/
```

Expected: both commands list `status.json`. If the first command lists the file and the second shows an empty folder or an
error, the container does not see the folder. There are three reasons:

- The compose file has no mount for `/var/lib/pacs-admin/status`. Add it ([reference.md](reference.md#mounts)).
- The container started before the folder existed, or somebody deleted the folder and created it again. Restart the
  container: `docker restart ohif`.
- You set `PACS_ADMIN_VAR`. The job then writes to `$PACS_ADMIN_VAR/status/`, and the compose file must mount that folder.

> **Warning**
>
> Restart `pacs-verwaltung` only when you changed a setting that the service uses, for example `PACS_SOCKET_UID`. The overview
> does not need it, because cron reads `/etc/default/pacs-admin` at every run. A restart stops a disk setup that runs, and it
> loses audit lines ([reference.md](reference.md#audit-lost)).

> **Check**
>
> ```bash
> ls -l --time-style=full-iso /var/lib/pacs-admin/status/status.json
> date
> ```
>
> Expected: the file has the owner `root` and the mode `-rw-r--r--`. Its time is less than 5 minutes older than the time that
> `date` prints. `/var/log/pacs-dashboard.log` gets no new line. Reload the page with F5. The line under the title says
> `Stand <date and time>, neu alle 5 Minuten`, and the tiles `Speicher` and `Neue Festplatte` are back. The tile `Dienste`
> returns when Docker works for the job.

<a id="audit-lines-missing"></a>
### 7.3 The tab `Protokoll` misses lines that you expect

**What you see.** You searched, opened a study or a report, or changed something on the admin page. The tab `Protokoll` does
not list it. Or the tab says `Keine Einträge in diesem Zeitraum.` ("no entries in this period") for a day with activity.

**Cause.** A line can be lost on its way, or the tab can hide it. The database tells which one. Ask it for the day and the
tag. The tag `ereignisse` holds searches and opened studies and reports. The tag `admin` holds changes made on the admin page.
Replace the day:

```bash
set -a; . /etc/default/pacs-admin; set +a
python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse 2026-10-14 2026-10-14 | tail -n 5
```

The program prints one JSON line per row. Example of a row ([reference.md](reference.md#audit-wire-format)):

```text
{"t":"2026-10-14T10:58:23+02:00","u":"anna","sub":"anna","ip":"192.0.2.10","r":"/dcm4chee-arc/aets/DCM4CHEE/rs/studies/1.2.3/series","status":200}
```

- The row is there: the tab hides it. Go to step 2.
- The row is not there: the line was lost. Go to step 1.

**Fix.**

**Step 1. The line was lost.** Look for the two known reasons:

```bash
docker logs ohif 2>&1 | grep 'to syslog'
journalctl -u pacs-verwaltung --since '1 day ago' --no-pager | grep 'Protokoll nicht abgelegt'
```

- Lines with `to syslog` in the log of nginx: nginx could not hand the line over, because the helper service was down or
  restarting. These lines are lost for good. Find the time of the gap with `journalctl -u pacs-verwaltung`. Start the service if
  it is down ([3.6](#no-sockets)).
- Lines `Protokoll nicht abgelegt (N Zeilen), neuer Versuch in 10 s: ...` ("audit log not stored (N lines), new try in 10 s")
  in the journal: the service could not write the database. It keeps the lines in memory and tries again every 10 seconds.
  The text behind the colon names the reason, for example the key file or a full disk. Fix the reason ([3.3](#audit-key-mismatch)).
  The service stores the lines at the next try.
- Neither of the two: the request did not pass nginx. The audit log does not record a call to a published HTTP port of
  dcm4chee itself, nor a DICOM or HL7 connection.

**Step 2. The tab hides the line.** The tab shows only a part of what the database holds:

| Rule of the tab | What it hides |
|---|---|
| It loads the tags `ereignisse` and `admin` only. | Every other request. The tag `zugriffe` holds all requests, but the tab never shows it. |
| It knows five kinds of rows: study search, patient search, opened study, opened report and change. | Requests for images, thumbnails or static files. |
| It skips a search whose only filter is `StudyInstanceUID`. | OHIF and the page send such a search when they open a study. The row `Studie geöffnet` records the opening. |
| The same account with the same action on the same study or search within 30 minutes is one row. | The repeats. `admin` rows are never merged. |
| It shows at most 2000 rows, the newest first. | The older rows. The info line says `N Einträge, nur die neuesten 2000, Filter enger setzen`. |
| It skips a line without a readable `t` or `r` and counts it. | The info line adds `N unlesbare Zeilen übersprungen`. |
| The filters `Patienten-ID` and `Patientenname` ask dcm4chee for the studies. | Rows of a study that dcm4chee no longer holds, for example a deleted study. |
| It loads the days from `Von` to `Bis`. The default is the last 30 days. | Days outside that range. Near midnight the days differ between the server and the browser ([7.4](#audit-timezone)). |

Set `Art` to `alle`, empty all other filters and choose a range that includes the day before and the day after. Press
`Anzeigen`. The info line shows the number of rows.

> **Warning**
>
> The database is the record. The tab is only a view of it. A line lost in step 1 cannot be restored. Do not restart
> `pacs-verwaltung` while its journal says `Protokoll nicht abgelegt`: the lines in memory are gone after the restart.

> **Check**
>
> Open the study list in the viewer and search for a study. Wait 5 seconds. Then run:
>
> ```bash
> set -a; . /etc/default/pacs-admin; set +a
> python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse $(date +%F) | tail -n 1
> ```
>
> Expected: one JSON line with your account in `u` and the time of the search in `t`. In the tab `Protokoll`, `Heute` and
> `Anzeigen` show the search as a row `Suche` at the top.

<a id="audit-timezone"></a>
### 7.4 The times in the tab `Protokoll` differ from the clock

**What you see.** One of these:

- A row shows a time that is one or two hours off from the time of the action.
- Rows from shortly after midnight are missing when you choose a single day, or they appear under the day before.

**Cause.** Three time zones take part. The audit log stores the right moment in every case. The day limits depend on the zone:

| Where | Which zone | What it does |
|---|---|---|
| nginx in the container | The zone of `/etc/localtime` in the container. Without the mount: UTC. | Writes the time of each request with its offset, for example `2026-10-14T10:58:23+02:00` (field `t`). |
| The helper service on the server | The time zone of the server | Cuts the days `Von` and `Bis` at midnight of the server. |
| The browser | The time zone of the PC | Shows the times and cuts the days again at its own midnight. |

A row with the offset `+00:00` is still the right moment, and the browser shows it in its own zone. The day limits are the
problem. Take a server in UTC and a browser at `+02:00`: the rows between 00:00 and 02:00 of the browser day belong to the
day before for the helper service, and it does not load them.

**Fix.** Put server, container and browsers into the same zone. First read the offsets:

```bash
date +%z
docker exec ohif date +%z
```

Both commands must print the same offset, for example `+0200`. If the container differs, mount `/etc/localtime` read-only
into it. The compose examples have this line in the volumes of `ohif`:

```text
      - /etc/localtime:/etc/localtime:ro
```

Recreate the container in the folder of its compose file:

```bash
cd /opt/ohif
docker compose up -d
```

A container reads the time zone when it starts (typical behaviour; not run for this page). After you change the zone of the
host, restart the container: `docker restart ohif`. Until the zones agree, choose one day earlier in `Von` and one day later in
`Bis`.

> **Warning**
>
> Rows that are already stored keep their offset. Their moment is right, and they need no repair. Do not edit the database.

> **Check**
>
> ```bash
> date +%z
> docker exec ohif date +%z
> ```
>
> Expected: the same offset twice. A new row carries this offset in `t`:
>
> ```bash
> set -a; . /etc/default/pacs-admin; set +a
> python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse $(date +%F) | tail -n 1
> ```
>
> Expected: `t` ends with the offset of the server, for example `+02:00`.

<a id="trouble-disk"></a>
## 8. Disk assistant

This chapter covers the tiles `Speicher` (storage) and `Neue Festplatte` (new disk) of the tab `Übersicht` and the script
`pacs-storage.sh` behind them ([modules.md, section 3](modules.md#disk-assistant)). The script appends the output of each call
to `/var/log/pacs-storage.log` (the setting `STORAGE_LOG`). The call `kandidaten` writes no log. The first checks of the script
(the settings and the lock) run before the logging starts. Their `HALT:` lines show on the screen and on the page, but not in
the log. The log is the first place to look:

```bash
tail -n 40 /var/log/pacs-storage.log
```

When a check fails, the script prints a line that starts with `HALT:` and stops. A failed action shows
`<action>: <reason> (HTTP <status>)` in red on the admin page. The status number tells the kind of failure:

| Status | Meaning |
|---|---|
| 409 | The script or the helper service refused the action. The reason is the text of the `HALT:` line without the word `HALT:`. See [8.1](#disk-halt). |
| 500 | The change is in the LDAP configuration, but `arc` did not reload it. The reason starts with `Archiv-Konfiguration nicht neu geladen`. Or the status script failed, and the reason is the last line of its error. See [8.3](#disk-half-done) and [7.2](#cron-not-running). |
| 504 | A script ran longer than 300 seconds, and the helper service stopped it. See [8.3](#disk-half-done). |
| 400 | The helper service did not accept the request. Reload the page with F5. See [8.1](#disk-halt). |

The exit codes of the script (0, 1 and 3) are in [reference.md](reference.md#storage-exit-codes).

<a id="disk-halt"></a>
### 8.1 A `HALT:` line when you set up or change a disk

**What you see.** One of these:

- The red box `Abgebrochen` ("cancelled") in the tile `Neue Festplatte <name>` shows a line that starts with `HALT:`. The
  text under `Ausgabe des Skripts` ("output of the script") holds the whole output. If the output has no `HALT:` line, the box
  says `siehe Ausgabe` ("see output").
- A red message behind the name of an action, for example `Platte einrichten: <reason> (HTTP 409)`. For the buttons of the tile
  `Speicher`, the name is the success text of the button and the short name of the disk, for example
  `Markierung voll entfernt: 02: <reason> (HTTP 409)`. The reason is the text of the `HALT:` line.
- `nicht ausgeführt, siehe Log von pacs-storage.sh` ("not carried out, see the log of pacs-storage.sh"). The script ended with an
  error but printed no `HALT:` line. The last lines of the log show the cause.
- One of the messages of the helper service in the last table of this entry.

**Cause.** The script checks the settings, the disk and the archive before and during each step. If a check fails, it prints
`HALT:` with the reason and stops. The steps before that line have run. The `ok` lines in the log show which ones
([8.3](#disk-half-done) lists them).

**Fix.** Run the script by hand to see the `HALT:` line on the screen. The command `scan` changes nothing. It makes the kernel
look for new disks and lists what the script finds:

```bash
bash /opt/pacs-admin/server/pacs-storage.sh scan
```

Find the message in the tables below. They follow the order of the checks. The words in brackets give the English meaning. A
name or a number in your message differs from the example.

**A. At the start of every call.**

| Message | Cause and fix |
|---|---|
| `als root aufrufen` | ("call as root") You ran the script as a normal user. This line has no `HALT:` in front. Open a root shell with `sudo -i` and run the command again. |
| `HALT: /etc/default/pacs-admin hat einen Syntaxfehler (Meldung davor)` | ("has a syntax error, message before") The settings file has a mistake that bash cannot read, for example a quote that is never closed. The message of bash stands in the line above, for example ``/etc/default/pacs-admin: line 1: unexpected EOF while looking for matching `"'``. Find the line and correct it. `bash -n /etc/default/pacs-admin` checks the file without running it. |
| `HALT: STORAGE_MIN_GB='100GB' ist keine ganze Zahl ohne fuehrende Null mit hoechstens 6 Stellen (/etc/default/pacs-admin)` | ("is not a whole number without a leading zero and with at most 6 digits") `STORAGE_MIN_GB` and `STORAGE_FREE_GB` take digits only, with no unit. These values fail: `100GB`, `0100`, `1234567`. The name and the value in your message differ. Correct the line. The next call reads the file again. `STORAGE_WARN_GB` has the same rule. The status job checks it ([7.2](#cron-not-running)). |
| `HALT: STORAGE_PREFIX 'PACS Data' ungueltig (Buchstabe, dann Buchstaben, Ziffern, - und _, hoechstens 14 Zeichen: ext4-Label max. 16)` | ("invalid: a letter, then letters, digits, - and _, at most 14 characters: an ext4 label has at most 16") The name of a disk is the prefix plus two digits, and an ext4 label has at most 16 characters. Correct `STORAGE_PREFIX`. Change the prefix only before the first disk exists. Disks that have the old prefix would not match any more. |
| `HALT: laeuft schon, ein anderer Aufruf von pacs-storage.sh haelt die Sperre /run/pacs-storage.lock seit ueber 30 s` | ("is already running, another call holds the lock for more than 30 s") Only one call runs at a time. The wait time is 30 seconds, and 120 seconds for the status job. Wait until the other call ends, then try again. The loop below shows the holder. |

A line with a stray word, such as `STORAGE_MIN_GB=100 GB`, passes the check `bash -n`. When the script reads the file, bash
prints `line 1: GB: command not found`, and the setting stays unset. The script then uses the default value, without a `HALT:`
line. Read the settings that the file contains with `grep -E '^(STORAGE_|ARC_|LDAP_)' /etc/default/pacs-admin` and check each
line by eye.

The next loop lists the processes that hold the lock, with their process number and command line. It uses only tools that
every Debian has. A child process of the script, for example `mkfs.ext4`, keeps the lock even after the script itself has
ended:

```bash
for p in /proc/[0-9]*; do ls -l $p/fd 2>/dev/null | grep -q /run/pacs-storage.lock && echo "${p#/proc/} $(tr '\0' ' ' < $p/cmdline)"; done
```

Wait for the holder to end. Stop it only when it hangs ([G](#disk-halt) below). Do not delete the file `/run/pacs-storage.lock`.

**B. Docker and LDAP.** The commands `scan`, `auto`, `add`, `activate`, `grow`, `freigeben`, `anhaengen` and `abhaengen` check
these points first. They read the AE of the archive from the LDAP server, so they stop before they change anything. The
command `kandidaten` does not make this check.

| Message | Cause and fix |
|---|---|
| `HALT: docker nicht gefunden (Docker installieren, z. B. apt install docker.io)` | ("docker not found, install Docker") The script finds no `docker` command. It needs Docker to read the archive configuration. Install Docker, or make sure that `docker` is in the path of the user that runs the script. |
| `HALT: AE 'DCM4CHEE' (Geraet 'dcm4chee-arc') steht nicht im LDAP von 'ldap'. ARC_AET, ARC_DEVICE und LDAP_BASE_DN in /etc/default/pacs-admin pruefen (docs/modules.de.md#disk-assistant)` | ("AE ... (device ...) is not in the LDAP of ...; check ARC_AET, ARC_DEVICE and LDAP_BASE_DN") The three settings do not match your archive. The next two commands show the AE title and the device name. Put them into `ARC_AET` and `ARC_DEVICE`. Check `LDAP_BASE_DN` too (default `dc=dcm4che,dc=org`). |
| `HALT: LDAP nicht lesbar (Container 'ldap'): <last line>. Pruefen: docker ps (Name = LDAP_CONTAINER), LDAP_ROOTPASS oder LDAP_ROOTPASS_FILE in der Umgebung des LDAP-Containers (docs/modules.de.md#disk-assistant)` | ("LDAP not readable ... Check: docker ps (name = LDAP_CONTAINER), LDAP_ROOTPASS or LDAP_ROOTPASS_FILE in the environment of the LDAP container") The script runs `ldapsearch` inside the LDAP container. `<last line>` is the last line of the error. The next table lists the usual ones. |

```bash
curl -s http://127.0.0.1:8080/dcm4chee-arc/aets | grep -o '"dicomAETitle" *: *"[^"]*"'
curl -s http://127.0.0.1:8080/dcm4chee-arc/devices | grep -o '"dicomDeviceName" *: *"[^"]*"'
```

The first command is the same as in [6.1](#viewer-no-studies). The second command is typical for dcm4chee-arc. It was not run
for this page. Use the `ARC_URL` of your install instead of `http://127.0.0.1:8080`.

| Last line of the error | Cause and fix |
|---|---|
| `Error response from daemon: No such container: ldap` | The container name is wrong. This text was recorded with Docker 29.8.0. `docker ps --format '{{.Names}}'` lists the names. Put the name of the LDAP container into `LDAP_CONTAINER`. |
| `Error response from daemon: container <64 hex characters> is not running` | The LDAP container is stopped. This text was recorded with Docker 29.8.0. Start it with `docker start ldap`. `docker logs --tail 50 ldap` shows why it stopped. |
| `LDAP_ROOTPASS im LDAP-Container nicht gesetzt` | ("LDAP_ROOTPASS not set in the LDAP container") The script reads the root password from the environment of the LDAP container. The container has neither `LDAP_ROOTPASS` nor `LDAP_ROOTPASS_FILE`. Add one of them to the compose file (edit C in [modules.md](modules.md#edits-overview)). |
| `ldap_bind: Invalid credentials (49)` | The LDAP server did not accept the root account of the container. Typical wording of OpenLDAP; not run for this page. Check `LDAP_ROOTDN` and the password in the compose file. |
| `ldap_sasl_bind(SIMPLE): Can't contact LDAP server (-1)` | The LDAP server does not run yet or not any more. Typical wording of OpenLDAP; not run for this page. `docker logs --tail 50 ldap` shows its state. |

**C. Formatting a new disk (`add`).**

| Message | Cause and fix |
|---|---|
| `HALT: Aufruf: add /dev/sdX [ja]` | ("usage") You gave no device on the command line. The commands `activate`, `grow`, `freigeben`, `anhaengen` and `abhaengen` print the same kind of line. The page always sends the argument. |
| `HALT: /dev/sdc wird nicht formatiert: <reasons>` | ("is not formatted") The script formats only a disk that is empty. The reasons stand behind the colon, joined with `;`. The next table explains each one. |
| `HALT: /mnt/fs/PACS-Data02 existiert und ist nicht leer`, `HALT: Label PACS-Data02 gibt es schon` or `HALT: PACS-Data02 steht schon im LDAP` | ("exists and is not empty", "label ... exists already", "is in the LDAP already") These checks rarely fire. The script takes the next number from the storages in LDAP, the folders below `/mnt/fs` and the labels in `/etc/fstab`. A hit means that something carries the name already: a folder with content (`ls -A /mnt/fs/PACS-Data02`), a file system with this label that is not mounted (`blkid -L PACS-Data02`) or a storage in the archive. Find out what it is. It can be a PACS disk that lost its mount ([8.4](#disk-not-mounted)). Do not format another disk under the same name. |
| `HALT: mkfs fehlgeschlagen` | ("mkfs failed") `mkfs.ext4` failed. Its message stands in the line above. Nothing else has changed. If it says `mkfs.ext4: command not found`, install `e2fsprogs` with `apt install e2fsprogs` (typical; not run). If `mkfs.ext4` wrote a part of the disk before it failed, the next call stops with `Signatur` or `erstes MiB nicht leer`. Wipe the disk as described below. |
| `HALT: mount fehlgeschlagen. fstab-Zeile steht, Sicherung /etc/fstab.bak-20261014-101503` | ("mount failed, the fstab line is in place, backup ...") The disk is formatted and the line is in `/etc/fstab`, but the mount failed. The message of `mount` stands in the line above. The date in the file name differs. Go to [8.3](#disk-half-done). |
| `HALT: /mnt/fs/PACS-Data02 ist nicht /dev/sdc` | ("is not /dev/sdc") The folder is mounted, but another device is mounted there. Go to [8.3](#disk-half-done). |

The reasons behind `wird nicht formatiert`:

| Reason | Meaning and fix |
|---|---|
| `kein Blockgeraet` | ("not a block device") The path is not a disk. Check the name with `lsblk`. |
| `Typ part`, `Typ loop`, `Typ lvm` | ("type ...") The device is not a whole disk. Give the whole disk (`/dev/sdc`), not a partition (`/dev/sdc1`). |
| `schreibgeschuetzt` | ("write-protected") The disk is read-only. Remove the protection in the hypervisor or on the hardware. |
| `hat Partitionen` | ("has partitions") The disk has a partition table with partitions. |
| `in Benutzung (LVM/RAID)` | ("in use") LVM or RAID uses the disk. Use another disk, or release this one with the tools of LVM or RAID. |
| `Signatur ext4` | ("signature") The disk carries a mark of an earlier use. Other examples are `swap` and `LVM2_member`. A partition table can count too, with `gpt` or `dos` (typical wording; not run). |
| `Dateisystem ext4` | ("file system") A file system is on the disk. |
| `gemountet` | ("mounted") The disk is mounted. `findmnt -S /dev/sdc` shows where. Check that you named the right device. |
| `steht in /etc/fstab` | ("is in /etc/fstab") A line in `/etc/fstab` names this device. Device names such as `/dev/sdc` can change after a reboot, so the line may belong to another disk. `grep -w /dev/sdc /etc/fstab` shows it. The script never removes a line itself. |
| `Swap` | The disk is in use as swap space. |
| `kleiner als 100 GiB` | ("smaller than ...") The disk is smaller than `STORAGE_MIN_GB`. The number in your message is your value. Use a larger disk, or lower `STORAGE_MIN_GB` if you want a smaller one. |
| `erstes MiB nicht leer` | ("first MiB not empty") The first megabyte of the disk holds data that is not zero. |

**Wipe a disk that you may wipe.** The reasons `hat Partitionen`, `Signatur`, `Dateisystem` and `erstes MiB nicht leer` mean that
somebody used the disk before. If you are sure that the disk is the right one and holds nothing that you need, wipe it.

> **Warning**
>
> The next two commands destroy the data on the disk at once. Nothing brings it back. Check the device name twice.
> `lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINT` shows the size, the model and the serial number of every disk. A wrong name wipes a
> disk of the system or of the archive. Never wipe a disk that is mounted or that stands in `/etc/fstab`. Never weaken a check
> of the script to format a disk that it refuses.

```bash
wipefs -a /dev/sdc
dd if=/dev/zero of=/dev/sdc bs=1M count=1
```

`wipefs -a` removes the marks (signatures) of earlier file systems and tables. It does not clear the first MiB. `dd` writes
zeros into it. Both steps were tested on a file that held a swap signature. After `wipefs -a`, the signature was gone and the
first MiB was still not empty. After `dd`, the first MiB was empty. The ext4 case follows the manual page of `wipefs` and was
not run. If `lsblk` still shows partitions below the disk, make the kernel read the table again with
`blockdev --rereadpt /dev/sdc` (typical; not run). Then choose `Jetzt suchen`, or wait up to 5 minutes.

**D. Putting a disk into the archive (`activate`; `add` runs it at the end).**

| Message | Cause and fix |
|---|---|
| `HALT: /mnt/fs/PACS-Data02 ist nicht gemountet` | ("is not mounted") No disk is mounted there. See [8.4](#disk-not-mounted). |
| `HALT: kein Vorlage-Storage gefunden` | ("no template storage found") The new storage copies the settings of an existing one. The script takes the first storage of the write list of the AE, or else the storage with the highest number that starts with `STORAGE_PREFIX`. It found none, or only the new one. Give the AE a first storage in the dcm4chee user interface, then run the setup again (typical; not run). |
| `HALT: arc sieht /mnt/fs/PACS-Data02 nicht, Archiv NICHT geaendert. arc braucht '- /mnt/fs:/mnt/fs:rslave' in Compose und` | ("arc does not see ..., archive NOT changed. arc needs ... in compose and") The message has two lines. The second line is `einmal neu erzeugen (Ausfall ~30 s). Danach: <script> activate PACS-Data02 ja` ("create once more, outage about 30 s. Afterwards: ..."). The page shows only the first line. The second stands under `Ausgabe des Skripts` and in the log. The container `arc` does not see the new mount, because its volume lacks the option `rslave` ([glossary](glossary.md#rslave)). Do the change in [modules.md, section 2](modules.md#recreate-arc). If `arc` stays down afterwards, see [6.4](#arc-rslave-refused). Then run `bash /opt/pacs-admin/server/pacs-storage.sh activate PACS-Data02 ja`. The disk is formatted and mounted already, so `activate` formats nothing. |
| `HALT: arc kann in /mnt/fs/PACS-Data02 nicht schreiben, Archiv NICHT geaendert` | ("arc cannot write in ..., archive NOT changed") The test file could not be written inside `arc` as the user `STORAGE_OWNER`. The owner of the folder is wrong. `docker exec arc id wildfly` shows the numbers of the account that runs WildFly ([modules.md, step 3](modules.md#disk-prepare)). Put them into `STORAGE_OWNER` as `UID:GID`. Set the owner of the folder: `chown 1023:1023 /mnt/fs/PACS-Data02 && chmod 755 /mnt/fs/PACS-Data02` (use your numbers). Then run `activate PACS-Data02 ja`. |
| `HALT: Storage PACS-Data02 nicht angelegt`, `HALT: dcmObjectStorageID nicht ergaenzt` or `HALT: dcmMetadataStorageID nicht ergaenzt` | ("storage not created", "... not added") The change in LDAP failed. The message of `ldapmodify` stands above the `HALT:` line. `docker logs --tail 50 ldap` can help. The steps before it have run. Go to [8.3](#disk-half-done). |
| `ACHTUNG: Archiv-Konfiguration nicht neu geladen (Antwort 000). Die Aenderung steht im LDAP, ...` | ("ATTENTION: archive configuration not reloaded (answer ...). The change is in the LDAP, ...") This line starts with `ACHTUNG:`, not with `HALT:`. The exit code is 3. Go to [8.3](#disk-half-done). |
| `ACHTUNG: PACS-Data02 nicht in http://127.0.0.1:8080/dcm4chee-arc/storage` | ("not in ...") The setup ended with exit code 0, but the list of storages of the archive does not show the new name. The tile can still say `eingerichtet`. Go to [8.3](#disk-half-done), the check of the case C. |

**E. Buttons of the tile `Speicher` (`freigeben`, `anhaengen`, `abhaengen`).**

| Message | Cause and fix |
|---|---|
| `HALT: /mnt/fs/PACS-Data02 ist nicht gemountet` | See [8.4](#disk-not-mounted). |
| `HALT: PACS-Data02 hat nur 12 GiB frei, unter 50 GB bleibt die Markierung` or `... unter 50 GB nicht in die Schreibliste` | ("has only 12 GiB free; below 50 GB the mark stays" or "not into the write list") The disk has less free space than `STORAGE_FREE_GB`. The limit is in GB (1,000,000,000 bytes) and the free space is in GiB (1,073,741,824 bytes), so 50 GB are about 47 GiB. The page offers the buttons from the numbers of `status.json`, which can be 5 minutes old. Make room on the disk, enlarge it (`grow` in [modules.md](modules.md#disk-operate)) or add a disk. |
| `HALT: PACS-Data02 steht nicht im Archiv, mit activate eintragen` | ("is not in the archive, enter it with activate") The disk is mounted, but the archive has no storage of this name. Enter it with `bash /opt/pacs-admin/server/pacs-storage.sh activate PACS-Data02 ja` (without `ja` the command only shows what it would do). |
| `HALT: PACS-Data01 ist in dcmObjectStorageID die letzte Platte, die nicht voll ist. Erst eine andere aufnehmen.` | ("is the last disk in dcmObjectStorageID that is not full. Add another one first.") The archive needs one storage that is not full in each list. `dcmObjectStorageID` is the list for the image files, `dcmMetadataStorageID` the list for the metadata. Put another disk with room into the list first (`In Schreibliste aufnehmen`). Then take this one out. |
| `HALT: Markierung bei PACS-Data02 nicht entfernt`, `HALT: dcmObjectStorageID nicht geaendert` or a line ending in `nicht ergaenzt` | ("mark not removed", "not changed", "not added") The change in LDAP failed. The message of `ldapmodify` stands above the `HALT:` line. Run the same action again. It skips what is done. If a list is changed and the other is not, the rerun finishes the work. |

**F. Enlarging a disk (`grow`, command line only).**

| Message | Cause and fix |
|---|---|
| `HALT: /dev/sdc ist kein gemounteter Storage unter /mnt/fs` | ("is not a mounted storage below ...") The device is not the one of a mounted PACS disk. The second column under `--- Storages` in the output of `scan` shows the right device. |
| `HALT: resize2fs fehlgeschlagen` | ("resize2fs failed") The message of `resize2fs` stands in the line above. The file system is unchanged. |

**G. Messages of the helper service.** They do not come from the script.

| Message | Cause and fix |
|---|---|
| `Es wird gerade schon eine Platte eingerichtet.` (HTTP 409) | ("A disk is being set up right now.") The helper service allows one setup at a time. The tile `Neue Festplatte <name>` shows the job with `läuft seit <time>`. Wait for its end. As a rule of thumb, a setup takes minutes, not hours. If the tile says `läuft seit` for much longer than 10 minutes, look at the processes and the log with the commands below the table. A script that hangs keeps the record. `systemctl restart pacs-verwaltung` clears the record, but it also stops a setup that runs. Read the Warning in [7.2](#cron-not-running) first. |
| `Die Platte ist nicht mehr genau so als leer erkannt. Bitte neu suchen.` (HTTP 409) | ("The disk is no longer recognised as empty in exactly this way. Please search again.") Before it starts, the helper service asks the script for the empty disks once more. The device, the size or the next name differs from what the page showed, or the disk is not empty any more. Choose `Jetzt suchen` (or press F5), compare the offer with `lsblk` and confirm again. If the offer is gone, see [8.2](#disk-not-offered). |
| `kein Plattengerät`, `Anfrage unvollständig` (HTTP 400) | ("no disk device", "request incomplete") The service accepts only whole disks with names like `/dev/sdc`, `/dev/vdb`, `/dev/xvdb` or `/dev/nvme0n1`. The page sends only names from its offer, so the page may be old. Reload it with F5. A disk of another kind, for example `/dev/mmcblk0`, only goes through `add` on the command line. |
| `keine PACS-Platte` (HTTP 400) | ("no PACS disk") The name of the disk is not `STORAGE_PREFIX` plus digits. The helper service reads `STORAGE_PREFIX` only when it starts. If you changed the prefix, restart the service when no setup runs. |
| `FEHLER im Dienst: <text>` at the end of `Ausgabe des Skripts` | ("error in the service") The helper service failed while it ran the script, for example because a file is missing (`[Errno 2] No such file or directory: ...`), or because the refresh of the overview ran longer than 300 seconds. The text names the error. If the lines above it end with `fertig.`, the setup itself is complete. |

The commands for the hanging setup in the first row of the table (the package `procps` provides `pgrep`):

```bash
pgrep -af pacs-storage.sh
pgrep -af dashboard-status.py
tail -n 20 /var/log/pacs-storage.log
```

Each `pgrep` line shows the process number and the command line of a running script. No output means that the script does not run.

> **Check**
>
> ```bash
> bash /opt/pacs-admin/server/pacs-storage.sh scan
> ```
>
> Expected: the four sections `--- Storages`, `--- Leere Platten (add)`, `--- Vergroesserte Platten (grow)` and
> `--- NO_MOUNT fehlt unter dem Mountpunkt (nomount)`, and no line that starts with `  HALT:`. Then repeat the action on the
> page.

<a id="disk-not-offered"></a>
### 8.2 The tile `Neue Festplatte` does not offer the new disk

**What you see.** You gave the server a new, empty disk. The tile `Neue Festplatte` ("new hard disk") still says
`Keine leere Platte gefunden.` ("no empty disk found"). It shows three steps and the button `Jetzt suchen` ("search now").

**Cause.** The list of empty disks comes from the call `pacs-storage.sh kandidaten`. The status job runs it every 5 minutes and
writes the result to `status.json` ([glossary](glossary.md#status-json)). `Jetzt suchen` runs the same job at once. A disk is
missing from the list for one of these reasons:

- The server does not see the disk. The cause is then in the hypervisor, in the cable or in the controller.
- The script refuses the disk, for example because it holds a partition table or a file system ([8.1](#disk-halt)).
- The name of the device is not one that the page accepts.
- The status job failed, or the page shows old numbers ([7.2](#cron-not-running)).
- A disk setup that ended less than 30 minutes ago hides the list. The tile shows the result of that setup instead.

**Fix.** Work through four checks. Use the name of your disk instead of `/dev/sdc`.

1. The server sees the disk. `lsblk` shows it as a line of the type `disk`, with its size, without partitions below it and
   without a mount point:

   ```bash
   lsblk -o NAME,SIZE,TYPE,MODEL,MOUNTPOINT
   ```

   If the disk is not in the list, the cause is outside the server. The script asks the kernel to look for new disks on every
   call, so the server needs no restart.

2. The script accepts the disk. The next call has no `ja` at the end, so it formats nothing:

   ```bash
   bash /opt/pacs-admin/server/pacs-storage.sh add /dev/sdc
   ```

   Expected for an empty disk: the section `--- Plan` and the last line
   `Trockenlauf. Ausfuehren: /opt/pacs-admin/server/pacs-storage.sh add /dev/sdc ja` ("dry run, to run it: ..."). Do not add
   `ja` now. If the output is `HALT: /dev/sdc wird nicht formatiert: ...`, the table in [8.1](#disk-halt), group C, explains
   the reasons. A `HALT:` about docker or LDAP is in group B.

3. The list of the script contains the disk:

   ```bash
   bash /opt/pacs-admin/server/pacs-storage.sh kandidaten
   ```

   Expected: one line `kandidat <device> <bytes> <model>` for each empty disk, then the lines `naechste`, `vorlage`,
   `schreibliste` and `voll`. This is an example for one disk of 100 GiB. The values differ on your server, and the line `voll`
   is empty when no storage is marked as full:

   ```text
   kandidat /dev/sdc 107374182400 QEMU HARDDISK
   naechste PACS-Data02
   vorlage PACS-Data01 10GB
   schreibliste PACS-Data01
   voll
   ```

   If there is no `kandidat` line although `add` printed a plan, the page does not accept the device name. The list holds only
   whole disks with names like `/dev/sdc`, `/dev/vdb`, `/dev/xvdb` or `/dev/nvme0n1`. Another kind of disk, for example
   `/dev/mmcblk0`, goes only through `add` on the command line.

   If the line `schreibliste` is missing, the script cannot read the AE from the LDAP server. The tile `Speicher` then says
   `Schreibliste nicht lesbar (LDAP-Container und pacs-storage.sh kandidaten prüfen).` ("write list not readable ..."). The
   call `scan` shows the reason as a `HALT:` line (group B in [8.1](#disk-halt)).

4. The page shows current numbers. The line under the title of the tab `Übersicht` shows the time of the last status. Choose
   `Jetzt suchen`. If it reports an error, go to [7.2](#cron-not-running).

A setup that ended less than 30 minutes ago keeps the tile on its result. The title is then `Neue Festplatte PACS-Data02`. The
list of empty disks returns after 30 minutes. To set up another disk sooner, use the command line
([modules.md, section 3.1](modules.md#disk-what)). The helper service keeps the record of the setup only in memory, so a
restart of the service shows the list again. Restart it only when no setup runs (see the Warning in
[7.2](#cron-not-running)).

> **Check**
>
> ```bash
> bash /opt/pacs-admin/server/pacs-storage.sh kandidaten
> ```
>
> Expected: a line `kandidat /dev/sdc <bytes> <model>` for the new disk. After `Jetzt suchen`, or after at most 5 minutes, the
> tile has the title `Neue Festplatte erkannt` and the text `leer, bereit zum Einrichten`. It lists the device, the size, the
> model and the button `Als PACS-Data02 einrichten …`.

<a id="disk-half-done"></a>
### 8.3 A disk setup or change stopped half way

**What you see.** One of these:

- The tile `Neue Festplatte PACS-Data02` says `abgebrochen <time>` ("cancelled") and shows the red box `Abgebrochen`. The list
  of steps stops after `Formatieren und einhängen` ("format and mount") or later. The box shows the `HALT:` line. It says
  `siehe Ausgabe` ("see output") when the output has no such line.
- The tile says `eingerichtet <time>, Archiv nicht neu geladen` ("set up, archive not reloaded") and shows the yellow box
  `Archiv nicht neu geladen`. The box repeats the text after `ACHTUNG:` in the output. The tile keeps this view for 30
  minutes after the end of the setup, even after you reloaded the archive. It is the record of that run, not the live state.
- A button of the tile `Speicher` fails with a message that begins with `Archiv-Konfiguration nicht neu geladen` and ends with
  `(HTTP 500)`. The text in between is: `(Antwort 000). Die Aenderung steht im LDAP, das Archiv arbeitet bis zum Neuladen mit der
  alten Konfiguration. In der Oberflaeche des Archivs unter Konfiguration auf Neu laden klicken.` ("The change is in the LDAP.
  The archive works with the old configuration until it reloads. Click Reload under Configuration in the user interface of
  the archive.") The number behind `Antwort` is the answer of the archive and differs.
- The message `pacs-storage.sh antwortet nicht (nach 300 s abgebrochen), Zustand pruefen (HTTP 504)` ("does not answer,
  stopped after 300 s, check the state"). The name can also be `dashboard-status.py`. nginx can answer by itself after 300
  seconds. The page then shows `abgelehnt (HTTP 504)`.
- The tile said `läuft seit <time>` ("running since"), and then the server restarted, or somebody restarted the service
  `pacs-verwaltung`. The service keeps the record of a setup only in memory, so the page does not show the setup any more.

**Cause.** The setup has no automatic way back. The script stops at the first step that fails and leaves the earlier steps in
place. The log shows the last step that ran. Find the run in `/var/log/pacs-storage.log`. A line such as
`=== 2026-10-14 10:15:03 pacs-storage.sh add /dev/sdc ja` starts each run. The next table lists what the last lines before the
stop mean. The script prints the exit code 3 when only the reload of the archive failed
([reference.md](reference.md#storage-exit-codes)).

| Last line before the stop | What has changed |
|---|---|
| `--- Plan` | Nothing. The script only checked. |
| `--- Platte` | `mkfs.ext4` started. If it failed, a part of the disk can be written. |
| `ok    ext4 PACS-Data02 auf /dev/sdc` | The disk is formatted. Nothing else has changed. |
| `ok    gemountet /mnt/fs/PACS-Data02, fstab ergaenzt (vorher /etc/fstab.bak-20261014-101503), NO_MOUNT darunter` | The folder with the file `NO_MOUNT` exists. The line is in `/etc/fstab`, with a backup. The disk is mounted and the owner is set. The archive is unchanged. |
| `--- Sichtbar im Container arc?` or `ok    Container sieht die Platte und kann schreiben` | Only a test file was written and removed. The archive is unchanged. |
| `ok    Storage PACS-Data02 angelegt: ...` | The storage exists in the LDAP configuration. It is not yet in the write list. |
| `ok    Schreibliste DCM4CHEE: ...` | The storage is in the write list in the LDAP configuration. `arc` works with the old configuration until it reloads. |
| `ok    Archiv-Konfiguration neu geladen` | The setup is complete. Only the check `ok    Archiv kennt PACS-Data02` and the last line `fertig.` follow. |

A new disk holds no images yet. The archive writes to it only after the storages in front of it are full
([modules.md, section 3.1](modules.md#disk-what)).

**Fix.**

Step 1. Read the end of the log and the state of the disk. Replace `PACS-Data02` with the name of your disk:

```bash
tail -n 60 /var/log/pacs-storage.log
bash /opt/pacs-admin/server/pacs-storage.sh scan
findmnt /mnt/fs/PACS-Data02
grep PACS-Data02 /etc/fstab
```

`findmnt` prints nothing when the disk is not mounted. `grep` prints nothing when `/etc/fstab` has no line for the disk. Use the
table above to choose one of the cases A to D.

Step 2. Finish the setup.

**Case A. The disk is formatted, but not mounted.** The last line is `ok    ext4 ...`, or the log ends with
`HALT: mount fehlgeschlagen` or with `HALT: /mnt/fs/PACS-Data02 ist nicht /dev/sdc`. First read the message of `mount` in the
line above the `HALT:` line and remove its cause. Then check that the label exists:

```bash
blkid -L PACS-Data02
```

If it prints nothing, the formatting did not finish. Wipe the disk as described in [8.1](#disk-halt), group C, and start the
setup again from the page. If it prints the device, finish the work by hand. The next commands do what the script does. They
are derived from the script and were not run on real hardware. Use your own name, path and owner. The owner is the setting
`STORAGE_OWNER`, `1023:1023` by default:

```bash
mkdir -p /mnt/fs/PACS-Data02
touch /mnt/fs/PACS-Data02/NO_MOUNT
chmod 444 /mnt/fs/PACS-Data02/NO_MOUNT
cp -p /etc/fstab /etc/fstab.bak-$(date +%Y%m%d-%H%M%S)
grep -q '^LABEL=PACS-Data02 ' /etc/fstab || echo 'LABEL=PACS-Data02 /mnt/fs/PACS-Data02 ext4 nosuid,nodev,nofail 0 0' >> /etc/fstab
systemctl daemon-reload
mount /mnt/fs/PACS-Data02
```

If `mount` prints an error, stop and read it. If it prints nothing, set the owner and put the disk into the archive:

```bash
chown 1023:1023 /mnt/fs/PACS-Data02
chmod 755 /mnt/fs/PACS-Data02
bash /opt/pacs-admin/server/pacs-storage.sh activate PACS-Data02 ja
```

**Case B. The log stops with a `HALT:` line after `ok    gemountet`.** The line names the cause: `arc sieht ... nicht`,
`arc kann in ... nicht schreiben`, `kein Vorlage-Storage gefunden` or a failed LDAP change. Remove the cause as described in
[8.1](#disk-halt), group D. Then run `activate` for the disk. It skips the steps that are done and prints, for example,
`ok    Storage PACS-Data02 steht schon im LDAP`:

```bash
bash /opt/pacs-admin/server/pacs-storage.sh activate PACS-Data02 ja
```

Do not run `add` again for a disk that is formatted. It refuses, because the disk is not empty any more.

**Case C. The archive did not reload its configuration.** The change is in the LDAP configuration. `arc` works with the old
one. Ask `arc` to reload it. This is the call that the script makes. Use the `ARC_URL` of your install instead of
`http://127.0.0.1:8080`:

```bash
curl -s -m 30 -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8080/dcm4chee-arc/ctrl/reload
```

The script counts the answers `204` and `200` as success. The answer `000` means that the archive did not answer. `docker ps`
and `docker logs --tail 50 arc` show why. As an alternative, click `Neu laden` ("reload") under `Konfiguration` in the dcm4chee
user interface, as the text of the script says. Then check that the archive knows the storage. The script makes the same check:

```bash
curl -s http://127.0.0.1:8080/dcm4chee-arc/storage | grep -o '"PACS-Data02"'
```

Expected: `"PACS-Data02"`. For a failed button action (`In Schreibliste aufnehmen`, `Aus Schreibliste nehmen` or
`Markierung entfernen`), do the same reload and press F5.

**Case D. After the answer 504 or after a restart.** A script that runs longer than 300 seconds is stopped with all its child
processes, so it did not finish its later steps. After `Formatieren und einrichten` the answer 504 means that the check before
the start ran out of time, so no setup was started. A restart of `pacs-verwaltung` stops a running setup. Find the
last line of the run in the log. Use the table above, then continue with case A, B or C. For a button action, the state of
the LDAP configuration is unknown. Run the same action again. It skips the steps that are done.

Step 3. Undo the setup, only if you do not want the disk any more. Do this only when the log has no line
`ok    Storage PACS-Data02 angelegt`. After that line, finish the setup instead, because the assistant cannot delete a storage.
The next commands remove the line from `/etc/fstab`, unmount the disk and remove the folder. They are derived from the script
and were not run on real hardware:

```bash
cp -p /etc/fstab /etc/fstab.bak-$(date +%Y%m%d-%H%M%S)
sed -i '\|^LABEL=PACS-Data02 |d' /etc/fstab
umount /mnt/fs/PACS-Data02
systemctl daemon-reload
rm -f /mnt/fs/PACS-Data02/NO_MOUNT
rmdir /mnt/fs/PACS-Data02
```

If `umount` says that the disk is not mounted, go on with the next command. The disk keeps its file system and its label. The
script does not offer it again until you wipe it ([8.1](#disk-halt), group C).

> **Warning**
>
> Keep the option `nofail` in the line of `/etc/fstab`. Without it, a server with a missing disk does not start. Do not delete
> the files `/etc/fstab.bak-*`. They are the way back to the state before the setup. Check every manual command against your
> log before you run it.

> **Check**
>
> ```bash
> findmnt /mnt/fs/PACS-Data02
> bash /opt/pacs-admin/server/pacs-storage.sh scan
> ```
>
> Expected: `findmnt` prints one line with the target `/mnt/fs/PACS-Data02`, the device and the type `ext4`. `scan` lists the
> disk under `--- Storages` with the word `Schreibliste` at the end of its line, and `keine` under
> `--- NO_MOUNT fehlt unter dem Mountpunkt (nomount)`. After `Jetzt suchen`, or after at most 5 minutes, the tile `Speicher`
> shows the bar of the disk.

<a id="disk-not-mounted"></a>
### 8.4 The badge `nicht eingehängt, bitte prüfen`

**What you see.** One of these:

- A disk in the tile `Speicher` shows the red badge `nicht eingehängt, bitte prüfen` ("not mounted, please check") instead of
  the bar. The tile shows the name without the prefix, for example `01` for `PACS-Data01`. A disk with this badge has no
  button.
- A button or the script reports `HALT: /mnt/fs/PACS-Data01 ist nicht gemountet`.

**Cause.** The folder `/mnt/fs/PACS-Data01` exists, but nothing is mounted there. The status job tests whether the folder is a
mount point. The usual reasons:

- The disk is gone. Look at the hypervisor, the cable and the controller.
- The mount failed when the server started. The option `nofail` lets the server start without the disk.
- The line for the disk is gone from `/etc/fstab`.
- Somebody ran `umount`.

The archive cannot read the images on this disk. The viewer cannot show the studies that live on it. The folder under the mount
point belongs to root, has the mode 755 and holds the file `NO_MOUNT` (mode 444). The file shows that the disk is missing. What
dcm4chee does with new images while a storage of the write list is missing was not tested.

**Fix.** Find out what the server sees:

```bash
lsblk -f
blkid -L PACS-Data01
grep PACS-Data01 /etc/fstab
dmesg | tail -n 30
```

| What you see | Meaning and fix |
|---|---|
| `blkid -L` prints nothing | The server does not see a disk with this label. Attach the disk again in the hypervisor, or check the cable. `dmesg` can show errors of the disk (typical; not run). Then run `bash /opt/pacs-admin/server/pacs-storage.sh scan`, which makes the kernel look for disks again. |
| `blkid -L` prints a device, and `grep` prints no line | The line in `/etc/fstab` is gone. Copy `/etc/fstab`, then add the line `LABEL=PACS-Data01 /mnt/fs/PACS-Data01 ext4 nosuid,nodev,nofail 0 0`. `ls -l /etc/fstab.bak-*` lists the backups that the assistant made. Then run `systemctl daemon-reload` and mount the disk (next row). |
| Both print something | Mount the disk with `mount /mnt/fs/PACS-Data01`. Read the message. |

If `mount` reports a damaged file system, do not format the disk. Check it read-only first with `fsck.ext4 -n /dev/sdc` (typical;
not run). Decide with the owner of the data what to do next.

After the disk is mounted, check three things:

```bash
findmnt /mnt/fs/PACS-Data01
bash /opt/pacs-admin/server/pacs-storage.sh scan
docker exec arc ls /mnt/fs/PACS-Data01 | head
```

`scan` must list the disk under `--- Storages`. If it lists the disk under `--- NO_MOUNT fehlt unter dem Mountpunkt (nomount)`,
run `bash /opt/pacs-admin/server/pacs-storage.sh nomount ja`. The call `docker exec` must show the folders of the archive, not
only `NO_MOUNT`. A mount that appears on the host after `arc` started is passed on to `arc` by the option `rslave`. If `arc`
shows only `NO_MOUNT`, check edit A in [modules.md](modules.md#edits-overview).

**If the disk cannot return soon,** take it out of the write list, so that new images go to another disk. The page has no
button for a missing disk, so use the command line. The first call prints the plan. The second call makes the change and asks
`arc` to reload its configuration:

```bash
bash /opt/pacs-admin/server/pacs-storage.sh abhaengen PACS-Data01
bash /opt/pacs-admin/server/pacs-storage.sh abhaengen PACS-Data01 ja
```

The script refuses when no other disk with room stays in the list. The message is
`HALT: PACS-Data01 ist in dcmObjectStorageID die letzte Platte, die nicht voll ist. Erst eine andere aufnehmen.` (group E in
[8.1](#disk-halt)). When the disk is back and mounted, the button `In Schreibliste aufnehmen` puts it into the list again.

> **Warning**
>
> Create no files in the folder `/mnt/fs/PACS-Data01` while no disk is mounted there. A file in that folder hides under the
> mount as soon as the disk returns, and it uses space of the system disk.

> **Check**
>
> ```bash
> findmnt /mnt/fs/PACS-Data01
> ```
>
> Expected: one line with the target `/mnt/fs/PACS-Data01`, the device and the type `ext4`. After `Jetzt suchen`, or after at most
> 5 minutes, the tile `Speicher` shows the bar and the size of the disk instead of the badge.

<a id="trouble-firewall"></a>
## 9. Firewall

This chapter covers the firewall: the tab `Firewall` of the admin page ([screen labels](glossary.md#screen-firewall)), the unit
`pacs-firewall` and the program `firewall.py` ([modules.md, section 4](modules.md#firewall)). Three places show its state:

- The badge at the top of the tab `Firewall`: `wirksam` (in effect), `nicht wirksam` (not in effect) or `ausgeschaltet`
  (switched off).
- The tile `Firewall` of the tab `Übersicht`.
- The command `firewall.py status`. It reads the `FW_` settings from `/etc/default/pacs-admin`, so the commands of this chapter
  load that file first.

The firewall never touches SSH (port 22). Keep an SSH session open while you work on it.

<a id="firewall-lockout-brake"></a>
### 9.1 No access after you saved firewall rules

**What you see.** After you saved rules in the tab `Firewall`, or after the first start of the firewall, one of these:

- A modality or an HL7 sender reports a failed send.
- A colleague cannot open the viewer or the admin page. The browser reports a refused connection (typical).
- A program that calls the REST interface of dcm4chee gets "connection refused".

SSH still works. If SSH does not work either, the cause is not this firewall. Use the console of the virtual machine.

**Cause.** A port in the mode `gesperrt` (blocked) rejects every new connection from a source that is not on the list of the
port. The client gets "connection refused". Before it saves, the page checks one thing only: your own computer must still reach
the first web port (443 in a default install). The check does not protect other users, other ports, users on IPv6 or users
behind a reverse proxy ([modules.md, 4.11](modules.md#firewall-lockout)). The built-in rule set applies while no `firewall.json`
exists and `FW_DEFAULT_RULES` is empty. It blocks seven ports at once ([modules.md, 4.2](modules.md#firewall-inventory)).

**Fix.** Work in this order.

Step 1. Pull the emergency brake. The command prints nothing. It removes the jump to the rule chain `PACS-SPERRE`, so all Docker
ports are open again at once. It deletes no rule and no file.

```bash
systemctl stop pacs-firewall
iptables -S DOCKER-USER
```

The second command must print no line that contains `PACS-SPERRE`. If `systemctl stop` reports an error, read it with
`journalctl -u pacs-firewall -n 20 --no-pager`. One cause is a unit that points to a wrong path of the repository
([modules.md, 4.4](modules.md#firewall-start), step 3). Remove the jump by hand then. The first command below lists it, for
example as `-A DOCKER-USER -i eth0 -j PACS-SPERRE`. Write that line into the second command and put `-D` in place of `-A`:

```bash
iptables -S DOCKER-USER
iptables -D DOCKER-USER -i eth0 -j PACS-SPERRE
```

Step 2. Find the rule that cut off the connection. The kernel logs rejected connections, at most 10 lines per minute for each
rule. The word after `pacs-` is the kind, the number is the port, and `SRC=` names the sender:

```bash
journalctl -k --since "1 hour ago" --no-pager | grep -E 'pacs-(sperre|standard) '
```

A line with `pacs-sperre 9990:` comes from the rule of port 9990. A line with `pacs-standard` comes from the setting
`Ports ohne eigene Regel` (ports without a rule of their own) when it is `gesperrt`. The command reads the current boot only.
The tile `Verbindungen an Regeln` (connections at rules) of the tab `Firewall` lists the sources of the last 7 days with the
kinds `abgewiesen` (rejected) and `Standard: abgewiesen`.

Step 3. Correct the rule. Open the tab `Firewall`. It opens again, because the brake opened all ports. The badge says
`nicht wirksam`. That is right: the rules are not applied now. Do one of these, then choose `Speichern`:

- Enter the source in the list of the port. Use the button `Erlauben` (allow) in the tile `Neu erkannt` (newly detected) or in
  the tile `Verbindungen an Regeln`, or type the address or the network into the list of the port
  ([modules.md, 4.6](modules.md#firewall-allow)).
- Set the port to `offen`, or to `Probelauf` (trial run: everybody passes, and the kernel logs the sources that are not listed).

A save that changes rules loads them into the kernel again. To get the old rules back without a change, run
`systemctl start pacs-firewall`.

> **Warning**
>
> The brake does not hold for good. The rules come back at the next start of the server, at the next save that changes rules,
> and within 5 minutes after the list of published Docker ports changes while `Ports ohne eigene Regel` is not `offen`. Correct
> the rule before one of these happens, or the lock-out returns. To keep the firewall off until you have time, see the
> [emergency brake](modules.md#firewall-brake). While the brake holds, nothing is filtered.

> **Check**
>
> ```bash
> iptables -S DOCKER-USER
> ```
>
> Expected right after the brake: no line with `PACS-SPERRE`. The device can connect again. The tab `Firewall` shows the badge
> `nicht wirksam` with the reason `kein Sprung von DOCKER-USER nach PACS-SPERRE, die Regeln sind nicht angewendet (systemctl
> status pacs-firewall)`.
>
> Expected after you corrected the rule and saved: the badge says `wirksam`, the line `-A DOCKER-USER -i eth0 -j PACS-SPERRE`
> is back (your interface), and the device connects. Test a blocked port from a second computer as in
> [modules.md, 4.7](modules.md#firewall-block), step 2.

<a id="firewall-not-effective"></a>
### 9.2 The badge `nicht wirksam`, or the rules do not block

**What you see.** One of these:

- The red badge `nicht wirksam` ("not in effect") at the top of the tab `Firewall`. The info line next to it starts with
  `Nicht wirksam:` and names the reason. The reason also shows when the pointer rests on the badge.
- The red badge `ausgeschaltet` ("switched off"). The box `eingeschaltet` (switched on) is not ticked.
- The tile `Firewall` of the tab `Übersicht` says `Ausgeschaltet` in red in place of `Wirksam`. The tile uses this word for every
  reason in the table below, also when the rules are only not applied.
- `firewall.py status` ends with `wirksam: False` and a line `Nicht wirksam, weil: ...`.
- A port in the mode `gesperrt` lets a computer through that is not on its list. The test of
  [modules.md, 4.7](modules.md#firewall-block), step 2, fails.

**Cause.** The rules live in the kernel. They work only while the chain `DOCKER-USER` has a jump to the rule chain `PACS-SPERRE`
for the network interface of the rules. The page asks the kernel for this jump every time it loads. The reason in the badge
tells which part is missing:

| Reason as shown | Meaning | Fix |
|---|---|---|
| `in /admin/ (Reiter Firewall) ausgeschaltet` ("switched off in /admin/, tab Firewall") | The saved rules have the box `eingeschaltet` off. | Tick `eingeschaltet` and choose `Speichern`. If you removed the unit as in [modules.md, 4.12](modules.md#firewall-uninstall), install it again first ([4.4](modules.md#firewall-start), step 3). |
| `kein Sprung von DOCKER-USER nach PACS-SPERRE, die Regeln sind nicht angewendet (systemctl status pacs-firewall)` ("no jump from DOCKER-USER to PACS-SPERRE, the rules are not applied") | The kernel has no jump. The unit is not running or failed, or somebody pulled the [brake](modules.md#firewall-brake). | Read the unit as shown below, then load the rules. |
| `der Sprung nach PACS-SPERRE gilt fuer eine andere Schnittstelle als eth0 (firewall.py start)` ("the jump applies to another interface than eth0") | The jump was set for another network interface than the one the rules name now. The default route moved, or `FW_INTERFACE` changed. | Load the rules again with `firewall.py start`, as shown below. |
| `iptables: No chain/target/match by that name. (die Kette DOCKER-USER legt Docker beim Start an: laeuft Docker?)` ("Docker creates the chain DOCKER-USER when it starts: does Docker run?") | The chain `DOCKER-USER` does not exist, so Docker does not run. The text before the bracket is the last line of the `iptables` error and differs by version (typical). | Start Docker: `systemctl start docker`. The unit starts with it. |
| `iptables nicht gefunden: apt install iptables (docs/modules.de.md#firewall)` | The program `iptables` is missing. | See [9.4](#firewall-tools-missing). |

**Fix.** Look at the unit, its messages and the kernel:

```bash
systemctl status pacs-firewall --no-pager
journalctl -u pacs-firewall -b --no-pager | tail -n 20
iptables -S DOCKER-USER
```

Expected when all is well: `Active: active (exited)` in the first output (typical for this kind of unit), and a jump line such as
`-A DOCKER-USER -i eth0 -j PACS-SPERRE` in the third. A start error shows in the journal as one line that begins with
`firewall.py start:`. Typical lines:

| Line in the journal | Meaning |
|---|---|
| `firewall.py start: Schnittstelle unbekannt: FW_INTERFACE in /etc/default/pacs-admin setzen` | The program found no default route within 60 seconds. Name the interface with `FW_INTERFACE` ([modules.md, 4.4](modules.md#firewall-start), step 1). |
| `firewall.py start: iptables-restore nicht gefunden: apt install iptables (docs/modules.de.md#firewall)` | A program is missing: [9.4](#firewall-tools-missing). |
| `firewall.py start: FW_DEFAULT_RULES: ...` | The file of the first-start rules is wrong: [9.5](#firewall-save-failed). |

Then load the rules. If the unit is not `active`, start it:

```bash
systemctl start pacs-firewall
```

If the unit is `active` but the jump is missing or belongs to another interface, load the rules again without a gap. The first
line loads your settings:

```bash
set -a; . /etc/default/pacs-admin; set +a
python3 /opt/pacs-admin/server/firewall.py start
```

The program prints `Firewall wirksam, 8 Regeln` (the number of your rules). If the unit does not exist (`Unit pacs-firewall.service
could not be found`), install it ([modules.md, 4.4](modules.md#firewall-start), step 3).

> **Warning**
>
> Do not use `systemctl restart pacs-firewall` to load the rules again. The restart removes the jump first, and all Docker ports
> are open until the rules are back ([modules.md, 4.10](modules.md#firewall-settings)). The program `firewall.py status` shows
> its defaults when you forget the first line: it then looks for the interface of the default route and can report a mismatch
> that does not exist on the page.

> **Check**
>
> ```bash
> systemctl is-active pacs-firewall
> iptables -S DOCKER-USER
> set -a; . /etc/default/pacs-admin; set +a
> python3 /opt/pacs-admin/server/firewall.py status | tail -n 1
> ```
>
> Expected: `active`, a line `-A DOCKER-USER -i eth0 -j PACS-SPERRE` (your interface), and a last line that contains
> `wirksam: True`. In the tab `Firewall`, choose `Neu laden` (reload): the badge says `wirksam`.

<a id="ipv6-not-filtered"></a>
### 9.3 The badge `IPv6 nicht gefiltert`

**What you see.** One of these:

- The red badge `IPv6 nicht gefiltert` ("IPv6 not filtered") behind the mode of a port in the tile `Ports` of the tab `Firewall`.
  When the pointer rests on it, the text says that Docker publishes the port on IPv6 too and that these connections run past
  the firewall.
- The tile `Firewall` of the tab `Übersicht` says `N Port über IPv6 nicht gefiltert` or `N Ports über IPv6 nicht gefiltert` in red.
  The tile counts only while the rules are in effect, and only ports that are not `offen`.
- `docker ps` shows an entry that starts with `[::]:` for the port.

**Cause.** The firewall filters IPv4 only. When Docker publishes a port on an IPv6 address too, it accepts those connections in
`docker-proxy` ([glossary](glossary.md#docker-proxy)). They do not pass the chain `DOCKER-USER`. A source that the list of the
port rejects on IPv4 can still connect over IPv6. A port in the mode `offen` shows no badge, because nothing needs filtering.

**Fix.** Publish the port on IPv4 only. Find the container that publishes it. The tile `Ports` names it below the port name. Or
list all ports:

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

Open the compose file of that container ([modules.md, 2.2](modules.md#edits-steps), step 1, shows how to find it). Write `0.0.0.0:`
in front of the host port of the entry, for example `"0.0.0.0:11112:11112"`. Write `127.0.0.1:` instead when nobody needs the
port from another computer. Edit B of [modules.md, section 2](modules.md#edits-overview) does this for the ports of `arc`. Then
recreate the container in the folder of the compose file:

```bash
cd /opt/dcm4chee-arc
docker compose up -d
```

> **Warning**
>
> Docker stops and removes a container whose compose entry changed, then starts a new one. For `arc` the archive is down until
> dcm4chee has started again, usually for a minute or more. Do this in a maintenance window. The other way, to switch IPv6 off on
> the whole server, can cut off your own SSH session: read [modules.md, 4.3](modules.md#firewall-ipv6) first.

> **Check**
>
> ```bash
> docker ps --format 'table {{.Names}}\t{{.Ports}}'
> ```
>
> Expected: the port appears as `0.0.0.0:11112->11112/tcp` (example) and no entry `[::]:11112->11112/tcp` stays. In the tab
> `Firewall`, choose `Neu laden`: the badge is gone.

<a id="firewall-tools-missing"></a>
### 9.4 A message like `iptables nicht gefunden: ...`

**What you see.** One of these:

- A red message at the top of the admin page. Example: `Firewall laden: Firewall: docker nicht gefunden: Docker installieren,
  z. B. apt install docker.io (docs/modules.de.md#firewall) (HTTP 500)`. A failed save shows `Firewall speichern: Firewall:
  ... (HTTP 500)` in the same way.
- The tile `Firewall` of the tab `Übersicht` shows the same text in red, without the words `Firewall laden:`.
- The badge `nicht wirksam` with a reason that starts with `iptables nicht gefunden:`.
- `firewall.py` and the unit print one line `firewall.py COMMAND: ... nicht gefunden: ...`.

**Cause.** The helper service and the unit run the programs `iptables`, `iptables-restore`, `ip`, `docker` and `journalctl`. When
one of them is not found, the program stops with a line that names the missing program and the package. The page shows the
status error as HTTP 500 with the prefix `Firewall:`. Only a missing `iptables` leaves the page usable: the badge then shows the
reason. The messages and the packages:

| Message | Meaning | Fix |
|---|---|---|
| `iptables nicht gefunden: apt install iptables (docs/modules.de.md#firewall)` | `iptables` is not installed. | `apt-get install -y iptables` |
| `iptables-restore nicht gefunden: apt install iptables (docs/modules.de.md#firewall)` | The loader of the rules is missing. It comes with the same package. | `apt-get install -y iptables` |
| `ip nicht gefunden: apt install iproute2 (docs/modules.de.md#firewall). Oder FW_INTERFACE in /etc/default/pacs-admin setzen` | `ip` is missing. The program needs it to find the default route. | `apt-get install -y iproute2`, or set `FW_INTERFACE` ([modules.md, 4.4](modules.md#firewall-start), step 1). |
| `docker nicht gefunden: Docker installieren, z. B. apt install docker.io (docs/modules.de.md#firewall)` | `docker` is not found. The status needs it to list the published ports and the Docker networks. | Install Docker, or see the note below the table. |
| `journalctl nicht gefunden: apt install systemd (docs/modules.de.md#firewall)` | `journalctl` is missing, so the program cannot read the kernel log. | `apt-get install -y systemd` |
| `hostname nicht gefunden: installieren (docs/modules.de.md#firewall)` | A program without a package hint is missing. | Install the program that the message names. |
| `docker antwortet nicht (nach 120 s abgebrochen)` ("docker does not answer, stopped after 120 s") | The program exists, but it ran longer than 120 seconds. The text starts with the name of the program. | Docker hangs. Look at `systemctl status docker` and run `docker ps` by hand. |
| `iptables nicht ausfuehrbar: ...` ("not executable") | The file exists, but the system cannot run it. The text ends with the reason of the system. | Look at the file: `ls -l "$(command -v iptables)"`. |

If `command -v docker` prints a path in your shell, but the message says `docker nicht gefunden`, the program is in a folder that
systemd does not search for the helper service and the unit. Docker from a snap package is a typical case (`/snap/bin/docker`).
Use the Docker packages of your distribution or Docker's own repository instead.

**Fix.** Install the package from the table. Do not restart anything: the next call of the page runs the program again.

```bash
apt-get install -y iptables iproute2
command -v iptables iptables-restore ip docker journalctl
```

If the unit failed at boot because of the missing program, start it once more:

```bash
systemctl start pacs-firewall
```

> **Check**
>
> Expected from `command -v`: one path for each program. Then choose `Neu laden` in the tab `Firewall`. The red message is gone,
> and the badge says `wirksam`. If the badge says `nicht wirksam`, go on with [9.2](#firewall-not-effective).

<a id="firewall-save-failed"></a>
### 9.5 `Firewall speichern: ...` or `Firewall laden: ...` shows an error

**What you see.** A red message at the top of the admin page. The part after the colon is the reason. The number at the end is the
HTTP status:

- `Firewall speichern: <reason> (HTTP 400)`: the helper service did not accept the rules, or the kernel refused them. Nothing
  changed, or the earlier rules came back.
- `Firewall speichern: Firewall: <reason> (HTTP 500)` or `Firewall laden: Firewall: <reason> (HTTP 500)`: the helper service
  could not do the work. The tab stays empty or the save does not happen.

Several reasons in one message are joined by ` · `.

**Cause.** The helper service checks the rules before it saves them, writes the file `firewall.json`, keeps a copy of the
earlier version and loads the rules into the kernel. Each of these steps has its own message. The page sends all rules of the
file back at every save. A wrong entry in a file that somebody edited by hand therefore stops every save.

**A. The helper service refused the rules.** The name or the number in your message differs from the example:

| Message | Meaning | Fix |
|---|---|---|
| `Port 443: dein PC (192.0.2.50) wäre danach selbst ausgesperrt. Erst ihn oder sein Netz eintragen.` | The lock-out check ([modules.md, 4.11](modules.md#firewall-lockout)): after the save, your computer could not reach the first web port. | Enter your computer or its network in the list of the port, then save again. If the address in the message is not the address of your computer, the front door sees a proxy: see [4.5](#proxy-wrong-address). |
| `Schnittstelle „Ethernet“ ungültig (FW_INTERFACE setzen)` | The interface name is not valid. A valid name has 2 to 15 characters, starts with a lowercase letter and holds only lowercase letters, digits, `_`, `.` and `-`. An empty name (`„“`) means that the default route gave no interface. | Find the name with `ip route show default` (the word after `dev`). Set `FW_INTERFACE` in `/etc/default/pacs-admin` and restart `pacs-verwaltung` ([modules.md, 4.10](modules.md#firewall-settings)). |
| `Port 70000 ungültig oder doppelt` | The port number is outside 1 to 65535, or the port stands twice in the file. | Correct the file (see below). |
| `Port fehlt oder ist keine Zahl` | A rule has no port number. | Correct the file. |
| `Port 22 (SSH) ist kein Docker-Port und hier nicht einstellbar` | The file holds a rule for port 22. The firewall never filters SSH. | Delete that rule from the file. |
| `Port 8080: Modus „zu“ unbekannt` | The modes are `offen`, `probelauf` and `gesperrt`. | Correct the file. |
| `Standard „zu“ unbekannt` | The same for the setting `standard`. | Correct the file. |
| `Port 8080: „192.0.2.300“ ist keine IPv4-Adresse und kein Netz` | A list holds a wrong entry. The page checks the entries that you type, so this points to a file that was edited by hand. | Correct the file. |
| `Regeln fehlen` | The request holds no list of rules. The page never sends such a request. | Reload the page with F5 and try again. |

**B. The kernel refused the rules.** The page shows `Nicht übernommen, die vorigen Regeln gelten weiter: <reason>`
("not applied, the earlier rules stay in effect"). The helper service loaded the earlier rules again. If it could not read
earlier rules, the message is `Nicht übernommen: <reason>`, and only the file was put back. In both cases `<reason>` is the last
line of the error of `iptables` (typical: `iptables: No chain/target/match by that name.`, or `iptables-restore: line 7 failed`).
Check the usual causes:

```bash
systemctl is-active docker
iptables -S DOCKER-USER
```

If Docker is not `active`, or the second command prints `No chain/target/match by that name`, start Docker first. If both
work, the kernel lacks a part of the rule set. The rules use the matches `conntrack`, `comment` and `limit`, the log target
and the target `REJECT`. A kernel without one of them cannot run this firewall (typical for a stripped kernel; not
reproduced). Ask whoever runs the machine.

**C. The tab does not load, or a save ends in HTTP 500.** The message starts with `Firewall:`. A missing program is
[9.4](#firewall-tools-missing). The file messages:

| Message | Meaning |
|---|---|
| `Firewall: /opt/dcm4chee-arc/firewall.json: Expecting ',' delimiter: line 7 column 3 (char 112)` | `firewall.json` is not valid JSON. The end of the line is the error of the JSON reader and differs by case. |
| `Firewall: /opt/dcm4chee-arc/firewall.json: kein JSON-Objekt mit einer Liste regeln` ("no JSON object with a list regeln") | The file is JSON, but not in the format that the program expects ([reference.md](reference.md#firewall-json)). |
| `Firewall: FW_DEFAULT_RULES: [Errno 2] No such file or directory: '/etc/pacs-admin-firewall-start.json'` | The setting `FW_DEFAULT_RULES` names a file that does not exist. The setting counts only while no `firewall.json` exists. |
| `Firewall: FW_DEFAULT_RULES /etc/pacs-admin-firewall-start.json: Port 443: Modus „zu“ unbekannt` | The file named by `FW_DEFAULT_RULES` holds an entry that group A refuses. |

For a damaged `firewall.json`, restore the last copy. The helper service keeps one copy for every save in the folder
`firewall/` under `PACS_DIR` (default `/opt/dcm4chee-arc`). The newest copy is the version before the last save. Copy it back,
and test that the file is valid JSON. The test prints nothing when the file is valid:

```bash
ls -t /opt/dcm4chee-arc/firewall/firewall-*.json | head -n 5
cp -p /opt/dcm4chee-arc/firewall/firewall-20261014-103012.json /opt/dcm4chee-arc/firewall.json
python3 -m json.tool /opt/dcm4chee-arc/firewall.json > /dev/null
```

Use a file name from the first command in place of the example. For a wrong `FW_DEFAULT_RULES` file, test it with the same
`json.tool` command, correct it, or delete the line `FW_DEFAULT_RULES=...` from `/etc/default/pacs-admin`. Restart
`pacs-verwaltung` after you change that line ([modules.md, 4.10](modules.md#firewall-settings)). The helper service reads
`firewall.json` at every call, so a restored `firewall.json` needs no restart.

> **Warning**
>
> A restored or corrected file changes what the page shows. It changes the kernel only when you save or run `firewall.py start`.
> Read the rules in the tab first. Rules that you load can block ports at once, so keep the [emergency brake](modules.md#firewall-brake)
> in reach. Do not restart `pacs-verwaltung` while a disk setup runs ([modules.md, 3.5](modules.md#disk-operate)).

> **Check**
>
> ```bash
> python3 -m json.tool /opt/dcm4chee-arc/firewall.json > /dev/null; echo "exit code $?"
> ```
>
> Expected: `exit code 0`. In the tab `Firewall`, choose `Neu laden`: no red message appears. Save a change: the message
> `Firewall speichern: erledigt` appears and the badge says `wirksam`.
