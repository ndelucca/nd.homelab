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
como nombre de repo y como path de imagen OCI, pero **NO** como nombre de unit systemd, de
contenedor, de subdominio (el cert wildcard cubre un solo label) ni de variable Ansible. Por eso
de un nombre de repo `R` se derivan **tres** nombres, de forma 100% determinista:

| Nombre | Regla | Se usa en | Ej. `nd.market` | Ej. `nd.foo.bar` |
|--------|-------|-----------|-----------------|------------------|
| **repo / imagen** | `R` tal cual (puntos OK) | nombre del repo Forgejo y **solo** el path de la imagen (`git.{{ nginx_domain }}/<owner>/R`) | `nd.market` | `nd.foo.bar` |
| **slug** | `R` con cada `.` → `-` | dir del rol, container, service/unit, **target de `home-deploy`** y subdominio por defecto. Siempre cumple `^[a-z0-9-]+$` | `nd-market` | `nd-foo-bar` |
| **var_prefix** | slug con `-` → `_` | prefijo de las variables Ansible | `nd_market` | `nd_foo_bar` |

- **Validación del nombre de repo**: `^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$` (minúsculas; puede tener
  puntos, guiones o guiones bajos internos). El **slug derivado siempre** cumple `^[a-z0-9-]+$`,
  que es lo que exige el dispatcher `home-deploy` (rechaza puntos).
- **Sin punto** (`R` = `mi-app`): los tres nombres coinciden (`mi-app` / `mi-app` / `mi_app`), así
  que el flujo viejo no cambia.
- **Subdominio**: por defecto = slug. Se puede override a un label más corto (ej. `nd.market` →
  subdominio `market`), pero **siempre single-label sin punto** por el wildcard TLS. El subdominio
  y el nombre del service NO tienen que coincidir (NGINX proxya `<sub>.` → el puerto loopback del
  service, se llame como se llame).

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
   `__REPO__` (nombre de repo, con puntos si los hay — va en la imagen y el título) y `__SLUG__`
   (nombre de repo con `.`→`-`, va en el target de `home-deploy` porque no admite puntos). Sin
   punto ambos coinciden:
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
| repo / imagen | nombre del repo tal cual (puntos OK); la imagen sale del workflow |
| slug | repo con `.`→`-` (cumple `^[a-z0-9-]+$`) — rol, container, service, target de deploy |
| var_prefix | slug con `-`→`_` — prefijo de vars Ansible |
| subdominio | = slug; override a label corto sin punto si el usuario lo pide (ej. `market`) |
| puerto del contenedor | `EXPOSE` |
| puerto host (loopback) | el siguiente libre; nueva var `nginx_<var_prefix>_port` |
| proxy especial | inferido |
| volúmenes/env/secrets | del repo o preguntando |

Solo usá `AskUserQuestion` para lo que no puedas inferir.

### 2. Aplicar los cambios (todo edits a este repo)

Ojo con tres cosas (detalladas en `references/app-role.md`):
- **Naming**: dir/container/service/subdominio usan el **slug** (`__SLUG__`, con `.`→`-`); la
  **imagen** usa el **nombre de repo** (`__REPO__`, con puntos si los hay); las **variables
  Ansible** usan el **var_prefix** (`__VAR__`, con `-`→`_`). Ej. `nd.market` → slug `nd-market`,
  repo/imagen `nd.market`, vars `nd_market_*`. Sin punto los tres coinciden (`hello-home` → vars
  `hello_home_*`, imagen `hello-home`).
- **Deploy target**: la última línea del workflow (`ssh … <slug>`) y el nombre de la unit deben
  ser el **slug** (sin punto), porque el dispatcher `home-deploy` valida `^[a-z0-9-]+$`. Si el
  repo tiene punto y el scaffold quedó con el nombre de repo ahí, corregilo al slug.
- **Pull privado**: si el paquete es privado, `ndelucca` necesita estar logueado al registry en
  el host para que `podman pull` (unit + `home-deploy`) funcione. Ver la sección final de
  `app-role.md`.

En orden (detalle y plantillas en `references/app-role.md`):
1. **Crear el rol `roles/<slug>/`** (Quadlet: `Image=` con el **nombre de repo**, publish en
   `127.0.0.1:<hostport>`, volúmenes `:Z`, SELinux vía `container_base`).
2. **NGINX**: agregar `nginx_<var_prefix>_port` y una entrada en `nginx_vhosts`
   (`roles/nginx/defaults/main.yml`) con `subdomain: <subdominio>`.
3. **AdGuard DNS**: agregar el rewrite en `adguard_dns_rewrites`
   (`inventory/group_vars/homeservers/services.yml`) → `<subdominio>.{{ nginx_domain }}` → `192.168.10.10`.
4. **Firewall**: agregar la entrada en `firewall_blocked` (`roles/firewall/defaults/main.yml`).
5. **site.yml**: registrar `roles/<slug>/` (elegí una posición razonable entre las apps).
6. **Deploy**: `deploy_ssh` ya es genérico (el dispatcher `home-deploy` valida por unit), así
   que NO hay que tocar nada por-app para el deploy — solo confirmá que `deploy_ssh_enabled`
   está activo y que el workflow del repo hace `ssh ndelucca@192.168.10.10 <slug>` (slug = nombre
   del service; sin punto). La clave de deploy vive en el usuario ndelucca, con forced-command.

### 3. Cerrar

- Recordá el **chicken-and-egg**: la imagen debe existir en el registry antes del primer
  `ansible-playbook` (que hace `podman pull`). Si aún no se pusheó, buildear/pushear una vez
  a mano, o el usuario hace un primer push que dispare el workflow (build+push) — pero el
  restart fallará hasta que la unit exista. Orden recomendado: primer push (crea la imagen) →
  correr el playbook (crea la unit + expone) → los pushes siguientes ya reinician solos.
- Imprimí el comando exacto:
  `ansible-playbook playbooks/site.yml -l ndelucca-server -t <slug>`
  (siempre con `-l ndelucca-server`, ver skill `ansible-host-limiter`).
- Verificación: `https://<subdominio>.ndelucca.dedyn.io` responde con TLS válido;
  `systemctl --user -M ndelucca@ status <slug>` activo.

---

## Modo `remove <nombre>`

Teardown completo. Ver `references/checklists.md` (checklist de teardown). Orden:

1. **Parar/deshabilitar y borrar la unit** (antes de borrar el rol, para poder usar sus vars):
   ```sh
   systemctl --user -M ndelucca@ disable --now <slug> || true
   sudo rm -f /etc/containers/systemd/users/1000/<slug>.container
   sudo -u ndelucca XDG_RUNTIME_DIR=/run/user/1000 systemctl --user daemon-reload
   ```
2. **Revertir los edits de `enable`** (con Edit, quitando exactamente lo agregado):
   - Borrar el rol `roles/<slug>/`.
   - Quitar la entrada de `nginx_vhosts` y la var `nginx_<var_prefix>_port` (`roles/nginx/defaults`).
     El mecanismo `.managed_vhosts` de `roles/nginx` limpia el vhost huérfano al re-correr nginx.
     Si la app tenía un vhost a medida (`conf.d/<algo>.conf.j2`), borrá ese archivo también.
   - Quitar el rewrite de `adguard_dns_rewrites` (por `<subdominio>`).
   - Quitar la entrada de `firewall_blocked`.
   - Quitar el `role: <slug>` de `playbooks/site.yml`.
3. **Re-aplicar** para que la limpieza tome efecto:
   `ansible-playbook playbooks/site.yml -l ndelucca-server -t nginx,adguard,firewall`
4. **Destructivo — confirmar con el usuario antes**:
   - Borrar el data dir bajo `app_data_root` (`{{ app_data_root }}/<slug>`).
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
