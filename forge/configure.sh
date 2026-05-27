#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# SCRIPT MAESTRO: CLONACIÓN AEROSPACE -> FORGE (LINUX)
# =====================================================================
# Este script iguala el comportamiento de GNOME Forge al de AeroSpace.
# Fuente de verdad: Configuración .toml de macOS.

echo "Iniciando configuración maestra de Forge..."

FORGE_UUID="${FORGE_UUID:-forge@jmmaranan.com}"
FORGE_SCHEMA_DIR="${FORGE_SCHEMA_DIR:-$HOME/.local/share/gnome-shell/extensions/$FORGE_UUID/schemas}"

if ! command -v gsettings >/dev/null 2>&1; then
  echo "Error: gsettings no está disponible." >&2
  exit 1
fi

if [[ -d "$FORGE_SCHEMA_DIR" ]]; then
  export GSETTINGS_SCHEMA_DIR="$FORGE_SCHEMA_DIR"
fi

if ! gsettings list-schemas | grep -qx 'org.gnome.shell.extensions.forge'; then
  echo "Error: no se encontró el schema org.gnome.shell.extensions.forge." >&2
  echo "Ruta esperada: $FORGE_SCHEMA_DIR" >&2
  exit 1
fi

# ---------------------------------------------------------------------
# 1. GAPS Y APARIENCIA (AeroSpace: 3px)
# ---------------------------------------------------------------------
gsettings set org.gnome.shell.extensions.forge tiling-mode-enabled true
gsettings set org.gnome.shell.extensions.forge auto-split-enabled true
gsettings set org.gnome.shell.extensions.forge primary-layout-mode "'tiling'"
gsettings set org.gnome.shell.extensions.forge workspace-skip-tile "''"
gsettings set org.gnome.shell.extensions.forge window-gap-size 3
gsettings set org.gnome.shell.extensions.forge focus-border-toggle false
gsettings set org.gnome.shell.extensions.forge split-border-toggle false

# ---------------------------------------------------------------------
# 2. NAVEGACIÓN (FOCO) - Identico a AeroSpace (Alt+Ctrl+HJKL)
# Propósito: Evitar conflictos con tmux y apps internas.
# ---------------------------------------------------------------------
gsettings set org.gnome.shell.extensions.forge.keybindings window-focus-left "['<Alt><Control>h']"
gsettings set org.gnome.shell.extensions.forge.keybindings window-focus-down "['<Alt><Control>j']"
gsettings set org.gnome.shell.extensions.forge.keybindings window-focus-up "['<Alt><Control>k']"
gsettings set org.gnome.shell.extensions.forge.keybindings window-focus-right "['<Alt><Control>l']"

# ---------------------------------------------------------------------
# 3. MOVIMIENTO DE VENTANAS (Alt+Shift+HJKL)
# ---------------------------------------------------------------------
gsettings set org.gnome.shell.extensions.forge.keybindings window-move-left "['<Alt><Shift>h']"
gsettings set org.gnome.shell.extensions.forge.keybindings window-move-down "['<Alt><Shift>j']"
gsettings set org.gnome.shell.extensions.forge.keybindings window-move-up "['<Alt><Shift>k']"
gsettings set org.gnome.shell.extensions.forge.keybindings window-move-right "['<Alt><Shift>l']"

# ---------------------------------------------------------------------
# 5. LAYOUTS, MONITORES Y VENTANA FLOTANTE (Identico a AeroSpace)
# ---------------------------------------------------------------------
# Cambiar entre mosaico horizontal/vertical (Alt + /)
gsettings set org.gnome.shell.extensions.forge.keybindings con-split-layout-toggle "['<Alt>slash']"

# Cambiar a modo Tabulado/Acordeón (Alt + ,)
gsettings set org.gnome.shell.extensions.forge.keybindings con-tabbed-layout-toggle "['<Alt>comma']"

# window-toggle-float DESHABILITADO: hace toggle "one-shot" pero no respeta
# always-float, lo cual confunde (ventana queda float sin poder volver). El
# binding correcto para float/tile es window-toggle-always-float (Shift+Super+C),
# que es sticky y siempre alterna bien.
gsettings set org.gnome.shell.extensions.forge.keybindings window-toggle-float "[]"

# ---------------------------------------------------------------------
# NO FUNCIONA TODAVIA - REDIMENSIONAR (Resize smart - Alt + Minus/Equal)
# ---------------------------------------------------------------------
# Desactiva los atajos de Gaps que están robando el comando
gsettings set org.gnome.shell.extensions.forge.keybindings window-gap-size-decrease "[]"
gsettings set org.gnome.shell.extensions.forge.keybindings window-gap-size-increase "[]"

# AeroSpace: Alt + Minus (Achicar ventana)
# Forzamos el decremento del tamaño del contenedor
gsettings set org.gnome.shell.extensions.forge.keybindings window-resize-right-decrease "['<Alt>minus']"
gsettings set org.gnome.shell.extensions.forge.keybindings window-resize-bottom-decrease "['<Alt>minus']"

# Forzamos el incremento del tamaño del contenedor derecho/inferior simultáneamente
gsettings set org.gnome.shell.extensions.forge.keybindings window-resize-right-increase "['<Alt>equal']"
gsettings set org.gnome.shell.extensions.forge.keybindings window-resize-bottom-increase "['<Alt>equal']"

# ---------------------------------------------------------------------
# 7. EXTRAS Y LIMPIEZA DE CONFLICTOS
# ---------------------------------------------------------------------
# prefs-tiling-toggle DESHABILITADO: dispara un bug en lib/extension/indicator.js:125
# de Forge main (commit 0319a712): "Object St.Icon already disposed". El listener
# del indicator no se desconecta al destruirse y cualquier cambio de la setting
# tiling-mode-enabled lo activa, dejando ventanas en estado inconsistente
# (modo acordeón residual). Al re-habilitar el binding cuando upstream haga
# release con el fix, restaurar a "['<Alt><Shift>r']".
gsettings set org.gnome.shell.extensions.forge.keybindings prefs-tiling-toggle "[]"

# Desactivar atajos de Forge que causan conflictos
gsettings set org.gnome.shell.extensions.forge.keybindings window-snap-center "[]"

# ---------------------------------------------------------------------
# 8. RE-ASERCIÓN DEFENSIVA DEL TILING AUTOMÁTICO
# ---------------------------------------------------------------------
# Si una sesión previa o un toggle accidental dejó el tiling apagado, lo
# forzamos de vuelta al final. El gsetting es el último estado conocido —
# Forge lo lee al iniciar la sesión y al cambiar de workspace.
gsettings set org.gnome.shell.extensions.forge tiling-mode-enabled true
gsettings set org.gnome.shell.extensions.forge auto-split-enabled true
gsettings set org.gnome.shell.extensions.forge primary-layout-mode "'tiling'"
gsettings set org.gnome.shell.extensions.forge workspace-skip-tile "''"

# ---------------------------------------------------------------------
# 9. LIMPIAR OVERRIDES ACCIDENTALES EN windows.json
# ---------------------------------------------------------------------
# Forge persiste en ~/.config/forge/config/windows.json cuando el usuario
# hace Shift+Super+C sobre una ventana. Limpiamos overrides de apps que
# SIEMPRE deben tilearse en este setup (alacritty, terminales, browsers).
FORGE_WINDOWS_JSON="$HOME/.config/forge/config/windows.json"
if [[ -f "$FORGE_WINDOWS_JSON" ]] && command -v python3 >/dev/null 2>&1; then
  python3 - "$FORGE_WINDOWS_JSON" <<'PY'
import json
import sys
from pathlib import Path

cfg = Path(sys.argv[1])
data = json.loads(cfg.read_text())
# Clases que NUNCA deben ser flotantes en este setup
NEVER_FLOAT = {"Alacritty", "alacritty"}
before = len(data.get("overrides", []))
data["overrides"] = [
    o for o in data.get("overrides", [])
    if not (o.get("wmClass") in NEVER_FLOAT and "wmTitle" not in o)
]
after = len(data["overrides"])
if before != after:
    cfg.write_text(json.dumps(data, indent=4))
    print(f"forge/configure: removidos {before - after} overrides de always-float (alacritty)")
PY
fi

echo "¡Hecho! Tu Linux ahora se comporta exactamente como tu Mac con AeroSpace."
echo ""
echo "Para float/tile usa: Shift+Super+C (toggle always-float, único confiable)"
echo "Alt+Shift+; y Alt+Shift+R deshabilitados:"
echo "  - Alt+Shift+; (toggle-float): no respeta always-float, deja stuck en float"
echo "  - Alt+Shift+R (prefs-tiling-toggle): dispara bug del St.Icon en Forge main"
