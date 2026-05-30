#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# Forge Install Script — clona main desde forge-ext/forge y lo builda.
# =====================================================================
# Razón: el último release oficial (v89) está roto en GNOME 50.1
# ("St.Icon already disposed" en lib/extension/indicator.js:125).
# El branch main tiene los fixes: "guard tree rendering against destroyed
# window actors", "Add support for GNOME Shell version 50", etc.
# extensions.gnome.org publica v89; gext y los paquetes de distro lo mismo.
# Por eso instalamos desde git directamente.
#
# Idempotente: si Forge ya está instalado desde main, no reinstala salvo
# que se pase --force.
#
# Uso:
#   bash forge/install.sh [--force]
#
# Variables:
#   FORGE_REPO       URL del repo (default: https://github.com/forge-ext/forge.git)
#   FORGE_BRANCH     Branch (default: main)
#   FORGE_COMMIT     Commit a fijar (default: known-good pineado abajo).
#                    Vacío ("") = flota en el HEAD del branch (NO recomendado).
#   FORGE_UUID       UUID de la extensión (default: forge@jmmaranan.com)
#
# PIN DE COMMIT: Forge main es bleeding edge y ha regresionado el manejo de
# window-stacking de Mutter en GNOME 50.1 (ventanas nuevas sin allocation,
# tiling/atajos que se degradan con el tiempo). Fijamos un commit reproducible
# para no traer un main distinto en cada setup. Para actualizar a un main más
# nuevo: cambiar FORGE_COMMIT, `bash forge/install.sh --force`, logout+login.

FORGE_REPO="${FORGE_REPO:-https://github.com/forge-ext/forge.git}"
FORGE_BRANCH="${FORGE_BRANCH:-main}"
FORGE_COMMIT="${FORGE_COMMIT:-0319a7125db1088556b159a69bbec77e111afca7}"
FORGE_UUID="${FORGE_UUID:-forge@jmmaranan.com}"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$FORGE_UUID"
MARKER="$EXT_DIR/.installed-from-main"

# === Sanity ===
if ! command -v gnome-shell >/dev/null 2>&1; then
  echo "Error: gnome-shell no encontrado, no es un sistema GNOME." >&2
  exit 1
fi

if ! command -v gnome-extensions >/dev/null 2>&1; then
  echo "Error: gnome-extensions CLI no encontrada." >&2
  exit 1
fi

# === Skip si ya está instalado desde main (idempotente) ===
if [[ "$FORCE" != true ]] && [[ -f "$MARKER" ]]; then
  echo "Forge ya instalado desde main ($(cat "$MARKER")). Saltando build."
  echo "Para reinstalar: bash $0 --force"
  exit 0
fi

# === Dependencias del build ===
echo "Verificando dependencias de build..."
MISSING=()
for cmd in make git glib-compile-schemas msgfmt xgettext awk sed; do
  command -v "$cmd" >/dev/null 2>&1 || MISSING+=("$cmd")
done

if (( ${#MISSING[@]} > 0 )); then
  echo "Faltan herramientas: ${MISSING[*]}" >&2
  # En Ubuntu, gettext provee xgettext/msgfmt; build-essential trae make.
  if command -v apt-get >/dev/null 2>&1; then
    echo "Instalando con apt..." >&2
    sudo apt-get install -y gettext make git libglib2.0-bin >&2
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y gettext make git glib2 >&2
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --noconfirm gettext make git glib2 >&2
  else
    echo "Instala manualmente: ${MISSING[*]}" >&2
    exit 1
  fi
fi

# === Erradicar TODO rastro de Forge anterior ===
# gnome-shell intenta cargar CUALQUIER dir en extensions/ como extensión;
# un dir incompleto (sin metadata.json) genera errores que interfieren con
# el shell. Además los stylesheets en ~/.config/forge y paquetes apt
# pueden colisionar. Delegamos al uninstall.sh para limpieza completa.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
if [[ -x "$SCRIPT_DIR/uninstall.sh" ]]; then
  bash "$SCRIPT_DIR/uninstall.sh" || true
fi

# === Clonar y build ===
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "Clonando $FORGE_REPO ($FORGE_BRANCH) en $TMPDIR..."
git clone --depth 1 --branch "$FORGE_BRANCH" "$FORGE_REPO" "$TMPDIR/forge"

cd "$TMPDIR/forge"

# Fijar el commit pineado (si FORGE_COMMIT no está vacío y difiere del HEAD).
# Usamos fetch shallow del commit puntual para no clonar todo el historial.
if [[ -n "$FORGE_COMMIT" ]] && [[ "$(git rev-parse HEAD)" != "$FORGE_COMMIT" ]]; then
  echo "Fijando commit pineado $FORGE_COMMIT..."
  git fetch --depth 1 origin "$FORGE_COMMIT"
  git checkout --quiet "$FORGE_COMMIT"
fi

COMMIT="$(git rev-parse HEAD)"

echo "Compilando e instalando (make build install)..."
# El target 'install' solo copia temp/* → no funciona sin 'build' antes.
# 'build' crea metadata.json, compila schemas y compila traducciones en temp/.
# No corremos 'restart' (target de 'all') porque en Wayland no recarga
# gnome-shell sin logout completo.
make build install

# === Aplicar patches locales (fixes upstream pendientes) ===
PATCH_SCRIPT="$SCRIPT_DIR/patches/apply-patches.sh"
if [[ -x "$PATCH_SCRIPT" ]]; then
  bash "$PATCH_SCRIPT" "$EXT_DIR" || echo "⚠ Algún patch falló (revisa output arriba)"
fi

# === Marker para idempotencia ===
echo "branch=$FORGE_BRANCH commit=$COMMIT date=$(date -Iseconds)" > "$MARKER"

# === Habilitar y desactivar conflictivas ===
gsettings set org.gnome.shell disable-extension-version-validation true 2>/dev/null || true
gnome-extensions enable "$FORGE_UUID" 2>/dev/null || true

# Ubuntu Tiling Assistant pelea con Forge por el manejo de ventanas
if gnome-extensions list 2>/dev/null | grep -qx "tiling-assistant@ubuntu.com"; then
  gnome-extensions disable "tiling-assistant@ubuntu.com" 2>/dev/null || true
fi

# === Borrar TODOS los backups antiguos por si quedaron de runs previos ===
find "$(dirname "$EXT_DIR")" -maxdepth 1 -name "${FORGE_UUID}.bak-*" -type d \
  -exec rm -rf {} + 2>/dev/null || true

echo "Forge instalado desde $FORGE_BRANCH (commit ${COMMIT:0:8})."
echo "NOTA: en Wayland necesitas logout+login para que gnome-shell recargue la extensión."
