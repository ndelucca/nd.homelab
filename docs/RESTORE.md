# Runbook de restore (restic ← D-Ursa)

Cómo recuperar datos tras perder el disco de appdata (**D-Draco**) o tras un
cambio de estado erróneo. Los backups son snapshots de restic en **D-Ursa**
(`/srv/disks/D-Ursa/restic`), escritos a diario por el role `backup`.

> El repositorio se **prueba automáticamente** una vez por mes con el
> `backup-restore-drill.timer` (restaura los últimos dumps de DB a un directorio
> temporal y los chequea). Una falla dispara un aviso por el camino de notify.
> Aun así, leé esto antes de un restore real — un drill prueba la
> *restaurabilidad*, no *tu* procedimiento.

## 0. Prerequisitos

El password de restic vive en dos lugares, así que un restore no necesita nada
memorizado:

- el vault: `backup_password` en `inventory/group_vars/homeservers/vault.yml`
  (se desencripta con el vault password — mantenelo en custodia fuera del equipo,
  ver BOOTSTRAP.md)
- en el equipo: `/home/ndelucca/.config/restic/password` (0600), recreado por el playbook

Todos los comandos corren como el usuario de servicio **ndelucca** (uid 1000).
Exportá el entorno del repo una vez:

```bash
export RESTIC_REPOSITORY=/srv/disks/D-Ursa/restic
export RESTIC_PASSWORD_FILE=/home/ndelucca/.config/restic/password
```

## 1. Inspeccionar lo que tenés

```bash
restic snapshots                 # listar snapshots (anotá el ID/hora que querés)
restic check                     # verificar la integridad del repo antes de confiar en él
restic ls latest | head          # espiar el árbol de archivos del último snapshot
```

## 2. Restaurar los datos de las apps (D-Draco perdido o borrado)

Tras re-montar un D-Draco fresco (ver abajo) y antes de arrancar las apps:

```bash
# Restaurar el ESTADO de las apps + la media irremplazable a sus rutas originales.
# --target / restaura a las rutas absolutas capturadas en el snapshot.
restic restore latest --target / \
  --include /srv/disks/D-Draco/appdata \
  --include /srv/disks/D-Draco/media/Gallery \
  --include /srv/disks/D-Draco/media/Books \
  --include /srv/disks/D-Leo
```

Corregí la propiedad de archivos (todo lo que cuelga del disco de appdata debe
ser `ndelucca:ndelucca`, uid/gid 1000 — pinned para el Podman rootless
`UserNS=keep-id`):

```bash
sudo chown -R 1000:1000 /srv/disks/D-Draco/appdata /srv/disks/D-Draco/media
```

Movies/Series **no** están en el backup por diseño (se pueden re-descargar) —
recreá los directorios vacíos para que las apps tengan sus raíces de biblioteca:

```bash
mkdir -p /srv/disks/D-Draco/media/Movies /srv/disks/D-Draco/media/Series
```

## 3. Restaurar las bases de datos desde los dumps (fuente autoritativa)

Los archivos de DB en vivo también se capturan, pero los **dumps** bajo
`.../appdata/<app>/dumps/` son la fuente de restore consistente y autoritativa.

**Immich (PostgreSQL):** arrancá solo el contenedor de la base de datos, luego
cargá el dump.

```bash
# Con el pod de immich corriendo (o solo immich-database):
gunzip -c /srv/disks/D-Draco/appdata/immich/dumps/immich.sql.gz \
  | podman exec -i immich-database psql -U immich -d immich
```

**Apps SQLite (Jellyfin, Forgejo, Kavita):** con la app **detenida**, copiá el
dump por encima de la DB en vivo. Los nombres de los user-service units son
`jellyfin`, `forgejo` y `kavita` respectivamente (todos quadlets de un solo
contenedor):

```bash
# Ejemplo de Forgejo — repetir por app con el unit/ruta de los defaults del role.
systemctl --user stop forgejo            # detener la app primero (igual para jellyfin / kavita)
cp /srv/disks/D-Draco/appdata/forgejo/dumps/forgejo.db \
   /srv/disks/D-Draco/appdata/forgejo/data/data/gitea.db
```

**FileBrowser (BoltDB):** misma idea — detener, copiar
`filebrowser/dumps/filebrowser.db` por encima del `filebrowser/filebrowser.db`
en vivo.

## 4. Devolver las apps a la vida

```bash
ansible-playbook -l ndelucca-server playbooks/site.yml
```

Re-correr el playbook recrea las configs/units y arranca los servicios contra los
datos restaurados. Verificá que cada servicio responda (ver el checklist abajo).

## 5. Restore puntual / a un momento en el tiempo

```bash
# Restaurar el estado de una app desde un snapshot específico a un dir temporal para inspeccionar.
restic restore <snapshot-id> --target /tmp/inspect \
  --include /srv/disks/D-Draco/appdata/kavita
# O restaurar un solo archivo:
restic dump <snapshot-id> /srv/disks/D-Draco/appdata/forgejo/dumps/forgejo.db > /tmp/forgejo.db
```

## Checklist de verificación

- [ ] `restic check` sin errores
- [ ] La propiedad es `1000:1000` bajo `D-Draco/appdata` y `D-Draco/media`
- [ ] Immich: `curl -k https://gallery.ndelucca.dedyn.io` y las fotos visibles
- [ ] Forgejo/Jellyfin/Kavita accesibles en sus subdominios, con los datos presentes
- [ ] `journalctl --user -M ndelucca@ -u backup.service` muestra la próxima corrida OK
