# Role Creation and Deployment Checklists

This document provides comprehensive checklists for creating, deploying, and testing new roles in the home-server infrastructure.

## Pre-Development Checklist

Before starting a new role, gather this information:

- [ ] Service name and purpose clearly defined
- [ ] Installation method identified (binary/package/container)
- [ ] Service documentation reviewed (official docs)
- [ ] Port requirements identified
- [ ] Storage requirements identified
- [ ] Web interface requirements known (if applicable)
- [ ] External dependencies identified
- [ ] License compatibility verified

## Role Structure Checklist

Verify all required directories and files are created:

### Required Directories

- [ ] `roles/[service_name]/` - Main role directory
- [ ] `roles/[service_name]/defaults/` - Default variables
- [ ] `roles/[service_name]/tasks/` - Task files
- [ ] `roles/[service_name]/handlers/` - Event handlers
- [ ] `roles/[service_name]/meta/` - Role metadata
- [ ] `roles/[service_name]/templates/` - Jinja2 templates (if needed)

### Required Files

- [ ] `defaults/main.yml` - All configurable variables documented
- [ ] `tasks/main.yml` - Orchestration with import_tasks
- [ ] `tasks/preflight.yml` - Pre-installation checks
- [ ] `tasks/install.yml` - Software installation
- [ ] `tasks/configure.yml` - Configuration deployment (if needed)
- [ ] `tasks/service.yml` - Systemd service management
- [ ] `tasks/selinux.yml` - SELinux configuration
- [ ] `handlers/main.yml` - Service restart handlers
- [ ] `meta/main.yml` - Role metadata with collections

### Optional Files (Based on Service Type)

- [ ] `tasks/repository.yml` - External repository setup (package services)
- [ ] `tasks/quadlet.yml` - Podman Quadlet deployment (container services)
- [ ] `templates/service.service.j2` - Systemd unit file (binary services)
- [ ] `templates/config.j2` - Service configuration file
- [ ] `templates/service-pod.yaml.j2` - Kubernetes YAML (container services)
- [ ] `templates/service.kube.j2` - Quadlet unit (container services)

## Variable Definition Checklist

Ensure all standard variables are defined in `defaults/main.yml`:

### Core Variables

- [ ] `[service]_user` - Service user (default: ndelucca)
- [ ] `[service]_group` - Service group (default: ndelucca)
- [ ] `[service]_uid` - User ID (for containers, obtained dynamically)

### Directory Variables

- [ ] `[service]_base_dir` - Base directory (/opt or /srv)
- [ ] `[service]_working_dir` - Working/data directory
- [ ] `[service]_config_dir` - Configuration directory
- [ ] `[service]_install_dir` - Binary location (for binary services)

### Service Variables

- [ ] `[service]_service_name` - Systemd service name
- [ ] `[service]_service_enabled` - Enable on boot (default: true)
- [ ] `[service]_service_state` - Service state (default: started)

### Network Variables

- [ ] `[service]_bind_address` - Bind address (MUST be 127.0.0.1 for web services)
- [ ] `[service]_port` - Service port

### Integration Variables

- [ ] `[service]_firewall_enabled` - Firewall rules enabled (false if behind NGINX)
- [ ] `[service]_firewall_zone` - Firewall zone (default: FedoraServer)
- [ ] `[service]_manage_selinux` - SELinux management (default: true)

### Installation Variables (Binary Services)

- [ ] `[service]_version` - Version or release tag
- [ ] `[service]_download_url` - Download URL template
- [ ] `[service]_arch` - Architecture (default: amd64)

### Container Variables (Podman Services)

- [ ] `[service]_pod_name` - Pod name
- [ ] `[service]_quadlet_dir` - Quadlet directory path
- [ ] `[service]_image` or `[service]_*_image` - Container image(s)
- [ ] Database credentials (if applicable)

## Task Implementation Checklist

### preflight.yml

- [ ] Fedora distribution verification
- [ ] Base directory creation with correct ownership
- [ ] Working directory creation
- [ ] Config directory creation
- [ ] Prerequisite package installation (tar, gzip for binaries)

### install.yml (Binary Services)

- [ ] Check if binary already exists
- [ ] Create temporary download directory
- [ ] Download binary archive
- [ ] Extract archive
- [ ] Copy binary to installation directory with correct permissions
- [ ] Clean up temporary directory
- [ ] Verify installation (version check)
- [ ] Display installed version

### install.yml (Package Services)

- [ ] Install packages via DNF
- [ ] Verify installation (version check)
- [ ] Display installed version

### install.yml (Container Services)

- [ ] Install Podman and dependencies
- [ ] Verify Podman version (>= 4.4 for Quadlet)
- [ ] Enable user lingering
- [ ] Install additional dependencies (Node.js, CLI tools, etc.)

### configure.yml

- [ ] Deploy configuration file(s) with correct ownership
- [ ] Deploy environment file(s) with correct mode (0600 for secrets)
- [ ] Notify restart handler on changes

### service.yml (Standard Services)

- [ ] Deploy systemd unit file
- [ ] Notify daemon-reload and restart handlers
- [ ] Flush handlers
- [ ] Enable and start service
- [ ] Wait for service availability (port check)

### service.yml (Container Services)

- [ ] Get user UID dynamically
- [ ] Ensure Quadlet directory exists
- [ ] Deploy Kubernetes YAML pod definition
- [ ] Deploy Quadlet .kube unit
- [ ] Flush handlers
- [ ] Enable and start service with user scope
- [ ] Set XDG_RUNTIME_DIR environment variable
- [ ] Wait for service availability

### selinux.yml

- [ ] Check SELinux status (getenforce)
- [ ] Install SELinux policy packages
- [ ] Set SELinux context for binary (bin_t)
- [ ] Set SELinux context for working directory (var_lib_t)
- [ ] Set SELinux context for data directory (appropriate type)
- [ ] Set SELinux context for container volumes (container_file_t)
- [ ] Allow service to bind to custom port (if not 80/443)
- [ ] Notify apply selinux context handler

### handlers/main.yml (Standard Services)

- [ ] daemon-reload handler
- [ ] restart service handler
- [ ] apply selinux context handler

### handlers/main.yml (Container Services)

- [ ] daemon-reload-user handler with XDG_RUNTIME_DIR
- [ ] restart service-pod handler with user scope
- [ ] apply selinux context handler

### meta/main.yml

- [ ] Galaxy info with author, description, license
- [ ] Minimum Ansible version specified
- [ ] Platform: Fedora specified
- [ ] Collections: community.general included
- [ ] Collections: ansible.posix included

## Integration Checklist

### Firewall Integration

- [ ] Create `roles/firewall/tasks/[service].yml`
- [ ] Implement appropriate firewall pattern (behind NGINX or direct access)
- [ ] Add import_tasks to `roles/firewall/tasks/main.yml`
- [ ] Include conditional based on `service_firewall_enabled`
- [ ] Add appropriate tags

### NGINX Integration (Web Services Only)

- [ ] Add `nginx_[service]_port` variable to `roles/nginx/defaults/main.yml`
- [ ] Create `roles/nginx/templates/conf.d/[service].conf.j2`
- [ ] Implement HTTP server block
- [ ] Implement HTTPS server block with SSL
- [ ] Add security headers
- [ ] Add WebSocket support (if needed)
- [ ] Add large upload support (if needed)
- [ ] Configure proxy settings (buffering, timeouts)
- [ ] Add template to `roles/nginx/tasks/configure.yml` loop
- [ ] Verify service binds to 127.0.0.1 (not 0.0.0.0)

### SELinux Integration

- [ ] All binaries have correct context (bin_t)
- [ ] All working directories have correct context (var_lib_t)
- [ ] All data directories have correct context (public_content_rw_t or container_file_t)
- [ ] Custom ports have correct SELinux port type (http_port_t)
- [ ] Container volumes have container_file_t context
- [ ] SELinux booleans set if needed (httpd_can_network_connect)

### DNS Integration (Web Services Only)

- [ ] Add DNS rewrite entry to `inventory/host_vars/ndelucca-server.yml`
- [ ] Use pattern: `[subdomain].ndelucca-server.com`
- [ ] Point to 192.168.10.10 (ndelucca-server)
- [ ] Set enabled: true

## Playbook Integration Checklist

### Service Playbook

- [ ] Create `playbooks/[service].yml`
- [ ] Add usage comment with ansible-playbook command
- [ ] Add note about firewall role
- [ ] Target hosts: homeservers
- [ ] Set gather_facts: true
- [ ] Include service role

### Site Playbook

- [ ] Add role to `playbooks/site.yml`
- [ ] Add appropriate tags (service name and category)
- [ ] Place in correct order (consider dependencies)
- [ ] Add conditional if needed (when: clause)

## Pre-Deployment Checklist

Before running the playbook for the first time:

### Code Review

- [ ] All task files follow established patterns
- [ ] Variables follow naming conventions
- [ ] No hardcoded values (use variables)
- [ ] Handlers properly defined and referenced
- [ ] Templates use correct variable substitution
- [ ] SELinux contexts appropriate for directories
- [ ] Service binds to 127.0.0.1 (not 0.0.0.0)
- [ ] No sensitive data in defaults (use Ansible Vault)

### Integration Review

- [ ] Firewall configuration appropriate
- [ ] NGINX configuration complete (if web service)
- [ ] DNS rewrite added (if web service)
- [ ] SELinux contexts for all directories
- [ ] All collections available (community.general, ansible.posix)

### Documentation Review

- [ ] Variables documented in defaults/main.yml
- [ ] Task files have descriptive names
- [ ] Complex tasks have comments
- [ ] Playbook has usage documentation

## Syntax Check

Before deployment, always run syntax check:

```bash
ansible-playbook playbooks/[service].yml --syntax-check -l ndelucca-server
```

Verify:

- [ ] No syntax errors
- [ ] No undefined variables
- [ ] All templates referenced exist
- [ ] All imported task files exist

## Deployment Checklist

### Initial Deployment

Run with ansible-host-limiter:

```bash
ansible-playbook playbooks/[service].yml -l ndelucca-server
```

Monitor:

- [ ] Playbook completes without errors
- [ ] No failed tasks
- [ ] All handlers execute successfully
- [ ] Service installation succeeds
- [ ] Service configuration succeeds
- [ ] Service starts successfully

### Deployment Troubleshooting

If deployment fails:

- [ ] Check playbook output for specific error
- [ ] Verify all prerequisites met (packages, repositories)
- [ ] Check service logs: `journalctl -u [service] -n 50`
- [ ] Check SELinux denials: `ausearch -m avc -ts recent`
- [ ] Verify file permissions and ownership
- [ ] Check disk space availability
- [ ] Verify network connectivity (for downloads)

## Post-Deployment Verification

### Service Status

- [ ] Service is enabled: `systemctl is-enabled [service]`
- [ ] Service is running: `systemctl is-active [service]`
- [ ] Service status shows no errors: `systemctl status [service]`
- [ ] Service listening on correct port: `ss -tlnp | grep [port]`
- [ ] Service bound to correct address (127.0.0.1)

### Container Status (Podman Services)

- [ ] Pod is running: `podman pod ps`
- [ ] All containers in pod running: `podman ps --pod`
- [ ] Container logs show no errors: `podman logs [container]`
- [ ] Volumes mounted correctly: `podman inspect [pod]`

### Network Access

For web services:

- [ ] Service responds on localhost: `curl http://127.0.0.1:[port]`
- [ ] HTTP access via subdomain: `curl http://[subdomain].ndelucca-server.com`
- [ ] HTTPS access via subdomain: `curl https://[subdomain].ndelucca-server.com`
- [ ] DNS resolution works: `dig [subdomain].ndelucca-server.com`
- [ ] WebSocket connection works (if applicable)

### Firewall Verification

- [ ] Firewall rules applied: `firewall-cmd --list-all`
- [ ] Correct ports open (or not open if behind NGINX)
- [ ] NGINX ports accessible (80, 443)
- [ ] Service not directly accessible from outside (if behind NGINX)

### SELinux Verification

- [ ] SELinux contexts correct: `ls -lZ [service_dir]`
- [ ] Binary has correct context: `ls -lZ [binary_path]`
- [ ] No SELinux denials: `ausearch -m avc -ts recent`
- [ ] Custom port has correct type: `semanage port -l | grep [port]`
- [ ] Required booleans enabled: `getsebool httpd_can_network_connect`

### File System Verification

- [ ] All directories exist with correct ownership
- [ ] All configuration files present with correct permissions
- [ ] Log files being written (if applicable)
- [ ] Data directories writable by service user
- [ ] Custom storage locations accessible

### Functional Testing

- [ ] Web UI accessible (if applicable)
- [ ] Can log in with credentials (if applicable)
- [ ] Basic functionality works (create/read/update/delete)
- [ ] File uploads work (if applicable)
- [ ] Media playback works (if applicable)
- [ ] Real-time features work (if applicable)

## Reboot Persistence Testing

Critical verification:

```bash
# Reboot the server
ansible ndelucca-server -m reboot --become -l ndelucca-server

# Wait for server to come back up
# Then verify service status
```

After reboot:

- [ ] Service automatically started
- [ ] Service is running correctly
- [ ] Web interface accessible
- [ ] Data persisted correctly
- [ ] Container services restarted (for Podman)
- [ ] All containers in pod running

## Security Review

- [ ] Service runs as non-root user
- [ ] Service binds to 127.0.0.1 (not 0.0.0.0)
- [ ] Configuration files have restrictive permissions (0600 for secrets)
- [ ] No passwords in plain text (use Ansible Vault)
- [ ] SELinux in enforcing mode
- [ ] Firewall rules minimal and appropriate
- [ ] NGINX security headers present
- [ ] SSL/TLS configured correctly

## Performance Testing

- [ ] Service responds quickly to requests
- [ ] CPU usage reasonable under load
- [ ] Memory usage stable
- [ ] Disk I/O acceptable
- [ ] Network bandwidth sufficient

## Documentation Tasks

After successful deployment:

- [ ] Document service URL and access method
- [ ] Document any manual configuration steps required
- [ ] Document backup procedures for service data
- [ ] Document restore procedures
- [ ] Document common troubleshooting steps
- [ ] Update DNS documentation with new subdomain
- [ ] Update service inventory/list

## Backup Configuration

- [ ] Identify critical data directories
- [ ] Configure backup for data directories
- [ ] Test backup procedure
- [ ] Test restore procedure
- [ ] Document backup location and schedule

## Monitoring Setup (Optional)

- [ ] Configure monitoring for service availability
- [ ] Set up alerts for service failures
- [ ] Monitor resource usage
- [ ] Set up log aggregation (if needed)

## Final Validation

Before considering the role complete:

- [ ] All checklists above completed
- [ ] Service running stable for 24+ hours
- [ ] No errors in logs
- [ ] No SELinux denials
- [ ] Backup tested successfully
- [ ] Documentation complete
- [ ] Team members can access service
- [ ] Service survived reboot test

## Role Update Checklist

When updating an existing role:

- [ ] Review current role implementation
- [ ] Identify what needs to change
- [ ] Test changes in development first
- [ ] Backup service data before update
- [ ] Run playbook with --check flag first
- [ ] Run playbook to apply changes
- [ ] Verify service still works after update
- [ ] Check for new SELinux denials
- [ ] Verify data integrity
- [ ] Update documentation if needed

## Troubleshooting Common Issues

### Service Won't Start

- [ ] Check service status and logs
- [ ] Verify all dependencies installed
- [ ] Check file permissions
- [ ] Check SELinux denials
- [ ] Verify configuration file syntax
- [ ] Check port availability

### Service Not Accessible via NGINX

- [ ] Verify service listening on 127.0.0.1
- [ ] Check NGINX configuration syntax
- [ ] Check NGINX error logs
- [ ] Verify SELinux boolean (httpd_can_network_connect)
- [ ] Check DNS resolution
- [ ] Verify firewall rules for ports 80/443

### Permission Denied Errors

- [ ] Check file ownership
- [ ] Check file permissions (especially config files)
- [ ] Check SELinux contexts
- [ ] Check SELinux denials
- [ ] Verify user exists and has correct UID

### Container Won't Start

- [ ] Check Podman version (>= 4.4)
- [ ] Verify user lingering enabled
- [ ] Check XDG_RUNTIME_DIR set correctly
- [ ] Verify Quadlet file syntax
- [ ] Check Kubernetes YAML syntax
- [ ] Verify container images accessible
- [ ] Check volume mount paths exist
- [ ] Check SELinux contexts for volumes

## Summary

Use these checklists systematically for every new role to ensure:
- Consistency across all roles
- No missed integration points
- Proper security configuration
- Complete documentation
- Thorough testing before production use

Remember: It's better to be thorough during development than to troubleshoot issues in production!
