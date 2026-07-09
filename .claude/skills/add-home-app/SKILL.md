---
name: add-home-app
description: Ciclo de vida completo de una app self-hosted deployada por Forgejo Actions en el home-server. Tres modos deterministas — init (crea el repo de código en Forgejo desde cero con scaffold), enable (expone la app en la red: rol Ansible + NGINX + AdGuard + firewall + deploy SSH), remove (teardown completo). Usar cuando el usuario quiera iniciar un proyecto nuevo en Forgejo, habilitar/exponer una app en la red, o borrarla. Reusa las convenciones del skill home-server-role-creator.
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# add-home-app

Punto de entrada único del ciclo de vida de una app del home-server que se buildea/deploya
vía Forgejo Actions. **Determinista por diseño**: el mismo scaffold y la misma secuencia de
comandos siempre; lo único que varía son los datos (nombre, puerto, imagen) inferidos o
preguntados. No inventes pasos ni cambies el orden.

## Modos

- **`init <nombre>`** — crea el repositorio de código en Forgejo desde cero (scaffold + commit
  en `master` + push que crea el repo). Es el **paso 1** de un proyecto nuevo.
- **`enable <nombre>`** — hace toda la "plomería" de red para exponer la app (rol de la app,
  NGINX, AdGuard, firewall, deploy SSH). Es el **paso 2**, cuando la app ya está lista.
- **`remove <nombre>`** — teardown completo: revierte todo lo que hizo `enable`.

Si el usuario no aclara el modo, inferilo del pedido ("crear/nuevo repo" → init; "exponer/
publicar/habilitar" → enable; "borrar/quitar/eliminar" → remove) o preguntá con una sola
pregunta.

## Relación con otros skills

Para las convenciones de un rol de container (estructura, `container_base`, SELinux, naming
`<app>_*`, integración NGINX/firewall/DNS) la fuente es **`home-server-role-creator`**. Este
skill no las duplica: las aplica y agrega el bootstrap del repo y el teardown. La **fuente de
verdad son los roles vivos** (`roles/nginx`, `roles/firewall`, `roles/forgejo`, `roles/kavita`)
por sobre cualquier snippet — leelos si algo difiere.

## Prerrequisitos (una sola vez, no por-app)

Antes de que `enable` sirva de algo, la infra de Actions tiene que estar puesta (ver el plan
del repo / `roles/forgejo_runner` + `roles/deploy_ssh`):
- Forgejo Actions habilitado (`forgejo_actions_enabled: true`) y runner registrado.
- `deploy_ssh_enabled: true` + `deploy_ssh_public_key` seteados, canal `home-deploy` desplegado.
- Secrets **a nivel usuario** en Forgejo: `DEPLOY_SSH_KEY` y `REGISTRY_TOKEN`. NO se setean a
  mano: el rol `forgejo_runner` (tasks/secrets.yml) los **empuja desde el vault** en cada corrida
  (`deploy_ssh_private_key` y `vault_forgejo_api_token`), así son reproducibles. Al ser a nivel
  usuario los heredan todos los repos, así que `init` no toca secrets.

Si falta algo de esto, avisá al usuario y no sigas con `enable`.

## Constantes del entorno (no preguntar)

- Owner por defecto: `ndelucca`
- Dominio: `git.<nginx_domain>` = `git.ndelucca.dedyn.io`
- Registry: mismo dominio (`git.ndelucca.dedyn.io/<owner>/<app>`)
- IP de LAN del server: `192.168.10.10`
- Branch por defecto: `master`

## Derivación de nombres (repos con punto: `nd.XXX`, `nd.xxx.xxx`)

El usuario suele nombrar los repos con puntos (`nd.market`, `nd.foo.bar`). El punto es válido
como nombre de repo y como path de imagen OCI, pero **NO** como nombre de rol/variable Ansible
(ansible-lint exige `^[a-z][a-z0-9_]*$`) ni de subdominio (el cert wildcard cubre un solo label).
La convención de la casa para roles y services es **guión_bajo** (`home_assistant`,
`cloud_torrent`). Por eso de un nombre de repo `R` se derivan **tres** nombres, deterministas:

| Nombre | Regla | Se usa en | Ej. `nd.market` | Ej. `nd.foo.bar` |
|--------|-------|-----------|-----------------|------------------|
| **`__REPO__`** (repo/imagen) | `R` tal cual | nombre del repo Forgejo y **solo** el path de la imagen (`git.{{ nginx_domain }}/<owner>/R`) | `nd.market` | `nd.foo.bar` |
| **`__APP__`** (nombre ansible/service) | `R` con `[.-]`→`_` | dir del rol, prefijo de vars, container, service/unit y **target de `home-deploy`**. Cumple `^[a-z][a-z0-9_]*$` | `nd_market` | `nd_foo_bar` |
| **`__SUB__`** (subdominio) | default = `R` con `[._]`→`-` | NGINX vhost + rewrite DNS. Single-label DNS; se puede override | `market` (elegido) | `nd-foo-bar` |

- **Validación del nombre de repo**: `^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$` (minúsculas; puede tener
  puntos, guiones o guiones bajos internos). `__APP__` derivado siempre cumple `^[a-z][a-z0-9_]*$`.
- **`home-deploy` acepta `[a-z0-9_-]`** como nombre de app (= nombre de unit). El nombre de la
  **imagen no se deriva** del nombre de la app: vive en el `Image=` de la unit Quadlet, que
  `home-deploy` reinicia con `Pull=newer`. Así el repo (`nd.market`) y la app (`nd_market`) difieren
  sin romper el deploy.
- **Sin punto ni guión** (`R` = `miapp`): los tres coinciden (`miapp`). Con guión (`R` = `mi-app`):
  `__REPO__`=`mi-app`, `__APP__`=`mi_app`, `__SUB__`=`mi-app`.
- **Subdominio**: single-label sin punto (wildcard TLS). El subdominio y el nombre del service NO
  tienen que coincidir (NGINX proxya `<sub>.` → el puerto loopback del service).

## Token de API de Forgejo (para init y para setear secrets)

Se lee del vault del repo (nunca se hardcodea). El archivo `all/vault.yml` es YAML plano con
valores `!vault` inline, así que `ansible-vault view` NO sirve; usar el loader de Ansible
(host-free, sin SSH). Desde la raíz de `nd.homelab`:

```sh
FJ_TOKEN=$(ansible localhost -m debug -a 'msg={{ vault_forgejo_api_token }}' \
  -e @inventory/group_vars/all/vault.yml 2>/dev/null \
  | sed '1s/.*=> //' | python3 -c 'import sys,json;print(json.load(sys.stdin)["msg"])')
```

(`.vault_pass` está en `ansible.cfg`, así que no pide password.) Si sale vacío, el token no
está vaulteado: crearlo con scopes `write:repository` + `write:package` + `write:user`
(este último es necesario para crear repos vía `POST /user/repos`) y agregarlo con
`ansible-vault encrypt_string --stdin-name vault_forgejo_api_token` a `all/vault.yml`.

---

## Modo `init <nombre>`

Crea el repo y lo llena con el scaffold fijo. Secuencia exacta (cada paso idempotente):

1. **Resolver datos**: `owner` (default `ndelucca`), `nombre` de repo (validar
   `^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$` — puede llevar puntos, ver "Derivación de nombres"),
   visibilidad (**default private**), descripción (opcional). Preguntar solo si falta algo
   esencial. **Nunca asumas el nombre** (p.ej. de un argumento residual del skill): si no viene
   claro en el pedido del usuario, preguntalo.

2. **Crear el repo vía API** (idempotente: 201 crea, 409 = ya existe, no es error):
   ```sh
   curl -fsS -X POST "https://git.ndelucca.dedyn.io/api/v1/user/repos" \
     -H "Authorization: token $FJ_TOKEN" -H "Content-Type: application/json" \
     -d '{"name":"<nombre>","private":true,"default_branch":"master","auto_init":false}' \
     -o /dev/null -w '%{http_code}\n'   # aceptar 201 o 409
   ```

3. **Escribir el scaffold** en un dir temporal del scratchpad (NO dentro de `nd.homelab`).
   Usar exactamente las plantillas de `references/scaffold.md`, sustituyendo `__OWNER__`,
   `__REPO__` (nombre de repo, con puntos si los hay — va en la imagen y el título) y `__APP__`
   (nombre de repo con `[.-]`→`_`, va en el target de `home-deploy` = nombre del service/unit).
   Sin punto ni guión ambos coinciden:
   ```
   <tmp>/<nombre>/
   ├── Containerfile
   ├── .forgejo/workflows/deploy.yml
   ├── .gitignore
   ├── .dockerignore
   └── README.md
   ```

4. **Commit inicial en master y push** (con user fijo del skill, para no depender del git
   config del host):
   ```sh
   cd <tmp>/<nombre>
   git init -b master
   git add -A
   git -c user.name='home-server' -c user.email='home-server@ndelucca.dedyn.io' \
       commit -m 'chore: scaffold inicial'
   git -c http.extraHeader="Authorization: token $FJ_TOKEN" \
       push "https://git.ndelucca.dedyn.io/<owner>/<nombre>.git" master
   ```

5. **Borrar el dir temporal.**

6. **Reportar**: URL del repo (`https://git.ndelucca.dedyn.io/<owner>/<nombre>`) y el siguiente
   paso (desarrollar; cuando esté listo para la red, correr `enable <nombre>`). Recordá que el
   `Containerfile` es un stub: hay que reemplazarlo con la app real.

**Determinismo**: el scaffold es SIEMPRE idéntico y neutro (sin lenguaje). No adaptes el
Containerfile a ninguna tecnología — el usuario elige el stack llenándolo.

---

## Modo `enable <nombre>`

Expone la app en la red. Ver `references/app-role.md` para todas las plantillas y
`references/checklists.md` para la checklist completa.

### 1. Descubrir lo que necesita (inferir primero, preguntar lo que falte)

Cloná/leé el repo Forgejo (o pedí la ruta si ya está local) e inferí:
- **Puerto del contenedor**: `EXPOSE` del `Containerfile`.
- **Imagen**: del `.forgejo/workflows/deploy.yml` (`git.ndelucca.dedyn.io/<owner>/<app>`).
- **Volúmenes / env / proxy especial** (websocket, SSE, body size): README / compose si hay.

Datos y defaults (ver "Derivación de nombres" para repos con punto):
| Dato | Default / inferencia |
|------|----------------------|
| `__REPO__` (repo/imagen) | nombre del repo tal cual (puntos OK); la imagen sale del workflow |
| `__APP__` (ansible/service) | repo con `[.-]`→`_` — rol, vars, container, service/unit, target de deploy |
| `__SUB__` (subdominio) | default = repo con `[._]`→`-`; override a label corto si el usuario lo pide (ej. `market`) |
| puerto del contenedor | `EXPOSE` |
| puerto host (loopback) | el siguiente libre; nueva var `nginx___APP___port` |
| proxy especial | inferido |
| volúmenes/env/secrets | del repo o preguntando |

Solo usá `AskUserQuestion` para lo que no puedas inferir.

### 2. Aplicar los cambios (todo edits a este repo)

Ojo con tres cosas (detalladas en `references/app-role.md`):
- **Naming**: rol/vars/container/service/target-de-deploy usan `__APP__` (repo con `[.-]`→`_`,
  guión_bajo); la **imagen** usa el **nombre de repo** (`__REPO__`, con puntos); el **subdominio**
  usa `__SUB__`. Ej. `nd.market` → `__APP__`=`nd_market`, imagen `nd.market`, `__SUB__`=`market`.
- **Deploy target**: la última línea del workflow (`ssh … <app>`) debe ser `__APP__` (= nombre de
  la unit). `home-deploy` acepta `[a-z0-9_-]` y NO deriva la imagen del nombre (la lee del `Image=`
  de la unit). Si el scaffold quedó con el nombre de repo (con punto), corregilo a `__APP__`.
- **Pull privado**: si el paquete es privado, `ndelucca` necesita estar logueado al registry en el
  host para que el `podman pull` de la unit (Quadlet `Pull=newer`, corre como ndelucca) funcione.
  Con paquete público el pull es anónimo y no hace falta login. Ver la sección final de `app-role.md`.

En orden (detalle y plantillas en `references/app-role.md`):
1. **Crear el rol `roles/__APP__/`** (Quadlet: `Image=` con el **nombre de repo**, publish en
   `127.0.0.1:<hostport>`, volúmenes `:Z`, SELinux vía `container_base`).
2. **NGINX**: agregar `nginx___APP___port` y una entrada en `nginx_vhosts`
   (`roles/nginx/defaults/main.yml`) con `subdomain: <__SUB__>`.
3. **AdGuard DNS**: agregar el rewrite en `adguard_dns_rewrites`
   (`inventory/group_vars/homeservers/services.yml`) → `<__SUB__>.{{ nginx_domain }}` → `192.168.10.10`.
4. **Firewall**: agregar la entrada en `firewall_blocked` (`roles/firewall/defaults/main.yml`).
5. **site.yml**: registrar `roles/__APP__/` (elegí una posición razonable entre las apps).
6. **Deploy**: `deploy_ssh` ya es genérico (el dispatcher `home-deploy` valida por unit), así
   que NO hay que tocar nada por-app para el deploy — solo confirmá que `deploy_ssh_enabled`
   está activo y que el workflow del repo hace `ssh ndelucca@192.168.10.10 __APP__` (= nombre del
   service/unit). La clave de deploy vive en el usuario ndelucca, con forced-command.

### 3. Cerrar

- Recordá el **chicken-and-egg**: la imagen debe existir en el registry antes del primer
  `ansible-playbook` (la unit hace `podman pull` al arrancar). Si aún no se pusheó, buildear/
  pushear una vez a mano, o el usuario hace un primer push que dispare el workflow (build+push) —
  pero el `home-deploy` (restart) fallará hasta que la unit exista. Orden recomendado: primer push
  (crea la imagen) → correr el playbook (crea la unit + expone) → los pushes siguientes reinician solos.
- Imprimí el comando exacto:
  `ansible-playbook playbooks/site.yml -l ndelucca-server -t __APP__`
  (siempre con `-l ndelucca-server`, ver skill `ansible-host-limiter`).
- Verificación: `https://<__SUB__>.ndelucca.dedyn.io` responde con TLS válido;
  `systemctl --user -M ndelucca@ status __APP__` activo.

---

## Modo `remove <nombre>`

Teardown completo. Ver `references/checklists.md` (checklist de teardown). Orden:

1. **Parar/deshabilitar y borrar la unit** (antes de borrar el rol, para poder usar sus vars):
   ```sh
   systemctl --user -M ndelucca@ disable --now __APP__ || true
   sudo rm -f /etc/containers/systemd/users/1000/__APP__.container
   sudo -u ndelucca XDG_RUNTIME_DIR=/run/user/1000 systemctl --user daemon-reload
   ```
2. **Revertir los edits de `enable`** (con Edit, quitando exactamente lo agregado):
   - Borrar el rol `roles/__APP__/`.
   - Quitar la entrada de `nginx_vhosts` y la var `nginx___APP___port` (`roles/nginx/defaults`).
     El mecanismo `.managed_vhosts` de `roles/nginx` limpia el vhost huérfano al re-correr nginx.
     Si la app tenía un vhost a medida (`conf.d/<algo>.conf.j2`), borrá ese archivo también.
   - Quitar el rewrite de `adguard_dns_rewrites` (por `<__SUB__>`).
   - Quitar la entrada de `firewall_blocked`.
   - Quitar el `role: __APP__` de `playbooks/site.yml`.
3. **Re-aplicar** para que la limpieza tome efecto:
   `ansible-playbook playbooks/site.yml -l ndelucca-server -t nginx,adguard,firewall`
4. **Destructivo — confirmar con el usuario antes**:
   - Borrar el data dir bajo `app_data_root` (`{{ app_data_root }}/__APP__`).
   - Borrar el paquete/imagen del registry de Forgejo (API `DELETE /packages/...`; el nombre del
     paquete es el **nombre de repo**, con puntos si los hay).
   - Borrar el repo de código en Forgejo si el usuario lo pide (API `DELETE /repos/<owner>/<repo>`,
     con el **nombre de repo** tal cual, puntos incluidos).
5. **Reportar** qué quedó fuera de Ansible (imágenes, repo, secrets si eran por-repo).

---

## Reference files

- **`references/scaffold.md`** — plantillas fijas del `init` (Containerfile, deploy.yml,
  .gitignore, .dockerignore, README).
- **`references/app-role.md`** — plantillas del `enable`: rol de la app completo + snippets de
  NGINX/DNS/firewall/site.yml.
- **`references/checklists.md`** — checklists de enable y de teardown.
