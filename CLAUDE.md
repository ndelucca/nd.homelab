# nd.homelab — notas de trabajo

Ansible para el home server Fedora (`ndelucca-server`, `192.168.10.10`). La arquitectura, la tabla
de servicios y el flujo de backups están en [README.md](README.md); acá van sólo las reglas de
operación que no se deducen leyendo los roles.

## Regla: `-l ndelucca-server` en todo comando

```sh
ansible-playbook playbooks/site.yml -l ndelucca-server --check --diff   # dry run primero
ansible-playbook playbooks/site.yml -l ndelucca-server -t nginx         # un solo rol
```

Qué protege de verdad, porque no es lo que parece: **la barrera principal es el `hosts:` del
play**, no el flag. Los seis playbooks del server ya están acotados a `hosts: homeservers`, que
tiene un único miembro, así que ahí el `-l` es redundante. Sumale los `assert` de preflight que
verifican el SO. El `-l` es la única barrera real en dos casos:

- **`playbooks/hosts.yml`**, el único con `hosts: all:!{{ local_host }}`.
- **Comandos ad-hoc** (`ansible <patrón> -m ...`), donde el patrón lo ponés vos.

Usalo igual siempre: no cuesta nada y evita tener que recordar en cuál de los dos casos estás.
Ver el skill `ansible-host-limiter`.

Corré siempre el `--check --diff` antes de aplicar. Es un server de verdad con datos de verdad.

### Qué NO valida `--check`

El dry-run cubre menos de lo que sugiere. Tres puntos ciegos conocidos:

- **`command`/`shell` no corren**: devuelven un stub con `rc: 0` y `stdout: ""`. Todo `when:`
  que dependa de un register de esos evalúa contra valores falsos. Los guards del repo usan
  `not (<reg>.skipped | default(false))`; si agregás un chequeo nuevo, seguí ese patrón.
- **Un bump de imagen da verde falso**: ningún Quadlet tiene `Pull=`, así que la imagen nueva
  se baja recién en el `start` del unit. En `--check` el template dice "changed", los handlers
  no corren y el `wait_for` del puerto pasa contra el servicio VIEJO. **Pre-pulleá a mano.**
- **Los handlers no se disparan**, así que nada de lo que dependa de un restart se verifica.

## Skills

- **`ansible-host-limiter`** — la regla de arriba, aplicada a cada comando.
- **`home-server-role-creator`** — convenciones de un rol de container (estructura,
  `container_base`, SELinux, naming `<app>_*`, wiring de NGINX/firewall/DNS). **Fuente de verdad
  de las convenciones.**
- **`add-home-app`** — ciclo de vida de una app deployada por Forgejo Actions: `init` (crea el
  repo con scaffold), `enable` (la expone en la red), `remove` (teardown).

Ante cualquier diferencia entre un snippet de un skill y un rol vivo (`roles/nginx`,
`roles/kavita`, `roles/forgejo`), **manda el rol vivo**.

## Puertos: viven en `services.yml`, no en los defaults del rol

`ansible.cfg` usa **`private_role_vars = True`**: los defaults de un rol **NO** son visibles
desde otro. Un `{{ kavita_port | default(5000) }}` escrito en `roles/nginx/defaults` cae
*siempre* al literal 5000 sin avisar — parece cableado y no lo está.

Por eso el puerto canónico de cada servicio vive en
`inventory/group_vars/homeservers/services.yml` (las vars de inventario sí son de scope
global), y `roles/nginx` + `roles/firewall` derivan de ahí. Cada rol conserva su propio
default con el mismo valor para seguir siendo usable solo.

**Al cambiar un puerto: se cambia en `services.yml` y listo.** NGINX y el firewall lo siguen.
Si lo cambiás sólo en el rol de la app, NGINX proxea a un puerto muerto (502) y el firewall
bloquea el viejo dejando abierto el nuevo. Ya pasó con `nd_market`.

La misma trampa aplica a cualquier var que un rol quiera leer de otro: si no está en el
inventario, no la ve.

## Secretos y dominio

- `base_domain` en `group_vars/all/main.yml` es la única fuente de verdad del dominio; todo lo
  demás se deriva. No hardcodees `ndelucca.dedyn.io` en un rol.
- **Convención**: toda clave de un `vault.yml` lleva el prefijo `vault_`, y `services.yml`
  la mapea a la variable que consume el rol (`immich_db_password: "{{ vault_immich_db_password }}"`).
  Así al leer un rol se ve de un vistazo qué sale del vault y qué es config en texto plano.
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

## fcontext de SELinux: gana la ÚLTIMA regla, no la más específica

En `file_contexts.local` (lo que escribe `sefcontext` / `semanage fcontext -a`), cuando varias
reglas matchean un path **gana la última en el archivo**, que es la que se registró más tarde. NO
gana la más específica. Es contraintuitivo y no se ve leyendo los roles.

Importa porque hay reglas amplias que tapan a las de abajo:

- `filebrowser` registra `/srv/disks(/.*)?` → `public_content_rw_t` (a propósito: es un file
  manager nativo cuya raíz es el disco entero).
- Todos los volumes de container abajo de ahí (`appdata/*`, `media/Gallery`, `media/Books`)
  necesitan `container_file_t`, y sólo sobreviven porque se registraron **después**.

Si una regla amplia queda registrada después de una específica, la tapa; el `restorecon -R` del
handler de ese rol repinta el volume con la etiqueta amplia y, como `container_read_public_content`
y `container_manage_public_content` están **off**, `container_t` deja de poder leer su propio
volume: el backend entra en crash-loop y NGINX devuelve **502**. Los permisos Unix se ven perfectos
y `ausearch` no muestra nada (son denials `dontaudit`), así que el síntoma despista.

Le pasó a Immich en jul-2026: `media/Gallery` había quedado registrado antes que la regla de
filebrowser. Diagnóstico rápido —

```sh
selabel_lookup -b file -k <path>   # qué etiqueta resuelve HOY (matchpathcon usa caché, no confíes)
grep -n "srv/disks" /etc/selinux/targeted/contexts/files/file_contexts.local   # el orden real
```

**Los roles de container se auto-reparan.** `container_base/tasks/selinux.yml` chequea con
`selabel_lookup` si cada path de `container_base_selinux_paths` sigue resolviendo a
`container_file_t` y, si quedó tapado, borra y re-agrega la regla para moverla al final. El orden
de registro dejó de importar para ellos: alcanza con correr el rol. `state: present` solo NO
arregla esto, porque la regla existe — lo que está mal es su posición.

Los roles de reglas amplias (`filebrowser`, `cloud_torrent`) corren antes que los de container en
`site.yml`, así que en un host limpio el orden ya sale bien; el guard cubre los hosts con historia.

Al agregar un rol: **nunca etiquetes un directorio padre compartido**, etiquetá sólo los
subdirectorios propios (por eso `jellyfin` lista `Movies`/`Series` en vez del media root). Y no
pongas un `state: absent` sobre una regla amplia: `cloud_torrent` posee legítimamente la del media
root y las corridas se pelearían entre sí.

## Imágenes pinneadas

Las imágenes de los roles de container van con tag explícito (o digest, en Kavita) para que los
deploys sean reproducibles. Para actualizar: subí la variable de versión en el `defaults/main.yml`
del rol y re-corré con su tag. `playbooks/update.yml` reporta qué hay más nuevo upstream.
