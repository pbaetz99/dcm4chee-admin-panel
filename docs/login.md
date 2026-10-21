# Login: how users sign in

English | [Deutsch](login.de.md)

nginx checks every request to the viewer, to the admin page and to dcm4chee. This check is the **login**. This page lists
every supported login, helps you choose one, sets it up step by step and names the ways that do not work.

Run all commands as root. Every step ends with a **Check** box that shows how to see that the step worked. A **Warning**
box names what can lock users out.

You pick a recipe (a compose file and a set of nginx files) in [install.md](install.md). Each recipe contains exactly one
login. This page covers what belongs to the login: accounts, secrets and checks.

- [1. Choose a login](#login-choose)
- [2. Login with oauth2-proxy: Entra ID, Keycloak, Authentik, Authelia, Zitadel, Google, GitHub](#login-oauth2)
- [3. Login with basic auth: user name and password in nginx](#login-basic)
- [4. No login: network lists](#login-none)
- [5. Other front doors: Traefik, Caddy, Apache, Cloudflare Tunnel](#login-other)
- [6. Not supported](#login-unsupported)
- [7. Who can open what](#login-access)
- [8. What the audit log records](#login-audit)

<a id="login-choose"></a>
## 1. Choose a login

Every login knows two levels. A **viewer** may open the viewer and search for studies. An **admin** may also open the admin
page (`/admin/`) and change data. The methods differ in how they decide the level.

| Login | Single sign-on | Second factor (MFA) | Viewer and admin | Account name in the audit log | Logout | You need | Effort |
|---|---|---|---|---|---|---|---|
| oauth2-proxy with Entra ID | Yes | Yes, set in Entra | Two Entra groups | The Entra user name | Link at the top of the admin page (one setting) | Entra rights, DNS name, certificate, oauth2-proxy container | High |
| oauth2-proxy with Keycloak, Authentik, Authelia or Zitadel | Yes | Yes, set in the provider | Groups or roles of the provider | User name, else e-mail, else the id of the provider | Link (see above) | A running provider, DNS name, certificate, oauth2-proxy container. Not tested here | High |
| oauth2-proxy with Google or GitHub | Yes | Yes, set at Google or GitHub | Google: no groups, admins are an e-mail list. GitHub: teams of an organisation | E-mail address (GitHub: login name when there is no e-mail) | Link (see above) | An OAuth app at Google or GitHub, DNS name, certificate, oauth2-proxy container. Not tested here | Medium |
| basic | No | No | Two files: all accounts, and admins | The account name you created | None. Close the browser | TLS certificate (mandatory), openssl | Low |
| none | No login | No | Two network lists: viewer PCs and admin PCs | The PC address only | Not applicable | A closed network with PCs you trust | Lowest |

**Single sign-on** means that users sign in once with their organisation account and do not get a new password for the PACS.
**MFA** (multi-factor authentication) means a second proof next to the password, for example a code in a phone app. oauth2-proxy
does no MFA itself. The identity provider does it.

### Which one for me

- Your organisation uses Microsoft 365 or Entra ID: use oauth2-proxy with Entra ID. Users keep their own password and second
  factor. You remove a person by removing them from a group.
- You already run another identity provider that speaks OpenID Connect: use oauth2-proxy with that provider.
- You have no identity provider and a small number of users, for example a small practice or a test system: use basic.
  Nothing outside the server is needed.
- You have a closed network, fixed PCs that you trust and no wish for accounts: use none. The audit log then names PCs, not
  people.
- You cannot decide: start with basic. You can change the login later. The login is four small nginx files plus a few
  lines in the compose file ([deploy/nginx/README.md](../deploy/nginx/README.md) lists them).

Use https between the browser and the PACS with every login. Without it, anybody on the network path can read passwords,
session cookies and patient data. The only plain http setup is the try-it recipe: its port listens on 127.0.0.1 only, and the
browser reaches it through an SSH tunnel (see [install.md](install.md)).

<a id="login-oauth2"></a>
## 2. Login with oauth2-proxy

### 2.1 How it works

oauth2-proxy is a small program that signs users in with an [identity provider](glossary.md#identity-provider). An identity
provider is a service that knows the users and checks their passwords, for example Microsoft Entra ID, Keycloak or Google.
oauth2-proxy talks to it with [OpenID Connect](glossary.md#oidc) (OIDC). It runs as the container `ohif-auth`. It has no port
outside the Docker network. The user types the password only at the identity provider, never at the PACS.

nginx asks oauth2-proxy about every request:

```text
 Browser            nginx (ohif)        oauth2-proxy (ohif-auth)      Identity provider
    |  GET /admin/      |                        |                          |
    |------------------>|  signed in? admin?     |                          |
    |                   |----------------------->|                          |
    |                   |  no session: 401       |                          |
    |  go to the login  |<-----------------------|                          |
    |<------------------|                        |                          |
    |  the user signs in at the provider                                    |
    |<--------------------------------------------------------------------->|
    |  back to /oauth2/callback: oauth2-proxy sets a cookie                 |
    |------------------>|----------------------->|                          |
    |  GET /admin/      |  signed in? admin?     |                          |
    |------------------>|----------------------->|                          |
    |                   |  yes: 202 + account    |                          |
    |  the page         |<-----------------------|                          |
    |<------------------|                        |                          |
```

oauth2-proxy answers with a status code. 202 means yes. 401 means that no session exists. 403 means that the user is signed in
but not allowed. The identity provider also tells oauth2-proxy the groups of the user. The groups decide the level:

- **Viewer level:** the user is in one of the groups that the compose file lists with `--allowed-group`.
- **Admin level:** the user is in the one admin group that `pacs/site.conf` names (`$pacs_admin_group`). The admin group is also
  one of the `--allowed-group` lines, so an admin needs only the admin group.

The admin group must be written identically in these two places. This is the most common mistake.

**What was tested.** The logins `basic` and `none` ran in Docker with the nginx files of this repository. The outputs in
[section 3](#login-basic) and [section 4](#login-none) come from those runs. The login `oauth2-proxy` was checked without a
provider: `nginx -t` on the assembled files, `docker compose config` and the edit commands of steps 8 and 9 on copies of the
files, and a small stand-in in front of nginx that answers like oauth2-proxy (202, 401 or 403). A real oauth2-proxy and a real
identity provider did not run. Entra ID is the setup this project was written for. Every other provider in
[2.6](#login-oauth2-providers) comes from the documentation of oauth2-proxy and of the provider. Each of them is marked "not
tested here". An output that only a real provider can produce is marked "not run against a real provider".

### 2.2 Before you start

- The DNS name of the PACS (here `pacs.example.org`) points to the server and the https certificate is in place
  ([install.md#tls-certificate](install.md#tls-certificate)). Why: a [redirect URI](glossary.md#redirect-uri) is the address
  where the provider sends the browser back after the sign-in. Providers accept only https addresses for a real host name.
  So the DNS name and the certificate come first.
- The compose file of the recipe `oauth2-proxy` is `/opt/ohif/docker-compose.yml` and the nginx files of this login are in
  `/opt/ohif/nginx` ([install.md](install.md)).

> **Check**
>
> ```bash
> grep -m1 -o 'Login [a-z0-9-]*' /opt/ohif/nginx/pacs/login/http.conf
> ls /opt/ohif/docker-compose.yml /opt/ohif/nginx/pacs/site.conf
> ```
>
> Expected:
>
> ```text
> Login oauth2-proxy
> /opt/ohif/docker-compose.yml
> /opt/ohif/nginx/pacs/site.conf
> ```
>
> If the first line says `Login basic` or `Login none`, the files of another login were copied. Go back to
> [install.md](install.md) and copy the files of the login `oauth2-proxy`.

<a id="login-oauth2-entra"></a>
### 2.3 Entra ID, step by step

You work in the Entra admin center (https://entra.microsoft.com). Microsoft changes the portal from time to time, so a
button can have a slightly different name. Microsoft's own pages are the reference:
[register an app](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app),
[group claims](https://learn.microsoft.com/en-us/entra/identity-platform/optional-claims#configure-groups-optional-claims).

**Rights you need.** The roles are the ones that the Microsoft documentation names as the minimum. One person with several
roles can do all steps. If you lack a role, ask your Entra administrator to do that step and to send you the values of the
table in step 6.

| Task | Role (at least) |
|---|---|
| Register the app (step 1) | Application Developer |
| Token configuration, API permissions, admin consent (steps 3 and 5) | Cloud Application Administrator |
| Create groups and add members (step 4) | Groups Administrator |

#### Step 1. Register the app

An app registration tells Entra that oauth2-proxy may sign users in, and where to send them back.

1. Open Entra ID > App registrations and select New registration.
2. Name: `PACS`. Users see this name on the sign-in page.
3. Supported account types: Single tenant only.
4. Redirect URI: platform Web, value `https://pacs.example.org/oauth2/callback`. Use your own host name. The path
   `/oauth2/callback` is fixed.
5. Select Register.

> **Check**
>
> The Overview page of the new app shows two values: Application (client) ID and Directory (tenant) ID. Under Manage >
> Authentication, the section Web lists `https://pacs.example.org/oauth2/callback`.
>
> If Microsoft later shows the error AADSTS50011 at sign-in, the redirect URI differs from the one that oauth2-proxy sends:
> see [troubleshooting](troubleshooting.md#login-redirect-uri-mismatch).

#### Step 2. Create the client secret

oauth2-proxy proves to Entra with the [client secret](glossary.md#client-secret) that it is the registered app. The secret is
a password for a program.

1. Open Manage > Certificates & secrets > Client secrets > New client secret.
2. Description: `PACS`. Choose how long the secret is valid.
3. Select Add.
4. Copy the **Value** at once. The portal shows it only now. The column Secret ID is not the secret.
5. Write the expiry date into a calendar.

> **Warning**
>
> When the secret expires, nobody can sign in. Create a new secret two weeks before the date and replace it as described in
> [2.5](#login-oauth2-operate). If you copy the Secret ID instead of the Value, the sign-in fails in the same way.

> **Check**
>
> The list under Client secrets shows one row with your description, an expiry date and a Value that is hidden. A later sign-in
> error about the client secret (AADSTS7000215 or AADSTS7000222) means a wrong or an expired secret: see
> [troubleshooting](troubleshooting.md#login-client-secret).

#### Step 3. Add the groups claim

A [claim](glossary.md#claim) is one piece of information that Entra puts into the token after the sign-in. The claim `groups`
lists the groups of the user. oauth2-proxy reads it to decide the level.

1. Open Manage > Token configuration > Add groups claim.
2. Select Security groups.
3. Keep Group ID for the ID token. Entra then writes the Object ID (a GUID) of each group into the token, not the name.
   Object IDs never change. Names can.
4. Select Save.

> **Check**
>
> The Token configuration page lists the claim `groups` for the ID token.
>
> Entra puts at most 200 groups into a token. Users in more groups need a different setting: see
> [2.4](#login-oauth2-overage).

#### Step 4. Create two groups

1. Open Entra ID > Groups > New group. Group type: Security. Name: `PACS Viewer`. Add the people who may open the viewer.
2. Create a second security group `PACS Admin`. Add the people who may also open `/admin/`.
3. Open each group. On its Overview page, copy the Object ID.

An admin does not need to be in the viewer group. Any one of the listed groups lets a user in.

> **Check**
>
> Both groups show an Object ID that looks like `aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee`.

#### Step 5. Consent

At the first sign-in Microsoft can ask the user to agree that the app reads the basic profile (permission `User.Read`, which
every new registration has). In most tenants users may agree on their own. If your tenant does not allow it, the sign-in page
asks for an administrator. Then an administrator opens App registrations > PACS > API permissions and selects Grant admin
consent for your tenant.

> **Check**
>
> Under API permissions the column Status shows "Granted for" and the name of your tenant for `User.Read`. This is needed only
> if the sign-in asked for an administrator.

#### Step 6. Where each value goes

| Value | Where you find it | File | Place |
|---|---|---|---|
| Host name | Your DNS name | `docker-compose.yml`, `nginx/pacs/site.conf` | `--redirect-url` and `server_name` (and the redirect URI in step 1) |
| Directory (tenant) ID | Overview of the app registration | `docker-compose.yml` | In `--oidc-issuer-url` |
| Application (client) ID | Overview of the app registration | `ohif-auth.env` | `OAUTH2_PROXY_CLIENT_ID` |
| Client secret Value | Certificates & secrets (shown once) | `ohif-auth.env` | `OAUTH2_PROXY_CLIENT_SECRET` |
| Object ID of the viewer group | Overview of the group | `docker-compose.yml` | The first `--allowed-group` |
| Object ID of the admin group | Overview of the group | `docker-compose.yml` and `nginx/pacs/site.conf` | The second `--allowed-group` and `$pacs_admin_group`. The same value in both |

All files are in `/opt/ohif`.

<a id="login-oauth2-env"></a>
#### Step 7. Create ohif-auth.env

`ohif-auth.env` holds the three secrets of oauth2-proxy. The commands below ask you for the two values you copied from the
portal and make the third one. They print no secret and leave no placeholder in the file. The typing of the secret is hidden.

Paste each of the next three blocks on its own and press Enter. A block that asks a question would otherwise take the next
pasted line as the answer.

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

The cookie secret encrypts the session cookie of oauth2-proxy. You never need to know it.

> **Check**
>
> ```bash
> ls -l /opt/ohif/ohif-auth.env
> cut -d= -f1 /opt/ohif/ohif-auth.env
> ```
>
> Expected: the mode `-rw-------`, the owner `root`, and the three names, without values:
>
> ```text
> OAUTH2_PROXY_CLIENT_ID
> OAUTH2_PROXY_CLIENT_SECRET
> OAUTH2_PROXY_COOKIE_SECRET
> ```
>
> Never print the whole file. If a name is missing or a value is wrong, run the three blocks again.

<a id="login-oauth2-edit"></a>
#### Step 8. Edit the compose file

The compose file `/opt/ohif/docker-compose.yml` starts oauth2-proxy with a list of flags. Six lines carry the marker
`CHANGE-ME`. List them:

```bash
grep -n 'CHANGE-M[E]' /opt/ohif/docker-compose.yml
```

The brackets keep the command from matching its own text in the header of the file. The output is the list of your six
tasks:

```text
94:      - --oidc-issuer-url=https://login.microsoftonline.com/TENANT-ID/v2.0   # ENTRA: CHANGE-ME: Directory (tenant) ID
97:      - --allowed-group=VIEWER-GROUP-ID         # ENTRA: CHANGE-ME: Object ID of the group that may open the viewer
98:      - --allowed-group=ADMIN-GROUP-ID          # ENTRA: CHANGE-ME: Object ID of the admin group (also in site.conf)
114:      - --redirect-url=https://pacs.example.org/oauth2/callback   # CHANGE-ME: https://HOST/oauth2/callback
123:      - --trusted-proxy-ip=172.16.0.0/12        # CHANGE-ME: subnet of the Docker network
136:    name: dcm4chee-arc_default   # CHANGE-ME: name of that network (docker network ls; preflight.sh prints it)
```

| Line | Value | Where you find it |
|---|---|---|
| 94 | Directory (tenant) ID | Overview of the app registration (step 1) |
| 97 | Object ID of the viewer group | Overview of the group (step 4) |
| 98 | Object ID of the admin group | Overview of the group (step 4) |
| 114 | Host name in the redirect URL | Your DNS name (step 1) |
| 123 | Subnet of the Docker network that nginx and oauth2-proxy share | `docker network inspect NETWORK -f '{{(index .IPAM.Config 0).Subnet}}'` |
| 136 | Name of the Docker network of dcm4chee | `docker network ls` (preflight.sh prints it) |

oauth2-proxy believes the headers `X-Forwarded-*` only from the subnet in line 123. The network is the one of line 136.
The shipped value `172.16.0.0/12` covers the usual Docker networks. Write the subnet that the command shows.

If you already set the network name in the install guide ([step 4.10](install.md#compose-file)), the output has five lines
and line 136 is missing. Then leave `DOCKER_NETWORK` as it is: the `sed` expression for that line finds nothing to change.

The lines marked `# ENTRA` are right for Entra ID. Another provider replaces them ([2.6](#login-oauth2-providers)).

Set the six values after the `=` signs and run the block. Each `-e` line replaces one value and deletes the marker comment.
The parts like `'"$TENANT_ID"'` put your values into the command.

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

You can edit the six lines by hand instead, for example with `nano /opt/ohif/docker-compose.yml`. Replace each value and
delete the marker comment. YAML uses spaces, never tabs.

> **Warning**
>
> A wrong group in the compose file locks users out. A wrong viewer group lets nobody open the viewer. A wrong admin group
> lets nobody open `/admin/`. Use the Object IDs of step 4, not the group names.

> **Check**
>
> ```bash
> grep -n 'CHANGE-M[E]' /opt/ohif/docker-compose.yml
> docker compose -f /opt/ohif/docker-compose.yml config --quiet && echo compose file ok
> ```
>
> Expected: the first command prints nothing. The second prints:
>
> ```text
> compose file ok
> ```
>
> A line in the output of the first command is a value that is still to be set. The text `CHANGE-ME-...` after an `=` sign
> means that a variable above was not filled in. An error from `docker compose config` names the line.

<a id="login-oauth2-site"></a>
#### Step 9. Set the admin group in nginx

`pacs/site.conf` is the only nginx file you edit. For this login it holds the host name and the admin group. The admin group
must be the same text as the admin group in the compose file (the second `--allowed-group`).

Set the two values after the `=` signs and run the block. Use the host name and the Object ID of step 8:

```bash
SERVER_NAME=CHANGE-ME-HOST-NAME
ADMIN_GROUP=CHANGE-ME-ADMIN-GROUP-ID
sed -E -i -e 's|^(server_name +)[^;]+;.*|\1'"$SERVER_NAME"';|' \
          -e 's|^(set \$pacs_admin_group +)[^;]+;.*|\1'"$ADMIN_GROUP"';|' /opt/ohif/nginx/pacs/site.conf
```

The command replaces both lines, together with their marker comments. An Object ID needs no special treatment. A group
name of another provider can: see [2.6](#login-oauth2-group-names).

> **Warning**
>
> An empty or wrong admin group does not open anything by mistake. An empty value gives 500 on `/admin/`. A wrong value gives
> 403 for everybody on `/admin/`. The shipped placeholder `00000000-0000-0000-0000-000000000000` is such a wrong value: it
> keeps `/admin/` closed until you set your group. A wrong group in the compose file for the viewer level is worse: nobody
> can open the viewer. Test with a test account before you tell users.

> **Check**
>
> ```bash
> grep -rn 'CHANGE-M[E]' /opt/ohif/nginx /opt/ohif/docker-compose.yml
> grep -n 'server_name\|pacs_admin_group' /opt/ohif/nginx/pacs/site.conf
> ```
>
> Expected: the first command prints nothing. The second prints your two values:
>
> ```text
> 4:server_name pacs.example.org;
> 20:set $pacs_admin_group aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee;
> ```
>
> A line in the output of the first command is a value that is still to be set.

<a id="login-oauth2-start"></a>
#### Step 10. Start and check

Start the containers. If they run already, the same command applies your changes.

```bash
cd /opt/ohif && docker compose up -d
docker exec ohif nginx -t
```

> **Check**
>
> ```bash
> docker ps --format '{{.Names}}  {{.Status}}' | grep '^ohif'
> docker exec ohif nginx -t
> curl -sk -o /dev/null -w '%{http_code} %{redirect_url}\n' https://pacs.example.org/ | cut -d/ -f1-3
> ```
>
> Expected: two containers that are `Up`, the two nginx lines, and a redirect to Microsoft for a request without a session.
> The last line was not run against a real provider:
>
> ```text
> ohif  Up 2 minutes
> ohif-auth  Up 2 minutes
> nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
> nginx: configuration file /etc/nginx/nginx.conf test is successful
> 302 https://login.microsoftonline.com
> ```
>
> The `-k` means "accept a self-signed certificate". Leave it out when you use a certificate from a real certificate
> authority. Then curl also checks the certificate. The `cut` keeps the host name and drops the long address behind it.
>
> If `ohif-auth` is not `Up`, or the redirect is missing: see [troubleshooting](troubleshooting.md#login-oauth2-proxy-down).
> If every page answers 500: see [troubleshooting](troubleshooting.md#every-page-500). If the browser jumps between the PACS
> and the login page: see [troubleshooting](troubleshooting.md#login-loop).

Now test with real accounts in a private browser window. Use one account of the viewer group and one of the admin group.

> **Check**
>
> 1. Open `https://pacs.example.org/`. Microsoft asks for the sign-in. Afterwards the viewer opens.
> 2. Open `https://pacs.example.org/oauth2/userinfo`. The page shows one line of JSON text. The admin page takes the account
>    name at its top from the entries `preferredUsername`, `email` and `user` (the first one that is not empty). An entry
>    `groups` holds a list with the Object ID of each group of this user. This output was not run against a real provider.
> 3. Open `https://pacs.example.org/admin/` with the **viewer** account: nginx shows `403 Forbidden`.
> 4. Open `https://pacs.example.org/admin/` with the **admin** account: the admin page opens. The account name stands at the
>    top of the page.
>
> Step 1 fails with a 403 after the sign-in: see [troubleshooting](troubleshooting.md#viewer-403-after-login). Step 4 shows
> 403 or 500 for the admin account: see [troubleshooting](troubleshooting.md#admin-403) and
> [troubleshooting](troubleshooting.md#admin-500). Each request of this test is in the audit log:
> [section 8](#login-audit) shows how to read it.

<a id="login-oauth2-signout"></a>
#### Step 11. Add a sign-out link (optional)

The admin page shows a link `Abmelden` (sign out) next to the account name when `abmeldenUrl` is set in `config.js`. Use your
own copy of the file, so that a `git pull` does not collide with your change. The compose file can mount the copy over the
original, but the mount line is a comment at first. These commands make the copy, set the address and switch the mount on
(the last one deletes the `# ` in front of the mount line):

```bash
cp -n /opt/pacs-admin/web/admin/config.js /opt/ohif/config.js
sed -i "s|abmeldenUrl: ''|abmeldenUrl: '/oauth2/sign_out'|" /opt/ohif/config.js
sed -E -i 's|^( +)# (- \./config\.js:)|\1\2|' /opt/ohif/docker-compose.yml
```

Then recreate the container, so that it sees the new mount:

```bash
cd /opt/ohif && docker compose up -d
```

The link `/oauth2/sign_out` ends the PACS session only. Entra may sign the user in again at once, without a password, because
the user is still signed in at Entra. To end the Entra session too, use this longer value in `abmeldenUrl` instead. The
compose file already allows the domain with `--whitelist-domain`:

```text
/oauth2/sign_out?rd=https%3A%2F%2Flogin.microsoftonline.com%2Fcommon%2Foauth2%2Fv2.0%2Flogout
```

After a later change of `config.js`, run `docker compose restart ohif` in `/opt/ohif`. The restart is needed because the
compose file mounts a single file, and a changed file is not visible in a running container.

> **Check**
>
> ```bash
> grep -o "abmeldenUrl: '[^']*'" /opt/ohif/config.js
> grep -n '^ *- \./config\.js:' /opt/ohif/docker-compose.yml
> docker compose -f /opt/ohif/docker-compose.yml config --quiet && echo compose file ok
> ```
>
> Expected:
>
> ```text
> abmeldenUrl: '/oauth2/sign_out'
> 78:      - ./config.js:/srv/pacs-admin/admin/config.js:ro
> compose file ok
> ```
>
> If the second command prints nothing, the mount is still a comment. Run the last `sed` command of this step again. Reload
> the admin page without cache (Ctrl+F5). The link `Abmelden` shows next to the account name. The edit commands ran on copies
> of the files. The sign-out itself was not run against a real provider.

<a id="login-oauth2-overage"></a>
### 2.4 Users in many groups (more than 200)

Entra puts at most 200 groups into a token. If a user is in more groups, Entra leaves all groups out. This is called a group
overage. oauth2-proxy then sees no group for that user and refuses the sign-in. Right after the Microsoft sign-in the user
lands on a page with the title "Forbidden" and the text "You do not have permission to access this resource". In
`docker logs ohif-auth` the line `Invalid authentication via OAuth2: unauthorized` appears. A refused user gets no session, so
`/oauth2/userinfo` cannot show the groups of this user (it answers 401). Other users are not affected, which makes the fault
hard to find. The page and the log line come from the source code of oauth2-proxy `v7.15.4`. They were not run against a
real provider.

You suspect an overage when a user is in the PACS groups, the same sign-in works for a colleague, and the user is a member of
more than 200 groups (Entra ID > Users > the user > Groups shows the number).

There are two fixes. The first is better for large tenants.

**A. Emit only the groups that are assigned to the application.**

1. Open Entra ID > Enterprise apps > All applications > `PACS` > Users and groups > Add user/group. Assign `PACS Viewer` and
   `PACS Admin`.
2. Open App registrations > `PACS` > Token configuration. Select the groups claim and choose Groups assigned to the
   application. Select Save.

Group assignment needs Microsoft Entra ID P1 or P2. Nested groups do not count. Users must be direct members of the two
groups. You change nothing in the compose file or in `site.conf`.

**B. Let oauth2-proxy ask Microsoft Graph.** Add `User.Read` to the scope in the compose file:

```text
- --scope=openid email profile User.Read
```

oauth2-proxy then reads the complete list of groups from Microsoft Graph. Some tenants need an administrator to consent to
`User.Read` (step 5). A long group list can make the session cookie too big.

Both fixes follow the documentation of
[oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/configuration/providers/ms_entra_id) and of
[Microsoft](https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-fed-group-claims). They were not run
here.

> **Check**
>
> Sign in as an affected user. The viewer opens and the "Forbidden" page does not appear. Then open
> `https://pacs.example.org/oauth2/userinfo`: the entry `groups` lists the Object IDs of the PACS groups of this user.
>
> If the "Forbidden" page still appears, the fix did not take effect. Each refused sign-in leaves one line in the log:
>
> ```bash
> docker logs ohif-auth 2>&1 | grep 'Invalid authentication' | tail -3
> ```
>
> Then see [troubleshooting](troubleshooting.md#viewer-403-after-login).

<a id="login-oauth2-operate"></a>
### 2.5 Daily work with oauth2-proxy

**Replace the client secret.** Create a new secret in the portal (step 2) before the old one expires. Run the three blocks of
step 7 again. The cookie secret changes as well, so everybody signs in once more. Then recreate the container:

```bash
cd /opt/ohif && docker compose up -d --force-recreate ohif-auth
```

> **Check**
>
> ```bash
> docker ps --format '{{.Names}}  {{.Status}}' | grep '^ohif-auth'
> ```
>
> Expected: `ohif-auth` with the status `Up` and a short time. Then sign in once. If the sign-in fails, see
> [troubleshooting](troubleshooting.md#login-client-secret).

**Add or remove a person.** Change the group membership in Entra. oauth2-proxy reads the groups at the sign-in and keeps them
in the session. The session ends after 12 hours (`--cookie-expire=12h`) and is not refreshed. A change therefore takes effect
at the next sign-in, at the latest after 12 hours. To apply it at once, the person opens `/oauth2/sign_out` and signs in again.

**End all sessions at once.** Run the three blocks of step 7 again and recreate `ohif-auth`. The new cookie secret makes
every old session cookie useless. Use this when a person must lose access immediately.

**Session ends while the admin page is open.** The page shows "Sitzung abgelaufen, Seite neu laden (F5)". Press F5 to sign in
again. See [troubleshooting](troubleshooting.md#session-expired).

**Change the admin group.** Change it in both places (compose file and `site.conf`), then:

```bash
cd /opt/ohif && docker compose up -d
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

<a id="login-oauth2-providers"></a>
### 2.6 Other OIDC providers

Another provider changes a few flags in the compose file and the value of the admin group in `site.conf`. Everything else of
section 2 stays: the redirect URI is always `https://pacs.example.org/oauth2/callback`, the three secrets go into
`ohif-auth.env`, and the admin group goes into the compose file and into `site.conf`.

**Not tested here.** The commands of this section ran on copies of the compose file and of the nginx files: `docker compose
config` and `nginx -t` accepted the result. No real oauth2-proxy and no real provider ran. What this section says about the
screens, the claims and the flags of a provider comes from the documentation of oauth2-proxy `v7.15.4` and of the provider.
Step E checks the result at your site.

#### The choices at a glance

| Provider | `--provider` | Issuer address | The level comes from | Example of the admin group |
|---|---|---|---|---|
| [Keycloak](#login-oauth2-keycloak) | `keycloak-oidc` | `https://idp.example.org/realms/pacs` | Groups, or realm roles | `pacs-admins`, or `role:pacs-admin` for a role |
| [Authentik](#login-oauth2-authentik) | `oidc` | `https://idp.example.org/application/o/pacs/` | Groups | `pacs-admins` |
| [Authelia](#login-oauth2-authelia) | `oidc` | `https://auth.example.org` | Groups | `pacs-admins` |
| [Zitadel](#login-oauth2-zitadel) | `oidc` | `https://zitadel.example.org` | Roles, turned into groups by an Action | `pacs-admin` |
| [Google](#login-oauth2-google) | `google` | none | E-mail addresses | `anna@example.org,ben@example.org` |
| [GitHub](#login-oauth2-github) | `github` | none | Teams of an organisation | `my-org:pacs-admins` |

The **issuer address** names the provider. oauth2-proxy fetches the rules of the sign-in from it. Step C shows how to check it.

**Active Directory.** A Windows domain alone cannot sign users in this way, because Active Directory does not speak OIDC. Two
ways exist. Synchronise the accounts to Entra ID and follow [2.3](#login-oauth2-entra). Or run Keycloak or Authentik and let
it read the accounts from Active Directory ([LDAP](glossary.md#ldap) federation). The second way was not tested here. AD FS
is not covered.

Do the steps in this order:

| Step | What you do |
|---|---|
| [A](#login-oauth2-register) | Register the application at your provider |
| [B](#login-oauth2-common) | Create `ohif-auth.env` |
| [C](#login-oauth2-compose) | Edit the compose file |
| [D](#login-oauth2-group-names) | Set the admin group in nginx |
| [Step 10 of 2.3](#login-oauth2-start) | Start the containers and check them (the same as with Entra ID) |
| [E](#login-oauth2-check) | Check the groups with a test account |
| [F](#login-oauth2-signout-other) | Add a sign-out link (optional) |

<a id="login-oauth2-register"></a>
#### Step A. Register the application at your provider

The provider must know oauth2-proxy. It needs the address where the browser returns after the sign-in (the redirect URI
`https://pacs.example.org/oauth2/callback`), and it hands out a Client ID and a client secret. It also needs the two groups,
and it must put the groups into the token. Use the part for your provider. Each part ends with the values that steps C and D
need.

<a id="login-oauth2-keycloak"></a>
##### Keycloak

[Keycloak](glossary.md#keycloak) is a free identity provider. The screen names below follow current Keycloak versions. Older
versions name some screens differently.

1. Choose the realm of your users in the admin console. The realm name is part of the issuer address (`pacs` in the example).
2. Open Clients > Create client. Client type: OpenID Connect. Client ID: `pacs`. Select Next.
3. Switch Client authentication to On. Leave only Standard flow checked. Select Next.
4. Valid redirect URIs: `https://pacs.example.org/oauth2/callback`. Select Save.
5. Open the tab Credentials. Copy the Client secret.
6. Open Groups > Create group. Make `pacs-viewers` and `pacs-admins`. Add the people as members.
7. Open Client scopes > Create client scope. Name: `groups`. Type: Default. Protocol: OpenID Connect. Select Save.
8. Open the new scope, then Mappers > Configure a new mapper > Group Membership. Name: `groups`. Token Claim Name: `groups`.
   Full group path: Off. Add to ID token, Add to access token and Add to userinfo: On. Select Save.
9. Open Clients > `pacs` > Client scopes > Add client scope. Choose `groups` and add it as Default.

Values for steps C and D:

```text
PROVIDER=keycloak-oidc
ISSUER=https://idp.example.org/realms/pacs
SCOPE='openid email profile groups'
VIEWER_GROUP=pacs-viewers
ADMIN_GROUP=pacs-admins
```

Keycloak older than version 17 puts `/auth` in front of `/realms` in the issuer address. With Full group path On, Keycloak
writes the groups with a leading slash (`/pacs-viewers`). Then write the slash in the values too.

**Realm roles instead of groups.** The provider `keycloak-oidc` hands realm roles to nginx as groups named `role:NAME`. Then
items 7 to 9 of the list above are not needed. Make the realm roles `pacs-viewer` and `pacs-admin`, give them to the people and
use these values:

```text
PROVIDER=keycloak-oidc
ISSUER=https://idp.example.org/realms/pacs
SCOPE='openid email profile'
VIEWER_GROUP=role:pacs-viewer
ADMIN_GROUP=role:pacs-admin
```

> **Check**
>
> The client `pacs` lists the redirect URI, and its tab Credentials shows a secret. Keycloak can show the token of a test
> user: Clients > `pacs` > Client scopes > Evaluate, choose the user, then the tab Generated ID token (the names differ
> between versions). The token holds a list `groups` with the group names. If it does not, the mapper (item 8) or the scope
> on the client (item 9) is missing. Step E checks the same thing through oauth2-proxy.

<a id="login-oauth2-authentik"></a>
##### Authentik

authentik is a free identity provider. The screen names below follow current versions and can differ in yours.

1. Open Applications > Providers > Create > OAuth2/OpenID Provider. Name: `pacs`.
2. Client type: Confidential. Redirect URIs: `https://pacs.example.org/oauth2/callback`. Some versions read this field as a
   regular expression. Then write `https://pacs\.example\.org/oauth2/callback`.
3. Signing Key: choose a certificate, for example the self-signed one that authentik ships. Without a signing key authentik
   signs tokens with the client secret (HS256), and oauth2-proxy cannot check that signature.
4. Select Finish. Open the provider and copy the Client ID and the Client Secret.
5. Open Applications > Applications > Create. Name: `PACS`. Slug: `pacs`. Provider: `pacs`. The slug is part of the issuer
   address.
6. Open Directory > Groups. Make `pacs-viewers` and `pacs-admins` and add the people.

The scope `profile` of authentik carries the claim `groups`, so the shipped scope list is enough. Values for steps C and D:

```text
PROVIDER=oidc
ISSUER=https://idp.example.org/application/o/pacs/
SCOPE='openid email profile'
VIEWER_GROUP=pacs-viewers
ADMIN_GROUP=pacs-admins
```

The issuer address of authentik ends with a slash. oauth2-proxy compares the address character by character, so keep the
slash. The default admin group of authentik is called `authentik Admins`, with a space. Step D shows how to write such a
name.

> **Check**
>
> The list of applications shows `PACS` with the provider `pacs`. The address
> `https://idp.example.org/application/o/pacs/.well-known/openid-configuration` shows a page of JSON text in the browser. The
> provider page of authentik can show the token of a user in a preview (the name of the tab differs between versions). The
> token holds a list `groups`. Step E checks the same thing through oauth2-proxy.

<a id="login-oauth2-authelia"></a>
##### Authelia

[Authelia](https://www.authelia.com/) is a sign-in portal that knows groups. This part was not checked in detail. The Authelia
page [OpenID Connect](https://www.authelia.com/integration/openid-connect/introduction/) is the reference for its configuration
file.

1. Add a client to the OpenID Connect part of the Authelia configuration file: Client ID `pacs`, the redirect URI
   `https://pacs.example.org/oauth2/callback` and the scopes `openid`, `email`, `profile` and `groups`. The exact keys depend
   on your version of Authelia. Restart Authelia.
2. Authelia stores only a hash of the client secret. oauth2-proxy needs the plain text. Make a long random text, put its hash
   into the Authelia file and the plain text into `ohif-auth.env` (step B).
3. The groups come from the user database of Authelia (a file or LDAP).

Values for steps C and D. The issuer address is the base address of the Authelia portal; the check in step C proves it:

```text
PROVIDER=oidc
ISSUER=https://auth.example.org
SCOPE='openid email profile groups'
VIEWER_GROUP=pacs-viewers
ADMIN_GROUP=pacs-admins
```

Authelia may deliver the groups only at its UserInfo endpoint and not in the ID token. oauth2-proxy asks that endpoint too,
unless `--skip-claims-from-profile-url=true` is set (it is not set in the compose file). This was not verified.

> **Check**
>
> The address `https://auth.example.org/.well-known/openid-configuration` shows a page of JSON text. Step C and step E prove
> the rest.

<a id="login-oauth2-zitadel"></a>
##### Zitadel

[Zitadel](https://zitadel.com/) keeps the roles of a user in the claim `urn:zitadel:iam:org:project:roles`. That claim is a
structure, not a list. oauth2-proxy reads a group claim only when it is a list of texts. So an Action in Zitadel must copy
the role names into a list claim `groups`. This is the least checked part of this guide. It rests on reports of Zitadel users
and on the Zitadel page about [Actions](https://zitadel.com/docs/apis/actions/introduction). Prefer another provider if you
can.

1. Create a project with the roles `pacs-viewer` and `pacs-admin`. Check in the project settings that roles are put into the
   token.
2. Create an application in the project: type Web, flow Code, redirect URI `https://pacs.example.org/oauth2/callback`. Copy
   the Client ID and the Client Secret.
3. Give the roles to the people.
4. Add an Action in the flow Complement Token that writes the role names into the claim `groups`. The script depends on your
   version of Zitadel. This guide does not print one.

Values for steps C and D:

```text
PROVIDER=oidc
ISSUER=https://zitadel.example.org
SCOPE='openid email profile'
VIEWER_GROUP=pacs-viewer
ADMIN_GROUP=pacs-admin
```

> **Check**
>
> The address `https://zitadel.example.org/.well-known/openid-configuration` shows a page of JSON text. Step E shows whether
> the Action works: the entry `groups` must list the role names.

<a id="login-oauth2-google"></a>
##### Google

Google puts no groups into the token. The two levels work differently from the other providers:

- **Viewer level:** every account of one Google Workspace domain (`--email-domain=example.org`).
- **Admin level:** a list of e-mail addresses in `pacs/site.conf`. nginx then asks oauth2-proxy for an address from the list
  and not for a group (step D).

> **Warning**
>
> `--email-domain=example.org` lets every account of the domain open the viewer. Use Google only if that is acceptable. Do
> not use it with private Gmail accounts: there is no domain to limit them to, and `--email-domain=*` would let every Google
> account open the viewer.

1. Open the [Google Cloud console](https://console.cloud.google.com/). Choose or create a project.
2. Open APIs & Services > OAuth consent screen. User type: Internal (this needs Google Workspace). Name: `PACS`.
3. Open Credentials > Create credentials > OAuth client ID. Application type: Web application. Authorised redirect URI:
   `https://pacs.example.org/oauth2/callback`.
4. Copy the Client ID and the Client secret.

Google has no issuer address, no scope list and no groups to set. The step C block for Google does not use the generic
provider block. Values for steps C and D:

```text
DOMAIN=example.org
ADMIN_LIST=anna@example.org,ben@example.org
```

Write the addresses in lower case. They must match the entry `email` of `/oauth2/userinfo` letter for letter (step E). A plus
sign in an address is written `%2B` in `ADMIN_LIST` (step D explains why).

> **Check**
>
> The credentials page lists the client with the redirect URI. Step E shows the addresses as oauth2-proxy sees them. The
> sign-in with Google was not run end to end. More: [Google's page about web server applications](https://developers.google.com/identity/protocols/oauth2/web-server).

<a id="login-oauth2-github"></a>
##### GitHub

GitHub puts no groups into a token either, but it knows teams of an organisation. oauth2-proxy lets in the members of the
teams that you name, and nginx asks for one team as the admin team. This needs an organisation on GitHub.

1. Open GitHub > Settings > Developer settings > OAuth Apps > New OAuth App. Application name: `PACS`. Homepage URL:
   `https://pacs.example.org/`. Authorization callback URL: `https://pacs.example.org/oauth2/callback`.
2. Select Register application. Copy the Client ID. Select Generate a new client secret and copy it at once.
3. Make two teams in the organisation, for example `pacs-viewers` and `pacs-admins`, and add the people. A team is named by
   its slug (the short name in the address of the team).
4. Organisations can restrict third-party apps. Then an owner of the organisation must approve the app before members can
   use it. The names of these screens change from time to time.

Values for steps C and D. `ORG` and `TEAMS` are the organisation and all teams that may open the viewer (a person in any one
of them gets in). `ADMIN_GROUP` is the organisation, a colon and the slug of the admin team:

```text
ORG=my-org
TEAMS=pacs-viewers,pacs-admins
ADMIN_GROUP=my-org:pacs-admins
```

GitHub Enterprise Server also needs the flags `--login-url`, `--redeem-url` and `--validate-url` with the addresses of your
server. They are not part of the compose file. See the page
[GitHub](https://oauth2-proxy.github.io/oauth2-proxy/configuration/providers/github) of oauth2-proxy.

> **Check**
>
> The list of OAuth Apps shows `PACS` with the callback URL. More:
> [GitHub's page about OAuth Apps](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app). The
> sign-in with GitHub was not run end to end.

<a id="login-oauth2-common"></a>
#### Step B. Create ohif-auth.env

Run the three blocks of [step 7](#login-oauth2-env) in 2.3. Where they ask for the Application (client) ID and the secret Value,
type the Client ID and the client secret of your provider. The block that makes the cookie secret stays the same.

> **Check**
>
> The Check of [step 7](#login-oauth2-env) applies: the mode `-rw-------` and the three names, without values.

<a id="login-oauth2-compose"></a>
#### Step C. Edit the compose file

The compose file starts oauth2-proxy with a list of flags. The lines marked `# ENTRA` are for Entra ID. A block of commented
lines holds the flags of a generic OIDC provider. Google and GitHub need a few lines of their own. The commands below delete
the Entra lines, switch the right flags on and fill in your values.

**Check the issuer address first** (not for Google and GitHub). oauth2-proxy stops at its start when the address you give
differs from the address that the provider announces about itself. The provider announces it at a fixed place. Write your
address after `ISSUER=` and ask for it:

```bash
ISSUER=https://idp.example.org/realms/pacs
curl -s "${ISSUER%/}/.well-known/openid-configuration" | python3 -c 'import sys,json; print(json.load(sys.stdin)["issuer"])'
```

> **Check**
>
> Expected: one line with the address as the provider announces it. For the Keycloak example above:
>
> ```text
> https://idp.example.org/realms/pacs
> ```
>
> The printed address, character for character, goes after `--oidc-issuer-url=`. A final slash counts: the address of
> authentik ends with one. If the command prints nothing, the address is wrong or the server cannot reach the provider. If
> Python reports an error, the address does not belong to an OIDC provider. With a wrong address `docker logs ohif-auth`
> ends with a message like `oidc: issuer did not match the issuer returned by provider, expected "..." got "..."` (a message
> of the library, not run here): see [troubleshooting](troubleshooting.md#login-oauth2-proxy-down).

**Keycloak, Authentik, Authelia, Zitadel.** Switch the generic block on:

```bash
sed -E -i -e '/# ENTRA/d' -e 's|^( +)# (- --)|\1\2|' /opt/ohif/docker-compose.yml
```

The first expression deletes the seven Entra lines. The second removes the `# ` in front of the eight lines of the generic
block. The block also sets `--oidc-groups-claim=groups` (the default name of the claim) and
`--oidc-email-claim=preferred_username` (accounts without an e-mail address can then sign in). Leave both as they are.

Set your values after the `=` signs. Take the first five from step A and the last three as in [step 8](#login-oauth2-edit).
Then run the block:

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

`IDP_HOST` is the host name inside the issuer address. It becomes `--whitelist-domain`, the one domain where a sign-out may
lead. If you already set the network name in the install guide ([step 4.10](install.md#compose-file)), the expression for the
last network line finds nothing to change. A group name with the characters `&`, `|` or a backslash breaks this block. Edit the
two `--allowed-group` lines by hand then.

**Google.** The generic block stays off. Add the provider, limit the viewer level to your domain and fill in the three
values of [step 8](#login-oauth2-edit):

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

**GitHub.** The generic block stays off. Add the provider, the organisation and the teams, and fill in the three values of
[step 8](#login-oauth2-edit). `--email-domain=*` stays: GitHub accounts have no common domain, and the teams decide who gets in.

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

The `\n` in the replacement text needs GNU sed, which every common Linux distribution has.

> **Warning**
>
> A wrong group in the compose file locks users out, as in step 8. Capital letters count. Write the names exactly as step A
> lists them: with Keycloak and the option Full group path On, with the leading slash.

> **Check**
>
> ```bash
> grep -n 'CHANGE-M[E]' /opt/ohif/docker-compose.yml
> docker compose -f /opt/ohif/docker-compose.yml config --quiet && echo compose file ok
> docker compose -f /opt/ohif/docker-compose.yml config | grep -E -e '- --(provider|oidc-issuer-url|scope|allowed-group|whitelist-domain|redirect-url|email-domain|github-org|github-team)='
> ```
>
> Expected: the first command prints nothing. The second and third print `compose file ok` and the flags with your values.
> For the Keycloak example of step A:
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
> For Google the list is `--provider=google`, the `--redirect-url` and `--email-domain=example.org`. For GitHub it is
> `--provider=github`, `--github-org=my-org`, `--github-team=pacs-viewers,pacs-admins`, the `--redirect-url` and
> `--email-domain=*`. An Entra line, `TENANT-ID` or `CHANGE-ME` in the output means that a command above did not run.

<a id="login-oauth2-group-names"></a>
#### Step D. Set the admin group in nginx

`pacs/site.conf` holds the host name and the admin group, as in [step 9](#login-oauth2-site). The compose file takes a group name as
it is. nginx does not. It pastes the value of `$pacs_admin_group` unchanged into a web address (a URL) that it sends to
oauth2-proxy. So the value in `site.conf` must be written in **percent form**: a character that a web address does not allow
becomes a percent sign and two hex digits. The Object IDs of Entra and the names in the examples above need no change. A name
with a space does: nginx then logs `auth request unexpected status: 400` and `/admin/` answers 500.

| Character in the name | Write in `site.conf` |
|---|---|
| space | `%20` |
| `&` | `%26` |
| `=` | `%3D` |
| `%` | `%25` |
| `+` | `%2B` |
| a letter with an accent, for example `ü` | its UTF-8 bytes, for example `%C3%BC` |

Letters, digits and the characters `- _ . ~ : / @` stay as they are. A comma cannot be part of a group name, because
oauth2-proxy splits a list at commas. For any other character use the command below. It converts a whole name:

```bash
python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe="-_.~:/@"))' 'authentik Admins'
```

Expected output:

```text
authentik%20Admins
```

Set the two values and run the block. `ADMIN_GROUP_ENC` is the admin group in percent form:

```bash
SERVER_NAME=CHANGE-ME-HOST-NAME
ADMIN_GROUP_ENC=CHANGE-ME-ADMIN-GROUP
sed -E -i -e 's|^(server_name +)[^;]+;.*|\1'"$SERVER_NAME"';|' \
          -e 's|^(set \$pacs_admin_group +)[^;]+;.*|\1'"$ADMIN_GROUP_ENC"';|' /opt/ohif/nginx/pacs/site.conf
```

**Google.** The admin level is a list of e-mail addresses. Two changes make nginx ask oauth2-proxy for an address instead of a
group. First change the question in the nginx file (one word, in the only line that holds it):

```bash
sed -i 's/allowed_groups=/allowed_emails=/' /opt/ohif/nginx/pacs/login/locations.conf
grep -n 'allowed_' /opt/ohif/nginx/pacs/login/locations.conf
```

Expected output of the second command:

```text
39:    proxy_pass $pacs_auth/oauth2/auth?allowed_emails=$pacs_admin_group;
```

Then run the block above with `ADMIN_GROUP_ENC` set to the list of addresses, separated by commas and without spaces, for
example `anna@example.org,ben@example.org`. The file `locations.conf` is not the file you normally edit. An update of the nginx
files overwrites this change, so write it down.

> **Warning**
>
> The admin group in `site.conf` and the admin group in the compose file must name the same group (Google: `site.conf` holds the
> addresses, the compose file holds no admin group). A wrong value gives 403 for everybody on `/admin/`. An empty value gives
> 500. The shipped placeholder `00000000-0000-0000-0000-000000000000` keeps `/admin/` closed until you replace it.

> **Check**
>
> ```bash
> grep -rn 'CHANGE-M[E]' /opt/ohif/nginx /opt/ohif/docker-compose.yml
> grep -n 'server_name\|pacs_admin_group' /opt/ohif/nginx/pacs/site.conf
> ```
>
> Expected: the first command prints nothing. The second prints your two values, for example:
>
> ```text
> 4:server_name pacs.example.org;
> 20:set $pacs_admin_group pacs-admins;
> ```

Now start the containers and run the Check of [step 10](#login-oauth2-start). With another provider the redirect in its last
line leads to the host of your provider, for example `302 https://idp.example.org`.

<a id="login-oauth2-check"></a>
#### Step E. Check the groups with a test account

Test with real accounts in a private browser window: one account that is only in the viewer group, one that is in the admin
group. This step proves that the provider sends the groups under the names you wrote down.

> **Check**
>
> 1. Sign in with the viewer account. The viewer opens. Open `https://pacs.example.org/oauth2/userinfo`. The page shows one
>    line of JSON text. The entry `groups` lists the groups of this account as the provider sends them. Google sends no
>    groups: read the entry `email` instead. This output was not run against a real provider.
> 2. Open `https://pacs.example.org/admin/` with the viewer account: nginx shows `403 Forbidden`.
> 3. Sign in with the admin account in another private window. The entry `groups` holds the admin group, written exactly as
>    in the compose file. Google: the entry `email` is one of the addresses of `ADMIN_LIST`.
> 4. Open `https://pacs.example.org/admin/` with the admin account: the admin page opens.
>
> Item 4 shows 403 or 500 for the admin account, or item 2 shows 500 instead of 403: see
> [troubleshooting](troubleshooting.md#admin-403) and [troubleshooting](troubleshooting.md#admin-500). If item 2 opens the
> admin page, that account is in the admin group, or `$pacs_admin_group` names the viewer group.

A refused user gets no session. So `/oauth2/userinfo` cannot show what the provider sent for that user: it answers 401. If the
viewer account lands on the page "Forbidden" right after the sign-in, look at the log of oauth2-proxy:

```bash
docker logs ohif-auth 2>&1 | tail -20
```

The line `Invalid authentication via OAuth2: unauthorized` marks a refused sign-in. Either the account is in none of the
`--allowed-group` groups, or the provider sent no groups. A successful sign-in leaves the line `Authenticated via OAuth2:` with
the session, and the session lists the groups that the provider sent. Compare these names with the names in the compose file,
letter by letter. The token preview of the provider (Keycloak: step A) shows the names without a successful sign-in. More
about this fault: [troubleshooting](troubleshooting.md#viewer-403-after-login). Both lines come from the source code of
oauth2-proxy `v7.15.4`.

<a id="login-oauth2-signout-other"></a>
#### Step F. Sign-out link for another provider (optional)

[Step 11](#login-oauth2-signout) added the link `Abmelden` with the address `/oauth2/sign_out`. Do step 11 first. That address ends
the PACS session only. Most providers keep their own session, and the next click signs the user in again without a password.
Many providers announce a logout address. oauth2-proxy can send the browser there after it has ended its own session. Ask the
provider for the address:

```bash
ISSUER=https://idp.example.org/realms/pacs
END=$(curl -s "${ISSUER%/}/.well-known/openid-configuration" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("end_session_endpoint",""))')
echo "$END"
```

Keycloak announces an address like `https://idp.example.org/realms/pacs/protocol/openid-connect/logout`. If the line is empty,
the provider has no such address. Keep `/oauth2/sign_out` then. Google and GitHub have none.

Put the address into `abmeldenUrl`. The address inside must be written in percent form, because it is the value of a
parameter. The commands convert it, change the line in `config.js` and restart the container:

```bash
ENC=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$END")
sed -i "s|abmeldenUrl: '[^']*'|abmeldenUrl: '/oauth2/sign_out?rd=$ENC'|" /opt/ohif/config.js
cd /opt/ohif && docker compose restart ohif
```

The host name of the logout address must be the one in `--whitelist-domain` (step C sets it from the issuer address). If the
logout address lies on another host, add that host to the compose file as a second `--whitelist-domain=HOST` line and run
`docker compose up -d`.

> **Check**
>
> ```bash
> grep -o "abmeldenUrl: '[^']*'" /opt/ohif/config.js
> ```
>
> Expected output for the Keycloak example (the address came from a stand-in provider):
>
> ```text
> abmeldenUrl: '/oauth2/sign_out?rd=https%3A%2F%2Fidp.example.org%2Frealms%2Fpacs%2Fprotocol%2Fopenid-connect%2Flogout'
> ```
>
> Reload the admin page without cache (Ctrl+F5) and select `Abmelden`. The browser should end up at the sign-in page of the
> provider. Not run against a real provider. Newer Keycloak versions can show a confirmation page, or ask for a parameter
> `id_token_hint`. In that case keep `/oauth2/sign_out` and tell the users to close the browser window.

<a id="login-basic"></a>
## 3. Login with basic auth

Basic authentication is a login that nginx does by itself. Nothing outside the server is needed: no identity provider and no
extra container. The browser asks for a name and a password, and nginx compares them with two files. This section fits the
recipes `basic`, `adminonly`, `proxied` and `tryit`.

**What was tested.** The outputs in this section come from runs in Docker. nginx 1.30.5 read the account lines that the
script wrote, and the script ran in a root container with OpenSSL 3.5.7. The OHIF image itself was not run. The sign-in test
in [3.4](#login-basic-start) proves your own setup.

- [3.1 How it works](#login-basic-how)
- [3.2 Before you start](#login-basic-before)
- [3.3 Make the first account](#login-basic-first)
- [3.4 Start and check](#login-basic-start)
- [3.5 Daily work: add, change and remove accounts](#login-basic-accounts)
- [3.6 When something fails](#login-basic-errors)
- [3.7 Limits](#login-basic-limits)

<a id="login-basic-how"></a>
### 3.1 How it works

On the first request the browser opens its own sign-in window and asks for a name and a password ([basic
auth](glossary.md#basic-auth)). The window belongs to the browser, not to the PACS. The browser sends the name and the
password again with every later request. nginx compares them with two files in the folder `/opt/ohif/htpasswd`. The format of
the files is [htpasswd](glossary.md#htpasswd).

| File | Holds | Opens |
|---|---|---|
| `users` | Every account | The viewer, the study search and the reads |
| `admins` | The administrators only | `/admin/` and every change |

An administrator needs a line in **both** files. For the paths in the first row of the table nginx reads `users`. For the paths
in the second row it reads `admins` and not `users`. The admin page also uses the study search, a path of the first row. A line
looks like `anna:$6$...`: the name, a colon and the password hash. A hash is a scrambled form of the password that nobody can
turn back into the password. The script of [3.3](#login-basic-first) writes the lines. You do not edit the files by hand.

What the user sees:

| Request | Result |
|---|---|
| No name and no password | 401. The browser opens its sign-in window |
| Right name and password, account in `users` | The viewer opens |
| Wrong password | 401. The window opens again |
| `/admin/` with an account that is only in `users` | 401. The window opens again, because basic auth cannot say "known, but not allowed" |
| `/admin/` with an account in `admins` | The admin page opens |

nginx reads both files at every request. A new account works at once, without a restart. The audit log names the account:
[section 8](#login-audit) shows how.

<a id="login-basic-before"></a>
### 3.2 Before you start

- The https certificate is in place ([install.md#tls-certificate](install.md#tls-certificate)). Why: the browser sends the
  password with every request. Without https anybody on the network path can read it. The only plain http recipe is `tryit`,
  which listens on 127.0.0.1 and is reached through an SSH tunnel.
- The folder of your compose file, here `/opt/ohif`, exists and holds the nginx files of the login `basic`.
- OpenSSL is installed on the server. The script needs version 1.1.1 or newer (`openssl version` shows it).

> **Check**
>
> ```bash
> grep -m1 -o 'Login [a-z0-9-]*' /opt/ohif/nginx/pacs/login/http.conf
> ls -d /opt/ohif /opt/ohif/docker-compose.yml
> ```
>
> Expected:
>
> ```text
> Login basic
> /opt/ohif
> /opt/ohif/docker-compose.yml
> ```
>
> If the first line says `Login oauth2-proxy` or `Login none`, the files of another login were copied. Go back to
> [install.md](install.md) and copy the files of the login `basic`.

<a id="login-basic-first"></a>
### 3.3 Make the first account

The script `pacs-adduser.sh` makes the lines of an account. It asks for the password twice and hides what you type. It
creates the folder `htpasswd`, hashes the password, writes the lines and gives the files the owner and the mode that nginx
needs. Make the first account an administrator. Run the script as root:

```bash
bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh admin anna
```

- The first word is the level. `admin` makes an account for the viewer and for `/admin/`. `all` makes an account for the
  viewer only.
- The name has letters, digits, `.`, `_` and `-`, at most 32 characters.
- The password has at least 10 characters and at most 256 bytes. Special characters and umlauts work.

The script prints the two prompts and then what it did:

```text
Password for anna (min. 10 characters, hidden):
Repeat the password:
account 'anna' (admin)
  directory /opt/ohif/htpasswd created (mode 755)
  /opt/ohif/htpasswd/users: line added
  /opt/ohif/htpasswd/admins: line added
  owner 101, mode 600, password hash type sha512-crypt
  nginx reads the files at every request: no restart needed.
```

The script prints English. It prints German when the first of the variables `LC_ALL`, `LC_MESSAGES` and `LANG` that is set
starts with `de` (a German server locale). The German version of this guide,
[login.de.md](login.de.md#login-basic-first), quotes the German output.

The files must belong to the user with the number 101 (the user of nginx in the OHIF image) and have the mode 600, so that
only nginx can read them. Only root can set that owner. The folder `/opt/ohif` must exist already: the script makes the
subfolder `htpasswd` in it, not the folder itself. For another folder use the option `--dir`
([3.5](#login-basic-accounts)).

> **Warning**
>
> Files of another owner are unreadable for nginx, and every request that carries a password fails with 500. When you run the
> script without root rights, the line after the file lines starts with `mode 600, hash type sha512-crypt. WARNING: not run
> as root, the owner was not set to 101.` Run the script again as root.
>
> The hash type `sha512-crypt` needs OpenSSL 1.1.1 or newer. With an older OpenSSL the script prints `pacs-adduser: WARNING:
> this openssl cannot make sha512-crypt hashes (it needs 1.1.1 or newer). Using apr1, the weaker hash type. Update openssl and
> set the password again.` and the summary line ends with `password hash type apr1`. nginx 1.30.5 accepted that hash type too.
> Update OpenSSL and run the script again for every account. The warning text and the summary line come from a run with a
> stand-in `openssl` that refuses the option `-6`. A real OpenSSL older than 1.1.1 was not tried.

> **Check**
>
> ```bash
> ls -ln /opt/ohif/htpasswd
> cd /opt/ohif/htpasswd && grep -o '^[^:]*' users admins
> ```
>
> Expected: two files of the user 101 (group 0) with the mode `-rw-------`, and the account name in both lists:
>
> ```text
> total 8
> -rw------- 1 101 0 112 Oct 14 07:54 admins
> -rw------- 1 101 0 112 Oct 14 07:54 users
> users:anna
> admins:anna
> ```
>
> The size is the length of the name plus 108: the name, a colon, a hash of 106 characters and a line break. Another name
> gives another number. The second command prints the names only. Never print the whole files: they hold the hashes.
>
> Another message: see [3.6](#login-basic-errors).

<a id="login-basic-start"></a>
### 3.4 Start and check

The compose file mounts the folder `htpasswd` into the container. If the containers do not run yet, start them as in
[install.md](install.md#start-and-check). If they run, nothing needs a restart.

> **Check**
>
> ```bash
> curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/
> curl -sk -u anna -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/
> curl -sk -u anna https://pacs.example.org/oauth2/userinfo
> ```
>
> The second and the third command ask for the password of `anna`. Expected: 401 without a password, 200 for the admin page,
> and the account label that the admin page shows at its top:
>
> ```text
> 401
> 200
> {"preferredUsername":"anna"}
> ```
>
> The `-k` means "accept a self-signed certificate". Leave it out when you use a certificate from a real certificate
> authority. If the first number is not 401, or the second is 401 with the right password: see
> [troubleshooting](troubleshooting.md#basic-login-401) and [3.6](#login-basic-errors).

Then open `https://pacs.example.org/admin/` in a private browser window. The browser asks for the name and the password.
After the sign-in the admin page opens, and the account name stands at its top.

<a id="login-basic-accounts"></a>
### 3.5 Daily work: add, change and remove accounts

Run the script once for every person. It tells what it did to each file.

**Add a viewer.** The account is in `users` only:

```bash
bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh all ben
```

```text
account 'ben' (all)
  /opt/ohif/htpasswd/users: line added
  /opt/ohif/htpasswd/admins: no line (not an admin)
  owner 101, mode 600, password hash type sha512-crypt
  nginx reads the files at every request: no restart needed.
```

**Make a viewer an administrator, or the other way round.** Run the script with the other level and the same name. The
script asks for a password again and sets it. The line in `users` is replaced, the line in `admins` is added or removed:

```bash
bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh admin ben
```

```text
account 'ben' (admin)
  /opt/ohif/htpasswd/users: line replaced (the account existed, the password is new)
  /opt/ohif/htpasswd/admins: line added
  owner 101, mode 600, password hash type sha512-crypt
  nginx reads the files at every request: no restart needed.
```

The word `all` takes the administrator right away again. The script then prints
`/opt/ohif/htpasswd/admins: line removed (the account is no longer an admin)`.

**Set a new password.** Run the script again with the same level and name. The line in `users` says `line replaced (the account
existed, the password is new)`. For an administrator the line in `admins` says the same.

**Remove an account.** Delete its line from both files. A dot in the name is written `\.` in the pattern, for example
`/^anna\.b:/d`. The command keeps the owner and the mode of the files:

```bash
sed -i '/^ben:/d' /opt/ohif/htpasswd/users /opt/ohif/htpasswd/admins
```

> **Warning**
>
> Delete the account from both files, else an administrator who left can still open the viewer or `/admin/`. Keep at least one
> administrator. An empty file `admins` answers 401 on `/admin/` for everybody.

**List the accounts** without the hashes:

```bash
cd /opt/ohif/htpasswd && grep -o '^[^:]*' users admins
```

> **Check**
>
> Expected after the commands above (`anna` is an administrator, `ben` a viewer). Then ask for the admin page with the viewer
> account. It must not pass:
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
> The `grep` command above shows the names. The two `curl` commands ask for the password of `ben`.

**Passwords in scripts.** When the input of the script is not a terminal, the script reads one line as the password. It does
not ask twice. Never write the password on the command line, because every user of the server can read it there and in the
shell history:

```bash
printf '%s\n' "$PW" | bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh admin anna
```

**Another folder, another nginx.** The options `--dir`, `--users`, `--admins`, `--owner` and `--mode` change where the files
are and who owns them. They are for a compose folder other than `/opt/ohif`, and for nginx installed on the host
([install.md#nginx-on-host](install.md#nginx-on-host)), where the workers run as `www-data`:

```bash
bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh admin anna --dir /srv/pacs
bash /opt/pacs-admin/deploy/tools/pacs-adduser.sh admin anna --users /etc/nginx/htpasswd/users --admins /etc/nginx/htpasswd/admins --owner root:www-data --mode 640
```

**By hand.** The script is the better way. If you must write a line yourself, make the hash with OpenSSL and append it. The
password then stays in the shell history, so use a password that you change afterwards with the script:

```bash
printf '%s:%s\n' NAME "$(printf '%s' 'PASSWORD' | openssl passwd -6 -stdin)" >> /opt/ohif/htpasswd/users
```

The hash starts with `$6$`. Add the same line to `admins` for an administrator.

<a id="login-basic-errors"></a>
### 3.6 When something fails

The error log of nginx names the account and the file. Read it first:

```bash
docker logs ohif 2>&1 | grep -E 'user "|htpasswd' | tail -5
```

The lines look like this (a test run, with the account names `clara` and `vera`):

```text
2026/10/14 07:39:56 [error] 98#98: *3 user "clara": password mismatch, client: 127.0.0.1, server: pacs.example.org, request: "GET / HTTP/2.0", host: "localhost:8443"
2026/10/14 07:39:56 [error] 100#100: *5 user "vera" was not found in "/etc/nginx/htpasswd/admins", client: 127.0.0.1, server: pacs.example.org, request: "GET /admin/ HTTP/2.0", host: "localhost:8443"
```

| What happens | Line in the log | Cause and fix |
|---|---|---|
| The sign-in window comes back after the right password | `user "clara": password mismatch` | The password differs. Set it again with the script |
| The window comes back on `/admin/` only | `user "vera" was not found in "/etc/nginx/htpasswd/admins"` | `vera` is a viewer account. Run the script with `admin vera` |
| The window comes back at once | `user "vera" was not found in "/etc/nginx/htpasswd/users"` | The account does not exist, or the name has another spelling. Run the script |
| 403 on the viewer pages right after the password. `/admin/` still opens | `open() "/etc/nginx/htpasswd/users" failed (2: No such file or directory)` | The file `users` is missing. If the folder `htpasswd` is missing next to the compose file, Docker made an empty one. Make the first account ([3.3](#login-basic-first)) |
| 403 on `/admin/` only | The same line with `admins` | The file `admins` is missing. Run the script with `admin` for one account |
| 500 on every page after the password | `[crit] ... open() ... failed (13: Permission denied)` | The owner or the mode of the files is wrong. Run the script as root: it sets owner 101 and mode 600 |
| 401 on `/admin/` for everybody | None | The file `admins` is empty. Make an administrator |

A request without a name and a password is answered with 401 in every case, because nginx does not open the files then. A
missing file therefore shows only after the first sign-in attempt. Lines like `[alert] connect() failed (111: Connection
refused) while logging to syslog` come from the audit log and not from the login: the helper service is down. (With `(2: No such
file or directory)` the service has not run since the server started.) See [reference.md](reference.md#audit-lost).

The script stops with a message and changes nothing in these cases:

| The script prints | Meaning |
|---|---|
| `pacs-adduser: invalid name 'anna@example.org': use letters, digits, . _ - only` | The name has a character that is not allowed |
| `pacs-adduser: the name must not contain a colon (it separates name and password hash in the file): 'anna:x'` | A colon in the name |
| `pacs-adduser: the password is shorter than 10 characters, nothing changed` | Use at least 10 characters |
| `pacs-adduser: the two passwords differ, nothing changed` | The second entry differs from the first |
| `pacs-adduser: the password is 257 bytes long: at most 256 bytes work (the hash covers only the first 256, so nginx would refuse the right password). Nothing changed.` | Use at most 256 bytes |
| `pacs-adduser: directory /nonexistent does not exist (use --dir DIR)` | The compose folder does not exist. Make it or name the right one with `--dir` |
| `pacs-adduser: role must be 'all' or 'admin', not 'both'` | The first word is wrong. The script prints its usage after this line |

More: [troubleshooting](troubleshooting.md#htpasswd-403-500) and [troubleshooting](troubleshooting.md#basic-login-401).

<a id="login-basic-limits"></a>
### 3.7 Limits

- **No sign-out.** The browser keeps the name and the password until it closes. Close the browser window to sign out.
- **No second factor.** There is only the password. Use a long password and https. Use oauth2-proxy
  ([section 2](#login-oauth2)) when you need MFA.
- **No limit on wrong passwords.** nginx does not block an account after wrong tries. Every try is in the audit log under the
  name that was typed ([section 8](#login-audit)).
- **Users cannot change their password.** An administrator runs the script.
- **One account per person.** The audit log names the account, so a shared account hides who did what.
- **A fast hash on purpose.** nginx checks the password at every request. The hash type sha512-crypt with the default number
  of rounds keeps this cheap. A slower hash would slow down every page. The hash type bcrypt (`$2y$`) is not read by every C
  library, so the script does not use it. Whether the nginx of the OHIF image reads `$6$` hashes was not run here: the sign-in
  test in [3.4](#login-basic-start) is the proof.

<a id="login-none"></a>
## 4. No login: network lists

Login `none` has no accounts and no passwords. nginx lets a request pass when the address of the PC is on a list. The login
uses the compose file of the recipe `basic` and the nginx files of `deploy/nginx/login/none`
([install.md](install.md#nginx-files)).

> **Warning**
>
> This is the weakest login. Everybody who sits at a PC on a list has the access of that list, and nobody has to prove who
> they are. The audit log names the address of the PC (`anon-192.0.2.77`) and not a person. Use `none` only in a closed
> network where every PC on the lists is trusted, and keep both lists short. For anything else take
> [basic](#login-basic) or [oauth2-proxy](#login-oauth2).

**What was tested.** The outputs in this section come from runs in Docker with nginx 1.30.5. The complete setup with the login
`none` ran in a test environment (nginx, a stand-in for dcm4chee and the real [helper service](glossary.md#helper-service)).
All 320 request checks and all 49 checks of the audit log passed. The lists of [4.1](#login-none-how) ran in all four
combinations. The edit commands of [4.2](#login-none-lists) and the log lines of [4.3](#login-none-check) come from runs on
copies of the files. Not run: an SSH tunnel, a PC behind a router with address translation, and IPv6.

- [4.1 How it works](#login-none-how)
- [4.2 Set the two lists](#login-none-lists)
- [4.3 Check it](#login-none-check)
- [4.4 Limits](#login-none-limits)

<a id="login-none-how"></a>
### 4.1 How it works

nginx reads the address of the PC from the connection. It compares the address with the lines `allow` and `deny` of a list
and uses the first line that matches. An address that no `allow` line names meets `deny all;` and gets the answer 403
("forbidden"). The browser shows a plain page with the text `403 Forbidden`.

Two files hold the two lists. They are in the folder `/opt/ohif/nginx/pacs/login/`:

| File | List | What it covers |
|---|---|---|
| `server.conf` | Viewer list | The viewer, the study search and every other read. This is everything that has no narrower list |
| `admin.conf` | Admin list | The page `/admin/`, the dcm4chee UI section, the patient list, the view of rejected studies and every change |

The admin list **replaces** the viewer list in these places. nginx does not add the two lists together. Four cases show what
happens (tested):

| The address of the PC is on | Viewer and study search | `/admin/` and changes |
|---|---|---|
| no list | 403 | 403 |
| the viewer list only | opens | 403 |
| the admin list only | 403 | opens |
| both lists | opens | opens |

Put every administrator PC on **both** lists. The admin page searches studies through the viewer list. A PC that is only on
the admin list opens the page, but its study search gets 403.

There are no accounts, so the audit log names the PC: `anon-` and the address, for example `anon-192.0.2.77`. The admin page
shows this label at its top. nginx takes the address from the connection and does not read it from a request header. A
header that a client writes does not change the label (tested with forged `Authorization`, `X-Auth-User`, `X-Real-IP` and
`X-Forwarded-For`). The listener `behind-proxy` is the one exception: it takes the address from the header of a proxy that
you name ([section 5](#login-other)). [Section 8](#login-audit) shows the rows of the audit log.

The compose file of the recipe `basic` mounts the folder `htpasswd`. With the login `none` nginx never reads it. Make the
empty folder anyway ([install.md](install.md#login-setup)), so that Docker does not create it as a folder of root.

<a id="login-none-lists"></a>
### 4.2 Set the two lists

Set the lists in [install.md](install.md#nginx-files), after the copy block with `LOGIN=none` and before the first start. The
same steps change the lists later. Each list file holds one example line with the marker `CHANGE-ME`. The example networks are
documentation networks that no real PC uses. Until you replace them, nobody gets in.

First decide who goes on which list:

- The viewer list holds the networks or the single PCs that may open the viewer.
- The admin list holds the administrator PCs only. Put each of them on the viewer list as well.

Write a network as `ADDRESS/LENGTH` ([CIDR](glossary.md#cidr)). `192.0.2.64/26` means the 64 addresses from 192.0.2.64 to
192.0.2.127. Write a single PC as its plain address, `198.51.100.10`. Give the administrator PCs fixed addresses. A PC with a
changing address (DHCP) gets another address one day and loses its access. On a Windows PC the command `ipconfig` shows the
IPv4 address, on a Linux PC the command `ip -4 addr`. If a router sits between the PC and the server, nginx sees the address of
the router and not of the PC ([4.4](#login-none-limits)).

> **Check**
>
> ```bash
> grep -m1 -o 'Login [a-z0-9-]*' /opt/ohif/nginx/pacs/login/http.conf
> grep -n CHANGE-ME /opt/ohif/nginx/pacs/login/server.conf /opt/ohif/nginx/pacs/login/admin.conf
> ```
>
> Expected: the name of the login and one example line per list file:
>
> ```text
> Login none
> /opt/ohif/nginx/pacs/login/server.conf:4:allow 192.0.2.0/24;                                # CHANGE-ME: the network of the PCs that may open the viewer
> /opt/ohif/nginx/pacs/login/admin.conf:3:allow 198.51.100.0/24;                             # CHANGE-ME: the network or the address of the administrator PCs
> ```
>
> If the first line says `Login basic` or `Login oauth2-proxy`, the files of another login were copied. Go back to
> [install.md](install.md#nginx-files) and copy the files of the login `none`. If a list line is missing, you set that list
> already.

Replace the two example lines. The commands cut the old `allow` line together with its marker comment. Write your own values in
the first two lines:

```bash
VIEWER_NET=192.0.2.64/26
ADMIN_NET=198.51.100.10
sed -E -i 's|^allow [^;]+;.*|allow '"$VIEWER_NET"';|' /opt/ohif/nginx/pacs/login/server.conf
sed -E -i 's|^allow [^;]+;.*|allow '"$ADMIN_NET"';|' /opt/ohif/nginx/pacs/login/admin.conf
```

Put the administrator PC on the viewer list too. The command adds one `allow` line above `deny all;`:

```bash
sed -E -i 's|^(deny all;)|allow '"$ADMIN_NET"';\n\1|' /opt/ohif/nginx/pacs/login/server.conf
```

Use the same command with another value for each more network or PC. `deny all;` must stay the last line of a list, because nginx
uses the first line that matches.

> **Warning**
>
> Do not run the two `sed` commands of the first block again once a list has more than one `allow` line. They replace
> **every** `allow` line of the file by one. Add lines with the second command or in an editor.

> **Check**
>
> ```bash
> grep -n -E '^(allow|deny)' /opt/ohif/nginx/pacs/login/server.conf /opt/ohif/nginx/pacs/login/admin.conf
> grep -rn CHANGE-ME /opt/ohif/nginx
> ```
>
> Expected: the lists with your values, and no output from the second command:
>
> ```text
> /opt/ohif/nginx/pacs/login/server.conf:4:allow 192.0.2.64/26;
> /opt/ohif/nginx/pacs/login/server.conf:5:allow 198.51.100.10;
> /opt/ohif/nginx/pacs/login/server.conf:6:deny all;
> /opt/ohif/nginx/pacs/login/admin.conf:3:allow 198.51.100.10;
> /opt/ohif/nginx/pacs/login/admin.conf:4:deny all;
> ```
>
> A line with `CHANGE-ME` in the second output is a value that you did not set. Set it as [install.md](install.md#nginx-files)
> says.

> **Warning**
>
> A wrong list does not lock you out of the server: you edit the file and read it again. While the list is wrong, users
> cannot open the viewer, or nobody can open `/admin/`. Check the admin list twice. Never write `allow all;`, because it lets
> everybody in, and keep the networks as small as you can.

At the first start nothing more is needed. After a later change, test the files and let nginx read them again:

```bash
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

> **Check**
>
> Expected: two lines of the test and one line of the reload (the numbers differ):
>
> ```text
> nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
> nginx: configuration file /etc/nginx/nginx.conf test is successful
> 2026/10/14 08:45:14 [notice] 17#17: signal process started
> ```
>
> A test that fails prints `[emerg]` and the file with the line number, and the reload does not run, so the old lists stay in
> force. Two typical messages: `invalid parameter "192.0.2.0/33"` (a network length above 32) and `invalid number of arguments
> in "allow" directive` (a missing semicolon). Correct the line that the message names and run the command again.

<a id="login-none-check"></a>
### 4.3 Check it

Run the checks on the PCs themselves. The address of the server is on no list, so a check on the server shows nothing about
the PCs. Open `https://pacs.example.org/` and `https://pacs.example.org/admin/` in a browser, or run the two commands (on
Windows `curl.exe`):

```bash
curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/
curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/admin/
```

> **Check**
>
> Expected, per kind of PC (tested):
>
> | PC | First command (viewer) | Second command (`/admin/`) |
> |---|---|---|
> | Administrator PC on both lists | 200 | 200 |
> | PC on the viewer list only | 200 | 403 |
> | PC on no list | 403 | 403 |
>
> The `-k` means "accept a self-signed certificate". Leave it out when you use a certificate from a real certificate
> authority. A number that differs: a list has the wrong network. Read the address in the log, see below, and
> [troubleshooting](troubleshooting.md#none-403).

From a PC that is allowed, the admin page shows the label of the PC at its top. The page reads it from this address:

```bash
curl -sk https://pacs.example.org/oauth2/userinfo
```

```text
{"preferredUsername":"anon-192.0.2.77"}
```

The address is the one of the PC that asked. Another PC shows its own address.

nginx writes every refused request into its error log, with the address that it saw. Read the log on the server:

```bash
docker logs ohif 2>&1 | grep 'access forbidden by rule' | tail -3
```

The lines look like this (a test run on plain http, with a documentation address):

```text
2026/10/14 08:41:35 [error] 9#9: *1 access forbidden by rule, client: 192.0.2.99, server: pacs.example.org, request: "GET /admin/ HTTP/1.1", host: "pacs.example.org"
2026/10/14 08:41:35 [error] 9#9: *2 access forbidden by rule, client: 192.0.2.200, server: pacs.example.org, request: "GET / HTTP/1.1", host: "pacs.example.org"
```

The word after `client:` is the address that nginx saw. A PC that is refused but should get in needs exactly this address on a
list. If it is not the address of the PC, read [4.4](#login-none-limits). The line also shows the page that the PC asked for:
`/admin/` in the first line, the viewer page in the second.

<a id="login-none-limits"></a>
### 4.4 Limits

- **No names.** The audit log names an address. When several people share one PC, or work on one remote desktop server, one
  address stands for all of them. A PC with a changing address appears under a new label.
- **Everybody on a list has the whole access of that list.** There is no way to give one person less.
- **The address must be the one that nginx sees.** nginx sees the address that connects to it. Behind a router with address
  translation (NAT) or behind a proxy this is the address of the router or the proxy, and the list then covers every PC behind
  it. With a proxy in front of nginx use the listener `behind-proxy` ([section 5](#login-other)). nginx then reads the address
  of the PC from the header `X-Forwarded-For`, but only when the proxy that sends the header is named in `set_real_ip_from`.
  Tested: with the proxy named, the lists worked on the address in the header (200 for an address on the list, 403 for any
  other). With another address named, every request got 403, because nginx saw the proxy address and ignored the header.
- **Published ports and IPv6.** The compose files write the ports as `0.0.0.0`, that is IPv4 only. Over IPv6 Docker would show
  nginx its own gateway address instead of the address of the PC (taken from the project files, not run here). So never put
  the gateway address on a list of a server that PCs reach over a published port.
- **A change needs a reload.** nginx reads the lists at the start and at the reload, not at every request. A login `basic`
  works differently.
- **The 403 page does not name the list.** The user sees `403 Forbidden`. You find the reason in the log ([4.3](#login-none-check)).

> **Warning**
>
> An SSH tunnel to a port that Docker publishes on 127.0.0.1 (the recipe `tryit`) shows nginx the address of the Docker
> gateway and not the address of your PC. Allow only that one address. Get it with the command below, where `NETWORK` is the
> name of the Docker network of the container `ohif` (`docker network ls` lists the names). The answer looks like `172.18.0.1`,
> and the list line is `allow 172.18.0.1;`. Never allow a range such as `172.16.0.0/12`, because it holds every Docker network
> of the host. This was not run here.
>
> ```bash
> docker network inspect NETWORK -f '{{(index .IPAM.Config 0).Gateway}}'
> ```

<a id="login-other"></a>
## 5. Other front doors

Many organisations run one **reverse proxy** in front of all their web services, for example Traefik, Caddy, Apache or
Cloudflare Tunnel. A reverse proxy takes the https connection of the browser, ends the encryption (TLS) and passes the request
on over plain http. This section covers the setups where such a proxy stands in front of nginx. nginx stays the front door: it
keeps the login, the locks and the audit log, and the proxy only ends TLS. A proxy that replaces nginx is not supported
([section 6](#login-unsupported)).

| Your setup | Login in nginx | Part |
|---|---|---|
| The proxy ends TLS. nginx checks name and password. | basic | [5.1](#login-other-proxied) |
| The proxy ends TLS. nginx checks the address of the PC. | none | [5.1](#login-other-proxied) |
| The proxy ends TLS. Users sign in at an identity provider. | oauth2-proxy | [5.2](#login-other-oauth2) |
| The proxy checks a login of its own before it passes the request on. | one of the three above | [5.3](#login-other-proxy-login) |

**What was tested.** The listener `behind-proxy` ran in Docker with nginx 1.30.5 (image `nginx:1.30`) and the login `basic`. A
test client took the place of the proxy and sent the header `X-Forwarded-For`. The lists of the login `none` ran the same way
([4.4](#login-none-limits)). The compose merge of [5.2](#login-other-oauth2) was checked with `docker compose config`, and the
nginx files of oauth2-proxy with the listener `behind-proxy` were checked with `nginx -t`. Traefik, Caddy, Apache, Cloudflare
and a real oauth2-proxy did not run.

<a id="login-other-proxied"></a>
### 5.1 A proxy in front of nginx, with the login basic or none

[install.md](install.md#variant-proxied) calls this recipe `proxied`: the compose file `docker-compose.proxied.example.yml`,
the nginx files with `LISTENER=behind-proxy`, and a proxy that sends the host name to `http://ohif:8080`. Follow the steps
there. This part explains the two points that matter for the login and shows how to check them.

```text
 Browser ---- https ---->  Proxy ---- http ---->  nginx (container ohif, port 8080)  ---->  arc
                           ends TLS               login, locks, audit log
                           writes the address of the PC into X-Forwarded-For
```

**Point 1: nginx must see the address of the PC.** The connection to nginx comes from the proxy, so nginx sees the address of
the proxy. The proxy therefore writes the address of the PC into the header `X-Forwarded-For`. The listener `behind-proxy`
makes nginx read the address from this header. nginx believes the header only when the connection comes from the subnet in the
line `set_real_ip_from` of `pacs/listener/server.conf`. That is the subnet of the Docker network that the proxy and nginx
share. The shipped line holds the address `203.0.113.1`, a documentation address that no real proxy uses. It trusts nobody:
until you replace it, nginx ignores the header and the audit log names the proxy for every request (tested). The audit log,
the lists of the login `none` and the lock-out check of the firewall tab all use this address.

**Point 2: only the proxy may reach nginx.** The compose file publishes no port, for this reason. Anything that reaches nginx
from the trusted subnet can write any address into `X-Forwarded-For`. With the login `none` that address decides the level.
So use a Docker network that only the proxy and nginx share.

The login works as in the sections before. With `basic`, the browser asks for the name and the password, and the proxy must
pass the header `Authorization` on to nginx. The accounts are those of [section 3](#login-basic). With `none`, the two lists of
[4.2](#login-none-lists) work on the address from the header.

> **Warning**
>
> A wrong `set_real_ip_from` fails in one of two ways. A range that is too wide, for example a network that other containers
> use, lets any of them choose its own address: with the login `none` that can open the admin level. A range that does not
> hold the proxy, and the shipped address too, makes nginx ignore the header. nginx then sees the address of the proxy. The
> audit log names the proxy for every request, and with the login `none` every request gets 403 (tested). A client that is
> not the proxy cannot choose its address: its header is ignored (tested). Write the subnet of the one network that the proxy
> and nginx share, nothing wider.

> **Check**
>
> Open `https://pacs.example.org/` on a PC and sign in. Then read the newest rows of the log `zugriffe` on the server
> ([8.3](#login-audit-read) explains the command):
>
> ```bash
> python3 /opt/pacs-admin/server/pacsdb.py protokoll zugriffe "$(date +%F)" | tail -n 3
> ```
>
> Expected: in every row of your request, `ip` is the address of the PC and not the address of the proxy. This row comes from
> the test with the PC address 192.0.2.77 (login `basic`):
>
> ```text
> {"t":"2026-10-14T09:00:26+00:00","u":"vera","sub":"vera","ip":"192.0.2.77","r":"/","status":200}
> ```
>
> A request without the header shows the address of the proxy. In the test this was `127.0.0.1`, the address of the test
> client. If all rows show the proxy, nginx does not read the header. Check the line first with
> `grep -n set_real_ip_from /opt/ohif/nginx/pacs/listener/server.conf`: it must not hold the shipped `203.0.113.1`. Then
> see [troubleshooting](troubleshooting.md#proxy-wrong-address).

<a id="login-other-oauth2"></a>
### 5.2 oauth2-proxy behind your own proxy

Single sign-on works behind a proxy too. The compose file `docker-compose.proxied.example.yml` has no service `ohif-auth`, so
you copy that service from the compose file of oauth2-proxy. Read [section 2](#login-oauth2) first. The provider side (steps 1
to 6 of [2.3](#login-oauth2-entra), or [2.6](#login-oauth2-providers)) and the secrets (step 7) stay as written. The list below
names only what differs. Do the steps in this order:

1. **Register the redirect URI** `https://pacs.example.org/oauth2/callback`, with the host name that the browser uses at the
   proxy. The proxy must pass the header `Host` unchanged and send every path, `/oauth2/` included, to nginx.
2. **Build the nginx files** with `LOGIN=oauth2-proxy; VIEWER=ohif; LISTENER=behind-proxy` in
   [step 4.9 of the install guide](install.md#nginx-files). Set `set_real_ip_from` as in [5.1](#login-other-proxied).
3. **Set both network names** in `/opt/ohif/docker-compose.yml`: the network of dcm4chee and the network of the proxy. The
   install guide does this in [step 4.10](install.md#compose-file) and in the part about the variant
   [`proxied`](install.md#variant-proxied).
4. **Create `ohif-auth.env`** with step 7 of [2.3](#login-oauth2-env).
5. **Merge the service `ohif-auth`** into the compose file (next block).
6. **Set the five values** with [step 8](#login-oauth2-edit), then the admin group with [step 9](#login-oauth2-site).
7. **Start and check** with [step 10](#login-oauth2-start).

Item 5 copies the block of the service `ohif-auth` from the oauth2 file (from the comment `# Login: nginx asks this container`
up to the comment `# The Docker network`) into your file, above the line `networks:`. Then it removes the mount of the folder
`htpasswd`, because this login has no password files.

```bash
cd /opt/ohif
awk 'FNR==NR { if (/^  # Login: nginx asks this container/) p=1; if (/^# The Docker network/) p=0; if (p) blk = blk $0 "\n"; next } /^networks:/ { printf "%s", blk } { print }' /opt/pacs-admin/deploy/compose/docker-compose.oauth2.example.yml docker-compose.yml > docker-compose.merged.yml
mv docker-compose.merged.yml docker-compose.yml
sed -i '\|^ *- \./htpasswd:/etc/nginx/htpasswd:ro|d' docker-compose.yml
```

You can merge by hand instead. Open both files. In the oauth2 file, copy the lines from `  # Login: nginx asks this container ...`
down to the line before `# The Docker network of your dcm4chee project`. Paste them above the line `networks:` of your file.
Delete the line `- ./htpasswd:/etc/nginx/htpasswd:ro`.

> **Check**
>
> ```bash
> grep -n 'CHANGE-M[E]' /opt/ohif/docker-compose.yml
> docker compose -f /opt/ohif/docker-compose.yml config --services
> ```
>
> Expected: five marker lines (the tenant ID, the two groups, the redirect URL and the subnet) and the two services. The line
> numbers can differ by a few lines. The second command needs the file `ohif-auth.env` of item 4. These lines come from the
> test:
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
> A sixth marker line at the end of the file (`name of the network of your proxy`) means that the name of the proxy network is
> still unset. Set it before [step 8](#login-oauth2-edit): the last `sed` expression of step 8 would delete the marker and leave
> the shipped name `proxy_default`. If the merge copied nothing, the service `ohif-auth` is missing from the output of the second
> command: merge by hand.

> **Warning**
>
> In [step 8](#login-oauth2-edit), write the subnet of the **network of dcm4chee** into `--trusted-proxy-ip`, not the subnet of
> the proxy network. nginx and oauth2-proxy talk to each other in the network of dcm4chee, and oauth2-proxy believes the
> `X-Forwarded-*` headers only from there. The merged file puts `ohif-auth` into that network only, so the proxy cannot reach it.
> The command `docker network inspect NAME -f '{{(index .IPAM.Config 0).Subnet}}'` with the name of that network shows the
> subnet.

After the start, sign in once from a PC and read the audit log as in [5.1](#login-other-proxied): `ip` must be the address of
the PC. Whether the sign-in works end to end through a proxy was not run, because no real oauth2-proxy and no real provider
ran here.

<a id="login-other-proxy-login"></a>
### 5.3 A login at the proxy

Some proxies check a login before they pass a request on, for example Cloudflare Access, or a forward-auth service next to
Traefik or Caddy. Such a gate can stand in front of nginx as an extra layer. It does not replace the login in nginx. nginx
decides the level (viewer or admin) and names the account in the audit log. It takes the name only from its own login: the
name in the header `Authorization` with `basic`, the answer of oauth2-proxy with `oauth2-proxy`, and the address of the PC with
`none`. It does not read a name from a header that the proxy sets.

So choose one login from the sections 2 to 4 and keep it. The gate at the proxy and the login in nginx then work one after the
other. If the gate at the proxy also uses HTTP basic authentication, do not combine it with the login `basic`: a request
carries one header `Authorization`, and both logins read it. This setup was not tested.

<a id="login-unsupported"></a>
## 6. Not supported

These setups do not work, or nobody tested them. [reference.md](reference.md#front-door-contract) states what a front door
must do.

<a id="login-unsupported-keycloak"></a>
### 6.1 dcm4chee with its own Keycloak login

dcm4chee ships images with a Keycloak login (their names end in `-secure` or `-secure-ui`) and images without one. The admin
page and nginx send no login token to the archive, so the archive must run without Keycloak: the image `dcm4chee-arc-psql`.
The archive then has no login of its own. The login of this page is the only one, and nginx is the only door.

> **Warning**
>
> Anybody who reaches port 8080 or 8443 of the container `arc` can use the archive without a login. Close both ports from
> outside: block them in the firewall ([modules.md](modules.md#firewall-block)), or publish them on `127.0.0.1` only. The
> requirements of the optional dcm4chee interface repeat this ([modules.md](modules.md#dcm4chee-ui)).

<a id="login-unsupported-front"></a>
### 6.2 Another program instead of nginx

Traefik, Caddy and Cloudflare Access cannot take the place of nginx. Nobody tested it. The locks on the paths, the header
`X-PACS-Admin`, the audit log and the link to the helper service are features of the nginx files, and the audit lines need a
shipper that sends them to the helper service ([reference.md](reference.md#audit-feed)). Put these products in front of nginx
instead ([section 5](#login-other)). A program that meets the whole contract of
[reference.md](reference.md#front-door-contract) can work, but this repository neither ships nor tests one.

<a id="login-unsupported-more"></a>
### 6.3 Logins that the nginx files do not contain

- **Two logins at once**, for example oauth2-proxy for viewers and basic for admins. You copy the files of one method into
  `pacs/login/`. A mix needs your own nginx files.
- **Active Directory without Entra ID.** A Windows domain alone does not speak OIDC. See [2.6](#login-oauth2-providers).
- **A provider that speaks only SAML.** oauth2-proxy speaks OpenID Connect and OAuth 2.0, not SAML.
- **Windows integrated sign-in (Kerberos or NTLM).** nginx does not offer it.

<a id="login-access"></a>
## 7. Who can open what

The login tells nginx who is asking. nginx then decides what that account may open. There are two levels: [any
account](glossary.md#any-account) (the viewer level of [section 1](#login-choose)) and [admin](glossary.md#admin-account). The
locks on the paths are the same for every login. Only the way to a level differs.

<a id="login-access-levels"></a>
### 7.1 How each login sets the level

| Login | Any account | Admin |
|---|---|---|
| oauth2-proxy | The user is in one of the groups of the lines `--allowed-group` in the compose file. | The user is in the group `$pacs_admin_group` of `pacs/site.conf`. |
| basic | The account is in the file `users`. | The account is in the file `admins`. |
| none | The address of the PC is on the list of `pacs/login/server.conf`. | The address of the PC is on the list of `pacs/login/admin.conf`. |

An admin is also a viewer. The three logins make sure of it in different ways:

- **oauth2-proxy:** the admin group is one of the `--allowed-group` lines. Nothing more is needed. With Google the admin level
  is an e-mail list instead of a group ([2.6](#login-oauth2-google)).
- **basic:** the script `pacs-adduser.sh` writes an admin into both files ([3.5](#login-basic-accounts)). The viewer pages read
  `users`, and `/admin/` reads `admins`.
- **none:** an admin PC must be on both lists. The admin list replaces the viewer list for `/admin/` and for the changes
  ([4.2](#login-none-lists)).

An admin group that is empty or still a placeholder locks the admin level. An empty `$pacs_admin_group` gives 500 on
`/admin/`. The shipped placeholder `00000000-0000-0000-0000-000000000000` gives 403 for everybody, so nobody is admin
([step 9](#login-oauth2-site) for Entra ID, [Step D](#login-oauth2-group-names) for other providers).

<a id="login-access-paths"></a>
### 7.2 What each level opens

| What | Path | Level | Header `X-PACS-Admin` |
|---|---|---|---|
| Viewer start page and its files (viewer mode `ohif`) | `/`, `/index.html`, `/app-config.js` | any account | no |
| Study search of the viewer and of the admin page | `GET /dcm4chee-arc/aets/DCM4CHEE/rs/studies` | any account | no |
| Reads of the viewer: studies, series, instances, WADO | `GET` below `/dcm4chee-arc/aets/DCM4CHEE/` | any account | no |
| Account name at the top of the admin page | `/oauth2/userinfo` | any account | no |
| Admin page and its numbers | `/admin/`, `/admin/daten/` | admin | no |
| Helper service of the admin page: disks, firewall, audit log | `/admin/dienst/` | admin | every `POST`, and the `GET` calls `platten` and `firewall?neu=1` |
| Patient list and view of rejected studies | `GET .../rs/patients`, `GET .../IOCM_QUALITY/rs/studies` | admin | no |
| Every change of studies and patients: edit, move, reject, restore, merge, delete | `POST`, `PUT` or `DELETE` on exactly the paths of `pacs.conf` | admin | yes |
| The optional dcm4chee interface | `/dcm4chee-arc/ui2/` | admin | no |

The header `X-PACS-Admin` carries a short text about the action. Only the admin page sets it. A change without it gets 403,
also from an admin. A web page of another site cannot make the browser of an admin send the header. The header is no login.
The audit log keeps its text ([section 8](#login-audit)).

More locks keep an admin from a wrong click: a study change names exactly one study, a patient edit never merges, and a
delete works only on rejected studies. [reference.md](reference.md#contract-paths) lists them. With the viewer mode `none`
there is no viewer: `/` redirects to `/admin/`, and the reads of the viewer answer 404.

> **Warning**
>
> The optional dcm4chee interface has none of these locks. Whoever may open it can delete studies and change the
> configuration of the archive. Give the admin level only to people whom you would also trust with that interface, or switch
> the interface off ([modules.md](modules.md#dcm4chee-ui-off)). [modules.md](modules.md#dcm4chee-ui) describes it.

<a id="login-access-public"></a>
### 7.3 Answers that need no login

A few answers carry no data. nginx gives them before it checks the login, so they work for everybody:

- `/admin` answers 301 and points to `/admin/`.
- A path that holds a semicolon, a backslash or `%5c` before any `?` answers 400. The archive could read these spellings as a
  way out of an allowed path, so nginx refuses them.
- A change that one of the locks refuses answers 403, also without a login: a change without the header `X-PACS-Admin`, a study
  change or move with another query than the admin page sends, and a patient edit with `merge`. A change that passes the locks
  answers 401 without a login (tested with the login `basic`).
- Every other path below `/dcm4chee-arc/` that the table in 7.2 does not name answers 404.
- With the optional dcm4chee interface: `/dcm4chee` answers 301, `/dcm4chee-arc/ui2/` answers a three-line script, and two
  files named `keycloak.json` answer `{}`.
- With the viewer mode `none`: `/` answers 302 and points to `/admin/`, and every unknown path answers 404.
- With the login oauth2-proxy: the paths below `/oauth2/` belong to the sign-in. They are the way in, so they need no session.

<a id="login-access-refused"></a>
### 7.4 What a refused user sees

| The request | oauth2-proxy | basic | none |
|---|---|---|---|
| No session, no name, or a PC on no list | 302 to the sign-in page of the provider | 401, the browser asks for name and password | 403 |
| A known account on a level it does not have, for example a viewer on `/admin/` | 403 | 401, the browser asks again | 403 |
| A change without the header `X-PACS-Admin` | 403 | 403 | 403 |

With `basic` the answer is always 401, because basic authentication cannot say "known, but not allowed". The browser then
asks again, and a viewer who types the password again meets 401 again. With `none` the user sees the page `403 Forbidden`,
and the reason is in the log of nginx ([4.3](#login-none-check)). A change without the header is refused first, before the
login runs, so a person who is not signed in gets 403 too.

> **Check**
>
> Ask four paths from a PC without a login. Use `-k` only with a self-signed certificate.
>
> ```bash
> for p in / /admin/ /dcm4chee-arc/aets/DCM4CHEE/rs/studies /dcm4chee-arc/aets/DCM4CHEE/rs/patients; do
>   printf '%s  ' "$p"; curl -sk -o /dev/null -w '%{http_code}\n' "https://pacs.example.org$p"
> done
> ```
>
> Expected: the same number four times. With `basic` it is `401`, with `none` (the PC is on no list) it is `403`, and with
> oauth2-proxy it is `302`. Output of the test with `basic`:
>
> ```text
> /  401
> /admin/  401
> /dcm4chee-arc/aets/DCM4CHEE/rs/studies  401
> /dcm4chee-arc/aets/DCM4CHEE/rs/patients  401
> ```
>
> A `200` means that a path opens without a login. Stop and check the nginx files of [install.md](install.md#nginx-files).
> A `404` or `502` means that the container is not what you think it is: see
> [troubleshooting](troubleshooting.md#every-page-500).

**What was tested.** In the runs of the logins `basic` and `none`, a script went through all 26 locations of the nginx files.
Each location either asks for the login or belongs to the answers in 7.3 (26 of 26). The script is not part of this
repository. The check above ran with `basic` and `none` in Docker. The `302` for oauth2-proxy comes from a run with a
stand-in that answers like oauth2-proxy, not from a real oauth2-proxy.

<a id="login-audit"></a>
## 8. What the audit log records

The audit log records who searched, who opened what and who changed what. nginx writes one line for each request. The
[helper service](glossary.md#helper-service) stores the lines in an encrypted database, and the tab `Protokoll` of the admin
page shows them. What a line says about the person depends on the login. This section shows the lines of each login and how
to read them. [reference.md](reference.md#audit-log) holds the complete rules.

<a id="login-audit-fields"></a>
### 8.1 What each login writes into a line

A line is one JSON object with the fields `t`, `u`, `sub`, `ip`, `r` and `status`. The login decides the fields `u` and `sub`:

| Field | Meaning | oauth2-proxy | basic | none |
|---|---|---|---|---|
| `u` | The account name. The tab shows it. | The claim `preferred_username`. If it is empty: the e-mail address, then the ID of the account, then `anon-` and the address of the PC. | The name that the client sent, also when the password was wrong. `anon-` and the address when the client sent no name. | Always `anon-` and the address of the PC. |
| `sub` | The ID that the login reports. | The header `X-Auth-Request-User` of oauth2-proxy. It is empty when the check refused the request: no session, or an account that is not allowed. | The same as `u`. | The same as `u`. |

`sub` is only the name of the field. What oauth2-proxy puts into `X-Auth-Request-User` depends on its configuration and on the provider; it is not necessarily the claim `sub` of the ID token.

The other fields do not depend on the login. `t` is the time, with the offset of the server. `ip` is the address of the PC.
nginx takes it from the connection, and the listener `behind-proxy` takes it from the header of your proxy
([5.1](#login-other-proxied)). `r` is the path of the request with its query, and `status` is the answer of nginx.

Every line carries a tag. The tag decides where the line is stored:

| Tag | What it holds |
|---|---|
| `zugriffe` | Every request, also the refused ones and the static files of the viewer. |
| `ereignisse` | The `GET` requests that people care about: searches, opened studies and opened reports. |
| `admin` | Every request to a path that changes data, and every `POST` to `/admin/dienst/`. |

A change through the admin page writes two lines, one under `zugriffe` and one under `admin`. The line under `admin` has four
more fields: `m` (the method), `uri` (the full address), `k` (the description that the page sends in the header `X-PACS-Admin`,
URL-encoded) and `body` (what the change sent). Its field `r` always holds the word `admin`.

<a id="login-audit-rows"></a>
### 8.2 Example lines for each login

The lines below come from tests in Docker with nginx 1.30.5 and the current nginx files. The time ends in `+00:00` (UTC),
because the test container had no time zone. On your server `t` shows the offset of the server, because the shipped compose
files mount `/etc/localtime`. The study number and the other values are test data.

**Login basic.** The test PC has the address 192.0.2.77. A viewer searches studies. The tag is `ereignisse`, and the same line
is under `zugriffe`:

```text
{"t":"2026-10-14T09:29:27+00:00","u":"viewer.user","sub":"viewer.user","ip":"192.0.2.77","r":"/dcm4chee-arc/aets/DCM4CHEE/rs/studies?limit=1","status":200}
```

The same viewer asks for `/admin/` and meets 401. The line names the account, because the browser sent the name:

```text
{"t":"2026-10-14T09:29:29+00:00","u":"viewer.user","sub":"viewer.user","ip":"192.0.2.77","r":"/admin/","status":401}
```

A request without a name gets 401, and the name is `anon-` and the address:

```text
{"t":"2026-10-14T09:29:30+00:00","u":"anon-192.0.2.77","sub":"anon-192.0.2.77","ip":"192.0.2.77","r":"/dcm4chee-arc/aets/DCM4CHEE/rs/studies","status":401}
```

A wrong password gets 401 too. The line carries the name that was typed. So a 401 row for a name does not mean that this
person did something:

```text
{"t":"2026-10-14T09:29:32+00:00","u":"viewer.user","sub":"viewer.user","ip":"192.0.2.77","r":"/dcm4chee-arc/aets/DCM4CHEE/rs/studies?limit=1","status":401}
```

An admin changes a study. This line is under the tag `admin`. `k` is the description that the page sent (here
`Testaktion · Studie`), and `body` is the data of the change:

```text
{"t":"2026-10-14T09:29:33+00:00","u":"admin.user","sub":"admin.user","ip":"192.0.2.77","r":"admin","m":"POST","uri":"/dcm4chee-arc/aets/DCM4CHEE/rs/studies/update?reasonForModification=CORRECT&StudyInstanceUID=1.2.840.1.2","status":200,"k":"Testaktion%20%C2%B7%20Studie","body":"{\"00100010\":{\"vr\":\"PN\"}}"}
```

A change without the header `X-PACS-Admin` gets 403, also for an admin. Here an admin sent a `POST` to the helper service
without it. The line shows the account, and `k` is empty:

```text
{"t":"2026-10-14T09:29:43+00:00","u":"admin.user","sub":"admin.user","ip":"192.0.2.77","r":"admin","m":"POST","uri":"/admin/dienst/freigeben","status":403,"k":"","body":""}
```

**Login none.** Every line names an address. In the test the viewer PC has the address 192.0.2.202, the admin PC has
192.0.2.201, and a third PC, 192.0.2.203, is on no list. The viewer PC searches studies:

```text
{"t":"2026-10-14T09:30:10+00:00","u":"anon-192.0.2.202","sub":"anon-192.0.2.202","ip":"192.0.2.202","r":"/dcm4chee-arc/aets/DCM4CHEE/rs/studies?limit=1","status":200}
```

The PC on no list asks for `/admin/` and gets 403. The log of nginx names the rule that refused it
([4.3](#login-none-check)):

```text
{"t":"2026-10-14T09:30:15+00:00","u":"anon-192.0.2.203","sub":"anon-192.0.2.203","ip":"192.0.2.203","r":"/admin/","status":403}
```

The admin PC changes a study:

```text
{"t":"2026-10-14T09:30:19+00:00","u":"anon-192.0.2.201","sub":"anon-192.0.2.201","ip":"192.0.2.201","r":"admin","m":"POST","uri":"/dcm4chee-arc/aets/DCM4CHEE/rs/studies/update?reasonForModification=CORRECT&StudyInstanceUID=1.2.840.1.2","status":200,"k":"Testaktion%20%C2%B7%20Studie","body":"{\"00100010\":{\"vr\":\"PN\"}}"}
```

**Login oauth2-proxy.** No recorded line exists, because no real identity provider took part in the tests. A line has this
form. The words in capitals stand for the values of your sign-in:

```text
{"t":"TIME","u":"USER NAME","sub":"USER ID","ip":"ADDRESS OF THE PC","r":"/","status":200}
```

`u` is usually the sign-in name of the user. At Entra ID this is a name of the form `name@domain`. Two kinds of request carry
no account. Their lines show `anon-` and the address in `u`, and `sub` is empty:

- A request without a session gets status 302. nginx sends the browser to the sign-in page of the provider.
- A user who is signed in but not allowed, for example a viewer on `/admin/`, gets status 403. The failed check sends no
  account, so the line does not name the user.

A test with a stand-in for oauth2-proxy produced these two lines. The stand-in sends the headers of the account only with an
accepted check, and the source of oauth2-proxy does the same. The PC was the test container, address 127.0.0.1:

```text
{"t":"2026-10-14T11:33:43+00:00","u":"anon-127.0.0.1","sub":"","ip":"127.0.0.1","r":"/","status":302}
{"t":"2026-10-14T11:33:43+00:00","u":"anon-127.0.0.1","sub":"","ip":"127.0.0.1","r":"/admin/","status":403}
```

**What a row proves.** The line names the account, and the login decides how much that means:

- **oauth2-proxy:** a person signed in at the identity provider. The rules of the provider apply, for example a second factor.
- **basic:** somebody who knew the password of the account. A shared account hides who did what.
- **none:** a PC, not a person. Several people can work at one PC.
- **A refused request:** no verified account. Compare `ip` and the time with the other rows of the same PC.

<a id="login-audit-read"></a>
### 8.3 Read the log

**In the admin page.** The tab `Protokoll` lists the lines of the tags `ereignisse` and `admin` for the chosen days, the
newest first. The columns are `Zeit`, `Wer`, `Was`, `Patient` and `Studie`. `Wer` shows the account without the part after the
`@`, and the PC below it. The filter `Konto` (the field says `Teil der Anmeldung`) searches the full name and ignores upper and
lower case. The filter `Art` has the entry `nur Abgelehntes und Fehler`, which lists the refused and failed requests. The
button `Als CSV speichern` saves the list with the full account names. The tab does not show the tag `zugriffe`.

**On the server.** As root, the program `pacsdb.py` of the helper service prints the stored lines of one tag. It reads all
three tags, so it also shows `zugriffe`. The arguments are the tag and, optional, the first and the last day as `YYYY-MM-DD`.
The last day is included. The lines come out as stored, the newest last:

```bash
python3 /opt/pacs-admin/server/pacsdb.py protokoll zugriffe "$(date +%F)" | tail -n 5
```

To follow one PC, filter the lines with `grep`. The same works for an account name:

```bash
python3 /opt/pacs-admin/server/pacsdb.py protokoll zugriffe "$(date +%F)" | grep -F '"ip":"192.0.2.77"'
```

If you changed `PROTOKOLL_DB` or `PROTOKOLL_KEY` in `/etc/default/pacs-admin`, load the file first with
`set -a; . /etc/default/pacs-admin; set +a`. A wrong path to the database creates an empty database, so an empty output can
mean a wrong path. [reference.md](reference.md#audit-read) lists all options, and it shows how to read the same rows from the
socket of the helper service.

> **Check**
>
> Sign in from a PC, open the viewer, and read the newest lines:
>
> ```bash
> python3 /opt/pacs-admin/server/pacsdb.py protokoll zugriffe "$(date +%F)" | tail -n 3
> ```
>
> Expected: your requests are the last lines. `u` names your account (login basic and oauth2-proxy) or your PC (`anon-` and its
> address, login none), and `ip` is the address of your PC. The lines of [8.2](#login-audit-rows) are the pattern. If the
> output is empty or your requests are missing, look for lost lines:
>
> ```bash
> docker logs ohif 2>&1 | grep 'to syslog'
> ```
>
> No output means that nginx lost no line. Lines with `to syslog` mean that nginx could not reach the helper service. Read
> [reference.md](reference.md#audit-lost) for the messages and the cause. If nginx lost no line and your requests are still
> missing, see [troubleshooting](troubleshooting.md#audit-lines-missing).

> **Warning**
>
> The audit log holds patient IDs and names, taken from search addresses and from the data of changes. Nothing prunes the log,
> and it grows with every request. Treat it like patient data. Restrict the access to the server and to the folder
> `/var/lib/pacs-protokoll/`, keep a copy of the key ([install.md](install.md#backup-audit-key)), and decide how long you keep
> the rows ([reference.md](reference.md#audit-retention)).
