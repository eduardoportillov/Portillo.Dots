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
# Idempotente: si ya está la versión pineada y los patches actuales, no reinstala.
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
#   OTILING_VERSION   tag del release a fijar (default: v2.9.21, build para shell 50)
#   TS_UUID           Tiling Shell (solo se toca con --remove-tiling-shell)
#   OTILING_AUTO_ENABLE  auto-habilitar tras instalar (default: false — ver TODO.md,
#                        "o-tiling: corrompe stack_position en cada ventana nueva")

OTILING_UUID="${OTILING_UUID:-o-tiling@oliwebd.github.com}"
OTILING_VERSION="${OTILING_VERSION:-v2.9.21}"
TS_UUID="${TS_UUID:-tilingshell@ferrarodomenico.com}"
OTILING_AUTO_ENABLE="${OTILING_AUTO_ENABLE:-false}"

FORCE=false
REMOVE_TS=false
DISABLE_DING=false
ALLOW_VERSION_MISMATCH=false

usage() {
  cat <<'EOF'
Uso: bash o-tiling/install.sh [opciones]

Instala o-tiling (tiling BSP dinámico para GNOME) desde su release de GitHub y
aplica patches locales. No toca otras extensiones salvo que se lo pidas.

Opciones:
  --force                    Reinstalar aunque el marcador coincida
  --remove-tiling-shell      OPT-IN: deshabilitar y borrar Tiling Shell
  --disable-ding             OPT-IN: deshabilitar los iconos de escritorio (ding)
  --allow-version-mismatch   OPT-IN: desactivar la validación de versión de
                             extensiones de GNOME (afecta a TODAS, no solo o-tiling)
  -h, --help                 Esta ayuda

Variables:
  OTILING_UUID        (o-tiling@oliwebd.github.com)
  OTILING_VERSION     tag del release a fijar (v2.9.21)
  TS_UUID             Tiling Shell (solo con --remove-tiling-shell)
  OTILING_AUTO_ENABLE habilitar al terminar (false por defecto)
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
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PATCH_SCRIPT="$SCRIPT_DIR/patches/apply-patches.sh"

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
# El marcador registra la versión del release Y el contenido del script de
# patches. Así, cambiar un patch dispara su re-aplicación aunque la extensión
# siga en la misma versión.
patch_digest="none"
if [[ -f "$PATCH_SCRIPT" ]]; then
  patch_digest="$(sha256sum "$PATCH_SCRIPT" 2>/dev/null | awk '{print $1}')" || patch_digest="unknown"
  [[ -n "$patch_digest" ]] || patch_digest="unknown"
fi
expected_marker="version=${OTILING_VERSION} patches=${patch_digest}"
current_marker="$(cat "$MARKER" 2>/dev/null || true)"

apply_local_patches() {
  [[ -f "$PATCH_SCRIPT" ]] || { echo "✗ No se encontró $PATCH_SCRIPT" >&2; return 1; }
  bash "$PATCH_SCRIPT" "$EXT_DIR"
}

if [[ "$FORCE" != true && -f "$MARKER" && "$current_marker" == "$expected_marker" ]]; then
  echo "o-tiling ya instalado ($OTILING_VERSION) con los patches actuales. Saltando."
  echo "Para reinstalar: bash $0 --force"
  if [[ "$OTILING_AUTO_ENABLE" == true ]]; then
    gnome-extensions enable "$OTILING_UUID" 2>/dev/null || true
  fi
  exit 0
fi

reapply_only=false
if [[ "$FORCE" != true && -f "$MARKER" ]] && [[ "$current_marker" == "version=${OTILING_VERSION} patches="* ]]; then
  echo "La versión coincide pero cambiaron los patches; re-aplicándolos sin descargar."
  reapply_only=true
fi

# =====================================================================
# 2. DESCARGAR E INSTALAR (release ZIP de GitHub)
# =====================================================================
if [[ "$reapply_only" != true ]]; then
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
fi

if [[ "$OTILING_AUTO_ENABLE" == true ]]; then
  gnome-extensions enable "$OTILING_UUID" 2>/dev/null || true
fi

# =====================================================================
# 3. APLICAR PATCHS LOCALES (fixes sobre el código instalado)
# =====================================================================
# El fallo de un patch es un fallo de la instalación: no se escribe un marcador
# de éxito que haría que la próxima ejecución lo diera por bueno.
if ! apply_local_patches; then
  echo "" >&2
  echo "✗ La instalación NO se considera completa: falló la aplicación de patches." >&2
  echo "  No se escribió el marcador; la próxima ejecución reintentará." >&2
  exit 1
fi

# === Marker idempotencia ===
mkdir -p "$EXT_DIR"
printf '%s\n' "$expected_marker" > "$MARKER"
chmod 0644 "$MARKER"

echo "o-tiling instalado ($OTILING_VERSION) con patches: $patch_digest"
echo "NOTA: en Wayland necesitás logout+login para que gnome-shell lo cargue."
