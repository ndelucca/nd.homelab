---
name: ansible-host-limiter
description: Ensures ansible and ansible-playbook commands target only ndelucca-server and never the Debian raspberry-printer or the Acer client. Activate this skill whenever running any ansible or ansible-playbook commands.
allowed-tools: Bash, Grep, Read
---

# Ansible Host Limiter

## Qué protege realmente

El inventario tiene tres hosts: `ndelucca-server` (Fedora), `ndelucca-raspberry-printer`
(Debian) y `ndelucca-acer` (cliente). Los roles de Fedora fallan en los otros dos.

Hay **tres capas** que lo evitan, y conviene saber cuál hace el trabajo en cada caso:

1. **El `hosts:` del play — la barrera principal.** Todos los playbooks salvo uno ya
   están acotados a un grupo:

   | Playbook | `hosts:` | Alcanza |
   |---|---|---|
   | `site.yml`, `os_update.yml`, `update.yml`, `remove_adguard.yml` | `homeservers` | sólo ndelucca-server |
   | `printers.yml`, `mainsailos_update.yml` | `printers` | sólo la Raspberry |
   | `hosts.yml` | **`all:!{{ local_host }}`** | **TODOS los hosts** |

   `homeservers` tiene un único miembro, así que en esos seis playbooks el `-l` es
   redundante: no cambia a qué host se conecta.

2. **Los `assert` de preflight.** Los roles verifican el SO antes de tocar nada
   (`os_update`: *"Assert the target is a Fedora host (never run on the Debian printer)"*;
   `mainsailos`: el assert espejo para Debian).

3. **El flag `-l` — cinturón extra.** Es la única barrera real en los dos casos donde
   las otras dos no aplican.

## Regla

Usá `-l ndelucca-server` en todo comando `ansible` / `ansible-playbook`. Es redundante
en la mayoría de los playbooks y no cuesta nada; **es imprescindible** en:

- **`playbooks/hosts.yml`**, el único con `hosts: all:!...`.
- **Comandos ad-hoc `ansible <patrón> -m ...`**, donde el patrón lo ponés vos y no hay
  ningún `hosts:` que te cubra. `ansible all -m ping` alcanza la Raspberry y el Acer.

```sh
ansible-playbook playbooks/site.yml -l ndelucca-server --check --diff   # dry run primero
ansible-playbook playbooks/site.yml -l ndelucca-server -t nginx         # un solo rol
ansible ndelucca-server -m ansible.builtin.systemd -a "name=nginx state=restarted" --become
```

No inventes nombres de playbook: **no existen** `playbooks/jellyfin.yml` ni
`playbooks/nginx.yml`. Cada servicio se despliega con el tag de su rol sobre
`site.yml` (ver la lista de tags en el propio `site.yml`).

## Antes de correr, verificá

- [ ] El `-l` está presente.
- [ ] El target es `ndelucca-server`, salvo pedido explícito.
- [ ] Corriste `--check --diff` primero si el comando muta algo.
- [ ] Para `immich`, `--check` **sin** `--diff` (el pod YAML lleva la password de PG;
      ya tiene `no_log`, pero el hábito ahorra sustos).

## Si el usuario pide varios hosts

Preguntá antes de ejecutar: *"Esto alcanzaría también a ndelucca-raspberry-printer
(Debian). ¿Lo limito a ndelucca-server?"* y esperá confirmación.

## Notas

- Directorio de trabajo: `/home/ndelucca/nd.homelab`.
- Inventario: `inventory/hosts.yml` (`playbooks/hosts.yml` es un playbook que gestiona
  `/etc/hosts`, no un inventario — no los confundas).
