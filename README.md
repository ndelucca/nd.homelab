# Fedora Home Server — Ansible

Automatización con Ansible de un home server Fedora: DNS/DHCP de la LAN, un
reverse proxy con TLS real y ~12 apps self-hosted como contenedores Podman
rootless — todas accesibles por nombre en la LAN, con **nada expuesto a
internet**.

## La arquitectura de un vistazo

- **Split-horizon DNS + certs reales.** AdGuard Home resuelve el dominio público
  (`ndelucca.dedyn.io`, alojado en deSEC) *internamente* a la IP de LAN del
  servidor. Un cert wildcard de Let's Encrypt se emite fuera de banda vía el
  challenge **DNS-01** (`roles/acme`, lego + deSEC), así el browser ve un cert
  confiable sin abrir jamás un puerto a internet.
- **Reverse proxy NGINX** termina el TLS de cada app en `192.168.10.10` y hace
  proxy a cada backend en `127.0.0.1`. Las apps escuchan solo en loopback; solo
  `53` (DNS), `80/443` (NGINX), DHCP y el git-SSH `2222` de Forgejo dan a la LAN.
- **Podman rootless + Quadlet.** Las apps en contenedor corren como el usuario sin
  privilegios `ndelucca` vía units de systemd Quadlet (`.container`, más `.kube`
  para el pod multi-contenedor de Immich).
- **Almacenamiento que sobrevive a una reinstalación.** Todo el estado
  irremplazable vive en discos de datos montados por UUID, no en root. Root
  contiene solo el SO y es 100% reproducible desde este playbook; re-correrlo
  tras una instalación limpia devuelve las apps con sus datos. Ver
  `inventory/group_vars/homeservers/storage.yml`.

## Servicios

| Subdominio (`*.ndelucca.dedyn.io`) | App | Role | Deploy |
|---|---|---|---|
| `adguard.` / apex | AdGuard Home (DNS + DHCP) | `adguard` | binario nativo |
| `cockpit.` | Cockpit (admin web) | `cockpit` | host (localhost + NGINX) |
| `files.` | FileBrowser | `filebrowser` | binario nativo |
| `jellyfin.` | Jellyfin (media) | `jellyfin` | paquete |
| `torrent.` | Cloud Torrent | `cloud_torrent` | binario nativo |
| `gallery.` | Immich (fotos) | `immich` | pod Podman `.kube` |
| `books.` | Kavita (lectura) | `kavita` | Podman `.container` |
| `slicer.` | OrcaSlicer (web) | `orcaslicer` | Podman `.container` |
| `home.` | Home Assistant | `home_assistant` | Podman `.container` |
| `git.` | Forgejo (+ git SSH :2222) | `forgejo` | Podman `.container` |
| `status.` | Uptime-Kuma | `monitoring` | Podman `.container` |
| `market.` | nd.market (Markets) | `nd_market` | Podman `.container` (Forgejo Actions) |

Roles transversales: `storage` (discos), `acme` (TLS), `nginx` (proxy),
`firewall` (firewalld), `backup` (restic → D-Ursa), `service_maintenance`
(watchdog de arranque en frío de AdGuard), `claude_bridge` (socket unix que
expone el CLI de Claude del host a las apps containerizadas; no escucha en red).

## Estructura del repositorio

```
ansible.cfg                         # config del proyecto (archivo de vault password, SSH, become)
requirements.yml                    # colecciones de Galaxy (ansible.posix, community.general)
inventory/
  hosts.yml                         # grupos homeservers / printers / clients
  group_vars/
    all/{main,vault}.yml            # base_domain + secretos compartidos
    homeservers/{services,storage,vault}.yml   # config de app/red, layout de discos, secretos
playbooks/
  site.yml                          # orquestación completa (correr este); un servicio con --tags <role>
  printers.yml, mainsailos_update.yml  # plays de la impresora Raspberry Pi (hosts: printers)
  hosts.yml                         # gestionar entradas de /etc/hosts
  remove_adguard.yml                # desmontar la instalación de AdGuard
  update.yml                        # reportar actualizaciones disponibles de imágenes de contenedor
roles/<role>/                       # un role por incumbencia: tasks/ defaults/ templates/ handlers/ meta/
docs/                               # BOOTSTRAP, RESTORE, TLS-AND-DNS, ADGUARD_CONFIG_SETUP
raspberry-scripts/                  # helpers sueltos para las Raspberry Pi (pendientes de refactor)
```

Los roles siguen un esqueleto consistente: `preflight → install → [configure] →
quadlet → selinux → service`. Los roles de contenedores rootless-Podman/Quadlet
(kavita, immich, forgejo, home_assistant, orcaslicer, monitoring) comparten su
**install + handlers, el paso de SELinux y el paso de service** vía el role
**`container_base`**: cada uno los incluye por nombre (`include_role … tasks_from:
install` / `selinux` / `service`) y expone las variables de contrato
(`container_base_user`, `container_base_uid`, `container_base_service_name`,
`container_base_selinux_paths`, `container_base_host`, `container_base_port`) vía
el `vars:` de cada `include_role`. Solo `preflight` (directorios específicos del role) y
`quadlet` (el template `.container`/`.kube` propio del role) quedan por role.

## Prerequisitos

- **Nodo de control:** Ansible 2.14+, Python 3.8+, y las colecciones:
  `ansible-galaxy collection install -r requirements.yml`
- **Target:** Fedora Server, autenticación SSH por clave, sudo. El nodo de
  control se conecta como `ndelucca` con `~/.ssh/id_ed25519` (ver `ansible.cfg`).
- **Vault password:** en `.vault_pass` (gitignored). Mantené una copia en
  custodia fuera del equipo — ver [docs/BOOTSTRAP.md](docs/BOOTSTRAP.md).

Clonar:

```bash
git clone git@github.com:ndelucca/nd.homelab.git "${HOME}/nd.homelab"
cd "${HOME}/nd.homelab"
```

## Uso

```bash
# Chequeo de conectividad
ansible -l ndelucca-server homeservers -m ping

# Setup completo / converge (idempotente — seguro de re-correr)
ansible-playbook -l ndelucca-server playbooks/site.yml

# Dry run
ansible-playbook -l ndelucca-server playbooks/site.yml --check --diff

# Un solo servicio vía tags (ej. solo NGINX, o solo AdGuard)
ansible-playbook -l ndelucca-server playbooks/site.yml --tags nginx
ansible-playbook -l ndelucca-server playbooks/site.yml --tags adguard
```

> **Pasá siempre `-l ndelucca-server`** para no tocar nunca la impresora
> Raspberry ni el cliente Acer por accidente.

Cada role está tagueado con su nombre más alias temáticos (`dns`, `media`, `tls`,
`photos`, `books`, `backup`, …) y los tags de etapa transversales (`preflight`,
`install`, `service`, `selinux`, `firewall`).

### Acelerar con Mitogen (opcional)

[Mitogen](https://mitogen.networkgenomics.com/ansible_detailed.html) multiplexa
Python sobre una sola conexión SSH por host y recorta el tiempo de ejecución
(medido acá: converge real ~7m30s → ~4m10s; corridas livianas tipo `--check`
hasta ~8× más rápidas). Está **vendorizado** en `vendor/mitogen-0.3.50/` (ver
`vendor/README.md`), así que no requiere pip.

- **Encender**: descomentar las dos líneas del bloque `Mitogen` en `ansible.cfg`
  (`strategy_plugins` y `strategy`).
- **Apagar**: volver a comentarlas → Ansible vuelve a la estrategia `linear`
  (estado por defecto). Ningún comando de uso diario cambia.

Las tareas `dnf` llevan `mitogen_task_isolation: fork` porque el módulo `dnf5` de
Fedora guarda estado global de `libdnf5` que revienta al reusar el intérprete
persistente de Mitogen; ese var es inerte cuando Mitogen está apagado.

## Configuración y secretos

- Config no secreta: `inventory/group_vars/homeservers/services.yml`
  (red, rewrites de DNS, DHCP, ajustes por app) y `storage.yml` (discos).
- La única fuente de verdad del dominio es `base_domain` en
  `group_vars/all/main.yml`; todo lo demás se deriva de él.
- Los secretos viven en archivos `vault.yml` como valores `!vault` inline.
  Editar con:
  ```bash
  ansible-vault edit inventory/group_vars/homeservers/vault.yml
  # o encriptar un solo valor:
  ansible-vault encrypt_string --name <var> '<value>'
  ```
- **Las imágenes de contenedor están pinned** (tag explícito, o digest para
  Kavita) para que los despliegues sean reproducibles. Actualizá subiendo la
  variable de versión en el `defaults/main.yml` del role y re-corriendo con el
  tag de ese role. `playbooks/update.yml` reporta cuándo hay imágenes más nuevas
  disponibles upstream.

## Backups y recuperación ante desastres

El role `backup` toma snapshots restic encriptados de los datos irremplazables
(estado de las apps + dumps de DB, la galería de Immich, los libros, el archivo
de D-Leo) hacia **D-Ursa**, en un timer de usuario de systemd diario. El
mantenimiento semanal hace prune y corre `restic check`; un **restore drill
mensual** restaura los últimos dumps de DB a un directorio temporal para probar
que el repo es restaurable. Las fallas se hacen visibles vía `OnFailure=` en el
journal, y en ntfy si `backup_notify_ntfy_url` está seteada en `services.yml`
(el mismo topic también recibe los avisos de falla de renovación de TLS).

- [docs/BOOTSTRAP.md](docs/BOOTSTRAP.md) — reconstruir el host desde cero.
- [docs/RESTORE.md](docs/RESTORE.md) — restaurar datos desde D-Ursa.
- [docs/TLS-AND-DNS.md](docs/TLS-AND-DNS.md) — diseño de Let's Encrypt / DNS.
- [docs/ADGUARD_CONFIG_SETUP.md](docs/ADGUARD_CONFIG_SETUP.md) — notas de setup de AdGuard.

```bash
# Correr un backup / restore drill ahora (como el usuario de servicio):
systemctl --user -M ndelucca@ start backup.service
systemctl --user -M ndelucca@ start backup-restore-drill.service
```

## Agregar un servicio

Creá `roles/<service>/` siguiendo un role de contenedor existente (ej. `kavita`
para un solo contenedor, `immich` para un pod) — reutilizá `container_base` para
el install de Podman y los handlers compartidos, y solo proveé las variables de
contrato `container_*` en el `defaults/main.yml` del nuevo role. Agregalo a
`playbooks/site.yml`, dejá un vhost de NGINX en
`roles/nginx/templates/conf.d/<service>.conf.j2` (autodescubierto), un rewrite de
DNS de AdGuard en `services.yml` y — solo si debe dar a la LAN directamente — una
entrada en `firewall_open_ports` del role firewall.

## Licencia

MIT
