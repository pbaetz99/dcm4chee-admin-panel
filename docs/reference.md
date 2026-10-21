# Reference

English | [Deutsch](reference.de.md)

This page lists facts: settings, tools, files, ports, the contract of the front door and the format of the audit log. It has no steps. For steps, read the [install guide](install.md). For the login methods, read [Login](login.md). The disk assistant and the firewall have their own page: [Modules](modules.md). For errors, read [Troubleshooting](troubleshooting.md). The [glossary](glossary.md) explains the terms.

1. [Configuration](#configuration)
2. [Tools and packages](#tools-and-packages)
3. [Files, services, ports, sockets and mounts](#files-ports-sockets)
4. [nginx recipes and the AE title](#nginx-recipes)
5. [Front-door contract](#front-door-contract)
6. [Audit log](#audit-log)

Three words are used in many places. The **front door** is the web server in front of the page, the helper service and dcm4chee. In this repository it is nginx. **Any account** means every account that the login lets in. **Admin** means an account that may open `/admin/` and change data. See [glossary](glossary.md#front-door).

<a id="configuration"></a>
## 1. Configuration

Five places hold settings.

| Place | Holds | Who edits it |
|---|---|---|
| `/etc/default/pacs-admin` | settings of the helper service, the firewall, the disk assistant and the cron job | you |
| `web/admin/config.js` | title, AE titles, links and account label of the page | you |
| `app-config.js` of the OHIF viewer | where the viewer finds the archive | you, with `set-aet.sh` for the AE title |
| `pacs/site.conf` in the nginx files | host name, upstream names, certificate, admin group | you, see [section 4](#nginx-recipes) |
| `PACS_DIR/firewall.json` | the firewall rules | the Firewall tab |

<a id="config-variables"></a>
### 1.1 Settings file /etc/default/pacs-admin

The file `deploy/pacs-admin.env.example` lists every variable with its default, commented out. Copy it to `/etc/default/pacs-admin` and uncomment only what differs on your server. A variable that is missing or empty uses its default.

Four readers use the file:

- systemd loads it for both units (`EnvironmentFile=-`, so a missing file is no error and the defaults apply).
- The cron job loads it as a shell file.
- `pacs-storage.sh` loads it itself, at every start. The file wins over the environment that the script inherits.
- The Python programs read only their environment. When you run one by hand, load the file first:

```
set -a; . /etc/default/pacs-admin; set +a
```

<a id="env-file-rules"></a>
#### Rules for the file

The shell and systemd read the same file. They disagree about comments after a value, about spaces and about CRLF line endings. Stay inside what both understand.

- Do write one `NAME=value` per line, without spaces around `=`.
- Do put single quotes around a value with spaces, braces or JSON: `FW_PORT_NAMES='{"104": "DICOM (old)"}'`.
- Do write numbers as digits only: `STORAGE_MIN_GB=100`.
- Do use LF line endings. A file saved on Windows has CRLF: `sed -i 's/\r$//' /etc/default/pacs-admin`.
- Do not write `export`.
- Do not write spaces around `=`.
- Do not write a comment behind a value: `FW_INTERFACE=eth0  # outside` is wrong.
- Do not use `$VARIABLES` or backquoted commands in values. Only the shell would expand them.

Check the syntax after every edit:

```
sh -n /etc/default/pacs-admin && echo syntax ok
```

`preflight.sh` checks the file too ([section 2.3](#command-preflight)). A syntax error stops the cron job. The error message goes to `/var/log/pacs-dashboard.log`. `pacs-storage.sh` runs `bash -n` on the file first and stops with `HALT: /etc/default/pacs-admin hat einen Syntaxfehler (Meldung davor)`. The message of `bash` stands in the line above.

**Numeric values.** Write whole numbers without a unit, a sign, a space or a leading zero: `STORAGE_FREE_GB=50`, not `50GB`, not `050`. This applies to `PACS_SOCKET_UID`, `STORAGE_MIN_GB`, `STORAGE_FREE_GB` and `STORAGE_WARN_GB`. The three `STORAGE_*` values take at most 6 digits (up to 999999 GB). Longer numbers overflow the arithmetic of bash in `pacs-storage.sh`, so `dashboard-status.py` refuses them too. `PACS_SOCKET_UID` takes at most 10 digits. A value that is not a whole number, or has too many digits, stops the program with one line that names the variable. Each program has its own wording:

| Program | Variables it checks | Message |
|---|---|---|
| verwaltung-dienst.py | `PACS_SOCKET_UID` | `verwaltung-dienst.py: PACS_SOCKET_UID=abc ist keine ganze Zahl ohne fuehrende Null mit hoechstens 10 Stellen (/etc/default/pacs-admin)`. A number of up to 10 digits outside 0 to 4294967294 gives `ist keine gueltige uid`. |
| dashboard-status.py | `STORAGE_FREE_GB`, `STORAGE_WARN_GB` | `dashboard-status.py: STORAGE_WARN_GB=300GB ist keine ganze Zahl ohne fuehrende Null mit hoechstens 6 Stellen (/etc/default/pacs-admin)` |
| pacs-storage.sh | `STORAGE_MIN_GB`, `STORAGE_FREE_GB` | `HALT: STORAGE_FREE_GB='50GB' ist keine ganze Zahl ohne fuehrende Null mit hoechstens 6 Stellen (/etc/default/pacs-admin)` |

The reason for the leading-zero rule is bash: it reads `08` as an invalid octal number and `010` as 8. The message reaches the journal for `pacs-verwaltung`, `/var/log/pacs-dashboard.log` for the cron job and the screen for `pacs-storage.sh`.

A bad value in `FW_WEB_PORTS`, `FW_DICOM_PORTS` or `FW_HL7_PORTS` does not stop anything: the program ignores it, writes a line that names the variable to the journal, and uses the default.

**Apply a change.**

- `systemctl restart pacs-verwaltung` makes the helper service read the file again. This covers every variable that the helper service reads, also through `firewall.py` and `pacsdb.py`. Do not restart while the page shows a disk setup that runs: the job ends with the service.
- The cron job and `pacs-storage.sh` read the file at every run. A changed `STORAGE_*` value reaches the overview with the next cron run (every 5 minutes).
- Restart the helper service after a change of `PACS_DIR`, `PACS_ADMIN_VAR`, `STORAGE_*` or `DASHBOARD_CONTAINERS` as well. The button "Jetzt suchen" and every disk action start `dashboard-status.py` from the helper service, and it uses the environment of the service, not the file. Without the restart the overview shows the old values after each click, until the next cron run writes the new ones.
- `pacs-firewall.service` reads the `FW_*` variables and `PACS_DIR` when it starts. To apply a changed value without a gap, run `firewall.py start` with the settings loaded (see [section 2.2](#server-commands)). `systemctl restart pacs-firewall` removes the jump into the firewall chain first, so all ports are open for a moment.

#### Variables

"Read by" names the program that reads the variable. Defaults are checked against the code.

General:

| Variable | Default | Read by | Meaning |
|---|---|---|---|
| `PACS_DIR` | `/opt/dcm4chee-arc` | firewall.py, dashboard-status.py | Directory of the dcm4chee Compose project, the one with its `docker-compose.yml`. `firewall.json` and the folder `firewall/` live here. The tile "Dienste" lists the containers whose Compose label `com.docker.compose.project.working_dir` equals this path. |
| `PACS_ADMIN_VAR` | `/var/lib/pacs-admin` | dashboard-status.py | Working directory. The file `status/status.json` below it is served as `/admin/daten/status.json`. |
| `PACS_SOCKET` | `/run/pacs-admin/verwaltung.sock` | verwaltung-dienst.py | HTTP socket of the helper service. nginx expects it at `/run/pacs-admin/verwaltung.sock` inside its container. At most 107 bytes. |
| `PACS_LOG_SOCKET` | `/run/pacs-admin/protokoll.sock` | verwaltung-dienst.py | Datagram socket for the log lines of nginx. Same directory as `PACS_SOCKET`. At most 107 bytes. |
| `PACS_SOCKET_UID` | `101` | verwaltung-dienst.py | Owner of both sockets: the uid of the nginx worker processes. It is 101 in the `nginx` and OHIF images and 33 (`www-data`) for nginx on Debian. Ideally no other account on the host has this uid, see [section 3.6](#permissions). |
| `PROTOKOLL_DB` | `/var/lib/pacs-protokoll/protokoll.db` | pacsdb.py | The encrypted audit database. |
| `PROTOKOLL_KEY` | `/etc/pacs-protokoll.key` | pacsdb.py | Key file: 64 lowercase hex characters. See [section 6.6](#audit-key-format). |

dcm4chee:

| Variable | Default | Read by | Meaning |
|---|---|---|---|
| `ARC_URL` | `http://127.0.0.1:8080` | pacs-storage.sh | REST address of dcm4chee as the host sees it. The disk assistant calls it, without a token, to reload the archive configuration. The arc container must publish this port on the host. |
| `ARC_AET` | `DCM4CHEE` | pacs-storage.sh | AE title of the archive whose write list the assistant changes. It must match the AE title in the nginx files, in `app-config.js` and in `config.js`, see [section 4.3](#ae-title). |
| `ARC_DEVICE` | `dcm4chee-arc` | pacs-storage.sh | Device name of dcm4chee in LDAP (`dicomDeviceName`). |
| `ARC_LOG_DIR` | `/var/local/dcm4chee-arc/wildfly/log/` | firewall.py | Directory of the WildFly `server.log` on the host. It is the host side of the mount of `/opt/wildfly/standalone` in the arc container, plus `/log`. A wrong value leaves the DICOM and HL7 sender lists empty, and the journal shows an `absender_sammeln` error every few minutes. |
| `ARC_CONTAINER` | `arc` | pacs-storage.sh | Name of the arc container. The assistant runs `docker exec` in it to check that arc sees and can write a new disk. |
| `LDAP_CONTAINER` | `ldap` | pacs-storage.sh | Name of the LDAP container. `ldapsearch` and `ldapmodify` run inside it, with its own root password. |
| `LDAP_BASE_DN` | `dc=dcm4che,dc=org` | pacs-storage.sh | Base DN of the dcm4chee configuration in LDAP. |

Storage (disk assistant and overview):

| Variable | Default | Read by | Meaning |
|---|---|---|---|
| `STORAGE_BASE` | `/mnt/fs` | pacs-storage.sh, dashboard-status.py | Directory with the mount points of the archive disks. A slash at the end is ignored. |
| `STORAGE_PREFIX` | `PACS-Data` | pacs-storage.sh, dashboard-status.py, verwaltung-dienst.py | Name of the disks: prefix plus number, for example `PACS-Data01`. The same name is the file system label, the mount directory and the storage ID. The prefix is one letter, then letters, digits, `-` and `_`, at most 14 characters (an ext4 label holds 16 characters with the number). Otherwise `pacs-storage.sh` stops. The helper service accepts only this prefix plus digits. Disks with other names do not appear in the overview. The overview shows disk names without the prefix (`prefix` in `status.json`). |
| `STORAGE_OWNER` | `1023:1023` | pacs-storage.sh | Owner of a new file system as uid:gid. It is the account of WildFly in the dcm4chee image. |
| `STORAGE_MIN_GB` | `100` | pacs-storage.sh | Smallest disk that the assistant offers, in GiB (1024 x 1024 x 1024 bytes). |
| `STORAGE_FREE_GB` | `50` | pacs-storage.sh, dashboard-status.py | Free space needed, in GB (10^9 bytes), to clear the full mark or to add a disk to the write list. The page gets the value as `frei_gb` in `status.json` and shows the two buttons only from this value on. |
| `STORAGE_WARN_GB` | `300` | dashboard-status.py | If the disks of the write list have less than this many GB left up to the threshold, the overview asks for a new disk. The page gets the value as `warn_gb`. |
| `STORAGE_LOG` | `/var/log/pacs-storage.log` | pacs-storage.sh | Log of the disk assistant. |

Firewall:

| Variable | Default | Read by | Meaning |
|---|---|---|---|
| `FW_INTERFACE` | empty | firewall.py | Network interface that the clients come in on. Empty means: the interface of the default route (at boot, `firewall.py start` waits up to 60 seconds for it). The name has 2 to 15 characters: lowercase letters, digits, `_`, `.` and `-`, starting with a letter. The first save in the Firewall tab stores the interface in `firewall.json` (`schnittstelle`), which then takes precedence over this variable. To change the interface later, edit or delete `schnittstelle` in `firewall.json`. |
| `FW_WEB_PORTS` | `443,80` | firewall.py | Host ports of the web server, separated by commas. The first is the https port: a save in the Firewall tab is refused when the saving PC would lose access to it. All are open in the built-in rule set, and the page asks before it blocks one. |
| `FW_DICOM_PORTS` | `11112,2762` | firewall.py | Host ports for DICOM. The first gets the suggestions under "Neu erkannt", the client PC check, and Probelauf in the built-in rule set. The sender list reads the dcm4chee log for these ports, translated to the container port through `docker ps` (for example `104:11112`). |
| `FW_HL7_PORTS` | `2575,12575` | firewall.py | The same for HL7. The three port lists must not share a port. Otherwise all three lists fall back to their defaults. |
| `FW_DEFAULT_RULES` | empty | firewall.py | JSON file in the format of `firewall.json` ([section 1.4](#firewall-json)). It applies while no `firewall.json` exists. Empty means: the built-in rule set. A missing or invalid file stops `firewall.py start`, and the Firewall tab shows the error. |
| `FW_PORT_NAMES` | empty | firewall.py | Your own port names as a JSON object, for example `'{"104": "DICOM (old)"}'`. They replace the built-in names. A name has at most 60 characters. Text that is not a JSON object is ignored, and the journal says so. |
| `FW_CLIENT_NAMES` | empty | firewall.py | Name patterns of client PCs for DNS lookups, separated by commas. `{a..b}` counts from a to b as in bash. If a bound has a leading zero, all numbers are padded with zeros to the width of the bounds. Example: `'pc{01..20},ws{001..040}'` gives pc01 to pc20 and ws001 to ws040. At most 100000 names per pattern. The lookups run at most once per hour, and the button "Jetzt suchen" in the Firewall tab starts one at once. Empty means: no lookups, and the card is hidden. |

Overview:

| Variable | Default | Read by | Meaning |
|---|---|---|---|
| `DASHBOARD_CONTAINERS` | empty | dashboard-status.py | Containers for the tile "Dienste", separated by commas or spaces. Empty means: all containers of the Compose project in `PACS_DIR`. Stopped containers show red. |

**Only for tests.** `FSTAB` (default `/etc/fstab`) and `PACS_STORAGE_TEST` (when set, loop devices are allowed) exist for the tests of `pacs-storage.sh`. Do not set them on a server.

**Variables of the LDAP container.** The disk assistant logs in to LDAP with the root account of the LDAP container. The password stays in that container: `LDAP_ROOTPASS`, or `LDAP_ROOTPASS_FILE` (a path inside the container). `LDAP_ROOTDN` names the root account. Without it the account is `cn=admin,` plus the base DN of the container. These variables belong to the LDAP container, not to `/etc/default/pacs-admin`. Check that the password exists, without printing it (the container is named `ldap`):

```
docker exec ldap sh -c 'test -n "$LDAP_ROOTPASS$LDAP_ROOTPASS_FILE" && echo ok'
```

<a id="config-js"></a>
### 1.2 Page settings: web/admin/config.js

The file `web/admin/config.js` is served as `/admin/config.js`. Edit values only. To keep `git pull` free of conflicts, copy the file to `/opt/ohif/config.js` and mount the copy over `/srv/pacs-admin/admin/config.js` in the compose file. The page reads the file at every load, so reload the page after a change.

| Key | Default | Meaning |
|---|---|---|
| `titel` | `'PACS-Verwaltung'` | Page title and text at the top. |
| `aet` | `'DCM4CHEE'` | AE title of the archive for search and changes (`/dcm4chee-arc/aets/AET/rs`). |
| `iocmAet` | `'IOCM_QUALITY'` | AE title of the view of rejected studies (restore, delete for good). The Protokoll tab also uses it to recognize searches in that view. |
| `dcm4cheeUrl` | `'/dcm4chee-arc/ui2/'` | Target of the link "dcm4chee" at the top. Empty hides the link. |
| `viewerUrl` | `'/'` | Target of the link "Viewer" at the top. Empty hides the link. Set it to empty when the viewer mode is `none`: `/` then redirects back to `/admin/`. |
| `logo` | `''` | Logo for a dark background. It must come from the same address as the page: `/admin/` sends `Cross-Origin-Embedder-Policy: require-corp`, so an image from another server does not load. A file in `web/admin/` is served below `/admin/`, for example `'/admin/logo.svg'`. With viewer `ohif` you can also mount the file at `/usr/share/nginx/html/pacs-logo.svg` and write `'/pacs-logo.svg'` ([section 3.5](#mounts)). Empty shows the title only. |
| `locale` | `'de-DE'` | Language tag for numbers and timestamps, for example `de-AT` or `de-CH`. DICOM dates (study date, birth date) always show as DD.MM.YYYY. An invalid tag falls back to `de-DE`. The texts stay German. |
| `kontoUrl` | `'/oauth2/userinfo'` | Address that returns JSON with the account name in `preferredUsername` (the page also accepts `email` and `user`). The page shows the name at the top. With login oauth2-proxy, oauth2-proxy answers this address. With login basic and none, nginx answers it in the same form, so the default works. Empty shows no name and makes no request. Any other answer (404, an HTML page, a redirect to another server) leaves the name empty without a message, and the page works. |
| `abmeldenUrl` | `''` | Target of the link "Abmelden" (sign out) next to the account name. Empty hides the link. With oauth2-proxy use `'/oauth2/sign_out'`, see [Login](login.md#login-oauth2). Login basic has no sign-out: the browser keeps the password until you close it. |

When the session ends, the page shows "Sitzung abgelaufen, Seite neu laden (F5)" instead of a network error. The page does this when a call gets a redirect (the login page of another server) or the status 401.

<a id="app-config-js"></a>
### 1.3 OHIF viewer: app-config.js

Needed only with viewer mode `ohif`. Copy `deploy/app-config.js.example` to `/opt/ohif/app-config.js`. The compose file mounts it over `/usr/share/nginx/html/app-config.js` of the OHIF image, and nginx serves it as `/app-config.js`. Without the file the viewer runs with the default of the image, which does not know your archive. The file has no host name: it builds every address from `window.location`, so the same file works for https, plain http and an SSH tunnel. See [install guide](install.md#viewer-config).

Check in the browser: open `https://pacs.example.org/app-config.js` (reload without cache). It must show the text of your file. In the browser console of the viewer page, `window.config.dataSources[0].configuration.qidoRoot` must print your address with `/dcm4chee-arc/aets/DCM4CHEE/rs`.

You may change:

- The AE title `DCM4CHEE` in the line `const arc = ...`. It must equal `aet` in `config.js` and `ARC_AET`. Use `set-aet.sh` ([section 4.3](#ae-title)) instead of editing by hand.
- `name` and `friendlyName`: the label of the data source, free text.
- `maxNumberOfWebWorkers` (CPU cores for image decoding) and `maxNumRequests` (parallel image requests).

You must not change:

- The addresses that are built from `window.location`.
- `supportsReject: false` and `dicomUploadEnabled: false`. The admin page rejects and deletes studies, and nginx blocks writing requests from the viewer.
- The `bulkDataURI` block. dcm4chee writes absolute bulk data links with `http://` and the host name without a port. On an https page the browser blocks such links, so the block rewrites them to the address of the page.

<a id="firewall-json"></a>
### 1.4 Firewall rules: firewall.json

The Firewall tab writes `PACS_DIR/firewall.json` (mode 0640). `FW_DEFAULT_RULES` uses the same format. The service keeps every earlier version in `PACS_DIR/firewall/`.

| Key | Meaning |
|---|---|
| `aktiv` | `true` or `false`: the rules apply or not. Default `true`. |
| `schnittstelle` | The interface that the clients come in on. Empty or missing: `FW_INTERFACE`, else the default route. |
| `standard` | Mode for ports without a rule: `offen`, `probelauf` or `gesperrt`. Default `offen`. |
| `regeln` | List of rules. One rule per port. |
| `ausgeblendet` | Sources hidden under "Neu erkannt", each as `PORT SOURCE`, for example `11112 192.0.2.50`. |
| `geaendert` | Who saved the rules last (`wer`) and when (`zeit`). The service writes it. |

A rule has these keys:

| Key | Meaning |
|---|---|
| `port` | Host port, 1 to 65535, once per file. Port 22 is refused. |
| `name` | Label, at most 60 characters. |
| `modus` | `offen` (everyone gets through), `probelauf` (everyone gets through, sources not on the list are logged) or `gesperrt` (only the list gets through). A rule without `modus` means `gesperrt`. |
| `protokollieren` | `true`: log connections that the list allows (at most 10 lines per minute per rule). |
| `erlaubt` | List of `{"quelle": "192.0.2.0/24", "notiz": "text"}`. A source is an IPv4 address or an IPv4 network. A note has at most 80 characters. |

Example:

```json
{"aktiv": true, "standard": "probelauf", "regeln": [
  {"port": 443, "name": "Viewer und Verwaltung", "modus": "offen"},
  {"port": 8080, "name": "dcm4chee REST (http)", "modus": "gesperrt"}
]}
```

<a id="tools-and-packages"></a>
## 2. Tools and packages

<a id="packages"></a>
### 2.1 Packages

Package names are for Debian 12 and 13. Ubuntu uses the same names and is not tested. `preflight.sh` checks all of this and prints the install command for what is missing.

| Tool | Debian package | Used by |
|---|---|---|
| Python 3.7 or newer at `/usr/bin/python3` | `python3` | all programs in `server/` and both units. The units start exactly `/usr/bin/python3`: a Python in `/usr/local/bin` does not count. |
| SQLCipher library | `libsqlcipher1` on Debian 13 (SQLCipher 4.x), `libsqlcipher0` on Debian 12 and older (SQLCipher 3.x) | pacsdb.py. Find the name for your release with `apt-cache search sqlcipher`. |
| `git` | `git` | clone and update |
| `curl` | `curl` | pacs-storage.sh (calls arc), the checks in the guides |
| `openssl` | `openssl` | audit key, certificate checks, pacs-adduser.sh (version 1.1.1 or newer for the sha512 hash), preflight.sh |
| `cron` | `cron` | `/etc/cron.d/pacs-dashboard` (overview numbers) |
| `ip`, `ss` | `iproute2` | firewall.py (default route), preflight.sh |
| `iptables`, `iptables-restore` | `iptables` | firewall.py (variant nft or legacy) |
| `journalctl`, `systemctl` | `systemd` | firewall.py (kernel log), pacs-storage.sh |
| `hostname` | `hostname` | firewall.py (`hostname -I`: the addresses of the server) |
| Docker engine and compose plugin | Debian 13: `docker.io` and `docker-compose` (version 2, a plugin). Debian 12: `docker.io` and the package `docker-compose-plugin` from the Docker repository. | firewall.py, dashboard-status.py, pacs-storage.sh, the compose examples |
| `lsblk`, `blockdev`, `blkid`, `wipefs`, `findmnt`, `flock`, `unshare` | `util-linux` | pacs-storage.sh |
| `mount`, `losetup`, `swapon` | `mount` | pacs-storage.sh |
| `mkfs.ext4`, `tune2fs`, `resize2fs` | `e2fsprogs` | pacs-storage.sh |
| `udevadm` | `udev` | pacs-storage.sh |
| `cmp` | `diffutils` | pacs-storage.sh |
| `bash` 3.2 or newer, `awk`, `sed`, `grep`, `df`, `sort`, `tr`, `date`, `id`, `stat` | `bash`, `mawk`, `sed`, `grep`, `coreutils` | pacs-storage.sh and the scripts in `deploy/tools/`. Always installed. |
| `logger` | `bsdutils` | optional: sends audit lines from another program, see [section 5.7](#audit-feed) |
| `sqlcipher` | `sqlcipher` | optional: opens the audit database by hand |
| `nginx` | `nginx` | only for nginx on the host. Version 1.25.1 or newer is needed for `http2 on`. Debian 13 has 1.26. Debian 12 has 1.22 and needs one edit, see [deploy/nginx/README.md](../deploy/nginx/README.md#listener). |

`ldapsearch` and `ldapmodify` run inside the LDAP container. The host needs nothing for them.

Debian 12 note: the Debian package `docker-compose` there is the old version 1 (`docker-compose` with a hyphen). The guides use the plugin form `docker compose`.

Images: the container `ohif` runs nginx 1.25.1 or newer. The `nginx` image (tested with 1.30) and the OHIF image both qualify. The compose examples name the tags of the OHIF image and of oauth2-proxy.

<a id="server-commands"></a>
### 2.2 Commands of the server programs

Run the Python programs as root, with the settings loaded (see [section 1.1](#config-variables)).

| Command | What it does |
|---|---|
| `python3 /opt/pacs-admin/server/pacsdb.py test` | Self-test of the audit database library. It uses a temporary key and database and does not touch the key file. It prints one line that starts with `Selbsttest ok`. |
| `python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse 2026-10-01` | Prints rows of the audit log as JSON lines, see [section 6.7](#audit-read). |
| `python3 /opt/pacs-admin/server/firewall.py start` | Applies the rules. Waits up to 60 seconds for the default route. A broken rules file stops it at once. |
| `python3 /opt/pacs-admin/server/firewall.py stop` | Removes the jump from `DOCKER-USER`. All ports are open. |
| `python3 /opt/pacs-admin/server/firewall.py status` | Rules, counters, interface, and whether the rules are in effect (with the reason if not). Without an argument, `firewall.py` runs `status`. |
| `python3 /opt/pacs-admin/server/firewall.py absender` | Reads the new lines of `server.log` (DICOM and HL7 senders). |
| `python3 /opt/pacs-admin/server/firewall.py nachholen` | Reads the rotated logs once, then the current file from the start. |
| `python3 /opt/pacs-admin/server/firewall.py clients` | Looks up the client PC names (`FW_CLIENT_NAMES`) now. |
| `python3 /opt/pacs-admin/server/firewall.py test` | Self-test. It needs neither iptables nor docker. It prints `Selbsttest ok`. |
| `python3 /opt/pacs-admin/server/dashboard-status.py` | Writes `status.json` now. It also runs `pacs-storage.sh kandidaten`, which rescans the SCSI hosts. If that script fails, `status.json` is still written and the exit code is 1, see the exit codes below. |
| `bash /opt/pacs-admin/server/pacs-storage.sh scan` | Rescans the disks. Lists storages, blank disks, grown disks and mount points without `NO_MOUNT`. |
| `bash /opt/pacs-admin/server/pacs-storage.sh add /dev/sdb` | Plan for a new disk. With `ja` as the last argument it formats, mounts and registers the disk. |
| `python3 /opt/pacs-admin/server/verwaltung-dienst.py` | The helper service. systemd starts it. Do not start it by hand while the unit runs: the second instance refuses to start (`laeuft schon`). |

`pacs-storage.sh` commands: `scan`, `auto`, `add DEVICE`, `activate ID`, `grow DEVICE`, `nomount`, `kandidaten`, `freigeben ID`, `anhaengen ID`, `abhaengen ID`. Every command that changes something only prints its plan, unless the last argument is `ja`. All commands except `kandidaten` and `nomount` first check that LDAP is readable and stop with a line `HALT: ...` and exit code 1 if it is not. `scan` and `kandidaten` rescan the SCSI hosts, which writes to `/sys`. Details: [Modules](modules.md#disk-assistant).

**Exit codes of the Python programs.**

- `firewall.py` with an unknown command prints the list of commands and exits with 1. A failure (a program is missing, the rules file is broken, `iptables` refuses) prints one line `firewall.py COMMAND: reason` and exits with 1. Success exits with 0.
- `pacsdb.py` with an unknown command prints its usage line and exits with 1. A problem with the library, the key or the database prints one line `pacsdb.py: reason` and exits with 1.
- `verwaltung-dienst.py` and `dashboard-status.py` print one line that starts with the program name and exit with 1 when a setting is wrong (see the table in [section 1.1](#env-file-rules)) or, for the helper service, when it cannot start (`laeuft schon`, a missing right, a socket that cannot be created).
- `dashboard-status.py` also exits with 1 when `pacs-storage.sh kandidaten` stops with an error or does not answer within 200 seconds. It writes `status.json` first, with `schreibliste_bekannt` set to `false`, and the last line on stderr gives the reason, for example the `HALT:` text of the script. The cron job puts that line into `/var/log/pacs-dashboard.log`: a broken script adds one line every 5 minutes until it is fixed.

<a id="storage-exit-codes"></a>
**Exit codes of `pacs-storage.sh`.**

- `0`: done. Without `ja` as the last argument it means that the plan was printed and nothing changed.
- `1`: stopped, nothing changed. The last line that starts with `HALT:` gives the reason. An unknown command prints the usage text and exits with 1 too.
- `3`: the change is made in LDAP, but the archive did not reload its configuration. The script asks three times, 5 seconds apart, and counts the HTTP answers 204 and 200 as success. The line `ACHTUNG: Archiv-Konfiguration nicht neu geladen (Antwort 000). ...` says so. This applies to `activate` (so also to `add DEVICE ja`), `grow`, `freigeben`, `anhaengen` and `abhaengen`. The archive keeps working with its old configuration until someone clicks **Neu laden** under **Konfiguration** in the archive UI. Do not repeat the command to repair this: the second run finds the change in LDAP, says so (`ist nicht als voll markiert`, `steht schon in der Schreibliste` or `steht in keiner Schreibliste`), exits with 0 and does not try the reload again.

The helper service turns the codes into answers, see [section 5.1](#contract-paths).

<a id="command-preflight"></a>
### 2.3 preflight.sh

Read-only check of a host before the install. It changes nothing, installs nothing and restarts nothing.

```
sudo -i
bash /opt/pacs-admin/deploy/tools/preflight.sh --host pacs.example.org --cert /opt/ohif/tls/server.crt --key /opt/ohif/tls/server.key --dir /opt/ohif
```

| Option | Meaning |
|---|---|
| `--host pacs.example.org` | Also check that the DNS name resolves, and to an address of this host. With `--cert`, also check that the certificate covers the name. |
| `--cert FILE` and `--key FILE` | Also check a TLS certificate and its key. Each option works alone. |
| `--dir /opt/ohif` | Also check the folder of your compose file (up to 5 levels deep, hidden folders skipped). See the list below. |
| `--lang de` or `--lang en` | Language of the output. Without it the first of `LC_ALL`, `LC_MESSAGES` and `LANG` that is not empty decides: a value that starts with `de` gives German, else English. |
| `-h` or `--help` | Print the usage and exit with 0. |

An option also works as `--host=pacs.example.org`. Run the script with `bash`: `sh` refuses it. A trailing `/` in the `--dir` value is ignored. Every Docker call has a time limit of 15 seconds, so a stuck daemon cannot hang the script.

Every check prints one line: `[ OK ]`, `[WARN]` or `[FAIL]`. A warning or failure adds one sentence about the meaning and the exact fix command. The output never contains a line of a configuration file and never a secret value.

```
[FAIL] SQLCipher: package libsqlcipher1 (4.6.1-2) fits this system, not installed yet
       The encrypted audit log needs this library; the helper service does not start without it. docs/install.md#audit-key
       Fix: apt-get install -y libsqlcipher1
```

| Exit code | Meaning |
|---|---|
| 0 | All checks passed. |
| 1 | Warnings only. |
| 2 | At least one failure, or a wrong option. |

What it checks:

- System and packages: root, the place of the repository (a warning if it is not `/opt/pacs-admin`), systemd, the operating system (Debian 12 and 13 pass, Ubuntu and anything else gives the warning "not tested"), the SQLCipher package that fits the release, `python3` at `/usr/bin/python3` in version 3.7 or newer, git, curl, openssl, ip, cron (installed and running), iptables, journalctl, and the tools of the disk assistant.
- Docker and dcm4chee: the Docker daemon and the compose plugin, then the containers of arc, LDAP and the database, found by image name (`dcm4chee-arc-*`, `slapd-dcm4chee*`, `postgres-dcm4chee*`). A `-secure` arc image is a failure: it is not supported. Also the Compose directory and the Docker network of arc, the WildFly log directory on the host, and whether the LDAP container has a root password (the value is never read or printed).
- Host settings: mounts under `STORAGE_BASE` and their mount propagation, whether uid 101 is free, ports 80 and 443, the interface of the default route, `/etc/localtime`, and with `--host` the DNS name.
- TLS certificate, with `--cert` or `--key`: PEM format, expiry (a warning below 30 days), `subjectAltName`, the host name, the order of the chain, a key without passphrase, key matches certificate, and the mode of the key file for the image that you use ([section 3.6](#permissions)). With `--dir` and without `--key`, the key in `tls/` gets the mode check too.
- Configuration files: the syntax of `/etc/default/pacs-admin`, whenever the file exists (CRLF, `sh -n`, an unquoted value with a space, a line that is not `NAME=value`, `CHANGE-ME` left in a value). With `--dir` the script also checks the folder of the compose file:
  - `CHANGE-ME` and `<placeholders>` left in the `*.conf`, `*.inc`, `*.yml`, `*.yaml`, `*.env` and `*.js` files (a failure), and example values such as `example.org` (a warning). The marker `CHANGE-ME` counts in a comment too: delete the marker comment once the value is set.
  - Every file that the nginx files include from `/etc/nginx/conf.d/` exists, so nginx can start (a failure). A folder with a compose file but without `nginx/pacs.conf` gives a warning.
  - Every bind mount of the compose file. A source that does not exist is a warning: Docker would make an empty folder owned by root. A source that is incomplete is a failure: `server.crt` and `server.key` missing in `tls/`, `users` or `admins` missing in `htpasswd/`, `pacs.conf` missing in `nginx/`, or `app-config.js` or `config.js` that is not a file.
  - Access of the nginx user (uid 101) to what is mounted: the admin page, the status folder, `app-config.js` and `config.js` (a failure if uid 101 cannot read them). With the OHIF image also `nginx/` and `tls/`. The lists in `htpasswd/`: the worker must be able to read them (a failure if not), and not every account (a warning if it can).
  - Every `env_file` of the compose file exists (a failure if not). In a compose file with oauth2-proxy it also holds the three values client ID, client secret and cookie secret, none empty (a failure if not).
  - A `*.env` file that other accounts can access (a warning).

  The script prints file names and line numbers. For a placeholder it prints the word (`CHANGE-ME` or `<name>`), for a `*.env` file only the variable name. It never prints a whole line or a value.

At the end it prints the summary, one `apt-get` loop for all missing packages (a package that does not exist is reported and the rest still installs), and a table "My values":

| Row | Goes into |
|---|---|
| compose project directory | `PACS_DIR` |
| compose file(s) | information |
| Docker network of arc | the external network in the compose file |
| arc container | `ARC_CONTAINER`, and the nginx upstream |
| ldap container | `LDAP_CONTAINER` |
| db container | information |
| wildfly log directory (host) | `ARC_LOG_DIR` |
| outside network interface | `FW_INTERFACE` |
| uid of nginx / sockets | `PACS_SOCKET_UID` |
| SQLCipher package | `apt-get install -y` |

"(not found)" in the value column means: look it up by hand. Below the table the script lists the lines for `/etc/default/pacs-admin` whose value differs from the current setting: `PACS_DIR`, `ARC_CONTAINER`, `LDAP_CONTAINER`, `ARC_LOG_DIR`, and `FW_INTERFACE` for as long as it is empty (a fixed name is safer than the lookup of the default route at boot). The last lines name the options that you did not give (`Not checked (option not given)`). Run the script again after every fix.

<a id="command-adduser"></a>
### 2.4 pacs-adduser.sh

Adds or changes a login for the variant `basic` (nginx HTTP basic authentication). It needs only bash and openssl.

```
sudo bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh admin anna
sudo bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh all vera
```

| Argument | Meaning |
|---|---|
| `admin` or `all` | `all`: the account may use the viewer. Its line goes into the list of all accounts. `admin`: the account may also use `/admin/`. Its line goes into both lists. |
| `anna` | Account name: letters, digits, `.`, `_` and `-`, at most 32 characters. Any other character is refused, so `anna@example.org` does not work. |

| Option | Meaning |
|---|---|
| `--dir /opt/ohif` | Folder of your compose file (default `/opt/ohif`). The lists are `htpasswd/users` and `htpasswd/admins` below it. The folder itself must exist, otherwise the script stops. The script creates the folder `htpasswd` (mode 755) below it when that is missing. If `htpasswd` is a plain file, the script stops and prints the `mv` command that fixes it. `--file` is an older name of this option. |
| `--users FILE` and `--admins FILE` | Name both list files yourself. Give both. Overrides `--dir`. |
| `--owner 101` | Owner of the files as `UID` or `UID:GID`, set when you run as root. Default 101, the nginx worker in the `nginx` and OHIF images. For nginx on the host use `--owner root:www-data`. |
| `--mode 600` | Mode of the files, three octal digits. Default 600. For nginx on the host use `--mode 640`. The script refuses a mode where the group or others may write. |

The password is never taken from the command line. The script asks twice with a hidden prompt, or reads one line from stdin when stdin is not a terminal: `printf '%s\n' 'CHANGE-ME-PASSWORD' | sudo bash pacs-adduser.sh admin anna`. A password needs at least 10 characters and at most 256 bytes. openssl hashes only the first 256 bytes, so a longer password could never match, and the script refuses it.

An existing account is replaced and moved between the lists as the role says: the role `all` removes its line from `admins`. To remove an account, delete its line from both files. The files are written in place, so a bind mount of a single file stays valid. Two runs at the same moment take turns when `flock` is installed (the second waits up to 30 seconds). nginx reads the files at every request: no restart is needed.

The password hash is sha512-crypt (`$6$`) with the default of 5000 rounds. nginx checks the hash at every request, so the script keeps the cost low and has no option for more rounds. The script needs openssl 1.1.1 or newer for this type. With an older openssl it prints a warning, uses apr1 (the weaker type) and still writes the line. Update openssl and set the password again.

Run the script as root. Before it writes anything it checks that a new file can get the owner and the mode. Without root it warns that the owner was not set. Files that the nginx worker cannot read give 500 to every request that carries a password. A missing file gives 403.

| Exit code | Meaning |
|---|---|
| 0 | The lists were written, or `-h` printed the usage. |
| 1 | Wrong arguments, wrong password input, a missing `openssl`, files that cannot be written or any other error. |

<a id="command-set-aet"></a>
### 2.5 set-aet.sh

Changes the AE titles in the files that hold them, see [section 4.3](#ae-title). It changes the viewer side only: the AE title itself is defined in dcm4chee.

```
sudo bash /opt/pacs-admin/deploy/tools/set-aet.sh MYARC MYARC_REJ --dir /opt/ohif
```

| Argument or option | Meaning |
|---|---|
| `MYARC` | New AE title of the archive. It replaces `DCM4CHEE`. |
| `MYARC_REJ` | New AE title of the view of rejected studies. It replaces `IOCM_QUALITY`. Leave it out to keep `IOCM_QUALITY`. |
| `--dir /opt/ohif` | Folder with your files (default `/opt/ohif`). The script looks at all text files below it, up to 5 levels deep, and picks them by content, not by name. It skips hidden folders (the backups of earlier runs), files of 1 MiB or more, and names that end in `.bak`, `.orig`, `.old`, `.save`, `.swp` or `~`. It refuses `/`. |
| `--dry-run` | Only show what would change. |
| `--yes` or `-y` | Do not ask for confirmation. |
| `--from OLD-ARCHIVE-AET` and `--from-rejection OLD-REJECTION-AET` | The titles that the files hold now, when they are not `DCM4CHEE` and `IOCM_QUALITY` any more. Needed for a second rename. |

A title has 1 to 16 characters: letters, digits, `_` and `-`. The two titles must differ.

The script replaces whole words only, case-sensitive. `99DCM4CHEE` (the coding scheme of "revoke rejection"), `DCM4CHEE2` and `MY_DCM4CHEE` stay as they are, and so does the lower-case `/dcm4chee-arc/` in paths. A file changes only if it contains the title and looks like an nginx, OHIF or admin-page file: it has `aets/`, `window.config`, `window.PACS_ADMIN`, a variable `$pacs_...`, or a line that starts with `location`, `map`, `upstream` or `server`. Other files that contain the word are listed as "NOT changed" for you to check by hand. A symbolic link is never rewritten. The script lists it, with the advice to change the file it points to.

The script shows every changed line and asks `Apply these changes? [y/N]`. If it cannot write one of the files, it stops before it changes anything: run it with `sudo`. Then it copies the originals to `DIR/.set-aet-backup-TIME/` and rewrites the files in place (same inode, mode and owner).

At the end it lists what is left to do by hand: dcm4chee needs an AE with the new title, `config.js` (when the script did not find it under the directory), `ARC_AET` in `/etc/default/pacs-admin` followed by `systemctl restart pacs-verwaltung`, a reload of nginx (`docker compose restart` in the folder of the compose file), and a browser reload without cache.

| Exit code | Meaning |
|---|---|
| 0 | Done, or `--dry-run`, or the new titles equal the old ones. |
| 1 | An error, nothing found (wrong `--dir`, or the titles were changed before: use `--from`), a file that cannot be written, or you answered no. |

<a id="files-ports-sockets"></a>
## 3. Files, services, ports, sockets and mounts

### 3.1 Files on the server

The directory layout is the one that the guide, the compose examples and the tools use.

| Path | What it is |
|---|---|
| `/opt/pacs-admin/` | The cloned repository. The units and the cron file expect this path. |
| `/etc/default/pacs-admin` | Settings, see [section 1.1](#config-variables). No secrets. |
| `/etc/pacs-protokoll.key` | Key of the audit database: 64 lowercase hex characters. Owner root, mode 0600. |
| `/var/lib/pacs-protokoll/protokoll.db` | The encrypted audit database (and `-wal`, `-shm`). Directory 0700, files 0600. The service creates it when it first opens it. |
| `/var/lib/pacs-admin/status/status.json` | Numbers for the overview, see below. Mode 0644. |
| `/var/lib/pacs-admin/status/rechner.json` | Optional, made by hand: a JSON object that maps IP addresses to PC names, for example `{"192.0.2.50": "WS0050"}`. The Protokoll tab shows the name next to the IP. Nothing in this repository writes it. |
| `/run/pacs-admin/` | The two sockets, see [section 3.4](#sockets). The service creates the directory (mode 0755). |
| `/etc/systemd/system/pacs-verwaltung.service`, `pacs-firewall.service` | The two units. |
| `/etc/cron.d/pacs-dashboard` | The cron job. |
| `/var/log/pacs-storage.log` | Log of the disk assistant (`STORAGE_LOG`). |
| `/var/log/pacs-dashboard.log` | Errors of the cron job. |
| `/opt/dcm4chee-arc/` | Default `PACS_DIR`: your dcm4chee Compose project. |
| `PACS_DIR/firewall.json` | The firewall rules (mode 0640). |
| `PACS_DIR/firewall/` | Earlier versions (`firewall-YYYYMMDD-HHMMSS.json`), and `absender.json`, `clients.json`, `angewendet.json`. |
| `/mnt/fs/PACS-Data01`, ... | Mount points of the archive disks (`STORAGE_BASE`, `STORAGE_PREFIX`). A read-only file `NO_MOUNT` lies underneath each one. |
| `/etc/fstab`, `/etc/fstab.bak-TIME` | The assistant adds one line per disk and keeps a copy of the file before the change. |
| `/run/pacs-storage.lock` | Lock of the disk assistant. |

The compose directory (default `/opt/ohif`):

| Path | What it is |
|---|---|
| `docker-compose.yml` | A copy of one of the compose examples in `deploy/compose/`. |
| `nginx/` | The nginx tree: `pacs.conf` and the folder `pacs/`. Mounted as one folder at `/etc/nginx/conf.d`, read only. |
| `tls/server.crt`, `tls/server.key` | Full chain (server certificate first) and key. Listener `tls` only. |
| `htpasswd/users`, `htpasswd/admins` | Login `basic` only. Written by `pacs-adduser.sh`. |
| `ohif-auth.env` | Login `oauth2-proxy` only: client ID, client secret, cookie secret. `chmod 600`. |
| `app-config.js` | Viewer `ohif` only: a copy of `deploy/app-config.js.example`. |
| `config.js` | Optional copy of `web/admin/config.js`. |
| `logo.svg` | Optional logo, viewer `ohif` only. |
| `.set-aet-backup-TIME/` | Originals saved by `set-aet.sh`. |

**status.json.** `dashboard-status.py` writes the file. It replaces the file in one step, so the page never reads a half-written file. The page shows what is present and hides what is missing.

| Key | Meaning |
|---|---|
| `stand` | Time of the run, ISO 8601 with offset. |
| `prefix`, `frei_gb`, `warn_gb` | The settings `STORAGE_PREFIX`, `STORAGE_FREE_GB` and `STORAGE_WARN_GB` for the page. |
| `platten` | One entry per directory `STORAGE_BASE/STORAGE_PREFIX` plus digits. A mounted disk has `name`, `groesse` and `frei` (bytes), `voll` (full mark), `in_liste` (in the write list), `neue_bilder` and `reihe`. `neue_bilder` is `jetzt` for the disk that gets the new images, `danach` for the disks behind it in the write list, else empty. `reihe` is the position among the disks of the write list that are not marked full: 1 gets the new images now, 0 means not in the write list or marked full. A disk that is not mounted has only `name` and `fehlt: true`. |
| `schreibliste_bekannt` | `false` when LDAP could not be read, or when `pacs-storage.sh kandidaten` failed ([exit codes](#server-commands)). The page then says „Schreibliste nicht lesbar“ and what to check, instead of claiming that no disk takes new images. |
| `neue_platten` | `kandidaten` (blank disks, each with `geraet`, `groesse` in bytes and `modell`), `name` (the name of the next disk), `vorlage` (the storage whose settings the new one copies) and `schwelle` (its threshold). |
| `dienste` | An object that maps a container name to `true` (runs) or `false`. Empty when Docker is not installed. |

### 3.2 Services and containers

| Name | What it does |
|---|---|
| `pacs-verwaltung.service` | The helper service. Description: "PACS admin: helper service for /admin/ (unix sockets, see verwaltung-dienst.py)". It runs `/usr/bin/python3 /opt/pacs-admin/server/verwaltung-dienst.py` as root, with `Restart=always` and `RestartSec=5`, after `docker.service`. It binds both sockets first, then starts three jobs: it stores log lines every 2 seconds, every 5 minutes it reads new DICOM and HL7 senders and new Docker ports, and every hour it looks up client names. On start it prints `pacs-verwaltung bereit: ...` to the journal. It has no `RuntimeDirectory=` on purpose: systemd would delete `/run/pacs-admin` at every stop, and the container mount would point to nothing. |
| `pacs-firewall.service` | The firewall. Description: "PACS firewall: filter the Docker-published ports from outside (firewall.py, tab Firewall in /admin/)". A one-shot unit with `RemainAfterExit`, `Requires=docker.service` and `PartOf=docker.service`. It is wanted by `multi-user.target` and by `docker.service`, so the rules return after every start of Docker. `ExecStart` runs `firewall.py start`, `ExecStop` runs `firewall.py stop`. **Emergency brake:** `systemctl stop pacs-firewall` removes the jump into the chain `PACS-SPERRE`, and all ports are open again. |
| `/etc/cron.d/pacs-dashboard` | Runs as root every 5 minutes: loads `/etc/default/pacs-admin`, runs `dashboard-status.py`, and writes errors to `/var/log/pacs-dashboard.log`. |
| container `ohif` | nginx (the `nginx` image or the OHIF image). |
| container `ohif-auth` | oauth2-proxy. Only with login `oauth2-proxy`. |

The units and the cron file expect the repository at `/opt/pacs-admin`. The units start exactly `/usr/bin/python3`. The cron file starts `python3` from its `PATH`. To move the repository, for example to `/srv/pacs-admin`, run this once after copying the files, and mount the same directory in the compose file:

```
sed -i 's|/opt/pacs-admin|/srv/pacs-admin|g' /etc/systemd/system/pacs-*.service /etc/cron.d/pacs-dashboard && systemctl daemon-reload
```

### 3.3 Ports

| Port | Who listens | Notes |
|---|---|---|
| 80 and 443 on the host | The container `ohif`: nginx on 8080 and 8443 in the container | Listener `tls`. Published as `0.0.0.0:80:8080` and `0.0.0.0:443:8443`. Port 80 only redirects to https. |
| `127.0.0.1:8080` on the host | The container `ohif`: nginx on 8080 | Listener `plain`. For an SSH tunnel. Never publish it on a network. |
| none | The container `ohif`: nginx on 8080 | Listener `behind-proxy`. The container joins the Docker network of the proxy. Only the proxy may reach it. |
| 4180 | oauth2-proxy | Reachable only inside the Docker network. Not published. |
| 8080, 8443 | dcm4chee-arc, REST | No login of its own. Publish on `127.0.0.1` only. nginx reaches arc through the Docker network. The disk assistant calls `ARC_URL` on the host. |
| 9990, 9993 | dcm4chee-arc, WildFly management | Publish on `127.0.0.1` only. |
| 11112, 2762 | DICOM (`FW_DICOM_PORTS`) | Published for the modalities. |
| 2575, 12575 | HL7 (`FW_HL7_PORTS`) | Published for the sending systems. |
| none | The helper service | It listens on unix sockets only, never on a TCP port. |

The Firewall tab filters the ports that Docker publishes. It does not filter nginx on the host.

Publish the ports of nginx on IPv4 only, as `0.0.0.0` (the compose examples do). Over IPv6 the Docker proxy accepts the connection, and nginx then sees only the Docker gateway as the client address. The audit log shows the gateway, the lock-out check of the firewall does nothing ([section 5.8](#contract-client-ip)), and the firewall of the admin panel, which handles IPv4 only, does not filter the port.

<a id="sockets"></a>
### 3.4 Sockets

| Socket | Type | Path | Used for |
|---|---|---|---|
| `verwaltung.sock` | stream, HTTP/1.0 | `PACS_SOCKET`, default `/run/pacs-admin/verwaltung.sock` | nginx passes `/admin/dienst/` to it. |
| `protokoll.sock` | datagram | `PACS_LOG_SOCKET`, default `/run/pacs-admin/protokoll.sock` | nginx sends the audit lines to it. |

Both sockets belong to `PACS_SOCKET_UID` and have mode 0600. The paths inside the nginx container are fixed in the nginx files: `/run/pacs-admin/verwaltung.sock` and `/run/pacs-admin/protokoll.sock`. Mount the directory `/run/pacs-admin` into the nginx container, and into no other container. Read-only is enough. If the directory is created again after the container started, the container does not see it until it restarts: `docker restart ohif`.

<a id="mounts"></a>
### 3.5 Mounts in the nginx container

The container paths are fixed, the nginx files refer to them. The host paths are examples.

| In the container | Content | Host path | Mode | When |
|---|---|---|---|---|
| `/etc/nginx/conf.d` | the folder with `pacs.conf` and `pacs/` | `/opt/ohif/nginx` | `:ro` | always |
| `/etc/nginx/tls` | `server.crt` and `server.key` | `/opt/ohif/tls` | `:ro` | listener `tls` |
| `/etc/nginx/htpasswd` | the files `users` and `admins` | `/opt/ohif/htpasswd` | `:ro` | login `basic` |
| `/srv/pacs-admin/admin` | `web/admin` of the repository | `/opt/pacs-admin/web/admin` | `:ro` | always |
| `/srv/pacs-admin/admin/config.js` | optional copy of `config.js` | `/opt/ohif/config.js` | `:ro` | optional |
| `/srv/pacs-admin/status` | the folder with `status.json` | `/var/lib/pacs-admin/status` | `:ro` | always |
| `/run/pacs-admin` | the two sockets | `/run/pacs-admin` | `:ro` | always |
| `/usr/share/nginx/html/app-config.js` | OHIF configuration | `/opt/ohif/app-config.js` | `:ro` | viewer `ohif` |
| `/usr/share/nginx/html/pacs-logo.svg` | logo for the page (`logo: '/pacs-logo.svg'` in `config.js`) | `/opt/ohif/logo.svg` | `:ro` | optional, viewer `ohif` |
| `/etc/localtime` | local time for the audit log | `/etc/localtime` | `:ro` | recommended |

Mount folders, not single files, for `conf.d` and `htpasswd`. A single file that is replaced (`sed -i`, `mv`) can keep its old content inside the container. A folder shows the new file at once. A folder over `/etc/nginx/conf.d` replaces the `default.conf` of the image. The start script of the image then prints `default.conf is not a file or does not exist`. The message is harmless.

`app-config.js`, `config.js` and the logo are single-file mounts. After an edit, run `docker compose restart` in the folder of the compose file, so that the container sees the new content.

With viewer `none` (the `nginx` image) do not mount a logo. Docker cannot add a new file inside the read-only folder `/srv/pacs-admin/admin`, and the container would not start. Copy the logo to `web/admin/logo.svg` in the repository instead and set `logo: '/admin/logo.svg'` in `config.js`.

<a id="permissions"></a>
### 3.6 Owners, modes and the uid 101

| Item | Read by | Owner and mode | Why |
|---|---|---|---|
| The two sockets | nginx worker processes | `PACS_SOCKET_UID`, 0600 (set by the helper service) | The uid and the mode are the only protection of the helper service, see below. |
| `htpasswd/users`, `htpasswd/admins` | nginx worker processes, at every request | Container: owner 101, mode 600. nginx on the host: `root:www-data`, mode 640. `pacs-adduser.sh` sets this. | A file that the worker cannot read gives 500 to every request that carries a name and password (error log: `open() ... failed (13: Permission denied)`). The password prompt still appears first. A missing file gives 403 (`failed (2: No such file or directory)`). |
| TLS key `server.key` | the nginx master process, at start | `nginx` image and nginx on the host: `root:root`, 0600. OHIF image: `chown root:101 server.key && chmod 640 server.key`. | In the OHIF image the master runs as uid 101 and could not read a root-only key. |
| `ohif-auth.env` | Docker Compose, as root | root, 0600 | It holds the client secret. |
| Audit key | the helper service, as root | root, 0600 | Without the key nobody can read the log. |
| `status.json` | nginx worker processes | 0644, directory 0755 | The file has no patient data. |

Find out which case applies to the TLS key:

```
docker exec ohif id
```

`uid=101(nginx)` means that the master runs as uid 101 (OHIF image). `uid=0(root)` means that it runs as root (`nginx` image).

**The uid of the sockets.** The nginx workers connect to the sockets, so the sockets belong to the uid of the workers: 101 in the `nginx` and OHIF images, 33 (`www-data`) for nginx on Debian. A mismatch gives 502 on `/admin/dienst/` and silently lost audit lines. The uid and the mode 0600 are the only protection of the helper service. Any process with that uid can use it as root: read the audit log, switch the firewall off, set up disks. So ideally no account on the host has this uid:

```
getent passwd 101
```

The command should print nothing. On Debian, uid 101 often belongs to a system account, for example `messagebus`. The risk is small for a plain system account, and the service starts anyway: it prints a warning to the journal when the uid belongs to an account. See [install guide](install.md#helper-service).

<a id="nginx-recipes"></a>
## 4. nginx recipes and the AE title

### 4.1 The three choices

The nginx configuration is one core file that you never edit, plus one small set of files for each of three choices:

- **Login** (`login/`): `oauth2-proxy`, `basic` or `none`. See [Login](login.md).
- **Viewer** (`viewer/`): `ohif` (the OHIF viewer and the reads it needs) or `none` (admin panel only: `/` redirects to `/admin/`).
- **Listener** (`listener/`): `tls` (https on this nginx), `plain` (plain http, for an SSH tunnel to `127.0.0.1`) or `behind-proxy` (plain http behind a proxy that ends TLS).

Every recipe edits the file `pacs/site.conf`. It holds `server_name`, the upstream names, the certificate paths and, for login `oauth2-proxy`, the admin group. Two choices add more values to change:

- Login `none`: the `allow` lines in `pacs/login/server.conf` (the PCs that may open the viewer) and `pacs/login/admin.conf` (the administrator PCs).
- Listener `behind-proxy`: `set_real_ip_from` in `pacs/listener/server.conf` (the address of the proxy; the shipped `203.0.113.1` trusts nobody).

Every value that you must change carries the marker `CHANGE-ME` on its line. Replace the value and delete the marker comment. Then `grep -rn CHANGE-ME /opt/ohif/nginx` prints nothing. A placeholder that is left in still passes `nginx -t`, so run the grep. The copy commands are in [deploy/nginx/README.md](../deploy/nginx/README.md#copy-commands). The list of all placeholders is in [deploy/nginx/README.md](../deploy/nginx/README.md#placeholders).

### 4.2 Recipes

A recipe is a choice of login, viewer and listener. The test lab of the maintainers names them `login-viewer-listener`, for example `oauth2-ohif-tls` ([deploy/nginx/README.md](../deploy/nginx/README.md#lab)).

| I want | Login | Viewer | Listener | Compose example in `deploy/compose/` |
|---|---|---|---|---|
| Microsoft Entra ID or another OIDC provider, OHIF viewer, https on this server | `oauth2-proxy` | `ohif` | `tls` | `docker-compose.oauth2.example.yml` |
| The same, admin panel only | `oauth2-proxy` | `none` | `tls` | start from the oauth2 example, use the `nginx` image |
| No OAuth proxy: user name and password in nginx, OHIF viewer, https | `basic` | `ohif` | `tls` | `docker-compose.basic.example.yml` |
| The same, admin panel only | `basic` | `none` | `tls` | `docker-compose.adminonly.example.yml` |
| A first look on 127.0.0.1 through an SSH tunnel, no TLS | `basic` | `none` (or `ohif`) | `plain` | `docker-compose.tryit.example.yml` |
| A TLS proxy (Traefik, Caddy, Apache, Cloudflare Tunnel) stays in front, nginx keeps login and locks | any | any | `behind-proxy` | `docker-compose.proxied.example.yml` |
| No login, only a list of networks | `none` | any | any | start from the nearest example |
| nginx installed on the host instead of a container | any | `none` | `tls` | none: the host steps are in [deploy/nginx/README.md](../deploy/nginx/README.md#host-nginx) |

Each compose example fixes one combination of login, viewer and listener:

| Example in `deploy/compose/` | Login | Viewer | Listener |
|---|---|---|---|
| `docker-compose.oauth2.example.yml` | `oauth2-proxy` | `ohif` | `tls` |
| `docker-compose.basic.example.yml` | `basic` | `ohif` | `tls` |
| `docker-compose.adminonly.example.yml` | `basic` | `none` | `tls` |
| `docker-compose.tryit.example.yml` | `basic` | `none` | `plain` |
| `docker-compose.proxied.example.yml` | `basic` | `ohif` | `behind-proxy` |

The header of each example names the lines to change for the other combinations.

Not supported: dcm4chee with its own Keycloak (the `-secure` images), and replacing nginx by Traefik, Caddy or Cloudflare Access. Those products can stand in front of nginx (listener `behind-proxy`).

<a id="ae-title"></a>
### 4.3 The AE title

The AE titles `DCM4CHEE` (archive) and `IOCM_QUALITY` (view of rejected studies) must be the same in every place that holds them:

| Place | Holds | Changed by |
|---|---|---|
| `nginx/pacs.conf` | the event map and the locations | `set-aet.sh` |
| `nginx/pacs/viewer.conf` | the viewer reads (viewer `ohif` only) | `set-aet.sh` |
| `app-config.js` | the data source (viewer `ohif` only) | `set-aet.sh` |
| `config.js`: `aet` and `iocmAet` | the page | `set-aet.sh`, if a copy of `config.js` lies under the directory. Otherwise by hand. |
| `/etc/default/pacs-admin`: `ARC_AET` | the disk assistant | by hand, then `systemctl restart pacs-verwaltung` |
| dcm4chee (LDAP) | the AE itself | dcm4chee |

`99DCM4CHEE` is a coding scheme, not an AE title. It stays. Do not use search and replace: `set-aet.sh` keeps it. [Section 2.5](#command-set-aet) describes the script.

<a id="front-door-contract"></a>
## 5. Front-door contract

This section states what the page and the helper service expect from a front door. Read it when you change the nginx files, when you build another front door, or when you send audit lines from another program. The nginx files in `deploy/nginx` meet every point.

This repository ships and tests only nginx as the front door. Another front door works if it meets this contract. Replacing nginx by Traefik, Caddy or Cloudflare Access is not supported: nobody tested it, and the audit lines need a shipper ([section 5.7](#audit-feed)). Put those products in front of nginx instead.

A front door must:

1. Serve the page and the status file at fixed paths on the origin root, without rewriting them ([5.1](#contract-paths), [5.9](#contract-same-origin)).
2. Check the login on every request, with two levels: any account and admin ([5.1](#contract-paths)).
3. Pass `/admin/dienst/` unchanged to the unix socket, and set `X-Auth-User` and `X-Real-IP` itself ([5.2](#contract-headers)).
4. Enforce the `X-PACS-Admin` guard ([5.3](#contract-guard)).
5. Pass the listed dcm4chee calls to arc without a token, and answer 404 for everything else ([5.5](#contract-dcm4chee)).
6. Remove `Authorization` and `Cookie` from calls to arc and to the helper service ([5.2](#contract-headers)).
7. Give the helper service the real client address ([5.8](#contract-client-ip)).
8. Write the audit lines to the log socket in the wire format ([5.6](#audit-wire-format)).

<a id="contract-paths"></a>
### 5.1 Paths, methods and levels

Every path is absolute and on the same origin as the page. The page lives at `/admin/`.

Level "admin" means an admin account. Level "any account" means every account that the login lets in.

| Path | Method | Level | Needs `X-PACS-Admin` | Answered by | Used for |
|---|---|---|---|---|---|
| `/admin` | GET | admin | no | front door | redirect to `/admin/` (not called by the page) |
| `/admin/`, `/admin/admin.css`, `/admin/config.js` | GET | admin | no | static files of `web/admin` | the page |
| `/admin/daten/status.json` | GET | admin | no | static file written by `dashboard-status.py` | numbers for the overview. No patient data. |
| `/admin/daten/rechner.json` | GET | admin | no | static file, optional | PC names. A 404 is fine. |
| `/admin/dienst/firewall` | GET | admin | no | helper service | rules, counters, senders |
| `/admin/dienst/firewall?neu=1` | GET | admin | yes | helper service | the same, after it reads new senders from `server.log` of the arc (`ARC_LOG_DIR`) and looks up the names of `FW_CLIENT_NAMES` in the DNS |
| `/admin/dienst/firewall` | POST | admin | yes | helper service | save all rules: JSON `{aktiv, schnittstelle, standard, regeln, ausgeblendet}`, at most 64 KB |
| `/admin/dienst/protokoll` | GET | admin | no | helper service | read the audit log, see [section 6.7](#audit-read) |
| `/admin/dienst/auftrag` | GET | admin | no | helper service | state and output of the last disk setup (`{}` before the first one since the helper started) |
| `/admin/dienst/platten` | GET | admin | yes | helper service | rescan the disks and refresh `status.json` |
| `/admin/dienst/einrichten` | POST | admin | yes | helper service | set up a disk: JSON `{geraet, groesse, name}` |
| `/admin/dienst/freigeben`, `/admin/dienst/anhaengen`, `/admin/dienst/abhaengen` | POST | admin | yes | helper service | clear the full mark, add to the write list, remove from the write list: JSON `{platte}` |
| `/oauth2/userinfo` | GET | any account | no | front door or oauth2-proxy | the account name at the top (`kontoUrl`). Optional. |
| `/dcm4chee-arc/aets/DCM4CHEE/rs/...` | see [5.5](#contract-dcm4chee) | | see 5.5 | arc | studies and patients |

The helper service answers with these status codes:

| Code | Meaning |
|---|---|
| 200 | Done. The body is JSON, except for `protokoll` (one JSON line per entry, `application/x-ndjson`). |
| 202 | A disk setup started. |
| 400 | The request is wrong. The body is `{"fehler": "..."}`. Causes: a POST body that is missing, not JSON or incomplete; a device or disk name that does not fit; a date or source of `protokoll` that is not valid; firewall rules that fail the check. |
| 404 | `{"fehler": "unbekannt"}`: any other path. |
| 409 | A disk job cannot run: another setup is still running, the disk is no longer recognized as blank in exactly this form, or `pacs-storage.sh` stopped with exit code 1. The body is `{"fehler": "..."}` with the reason; after a stop of the script it is the text behind `HALT: `. |
| 500 | An error inside. `firewall` answers `{"fehler": "Firewall: ..."}`, for example when `docker` is not installed, because the status needs the Docker networks. `platten` answers `{"ok": false, "fehler": "..."}` with the last line of the error message of `dashboard-status.py`, for example a bad number in `/etc/default/pacs-admin`. `freigeben`, `anhaengen` and `abhaengen` answer `{"fehler": "Archiv-Konfiguration nicht neu geladen (Antwort 000). ..."}` when `pacs-storage.sh` exits with 3 ([exit codes](#storage-exit-codes)): the change is made in LDAP and only the reload failed, so the answer is no 409 ("not done"). The text is the line behind `ACHTUNG: ` and tells to click **Neu laden** in the archive UI. The `einrichten` job ends in the same case with `rc` 3 in `GET /admin/dienst/auftrag`; the tile `Neue Festplatte` then shows the yellow box „Archiv nicht neu geladen“ with the same line. |
| 501 | A method other than GET and POST. The body is the standard error page of Python, not JSON. |
| 503 | `protokoll` only: the audit key or the database is not usable. The body is `{"fehler": "Protokoll: ..."}`. |
| 504 | `platten`, `freigeben`, `anhaengen` and `abhaengen`: `pacs-storage.sh` or `dashboard-status.py` did not finish within 300 seconds, and the helper stopped it. `einrichten` answers 504 only when the check before the start (`pacs-storage.sh kandidaten`) does not finish; no setup is started then. The script of the setup itself runs in the background without a time limit. The body is `{"fehler": "pacs-storage.sh antwortet nicht (nach 300 s abgebrochen), Zustand pruefen"}`; for `platten` the name is `dashboard-status.py`. After a button action the state is unknown: look at the disks on the server and at `/var/log/pacs-storage.log` before you try again. |

The helper reads the body of a POST up to a limit: 65536 bytes for the firewall, 4096 bytes for every other POST. It parses the body as JSON before it looks at the path. So a POST with a body that is not JSON gets 400 also on a path that does not exist. It speaks HTTP/1.0 and closes the connection after each answer. A client that does not finish its headers or its body within 30 seconds is disconnected without an answer. The disk calls and the rescan run long: allow 300 seconds for the answer. The nginx files set `proxy_read_timeout 300s`.

The helper matches the path text literally and in full. `/admin/dienst/platten?x=1`, `/admin/dienst/firewall?neu=0` and a path with a slash at the end all get 404. Only `protokoll` takes other query parameters. Do not rewrite the path.

<a id="contract-headers"></a>
### 5.2 Headers

| Header | Direction | Rule |
|---|---|---|
| `X-Auth-User` | front door to helper | The account name. Set it from the verified login, never from the request of the browser. The helper stores it as the name of whoever saved the firewall and of whoever started a disk setup. Missing means empty. It is attribution only, never authorization. |
| `X-Real-IP` | front door to helper | The address of the client PC. The helper uses it for the lock-out check of the firewall ([5.8](#contract-client-ip)). |
| `X-PACS-Admin` | browser to front door | The guard of [5.3](#contract-guard). The helper never reads it. The front door must remove it before it passes the request on. |
| `Authorization`, `Cookie` | browser to front door | Do not pass them to arc or to the helper service. A basic-auth password or a session cookie must not reach other components. |
| `X-Forwarded-For` | front door to arc | Set it to the client address. Do not pass the chain of the browser on. |

The helper reads `X-Auth-User`, `X-Real-IP` and `Content-Length`. It ignores all other headers, including `Host` and `Content-Type`.

**Authorization of the helper service is the socket.** The helper does not decide who may do what. Everything that can connect to `verwaltung.sock` can do everything that the page can do, as root. The socket belongs to `PACS_SOCKET_UID` and has mode 0600. A client that can connect can set any name in `X-Auth-User`: the stored name is only as trustworthy as the front door.

The nginx files set these headers in every location that talks to arc or to the helper service (`common/proxy.conf`):

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
### 5.3 The X-PACS-Admin guard (hard requirement)

The page sets the header `X-PACS-Admin` on every call that changes something. Its value is a readable description of the change, URL-encoded, and the audit log stores it. A page of another site cannot set a custom header without a CORS preflight, so the guard stops cross-site and accidental requests. The helper service does not check the header. The guard exists only in the front door, so every front door must implement it:

1. Answer `403` to a `POST` to `/admin/dienst/` when `X-PACS-Admin` is missing or empty.
2. Answer `403` to `GET /admin/dienst/platten` and `GET /admin/dienst/firewall?neu=1` without the header. Both have side effects (a disk rescan, a read of the arc log). The page sends the header for both. Compare the raw request target, exactly as the helper does ([5.1](#contract-paths)), and pass it on unchanged.
3. Answer `403` to every changing dcm4chee call of [5.5](#contract-dcm4chee) without the header.
4. Remove the header before the request goes to arc or to the helper.
5. Allow only `GET` and `POST` on `/admin/dienst/`. Answer `403` to `OPTIONS` and to every other method, and send no CORS headers. (`limit_except GET POST` of nginx lets `HEAD` through with `GET`. The helper answers it with 501.)

With login `basic` the browser sends the cached password with every request to the site, also with a request that another site triggers. The cross-site protection of a session cookie (`SameSite`) does not exist there, so the header is the only guard. (This follows from how basic authentication works. It was not tested with a browser.)

<a id="contract-minimal-nginx"></a>
### 5.4 Minimum nginx for an admin-only page

This configuration serves the page, the status file and the helper service, with login basic. Overview, Firewall and Protokoll (changes) work. Studien and Patienten need the dcm4chee calls of [5.5](#contract-dcm4chee) and show "abgelehnt (HTTP 404)" without them. Put the file in `/etc/nginx/conf.d/default.conf` (it sits in the `http` block). Mount `/srv/pacs-admin/admin` (the folder `web/admin`), `/srv/pacs-admin/status` and `/run/pacs-admin` as in [section 3.5](#mounts).

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

The file writes audit lines for the calls to `/admin/dienst/` only. It has no `access_log` for the rest of the server.

Checked in Docker with the image `nginx:1.30` (Debian 13), in front of the real helper service (Python 3.13, libsqlcipher 4):

- Without a name and password the page and the helper path give `401`. A wrong password gives `401` too. With a correct login the page, `config.js` and `status.json` give `200`.
- A POST without `X-PACS-Admin`, or with an empty one, gives `403`. So do `GET /admin/dienst/platten` and `GET /admin/dienst/firewall?neu=1` without the header. With the header the helper answers with its own status: `400` for a body that is not valid JSON or lacks fields, `404` for an unknown path.
- `PUT`, `DELETE` and `OPTIONS` give `403`. `HEAD` passes nginx and the helper answers `501`. A body of 70 KB gives `413`.
- 24 requests to `/admin/dienst/` left 24 `zugriffe` rows and 6 `admin` rows: one `admin` row per POST, the refused ones included.
- A stand-in that echoes the request showed what the helper receives. `X-Auth-User` and `X-Real-IP` come from nginx (forged values of the browser are replaced). `X-PACS-Admin`, `Authorization` and `Cookie` do not arrive. `Host` is `localhost`. Other headers of the browser, such as `X-Forwarded-For`, pass through. The helper reads only `X-Auth-User`, `X-Real-IP` and `Content-Length`.

Not needed here: the OHIF viewer, the cross-origin headers, the oauth2 locations, HTTP/2, gzip and a resolver. Replace `auth_basic` by a network list (`allow` and `deny`) or by another login. Keep the name rule: `$pacs_user` must not be empty.

<a id="contract-dcm4chee"></a>
### 5.5 dcm4chee REST calls

The examples use the default AE titles `DCM4CHEE` and `IOCM_QUALITY`. They follow `aet` and `iocmAet` of `config.js`. The study UID in the examples is `1.2.3`.

Calls of the admin page:

| Call | Level | `X-PACS-Admin` | Used for |
|---|---|---|---|
| `GET /dcm4chee-arc/aets/DCM4CHEE/rs/studies?PatientID=...` | any account | no | study search (QIDO) of the Studien tab. The parameters are `PatientID`, `PatientName` (the page adds a `*`), `AccessionNumber`, `StudyDate` (`YYYYMMDD-YYYYMMDD`), `includefield`, `limit=200` and `orderby`. |
| `GET /dcm4chee-arc/aets/DCM4CHEE/rs/studies?StudyInstanceUID=1.2.3,...` | any account | no | the lookups of the Protokoll tab: studies of a patient number (`PatientID`, `limit=1000`), of a name (`PatientName` with `*` and `fuzzymatching=false`, `limit=1000`), and by lists of up to 40 `StudyInstanceUID` (`limit=100`). All with `includefield`. |
| `GET /dcm4chee-arc/aets/DCM4CHEE/rs/patients?...` | admin | no | patient search of the Patienten tab (`PatientID`, `PatientName` with `*`, `includefield=all`, `limit=100`) and the look-up of the target patient when you move a study (`PatientID`, `includefield`) |
| `GET /dcm4chee-arc/aets/IOCM_QUALITY/rs/studies?...` | admin | no | the view of rejected studies (same parameters as the study search) |
| `POST /dcm4chee-arc/aets/DCM4CHEE/rs/studies/1.2.3/reject/113001%5EDCM` | admin | yes | reject a study |
| `POST /dcm4chee-arc/aets/IOCM_QUALITY/rs/studies/1.2.3/reject/REVOKE_REJECTION%5E99DCM4CHEE` | admin | yes | restore a rejected study |
| `DELETE /dcm4chee-arc/aets/IOCM_QUALITY/rs/studies/1.2.3` | admin | yes | delete a rejected study for good |
| `POST /dcm4chee-arc/aets/DCM4CHEE/rs/studies/update?reasonForModification=CORRECT&StudyInstanceUID=1.2.3` | admin | yes | change study attributes (JSON body) |
| `POST /dcm4chee-arc/aets/DCM4CHEE/rs/studies/1.2.3/patient?PatientID=P1&IssuerOfPatientID=I1&updatePolicy=PRESERVE` | admin | yes | move a study to another patient |
| `POST /dcm4chee-arc/aets/DCM4CHEE/rs/patients/P1/merge/P2` | admin | yes | merge two patients |
| `PUT /dcm4chee-arc/aets/DCM4CHEE/rs/patients/P1` | admin | yes | change a patient (the whole record as JSON) |

Calls of the OHIF viewer (viewer mode `ohif`): `GET` below `/dcm4chee-arc/aets/DCM4CHEE/rs/studies`, `rs/series`, `rs/instances` and `/wado`, level any account. OHIF sends no `orderby`, and dcm4chee then lists the oldest study first. So nginx adds `orderby=-StudyDate,-StudyTime` to every study search without `orderby`.

Locks that the nginx files add. A front door that wants the same protection reproduces them:

- Change a study only with exactly the query string `reasonForModification=NAME&StudyInstanceUID=UID`, where `UID` is digits and dots, matched case-sensitively (without a `StudyInstanceUID` dcm4chee changes all studies). Allow this one form instead of blocking bad forms: a second `StudyInstanceUID` or a comma list in one selects several studies, and arc also reads the key in other spellings (the hex form `0020000D`), so a list of forbidden forms is never complete.
- Move a study only with `PatientID=ID`, optionally `&IssuerOfPatientID=ID`, and `&updatePolicy=PRESERVE`, in this order and nothing else (otherwise dcm4chee overwrites the target patient).
- Change a patient never with `merge`, and refuse a percent sign in a parameter name.
- Delete for good only through `IOCM_QUALITY`, where dcm4chee deletes rejected studies only.
- Answer `400` to a path that contains `;`, an encoded backslash (`%5c`) or a raw backslash: nginx does not normalize path parameters, and the upstream may.
- The locks on the query string and the guard for the path answer before the login check, so a wrong request gets 403 or 400 even without a login.
- Answer `404` to every other path below `/dcm4chee-arc/`.

**dcm4chee must run without Keycloak.** The page and nginx send no token to arc. `pacs-storage.sh` calls arc on the host without a token too: `POST ARC_URL/dcm4chee-arc/ctrl/reload` and `GET ARC_URL/dcm4chee-arc/storage`. Besides REST, the disk assistant needs `docker exec` into the arc container and into the LDAP container. The `-secure` images of dcm4chee (own Keycloak login) are not supported.

<a id="audit-wire-format"></a>
### 5.6 Audit lines: wire format

The front door sends one datagram per line to the unix datagram socket `PACS_LOG_SOCKET`. nginx does this with `access_log syslog:`. A datagram has these parts, without a newline:

| Part | Value |
|---|---|
| `<PRI>` | `<` digits `>`, for example `<190>` (nginx) or `<13>` (`logger`). The number is ignored. |
| time | Exactly 15 characters, for example `Oct  1 10:58:23`. The helper ignores the content. |
| space | one space |
| tag | `zugriffe`, `ereignisse` or `admin`, in lower case |
| separator | a colon and a space |
| message | one JSON object on one line |

Example:

```
<190>Oct  1 10:58:23 ereignisse: {"t":"2026-10-01T10:58:23+02:00","u":"anna","sub":"anna","ip":"192.0.2.10","r":"/dcm4chee-arc/aets/DCM4CHEE/rs/studies/1.2.3/series","status":200}
```

The helper matches each datagram with this pattern, with `re.match` and the flag `re.S`:

```
<\d+>.{15} (zugriffe|ereignisse|admin): (.*)
```

A datagram that does not match is dropped without a message. Typical mistakes are a host name between the time and the tag (nginx without `nohostname`), a tag in another case, and a missing `<PRI>`. A trailing newline is accepted. One datagram is one line: do not put a newline inside the JSON. The helper reads datagrams of up to 1 MiB. nginx lines of about 20 KB arrived complete.

Every message is one JSON object. The helper stores the text unchanged. It takes the time of the row from the field `t`, and uses the arrival time when `t` is missing or unreadable. The page reads these fields:

| Field | Tags | Meaning |
|---|---|---|
| `t` | all | Time of the request in ISO 8601 with a numeric offset with a colon, for example `2026-10-01T10:58:23+02:00` (nginx `$time_iso8601`). Python 3.7 to 3.10 does not read `+0200` or `Z`: the helper then stores the arrival time. The page parses `t` itself with the browser: a line without a `t` that the browser reads is skipped and counted. |
| `u` | all | Account name. It should not be empty. An empty or missing `u` shows as "(ohne Konto)". |
| `sub` | all | ID of the account as the login reports it. The page does not read it. See [section 6.2](#audit-account). |
| `ip` | all | Address of the client PC. The page shows it as "PC". With `rechner.json` it shows the PC name too. |
| `r` | `zugriffe`, `ereignisse` | The request URI as the browser sent it, with the query. The page derives the action from it. For `admin` the value is the text `admin`. |
| `status` | all | HTTP status as a number. A value of 400 or more shows as "(HTTP nnn)". |
| `m` | `admin` | Method. Optional. |
| `uri` | `admin` | Request URI. Optional. The page takes the study number from it. |
| `k` | `admin` | Description from the page (the value of `X-PACS-Admin`, URL-encoded). Optional. |
| `body` | `admin` | Request body. The page does not read it. |

Tags:

- `zugriffe`: every request. Fields `t`, `u`, `sub`, `ip`, `r`, `status`. Only `pacsdb.py` reads this tag. The Protokoll tab does not.
- `ereignisse`: requests that users care about: searches, opened studies and reports. Same fields. The tab derives the action from `r`.
- `admin`: changes. Fields `t`, `u`, `sub`, `ip`, `r` (always `admin`), `m`, `uri`, `status`, `k`, `body`.

What the Protokoll tab does with a line. It asks the helper service for the tags `ereignisse` and `admin` of the chosen days, and then:

- A line that is not a JSON object is skipped and counted.
- A line without a `t` that the browser can read is skipped and counted.
- An `r` that the browser cannot read as an address is skipped and counted. The tab shows the count below the list: "N unlesbare Zeilen übersprungen" (one line: "1 unlesbare Zeile übersprungen").
- A line without `r`, or with an `r` that is not a study search, a patient search, an opened study or an opened report, is skipped without a count. A search with only `StudyInstanceUID` as filter is skipped too: OHIF and the page itself send it when they open a study.
- A missing or empty `u` shows as "(ohne Konto)".
- An `admin` line shows the text of `k`, or `m` and `uri` if `k` is missing, or "Änderung" if all three are missing, followed by "(Verwaltung)". The tab takes the study number from `uri`.
- A missing `status` counts as no error. A value of 400 or more shows as "(HTTP nnn)".
- The tab shows at most 2000 rows, the newest first. The same account with the same study or search within 30 minutes counts as one row, and each repeat restarts the 30 minutes. `admin` lines are never merged.

The name and the study details of a row come from the archive at display time: the tab asks `rs/studies` for the study numbers, or for the patient number or name that you typed in the filter ([5.5](#contract-dcm4chee)).

The Übersicht shows the last 15 `admin` lines with `t`, `u`, `k` (or `m` and `uri`) and `status`. A `status` below 300 shows as "erledigt", anything else as "HTTP nnn". Both views ask the helper service for the lines. If it answers with an error, the Protokoll tab shows "Fehler: Protokoll: HTTP nnn".

<a id="audit-feed"></a>
### 5.7 Feed the log from another program

Another front door or a log shipper can write the datagrams itself. The socket belongs to `PACS_SOCKET_UID` and has mode 0600: the program must run as root or as that uid, or inside the nginx container. With `logger` from the package `bsdutils`:

```
logger -u /run/pacs-admin/protokoll.sock -t zugriffe '{"t":"2026-10-01T12:00:00+02:00","u":"anna","sub":"anna","ip":"192.0.2.10","r":"/admin/","status":200}'
```

`logger` sends `<13>Oct  2 07:44:42 zugriffe: {...}`, which the helper accepts. A shipper in Python that reads JSON lines from stdin:

```python
import socket, sys, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
for line in sys.stdin:
    line = line.strip()
    if line:
        s.sendto(("<13>%s zugriffe: %s" % (time.strftime("%b %e %H:%M:%S"), line)).encode(), "/run/pacs-admin/protokoll.sock")
```

The helper stores the lines within about 2 seconds. Check the result:

```
python3 /opt/pacs-admin/server/pacsdb.py protokoll zugriffe $(date +%F)
```

Limits:

- The Protokoll tab reads only `ereignisse` and `admin`. A shipper that writes only `zugriffe` fills the database, and the tab stays empty. To fill the tab, classify the requests yourself: `ereignisse` for searches and opened studies, `admin` for changes (with `m`, `uri`, `k`).
- Only nginx has the maps and `$request_body` for `ereignisse` and `admin` lines.
- Caddy and Traefik write JSON to stdout or a file and need a shipper like the one above. oauth2-proxy, Authelia, Authentik and Cloudflare Access only see the login request: they cannot write the lines.

Apache 2.4 can feed `zugriffe` through a piped `CustomLog`. This format delivered valid rows (tested with Apache 2.4.68 and `logger` from `bsdutils`):

```
LogFormat "{\"t\":\"%{%Y-%m-%dT%H:%M:%S%z}t\",\"u\":\"%u\",\"sub\":\"%u\",\"ip\":\"%a\",\"r\":\"%U%q\",\"status\":%>s}" pacs
CustomLog "|/usr/bin/logger -u /run/pacs-admin/protokoll.sock -t zugriffe" pacs
```

Three differences from nginx:

- `u` is `-` for a request without login. Apache has no rule like `anon-` plus the address.
- `%z` writes the offset without a colon, for example `+0200`. Python before 3.11 cannot read that, so the helper stores such rows with the arrival time. (Python 3.13 read it. Python 3.7 to 3.10 was not run.)
- `%U` is the decoded path, and Apache writes a control character as `\x01`, which is not valid JSON. A quote or a backslash is escaped correctly.

<a id="contract-client-ip"></a>
### 5.8 The real client address

The front door must pass the real address of the client PC in `X-Real-IP`, and it must use that address in the `ip` field of the audit lines. The helper uses `X-Real-IP` for the lock-out check of the firewall: a save is refused when the saving PC would lose access to the https port (the first of `FW_WEB_PORTS`). The check works for IPv4 addresses only. Addresses in Docker networks, on the server itself and on loopback are exempt. If the header is missing or not an IPv4 address, the check is skipped and the change is accepted.

Behind another proxy the address of the connection is the address of the proxy, usually inside a Docker network. The audit log and the PC column then show the proxy, and the lock-out check does nothing. With nginx behind a proxy, set the real address from the header of the proxy. The listener `behind-proxy` does this:

```
set_real_ip_from 203.0.113.1;   # CHANGE-ME: the address of your proxy
real_ip_header X-Forwarded-For;
real_ip_recursive on;
```

The shipped file carries `203.0.113.1`, an address from the documentation range that trusts nobody. Replace it with the address of your proxy, or at most the network that nginx shares with it, and let only the proxy reach nginx. From anywhere else `X-Forwarded-For` is a forgery.

<a id="contract-same-origin"></a>
### 5.9 Same origin and absolute paths

The page lives at `/admin/` on the origin root. It calls `/admin/daten/`, `/admin/dienst/` and `/dcm4chee-arc/aets/AET/rs` with absolute paths on the same origin, and the helper compares the path text literally. A front door that rewrites a path, removes a prefix, hosts the page under a sub-path, or splits the page and the REST calls over different hosts or ports does not work without editing `index.html`. The page never reads cookies. Its calls use the cookies or the password that the browser holds for the same origin.

When the session ends, the front door should answer a call with a redirect (to the login page) or with status 401. The page treats both as an expired session and shows "Sitzung abgelaufen, Seite neu laden (F5)". It does not follow redirects, so it treats every redirect that way, also one to the same origin. Do not redirect calls for other reasons, for example to add a trailing slash.

<a id="audit-log"></a>
## 6. Audit log

The audit log records who searched, who opened what and who changed what. nginx sends the lines, the helper service stores them in an encrypted database, and the Protokoll tab shows them. The wire format is in [section 5.6](#audit-wire-format).

<a id="audit-tags"></a>
### 6.1 What is logged under which tag

| Tag | What | Where nginx writes it |
|---|---|---|
| `zugriffe` | every request: static files, searches, changes and refused requests | the server block of `pacs.conf`. The write locations, `/admin/dienst/` and the dcm4chee UI section repeat it, because an `access_log` in a location replaces the ones of the server block. |
| `ereignisse` | `GET` only: a study search (`rs/studies`), a patient search (`rs/patients`), a search in the view of rejected studies (`IOCM_QUALITY/rs/studies`), the series list of a study (that is "study opened"), the metadata of an instance and WADO-URI (that is "report opened") | the server block, for the viewer and the page. The dcm4chee UI section writes it too, for the same calls. |
| `admin` | every request to a write location, also a refused one; every `POST` to `/admin/dienst/`; every request of the dcm4chee UI section except `GET`, `HEAD` and `OPTIONS` | `common/audit-write.conf` (included in the write locations), the location `/admin/dienst/`, the dcm4chee UI section |

So a change through the page writes two lines, one `zugriffe` and one `admin`. A `GET` to `/admin/dienst/` writes one line, `zugriffe`. A study search writes `zugriffe` and `ereignisse`.

Nothing goes to `docker logs`, because the URLs contain patient data. For a debug session add `access_log /dev/stdout pacs;` to the server block for a while. It covers only the locations without an `access_log` of their own.

<a id="audit-account"></a>
### 6.2 The account name

The field `u` is never empty. nginx fills it like this:

| Login | `u` |
|---|---|
| `oauth2-proxy` | the claim `preferred_username`; if it is empty the e-mail address; then the user ID that oauth2-proxy reports (the value of `sub`); then `anon-` plus the client address |
| `basic` | the name the client sent (the claimed name, also for a wrong password); `anon-` plus the client address when no name was sent |
| `none` | always `anon-` plus the client address. There are no accounts. |

`sub` carries the ID that the login reports. With `oauth2-proxy` it is the header `X-Auth-Request-User` of oauth2-proxy (empty when no session was checked). With `basic` and `none` it equals `u`. `sub` is only the name of the field: what oauth2-proxy puts into that header depends on its configuration and on the provider, and it is not necessarily the claim `sub` of the ID token.

<a id="audit-refused"></a>
### 6.3 Refused requests have no verified account

nginx refuses some requests before the login check ran: a missing `X-PACS-Admin`, a lock argument, a `;` in the path. With login `oauth2-proxy` and `none`, a non-admin on `/admin/` is refused by the login check, which sets no account on failure. All these rows carry `anon-` plus the client address. With login `basic` they carry the name that the client sent. A refused row shows the PC and the time, not a verified person. To find the person, compare the `ip` and the time with the `zugriffe` rows of the same PC.

A request without a session is logged too. With oauth2-proxy it gets status 302 and `u` `anon-ADDRESS`. A search URL that was requested without a session therefore shows in the tab as a search by `anon-ADDRESS`. With login `basic`, a failed login shows the claimed name and status 401, so a 401 row for `vera` does not mean that Vera did something. The nginx error log also records `user "vera": password mismatch`.

Rows with a status of 400 or more show "(HTTP nnn)". The filter "nur Abgelehntes und Fehler" lists them.

<a id="audit-lost"></a>
### 6.4 Lost lines

nginx sends the lines as datagrams and does not wait. While the helper service is down or restarting, every line is lost. After a restart, the helper has a new socket file, and the first line of each nginx worker is lost too. Users keep working and nothing shows an error, but a call to `/admin/dienst/` answers 502.

The nginx error log shows both. For each lost line it has up to three messages, all with `to syslog`:

```
[error] send() failed (111: Connection refused) while logging to syslog, server: unix:/run/pacs-admin/protokoll.sock
[alert] connect() failed (111: Connection refused) while logging to syslog, server: unix:/run/pacs-admin/protokoll.sock
[warn] send() to syslog failed while logging request, ...
```

For the 502 it has `connect() to unix:/run/pacs-admin/verwaltung.sock failed (111: Connection refused) while connecting to upstream`. To list the lost lines:

```
docker logs ohif 2>&1 | grep 'to syslog'
```

Restart `pacs-verwaltung` rarely and outside working hours.

If the helper cannot write the database (key missing or wrong, disk full), it keeps the lines in memory and tries again every 10 seconds. A restart of the service drops those lines. The journal shows the reason, for example `Protokoll nicht abgelegt (5 Zeilen), neuer Versuch in 10 s: [Errno 2] No such file or directory: '/etc/pacs-protokoll.key'`. While the database is unusable, `GET /admin/dienst/protokoll` and the Protokoll tab get status 503. At the next try after the key or the disk is fixed, the helper stores the kept lines.

<a id="audit-retention"></a>
### 6.5 Retention

The audit log is never pruned. No program in this repository removes rows. The database grows with every request, because `zugriffe` holds one row per request, static files included. Plan the disk space of `/var/lib/pacs-protokoll/` and your own retention rules. The log contains patient IDs and names from search URLs and from the body of changes. Treat it like patient data.

<a id="audit-key-format"></a>
### 6.6 Key and database format

**Key.** The database is encrypted with SQLCipher. The key is a raw 256-bit key: 64 lowercase hex characters in `PROTOKOLL_KEY`. It is not a passphrase and has no key derivation. Make it, check it and keep a copy offline (for example in the password safe). Without the key nobody can read the log, you included.

```
(umask 077; openssl rand -hex 32 > /etc/pacs-protokoll.key)
grep -Eq '^[0-9a-f]{64}$' /etc/pacs-protokoll.key && echo key ok
```

`pacsdb.py test` uses a temporary key and never opens the key file. To check the real key, read the real database: `python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse`. It prints nothing for an empty database. See [install guide](install.md#audit-key).

**File format.** SQLCipher 3.x and 4.x write different file formats. New databases get format 3 (`PRAGMA cipher_compatibility = 3`, page size 1024), which both library versions open. Version 3.x ignores the pragma, because format 3 is its default. When a file is opened, `pacsdb.py` tries format 3 first, then the library default (format 4 on 4.x).

| File | Opens on libsqlcipher 3.x | Opens on libsqlcipher 4.x |
|---|---|---|
| format 3, written on 3.x | yes | yes |
| format 3, written on 4.x (by this version) | yes | yes |
| format 4, written on 4.x by an older version of `pacsdb.py` | no | yes |

All rows were tested with libsqlcipher 3.4.1 (Debian 10 and 12) and 4.6.1 (Debian 13). Other versions are not tested. After an OS upgrade (Debian 12 to 13) the file stays readable. A format 4 file cannot be opened on a host with libsqlcipher 3.x. SQLCipher gives the same answer for three causes: a wrong key, a file that is not a SQLCipher file, and a format 4 file on 3.x. So the error names all three and the library version. It starts with the path and the SQLite text (`file is not a database` or `file is encrypted or is not a database`) and ends like this: `Schluessel falsch, keine SQLCipher-Datei oder eine Datei im Format von SQLCipher 4, die libsqlcipher 3.x nicht oeffnet (hier SQLCipher 3.4.1), siehe docs/install.de.md#audit-key`. A failed open changes nothing in the file. There is no converter. Either read the file on a host with 4.x (`pacsdb.py protokoll` prints JSON lines), or move the file aside and let the service create a new format 3 file with the same key.

By hand, with the `sqlcipher` program:

```
sqlcipher /var/lib/pacs-protokoll/protokoll.db
PRAGMA key = "x'CHANGE-ME-64-HEX-CHARACTERS'";
PRAGMA cipher_compatibility = 3;
select count(*) from protokoll;
```

The `PRAGMA cipher_compatibility = 3;` line is needed for a format 3 file on SQLCipher 4.x and is ignored on 3.x. The table is `protokoll(id, quelle, zeit, zeile)`: `quelle` is the tag, `zeit` the time as a number of seconds, `zeile` the JSON line.

<a id="audit-read"></a>
### 6.7 Read the log from the command line

On the server, as root:

```
python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse 2026-10-01 2026-10-02
```

The arguments are the tag (`zugriffe`, `ereignisse` or `admin`) and, optional, a first and a last day as `YYYY-MM-DD`. The last day is included. The days start at midnight in the time zone of the server. The program prints one JSON line per row, ordered by time. An unknown tag gives no output and no error. A date that it cannot read counts as the current time: no error, and usually no output.

The program uses `PROTOKOLL_DB` and `PROTOKOLL_KEY`. When you changed them in `/etc/default/pacs-admin`, load the file first:

```
set -a; . /etc/default/pacs-admin; set +a
```

If the database file does not exist, the program creates it, empty, together with its folder (folder mode 700, file mode 600). So check the path when the output is empty. On a problem (key missing or wrong, library missing, wrong format) it prints one line `pacsdb.py: ...` and exits with 1. Without arguments it prints its usage and exits with 1.

The helper service gives the same rows over its socket (as root, no nginx needed):

```
curl -s --unix-socket /run/pacs-admin/verwaltung.sock 'http://localhost/admin/dienst/protokoll?quelle=admin&letzte=15'
```

| Parameter | Meaning |
|---|---|
| `quelle` | One or more tags, separated by commas. Default `ereignisse,admin`. Unknown names are ignored. Answer 400 if none is left. |
| `von`, `bis` | First and last day as `YYYY-MM-DD`, the last day included. Default: the last 30 days. The day limits are midnight in the time zone of the server. A bad date gives 400. A reversed range gives an empty answer. |
| `letzte` | The last N rows, at most 1000, regardless of the dates. 0 or a negative number means: use the date range. A non-number gives 400. |

The answer has the type `application/x-ndjson`: one JSON line per row, lines separated by a newline, ordered by time. The page and the nginx lines use time zones too: `t` carries the offset of nginx (mount `/etc/localtime` into the container), the day limits of the helper use the time zone of the server, and the page uses the time zone of the browser. Keep the server, the containers and the browsers in the same time zone.
