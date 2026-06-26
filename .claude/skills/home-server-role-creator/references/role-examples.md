# Complete Role Examples

This document provides complete examples from actual roles in the home-server infrastructure, showing real implementations of the three installation patterns.

## Example 1: Binary Service (FileBrowser)

FileBrowser is a simple web-based file manager installed as a standalone binary.

### Installation Method: Binary Download/Extract

**Characteristics:**
- Downloaded binary from GitHub releases
- Systemd service for process management
- Behind NGINX reverse proxy
- Simple configuration file
- File management service with upload support

### File Structure

```
roles/filebrowser/
├── defaults/
│   └── main.yml
├── handlers/
│   └── main.yml
├── meta/
│   └── main.yml
├── tasks/
│   ├── main.yml
│   ├── preflight.yml
│   ├── install.yml
│   ├── configure.yml
│   ├── service.yml
│   └── selinux.yml
└── templates/
    ├── filebrowser.service.j2
    └── config.json.j2
```

### Key Implementation Files

**defaults/main.yml:**
```yaml
---
# Default variables for FileBrowser role

# Installation configuration
filebrowser_version: latest
filebrowser_arch: amd64
filebrowser_download_url: "https://github.com/filebrowser/filebrowser/releases/download/{{ filebrowser_version }}/filebrowser-{{ filebrowser_arch }}.tar.gz"
filebrowser_install_dir: /usr/local/bin

# Service user configuration
filebrowser_user: ndelucca
filebrowser_group: ndelucca

# Directory configuration
filebrowser_base_dir: /srv/filebrowser
filebrowser_root_dir: "{{ filebrowser_base_dir }}/files"
filebrowser_database: "{{ filebrowser_base_dir }}/filebrowser.db"
filebrowser_config_file: "{{ filebrowser_base_dir }}/config.json"

# Service configuration
filebrowser_service_name: filebrowser
filebrowser_service_enabled: true
filebrowser_service_state: started

# Network configuration
filebrowser_bind_address: 127.0.0.1
filebrowser_port: 8080

# Firewall settings
filebrowser_firewall_enabled: false  # Behind NGINX
filebrowser_firewall_zone: FedoraServer

# SELinux configuration
filebrowser_manage_selinux: true
filebrowser_use_config_file: true
```

**tasks/install.yml:**
```yaml
---
# Install FileBrowser binary

- name: Check if FileBrowser binary exists
  ansible.builtin.stat:
    path: "{{ filebrowser_install_dir }}/filebrowser"
  register: filebrowser_binary

- name: Create temporary download directory
  ansible.builtin.tempfile:
    state: directory
    suffix: _filebrowser_download
  register: download_dir
  when: not filebrowser_binary.stat.exists

- name: Download FileBrowser archive
  ansible.builtin.get_url:
    url: "{{ filebrowser_download_url }}"
    dest: "{{ download_dir.path }}/filebrowser.tar.gz"
    mode: '0644'
  when: not filebrowser_binary.stat.exists

- name: Extract FileBrowser archive
  ansible.builtin.unarchive:
    src: "{{ download_dir.path }}/filebrowser.tar.gz"
    dest: "{{ download_dir.path }}"
    remote_src: true
  when: not filebrowser_binary.stat.exists

- name: Copy binary to installation directory
  ansible.builtin.copy:
    src: "{{ download_dir.path }}/filebrowser"
    dest: "{{ filebrowser_install_dir }}/filebrowser"
    remote_src: true
    owner: root
    group: root
    mode: '0755'
  become: true
  when: not filebrowser_binary.stat.exists
  notify: restart filebrowser

- name: Clean up temporary directory
  ansible.builtin.file:
    path: "{{ download_dir.path }}"
    state: absent
  when: download_dir is defined

- name: Verify FileBrowser installation
  ansible.builtin.command: "{{ filebrowser_install_dir }}/filebrowser version"
  register: filebrowser_version_output
  changed_when: false

- name: Display FileBrowser version
  ansible.builtin.debug:
    msg: "Installed {{ filebrowser_version_output.stdout }}"
```

**templates/filebrowser.service.j2:**
```jinja2
[Unit]
Description=FileBrowser - Web File Manager
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User={{ filebrowser_user }}
Group={{ filebrowser_group }}
ExecStart={{ filebrowser_install_dir }}/filebrowser \
    --config {{ filebrowser_config_file }} \
    --database {{ filebrowser_database }} \
    --root {{ filebrowser_root_dir }} \
    --address {{ filebrowser_bind_address }} \
    --port {{ filebrowser_port }}

Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths={{ filebrowser_base_dir }}

[Install]
WantedBy=multi-user.target
```

**Firewall configuration (roles/firewall/tasks/filebrowser.yml):**
```yaml
---
# FileBrowser is behind NGINX reverse proxy
# Access via files.ndelucca-server.com on ports 80/443 (handled by NGINX)

- name: Remove old direct FileBrowser port from firewall
  ansible.posix.firewalld:
    port: "{{ filebrowser_port }}/tcp"
    zone: "{{ filebrowser_firewall_zone }}"
    permanent: true
    immediate: true
    state: disabled
  become: true
  notify: reload firewalld
  ignore_errors: true
```

**NGINX configuration (roles/nginx/templates/conf.d/filebrowser.conf.j2):**
```nginx
# ========================================
# FILEBROWSER SUBDOMAIN
# ========================================

# HTTP
server {
    listen 80;
    server_name files.{{ nginx_domain }};

    # Disable buffering for large file uploads
    client_max_body_size 0;
    proxy_request_buffering off;

    location / {
        proxy_pass http://127.0.0.1:{{ nginx_filebrowser_port }};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Support for large file uploads
        proxy_buffering off;
        proxy_http_version 1.1;
    }
}

# HTTPS
server {
    listen 443 ssl;
    http2 on;
    server_name files.{{ nginx_domain }};

    ssl_certificate {{ nginx_ssl_certificate }};
    ssl_certificate_key {{ nginx_ssl_certificate_key }};

    client_max_body_size 0;
    proxy_request_buffering off;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    location / {
        proxy_pass http://127.0.0.1:{{ nginx_filebrowser_port }};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_buffering off;
        proxy_http_version 1.1;
    }
}
```

---

## Example 2: Package Service (Jellyfin)

Jellyfin is a media server installed from RPMFusion repository.

### Installation Method: DNF Package

**Characteristics:**
- Installed from RPMFusion repository
- Systemd service managed by package
- WebSocket support for real-time features
- Media streaming with transcoding
- Plugin management

### File Structure

```
roles/jellyfin/
├── defaults/
│   └── main.yml
├── handlers/
│   └── main.yml
├── meta/
│   └── main.yml
└── tasks/
    ├── main.yml
    ├── preflight.yml
    ├── repository.yml
    ├── install.yml
    ├── plugins.yml
    ├── service.yml
    └── selinux.yml
```

### Key Implementation Files

**defaults/main.yml:**
```yaml
---
# Default variables for Jellyfin role

# Service configuration
jellyfin_service_name: jellyfin
jellyfin_service_enabled: true
jellyfin_service_state: started

# Network configuration
jellyfin_port: 8096

# Firewall settings
jellyfin_firewall_enabled: false  # Behind NGINX
jellyfin_firewall_zone: FedoraServer

# SELinux configuration
jellyfin_manage_selinux: true

# Plugin configuration
jellyfin_install_plugins: true
jellyfin_plugins:
  - name: "Kodi Sync Queue"
    repo_url: "https://repo.jellyfin.org/releases/plugin/kodi-sync-queue/kodi-sync-queue_9.0.0.0.zip"
```

**tasks/repository.yml:**
```yaml
---
# Configure RPMFusion repository for Jellyfin

- name: Check if RPMFusion Free repository is enabled
  ansible.builtin.command: dnf repolist --enabled
  register: repo_list
  changed_when: false

- name: Install RPMFusion Free repository
  ansible.builtin.dnf:
    name: "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-{{ ansible_distribution_version }}.noarch.rpm"
    state: present
    disable_gpg_check: true
  become: true
  when: "'rpmfusion-free' not in repo_list.stdout"

- name: Update DNF cache after adding repository
  ansible.builtin.dnf:
    update_cache: true
  become: true
  when: "'rpmfusion-free' not in repo_list.stdout"
```

**tasks/install.yml:**
```yaml
---
# Install Jellyfin from RPMFusion

- name: Install Jellyfin packages
  ansible.builtin.dnf:
    name:
      - jellyfin
      - jellyfin-server
      - jellyfin-web
    state: present
  become: true
  notify: restart jellyfin

- name: Verify Jellyfin installation
  ansible.builtin.command: jellyfin --version
  register: jellyfin_version
  changed_when: false
  failed_when: false

- name: Display Jellyfin version
  ansible.builtin.debug:
    msg: "Installed {{ jellyfin_version.stdout }}"
  when: jellyfin_version.rc == 0
```

**tasks/plugins.yml:**
```yaml
---
# Install Jellyfin plugins

- name: Ensure Jellyfin plugins directory exists
  ansible.builtin.file:
    path: /var/lib/jellyfin/plugins
    state: directory
    owner: jellyfin
    group: jellyfin
    mode: '0755'
  become: true
  when: jellyfin_install_plugins

- name: Download and install Jellyfin plugins
  ansible.builtin.unarchive:
    src: "{{ item.repo_url }}"
    dest: /var/lib/jellyfin/plugins
    remote_src: true
    owner: jellyfin
    group: jellyfin
  become: true
  loop: "{{ jellyfin_plugins }}"
  when: jellyfin_install_plugins
  notify: restart jellyfin
```

**NGINX configuration (roles/nginx/templates/conf.d/jellyfin.conf.j2):**
```nginx
# ========================================
# JELLYFIN (MEDIA SERVER) SUBDOMAIN
# ========================================

# HTTP
server {
    listen 80;
    server_name jellyfin.{{ nginx_domain }};

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";

    location / {
        proxy_pass http://127.0.0.1:{{ nginx_jellyfin_port }};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;

        # WebSocket support for real-time features
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Buffering
        proxy_buffering off;
    }
}

# HTTPS
server {
    listen 443 ssl;
    http2 on;
    server_name jellyfin.{{ nginx_domain }};

    ssl_certificate {{ nginx_ssl_certificate }};
    ssl_certificate_key {{ nginx_ssl_certificate_key }};

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    location / {
        proxy_pass http://127.0.0.1:{{ nginx_jellyfin_port }};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_buffering off;
    }
}
```

---

## Example 3: Container Service (Immich)

Immich is a photo management platform deployed as a multi-container Podman pod.

### Installation Method: Podman Quadlet

**Characteristics:**
- Multi-container pod (4 containers: server, ML, Redis, PostgreSQL)
- Rootless Podman deployment
- Podman Quadlet for systemd integration
- Custom storage location on external disk
- Large file upload support
- CLI tool installation (Node.js/npm)

### File Structure

```
roles/immich/
├── defaults/
│   └── main.yml
├── handlers/
│   └── main.yml
├── meta/
│   └── main.yml
├── tasks/
│   ├── main.yml
│   ├── preflight.yml
│   ├── install.yml
│   ├── configure.yml
│   ├── quadlet.yml
│   ├── service.yml
│   └── selinux.yml
└── templates/
    ├── immich.env.j2
    ├── immich-pod.yaml.j2
    └── immich.kube.j2
```

### Key Implementation Files

**defaults/main.yml:**
```yaml
---
# Default variables for Immich role

# Service user configuration
immich_user: ndelucca
immich_group: ndelucca
immich_uid: 1000  # Obtained dynamically via getent in preflight

# Directory configuration
immich_base_dir: /srv/immich
immich_upload_location: "{{ immich_base_dir }}/library"
immich_db_data_location: "{{ immich_base_dir }}/postgres"
immich_config_dir: "{{ immich_base_dir }}/config"
immich_model_cache: "{{ immich_base_dir }}/model-cache"

# Podman configuration
immich_podman_user: "{{ immich_user }}"
immich_pod_name: immich
immich_quadlet_dir: /etc/containers/systemd/users

# Network configuration
immich_port: 2283
immich_host: 127.0.0.1

# Application configuration
immich_version: release  # Can pin to specific versions like v1.117.0
immich_timezone: America/Los_Angeles

# Database configuration
immich_db_username: immich
immich_db_database: immich
immich_db_password: "{{ lookup('password', '/dev/null length=32 chars=ascii_letters,digits') }}"

# Service configuration
immich_service_name: immich-pod
immich_service_enabled: true
immich_service_state: started

# Firewall settings
immich_firewall_zone: FedoraServer
immich_firewall_enabled: false  # False because NGINX handles external access

# SELinux configuration
immich_manage_selinux: true

# Podman images
immich_server_image: "ghcr.io/immich-app/immich-server:{{ immich_version }}"
immich_ml_image: "ghcr.io/immich-app/immich-machine-learning:{{ immich_version }}"
immich_redis_image: docker.io/valkey/valkey:9-alpine
immich_postgres_image: ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0
```

**tasks/install.yml:**
```yaml
---
# Install Podman and dependencies

- name: Install Podman packages
  ansible.builtin.dnf:
    name:
      - podman
      - slirp4netns     # For rootless networking
      - fuse-overlayfs  # For rootless storage
      - crun            # Modern OCI runtime
    state: present
  become: true

- name: Verify Podman installation
  ansible.builtin.command: podman --version
  register: podman_version
  changed_when: false

- name: Display Podman version
  ansible.builtin.debug:
    msg: "Installed {{ podman_version.stdout }}"

- name: Check Podman version is >= 4.4 (required for Quadlet)
  ansible.builtin.assert:
    that:
      - podman_version.stdout is version('podman version 4.4', '>=', version_type='loose')
    fail_msg: "Podman 4.4+ is required for Quadlet support"
    success_msg: "Podman version is compatible with Quadlet"
  when: podman_version.stdout is defined

- name: Enable lingering for user (allows user services without login)
  ansible.builtin.command: loginctl enable-linger {{ immich_user }}
  become: true
  changed_when: false

- name: Install Node.js and npm for Immich CLI
  ansible.builtin.dnf:
    name:
      - nodejs
      - npm
    state: present
  become: true

- name: Install Immich CLI globally
  ansible.builtin.command: npm install -g @immich/cli
  become: true
  register: immich_cli_install
  changed_when: "'added' in immich_cli_install.stdout"

- name: Verify Immich CLI installation
  ansible.builtin.command: immich --version
  register: immich_cli_version
  changed_when: false
  failed_when: false

- name: Display Immich CLI version
  ansible.builtin.debug:
    msg: "Installed Immich CLI {{ immich_cli_version.stdout }}"
  when: immich_cli_version.rc == 0
```

**tasks/quadlet.yml:**
```yaml
---
# Deploy Podman Quadlet configuration for Immich

- name: Get user UID dynamically
  ansible.builtin.command: "getent passwd {{ immich_user }}"
  register: getent_output
  changed_when: false

- name: Extract UID from getent
  ansible.builtin.set_fact:
    immich_uid: "{{ getent_output.stdout.split(':')[2] }}"

- name: Ensure systemd user directory exists
  ansible.builtin.file:
    path: "{{ immich_quadlet_dir }}/{{ immich_uid }}"
    state: directory
    owner: root
    group: root
    mode: '0755'
  become: true

- name: Deploy Immich Quadlet .kube unit
  ansible.builtin.template:
    src: immich.kube.j2
    dest: "{{ immich_quadlet_dir }}/{{ immich_uid }}/{{ immich_service_name }}.kube"
    owner: root
    group: root
    mode: '0644'
  become: true
  notify:
    - daemon-reload-user
    - restart immich-pod
```

**templates/immich-pod.yaml.j2:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: {{ immich_pod_name }}
spec:
  restartPolicy: Always

  containers:
  # Main Immich server
  - name: immich-server
    image: {{ immich_server_image }}
    ports:
    - containerPort: 2283
      hostPort: {{ immich_port }}
      hostIP: {{ immich_host }}
    env:
    - name: UPLOAD_LOCATION
      value: "/data"
    - name: DB_HOSTNAME
      value: "127.0.0.1"
    - name: DB_USERNAME
      value: "{{ immich_db_username }}"
    - name: DB_PASSWORD
      value: "{{ immich_db_password }}"
    - name: DB_DATABASE_NAME
      value: "{{ immich_db_database }}"
    - name: REDIS_HOSTNAME
      value: "127.0.0.1"
    - name: TZ
      value: "{{ immich_timezone }}"
    volumeMounts:
    - name: upload-storage
      mountPath: /data
    - name: model-cache
      mountPath: /cache

  # Machine Learning service
  - name: immich-machine-learning
    image: {{ immich_ml_image }}
    env:
    - name: TZ
      value: "{{ immich_timezone }}"
    volumeMounts:
    - name: model-cache
      mountPath: /cache

  # Redis cache
  - name: redis
    image: {{ immich_redis_image }}
    command:
    - valkey-server
    - --save
    - "60"
    - "1"

  # PostgreSQL database
  - name: database
    image: {{ immich_postgres_image }}
    env:
    - name: POSTGRES_USER
      value: "{{ immich_db_username }}"
    - name: POSTGRES_PASSWORD
      value: "{{ immich_db_password }}"
    - name: POSTGRES_DB
      value: "{{ immich_db_database }}"
    - name: TZ
      value: "{{ immich_timezone }}"
    volumeMounts:
    - name: db-data
      mountPath: /var/lib/postgresql/data

  volumes:
  - name: upload-storage
    hostPath:
      path: {{ immich_upload_location }}
      type: Directory
  - name: db-data
    hostPath:
      path: {{ immich_db_data_location }}
      type: Directory
  - name: model-cache
    hostPath:
      path: {{ immich_model_cache }}
      type: Directory
```

**templates/immich.kube.j2:**
```ini
[Unit]
Description=Immich Photo Management Pod
After=network-online.target
Wants=network-online.target

[Kube]
Yaml={{ immich_config_dir }}/immich-pod.yaml
AutoUpdate=registry

[Service]
Restart=on-failure
RestartSec=30
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target default.target
```

**handlers/main.yml:**
```yaml
---
# Handlers for Immich rootless Podman role

- name: daemon-reload-user
  ansible.builtin.systemd:
    daemon_reload: true
    scope: user
  become: true
  become_user: "{{ immich_user }}"
  environment:
    XDG_RUNTIME_DIR: "/run/user/{{ immich_uid }}"

- name: restart immich-pod
  ansible.builtin.systemd:
    name: "{{ immich_service_name }}"
    state: restarted
    scope: user
  become: true
  become_user: "{{ immich_user }}"
  environment:
    XDG_RUNTIME_DIR: "/run/user/{{ immich_uid }}"

- name: apply selinux context
  ansible.builtin.command: "restorecon -Rv {{ item }}"
  become: true
  loop:
    - "{{ immich_upload_location }}"
    - "{{ immich_db_data_location }}"
    - "{{ immich_config_dir }}"
  changed_when: false
```

**tasks/service.yml:**
```yaml
---
# Configure systemd user service for Immich pod

- name: Flush handlers to reload systemd
  ansible.builtin.meta: flush_handlers

- name: Enable and start Immich pod service
  ansible.builtin.systemd:
    name: "{{ immich_service_name }}"
    enabled: "{{ immich_service_enabled }}"
    state: "{{ immich_service_state }}"
    scope: user
    daemon_reload: true
  become: true
  become_user: "{{ immich_user }}"
  environment:
    XDG_RUNTIME_DIR: "/run/user/{{ immich_uid }}"

- name: Wait for Immich to be available
  ansible.builtin.wait_for:
    host: "{{ immich_host }}"
    port: "{{ immich_port }}"
    delay: 5
    timeout: 60
  when: immich_service_state == 'started'
```

**NGINX configuration (roles/nginx/templates/conf.d/immich.conf.j2):**
```nginx
# ========================================
# IMMICH (GALLERY) SUBDOMAIN
# ========================================

# HTTP
server {
    listen 80;
    server_name gallery.{{ nginx_domain }};

    # Allow large photo/video uploads (adjust as needed)
    client_max_body_size 50G;
    client_body_timeout 600s;
    proxy_read_timeout 600s;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";

    location / {
        proxy_pass http://127.0.0.1:{{ nginx_immich_port }};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;

        # WebSocket support for real-time features
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Buffering settings for large uploads
        proxy_buffering off;
        proxy_request_buffering off;
    }
}

# HTTPS
server {
    listen 443 ssl;
    http2 on;
    server_name gallery.{{ nginx_domain }};

    ssl_certificate {{ nginx_ssl_certificate }};
    ssl_certificate_key {{ nginx_ssl_certificate_key }};

    client_max_body_size 50G;
    client_body_timeout 600s;
    proxy_read_timeout 600s;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    location / {
        proxy_pass http://127.0.0.1:{{ nginx_immich_port }};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Buffering settings
        proxy_buffering off;
        proxy_request_buffering off;
    }
}
```

**Host variables override (inventory/host_vars/ndelucca-server.yml):**
```yaml
# Immich configuration - custom storage location
immich_upload_location: /srv/disks/D-Draco/media/Gallery
```

---

## Comparison Summary

| Aspect | FileBrowser (Binary) | Jellyfin (Package) | Immich (Container) |
|--------|---------------------|--------------------|--------------------|
| **Installation** | Download + Extract | DNF Package | Podman Quadlet |
| **Binary Location** | /usr/local/bin | System-managed | Container images |
| **Service Type** | Systemd system | Systemd system | Systemd user (rootless) |
| **Configuration** | JSON file | System defaults | Environment + YAML |
| **Dependencies** | None | RPMFusion repo | Podman, Node.js |
| **Complexity** | Low | Medium | High |
| **Update Method** | Manual re-download | DNF upgrade | Container image pull |
| **Isolation** | Process | Process | Container pod |
| **Storage** | Direct filesystem | Direct filesystem | Volume mounts |
| **Multi-component** | No | No (monolithic) | Yes (4 containers) |
| **Custom Storage** | Config variable | Standard paths | Volume mount override |

## Key Takeaways

1. **Binary services** are simple and portable but require manual updates
2. **Package services** get automatic updates but depend on repository availability
3. **Container services** provide isolation and reproducibility but add complexity
4. **All services** follow the same integration patterns (NGINX, firewall, SELinux, DNS)
5. **Rootless containers** require special systemd handling with `scope: user` and `XDG_RUNTIME_DIR`
6. **Custom storage** locations require SELinux context configuration
