#!/usr/bin/env bash
# =====================================================================
# o-tiling Acceptance Verification
# =====================================================================
# Comprueba que el release UPSTREAM de o-tiling funciona en este equipo.
# Filosofía: sin parches manuales, sin workarounds. Si falla, se deshabilita
# la extensión y se espera al fix de upstream.
#
# Este script:
#   - NO modifica el código de la extensión
#   - NO aplica parches ni cambia la validación de versiones de GNOME
#   - SÍ puede habilitar/deshabilitar la extensión como parte del veredicto
#
# Fases:
#   prepare    instala y habilita, e imprime la lista de aceptación
#   integrity  comprueba que los archivos instalados son idénticos al ZIP upstream
#   report     captura el journal, pide el resultado por bloque y emite veredicto
#   status     muestra el estado actual
#
# Uso: bash o-tiling/verify.sh [prepare|integrity|report|status|help]

set -euo pipefail

OTILING_UUID="${OTILING_UUID:-o-tiling@oliwebd.github.com}"
OTILING_VERSION="${OTILING_VERSION:-v2.12.01}"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/portillo-dots/otiling-verify"
STARTED_AT="$STATE_DIR/started-at"
VERDICT="$STATE_DIR/verdict.txt"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$OTILING_UUID"
VERIFY_TMPZIP=""
cleanup_verify() { [[ -z "$VERIFY_TMPZIP" ]] || rm -f "$VERIFY_TMPZIP"; }
trap cleanup_verify EXIT

# Patrones que indican el bug conocido (issue upstream #50).
BUG_PATTERNS='meta_window_set_stack_position_no_sync|stack_position >= 0|_syncStacking'

usage() {
  cat <<'EOF'
Uso: bash o-tiling/verify.sh [comando]

Comprueba el release upstream de o-tiling sin modificarlo.

Comandos:
  prepare     instala/habilita y muestra la lista de aceptación
  integrity   comprueba que la extensión instalada = ZIP upstream (cero parches)
  report      captura el journal, pide resultados y emite veredicto
  status      estado actual de la extensión y de la verificación
  help        esta ayuda

Flujo recomendado:
  1. bash o-tiling/verify.sh prepare
  2. logout + login (obligatorio en Wayland)
  3. seguir la lista de aceptación que imprime prepare
  4. bash o-tiling/verify.sh report
EOF
}

state_dir() {
  mkdir -p "$STATE_DIR"
  chmod 0700 "$STATE_DIR"
}

require_gnome() {
  command -v gnome-extensions >/dev/null 2>&1 \
    || { echo "Error: gnome-extensions no disponible." >&2; exit 1; }
}

extension_state() {
  gnome-extensions info "$OTILING_UUID" 2>/dev/null \
    | awk -F': ' '/^ *State/{print $2}' | tr -d ' ' || echo "unknown"
}

print_checklist() {
  cat <<'EOF'

════════════════════════════════════════════════════════════════
 LISTA DE ACEPTACIÓN — o-tiling (release upstream, sin parches)
════════════════════════════════════════════════════════════════

Convención: Ctrl+Alt = navegar foco · Shift+Alt = mover ventana

── BLOQUE A · Auto-tiling al crear ventanas (bug principal) ──
 A1  Ctrl+Alt+T                  → la ventana SE TILEA sola (no flota)
 A2  Ctrl+Alt+T otra vez         → segunda ventana tileada junto a la primera
 A3  Abrir Chrome manualmente    → Chrome se tilea en el árbol
 A4  Abrir 6 ventanas seguidas   → las 6 tileadas, ninguna invisible
    ✔ Pasa solo si además NO aparece
      'meta_window_set_stack_position_no_sync' en el journal

── BLOQUE B · Mover foco (segundo modo de fallo) ──
 B1  Ctrl+Alt+L                  → foco salta a la ventana de la derecha
 B2  Ctrl+Alt+H                  → foco vuelve a la izquierda
 B3  Ctrl+Alt+J                  → foco baja (o nada si no hay vecina)
 B4  Ctrl+Alt+K                  → foco sube
 B5  Repetir B1/B2 cinco veces   → responde SIEMPRE
    ✔ Pasa si el foco se mueve cada vez, sin excepción

── BLOQUE C · Mover ventanas (comportamiento upstream) ──
 C1  Alt+Shift+H / L             → reacomoda; al borde CRUZA al otro monitor
 C2  Alt+Shift+J / K             → reacomoda vertical. SIN nuestro parche,
                                  puede saltar de monitor en el borde. Eso es
                                  upstream, NO es fallo — repórtalo tal cual.
 C3  Alt+/ con dos ventanas      → el grupo pasa a vertical (una arriba, otra abajo)
 C4  Alt+/ otra vez              → vuelve a horizontal

── BLOQUE D · Float y workspaces ──
 D1  Shift+Super+C               → la ventana pasa a flotante
 D2  Shift+Super+C otra vez      → vuelve a tilear
 D3  Alt+1 … Alt+5               → cambia de workspace sin romper el tiling
 D4  Alt+Shift+3                 → mueve la ventana al workspace 3
 D5  Ctrl+Alt+T en workspace vacío → se tilea también ahí

── BLOQUE E · Resiliencia ──
 E1  Bloquear/desbloquear (Super+L) → el tiling se conserva
 E2  Cambiar de workspace y volver  → idem
 E3  Abrir y cerrar 10 ventanas     → sin assertions, sin ventanas invisibles
 E4  Esperar 5 min y abrir otra     → sigue tileando

── Verificación de estado ──
   gnome-extensions info o-tiling@oliwebd.github.com
   → debe decir State: ENABLED y sin Error

En una segunda terminal dejá corriendo durante la prueba:
   journalctl --user -f

Cuando termines: bash o-tiling/verify.sh report
════════════════════════════════════════════════════════════════
EOF
}

cmd_prepare() {
  require_gnome
  state_dir
  echo "Instalando $OTILING_VERSION (upstream, sin parches)..."
  bash "$SCRIPT_DIR/install.sh" --force
  echo
  echo "Habilitando la extensión..."
  gnome-extensions enable "$OTILING_UUID" 2>/dev/null || true
  date -u +%Y-%m-%dT%H:%M:%SZ > "$STARTED_AT"
  echo "Timestamp de inicio: $(cat "$STARTED_AT")"
  echo
  echo "⚠  En Wayland hace falta logout + login para que gnome-shell la cargue."
  print_checklist
  echo
  echo "Estado actual: $(extension_state)"
}

cmd_integrity() {
  require_gnome
  command -v curl >/dev/null 2>&1 || { echo "Error: falta curl." >&2; exit 1; }
  command -v python3 >/dev/null 2>&1 || { echo "Error: falta python3." >&2; exit 1; }
  [[ -d "$EXT_DIR" ]] || { echo "Error: la extensión no está instalada." >&2; exit 1; }

  echo "Comprobando que la extensión instalada es idéntica al release upstream..."
  local tmpdir tmp
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/o-tiling-verify.XXXXXX")"
  tmp="$tmpdir/release.zip"
  trap 'rm -rf "$tmpdir"' EXIT
  curl -fsSL "https://github.com/oliwebd/o-tiling/releases/download/${OTILING_VERSION}/${OTILING_UUID}-${OTILING_VERSION}.zip" \
    -o "$tmp"

  python3 - "$tmp" "$EXT_DIR" <<'PY'
import hashlib, sys, zipfile
from pathlib import Path

archive, version, ext_dir = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
with zipfile.ZipFile(archive) as z:
    upstream = {}
    for info in z.infolist():
        if info.is_dir():
            continue
        # El ZIP puede traer un prefijo de directorio; nos quedamos con la ruta relativa.
        rel = info.filename.split('/', 1)[1] if '/' in info.filename else info.filename
        upstream[rel] = hashlib.sha256(z.read(info)).hexdigest()

installed = {}
GENERATED = {'.installed-version', 'schemas/gschemas.compiled'}

for p in ext_dir.rglob('*'):
    if p.is_file() and not p.is_symlink():
        rel = str(p.relative_to(ext_dir))
        # El marcador de instalación y el cache de schemas los generamos nosotros;
        # no forman parte del ZIP upstream.
        if rel in GENERATED or rel.startswith('.'):
            continue
        installed[rel] = hashlib.sha256(p.read_bytes()).hexdigest()

missing = sorted(set(upstream) - set(installed))
extra = sorted(set(installed) - set(upstream))
changed = sorted(f for f in set(upstream) & set(installed) if upstream[f] != installed[f])

if missing:
    print('✗ Archivos del release que faltan:', file=sys.stderr)
    for f in missing:
        print('   -', f, file=sys.stderr)
if extra:
    print('✗ Archivos que no están en el release:', file=sys.stderr)
    for f in extra:
        print('   +', f, file=sys.stderr)
if changed:
    print('✗ Archivos MODIFICADOS respecto al release (parche manual):', file=sys.stderr)
    for f in changed:
        print('   ~', f, file=sys.stderr)

if missing or extra or changed:
    sys.exit(1)
print(f'✓ Integridad OK: {len(installed)} archivos idénticos al release upstream {version}.')
print('✓ No hay ningún parche manual aplicado.')
PY
}

cmd_report() {
  require_gnome
  state_dir
  local started
  started="$(cat "$STARTED_AT" 2>/dev/null || true)"
  [[ -n "$started" ]] || { echo "Error: ejecutá 'verify.sh prepare' primero." >&2; exit 1; }

  echo "════════ Evidencia del journal desde $started ════════"
  local hits
  hits="$(journalctl --user --since "$started" --no-pager 2>/dev/null \
    | grep -E "$BUG_PATTERNS" || true)"
  if [[ -n "$hits" ]]; then
    echo "✗ Se detectaron assertions del bug conocido:"
    echo "$hits" | tail -20
  else
    echo "✓ Ninguna assertion de stack_position/_syncStacking en el periodo."
  fi
  local js_errors
  js_errors="$(journalctl --user --since "$started" --no-pager 2>/dev/null \
    | grep -E 'JS ERROR|Extension.*error' | grep -i "$OTILING_UUID" || true)"
  if [[ -n "$js_errors" ]]; then
    echo "✗ Errores JS de la extensión:"
    echo "$js_errors" | tail -10
  else
    echo "✓ Ningún JS ERROR de la extensión."
  fi
  echo
  echo "Estado actual: $(extension_state)"
  echo

  echo "Marcá PASS o FAIL por bloque (A B C D E)."
  local block answer
  local -a verdicts=()
  for block in A B C D E; do
    answer=""
    read -r -p "  Bloque $block [PASS/FAIL/skip]: " answer || answer="skip"
    case "$answer" in
      PASS|pass|P|p) verdicts+=("$block:PASS") ;;
      FAIL|fail|F|f)
        detail=""
        read -r -p "    Caso que falló (ej. B2): " detail || detail=""
        verdicts+=("$block:FAIL:${detail:-unspecified}") ;;
      *) verdicts+=("$block:SKIP") ;;
    esac
  done

  {
    echo "o-tiling $OTILING_VERSION — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "journal_hits=$( [[ -n "$hits" ]] && echo yes || echo no )"
    printf '%s\n' "${verdicts[@]}"
  } > "$VERDICT"

  echo
  echo "════════ Veredicto ════════"
  printf '%s\n' "${verdicts[@]}"
  echo

  # Retirada automática si el bug principal reaparece.
  local has_failure=0
  for entry in "${verdicts[@]}"; do
    case "$entry" in
      A:FAIL*|B:FAIL*) has_failure=1 ;;
    esac
  done
  [[ -n "$hits" ]] && has_failure=1

  if [[ "$has_failure" -eq 1 ]]; then
    echo "✗ FALLÓ el núcleo (A/B o assertion en el journal)."
    echo "  Deshabilitando la extensión y quedando a la espera de upstream."
    gnome-extensions disable "$OTILING_UUID" 2>/dev/null || true
    echo "  Resultado guardado en: $VERDICT"
    echo "  Pin mantenido en $OTILING_VERSION; sin parches manuales."
    return 1
  fi

  echo "✓ Aceptación superada. La extensión queda HABILITADA."
  echo "  Resultado guardado en: $VERDICT"
  return 0
}

cmd_status() {
  require_gnome
  echo "UUID:        $OTILING_UUID"
  echo "Versión pin: $OTILING_VERSION"
  echo "Estado:      $(extension_state)"
  local marker="$EXT_DIR/.installed-version"
  [[ -f "$marker" ]] && echo "Marcador:    $(cat "$marker")" || echo "Marcador:    (sin instalar)"
  if [[ -f "$STARTED_AT" ]]; then
    echo "Prueba desde: $(cat "$STARTED_AT")"
  else
    echo "Prueba desde: (sin prepare)"
  fi
  [[ -f "$VERDICT" ]] && { echo "Último veredicto:"; sed 's/^/  /' "$VERDICT"; } || true
}

case "${1:-help}" in
  prepare)   cmd_prepare ;;
  integrity) cmd_integrity ;;
  report)    cmd_report ;;
  status)    cmd_status ;;
  help|-h|--help) usage ;;
  *) echo "Comando desconocido: $1" >&2; usage; exit 2 ;;
esac
