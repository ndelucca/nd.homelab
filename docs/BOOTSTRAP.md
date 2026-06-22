# Bootstrap / disaster recovery runbook

How to rebuild the home server from nothing — fresh OS, or a new box after a
root/motherboard failure. The design goal: **root holds only the OS and is 100%
reproducible from this playbook**; the irreplaceable data lives on D-Draco
(appdata/media) and D-Leo (personal), backed up to D-Ursa.

Recovery splits in two:
1. **Root failed, data disks intact** → reinstall OS, re-run playbook. Data is
   already on D-Draco/D-Leo; nothing to restore.
2. **Data disk (D-Draco) also lost** → do step 1, then follow
   [RESTORE.md](RESTORE.md) to restore from D-Ursa.

## 1. Install Fedora Server

- Install Fedora Server (matching the version the roles target; see README).
- Create the **`ndelucca` user with uid/gid 1000** — this is pinned and must
  match so rootless Podman `UserNS=keep-id` and file ownership stay valid:
  ```bash
  sudo useradd -u 1000 -m ndelucca && sudo passwd ndelucca
  sudo usermod -aG wheel ndelucca
  ```
- Set a static IP / reservation of `192.168.10.10` (the DHCP lease lives in
  AdGuard config, but on first boot AdGuard isn't up yet).

## 2. Control-node prerequisites (the machine you run Ansible from)

```bash
# Install Ansible + collections
ansible-galaxy collection install -r requirements.yml

# SSH key access to the new host
ssh-copy-id ndelucca@192.168.10.10
ssh ndelucca@192.168.10.10 true        # confirm key auth works

# Vault password — restic + all app secrets decrypt with this.
printf '%s' '<the-vault-password>' > .vault_pass && chmod 600 .vault_pass
ansible-inventory -i inventory --host ndelucca-server >/dev/null  # decrypts → no error = good
```

## 3. Attach and identify the data disks

The disks are addressed by **filesystem UUID** (stable across hardware), listed
in `inventory/group_vars/homeservers/storage.yml`:

| Disk     | Role     | UUID                                   | Mount                |
|----------|----------|----------------------------------------|----------------------|
| D-Draco  | appdata  | `be7615af-92fe-40e7-9989-4b58c0ab4e1f` | `/srv/disks/D-Draco` |
| D-Leo    | personal | `ced8adab-8745-4c2f-b1b5-2a02ed02c12e` | `/srv/disks/D-Leo`   |
| D-Ursa   | backup   | `aabf1b5e-2bf1-41f4-ab93-bc27d508fc05` | `/srv/disks/D-Ursa`  |

- **Same disks, intact:** just plug them in; `blkid` should show those UUIDs.
- **New/replacement disk:** create the filesystem, then update the matching
  `uuid:` in `storage.yml` to the new `blkid` value before running the playbook:
  ```bash
  sudo mkfs.ext4 -L D-Draco /dev/<dev>
  blkid /dev/<dev>          # copy UUID into storage.yml
  ```

The `storage` role mounts them (`nofail` + device-timeout, so the box still boots
if a disk is absent) and creates the appdata/media skeleton owned by 1000:1000.

## 4. Run the playbook

```bash
# Idempotent dry-run first
ansible-playbook -l ndelucca-server playbooks/site.yml --check --diff

# Real run
ansible-playbook -l ndelucca-server playbooks/site.yml
```

This installs and starts everything: storage, Cockpit, NGINX+TLS, AdGuard
(DNS/DHCP), all apps, backup timers, the watchdog and firewall.

## 5. If D-Draco data was lost — restore

Follow [RESTORE.md](RESTORE.md): restore appdata/media + D-Leo from D-Ursa, load
the DB dumps, fix ownership, then re-run `site.yml`.

## 6. Post-recovery checks

- [ ] `ansible-playbook -l ndelucca-server playbooks/site.yml --check` → no changes
- [ ] LAN DNS works: `dig @192.168.10.10 git.ndelucca-server.com`
- [ ] Each subdomain responds: `curl -k https://<app>.ndelucca-server.com`
- [ ] `systemctl --user -M ndelucca@ list-timers` shows backup + drill timers armed
- [ ] Trigger a backup once and confirm a fresh snapshot:
      `systemctl --user -M ndelucca@ start backup.service && restic snapshots`

## Quick reference: what survives what

| Failure                | Data outcome                          | Action                       |
|------------------------|---------------------------------------|------------------------------|
| Root / motherboard     | D-Draco/D-Leo/D-Ursa intact           | reinstall OS, re-run playbook |
| D-Draco (appdata)      | restore from D-Ursa                    | RESTORE.md                   |
| D-Ursa (backup)        | live data fine; no backups until fixed | replace disk, re-run playbook |
| D-Leo (personal)       | restore from D-Ursa                    | RESTORE.md                   |
