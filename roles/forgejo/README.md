# Forgejo Ansible Role

This role deploys [Forgejo](https://forgejo.org/) — a self-hosted, lightweight
git forge — as a rootless Podman container managed by systemd Quadlet on Fedora.

It follows the same pattern as the other container roles in this repository
(Immich, Kavita, Home Assistant): the container listens on `127.0.0.1` and is
served to the LAN through the central NGINX reverse proxy, with a dedicated
subdomain and an AdGuard DNS rewrite.

## Features

- Rootless Podman container via systemd Quadlet (`.container` unit)
- SQLite backend (single container, no external database)
- HTTP served behind NGINX at `https://git.ndelucca-server.com`
- Git over SSH on a dedicated port (`2222`) using the container's **own** SSH
  server — the host `sshd` (port 22) is never touched
- Idempotent admin-user creation
- Persistent data under `/srv/forgejo/data`
- SELinux and firewall integration
- Image pinned + `AutoUpdate=registry` (kept current by `playbooks/update.yml`)

## Requirements

- Fedora with Podman 4.4+ (Quadlet support)
- Ansible 2.13+
- Collections: `community.general`, `ansible.posix`

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `forgejo_user` / `forgejo_group` | `ndelucca` | Rootless service user/group |
| `forgejo_base_dir` | `/srv/forgejo` | Base directory |
| `forgejo_data_dir` | `{{ forgejo_base_dir }}/data` | Persistent data (repos, SQLite, config) |
| `forgejo_port` | `3000` | HTTP port (bound to `127.0.0.1`, behind NGINX) |
| `forgejo_host` | `127.0.0.1` | HTTP bind address |
| `forgejo_ssh_port` | `2222` | Git SSH port exposed on the LAN |
| `forgejo_version` | `11.0.1` | Pinned image tag |
| `forgejo_image` | `codeberg.org/forgejo/forgejo:{{ forgejo_version }}` | Container image |
| `forgejo_domain` | `git.ndelucca-server.com` | Public domain |
| `forgejo_root_url` | `https://{{ forgejo_domain }}/` | External root URL |
| `forgejo_admin_user` | `ndelucca` | Initial admin username |
| `forgejo_admin_email` | `ndelucca@protonmail.com` | Initial admin email |
| `forgejo_admin_password` | `""` | **Required** — set via Ansible Vault in host_vars |
| `forgejo_disable_registration` | `true` | Disable open self-registration |
| `forgejo_firewall_enabled` | `true` | Open the git SSH port in firewalld |
| `forgejo_manage_selinux` | `true` | Manage SELinux file contexts |

## Tags

`forgejo`, `preflight`, `install`, `quadlet`, `service`, `admin`, `selinux`

## Usage

```bash
# Deploy Forgejo only
ansible-playbook playbooks/forgejo.yml -l ndelucca-server

# As part of the full site
ansible-playbook playbooks/site.yml -l ndelucca-server --tags forgejo
```

## SSH vs. the host sshd

The git SSH service is the SSH server **inside** the Forgejo container, published
on the host as port `2222`. The system `sshd` on port `22` (your normal shell
access to the server) is completely independent and is never reconfigured or
restarted by this role. Firewalld only *adds* a rule for `2222`.

## Seeding the `home-server` repo (run once, manually)

After the role has deployed Forgejo and created the admin user, mirror this very
repository into Forgejo so it appears identical there.

```bash
# 1) Create an empty 'home-server' repo (Web UI -> + New Repository, no
#    README/license, owner: ndelucca), or via the API:
curl -k -u ndelucca:<password> -H 'Content-Type: application/json' \
  -d '{"name":"home-server","private":true,"auto_init":false}' \
  https://git.ndelucca-server.com/api/v1/user/repos

# 2) Push this repo identically (mirror) over SSH (recommended — no cert hassle).
#    First add your public key in Forgejo: Settings -> SSH Keys.
git remote add forgejo ssh://git@git.ndelucca-server.com:2222/ndelucca/home-server.git
git push forgejo --mirror

#    Alternative over HTTPS (self-signed cert -> disable verification):
git -c http.sslVerify=false push \
  https://git.ndelucca-server.com/ndelucca/home-server.git --mirror
```

Verify in the Web UI that all branches and commit history are present, then
optionally `git clone` it back to a temp dir and run `git log` to confirm parity.

## Author

Naza
