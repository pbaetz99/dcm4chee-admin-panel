# nginx for the PACS admin panel

nginx is the front door of the admin panel. It checks who may come in, serves the page, passes calls to the helper service
and to dcm4chee-arc with locks that keep wrong changes out, and writes the audit log. The configuration is **one core
file that you never edit** plus a few small files that you pick: one **login**, one **viewer** mode and one **listener**.
You edit exactly one small file (`site.conf`) with your own values.

- [Recipes: I want X, copy these files](#recipes)
- [Copy commands](#copy-commands)
- [Placeholders (CHANGE-ME)](#placeholders)
- [Mount points for the compose file](#mount-points)
- [The choices in detail](#choices): [login](#login), [viewer](#viewer), [listener](#listener), [dcm4chee UI section](#dcm4chee-ui)
- [nginx on the host instead of a container](#host-nginx)
- [AE titles](#ae-titles)
- [Changes against the old single file](#upgrade)
- [What the configuration guarantees](#guarantees)
- [Checks and troubleshooting](#checks)
- [Test lab](#lab)

## Layout

```
deploy/nginx/
  pacs.conf               core: log formats, maps, the server block with every location and lock (never edited)
  site.conf.example       your values: copy it to pacs/site.conf and edit it (the only file you edit on nginx 1.25.1 or newer)
  common/                 shared pieces, copied as they are: proxy.conf  headers.conf  audit-write.conf
  login/oauth2-proxy/     login with oauth2-proxy (Entra ID, Keycloak, Authentik, Google, GitHub ...)
  login/basic/            login with HTTP basic auth (two htpasswd files: all accounts / admins)
  login/none/             no login, only a list of allowed networks
                          each of the three has four files: http.conf  server.conf  locations.conf  admin.conf
  viewer/ohif.conf        OHIF viewer plus the DICOMweb reads only the viewer needs
  viewer/none.conf        admin panel only: "/" redirects to /admin/
  listener/tls/           https on this nginx (and http -> https redirect)       two files: http.conf  server.conf
  listener/plain/         plain http, for a first look through an SSH tunnel
  listener/behind-proxy/  plain http behind a proxy that ends TLS (Traefik, Caddy, Apache, Cloudflare Tunnel)
  optional/dcm4chee-ui.conf   the dcm4chee user interface behind the same login (optional)
```

What you build and mount into the nginx container (the folder `/opt/ohif/nginx` is only an example):

```
/opt/ohif/nginx/              mounted read only as /etc/nginx/conf.d
  pacs.conf                   the core
  pacs/
    site.conf                 your values
    proxy.conf  headers.conf  audit-write.conf            shared pieces
    viewer.conf                                           the chosen viewer
    login/    http.conf server.conf locations.conf admin.conf   the chosen login
    listener/ http.conf server.conf                       the chosen listener
    optional/dcm4chee-ui.conf                             delete this file to switch the section off
```

How the pieces fit: `pacs.conf` includes `login/http.conf` and `listener/http.conf` in the http block (log account name, http to
https redirect, Referer rule), and `site.conf`, `listener/server.conf`, `login/server.conf`, `login/locations.conf`,
`optional/*.conf` and `viewer.conf` in the server block. Every location that is for admins only includes **one** file,
`login/admin.conf`, as its login check: that file holds the whole difference between "admin" and "any account", for
every login method. Locations that are for any account use the check of `login/server.conf` that they inherit.

<a id="recipes"></a>
## Recipes: I want X, copy these files

| I want | login | viewer | listener | also needed |
|---|---|---|---|---|
| Entra ID (or Keycloak, Authentik, Authelia, Zitadel, Google, GitHub) with oauth2-proxy, OHIF viewer, https on this server | `oauth2-proxy` | `ohif` | `tls` | oauth2-proxy container, certificate, admin group in `site.conf` |
| the same, admin panel only (no viewer, plain `nginx` image) | `oauth2-proxy` | `none` | `tls` | as above |
| no OAuth proxy: user name and password in nginx (two htpasswd files), OHIF viewer, https | `basic` | `ohif` | `tls` | certificate, htpasswd files `users` and `admins` |
| the same, admin panel only | `basic` | `none` | `tls` | as above |
| a first look on 127.0.0.1 without TLS through an SSH tunnel | `basic` | `none` (or `ohif`) | `plain` | htpasswd files; publish the port on 127.0.0.1 only |
| an existing TLS proxy (Traefik, Caddy, Apache, Cloudflare Tunnel) stays in front, nginx keeps login and locks | any | any | `behind-proxy` | proxy network in `listener/server.conf`; reach nginx only from the proxy |
| no login at all, only a list of PCs that may come in | `none` | any | any | the two network lists of `login/none/` |
| nginx installed on the host instead of a container | any | `none` (OHIF files come with the OHIF image) | `tls` | [host steps](#host-nginx) |

Not supported: dcm4chee with its own Keycloak (the `-secure` images: nginx sends no token to arc), and replacing nginx by Traefik,
Caddy or Cloudflare Access (the locks, the helper socket and the audit log are done by nginx; those products can only stand
in front of it, recipe `behind-proxy`).

<a id="copy-commands"></a>
## Copy commands

Step 1 is the same for every recipe. `N` is this folder of the repository, `T` is your copy, the folder that the compose file
mounts as `/etc/nginx/conf.d`.

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

The last line is the optional dcm4chee UI section; leave it out, or later `rm $T/pacs/optional/dcm4chee-ui.conf`, to switch it off.

Step 2: the login. Copy exactly one of the three.

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

Step 3: the viewer. Copy exactly one.

<!-- lab:viewer=ohif -->
```bash
cp $N/viewer/ohif.conf $T/pacs/viewer.conf
```

<!-- lab:viewer=none -->
```bash
cp $N/viewer/none.conf $T/pacs/viewer.conf
```

Step 4: the listener. Copy exactly one.

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

Step 5: edit `$T/pacs/site.conf` (and the files named in [Placeholders](#placeholders)), then check. The two values of `site.conf`
can be set in one go (the lines are replaced together with their marker comment; use your own name and group id):

```bash
sed -E -i -e 's/^(server_name +)[^;]+;.*/\1pacs.yourdomain.example;/' \
          -e 's/^(set \$pacs_admin_group +)[^;]+;.*/\1YOUR-ADMIN-GROUP-ID;/' $T/pacs/site.conf
```

Then check:

```bash
grep -rn CHANGE-ME $T          # must print nothing
docker exec ohif nginx -t      # once the container runs: "syntax is ok" and "test is successful"
```

Before the first start the same check works in a throw-away container (listener `tls`; with `plain` or `behind-proxy` leave out the second `-v`):
`docker run --rm -v $T:/etc/nginx/conf.d:ro -v /opt/ohif/tls:/etc/nginx/tls:ro nginx:1.30 nginx -t`.

The commands to run after a change of the files are `docker exec ohif nginx -t` and `docker exec ohif nginx -s reload` (the container
name `ohif` is the one of the compose example). Nothing is edited inside the container: the folder is mounted read only.

<a id="placeholders"></a>
## Placeholders (CHANGE-ME)

Every value you must change carries the marker `CHANGE-ME` in a comment on the same line. Replace the value **and delete the
comment with the marker**; `grep -rn CHANGE-ME $T` must then print nothing. A placeholder that is left in still passes
`nginx -t` (every example value is well-formed), so check with the grep. The example admin group and the example networks of login
`none` fail closed: nobody gets in by them. The shipped `set_real_ip_from 203.0.113.1` is an address from the documentation range (RFC 5737) and trusts nobody: while it stays,
nginx takes the address of the connection as the client address, and the audit log shows the proxy for every client. Put the address
of your proxy container there (`docker inspect PROXY`), at most the subnet nginx shares with it.

| File in `pacs/` | What | Needed for |
|---|---|---|
| `site.conf` | `server_name`: the name users type in the browser | always |
| `site.conf` | `set $pacs_admin_group`: Entra ID object id of the admin group, or the group name of another OIDC provider | login `oauth2-proxy` (with `basic` and `none` ignore the line or delete it, with its marker) |
| `login/server.conf` | `allow`: network of the PCs that may open the viewer | login `none` |
| `login/admin.conf` | `allow`: network or address of the administrator PCs | login `none` |
| `listener/server.conf` | `set_real_ip_from`: the address of the proxy in front, or its Docker network | listener `behind-proxy` |

Values that usually stay as they are, but you should look at them once (`site.conf`, no marker):

| Value | Default | Change it when |
|---|---|---|
| `set $arc` | `http://arc:8080` | your dcm4chee-arc container has another name or http port (`docker ps`); host nginx: `http://127.0.0.1:8080` |
| `resolver` | `127.0.0.11` (DNS of Docker) | host nginx with an IP address above: delete the line |
| `set $pacs_auth` | `http://ohif-auth:4180` | the oauth2-proxy service has another name or port |

The certificate paths are not in `site.conf`: `ssl_certificate` and `ssl_certificate_key` are the last two lines of `listener/server.conf`
of the listener `tls` (`/etc/nginx/tls/server.crt` and `server.key`; change them when the certificate is somewhere else, host nginx:
the Let's Encrypt paths). The listeners `plain` and `behind-proxy` have no such lines and need no `tls` folder.

<a id="mount-points"></a>
## Mount points for the compose file

Paths inside the nginx container. These are fixed, the files above refer to them; the host paths are examples.

| In the container | Content | Host path (example) | Mount | When |
|---|---|---|---|---|
| `/etc/nginx/conf.d` | the folder `$T` with `pacs.conf` and `pacs/` | `/opt/ohif/nginx` | `:ro` | always |
| `/etc/nginx/tls` | `server.crt` (full chain) and `server.key` | `/opt/ohif/tls` | `:ro` | listener `tls` |
| `/etc/nginx/htpasswd` | the files `users` (all accounts) and `admins` | `/opt/ohif/htpasswd` | `:ro` | login `basic` |
| `/srv/pacs-admin/admin` | `web/admin` of this repository | `/opt/pacs-admin/web/admin` | `:ro` | always |
| `/srv/pacs-admin/status` | `status.json` of `dashboard-status.py` | `/var/lib/pacs-admin/status` | `:ro` | always |
| `/run/pacs-admin` | the sockets `verwaltung.sock` and `protokoll.sock` of the helper service | `/run/pacs-admin` | `:ro` | always |
| `/usr/share/nginx/html/app-config.js` | OHIF configuration | `/opt/ohif/app-config.js` | `:ro` | viewer `ohif` |
| `/etc/localtime` | local time in the audit log | `/etc/localtime` | `:ro` | recommended |

- Mount the **folders** `conf.d` and `htpasswd`, not single files: a file that is replaced (`sed -i`, `mv`) can keep its old content
  inside the container when it was mounted as a single file, a folder shows the new file at once.
- Published ports: listener `tls` publishes `80:8080` and `443:8443`; listener `plain` only `127.0.0.1:8080:8080`;
  listener `behind-proxy` publishes nothing and joins the Docker network of the proxy.
- Mounting a folder over `/etc/nginx/conf.d` replaces the `default.conf` of the image, which is what you want. The start script of
  the nginx image then prints `default.conf is not a file or does not exist`; that message is harmless.
- The sockets are owned by `PACS_SOCKET_UID` (helper service), which must be the uid of the nginx worker processes: 101 in the
  `nginx` image and in the OHIF image. A mismatch shows as 502 on `/admin/dienst/` and as missing audit lines.
- nginx 1.25.1 or newer (`http2 on`); the image needs the modules `http_ssl`, `http_v2`, `http_realip` (listener `behind-proxy`),
  `http_auth_request` (login `oauth2-proxy`) and `http_gunzip` / `http_gzip_static` (viewer `ohif`). The official `nginx` image has all of them.

<a id="choices"></a>
## The choices in detail

<a id="login"></a>
### Login

All three give nginx an account name for the audit log (`u`) and for the helper service (`X-Auth-User`), never empty: a request
that is refused before the login check ran (a lock, a missing `X-PACS-Admin`, a `;` in the path) is logged as `anon-<client address>`
with oauth2-proxy and `none`, and with the name the client claimed with `basic`.

**oauth2-proxy** (`login/oauth2-proxy/`). nginx asks oauth2-proxy for every request (`auth_request`). oauth2-proxy must run with
`--set-xauthrequest=true` and `--reverse-proxy=true`. Viewer level = any account that oauth2-proxy lets in (its `--allowed-group`
flags); admin level = the group in `site.conf` (`$pacs_admin_group`, used in exactly one place, the location `/oauth2/auth-admin`
in `login/locations.conf`). An empty group is refused instead of meaning "everybody". For a provider without groups (Google)
change the query name in that one line to `allowed_emails=` and put the comma-separated e-mail addresses into
`$pacs_admin_group` (not tested end to end). The page shows the account name from `/oauth2/userinfo`, which nginx passes on.

**basic** (`login/basic/`). nginx checks user name and password itself (`auth_basic`), with two files in `/etc/nginx/htpasswd/`:
`users` has every account (also the admins), `admins` only the administrators. An account in `users` only can use the viewer; on
`/admin/` it gets 401 again and the browser asks for the password once more (basic auth cannot answer 403). Create the files with
`bash deploy/tools/pacs-adduser.sh`, or by hand: `printf '%s:%s\n' NAME "$(printf '%s' 'PASSWORD' | openssl passwd -6 -stdin)" >> users`
(admins: in both files). Both write sha512-crypt (`$6$`, needs OpenSSL 1.1.1 or newer; the script falls back to apr1 with a warning when
`-6` is missing). nginx checks the hash at every request, so keep the default round count: a high one slows down every request. nginx
reads the files on every request: a new account works at once, without a reload. The nginx
worker must be able to read them (container: owner uid 101 and mode 0600 work, host nginx: `root:www-data` and `0640`); a missing
file makes every request that carries a password answer 403, an unreadable one makes it answer 500 (the nginx log says `open() ... failed`);
a request without a password gets 401 first. An account name with `"` or `\` works
but shows as `?` at the top of the admin page. Limits: no sign out (close the browser), no second factor, no limit on wrong
passwords, a wrong login is logged under the name that was typed. `auth_basic` is set in the server block and in the admin
locations themselves; it does not work inside an `auth_request` subrequest (everybody would get in).

**none** (`login/none/`). No login, only networks. `login/server.conf` lists who may use the viewer and everything else,
`login/admin.conf` the narrower list for `/admin/`, the dcm4chee UI section and every change; everybody else gets 403. The audit log
then names the PC (`anon-<address>`), never a person, and everybody inside a list can do everything that list allows. Behind
an SSH tunnel to a port published on 127.0.0.1 nginx sees the address of the Docker gateway, not your PC: allow only that address
(`docker network inspect NETWORK -f '{{(index .IPAM.Config 0).Gateway}}'`, for example `allow 172.18.0.1;`), never a range such as
`172.16.0.0/12`, which holds every Docker network of the host. The page shows `anon-<address>` at the top.

<a id="viewer"></a>
### Viewer

**ohif**: serves the OHIF files of the image (`/usr/share/nginx/html`, `app-config.js` from your mount) and allows the DICOMweb reads
the viewer needs (studies, series, instances, WADO), GET only. **none**: `/` redirects to `/admin/`, series, instances and WADO give 404
(the admin page needs only the study search, the patient list and the view of rejected studies, which both modes have). Set
`viewerUrl: ''` in `web/admin/config.js` to hide the Viewer link.

<a id="listener"></a>
### Listener

**tls**: `listen 8443 ssl` with `http2 on` (nginx 1.25.1 or newer; on an older nginx, for example Debian 12 with 1.22, delete that
line and write `ssl http2` in the `listen` line; checked on 1.22: `nginx -t`, HTTP/2 and the redirect), TLS 1.2 and 1.3, and a second server on 8080 that redirects http to https. The certificate and key (`ssl_certificate`, `ssl_certificate_key`, the last two lines of `listener/server.conf`) are read by the nginx
master process when it starts, so the key permissions depend on the image. Viewer `ohif` (the OHIF image, its nginx master runs as
uid 101): `chown root:101 server.key && chmod 640 server.key`. Viewer `none` (plain `nginx` image) and host nginx (master is root):
`chown root:root server.key && chmod 600 server.key`. `docker exec ohif id` shows which case you have. No HSTS by default; see
the end of `common/headers.conf` for the optional line (only with a real certificate).

**plain**: `listen 8080`, no TLS, only for a first look through an SSH tunnel (`ssh -L 8080:127.0.0.1:8080 user@server`, the **same**
port on both ends: the browser puts it into the Referer, and the rule of the dcm4chee UI section names `:8080`). Passwords and patient
data would be readable on any other path; never publish this on a network.

**behind-proxy**: `listen 8080` plus `set_real_ip_from <proxy address or network>`, `real_ip_header X-Forwarded-For`, `real_ip_recursive on`.
The proxy ends TLS and must pass `Host` unchanged (Apache: `ProxyPreserveHost On`) and the client address in `X-Forwarded-For`
(Traefik, Caddy and Cloudflare Tunnel do). Nginx must be reachable **only** from the proxy (no published port, a Docker network shared
with the proxy): from anywhere else `X-Forwarded-For` would be a forgery. The shipped address `203.0.113.1` trusts nobody until you replace it. The audit log, `X-Real-IP` for the helper service (firewall
lock-out check), the network lists of login `none` and the oauth2-proxy calls then use the real client address. If the proxy
listens on another port than 443, put it into the Referer rule in `listener/http.conf`.

<a id="dcm4chee-ui"></a>
### dcm4chee UI section (optional)

`optional/dcm4chee-ui.conf` makes the dcm4chee user interface (`/dcm4chee-arc/ui2/`) usable for admins behind the same login,
without Keycloak. It needs an arc without Keycloak (not the `-secure` images). nginx recognises calls of the UI by the Referer
`<scheme>://<host>/dcm4chee-arc/ui2/` (same host, no other port, see the listener files) and sends them to a location where everything
is allowed; the locks of the admin page do not apply there. Changes made there are in the audit log with the account. Switch it off:
`rm $T/pacs/optional/dcm4chee-ui.conf` and reload; without the file every call of the UI gives 404.

<a id="host-nginx"></a>
## nginx on the host instead of a container

Same files, different paths. The helper service and nginx must agree on the uid of the nginx workers: on Debian that is `www-data` (33),
so `PACS_SOCKET_UID=33` in `/etc/default/pacs-admin`, then `systemctl restart pacs-verwaltung`. The helper warns that `www-data` is
shared with other programs; if PHP or another web application runs as `www-data` give nginx its own account instead
(`useradd -r -s /usr/sbin/nologin pacsweb`, `user pacsweb;` in `nginx.conf`, `PACS_SOCKET_UID=<its uid>`). arc has to be published on
`127.0.0.1:8080`. The OHIF files are not part of the distro nginx: use viewer `none`, or copy the files out of the OHIF image yourself.
Needs nginx 1.25.1 or newer (Debian 13 has 1.26; Debian 12 has 1.22: see the `http2` line under listener `tls`).

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

Then edit `site.conf` (`server_name`, the admin group for oauth2-proxy), put the certificate files where `listener/server.conf` points (the key
`root:root 0600`: the master process is root), create the htpasswd files in `/etc/nginx/htpasswd/` (`chown root:www-data`,
`chmod 640`), and `nginx -t && systemctl reload nginx`. Ports 80 and 443 of the host are not filtered by the firewall tab of the
admin page (it filters Docker). Start order: `pacs-verwaltung` should be up before nginx, else audit lines are lost until the sockets
exist (`Wants=` and `After=pacs-verwaltung.service` in a drop-in of `nginx.service`; not tested).

<a id="ae-titles"></a>
## AE titles

The AE titles `DCM4CHEE` (archive) and `IOCM_QUALITY` (view of rejected studies) are written out in exactly two files, and
only there: `pacs.conf` (the event map and the locations) and `pacs/viewer.conf` (viewer `ohif` only; viewer `none` has none).
`99DCM4CHEE` is a coding scheme, not an AE title, and must stay. Rename (this is what `bash deploy/tools/set-aet.sh` does):

```bash
for f in $T/pacs.conf $T/pacs/viewer.conf; do
  sed -E -i -e 's/99DCM4CHEE/@@CODING@@/g' -e 's/DCM4CHEE/MYARC/g' -e 's/IOCM_QUALITY/MYARC_REJ/g' -e 's/@@CODING@@/99DCM4CHEE/g' $f
done
```

The names must match `aet` and `iocmAet` in `web/admin/config.js` and `ARC_AET` in `/etc/default/pacs-admin`.

<a id="upgrade"></a>
## Changes against the old single file `deploy/nginx.conf.example`

If you run the old file: the compose volume `./nginx.conf:/etc/nginx/conf.d/default.conf:ro` becomes `./nginx:/etc/nginx/conf.d:ro`
(the folder of this README), the values you edited in the old file move into `pacs/site.conf` and the files named under
[Placeholders](#placeholders), and the key permissions follow listener `tls` (OHIF image `root:101 0640`, plain `nginx` image or host `root:root 0600`).
Behaviour that is new: a study update and a study move accept only the query string that the admin page sends, and a path with `;`, an encoded backslash or a raw backslash gives 400,
`Authorization` and `Cookie` no longer reach arc and the helper service, uploads through the dcm4chee UI section work above 1 MB
(the auth subrequest got `client_max_body_size 0`), the audit account is never empty, `Server` shows no version.

<a id="guarantees"></a>
## What the configuration guarantees

- Every write has a lock (see the comments in `pacs.conf`). A study update accepts exactly the query string that the admin page
  sends: `reasonForModification=` and one `StudyInstanceUID` made of digits and dots, nothing else. A study move accepts exactly
  `PatientID`, optionally `IssuerOfPatientID`, and `updatePolicy=PRESERVE`. A patient update never carries `merge` or a percent sign
  in a parameter name. Permanent delete goes only through `IOCM_QUALITY`, and reject, restore and merge only through the listed
  calls. Every change needs the header `X-PACS-Admin`, which only the admin page sets. The two study locks name what is allowed,
  because a list of what is forbidden cannot be complete: a second `StudyInstanceUID` or a comma list in one can select several
  studies. `studyinstanceuid=`, a second `StudyInstanceUID`, a comma list, the hex form `0020000D=`, `Study%49nstanceUID`, `merge=0`
  and any other extra parameter all give 403. The locks answer before the login check, so a wrong query string gets 403 even
  without a login.
- A `;`, an encoded backslash or a raw backslash in the path gives 400 (nginx does not normalise path parameters, the upstream may).
  This answer also comes before the login check.
- `Authorization` and `Cookie` of the browser never reach arc or the helper service; `X-Forwarded-For`, `X-Real-IP`, `X-Auth-User` and
  `X-PACS-Admin` towards them are set by nginx, a forged value from the browser is replaced. The auth subrequest and the oauth2-proxy
  calls get `X-Forwarded-For` and `X-Real-IP` from the connecting address, not from the browser.
- The audit log has the three tags `zugriffe`, `ereignisse`, `admin` with the field names the helper service and the page read (`t`, `u`,
  `sub`, `ip`, `r`, plus `m`, `uri`, `status`, `k`, `body` for `admin`); `u` is never empty. Nothing is written to `docker logs`.
  While the helper service is down or restarting audit lines are lost (the first line of every nginx worker after a restart too).
- Cross-origin isolation headers (`COOP`, `COEP`, `CORP`) on the page, the viewer and the admin calls; `server_tokens off`; no
  HSTS by default.
- Locations that answer with a fixed text before any login check (`/admin` redirect, `/dcm4chee` redirect, `/dcm4chee-arc/` 404, the entry script
  and `keycloak.json` of the dcm4chee UI section, `/` of viewer `none`, the oauth2-proxy login endpoints) are public by design and contain no data.

<a id="checks"></a>
## Checks and troubleshooting

```bash
grep -rn CHANGE-ME /opt/ohif/nginx        # must print nothing
docker exec ohif nginx -t                 # syntax ok / test successful
docker exec ohif nginx -T | grep -n 'location '    # the loaded locations
docker logs ohif 2>&1 | tail              # why the container does not start
curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/            # no login: oauth2-proxy 302, basic 401, none 403 (outside the list)
curl -sk -u anna -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/    # login basic, an admin account: 200
```

| Symptom | Cause and fix |
|---|---|
| container does not start, `[emerg] open() "/etc/nginx/conf.d/pacs/..." failed` | a folder or file of step 1 to 4 was not copied |
| `unknown directive "http2"` | nginx older than 1.25.1: see listener `tls` |
| `no "ssl_certificate" is defined` / `cannot load certificate` | certificate files missing or paths at the end of `listener/server.conf` wrong; key readable by the master only, see listener `tls` |
| `unknown "pacs_dcm4chee_ui" variable` | the listener folder was not copied (`listener/http.conf`) |
| every page answers 500, log says `could not be resolved` | `set $arc` / `set $pacs_auth` name is wrong, or the container is not in that Docker network |
| login `basic`: a request with a password answers 403 or 500 | `/etc/nginx/htpasswd/users` or `admins` missing (403) or not readable by the worker (500); log: `open() ... failed` |
| login `oauth2-proxy`: `/admin/` is 403 for an admin | the group in `site.conf` is not the one in the token (look at `/oauth2/userinfo`), or the placeholder is still there |
| 502 on `/admin/dienst/`, audit lines missing | helper service not running, or `PACS_SOCKET_UID` is not the uid of the nginx workers |
| upload through the dcm4chee UI fails above 1 MB with 500 | old single-file configuration: the auth subrequest had its own body limit (fixed here) |
| the dcm4chee UI gives 404 on every call | no Referer match: other host name or port than the listener expects, or the optional file is gone |

<a id="lab"></a>
## Test lab

The configuration was verified with a throw-away lab of containers (the lab scripts are kept by the maintainers and are not
installed on a PACS server): the real helper service, a stub arc that echoes what reaches it, a stub oauth2-proxy, nginx under test,
a second nginx whose helper socket is an echo, a proxy in front for `behind-proxy`, and a client that runs a test matrix (about 370
checks per recipe: every lock, the Referer rule, header scrubbing, the audit log end to end, the account label, and a check that
every location of `nginx -T` has a login requirement or is on the public list). Recipes are named `login-viewer-listener`:
`run.sh oauth2-ohif-tls`, `basic-ohif-tls`, `basic-none-plain`, `none-none-plain`, `oauth2-ohif-proxy` and the other combinations,
plus `run.sh nginx-t` (nginx -t and the CHANGE-ME check for all 18 combinations, with and without the dcm4chee UI file), `host` and
`debian12` (distro nginx), `keymode` (who must read the TLS key), `aet` (AE title rename) and `oauth2-group` (placeholder or empty
admin group). A recipe builds, tests and tears everything down again; everything it creates is named `pacsadm-nginx-*`.
