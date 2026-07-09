# Plantillas del modo `enable`

Sustituir dos placeholders (¡son distintos!):
- **`__APP__`** = slug tal cual (con guiones OK): nombre del **dir del rol**, del **container**,
  del **service**, del **subdominio** y de la **imagen**. Ej: `hello-home`.
- **`__VAR__`** = slug con **guiones → guiones bajos**: prefijo de las **variables Ansible**
  (los nombres de variable NO admiten guiones). Ej: `hello_home`.

Y además: `__OWNER__` (default `ndelucca`), `__PORT__` (puerto host en loopback, elegir uno
libre), `__CPORT__` (puerto del contenedor, del `EXPOSE`). Estas plantillas siguen el patrón de
`roles/forgejo` y `roles/kavita`; ante dudas, leé esos roles vivos.

> Ejemplo para `hello-home`: `__APP__`=`hello-home`, `__VAR__`=`hello_home`.

---

## `roles/__APP__/defaults/main.yml`

```yaml
---
# Variables por defecto del role __APP__ (app deployada por Forgejo Actions).

__VAR___user: ndelucca
__VAR___group: ndelucca
__VAR___uid: 1000  # Se obtiene dinámicamente vía getent en preflight

__VAR___base_dir: "{{ app_data_root }}/__APP__"
__VAR___data_dir: "{{ __VAR___base_dir }}/data"

__VAR___quadlet_dir: /etc/containers/systemd/users
__VAR___container_name: __APP__

# Imagen publicada por el workflow en el registry de Forgejo.
__VAR___image: "git.{{ nginx_domain }}/__OWNER__/__APP__:latest"

__VAR___port: __PORT__            # HTTP en loopback, servido vía NGINX
__VAR___host: 127.0.0.1
__VAR___container_port: __CPORT__ # puerto que escucha la app dentro del contenedor

__VAR___service_name: __APP__
__VAR___service_enabled: true
__VAR___service_state: started

__VAR___manage_selinux: true
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
    container_base_user: "{{ __VAR___user }}"
  tags: ['__APP__', 'install']

- name: Deploy Quadlet configuration
  ansible.builtin.import_tasks: quadlet.yml
  tags: ['__APP__', 'quadlet']

- name: Configure SELinux (shared container_base step)
  ansible.builtin.include_role:
    name: container_base
    tasks_from: selinux
  vars:
    container_base_selinux_paths: "{{ [__VAR___data_dir] }}"
  tags: ['__APP__', 'selinux']
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

## `roles/__APP__/tasks/quadlet.yml`

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

- name: Deploy __APP__ Quadlet .container unit
  ansible.builtin.template:
    src: __APP__.container.j2
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

## `roles/__APP__/templates/__APP__.container.j2`

```jinja
[Unit]
Description=__APP__ Container
After=network-online.target
Wants=network-online.target

[Container]
Image={{ __VAR___image }}
ContainerName={{ __VAR___container_name }}

UserNS=keep-id:uid={{ __VAR___uid }},gid={{ __VAR___uid }}

# HTTP en loopback; NGINX lo sirve en https://__APP__.{{ nginx_domain }}.
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
Y una entrada en `nginx_vhosts`:
```yaml
  - {subdomain: "__APP__", port: "{{ nginx___VAR___port }}"}
```
Si la app usa websocket/SSE o subidas grandes, agregar los params correspondientes
(`websocket`, `client_max_body_size`, `server_snippet`, `location_snippet`) — ver los ejemplos
en el mismo archivo.

### `inventory/group_vars/homeservers/services.yml`

Agregar el rewrite DNS en `adguard_dns_rewrites` (junto a las apps del server):
```yaml
  - domain: "__APP__.{{ nginx_domain }}"
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

Si el repo/paquete es **privado**, `podman pull` (que hacen la unit y el dispatcher
`home-deploy`) necesita que `ndelucca` esté logueado al registry en el host. Es un login
persistente reproducible (una vez, no por-app): una tarea que corra
`podman login --username ndelucca --password-stdin git.{{ nginx_domain }}` con el token
vaulteado (`vault_forgejo_api_token`) como `become_user: ndelucca` (crea
`~/.config/containers/auth.json`). Alternativa: hacer el paquete público en Forgejo.
