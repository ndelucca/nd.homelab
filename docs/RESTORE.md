# Restore runbook (restic ← D-Ursa)

How to recover data after losing the appdata disk (**D-Draco**) or after a bad
state change. Backups are restic snapshots on **D-Ursa** (`/srv/disks/D-Ursa/restic`),
written daily by the `backup` role.

> The repository is **automatically restore-tested** once a month by the
> `backup-restore-drill.timer` (restores the latest DB dumps to a temp dir and
> checks them). A failure pushes an alert via the notify path. Still, read this
> before a real restore — a drill proves *restorability*, not *your* procedure.

## 0. Prerequisites

The restic password lives in two places, so a restore needs nothing memorised:

- the vault: `backup_password` in `inventory/group_vars/homeservers/vault.yml`
  (decrypts with the vault password — keep that escrowed off-box, see BOOTSTRAP.md)
- on the box: `/home/ndelucca/.config/restic/password` (0600), recreated by the playbook

All commands run as the service user **ndelucca** (uid 1000). Export the repo env once:

```bash
export RESTIC_REPOSITORY=/srv/disks/D-Ursa/restic
export RESTIC_PASSWORD_FILE=/home/ndelucca/.config/restic/password
```

## 1. Inspect what you have

```bash
restic snapshots                 # list snapshots (note the ID/time you want)
restic check                     # verify repository integrity before relying on it
restic ls latest | head          # peek at the file tree of the latest snapshot
```

## 2. Restore application data (D-Draco lost or wiped)

After re-mounting a fresh D-Draco (see below) and before starting the apps:

```bash
# Restore app STATE + the irreplaceable media back to their original paths.
# --target / restores to absolute paths captured in the snapshot.
restic restore latest --target / \
  --include /srv/disks/D-Draco/appdata \
  --include /srv/disks/D-Draco/media/Gallery \
  --include /srv/disks/D-Draco/media/Books \
  --include /srv/disks/D-Leo
```

Fix ownership (everything under the appdata disk must be `ndelucca:ndelucca`,
uid/gid 1000 — pinned for rootless Podman `UserNS=keep-id`):

```bash
sudo chown -R 1000:1000 /srv/disks/D-Draco/appdata /srv/disks/D-Draco/media
```

Movies/Series are **not** in backup by design (re-downloadable) — recreate the
empty dirs so the apps have their library roots:

```bash
mkdir -p /srv/disks/D-Draco/media/Movies /srv/disks/D-Draco/media/Series
```

## 3. Restore databases from the dumps (authoritative)

The live DB files are captured too, but the **dumps** under
`.../appdata/<app>/dumps/` are the consistent, authoritative restore source.

**Immich (PostgreSQL):** start only the database container, then load the dump.

```bash
# With the immich pod running (or just immich-database):
gunzip -c /srv/disks/D-Draco/appdata/immich/dumps/immich.sql.gz \
  | podman exec -i immich-database psql -U immich -d immich
```

**SQLite apps (Jellyfin, Forgejo, Kavita):** with the app **stopped**, copy the
dump over the live DB. The user-service unit names are `jellyfin`, `forgejo` and
`kavita` respectively (all single-container quadlets):

```bash
# Forgejo example — repeat per app with the unit/path from the role defaults.
systemctl --user stop forgejo            # stop the app first (jellyfin / kavita likewise)
cp /srv/disks/D-Draco/appdata/forgejo/dumps/forgejo.db \
   /srv/disks/D-Draco/appdata/forgejo/data/data/gitea.db
```

**FileBrowser (BoltDB):** same idea — stop, copy `filebrowser/dumps/filebrowser.db`
over the live `filebrowser/filebrowser.db`.

## 4. Bring the apps back

```bash
ansible-playbook -l ndelucca-server playbooks/site.yml
```

Re-running the playbook recreates configs/units and starts the services against
the restored data. Verify each service responds (see the checklist below).

## 5. Targeted / point-in-time restore

```bash
# Restore one app's state from a specific snapshot into a temp dir to inspect.
restic restore <snapshot-id> --target /tmp/inspect \
  --include /srv/disks/D-Draco/appdata/kavita
# Or restore a single file:
restic dump <snapshot-id> /srv/disks/D-Draco/appdata/forgejo/dumps/forgejo.db > /tmp/forgejo.db
```

## Verification checklist

- [ ] `restic check` clean
- [ ] Ownership is `1000:1000` under `D-Draco/appdata` and `D-Draco/media`
- [ ] Immich: `curl -k https://gallery.ndelucca.dedyn.io` and photos visible
- [ ] Forgejo/Jellyfin/Kavita reachable on their subdomains, data present
- [ ] `journalctl --user -M ndelucca@ -u backup.service` shows the next run OK
