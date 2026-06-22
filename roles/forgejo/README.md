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
- HTTP served behind NGINX at `https://git.ndelucca.dedyn.io`
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
| `forgejo_domain` | `git.ndelucca.dedyn.io` | Public domain |
| `forgejo_root_url` | `https://{{ forgejo_domain }}/` | External root URL |
| `forgejo_admin_user` | `ndelucca` | Initial admin username |
| `forgejo_admin_email` | `ndelucca@protonmail.com` | Initial admin email |
| `forgejo_admin_password` | `""` | **Required** — set via Ansible Vault in host_vars |
| `forgejo_disable_registration` | `true` | Disable open self-registration |
| `forgejo_firewall_enabled` | `true` | Open the git SSH port in firewalld |
| `forgejo_manage_selinux` | `true` | Manage SELinux file contexts |

## Tags

`forgejo`, `preflight`, `install`, `quadlet`, `service`, `admin`, `mirror`, `selinux`

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

## Mirroring GitHub repositories (pull mirrors)

The home-server is local and **not reachable from GitHub**, but GitHub is always
reachable **from** the server. So syncing is done with **pull mirrors**: Forgejo
reaches out to GitHub and fetches changes periodically. In this model **GitHub is
the source of truth** and the Forgejo repos are **read-only mirrors** — they are
overwritten on every sync, so you push to GitHub, not to Forgejo.

The role enumerates all of the user's GitHub repositories (including private,
forks and archived) and creates each one in Forgejo as a pull mirror via the
`POST /api/v1/repos/migrate` API (`mirror: true`). It is idempotent: repos that
already exist are skipped (HTTP 409).

> **Push mirror vs. pull mirror are mutually exclusive on a repo.** A pull-mirror
> repo is managed by Forgejo and cannot be pushed to. That is why a repo that was
> created normally (e.g. an early manual `git push`) must be **deleted and
> recreated** as a mirror — list it in `forgejo_mirror_force_recreate` for a
> single run.

### Setup

1. **Create a GitHub PAT.** Classic token with the `repo` scope (reads and clones
   private repos), or a fine-grained token with **Contents: Read** +
   **Metadata: Read** over all repositories.

2. **Encrypt it into host_vars** with the repo's vault password file:

   ```bash
   ansible-vault encrypt_string --name forgejo_github_token '<PAT>'
   ```

   Paste the resulting `!vault |` block into
   `inventory/host_vars/ndelucca-server.yml` and set:

   ```yaml
   forgejo_pull_mirror_enabled: true
   forgejo_mirror_force_recreate:
     - environment        # one-time, then empty it
   ```

3. **Deploy:**

   ```bash
   ansible-playbook playbooks/forgejo.yml -l ndelucca-server --tags forgejo,mirror
   ```

4. **Empty `forgejo_mirror_force_recreate`** after the first successful run (it is
   destructive — it deletes the named Forgejo repos before recreating them).

### Relevant variables

| Variable | Default | Description |
|----------|---------|-------------|
| `forgejo_pull_mirror_enabled` | `false` | Master switch for GitHub mirroring |
| `forgejo_github_token` | `""` | **Required** GitHub PAT (set via Vault) |
| `forgejo_mirror_interval` | `8h0m0s` | Periodic fetch interval (≥ `MIN_INTERVAL`) |
| `forgejo_mirror_include_forks` | `true` | Mirror forks |
| `forgejo_mirror_include_archived` | `true` | Mirror archived repos |
| `forgejo_mirror_max_pages` | `5` | Pagination cap (100/page); fails if exceeded |
| `forgejo_mirror_force_recreate` | `[]` | Repos to delete+recreate as mirrors (one-time) |

Verify in the Web UI (`https://git.ndelucca.dedyn.io/ndelucca`) that the repos
appear with the **mirror** badge; use "Synchronize Now" on a repo to confirm a
GitHub commit lands in Forgejo.

## Author

Naza
