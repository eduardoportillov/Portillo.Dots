# o-tiling — tiling BSP dinámico (reemplazo de Forge)

Extensión de tiling para GNOME Shell, estilo i3/AeroSpace. Fork de Pop Shell.

- **UUID:** `o-tiling@oliwebd.github.com`
- **Versión pineada:** `OTILING_VERSION` en `install.sh` (actual `v2.12.01`)
- **Instalar/actualizar:** `bash o-tiling/install.sh --force` → **logout + login** (Wayland)
- **Verificar:** `bash o-tiling/verify.sh prepare` … `verify.sh report`

## Upstream puro — sin parches locales

La extensión se instala **byte a byte como la publica su autor**. Este repo:

- ✅ instala el ZIP del release
- ✅ aplica `configure.sh` (gsettings: atajos, gaps, auto-tiling)
- ❌ **no** modifica `tiling.js`, `window.js` ni ningún archivo de la extensión
- ❌ **no** aplica parches ni workarounds
- ❌ **no** desactiva la validación de versiones de GNOME salvo petición explícita

Si el release tiene un bug, se reporta y **se espera al fix de upstream**. No se
mantiene una copia parcheada del código de un tercero.

`verify.sh integrity` descarga el ZIP del release y compara hashes contra lo
instalado: si algo se modificó, lo detecta y falla.

## Atajos

| Acción | Atajo |
|---|---|
| **Foco** entre ventanas (navegar) | `Ctrl+Alt+H/J/K/L` |
| **Mover** horizontal (cruza al otro monitor al borde) | `Shift+Alt+H/L` |
| **Mover** vertical (reacomoda arriba/abajo) | `Shift+Alt+J/K` |
| **Orientación** del grupo: horizontal ↔ vertical | `Alt+/` |
| **Float / unfloat** ventana | `Shift+Super+C` |
| **Workspaces** (GNOME, no o-tiling) | `Alt+1..5` cambiar · `Alt+Shift+1..5` mover ventana |

- Gaps de tiling = **1px** (`gap-inner` / `gap-outer`).
- Convención: `Ctrl+Alt` = **navegar foco**; `Shift+Alt` = **mover ventana**.

> ⚠ `Super+T` (toggle auto-tiling) y `Super+Return` (modo resize) aparecían en
> versiones anteriores de este README pero **no están en `configure.sh`**. Si la
> extensión los trae por defecto, funcionarán; si no, hay que documentar que no
> existen. Verificar antes de darlos por válidos.

## ⚠️ Comportamiento vertical de `Shift+Alt+J/K` (upstream)

Con el paso a upstream puro, **ya no aplica el parche local** que impedía a
`J/K` saltar de monitor. El comportamiento ahora es el de la extensión tal cual:

- **`Shift+Alt+H/L`** (horizontal): si no hay ventana al lado, **cruza al otro
  monitor** (deseado con monitores lado a lado).
- **`Shift+Alt+J/K`** (vertical): reacomoda arriba/abajo; **al llegar al borde
  puede cruzar al otro monitor**. Eso es upstream, no es un fallo.

Si esa diferencia llegara a importar, habría que mantener un parche local, que
es justo lo que se decidió eliminar. Se acepta el comportamiento de upstream.

## ⚠️ Apilar ventanas en VERTICAL (caso importante)

o-tiling es **BSP**: las ventanas forman un árbol con un **eje**. Por eso el
vertical es de **dos pasos**:

1. Con 2 ventanas **lado a lado** (horizontal), tienen relación
   izquierda/derecha → `Shift+Alt+H/L` las mueve, y `J/K` **no hace nada**.
2. Apretás **`Alt+/`** → el grupo pasa a **vertical** (una arriba, otra abajo).
3. Recién ahí `Ctrl+Alt+J/K` (foco) y `Shift+Alt+J/K` (mover) actúan vertical.

**No es un bug:** `Alt+/` no «habilita» J/K — **define el eje**.

## Diferencias con AeroSpace sin equivalente

- **Acordeón** (`Alt+,` en AeroSpace) = modo *stacking* en o-tiling → es la ruta
  del crash de Pop Shell (`stack_position`). Se deja **desactivado**.
- **Resize de una sola tecla** (AeroSpace `alt-minus/equal`): o-tiling solo
  redimensiona en su modo gestión. No hay `tile-resize-*-global`.
- **`Alt+Tab` back-and-forth** y **mover workspace a otro monitor**: sin
  equivalente directo.

## ⚠️ Estado del bug de stacking

`meta_window_set_stack_position_no_sync` sigue siendo un bug abierto
([oliwebd/o-tiling#50](https://github.com/oliwebd/o-tiling/issues/50)). La
versión `v2.12.01` incluye cambios en `stacking sync`, `layout reconstruction` y
`raise()`, pero **el issue no está cerrado ni confirmado**.

Por eso la extensión se instala y **se verifica** con `verify.sh` antes de
darla por buena. Si el bug reaparece:

1. `verify.sh report` la **deshabilita automáticamente**.
2. Se registra la versión probada y la fecha.
3. Se queda **esperando el fix de upstream** — sin parches ni workarounds.

## Recuperación (solo reseteo, no parche)

- **`Super+Shift+R`** (atajo) o **`dots-fix-tiling`** — disable→enable sin logout.
  Re-arma el árbol si el tiling se degrada.
- Si no alcanza: **logout/login**.
- `dots-diag` — captura la firma del bug para reportar upstream.
- Solo puede haber **UN tiler activo**: dos a la vez corrompen el window-stack.

## ding (íconos del escritorio)

Por defecto **no se toca**. Solo se desactiva con `install.sh --disable-ding`
(OPT-IN). En Wayland `ding` puede robar foco/input a las ventanas tileadas.

## Archivos

- `install.sh` — instala el release upstream y aplica gsettings. **No parchea.**
- `configure.sh` — gsettings (atajos, gaps, auto-tiling). Idempotente.
- `verify.sh` — protocolo de aceptación, verificación de integridad y retirada
  automática si falla el núcleo.
