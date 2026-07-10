# nd.homelab — notas de trabajo

Ansible para el home server Fedora (`ndelucca-server`, `192.168.10.10`). La arquitectura, la tabla
de servicios y el flujo de backups están en [README.md](README.md); acá van sólo las reglas de
operación que no se deducen leyendo los roles.

## Regla no negociable: `-l ndelucca-server`

Todo comando `ansible` / `ansible-playbook` lleva `-l ndelucca-server`. Sin el flag, el inventario
incluye la Raspberry de la impresora (Debian) y el cliente Acer, y los roles de Fedora explotan
ahí. Ver el skill `ansible-host-limiter`.

```sh
ansible-playbook playbooks/site.yml -l ndelucca-server --check --diff   # dry run primero
ansible-playbook playbooks/site.yml -l ndelucca-server -t nginx         # un solo rol
```

Corré siempre el `--check --diff` antes de aplicar. Es un server de verdad con datos de verdad.

## Skills

- **`ansible-host-limiter`** — la regla de arriba, aplicada a cada comando.
- **`home-server-role-creator`** — convenciones de un rol de container (estructura,
  `container_base`, SELinux, naming `<app>_*`, wiring de NGINX/firewall/DNS). **Fuente de verdad
  de las convenciones.**
- **`add-home-app`** — ciclo de vida de una app deployada por Forgejo Actions: `init` (crea el
  repo con scaffold), `enable` (la expone en la red), `remove` (teardown).

Ante cualquier diferencia entre un snippet de un skill y un rol vivo (`roles/nginx`,
`roles/kavita`, `roles/forgejo`), **manda el rol vivo**.

## Secretos y dominio

- `base_domain` en `group_vars/all/main.yml` es la única fuente de verdad del dominio; todo lo
  demás se deriva. No hardcodees `ndelucca.dedyn.io` en un rol.
- Los secretos son valores `!vault` inline dentro de archivos `vault.yml`, así que
  `ansible-vault view` **no sirve** sobre ellos. Para leer uno, usá el loader:
  ```sh
  ansible localhost -m debug -a 'msg={{ vault_forgejo_api_token }}' \
    -e @inventory/group_vars/all/vault.yml
  ```
- `.vault_pass` está gitignoreado y referenciado desde `ansible.cfg`: no pide password.

## Apps deployadas por Forgejo Actions

Las apps con CI/CD propio (hoy `nd_market`) tienen su código en otro repo y su `CLAUDE.md` con el
contrato de la imagen. Dos cosas que este repo controla y ese no:

- **`<app>_container_port`** (`roles/<app>/defaults/main.yml`) es una **copia congelada** del
  `EXPOSE` del Containerfile, tomada cuando se corrió `add-home-app enable`. Si la app cambia su
  puerto, acá no se entera nadie: la unit queda `active` publicando hacia un puerto muerto y NGINX
  devuelve 502. Ya pasó con `nd_market`.
- **Los flags del vhost** (`roles/nginx/defaults/main.yml`): SSE y WebSockets necesitan
  `proxy_buffering off` / `websocket: true`. El default bufferea, y una app de SSE "anda" pero no
  emite nada.

El `podman pull` de esas units usa `Pull=newer` contra un registry **privado**, y funciona porque
`ndelucca` está logueado a mano en el host. **No hay tarea de Ansible que haga ese login**: si se
reconstruye el server (ver `docs/BOOTSTRAP.md`), hay que rehacerlo o el pull falla en silencio.

## `claude_bridge` — el CLI de Claude para apps containerizadas

El rol `claude_bridge` expone el CLI `claude` del host a los contenedores por un **socket unix**
(`/run/home-claude/sock`), porque una imagen `scratch` no puede llevar el binario (223 MB + glibc)
ni la sesión OAuth de `~/.claude`. Es infra transversal, hermana de `deploy_ssh`. Tres cosas que no
se deducen del rol:

- **El CLI y su login NO los gestiona Ansible.** El rol asume que `ndelucca` ya instaló `claude` en
  `~/.local/bin` y corrió el login OAuth a mano (igual que el `podman login` del registry). El
  `preflight` falla con un mensaje claro si falta el binario o `~/.claude/.credentials.json`. Al
  reconstruir el server (`docs/BOOTSTRAP.md`) hay que rehacer ambos.
- **Serializa TODAS las consultas** con un `flock` (concurrencia efectiva 1). Es a propósito: el CLI
  reescribe `~/.claude/.credentials.json` al refrescar el token y dos escrituras concurrentes lo
  corrompen para todas las apps. No subas la concurrencia sin resolver eso primero.
- **El gate de tools vive en `/etc/home-claude/settings.json`** (deny-list, fuente de verdad no
  spoofeable desde el prompt) y el CLI corre sandboxeado por systemd (HOME vacío salvo `~/.claude`).
  Montar el socket en una app le da acceso a la suscripción: es la frontera de confianza, cuidá
  quién lo monta. Contrato del socket: `.claude/skills/add-home-app/references/claude-bridge.md`.

Las units son de **usuario** (no de sistema) a propósito: el manager de usuario corre como
`unconfined_t` y puede crear el socket con etiqueta `container_file_t`; `init_t` (pid 1) no puede.
Y hay un módulo SELinux puntual (`home-claude.cil`) porque `container_t` no puede `connectto` a un
peer `unconfined_t` sin él.

## Imágenes pinneadas

Las imágenes de los roles de container van con tag explícito (o digest, en Kavita) para que los
deploys sean reproducibles. Para actualizar: subí la variable de versión en el `defaults/main.yml`
del rol y re-corré con su tag. `playbooks/update.yml` reporta qué hay más nuevo upstream.
