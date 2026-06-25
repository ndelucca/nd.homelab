# Gestión de la configuración de AdGuard Home

Este documento describe el sistema de gestión de configuración que se agregó al
role de Ansible de AdGuard Home.

## Qué se hizo

### 1. Se obtuvo la configuración actual
La configuración actual de AdGuard Home se obtuvo de `ndelucca-server`,
incluyendo:
- El archivo de configuración principal (`AdGuardHome.yaml`)
- Los leases estáticos de DHCP (`data/leases.json`)

### 2. Se crearon templates Jinja2

**`roles/adguard_home/templates/AdGuardHome.yaml.j2`**
- Template completo de configuración de AdGuard Home
- Todos los ajustes parametrizados vía variables de Ansible
- Soporta DNS, DHCP, filtrado, rewrites y más

**`roles/adguard_home/templates/leases.json.j2`**
- Template de los leases estáticos de DHCP
- Gestiona las asignaciones de IP estática de tus dispositivos

### 3. Se actualizaron las variables del role

**`roles/adguard_home/defaults/main.yml`**
Se agregaron 100+ variables de configuración, incluyendo:
- Ajustes de autenticación de usuario
- Servidores y modos de DNS upstream
- Configuración del servidor DHCP
- Rewrites de DNS (entradas de DNS local)
- Listas de filtros
- Logging de queries y estadísticas
- Ajustes de TLS/encriptación
- Y muchos más...

### 4. Se creó la task de configuración

**`roles/adguard_home/tasks/configure.yml`**
- Despliega los templates de configuración al servidor
- Crea backups antes de modificar archivos
- Reinicia AdGuard Home cuando hace falta
- Se puede correr de forma independiente con `--tags configure`

### 5. Dónde vive la configuración

La configuración no secreta del servidor vive en
**`inventory/group_vars/homeservers/services.yml`** (los secretos, como el hash de
la contraseña del usuario admin, viven en `vault.yml`). Incluye:
- Usuario: ndelucca (con el hash de contraseña existente, en `vault.yml`)
- DHCP habilitado en enp6s0
- Rango de IP: 192.168.10.100-200
- Gateway: 192.168.10.1
- Leases estáticos de DHCP de tus dispositivos
- Rewrites de DNS para los nombres de dominio locales

> El archivo `inventory/host_vars/ndelucca-server.yml` quedó vacío a propósito:
> `ndelucca-server` es el único miembro del grupo `homeservers`, así que toda su
> config vive ahora a nivel de grupo en `group_vars/homeservers/`.

## Tu configuración actual

### Leases estáticos de DHCP
| IP | Hostname | Dirección MAC |
|----|----------|---------------|
| 192.168.10.10 | ndelucca-server | 4c:cc:6a:d3:fc:a1 |
| 192.168.10.11 | ndelucca-raspberry-printer | b8:27:eb:f1:af:50 |
| 192.168.10.12 | ndelucca-raspberry-printer-wireless | b8:27:eb:a4:fa:05 |
| 192.168.10.13 | ndelucca-acer | fa:da:6d:73:ff:15 |
| 192.168.10.20 | ndelucca-tv-tcl | 48:9e:9d:8f:65:20 |
| 192.168.10.21 | ndelucca-pixel-8-5ghz | 1e:9c:15:ee:48:26 |
| 192.168.10.22 | ndelucca-pixel-8-2.4ghz | ca:61:9f:ce:53:ce |

### Rewrites de DNS
| Dominio | IP |
|---------|----|
| ndelucca.dedyn.io | 192.168.10.10 |
| ndelucca-acer.com | 192.168.10.13 |
| printer.ndelucca.dedyn.io | 192.168.10.12 |

> La impresora se accede por WiFi (.12), la ruta activa — `ansible_host`, el
> rewrite `printer.` y su cert TLS apuntan todos a .12. El lease ethernet .11 está
> inactivo (cable caído). La lista de rewrites completa y autoritativa vive en
> `inventory/group_vars/homeservers/services.yml`; esta tabla es ilustrativa.

### Ajustes de DNS
- **DNS upstream**: AdGuard sin filtrar, Quad9
- **Modo**: Load balance
- **Filtros**: filtro AdGuard DNS (habilitado)
- **Cache**: habilitado, 4MB

## Cómo usarlo

### Aplicar la configuración completa
```bash
# Desplegar todo (binario, config, service)
ansible-playbook playbooks/site.yml -l ndelucca-server --tags adguard
```

### Actualizar solo la configuración
```bash
# Actualizar solo la configuración sin reinstalar
ansible-playbook playbooks/site.yml -l ndelucca-server --tags adguard
```

### Saltear la configuración (setup manual vía UI web)
```bash
# Instalar binario y service, pero no desplegar config
ansible-playbook playbooks/site.yml -l ndelucca-server --tags adguard -e "adguard_configure_app=false"
```

## Modificar la configuración

### Opción 1: Editar las variables del grupo
Editá `inventory/group_vars/homeservers/services.yml` para cambiar los ajustes:

```yaml
# Agregar un nuevo lease estático
adguard_dhcp_static_leases:
  - ip: 192.168.10.30
    hostname: new-device
    mac: "aa:bb:cc:dd:ee:ff"

# Agregar un nuevo rewrite de DNS
adguard_dns_rewrites:
  - domain: newdevice.local
    answer: 192.168.10.30
    enabled: true
```

### Opción 2: Editar las variables por defecto
Editá `roles/adguard_home/defaults/main.yml` para cambiar los defaults de todos
los servidores.

### Opción 3: Usar extra vars
Sobrescribir variables en tiempo de ejecución:

```bash
ansible-playbook playbooks/site.yml -l ndelucca-server --tags adguard -e "adguard_dhcp_range_end=192.168.10.250"
```

## Gestión de la contraseña

AdGuard Home usa contraseñas hasheadas con bcrypt. Para cambiar la contraseña:

1. **Generar un hash**:
   ```bash
   htpasswd -nbB "" "your-new-password" | cut -d ":" -f 2
   ```

2. **Actualizar el hash** en `vault.yml` (`adguard_users`), editando con
   `ansible-vault edit inventory/group_vars/homeservers/vault.yml`:
   ```yaml
   adguard_users:
     - name: ndelucca
       password: $2a$10$NEW_HASH_HERE
   ```

3. **Aplicar el cambio**:
   ```bash
   ansible-playbook playbooks/site.yml -l ndelucca-server --tags adguard
   ```

## Archivos de configuración gestionados

Cuando `adguard_configure_app: true` (default para ndelucca-server):

| Archivo | Propósito | Backup |
|---------|-----------|--------|
| `/opt/AdGuardHome/AdGuardHome.yaml` | Configuración principal | Sí (.backup) |
| `/opt/AdGuardHome/data/leases.json` | Leases estáticos de DHCP | Sí (.backup) |

## Notas importantes

1. **Backups**: los archivos originales se respaldan automáticamente antes de modificarlos
2. **Reinicio del service**: AdGuard Home se reinicia cuando cambia la configuración
3. **Idempotente**: seguro de correr varias veces — solo cambia cuando hace falta
4. **Templated**: todos los ajustes se gestionan ahora vía variables de Ansible
5. **Control de versiones**: la configuración queda registrada en Git

## Tags disponibles

| Tag | Propósito |
|-----|-----------|
| `configure` | Desplegar solo la configuración |
| `install` | Instalar solo el binario |
| `service` | Configurar solo el service |
| `firewall` | Configurar solo el firewall |
| `selinux` | Configurar solo SELinux |

## Ejemplos

### Agregar un dispositivo nuevo
```yaml
# En inventory/group_vars/homeservers/services.yml
adguard_dhcp_static_leases:
  # ... leases existentes ...
  - ip: 192.168.10.25
    hostname: laptop
    mac: "12:34:56:78:9a:bc"

adguard_dns_rewrites:
  # ... rewrites existentes ...
  - domain: laptop.local
    answer: 192.168.10.25
    enabled: true
```

Luego aplicar:
```bash
ansible-playbook playbooks/site.yml -l ndelucca-server --tags adguard
```

### Cambiar los servidores de DNS upstream
```yaml
# En inventory/group_vars/homeservers/services.yml
adguard_upstream_dns:
  - https://dns.cloudflare.com/dns-query
  - https://dns.google/dns-query
```

### Habilitar más filtros
```yaml
# En inventory/group_vars/homeservers/services.yml
adguard_filters:
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt
    name: AdGuard DNS filter
    id: 1
  - enabled: true  # Cambiado de false a true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt
    name: AdAway Default Blocklist
    id: 2
```

## Troubleshooting

### La configuración no se aplicó
```bash
# Chequear si la task configure corrió
ansible-playbook playbooks/site.yml -l ndelucca-server --tags adguard -vv

# Verificar el archivo de configuración
ansible ndelucca-server -m shell -a "cat /opt/AdGuardHome/AdGuardHome.yaml | head -20" --become
```

### El service no arranca tras un cambio de config
```bash
# Chequear el estado del service
ansible ndelucca-server -m shell -a "systemctl status AdGuardHome" --become

# Chequear los logs del service
ansible ndelucca-server -m shell -a "journalctl -u AdGuardHome -n 50" --become

# Validar la sintaxis YAML
ansible ndelucca-server -m shell -a "python3 -c 'import yaml; yaml.safe_load(open(\"/opt/AdGuardHome/AdGuardHome.yaml\"))'" --become
```

### Restaurar la configuración anterior
```bash
# Encontrar los archivos de backup
ansible ndelucca-server -m shell -a "ls -la /opt/AdGuardHome/*.backup*" --become

# Restaurar desde el backup
ansible ndelucca-server -m shell -a "cp /opt/AdGuardHome/AdGuardHome.yaml.backup /opt/AdGuardHome/AdGuardHome.yaml" --become
ansible ndelucca-server -m shell -a "systemctl restart AdGuardHome" --become
```

## Próximos pasos

1. **Revisar la configuración**: chequeá `inventory/group_vars/homeservers/services.yml` para verificar los ajustes
2. **Probar una actualización**: probá actualizar la configuración con `--tags configure`
3. **Agregar más dispositivos**: agregá leases estáticos y rewrites de DNS según haga falta
4. **Personalizar los filtros**: habilitá/deshabilitá listas de filtros según tus necesidades
5. **Control de versiones**: commiteá los cambios a Git para registrar el historial de configuración

## Documentación

- README del role: `roles/adguard_home/README.md`
- Referencia completa de variables: `roles/adguard_home/defaults/main.yml`
- Templates: `roles/adguard_home/templates/`
