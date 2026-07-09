# Checklists

## `init` — crear el repo

- [ ] **Nombre confirmado por el usuario** (nunca asumido de un argumento residual del skill).
- [ ] Nombre de repo valida `^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$` (puede llevar puntos: `nd.XXX`).
- [ ] `FJ_TOKEN` obtenido del vault (no vacío).
- [ ] Repo creado vía API (201) o ya existía (409) — ninguno es error.
- [ ] Scaffold escrito en dir temporal del scratchpad (NO en `nd.homelab`), con `__OWNER__`,
      `__REPO__` (nombre de repo) y `__APP__` (repo con `[.-]`→`_`) sustituidos.
- [ ] `git init -b master` → add → commit (user fijo del skill) → push a la URL del repo con token.
- [ ] Dir temporal borrado.
- [ ] Reportada la URL del repo y el próximo paso (`enable`).

## `enable` — exponer en la red

- [ ] Prerrequisitos OK: Actions habilitado, runner online, `deploy_ssh_enabled`, secrets a nivel
      usuario (`DEPLOY_SSH_KEY`, `REGISTRY_TOKEN`).
- [ ] Nombres derivados: **`__APP__`** (repo con `[.-]`→`_` — rol/vars/service/target de deploy),
      **`__REPO__`** (imagen), **`__SUB__`** (subdominio; default = repo con `[._]`→`-`, override single-label).
- [ ] Puerto del contenedor inferido del `EXPOSE`; imagen inferida del workflow (path = nombre de repo).
- [ ] Puerto host loopback elegido libre (no colisiona con `nginx_*_port` ni `firewall_blocked`).
- [ ] Rol `roles/__APP__/` creado (defaults, meta, tasks/{main,preflight,quadlet}, template);
      `Image=` usa el **nombre de repo** (con puntos), no `__APP__`.
- [ ] `nginx___APP___port` + entrada en `nginx_vhosts` (`subdomain: <__SUB__>`) agregadas.
- [ ] Rewrite DNS agregado en `adguard_dns_rewrites` (por `<__SUB__>`).
- [ ] Entrada en `firewall_blocked` agregada.
- [ ] `role: __APP__` registrado en `playbooks/site.yml`.
- [ ] Workflow del repo: `ssh … __APP__` coincide con el nombre de la unit (no el nombre de repo).
- [ ] Chicken-and-egg avisado: imagen en el registry antes del primer pull de la unit.
- [ ] Comando impreso: `ansible-playbook playbooks/site.yml -l ndelucca-server -t __APP__`.
- [ ] Verificado: `https://<__SUB__>.ndelucca.dedyn.io` con TLS válido + servicio activo.

## `remove` — teardown

- [ ] Servicio parado/deshabilitado (`systemctl --user -M ndelucca@ disable --now __APP__`).
- [ ] Unit `.container` borrada de `/etc/containers/systemd/users/1000/` + `daemon-reload`.
- [ ] Rol `roles/__APP__/` borrado.
- [ ] Entrada de `nginx_vhosts` + var `nginx___APP___port` quitadas (y el `conf.d/*.conf.j2`
      a medida si la app tenía uno).
- [ ] Rewrite DNS (por `<__SUB__>`) quitado de `adguard_dns_rewrites`.
- [ ] Entrada de `firewall_blocked` quitada.
- [ ] `role: __APP__` quitado de `playbooks/site.yml`.
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
