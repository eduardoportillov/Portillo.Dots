# Scripts independientes: hardware y o-tiling

Estos scripts **no se ejecutan automáticamente** desde `setup.sh`. Siguen en el
repo porque se usan manualmente, y porque un servicio instalado en el pasado
ejecuta uno de ellos. Su contrato es: explícitos, verificables, y sin prometer
resolver el fallo upstream que sigue abierto.

## o-tiling

### Estado real del proyecto

`TODO.md` documenta que `meta_window_set_stack_position_no_sync` es un bug
**abierto** ([oliwebd/o-tiling#50](https://github.com/oliwebd/o-tiling/issues/50)).
Se probaron cuatro mitigaciones —incluidas dos en código local y un fix
upstream— y **ninguna resolvió el problema** en `v2.9.21`.

La versión actual es **`v2.12.01`** (28-sep-2026). Trae cambios en `stacking
sync`, `layout reconstruction`, un guard en `raise()` y soporte para GNOME 51,
pero **el issue sigue abierto y sin confirmar**. Por eso no se da por buena sin
verificar.

### Upstream puro: cero parches manuales

Decisión tomada: **la extensión se usa tal cual la publica su autor**.

| Se hace | No se hace |
|---|---|
| Instalar el ZIP del release | Modificar `tiling.js` / `window.js` |
| Aplicar `configure.sh` (gsettings) | Aplicar parches o workarounds |
| Verificar con `verify.sh` | Desactivar validación de versiones de GNOME |
| Deshabilitar y esperar si falla | Mantener una copia parcheada de código ajeno |

Por eso se eliminó el directorio `o-tiling/patches/`. Se pierde el comportamiento
que aportaban esos parches: `Alt+Shift+J/K` ya no queda limitado al monitor
actual y **puede cruzar de monitor en el borde**. Ese es el comportamiento
upstream y se acepta.

El marcador de instalación contiene solo la versión:

```text
version=v2.12.01
```

### Verificación de aceptación

`o-tiling/verify.sh` orquesta la prueba y emite veredicto:

```bash
bash o-tiling/verify.sh prepare      # instala, habilita e imprime la lista
# ... logout + login, seguir bloques A-E ...
bash o-tiling/verify.sh integrity    # opcional: ¿la extensión está intacta?
bash o-tiling/verify.sh report       # journal + veredicto + retirada si falla
```

- **`integrity`** descarga el ZIP del release y compara hashes contra lo
  instalado. Detecta cualquier modificación manual, incluidos los artefactos que
  generamos nosotros (`.installed-version`, `gschemas.compiled`) y los excluye.
- **`report`** escanea `journalctl --user` en busca de `stack_position` /
  `_syncStacking` / `JS ERROR`, pide PASS/FAIL por bloque y decide.

**Regla de retirada automática:** si falla el bloque A o B, o aparece una
assertion en el journal, `verify.sh` **deshabilita la extensión** y registra
«esperando parche upstream». Un fallo en C2 (`Alt+Shift+J/K` cruzando monitor)
**no** cuenta como fallo: es comportamiento upstream.

### Acciones destructivas: opt-in

Tres acciones afectan a software ajeno y siguen tras flags explícitos:

| Acción | Flag |
|---|---|
| Deshabilitar y **borrar** Tiling Shell | `--remove-tiling-shell` |
| Deshabilitar `ding` (iconos de escritorio) | `--disable-ding` |
| Desactivar la validación de versión de extensiones de GNOME | `--allow-version-mismatch` |

La última es global — afecta a todas las extensiones del usuario — y se avisa
antes de aplicarse.

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
- El marcador contiene **solo** la versión del release upstream.
- El directorio de la extensión instalada solo recibe `.installed-version`:
  ninguna escritura de código, ningún parche.
- `o-tiling/patches/` no existe y el instalador no referencia ningún mecanismo
  de parcheo local.
- El pin es `v2.12.01`, la última release conocida.
- El help afirma explícitamente que no se modifica ningún archivo.
- `verify.sh` existe, es ejecutable y documenta prepare/integrity/report/status.
- Un assertion del bug conocido en el journal **deshabilita** la extensión.
- Un fallo en el bloque A o B **deshabilita** la extensión.
- Una ejecución limpia la **mantiene habilitada**.
- C2 (J/K cruzando de monitor) **no** se trata como fallo del núcleo.
- Ninguna referencia al flujo de parches retirado sobrevive en el repo.
- Las opciones desconocidas se rechazan con código 2.
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
- **`v2.12.01` no está validada en el escritorio.** El veredicto depende de la
  ejecución manual de `verify.sh`; hasta entonces el bug se considera abierto.
