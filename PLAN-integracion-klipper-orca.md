# Plan: integrar la configuración de Klipper y OrcaSlicer en un solo repo desplegable

## Contexto

Naza tiene una Ender 3 S1 Pro con Klipper sobre una Raspberry Pi 3B+ (MainsailOS,
host `ndelucca-raspberry-printer`, `192.168.10.12`). Hoy la configuración vive
repartida en tres repos que no se hablan entre sí:

| Repo | Qué es | Problema |
|---|---|---|
| `nd.homelab` | Ansible para el server Fedora y la Pi | No gestiona la config de Klipper |
| `klipper-conf` | Los `.cfg` de Klipper | Es un registro, no una fuente. El flujo va de la Pi al repo |
| `nd.orcaslicer` (dir local `3dprint`) | Presets de OrcaSlicer generados con Python | No sabe nada de la config de Klipper contra la que fue calibrado |

El acoplamiento entre las dos mitades es real y ya causó un problema concreto:
`[gcode_arcs] resolution` en `printer.cfg` invalidaba `enable_arc_fitting` en el
preset de Orca. Los machine limits del preset son un espejo literal de
`[printer]`, y el start gcode es un contrato con la firma del macro `START_PRINT`.
Nada verifica que esas dos mitades sigan coincidiendo.

**Resultado buscado:** un solo repo (`nd.printer`) que contenga las dos mitades, con
un comando que falle si se desincronizan, y un rol de Ansible que despliegue la
mitad de Klipper a la Pi sin pisar las calibraciones que Klipper escribe solo.

**Este plan es temporal y se copia dentro de los repos** para que se pueda ejecutar
desde otra máquina con Claude sin el contexto de la conversación donde se diseñó.
Se borra cuando la implementación termine.

---

## Estado actual verificado

Todo lo de abajo fue comprobado contra la máquina viva vía la API de Moonraker el
2026-08-27, no es suposición.

```
 [printer]      max_velocity 300   max_accel 2000   max_z_velocity 5
                max_z_accel 100    square_corner_velocity 5
                minimum_cruise_ratio 0.5   kinematics cartesian
 [extruder]     nozzle 0.4   max_temp 300   min_extrude_temp 170
                pressure_advance 0.0        <- Klipper no lo setea, lo emite Orca
 [heater_bed]   max_temp 110
 [gcode_arcs]   resolution 1.0              <- default, causa facetado
 [input_shaper] NO CONFIGURADO
 [idle_timeout] timeout 10 (SEGUNDOS)  gcode: STATUS   <- macro que NO EXISTE
```

Macros realmente definidos en la Pi (14): `CANCEL_PRINT`, `END_PRINT`, `M0`,
`PAUSE`, `RESUME`, `SET_PAUSE_AT_LAYER`, `SET_PAUSE_NEXT_LAYER`,
`SET_PRINT_STATS_INFO`, `START_PRINT`, `_CLIENT_EXTRUDE`, `_CLIENT_LINEAR_MOVE`,
`_CLIENT_RETRACT`, `_TOOLHEAD_PARK_PAUSE_CANCEL`, `m300`. **No hay `STATUS`.**

### El mecanismo de deploy que ya existe: symlinks

Esto es lo más importante que hay que saber antes de tocar nada.
`~/printer_data/config/` NO es un directorio de archivos sueltos. Es una mezcla:

```
 macros.cfg    -> ../../klipper-conf/versions/v1/macros.cfg    SYMLINK, apunta a v1
 mainsail.cfg  -> ~/mainsail-config/mainsail.cfg               SYMLINK al repo upstream
 timelapse.cfg -> ~/moonraker-timelapse/klipper_macro/...      SYMLINK
 printer.cfg      archivo real, 3725 bytes                     lo escribe Klipper
 moonraker.conf   archivo real                                 lo escribe el instalador
 crowsnest.conf   archivo real                                 idem
 sonar.conf       archivo real                                 idem
```

Consecuencias, todas relevantes para el plan:

- **El repo `klipper-conf` SÍ está clonado en la Pi**, en `/home/ndelucca/klipper-conf`,
  en `main`, con working tree limpio, apuntando a `ssh://git@github.com/ndelucca/klipper-conf`.
  La entrada `mainsailos_managed_repos` de `nd.homelab` es cierta hoy.
- **El symlink de `macros.cfg` apunta a `v1`, no a `v2`.** O sea que `v2` nunca se
  desplegó. Funcionalmente da igual porque los dos `macros.cfg` son byte a byte
  idénticos (mismo MD5), pero significa que crear un directorio `vN` no despliega
  nada por sí solo: hay que reapuntar el symlink.
- **`mainsail.cfg` se sirve desde `~/mainsail-config`, el repo que actualiza Moonraker.**
  La copia versionada en `klipper-conf` nunca se usó. Sacarla del repo (decisión ya
  tomada) no cambia absolutamente nada en la máquina.
- **`printer.cfg` es un archivo real y nunca se desplegó desde el repo.** Para ese
  archivo el flujo sí va de la Pi al repo, a mano.
- Cuando Moonraker reporta un archivo de config como `r` (solo lectura) es porque es
  un **symlink**, no porque tenga permisos restringidos. Los archivos del repo en la
  Pi están en modo 755. No existe ninguna protección de escritura hoy.

Contenido: `macros.cfg` es idéntico al del repo. `printer.cfg` coincide con
`versions/v2/printer.cfg` salvo el bloque `SAVE_CONFIG` con la malla 6x6, que Klipper
escribe y el repo correctamente no versiona. **La malla SÍ existe en la Pi.**

`START_PRINT` acepta hoy solo `BED_TEMP` (default 60) y `EXTRUDER_TEMP` (default
200). `END_PRINT` no acepta parámetros.

### Acceso a la Pi

SSH **directo** a la Pi no funciona: la clave `id_ed25519` de la máquina de trabajo
se ofrece y la Pi la rechaza (probado desde Git Bash y desde WSL). Pero **el servidor
sí tiene acceso**, así que se llega con doble salto:

```sh
ssh ndelucca@ndelucca.dedyn.io 'ssh ndelucca@192.168.10.12 "<comando>"'
```

Para habilitar el acceso directo hay que agregar esta clave pública a
`~/.ssh/authorized_keys` de `ndelucca` en la Pi. Es un paso manual pendiente:

```sh
ssh ndelucca@ndelucca.dedyn.io 'ssh ndelucca@192.168.10.12 "echo \"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJqikCQpxJfijxlWlOlrp3b0uun5bT4tv+zOzWzJMb/8\" >> ~/.ssh/authorized_keys"'
```

Además, en WSL el archivo `~/.ssh/id_ed25519` está como `root:root` modo 644 y
OpenSSH lo va a rechazar: corregir a `ndelucca` modo 600.

Las lecturas de estado en vivo (secciones resueltas, macros definidos) se hacen por
la API de Moonraker, cuya URL está en `.printer-host` (archivo gitignoreado, **nunca
publicarlo**: la instancia no tiene autenticación).

### Limitación del entorno de trabajo

**Ansible no se puede ejecutar desde la máquina Windows**, y además `.vault_pass` no
existe en el checkout local. Sin ese archivo ni siquiera se carga el inventario,
porque `inventory/hosts.yml` trae `ansible_become_password` como valor `!vault` inline.

Lo que **sí** se puede validar localmente (WSL, con un `.vault_pass` dummy como hace
el CI):

```sh
yamllint .
ansible-lint
ansible-playbook playbooks/printers.yml --syntax-check
```

Lo que **no**: `--check --diff` ni la aplicación real contra la Pi. El rol de F6 se
escribe y se lintea acá, pero lo ejecuta el usuario desde donde corre Ansible
habitualmente.

---

## Decisiones tomadas

Todas confirmadas por el usuario. No re-preguntar.

| Tema | Decisión | Por qué |
|---|---|---|
| Fusión de repos | `klipper-conf` es la base, se le trae `nd.orcaslicer` adentro y se renombra a `nd.printer` | `klipper-conf` tiene la historia larga de la impresora |
| Pressure advance | Klipper pone el piso por material, Orca puede pisarlo | Cualquier gcode hereda el PA correcto; Orca queda libre para experimentar |
| `printer.cfg` | Split completo: raíz mutable no versionada + includes versionados de solo lectura | Es lo único que permite desplegar sin pisar el bloque `SAVE_CONFIG` |
| `versions/` | Se mantiene el esquema `versions/vN`. Se crea `v3` | Preferencia del usuario: poder ver un estado conocido-bueno completo |
| `[idle_timeout]` | Arreglarlo: `timeout: 3600` + `TURN_OFF_HEATERS` + `M84` | Hoy no apaga nada y tira error cada vez que entra en reposo |
| `mainsail.cfg` | Sale del repo | Es upstream de `mainsail-crew/mainsail-config` y Moonraker ya lo actualiza solo |
| Input shaper | Fuera de alcance. Se deja la sección comentada y documentada | Requiere calibración física |
| OrcaSlicer del server | Fuera de alcance. Solo se documenta el procedimiento manual | El rol usa `podman unshare chown` + ACL + SELinux y Orca reescribe sus configs al cerrar |

---

## Arquitectura destino

```
 nd.printer/  (era klipper-conf, renombrado en GitHub)
 ├── PLAN-integracion-klipper-orca.md    <- este plan, temporal
 ├── README.md                            <- reescrito, cubre las dos mitades
 ├── versions/
 │   ├── CURRENT                          <- contiene "v3". Fuente de verdad
 │   ├── v1/ v2/                          <- congelados, no se tocan
 │   └── v3/
 │       ├── hardware.cfg                 pines, PID, probe, buzzer
 │       ├── limits.cfg                   [printer] [gcode_arcs] [idle_timeout]
 │       ├── macros.cfg                   START_PRINT / END_PRINT / M0 / m300
 │       ├── printer.cfg.example          plantilla del archivo mutable
 │       └── firmware/                    binarios + build.config
 └── orca/
     ├── orca.py                          CLI: where build install verify audit check
     ├── src/                             profiles.py y compañía
     ├── presets/                         snapshot generado de los 9 perfiles
     └── docs/

 nd.homelab/
 ├── PLAN-integracion-klipper-orca.md    <- copia del mismo plan, temporal
 ├── roles/klipper_config/                <- NUEVO
 └── playbooks/printers.yml               <- se le suma el rol
```

Flujo de trabajo resultante:

```
  editar versions/v3/limits.cfg  o  orca/src/profiles.py
        │
        ├─ orca/orca.py build      regenera presets/
        ├─ orca/orca.py check      FALLA si las dos mitades no coinciden
        ├─ git push
        │
        ├─ PC cliente:  orca/orca.py install
        └─ la Pi:       ansible-playbook playbooks/printers.yml \
                          -l ndelucca-raspberry-printer -t klipper_config
```

---

## F0. Dejar el plan en los repos

Copiar este archivo como `PLAN-integracion-klipper-orca.md` a la raíz de los tres
repos (`nd.homelab`, `klipper-conf`, `3dprint`), commitear y pushear. Se incluye
`3dprint` porque hasta la fase F1 sigue siendo un repo independiente y alguien
podría arrancar desde ahí.

---

## F1. Fusionar los repos

**1.1** En `C:\Users\Naza\3dprint`, mover todo bajo `orca/` para que no colisione:

```sh
cd /c/Users/Naza/3dprint
mkdir orca
git mv orca.py src presets docs reference orca/
```

**1.2** Ajustar las rutas en `orca/orca.py`. Hoy tiene:

```python
REPO = Path(__file__).resolve().parent
sys.path.insert(0, str(REPO / "src"))
PRESETS = REPO / "presets"
```

Pasa a distinguir la raíz del repo de la carpeta de la herramienta, porque
`.printer-host` queda en la raíz y los presets bajo `orca/`:

```python
HERE = Path(__file__).resolve().parent      # nd.printer/orca
REPO = HERE.parent                          # nd.printer
sys.path.insert(0, str(HERE / "src"))
PRESETS = HERE / "presets"
```

`localhost_.resolve(REPO)` sigue recibiendo la raíz, así que `.printer-host` va
en la raíz del repo fusionado. Ese archivo está gitignoreado: hay que **moverlo a
mano**, `git mv` no lo alcanza.

**1.3** Commitear y pushear el movimiento en `3dprint`.

**1.4** Traer la historia a `klipper-conf`:

```sh
cd /c/Users/Naza/klipper-conf
git remote add orca /c/Users/Naza/3dprint
git fetch orca
git merge --allow-unrelated-histories orca/main
```

Conflictos esperados y su resolución:

- `.gitignore`: `klipper-conf` tiene el template genérico de Python de 3078 bytes,
  que no aplica. Quedarse con el de `3dprint` (`__pycache__/`, `.printer-host`,
  `backup/`, artefactos de SO) y agregarle nada más.
- `README.md`: reescribir de cero cubriendo las dos mitades. El de `klipper-conf`
  tiene 96 bytes y no dice nada.
- `.gitattributes`: solo existe en `3dprint`. **Borrar la regla `reference/** -text`**,
  porque `reference/` desaparece en F2 y una config gestionada debe normalizarse a LF.
- `LICENSE` (MIT, solo en `klipper-conf`): se queda tal cual.

**1.5** Renombrar el directorio local `C:\Users\Naza\klipper-conf` a
`C:\Users\Naza\nd.printer`.

**1.6** En GitHub: renombrar el repo `ndelucca/klipper-conf` a `ndelucca/nd.printer`
(GitHub deja un redirect automático desde la URL vieja). Actualizar el `origin` local.

**1.7** Archivar `ndelucca/nd.orcaslicer` en GitHub, agregándole antes un `README.md`
de una línea que apunte a `nd.printer`. No borrarlo: el artifact publicado lo enlaza.

**Verificación de F1:** `git log --follow orca/src/profiles.py` muestra los commits
originales de `nd.orcaslicer`, y `git log --follow versions/v2/printer.cfg` los de
`klipper-conf`.

---

## F2. Crear `versions/v3` con el split

Partir de `versions/v2` (que es lo que corre hoy en la Pi, verificado byte a byte).

**2.1 `versions/v3/hardware.cfg`** recibe todo lo que describe la máquina física.
Copiar de `v2/printer.cfg` estas secciones tal cual, sin cambios de valores:

`[stepper_x]` `[stepper_y]` `[stepper_z]` `[extruder]` `[heater_bed]`
`[heater_fan hotend_fan]` `[fan]` `[mcu]` `[bltouch]` `[bed_mesh]` `[safe_z_home]`
`[filament_switch_sensor e0_sensor]` `[pause_resume]` `[bed_screws]`

Y además **mover acá `[output_pin PB13]`**, que hoy vive en `macros.cfg` pero es
hardware (el buzzer). El macro `m300` que lo usa se queda en `macros.cfg` con el pin
hardcodeado; no vale la pena parametrizarlo.

**2.2 `versions/v3/limits.cfg`** recibe lo que es contrato con el slicer:

```ini
# {{ generado a mano, pero es lo que orca.py check valida }}

[printer]
kinematics: cartesian
max_velocity: 300
max_accel: 2000
max_z_velocity: 5
max_z_accel: 100

[gcode_arcs]
# Sin esta clave Klipper usa 1.0 mm y parte cada arco en cuerdas de 1 mm,
# lo que deja facetas visibles en radios chicos. Con 0.1 el error de sagitta
# en un radio de 2 mm baja de 0.064 mm a 0.0006 mm.
resolution: 0.1

[exclude_object]

[idle_timeout]
# Antes: timeout 10 (segundos) + gcode STATUS, un macro que no existe.
# El efecto real era que nada se apagaba nunca y Klipper tiraba error en cada
# entrada a reposo.
timeout: 3600
gcode:
  TURN_OFF_HEATERS
  M84

# [input_shaper]
# Sin calibrar. Mientras no exista esta seccion, max_accel debe quedarse en 2000
# y las aceleraciones de los procesos de Orca calibradas contra ese techo.
# Para calibrar: imprimir una ringing tower, medir la separacion de las ondas
# con calibre, freq = velocidad_del_test / separacion. Despues subir max_accel
# aca y regenerar los presets con orca.py build.
# shaper_type_x: mzv
# shaper_freq_x: ??
```

**2.3 `versions/v3/macros.cfg`** parte de `v2/macros.cfg` con tres cambios (detallados
en F3): sale `[output_pin PB13]`, `START_PRINT` gana `MATERIAL` y carga la malla.

**2.4 `versions/v3/printer.cfg.example`**, la plantilla del archivo mutable:

```ini
# Este archivo es el UNICO que Klipper puede escribir y el unico que NO se versiona.
# Es dueño del bloque SAVE_CONFIG de abajo, donde Klipper persiste la malla de cama,
# el z_offset del probe y los PID cuando corres las calibraciones.
# Todo lo demas vive en los includes, que se despliegan en modo 0444.

[include hardware.cfg]
[include limits.cfg]
[include mainsail.cfg]
[include macros.cfg]
```

`mainsail.cfg` se incluye pero **no se versiona ni se despliega**: lo mantiene el
`[update_manager mainsail-config]` de Moonraker.

**2.5 `versions/v3/firmware/`**: copiar de `v2` el `.bin` y `klipper-build.config`.
Eliminar el subdirectorio duplicado `STM32F4_UPDATE/` (es una copia byte a byte del
mismo binario, ~42 KB redundantes) y documentar en el README de `v3` que hay que
crear esa carpeta en la microSD al flashear.

**2.6 `versions/CURRENT`**: archivo de una línea con el texto `v3`. Es la fuente de
verdad de qué versión está viva. Lo leen `orca.py check` y el rol de Ansible.

**2.7 `versions/v3/README.md`**: copiar el de `v2` (documenta la build del firmware
del MCU y el procedimiento de flasheo por microSD, sigue vigente) y agregarle una
sección explicando el split de archivos.

**No tocar `versions/v1` ni `versions/v2`.** Quedan congelados.

---

## F3. Cambios de comportamiento en Klipper

Todos van en `versions/v3/`. Son cuatro.

**3.1 `[idle_timeout]` arreglado** (ya escrito en `limits.cfg` en F2).

**3.2 `[gcode_arcs] resolution: 0.1`** (ya escrito en `limits.cfg` en F2). Habilita
volver a prender el arc fitting en Orca en F4.

**3.3 La malla de cama se muda al macro.** Hoy el start gcode de Orca hace
`BED_MESH_PROFILE LOAD=default` después de llamar a `START_PRINT`. Eso es una
dependencia del slicer que no corresponde: la malla es de la máquina. Va adentro de
`START_PRINT`, **después** del `M109` que espera el nozzle, para que la cama ya esté
a temperatura y dilatada cuando se aplique la malla:

```
  ... M190 S{BED_TEMP}
  ... M109 S{EXTRUDER_TEMP}
  BED_MESH_PROFILE LOAD=default     <- NUEVO
  G1 Z0.28 F240
  ... (purga, sin cambios)
```

**3.4 Pressure advance por material.** `START_PRINT` gana un parámetro `MATERIAL` y
una tabla:

```ini
[gcode_macro START_PRINT]
variable_pa: {'PLA': 0.04, 'PETG': 0.06, 'ABS': 0.05, 'TPU': 0.6}
gcode:
  {% set BED_TEMP = params.BED_TEMP|default(60)|float %}
  {% set EXTRUDER_TEMP = params.EXTRUDER_TEMP|default(200)|float %}
  {% set MATERIAL = params.MATERIAL|default('PLA')|upper %}
  ...
  SET_PRESSURE_ADVANCE ADVANCE={printer["gcode_macro START_PRINT"].pa.get(MATERIAL, 0.04)}
```

Los cuatro valores salen de `orca/src/profiles.py` (claves `pressure_advance` de cada
filamento) y `orca.py check` valida que sigan coincidiendo.

Semántica del override: Orca emite el start gcode de máquina primero (que llama a
`START_PRINT`) y el de filamento después. Si un filamento tiene
`enable_pressure_advance: 1`, su `SET_PRESSURE_ADVANCE` corre después y gana. Ese es
exactamente el comportamiento pedido: Klipper pone el piso, Orca puede pisarlo.

---

## F4. Ajustar los presets de Orca

Todo en `orca/src/profiles.py`. Después de cada cambio correr `orca.py build`.

**4.1 Start gcode.** La constante `START` pasa a pasar el material y a no cargar la
malla (eso ahora lo hace el macro):

```python
START = ("START_PRINT BED_TEMP=[bed_temperature_initial_layer_single] "
         "EXTRUDER_TEMP=[nozzle_temperature_initial_layer] "
         "MATERIAL=[filament_type]\n")
```

`[filament_type]` en Orca devuelve `PLA`, `PETG`, `ABS`, `TPU`, que son exactamente
las claves de `variable_pa`.

**4.2 Arc fitting.** En el dict `COMMON` de procesos, `enable_arc_fitting` vuelve a
`"1"`. Ahora es seguro porque `[gcode_arcs] resolution` es 0.1. Actualizar el
comentario largo que hoy explica por qué estaba apagado.

**4.3 Pressure advance.** En los cuatro filamentos, `enable_pressure_advance` pasa a
`["0"]`. El valor de `pressure_advance` se **conserva** en el dict: deja de emitirse,
pero sigue siendo la fuente de verdad que `check` cruza contra `variable_pa`.
Documentar en el comentario que poner `["1"]` en un filamento es un override
deliberado y que `check` lo va a reportar como aviso, no como error.

**4.4** Correr `orca.py build` y `orca.py audit`. El audit debe seguir dando 0 y el
caudal máximo del proceso Standard debe seguir por debajo del tope de 11 mm3/s del PLA.

---

## F5. El subcomando `check`

**5.1 `orca/src/klippercfg.py`** (nuevo, ~50 líneas). Parser mínimo de `.cfg` de
Klipper. `configparser` no sirve tal cual: hay que tolerar secciones con espacio
(`[gcode_macro START_PRINT]`), secciones vacías (`[exclude_object]`), y descartar el
bloque `#*#` de `SAVE_CONFIG`. Devuelve `{seccion: {clave: valor}}`. Función
`load_dir(path)` que lee y mergea `hardware.cfg` + `limits.cfg` + `macros.cfg`.

**5.2 `orca/src/checkcfg.py`** (nuevo). Seguir el estilo de `src/audit.py`: constantes
en mayúscula declarando qué se valida, `BAR = "=" * 78` como separador, secciones
numeradas, una línea `OK` o mensaje en mayúsculas por ítem, contador `fallos`,
`return 1 if fallos else 0`. Reusar el helper `_num()` de `audit.py` para normalizar
los valores de Orca, que son strings o listas de strings y a veces llevan `%`.

Lee `profiles.MACHINE` / `PROCESSES` / `FILAMENTS` / `START` directamente (no requiere
OrcaSlicer instalado) contra el directorio de Klipper.

Invariantes a validar:

```
 GEOMETRIA
   printable_area X          ==  [stepper_x] position_max
   printable_area Y          ==  [stepper_y] position_max
   printable_height          ==  [stepper_z] position_max
   nozzle_diameter           ==  [extruder] nozzle_diameter
   filament_diameter         ==  [extruder] filament_diameter

 LIMITES DE MOVIMIENTO
   machine_max_speed_x / _y  ==  [printer] max_velocity
   machine_max_speed_z       ==  [printer] max_z_velocity
   machine_max_acceleration_*==  [printer] max_accel
   machine_max_acceleration_z==  [printer] max_z_accel
   machine_max_jerk_x / _y   ==  [printer] square_corner_velocity
   toda *_acceleration de proceso  <=  [printer] max_accel
   travel_speed_z            <=  [printer] max_z_velocity

 TERMICO
   max(nozzle_temperature*)  <   [extruder] max_temp
   min(nozzle_temperature*)  >=  [extruder] min_extrude_temp
   max(*_plate_temp)         <   [heater_bed] max_temp

 FEATURES
   exclude_object == 1       requiere  [exclude_object] presente
   enable_arc_fitting == 1   requiere  [gcode_arcs] resolution <= 0.2
   parametros del START gcode  ==  params.* que lee START_PRINT
   machine_end_gcode llama a un macro que existe

 PRESSURE ADVANCE
   filamento con enable_pressure_advance == 0
       -> variable_pa[MATERIAL] existe y coincide con su pressure_advance
   filamento con enable_pressure_advance == 1
       -> AVISO de override explicito, no cuenta como fallo

 INPUT SHAPER
   si [input_shaper] no existe  ->  [printer] max_accel debe ser <= 2000
```

**5.3 Enganchar en `orca/orca.py`.** Cuatro puntos mecánicos:

1. El docstring del módulo (líneas 5-9) es la ayuda del CLI: agregar la línea de `check`.
2. `def cmd_check(args)` cerca de `cmd_audit`, con import lazy, igual que `cmd_audit`:
   ```python
   def cmd_check(args):
       import checkcfg
       return checkcfg.run(klipper_dir(args))
   ```
3. Registrar el subparser con un flag propio:
   ```python
   c = sub.add_parser("check", parents=[common],
                      help="valida coherencia entre los presets y la config de Klipper")
   c.add_argument("--klipper-dir", metavar="RUTA", default=None,
                  help="default: versions/<CURRENT>")
   ```
4. Agregarlo al dict de dispatch.

El default de `--klipper-dir` sale de leer `REPO / "versions" / "CURRENT"`.

**Nota de naming:** ya existe `orca.py build --check`, que es otra cosa (detecta que
`presets/` quedó desincronizado de `profiles.py`). Documentar la diferencia en el
README para que no se confundan: `build --check` es deriva interna, `check` es
coherencia con la máquina.

**5.4 Borrar `orca/reference/klipper/`.** Era un snapshot de referencia; ahora la
config real vive en `versions/`. Quitar también la regla `reference/** -text` del
`.gitattributes` si quedó de F1.

**5.5 CI.** Agregar `.github/workflows/check.yml` a `nd.printer` que corra, en cada
push, `python orca/orca.py build --check` y `python orca/orca.py check`. Ambos son
stdlib pura, no hace falta instalar nada.

---

## F6. Rol de Ansible `klipper_config`

En `nd.homelab`. Seguir las convenciones del repo, que están en `CLAUDE.md` y en el
skill `home-server-role-creator`, con la salvedad de que **ese skill describe roles de
contenedor sobre Fedora**: no aplica nada de SELinux, firewalld, Quadlet ni Podman.
Los modelos vivos a copiar son `roles/mainsail_tls/` (deploy de archivo + validación +
handler) y `roles/acme/` (orquestación con `import_tasks` + tags).

**Prerrequisito manual:** autorizar la clave pública de Naza en la Pi. Sin eso Ansible
no puede conectarse.

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJqikCQpxJfijxlWlOlrp3b0uun5bT4tv+zOzWzJMb/8
```

Va a `~/.ssh/authorized_keys` de `ndelucca` en `192.168.10.12`, por el editor de
Mainsail o por acceso físico. Además, en WSL el archivo `~/.ssh/id_ed25519` está
como `root:root` modo 644 y OpenSSH lo va a rechazar: corregir a `ndelucca` modo 600.

**6.1 Estructura:**

```
roles/klipper_config/
  defaults/main.yml      todas las vars klipper_config_*
  meta/main.yml          galaxy_info, platforms Debian/bookworm, dependencies: []
  handlers/main.yml      "Restart klipper"
  tasks/main.yml         solo import_tasks + tags ['klipper_config', '<paso>']
  tasks/preflight.yml    asserts
  tasks/checkout.yml     clona/actualiza nd.printer en la Pi
  tasks/migrate.yml      el split one-shot de printer.cfg
  tasks/configure.yml    copia los .cfg gestionados
  tasks/verify.yml       restart + poll a /printer/info
```

**6.2 `defaults/main.yml`:**

```yaml
klipper_config_repo: https://github.com/ndelucca/nd.printer.git
klipper_config_ref: main
klipper_config_checkout: "/home/{{ ansible_user }}/nd.printer"
klipper_config_dir: "/home/{{ ansible_user }}/printer_data/config"
klipper_config_version: ""        # vacio = leer versions/CURRENT del checkout
klipper_config_managed_files:     # mainsail.cfg NO esta: lo gestiona Moonraker
  - hardware.cfg
  - limits.cfg
  - macros.cfg
klipper_config_moonraker_url: "http://127.0.0.1:7125"
klipper_config_restart: true
klipper_config_ready_retries: 20
klipper_config_ready_delay: 3
```

**6.3 `tasks/preflight.yml`.** Copiar literalmente los dos asserts de
`roles/mainsailos/tasks/preflight.yml`: el que exige `os_family == "Debian"` (para no
correr nunca sobre el server Fedora) y el que aborta si hay una impresión en curso
consultando `/printer/objects/query?print_stats`. Ambos ya están escritos y probados.

**6.4 `tasks/checkout.yml`.** `ansible.builtin.git` con `version:` explícito (nunca
`HEAD`), `update: true`, corriendo como `{{ ansible_user }}` y no como root porque los
archivos de `printer_data` son de `ndelucca`. Después, un `slurp` de
`versions/CURRENT` para resolver la versión efectiva cuando
`klipper_config_version` está vacío.

No hay precedente de `ansible.builtin.git` en el repo, así que esta es la primera vez;
`.ansible-lint` ya contempla operaciones de git en la impresora.

**6.5 `tasks/migrate.yml`.** El paso de una sola vez y el más delicado del plan.
Convierte el `printer.cfg` monolítico de la Pi en el archivo de includes.

```
  detectar   grep '^\[stepper_x\]' printer.cfg
             si NO aparece -> ya migrado, saltear todo
        │
  backup     copiar printer.cfg a printer.cfg.premigracion (force: false,
             el mismo patron que usa mainsail_tls con el vhost stock)
        │
  extraer    la cola SAVE_CONFIG: desde la linea que empieza con
             '#*# <---------------------- SAVE_CONFIG' hasta el final
        │
  symlink    BORRAR el symlink macros.cfg (hoy apunta a
             ../../klipper-conf/versions/v1/macros.cfg). F6.6 escribe un
             archivo real en su lugar.
             NO TOCAR mainsail.cfg ni timelapse.cfg: esos symlinks apuntan a
             repos que gestiona Moonraker y deben quedar como estan.
        │
  escribir   printer.cfg.example + '\n' + cola preservada
        │
  desplegar  hardware.cfg / limits.cfg / macros.cfg  (F6.6)
```

Guardar la tarea con `when: not ansible_check_mode` donde corresponda para que
`--check --diff` muestre el plan sin ejecutar.

**Por qué se abandona el symlink y se pasa a copias.** El setup actual sirve
`macros.cfg` por symlink al working tree del repo. Funciona, pero tiene dos
problemas para automatizar: cualquier edición desde el editor de Mainsail ensucia
el working tree y hace fallar el siguiente `git pull`, y no hay forma de previsualizar
el cambio con `--check --diff` porque el contenido no lo escribe Ansible. Con copias
en modo `0444` una edición accidental se revierte sola en la próxima corrida, que es
el comportamiento declarativo correcto, y el diff se ve antes de aplicar.

El checkout viejo `/home/ndelucca/klipper-conf` queda huérfano tras la migración.
Dejarlo en su lugar como red de seguridad y documentar que se puede borrar después
de la primera impresión exitosa.

**6.6 `tasks/configure.yml`.** `ansible.builtin.copy` con `remote_src: true` desde
`{{ klipper_config_checkout }}/versions/{{ version }}/` hacia
`{{ klipper_config_dir }}/`, en loop sobre `klipper_config_managed_files`, con
`owner: {{ ansible_user }}` y **`mode: '0444'`**. El modo de solo lectura es
deliberado y continúa lo que Naza ya hacía a mano: impide que el editor de Mainsail
los pise y mantiene limpio el working tree del checkout. Notificar el handler
`Restart klipper` cuando cambie algo.

**6.7 `tasks/verify.yml`.** Este es el que convierte el deploy en algo seguro:

```
  restart    POST /printer/restart  (o systemd klipper)
        │
  poll       GET /printer/info
             until: status == 200 and json.result.state == 'ready'
             retries / delay de los defaults
        │
  si falla   fail mostrando json.result.state_message, que es el error exacto
             del parser de Klipper, y avisar de restaurar
             printer.cfg.premigracion
```

Seguir el idioma de poll del repo: `become: false` explícito (porque `ansible.cfg`
tiene `become = True` global), `changed_when: false`, `check_mode: false`, y
`| default(<valor pesimista>)` dentro del `until` para que un endpoint caído
reintente en vez de evaluar undefined. El modelo exacto está en
`roles/mainsailos/tasks/klipper_stack.yml` líneas 78-93.

Cerrar con el loop de `systemd` + `assert ActiveState == "active"` sobre
`[klipper, moonraker, nginx]`, igual que `roles/mainsailos/tasks/verify.yml`.

**6.8 Wiring:**

- Agregar el rol a `playbooks/printers.yml` como tercer rol, con
  `tags: ['klipper_config', 'klipper']`.
- Actualizar `roles/mainsailos/defaults/main.yml` línea 51: la entrada
  `/home/{{ ansible_user }}/klipper-conf` de `mainsailos_managed_repos` pasa a
  `/home/{{ ansible_user }}/nd.printer`. Hoy esa entrada es una promesa vacía porque
  nada garantiza que el repo esté clonado; con este rol pasa a ser cierta y el
  manifiesto de rollback empieza a servir.
- Overrides del grupo, si hacen falta, en
  `inventory/group_vars/printers/services.yml`.

**6.9 Lint.** El repo corre `yamllint` y `ansible-lint` (perfil `moderate`) en CI.
Reglas que rompen el build: `---` al inicio de todo YAML, FQCN en todos los módulos
(`ansible.builtin.copy`, no `copy`), nombres de tarea capitalizados, `mode` entre
comillas (`'0444'`), `true`/`false` en vez de `yes`/`no`, sin trailing whitespace.

---

## F7. Documentación y limpieza

**7.1 `nd.printer/README.md`** reescrito: las dos mitades, el flujo de trabajo, los
comandos, el modelo de quién manda sobre qué (máquina a Klipper, objeto al slicer,
material repartido a propósito), y la explicación del split de `printer.cfg`.

**7.2 `orca/docs/orcaslicer-ender3s1pro-klipper.md`**: actualizar la sección de arc
fitting (ahora está prendido y por qué), la de pressure advance (ahora lo pone
Klipper), y la tabla "Dependencias sobre la máquina", que pasa de ser prosa a ser lo
que `orca.py check` valida automáticamente.

**7.3 `orca/docs/artifact.html`**: los mismos cambios. Republicar **pasando el
parámetro `url` con la URL existente**
(`https://claude.ai/code/artifact/578d117c-c02b-4661-abd7-7288c7ce3d11`), porque el
archivo cambió de ruta al moverse a `orca/` y sin ese parámetro se crearía un
artifact nuevo en vez de actualizar el que ya está publicado.

**7.4 `docs/orcaslicer-en-el-server.md`** (nuevo, corto). El procedimiento manual para
aplicar los presets al OrcaSlicer containerizado del server, que queda fuera de
alcance pero documentado. Datos concretos relevados:

- Ruta real del config: `/srv/disks/D-Draco/appdata/orcaslicer/config`, que dentro
  del contenedor es `/config`.
- El árbol NO es de `ndelucca`: `roles/orcaslicer/tasks/preflight.yml` corre
  `podman unshare chown -R 1000:1000` porque la imagen LSIO usa un sub-uid de
  podman rootless. Forzar la propiedad a `ndelucca` es justo lo que rompe la app.
- Hace falta contexto SELinux `container_file_t` y ACLs, y hay que parar el
  contenedor antes de escribir porque OrcaSlicer reescribe sus configs al cerrarse.

**7.5** Borrar `PLAN-integracion-klipper-orca.md` de los repos. Es lo último.

---

## Verificación de punta a punta

En orden, después de F6:

```sh
# 1. Las dos mitades coinciden entre si
cd /c/Users/Naza/nd.printer
python orca/orca.py build --check      # 0 = presets sincronizados con profiles.py
python orca/orca.py check              # 0 = presets coherentes con versions/v3
python orca/orca.py audit              # 0 = sin herencia peligrosa, caudales ok

# 2. El repo de ansible pasa su propio CI
cd /c/Users/Naza/nd.homelab
yamllint .
ansible-lint

# 3. Dry run contra la Pi. SIEMPRE con -l, es regla no negociable del repo
ansible-playbook playbooks/printers.yml -l ndelucca-raspberry-printer \
  -t klipper_config --check --diff

# 4. Aplicar
ansible-playbook playbooks/printers.yml -l ndelucca-raspberry-printer -t klipper_config
```

Después, contra la máquina viva (`$H` = la URL de `.printer-host`):

```sh
curl -s "$H/printer/info" | python -m json.tool          # state debe ser "ready"
curl -s "$H/printer/objects/query?configfile=settings"   # verificar:
#   [gcode_arcs] resolution == 0.1
#   [idle_timeout] timeout == 3600
#   [printer] max_accel == 2000
curl -s "$H/printer/objects/list"                        # START_PRINT sigue existiendo
```

Y la prueba real: **laminar e imprimir la misma pieza de referencia**
(`SoporteCocina-Body`, la que ya se imprimió dos veces) y comparar. En el gcode
generado hay que verificar que aparezca `MATERIAL=PLA` en la llamada a `START_PRINT`,
que haya comandos `G2`/`G3` (arc fitting activo) y que **no** haya un
`SET_PRESSURE_ADVANCE` emitido por Orca.

Durante la impresión, confirmar por consola que Klipper tiene el PA cargado:

```
 curl -s "$H/printer/objects/query?extruder" | grep pressure_advance
 # debe dar 0.04 para PLA, no 0.0
```

---

## Riesgos y rollback

| Riesgo | Mitigación |
|---|---|
| La migración de `printer.cfg` deja a Klipper sin arrancar | `printer.cfg.premigracion` queda en la Pi. `verify.yml` falla mostrando el `state_message` del parser. Restaurar ese archivo y `FIRMWARE_RESTART` |
| Se pierde la malla de cama al migrar | `migrate.yml` extrae y vuelve a pegar la cola `SAVE_CONFIG`. Verificar con `BED_MESH_PROFILE LOAD=default` a mano antes de imprimir |
| El deploy corre a mitad de una impresión | El assert de `preflight.yml` aborta si `print_stats.state == 'printing'` |
| La fusión de repos pierde historia | Verificar con `git log --follow` sobre un archivo de cada mitad antes de archivar `nd.orcaslicer` |
| `resolution: 0.1` sobrecarga la Pi 3B+ | Es estrictamente mejor que el estado actual, donde Orca manda segmentos de 0.012 mm por serie. Si aparece `Timer too close`, subir a 0.2 |
| El backup del rol `mainsailos` vive en la misma SD que respalda | Fuera de alcance, pero considerar poner `mainsailos_backup_remote_fetch: true` en `group_vars/printers/services.yml` |

Antes de empezar F6, correr el backup existente, que ya archiva
`printer_data/{config,database,certs}` con retención de 5:

```sh
ansible-playbook playbooks/mainsailos_update.yml -l ndelucca-raspberry-printer -t backup
```

---

## Fuera de alcance (decidido, no re-preguntar)

- **Input shaper.** `limits.cfg` queda con la sección comentada y el procedimiento
  documentado. Mientras no exista, `max_accel` se queda en 2000 y `check` lo valida.
- **Aplicar los presets al OrcaSlicer containerizado del server.** Solo se documenta
  el procedimiento manual en F7.4.
- **Seguridad de Moonraker.** La instancia sigue expuesta sin autenticación:
  `trusted_clients` incluye `192.168.0.0/16` y el nginx que proxea está en la LAN, así
  que toda petición de internet entra como confiable. Es un problema conocido y
  aparte. Nunca publicar la URL de `.printer-host`.
- **Aplanar `versions/`, tags y releases.** El usuario prefiere mantener el esquema de
  directorios.
