# AdGuard Home Ansible Role

This role installs and configures AdGuard Home DNS server as a native binary on Fedora systems.

## Features

- Native binary installation (not containerized)
- Full configuration management via Ansible variables
- DHCP server configuration with static leases
- DNS rewrites (custom local DNS entries)
- Comprehensive DNS filtering options
- Automatic systemd-resolved conflict resolution
- SELinux and firewall configuration

## Requirements

- Fedora 38 or higher
- Ansible 2.14+
- Collections:
  - ansible.posix
  - community.general

## Role Variables

### Basic Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `adguard_version` | `latest` | AdGuard Home version to install |
| `adguard_install_dir` | `/usr/local/bin` | Binary installation directory |
| `adguard_working_dir` | `/opt/AdGuardHome` | Working directory for data and config |
| `adguard_user` | `adguard` | System user for AdGuard Home |
| `adguard_group` | `adguard` | System group for AdGuard Home |
| `adguard_configure_app` | `true` | Deploy custom configuration (set to false for manual setup) |

### Network Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `adguard_bind_host` | `0.0.0.0` | IP address to bind HTTP interface |
| `adguard_admin_port` | `80` | Admin web interface port |
| `adguard_dns_port` | `53` | DNS server port |
| `adguard_dns_over_tls_port` | `853` | DNS-over-TLS port |
| `adguard_dns_over_quic_port` | `784` | DNS-over-QUIC port |
| `adguard_dns_over_https_port` | `443` | DNS-over-HTTPS port |

### DNS Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `adguard_upstream_dns` | AdGuard + Quad9 | List of upstream DNS servers |
| `adguard_upstream_mode` | `load_balance` | Upstream mode: load_balance, parallel, or fastest_addr |
| `adguard_bootstrap_dns` | Multiple providers | Bootstrap DNS for resolving upstream hostnames |
| `adguard_cache_enabled` | `true` | Enable DNS cache |
| `adguard_cache_size` | `4194304` | Cache size in bytes (4MB) |

### DHCP Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `adguard_dhcp_enabled` | `false` | Enable DHCP server |
| `adguard_dhcp_interface_name` | `eth0` | Network interface for DHCP |
| `adguard_dhcp_gateway_ip` | `192.168.1.1` | Gateway IP address |
| `adguard_dhcp_range_start` | `192.168.1.100` | DHCP range start |
| `adguard_dhcp_range_end` | `192.168.1.200` | DHCP range end |
| `adguard_dhcp_lease_duration` | `86400` | Lease duration in seconds (24h) |
| `adguard_dhcp_static_leases` | `[]` | List of static DHCP leases |

### DNS Rewrites

| Variable | Default | Description |
|----------|---------|-------------|
| `adguard_dns_rewrites` | `[]` | Custom local DNS entries |

### Filters

| Variable | Default | Description |
|----------|---------|-------------|
| `adguard_filters` | AdGuard DNS filter | List of filter lists to enable |
| `adguard_filtering_enabled` | `true` | Enable DNS filtering |
| `adguard_protection_enabled` | `true` | Enable protection features |

## Example Configurations

### Basic Installation (Manual Web Setup)

```yaml
# Disable automatic configuration to use web UI for setup
adguard_configure_app: false
```

### Configured Installation with DHCP

```yaml
# inventory/host_vars/myserver.yml
adguard_configure_app: true

# User with hashed password
adguard_users:
  - name: admin
    password: $2a$10$... # Generate with: htpasswd -nbB "" "password" | cut -d ":" -f 2

# DHCP server
adguard_dhcp_enabled: true
adguard_dhcp_interface_name: eth0
adguard_dhcp_gateway_ip: 192.168.1.1
adguard_dhcp_subnet_mask: 255.255.255.0
adguard_dhcp_range_start: 192.168.1.100
adguard_dhcp_range_end: 192.168.1.200

# Static DHCP leases
adguard_dhcp_static_leases:
  - ip: 192.168.1.10
    hostname: server
    mac: "aa:bb:cc:dd:ee:ff"
  - ip: 192.168.1.20
    hostname: workstation
    mac: "11:22:33:44:55:66"

# DNS rewrites (local DNS entries)
adguard_dns_rewrites:
  - domain: server.local
    answer: 192.168.1.10
    enabled: true
  - domain: nas.local
    answer: 192.168.1.50
    enabled: true
```

### Custom DNS Configuration

```yaml
# Use custom upstream DNS servers
adguard_upstream_dns:
  - https://dns.cloudflare.com/dns-query
  - https://dns.google/dns-query
  - 1.1.1.1
  - 8.8.8.8

# Use parallel mode for faster resolution
adguard_upstream_mode: parallel

# Increase cache size
adguard_cache_size: 8388608  # 8MB
```

## Usage

### Run Complete Installation

```bash
ansible-playbook playbooks/adguard.yml
```

### Run Only Configuration Update

```bash
# Update configuration without reinstalling
ansible-playbook playbooks/adguard.yml --tags configure
```

### Skip Configuration (Manual Setup)

```bash
# Install binary and service only, configure via web UI
ansible-playbook playbooks/adguard.yml -e "adguard_configure_app=false"
```

## Password Management

AdGuard Home requires bcrypt-hashed passwords in the configuration file.

### Generate a Password Hash

```bash
# Using htpasswd (from apache2-utils package)
htpasswd -nbB "" "yourpassword" | cut -d ":" -f 2

# Example output: $2a$10$A/PkUdTvjpRlqwtFvEYEX.L8ypXT3saCpsxE0/XzsUTV6SRZAwJ.a
```

Then add to your inventory:

```yaml
adguard_users:
  - name: yourusername
    password: $2a$10$A/PkUdTvjpRlqwtFvEYEX.L8ypXT3saCpsxE0/XzsUTV6SRZAwJ.a
```

## Configuration Files

When `adguard_configure_app: true`, the role manages:

- `/opt/AdGuardHome/AdGuardHome.yaml` - Main configuration file
- `/opt/AdGuardHome/data/leases.json` - DHCP static leases

Existing files are backed up with `.backup` extension before modification.

## Tags

| Tag | Description |
|-----|-------------|
| `adguard` | All AdGuard Home tasks |
| `preflight` | Pre-installation checks |
| `install` | Binary installation |
| `configure` | Application configuration |
| `service` | Systemd service setup |
| `firewall` | Firewall rules |
| `selinux` | SELinux contexts |

## Dependencies

None

## License

MIT

## Author

Nicolas Delucca
