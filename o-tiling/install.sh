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
# Idempotente: si ya está la versión pineada, no reinstala.
#
# IMPORTANTE: la extensión se instala BYTE A BYTE como la publica upstream.
# Este repo NO aplica parches locales, NO modifica tilting.js/window.js y NO
# desactiva la validación de versiones de GNOME salvo petición explícita. Si el
# release tiene un bug, se reporta y se espera al fix de upstream.
#
# Uso:   bash o-tiling/install.sh [opciones]
# Opciones:
#   --force                    Reinstalar la extensión aunque el marcador coincida
#   --remove-tiling-shell      OPT-IN: deshabilitar y borrar la extensión Tiling Shell
#   --disable-ding             OPT-IN: deshabilitar los iconos de escritorio (ding)
#   --allow-version-mismatch   OPT-IN: desactivar la validación de versión de extensiones
#                              de GNOME. Afecta a TODAS las extensiones del usuario.
#   --help                     Esta ayuda
#
# Sin esas opciones el script NO deshabilita, NO borra y NO cambia la validación de
# extensiones de otras extensiones. Solo instala/configura o-tiling.
#
# Vars:
#   OTILING_UUID      (default: o-tiling@oliwebd.github.com)
#   OTILING_VERSION   tag del release a fijar (default: v2.12.01)
#   TS_UUID           Tiling Shell (solo se toca con --remove-tiling-shell)
#   OTILING_AUTO_ENABLE  auto-habilitar tras instalar (default: false — ver TODO.md)

OTILING_UUID="${OTILING_UUID:-o-tiling@oliwebd.github.com}"
OTILING_VERSION="${OTILING_VERSION:-v2.12.01}"
TS_UUID="${TS_UUID:-tilingshell@ferrarodomenico.com}"
OTILING_AUTO_ENABLE="${OTILING_AUTO_ENABLE:-false}"

FORCE=false
REMOVE_TS=false
DISABLE_DING=false
ALLOW_VERSION_MISMATCH=false

usage() {
  cat <<'EOF'
Uso: bash o-tiling/install.sh [opciones]

Instala o-tiling (tiling BSP dinámico para GNOME) tal cual lo publica upstream.
No parchea ni modifica ningún archivo de la extensión. No toca otras extensiones
salvo que se lo pidas.

Opciones:
  --force                    Reinstalar aunque el marcador coincida
  --remove-tiling-shell      OPT-IN: deshabilitar y borrar Tiling Shell
  --disable-ding             OPT-IN: deshabilitar los iconos de escritorio (ding)
  --allow-version-mismatch   OPT-IN: desactivar la validación de versión de
                             extensiones de GNOME (afecta a TODAS, no solo o-tiling)
  -h, --help                 Esta ayuda

Variables:
  OTILING_UUID        (o-tiling@oliwebd.github.com)
  OTILING_VERSION     tag del release a fijar (v2.12.01)
  TS_UUID             Tiling Shell (solo con --remove-tiling-shell)
  OTILING_AUTO_ENABLE habilitar al terminar (false por defecto)

Verificación de aceptación: bash o-tiling/verify.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=true ;;
    --remove-tiling-shell) REMOVE_TS=true ;;
    --disable-ding) DISABLE_DING=true ;;
    --allow-version-mismatch) ALLOW_VERSION_MISMATCH=true ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Opción desconocida: $1 (usa --help)" >&2; exit 2 ;;
  esac
  shift
done

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
# 1. OPCIONAL: DESMONTAR TILING SHELL / DING / VALIDACIÓN DE VERSIONES
# =====================================================================
# Cada acción afecta a software que no es de este repo, así que es opt-in.
# Dos tilers activos a la vez pelean por el window-stack y lo corrompen
# (stack_position assertions), pero borrar la extensión de otra persona sin
# preguntar es peor que dejarla presente y deshabilitada.

if [[ "$REMOVE_TS" == true ]]; then
  echo "Desmontando Tiling Shell (--remove-tiling-shell)..."
  gnome-extensions disable "$TS_UUID" 2>/dev/null || true
  target="$HOME/.local/share/gnome-shell/extensions/$TS_UUID"
  if [[ -d "$target" && ! -L "$target" ]]; then
    rm -rf "$target"
    echo "  borrada: $target"
  fi
  if command -v gsettings >/dev/null 2>&1; then
    python3 - "$TS_UUID" "$OTILING_UUID" "$OTILING_AUTO_ENABLE" <<'PY' || true
import subprocess, sys, ast
ts, ot, auto_enable = sys.argv[1], sys.argv[2], sys.argv[3] == "true"
out = subprocess.run(["gsettings","get","org.gnome.shell","enabled-extensions"],
                     capture_output=True, text=True).stdout.strip()
try:
    lst = ast.literal_eval(out) if out.startswith("[") else []
except Exception:
    print("No se pudo leer enabled-extensions; no se modifica nada.", file=sys.stderr)
    sys.exit(1)
lst = [e for e in lst if e != ts]
if auto_enable:
    if ot not in lst:
        lst.append(ot)
else:
    lst = [e for e in lst if e != ot]
subprocess.run(["gsettings","set","org.gnome.shell","enabled-extensions", str(lst)], check=True)
PY
  fi
else
  echo "Tiling Shell intacta (usa --remove-tiling-shell para deshabilitar/borrarla)."
fi

if [[ "$DISABLE_DING" == true ]]; then
  echo "Desactivando ding (iconos de escritorio) por --disable-ding..."
  gnome-extensions disable ding@rastersoft.com 2>/dev/null || true
fi

if [[ "$ALLOW_VERSION_MISMATCH" == true ]]; then
  echo "AVISO: se desactiva la validación de versión de extensiones de GNOME."
  echo "       Afecta a TODAS las extensiones del usuario, no solo a o-tiling."
  gsettings set org.gnome.shell disable-extension-version-validation true 2>/dev/null || true
fi

# === Estado de instalación ===
# Solo la versión del release. No hay digest de patches porque no hay patches:
# la extensión se usa tal cual la publica upstream.
expected_marker="version=${OTILING_VERSION}"
current_marker="$(cat "$MARKER" 2>/dev/null || true)"

if [[ "$FORCE" != true && -f "$MARKER" && "$current_marker" == "$expected_marker" ]]; then
  echo "o-tiling ya instalado ($OTILING_VERSION). Saltando."
  echo "Para reinstalar: bash $0 --force"
  if [[ "$OTILING_AUTO_ENABLE" == true ]]; then
    gnome-extensions enable "$OTILING_UUID" 2>/dev/null || true
  fi
  exit 0
fi

# =====================================================================
# 2. DESCARGAR E INSTALAR (release ZIP de GitHub, sin modificar)
# =====================================================================
ZIP_URL="https://github.com/oliwebd/o-tiling/releases/download/${OTILING_VERSION}/${OTILING_UUID}-${OTILING_VERSION}.zip"
TMPDIR_OTILING="$(mktemp -d "${TMPDIR:-/tmp}/o-tiling.XXXXXX")"
TMPZIP="$TMPDIR_OTILING/release.zip"
trap 'rm -rf "$TMPDIR_OTILING"' EXIT
echo "Descargando $ZIP_URL ..."
curl -fsSL "$ZIP_URL" -o "$TMPZIP"

echo "Instalando extensión (contenido upstream, sin parches)..."
gnome-extensions install --force "$TMPZIP"

# El ZIP trae el schema .xml; aseguramos que esté compilado (gschemas.compiled)
# para poder aplicar gsettings antes del logout/login. Compilar un schema no
# modifica el código de la extensión.
if [[ -d "$EXT_DIR/schemas" ]] && command -v glib-compile-schemas >/dev/null 2>&1; then
  glib-compile-schemas "$EXT_DIR/schemas" 2>/dev/null || true
fi

if [[ "$OTILING_AUTO_ENABLE" == true ]]; then
  gnome-extensions enable "$OTILING_UUID" 2>/dev/null || true
fi

# === Marker idempotencia ===
mkdir -p "$EXT_DIR"
printf '%s\n' "$expected_marker" > "$MARKER"
chmod 0644 "$MARKER"

echo "o-tiling instalado ($OTILING_VERSION) — contenido upstream sin modificar."
echo "NOTA: en Wayland necesitás logout+login para que gnome-shell lo cargue."
echo "Siguiente paso: bash o-tiling/verify.sh para la verificación de aceptación."
