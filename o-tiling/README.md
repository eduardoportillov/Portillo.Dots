# o-tiling — tiling BSP dinámico (reemplazo de Forge)

Extensión de tiling para GNOME Shell 50.1, estilo i3/AeroSpace. Fork de Pop Shell.
Instalada y configurada por `./setup.sh` (scripts en esta carpeta).

- **UUID:** `o-tiling@oliwebd.github.com`
- **Versión pineada:** `OTILING_VERSION` en `install.sh` (actual `v2.9.21`)
- **Instalar/actualizar:** `bash o-tiling/install.sh --force` → **logout + login** (Wayland)

## Atajos

| Acción | Atajo |
|---|---|
| **Foco** entre ventanas (navegar) | `Ctrl+Alt+H/J/K/L` |
| **Mover** horizontal (cruza al otro monitor en el borde) | `Shift+Alt+H/L` |
| **Mover** vertical (reacomoda en el MISMO monitor, no salta) | `Shift+Alt+J/K` |
| **Orientación** del grupo: horizontal ↔ vertical | `Alt+/` |
| **Float / unfloat** ventana | `Shift+Super+C` |
| **Toggle** auto-tiling on/off | `Super+T` |
| **Redimensionar** (modo gestión) | `Super+Return` → `Shift+H/L` (o `Shift+J/K`) → `Return` |
| **Workspaces** (GNOME, no o-tiling) | `Alt+1..5` cambiar · `Alt+Shift+1..5` mover ventana |

- Gaps de tiling = **1px** (`gap-inner` / `gap-outer`).
- Convención: `Ctrl+Alt` = **navegar foco**; `Shift+Alt` = **mover ventana**.

## ⚠️ Apilar ventanas en VERTICAL (caso importante)

o-tiling es **BSP**: las ventanas forman un árbol con un **eje**, y las teclas siguen la
disposición física. Por eso el vertical es de **dos pasos**:

1. Con 2 ventanas **lado a lado** (horizontal), tienen relación **izquierda/derecha** →
   `Shift+Alt+H/L` las mueve, y `J/K` **no hace nada** (no hay nada arriba/abajo).
2. Apretás **`Alt+/`** → el grupo pasa a **vertical** (una arriba, otra abajo).
3. Recién ahí `Ctrl+Alt+J/K` (foco) y `Shift+Alt+J/K` (mover) actúan **vertical**.

**No es un bug:** `Alt+/` no "habilita" J/K — **define el eje**. J/K siempre opera sobre
el eje vertical, que existe solo cuando las ventanas están apiladas vertical.

> Diferencia con AeroSpace: allá el `move` a veces crea el split vertical solo (un paso).
> o-tiling **no** lo hace nativamente (se decidió dejarlo en dos pasos por estabilidad;
> auto-splittear requeriría parchear el core del tiler, con riesgo de romperlo).

## Mover H/L vs J/K (patch local)

`patches/apply-patches.sh` parchea `engine/tiling.js` (`move_up`/`move_down` usan
`same_monitor_window()`):

- **`Shift+Alt+H/L`** (horizontal): si no hay ventana al lado, **cruza al otro monitor**
  (deseado, monitores lado a lado).
- **`Shift+Alt+J/K`** (vertical): reacomoda **solo en el mismo monitor**; si no hay vecina
  arriba/abajo, **no hace nada** (no salta de monitor). Upstream sí saltaba.

El patch se reaplica solo desde `install.sh` (idempotente, marker `PORTILLO.DOTS PATCH`).
Toma efecto tras **logout/login** (Wayland recarga el JS de la extensión).

## Diferencias con AeroSpace sin equivalente

- **Acordeón** (`Alt+,` en AeroSpace) = modo *stacking* en o-tiling → es la ruta del crash
  de Pop Shell (`stack_position`, pop-os/shell#647). Se deja **desactivado**.
- **Resize de una sola tecla** (AeroSpace `alt-minus/equal`): o-tiling solo redimensiona en
  su modo gestión (ver tabla). No hay `tile-resize-*-global`.
- **`Alt+Tab` back-and-forth** y **mover workspace a otro monitor**: sin equivalente directo.

Para un i3/AeroSpace 100% idéntico haría falta un compositor nativo (Sway/Hyprland), que
implica salir de GNOME — se decidió quedarse en GNOME con o-tiling.

## ⚠️ Caveat conocido: corrupción de stack (heredada de Pop Shell)

o-tiling **a veces corrompe el window-stack de Mutter** (`stack_position`, bug de Pop Shell
pop-os/shell#647 — el mismo que tenía Forge). No es constante: anda bien y se degrada con el
uso. **Síntoma típico:** al cerrar una ventana el tiling **no reacomoda** y cuenta la cerrada
como abierta. Se decidió quedarse con o-tiling (BSP) y **resetear cuando pase**.

## Recuperación

- **`Super+Shift+R`** (atajo) o **`dots-fix-tiling`** (comando) — disable→enable o-tiling sin
  logout: re-arma el árbol y vuelve a la normalidad. **Es el reset cuando el tiling se rompe.**
- Si no alcanza: **logout/login**.
- `dots-diag` — captura la firma del bug de stacking si algo se rompe (para reportar upstream).
- Solo puede haber **UN tiler activo** — dos a la vez corrompen el window-stack de Mutter.

## ding (íconos del escritorio) — DESACTIVADO

`ding@rastersoft.com` se deja **apagado** (`install.sh` lo desactiva). En Wayland le robaba el
foco/input a las ventanas tileadas: la ventana se veía pero el escritorio recibía el input
(aparecía el rubber-band de íconos al intentar seleccionar). En tiling no se usan iconos del
escritorio. Para reactivarlo (no recomendado): `gnome-extensions enable ding@rastersoft.com`.

## Archivos

- `install.sh` — instala desde release ZIP de GitHub, desmonta Tiling Shell, aplica patches.
- `configure.sh` — gsettings (atajos, gaps, auto-tiling). Idempotente.
- `patches/apply-patches.sh` — fix del move vertical (mismo monitor).
