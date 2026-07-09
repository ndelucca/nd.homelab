# forgejo_runner

Despliega un runner de **Forgejo Actions** (act_runner / `forgejo-runner`) como contenedor
rootless/Quadlet, siguiendo el patrón de `roles/forgejo` + `container_base`.

## Qué hace

- Instala Podman (vía `container_base`) y habilita el **socket de la API de Podman** del usuario.
- Obtiene un **token de registro** de la CLI del contenedor de Forgejo (o de Vault) y **registra**
  el runner (idempotente: solo si no existe `.runner`).
- Despliega el daemon como servicio de usuario systemd, con `config.yml` apuntando al socket de
  Podman para spawnear el contenedor de cada job.

Es **saliente puro**: marca contra la instancia de Forgejo para buscar jobs. No expone puertos,
así que **no toca firewall, NGINX ni DNS**.

## Requisitos

- El rol `forgejo` debe correr antes (el runner toma el token de su CLI). Ya está ordenado así en
  `playbooks/site.yml`.
- `forgejo_actions_enabled: true` en el rol forgejo (default).
- Activar con `forgejo_runner_enabled: true` en `group_vars` (default false).
- **Verificar y pinear** `forgejo_runner_version` con el tag stable actual de
  `code.forgejo.org/forgejo/runner` antes de aplicar.

## Decisiones de red/SELinux (aprendidas en el deploy)

Un contenedor rootless con red default **no alcanza los servicios del propio host** (Forgejo en
la LAN) — el registro se cuelga. Por eso:
- El daemon y el registro usan `Network=host` (`--network=host`), y los jobs `container.network:
  host` en `config.yml`, para poder llegar a Forgejo (clonar, reportar, registrar).
- El `podman run` de registro necesita `--userns=keep-id` para escribir `.runner` (owner del host).
- La imagen tiene `ENTRYPOINT` vacío y `CMD=/bin/forgejo-runner`, así que la unit nombra el
  binario explícito: `Exec=/bin/forgejo-runner daemon --config /config.yml`.
- El socket de Podman del host está labeleado `user_tmp_t`; bajo SELinux enforcing el contenedor
  no lo abre, así que la unit usa `SecurityLabelDisable=true` (solo este contenedor).

## Punto de iteración conocido

Construir imágenes dentro de contenedores rootless anidados (buildah/podman-in-podman) es la
parte más delicada y **todavía sin validar end-to-end**. Los workflows de deploy usan
`buildah bud --isolation chroot`; si falla, puede requerir privilegios extra o ajustar
`container_base_selinux_booleans` (ej. `container_manage_cgroup`). Ver el label `buildah` en
`defaults/main.yml`.

## Gestión

```sh
systemctl --user -M ndelucca@ status forgejo-runner
```
El runner aparece en Forgejo en *Site Administration → Actions → Runners*.
