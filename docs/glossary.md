# Glossary

English | [Deutsch](glossary.de.md)

This page explains the words that the [install guide](install.md), the [login guide](login.md) and the [reference](reference.md)
use. Each entry is short on purpose. Where a longer explanation exists, the entry links to it.

Groups:
[the parts of the system](#terms-system) |
[login](#terms-login) |
[Docker and Linux](#terms-linux) |
[certificates](#terms-certificates) |
[DICOM and storage](#terms-dicom) |
[words on the screen](#screen-labels)

<a id="terms-system"></a>
## 1. The parts of the system

<a id="pacs"></a>
### PACS

PACS stands for picture archiving and communication system. It stores medical images and shows them to doctors. Here the PACS
is the archive dcm4chee-arc. This repository puts an admin page, a login and an audit log in front of it.

<a id="arc"></a>
### arc

`arc` is the name of the container that runs dcm4chee-arc, the archive. It is the name in the standard dcm4chee compose file.
nginx reaches the archive by this name inside the Docker network. If your container has another name, change `$arc` in
`site.conf`.

<a id="ohif"></a>
### ohif and ohif-auth

`ohif` is the name of the nginx container in the compose files of this repository. It keeps the name when no viewer is installed.
`ohif-auth` is the name of the [oauth2-proxy](#oauth2-proxy) container.

<a id="viewer"></a>
### Viewer

The viewer is the web page that shows images in the browser. This repository uses OHIF. The viewer is optional: the
administration page works without it.

<a id="front-door"></a>
### Front door

The front door is the web server in front of the admin page, the helper service, the viewer and dcm4chee. In this repository it
is nginx, in the container `ohif`. It checks the login, applies the locks that keep wrong changes out, and writes the audit log.
The nginx files are built from small parts: one [login method](#login-method), one viewer mode and one [listener](#listener).

<a id="any-account"></a>
### Any account

Any account is every account that the login lets in. It may open the viewer.

<a id="admin-account"></a>
### Admin

An admin is an account that may open `/admin/` and change data. With the login `oauth2-proxy` the admin group of the
[identity provider](#identity-provider) decides. With the login `basic` the file `admins` decides.

<a id="login-method"></a>
### Login method

The login method decides how users prove who they are. There are three. `oauth2-proxy` signs users in at an identity provider.
`basic` checks user names and passwords in files. `none` has no login and lets in only listed networks.
Guide: [login.md](login.md).

<a id="listener"></a>
### Listener

The listener is the part of the nginx files that decides how nginx accepts connections. There are three. `tls` serves HTTPS on
port 443 and redirects port 80. `plain` serves HTTP on 127.0.0.1 only, for a first look through an SSH tunnel. `behind-proxy`
serves HTTP to another web server that ends the TLS.

<a id="helper-service"></a>
### Helper service

The helper service is a small Python program (`server/verwaltung-dienst.py`) that runs as root on the server. It does the things
that nginx must not do: change the firewall, set up a new disk and store the audit log. nginx talks to it through two
[unix sockets](#unix-socket). It runs as the [systemd unit](#systemd-unit) `pacs-verwaltung`.
Install steps: [install.md#helper-service](install.md#helper-service).

<a id="audit-log"></a>
### Audit log

The audit log records who searched, which study or report was opened and what was changed in the admin page. nginx writes one
line per request and sends it through [syslog](#syslog) to the helper service. The helper service stores the lines in an
encrypted database ([SQLCipher](#sqlcipher)). Nothing is deleted. The tab is called Protokoll.
Reference: [reference.md#audit-log](reference.md#audit-log).

<a id="status-json"></a>
### status.json

`status.json` is the file with the numbers of the overview tab: services, disks and a new disk. The script
`dashboard-status.py` writes it every 5 minutes, started by [cron](#cron).

<a id="wildfly"></a>
### WildFly

WildFly is the Java application server inside the `arc` container. dcm4chee-arc runs in it. The firewall module reads its log
(`server.log`) to find the senders of images. The setting `ARC_LOG_DIR` names the folder.

<a id="ldap"></a>
### LDAP

LDAP is a directory service. dcm4chee-arc keeps its configuration in it: devices, [AE titles](#ae-title) and
[storages](#storage). The container `ldap` runs it. The disk assistant reads and changes the [write list](#write-list) there.

<a id="terms-login"></a>
## 2. Login

<a id="identity-provider"></a>
### Identity provider

An identity provider is a service that knows the users and checks their passwords. Examples are Microsoft Entra ID, Keycloak,
Authentik, Authelia, Zitadel and Google. It is often called IdP. The user types the password only at the identity provider,
never at the PACS.

<a id="oidc"></a>
### OpenID Connect (OIDC)

OpenID Connect is a sign-in standard. The identity provider checks the password and hands the application a signed token with
[claims](#claim) about the user. The application never sees the password. [oauth2-proxy](#oauth2-proxy) talks OIDC with
the identity provider.

<a id="oauth2-proxy"></a>
### oauth2-proxy

oauth2-proxy is a small open-source program that signs users in at an [identity provider](#identity-provider) and keeps the
session in a cookie. nginx asks it about every request ([auth_request](#auth-request)). It runs as the container `ohif-auth`
and has no port outside the Docker network. Guide: [login.md#login-oauth2](login.md#login-oauth2).

<a id="auth-request"></a>
### auth_request

`auth_request` is a feature of nginx. Before nginx answers a request, it sends a small request of its own to another address.
Answer 2xx lets the request pass. Answer 401 sends the user to the login. Answer 403 refuses. In this repository nginx asks
oauth2-proxy.

<a id="entra-id"></a>
### Microsoft Entra ID

Microsoft Entra ID is the cloud service of Microsoft for user accounts and sign-in. Its earlier name was Azure Active
Directory (Azure AD). Guide: [login.md#login-oauth2-entra](login.md#login-oauth2-entra).

<a id="tenant"></a>
### Tenant

A tenant is the own part of Entra ID that belongs to your organisation. It has an ID, the Directory (tenant) ID. The ID is a
GUID, for example `11111111-2222-3333-4444-555555555555`. It is part of the issuer address
`https://login.microsoftonline.com/<tenant-id>/v2.0` in the oauth2-proxy settings.

<a id="object-id"></a>
### Object ID

Entra gives every user and every group an Object ID, a GUID. The ID never changes. The name of a group can change. The compose
file and `site.conf` use the Object ID of the viewer group and of the admin group.

<a id="client-id"></a>
### Client ID

The client ID (Entra: Application (client) ID) is the public name of the app that you register at the identity provider. It is
the first line of `ohif-auth.env`.

<a id="client-secret"></a>
### Client secret

The client secret is the password of the registered app. oauth2-proxy proves with it to the identity provider that it is the
registered app. The provider shows the value once, when you create it. It expires on a date that you choose, and the login stops
on that day. It is the second line of `ohif-auth.env`.

<a id="cookie-secret"></a>
### Cookie secret

The cookie secret is a random string that oauth2-proxy uses to protect the session cookie. Make a new one for each
installation, with the command in the compose file. It is the third line of `ohif-auth.env`.

<a id="redirect-uri"></a>
### Redirect URI

The redirect URI is the address to which the identity provider sends the browser back after the sign-in, for example
`https://pacs.example.org/oauth2/callback`. You register it at the provider. It must match the address in the oauth2-proxy
setting `--redirect-url` character by character. Most providers accept only https addresses.

<a id="claim"></a>
### Claim

A claim is one piece of information that the identity provider writes into the signed token after the sign-in, for example the
name, the e-mail address or the groups of the user.

<a id="groups-claim"></a>
### Groups claim

The groups claim is the claim `groups`. It lists the groups of the user. Entra writes the [Object IDs](#object-id) of the
groups into it when the token configuration asks for it. Other providers write group names. oauth2-proxy reads the claim to
decide who may open the viewer and who is an [admin](#admin-account).

<a id="basic-auth"></a>
### Basic authentication

Basic authentication is the oldest login method of the web. The browser shows a window for user name and password and sends
them with every request. nginx checks them against [htpasswd](#htpasswd) files. There is no sign-out, no second factor and no
limit on wrong passwords. Guide: [login.md#login-basic](login.md#login-basic).

<a id="htpasswd"></a>
### htpasswd

An htpasswd file is a text file with one line per account: the user name and a hash of the password. nginx reads it for basic
authentication. This repository uses two files in `/opt/ohif/htpasswd`: `users` (all accounts) and `admins` (the
administrators). The tool `deploy/tools/pacs-adduser.sh` writes them.

<a id="keycloak"></a>
### Keycloak

Keycloak is an open-source identity provider. It can be the identity provider for oauth2-proxy. The dcm4chee images with
`-secure` in their name bring their own Keycloak and their own login. This repository does not support that setup.

<a id="terms-linux"></a>
## 3. Docker and Linux

<a id="compose-project"></a>
### Compose project

A compose project is a group of containers that one compose file starts. The name of the project is the name of the folder that
holds the file, unless the file sets another. The command `docker compose` acts on the project of the folder you are in. The
project name is the first part of the name of its networks, for example `dcm4chee-arc_default`.

<a id="external-network"></a>
### External network

An external network is a Docker network that a compose file does not create but joins. The compose files of this repository join
the network of your dcm4chee project (last block of the file, `external: true`). That is how nginx reaches `arc` by name.

<a id="bind-mount"></a>
### Bind mount

A bind mount shows a folder or a file of the server inside a container. The compose files of this repository mount folders and
not single files. A tool that replaces a single file leaves the container with the old file. A folder shows the new file at once.

<a id="uid"></a>
### uid

A uid is the number of an account in Linux. Programs in containers use the numbers of the server, not their own account names.
The nginx worker processes in the `nginx` image and in the OHIF image run as uid 101. The sockets of the helper service belong
to the uid in `PACS_SOCKET_UID` (default 101), so that nginx can use them. On the server, uid 101 can belong to another
account: `getent passwd 101` shows it.

<a id="unix-socket"></a>
### Unix socket

A unix socket is a file through which two programs on the same computer talk to each other. It replaces a network port. In
`ls -l` it starts with `s`, for example `srw-------`. The helper service has two:
`/run/pacs-admin/verwaltung.sock` (calls from the admin page) and `/run/pacs-admin/protokoll.sock` (audit lines). The nginx
container sees them through a mount of the folder `/run/pacs-admin`.

<a id="mount-propagation"></a>
<a id="rslave"></a>
### Mount propagation (rslave)

A disk that the server mounts after a container has started is normally invisible inside that container. The flag `:rslave` on
a bind mount changes that: the container receives the mounts that the server makes later below this folder. The disk assistant
needs it for the folder `/mnt/fs` of the `arc` container ([modules.md#disk-assistant](modules.md#disk-assistant)).

<a id="systemd-unit"></a>
### systemd unit

A systemd unit is a file that tells Linux how to run a service: which program, as which account, whether to restart it. The
units of this repository are `pacs-verwaltung.service` and `pacs-firewall.service` in `/etc/systemd/system/`. Useful commands
are `systemctl status NAME`, `systemctl restart NAME` and `journalctl -u NAME -n 20 --no-pager`.

<a id="cron"></a>
### cron

cron is the job scheduler of Linux. It runs the file `/etc/cron.d/pacs-dashboard` every 5 minutes. The job writes
[status.json](#status-json). cron needs its own package, `cron`.

<a id="syslog"></a>
### syslog

Syslog is a standard for log messages. nginx sends each line of the [audit log](#audit-log) as a syslog message to the helper
service through the [unix socket](#unix-socket) `protokoll.sock`.

<a id="docker-proxy"></a>
### docker-proxy

`docker-proxy` is the program in which Docker accepts a connection on a published port before it passes the connection to the
container. Over IPv6 it hides the real address of the client: nginx sees only the Docker gateway. For this reason the compose
files publish the ports as `0.0.0.0:80:8080`, which is IPv4 only.

<a id="iptables"></a>
<a id="docker-user"></a>
### iptables and DOCKER-USER

iptables is the packet filter of the Linux kernel. Docker adds rules for every port that it publishes. The chain `DOCKER-USER`
is the place for your own rules: Docker checks it before its own rules. Docker rebuilds the chain every time it starts. The
firewall of the admin page keeps its rules in the chain `PACS-SPERRE` and jumps to it from `DOCKER-USER`. The service
`pacs-firewall` sets the jump again after each start of Docker. The firewall filters only IPv4 and only ports that Docker
publishes. Guide: [modules.md#firewall](modules.md#firewall).

<a id="cidr"></a>
### CIDR

CIDR is a short way to write a network: an address, a slash and the number of fixed bits. `192.0.2.0/24` means the 256
addresses from 192.0.2.0 to 192.0.2.255. `192.0.2.17/32` means that one address.

<a id="terms-certificates"></a>
## 4. Certificates

<a id="tls-certificate"></a>
### TLS certificate

A TLS certificate lets the browser check that it talks to the real server, and it turns on https. It belongs to a host name,
for example `pacs.example.org`. It comes with a private key. The key stays secret on the server.
How to get and install one: [install.md#tls-certificate](install.md#tls-certificate).

<a id="ca"></a>
### Certificate authority (CA)

A certificate authority is an organisation that signs certificates. Examples are Let's Encrypt and the CA of your own
organisation. Browsers trust the public authorities. Your own CA works only on PCs that were set up to trust it.

<a id="certificate-chain"></a>
### Certificate chain

The certificate chain is your server certificate followed by the certificates of the authorities that signed it. nginx needs
them in one file, `server.crt`, with the server certificate first. Without the intermediate certificates some clients refuse the
connection.

<a id="intermediate-certificate"></a>
### Intermediate certificate

An intermediate certificate sits between the root certificate of the authority and your server certificate. The authority gives
it to you together with your certificate.

<a id="pem"></a>
### PEM

PEM is a text format for certificates and keys. A PEM file starts with a line such as `-----BEGIN CERTIFICATE-----`. nginx reads
only PEM.

<a id="pfx"></a>
### PFX

A PFX file (`.pfx` or `.p12`) is one binary file that holds the certificate, the chain and the private key, protected by a
password. Windows servers export this format. nginx cannot read it. Convert it with `openssl pkcs12`, see
[install.md#tls-certificate](install.md#tls-certificate).

<a id="subject-alt-name"></a>
### Subject alternative name (SAN)

The subject alternative name is the list of host names inside a certificate. Current browsers check the host name against this
list and ignore the older field CN. A certificate without a SAN is refused, also a self-signed one.

<a id="self-signed"></a>
### Self-signed certificate

A self-signed certificate is signed by its own key. No authority vouches for it, so browsers show a warning. It is good for a
test and not for daily use.

<a id="terms-dicom"></a>
## 5. DICOM and storage

<a id="dicom"></a>
### DICOM

DICOM is the standard for medical images and for the way devices send them over the network. A device that makes images is a
[modality](#modality). The archive listens for DICOM on its own port.

<a id="hl7"></a>
### HL7

HL7 is a standard for messages between hospital systems, for example patient and admission data. The archive listens for HL7
on its own port.

<a id="modality"></a>
### Modality

A modality is a device that makes images, for example a CT, an ultrasound or an X-ray unit. The column Mod. in the list of
studies shows its code.

<a id="ae-title"></a>
### AE title

An AE title (application entity title) is the name of a DICOM device. It has up to 16 characters. A modality and the archive
know each other by these names. The AE title of the archive is `DCM4CHEE` by default. It appears in `config.js` (`aet`), in
`/etc/default/pacs-admin` (`ARC_AET`) and in the nginx files. The tool `deploy/tools/set-aet.sh` renames it in all places that
belong to this repository. Reference: [reference.md#ae-title](reference.md#ae-title).

<a id="iocm-quality"></a>
### IOCM_QUALITY and 113001^DCM

IOCM stands for Imaging Object Change Management, a DICOM way to hide images without deleting them. When the admin page rejects
a study, dcm4chee-arc stores a rejection note with the code `113001^DCM` (Rejected for Quality Reasons) and hides the study.
`IOCM_QUALITY` is the AE title of the view that shows the rejected studies. There the admin page can restore a study or delete
it for good. The setting is `iocmAet` in `config.js`.

<a id="coding-scheme-99dcm4chee"></a>
### 99DCM4CHEE

`99DCM4CHEE` is the name of a DICOM coding scheme, a table of codes. It is not an AE title. It is part of the call that restores a
rejected study. Leave it as it is when you rename the AE title.

<a id="storage"></a>
### Storage

A storage is a place where dcm4chee-arc keeps image files. In this setup each storage is one disk, mounted below `/mnt/fs` with
a name such as `PACS-Data01` or `PACS-Data02` (settings `STORAGE_BASE` and `STORAGE_PREFIX`). Each storage is also an entry in
the configuration of the archive in [LDAP](#ldap). Each storage has a threshold: the free space that must stay. Below the
threshold the archive counts the storage as full.

<a id="write-list"></a>
### Write list

The write list is the ordered list of storages that receive new images. New images go to the first storage of the list. When
that storage is full, they go to the next one. The overview tab shows the order ("neue Bilder jetzt", "neue Bilder als 2.").
Guide: [modules.md#disk-assistant](modules.md#disk-assistant).

<a id="sqlcipher"></a>
### SQLCipher

SQLCipher is SQLite with encryption. The audit log is stored in such a database, in `/var/lib/pacs-protokoll/protokoll.db`. The
key is in the file `/etc/pacs-protokoll.key`. The helper service needs the library: the package `libsqlcipher1` on Debian 13, and
`libsqlcipher0` on Debian 12 and older. Back up the key: without it the stored lines cannot be read.
Steps: [install.md#audit-key](install.md#audit-key).

<a id="screen-labels"></a>
## 6. Words on the screen

The admin page is in German. This table lists the labels that the guides name, with their English meaning. The guides write the
German label in `code` and give the English meaning at the first use.

<a id="screen-tabs"></a>
### Tabs and links in the top bar

| Label | Meaning |
|---|---|
| `Übersicht` | Overview: services, firewall summary, disks, latest changes |
| `Studien` | Studies: search, edit, move, reject |
| `Patienten` | Patients: search, correct, merge |
| `Firewall` | Firewall: who may reach which port of the server |
| `Protokoll` | Audit log: who searched, opened or changed what |
| `dcm4chee` | Link to the dcm4chee user interface |
| `Viewer` | Link to the OHIF viewer |
| `Abmelden` | Sign out (shown only when `abmeldenUrl` is set) |

<a id="screen-overview"></a>
### Overview tab

| Label | Meaning |
|---|---|
| `Dienste` | Services: one badge per container; `aus` after the name means the container is not running |
| `Speicher` | Storage: the disks, with free space |
| `Letzte Änderungen` | Latest changes made through the admin page |
| `neue Bilder jetzt` | New images go to this disk now |
| `neue Bilder als 2.` | New images go to this disk after the disks in front of it are full (here: second place) |
| `als voll markiert` | Marked as full |
| `Markierung entfernen` | Remove the mark "full" |
| `In Schreibliste aufnehmen` | Add to the [write list](#write-list) |
| `Aus Schreibliste nehmen` | Remove from the write list |
| `nicht eingehängt, bitte prüfen` | Not mounted, please check |
| `Neue Festplatte` | New disk: appears when the server has found an empty disk |
| `Als PACS-Data02 einrichten …` | Set up as PACS-Data02 |
| `Formatieren und einrichten` | Format and set up |
| `Jetzt suchen` | Search now |
| `Kein Status vorhanden (dashboard-status.py läuft per cron alle 5 Minuten).` | No status available (the status script runs by cron every 5 minutes) |
| `Sitzung abgelaufen, Seite neu laden (F5)` | Session expired, reload the page (F5) |

<a id="screen-firewall"></a>
### Firewall tab

<a id="probelauf"></a>
<a id="offen"></a>
<a id="gesperrt"></a>

Every port has one of three modes. The setting `Ports ohne eigene Regel` gives the mode for all ports without their own rule,
also for ports that Docker publishes in the future.

| Label | Meaning |
|---|---|
| `gesperrt` | Blocked: only the listed hosts and networks pass. All others are rejected. |
| `Probelauf` | Trial run: everyone passes. A source that is not listed appears under `Neu erkannt`. Use it before you block. |
| `offen` | Open: everyone passes. |
| `Ports ohne eigene Regel` | Ports without their own rule: the mode for all other ports |
| `eingeschaltet` | Switched on: the checkbox that turns the whole firewall on |
| `wirksam` / `nicht wirksam` / `ausgeschaltet` | Effective / not effective / switched off |
| `Neu erkannt` | Newly detected: devices, senders and connections that no rule lists yet |
| `Erlauben` | Allow: add the source to the rule of its port |
| `Ausblenden` | Hide: take the entry out of the list until you choose `Wieder anzeigen` |
| `Wieder anzeigen` | Show again |
| `Speichern` | Save: applies all changes at once |
| `Verwerfen` | Discard the changes that are not saved |
| `Neu laden` | Reload |
| `Hinzufügen` | Add |
| `IPv6 nicht gefiltert` | IPv6 not filtered: Docker publishes the port over IPv6 too, and the firewall filters only IPv4 |

<a id="screen-audit"></a>
### Audit log tab

| Label | Meaning |
|---|---|
| `Von` / `Bis` | From / To (dates) |
| `Heute`, `7 Tage`, `30 Tage` | Today, 7 days, 30 days |
| `Anzeigen` | Show |
| `Als CSV speichern` | Save as CSV file |
| `Patienten-ID` | Patient ID: shows only the entries about this patient |
| `Patientenname` | Patient name: shows only the entries about patients with this name. The start of the name is enough. The field shows the hint `Nachname` (family name) |
| `Konto` | Account: a part of the sign-in name is enough. The field shows the hint `Teil der Anmeldung` (part of the sign-in) |
| `(ohne Konto)` | Without account |
| `PC` | The computer that made the request: a part of its name or IP address is enough. The field shows the hint `Name oder IP` (name or IP address) |
| `Art` | Type of line: `alle` (all), `Studie geöffnet` (study opened), `Bericht geöffnet` (report opened), `Suche` (search), `Verwaltung` (administration), `nur Abgelehntes und Fehler` (only refused requests and errors) |
| `Text in Aktion und Details` | Text in action and details: shows only the entries that contain this text in the action, the details or the study. The field shows the hint `z. B. Accession, Beschreibung` (for example accession number, description) |
| `Zeit` | Table column Time: the time of day. The day is a line of its own above the entries of that day |
| `Wer` | Table column Who: the account without the part after the `@`, and below it the PC |
| `Was` | Table column What: the action as a coloured badge (changes and refused requests stand out), and below it one line for each detail |
| `Patient` | Table column Patient: the patient name, and below it the patient ID |
| `Studie` | Table column Study: date, modality and accession number of the study, or the study UID when the archive does not know the study |
