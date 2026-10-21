# Optional modules

English | [Deutsch](modules.de.md)

The base install ([install.md](install.md)) leaves your dcm4chee archive as it is. This page describes three optional modules.
Each module stands alone. Use none, one or all of them.

Run all commands as root. Every step ends with a **Check** box that shows how to see that the step worked. A **Warning** box
names what can break, how long it lasts and how to go back.

- [1. The three modules](#modules-overview)
- [2. Change the compose file of dcm4chee once](#recreate-arc)
- [3. Disk assistant](#disk-assistant)
- [4. Firewall](#firewall)
- [5. The dcm4chee user interface through the front door](#dcm4chee-ui)

<a id="modules-overview"></a>
## 1. The three modules

| Module | Who needs it | What it changes | Outage |
|---|---|---|---|
| [Disk assistant](#disk-assistant) | You add disks to the archive and want to do it from the admin page, without typing LDAP commands. | The compose file of dcm4chee. For every new disk: a file system, a line in `/etc/fstab` and a [storage](glossary.md#storage) in the configuration of dcm4chee. | `arc` restarts once, for the compose change. |
| [Firewall](#firewall) | Many networks reach the server and you want to limit who may open the ports for DICOM, HL7 and management. | The compose file of dcm4chee, rules in the packet filter of the kernel, one systemd unit. | `arc` restarts once, for the compose change. |
| [dcm4chee user interface](#dcm4chee-ui) | Admins use the web interface of dcm4chee itself and want to reach it through the front door. | One nginx file. | None. nginx reloads. |

Terms used on this page:

- **`arc`** is the dcm4chee archive container. `ldap` is its configuration server. See [LDAP](glossary.md#ldap).
- The **compose file of dcm4chee** is the `docker-compose.yml` of your dcm4chee project. This page writes the folder as
  `/opt/dcm4chee-arc`. Use your own folder ([compose project](glossary.md#compose-project)).
- The **front door** is the web server in front of the admin page, the viewer and dcm4chee ([glossary](glossary.md#front-door)).
- The **repository folder** holds the files of this project on your server. This page writes it as `/opt/pacs-admin`
  ([install.md](install.md#get-files)). Use your own folder if it differs.

Before you start:

- The base install works. The admin page opens and the tab `Übersicht` (overview) shows its tiles
  ([install.md](install.md#first-test)).
- You can plan a short outage of the archive. The disk assistant and the firewall both recreate `arc`.

<a id="recreate-arc"></a>
## 2. Change the compose file of dcm4chee once

The disk assistant and the firewall both need a change in the compose file of dcm4chee. A changed compose file makes Docker
recreate the container `arc`. Docker stops the old container, removes it and starts a new one. The archive cannot be reached
from the stop until dcm4chee has started again. The script of the disk assistant estimates 30 seconds. A large archive can need
longer.

Make all edits for the modules you want in one session and recreate once. The archive is then down once, not once per module.
If you want only the dcm4chee user interface ([section 5](#dcm4chee-ui)), skip this section.

<a id="edits-overview"></a>
### 2.1 The three edits

| Edit | What it changes in the compose file | Needed by |
|---|---|---|
| A | Adds the volume `/mnt/fs:/mnt/fs:rslave` to the service `arc`. | Disk assistant |
| B | Writes the ports of the service `arc` with the address `0.0.0.0`. | Firewall |
| C | Adds the password of the LDAP root account to the environment of the service `ldap`. | Disk assistant, only if the check in step 6 says `missing` |

<a id="edits-steps"></a>
### 2.2 Step by step

#### Step 1. Copy the compose file

Find the compose file and keep a copy. The copy is your way back.

```bash
docker inspect -f '{{index .Config.Labels "com.docker.compose.project.config_files"}}' arc
```

Example output: `/opt/dcm4chee-arc/docker-compose.yml`. If the label lists several files, separated by commas, copy all of them and
make each edit in the file that defines the service.

```bash
cp -a /opt/dcm4chee-arc/docker-compose.yml /root/dcm4chee-compose.before-modules.yml
```

> **Check**
>
> ```bash
> ls -l /root/dcm4chee-compose.before-modules.yml
> ```
>
> Expected: one line that shows the file with the size of your compose file. If the file is missing, do not go on.

#### Step 2. Check that the project runs

Start from a working state. Then every problem after the change comes from the change.

```bash
cd /opt/dcm4chee-arc
docker compose ps
```

> **Check**
>
> Expected: `arc`, `ldap` and `db` show `Up` at the start of the column `STATUS`. If one of them does not, fix that first.
> A broken project stays broken after the change.

#### Step 3. Check mount propagation (edit A only)

The volume of edit A uses the flag `:rslave`. With it, a disk that the server mounts later also appears inside `arc`. Docker
accepts the flag only when the server has set up the mount of `/` for sharing ([mount propagation](glossary.md#mount-propagation)).
Check this before you edit. The folder must exist, because `findmnt` prints nothing for a folder that does not exist.

```bash
mkdir -p /mnt/fs
findmnt -T /mnt/fs -o TARGET,PROPAGATION
```

> **Check**
>
> Expected: a header line and one line whose second column is `shared` or `slave`. Example:
>
> ```text
> TARGET PROPAGATION
> /      shared
> ```
>
> Most servers with systemd show `shared`. If the second column says `private`, make the root mount shared:
>
> ```bash
> mount --make-rshared /
> findmnt -T /mnt/fs -o TARGET,PROPAGATION
> ```

> **Warning**
>
> `mount --make-rshared /` holds until the next reboot. Run the `findmnt` command again after the first reboot of the server.
> If it says `private` again, make the change permanent in the way your system provides (for example a small systemd unit that
> runs the command at boot). To go back now, run `mount --make-rprivate /`. If the command fails, do not edit the compose file:
> Docker would refuse the volume and `arc` would stay down.

#### Step 4. Edit A: add the volume (disk assistant)

Open the compose file in the editor you use (for example `nano /opt/dcm4chee-arc/docker-compose.yml`). In the service `arc`, add
one line to the list `volumes:`. Keep the lines that are already there.

```yaml
  arc:
    volumes:
      # the existing lines stay as they are
      - /mnt/fs:/mnt/fs:rslave
```

If you set `STORAGE_BASE` to another folder in `/etc/default/pacs-admin`, write that folder on both sides of the colon. Keep
the indentation of the other lines. YAML does not accept tabs.

> **Warning**
>
> Once the disk assistant has created its first storage, this volume carries your images. If you take it out again, dcm4chee
> cannot read the images on the new disks, and new images land inside the container. Go back before the first disk only
> ([2.3](#recreate-rollback)).

#### Step 5. Edit B: write the ports with the address (firewall)

Docker publishes a port that has no address on all IPv4 addresses and often on all IPv6 addresses as well. The firewall filters
IPv4 only. A port that is also open over IPv6 passes it. The address `0.0.0.0` makes Docker publish on IPv4 only. The admin page
shows the badge `IPv6 nicht gefiltert` (IPv6 not filtered) at a port that Docker still publishes over IPv6.

In the service `arc`, **replace** the whole list `ports:`. Do not add a second list and do not add lines next to the old ones.
Keep one entry for each port. Write the host port that your file has now. This is the usual list of dcm4chee:

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

- A port that your file maps to another host port keeps that host port. For example `"104:11112"` becomes
  `"0.0.0.0:104:11112"`. Then set `FW_DICOM_PORTS` ([4.10](#firewall-settings)).
- A port that your file already binds to an address, for example `"127.0.0.1:8080:8080"`, stays as it is.
- Ports of other containers (LDAP `389`, Kibana `5601`, Portainer `8000` and `9443`) get the same prefix in the compose file
  that publishes them.
- Do not close ports in this step. The edit only changes how Docker publishes them. Who may reach them is decided later, in
  [section 4](#firewall).

> **Warning**
>
> Clients that reach these ports over an IPv6 address lose the connection after the recreate. DICOM devices and HL7 senders
> normally use IPv4 addresses. Check this in [4.2](#firewall-inventory) before you recreate. To go back, restore the copy of
> step 1.

#### Step 6. Edit C: let the assistant log in to LDAP (disk assistant)

The assistant changes the configuration of dcm4chee in the LDAP server. It runs `ldapsearch` and `ldapmodify` inside the
container `ldap` and reads the root password from the environment of that container. The host stores no password. The container
needs `LDAP_ROOTPASS` (the password) or `LDAP_ROOTPASS_FILE` (the path of a file inside the container that holds it). This
command tells whether one of them is set and does not print it:

```bash
docker exec ldap sh -c 'if [ -n "${LDAP_ROOTPASS:-}${LDAP_ROOTPASS_FILE:-}" ]; then echo set; else echo missing; fi'
```

If the answer is `set`, do nothing in this step. If the answer is `missing`, add the line below to the service `ldap`, in its
`environment:` list. Write the root password that the LDAP server has now. The assistant only reads this value. It does not
change the password of the server.

```yaml
  ldap:
    environment:
      # the existing lines stay as they are
      LDAP_ROOTPASS: CHANGE-ME-ldap-root-password
```

Use the notation of the lines around it: if they read `NAME=value` in a list, write `- LDAP_ROOTPASS=...`. If the LDAP
container has another name than `ldap` in your project, use that name in the command above and set `LDAP_CONTAINER`
([3.2](#disk-prepare)).

> **Warning**
>
> The compose file now holds the LDAP password in plain text. Restrict the file to root (`chmod 600`) and do not copy it to a
> place that others read. A change in the environment recreates `ldap` as well: dcm4chee cannot read its configuration for a
> moment. To go back, restore the copy of step 1.

#### Step 7. Check the file and preview the change

```bash
cd /opt/dcm4chee-arc
docker compose config --quiet
```

> **Check**
>
> Expected: no output. An error message names the line of the YAML problem. Fix it and run the command again. Then open the
> file once more and read your edits: only the lines of A, B and C differ from the copy.
>
> ```bash
> diff /root/dcm4chee-compose.before-modules.yml /opt/dcm4chee-arc/docker-compose.yml
> ```

Newer versions of Docker Compose have the option `--dry-run`. With it, `docker compose up -d --dry-run` lists what Docker
would recreate, and it recreates nothing. Expected: a line with `Recreate` for `arc`, and for `ldap` only if you did edit C.

#### Step 8. Recreate once

> **Warning**
>
> This stops `arc` and starts a new container. The archive is unreachable until dcm4chee has started again, 30 seconds or
> more. DICOM devices that send during that time get an error and try again later, or not, depending on the device. Do this
> in a maintenance window. To go back, restore the copy of step 1 and run `docker compose up -d` again ([2.3](#recreate-rollback)).

Name no service. Then Docker recreates every service whose configuration changed, in one run.

```bash
cd /opt/dcm4chee-arc
docker compose up -d
```

Docker prints one line for each container and action: ` Container arc  Recreate`, then `Recreated`, `Starting`, `Started`.
A container without change shows `Running`.

> **Check**
>
> Wait for dcm4chee to start. The log of a recreated container starts empty, so this line proves the new start:
>
> ```bash
> docker logs arc 2>&1 | grep WFLYSRV0025
> ```
>
> Expected: one line with `WFLYSRV0025` that ends with `started in` and a time. If there is no line yet, wait and run the
> command again. After 5 minutes, read the end of the log with `docker logs arc 2>&1 | tail -n 50`.
>
> If you did edit A, check that the volume arrived with the right flag:
>
> ```bash
> docker inspect -f '{{range .Mounts}}{{.Destination}} {{.Propagation}}{{"\n"}}{{end}}' arc | grep '^/mnt/fs '
> ```
>
> Expected: `/mnt/fs rslave`.
>
> If you did edit B, check the ports:
>
> ```bash
> docker ps --format 'table {{.Names}}\t{{.Ports}}'
> ```
>
> Expected: for `arc`, every port shows as `0.0.0.0:PORT->PORT/tcp` without a second entry `[::]:PORT->PORT/tcp`.

If `docker compose up -d` stops with `it is not a shared or slave mount`, Docker has already removed the old `arc`. It created
the new one and could not start it. `arc` is down. See [troubleshooting](troubleshooting.md#arc-rslave-refused).

<a id="recreate-rollback"></a>
### 2.3 Go back

Restore the copy and recreate once more. This undoes all edits at once.

```bash
cp -a /root/dcm4chee-compose.before-modules.yml /opt/dcm4chee-arc/docker-compose.yml
cd /opt/dcm4chee-arc
docker compose up -d
```

> **Warning**
>
> This recreates `arc` again: another outage, as long as in step 8. Two exceptions:
>
> - After the disk assistant has created a storage, keep edit A. Without the volume, dcm4chee cannot read the images on the
>   new disks. Restore the file, add the volume line again, and run `docker compose up -d`.
> - If the firewall is on, it applies its rules again within 5 minutes after the ports change. This is normal.

> **Check**
>
> ```bash
> cd /opt/dcm4chee-arc && docker compose ps
> docker logs arc 2>&1 | grep WFLYSRV0025
> ```
>
> Expected: all services `Up` and one `WFLYSRV0025` line, as in step 8.

<a id="disk-assistant"></a>
## 3. Disk assistant

**Who needs it.** You add disks to the archive over time, for example a new virtual disk in the hypervisor. You want to set up
each new disk from the admin page. Without the assistant, you create the file system, the mount, the line in `/etc/fstab` and
the [storage](glossary.md#storage) in the LDAP configuration of dcm4chee by hand.

**What it changes.** For each new disk, the assistant formats the disk with ext4, mounts it below `/mnt/fs` and adds a line to
`/etc/fstab`. It creates a storage in the configuration of dcm4chee and puts the storage at the end of the
[write list](glossary.md#write-list). Then it tells `arc` to read its configuration again. It does not restart `arc` and it
does not move any image.

> **Warning**
>
> Formatting destroys all data on a disk and cannot be undone. The assistant formats only a disk that is empty: no partition,
> no file system, no signature, not mounted, not in `/etc/fstab`, and a first MiB that holds only zeros. It checks this again
> right before it formats. It cannot know which empty disk you want to keep for another use. Read the size and the model in
> the confirmation text before you confirm.
>
> The assistant needs the change of [section 2](#recreate-arc) first (edit A and, if the check says so, edit C). That change
> stops `arc` for 30 seconds or more. To go back before the first disk, use [2.3](#recreate-rollback). After the first disk,
> use [3.6](#disk-rollback).

<a id="disk-what"></a>
### 3.1 How it works

- **Names.** Each storage is one disk. Its name is the prefix `PACS-Data` and a number with two digits: `PACS-Data01`,
  `PACS-Data02`. The disk is mounted at `/mnt/fs/PACS-Data01`. The same name is the ext4 label, and `/etc/fstab` mounts the
  disk by this label. A device name such as `/dev/sdc` can change after a reboot. The label does not. The assistant takes the
  highest number that it finds in the storages of LDAP, in the folders of `/mnt/fs` and in the `LABEL=` entries of
  `/etc/fstab`, and adds one.
- **Template.** The new storage copies the settings of an existing storage: the first storage of the write list, or, if the
  list is empty, the storage with the highest number that starts with the prefix. It copies all settings, for example the
  threshold (the free space that must stay), but not the name, the path and the mark "full". If it finds no template, it
  stops with `kein Vorlage-Storage gefunden`.
- **Write list.** dcm4chee writes new images to the first storage of the list that is not marked as full. When the free space
  of that storage falls below its threshold, dcm4chee marks it as full and continues with the next storage. dcm4chee never
  removes the mark itself. The assistant adds a new storage at the end of the list. It receives images when the storages in
  front of it are full. The page shows the order ([3.5](#disk-operate)).
- **Plan first.** A command that changes something prints only a plan, unless its last word is `ja`. For example,
  `add /dev/sdc` shows the plan and `add /dev/sdc ja` does the work. The buttons of the page always pass `ja`, after you
  confirm.
- **Log and lock.** Each call prints to the screen. Every call except `kandidaten` also appends to
  `/var/log/pacs-storage.log` (`STORAGE_LOG`). A line such as `=== 2026-10-14 10:15:03 pacs-storage.sh add /dev/sdc ja` starts
  each call in the log. The first checks (the settings file, the prefix, root, the lock) run before the logging starts, so
  their `HALT:` lines are on the screen and not in the log. Only one call runs at a time. A second call waits 30 seconds and
  then prints `laeuft schon`. The script runs as root only.
- **Protective file.** Under every mount point, the assistant puts the file `NO_MOUNT`. You see it only while no disk is
  mounted there, so a missing disk is easy to see.

The script `pacs-storage.sh` in the folder `server` of the repository has these commands:

| Command | What it does |
|---|---|
| `scan` | Makes the kernel look for new and enlarged disks. Lists the storages, the empty disks, the enlarged disks and the mount points without `NO_MOUNT`. Changes nothing. |
| `add /dev/sdX [ja]` | Formats the empty disk, mounts it, writes the `/etc/fstab` line and then runs `activate`. |
| `auto [ja]` | Runs `scan`, then `add` for the one empty disk. With no empty disk or several, it only says so. |
| `activate ID [ja]` | Puts a mounted disk into the archive and at the end of the write list. `add` calls it. Run it alone after you fixed the compose file ([3.4](#disk-first)). |
| `freigeben ID [ja]` | Removes the mark "full". The page button is `Markierung entfernen`. The disk needs `STORAGE_FREE_GB` free. |
| `anhaengen ID [ja]` | Puts a storage at the end of the write list and removes its mark "full". The page button is `In Schreibliste aufnehmen`. The disk needs `STORAGE_FREE_GB` free. |
| `abhaengen ID [ja]` | Takes a storage out of the write list. The images stay readable. The page button is `Aus Schreibliste nehmen`. |
| `grow /dev/sdX [ja]` | Enlarges the file system after you enlarged the disk. It works while the disk is in use. Command line only. |
| `nomount [ja]` | Creates the file `NO_MOUNT` under every mount point that lacks it. |
| `kandidaten` | The same information as `scan` in a form that programs read. `dashboard-status.py` uses it. |

<a id="disk-prepare"></a>
### 3.2 Prepare

#### Step 1. Check the settings

The assistant works with the defaults of a standard dcm4chee install. Change a value only if your install differs. All
settings are lines in `/etc/default/pacs-admin` ([rules for this file](reference.md#env-file-rules)). Each value is a whole
number without a leading zero, or text without spaces. `STORAGE_MIN_GB`, `STORAGE_FREE_GB` and `STORAGE_WARN_GB` take at most
6 digits. A value such as `50GB` or `08` stops the program that reads it. The message continues with
`ist keine ganze Zahl ohne fuehrende Null mit hoechstens 6 Stellen`.

The script runs `bash -n` on the file before it reads it. A syntax error stops the script with
`HALT: /etc/default/pacs-admin hat einen Syntaxfehler (Meldung davor)`. The message of `bash` stands in the line above. The
meaning of each message is in [troubleshooting](troubleshooting.md#disk-halt).

| Setting | Default | Meaning |
|---|---|---|
| `STORAGE_BASE` | `/mnt/fs` | Folder below which the disks are mounted. Use the same folder on both sides of the volume of edit A. |
| `STORAGE_PREFIX` | `PACS-Data` | Name of a disk without the number. It starts with a letter and has up to 14 letters, digits, `-` or `_`. |
| `STORAGE_OWNER` | `1023:1023` | User and group (uid:gid) that own a new disk. This is the account that runs WildFly in the dcm4chee-arc image. |
| `STORAGE_MIN_GB` | `100` | Smallest disk that the assistant offers, in GiB. |
| `STORAGE_FREE_GB` | `50` | Free space in GB that a disk needs before the buttons `Markierung entfernen` and `In Schreibliste aufnehmen` work. |
| `STORAGE_WARN_GB` | `300` | The overview asks for a new disk when the room until the thresholds is below this value, in GB. |
| `STORAGE_LOG` | `/var/log/pacs-storage.log` | Log file of the script. |
| `ARC_CONTAINER` | `arc` | Name of the archive container. |
| `LDAP_CONTAINER` | `ldap` | Name of the LDAP container. |
| `ARC_AET` | `DCM4CHEE` | [AE title](glossary.md#ae-title) of the archive. |
| `ARC_DEVICE` | `dcm4chee-arc` | Name of the archive device in LDAP. |
| `ARC_URL` | `http://127.0.0.1:8080` | REST address of the archive, called from the server itself. Change it if you publish port 8080 on another address. |
| `LDAP_BASE_DN` | `dc=dcm4che,dc=org` | Base of the dcm4chee configuration in LDAP. |

All settings and their effects are in [reference.md](reference.md#config-variables). After a change, run
`systemctl restart pacs-verwaltung`, but not while a disk setup runs ([3.5](#disk-operate)). The script reads the file at
every start. The cron job reads it at its next run.

> **Check**
>
> ```bash
> grep -E '^(STORAGE_|ARC_|LDAP_)' /etc/default/pacs-admin
> ```
>
> Expected: the lines that you changed, or no output when you use all defaults.

#### Step 2. Check that `arc` sees the folder

This step proves that edit A works.

```bash
docker exec arc ls -ld /mnt/fs
```

> **Check**
>
> Expected: one line that starts with `d` and ends with `/mnt/fs`. If the answer is `No such file or directory`, the volume
> is missing: go back to [step 4 of section 2](#edits-steps).

#### Step 3. Check the owner of the files

```bash
docker exec arc id wildfly
```

> **Check**
>
> Expected: a line with the numbers of the account, for example `uid=1023(wildfly) gid=1023(wildfly) groups=1023(wildfly)`.
> If the numbers differ, set `STORAGE_OWNER=UID:GID` with your numbers. If the command says that the user does not exist,
> find the account that runs WildFly in your image and use its numbers.

<a id="disk-scan"></a>
### 3.3 Look at the server with `scan`

`scan` is the safe first call. It changes no disk and no configuration. Before it lists anything, it checks that Docker exists
and that it can read the AE of the archive from the LDAP server. This proves edit C and the settings `ARC_AET`,
`ARC_DEVICE`, `LDAP_BASE_DN` and `LDAP_CONTAINER`.

```bash
bash /opt/pacs-admin/server/pacs-storage.sh scan
```

> **Check**
>
> Expected on a server that has no PACS disk yet. The text under `--- Storages` is normal before the first disk:
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
> If the folder `/mnt/fs` does not exist, one more line says `/mnt/fs gibt es nicht: mkdir -p /mnt/fs`. A line that starts
> with `  HALT:` means the assistant cannot work. Read the text of that line in
> [troubleshooting](troubleshooting.md#disk-halt).

The four sections:

| Section | Meaning |
|---|---|
| `--- Storages` | The disks that are mounted below `/mnt/fs` with the prefix. Each line shows the name, the device, the size, the free space and the word `Schreibliste` for a disk in the write list. |
| `--- Leere Platten (add)` | Disks that the assistant may format. Each line shows the device, the size and the model. |
| `--- Vergroesserte Platten (grow)` | Disks that are larger than their file system. See `grow` in [3.5](#disk-operate). |
| `--- NO_MOUNT fehlt unter dem Mountpunkt (nomount)` | Mount points without the protective file. `nomount ja` creates it. |

Example of the first section on a server with two disks (the numbers are an example):

```text
--- Storages
  PACS-Data01  /dev/sdb    2048 GiB gesamt   312 GiB frei   Schreibliste
  PACS-Data02  /dev/sdc    2048 GiB gesamt  1980 GiB frei
```

<a id="disk-first"></a>
### 3.4 Set up a disk

Do the steps of [section 2](#recreate-arc) for edit A (and edit C if needed) first. Then `scan` must run without `HALT`.

#### Step 1. Give the server an empty disk

On a virtual machine, add a new virtual disk in the hypervisor. On a physical server, attach the disk. Do not create a
partition, do not format the disk and do not mount it. The disk needs at least `STORAGE_MIN_GB` GiB (100 GiB by default).

#### Step 2. Let the page find the disk

Open the admin page and the tab `Übersicht` (overview). The tile `Neue Festplatte` (new disk) says
`Keine leere Platte gefunden.` until the server has found the disk. The status script looks every 5 minutes. To look at once,
choose `Jetzt suchen` (search now).

> **Check**
>
> Expected: the tile changes to `Neue Festplatte erkannt` with the text `leer, bereit zum Einrichten`. It shows the device,
> the size and the model of the disk, and the button `Als PACS-Data01 einrichten …`. If the tile does not change, see
> [troubleshooting](troubleshooting.md#disk-not-offered). If `Jetzt suchen` shows a red message that ends with `(HTTP 500)`,
> the status script failed. The message holds the last line of its error, for example a bad number in
> `/etc/default/pacs-admin`.

#### Step 3. Confirm

> **Warning**
>
> This formats the disk. Compare the device, the size and the model with the disk that you gave the server. During the setup,
> do not restart `pacs-verwaltung` and do not reboot the server. A setup that stops in the middle can leave a formatted disk
> that the archive does not know yet. [Troubleshooting](troubleshooting.md#disk-half-done) shows how to finish or undo it.

Choose `Als PACS-Data01 einrichten …`. A box names the disk and lists what happens:

1. A file system ext4 with the name of the disk, without the reserve for root.
2. The disk is mounted, and `/etc/fstab` gets a line.
3. The storage appears in the archive, with the settings of the template. The box names the template and its threshold.
4. The storage goes to the end of the write list. New images come to it when the disks in front of it are full.

If the box shows `Schwelle ?`, the template storage has no threshold, and the new storage has none either. Set a threshold on
the template storage in the dcm4chee user interface before you go on.

Choose `Formatieren und einrichten` (format and set up). `Abbrechen` closes the box and changes nothing. The tile
`Neue Festplatte PACS-Data01` now shows the steps `Platte prüfen`, `Formatieren und einhängen`, `Archiv sieht die Platte`,
`Im Archiv eintragen` and `Fertig` while the script runs.

#### Step 4. Check the result

> **Check**
>
> Expected: the tile says `PACS-Data01 ist eingerichtet.` and `eingerichtet` with the time. The tile `Speicher` (storage)
> shows a new bar. Its name is `01`, because the tile leaves out the prefix. Then check the server:
>
> ```bash
> findmnt /mnt/fs/PACS-Data01
> grep PACS-Data01 /etc/fstab
> tail -n 12 /var/log/pacs-storage.log
> ```
>
> Expected: `findmnt` shows the mount with the file system `ext4`. `grep` shows the line
> `LABEL=PACS-Data01 /mnt/fs/PACS-Data01 ext4 nosuid,nodev,nofail 0 0`. The end of the log ends with a line `fertig.`

If the tile shows `Abgebrochen` (cancelled), it names the first `HALT` line. Open `Ausgabe des Skripts` (output of the
script) for the full text. The meaning of each `HALT` line is in [troubleshooting](troubleshooting.md#disk-halt).

If a red message at the lower right ends with `(HTTP 504)`, a script did not finish within 300 seconds, and the helper
service stopped it. After `Formatieren und einrichten` this means that the check before the start ran out of time: no setup
was started. Look at the disks on the server and at `/var/log/pacs-storage.log` before you try again
([troubleshooting](troubleshooting.md#disk-half-done)).

If the tile says `eingerichtet` with the time and `Archiv nicht neu geladen` (archive not reloaded), and a yellow box with the
same title is open, the setup is complete in the LDAP configuration, but `arc` did not reload it. `arc` keeps the old
configuration until it reloads. The box repeats the text after `ACHTUNG:` in the output of the script. The steps to reload are
in [troubleshooting](troubleshooting.md#disk-half-done).

**The same on the command line.** Use this to see the plan first, or when the page is not available.

```bash
bash /opt/pacs-admin/server/pacs-storage.sh scan
bash /opt/pacs-admin/server/pacs-storage.sh add /dev/sdc
```

The second command only prints the plan. This is the format of the plan. The names depend on your archive:

```text
--- Plan
  Platte:  /dev/sdc, 1024 GiB, MODEL, leer
  Format:  ext4, Label PACS-Data02, ohne root-Reserve (-m 0)
  Mount:   /mnt/fs/PACS-Data02, fstab: LABEL=PACS-Data02 /mnt/fs/PACS-Data02 ext4 nosuid,nodev,nofail 0 0
  Archiv:  Storage PACS-Data02 wie PACS-Data01, Schreibliste DCM4CHEE danach: PACS-Data01 PACS-Data02
Trockenlauf. Ausfuehren: /opt/pacs-admin/server/pacs-storage.sh add /dev/sdc ja
```

On a new archive, the template is the storage that dcm4chee created itself. Its name depends on your install, so the line
`Archiv:` can read `wie fs1, Schreibliste DCM4CHEE danach: fs1 PACS-Data01`. The new disk then receives images only when `fs1`
is full ([3.5](#disk-operate) shows how to change this).

To format and set up, run the same command with `ja` at the end. This is the format of the output. It is derived from the
text of the script and was not recorded on a real disk:

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

If the script stops in the step `Sichtbar im Container arc?` with `HALT: arc sieht /mnt/fs/PACS-Data02 nicht`, the disk is
formatted and mounted, but the archive does not know it. `arc` has no volume `/mnt/fs:/mnt/fs:rslave`, or it was not
recreated after the edit. Do [section 2](#recreate-arc) (edit A and the recreate), then run `activate` with the name from
the message:

```bash
bash /opt/pacs-admin/server/pacs-storage.sh activate PACS-Data02 ja
```

<a id="disk-operate"></a>
### 3.5 Daily work

The tile `Speicher` of the tab `Übersicht` shows one bar for each disk in `/mnt/fs`. It uses the numbers of
`status.json`, which the cron job renews every 5 minutes and each disk action renews at once.

| Mark on a bar | Meaning |
|---|---|
| `neue Bilder jetzt` | New images go to this disk now. |
| `neue Bilder als 2.` | New images go to this disk when the disks in front of it are full. The number is the place in the write list. |
| `als voll markiert` | dcm4chee marked the disk as full. It skips the disk. |
| `nicht eingehängt, bitte prüfen` | The folder exists, but no disk is mounted there. See [troubleshooting](troubleshooting.md#disk-not-mounted). |

The line under the bars tells you whether the room is enough:

| Line | Meaning and action |
|---|---|
| `Neue Bilder gehen auf 01, danach 02. Platz bis zur Schwelle: …` | The order of the write list (example) and the room until the thresholds. No action. |
| The same line, ending with `Bald dem Server eine neue Platte geben.` | The room is below `STORAGE_WARN_GB`. Add a disk ([3.4](#disk-first)). |
| `Keine Platte nimmt neue Bilder an. Sofort dem Server eine neue Platte geben.` | No disk of the list is free for new images. Add a disk, or free space and use the buttons below. |
| `Schreibliste nicht lesbar (LDAP-Container und pacs-storage.sh kandidaten prüfen). Welche Platte neue Bilder bekommt, ist gerade unbekannt.` | The status script could not read the write list. Run `scan` and read the `HALT` line ([troubleshooting](troubleshooting.md#disk-halt)). |
| `Keine Daten zu den Platten (status.json nennt keine; STORAGE_BASE und STORAGE_PREFIX prüfen).` | No folder `STORAGE_BASE/STORAGE_PREFIX` plus a number. Normal before the first disk. Otherwise check both settings. |
| `Kein Status vorhanden (dashboard-status.py läuft per cron alle 5 Minuten).` | No status file. See [troubleshooting](troubleshooting.md#cron-not-running). |

Three buttons change the write list. Each one asks for a confirmation first and writes a line to the audit log:

| Button | Shown when | What it does |
|---|---|---|
| `Markierung entfernen` (remove the mark) | The disk is marked as full and has `STORAGE_FREE_GB` free. | Removes the mark "full". If the disk is in the write list, it gets new images when the disks in front of it are full. If dcm4chee finds the disk full again, it marks the disk again. |
| `In Schreibliste aufnehmen` (add to the write list) | The disk is not in the write list and has `STORAGE_FREE_GB` free. | Puts the disk at the end of the list and removes the mark "full". |
| `Aus Schreibliste nehmen` (take out of the write list) | The disk is in the list and another disk that is not full stays in it. | The disk gets no new images. Its images stay readable. |

The script checks the conditions again. If a button fails, the message names the reason. The texts are in
[troubleshooting](troubleshooting.md#disk-halt). A message that begins with `Archiv-Konfiguration nicht neu geladen` and ends
with `(HTTP 500)` means that the change is in the LDAP configuration, but `arc` did not reload it. A message that ends with
`(HTTP 504)` means that the script did not finish within 300 seconds. Both cases are in
[troubleshooting](troubleshooting.md#disk-half-done).

**Send new images to a new disk at once.** A new disk is at the end of the list. To make it the target now, take the disks in
front of it out of the write list with `Aus Schreibliste nehmen`. The box names the disk that gets the new images. To go
back, use `In Schreibliste aufnehmen` on the old disk. It then stands at the end of the list. This works for disks named
`PACS-Data` plus a number. For other names, see the last paragraph of this section.

> **Check**
>
> Expected: the mark `neue Bilder jetzt` moves to the disk that you meant. On the command line, `scan` shows the word
> `Schreibliste` only behind disks that are in the list.

**Enlarge a disk.** Enlarge the disk in the hypervisor, then use the command line. `scan` lists the disk under
`--- Vergroesserte Platten (grow)`.

```bash
bash /opt/pacs-admin/server/pacs-storage.sh grow /dev/sdc
bash /opt/pacs-admin/server/pacs-storage.sh grow /dev/sdc ja
```

The first call shows the plan. The second call enlarges the file system, and the disk stays in use. If the disk is not in the
write list, `grow` puts it at the end. A mark "full" can stay. Then choose `Markierung entfernen`.

> **Warning**
>
> Do not restart `pacs-verwaltung` while the tile `Neue Festplatte` says `läuft seit …`. The restart stops the running setup in
> the middle. Wait for the end, then restart. The helper service writes no audit line while it restarts
> ([troubleshooting](troubleshooting.md#audit-lines-missing)).

**Storages with other names.** dcm4chee keeps using a storage with another name, for example one that dcm4chee created
itself. The tile and the commands `freigeben`, `anhaengen` and `grow` handle only the disks `PACS-Data` plus a number below
`/mnt/fs`. `abhaengen` accepts every name, but no tool of this repository puts such a storage back into the list.

<a id="disk-rollback"></a>
### 3.6 Go back

- **Before the first disk:** restore the compose file as in [2.3](#recreate-rollback).
- **After the first disk:** keep edit A. Without the volume, dcm4chee cannot read the images on the new disks.
- **A disk that should get no more images:** take it out of the write list (`Aus Schreibliste nehmen`). Keep it mounted. The
  assistant has no function to remove a disk or a storage. If you remove a disk that holds images, those images cannot be
  read any more.
- **A setup that stopped in the middle:** see [troubleshooting](troubleshooting.md#disk-half-done).
- **Remove the whole product:** the steps are in [install.md](install.md#uninstall). They include the volume, the ports and
  the password line of the compose file.

<a id="firewall"></a>
## 4. Firewall

The firewall decides which computers may open a connection to the Docker ports of this server: DICOM, HL7, the REST
interface of dcm4chee and the management ports. It uses [iptables](glossary.md#iptables) rules that you manage in the tab
`Firewall` of the admin page ([screen labels](glossary.md#screen-firewall)). Read the emergency brake first.

<a id="firewall-brake"></a>
> **Warning**
>
> **Emergency brake.** A wrong rule can cut off a modality, an HL7 sender or a user at once. It can cut off the admin page as
> well. SSH keeps working, because the firewall never touches it. Log in over SSH (or open the console of the virtual machine)
> and run as root:
>
> ```bash
> systemctl stop pacs-firewall
> ```
>
> The command removes the jump to the rule chain `PACS-SPERRE`. All Docker ports are open again at once. It deletes no rule
> and no file. To see that it worked:
>
> ```bash
> iptables -S DOCKER-USER
> ```
>
> Expected: no line that contains `PACS-SPERRE`.
>
> The brake holds only for a while. The rules come back when
>
> - the server starts again,
> - someone saves a changed rule set in the tab `Firewall`, or
> - the list of published Docker ports changes (for example when `arc` is recreated) and `Ports ohne eigene Regel` (ports
>   without a rule of their own) is not `offen`. The helper service checks this every 5 minutes.
>
> To switch the firewall off for good, untick `eingeschaltet` (switched on) in the tab, choose `Speichern` (save) and run
> `systemctl disable --now pacs-firewall`. Do not use `systemctl restart pacs-firewall` to apply a change: it opens all ports
> for a moment ([4.10](#firewall-settings) shows the way without a gap).

**Who needs it.** Many networks reach the server, and you want to decide who may connect to the DICOM and HL7 ports and to the
management ports. If only a few trusted computers reach the server, the firewall of your network may be enough.

**What it changes.**

- The compose file of dcm4chee: edit B ([section 2](#edits-overview)) writes the ports with an address. `arc` restarts once.
- The packet filter: a chain `PACS-SPERRE` with your rules and one jump to it from the chain `DOCKER-USER`.
- One systemd unit, `pacs-firewall`, that sets the rules again at every start of the server and of Docker.
- Files in the folder `PACS_DIR` (default `/opt/dcm4chee-arc`): `firewall.json` holds your rules, and the folder `firewall/`
  holds backups of it and the lists that the page collects.
- One line `FW_DEFAULT_RULES` in `/etc/default/pacs-admin` for the first start ([4.4](#firewall-start)).

The firewall changes no setting of dcm4chee, nginx or the viewer.

> **Warning**
>
> A rule that blocks a port cuts off everyone who uses it, and nobody tells you until a device or a user complains. Do not
> block a port before you know who uses it. Start in trial mode ([4.4](#firewall-start)), read the results
> ([4.5](#firewall-read)), block one port at a time ([4.7](#firewall-block)) and test each step from a second computer. Keep an
> SSH session open while you work.

Work in this order:

1. [Find out who uses which port](#firewall-inventory) (4.2).
2. [Publish the ports on IPv4 only](#firewall-ports) (4.3).
3. [Start the firewall in trial mode](#firewall-start) (4.4) and let it collect for about a week ([4.5](#firewall-read)).
4. [Allow the known sources](#firewall-allow) (4.6), then [block port by port](#firewall-block) (4.7).
5. [Test a reboot](#firewall-reboot) (4.8).

Sections 4.9 to 4.12 are options and reference: [client PCs](#firewall-clients), [settings](#firewall-settings),
[the lock-out check](#firewall-lockout) and [removal](#firewall-uninstall).

<a id="firewall-scope"></a>
### 4.1 What the firewall covers

The firewall checks **new connections** that come from outside to a port that Docker publishes on an IPv4 address. Docker sends
these connections through the chain `DOCKER-USER`, and the firewall hooks in there ([glossary](glossary.md#docker-user)).

It covers:

- new connections from outside to the ports that a container publishes on IPv4: DICOM, HL7, the REST ports 8080 and 8443, the
  web ports 443 and 80, and the management ports. This holds for every container, not only for `arc`.

It does not cover:

- SSH (port 22) and every service that runs on the host itself, outside Docker.
- Connections over IPv6 that Docker accepts through `docker-proxy`. They pass the firewall. The tab shows the badge
  `IPv6 nicht gefiltert` (IPv6 not filtered) at such a port ([4.3](#firewall-ipv6)).
- Connections that a container opens itself, for example `arc` sending images to a modality. The firewall lets the traffic of
  existing connections pass. A connection that already exists when you save a rule stays open until it closes.
- Traffic of the server to itself (`127.0.0.1`). A port that Docker binds to `127.0.0.1` only is not listed: nobody outside
  reaches it.
- Traffic that enters through another network interface than the one the firewall watches (step 1 of [4.4](#firewall-start)).

Every port has one of three modes. The setting `Ports ohne eigene Regel` gives the mode for all other ports, also for ports
that Docker publishes later.

| Mode | What happens to a new connection |
|---|---|
| `offen` (open) | It passes. |
| `Probelauf` (trial run) | It passes. If the source is not on the list of the port, the kernel writes a log line and the source appears under `Neu erkannt` (newly detected). |
| `gesperrt` (blocked) | It passes only from a host or network on the list of the port. Every other source is rejected: the client gets "connection refused". The kernel writes a log line. |

A list holds IPv4 addresses (`192.0.2.18`) and IPv4 networks in [CIDR](glossary.md#cidr) notation (`192.0.2.0/24`).

<a id="firewall-inventory"></a>
### 4.2 Find out who uses which port

> **Warning**
>
> The built-in rule set of the firewall blocks seven ports **at once** when the unit starts for the first time: 8080, 8443,
> 9990, 9993, 5601, 8000 and 9443. Binding a port to `127.0.0.1` in the compose file has the same effect for that port.
> Everyone who uses such a port from another computer then gets "connection refused". The start in [4.4](#firewall-start)
> avoids the built-in set. Make the list below first.

| Port | Service | Who uses it | What stops when you block it |
|---|---|---|---|
| `443`, `80` | Front door: viewer and admin page | All staff | The viewer and the admin page do not open. The built-in rules leave both open. |
| `11112` | DICOM | Modalities, other archives and workstations that send or query images | Images are not stored. The device reports a failed send. |
| `2762` | DICOM over TLS | The same devices, if they use TLS | The same. |
| `2575` | HL7 | The HIS or RIS that sends orders and patient messages | Messages are not delivered. |
| `12575` | HL7 over TLS | The same sender, if it uses TLS | The same. |
| `8080`, `8443` | REST interface and user interface of dcm4chee (http, https) | People who open the dcm4chee user interface directly, programs that call WADO, QIDO or STOW, monitoring | The caller gets "connection refused". The viewer and the admin page keep working: they reach `arc` through the Docker network and through `127.0.0.1`. |
| `9990`, `9993` | Management console of WildFly (http, https) | Administrators, rarely | The console does not open. |
| `5601` | Kibana, if you run it | Administrators | Kibana does not open. |
| `8000`, `9443` | Portainer, if you run it | Administrators | Portainer does not open. |

Other containers may publish more ports. The tile `Ports` of the tab `Firewall` lists every published port and names its
container.

**Who connects now.** The kernel keeps a table of the connections that exist now. Read it as root. The command counts the
connections for each source and port of the table above:

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

> **Check**
>
> Expected: one line for each source and port, with the number of connections, the port and the source address. Example:
>
> ```text
> 2 8080 192.0.2.50
> 1 8443 192.0.2.77
> ```
>
> No output means that nobody uses these ports at this moment. It does not mean that nobody uses them at all. If the error
> says that the file does not exist, the kernel has not loaded the connection tracking yet: run `modprobe nf_conntrack`.

Connections over IPv6 and connections to programs on the host itself are not in that table. List them with `ss`. A peer
address with colons in square brackets is an IPv6 client:

```bash
ss -tn state established '( sport = :8080 or sport = :8443 or sport = :9990 or sport = :9993 or sport = :5601 or sport = :8000 or sport = :9443 )'
```

A snapshot is not a census. A modality may connect once a day, an HL7 sender once an hour and an administrator once a month.
The trial run in [4.4](#firewall-start) is the reliable inventory: it logs every new connection from a source that is not on a
list. Also ask your colleagues:

- Who opens the dcm4chee user interface on port 8080 or 8443? These people need [section 5](#dcm4chee-ui) before you block the
  two ports.
- Which monitoring tools and scripts call the REST interface?

<a id="firewall-ports"></a>
### 4.3 Publish the ports on IPv4 only

The firewall filters IPv4 only. A port without an address in the compose file is published on IPv4 and, on many installs, on
IPv6 as well. Docker accepts the IPv6 connections in `docker-proxy` ([glossary](glossary.md#docker-proxy)), and these
connections run past the firewall. Edit B of [section 2](#edits-steps) writes every port of `arc` as `0.0.0.0:PORT:PORT`.
Docker then publishes on IPv4 only. Make edit B in the same recreate as edit A. For the ports of other containers (LDAP,
Kibana, Portainer), add `0.0.0.0:` in the compose file that publishes them.

After the recreate, look at what Docker publishes:

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

> **Check**
>
> Expected: every published port of `arc` appears once, as `0.0.0.0:11112->11112/tcp` (example). An entry such as
> `[::]:11112->11112/tcp` next to it means that the port is also open over IPv6 and not filtered. The tab marks such a port
> with the badge `IPv6 nicht gefiltert`. A port that shows only `127.0.0.1:` is not reachable from outside.

<a id="firewall-ipv6"></a>
#### If a port stays open over IPv6

There are two options. Choose the first one when you can.

**Option 1: fix the compose file.** Write `0.0.0.0:` in front of the port, as in edit B. Write `127.0.0.1:` when nobody needs
the port from another computer. Recreate the container once more.

**Option 2: switch IPv6 off on the server.** Use this only when no service of the server needs IPv6.

> **Warning**
>
> This stops SSH and every other service on IPv6 addresses. If you work over an IPv6 address, you cut off your own session.
> Have the console of the server ready. Do not restart Docker to apply the setting: a restart of Docker stops all containers,
> unless `live-restore` is on. How Docker publishes ports when IPv6 is off depends on its version, so check the ports after
> the reboot. To go back, delete the file below and reboot.

```bash
cat > /etc/sysctl.d/90-pacs-no-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
sysctl --system
```

Reboot the server in a maintenance window, then look at the ports again.

> **Check**
>
> ```bash
> sysctl net.ipv6.conf.all.disable_ipv6
> docker ps --format 'table {{.Names}}\t{{.Ports}}'
> ```
>
> Expected: `net.ipv6.conf.all.disable_ipv6 = 1`, and no entry that starts with `[::]:`. If an entry remains, use option 1 for that
> port.

<a id="firewall-start"></a>
### 4.4 First start in trial mode

Start the firewall with every port in trial mode. Nobody is blocked in trial mode, and the firewall logs every source that no list
names. The built-in rule set would block seven ports at once ([4.2](#firewall-inventory)), so replace it for the first start.

#### Step 1. Check the programs and the network interface

The firewall needs the programs `iptables` and `ip`. It watches the traffic that enters through one network interface, the
interface of the default route.

```bash
command -v iptables ip
ip route show default
```

> **Check**
>
> Expected: two paths, one for `iptables` and one for `ip`, and a route line such as
> `default via 192.0.2.1 dev eth0 proto static` (example). The word after `dev` is the interface. If a program is missing,
> run `apt-get install -y iptables iproute2`.
>
> If the output shows no route or several routes, or if your clients reach the server through another network card, name the
> interface by hand: add the line `FW_INTERFACE=eth0` (with your interface name) to `/etc/default/pacs-admin`.

#### Step 2. Write the rule set for the first start

The file below has the format of `firewall.json` ([reference](reference.md#firewall-json)). The ports 443 and 80 stay open. The
ports 11112 (DICOM), 2575 (HL7), 8080, 8443, 9990 and 9993 get the mode `probelauf`. `standard` is the mode for all other
ports, also `probelauf`. Use the host port, the number left of the colon in the compose file: if your devices send to
`104`, write `104`.

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

Tell the firewall to use this file as long as no `firewall.json` exists. After your first `Speichern` in the tab,
`firewall.json` takes over and this file is no longer read.

> **Warning**
>
> Write `>>` (two characters). A single `>` replaces the whole file `/etc/default/pacs-admin` and removes all your settings. If
> that happens, restore the settings from your notes or from `deploy/pacs-admin.env.example`.

```bash
echo 'FW_DEFAULT_RULES=/etc/pacs-admin-firewall-start.json' >> /etc/default/pacs-admin
```

#### Step 3. Restart the helper service and start the firewall

The helper service reads `FW_DEFAULT_RULES` when it starts, so restart it once.

> **Warning**
>
> Do not restart `pacs-verwaltung` while a disk setup runs ([3.5](#disk-operate)). The helper service writes no audit line while
> it restarts. This step blocks nobody: every port is open or in trial mode.

```bash
systemctl restart pacs-verwaltung
```

Install the unit and start it. If your repository is not in `/opt/pacs-admin`, change the path in the unit first, as
[install.md](install.md#helper-service) shows for the other unit.

```bash
cp /opt/pacs-admin/deploy/systemd/pacs-firewall.service /etc/systemd/system/
systemctl enable --now pacs-firewall
```

#### Step 4. Check that the rules work

> **Check**
>
> ```bash
> systemctl is-active pacs-firewall
> iptables -S DOCKER-USER
> set -a; . /etc/default/pacs-admin; set +a
> python3 /opt/pacs-admin/server/firewall.py status
> ```
>
> Expected: `active`, then three lines (the interface is yours):
>
> ```text
> -N DOCKER-USER
> -A DOCKER-USER -i eth0 -j PACS-SPERRE
> -A DOCKER-USER -j RETURN
> ```
>
> Then one line for each rule and a last line with `wirksam: True`. Example:
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
> The tab `Firewall` shows the badge `wirksam` (in effect). Open the viewer once to see that it still works. If the badge says
> `nicht wirksam`, it names the reason: see [troubleshooting](troubleshooting.md#firewall-not-effective).
>
> If the page shows a red message that starts with `Firewall laden: Firewall:` and ends with `(HTTP 500)`, the helper service
> could not read the status. One cause is that `docker` is not installed, because the status reads the Docker networks. See
> [troubleshooting](troubleshooting.md#firewall-tools-missing).

<a id="firewall-read"></a>
### 4.5 Let it collect, then read the results

Leave the firewall in trial mode for about one week, or longer than the longest cycle of your devices. Some devices send once
a night, some once a week. The tab reads the kernel log of the current boot only, so avoid a reboot during this time.

| Where in the tab | What it shows | Use |
|---|---|---|
| Badge at the top | `wirksam`, `nicht wirksam` with the reason, or `ausgeschaltet` (switched off). Also the interface, the time since which the numbers count, and who changed the rules last. | If it says `nicht wirksam`, read the reason first. |
| Tile `Ports`, column `Andere` (others) | The number of new connections from sources that are not on the list of the port: `N nicht eingetragen` (not listed) in trial mode, `N abgewiesen` (rejected) when blocked. The numbers are exact and start again at zero after each save that changes rules. | A port with no such number had no foreign connection. |
| Tile `Neu erkannt` | Sources that no list names yet: client networks, DICOM devices, HL7 senders and sources from the trial run. | Work through it in [4.6](#firewall-allow). |
| Tiles `DICOM-Absender` and `HL7-Absender` (senders) | Devices that sent data to the archive. The helper service reads them from the log of dcm4chee every 5 minutes. A badge says `intern, nicht betroffen`, `eingetragen` or `nicht eingetragen`. | Shows senders that stay silent in the kernel log. |
| Details `Verbindungen an Regeln` (connections at rules) | Sources that hit a rule, from the kernel log: `abgewiesen`, `Probelauf: nicht eingetragen`, `erlaubt, protokolliert` (allowed, logged), `Standard: abgewiesen`. | The evidence for each entry. |

Limits of the data:

- The kernel writes at most 10 log lines per minute for each rule. A busy source can hide a rare source within one minute. Over
  a week, every source that connects at least once a day shows up.
- The sender tiles need the log of dcm4chee. The helper service finds it through `ARC_LOG_DIR` ([4.10](#firewall-settings)).
- `firewall.py nachholen` reads the packed logs of dcm4chee and then the running log from its start. It replaces the sender
  lists that the page has collected so far. Use it once if you want the senders of earlier days in the lists
  ([4.10](#firewall-settings)).

> **Check**
>
> Expected: after at most 10 minutes, the tiles `DICOM-Absender` and `HL7-Absender` list the devices that sent data. If a tile
> says `Noch keine Absender erfasst.` while devices send, see [troubleshooting](troubleshooting.md#arc-log-dir).

<a id="firewall-allow"></a>
### 4.6 Allow the known sources

After the week of collecting, enter every source that has a reason to reach a port. A port that you block later lets in only
the sources on its list. Every other source is rejected.

#### Step 1. Work through `Neu erkannt`

The tile `Neu erkannt` is at the top of the tab. Its table lists each source that no list of its port names yet. The columns
are `Was` (kind), `Quelle` (source), `Name`, `Port`, `Verbindungen` (connections) and `zuletzt` (last seen). The tile shows no
source for a port in the mode `offen`.

| `Was` | Meaning |
|---|---|
| `Client-PCs` | A /24 network with computers that the DNS search found ([4.9](#firewall-clients)). The row is for the first DICOM port. |
| `DICOM-Gerät` | A device that sent data to the archive. `Name` shows its [AE title](glossary.md#ae-title). |
| `HL7-Absender` | A sender of HL7 messages. |
| `Probelauf: nicht eingetragen` | A source that connected to a port in trial mode and is on no list. |
| `abgewiesen` | A source that was rejected at a web port, at the first DICOM port or at the first HL7 port. |

Decide each row:

- The computer or device belongs to your hospital and needs the port: choose `Erlauben` (allow).
- You do not know the source: read the column `Name`, ask the owner of the device and wait. Do not allow what you cannot name.
- The source must not connect and you do not want to see it again: choose `Ausblenden` (hide). The row stays away until you
  choose `Wieder anzeigen` (show again) in the footer of the tile.

`Erlauben` and `Ausblenden` change nothing on the server yet. They collect your changes in a bar at the bottom of the tab:
`N Änderungen` (N changes). A port without a rule of its own gets a new rule. The rule starts in the mode of
`Ports ohne eigene Regel`, or in `Probelauf` if that setting is `offen`.

> **Warning**
>
> A row of the kind `Client-PCs` allows the whole /24 network for the DICOM port, not only the computers that the search
> found. `Alle N erlauben` (allow all N) enters every row at once, also the rows you have not read. Use it only after you
> have read every row. Before you save, `Verwerfen` (discard) drops all pending changes.

#### Step 2. Add a source by hand

Use this for a device that has not connected yet, for example a new modality. Find the row of its port in the tile `Ports`.

1. A port that still follows the default shows `niemand (Standard)` and no input fields. Choose a mode in the column `Zugang`
   (access) first, for example `Probelauf`. The column `Erlaubte Rechner und Netze` (allowed computers and networks) then
   shows two fields and a button.
2. Enter the IPv4 address of the device, or its network in [CIDR](glossary.md#cidr) notation, in `IP oder Netz` (IP or
   network), for example `192.0.2.18` or `192.0.2.0/24`. Enter the name of the device and the name of its owner in `Notiz`
   (note).
3. Choose `Hinzufügen` (add).

The list accepts IPv4 only. For anything else the page says
`Bitte eine IPv4-Adresse oder ein Netz eingeben, z. B. 192.0.2.18 oder 192.0.2.0/24`. To remove an entry, choose the `×` on it.

To see how often a listed device connects, tick `protokollieren` (log) in the row. The kernel then logs its new connections too,
at most 10 lines per minute. They appear under `Verbindungen an Regeln` as `erlaubt, protokolliert`.

#### Step 3. Save

Choose `Speichern` (save) in the bar. The page shows your changes in a box. The box starts with `Firewall ändern:` and ends with
`Gilt sofort.` (valid at once). Read the list and confirm.

The helper service writes the rules to `firewall.json`, keeps every earlier version in the folder `firewall/` under `PACS_DIR`
and loads the rules into the kernel. If the kernel refuses the rules, the earlier rules stay, and the page says
`Nicht übernommen, die vorigen Regeln gelten weiter:` followed by the reason. Your account and the list of changes go to the
audit log, tab `Protokoll`.

> **Check**
>
> Expected: the bar disappears. When you have decided every row, `Neu erkannt` says
> `Nichts Neues: alles Erkannte ist eingetragen.` Choose `Jetzt suchen` (search now) to read the logs at once. They are read
> every 5 minutes anyway. Rows can come back later: a device that connects once a week shows up in the week after.

<a id="firewall-block"></a>
### 4.7 Block port by port

Block the ports in this order and test from a second computer after each port:

1. The management ports that nobody uses: 9990, 9993, 5601, 8000 and 9443.
2. The REST ports 8080 and 8443. Do this after the people who use the dcm4chee user interface moved to
   [section 5](#dcm4chee-ui) and the programs that call the REST interface are on the lists.
3. The HL7 and DICOM ports: 2575, 12575, 11112 and 2762.
4. The setting `Ports ohne eigene Regel`, last.

Leave 443 and 80 on `offen`, unless only known networks may open the viewer and the admin page.

> **Warning**
>
> A blocked port rejects every source that is not on its list. A device that is not on the list gets "connection refused" and
> reports a failed send. Nothing else tells you. Block a port only after you have decided every row of `Neu erkannt` for it.
> Keep your SSH session open. To go back for one port, set it to `offen` and save: the change works at once. For a wide
> outage use the [emergency brake](#firewall-brake).

#### Step 1. Block one port

In the tile `Ports`, choose `gesperrt` (blocked) in the column `Zugang` of the port. For the web ports, the first DICOM port
and the first HL7 port the page asks first:
`Port N (Name) sperren? Danach kommen nur noch die eingetragenen Rechner durch, alle anderen werden abgewiesen.`
For a port in trial mode it adds
`Vorher im Probelauf prüfen: unten darf niemand mehr als „nicht eingetragen“ stehen.`
(check the trial run first: nobody below may be left as "not listed"). Confirm, then choose `Speichern` as in
[4.6](#firewall-allow), step 3.

#### Step 2. Test from a second computer

Use a computer that is not on the list of the port and is not the computer you work on. Run the test against a port whose
service runs: a stopped service refuses connections too. On Windows, in PowerShell:

```powershell
Test-NetConnection -ComputerName pacs.example.org -Port 9990
```

On Linux:

```bash
curl -sS -m 5 -o /dev/null http://pacs.example.org:9990/
```

> **Check**
>
> Expected from a computer that is **not** on the list: PowerShell shows `TcpTestSucceeded : False`, and `curl` ends with
> `curl: (7)`.
>
> Expected from a computer that **is** on the list: PowerShell shows `TcpTestSucceeded : True`, and `curl` prints an answer or
> an error other than `(7)`. The connection opened, so the firewall let it in.
>
> If a computer outside the list gets through, the port is not blocked. Read the badge at the top of the tab, and see
> [troubleshooting](troubleshooting.md#firewall-not-effective).

The test shows only that the port opens. For a DICOM device, also run the DICOM echo (C-ECHO, a "ping" for DICOM) from the device
or from its service menu. For an HL7 sender, send a test message.

#### Step 3. See the rejected connection

The kernel log and the tab both record the test of step 2.

```bash
journalctl -k --since "10 minutes ago" --no-pager | grep 'pacs-sperre 9990'
```

> **Check**
>
> Expected: at least one line with `pacs-sperre 9990:` and, after `SRC=`, the address of the test computer. In the tab, the row
> of the port shows `N abgewiesen` (N rejected) in the column `Andere`, and the tile `Verbindungen an Regeln` lists the address
> with the kind `abgewiesen`. The numbers start again at zero after each save.

#### Step 4. Close the default

When every port you care about has a rule of its own, set `Ports ohne eigene Regel` (at the top of the tab) to `gesperrt`.
Every other published port is then closed from outside, also the port of a container that you start later. The page asks
`Standard „gesperrt“: alle Ports ohne eigene Regel sind danach von außen zu, auch künftig veröffentlichte.` and lists the
ports that have no rule today.

> **Warning**
>
> Make sure that 443 and 80 have a rule `offen`, or list the networks that may use them, as the page says. A port in
> `Probelauf` stays open for everybody, also with the default `gesperrt`. The default also rejects new UDP traffic to
> container ports. After you start a new container that publishes a port, add a rule for the port or nobody reaches it from
> outside. To go back, set the default to `Probelauf` or `offen` and save.

Test once more from the second computer: the viewer must open, and a port that has no rule must refuse the connection.

<a id="firewall-reboot"></a>
### 4.8 Test a reboot

The rules live in the kernel. A reboot removes them, and the unit `pacs-firewall` loads them again at the start of the server.
Prove that once, in a maintenance window, before you rely on the firewall.

> **Warning**
>
> The reboot stops the archive, the viewer and the admin page until everything has started again. After the start of Docker,
> the containers may run for a few seconds before the unit sets the rules. The ports can be open in this time. Do the test
> when this is acceptable.

```bash
reboot
```

When the server is up again, log in over SSH:

```bash
systemctl is-active pacs-firewall
iptables -S DOCKER-USER
```

> **Check**
>
> Expected: `active`, and among the lines of the second command `-A DOCKER-USER -i eth0 -j PACS-SPERRE` (your interface). The
> tab `Firewall` shows `wirksam`. Repeat the test of [4.7](#firewall-block), step 2, for one blocked port. If the unit is not
> active or the badge says `nicht wirksam`, see [troubleshooting](troubleshooting.md#firewall-not-effective).

<a id="firewall-clients"></a>
### 4.9 Client PCs (optional)

Skip this section if staff only use the viewer in a browser: the viewer reaches the server on port 443. Use it if workstations
open DICOM connections to the archive, for example to query or retrieve images. The server then looks up the names of the
workstations in DNS, groups them by network and suggests one entry per network for the first DICOM port.

Give the naming scheme of your workstations as a pattern. Patterns are separated by commas. A range `{a..b}` counts from a to
b as in bash. If a bound has a leading zero, the numbers are padded with zeros to the width of the bounds. At most 100000 names
are allowed for each pattern. The pattern `pc{01..20},ws{001..040}` gives `pc01` to `pc20` and `ws001` to `ws040`. If the
resolver of the server does not add your domain, write the full name: `pc{01..20}.example.org`.

#### Step 1. Set the pattern

Replace the example pattern with the scheme of your workstations. Write `>>` (two characters) so that the settings stay. The
single quotes keep the shell from changing the braces ([rules for the settings file](reference.md#env-file-rules)).

```bash
echo "FW_CLIENT_NAMES='pc{01..20},ws{001..040}'" >> /etc/default/pacs-admin
```

#### Step 2. Restart the helper service and search

> **Warning**
>
> Do not restart `pacs-verwaltung` while a disk setup runs ([3.5](#disk-operate)). The helper service writes no audit line while
> it restarts.

```bash
systemctl restart pacs-verwaltung
```

In the tab `Firewall`, choose `Jetzt suchen` in the tile `Neu erkannt`. Or run the search on the command line:

```bash
set -a; . /etc/default/pacs-admin; set +a
python3 /opt/pacs-admin/server/firewall.py clients
```

> **Check**
>
> Expected: a line such as `37 Client-PCs` (example): the number of names from your pattern that DNS could resolve. The line
> `Client-Suche aus (FW_CLIENT_NAMES leer)` means that the setting is empty or was not loaded: check the line in
> `/etc/default/pacs-admin`.
>
> The tab shows a tile `Client-PCs`: `N im DNS (Muster …) in N Netzen` (N in DNS, pattern, in N networks). Its table has one
> row for each /24 network with the columns `Netz` (network), `PCs`, `Namen` (names) and `DICOM (11112)`. The last column says
> `eingetragen` (listed), `N nicht eingetragen` or `überschneidet Docker-Netz, erreicht das PACS nicht`.

The last text means that every address in this row lies inside a network that Docker uses on the server (or is an address of
the server). The server routes traffic for such addresses into its Docker network, not to your network, so these computers
cannot reach the archive. The firewall does not cause this. Change the address range of the Docker network.

The server looks up the names at most once an hour, with 8 lookups at a time. If DNS finds nothing (for example when the DNS
server is down), the server keeps the earlier result. `Jetzt suchen` runs the search at once.

<a id="firewall-settings"></a>
### 4.10 Settings and commands

The settings live in `/etc/default/pacs-admin` ([all settings](reference.md#config-variables)). The firewall reads these:

| Variable | Default | What it sets |
|---|---|---|
| `FW_INTERFACE` | empty: the interface of the default route | The network interface that the firewall watches. The first `Speichern` stores the interface in `firewall.json`, and the stored value wins from then on. |
| `FW_WEB_PORTS` | `443,80` | Host ports of the front door. The first one is the https port that the lock-out check protects ([4.11](#firewall-lockout)). |
| `FW_DICOM_PORTS` | `11112,2762` | Host ports for DICOM (plain and TLS). The first port is the main one: the suggestions in `Neu erkannt` use it. |
| `FW_HL7_PORTS` | `2575,12575` | Host ports for HL7 (plain and TLS). The first port is the main one, as for DICOM. |
| `FW_DEFAULT_RULES` | empty | A JSON file in the format of `firewall.json`. It applies while no `firewall.json` exists ([4.4](#firewall-start)). |
| `FW_PORT_NAMES` | empty | Your own port names as a JSON object, for example `'{"104": "DICOM (old)"}'`. |
| `FW_CLIENT_NAMES` | empty | Name patterns of the client PCs ([4.9](#firewall-clients)). |
| `ARC_LOG_DIR` | `/var/local/dcm4chee-arc/wildfly/log/` | The folder of the log `server.log` of dcm4chee, on the server. |
| `PACS_DIR` | `/opt/dcm4chee-arc` | The folder that holds `firewall.json` and the folder `firewall/`. |

A port may stand in one of the three port lists only. If a port stands in two lists, the firewall ignores all three settings,
uses the defaults and writes the message `FW_WEB_PORTS, FW_DICOM_PORTS und FW_HL7_PORTS ignoriert, ein Port steht in mehreren`
to the journal.

**Apply a change.** The helper service reads the settings when it starts, so restart it. To load the rules into the kernel
again without a gap, run `firewall.py start` with the settings loaded. Do not use `systemctl restart pacs-firewall` for this:
the restart removes the rules first, and every port is open until they are loaded again.

```bash
systemctl restart pacs-verwaltung
set -a; . /etc/default/pacs-admin; set +a
python3 /opt/pacs-admin/server/firewall.py start
```

> **Check**
>
> Expected: the last command prints `Firewall wirksam, 8 Regeln` (the number of your rules). `Firewall aus (Regeln geladen)`
> means that the firewall is switched off in the rules: the rules are loaded, but nothing jumps to them.

**Find `ARC_LOG_DIR`.** The helper service reads the senders of DICOM and HL7 from the log of dcm4chee. The log lives on the
server in the folder that `arc` mounts as `/opt/wildfly/standalone`, in the subfolder `log/`. The standard compose file of
dcm4chee mounts `/var/local/dcm4chee-arc/wildfly`, so the default fits. To see your own mount:

```bash
docker inspect -f '{{range .Mounts}}{{if eq .Destination "/opt/wildfly/standalone"}}{{.Source}}{{end}}{{end}}' arc
ls -l /var/local/dcm4chee-arc/wildfly/log/server.log
```

Use the folder from the first command, followed by `/log/`, in the second command and in the setting `ARC_LOG_DIR`. If the
setting is wrong, the sender tiles stay empty. See [troubleshooting](troubleshooting.md#arc-log-dir).

**Commands.** All commands run as root. Load the settings first, as in the block above, or the program shows its defaults.

| Command | What it does | Output (examples) |
|---|---|---|
| `python3 /opt/pacs-admin/server/firewall.py status` | Shows every rule, its counters and whether the rules are in effect. It is the command without an argument. | See [4.4](#firewall-start). If the rules are not in effect, the last line starts with `Nicht wirksam, weil:`. |
| `... firewall.py start` | Loads the rules and sets the jump. The unit runs it at every start. It waits up to 60 seconds for the network interface. | `Firewall wirksam, 8 Regeln` |
| `... firewall.py stop` | Removes the jump. The unit runs it at stop. This is the emergency brake. | `Sprung nach PACS-SPERRE entfernt, alle Ports offen` |
| `... firewall.py absender` | Reads the new lines of the log of dcm4chee into the sender lists. The helper service does this every 5 minutes. | `12 neue Zeilen` |
| `... firewall.py nachholen` | Reads the packed logs, then the running log from its start, and replaces the sender lists. Run it once to get the senders of earlier days. | `server.log.2026-10-13.gz 1234 Zeilen`, then `laufende Datei: 567 Zeilen` |
| `... firewall.py clients` | Looks up the client PC names now. | `37 Client-PCs` |
| `... firewall.py test` | Checks the program with temporary data. It changes nothing on the server. | `Selbsttest ok` |

An error shows as one line `firewall.py COMMAND: reason`, and the exit code is 1.

<a id="firewall-lockout"></a>
### 4.11 What the lock-out check protects

When you save, the helper service checks that you do not cut off your own computer from the admin page. It uses the address
that the front door reports for your computer (the header `X-Real-IP`). It refuses to save when all of this holds:

- The firewall is switched on in the new rules.
- Your address is an IPv4 address and not an address of the server or of a Docker network.
- The new rules block the first web port (443 in a default install), and your address is not on its list.

The page then shows this message (the address is an example):

```text
Port 443: dein PC (192.0.2.50) wäre danach selbst ausgesperrt. Erst ihn oder sein Netz eintragen.
```

Enter your computer or its network in the list of the port, then save again.

The check does **not** protect:

- Other users. A colleague in another network can lose the viewer and the admin page.
- Any port other than the first web port: DICOM, HL7 and every other port.
- Users behind a reverse proxy. The firewall sees the address of the proxy, not the address of the user.
- Users on IPv6, and saves that arrive without the header.

So the check is no replacement for the test from a second computer in [4.7](#firewall-block). Keep the [emergency
brake](#firewall-brake) in reach.

<a id="firewall-uninstall"></a>
### 4.12 Remove the firewall

Remove the firewall in this order. The order matters: the helper service puts the rules back within 5 minutes if it still has
them switched on.

> **Warning**
>
> From the step `systemctl disable --now pacs-firewall` on, all Docker ports are open to everyone. Remove the firewall only
> when you accept that. The compose edits stay as they are, because they do no harm without the firewall.

1. In the tab `Firewall`, untick `eingeschaltet` (switched on), choose `Speichern` and confirm. The box says
   `Firewall AUSGESCHALTET`.
2. Stop the unit and remove it:

   ```bash
   systemctl disable --now pacs-firewall
   iptables -F PACS-SPERRE
   iptables -X PACS-SPERRE
   rm /etc/systemd/system/pacs-firewall.service
   systemctl daemon-reload
   ```

3. Remove the first-start rule set, if you made one in [4.4](#firewall-start):

   ```bash
   sed -i '/^FW_DEFAULT_RULES=/d' /etc/default/pacs-admin
   rm -f /etc/pacs-admin-firewall-start.json
   ```

4. Restart the helper service. It reads the settings again. Do not do this during a disk setup ([3.5](#disk-operate)).

   ```bash
   systemctl restart pacs-verwaltung
   ```

> **Check**
>
> ```bash
> iptables -S DOCKER-USER
> iptables -S PACS-SPERRE
> ```
>
> Expected: the first command prints no line with `PACS-SPERRE`. The second prints `iptables: No chain/target/match by that
> name.` The tab `Firewall` shows `ausgeschaltet`. Do not tick `eingeschaltet` again: the helper service would set the rules
> again.

`firewall.json` and the folder `firewall/` stay in `PACS_DIR`. If you set the firewall up again later, the saved file has the
firewall switched off. Tick `eingeschaltet` again then. The full removal of the admin panel is in
[install.md](install.md#uninstall).

<a id="dcm4chee-ui"></a>
## 5. The dcm4chee user interface through the front door

dcm4chee has a web interface of its own, the `ui2` of the archive. This module lets admins open it through the front door,
behind the same login as the admin page. The admins then do not need the ports 8080 or 8443 of the archive.

**Who needs it.** Admins who use the interface of dcm4chee, for example to look at studies, move them or change the
configuration. If nobody uses it, skip this section.

**What it changes.** One nginx file, `pacs/optional/dcm4chee-ui.conf`, in the folder of the front door. Nothing else changes:
not the compose file, not the archive, not the admin page. nginx reloads without an outage.

**Requirements.**

- The archive runs without Keycloak. This means the image `dcm4chee-arc-psql`, not a `-secure` or `-secure-ui` image.
- The ports 8080 and 8443 of `arc` are closed from outside: blocked in the firewall ([4.7](#firewall-block)), or bound to
  `127.0.0.1` in the compose file. Else people reach the interface on the direct port without a login.
- The file `pacs/optional/dcm4chee-ui.conf` is in the folder of the front door. Step 4.9 of the install copies it
  ([install.md](install.md#nginx-files)).

**How nginx finds the calls of the interface.** The interface calls many addresses below `/dcm4chee-arc/`. nginx lets these
calls through to the archive only when the header `Referer` of the browser names the interface as the page they come from:
`https://`, the same host name as in the request, no port, and the path `/dcm4chee-arc/ui2/`. Every other call below
`/dcm4chee-arc/` keeps the locks of the admin page.

The rule is no login. Every call still needs an admin account. It also needs your host name to appear in the address bar the
same way for every call. Change the rule when you open the PACS another way:

| How users open the PACS | What to do |
|---|---|
| `https://pacs.example.org/` (listener `tls`, the default) | Nothing. The rule fits. |
| `https://pacs.example.org:8443/` (another port) | Put the port into the pattern: `https://\1:8443/dcm4chee-arc/ui2/`. |
| Through an SSH tunnel to `http://127.0.0.1:8080/` (listener `plain`) | Use the same port at both ends of the tunnel. The delivered pattern names `:8080`. |
| Behind a reverse proxy (listener `behind-proxy`) | The proxy must pass the header `Host` unchanged (Apache: `ProxyPreserveHost On`). If the proxy listens on another port than 443, put the port into the pattern. |

The pattern is in the file `/opt/ohif/nginx/pacs/listener/http.conf`, in the block `map "$host $http_referer" $pacs_dcm4chee_ui`.
After a change, test the configuration and reload nginx as in the first step below.

> **Warning**
>
> The interface of dcm4chee has no locks. Whoever may open it can delete studies and change the configuration of the archive.
> The locks and the header `X-PACS-Admin` of the admin page do not apply here. nginx writes every change (all calls except GET,
> HEAD and OPTIONS) to the audit log with the account, and it records small changes with their content. The log shows what
> happened. It does not undo it. Give access only to people whom you would also trust with the vendor tool.

#### Step 1. Put the file in place

Skip this step if the folder already holds the file.

```bash
ls /opt/ohif/nginx/pacs/optional/
```

If the output does not list `dcm4chee-ui.conf`, copy it, test the configuration and reload nginx:

```bash
cp /opt/pacs-admin/deploy/nginx/optional/dcm4chee-ui.conf /opt/ohif/nginx/pacs/optional/
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

> **Check**
>
> Expected: `nginx -t` prints `syntax is ok` and `test is successful`. nginx reloads without an outage. If it prints an error,
> nginx keeps the old configuration: fix the message, then reload. The message `unknown "pacs_dcm4chee_ui" variable` means
> that the listener files were not copied ([troubleshooting](troubleshooting.md#nginx-wont-start)).

#### Step 2. Open the interface

Log in as an admin and choose the link `dcm4chee` in the header of the admin page. Or open
`https://pacs.example.org/dcm4chee-arc/ui2/`. The entry page deletes the Keycloak settings that the browser may remember, then
opens the interface in German unless the browser remembers another language.

```bash
curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/dcm4chee
```

> **Check**
>
> Expected: `301` from the command (a redirect to `/dcm4chee-arc/ui2/` that needs no login). In the browser: the interface
> shows its list of studies. If the browser shows `404` or an empty page, see
> [troubleshooting](troubleshooting.md#dcm4chee-ui-404). If the header link `dcm4chee` is missing, the setting `dcm4cheeUrl`
> in `config.js` is empty ([reference](reference.md#config-js)).

<a id="dcm4chee-ui-off"></a>
#### Switch it off

Delete the file and reload nginx. Nothing else changes.

```bash
rm /opt/ohif/nginx/pacs/optional/dcm4chee-ui.conf
docker exec ohif nginx -t && docker exec ohif nginx -s reload
```

> **Check**
>
> ```bash
> curl -sk -o /dev/null -w '%{http_code}\n' https://pacs.example.org/dcm4chee
> ```
>
> Expected: not `301`. Every call of the interface gives `404` now. To hide the link `dcm4chee` in the header of the admin
> page, set `dcm4cheeUrl: ''` in `config.js`.
