#!/usr/bin/env bash
set -uo pipefail

# =====================================================================
# Patches locales para Forge main
# =====================================================================
# Aplica fixes al código instalado de Forge que NO están aún en upstream.
# Idempotente: si el patch ya está aplicado, no hace nada.
#
# Uso:  bash apply-patches.sh <EXT_DIR>
# Donde EXT_DIR = ~/.local/share/gnome-shell/extensions/forge@jmmaranan.com

EXT_DIR="${1:-$HOME/.local/share/gnome-shell/extensions/forge@jmmaranan.com}"

if [[ ! -d "$EXT_DIR" ]]; then
  echo "Error: $EXT_DIR no existe." >&2
  exit 1
fi

# =====================================================================
# PATCH 1: fix-indicator-disposed
# =====================================================================
# Bug upstream: lib/extension/indicator.js:121-127 conecta un listener a
# settings."changed" que toca this._indicator.visible. Cuando la extensión
# se desactiva/reactiva, _indicator queda disposed pero el listener sobrevive,
# y cualquier cambio de setting (incluido el toggle off→on de tiling-mode-
# enabled que hacemos al login) crashea con "St.Icon already disposed".
# Fix: envolver en try/catch + guard.
#
# Issue: https://github.com/forge-ext/forge/issues (sin reporte aún)
# =====================================================================
patch_indicator() {
  local file="$EXT_DIR/lib/extension/indicator.js"
  if [[ ! -f "$file" ]]; then
    echo "  ⚠ $file no existe — skip"
    return 0
  fi

  if grep -q "PORTILLO.DOTS PATCH: guard contra listener fantasma" "$file"; then
    echo "  ✓ indicator.js ya patched (skip)"
    return 0
  fi

  python3 - "$file" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
src = p.read_text()

old = '''    this.extension.settings.connect("changed", (_, name) => {
      switch (name) {
        case "tiling-mode-enabled":
        case "quick-settings-enabled":
          this._indicator.visible = this.extension.settings.get_boolean(name);
      }
    });'''

new = '''    // PORTILLO.DOTS PATCH: guard contra listener fantasma cuando _indicator
    // fue disposed (bug upstream forge-ext/forge indicator.js).
    this.extension.settings.connect("changed", (_, name) => {
      try {
        if (!this._indicator) return;
        switch (name) {
          case "tiling-mode-enabled":
          case "quick-settings-enabled":
            this._indicator.visible = this.extension.settings.get_boolean(name);
        }
      } catch (e) {
        // Indicator destroyed — listener fantasma, ignore silently.
      }
    });'''

if old in src:
    p.write_text(src.replace(old, new))
    print("  ✓ indicator.js patched (fix-indicator-disposed)")
else:
    print("  ⚠ indicator.js: patrón original NO encontrado (¿upstream cambió?)")
    sys.exit(2)
PY
}

# =====================================================================
# Aplicar patches
# =====================================================================
echo "Aplicando patches a Forge..."
patch_indicator
echo "Patches aplicados."
