# Usar el CLI de Claude desde una app containerizada (`claude_bridge`)

Una app que corre en un contenedor **no** puede ejecutar el CLI `claude` directamente: el binario
son ~223 MB linkeados a glibc (no entra en una imagen `scratch`/mínima) y las credenciales son la
sesión OAuth del host (`~/.claude`, que el CLI reescribe al refrescar el token). En vez de meter
todo eso en la imagen, el rol **`claude_bridge`** deja el CLI del lado del host detrás de un
**socket unix** con un contrato JSON estrecho, y la app lo monta.

Es infra transversal, análoga a `deploy_ssh`/`home-deploy`: se instala una sola vez
(`claude_bridge_enabled: true` en `group_vars/homeservers/services.yml`), no por-app. La fuente de
verdad es el rol vivo `roles/claude_bridge/`.

## Frontera de confianza (leer antes de habilitarlo en una app)

**No hay autenticación en el protocolo.** Cualquier contenedor que monte el dir del socket puede
consultar y **gastar la suscripción**. El control de acceso es exactamente *quién monta el socket*.
Sólo habilitá el bridge en apps que confiás. Además el prompt viaja datos no confiables: el CLI
corre sandboxeado (HOME vacío salvo `~/.claude`, tools denegadas vía `settings.json`), pero no le
mandes desde la app secretos que no quieras que un prompt-injection intente exfiltrar.

## Qué agrega el `enable` de una app que usa el bridge

Un solo cambio en la Quadlet del rol de la app (`roles/__APP__/templates/__APP__.container.j2`),
idealmente detrás de un flag `__APP___claude_bridge_enabled` en `defaults/main.yml`:

```jinja
{% if __APP___claude_bridge_enabled %}
# Bridge del CLI de Claude (rol claude_bridge). SIN `:z`/`:Z`: el dir ya viene etiquetado
# container_file_t, y `:Z` (MCS privado) se lo robaría a las demás apps que comparten el socket.
Volume={{ claude_bridge_socket_dir }}:{{ claude_bridge_container_mount }}
Environment=... provider/socket que espere tu app ...
{% endif %}
```

- El default `claude_bridge_socket_dir` y `claude_bridge_container_mount` son ambos
  `/run/home-claude`; el socket queda en `/run/home-claude/sock` dentro del contenedor.
- **No** toca NGINX, DNS ni firewall: el bridge no escucha en ningún puerto.
- **No** requiere `keep-id` especial: el socket es `0660 ndelucca`, así que el proceso del
  contenedor tiene que mapear a uid 1000 en el host (imagen con `USER 1000:1000` +
  `UserNS=keep-id:uid=1000`, que es la convención de la casa). Un contenedor que corre como root
  dentro **no** llega (mapea a un subuid).

## El protocolo (por si la app lo implementa de cero)

Una conexión = una consulta. El cliente escribe **un objeto JSON**, hace half-close
(`shutdown(SHUT_WR)`), y lee la respuesta hasta EOF.

Request — sólo estas tres claves (cualquier otra se rechaza):
```json
{"prompt": "…", "system": "… (opcional)", "model": "sonnet (opcional; opus|sonnet|haiku)"}
```

Response — el envelope de `claude -p --output-format json` tal cual
(`{type, subtype, is_error, result, session_id, total_cost_usd}`). Ante cualquier error del bridge
(validación, timeout, lock ocupado, CLI caído) devuelve el **mismo** formato con `is_error: true` y
el motivo en `result`. El cliente parsea un solo formato siempre.

Notas para el cliente:
- Tras un restart de la socket unit el archivo se recrea; un `connect()` en esa ventana da
  `ENOENT`/`ECONNREFUSED`. Reintentá corto antes de dar error.
- El bridge **serializa** todas las consultas del host (un `flock`), para que dos invocaciones no
  corrompan el refresh del token OAuth. Una consulta larga hace esperar a las demás: dimensioná el
  timeout del cliente en consecuencia.

Ejemplo de referencia: el adapter `bridge` de `nd.market`
(`internal/adapters/claude`, `NewBridge`) — `net.Dial("unix", …)` + `CloseWrite()` +
`io.ReadAll`, con `NDM_CLAUDE_PROVIDER=bridge` / `NDM_CLAUDE_SOCKET`.
