# TLS y DNS — arquitectura y opciones

---

## 1. TLS: certs reales de Let's Encrypt vía DNS-01 (implementado)

### Cómo funciona

Cada app se sirve con un certificado **real y de confianza pública** — sin
advertencias del browser — mientras **nada está expuesto a internet**. Esto es
posible porque los certs se emiten con el **challenge ACME DNS-01**, que solo
necesita un registro TXT público; la CA nunca se conecta al host, así que no se
abre ningún puerto entrante.

- **Dominio:** `ndelucca.dedyn.io` — un dominio público gratuito alojado en
  [deSEC](https://desec.io). El `ndelucca-server.com` original era *inventado*
  (solo resoluble dentro de AdGuard), así que ninguna CA podría firmarlo jamás.
  AdGuard resuelve `*.ndelucca.dedyn.io` **internamente** a IPs de la LAN; la zona
  pública en deSEC se usa *solo* para responder los lookups del TXT
  `_acme-challenge` durante la emisión/renovación.
- **Cliente:** [`lego`](https://github.com/go-acme/lego) (un solo binario Go, con
  provider `desec` nativo). Instalado y mantenido al día por `roles/acme`.
- **Servidor (`ndelucca-server`, .10):** un cert **wildcard**
  `*.ndelucca.dedyn.io` (+ apex) terminado por NGINX para las 13 apps. Los vhosts
  ya se basan en `nginx_domain`, así que no hicieron falta cambios de config por app.
- **Impresora (`ndelucca-raspberry-printer`, .12):** emite su **propio** cert
  `printer.ndelucca.dedyn.io` y sirve Mainsail sobre HTTPS directamente
  (`roles/mainsail_tls`). DNS-01 no necesita ayuda del servidor, así que la Pi se
  auto-renueva de forma independiente — sin sincronización de certs entre hosts.
- **Renovación:** un `lego-renew.timer` diario en cada host corre `lego renew` y
  recarga NGINX vía `--renew-hook`. Las renovaciones además mantienen activo el
  dominio de deSEC.
- **Secreto:** el token de la API de deSEC vive en `group_vars/all/vault.yml`
  (`vault_desec_token`), compartido por ambos hosts.

### Layout

| Host | Role(s) | dir de datos de lego | Cert |
|------|---------|----------------------|------|
| `ndelucca-server` | `acme` → `nginx` | `/etc/pki/nginx/lego` | `ndelucca.dedyn.io` + `*.ndelucca.dedyn.io` |
| `ndelucca-raspberry-printer` | `acme` → `mainsail_tls` | `/etc/ssl/mainsail` | `printer.ndelucca.dedyn.io` |

### Fallback a self-signed (cambio manual)

El servidor mantiene un cert **self-signed** generado por el role nginx como piso
de bootstrap. Si la emisión falla alguna vez (token inválido, sin internet, deSEC
caído), el role `acme` falla el play **antes** de reconfigurar NGINX, así que nada
se rompe. Para recuperarte, cambiá el switch y re-corré:

```yaml
# inventory/group_vars/homeservers/services.yml
nginx_tls_mode: selfsigned        # letsencrypt (default) | selfsigned
```
```bash
ansible-playbook playbooks/site.yml -l ndelucca-server --tags nginx
```

NGINX entonces sirve el cert self-signed sin downtime. Volvé a `letsencrypt` una
vez resuelto el problema.

### Operación

```bash
# Emitir / renovar en el servidor (staging primero para evitar rate limits):
ansible-playbook playbooks/site.yml -l ndelucca-server --tags acme   # acme_staging: true|false
# Impresora:
ansible-playbook playbooks/printers.yml -l ndelucca-raspberry-printer --tags acme,tls
# Forzar un chequeo de renovación ahora:
sudo systemctl start lego-renew.service && systemctl status lego-renew.timer
# Inspeccionar el cert:
openssl x509 -in /etc/pki/nginx/lego/certificates/ndelucca.dedyn.io.crt -noout -issuer -dates -ext subjectAltName
```

### Notas y hardening

- Un cert público para `*.ndelucca.dedyn.io` aparece en los logs de Certificate
  Transparency (el **nombre** es público; los servicios no son accesibles desde
  afuera).
- El token compartido de deSEC tiene control total del DNS. Para reducir el radio
  de impacto, creá un token de deSEC **acotado** (limitado a los registros
  `_acme-challenge` que cada host necesita) y reemplazá `vault_desec_token` por
  tokens por host.
- `update.dedyn.io` (deSEC dynDNS) **no** se usa a propósito — eso publicaría un
  registro A apuntando a tu IP pública. DNS-01 solo necesita el token de la API.

---

## 2. DNS: AdGuard es el punto único de falla de la LAN

### Estado actual

AdGuard Home sirve **tanto** DHCP como DNS para toda la LAN. Si se cae, cada
dispositivo pierde la resolución de nombres. Esto se mitiga con el watchdog
post-arranque (`service_maintenance` reinicia AdGuard), pero una falla dura igual
deja la LAN sin resolución.

### Opción A — anunciar un DNS secundario en DHCP (barato, recomendado)

Entregá a los clientes un resolver de fallback junto con AdGuard, así una caída
puntual de AdGuard degrada a "los ads no se filtran" en lugar de "sin internet":

- Agregá un resolver público (ej. `1.1.1.1` / `9.9.9.9`) o el router como DNS
  **secundario** en las opciones de DHCP.
- Salvedad: los clientes pueden usar el secundario de forma oportunista, así que
  algunas queries esquivan el filtrado incluso con AdGuard sano. Aceptable por
  resiliencia; si el filtrado estricto importa más que el uptime, salteá esto y
  confiá en el watchdog.

Es un cambio chico en la config de DHCP de AdGuard (`adguard_dhcp_*` en
`group_vars/homeservers/services.yml`) — agregar la opción de DNS secundario.

### Opción B — una segunda instancia real de AdGuard (más trabajo)

Correr una segunda instancia liviana de AdGuard (ej. en la Raspberry Pi que ya
está en el inventario) y anunciar ambas como DNS en DHCP. AdGuard Home no
sincroniza la config entre instancias de forma nativa, así que las manejarías a
ambas vía este playbook (la config ya es declarativa acá). Máxima resiliencia;
máximo esfuerzo.

**Recomendación:** empezá con la **Opción A** (una opción de DHCP) para una gran
ganancia de resiliencia a costo casi cero; considerá la Opción B solo si el uptime
del DNS se vuelve crítico.

---

## 3. Exponer servicios a internet (opción futura, no hecha)

Hoy todo es **solo-LAN** y eso es deliberado. Si alguna vez querés un subdominio
accesible desde afuera, tené en cuenta que **AdGuard no es donde se hace** —
AdGuard solo responde a clientes de tu LAN, no es autoritativo en la internet
pública. La resolución pública vive en **deSEC**.

Esto es **split-horizon DNS** y los dos resolvers se complementan:

| Quién pregunta | Resuelve vía | Apunta a |
|----------------|--------------|----------|
| Un cliente en tu LAN | rewrite de AdGuard | `192.168.10.10` (privada — nunca hace hairpin por el router) |
| Un cliente en internet | registro A de deSEC | tu IP pública |

Lo que exponer requeriría realmente (es más que DNS):

1. **deSEC:** crear un **registro A** (el apex o solo los subdominios que querés
   públicos) → tu IP pública. Si tu IP de casa es **dinámica**, acá es donde
   `update.dedyn.io` (deSEC dynDNS) finalmente importa — corré un updater en el
   **router** o un pequeño timer con `curl` en el servidor, **no** en AdGuard.
2. **Router:** hacer port-forward del **443** (y el 80 para el redirect) a
   `192.168.10.10`.
3. **Firewall del servidor:** abrir el 443 entrante (hoy está acotado a la LAN).
4. **AdGuard:** dejarlo **como está** — el rewrite interno mantiene el tráfico de
   la LAN en la IP privada.

La parte buena: **el certificado no necesita ningún cambio.** Como usamos DNS-01,
el wildcard ya funciona idéntico dentro y fuera (HTTP-01 habría necesitado el
puerto 80 abierto; DNS-01 no).

La salvedad: exponer agranda la superficie de ataque. Si lo hacés, exponé lo
mínimo, y poné una capa de auth adelante (ej. Authelia / oauth2-proxy en NGINX)
más fail2ban. Esto podría cablearse en Ansible como un `expose: true/false`
reversible por subdominio (crear/borrar el registro A de deSEC con el mismo token
+ abrir el firewall) manteniendo el split-horizon — a diseñar si/cuando se quiera.

---

## Qué se implementó vs. qué está documentado

- **Implementado:** certs reales de Let's Encrypt vía DNS-01 (esta sección 1,
  roles `acme` + `mainsail_tls`); monitoreo (Uptime-Kuma); avisos de falla de
  backup/disco lleno.
- **Solo documentado (este archivo):** el cambio de resiliencia con DNS secundario
  (necesita una decisión filtrado-vs-uptime) y la exposición a internet (sección 3).
