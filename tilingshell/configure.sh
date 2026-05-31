#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# SCRIPT MAESTRO: configuración de Tiling Shell (Linux)
# =====================================================================
# Replica el comportamiento que teníamos con Forge / AeroSpace: tiling BSP
# automático + navegación vim (Alt+Ctrl+HJKL foco, Alt+Shift+HJKL mover).
# Fuente de verdad: este script (idempotente vía gsettings).

echo "Configurando Tiling Shell..."

TILINGSHELL_UUID="${TILINGSHELL_UUID:-tilingshell@ferrarodomenico.com}"
TS_SCHEMA_DIR="${TS_SCHEMA_DIR:-$HOME/.local/share/gnome-shell/extensions/$TILINGSHELL_UUID/schemas}"
S="org.gnome.shell.extensions.tilingshell"

if ! command -v gsettings >/dev/null 2>&1; then
  echo "Error: gsettings no está disponible." >&2
  exit 1
fi

# El schema de la extensión no está en el path global; lo apuntamos.
if [[ -d "$TS_SCHEMA_DIR" ]]; then
  export GSETTINGS_SCHEMA_DIR="$TS_SCHEMA_DIR"
fi

if ! gsettings list-schemas | grep -qx "$S"; then
  echo "Error: no se encontró el schema $S." >&2
  echo "Ruta esperada: $TS_SCHEMA_DIR" >&2
  echo "¿Instalaste Tiling Shell y hiciste logout+login? (bash tilingshell/install.sh)" >&2
  exit 1
fi

# ---------------------------------------------------------------------
# 1. TILING AUTOMÁTICO + APARIENCIA
# ---------------------------------------------------------------------
gsettings set $S enable-tiling-system true      # sistema de tiling al arrastrar
gsettings set $S enable-autotiling true         # ventanas NUEVAS se auto-tilean (BSP)
gsettings set $S enable-snap-assist true        # asistente de snap al mover
gsettings set $S enable-move-keybindings true   # habilita los atajos de mover/foco
gsettings set $S inner-gaps 3                    # gaps de 3px (como Forge/AeroSpace)
gsettings set $S outer-gaps 3

# ---------------------------------------------------------------------
# 2. NAVEGACIÓN (FOCO) — Alt+Ctrl+HJKL (idéntico a Forge/AeroSpace)
# ---------------------------------------------------------------------
gsettings set $S focus-window-left  "['<Alt><Control>h']"
gsettings set $S focus-window-down  "['<Alt><Control>j']"
gsettings set $S focus-window-up    "['<Alt><Control>k']"
gsettings set $S focus-window-right "['<Alt><Control>l']"

# ---------------------------------------------------------------------
# 3. MOVIMIENTO DE VENTANAS — Alt+Shift+HJKL
# ---------------------------------------------------------------------
gsettings set $S move-window-left  "['<Alt><Shift>h']"
gsettings set $S move-window-down  "['<Alt><Shift>j']"
gsettings set $S move-window-up    "['<Alt><Shift>k']"
gsettings set $S move-window-right "['<Alt><Shift>l']"

# ---------------------------------------------------------------------
# 4. LAYOUT Y FLOAT
# ---------------------------------------------------------------------
# Alt + / : cicla entre los layouts disponibles (equivalente al split-toggle)
gsettings set $S cycle-layouts "['<Alt>slash']"
# Shift+Super+C : saca la ventana del tiling (equivalente al float toggle)
gsettings set $S untile-window "['<Shift><Super>c']"

# ---------------------------------------------------------------------
# 5. EVITAR CONFLICTOS
# ---------------------------------------------------------------------
# Tiling Shell maneja su propio edge-tiling; apagamos el nativo de GNOME para
# que no haya doble snap en los bordes.
gsettings set org.gnome.mutter edge-tiling false
# Mantener el Alt+Tab y el menú de ventana nativos de GNOME.
gsettings set $S override-alt-tab false 2>/dev/null || true
gsettings set $S override-window-menu false 2>/dev/null || true

echo "¡Hecho! Tiling Shell configurado (BSP automático + navegación Alt+Ctrl/Shift+HJKL)."
echo "Float/untile: Shift+Super+C · Ciclar layout: Alt+/"
