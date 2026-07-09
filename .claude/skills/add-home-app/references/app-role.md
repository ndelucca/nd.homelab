# Plantillas del modo `enable`

Sustituir cuatro placeholders (¡ojo que el slug y el nombre de repo pueden diferir!):
- **`__SLUG__`** = **slug** (repo con `.`→`-`, siempre `^[a-z0-9-]+$`): nombre del **dir del rol**,
  del **container**, del **service** y del **subdominio por defecto**. Ej: `nd-market`.
- **`__REPO__`** = **nombre de repo** tal cual (con puntos si los hay): va **solo** en el path de
  la **imagen** del registry. Ej: `nd.market`. Sin punto, `__REPO__` == `__SLUG__`.
- **`__VAR__`** = slug con **guiones → guiones bajos**: prefijo de las **variables Ansible**
  (los nombres de variable NO admiten guiones ni puntos). Ej: `nd_market`.
- **`__SUB__`** = **subdominio** (single-label, sin punto — el cert wildcard cubre un solo nivel).
  Por defecto = `__SLUG__`; el usuario puede pedir uno más corto (ej. `market`).

Y además: `__OWNER__` (default `ndelucca`), `__PORT__` (puerto host en loopback, elegir uno
libre), `__CPORT__` (puerto del contenedor, del `EXPOSE`). Estas plantillas siguen el patrón de
`roles/forgejo` y `roles/kavita`; ante dudas, leé esos roles vivos.

> Ejemplo `hello-home` (sin punto): `__SLUG__`=`__REPO__`=`__SUB__`=`hello-home`, `__VAR__`=`hello_home`.
> Ejemplo `nd.market` (con punto): `__SLUG__`=`nd-market`, `__REPO__`=`nd.market`, `__VAR__`=`nd_market`,
> `__SUB__`=`market` (elegido por el usuario).

---

## `roles/__SLUG__/defaults/main.yml`

```yaml
---
# Variables por defecto del role __SLUG__ (app deployada por Forgejo Actions).

__VAR___user: ndelucca
__VAR___group: ndelucca
__VAR___uid: 1000  # Se obtiene dinámicamente vía getent en preflight

__VAR___base_dir: "{{ app_data_root }}/__SLUG__"
__VAR___data_dir: "{{ __VAR___base_dir }}/data"

__VAR___quadlet_dir: /etc/containers/systemd/users
__VAR___container_name: __SLUG__

# Imagen publicada por el workflow en el registry de Forgejo (usa el NOMBRE DE REPO, con puntos).
__VAR___image: "git.{{ nginx_domain }}/__OWNER__/__REPO__:latest"

__VAR___port: __PORT__            # HTTP en loopback, servido vía NGINX
__VAR___host: 127.0.0.1
__VAR___container_port: __CPORT__ # puerto que escucha la app dentro del contenedor

__VAR___service_name: __SLUG__
__VAR___service_enabled: true
__VAR___service_state: started

__VAR___manage_selinux: true
```

---

## `roles/__SLUG__/meta/main.yml`

```yaml
---
galaxy_info:
  author: Naza
  description: Deploy __SLUG__ (Forgejo-built container) on Fedora
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

## `roles/__SLUG__/tasks/main.yml`

```yaml
---
# Punto de entrada principal del role __SLUG__.

- name: Include preflight checks
  ansible.builtin.import_tasks: preflight.yml
  tags: ['__SLUG__', 'preflight']

- name: Install Podman and dependencies
  ansible.builtin.include_role:
    name: container_base
    tasks_from: install
  vars:
    container_base_user: "{{ __VAR___user }}"
  tags: ['__SLUG__', 'install']

- name: Deploy Quadlet configuration
  ansible.builtin.import_tasks: quadlet.yml
  tags: ['__SLUG__', 'quadlet']

- name: Configure SELinux (shared container_base step)
  ansible.builtin.include_role:
    name: container_base
    tasks_from: selinux
  vars:
    container_base_selinux_paths: "{{ [__VAR___data_dir] }}"
  tags: ['__SLUG__', 'selinux']
  when: __VAR___manage_selinux | bool

- name: Configure systemd service (shared container_base step)
  ansible.builtin.include_role:
    name: container_base
    tasks_from: service
  vars:
    container_base_user: "{{ __VAR___user }}"
    container_base_uid: "{{ __VAR___uid }}"
    container_base_service_name: "{{ __VAR___service_name }}"
    container_base_host: "{{ __VAR___host }}"
    container_base_port: "{{ __VAR___port }}"
    container_base_service_enabled: "{{ __VAR___service_enabled }}"
    container_base_service_state: "{{ __VAR___service_state }}"
  tags: ['__SLUG__', 'service']
```

---

## `roles/__SLUG__/tasks/preflight.yml`

```yaml
---
- name: Verify Fedora operating system
  ansible.builtin.assert:
    that:
      - ansible_facts['distribution'] == "Fedora"
    fail_msg: "This role only supports Fedora"

- name: Resolve __SLUG__ user UID for rootless Podman
  ansible.builtin.getent:
    database: passwd
    key: "{{ __VAR___user }}"
  check_mode: false

- name: Set __VAR___uid fact
  ansible.builtin.set_fact:
    __VAR___uid: "{{ ansible_facts['getent_passwd'][__VAR___user][1] }}"

- name: Ensure base and data directories exist
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: "{{ __VAR___user }}"
    group: "{{ __VAR___group }}"
    mode: '0750'
  become: true
  loop:
    - "{{ __VAR___base_dir }}"
    - "{{ __VAR___data_dir }}"
```

---

## `roles/__SLUG__/tasks/quadlet.yml`

```yaml
---
- name: Ensure systemd user directory exists
  ansible.builtin.file:
    path: "{{ __VAR___quadlet_dir }}/{{ __VAR___uid }}"
    state: directory
    owner: root
    group: root
    mode: '0755'
  become: true

- name: Deploy __SLUG__ Quadlet .container unit
  ansible.builtin.template:
    src: __SLUG__.container.j2
    dest: "{{ __VAR___quadlet_dir }}/{{ __VAR___uid }}/{{ __VAR___service_name }}.container"
    owner: root
    group: root
    mode: '0644'
  become: true
  notify:
    - Container daemon-reload-user
    - Container restart
```

---

## `roles/__SLUG__/templates/__SLUG__.container.j2`

```jinja
[Unit]
Description=__SLUG__ Container
After=network-online.target
Wants=network-online.target

[Container]
Image={{ __VAR___image }}
ContainerName={{ __VAR___container_name }}

UserNS=keep-id:uid={{ __VAR___uid }},gid={{ __VAR___uid }}

# HTTP en loopback; NGINX lo sirve en https://__SUB__.{{ nginx_domain }}.
PublishPort={{ __VAR___host }}:{{ __VAR___port }}:{{ __VAR___container_port }}

Volume={{ __VAR___data_dir }}:/data:Z

# El deploy hace `podman pull` de :latest y reinicia; Pull=newer deja la política explícita.
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
nginx___VAR___port: __PORT__
```
Y una entrada en `nginx_vhosts` (el `subdomain` es `__SUB__`, sin punto):
```yaml
  - {subdomain: "__SUB__", port: "{{ nginx___VAR___port }}"}
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
  - { port: "__PORT__/tcp", comment: "__SLUG__ direct — localhost only, behind NGINX" }
```

### `playbooks/site.yml`

Registrar el rol entre las apps:
```yaml
    - role: __SLUG__
      tags: ['__SLUG__']
```

---

## Pull de imágenes privadas (login al registry en el host)

Si el repo/paquete es **privado**, `podman pull` (que hacen la unit y el dispatcher
`home-deploy`) necesita que `ndelucca` esté logueado al registry en el host. Es un login
persistente reproducible (una vez, no por-app): una tarea que corra
`podman login --username ndelucca --password-stdin git.{{ nginx_domain }}` con el token
vaulteado (`vault_forgejo_api_token`) como `become_user: ndelucca` (crea
`~/.config/containers/auth.json`). Alternativa: hacer el paquete público en Forgejo.
