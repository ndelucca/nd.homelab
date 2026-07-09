# Plantillas del modo `enable`

Sustituir tres nombres derivados (¡pueden diferir entre sí!):
- **`__APP__`** = **nombre ansible/service** = nombre de repo con `[.-]`→`_` (siempre
  `^[a-z][a-z0-9_]*$`, la convención de la casa: `home_assistant`, `cloud_torrent`). Es el
  **dir del rol**, el **prefijo de variables**, el **container**, el **service/unit** y el
  **target de deploy** (el dispatcher `home-deploy` acepta `[a-z0-9_-]`). Ej: `nd_market`.
- **`__REPO__`** = **nombre de repo** tal cual (con puntos/guiones si los hay): va **solo** en el
  path de la **imagen** del registry. Ej: `nd.market`. Sin punto ni guión, `__REPO__` == `__APP__`.
- **`__SUB__`** = **subdominio** (single-label DNS: sin punto ni guión_bajo — el cert wildcard
  cubre un solo nivel). Por defecto = nombre de repo con `[._]`→`-`; el usuario suele pedir uno más
  corto (ej. `market`). Ej: `market`.

Y además: `__OWNER__` (default `ndelucca`), `__PORT__` (puerto host en loopback, elegir uno
libre), `__CPORT__` (puerto del contenedor, del `EXPOSE`). Estas plantillas siguen el patrón de
`roles/forgejo` y `roles/kavita`; ante dudas, leé esos roles vivos.

> Ejemplo `hello-world` (guión): `__APP__`=`hello_world`, `__REPO__`=`hello-world`, `__SUB__`=`hello-world`.
> Ejemplo `nd.market` (punto): `__APP__`=`nd_market`, `__REPO__`=`nd.market`, `__SUB__`=`market` (elegido).

---

## `roles/__APP__/defaults/main.yml`

```yaml
---
# Variables por defecto del role __APP__ (app deployada por Forgejo Actions).

__APP___user: ndelucca
__APP___group: ndelucca
__APP___uid: 1000  # Se obtiene dinámicamente vía getent en preflight

__APP___base_dir: "{{ app_data_root }}/__APP__"
__APP___data_dir: "{{ __APP___base_dir }}/data"

__APP___quadlet_dir: /etc/containers/systemd/users
__APP___container_name: __APP__

# Imagen publicada por el workflow en el registry de Forgejo (usa el NOMBRE DE REPO, con puntos).
__APP___image: "git.{{ nginx_domain }}/__OWNER__/__REPO__:latest"

__APP___port: __PORT__            # HTTP en loopback, servido vía NGINX
__APP___host: 127.0.0.1
__APP___container_port: __CPORT__ # puerto que escucha la app dentro del contenedor

__APP___service_name: __APP__
__APP___service_enabled: true
__APP___service_state: started

__APP___manage_selinux: true
```

---

## `roles/__APP__/meta/main.yml`

```yaml
---
galaxy_info:
  author: Naza
  description: Deploy __APP__ (Forgejo-built container) on Fedora
  license: MIT
  min_ansible_version: '2.13'
  platforms:
    - name: Fedora
      versions:
        - all

dependencies: []

collections:
  - community.general
  - ansible.posix
```

---

## `roles/__APP__/tasks/main.yml`

```yaml
---
# Punto de entrada principal del role __APP__.

- name: Include preflight checks
  ansible.builtin.import_tasks: preflight.yml
  tags: ['__APP__', 'preflight']

- name: Install Podman and dependencies
  ansible.builtin.include_role:
    name: container_base
    tasks_from: install
  vars:
    container_base_user: "{{ __APP___user }}"
  tags: ['__APP__', 'install']

- name: Deploy Quadlet configuration
  ansible.builtin.import_tasks: quadlet.yml
  tags: ['__APP__', 'quadlet']

- name: Configure SELinux (shared container_base step)
  ansible.builtin.include_role:
    name: container_base
    tasks_from: selinux
  vars:
    container_base_selinux_paths: "{{ [__APP___data_dir] }}"
  tags: ['__APP__', 'selinux']
  when: __APP___manage_selinux | bool

- name: Configure systemd service (shared container_base step)
  ansible.builtin.include_role:
    name: container_base
    tasks_from: service
  vars:
    container_base_user: "{{ __APP___user }}"
    container_base_uid: "{{ __APP___uid }}"
    container_base_service_name: "{{ __APP___service_name }}"
    container_base_host: "{{ __APP___host }}"
    container_base_port: "{{ __APP___port }}"
    container_base_service_enabled: "{{ __APP___service_enabled }}"
    container_base_service_state: "{{ __APP___service_state }}"
  tags: ['__APP__', 'service']
```

---

## `roles/__APP__/tasks/preflight.yml`

```yaml
---
- name: Verify Fedora operating system
  ansible.builtin.assert:
    that:
      - ansible_facts['distribution'] == "Fedora"
    fail_msg: "This role only supports Fedora"

- name: Resolve __APP__ user UID for rootless Podman
  ansible.builtin.getent:
    database: passwd
    key: "{{ __APP___user }}"
  check_mode: false

- name: Set __APP___uid fact
  ansible.builtin.set_fact:
    __APP___uid: "{{ ansible_facts['getent_passwd'][__APP___user][1] }}"

- name: Ensure base and data directories exist
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: "{{ __APP___user }}"
    group: "{{ __APP___group }}"
    mode: '0750'
  become: true
  loop:
    - "{{ __APP___base_dir }}"
    - "{{ __APP___data_dir }}"
```

---

## `roles/__APP__/tasks/quadlet.yml`

```yaml
---
- name: Ensure systemd user directory exists
  ansible.builtin.file:
    path: "{{ __APP___quadlet_dir }}/{{ __APP___uid }}"
    state: directory
    owner: root
    group: root
    mode: '0755'
  become: true

- name: Deploy __APP__ Quadlet .container unit
  ansible.builtin.template:
    src: __APP__.container.j2
    dest: "{{ __APP___quadlet_dir }}/{{ __APP___uid }}/{{ __APP___service_name }}.container"
    owner: root
    group: root
    mode: '0644'
  become: true
  notify:
    - Container daemon-reload-user
    - Container restart
```

---

## `roles/__APP__/templates/__APP__.container.j2`

```jinja
[Unit]
Description=__APP__ Container
After=network-online.target
Wants=network-online.target

[Container]
Image={{ __APP___image }}
ContainerName={{ __APP___container_name }}

UserNS=keep-id:uid={{ __APP___uid }},gid={{ __APP___uid }}

# HTTP en loopback; NGINX lo sirve en https://__SUB__.{{ nginx_domain }}.
PublishPort={{ __APP___host }}:{{ __APP___port }}:{{ __APP___container_port }}

Volume={{ __APP___data_dir }}:/data:Z

# Pull=newer: al reiniciar (lo hace `home-deploy`), el Quadlet re-baja :latest del registry.
# El nombre de la imagen vive acá (Image=), no se deriva del nombre de la app.
Pull=newer

[Service]
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target default.target
```

---

## Wiring — ediciones a archivos existentes

### `roles/nginx/defaults/main.yml`

Agregar la var de puerto backend (junto a las otras `nginx_*_port`):
```yaml
nginx___APP___port: __PORT__
```
Y una entrada en `nginx_vhosts` (el `subdomain` es `__SUB__`, sin punto):
```yaml
  - {subdomain: "__SUB__", port: "{{ nginx___APP___port }}"}
```
Si la app usa websocket/SSE o subidas grandes, agregar los params correspondientes
(`websocket`, `client_max_body_size`, `server_snippet`, `location_snippet`) — ver los ejemplos
en el mismo archivo.

### `inventory/group_vars/homeservers/services.yml`

Agregar el rewrite DNS en `adguard_dns_rewrites` (junto a las apps del server; usa `__SUB__`):
```yaml
  - domain: "__SUB__.{{ nginx_domain }}"
    answer: 192.168.10.10
    enabled: true
```

### `roles/firewall/defaults/main.yml`

Agregar en `firewall_blocked` (queda detrás de NGINX, no se abre):
```yaml
  - { port: "__PORT__/tcp", comment: "__APP__ direct — localhost only, behind NGINX" }
```

### `playbooks/site.yml`

Registrar el rol entre las apps:
```yaml
    - role: __APP__
      tags: ['__APP__']
```

---

## Pull de imágenes privadas (login al registry en el host)

Si el repo/paquete es **privado**, el `podman pull` (que hace la unit del Quadlet vía
`Pull=newer`, corriendo como `ndelucca`) necesita que `ndelucca` esté logueado al registry en
el host. (Con paquete público el pull es anónimo y no hace falta login.) Es un login
persistente reproducible (una vez, no por-app): una tarea que corra
`podman login --username ndelucca --password-stdin git.{{ nginx_domain }}` con el token
vaulteado (`vault_forgejo_api_token`) como `become_user: ndelucca` (crea
`~/.config/containers/auth.json`). Alternativa: hacer el paquete público en Forgejo.
