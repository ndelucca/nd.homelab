# Scaffold del modo `init`

Plantillas **fijas** que se escriben en el dir temporal. Sustituir tres placeholders:
- **`__OWNER__`** — owner (default `ndelucca`).
- **`__REPO__`** — **nombre de repo** tal cual (con puntos/guiones si los hay, ej. `nd.market`).
  Va en el path de la **imagen** y en el título/README.
- **`__APP__`** — nombre ansible/service = nombre de repo con `[.-]`→`_` (ej. `nd_market`). Va en
  el target de `home-deploy` (`ssh … __APP__`): es el nombre del service/unit que se reinicia
  (el dispatcher acepta `[a-z0-9_-]`; el nombre de la imagen NO se deriva de acá).

Sin punto ni guión en el nombre, `__REPO__` y `__APP__` coinciden. No adaptar a ninguna tecnología:
el stub es neutro a propósito para que `init` sea 100% determinista.

---

## `Containerfile`

```dockerfile
# Containerfile — STUB de scaffold. Reemplazá esto con el build real de tu app.
#
# Contrato con el home-server (ver CLAUDE.md; incumplirlo NO falla el build, falla el runtime):
#   1. Escucha en un puerto y lo declarás con EXPOSE. OJO: `add-home-app enable` lee ese
#      EXPOSE UNA SOLA VEZ y lo congela en <app>_container_port del lado de nd.homelab.
#      Si después lo cambiás, hay que editar esa var y re-correr el playbook.
#   2. USER 1000:1000 — el data dir del host es 0750 ndelucca y la unit usa UserNS=keep-id.
#   3. El estado persistente va a /data — es el único volumen que monta la unit.
#   4. Arranca SIN variables de entorno — la unit no define Environment=.
#   5. Si la base es `scratch` y hacés HTTPS de salida, copiá los CA certs del stage de build.
#
# Ejemplo mínimo (un server estático de placeholder) — cambialo por tu stack:
FROM docker.io/library/busybox:stable

WORKDIR /app
RUN printf '%s\n' '<h1>__REPO__ funcionando</h1>' > /app/index.html

# Cambiá el puerto al que use tu app de verdad.
EXPOSE 8080

USER 1000:1000
CMD ["httpd", "-f", "-p", "8080", "-h", "/app"]
```

---

## `.forgejo/workflows/deploy.yml`

```yaml
# CI/CD del home-server: build de la imagen -> push al registry de Forgejo -> deploy por SSH.
# Los secrets REGISTRY_TOKEN y DEPLOY_SSH_KEY están a nivel usuario (heredados), no hay que
# setearlos por repo.
#
# NOTA: la imagen 'buildah' no trae Node, así que NO se usa actions/checkout (acción Node);
# se clona el repo con git en un `run:`. El build es con buildah (sin daemon).
name: deploy
on:
  push:
    branches: [master]

jobs:
  build-and-deploy:
    runs-on: buildah              # matchea el label del runner (imagen con buildah + git)
    env:
      IMAGE: git.ndelucca.dedyn.io/__OWNER__/__REPO__
    steps:
      - name: Clonar el repo
        run: |
          git clone --depth 1 --branch "${{ github.ref_name }}" \
            "https://__OWNER__:${{ secrets.REGISTRY_TOKEN }}@git.ndelucca.dedyn.io/${{ github.repository }}.git" src

      - name: Login + build + push
        working-directory: src
        run: |
          echo "${{ secrets.REGISTRY_TOKEN }}" \
            | buildah login -u __OWNER__ --password-stdin git.ndelucca.dedyn.io
          # --isolation chroot: build rootless dentro de un contenedor anidado.
          buildah bud --isolation chroot -t "$IMAGE:latest" -t "$IMAGE:${{ github.sha }}" .
          buildah push "$IMAGE:latest"
          buildah push "$IMAGE:${{ github.sha }}"

      - name: Deploy en el home-server
        run: |
          install -d -m700 ~/.ssh
          install -m600 /dev/stdin ~/.ssh/deploy_key <<< "${{ secrets.DEPLOY_SSH_KEY }}"
          # El forced-command del host (clave en el usuario ndelucca) ignora todo salvo el
          # nombre de la app (= nombre del service/unit, ej. nd_market), que llega en $SSH_ORIGINAL_COMMAND.
          ssh -i ~/.ssh/deploy_key -o StrictHostKeyChecking=accept-new \
              ndelucca@192.168.10.10 __APP__
```

---

## `.gitignore`

```gitignore
# Dependencias / build (ajustar según tu stack)
node_modules/
dist/
build/
target/
__pycache__/
*.pyc
.env
.env.local
```

---

## `.dockerignore`

```dockerignore
# Ojo con los globs de docs: si tu app embebe archivos .md (go:embed, include_str!, importlib),
# ignorarlos a lo ancho del repo rompe el build. Por eso los excluidos van anclados con `/`.
.git
.gitignore
.forgejo
node_modules
dist
build
target
/README.md
/CLAUDE.md
```

---

## `README.md`

```markdown
# __REPO__

Proyecto self-hosted en el home-server (Forgejo + Actions).

## Deploy

- Push a `master` → el workflow buildea la imagen, la pushea al registry de Forgejo
  (`git.ndelucca.dedyn.io/__OWNER__/__REPO__`) y la deploya en el home-server.
- Para exponerlo en la red la primera vez, correr en `nd.homelab` el skill:
  `add-home-app enable __REPO__`.

## Desarrollo

Reemplazá el `Containerfile` stub con el build real de tu app y ajustá el `EXPOSE` al puerto
que use. El resto del pipeline no hace falta tocarlo.

Antes de tocar nada, leé [CLAUDE.md](CLAUDE.md): tiene el contrato con el home-server.
```

---

## `CLAUDE.md`

Se escribe **tal cual** (sólo sustituyendo los placeholders). Es el contrato que el repo de la app
no puede derivar de sí mismo: todo esto vive en `nd.homelab` y rompe en **runtime**, no en build.
No copiar acá la arquitectura del home-server (DNS, TLS, backups) — eso es `nd.homelab/README.md`
y duplicarlo garantiza que se pudra.

```markdown
# __REPO__ — notas de trabajo

App self-hosted que se deploya sola: push a `master` → Forgejo Actions buildea la imagen, la
pushea al registry y reinicia la unit `__APP__` en el home-server.

La infra vive en otro repo: **`~/nd.homelab`** (Ansible). Este archivo *no* repite su
arquitectura —está en `nd.homelab/README.md`— sino sólo lo que **este** repo debe cumplir, y lo
que rompe en silencio si no se cumple.

## El contrato con el home-server

La unit Quadlet que corre esta imagen vive en `nd.homelab/roles/__APP__/`. La imagen tiene que
cumplir esto o la app no arranca:

- **`USER 1000:1000`.** El data dir del host es `0750 ndelucca:ndelucca` y la unit usa
  `UserNS=keep-id:uid=1000`. Como root, el proceso no puede escribir `/data`.
- **El estado va a `/data`.** Es el **único** volumen que monta la unit. Cualquier otra ruta se
  escribe en el layer efímero y se pierde en cada deploy.
- **Tiene que arrancar sin ninguna variable de entorno.** La plantilla Quadlet no define
  `Environment=`: los defaults de la imagen (`ENV …`) son lo único que hay.
- **CA certs.** Si la base es `scratch`/`distroless` y la app hace HTTPS de salida, copiá
  `ca-certificates.crt` desde el stage de build o todos los fetch fallan.

## Lo que rompe en silencio

**`EXPOSE` es un snapshot, no un binding.** El skill `add-home-app enable` lo lee **una sola vez**
y lo congela en `__APP___container_port` (`nd.homelab/roles/__APP__/defaults/main.yml`). Si
cambiás el `EXPOSE`, el pipeline sigue verde y la app queda inalcanzable detrás de un
`PublishPort` que apunta al puerto viejo. Hay que editar esa variable y re-correr el playbook.

**El pipeline no verifica que la app responda.** Un action verde significa "la imagen se buildeó,
se pusheó y systemd reinició la unit". No que la app ande: la unit puede quedar `active` con el
proceso muerto o inalcanzable. Verificá a mano contra `/healthz` (o lo que exponga la app), por
loopback en el server y por HTTPS.

**Los cambios de proxy son cross-repo.** WebSockets, Server-Sent Events, subidas grandes o
timeouts largos necesitan flags en el vhost (`nd.homelab/roles/nginx/defaults/main.yml`:
`websocket`, `location_snippet`, `client_max_body_size`). Sin eso la app carga pero se comporta
raro — SSE bufferado, uploads cortados. Nada del lado de este repo lo detecta.

**El paquete del registry es privado.** El `podman pull` de la unit (`Pull=newer`) funciona porque
`ndelucca` está logueado a mano en el host; no hay tarea de Ansible que lo haga. Si se recrea el
server o se rota el token, el pull falla hasta que alguien vuelva a loguear.

## Nombres (no son el mismo)

| Cosa | Valor |
|------|-------|
| Repo e imagen | `__REPO__` |
| Unit, rol Ansible, target de deploy | `__APP__` |

El `ssh … __APP__` del final del workflow es el **nombre de la unit**. El nombre de la imagen no
se deriva de ahí: vive en el `Image=` del Quadlet.

## Tests

Corrélos **dentro del `Containerfile`** (una stage antes del build): si fallan, no hay imagen ni
deploy. No hay job de tests aparte en el workflow.
```
