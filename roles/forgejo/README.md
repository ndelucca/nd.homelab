# Role de Ansible: Forgejo

Este role despliega [Forgejo](https://forgejo.org/) — un git forge liviano y
self-hosted — como contenedor Podman rootless gestionado por systemd Quadlet en
Fedora.

Sigue el mismo patrón que los otros roles de contenedor de este repositorio
(Immich, Kavita, Home Assistant): el contenedor escucha en `127.0.0.1` y se sirve
a la LAN a través del reverse proxy central de NGINX, con un subdominio dedicado y
un rewrite de DNS de AdGuard.

## Características

- Contenedor Podman rootless vía systemd Quadlet (unit `.container`)
- Backend SQLite (un solo contenedor, sin base de datos externa)
- HTTP servido detrás de NGINX en `https://git.ndelucca.dedyn.io`
- Git sobre SSH en un puerto dedicado (`2222`) usando el servidor SSH **propio**
  del contenedor — el `sshd` del host (puerto 22) nunca se toca
- Creación idempotente del usuario admin
- Datos persistentes bajo `/srv/forgejo/data`
- Integración con SELinux y firewall
- Imagen pinned por tag (sin `AutoUpdate`; subí `forgejo_version` y re-corré para
  actualizar — `playbooks/update.yml` solo reporta cuándo hay una imagen más nueva)

## Requisitos

- Fedora con Podman 4.4+ (soporte de Quadlet)
- Ansible 2.13+
- Colecciones: `community.general`, `ansible.posix`

## Variables del role

| Variable | Default | Descripción |
|----------|---------|-------------|
| `forgejo_user` / `forgejo_group` | `ndelucca` | Usuario/grupo de servicio rootless |
| `forgejo_base_dir` | `/srv/forgejo` | Directorio base |
| `forgejo_data_dir` | `{{ forgejo_base_dir }}/data` | Datos persistentes (repos, SQLite, config) |
| `forgejo_port` | `3000` | Puerto HTTP (bound a `127.0.0.1`, detrás de NGINX) |
| `forgejo_host` | `127.0.0.1` | Dirección de bind HTTP |
| `forgejo_ssh_port` | `2222` | Puerto SSH de git expuesto en la LAN |
| `forgejo_version` | `11.0.1` | Tag de imagen pinned |
| `forgejo_image` | `codeberg.org/forgejo/forgejo:{{ forgejo_version }}` | Imagen del contenedor |
| `forgejo_domain` | `git.ndelucca.dedyn.io` | Dominio público |
| `forgejo_root_url` | `https://{{ forgejo_domain }}/` | Root URL externa |
| `forgejo_admin_user` | `ndelucca` | Usuario admin inicial |
| `forgejo_admin_email` | `ndelucca@protonmail.com` | Email del admin inicial |
| `forgejo_admin_password` | `""` | **Requerido** — setear vía Ansible Vault en vault.yml |
| `forgejo_disable_registration` | `true` | Deshabilitar el auto-registro abierto |
| `forgejo_firewall_enabled` | `true` | Abrir el puerto SSH de git en firewalld |
| `forgejo_manage_selinux` | `true` | Gestionar los contextos de archivo de SELinux |

## Tags

`forgejo`, `preflight`, `install`, `quadlet`, `service`, `admin`, `mirror`, `selinux`

## Uso

```bash
# Desplegar solo Forgejo
ansible-playbook playbooks/site.yml -l ndelucca-server --tags forgejo

# Como parte del site completo
ansible-playbook playbooks/site.yml -l ndelucca-server
```

## SSH vs. el sshd del host

El servicio SSH de git es el servidor SSH que corre **dentro** del contenedor de
Forgejo, publicado en el host como puerto `2222`. El `sshd` del sistema en el
puerto `22` (tu acceso de shell normal al servidor) es completamente independiente
y este role nunca lo reconfigura ni lo reinicia. Firewalld solo *agrega* una regla
para el `2222`.

## Espejar repositorios de GitHub (pull mirrors)

El home-server es local y **no es accesible desde GitHub**, pero GitHub siempre es
accesible **desde** el servidor. Por eso la sincronización se hace con **pull
mirrors**: Forgejo sale hacia GitHub y trae los cambios periódicamente. En este
modelo **GitHub es la fuente de verdad** y los repos de Forgejo son **mirrors de
solo lectura** — se sobrescriben en cada sync, así que pusheás a GitHub, no a
Forgejo.

El role enumera todos los repositorios de GitHub del usuario (incluyendo privados,
forks y archivados) y crea cada uno en Forgejo como pull mirror vía la API
`POST /api/v1/repos/migrate` (`mirror: true`). Es idempotente: los repos que ya
existen se saltean (HTTP 409).

> **Push mirror y pull mirror son mutuamente excluyentes en un repo.** Un repo
> pull-mirror lo gestiona Forgejo y no se le puede pushear. Por eso un repo creado
> normalmente (ej. un `git push` manual temprano) debe ser **borrado y recreado**
> como mirror — listalo en `forgejo_mirror_force_recreate` para una sola corrida.

### Setup

1. **Creá un PAT de GitHub.** Token clásico con el scope `repo` (lee y clona repos
   privados), o un token fine-grained con **Contents: Read** + **Metadata: Read**
   sobre todos los repositorios.

2. **Encriptalo en el vault** con el archivo de vault password del repo:

   ```bash
   ansible-vault encrypt_string --name forgejo_github_token '<PAT>'
   ```

   Pegá el bloque `!vault |` resultante en
   `inventory/group_vars/homeservers/vault.yml`, y en
   `inventory/group_vars/homeservers/services.yml` seteá:

   ```yaml
   forgejo_pull_mirror_enabled: true
   forgejo_mirror_force_recreate:
     - environment        # una sola vez, luego vaciarlo
   ```

3. **Desplegá:**

   ```bash
   ansible-playbook playbooks/site.yml -l ndelucca-server --tags forgejo,mirror
   ```

4. **Vaciá `forgejo_mirror_force_recreate`** después de la primera corrida exitosa
   (es destructivo — borra los repos de Forgejo nombrados antes de recrearlos).

### Variables relevantes

| Variable | Default | Descripción |
|----------|---------|-------------|
| `forgejo_pull_mirror_enabled` | `false` | Switch maestro del mirroring de GitHub |
| `forgejo_github_token` | `""` | PAT de GitHub **requerido** (setear vía Vault) |
| `forgejo_mirror_interval` | `8h0m0s` | Intervalo de fetch periódico (≥ `MIN_INTERVAL`) |
| `forgejo_mirror_include_forks` | `true` | Espejar forks |
| `forgejo_mirror_include_archived` | `true` | Espejar repos archivados |
| `forgejo_mirror_max_pages` | `5` | Tope de paginación (100/página); falla si se excede |
| `forgejo_mirror_force_recreate` | `[]` | Repos a borrar+recrear como mirrors (una sola vez) |

Verificá en la UI web (`https://git.ndelucca.dedyn.io/ndelucca`) que los repos
aparezcan con el badge de **mirror**; usá "Synchronize Now" en un repo para
confirmar que un commit de GitHub llega a Forgejo.

## Autor

Naza
