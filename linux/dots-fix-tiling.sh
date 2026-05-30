#!/usr/bin/env bash
set -uo pipefail

# =====================================================================
# dots-fix-tiling — recuperación rápida de Forge SIN logout
# =====================================================================
# Cuándo usarlo: cuando el tiling se degrada y/o las ventanas nuevas
# (p.ej. Ctrl+Alt+T) se lanzan pero quedan invisibles. Esto pasa cuando
# Forge corrompe el window-stack de Mutter en runtime
# ("meta_window_set_stack_position_no_sync: assertion ... failed").
#
# Hace disable→enable de la extensión Forge, lo que re-inicializa su árbol
# de ventanas desde cero (equivalente "barato" a un logout para Forge).
# En Wayland NO se puede reiniciar gnome-shell sin logout; si esto no
# alcanza, la recuperación total es logout + login.
#
# Uso:  bash dots-fix-tiling.sh

FORGE_UUID="${FORGE_UUID:-forge@jmmaranan.com}"

if ! command -v gnome-extensions >/dev/null 2>&1; then
  echo "Error: gnome-extensions CLI no encontrada." >&2
  exit 1
fi

if ! gnome-extensions list 2>/dev/null | grep -qx "$FORGE_UUID"; then
  echo "Error: Forge ($FORGE_UUID) no está instalada." >&2
  exit 1
fi

echo "Deshabilitando Forge (las ventanas se destilean y vuelven a ser visibles)..."
gnome-extensions disable "$FORGE_UUID" 2>/dev/null || true
sleep 1.5

echo "Re-habilitando Forge (re-inicializa el árbol de tiling)..."
gnome-extensions enable "$FORGE_UUID" 2>/dev/null || true
sleep 1.5

echo "Hecho."
echo "Si el problema persiste, hacé logout + login (recuperación total en Wayland)."
echo "Si reaparece seguido, corré dots-diag.sh cuando esté roto para capturar evidencia."
