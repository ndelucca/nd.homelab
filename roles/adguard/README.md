# Role de Ansible: AdGuard Home

Este role instala y configura el servidor DNS AdGuard Home como binario nativo en
sistemas Fedora.

## Características

- Instalación como binario nativo (no en contenedor)
- Gestión completa de la configuración vía variables de Ansible
- Configuración del servidor DHCP con leases estáticos
- Rewrites de DNS (entradas de DNS local personalizadas)
- Opciones completas de filtrado de DNS
- Resolución automática de conflictos con systemd-resolved
- Configuración de SELinux y firewall

## Requisitos

- Fedora 38 o superior
- Ansible 2.14+
- Colecciones:
  - ansible.posix
  - community.general

## Variables del role

### Configuración básica

| Variable | Default | Descripción |
|----------|---------|-------------|
| `adguard_version` | `v0.107.77` | Versión pinned de AdGuard Home (mantener en sync con `adguard_schema_version`) |
| `adguard_install_dir` | `/usr/local/bin` | Directorio de instalación del binario |
| `adguard_working_dir` | `/opt/AdGuardHome` | Directorio de trabajo para datos y config |
| `adguard_user` | `ndelucca` | Usuario de sistema para AdGuard Home |
| `adguard_group` | `ndelucca` | Grupo de sistema para AdGuard Home |
| `adguard_configure_app` | `false` | Desplegar configuración propia (poner en true en el inventario para gestionar la config) |

### Configuración de red

| Variable | Default | Descripción |
|----------|---------|-------------|
| `adguard_bind_host` | `127.0.0.1` | IP donde escucha la interfaz de admin HTTP (detrás de NGINX) |
| `adguard_admin_port` | `8081` | Puerto de la interfaz web de admin |
| `adguard_dns_port` | `53` | Puerto del servidor DNS |
| `adguard_dns_over_tls_port` | `853` | Puerto de DNS-over-TLS |
| `adguard_dns_over_quic_port` | `853` | Puerto de DNS-over-QUIC |
| `adguard_dns_over_https_port` | `443` | Puerto de DNS-over-HTTPS |

### Configuración de DNS

| Variable | Default | Descripción |
|----------|---------|-------------|
| `adguard_upstream_dns` | AdGuard + Quad9 | Lista de servidores DNS upstream |
| `adguard_bootstrap_dns` | Varios providers | DNS de bootstrap para resolver los hostnames upstream |
| `adguard_cache_enabled` | `true` | Habilitar la cache de DNS |

> Nota: el modo upstream (`parallel`) y el tamaño de cache (4 MB) están fijos en el
> template de config, no expuestos como variables. Editá
> `templates/AdGuardHome.yaml.j2` para cambiarlos.

### Configuración de DHCP

| Variable | Default | Descripción |
|----------|---------|-------------|
| `adguard_dhcp_enabled` | `false` | Habilitar el servidor DHCP |
| `adguard_dhcp_interface_name` | `eth0` | Interfaz de red para DHCP |
| `adguard_dhcp_gateway_ip` | `192.168.1.1` | IP del gateway |
| `adguard_dhcp_range_start` | `192.168.1.100` | Inicio del rango DHCP |
| `adguard_dhcp_range_end` | `192.168.1.200` | Fin del rango DHCP |
| `adguard_dhcp_lease_duration` | `86400` | Duración del lease en segundos (24h) |
| `adguard_dhcp_static_leases` | `[]` | Lista de leases estáticos de DHCP |

### Rewrites de DNS

| Variable | Default | Descripción |
|----------|---------|-------------|
| `adguard_dns_rewrites` | `[]` | Entradas de DNS local personalizadas |

### Filtros

| Variable | Default | Descripción |
|----------|---------|-------------|
| `adguard_filters` | filtro AdGuard DNS | Lista de listas de filtros a habilitar |
| `adguard_filtering_enabled` | `true` | Habilitar el filtrado de DNS |
| `adguard_protection_enabled` | `true` | Habilitar las funciones de protección |

## Configuraciones de ejemplo

### Instalación básica (setup manual por web)

```yaml
# Deshabilitar la configuración automática para usar la UI web en el setup
adguard_configure_app: false
```

### Instalación configurada con DHCP

```yaml
# inventory/host_vars/myserver.yml
adguard_configure_app: true

# Usuario con contraseña hasheada
adguard_users:
  - name: admin
    password: $2a$10$... # Generar con: htpasswd -nbB "" "password" | cut -d ":" -f 2

# Servidor DHCP
adguard_dhcp_enabled: true
adguard_dhcp_interface_name: eth0
adguard_dhcp_gateway_ip: 192.168.1.1
adguard_dhcp_subnet_mask: 255.255.255.0
adguard_dhcp_range_start: 192.168.1.100
adguard_dhcp_range_end: 192.168.1.200

# Leases estáticos de DHCP
adguard_dhcp_static_leases:
  - ip: 192.168.1.10
    hostname: server
    mac: "aa:bb:cc:dd:ee:ff"
  - ip: 192.168.1.20
    hostname: workstation
    mac: "11:22:33:44:55:66"

# Rewrites de DNS (entradas de DNS local)
adguard_dns_rewrites:
  - domain: server.local
    answer: 192.168.1.10
    enabled: true
  - domain: nas.local
    answer: 192.168.1.50
    enabled: true
```

### Configuración de DNS personalizada

```yaml
# Usar servidores DNS upstream propios
adguard_upstream_dns:
  - https://dns.cloudflare.com/dns-query
  - https://dns.google/dns-query
  - 1.1.1.1
  - 8.8.8.8
```

## Uso

### Correr la instalación completa

```bash
ansible-playbook playbooks/site.yml -l ndelucca-server --tags adguard
```

### Correr solo la actualización de configuración

```bash
# Actualizar la configuración sin reinstalar
ansible-playbook playbooks/site.yml -l ndelucca-server --tags adguard,configure
```

### Saltear la configuración (setup manual)

```bash
# Instalar solo binario y service, configurar vía UI web
ansible-playbook playbooks/site.yml -l ndelucca-server --tags adguard -e "adguard_configure_app=false"
```

## Gestión de la contraseña

AdGuard Home requiere contraseñas hasheadas con bcrypt en el archivo de
configuración.

### Generar un hash de contraseña

```bash
# Usando htpasswd (del paquete apache2-utils)
htpasswd -nbB "" "yourpassword" | cut -d ":" -f 2

# Ejemplo de salida: $2a$10$A/PkUdTvjpRlqwtFvEYEX.L8ypXT3saCpsxE0/XzsUTV6SRZAwJ.a
```

Luego agregalo a tu inventario:

```yaml
adguard_users:
  - name: yourusername
    password: $2a$10$A/PkUdTvjpRlqwtFvEYEX.L8ypXT3saCpsxE0/XzsUTV6SRZAwJ.a
```

## Archivos de configuración

Cuando `adguard_configure_app: true`, el role gestiona:

- `/opt/AdGuardHome/AdGuardHome.yaml` - Archivo de configuración principal
- `/opt/AdGuardHome/data/leases.json` - Leases estáticos de DHCP

Los archivos existentes se respaldan con extensión `.backup` antes de
modificarlos.

## Tags

| Tag | Descripción |
|-----|-------------|
| `adguard` | Todas las tasks de AdGuard Home |
| `preflight` | Chequeos previos a la instalación |
| `install` | Instalación del binario |
| `configure` | Configuración de la aplicación |
| `service` | Setup del service de systemd |
| `firewall` | Reglas de firewall |
| `selinux` | Contextos de SELinux |

## Dependencias

Ninguna

## Licencia

MIT

## Autor

Nicolas Delucca
