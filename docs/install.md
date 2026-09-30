# Installation

English | [Deutsch](install.de.md)

This guide assumes:

- the repository in `/opt/pacs-admin` (the systemd units and the cron file use this path)
- the dcm4chee Compose project in `/opt/dcm4chee-arc` (`PACS_DIR`), with the containers `arc` and `ldap` on the
  Docker network `dcm4chee_default`
- a separate Compose project for OHIF and oauth2-proxy, here `/opt/ohif`
- the host name `pacs.example.org`

Run all commands as root. If your paths or names differ, change them in `/etc/default/pacs-admin` (step 3) and in the
two example files (step 9). A repository path other than `/opt/pacs-admin` also goes into `ExecStart` of both units
and into the cron file.

## 1. Check the requirements

```
python3 --version                                   # 3.7 or newer
docker version --format '{{.Server.Version}}'
docker compose version
iptables --version                                  # "(nf_tables)" means iptables-nft
docker inspect -f '{{.Config.Image}}' arc           # dcm4chee-arc-psql, not a -secure image
apt install libsqlcipher0 util-linux e2fsprogs curl
```

The archive must run without Keycloak. nginx calls the dcm4chee REST API without a token.

## 2. Copy the files

```
git clone https://github.com/pbaetz99/dcm4chee-admin-panel.git /opt/pacs-admin
```

Copying the directory works as well. The scripts are started through `python3` and `/bin/bash`, so missing execute
bits do not matter.

## 3. Settings

```
cp /opt/pacs-admin/deploy/pacs-admin.env.example /etc/default/pacs-admin
```

Every line in the file is commented out and shows the default. Uncomment and change only what differs on your site.
Typical candidates: `PACS_DIR`, `ARC_AET`, `ARC_CONTAINER`, `LDAP_CONTAINER`, `STORAGE_PREFIX`, `FW_CLIENT_NAMES`,
`DASHBOARD_CONTAINERS`. All variables are listed under [Configuration](#configuration).

The systemd units and the cron job load this file. `pacs-storage.sh` reads it itself. The Python scripts read only
their environment, so load the file first when you run one of them by hand:

```
set -a; . /etc/default/pacs-admin; set +a
```

## 4. Audit log key

```
(umask 077; openssl rand -hex 32 > /etc/pacs-protokoll.key)
python3 /opt/pacs-admin/server/pacsdb.py test
```

The test prints `Selbsttest ok: ...`. It checks that libsqlcipher is found and that the database file holds no plain
text.

The key is 64 lowercase hex characters, owned by root, mode 0600. Put a copy offline, for example in the password
safe. Without the key nobody can read the log, you included.

The helper service creates the database on its first write: `/var/lib/pacs-protokoll/protokoll.db` (directory 0700,
file 0600).

## 5. Prepare the archive for the disk assistant

The assistant only adds a storage once the arc container sees the new mount. arc needs `STORAGE_BASE` as a volume with
mount propagation. In `/opt/dcm4chee-arc/docker-compose.yml`:

```
  arc:
    volumes:
      - /mnt/fs:/mnt/fs:rslave
```

Recreate arc. The archive is down for about 30 seconds.

```
cd /opt/dcm4chee-arc && docker compose up -d arc
```

Storage ID, filesystem label and mount directory share one name: `STORAGE_PREFIX` plus a two-digit number, for example
storage `PACS-Data01` on `/mnt/fs/PACS-Data01`. The overview lists only mount points that follow this pattern. Check
what the assistant sees:

```
bash /opt/pacs-admin/server/pacs-storage.sh scan
```

It lists the mounted storages, blank disks, grown disks and mount points without `NO_MOUNT`. `NO_MOUNT` is a read-only
file below the mount point. It is visible only when the disk is not mounted, for dcm4chee's "Check Mount File Path".
`bash /opt/pacs-admin/server/pacs-storage.sh nomount` shows the plan,
`bash /opt/pacs-admin/server/pacs-storage.sh nomount ja` creates the file where it is missing.

Every changing command of `pacs-storage.sh` only prints its plan unless the last argument is `ja`. It logs to
`/var/log/pacs-storage.log`.

The assistant sets up whole blank disks, never partitions. The overview offers only the disks that
`pacs-storage.sh kandidaten` lists (blank, not in use, at least `STORAGE_MIN_GB`). The helper service accepts these
device names: `/dev/sd[a-z]+`, `/dev/vd[a-z]+`, `/dev/xvd[a-z]+` and `/dev/nvme[0-9]+n[0-9]+`.

## 6. Helper service

```
cp /opt/pacs-admin/deploy/systemd/pacs-verwaltung.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now pacs-verwaltung
ls -l /run/pacs-admin/
```

Expected: two sockets, owner 101 (nginx in the OHIF image), mode `srw-------`.

```
srw------- 1 101 root 0 ... protokoll.sock
srw------- 1 101 root 0 ... verwaltung.sock
```

The sockets, and the TLS key in step 9, are protected by this uid alone. No account on the host may have it:

```
getent passwd 101
```

The command must print nothing. On Debian, uid 101 often belongs to a system account that a package created. Every
process of that account could then read the audit log through the socket and switch the firewall off. The service
writes a warning to the journal in that case. Two ways out: Docker's `userns-remap`, so that uid 101 in the container
is a free, high uid on the host, or `user:` in the compose file with a uid that is free on the host (check that nginx
in the image still starts). Set `PACS_SOCKET_UID` to the uid the host sees and give that uid the TLS key.

Test it without nginx:

```
curl -s --unix-socket /run/pacs-admin/verwaltung.sock http://localhost/admin/dienst/auftrag
```

The answer is `{}` as long as no disk has been set up.

## 7. Overview numbers (cron)

```
cp /opt/pacs-admin/deploy/cron/pacs-dashboard /etc/cron.d/pacs-dashboard
set -a; . /etc/default/pacs-admin; set +a
python3 /opt/pacs-admin/server/dashboard-status.py
cat /var/lib/pacs-admin/status/status.json
```

The cron job runs every 5 minutes and writes errors to `/var/log/pacs-dashboard.log`.

Besides disks, blank disks and containers, `status.json` carries three settings for the page: `prefix`
(`STORAGE_PREFIX`, the overview shows disk names without it), `frei_gb` (`STORAGE_FREE_GB`, the overview shows
"Markierung entfernen" and "In Schreibliste aufnehmen" only on disks with at least this many GB free) and `warn_gb`
(`STORAGE_WARN_GB`, below this the overview asks for a new disk). After changing one of them in
`/etc/default/pacs-admin`, restart `pacs-verwaltung` and run the job again.

By default the Dienste tile shows the containers of the Compose project in `PACS_DIR`. OHIF and oauth2-proxy run in
their own project. To show them too, list all containers: `DASHBOARD_CONTAINERS=arc,ldap,db,ohif,ohif-auth`.

## 8. App registration in Entra ID

In the Entra admin center:

1. App registrations, New registration. Name for example "PACS". Supported account types: this organizational
   directory only. Redirect URI: platform Web, `https://pacs.example.org/oauth2/callback`.
2. Overview: note the Application (client) ID and the Directory (tenant) ID.
3. Certificates & secrets, New client secret. Copy the Value, not the Secret ID. Note the expiry date. When the
   secret expires, nobody can log in.
4. Token configuration, Add groups claim: Security groups, ID token as Group ID.
5. Create two security groups, for example "PACS Viewer" and "PACS Admin", and note their Object IDs. Members of the
   viewer group can use the viewer. Members of the admin group can use the viewer and `/admin/`.

Where the values go:

| Value | File | Place |
|---|---|---|
| Directory (tenant) ID | `docker-compose.yml` | `TENANT-ID` in `--oidc-issuer-url` |
| Application (client) ID | `ohif-auth.env` | `OAUTH2_PROXY_CLIENT_ID` |
| Client secret value | `ohif-auth.env` | `OAUTH2_PROXY_CLIENT_SECRET` |
| Viewer group Object ID | `docker-compose.yml` | `VIEWER-GRUPPEN-ID` |
| Admin group Object ID | `docker-compose.yml` and `nginx.conf` | `ADMIN-GRUPPEN-ID` (both places) |

Another OIDC provider: set `--provider=oidc` and its `--oidc-issuer-url`, and use the group names as they appear in
the `groups` claim. The audit log names the account by `preferred_username`. If the provider does not send that claim
(Google, for example), nginx takes the e-mail address instead.

## 9. nginx and Compose for OHIF

```
mkdir -p /opt/ohif/tls
cp /opt/pacs-admin/deploy/docker-compose.example.yml /opt/ohif/docker-compose.yml
cp /opt/pacs-admin/deploy/nginx.conf.example /opt/ohif/nginx.conf
```

Secrets for oauth2-proxy. Replace the two placeholders after writing the file:

```
cat > /opt/ohif/ohif-auth.env <<EOF
OAUTH2_PROXY_CLIENT_ID=<Application (client) ID>
OAUTH2_PROXY_CLIENT_SECRET=<client secret value>
OAUTH2_PROXY_COOKIE_SECRET=$(python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())')
EOF
chmod 600 /opt/ohif/ohif-auth.env
```

Certificate with intermediates and key. nginx runs as uid 101 in the OHIF image (another uid if you changed it in
step 6):

```
cp server.crt server.key /opt/ohif/tls/
chown 101 /opt/ohif/tls/server.key && chmod 600 /opt/ohif/tls/server.key
```

Site values in both files are marked `ANPASSEN`:

```
grep -n ANPASSEN /opt/ohif/nginx.conf /opt/ohif/docker-compose.yml
```

- `nginx.conf`: `server_name`, certificate paths, `$arc` (container name and http port of arc), `$auth`,
  `ADMIN-GRUPPEN-ID`. If your archive AE is not `DCM4CHEE`, replace `DCM4CHEE` and `IOCM_QUALITY` in all places
  (`grep -n 'DCM4CHEE\|IOCM_QUALITY' /opt/ohif/nginx.conf`). `99DCM4CHEE` is a coding scheme, not an AE title. Leave
  it.
- `docker-compose.yml`: a fixed `ohif/app` tag (nginx 1.25.1 or newer), the path to `web/admin`, `TENANT-ID`,
  `--redirect-url`, both group IDs, `--trusted-proxy-ip` (the subnet of the Docker network, shown by
  `docker network inspect dcm4chee_default -f '{{(index .IPAM.Config 0).Subnet}}'`), and the network name.
- Different AE titles also go into `aet` and `iocmAet` of `web/admin/config.js` and into `ARC_AET`. Copy `config.js`
  out of the repository (`cp /opt/pacs-admin/web/admin/config.js /opt/ohif/config.js`), edit the copy and enable the
  commented volume line `./config.js:/srv/pacs-admin/admin/config.js:ro`. Then `git pull` does not collide with your
  changes.
- The dcm4chee UI section in `nginx.conf` is optional. To drop it, delete the block from the line
  `# ---- OPTIONAL dcm4chee-UI: dcm4chee-Oberflaeche ueber dieselbe Anmeldung` to `# ---- Ende OPTIONAL dcm4chee-UI`
  and the three-line `if ($pacs_dcm4chee_ui)` block in the `server`. The two maps marked OPTIONAL at the top can stay.
  Set `dcm4cheeUrl: ''` in `config.js` to hide the link.
- With the section in place, nginx recognizes requests of the dcm4chee UI by a `Referer` of
  `https://<host>/dcm4chee-arc/ui2/` whose host equals the host of the request, without a port. Browsers leave out
  the default port 443. If clients reach nginx on another port, add it in the map (line marked `ANPASSEN`). A proxy
  in front of nginx must pass the `Host` header unchanged, otherwise the UI gets 404 on its API calls.

If you already run OHIF behind your own nginx, take the volumes and locations from the examples into your setup
instead. The socket paths inside the container are fixed in `nginx.conf`: `/run/pacs-admin/verwaltung.sock` and
`/run/pacs-admin/protokoll.sock`.

Start the containers after the helper service (step 6), so `/run/pacs-admin` exists:

```
cd /opt/ohif && docker compose up -d
docker exec ohif nginx -t
docker exec ohif ls -l /run/pacs-admin/
```

## 10. Firewall, first start in Probelauf

The firewall filters IPv4 only. With Docker's defaults every published port is also bound to `[::]`. IPv6
connections then go through `docker-proxy` and pass the firewall, and nginx sees the Docker gateway as client address.
The Firewall tab marks such ports with "IPv6 nicht gefiltert". Publish the ports on IPv4 only. In
`/opt/dcm4chee-arc/docker-compose.yml`, bind the REST and management ports of arc to the host (nginx reaches arc
through the Docker network, `ARC_URL` uses 127.0.0.1) and DICOM and HL7 to `0.0.0.0`:

```
  arc:
    ports:
      - "127.0.0.1:8080:8080"
      - "127.0.0.1:8443:8443"
      - "127.0.0.1:9990:9990"
      - "127.0.0.1:9993:9993"
      - "0.0.0.0:11112:11112"
      - "0.0.0.0:2762:2762"
      - "0.0.0.0:2575:2575"
      - "0.0.0.0:12575:12575"
```

Then `cd /opt/dcm4chee-arc && docker compose up -d arc`. The compose example for OHIF already publishes 80 and 443 on
`0.0.0.0`. Do the same for other containers with published ports (Kibana, Portainer). The other way is to switch
IPv6 off on the host (`net.ipv6.conf.all.disable_ipv6 = 1` in `/etc/sysctl.d/`, then restart Docker). Keep the
blocking rules for 8080, 8443, 9990 and 9993 either way.

Without `PACS_DIR/firewall.json`, `firewall.py` uses the file in `FW_DEFAULT_RULES` or its built-in rule set: the
viewer ports (`FW_WEB_PORTS`, default 443 and 80) open, DICOM and HL7 (the first port of `FW_DICOM_PORTS` and
`FW_HL7_PORTS`, default 11112 and 2575) in Probelauf, 8080, 8443, 9990, 9993, 5601, 8000 and 9443 blocked, all other
ports open. The built-in set blocks the REST and management ports of dcm4chee from outside at once.

The rules work on host ports. If DICOM or HL7 reach the server on another host port, for example `104:11112` in the
dcm4chee compose file, set `FW_DICOM_PORTS=104` (or `FW_HL7_PORTS`). For the sender lists `firewall.py` translates the
host port to the port in the container through `docker ps`. If the viewer is not on 443, put its https port first in
`FW_WEB_PORTS`.

For the first start, let everything through and only log, except the REST and management ports of dcm4chee, which
stay blocked:

```
cat > /etc/pacs-admin-firewall-start.json <<'EOF'
{"aktiv": true, "standard": "probelauf", "regeln": [
  {"port": 80, "name": "Viewer und Verwaltung (http)", "modus": "offen"},
  {"port": 443, "name": "Viewer und Verwaltung", "modus": "offen"},
  {"port": 11112, "name": "DICOM", "modus": "probelauf"},
  {"port": 2575, "name": "HL7", "modus": "probelauf"},
  {"port": 8080, "name": "dcm4chee REST (http)", "modus": "gesperrt"},
  {"port": 8443, "name": "dcm4chee REST (https)", "modus": "gesperrt"},
  {"port": 9990, "name": "WildFly-Verwaltung", "modus": "gesperrt"},
  {"port": 9993, "name": "WildFly-Verwaltung (https)", "modus": "gesperrt"}
]}
EOF
echo 'FW_DEFAULT_RULES=/etc/pacs-admin-firewall-start.json' >> /etc/default/pacs-admin
set -a; . /etc/default/pacs-admin; set +a
python3 /opt/pacs-admin/server/firewall.py status
```

`status` shows the rules and the interface. The interface must be the one the clients come in on. If it is wrong or
empty, set `FW_INTERFACE`. If the file in `FW_DEFAULT_RULES` is missing or invalid, `status` stops with the error,
`pacs-firewall` does not start and the Firewall tab shows the error. Fix the file, or save once in the Firewall tab,
which writes `firewall.json` and replaces it.

```
cp /opt/pacs-admin/deploy/systemd/pacs-firewall.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now pacs-firewall
systemctl restart pacs-verwaltung
iptables -S DOCKER-USER
```

Expected line: `-A DOCKER-USER -i ens192 -j PACS-SPERRE` (with your interface).

Read the rotated dcm4chee logs once, so the DICOM and HL7 sender lists include past senders:

```
python3 /opt/pacs-admin/server/firewall.py nachholen
```

Leave the Probelauf running for a while. The Firewall tab shows under "Neu erkannt" and "Verbindungen an Regeln" who
connects to which port. The kernel log gets at most 10 lines per minute per rule, so on busy ports rare sources show up
late. Allow the sources you know, then switch ports to gesperrt one by one. The first "Speichern" writes
`PACS_DIR/firewall.json`. From then on `FW_DEFAULT_RULES` is no longer used. Every save keeps the previous version in
`PACS_DIR/firewall/`.

`systemctl stop pacs-firewall` removes the jump from `DOCKER-USER` until the next Docker start or the next save in the
Firewall tab. To switch the firewall off for good, clear "eingeschaltet" in the Firewall tab and save.

## 11. Checks

```
systemctl status pacs-verwaltung pacs-firewall --no-pager
journalctl -u pacs-verwaltung -n 50 --no-pager
python3 /opt/pacs-admin/server/firewall.py test
cat /var/log/pacs-dashboard.log
```

- The journal shows no `Protokoll nicht abgelegt` and no `absender_sammeln:` errors.
- `firewall.py test` prints `Selbsttest ok`.
- https://pacs.example.org/ asks for the login and opens the viewer.
- https://pacs.example.org/admin/ with an admin account shows disks and containers. An account in the viewer group
  only gets 403.
- Open a study in the viewer. In the Protokoll tab, "Heute" shows "Studie geöffnet". On the host:
  `python3 /opt/pacs-admin/server/pacsdb.py protokoll ereignisse $(date +%F)`.

## 12. Update

```
cd /opt/pacs-admin
git pull
git diff ORIG_HEAD -- deploy/
systemctl restart pacs-verwaltung
```

- The page is served straight from `/opt/pacs-admin/web/admin`. Browsers get the new version on the next reload.
- Carry changes in `deploy/` into `/opt/ohif/nginx.conf`, `/opt/ohif/docker-compose.yml` and
  `/etc/default/pacs-admin`. After changing `nginx.conf`: `docker exec ohif nginx -t && docker exec ohif nginx -s reload`.
- If a unit or the cron file changed, copy it again and run `systemctl daemon-reload`.
- `pacs-verwaltung` loads the new `firewall.py` on restart. `pacs-firewall.service` uses it at the next Docker start.
  To apply the rules with the new code now, run `python3 /opt/pacs-admin/server/firewall.py start` with the settings
  loaded. `iptables-restore` replaces the chain in one step, without a gap.

## 13. Uninstall

```
systemctl disable --now pacs-verwaltung
systemctl disable --now pacs-firewall          # removes the jump from DOCKER-USER, all ports open
iptables -F PACS-SPERRE
iptables -X PACS-SPERRE
rm /etc/systemd/system/pacs-firewall.service /etc/systemd/system/pacs-verwaltung.service /etc/cron.d/pacs-dashboard
systemctl daemon-reload
```

Remove the `/admin/` locations and the `access_log syslog:` lines from `nginx.conf`, remove the volumes for
`/srv/pacs-admin` and `/run/pacs-admin` from `docker-compose.yml`, then `docker compose up -d` in `/opt/ohif`.

What stays behind:

- `/var/lib/pacs-protokoll/` and `/etc/pacs-protokoll.key`: the audit log. Keep both as long as your retention rules
  require.
- `/var/lib/pacs-admin/`, `PACS_DIR/firewall.json`, `PACS_DIR/firewall/`, `/etc/default/pacs-admin`,
  `/etc/pacs-admin-firewall-start.json`, `/var/log/pacs-storage.log`, `/var/log/pacs-dashboard.log`, `/opt/pacs-admin`:
  delete when no longer needed.
- Disks set up by the assistant stay normal dcm4chee storages with their `/etc/fstab` entries.

## Configuration

All variables go into `/etc/default/pacs-admin`, one `NAME=value` per line, without `export`. Put values with spaces
or JSON in single quotes. After a change: `systemctl restart pacs-verwaltung pacs-firewall`.

| Variable | Default | Read by | Meaning |
|---|---|---|---|
| `PACS_DIR` | `/opt/dcm4chee-arc` | firewall.py, dashboard-status.py | Compose project of dcm4chee. `firewall.json` and `firewall/` (backups, sender and client lists) live here. |
| `PACS_ADMIN_VAR` | `/var/lib/pacs-admin` | dashboard-status.py | Working directory. `status/status.json` is served as `/admin/daten/status.json`. |
| `PACS_SOCKET` | `/run/pacs-admin/verwaltung.sock` | verwaltung-dienst.py | HTTP socket of the helper service. nginx expects it as `/run/pacs-admin/verwaltung.sock` in the container. |
| `PACS_LOG_SOCKET` | `/run/pacs-admin/protokoll.sock` | verwaltung-dienst.py | Datagram socket for the syslog lines from nginx. Same directory as `PACS_SOCKET`. |
| `PACS_SOCKET_UID` | `101` | verwaltung-dienst.py | Owner of both sockets: the uid of nginx in the OHIF container. No account on the host may have this uid (step 6). |
| `PROTOKOLL_DB` | `/var/lib/pacs-protokoll/protokoll.db` | pacsdb.py | Encrypted audit database. |
| `PROTOKOLL_KEY` | `/etc/pacs-protokoll.key` | pacsdb.py | Key file, 64 lowercase hex characters. |
| `ARC_URL` | `http://127.0.0.1:8080` | pacs-storage.sh | dcm4chee REST as seen from the host, used to reload the archive configuration. |
| `ARC_AET` | `DCM4CHEE` | pacs-storage.sh | Archive AE whose write list the assistant changes. Must match `aet` in `config.js` and `nginx.conf`. |
| `ARC_DEVICE` | `dcm4chee-arc` | pacs-storage.sh | Device name of dcm4chee in LDAP (`dicomDeviceName`). |
| `ARC_LOG_DIR` | `/var/local/dcm4chee-arc/wildfly/log/` | firewall.py | Host directory with the wildfly `server.log`, source of the DICOM and HL7 senders. |
| `ARC_CONTAINER` | `arc` | pacs-storage.sh | Name of the arc container, used to check that it sees and can write a new disk. |
| `LDAP_CONTAINER` | `ldap` | pacs-storage.sh | Name of the LDAP container. `ldapsearch` and `ldapmodify` run inside it with its own `LDAP_ROOTPASS`. |
| `LDAP_BASE_DN` | `dc=dcm4che,dc=org` | pacs-storage.sh | Base DN of the dcm4chee configuration. |
| `STORAGE_BASE` | `/mnt/fs` | pacs-storage.sh, dashboard-status.py | Directory with the mount points of the disks. |
| `STORAGE_PREFIX` | `PACS-Data` | pacs-storage.sh, dashboard-status.py, verwaltung-dienst.py | Name of new disks: prefix plus two-digit number, used as label, mount directory and storage ID. A letter, then letters, digits, `-` and `_`, at most 14 characters (the ext4 label holds 16 with the number); otherwise `pacs-storage.sh` stops. The helper service accepts only this prefix plus digits. The overview gets it as `prefix` in `status.json` and shows names without it. |
| `STORAGE_OWNER` | `1023:1023` | pacs-storage.sh | Owner of a new filesystem, uid:gid of wildfly in the dcm4chee image. |
| `STORAGE_MIN_GB` | `100` | pacs-storage.sh | Smallest disk in GiB the assistant offers. |
| `STORAGE_FREE_GB` | `50` | pacs-storage.sh, dashboard-status.py | Free GB needed to clear the full mark or to add a disk to the write list. The overview gets it as `frei_gb` in `status.json` and shows the two buttons only from this value on. |
| `STORAGE_WARN_GB` | `300` | dashboard-status.py | If less than this many GB are left up to the threshold on the disks of the write list, the overview asks for a new disk. The page gets it as `warn_gb` in `status.json`. |
| `STORAGE_LOG` | `/var/log/pacs-storage.log` | pacs-storage.sh | Log of the assistant. |
| `FW_INTERFACE` | interface of the default route | firewall.py | Interface the clients come in on. The first save in the Firewall tab stores it in `firewall.json` (`schnittstelle`), which then takes precedence. |
| `FW_WEB_PORTS` | `443,80` | firewall.py | Host ports of the viewer, comma-separated. The first is the https port: a save in the Firewall tab is refused if the saving PC would lose it. All are open in the built-in rule set, and the page asks before blocking them. |
| `FW_DICOM_PORTS` | `11112,2762` | firewall.py | Host ports for DICOM. The first gets the suggestions under "Neu erkannt", the client PC check and Probelauf in the built-in rule set. The sender list reads the dcm4chee log for these ports, translated to the container port through `docker ps` (for example `104:11112`). |
| `FW_HL7_PORTS` | `2575,12575` | firewall.py | The same for HL7. The three lists must not share a port, otherwise all three fall back to their defaults. |
| `FW_DEFAULT_RULES` | empty | firewall.py | JSON file in the format of `firewall.json`, used while there is no `firewall.json`. Empty: built-in rule set. |
| `FW_PORT_NAMES` | empty | firewall.py | Own port names as JSON, for example `'{"104": "DICOM (alt)"}'`, laid over the built-in names. |
| `FW_CLIENT_NAMES` | empty | firewall.py | Name patterns of client PCs for DNS lookups, comma-separated. `{a..b}` counts from a to b as in bash. If a bound has a leading zero, all numbers are padded with zeros to the width of the bounds. Example: `'PC{001..250},WS{0001..0400}'` gives PC001 to PC250 and WS0001 to WS0400. At most 100000 names per pattern. Looked up hourly. Empty: no lookups. |
| `DASHBOARD_CONTAINERS` | empty | dashboard-status.py | Containers for the Dienste tile, separated by comma or space. Empty: all containers of the Compose project in `PACS_DIR`, stopped ones shown red. |

`pacs-storage.sh` also accepts its older names as fallback: `BASE`, `PREFIX`, `OWNER`, `MIN_GB`, `FREI_GB`, `LOG`,
`AE`, `C_ARC`, `C_LDAP`. The new names take precedence, so set those. `dashboard-status.py` also reads `FREI_GB`.
`FSTAB` (default `/etc/fstab`) and `PACS_STORAGE_TEST` (set: loop devices allowed) exist for tests.

The web page reads its settings from `web/admin/config.js`: `titel`, `aet`, `iocmAet`, `dcm4cheeUrl`, `viewerUrl`,
`logo`, `locale`. An empty URL hides the link, an empty `logo` shows the title only. The logo must come from the same
origin as the page: `/admin/` sends `Cross-Origin-Embedder-Policy: require-corp`, so an image from another server
does not load. The compose example has a commented volume line that serves it as `/pacs-logo.svg`. `locale` (default
`de-DE`) sets the format of numbers and timestamps, for example `de-CH`. DICOM dates (study date, birth date) always
show as DD.MM.YYYY. An invalid tag falls back to `de-DE`. The texts stay German.

Optional: `/var/lib/pacs-admin/status/rechner.json`, a JSON object IP to PC name, for example
`{"192.0.2.50": "WS0050"}`. If it exists, the Protokoll tab shows the PC name next to the IP. Nothing in this
repository writes it.

## Troubleshooting

### The overview says "Kein Status vorhanden"

`/admin/daten/status.json` is missing. Run the job by hand and look at the output:

```
set -a; . /etc/default/pacs-admin; set +a
python3 /opt/pacs-admin/server/dashboard-status.py
cat /var/log/pacs-dashboard.log
docker exec ohif ls -l /srv/pacs-admin/status/
```

If the file exists on the host but not in the container, the volume for `/srv/pacs-admin/status` points to the wrong
directory. Disks that do not match `STORAGE_BASE/STORAGE_PREFIX<number>` are missing from the list.

### Firewall and Protokoll show "HTTP 502"

nginx cannot reach the helper service socket. Check both sides:

```
systemctl status pacs-verwaltung --no-pager
ls -l /run/pacs-admin/
docker exec ohif ls -l /run/pacs-admin/
docker logs ohif 2>&1 | grep verwaltung.sock | tail
```

- `No such file or directory` in the container while the socket exists on the host: the directory was created again
  after the container started. Run `docker restart ohif`.
- `Permission denied`: the socket owner does not match the nginx uid in the container. Set `PACS_SOCKET_UID` and
  restart `pacs-verwaltung`.

### The audit log stays empty

`pacs-verwaltung` does not start and the journal shows `libsqlcipher nicht gefunden`: install `libsqlcipher0`.

The journal shows `Protokoll nicht abgelegt (N Zeilen), neuer Versuch in 10 s:` followed by

- `No such file or directory: '/etc/pacs-protokoll.key'`: the key file is missing (step 4).
- `ist nicht 64 Hex-Zeichen (kleingeschrieben)`: the key has the wrong format.
- `file is not a database`: the key does not belong to the existing database. Put back the right key.

The service keeps the waiting lines in memory and retries every 10 seconds. A restart of the service drops them.

### /admin/ returns 403, the viewer works

oauth2-proxy does not see the admin group in the token.

- Token configuration of the app registration has the groups claim, as Group ID.
- The Object ID in `nginx.conf` (`allowed_groups=`) is the same as in the second `--allowed-group` line.
- After a change of group membership, log out at `https://pacs.example.org/oauth2/sign_out` and log in again. The
  groups are read at login.

### A new disk stops at "arc sieht ... nicht"

The page shows "Abgebrochen" with `HALT: arc sieht /mnt/fs/PACS-Data06 nicht, Archiv NICHT geaendert`. The disk is
already formatted, mounted and in `/etc/fstab`, but arc does not see the mount and the archive was not changed. Add the
volume from step 5, recreate arc, then finish the step by hand:

```
cd /opt/dcm4chee-arc && docker compose up -d arc
bash /opt/pacs-admin/server/pacs-storage.sh activate PACS-Data06 ja
```
