#!/usr/bin/env bash
set -uo pipefail

# =====================================================================
# dots-fix-tiling — recuperación rápida del tiling SIN logout
# =====================================================================
# Cuándo usarlo: cuando el tiling se degrada y/o las ventanas nuevas
# (p.ej. Ctrl+Alt+T) se lanzan pero quedan invisibles, o si el dispatch de
# atajos se atasca.
#
# Hace disable→enable de la extensión de tiling (Tiling Shell), lo que
# re-inicializa su estado desde cero (equivalente "barato" a un logout para
# la extensión). En Wayland NO se puede reiniciar gnome-shell sin logout; si
# esto no alcanza, la recuperación total es logout + login.
#
# Uso:  bash dots-fix-tiling.sh

TS_UUID="${TS_UUID:-tilingshell@ferrarodomenico.com}"

if ! command -v gnome-extensions >/dev/null 2>&1; then
  echo "Error: gnome-extensions CLI no encontrada." >&2
  exit 1
fi

if ! gnome-extensions list 2>/dev/null | grep -qx "$TS_UUID"; then
  echo "Error: Tiling Shell ($TS_UUID) no está instalada." >&2
  exit 1
fi

echo "Deshabilitando Tiling Shell (las ventanas se destilean y vuelven a ser visibles)..."
gnome-extensions disable "$TS_UUID" 2>/dev/null || true
sleep 1.5

echo "Re-habilitando Tiling Shell (re-inicializa el estado de tiling)..."
gnome-extensions enable "$TS_UUID" 2>/dev/null || true
sleep 1.5

echo "Hecho."
echo "Si el problema persiste, hacé logout + login (recuperación total en Wayland)."
echo "Si reaparece seguido, corré dots-diag.sh cuando esté roto para capturar evidencia."
