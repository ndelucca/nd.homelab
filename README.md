# Fedora Home Server — Ansible

Ansible automation for a Fedora home server: LAN DNS/DHCP, a reverse proxy with
real TLS, and ~12 self-hosted apps as rootless Podman containers — all reachable
on the LAN by name, with **nothing exposed to the internet**.

## Architecture at a glance

- **Split-horizon DNS + real certs.** AdGuard Home resolves the public domain
  (`ndelucca.dedyn.io`, hosted at deSEC) *internally* to the server's LAN IP.
  A wildcard Let's Encrypt cert is issued out-of-band via the **DNS-01**
  challenge (`roles/acme`, lego + deSEC), so browsers see a trusted cert while
  no port is ever opened to the internet.
- **NGINX reverse proxy** terminates TLS for every app on `192.168.10.10` and
  proxies to each backend on `127.0.0.1`. Apps bind to loopback only; only
  `53` (DNS), `80/443` (NGINX), DHCP and Forgejo's git-SSH `2222` face the LAN.
- **Rootless Podman + Quadlet.** Containerized apps run as the unprivileged
  `ndelucca` user via systemd Quadlet units (`.container`, plus `.kube` for the
  multi-container Immich pod).
- **Storage that survives a reinstall.** All irreplaceable state lives on
  UUID-mounted data disks, not on root. Root holds only the OS and is 100%
  reproducible from this playbook; re-running it after a fresh install brings
  the apps back with their data. See `inventory/group_vars/homeservers/storage.yml`.

## Services

| Subdomain (`*.ndelucca.dedyn.io`) | App | Role | Deploy |
|---|---|---|---|
| `adguard.` / apex | AdGuard Home (DNS + DHCP) | `adguard_home` | native binary |
| `cockpit.` | Cockpit (web admin) | `cockpit` | host (localhost + NGINX) |
| `files.` | FileBrowser | `filebrowser` | native binary |
| `jellyfin.` | Jellyfin (media) | `jellyfin` | package |
| `torrent.` | Cloud Torrent | `cloud_torrent` | native binary |
| `gallery.` | Immich (photos) | `immich` | Podman `.kube` pod |
| `books.` | Kavita (reading) | `kavita` | Podman `.container` |
| `slicer.` | OrcaSlicer (web) | `orcaslicer` | Podman `.container` |
| `home.` | Home Assistant | `home_assistant` | Podman `.container` |
| `git.` | Forgejo (+ git SSH :2222) | `forgejo` | Podman `.container` |
| `status.` | Uptime-Kuma | `monitoring` | Podman `.container` |
| `market.` | nd.markets | (external app) | reverse-proxied only |

Cross-cutting roles: `storage` (disks), `acme` (TLS), `nginx` (proxy),
`firewall` (firewalld), `backup` (restic → D-Ursa), `service_maintenance`
(AdGuard cold-boot watchdog).

## Repository layout

```
ansible.cfg                         # project config (vault password file, SSH, become)
requirements.yml                    # Galaxy collections (ansible.posix, community.general)
inventory/
  hosts.yml                         # homeservers / printers / clients groups
  group_vars/
    all/{main,vault}.yml            # base_domain + shared secrets
    homeservers/{services,storage,vault}.yml   # app/network config, disk layout, secrets
playbooks/
  site.yml                          # full orchestration (run this)
  <service>.yml                     # per-service playbooks
  update.yml                        # report available container image updates
roles/<role>/                       # one role per concern: tasks/ defaults/ templates/ handlers/ meta/
docs/                               # BOOTSTRAP, RESTORE, TLS-AND-DNS, ADGUARD_CONFIG_SETUP
```

Roles follow a consistent skeleton: `preflight → install → [configure] →
quadlet → service → selinux`, with handlers for daemon-reload / restart /
SELinux relabel.

## Prerequisites

- **Control node:** Ansible 2.14+, Python 3.8+, and the collections:
  `ansible-galaxy collection install -r requirements.yml`
- **Target:** Fedora Server, SSH key auth, sudo. The control node connects as
  `ndelucca` with `~/.ssh/id_rsa` (see `ansible.cfg`).
- **Vault password:** in `.vault_pass` (gitignored). Keep a copy escrowed
  off-box — see [docs/BOOTSTRAP.md](docs/BOOTSTRAP.md).

## Usage

```bash
# Connectivity check
ansible -l ndelucca-server homeservers -m ping

# Full setup / converge (idempotent — safe to re-run)
ansible-playbook -l ndelucca-server playbooks/site.yml

# Dry run
ansible-playbook -l ndelucca-server playbooks/site.yml --check --diff

# One service via tags (e.g. just NGINX, or just AdGuard)
ansible-playbook -l ndelucca-server playbooks/site.yml --tags nginx
ansible-playbook -l ndelucca-server playbooks/site.yml --tags adguard
```

> **Always pass `-l ndelucca-server`** so you never touch the Raspberry printer
> or the Acer client by accident.

Each role is tagged with its name plus topic aliases (`dns`, `media`, `tls`,
`photos`, `books`, `backup`, …) and the cross-cutting stage tags
(`preflight`, `install`, `service`, `selinux`, `firewall`).

## Configuration & secrets

- Non-secret config: `inventory/group_vars/homeservers/services.yml`
  (network, DNS rewrites, DHCP, per-app settings) and `storage.yml` (disks).
- The single source of truth for the domain is `base_domain` in
  `group_vars/all/main.yml`; everything derives from it.
- Secrets live in `vault.yml` files as inline `!vault` values. Edit with:
  ```bash
  ansible-vault edit inventory/group_vars/homeservers/vault.yml
  # or encrypt a single value:
  ansible-vault encrypt_string --name <var> '<value>'
  ```
- **Container images are pinned** (explicit tag, or digest for Kavita) so
  deployments are reproducible. Upgrade by bumping the version var in the role's
  `defaults/main.yml` and re-running with that role's tag. `playbooks/update.yml`
  reports when newer images are available upstream.

## Backups & disaster recovery

The `backup` role takes encrypted restic snapshots of the irreplaceable data
(app state + DB dumps, the Immich gallery, books, the D-Leo archive) to
**D-Ursa**, on a daily systemd user timer. Weekly maintenance prunes and runs
`restic check`; a **monthly restore drill** restores the latest DB dumps to a
temp dir to prove the repo is restorable. Failures surface via `OnFailure=` to
the journal, and to ntfy if `backup_notify_ntfy_url` is set in `services.yml`
(the same topic also receives TLS-renewal-failure alerts).

- [docs/BOOTSTRAP.md](docs/BOOTSTRAP.md) — rebuild the host from scratch.
- [docs/RESTORE.md](docs/RESTORE.md) — restore data from D-Ursa.
- [docs/TLS-AND-DNS.md](docs/TLS-AND-DNS.md) — Let's Encrypt / DNS design.
- [docs/ADGUARD_CONFIG_SETUP.md](docs/ADGUARD_CONFIG_SETUP.md) — AdGuard setup notes.

```bash
# Run a backup / restore drill now (as the service user):
systemctl --user -M ndelucca@ start backup.service
systemctl --user -M ndelucca@ start backup-restore-drill.service
```

## Adding a service

Create `roles/<service>/` following an existing container role (e.g. `kavita`
for a single container, `immich` for a pod), add it to `playbooks/site.yml`,
drop an NGINX vhost at `roles/nginx/templates/conf.d/<service>.conf.j2` (auto-
discovered), an AdGuard DNS rewrite in `services.yml`, and — only if it must
face the LAN directly — an entry in the firewall role's `firewall_open_ports`.

## License

MIT
