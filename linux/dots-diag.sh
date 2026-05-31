#!/usr/bin/env bash
set -uo pipefail

# =====================================================================
# dots-diag — captura la firma del bug de stacking del WM/tiling
# =====================================================================
# Corré ESTO cuando el sistema esté ROTO (Ctrl+Alt+T no abre terminal,
# Win+Shift+S no anda, o el tiling se degradó). Vuelca toda la evidencia a
# un archivo para confirmar la causa raíz y, si hace falta, reportarla
# upstream (Tiling Shell: github.com/domferr/tilingshell).
#
# Uso:  bash dots-diag.sh   (imprime y guarda en ~/.local/state/)

OUT_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
mkdir -p "$OUT_DIR"
STAMP="$(date '+%Y%m%d-%H%M%S')"
OUT="$OUT_DIR/dots-diag-$STAMP.txt"
TS_UUID="${TS_UUID:-tilingshell@ferrarodomenico.com}"
TS_SCHEMAS="$HOME/.local/share/gnome-shell/extensions/$TS_UUID/schemas"

{
  echo "===== dots-diag $STAMP ====="
  echo

  echo "===== [1] Corrupción de window-stack de Mutter (firma del bug) ====="
  echo "(si aparecen líneas aquí, la extensión de tiling corrompió el stack → ventanas nuevas invisibles)"
  journalctl -b _COMM=gnome-shell --no-pager 2>/dev/null \
    | grep -iE "stack_position|_syncStacking|needs an allocation|can't access property .clone" \
    | tail -40
  echo

  echo "===== [2] Errores JS recientes de gnome-shell (30 min) ====="
  journalctl --since "30 min ago" _COMM=gnome-shell --no-pager 2>/dev/null \
    | grep -iE "JS ERROR|tilingshell|disposed|exception" | tail -30
  echo

  echo "===== [3] Procesos alacritty (¿fantasmas sin ventana?) ====="
  ps -eo pid,etime,stat,cmd | grep -iE "[a]lacritty" || echo "(ninguno)"
  echo "(un alacritty 'Sl' viejo sin ventana visible = window-mapping roto)"
  echo

  echo "===== [4] gsettings de los atajos (deberían seguir intactos) ====="
  echo -n "Ctrl+Alt+T binding : "; gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding 2>&1
  echo -n "Ctrl+Alt+T command : "; gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command 2>&1
  echo -n "screenshot UI      : "; gsettings get org.gnome.shell.keybindings show-screenshot-ui 2>&1
  echo

  echo "===== [5] Tiling Shell: estado y uptime de gnome-shell ====="
  [[ -d "$TS_SCHEMAS" ]] && export GSETTINGS_SCHEMA_DIR="$TS_SCHEMAS"
  echo -n "enable-autotiling  : "; gsettings get org.gnome.shell.extensions.tilingshell enable-autotiling 2>&1
  echo -n "tilingshell activa : "; gnome-extensions list --enabled 2>/dev/null | grep -qx "$TS_UUID" && echo "sí" || echo "NO"
  echo "gnome-shell:"; ps -o pid,etime,%cpu,%mem,rss,cmd -C gnome-shell 2>&1
  echo

  echo "===== Interpretación ====="
  echo "Si [1] tiene líneas y [3] muestra un alacritty viejo sin ventana, mientras"
  echo "[4] sigue intacto → es corrupción de stack de la extensión de tiling (no la config)."
  echo "Recuperá con: bash dots-fix-tiling.sh  (o logout+login)."
} | tee "$OUT"

echo
echo ">>> Guardado en: $OUT"
