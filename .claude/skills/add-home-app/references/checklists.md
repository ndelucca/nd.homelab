# Checklists

## `init` — crear el repo

- [ ] **Nombre confirmado por el usuario** (nunca asumido de un argumento residual del skill).
- [ ] Nombre de repo valida `^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$` (puede llevar puntos: `nd.XXX`).
- [ ] `FJ_TOKEN` obtenido del vault (no vacío).
- [ ] Repo creado vía API (201) o ya existía (409) — ninguno es error.
- [ ] Scaffold escrito en dir temporal del scratchpad (NO en `nd.homelab`), con `__OWNER__`,
      `__REPO__` (nombre de repo) y `__SLUG__` (repo con `.`→`-`) sustituidos.
- [ ] `git init -b master` → add → commit (user fijo del skill) → push a la URL del repo con token.
- [ ] Dir temporal borrado.
- [ ] Reportada la URL del repo y el próximo paso (`enable`).

## `enable` — exponer en la red

- [ ] Prerrequisitos OK: Actions habilitado, runner online, `deploy_ssh_enabled`, secrets a nivel
      usuario (`DEPLOY_SSH_KEY`, `REGISTRY_TOKEN`).
- [ ] Nombres derivados: **slug** (repo con `.`→`-`), **var_prefix** (slug con `-`→`_`),
      **subdominio** (default = slug; override single-label sin punto si el usuario lo pide).
- [ ] Puerto del contenedor inferido del `EXPOSE`; imagen inferida del workflow (path = nombre de repo).
- [ ] Puerto host loopback elegido libre (no colisiona con `nginx_*_port` ni `firewall_blocked`).
- [ ] Rol `roles/<slug>/` creado (defaults, meta, tasks/{main,preflight,quadlet}, template);
      `Image=` usa el **nombre de repo** (con puntos), no el slug.
- [ ] `nginx_<var_prefix>_port` + entrada en `nginx_vhosts` (`subdomain: <subdominio>`) agregadas.
- [ ] Rewrite DNS agregado en `adguard_dns_rewrites` (por `<subdominio>`).
- [ ] Entrada en `firewall_blocked` agregada.
- [ ] `role: <slug>` registrado en `playbooks/site.yml`.
- [ ] Workflow del repo: `ssh … <slug>` (sin punto) coincide con el nombre de la unit.
- [ ] Chicken-and-egg avisado: imagen en el registry antes del primer `podman pull` del playbook.
- [ ] Comando impreso: `ansible-playbook playbooks/site.yml -l ndelucca-server -t <slug>`.
- [ ] Verificado: `https://<subdominio>.ndelucca.dedyn.io` con TLS válido + servicio activo.

## `remove` — teardown

- [ ] Servicio parado/deshabilitado (`systemctl --user -M ndelucca@ disable --now <slug>`).
- [ ] Unit `.container` borrada de `/etc/containers/systemd/users/1000/` + `daemon-reload`.
- [ ] Rol `roles/<slug>/` borrado.
- [ ] Entrada de `nginx_vhosts` + var `nginx_<var_prefix>_port` quitadas (y el `conf.d/*.conf.j2`
      a medida si la app tenía uno).
- [ ] Rewrite DNS (por `<subdominio>`) quitado de `adguard_dns_rewrites`.
- [ ] Entrada de `firewall_blocked` quitada.
- [ ] `role: <slug>` quitado de `playbooks/site.yml`.
- [ ] Re-aplicado: `ansible-playbook playbooks/site.yml -l ndelucca-server -t nginx,adguard,firewall`
      (el `.managed_vhosts` de nginx limpia el vhost huérfano).
- [ ] **Confirmado con el usuario** antes de lo destructivo: data dir bajo `app_data_root`,
      imagen del registry, repo de código, secrets por-repo (si los hubiera).
- [ ] Reportado qué quedó fuera de Ansible (imágenes/paquetes/repo en Forgejo).

## Notas transversales

- Siempre `-l ndelucca-server` en cualquier `ansible-playbook` (skill `ansible-host-limiter`).
- La fuente de verdad son los roles vivos (`roles/nginx`, `roles/firewall`, `roles/forgejo`,
  `roles/kavita`) por sobre estas plantillas si algo difiere.
- El deploy NO necesita cambios por-app: el dispatcher `home-deploy` (rol `deploy_ssh`) valida el
  slug contra las units de usuario gestionadas.
