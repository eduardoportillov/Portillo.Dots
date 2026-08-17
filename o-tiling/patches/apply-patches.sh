#!/usr/bin/env bash
set -uo pipefail

# =====================================================================
# Patches locales para o-tiling
# =====================================================================
# Aplica fixes al código instalado de o-tiling. Idempotente (marker).
#
# Uso:  bash apply-patches.sh [EXT_DIR]
# EXT_DIR = ~/.local/share/gnome-shell/extensions/o-tiling@oliwebd.github.com

EXT_DIR="${1:-$HOME/.local/share/gnome-shell/extensions/o-tiling@oliwebd.github.com}"

if [[ ! -d "$EXT_DIR" ]]; then
  echo "Error: $EXT_DIR no existe." >&2
  exit 1
fi

# =====================================================================
# PATCH 1: move vertical (J/K) se queda en el mismo monitor
# =====================================================================
# Problema: move_up/move_down usan move_window_or_monitor(..., UP/DOWN), que si no
# hay ventana vecina cae al MONITOR de esa dirección. Con monitores lado a lado, mover
# vertical (J/K) en el borde salta al otro monitor — molesto. Queremos que J/K solo
# reacomode VERTICAL en el MISMO monitor (y no haga nada si no hay vecina). El move
# horizontal (H/L) se deja igual (cruzar monitor es deseado).
# Fix: helper same_monitor_window() que devuelve la vecina solo si está en el mismo
# monitor (si no, null → move() no hace nada); move_up/move_down lo usan.
patch_vertical_same_monitor() {
  local file="$EXT_DIR/engine/tiling.js"
  if [[ ! -f "$file" ]]; then
    echo "  ⚠ $file no existe — skip"
    return 0
  fi
  if grep -q "PORTILLO.DOTS PATCH: same_monitor_window" "$file"; then
    echo "  ✓ tiling.js ya patched (skip)"
    return 0
  fi

  python3 - "$file" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
src = p.read_text()

helper = '''// PORTILLO.DOTS PATCH: same_monitor_window — para el move vertical (J/K), devuelve
// la ventana vecina SOLO si está en el mismo monitor que la enfocada; si no, null
// (move() lo trata como no-op). Evita que J/K salte al otro monitor en el borde.
function same_monitor_window(ext, method) {
    return () => {
        const focus = ext.focus_window();
        let w = method.call(ext.focus_selector, ext, null);
        w = w?.actor_exists() ? w : null;
        if (w && focus && w.meta.get_monitor() === focus.meta.get_monitor())
            return w;
        return null;
    };
}
function move_window_or_monitor('''

# 1) Insertar el helper justo antes de la función move_window_or_monitor
anchor = 'function move_window_or_monitor('
if anchor not in src:
    print("  ⚠ tiling.js: no se encontró 'function move_window_or_monitor(' — ¿cambió upstream?")
    sys.exit(2)
if src.count(anchor) != 1:
    print("  ⚠ tiling.js: 'function move_window_or_monitor(' aparece más de una vez — abort")
    sys.exit(2)
src = src.replace(anchor, helper, 1)

# 2) Cambiar move_down y move_up para usar same_monitor_window
repls = [
    ("move_window_or_monitor(ext, ext.focus_selector.down, Meta.DisplayDirection.DOWN)",
     "same_monitor_window(ext, ext.focus_selector.down)"),
    ("move_window_or_monitor(ext, ext.focus_selector.up, Meta.DisplayDirection.UP)",
     "same_monitor_window(ext, ext.focus_selector.up)"),
]
for old, new in repls:
    if old not in src:
        print(f"  ⚠ tiling.js: patrón no encontrado: {old[:50]}... — abort")
        sys.exit(2)
    src = src.replace(old, new, 1)

p.write_text(src)
print("  ✓ tiling.js patched (move vertical J/K = mismo monitor)")
PY
}

# =====================================================================
# PATCH 2: diferir auto_tile() en notify::wm-class al próximo redraw
# =====================================================================
# Problema: wm_class_changed() (window/window.js) llama a auto_tile() de forma
# SINCRÓNICA dentro del callback de la señal 'notify::wm-class', que es de las
# primeras señales que Mutter emite para una ventana recién creada — a veces
# antes de que Mutter termine de asentar el stack_position interno de esa
# ventana. Tilear ahí mismo puede pisar meta_window_set_stack_position_no_sync
# (assertion 'window->stack_position >= 0' failed), lo que corrompe el tile
# silenciosamente (la ventana queda flotando, sin error visible en JS).
# Fix: diferir auto_tile() al próximo Meta.LaterType.BEFORE_REDRAW (misma API
# de "later" que el propio forest.js ya usa para reintentos de move_window),
# para que corra después de que Mutter estabilizó el estado de la ventana.
patch_defer_auto_tile() {
  local file="$EXT_DIR/window/window.js"
  if [[ ! -f "$file" ]]; then
    echo "  ⚠ $file no existe — skip"
    return 0
  fi
  if grep -q "PORTILLO.DOTS PATCH: defer auto_tile" "$file"; then
    echo "  ✓ window.js ya patched (skip)"
    return 0
  fi

  python3 - "$file" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
src = p.read_text()

old = '''    wm_class_changed() {
        if (this.is_tilable(this.ext)) {
            this.ext.connect_window(this);
            if (!this.meta.minimized) {
                this.ext.auto_tiler?.auto_tile(this.ext, this);
            }
        }
    }'''

new = '''    wm_class_changed() {
        if (this.is_tilable(this.ext)) {
            this.ext.connect_window(this);
            if (!this.meta.minimized) {
                // PORTILLO.DOTS PATCH: defer auto_tile to the next compositor redraw
                // tick. notify::wm-class can fire before Mutter has fully settled the
                // new window's internal stacking state; tiling synchronously here can
                // hit meta_window_set_stack_position_no_sync (assertion
                // 'stack_position >= 0'), which silently corrupts the tile.
                lib.later_add(Meta.LaterType.BEFORE_REDRAW, () => {
                    if (this.actor_exists() && !this.meta.minimized) {
                        this.ext.auto_tiler?.auto_tile(this.ext, this);
                    }
                    return GLib.SOURCE_REMOVE;
                });
            }
        }
    }'''

if old not in src:
    print("  ⚠ window.js: no se encontró el cuerpo exacto de wm_class_changed() — ¿cambió upstream?")
    sys.exit(2)
if src.count(old) != 1:
    print("  ⚠ window.js: el patrón aparece más de una vez — abort")
    sys.exit(2)
src = src.replace(old, new, 1)

p.write_text(src)
print("  ✓ window.js patched (auto_tile diferido a BEFORE_REDRAW)")
PY
}

echo "Aplicando patches a o-tiling..."
patch_vertical_same_monitor
patch_defer_auto_tile
echo "Patches aplicados."
