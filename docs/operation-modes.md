# Modos de operación, diagnósticos y códigos de salida

## Modos

| Modo | Escribe config | Instala paquetes | sudo | Servicios | Red |
|---|---|---|---|---|---|
| `--dry-run` | no | no | no | no | no |
| `--check` | no | no | no | no | no |
| `--config-only` | sí | no | no | no | no |
| instalación normal | sí | sí | una fase | según opciones | sí |
| `--upgrade` | sí | sí + actualizar | una fase | según opciones | sí |
| `--hardware` / `--apply-linux` | según modo | según modo | sí | **sí, opt-in** | según modo |
| `--change-shell` | según modo | según modo | sí | no | según modo |
| `--check-sudo` | no | no | solo identidad | no | no |
| `--harden-existing-service` | no | no | acotado | no | no |

`--dry-run` y `--check` son **de solo lectura**: no crean configuración, no crean
estado del instalador y no arrancan nada. Un test verifica su huella.

> Nota: consultar una herramienta puede hacer que **esa herramienta** cree sus
> propios directorios XDG (`opencode --version`, por ejemplo). Eso no es el
> instalador escribiendo; la huella que se prohíbe es la de config y estado que
> administra este repo.

## Resumen de resultado

Al terminar, cada ejecución imprime qué ocurrió, no solo qué se planeaba:

```text
[INFO] Outcome for workstation (linux/x86_64, brew):
[INFO]   created 0 | unchanged 4 | preserved 0 | restricted 0 | skipped 0 | failed 0
```

Los conteos:

| Estado | Significado |
|---|---|
| `created` | algo nuevo: enlace, config generada, binario |
| `unchanged` | ya estaba correcto; no se tocó |
| `preserved` | existía una versión propia/independiente y **no** se sobrescribió |
| `restricted` | permisos de credenciales apretados |
| `skipped` | componente opcional ausente, sin ser error |
| `failed` | requisito obligatorio ausente o comprobación fallida |

Todo lo que no sea `unchanged` se nombra explícitamente con un prefijo:

```text
    [+] ~/.config/opencode/cli.json          # created
    [!] ~/.config/opencode/opencode.jsonc    # preserved
    [k] /repo/opencode/.env (664 -> 0600)    # restricted
    [-] optional tool absent: atuin          # skipped
    [x] required tool missing: git           # failed
```

Así se distingue de un vistazo un "todo correcto" de un "instaló pero dejó cosas
a medias".

## Códigos de salida

| Código | Cuándo |
|---|---|
| `0` | el modo terminó sin fallos registrados |
| `1` | un requisito obligatorio falta o una comprobación falló |
| `2` | argumento desconocido, valor faltante o combinación inválida |

**Nunca se informa «Completed» tras un fallo esencial.** La línea final dice
`Completed: <perfil>` solo cuando `failed 0`; si no, `Completed WITH FAILURES` y
el código de salida es `1`. `--check` hace lo mismo con `Verification passed` /
`Verification FAILED`.

## Validación de argumentos

Se rechazan, con código `2`:

- Flags sin valor: `--profile`, `--profile --check`, `--package-manager`
- Valores vacíos: `--profile ""`, `--package-manager ""`
- Valores fuera del enum: `--profile desktop`, `--package-manager apt`
- Flags desconocidos y argumentos posicionales: `--nope`, `extra`
- Combinaciones de modos incompatibles (ver la tabla de arriba)

## Diagnóstico

`--dry-run` imprime el plan completo antes de tocar nada, incluidas las acciones
opt-in seleccionadas y las versiones mínimas declaradas:

```bash
bash setup.sh --profile workstation --dry-run --hardware --change-shell
```

`--check` imprime el mismo plan, ejecuta la verificación y termina con el resumen
de resultado. Es el comando que conviene ejecutar tras una instalación o tras un
`git pull`.

El detalle de los instaladores externos va al log (`~/.local/state/portillo-dots/
setup.log`, modo `0600`); el resumen de la pantalla no intenta sustituirlo.

## Cómo probarlo

```bash
python3 -B -m unittest discover -s tests -p 'test_operation_modes.py' -v
```

Cubre:

- `--dry-run` y `--check` sin huella de instalador
- código de salida `1` cuando falta una herramienta obligatoria
- el resumen nombra `created` / `preserved` / `failed`
- un fallo produce `Completed WITH FAILURES` y **no** `Completed:`
- `--config-only` nunca invoca sudo
- valores faltantes, enums inválidos, flags desconocidos y combinaciones
  conflictivas se rechazan sin escribir nada

## Límites conocidos

- El resumen clasifica lo que el instalador decidió hacer; no inventaría el
  sistema completo ni detecta software instalado por otras vías.
- Los códigos `2` cubren el parser de `setup.sh`; los fallos internos de un
  instalador externo se propagan con su propio código dentro del log.
- No se ha probado `--interactive` con un TTY real, ni el flujo de cancelación
  con un teclado físico.
- `--upgrade` actualiza lo que los gestores de paquetes permiten; la política de
  versiones concretas queda fuera de este modo.
