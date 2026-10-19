# Scripts independientes: hardware y o-tiling

Estos scripts **no se ejecutan automáticamente** desde `setup.sh`. Siguen en el
repo porque se usan manualmente, y porque un servicio instalado en el pasado
ejecuta uno de ellos. Su contrato es: explícitos, verificables, y sin prometer
resolver el fallo upstream que sigue abierto.

## o-tiling

### Estado real del proyecto

`TODO.md` documenta que **o-tiling sigue deshabilitado** por un bug que corrompe
`stack_position` en cada ventana nueva bajo GNOME 50.1. Se probaron cuatro
mitigaciones, incluidos patches locales y un fix upstream, y **ninguna funcionó**.

Por eso:

- `OTILING_AUTO_ENABLE=false` por defecto: instalar no habilita la extensión.
- El script no afirma que los patches resuelvan el bug; son mejoras puntuales de
  comportamiento (J/K sin saltar de monitor, `auto_tile` diferido).
- La activación es manual y consciente: `gnome-extensions enable <uuid>`.

### Acciones destructivas: ahora opt-in

La versión anterior hacía tres cosas sin preguntar sobre software ajeno:

| Acción | Antes | Ahora |
|---|---|---|
| Deshabilitar y **borrar** Tiling Shell | automático | `--remove-tiling-shell` |
| Deshabilitar `ding` (iconos de escritorio) | automático | `--disable-ding` |
| Desactivar la validación de versión de extensiones de GNOME | automático | `--allow-version-mismatch` |

La última es especialmente delicada: `disable-extension-version-validation` es
**global**, afecta a todas las extensiones del usuario, no solo a o-tiling. Se
documenta con un aviso antes de aplicarse.

Sin esos flags el script solo instala/configura o-tiling e imprime qué quedó
intacto.

### Patches: propagación de fallos

Antes, `apply-patches.sh` terminaba con `echo "Patches aplicados."` y código 0
**incluso si ambos patches fallaban**, y `install.sh` escribía igualmente el
marcador `version=`. La próxima ejecución lo daba por bueno.

Ahora:

- Un archivo objetivo que no existe es un **fallo**, no un skip silencioso.
- Cualquier patch que no aplique hace que `apply-patches.sh` salga con código 1.
- `install.sh` **no escribe el marcador** si los patches fallan: la próxima
  ejecución reintenta en lugar de darlo por instalado.
- El mensaje de éxito solo aparece cuando **todos** los patches aplicaron.

### El marcador detecta cambios en los patches

El marcador guarda dos cosas:

```text
version=v2.9.21 patches=<sha256 de patches/apply-patches.sh>
```

Si cambia el script de patches pero la versión de la extensión no, el script
**reaplica los patches sin volver a descargar**. Esto resuelve el caso en que
iterabas sobre un patch y el marcador seguía diciendo "ya instalado".

## Hardware: un perfil personal, no una optimización universal

`linux/optimize.sh` aplicaba `CPU governor = performance`, `EPP = performance`,
`PPD = balanced`, `swappiness = 10` mientras el encabezado decía *"applies
optimal settings — safe to run on any Linux"*. Eso presentaba preferencias
personales como si fueran óptimas para todos.

Ahora el script se describe como **un perfil elegido por el autor para un ASUS TUF
concreto**, con `--list` para verlo antes de aplicar nada:

```bash
bash linux/optimize.sh --list
```

Todos los valores son sobrescribibles por entorno:

```bash
sudo CPU_GOVERNOR=schedutil SWAPPINESS=60 ./optimize.sh --apply
```

| Variable | Default | Alternativas |
|---|---|---|
| `CPU_GOVERNOR` | `performance` | `schedutil`, `powersave` |
| `CPU_EPP` | `performance` | `balance_performance`, `balance_power`, `power` |
| `PPD_PROFILE` | `balanced` | `performance`, `power-saver` |
| `SWAPPINESS` | `10` | `0`–`200` (60 es el default conservador) |
| `THROTTLE_POLICY` | `0` | ASUS: 0/1/2 |

El script no toca red, usuarios, firewall, shell ni software de producción. Un
test lo prohíbe explícitamente.

### La regla de batería es de un equipo concreto

`linux/99-battery-charge-threshold.rules` fija `KERNEL=="BAT1"` y umbral `60`.
El encabezado ahora avisa que **hay que revisar ambos valores** antes de
instalarlo en otra máquina: el nombre de la batería varía (`BAT0`, `BATT`, …) y
el umbral depende del uso.

No es una optimización universal ni un valor recomendado para todos los portátiles.

## Cómo probarlo

```bash
python3 -B -m unittest discover -s tests -p 'test_hardware_otiling.py' -v
```

Los tests usan `gnome-extensions`, `gsettings`, `curl`, `udevadm`, `systemctl`,
`cpupower` y `powerprofilesctl` **simulados**: nunca tocan GNOME, dconf, udev,
sysfs ni la red.

Cubren:

- La ejecución por defecto no borra ni deshabilita nada ajeno.
- Cada acción destructiva está detrás de su flag.
- Un patch fallido aborta la instalación y **no** escribe marcador.
- El marcador contiene el digest correcto del script de patches.
- Cambiar los patches reactiva su aplicación sin descargar.
- Las opciones desconocidas se rechazan con código 2.
- Un objetivo de patch ausente es fallo, no skip.
- `--list` no escribe nada y respeta las variables de entorno.
- El help ya no afirma optimizaciones universales.
- `optimize.sh` no gestiona servicios ni cuentas.

## Límites conocidos

- **o-tiling sigue sin funcionar** en GNOME 50.1 según `TODO.md`. Este punto no
  cambia eso: solo hace que el script sea honesto y no destructivo por defecto.
- `--allow-version-mismatch` sigue existiendo porque hay casos legítimos (un
  `minor` de shell que no coincide con el metadata), pero ahora exige pedirlo y
  avisa de su alcance global.
- El perfil de hardware se puede cambiar por variables, pero no se han medido
  efectos de rendimiento ni consumo con cada combinación.
- `THROTTLE_POLICY`/`PPD_PROFILE` solo son relevantes en hardware ASUS con
  `asus-wmi`; en otro hardware se omiten sin error.
- La validación de los scripts es estática y con stubs: no se ha ejecutado
  `--apply` real ni se ha instalado la extensión durante esta refactorización.
