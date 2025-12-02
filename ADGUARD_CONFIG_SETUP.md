# AdGuard Home Configuration Management Setup

This document describes the configuration management system that has been added to the AdGuard Home Ansible role.

## What Was Done

### 1. Fetched Current Configuration
Your current AdGuard Home configuration was fetched from `ndelucca-server` including:
- Main configuration file (`AdGuardHome.yaml`)
- DHCP static leases (`data/leases.json`)

### 2. Created Jinja2 Templates

**`roles/adguard_home/templates/AdGuardHome.yaml.j2`**
- Complete AdGuard Home configuration template
- All settings parameterized via Ansible variables
- Supports DNS, DHCP, filtering, rewrites, and more

**`roles/adguard_home/templates/leases.json.j2`**
- DHCP static leases template
- Manages static IP assignments for your devices

### 3. Updated Role Variables

**`roles/adguard_home/defaults/main.yml`**
Added 100+ configuration variables including:
- User authentication settings
- DNS upstream servers and modes
- DHCP server configuration
- DNS rewrites (local DNS entries)
- Filter lists
- Query logging and statistics
- TLS/encryption settings
- And many more...

### 4. Created Configuration Task

**`roles/adguard_home/tasks/configure.yml`**
- Deploys configuration templates to the server
- Creates backups before modifying files
- Restarts AdGuard Home when needed
- Can be run independently with `--tags configure`

### 5. Created Host-Specific Configuration

**`inventory/host_vars/ndelucca-server.yml`**
Contains your current configuration:
- User: ndelucca (with existing password hash)
- DHCP enabled on enp6s0
- IP range: 192.168.10.100-200
- Gateway: 192.168.10.1
- 7 static DHCP leases for your devices
- 3 DNS rewrites for local domain names

## Your Current Configuration

### DHCP Static Leases
| IP | Hostname | MAC Address |
|----|----------|-------------|
| 192.168.10.10 | ndelucca-server | 4c:cc:6a:d3:fc:a1 |
| 192.168.10.11 | ndelucca-raspberry-printer | b8:27:eb:f1:af:50 |
| 192.168.10.12 | ndelucca-raspberry-printer-wireless | b8:27:eb:a4:fa:05 |
| 192.168.10.13 | ndelucca-acer | fa:da:6d:73:ff:15 |
| 192.168.10.20 | ndelucca-tv-tcl | 48:9e:9d:8f:65:20 |
| 192.168.10.21 | ndelucca-pixel-8-5ghz | 1e:9c:15:ee:48:26 |
| 192.168.10.22 | ndelucca-pixel-8-2.4ghz | ca:61:9f:ce:53:ce |

### DNS Rewrites
| Domain | IP Address |
|--------|------------|
| ndelucca-server.com | 192.168.10.10 |
| ndelucca-acer.com | 192.168.10.13 |
| ndelucca-raspberry-printer.com | 192.168.10.11 |

### DNS Settings
- **Upstream DNS**: AdGuard unfiltered, Quad9
- **Mode**: Load balance
- **Filters**: AdGuard DNS filter (enabled)
- **Cache**: Enabled, 4MB

## How to Use

### Apply Full Configuration
```bash
# Deploy everything (binary, config, service)
ansible-playbook playbooks/adguard.yml
```

### Update Configuration Only
```bash
# Update just the configuration without reinstalling
ansible-playbook playbooks/adguard.yml --tags configure
```

### Skip Configuration (Manual Setup via Web UI)
```bash
# Install binary and service, but don't deploy config
ansible-playbook playbooks/adguard.yml -e "adguard_configure_app=false"
```

## Modifying Configuration

### Option 1: Edit Host Variables
Edit `inventory/host_vars/ndelucca-server.yml` to change settings:

```yaml
# Add a new static lease
adguard_dhcp_static_leases:
  - ip: 192.168.10.30
    hostname: new-device
    mac: "aa:bb:cc:dd:ee:ff"

# Add a new DNS rewrite
adguard_dns_rewrites:
  - domain: newdevice.local
    answer: 192.168.10.30
    enabled: true
```

### Option 2: Edit Default Variables
Edit `roles/adguard_home/defaults/main.yml` to change defaults for all servers.

### Option 3: Use Extra Vars
Override variables at runtime:

```bash
ansible-playbook playbooks/adguard.yml -e "adguard_dhcp_range_end=192.168.10.250"
```

## Password Management

AdGuard Home uses bcrypt-hashed passwords. To change the password:

1. **Generate a hash**:
   ```bash
   htpasswd -nbB "" "your-new-password" | cut -d ":" -f 2
   ```

2. **Update the hash** in `inventory/host_vars/ndelucca-server.yml`:
   ```yaml
   adguard_users:
     - name: ndelucca
       password: $2a$10$NEW_HASH_HERE
   ```

3. **Apply the change**:
   ```bash
   ansible-playbook playbooks/adguard.yml --tags configure
   ```

## Configuration Files Managed

When `adguard_configure_app: true` (default for ndelucca-server):

| File | Purpose | Backup |
|------|---------|--------|
| `/opt/AdGuardHome/AdGuardHome.yaml` | Main configuration | Yes (.backup) |
| `/opt/AdGuardHome/data/leases.json` | Static DHCP leases | Yes (.backup) |

## Important Notes

1. **Backups**: Original files are backed up automatically before modification
2. **Service Restart**: AdGuard Home is restarted when configuration changes
3. **Idempotent**: Safe to run multiple times - only changes when needed
4. **Templated**: All settings are now managed via Ansible variables
5. **Version Control**: Configuration is now tracked in Git

## Available Tags

| Tag | Purpose |
|-----|---------|
| `configure` | Deploy configuration only |
| `install` | Install binary only |
| `service` | Configure service only |
| `firewall` | Configure firewall only |
| `selinux` | Configure SELinux only |

## Examples

### Add a New Device
```yaml
# In inventory/host_vars/ndelucca-server.yml
adguard_dhcp_static_leases:
  # ... existing leases ...
  - ip: 192.168.10.25
    hostname: laptop
    mac: "12:34:56:78:9a:bc"

adguard_dns_rewrites:
  # ... existing rewrites ...
  - domain: laptop.local
    answer: 192.168.10.25
    enabled: true
```

Then apply:
```bash
ansible-playbook playbooks/adguard.yml --tags configure
```

### Change DNS Upstream Servers
```yaml
# In inventory/host_vars/ndelucca-server.yml
adguard_upstream_dns:
  - https://dns.cloudflare.com/dns-query
  - https://dns.google/dns-query
```

### Enable More Filters
```yaml
# In inventory/host_vars/ndelucca-server.yml
adguard_filters:
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt
    name: AdGuard DNS filter
    id: 1
  - enabled: true  # Changed from false to true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt
    name: AdAway Default Blocklist
    id: 2
```

## Troubleshooting

### Configuration Not Applied
```bash
# Check if configure task ran
ansible-playbook playbooks/adguard.yml --tags configure -vv

# Verify configuration file
ansible ndelucca-server -m shell -a "cat /opt/AdGuardHome/AdGuardHome.yaml | head -20" --become
```

### Service Won't Start After Config Change
```bash
# Check service status
ansible ndelucca-server -m shell -a "systemctl status AdGuardHome" --become

# Check service logs
ansible ndelucca-server -m shell -a "journalctl -u AdGuardHome -n 50" --become

# Validate YAML syntax
ansible ndelucca-server -m shell -a "python3 -c 'import yaml; yaml.safe_load(open(\"/opt/AdGuardHome/AdGuardHome.yaml\"))'" --become
```

### Restore Previous Configuration
```bash
# Find backup files
ansible ndelucca-server -m shell -a "ls -la /opt/AdGuardHome/*.backup*" --become

# Restore from backup
ansible ndelucca-server -m shell -a "cp /opt/AdGuardHome/AdGuardHome.yaml.backup /opt/AdGuardHome/AdGuardHome.yaml" --become
ansible ndelucca-server -m shell -a "systemctl restart AdGuardHome" --become
```

## Next Steps

1. **Review Configuration**: Check `inventory/host_vars/ndelucca-server.yml` to verify settings
2. **Test Update**: Try updating configuration with `--tags configure`
3. **Add More Devices**: Add static leases and DNS rewrites as needed
4. **Customize Filters**: Enable/disable filter lists based on your needs
5. **Version Control**: Commit changes to Git to track configuration history

## Documentation

- Role README: `roles/adguard_home/README.md`
- Full variable reference: `roles/adguard_home/defaults/main.yml`
- Templates: `roles/adguard_home/templates/`
