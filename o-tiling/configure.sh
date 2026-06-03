#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# SCRIPT MAESTRO: configuración de o-tiling (Linux)
# =====================================================================
# Replica el comportamiento de Forge/AeroSpace: tiling BSP dinámico automático
# + navegación vim (Alt+Ctrl+HJKL foco, Alt+Shift+HJKL mover/swap).
# Fuente de verdad: este script (idempotente vía gsettings).

echo "Configurando o-tiling..."

OTILING_UUID="${OTILING_UUID:-o-tiling@oliwebd.github.com}"
OT_SCHEMA_DIR="${OT_SCHEMA_DIR:-$HOME/.local/share/gnome-shell/extensions/$OTILING_UUID/schemas}"
S="org.gnome.shell.extensions.o-tiling"

if ! command -v gsettings >/dev/null 2>&1; then
  echo "Error: gsettings no está disponible." >&2
  exit 1
fi

# El schema de la extensión no está en el path global; lo apuntamos.
if [[ -d "$OT_SCHEMA_DIR" ]]; then
  export GSETTINGS_SCHEMA_DIR="$OT_SCHEMA_DIR"
fi

if ! gsettings list-schemas | grep -qx "$S"; then
  echo "Error: no se encontró el schema $S." >&2
  echo "Ruta esperada: $OT_SCHEMA_DIR" >&2
  echo "¿Instalaste o-tiling? (bash o-tiling/install.sh)" >&2
  exit 1
fi

# ---------------------------------------------------------------------
# 1. TILING AUTOMÁTICO + GAPS
# ---------------------------------------------------------------------
gsettings set $S tile-by-default true     # ventanas NUEVAS se auto-tilean (BSP)
gsettings set $S gap-inner 3
gsettings set $S gap-outer 3

# ---------------------------------------------------------------------
# 2. NAVEGACIÓN (FOCO) — Alt+Ctrl+HJKL (global, sin modo)
# ---------------------------------------------------------------------
gsettings set $S focus-left  "['<Alt><Control>h']"
gsettings set $S focus-down  "['<Alt><Control>j']"
gsettings set $S focus-up    "['<Alt><Control>k']"
gsettings set $S focus-right "['<Alt><Control>l']"

# ---------------------------------------------------------------------
# 3. MOVER/SWAP VENTANAS — Alt+Shift+HJKL (global, sin modo)
# ---------------------------------------------------------------------
gsettings set $S tile-swap-left  "['<Alt><Shift>h']"
gsettings set $S tile-swap-down  "['<Alt><Shift>j']"
gsettings set $S tile-swap-up    "['<Alt><Shift>k']"
gsettings set $S tile-swap-right "['<Alt><Shift>l']"

# ---------------------------------------------------------------------
# 4. FLOAT
# ---------------------------------------------------------------------
gsettings set $S toggle-floating "['<Shift><Super>c']"

# ---------------------------------------------------------------------
# 5. EVITAR LA RUTA DEL CRASH (stacking)
# ---------------------------------------------------------------------
# El modo stacking/tabbed es la ruta del crash de stack en pop-shell (#647).
# Lo dejamos SIN bindear para no dispararlo accidentalmente.
gsettings set $S toggle-stacking "[]" 2>/dev/null || true
gsettings set $S toggle-stacking-global "[]" 2>/dev/null || true

echo "¡Hecho! o-tiling configurado (BSP automático + navegación Alt+Ctrl/Shift+HJKL)."
echo "Float: Shift+Super+C · Toggle tiling: Super+T"
