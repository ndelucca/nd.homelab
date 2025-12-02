# Fedora Home Server Ansible Configuration

Ansible project to configure a Fedora home server with Cockpit (web management interface) and AdGuard Home for DNS filtering.

## Overview

This project uses Ansible best practices with a role-based structure to:
- Install and configure **Cockpit** web console for server management
- Install and configure **AdGuard Home** for DNS filtering and ad blocking (native binary)
- Handle Fedora-specific configurations (systemd-resolved, SELinux, firewalld)
- Provide a maintainable, extensible foundation for future services

## Features

- **Modern Ansible Best Practices**: FQCN, YAML inventory, role-based organization
- **Fedora-Optimized**: Handles systemd-resolved port conflicts and SELinux contexts
- **Security Hardening**: Systemd service restrictions, unprivileged users, capabilities
- **Idempotent**: Safe to run multiple times
- **Tagged Tasks**: Run specific components independently
- **Extensible**: Easy to add new roles and services

## Prerequisites

### Control Node (where you run Ansible)
- Ansible 2.14 or higher
- Python 3.8+
- Required collections:
  ```bash
  ansible-galaxy collection install ansible.posix
  ansible-galaxy collection install community.general
  ```

### Target Server
- Fedora 38 or higher
- SSH access with key-based authentication
- User with sudo privileges
- Minimum 1GB RAM (2GB+ recommended)
- Internet connection

## Quick Start

### 1. Clone or Navigate to This Directory

```bash
cd /home/ndelucca/environment/home-server
```

### 2. Update Inventory Configuration

Edit `inventory/hosts.yml` and update:
- `ansible_host`: Your server's IP address
- `ansible_user`: Your SSH username

```yaml
ndelucca-server:
  ansible_host: 192.168.1.100  # CHANGE THIS
  ansible_user: your_username   # CHANGE THIS
```

### 3. Verify SSH Key Configuration

Ensure your SSH key path matches in `ansible.cfg` (default: `~/.ssh/id_ed25519`):

```bash
# Test SSH connection
ssh your_username@192.168.1.100
```

### 4. Test Ansible Connectivity

```bash
ansible homeservers -m ping
```

Expected output:
```
ndelucca-server | SUCCESS => {
    "ping": "pong"
}
```

### 5. Run the Complete Setup

```bash
ansible-playbook playbooks/site.yml
```

This will:
1. Install and configure Cockpit
2. Configure systemd-resolved to free port 53
3. Install AdGuard Home native binary
4. Configure firewall rules
5. Set SELinux contexts
6. Start all services

## Usage Examples

### Run Complete Setup
```bash
ansible-playbook playbooks/site.yml
```

### Install Only Cockpit
```bash
ansible-playbook playbooks/cockpit.yml
```

### Install Only AdGuard Home
```bash
ansible-playbook playbooks/adguard.yml
```

### Use Tags for Specific Tasks
```bash
# Run only firewall configuration
ansible-playbook playbooks/site.yml --tags firewall

# Run only AdGuard installation (skip configuration)
ansible-playbook playbooks/site.yml --tags install

# Skip SELinux configuration
ansible-playbook playbooks/site.yml --skip-tags selinux
```

### Dry Run (Check Mode)
```bash
# See what would change without making changes
ansible-playbook playbooks/site.yml --check --diff
```

### Syntax Check
```bash
ansible-playbook playbooks/site.yml --syntax-check
```

## Post-Installation

### Access Cockpit

1. Open your browser and navigate to:
   ```
   https://YOUR_SERVER_IP:9090
   ```

2. Log in with your server credentials
3. Accept the self-signed certificate warning (or install a proper certificate)

### Configure AdGuard Home

1. Open your browser and navigate to:
   ```
   http://YOUR_SERVER_IP:3000
   ```

2. Complete the initial setup wizard:
   - Set admin username and password
   - Configure listening interfaces (usually keep defaults)
   - Configure upstream DNS servers (e.g., 1.1.1.1, 8.8.8.8)
   - Choose filter lists (recommended: enable default lists)

3. Configure your devices to use the server's IP as their DNS server

### Service Management (AdGuard Home)

```bash
# View AdGuard Home service logs
sudo journalctl -u AdGuardHome -n 50

# Restart AdGuard Home service
sudo systemctl restart AdGuardHome

# Check service status
sudo systemctl status AdGuardHome

# Update AdGuard Home binary
ansible-playbook playbooks/adguard.yml
```

### Verification Commands

```bash
# Check service status
sudo systemctl status cockpit.socket
sudo systemctl status AdGuardHome

# Verify DNS functionality
dig @127.0.0.1 example.com

# Check listening ports
ss -tulnp | grep -E ':(53|3000|80|9090)'

# Check firewall rules
sudo firewall-cmd --list-all

# Check SELinux denials
sudo ausearch -m avc -ts recent
```

## Configuration

### Customizing Variables

#### Host-Specific Variables
Edit `inventory/hosts.yml`:
```yaml
ndelucca-server:
  ansible_host: 192.168.1.100
  cockpit_port: 9090
  adguard_container_tag: "latest"
```

#### Group Variables
Edit `inventory/group_vars/homeservers.yml`:
```yaml
firewall_enabled: true
firewall_default_zone: public
selinux_state: enforcing
timezone: America/New_York
```

#### Override Role Defaults
Create `host_vars/ndelucca-server.yml`:
```yaml
# Change AdGuard Home ports
adguard_bind_port: 8080
adguard_dns_port: 5353

# Disable certain features
adguard_manage_selinux: false
```

### Common Customizations

#### Change AdGuard Home Version
In `inventory/hosts.yml` or via extra vars:
```yaml
adguard_version: "v0.107.69"  # Pin to specific version (or use 'latest')
```

#### Add More Cockpit Modules
In `roles/cockpit/defaults/main.yml`:
```yaml
cockpit_packages:
  - cockpit
  - cockpit-podman      # Add container management
  - cockpit-machines    # Add VM management
  - cockpit-pcp         # Add performance monitoring
```

#### Customize Firewall Zones
In `inventory/group_vars/homeservers.yml`:
```yaml
firewall_default_zone: home  # Use 'home' zone instead of 'public'
```

## Troubleshooting

### Port 53 Already in Use

**Symptom**: AdGuard Home fails to start with port binding error

**Solution**: Manually check and disable systemd-resolved stub:
```bash
# Check what's using port 53
sudo ss -tulnp | grep :53

# Verify systemd-resolved configuration
cat /etc/systemd/resolved.conf.d/adguardhome.conf

# Reload systemd-resolved
sudo systemctl restart systemd-resolved

# Verify port is free
sudo ss -tulnp | grep :53
```

### SELinux Denials

**Symptom**: AdGuard Home fails with permission errors

**Solution**: Check and apply SELinux contexts:
```bash
# Check for denials
sudo ausearch -m avc -ts recent

# Manually apply contexts
sudo restorecon -Rv /opt/AdGuardHome
sudo restorecon -Rv /var/lib/AdGuardHome

# Temporarily set to permissive (for testing only)
sudo setenforce 0
```

### Firewall Blocking Access

**Symptom**: Cannot access Cockpit or AdGuard Home from network

**Solution**: Verify firewall rules:
```bash
# Check firewall status
sudo firewall-cmd --state

# List all rules
sudo firewall-cmd --list-all

# Manually add rules if needed
sudo firewall-cmd --permanent --add-service=cockpit
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --permanent --add-port=53/tcp
sudo firewall-cmd --permanent --add-port=53/udp
sudo firewall-cmd --reload
```

### SSH Connection Issues

**Symptom**: Ansible cannot connect to server

**Solution**:
```bash
# Test SSH manually
ssh -vvv your_username@server_ip

# Verify SSH key
ssh-add -l

# Test with password (if key fails)
ansible homeservers -m ping --ask-pass
```

### AdGuard Home Service Won't Start

**Symptom**: AdGuard Home service fails to start

**Solution**: Check service and binary configuration:
```bash
# Check systemd logs
sudo journalctl -u AdGuardHome -n 50 --no-pager

# Verify binary exists
ls -la /usr/local/bin/AdGuardHome

# Check working directory permissions
ls -la /opt/AdGuardHome

# Check capabilities
getcap /usr/local/bin/AdGuardHome

# Manually reload systemd
sudo systemctl daemon-reload

# Try starting manually
sudo systemctl start AdGuardHome
```

## Project Structure

```
home-server/
├── ansible.cfg                          # Project configuration
├── inventory/
│   ├── hosts.yml                        # Server inventory
│   └── group_vars/
│       ├── all.yml                      # Global variables
│       └── homeservers.yml              # Group variables
├── playbooks/
│   ├── site.yml                         # Main playbook
│   ├── cockpit.yml                      # Cockpit playbook
│   ├── adguard.yml                      # AdGuard playbook
│   └── remove_adguard.yml               # AdGuard removal playbook
├── roles/
│   ├── cockpit/                         # Cockpit role
│   │   ├── tasks/main.yml
│   │   ├── handlers/main.yml
│   │   ├── defaults/main.yml
│   │   └── meta/main.yml
│   └── adguard_home/                    # AdGuard Home role
│       ├── tasks/
│       │   ├── main.yml
│       │   ├── preflight.yml
│       │   ├── systemd-resolved.yml
│       │   ├── install.yml
│       │   ├── service.yml
│       │   ├── firewall.yml
│       │   └── selinux.yml
│       ├── handlers/main.yml
│       ├── defaults/main.yml
│       └── meta/main.yml
└── README.md
```

## Available Tags

| Tag | Description |
|-----|-------------|
| `cockpit` | All Cockpit tasks |
| `adguard` | All AdGuard Home tasks |
| `dns` | Same as adguard |
| `monitoring` | Same as cockpit |
| `preflight` | Pre-installation checks |
| `systemd-resolved` | systemd-resolved configuration |
| `install` | Binary installation |
| `service` | Systemd service configuration |
| `firewall` | Firewall configuration |
| `selinux` | SELinux configuration |

## Security Notes

- AdGuard Home runs as an unprivileged `adguard` user
- Capabilities are used instead of root for port binding
- SELinux remains in enforcing mode with proper contexts
- Systemd service includes security hardening directives
- Only necessary ports are opened in the firewall
- SSH uses key-based authentication only

## Extending This Project

### Adding a New Service

1. Create a new role:
   ```bash
   mkdir -p roles/myservice/{tasks,handlers,defaults,templates,meta}
   ```

2. Create role files following the Cockpit role as a template

3. Add to `playbooks/site.yml`:
   ```yaml
   - role: myservice
     tags: ['myservice']
   ```

### Adding Multiple Servers

1. Edit `inventory/hosts.yml`:
   ```yaml
   homeservers:
     hosts:
       ndelucca-server:
         ansible_host: 192.168.10.10
       ndelucca-acer:
         ansible_host: 192.168.10.13
   ```

2. Use host variables for server-specific configuration

### Creating a Staging Environment

1. Copy inventory:
   ```bash
   cp -r inventory inventory_staging
   ```

2. Update staging hosts and variables

3. Run with staging inventory:
   ```bash
   ansible-playbook -i inventory_staging playbooks/site.yml
   ```

## Maintenance

### Updating AdGuard Home

1. Change version in inventory or use extra vars:
   ```yaml
   adguard_version: "v0.108.0"  # New version
   ```

2. Run the playbook to download new binary and restart service:
   ```bash
   ansible-playbook playbooks/adguard.yml
   # Or use extra vars directly:
   ansible-playbook playbooks/adguard.yml -e "adguard_version=latest"
   ```

### Backup AdGuard Home Configuration

```bash
# Manual backup (native binary installation)
scp your_username@server_ip:/opt/AdGuardHome/AdGuardHome.yaml ./backups/

# Backup entire working directory
ssh your_username@server_ip "sudo tar -czf /tmp/adguard-backup.tar.gz /opt/AdGuardHome"
scp your_username@server_ip:/tmp/adguard-backup.tar.gz ./backups/

# Or use Ansible to fetch config
ansible homeservers -m fetch \
  -a "src=/opt/AdGuardHome/AdGuardHome.yaml dest=./backups/{{ inventory_hostname }}/" \
  --become
```

## License

MIT

## Contributing

Feel free to submit issues and pull requests for improvements.

## References

- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [AdGuard Home Documentation](https://github.com/AdguardTeam/AdGuardHome/wiki)
- [Cockpit Project](https://cockpit-project.org/)
- [Fedora Documentation](https://docs.fedoraproject.org/)
