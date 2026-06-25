# Runbook de bootstrap / recuperación ante desastres

Cómo reconstruir el home server desde cero — SO limpio, o un equipo nuevo tras
una falla de root/motherboard. El objetivo de diseño: **root contiene solo el SO
y es 100% reproducible desde este playbook**; los datos irremplazables viven en
D-Draco (appdata/media) y D-Leo (personal), respaldados en D-Ursa.

La recuperación se divide en dos:
1. **Falló root, discos de datos intactos** → reinstalar el SO, re-correr el
   playbook. Los datos ya están en D-Draco/D-Leo; no hay nada que restaurar.
2. **También se perdió el disco de datos (D-Draco)** → hacé el paso 1, luego
   seguí [RESTORE.md](RESTORE.md) para restaurar desde D-Ursa.

> ⚠️ **El único secreto que tenés que tener sí o sí: el vault password de Ansible.**
> NO está guardado en este repo (solo el vault encriptado). Todo lo demás — el
> password de backup de restic, cada secreto de app, el token de deSEC — está
> dentro del vault y se desencripta *solo* con él. **Si perdés el vault password,
> los backups y todos los secretos quedan irrecuperables para siempre.** Guardalo
> en custodia FUERA del servidor y fuera de este repo: un gestor de contraseñas
> y/o una copia impresa en algún lugar separado de la máquina. Verificá que podés
> recuperarlo *antes* de necesitar este runbook.

## 1. Instalar Fedora Server

- Instalá Fedora Server (en la versión que apuntan los roles; ver README).
- Creá el **usuario `ndelucca` con uid/gid 1000** — está pinned y debe coincidir
  para que el Podman rootless `UserNS=keep-id` y la propiedad de archivos sigan
  siendo válidos:
  ```bash
  sudo useradd -u 1000 -m ndelucca && sudo passwd ndelucca
  sudo usermod -aG wheel ndelucca
  ```
- Asigná una IP estática / reserva de `192.168.10.10` (el lease de DHCP vive en
  la config de AdGuard, pero en el primer arranque AdGuard todavía no está
  levantado).

## 2. Prerequisitos del nodo de control (la máquina desde la que corrés Ansible)

```bash
# Instalar Ansible + colecciones
ansible-galaxy collection install -r requirements.yml

# Acceso por clave SSH al host nuevo
ssh-copy-id ndelucca@192.168.10.10
ssh ndelucca@192.168.10.10 true        # confirmar que la autenticación por clave funciona

# Vault password — restic y todos los secretos de apps se desencriptan con esto.
# Recuperalo de tu custodia fuera del equipo (ver la advertencia de arriba). No
# hay forma de derivarlo.
printf '%s' '<the-vault-password>' > .vault_pass && chmod 600 .vault_pass
ansible-inventory -i inventory --host ndelucca-server >/dev/null  # desencripta → sin error = OK
```

## 3. Conectar e identificar los discos de datos

Los discos se direccionan por **UUID del filesystem** (estable entre hardware),
listados en `inventory/group_vars/homeservers/storage.yml`:

| Disco    | Role     | UUID                                   | Mount                |
|----------|----------|----------------------------------------|----------------------|
| D-Draco  | appdata  | `be7615af-92fe-40e7-9989-4b58c0ab4e1f` | `/srv/disks/D-Draco` |
| D-Leo    | personal | `ced8adab-8745-4c2f-b1b5-2a02ed02c12e` | `/srv/disks/D-Leo`   |
| D-Ursa   | backup   | `aabf1b5e-2bf1-41f4-ab93-bc27d508fc05` | `/srv/disks/D-Ursa`  |

- **Mismos discos, intactos:** solo conectalos; `blkid` debería mostrar esos UUIDs.
- **Disco nuevo/de reemplazo:** creá el filesystem, luego actualizá el `uuid:`
  correspondiente en `storage.yml` al nuevo valor de `blkid` antes de correr el
  playbook:
  ```bash
  sudo mkfs.ext4 -L D-Draco /dev/<dev>
  blkid /dev/<dev>          # copiar el UUID a storage.yml
  ```

El role `storage` los monta (`nofail` + device-timeout, así el equipo igual
arranca si falta un disco) y crea el esqueleto appdata/media con propietario
1000:1000.

## 4. Correr el playbook

```bash
# Primero un dry-run idempotente
ansible-playbook -l ndelucca-server playbooks/site.yml --check --diff

# Corrida real
ansible-playbook -l ndelucca-server playbooks/site.yml
```

Esto instala y arranca todo: storage, Cockpit, NGINX+TLS, AdGuard (DNS/DHCP),
todas las apps, los timers de backup, el watchdog y el firewall.

## 5. Si se perdieron los datos de D-Draco — restaurar

Seguí [RESTORE.md](RESTORE.md): restaurá appdata/media + D-Leo desde D-Ursa,
cargá los dumps de DB, corregí la propiedad de archivos, luego re-corré
`site.yml`.

## 6. Chequeos post-recuperación

- [ ] `ansible-playbook -l ndelucca-server playbooks/site.yml --check` → sin cambios
- [ ] El DNS de la LAN funciona: `dig @192.168.10.10 git.ndelucca.dedyn.io`
- [ ] Cada subdominio responde: `curl -k https://<app>.ndelucca.dedyn.io`
- [ ] `systemctl --user -M ndelucca@ list-timers` muestra los timers de backup + drill armados
- [ ] Disparar un backup una vez y confirmar un snapshot fresco:
      `systemctl --user -M ndelucca@ start backup.service && restic snapshots`

## Referencia rápida: qué sobrevive a qué

| Falla                   | Resultado para los datos                 | Acción                        |
|-------------------------|------------------------------------------|-------------------------------|
| Root / motherboard      | D-Draco/D-Leo/D-Ursa intactos            | reinstalar SO, re-correr playbook |
| D-Draco (appdata)       | restaurar desde D-Ursa                   | RESTORE.md                    |
| D-Ursa (backup)         | datos en vivo OK; sin backups hasta arreglarlo | reemplazar disco, re-correr playbook |
| D-Leo (personal)        | restaurar desde D-Ursa                   | RESTORE.md                    |
| **Vault password perdido** | **backups + todos los secretos irrecuperables** | **ninguna — debe estar en custodia fuera del equipo** |
