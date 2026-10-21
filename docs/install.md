# Install the admin panel

English | [Deutsch](install.de.md)

This guide installs the admin panel next to a running dcm4chee archive, step by step. It is written for a system administrator
who knows Windows and the basics of Linux and has used Docker Compose. It explains new words where they first appear. The
[glossary](glossary.md) lists them all.

- [1. Start here](#start-here)
- [2. Path A: try the demo](#demo)
- [3. Before you begin](#prerequisites)
- [4. The real install](#real-install): [4.1 files](#get-files), [4.2 preflight](#preflight), [4.3 packages](#packages),
  [4.4 settings](#settings-file), [4.5 audit key](#audit-key), [4.6 helper service](#helper-service),
  [4.7 overview job](#overview-cron), [4.8 certificate](#tls-certificate), [4.9 nginx files](#nginx-files),
  [4.10 compose file](#compose-file), [4.11 viewer and page settings](#viewer-config), [4.12 login](#login-setup),
  [4.13 start](#start-and-check), [4.14 first test](#first-test), [4.15 optional modules](#optional-modules)
- [5. Variants in detail](#variants-detail)
- [6. Daily operation](#operate)

<a id="start-here"></a>
## 1. Start here

<a id="what-changes"></a>
### 1.1 What the install changes

The admin panel is a web page at `/admin/`. It shows services and disks, searches studies and patients, controls a firewall
and shows an audit log. It has three parts:

- The **front door** is nginx in the container `ohif`. It checks the login, applies locks and writes the audit log. With
  single sign-on a second container, `ohif-auth`, helps it ([glossary](glossary.md#front-door)).
- The **helper service** `pacs-verwaltung` runs on the host under systemd. It does the work that a container must not do,
  for example it writes the encrypted audit database ([glossary](glossary.md#helper-service)).
- A **cron job** writes the file `status.json` every 5 minutes. The tab `Übersicht` (overview) shows it.

The base install adds the items below. It changes nothing in your dcm4chee project and does not restart `arc`, `ldap` or `db`.

| What | Where |
|---|---|
| Program files | `/opt/pacs-admin` |
| Compose file, nginx files, certificate, accounts | `/opt/ohif` |
| Settings and audit key | `/etc/default/pacs-admin`, `/etc/pacs-protokoll.key` |
| Service and cron job | `/etc/systemd/system/pacs-verwaltung.service`, `/etc/cron.d/pacs-dashboard` |
| Data and sockets | `/var/lib/pacs-protokoll`, `/var/lib/pacs-admin`, `/run/pacs-admin` |
| Containers and ports | `ohif` (and `ohif-auth`), host ports 80 and 443 |

Of the optional modules only the disk assistant and the firewall restart `arc` ([4.15](#optional-modules)).

<a id="pick-path"></a>
### 1.2 Pick your path

| Path | Use it for | You need | Result |
|---|---|---|---|
| **A. Demo** | A first look | Python 3 on any PC | The screens with made-up data. No dcm4chee, no login |
| **B. Real install with single sign-on** | Daily use with Microsoft Entra ID or another OpenID Connect provider | Server, DNS name, TLS certificate, the right to register an app at the provider | Viewer and admin panel on https. Users sign in at the provider |
| **C. Real install without OAuth proxy** | Daily use with accounts kept by nginx, a closed network, or a first test | Server, DNS name, TLS certificate (not for `tryit`) | Viewer and admin panel with a user name and password, or with network lists |

A **recipe** is a compose file plus a set of nginx files. The nginx files have three parts that you exchange: the
[login method](glossary.md#login-method), the viewer and the [listener](glossary.md#listener). Each path uses these recipes:

| Recipe | Path | Compose file in `deploy/compose/` | Login | Viewer | Listener |
|---|---|---|---|---|---|
| `oauth2` | B | `docker-compose.oauth2.example.yml` | oauth2-proxy | OHIF | tls |
| `basic` | C | `docker-compose.basic.example.yml` | basic | OHIF | tls |
| `adminonly` | C | `docker-compose.adminonly.example.yml` | basic | none | tls |
| `proxied` | C | `docker-compose.proxied.example.yml` | basic | OHIF | behind-proxy |
| `tryit` | C | `docker-compose.tryit.example.yml` | basic | none | plain |

Unsure which login to take? Read [login.md](login.md#login-choose). A third login, `none` (network lists instead of accounts),
uses the compose file of `basic` ([login.md](login.md#login-none)). You can change the login later.

<a id="variants"></a>
### 1.3 Variants and what is not supported

- Admin panel only, without the OHIF viewer: recipe `adminonly` ([5.1](#variant-adminonly)).
- Behind your own TLS proxy such as Traefik, Caddy, Apache or Cloudflare Tunnel: recipe `proxied` ([5.2](#variant-proxied)).
  The proxy ends TLS. nginx keeps the login and the locks.
- nginx on the host instead of in a container: [5.3](#nginx-on-host).
- A first look on the server itself through an SSH tunnel, without TLS: recipe `tryit` ([5.4](#variant-tryit)).

Not supported:

- dcm4chee with its own Keycloak login (the `-secure` images). The front door calls the dcm4chee REST interface without a
  token. The archive must run without Keycloak.
- Traefik, Caddy or Cloudflare **instead of** nginx. They can stand in front of nginx (recipe `proxied`). The locks, the
  audit log and the link to the helper service are nginx features.

<a id="how-to-read"></a>
### 1.4 How to read the steps

- Run every command as root. Open a root shell once with `sudo -i` and stay in it.
- Paste each code block as a whole. Blocks that ask a question say so.
- A value to change is marked `CHANGE-ME` or is an example: `pacs.example.org` (host name), `192.0.2.10` (address), `anna`
  (account). Replace every example with your own value.
- The admin panel speaks German. Screen labels stay German in `code` format. The first use adds an English gloss, for
  example `Protokoll` (audit log).
- A **Check** box shows the command, the output to expect, and where to look when the output differs. Compare before you go on.
- A **Warning** box comes before a risky step. It names what can break, how long it lasts and how to go back.

<a id="demo"></a>
## 2. Path A: try the demo

The demo runs the real admin page with made-up data on your own PC. It needs Python 3.7 or newer. It needs no dcm4chee, no
login and no root rights, and nothing leaves your browser. Skip this section if you want the real install.

Get the files with git, or download the ZIP file from the project page (button `Code`, then `Download ZIP`) and unpack it.

```bash
git clone https://github.com/pbaetz99/dcm4chee-admin-panel.git
cd dcm4chee-admin-panel
python3 demo/serve.py
```

On Windows start the last command as `python demo\serve.py`. Add a port number for another port than 8000, for example
`python3 demo/serve.py 8081`. Press Ctrl+C to end the demo.

> **Check**
>
> The terminal prints one line:
>
> ```text
> Demo: http://127.0.0.1:8000/admin/   (Strg+C beendet)
> ```
>
> Open that address in a browser. The admin panel opens with the tabs `Übersicht`, `Studien` (studies), `Patienten`
> (patients), `Firewall` and `Protokoll`. If the terminal prints an error about the port, start the demo with another
> port number.

Four options change the demo page. Add them to the address:

- `?demo=platte` shows a new, empty disk.
- `?demo=ohne` shows a status without disks.
- `?demo=offen` opens all cards in the tab `Firewall`.
- `?demo=abgelaufen` makes every call answer like an expired session. The page shows `Sitzung abgelaufen` (session expired).

<a id="prerequisites"></a>
## 3. Before you begin

Collect these items first. Each one stops the install if it is missing.

- [ ] **A server** with Debian 13 or Debian 12 (Ubuntu was not tested), root access, and your dcm4chee archive running in
  Docker Compose.
- [ ] **A maintenance window.** The base install does not restart dcm4chee. It does take over ports 80 and 443, and the
  optional modules restart `arc`.
- [ ] **A DNS name** for the PACS, for example `pacs.example.org`, that points to this server. Ask your network team.
- [ ] **A TLS certificate** for that name, or time to get one ([4.8](#tls-certificate)). Only the recipe `tryit` works without it.
- [ ] **Free ports 80 and 443** on the server ([4.2](#preflight) checks them).
- [ ] **Internet access** to GitHub (the files), Docker Hub (the images) and, for path B, `quay.io` (oauth2-proxy).
- [ ] **Path B only:** a person who may register an app and create groups in Microsoft Entra ID, or the same right at
  your provider. Ask early. This can take days.

Make copies of the compose files before you change anything. First find the folder of your dcm4chee project:

```bash
docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' arc
```

Copy the compose file from that folder. If an OHIF compose file exists already, copy it too:

```bash
cp -a /opt/dcm4chee-arc/docker-compose.yml /root/dcm4chee-compose.$(date +%F).yml
[ -f /opt/ohif/docker-compose.yml ] && cp -a /opt/ohif/docker-compose.yml /root/ohif-compose.$(date +%F).yml
```

> **Warning**
>
> A web server or container that uses port 80 or 443 blocks the new front door. Replace it in one planned step: stop the old
> one, start the new one ([4.13](#start-and-check)). Users have no access in between, usually for a few minutes. To go
> back, stop `ohif` (`cd /opt/ohif && docker compose down`) and start the old one from your copy of its compose file.

> **Check**
>
> ```bash
> for h in github.com registry-1.docker.io quay.io; do printf '%s ' "$h"; curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 "https://$h/"; done
> ```
>
> Expected: one line per host with a number. Any number except `000` proves that the server reaches the host. `000` means
> no connection. Ask for a proxy or a firewall rule, and set the proxy for Docker as well (see the Docker documentation).

<a id="real-install"></a>
## 4. The real install

Work through the steps in order. Paths B and C share the steps. Where they differ, the step says so.

<a id="get-files"></a>
### 4.1 Get the files

The program files go to `/opt/pacs-admin`. The systemd unit and the cron file expect exactly this folder.

```bash
apt-get install -y git
git clone https://github.com/pbaetz99/dcm4chee-admin-panel.git /opt/pacs-admin
```

Without git, download the ZIP file from the project page, unpack it and rename the folder to `/opt/pacs-admin`. The scripts
run with `bash script` and `python3 script`, so missing execute rights do not matter.

> **Check**
>
> ```bash
> ls -1 /opt/pacs-admin/deploy/tools
> ```
>
> Expected:
>
> ```text
> pacs-adduser.sh
> preflight.sh
> set-aet.sh
> ```
>
> If the folder is missing, the clone failed. Read the error message. It names a network or a permission problem.

<a id="preflight"></a>
### 4.2 Run the preflight check

`preflight.sh` is a read-only script. It changes nothing. It checks packages, Docker, dcm4chee, ports and DNS. At the end it
prints **My values**: names and paths of your system that later steps need. Run it now and after every fix.

```bash
bash /opt/pacs-admin/deploy/tools/preflight.sh --host pacs.example.org
```

`--host` also checks that the DNS name points to this server. Later steps add `--cert` and `--key` ([4.8](#tls-certificate))
and `--dir /opt/ohif` ([4.13](#start-and-check)). The output is German when `LANG` starts with `de`. `--lang en` forces English.

A real run on a system that is ready (long runs of `[ OK ]` lines shortened with `...`):

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

How to read it:

- `[ OK ]` needs nothing. `[WARN]` needs your attention, and its `Fix:` line shows a command. `[FAIL]` stops the install: fix it
  first. The exit code is 0 (all ok), 1 (warnings) or 2 (failures).
- The mount-propagation warning belongs to the disk assistant ([modules.md](modules.md#disk-assistant)). Ignore it while you do
  not use the assistant.
- The DNS line shows the address of your server, not `127.0.0.1`.
- A missing package shows as `[FAIL]` or `[WARN]`. Step 4.3 installs it.
- The block "Lines still missing in /etc/default/pacs-admin" lists lines for step 4.4.

> **Check**
>
> Expected: the last lines of the summary read `Result: ... 0 failure(s)` and one of `READY: all checks passed` or
> `READY, with warnings: read the [WARN] lines`. `NOT READY: fix the [FAIL] lines first` means that a `[FAIL]` line names
> something to fix. Fix it, run the script again, and see [troubleshooting](troubleshooting.md#preflight-fails) if it stays.

<a id="packages"></a>
### 4.3 Install the packages

The helper service needs SQLCipher, an encryption library for the audit database ([glossary](glossary.md#sqlcipher)).
The package name depends on the Debian release. Docker Compose must be version 2.

| Release | SQLCipher package | Docker packages |
|---|---|---|
| Debian 13 (trixie) | `libsqlcipher1` | `docker.io`, `docker-compose` (this is Compose v2) |
| Debian 12 (bookworm) | `libsqlcipher0` | `docker.io`, `docker-compose-plugin` from the Docker repository (the Debian package `docker-compose` is Compose v1 and does not work) |
| Ubuntu | not tested | find the package with `apt-cache search sqlcipher` |

Install the packages that preflight reported as missing. This block installs the tools for Debian 13. Use `libsqlcipher0` on
Debian 12.

```bash
apt-get update
apt-get install -y libsqlcipher1 git curl cron openssl iproute2 iptables util-linux e2fsprogs udev
```

Preflight also prints a loop under "Missing packages in one go". It installs the packages one by one and reports a package that
does not exist.

> **Check**
>
> ```bash
> bash /opt/pacs-admin/deploy/tools/preflight.sh | grep -E '^\[(WARN|FAIL)\]'
> ```
>
> Expected: no `[FAIL]` line. Warnings about mount propagation or ports are allowed at this point.

<a id="settings-file"></a>
### 4.4 Create the settings file

The file `/etc/default/pacs-admin` tells the helper service, the cron job and the tools where things are on your server. Every
line of the example is commented out and shows the built-in default. On a standard dcm4chee layout you change little or nothing.

```bash
cp /opt/pacs-admin/deploy/pacs-admin.env.example /etc/default/pacs-admin
```

Compare **My values** from step 4.2 with the defaults. For each value that differs, remove the `#` in front of the line and
write your value. Open the file in an editor, for example `nano /etc/default/pacs-admin`. These are the settings you may need:

| Name | Change it when | Value from "My values" |
|---|---|---|
| `PACS_DIR` | the dcm4chee project folder is not `/opt/dcm4chee-arc` | compose project directory |
| `ARC_LOG_DIR` | the WildFly log lies elsewhere | wildfly log directory (host) |
| `ARC_CONTAINER`, `LDAP_CONTAINER` | the containers are not named `arc` and `ldap` | arc container, ldap container |
| `DASHBOARD_CONTAINERS` | the tile `Dienste` (services) should also show `ohif` and `ohif-auth` | `arc,ldap,db,ohif,ohif-auth` |
| `PACS_SOCKET_UID` | uid 101 is taken, or nginx runs on the host ([4.6](#helper-service), [5.3](#nginx-on-host)) | uid of nginx / sockets |
| `FW_INTERFACE` | you use the firewall module | outside network interface |

The file follows strict rules, because the shell and systemd both read it: one `NAME=value` per line, no spaces around `=`, no
`export`, no comment behind a value, whole numbers for numeric settings, and LF line endings. All variables and the rules are in
[reference.md](reference.md#config-variables) and [reference.md](reference.md#env-file-rules).

> **Check**
>
> ```bash
> sh -n /etc/default/pacs-admin && echo syntax ok
> grep -c $'\r' /etc/default/pacs-admin
> ```
>
> Expected:
>
> ```text
> syntax ok
> 0
> ```
>
> A number above 0 means Windows line endings. Fix them with `sed -i 's/\r$//' /etc/default/pacs-admin`.

<a id="audit-key"></a>
### 4.5 Create the audit key

The [audit log](glossary.md#audit-log) records who searched, opened a study or changed data. The helper service stores it in an
encrypted database. The key is a file with 64 hex characters. Only root may read it. The command below makes it:

```bash
(umask 077; openssl rand -hex 32 > /etc/pacs-protokoll.key)
```

> **Warning**
>
> Create the key once. A second run replaces it, and the events written so far can no longer be read. Without the key nobody
> can recover them. Back the key up now ([6.5](#backup-audit-key)).

The service creates the database `/var/lib/pacs-protokoll/protokoll.db` when it first starts ([4.6](#helper-service)). New files
use the SQLCipher format 3 (page size 1024), which Debian 12 and Debian 13 both open. A file in SQLCipher 4 format does not open
with `libsqlcipher` 3.x (Debian 12), and there is no converter. A tool that prints `file is not a database` (Debian 10 and 12
print `file is encrypted or is not a database`) met a wrong key, a foreign file or such a format 4 file.

> **Check**
>
> ```bash
> ls -l /etc/pacs-protokoll.key
> python3 /opt/pacs-admin/server/pacsdb.py test
> ```
>
> Expected: the file has 65 bytes (64 characters and a line break), owner `root` and mode `-rw-------`. The self-test uses a
> throw-away database, not your key. On Debian 13 it prints:
>
> ```text
> -rw------- 1 root root 65 Oct 13 14:50 /etc/pacs-protokoll.key
> Selbsttest ok: schreiben, lesen, Datei ohne Klartext, falscher Schluessel und fremde Datei abgewiesen, Format 3 (Seitengroesse 1024) und Bibliotheksstandard (4096) lesbar, SQLCipher 4.6.1 community
> ```
>
> `Selbsttest ok` means the self-test passed. On Debian 12 the line ends with `Bibliotheksstandard (1024) lesbar, SQLCipher
> 3.4.1`. If it names a missing library, see [troubleshooting](troubleshooting.md#libsqlcipher-missing). If a tool reports a
> wrong key later, see [troubleshooting](troubleshooting.md#audit-key-mismatch).

<a id="helper-service"></a>
### 4.6 Start the helper service

The [helper service](glossary.md#helper-service) is a small Python program that runs as root under systemd. It does the work
that nginx in a container must not do: it writes the audit log, changes firewall rules and runs the disk assistant. nginx
and the service talk through two [unix sockets](glossary.md#unix-socket) in `/run/pacs-admin/`. A unix socket is a file that
works like a network port inside one machine. The service gives both sockets to the [uid](glossary.md#uid) of nginx in the
container, which is 101. A uid is the number Linux uses for an account.

Ideally no account on the host has uid 101, because every program of such an account could use the sockets. Both commands below
should print nothing:

```bash
getent passwd 101
getent group 101
```

If one prints a line, see [troubleshooting](troubleshooting.md#uid-101-taken). For a plain system account (on Debian 12 it is
often `messagebus`) the risk is small, and the service starts anyway with a warning. Then install and start the unit:

```bash
cp /opt/pacs-admin/deploy/systemd/pacs-verwaltung.service /etc/systemd/system/
systemctl enable --now pacs-verwaltung
```

`enable --now` starts the service and starts it again at every boot. Do not start the script by hand while the unit runs. It
answers `laeuft schon` (already running).

> **Check**
>
> ```bash
> systemctl is-active pacs-verwaltung
> ls -l /run/pacs-admin/
> journalctl -u pacs-verwaltung -n 20 --no-pager
> curl -s --unix-socket /run/pacs-admin/verwaltung.sock http://localhost/admin/dienst/auftrag
> ```
>
> Expected: `active`, two sockets owned by `101` with mode `srw-------`, a ready line in the journal, and `{}` from the
> service (the date differs, and the journal line starts with date, host and program name):
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
> A journal line with `absender_sammeln` means that `ARC_LOG_DIR` is wrong ([4.4](#settings-file)). It does not stop the
> service. If the service is not `active` or the sockets are missing, see [troubleshooting](troubleshooting.md#no-sockets).

<a id="overview-cron"></a>
### 4.7 Install the overview job

The tab `Übersicht` needs the file `status.json`. A [cron](glossary.md#cron) job writes it every 5 minutes: disks, containers
and the state of the write list. Cron is the time scheduler of Linux. It runs from the package `cron`.

```bash
cp /opt/pacs-admin/deploy/cron/pacs-dashboard /etc/cron.d/pacs-dashboard
```

Do not wait for the first run. Start the job once by hand. It reads the settings file the same way as the cron job:

```bash
bash -c 'set -a; . /etc/default/pacs-admin; set +a; python3 /opt/pacs-admin/server/dashboard-status.py'
```

The repository may lie in another folder than `/opt/pacs-admin`. Then change the path in the files you copied, once:

```bash
sed -i 's|/opt/pacs-admin|/srv/pacs-admin|g' /etc/systemd/system/pacs-*.service /etc/cron.d/pacs-dashboard
systemctl daemon-reload && systemctl restart pacs-verwaltung
```

> **Check**
>
> ```bash
> systemctl is-active cron
> ls -l /var/lib/pacs-admin/status/status.json
> ```
>
> Expected: `active`, then one line for `status.json` with owner `root` and mode `-rw-r--r--`. The size and date differ. The
> manual run prints nothing when it works. If it prints `docker nicht gefunden`, Docker is not installed or not in the path
> of root. If `cron` is not `active`, see [troubleshooting](troubleshooting.md#cron-not-running).

<a id="tls-certificate"></a>
### 4.8 Get the TLS certificate

A [TLS certificate](glossary.md#tls-certificate) lets browsers trust the server and encrypts the traffic. nginx needs two files in
`/opt/ohif/tls/`: `server.crt` (the certificate, followed by its [chain](glossary.md#certificate-chain)) and `server.key` (the
private key). Skip this step for the recipes `proxied` (your proxy holds the certificate) and `tryit` (no TLS).

```bash
mkdir -p /opt/ohif/tls
```

**From your IT department or a certificate authority ([CA](glossary.md#ca)).** Ask for a certificate for `pacs.example.org` in
[PEM](glossary.md#pem) format. You get it in one of two forms. Two PEM files (server certificate and intermediate certificate):
join them, the server certificate first, and copy the key.

```bash
cat server.pem intermediate.pem > /opt/ohif/tls/server.crt
cp server-key.pem /opt/ohif/tls/server.key
```

One [PFX](glossary.md#pfx) file (`.pfx` or `.p12`): convert it. `openssl` asks for the password of the file.

```bash
openssl pkcs12 -in pacs.pfx -nocerts -nodes -out /opt/ohif/tls/server.key
openssl pkcs12 -in pacs.pfx -nokeys -out /opt/ohif/tls/server.crt
```

The output files contain harmless `Bag Attributes` lines. An old PFX file fails with `Error outputting keys and certificates`.
Add `-legacy` to both commands then.

**Let's Encrypt.** This service issues free certificates. Its tool `certbot` must prove that the name is yours, by a file on
port 80 of this server or by a DNS record. A server that the internet cannot reach needs the DNS way. This guide did not test
that path. Copy `/etc/letsencrypt/live/pacs.example.org/fullchain.pem` to `server.crt` and `privkey.pem` to `server.key`, and
repeat the copy after every renewal ([6.3](#renew-certificate)).

**Self-signed, for a test.** One command makes both files. Browsers warn about such a certificate and some login providers
refuse it.

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 825 -keyout /opt/ohif/tls/server.key -out /opt/ohif/tls/server.crt \
  -subj "/CN=pacs.example.org" -addext "subjectAltName=DNS:pacs.example.org"
```

**Set the permissions.** nginx reads the key when it starts, and who may read it depends on the image. The OHIF image (recipes
`oauth2`, `basic`) runs the nginx main process as uid 101, so the key must be readable by 101. The plain image `nginx:1.30`
(recipe `adminonly`) and nginx on the host run it as root. Run the block that fits:

```bash
chown root:101 /opt/ohif/tls/server.key && chmod 640 /opt/ohif/tls/server.key
```

```bash
chown root:root /opt/ohif/tls/server.key && chmod 600 /opt/ohif/tls/server.key
```

Keep the folder `tls/` at mode 755. A closed folder (700) stops the container as well. Never send the key by e-mail or put it in
a ticket or in git.

> **Check**
>
> ```bash
> bash /opt/pacs-admin/deploy/tools/preflight.sh --lang en --host pacs.example.org --cert /opt/ohif/tls/server.crt --key /opt/ohif/tls/server.key | sed -n '/== 4. TLS certificate/,/^$/p'
> ```
>
> Expected, here for a self-signed certificate with the first key mode (the dates differ):
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
> A certificate from a CA shows no `[WARN]` line. A `[FAIL]` line names the problem and a `Fix:`. Without `--dir` preflight
> does not know which nginx image you use. It prints the rights of the key and warns only when everybody can read it, so a
> `root:root 600` key (recipe `adminonly`) passes too. Step 4.13 runs the check again with `--dir` and then judges the rights
> for your image. For a key that nginx cannot read, see [troubleshooting](troubleshooting.md#tls-key-unreadable).

<a id="nginx-files"></a>
### 4.9 Build the nginx files

The front door reads its settings from a folder of small files, `/opt/ohif/nginx`. You build it from the repository in
`deploy/nginx`. It has three parts that you exchange: the [login method](glossary.md#login-method), the viewer, and the
[listener](glossary.md#listener) (how nginx accepts connections). The core file `pacs.conf` stays as it is. You edit only
`pacs/site.conf`. Every detail is in `deploy/nginx/README.md` and in [reference.md](reference.md#nginx-recipes).

Take the three values of your recipe from this table:

| Recipe | `LOGIN` | `VIEWER` | `LISTENER` |
|---|---|---|---|
| `oauth2` | `oauth2-proxy` | `ohif` | `tls` |
| `basic` | `basic` | `ohif` | `tls` |
| `adminonly` | `basic` | `none` | `tls` |
| `proxied` | `basic` | `ohif` | `behind-proxy` |
| `tryit` | `basic` | `none` | `plain` |

The login `none` (network lists, [login.md](login.md#login-none)) takes `LOGIN=none` and otherwise the values of `basic`.
Write your values in the first line and run the block:

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

The line with `optional/dcm4chee-ui.conf` copies the optional section for the dcm4chee user interface
([modules.md](modules.md#dcm4chee-ui)). Leave that line out if you do not want the section. The count in the check below is
then `12`.

Now edit `site.conf`. First write the name that users type in the browser:

```bash
HOST=pacs.example.org
sed -E -i "s/^(server_name +)[^;]+;.*/\1${HOST};/" /opt/ohif/nginx/pacs/site.conf
```

With `basic` or `none` the file `admins` decides who is an administrator, so delete the line of the admin group. With
`oauth2-proxy` keep it: step 4.12 sets it.

```bash
sed -i '/^set \$pacs_admin_group/d' /opt/ohif/nginx/pacs/site.conf
```

Recipe `proxied`: set the address range of your proxy now ([5.2](#variant-proxied)). Login `none`: set its two allow lists now
([login.md](login.md#login-none)).

> **Check**
>
> ```bash
> find /opt/ohif/nginx -type f | wc -l
> grep -rn CHANGE-ME /opt/ohif/nginx
> ```
>
> Expected: `13` files for every combination, and no output from `grep`. These markers stay until a later step: `oauth2`
> keeps the `pacs_admin_group` line (step 4.12), `proxied` the `set_real_ip_from` line ([5.2](#variant-proxied)), login `none`
> its allow lists. If the count differs, one of the three `cp` lines used a wrong value; run the block again.

Test the files before the first start. A throw-away container checks the syntax and disappears again. For `tryit` and
`proxied` leave out the second `-v` option, because they have no `tls` folder.

```bash
docker run --rm -v /opt/ohif/nginx:/etc/nginx/conf.d:ro -v /opt/ohif/tls:/etc/nginx/tls:ro nginx:1.30 nginx -t
```

> **Check**
>
> Expected: these last two lines. Messages about `default.conf` and about IPv6 before them are harmless.
>
> ```text
> nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
> nginx: configuration file /etc/nginx/nginx.conf test is successful
> ```
>
> `cannot load certificate` means that `tls/server.crt` or `server.key` is missing (step 4.8). Any other `[emerg]` line names
> the file and the line. See [troubleshooting](troubleshooting.md#nginx-wont-start).

<a id="compose-file"></a>
### 4.10 Copy and adjust the compose file

The compose file in `/opt/ohif` defines the container `ohif` (and for single sign-on `ohif-auth`). Copy the file of your recipe:

```bash
RECIPE=basic
cp /opt/pacs-admin/deploy/compose/docker-compose.$RECIPE.example.yml /opt/ohif/docker-compose.yml
```

Write the Docker network of your dcm4chee project into it, so that nginx reaches `arc` by name. The name is in **My values**
(step 4.2) and in `docker network ls`.

```bash
NETWORK=dcm4chee-arc_default
sed -i -E "s|^(    name: ).*# CHANGE-ME: name of that network.*|\1${NETWORK}|" /opt/ohif/docker-compose.yml
```

Each recipe needs other items in the folder `/opt/ohif`. Docker makes an empty folder, owned by root, for every missing item,
and the service behind it fails. The steps in brackets make the items.

| Recipe | `tls/` (4.8) | `htpasswd/` (4.12) | `app-config.js` (4.11) | `config.js` (4.11) | `ohif-auth.env` (4.12) |
|---|---|---|---|---|---|
| `oauth2` | yes | | yes | optional | yes |
| `basic` | yes | yes | yes | optional | |
| `adminonly` | yes | yes | | required | |
| `proxied` | | yes | yes | optional | |
| `tryit` | | yes | | required | |

> **Check**
>
> ```bash
> grep -n 'CHANGE-M[E]' /opt/ohif/docker-compose.yml
> docker compose -f /opt/ohif/docker-compose.yml config --quiet && echo "compose file ok"
> ```
>
> Expected: no output from `grep` (the brackets keep the header comment of the file out of the result), then `compose file ok`.
> More markers stay in two recipes: `proxied` keeps the proxy network line ([5.2](#variant-proxied)), and `oauth2` keeps five
> lines (tenant, two groups, redirect address, proxy subnet), which step 4.12 fills. Run the second command for `oauth2`
> after step 4.12, because it needs `ohif-auth.env`. A YAML error names the line to fix.

<a id="viewer-config"></a>
### 4.11 Set up the viewer and the page settings

Two small files adjust what users see. The compose file mounts them into the container.

**Recipes with the viewer (`oauth2`, `basic`, `proxied`): `app-config.js`.** It tells the OHIF viewer where the archive is (the
address of the page itself, AE title `DCM4CHEE`) and turns off functions that the front door does not allow.

```bash
cp /opt/pacs-admin/deploy/app-config.js.example /opt/ohif/app-config.js
```

Leave the file as it is. Never change `supportsReject: false`, `dicomUploadEnabled: false` and the bulkDataURI block: the locks
of the front door rely on them. For another AE title use `set-aet.sh` ([reference.md](reference.md#command-set-aet)). Every line
is explained in [reference.md](reference.md#app-config-js). After an edit run `docker compose restart` in `/opt/ohif`, because the
container reads a mounted single file only at its start.

**Recipes without the viewer (`adminonly`, `tryit`): `config.js` is required.** It hides the link `Viewer` in the top bar. Copy
it, set `viewerUrl: ''`, and remove the `# ` in front of the mount line in the compose file:

```bash
cp /opt/pacs-admin/web/admin/config.js /opt/ohif/config.js
sed -i "s|^\( *viewerUrl: \)'/',|\1'',|" /opt/ohif/config.js
sed -i -E 's|^( +)# (- \./config\.js:)|\1\2|' /opt/ohif/docker-compose.yml
```

**Recipes with the viewer: `config.js` is optional.** It sets the page title, the AE titles, the links and the language (keys
`titel`, `aet`, `iocmAet`, `dcm4cheeUrl`, `viewerUrl`, `logo`, `locale`, `kontoUrl`, `abmeldenUrl`; see
[reference.md](reference.md#config-js)). To use it, run the `cp` command and the last `sed` command above, edit the copy, and
run `docker compose restart` in `/opt/ohif` after each edit.

> **Warning**
>
> Edit the copy in `/opt/ohif`, never `/opt/pacs-admin/web/admin/config.js`. `git pull` stops with a conflict on a changed file
> ([6.1](#update)). To undo a mistake in the copy, delete it and copy the original again.

> **Check**
>
> ```bash
> grep -n 'viewerUrl' /opt/ohif/config.js
> grep -n '^ *- \./config\.js' /opt/ohif/docker-compose.yml
> ```
>
> Expected for a recipe without the viewer (the example shows `adminonly`; the mount line has the number 71 there and 67 in `tryit`):
>
> ```text
> 8:  viewerUrl: '',                       // Verweis "Viewer" im Kopf, leer = ausblenden
> 71:      - ./config.js:/srv/pacs-admin/admin/config.js:ro
> ```
>
> The file `app-config.js` is checked by the preflight run in step 4.13. After the start you can also open
> `https://pacs.example.org/app-config.js`: the script text appears.

<a id="login-setup"></a>
### 4.12 Set up the login

The login chapter of your recipe finishes the setup. Use the part that fits.

**Single sign-on (`oauth2`).** Follow [login.md](login.md#login-oauth2-entra), steps 1 to 9. They register the app in Microsoft
Entra ID, write `ohif-auth.env`, fill the five remaining marker lines of the compose file, and put the admin group into
`site.conf`. Stop before step 10, which starts the containers. Step 4.13 starts them as well, and a second
`docker compose up -d` does no harm. Steps 4.9 and 4.10 already set the host name and the network name. login.md sets them
again, which does no harm, and its step 8 then lists five marker lines instead of six. For another provider see
[login.md](login.md#login-oauth2-providers).

**Accounts kept by nginx (`basic`, `adminonly`, `proxied`, `tryit`).** Make the first account with the helper script. `admin`
lets the account use the admin panel and the viewer. `all` lets it use the viewer only. The script asks for the password twice
(at least 10 characters) and creates `/opt/ohif/htpasswd/users` (all accounts) and `admins`.

```bash
bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh admin anna
```

nginx reads the two files at every request, so new accounts work at once. Run the command again for every person. The same name
with a new password replaces the old password. To remove an account, delete its line from both files and keep at least one
administrator:

```bash
sed -i '/^anna:/d' /opt/ohif/htpasswd/users /opt/ohif/htpasswd/admins
```

Limits of this login (no sign-out, no second factor, no limit on wrong passwords): [login.md](login.md#login-basic).

> **Check**
>
> ```bash
> ls -ln /opt/ohif/htpasswd
> ```
>
> Expected: the script printed these lines (for `admin`), and the two files belong to uid 101 with mode 600:
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
> The size is the length of the name plus 108 (name, colon, a hash of 106 characters, line break), so another name gives
> another number. `the password is shorter than 10 characters` and `invalid name` stop the script without a change. The line
> `WARNING: this openssl cannot make sha512-crypt hashes` means that OpenSSL is older than 1.1.1: the script uses the
> weaker hash type `apr1` instead, and the summary line says `password hash type apr1`. Update OpenSSL and run the command
> again. Without the two files, or when the nginx worker cannot read them, the browser asks for a password and then shows an
> error page: 403 for a missing file, 500 for an unreadable one ([troubleshooting](troubleshooting.md#htpasswd-403-500)).

**No login (`none`).** Access is limited by network lists only. Create the empty folder that the compose file mounts, then
follow [login.md](login.md#login-none):

```bash
mkdir -p /opt/ohif/htpasswd
```

<a id="start-and-check"></a>
### 4.13 Start the front door and check it

At the first start Docker downloads the images. This takes a minute or more.

> **Warning**
>
> The start takes over the ports 80 and 443 (`tryit`: 8080 on 127.0.0.1; `proxied`: no port). Users of an old front door lose
> access at that moment. If Docker answers `address already in use`, another program still holds the port: stop it first
> (section 3). `arc`, `ldap` and `db` are not touched. To go back, run `cd /opt/ohif && docker compose down` and start the
> old front door from your copy of its compose file.

```bash
cd /opt/ohif && docker compose up -d
```

Docker prints a few lines per container and ends with `Started`:

```text
 Container ohif Creating
 Container ohif Created
 Container ohif Starting
 Container ohif Started
```

> **Check**
>
> ```bash
> docker ps --format '{{.Names}}  {{.Status}}' | grep '^ohif'
> docker exec ohif nginx -t
> docker logs ohif 2>&1 | grep -c emerg
> curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/
> ```
>
> Expected (`oauth2` also lists `ohif-auth`):
>
> ```text
> ohif  Up 7 seconds
> nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
> nginx: configuration file /etc/nginx/nginx.conf test is successful
> 0
> 401
> ```
>
> The last number depends on the login, asked without a password: `oauth2` answers `302` (to the sign-in page), `basic` `401`,
> `none` `403` from a PC outside the allow list. If the name does not resolve yet, add `--resolve pacs.example.org:443:127.0.0.1`
> to `curl`. With `basic` this call must return `200` (`curl` asks for the password):
> `curl -sk -u anna -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/`.
> A status `Restarting`, a count above `0`, or another number: read `docker logs ohif` and see
> [troubleshooting](troubleshooting.md#nginx-wont-start). For `proxied` and `tryit` use the checks in section 5 instead of the
> `curl` call.

Run the preflight check once more, now with the folder, the certificate and the key:

```bash
bash /opt/pacs-admin/deploy/tools/preflight.sh --host pacs.example.org --cert /opt/ohif/tls/server.crt --key /opt/ohif/tls/server.key --dir /opt/ohif
```

> **Check**
>
> Expected: no `[FAIL]` line. Two warnings are normal now, `[WARN] port 80 is already in use` and the same for port 443,
> because your own container holds them. The last group shows (the numbers differ by recipe):
>
> ```text
> == 5. Configuration files ==
> [ OK ] /etc/default/pacs-admin: syntax ok (shell and systemd read it the same way)
> [ OK ] /opt/ohif: no CHANGE-ME and no <placeholder> left in 15 file(s)
> [ OK ] nginx tree /opt/ohif/nginx: all 11 included files exist
> [ OK ] compose bind mounts: all 8 sources exist and look complete
> ```
>
> A `[WARN]` or `[FAIL]` line in this group names the file and a `Fix:` command.

<a id="first-test"></a>
### 4.14 Test in the browser

1. Open `https://pacs.example.org/admin/` and sign in. With `basic` the browser asks for a user name and a password. With `oauth2`
   it opens the page of your identity provider.
2. The top bar shows the tabs `Übersicht` (overview), `Studien` (studies), `Patienten` (patients), `Firewall` and `Protokoll`
   (audit log), and the links `dcm4chee` and `Viewer`. `Abmelden` (sign out) appears with oauth2-proxy
   ([login.md](login.md#login-oauth2-operate)).
3. The tab `Übersicht` shows the tiles `Dienste` (services), `Speicher` (storage) and `Letzte Änderungen` (last changes). If the
   tile says `Kein Status vorhanden`, run the by-hand job of step 4.7. The tile `Dienste` lists the containers of the dcm4chee
   project. To add `ohif` and `ohif-auth`, set `DASHBOARD_CONTAINERS=arc,ldap,db,ohif,ohif-auth` ([4.4](#settings-file)).
4. Open the `Viewer` link and a study (recipes with the viewer). Then open the tab `Protokoll`, choose `Heute` (today) and click
   `Anzeigen` (show). The list shows a row `Studie geöffnet` (study opened) with your account.

![The tab Übersicht](screenshots/overview.png)

> **Check**
>
> ```bash
> journalctl -u pacs-verwaltung -n 50 --no-pager | grep -c 'Protokoll nicht abgelegt'
> ```
>
> Expected: `0`. A number above 0 means the helper service could not store audit lines: see
> [troubleshooting](troubleshooting.md#audit-key-mismatch). A `502` on the admin page: see
> [troubleshooting](troubleshooting.md#admin-dienst-502).

<a id="optional-modules"></a>
### 4.15 Optional modules

The base install is complete. Three modules add more. Each has its own chapter in [modules.md](modules.md) and is not needed
for the admin panel:

- The **disk assistant** prepares new disks for dcm4chee storage ([modules.md](modules.md#disk-assistant)).
- The **firewall** limits which computers may reach the DICOM ports of the archive ([modules.md](modules.md#firewall)).
- The **dcm4chee user interface** gives administrators the web interface of dcm4chee itself behind the same login
  ([modules.md](modules.md#dcm4chee-ui)). Step 4.9 already copied its nginx file.

> **Warning**
>
> The disk assistant and the firewall change the compose file of the dcm4chee project and recreate the container `arc`. The
> archive is unreachable until `arc` is up again. Do this in a maintenance window. Check with `docker compose ps` and
> `docker logs arc` in the dcm4chee folder. To go back, restore the copy of the compose file from section 3
> (`cp /root/dcm4chee-compose.DATE.yml /opt/dcm4chee-arc/docker-compose.yml`) and run `docker compose up -d` there.

<a id="variants-detail"></a>
## 5. Variants in detail

Each variant changes a few steps of section 4. This section lists only the differences. Everything else stays as written.

<a id="variant-adminonly"></a>
### 5.1 Admin panel only (`adminonly`)

There is no OHIF viewer, and nginx runs in the plain image `nginx:1.30`. Step 4.8: the key gets `root:root 600` (the second
block). Step 4.9: `LOGIN=basic; VIEWER=none; LISTENER=tls`. Step 4.10: copy `docker-compose.adminonly.example.yml`. Step 4.11:
no `app-config.js`, but `config.js` with `viewerUrl: ''` is required. Step 4.12: accounts as for `basic`.

> **Check**
>
> ```bash
> curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/
> bash /opt/pacs-admin/deploy/tools/preflight.sh --lang en --host pacs.example.org --cert /opt/ohif/tls/server.crt --key /opt/ohif/tls/server.key --dir /opt/ohif | grep 'private key permissions'
> ```
>
> Expected: the start page redirects to the admin panel, and the key mode fits the plain image.
>
> ```text
> 302
> [ OK ] private key permissions fit the plain nginx image (root:root 600)
> ```

<a id="variant-proxied"></a>
### 5.2 Behind your own TLS proxy (`proxied`)

A proxy that you already run (Traefik, Caddy, Apache, Cloudflare Tunnel) ends TLS and passes the traffic to the container
`ohif` over plain http. nginx keeps the login, the locks and the audit log. The container publishes no port, and only the
proxy may reach it. Otherwise anybody could write a false client address into `X-Forwarded-For`, and the audit log would
believe it.

- Step 4.8 is not needed. Step 4.9: `LOGIN=basic; VIEWER=ohif; LISTENER=behind-proxy`. Step 4.10: copy
  `docker-compose.proxied.example.yml`. Step 4.12: accounts as for `basic`. For single sign-on behind a proxy see
  [login.md](login.md#login-other).
- Name the Docker network that the proxy and `ohif` share. A network that only these two use is best. If your proxy sits in the
  dcm4chee network itself, delete the block `proxy:` and the line `- proxy` in the compose file instead.
- Tell nginx which network may report client addresses, with the subnet of that network. The shipped value `203.0.113.1` trusts nobody; the last command replaces it.

```bash
PROXY_NETWORK=proxy_default
sed -i -E "s|^(    name: ).*# CHANGE-ME: name of the network of your proxy.*|\1${PROXY_NETWORK}|" /opt/ohif/docker-compose.yml
PROXY_NET=$(docker network inspect $PROXY_NETWORK -f '{{(index .IPAM.Config 0).Subnet}}')
sed -E -i "s|^(set_real_ip_from +)[^;]+;.*|\1${PROXY_NET};|" /opt/ohif/nginx/pacs/listener/server.conf
```

In the proxy, send the host name to `http://ohif:8080` (container name and container port). Pass the `Host` header unchanged
(Apache: `ProxyPreserveHost On`) and the client address in `X-Forwarded-For` (Traefik, Caddy and Cloudflare Tunnel do). If the
proxy listens on another port than 443, put that port into the pattern in `pacs/listener/http.conf`.

> **Check**
>
> ```bash
> grep -n set_real_ip_from /opt/ohif/nginx/pacs/listener/server.conf
> curl -s -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/
> ```
>
> Expected: the line shows your subnet, for example `5:set_real_ip_from 172.23.0.0/16;`, and the call through the proxy
> answers `401`. Run the second command on a PC, not on the server, if the proxy is on another host. A `502` or `504` comes
> from the proxy: check the network name and the target `http://ohif:8080`.

<a id="nginx-on-host"></a>
### 5.3 nginx on the host

nginx can also run as a package on the host. This variant has no OHIF viewer, because the Debian package does not contain the
OHIF files. It needs nginx 1.25.1 or newer. Debian 13 has 1.26. Debian 12 has 1.22 (see the last block of this part). Steps
4.1 to 4.7 stay. The container `ohif` is not used, so steps 4.10, 4.11 (`app-config.js`) and 4.13 fall away. The full recipe is
in the section `host-nginx` of `deploy/nginx/README.md`.

1. Install nginx. Remove the default site, else nginx complains about a duplicate default server.

   ```bash
   apt-get install -y nginx openssl
   rm -f /etc/nginx/sites-enabled/default
   ```

2. Build the nginx files as in step 4.9, with `T=/etc/nginx/conf.d`, `VIEWER=none`, `LISTENER=tls` and your `LOGIN`. Then use the
   host ports and point nginx to the archive on the loopback address.

   ```bash
   T=/etc/nginx/conf.d
   sed -i -e 's/8080/80/g' -e 's/8443/443/g' $T/pacs/listener/*.conf
   sed -i -e 's#^set \$arc .*#set $arc http://127.0.0.1:8080;#' -e '/^resolver /d' $T/pacs/site.conf
   ```

3. Put the admin page and the status file where `pacs.conf` expects them.

   ```bash
   mkdir -p /srv/pacs-admin /var/lib/pacs-admin/status
   ln -sfn /opt/pacs-admin/web/admin /srv/pacs-admin/admin
   ln -sfn /var/lib/pacs-admin/status /srv/pacs-admin/status
   ```

4. The nginx workers run as `www-data` (uid 33). The helper service must give its sockets to that uid ([4.6](#helper-service)).

   ```bash
   sed -i 's/^#PACS_SOCKET_UID=.*/PACS_SOCKET_UID=33/' /etc/default/pacs-admin
   systemctl restart pacs-verwaltung
   ```

   The service warns that `www-data` is shared. If PHP or another web application runs as `www-data`, give nginx its own
   account: `useradd -r -s /usr/sbin/nologin pacsweb`, the line `user pacsweb;` in `/etc/nginx/nginx.conf`, and the uid of
   that account in `PACS_SOCKET_UID`.

5. Make the accounts in `/etc/nginx/htpasswd/`, with the owner and mode that fit the workers.

   ```bash
   mkdir -p /etc/nginx/htpasswd
   bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh admin anna --users /etc/nginx/htpasswd/users --admins /etc/nginx/htpasswd/admins --owner root:www-data --mode 640
   ```

6. In `/etc/nginx/conf.d/pacs/site.conf` set `server_name` as in step 4.9. The last two lines of
   `/etc/nginx/conf.d/pacs/listener/server.conf` are the `ssl_certificate` lines: point them to your files (with Let's Encrypt:
   `/etc/letsencrypt/live/pacs.example.org/fullchain.pem` and `privkey.pem`). The key is `root:root 600`, because the nginx main
   process is root.
7. The archive must listen on `127.0.0.1:8080`. If the check below shows nothing, change the `ports` line of `arc` in the
   dcm4chee compose file to `127.0.0.1:8080:8080` and recreate `arc`.

> **Warning**
>
> Recreating `arc` makes the archive unreachable until it is up again. Check with `docker compose ps` and `docker logs arc`
> in the dcm4chee folder. To go back, restore the copy of the compose file from section 3 and run `docker compose up -d`.

On Debian 12 (nginx 1.22) change the listener before the first start, else nginx stops with `unknown directive "http2"`. This
edit was checked on Debian 12 with nginx 1.22.1: `nginx -t` passes, HTTP/2 works, and port 80 redirects to https.

```bash
sed -i -e '/^http2 on;/d' -e 's/^listen 443 ssl default_server;/listen 443 ssl http2 default_server;/' /etc/nginx/conf.d/pacs/listener/server.conf
```

> **Check**
>
> ```bash
> ss -ltn | grep '127.0.0.1:8080'
> nginx -t && systemctl reload nginx
> curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/
> ```
>
> Expected: one `LISTEN` line for `127.0.0.1:8080`, then `syntax is ok` and `test is successful`, and `401` (`basic`) or
> `302` (`oauth2-proxy`). See [troubleshooting](troubleshooting.md#nginx-wont-start) if nginx does not start.

The firewall tab filters Docker traffic only, so it does not cover ports 80 and 443 of the host. nginx should start after the
helper service, else it loses audit lines until the sockets exist: a systemd drop-in for `nginx.service` with `Wants=` and
`After=pacs-verwaltung.service` does that (not tested).

<a id="variant-tryit"></a>
### 5.4 A first look through an SSH tunnel (`tryit`)

nginx listens on `127.0.0.1:8080` of the server, without TLS. Nobody reaches it from the network, and it needs no certificate.
Use it to test, not for daily work. Step 4.8 is not needed. Step 4.9: `LOGIN=basic; VIEWER=none; LISTENER=plain`. Step 4.10: copy `docker-compose.tryit.example.yml`. Step 4.11: `config.js` is required.
Step 4.12: accounts as for `basic`. Because nginx sees only the Docker gateway as client, the audit log shows one address for
all users.

From your PC open the tunnel. Use the same port at both ends: the browser puts the port into the Referer, and a rule of the
dcm4chee UI section names `:8080`.

```bash
ssh -L 8080:127.0.0.1:8080 USER@SERVER
```

Then browse `http://localhost:8080/admin/` on your PC.

> **Check**
>
> ```bash
> curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/admin/
> curl -s -u anna -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/admin/
> ```
>
> Expected on the server: `401` without a login, then `200` with the account `anna` (`curl` asks for the password). The start
> page `/` answers `302` to `/admin/`.

<a id="operate"></a>
## 6. Daily operation

These tasks come back after the installation: update, apply a changed setting, renew the certificate, change a password, save the
audit key, and remove the panel.

<a id="update"></a>
### 6.1 Update to a new version

The programs live in the git folder `/opt/pacs-admin`. Your settings live outside it, so `git pull` does not overwrite them.
Your copies of the nginx files, the compose file and the settings file stay as they are, too. You compare them with the new
examples (table below). Note the current version first. It is the way back.

```bash
cd /opt/pacs-admin
git rev-parse --short HEAD
git pull
```

`git pull` lists the files that changed. If it stops with "Your local changes ... would be overwritten", you edited a file in the
folder. Copy that file to another place, run `git checkout -- FILE`, pull again, and use the copy from now on.

| Changed path | What to do |
|---|---|
| `web/admin/`, `server/dashboard-status.py`, `server/pacs-storage.sh`, `deploy/tools/` | Nothing. The container reads `web/admin/` directly (press Ctrl+F5 in the browser). The other files start anew at every run. |
| `server/verwaltung-dienst.py`, `server/pacsdb.py`, `deploy/systemd/pacs-verwaltung.service` | If the unit file changed, copy it again ([4.6](#helper-service)) and run `systemctl daemon-reload`. Then restart the service (below). |
| `deploy/cron/pacs-dashboard` | Copy it again ([4.7](#overview-cron)). |
| `server/firewall.py`, `deploy/systemd/pacs-firewall.service` | Only with the firewall module. Copy the unit again if it changed. Apply the new code without a gap: `set -a; . /etc/default/pacs-admin; set +a; python3 /opt/pacs-admin/server/firewall.py start`. Never run `systemctl restart pacs-firewall`: it opens all ports for a moment. |
| `deploy/nginx/` | Run the copy block of [4.9](#nginx-files) again with `T=/opt/ohif/nginx.new` and your values. Then `diff -r /opt/ohif/nginx /opt/ohif/nginx.new`. Your values in `site.conf` show as differences, every other difference is new. Copy those into `/opt/ohif/nginx` and reload nginx ([6.2](#change-settings)). |
| `deploy/compose/` | `diff /opt/pacs-admin/deploy/compose/docker-compose.$RECIPE.example.yml /opt/ohif/docker-compose.yml` with `RECIPE` as in [4.10](#compose-file). The lines with your values differ, the rest is new. Add the new lines and run `docker compose up -d`. |
| `deploy/pacs-admin.env.example`, `deploy/app-config.js.example` | `diff` them against your copies the same way. Add the new lines and apply them as in [6.2](#change-settings). |

The compose files pin their image versions. A tag such as `nginx:1.30` still receives fixes. To load them, run
`cd /opt/ohif && docker compose pull && docker compose up -d`. This recreates `ohif` and interrupts users for a few seconds. For a
new version of the OHIF image or of oauth2-proxy, change the tag in your compose file first.

> **Warning**
>
> A restart of `pacs-verwaltung` takes a few seconds. In that time nginx cannot write audit lines, they are lost
> ([reference.md](reference.md#audit-lost)), and the admin panel answers `502`. Restart outside working hours, and never while the
> disk assistant runs a setup: the restart stops it in the middle. If the service does not start after an update, go back:
> `git reset --hard NUMBER` in `/opt/pacs-admin` (the number noted above, it also discards edits in that folder), copy the unit
> file again if it changed, then `systemctl daemon-reload && systemctl restart pacs-verwaltung`.

```bash
systemctl restart pacs-verwaltung
```

> **Check**
>
> ```bash
> systemctl is-active pacs-verwaltung
> journalctl -u pacs-verwaltung -n 3 --no-pager
> ```
>
> Expected: `active` and the ready line `pacs-verwaltung bereit: ...` as in [4.6](#helper-service). Otherwise see
> [troubleshooting](troubleshooting.md#no-sockets).

<a id="change-settings"></a>
### 6.2 Apply a changed setting

After you edit a file, one command makes the change work. The wrong command does nothing, or it restarts more than needed.

| You changed | Run |
|---|---|
| `/etc/default/pacs-admin` | `systemctl restart pacs-verwaltung` (Warning in [6.1](#update)). The cron job reads the file at every run. Firewall values need `firewall.py start` as in 6.1. |
| a file in `/opt/ohif/nginx/` | `docker exec ohif nginx -t && docker exec ohif nginx -s reload` |
| `/opt/ohif/docker-compose.yml` | `cd /opt/ohif && docker compose up -d` |
| `/opt/ohif/config.js` or `app-config.js` | `cd /opt/ohif && docker compose restart ohif`, then Ctrl+F5 in the browser |
| `/opt/ohif/htpasswd/` | Nothing. nginx reads the files at every request. |
| `/opt/ohif/tls/server.crt` or `server.key` | Reload nginx as in the second row ([6.3](#renew-certificate)). |

`nginx -t` tests the files first. When it prints an error, the `&&` stops the reload and nginx keeps its old files, so a typo
does no harm. With nginx on the host use `nginx -t && systemctl reload nginx`.

<a id="renew-certificate"></a>
### 6.3 Renew the TLS certificate

A certificate ends on a fixed date. After that every browser shows a warning. Look at the end date, and set a reminder 30 days
before it:

```bash
openssl x509 -in /opt/ohif/tls/server.crt -noout -enddate
```

With the recipe `proxied` your proxy holds the certificate: renew it there. For the other recipes:

1. Get the new certificate as in [4.8](#tls-certificate): the full chain, server certificate first. When your CA wants a new key,
   use the new key with the new certificate.
2. Keep the old files until the check passes.

   ```bash
   cp -a /opt/ohif/tls /root/ohif-tls.$(date +%F)
   ```

3. Copy the new files over `server.crt` and `server.key` in `/opt/ohif/tls/`. Set owner and mode again with the block of 4.8 that
   fits your image. With Let's Encrypt, repeat the two `cp` commands of 4.8 after every renewal. A script in
   `/etc/letsencrypt/renewal-hooks/deploy/` can do that and the reload for you (not tested here).
4. Reload nginx. It reads certificate and key again, and open connections stay up.

   ```bash
   docker exec ohif nginx -t && docker exec ohif nginx -s reload
   ```

> **Check**
>
> ```bash
> openssl x509 -in /opt/ohif/tls/server.crt -noout -enddate
> echo | openssl s_client -connect pacs.example.org:443 -servername pacs.example.org 2>/dev/null | openssl x509 -noout -enddate
> ```
>
> Expected: both lines show the same new end date, for example `notAfter=Jan 15 15:27:00 2029 GMT`. If the second line shows the
> old date, nginx did not reload (read the output of `nginx -t`). If the key cannot be read, see
> [troubleshooting](troubleshooting.md#tls-key-unreadable). To go back, copy `/root/ohif-tls.DATE` over `/opt/ohif/tls` and
> reload nginx.

<a id="rotate-secrets"></a>
### 6.4 Change passwords and secrets

| Secret | How to change it |
|---|---|
| Client secret and cookie secret (`oauth2-proxy`) | [login.md](login.md#login-oauth2-operate). Everybody signs in again. |
| Password of a `basic` account | Run `pacs-adduser.sh` again with the same name and the same list: `admin` for an administrator, `all` for everybody else (`all` takes an administrator out of the admin list). It asks twice for the new password and replaces the line. The new password works at once. Host nginx needs the extra options of [5.3](#nginx-on-host). |
| TLS key | Make a new key and a new certificate together, then replace both files ([6.3](#renew-certificate)). |
| Audit key | The repository has no tool that re-keys the database. Keep the key and back it up ([6.5](#backup-audit-key)). |

<a id="backup-audit-key"></a>
### 6.5 Back up the audit key and the audit database

Without the key nobody can read the audit log again, you included. Keep a copy outside this server, in your password safe and
apart from the database backup. A key that lies next to the data protects nothing.

```bash
cat /etc/pacs-protokoll.key
```

Copy the 64 characters into the safe. Then prove that the copy is right. `read -rs` asks for the text, shows nothing and keeps it
out of the shell history. Paste the key from the safe and press Enter:

```bash
read -rs KEYCOPY; echo
[ "$KEYCOPY" = "$(cat /etc/pacs-protokoll.key)" ] && echo "key copy matches"
```

The database is the folder `/var/lib/pacs-protokoll/`. The audit log is never pruned and holds patient IDs
([reference.md](reference.md#audit-retention)). Add the folder to your server backup like patient data. Keep all its files
together: `protokoll.db`, and while the service runs also `protokoll.db-wal` and `protokoll.db-shm`. A copy taken during a write
can be damaged, so read every backup once with the live key:

```bash
PROTOKOLL_DB=/mnt/backup/pacs-protokoll/protokoll.db python3 /opt/pacs-admin/server/pacsdb.py protokoll zugriffe | wc -l
```

> **Check**
>
> Expected: `key copy matches`, then a number above 0 (the stored requests). The line `pacsdb.py: ... not a database`
> means a wrong key or a damaged copy ([troubleshooting](troubleshooting.md#audit-key-mismatch)). A `0` means a wrong path (the
> program then creates an empty database there) or that nobody has used the panel yet. To restore on a new server, put the key
> at `/etc/pacs-protokoll.key` (mode 600) and the folder at `/var/lib/pacs-protokoll/` before the service starts.

<a id="uninstall"></a>
### 6.6 Remove the admin panel

> **Warning**
>
> This removes the login, the locks and the audit log in front of the archive. The viewer and the admin panel stop working.
> The dcm4chee archive keeps running. Nothing in `/opt/ohif` is deleted. To go back, run `cd /opt/ohif && docker compose up -d`
> and repeat the steps [4.6](#helper-service) and [4.7](#overview-cron).

**1. Containers.** The folder `/opt/ohif`, the images and the dcm4chee containers stay.

```bash
cd /opt/ohif && docker compose down
```

**2. Helper service and cron job.**

```bash
systemctl disable --now pacs-verwaltung
rm /etc/systemd/system/pacs-verwaltung.service /etc/cron.d/pacs-dashboard
systemctl daemon-reload
```

**3. Firewall module, only if you use it.**

> **Warning**
>
> The first command removes the jump into the chain `PACS-SPERRE`. From then on every port that Docker publishes is open to all
> networks that reach the server. Make sure another firewall protects them. To go back, copy `pacs-firewall.service` again and run
> `systemctl enable --now pacs-firewall` ([modules.md](modules.md#firewall)).

```bash
systemctl disable --now pacs-firewall
iptables -F PACS-SPERRE
iptables -X PACS-SPERRE
rm /etc/systemd/system/pacs-firewall.service
systemctl daemon-reload
```

**4. Changes in the dcm4chee project, only if you used a module.** The disk assistant and the firewall changed the compose file
of dcm4chee. Undo these changes as [modules.md](modules.md#disk-assistant) and [modules.md](modules.md#firewall) describe.

> **Warning**
>
> This recreates `arc`. The archive is unreachable until `arc` is up again. Do it in a maintenance window. Check with
> `docker compose ps` and `docker logs arc` in the dcm4chee folder. To go back, restore the copy of the compose file you made
> before the change and run `docker compose up -d` there.

> **Check**
>
> ```bash
> docker ps -a --format '{{.Names}}' | grep -c '^ohif'
> ls /etc/systemd/system/pacs-verwaltung.service /etc/cron.d/pacs-dashboard
> ```
>
> Expected: `0`, then two lines `ls: cannot access '...': No such file or directory`.

What stays on purpose, until you delete it yourself:

- `/var/lib/pacs-protokoll/` and `/etc/pacs-protokoll.key`: the audit log and its key. The log holds patient IDs, so keep both
  as long as your retention rules say, and delete them together.
- `/etc/default/pacs-admin`, `/opt/pacs-admin`, `/opt/ohif`, `/var/lib/pacs-admin/`, `/var/log/pacs-dashboard.log`.
- With the modules: `firewall.json` and the folder `firewall/` in the dcm4chee folder, the file that `FW_DEFAULT_RULES` names,
  `/var/log/pacs-storage.log`, and the disks that the assistant set up. Those disks hold studies. They are normal dcm4chee
  storages with entries in `/etc/fstab`.
