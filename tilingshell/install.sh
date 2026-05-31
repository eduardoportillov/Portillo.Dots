#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# Tiling Shell Install Script
# =====================================================================
# Instala Tiling Shell (domferr) desde extensions.gnome.org y desmonta Forge.
#
# Razón de la migración: Forge (forge@jmmaranan.com) está sin maintainer y es
# incompatible con GNOME 50.1 — corrompe el window-stack de Mutter en setups
# multi-monitor (bug forge-ext/forge#303: "meta_window_set_stack_position_no_sync
# assertion 'window->stack_position >= 0' failed"), dejando ventanas nuevas
# invisibles y atascando el dispatch de atajos (Ctrl+Alt+T, Win+Shift+S). El
# commit instalado ya era el HEAD de main, así que no había a dónde actualizar.
# Tiling Shell hace tiling BSP automático, está activamente mantenido y soporta
# shell 45–50.
#
# Idempotente: si ya está instalada la versión pineada, no reinstala salvo --force.
#
# Uso:   bash tilingshell/install.sh [--force]
# Vars:
#   TILINGSHELL_UUID         (default: tilingshell@ferrarodomenico.com)
#   TILINGSHELL_VERSION_TAG  pk/version_tag de EGO a fijar (default: 70233 = v76,
#                            la build para shell 50). Vacío = resolver la última.
#   FORGE_UUID               extensión vieja a desmontar (default: forge@jmmaranan.com)

TILINGSHELL_UUID="${TILINGSHELL_UUID:-tilingshell@ferrarodomenico.com}"
TILINGSHELL_VERSION_TAG="${TILINGSHELL_VERSION_TAG:-70233}"
FORGE_UUID="${FORGE_UUID:-forge@jmmaranan.com}"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$TILINGSHELL_UUID"
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
# 1. DESMONTAR FORGE (one-time, idempotente)
# =====================================================================
# Dos tilers peleando por las ventanas es caos; además queremos erradicar la
# fuente de la corrupción del stack.
echo "Desmontando Forge si está presente..."
gnome-extensions disable "$FORGE_UUID" 2>/dev/null || true
rm -rf "$HOME/.local/share/gnome-shell/extensions/$FORGE_UUID" 2>/dev/null || true
rm -rf "$HOME/.config/forge" 2>/dev/null || true
# Sacar Forge de la lista de habilitadas por las dudas
if command -v gsettings >/dev/null 2>&1; then
  current="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "@as []")"
  if [[ "$current" == *"$FORGE_UUID"* ]]; then
    python3 - "$FORGE_UUID" <<'PY' || true
import subprocess, sys, ast
uuid = sys.argv[1]
out = subprocess.run(["gsettings","get","org.gnome.shell","enabled-extensions"],
                     capture_output=True, text=True).stdout.strip()
try:
    lst = ast.literal_eval(out) if out.startswith("[") else []
except Exception:
    lst = []
lst = [e for e in lst if e != uuid]
subprocess.run(["gsettings","set","org.gnome.shell","enabled-extensions", str(lst)])
PY
  fi
fi

# === Skip si ya está la versión pineada (idempotente) ===
if [[ "$FORCE" != true ]] && [[ -f "$MARKER" ]] \
  && [[ "$(cat "$MARKER" 2>/dev/null)" == "version_tag=${TILINGSHELL_VERSION_TAG}" ]] \
  && [[ -n "$TILINGSHELL_VERSION_TAG" ]]; then
  echo "Tiling Shell ya instalada (version_tag=$TILINGSHELL_VERSION_TAG). Saltando."
  echo "Para reinstalar: bash $0 --force"
  gnome-extensions enable "$TILINGSHELL_UUID" 2>/dev/null || true
  exit 0
fi

# =====================================================================
# 2. RESOLVER URL DE DESCARGA (EGO)
# =====================================================================
BASE="https://extensions.gnome.org"
if [[ -n "$TILINGSHELL_VERSION_TAG" ]]; then
  DL_URL="$BASE/download-extension/${TILINGSHELL_UUID}.shell-extension.zip?version_tag=${TILINGSHELL_VERSION_TAG}"
else
  echo "Resolviendo última versión para shell 50 desde EGO..."
  INFO="$(curl -fsS "$BASE/extension-info/?uuid=${TILINGSHELL_UUID}&shell_version=50")"
  DL_PATH="$(printf '%s' "$INFO" | python3 -c 'import sys,json;print(json.load(sys.stdin)["download_url"])')"
  DL_URL="$BASE$DL_PATH"
fi

# =====================================================================
# 3. DESCARGAR E INSTALAR
# =====================================================================
TMPZIP="$(mktemp --suffix=.zip)"
trap 'rm -f "$TMPZIP"' EXIT
echo "Descargando $DL_URL ..."
curl -fsSL "$DL_URL" -o "$TMPZIP"

echo "Instalando extensión..."
gnome-extensions install --force "$TMPZIP"

# Por si el shell minor (50.1) no matchea el metadata exacto
gsettings set org.gnome.shell disable-extension-version-validation true 2>/dev/null || true
gnome-extensions enable "$TILINGSHELL_UUID" 2>/dev/null || true

# === Marker idempotencia ===
mkdir -p "$EXT_DIR"
echo "version_tag=${TILINGSHELL_VERSION_TAG:-latest}" > "$MARKER"

echo "Tiling Shell instalada (version_tag=${TILINGSHELL_VERSION_TAG:-latest})."
echo "NOTA: en Wayland necesitás logout+login para que gnome-shell la cargue."
