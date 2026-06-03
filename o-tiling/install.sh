#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# o-tiling Install Script
# =====================================================================
# Instala o-tiling (fork de Pop Shell, tiling BSP dinámico) desde el release
# ZIP de GitHub y desmonta Tiling Shell.
#
# Por qué o-tiling: es la única extensión de GNOME viva con tiling BSP dinámico
# (estilo Forge/AeroSpace) que soporta GNOME 50. Forge quedó abandonado y rompía
# el window-stack de Mutter en multi-monitor; Tiling Shell funciona pero usa
# layouts/zonas fijas (no splits dinámicos), que no es lo que el usuario quiere.
#
# Idempotente: si ya está la versión pineada, no reinstala salvo --force.
#
# Uso:   bash o-tiling/install.sh [--force]
# Vars:
#   OTILING_UUID      (default: o-tiling@oliwebd.github.com)
#   OTILING_VERSION   tag del release a fijar (default: v2.8.8, build para shell 50)
#   TS_UUID           Tiling Shell a desmontar (default: tilingshell@ferrarodomenico.com)

OTILING_UUID="${OTILING_UUID:-o-tiling@oliwebd.github.com}"
OTILING_VERSION="${OTILING_VERSION:-v2.8.8}"
TS_UUID="${TS_UUID:-tilingshell@ferrarodomenico.com}"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$OTILING_UUID"
MARKER="$EXT_DIR/.installed-version"

# === Sanity ===
if ! command -v gnome-extensions >/dev/null 2>&1; then
  echo "Error: gnome-extensions CLI no encontrada (¿no es GNOME?)." >&2
  exit 1
fi
for cmd in curl python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Error: falta $cmd." >&2; exit 1; }
done

# =====================================================================
# 1. DESMONTAR TILING SHELL (one-time, idempotente)
# =====================================================================
# Dos tilers activos a la vez pelean por el window-stack y lo corrompen
# (stack_position assertions). Erradicamos Tiling Shell para dejar solo o-tiling.
echo "Desmontando Tiling Shell si está presente..."
gnome-extensions disable "$TS_UUID" 2>/dev/null || true
rm -rf "$HOME/.local/share/gnome-shell/extensions/$TS_UUID" 2>/dev/null || true
# Sacar Tiling Shell de enabled-extensions y asegurar o-tiling adentro
if command -v gsettings >/dev/null 2>&1; then
  python3 - "$TS_UUID" "$OTILING_UUID" <<'PY' || true
import subprocess, sys, ast
ts, ot = sys.argv[1], sys.argv[2]
out = subprocess.run(["gsettings","get","org.gnome.shell","enabled-extensions"],
                     capture_output=True, text=True).stdout.strip()
try:
    lst = ast.literal_eval(out) if out.startswith("[") else []
except Exception:
    lst = []
lst = [e for e in lst if e != ts]
if ot not in lst:
    lst.append(ot)
subprocess.run(["gsettings","set","org.gnome.shell","enabled-extensions", str(lst)])
PY
fi

# === Skip si ya está la versión pineada (idempotente) ===
if [[ "$FORCE" != true ]] && [[ -f "$MARKER" ]] \
  && [[ "$(cat "$MARKER" 2>/dev/null)" == "version=${OTILING_VERSION}" ]]; then
  echo "o-tiling ya instalado ($OTILING_VERSION). Saltando."
  echo "Para reinstalar: bash $0 --force"
  gnome-extensions enable "$OTILING_UUID" 2>/dev/null || true
  exit 0
fi

# =====================================================================
# 2. DESCARGAR E INSTALAR (release ZIP de GitHub)
# =====================================================================
ZIP_URL="https://github.com/oliwebd/o-tiling/releases/download/${OTILING_VERSION}/${OTILING_UUID}-${OTILING_VERSION}.zip"
TMPZIP="$(mktemp --suffix=.zip)"
trap 'rm -f "$TMPZIP"' EXIT
echo "Descargando $ZIP_URL ..."
curl -fsSL "$ZIP_URL" -o "$TMPZIP"

echo "Instalando extensión..."
gnome-extensions install --force "$TMPZIP"

# El ZIP trae el schema .xml; aseguramos que esté compilado (gschemas.compiled)
# para poder aplicar gsettings antes del logout/login.
if [[ -d "$EXT_DIR/schemas" ]] && command -v glib-compile-schemas >/dev/null 2>&1; then
  glib-compile-schemas "$EXT_DIR/schemas" 2>/dev/null || true
fi

# Por si el shell minor (50.1) no matchea el metadata exacto
gsettings set org.gnome.shell disable-extension-version-validation true 2>/dev/null || true
gnome-extensions enable "$OTILING_UUID" 2>/dev/null || true

# === Marker idempotencia ===
mkdir -p "$EXT_DIR"
echo "version=${OTILING_VERSION}" > "$MARKER"

echo "o-tiling instalado ($OTILING_VERSION)."
echo "NOTA: en Wayland necesitás logout+login para que gnome-shell lo cargue."
