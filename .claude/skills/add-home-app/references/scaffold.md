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
# El único contrato con el home-server es:
#   1. La imagen arranca y queda escuchando en un puerto.
#   2. Declarás ese puerto con EXPOSE (el skill `add-home-app enable` lo lee de acá).
#
# Ejemplo mínimo (un server estático de placeholder) — cambialo por tu stack:
FROM docker.io/library/busybox:stable

WORKDIR /app
RUN printf '%s\n' '<h1>__REPO__ funcionando</h1>' > /app/index.html

# Cambiá el puerto al que use tu app de verdad.
EXPOSE 8080

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
.git
.gitignore
.forgejo
node_modules
dist
build
target
*.md
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
```
