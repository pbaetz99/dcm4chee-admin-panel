# dcm4chee-admin-panel

English | [Deutsch](README.de.md)

An admin page for a dcm4chee-arc-light PACS that runs in Docker Compose. It is one static page, served by the nginx
that already serves the OHIF viewer, behind oauth2-proxy. A small helper service on the host does what a browser
cannot: add disks to the archive, manage iptables rules for the Docker ports and keep an encrypted audit log.

The user interface is in German.

## Screenshots

![Übersicht: disks, write list, containers, firewall](docs/screenshots/overview.png)

![Firewall: ports, modes, newly detected sources](docs/screenshots/firewall.png)

![Protokoll: audit log with filters](docs/screenshots/protokoll.png)

![Studien: search and edit studies](docs/screenshots/studien.png)

## Features

### Übersicht (overview)

- Disks of the archive with fill level and free space, and which disk gets new images now and which ones follow.
  The order is the write list of the archive AE (`dcmObjectStorageID` and `dcmMetadataStorageID`). Below
  `STORAGE_WARN_GB` (default 300 GB) left up to the threshold, the page asks for a new disk.
- Write list:
  - "In Schreibliste aufnehmen" adds a disk at the end of the list.
  - "Aus Schreibliste nehmen" removes a disk from the list. Its images stay readable. The page hides the button on
    the last disk that takes new images, and `pacs-storage.sh` refuses to remove the last storage that is not marked
    full.
  - "Markierung entfernen" clears the full mark (`dcmStorageThresholdExceeded`) that dcm4chee sets at the threshold.
  - Adding and clearing need at least `STORAGE_FREE_GB` free on the disk (default 50 GB). The page shows the two
    buttons only on disks with at least that much free space (`frei_gb` in `status.json`), and `pacs-storage.sh`
    checks it again.
- New disk: give the server (or VM) a blank disk. It shows up within 5 minutes, or at once with "Jetzt suchen". After
  you confirm, `pacs-storage.sh` formats it as ext4, mounts it under `STORAGE_BASE`, adds it to `/etc/fstab`, creates
  the storage in LDAP as a copy of the current one and appends it to the write list. The page shows each step and the
  script output.
- Containers of the dcm4chee Compose project, running or stopped.
- Firewall tile: on or off, default mode, number of newly detected sources.
- The last 15 changes made through the page, with account.

### Studien (studies)

- Search by patient ID, name, accession number and date range. Newest first, up to 200 results.
- Edit description, accession number, study date and referring physician. dcm4chee keeps the old values in the
  Original Attributes Sequence.
- Move a study to another patient. Name and birth date of the target patient stay as they are.
- Reject a study (`113001^DCM`). In the view of rejected studies: restore, or delete permanently. Deleting asks you to
  type the accession number (or the patient ID) first.

### Patienten (patients)

- Search by patient ID and name, up to 100 results.
- Edit name, birth date and sex. The page sends the whole record back, so address and other attributes stay.
- Merge two patient entries.

### Firewall

- iptables rules for every port Docker publishes. Per port one mode: offen (everyone), Probelauf (dry run: everyone
  gets through, sources not on the list are logged) or gesperrt (only listed IPv4 addresses and networks).
- A default mode for ports without a rule, which also covers ports published later.
- Ports that Docker also publishes on IPv6 get the badge "IPv6 nicht gefiltert", see [Limitations](#limitations).
- DICOM, HL7 and viewer ports are settings (`FW_DICOM_PORTS`, `FW_HL7_PORTS`, `FW_WEB_PORTS`), for sites that
  publish DICOM on 104 or the viewer on another port.
- "Neu erkannt" lists sources that were seen but are not allowed for their port, with "Erlauben" and "Ausblenden".
  Sources come from the dcm4chee `server.log` (DICOM and HL7 senders), from the kernel log (connections logged by the
  rules, last 7 days) and from client PC discovery.
- Client PC discovery looks up DNS names built from patterns such as `WS{0001..0400}` (`FW_CLIENT_NAMES`) and
  suggests one /24 per network for DICOM. Empty pattern: no lookups, and the card is hidden.
- Counters of new connections per port and source.
- Changes apply on "Speichern". The service refuses a rule set that would lock the saving PC out of the https port
  (443), keeps the previous version in `PACS_DIR/firewall/` and goes back to it if applying fails.

### Protokoll (audit log)

- Who searched for studies or patients, who opened which study or report (in the viewer, on this page or in the
  dcm4chee UI section), and every change made through the page, with account, PC and time.
- Filters: date range, patient ID, patient name, account, PC, type of entry, free text. The same account with the same
  study or search within 30 minutes counts as one entry.
- CSV export for Excel (semicolon, UTF-8 with BOM).
- Stored encrypted with SQLCipher on the server. Every single request is stored too (source `zugriffe`) and can be
  read with `server/pacsdb.py`.

The header links to the dcm4chee UI and to the viewer. Title, AE titles, links, an optional logo and the locale for
numbers and timestamps come from `web/admin/config.js`.

## How it works

```
Browser --https--> nginx in the OHIF container --auth_request--> oauth2-proxy --> Entra ID or other OIDC
                     |
                     +-- /admin/          static page (web/admin, read-only mount)
                     +-- /admin/daten/    status.json, written by dashboard-status.py (cron, every 5 minutes)
                     +-- /admin/dienst/   unix socket --> verwaltung-dienst.py (root, on the host)
                     |                                      +-- pacs-storage.sh  disks, LDAP
                     |                                      +-- firewall.py      iptables
                     |                                      +-- pacsdb.py        audit log (SQLCipher)
                     +-- /dcm4chee-arc/   allow-listed REST calls --> dcm4chee-arc
                     +-- access_log syslog --> unix socket --> verwaltung-dienst.py --> audit log
```

- The page is plain HTML, JavaScript and CSS. No build step, no CDN, no external fonts. nginx serves it straight from
  the repository directory.
- Login: every request goes through `auth_request` to oauth2-proxy. The viewer needs one of the allowed groups.
  `/admin/` and every changing dcm4chee call need the admin group.
- dcm4chee REST: nginx passes only the calls the viewer and the page use. Everything else under `/dcm4chee-arc/`
  returns 404. Changes need the admin group and the `X-PACS-Admin` header, which the page sets with a readable
  description for the log. nginx adds these locks:
  - study update only with a `StudyInstanceUID` (without it dcm4chee updates all studies)
  - move to another patient only with `updatePolicy=PRESERVE` (otherwise dcm4chee overwrites the target patient)
  - patient update never with `merge`
  - permanent delete only through the AE `IOCM_QUALITY`, where dcm4chee deletes only rejected studies
- Helper service: `server/verwaltung-dienst.py` runs as root on the host and listens only on a unix socket. nginx
  passes the account in `X-Auth-User` and the client IP in `X-Real-IP`. The service runs `pacs-storage.sh` for disks
  and `firewall.py` for iptables, and reads the audit log.
- Audit log: nginx sends one JSON line per request by syslog to a second unix socket. The service collects the lines
  and writes them to the SQLCipher database every 2 seconds. Sources: `zugriffe` (every request with account),
  `ereignisse` (study and patient searches, opened studies), `admin` (changes, with description and new values).
- `server/dashboard-status.py` runs from cron every 5 minutes and writes `status.json`: disks, blank disks,
  containers. No patient data.
- `server/firewall.py` keeps its rules in the chain `PACS-SPERRE`, jumped to from `DOCKER-USER` for the outside
  interface. `pacs-firewall.service` applies them after every Docker start.
- Optional: a section in the nginx example serves the dcm4chee UI through the same login, without Keycloak, for the
  admin group only. Changes made there go into the audit log.

## Requirements

- dcm4chee-arc-light in Docker Compose, running without Keycloak (image `dcm4chee-arc-psql`, not the `-secure`
  variants). nginx and oauth2-proxy do the access control.
- Linux host with systemd, Python 3.7 or newer (standard library only), Docker with the compose plugin, iptables, cron.
- `libsqlcipher0` (Debian/Ubuntu package) for the audit log.
- For the disk assistant: util-linux, e2fsprogs, curl. The LDAP container needs its root password in its own
  environment (`LDAP_ROOTPASS` or `LDAP_ROOTPASS_FILE`). The arc container needs `STORAGE_BASE` mounted with
  `:rslave`.
- The OHIF image (nginx 1.25.1 or newer) and oauth2-proxy. The compose example sets up both.
- An OIDC provider with a groups claim. Tested with Microsoft Entra ID.

## Quick start

[docs/install.md](docs/install.md) goes through every step. In short:

1. Clone the repository to `/opt/pacs-admin` and copy `deploy/pacs-admin.env.example` to `/etc/default/pacs-admin`.
2. Install `libsqlcipher0` and create the key for the audit log.
3. Install `pacs-verwaltung.service` and the cron job.
4. Register the app in Entra ID, fill in the compose and nginx examples, start the OHIF container.
5. Start the firewall in Probelauf, with the dcm4chee REST and management ports blocked, and tighten it later in the
   Firewall tab.

## Demo

```
python demo/serve.py
```

Open http://localhost:8000/admin/. The demo serves `web/` and loads `demo/mock.js`, which answers every request of
the page with made-up data inside the browser. No dcm4chee, nginx or helper service needed. Changes last until you
reload the page.

- `python demo/serve.py 8080` uses another port.
- `http://localhost:8000/admin/?demo=platte` shows a blank disk ready to be set up.
- `http://localhost:8000/admin/?demo=offen#firewall` opens all cards in the Firewall tab.

## Limitations

- The UI is German only. The docs are English and German.
- Tested with dcm4chee-arc-light 5.35.1, Debian 10, Docker 26 and iptables-nft.
- The firewall covers only ports that Docker publishes, for IPv4 traffic coming in over one interface. It does not
  cover SSH, other host services, or traffic from the host itself and from Docker networks.
- With Docker's defaults a published port is also bound to `[::]`. IPv6 connections then reach the container through
  `docker-proxy`, past the firewall, whatever the Firewall tab says for that port. The tab marks such ports with
  "IPv6 nicht gefiltert". Publish ports on IPv4 only or switch IPv6 off on the host
  ([install guide, step 10](docs/install.md#10-firewall-first-start-in-probelauf)).
- Client PC discovery works only by DNS name pattern. PCs without a predictable name show up only through their
  connections.
- The DICOM and HL7 sender lists parse the dcm4chee `server.log` for the ports in `FW_DICOM_PORTS` and `FW_HL7_PORTS`
  (default 11112, 2762, 2575 and 12575), translated to the container port through `docker ps`.
- The disk assistant formats whole disks as ext4, never partitions. The page offers only the blank disks that
  `pacs-storage.sh kandidaten` lists, and the helper service accepts only the device names `/dev/sd*`, `/dev/vd*`,
  `/dev/xvd*` and `/dev/nvme*n*`. Storage ID, filesystem label and mount directory share one name (`STORAGE_PREFIX`
  plus number). Storages named differently do not appear in the overview.
- One archive AE per installation.
- The audit log is never pruned. Plan disk space and retention yourself.

## Security notes

- The helper service runs as root and trusts `X-Auth-User` and `X-Real-IP`. Only nginx may reach its socket. The
  service creates both sockets with owner `PACS_SOCKET_UID` and mode 0600. Mount the socket directory only into the
  nginx container. The uid is the only protection of the sockets and the TLS key, so no account on the host may have
  it: `getent passwd 101` must print nothing ([install guide, step 6](docs/install.md#6-helper-service)).
- nginx replaces `X-Auth-User` and `X-Real-IP` sent by the browser before it passes a request to the helper service,
  and strips `X-PACS-Admin` before it passes a change on. A change through `/admin/dienst/` or through the allow-listed
  dcm4chee calls without `X-PACS-Admin` gets 403. Pages from other origins cannot set this header, because nginx
  answers no CORS preflight on these paths.
- The optional dcm4chee UI section sends every request under `/dcm4chee-arc/` whose `Referer` starts with
  `https://<host of the request>/dcm4chee-arc/ui2/` (no port, that is 443) to the full dcm4chee API. There the locks
  listed under [How it works](#how-it-works) and the `X-PACS-Admin` check do not apply, the admin group check does.
  The map compares the host in the `Referer` with `$host`. A `Referer` with another host, with a port, over http, or no
  `Referer` at all leaves the request with the locked locations. Browsers let a page send only a `Referer` of its own
  origin (scheme, host and port). Another service on the same host name, for example Portainer on 9443, is another
  origin, and its `Referer` carries the port. A logged-in admin can set any `Referer` with curl and gets the same
  access as through the dcm4chee UI. Without the section (the `if ($pacs_dcm4chee_ui)` block removed) only the
  allow-listed calls reach dcm4chee.
- dcm4chee runs without its own authentication. Anyone who reaches arc on 8080 or 8443 directly can read and change
  everything. Publish these ports on 127.0.0.1 only (nginx reaches arc through the Docker network), keep them blocked
  from outside (the built-in firewall rule set does) and keep them off other networks. A port that Docker also binds
  to `[::]` is open over IPv6, see [Limitations](#limitations).
- The audit database is encrypted with the raw 256-bit key in `PROTOKOLL_KEY`. Keep the key file root-only (0600) and
  keep an offline copy. Without the key the log cannot be read. The log contains patient IDs and names from search
  URLs. Treat it like patient data.
- nginx writes no access log to `docker logs`, because URLs contain patient data.
- Narrow `--trusted-proxy-ip` of oauth2-proxy to the subnet of the Docker network. Sessions end after 12 hours
  (`--cookie-expire`) and are not refreshed.
- The lock-out check on firewall saves covers only the saving PC and the https port (the first of `FW_WEB_PORTS`).
  It skips addresses in the Docker networks: over IPv6 nginx sees the Docker gateway, not the PC.

## License

MIT, see [LICENSE](LICENSE).
