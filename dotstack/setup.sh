#!/bin/sh
# setup.sh - script de preparación para dotstack
# Ubicación esperada: repo/dotstack/setup.sh
# Propósito: preparar entorno, crear symlinks y directorios necesarios

set -e
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOME_DS="$HOME/.dotstack"
LOCAL_BIN="$HOME/.local/bin"
DOTSTACK_BIN="$ROOT_DIR/bin/dotstack"

usage() {
  cat <<EOF
Uso: setup.sh [--yes] [--preflight]

Opciones:
  --yes       Responde afirmativamente a prompts que requieran confirmación
  --preflight Ejecuta 'dotstack preflight' al final (requiere curl/git/jq o portables)
EOF
}

CONFIRM=0
DO_PREFLIGHT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) CONFIRM=1; shift;;
    --preflight) DO_PREFLIGHT=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Parámetro desconocido: $1"; usage; exit 1;;
  esac
done

echo "[dotstack setup] Root repo: $ROOT_DIR"

# crear estructura mínima dentro del repo (si faltan)
for d in "$ROOT_DIR/opt" "$ROOT_DIR/logs" "$ROOT_DIR/backups" "$ROOT_DIR/share" "$ROOT_DIR/repo/configs" "$ROOT_DIR/repo/manifests" "$ROOT_DIR/repo/scripts"; do
  if [ ! -d "$d" ]; then
    mkdir -p "$d"
    echo "Creado: $d"
  fi
done

# asegurar que el entrypoint existe y sea ejecutable
if [ -f "$DOTSTACK_BIN" ]; then
  chmod +x "$DOTSTACK_BIN" || true
  echo "Entrypoint listo: $DOTSTACK_BIN"
else
  echo "WARNING: no se encontró $DOTSTACK_BIN"
fi

# crear symlink en ~/.local/bin
if [ ! -d "$LOCAL_BIN" ]; then
  mkdir -p "$LOCAL_BIN"
  echo "Creado: $LOCAL_BIN"
fi
if [ -e "$LOCAL_BIN/dotstack" ]; then
  echo "Nota: $LOCAL_BIN/dotstack ya existe; se actualizará el enlace"
fi
ln -sf "$DOTSTACK_BIN" "$LOCAL_BIN/dotstack"
echo "Symlink creado: $LOCAL_BIN/dotstack -> $DOTSTACK_BIN"

# crear o actualizar symlink ~/.dotstack -> repo/dotstack
if [ -L "$HOME_DS" ]; then
  echo "~/.dotstack ya es un symlink -> $(readlink -f "$HOME_DS")"
elif [ -e "$HOME_DS" ]; then
  if [ "$CONFIRM" -eq 1 ]; then
    rm -rf "$HOME_DS"
    ln -s "$ROOT_DIR" "$HOME_DS"
    echo "Reemplazado ~/.dotstack por symlink hacia $ROOT_DIR"
  else
    echo "Existe $HOME_DS (no es symlink). Ejecuta setup.sh --yes para reemplazarlo por un symlink al repo"
  fi
else
  ln -s "$ROOT_DIR" "$HOME_DS"
  echo "Creado symlink: ~/.dotstack -> $ROOT_DIR"
fi

# instrucciones finales
echo
cat <<EOF
Listo. Siguientes pasos recomendados:
  - Ejecuta: dotstack preflight
  - Ejecuta: dotstack activate --append (o manualmente source ~/.dotstack/activate)
  - Revisa: ~/.dotstack/repo/manifests y ~/.dotstack/repo/configs

Si ejecutes con --preflight, se ejecutará dotstack preflight ahora (si dotstack es ejecutable).
EOF

if [ "$DO_PREFLIGHT" -eq 1 ]; then
  if command -v dotstack >/dev/null 2>&1; then
    echo "Ejecutando: dotstack preflight"
    dotstack preflight || echo "dotstack preflight detectó problemas"
  else
    echo "dotstack no está en PATH. Ejecuta "$LOCAL_BIN/dotstack" preflight o añade ~/.local/bin a tu PATH"
  fi
fi
