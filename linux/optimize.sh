#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════
# Portillo Linux Settings
# Aplica UN PERFIL de ajustes de hardware elegido por el autor de este repo.
# NO son optimizaciones universales: son preferencias concretas que priorizan
# rendimiento y salud de batería en un ASUS TUF concreto.
#
# Antes de usarlo, ejecuta `--list` y revisa cada valor. Todos se pueden
# sobrescribir por variable de entorno, p. ej.:
#
#     sudo CPU_GOVERNOR=schedutil SWAPPINESS=60 ./optimize.sh --apply
#
# Solo escribe lo que el hardware expone y omite lo que no encuentra.
# No configura red, usuarios, firewall, shell ni software de producción.
# ═══════════════════════════════════════════════════

# === CONFIGURATION ===
# NOTA: el límite de carga de batería NO se maneja acá. Es responsabilidad
# exclusiva de la regla udev linux/99-battery-charge-threshold.rules (se dispara
# en boot, suspensión y hotplug). Antes esto escribía charge_control_end_threshold
# y charge_mode, pero era redundante con udev y la lógica de charge_mode era
# incorrecta (es un atributo de solo-lectura). Ver TODO.md.
#
# PERFIL (sobrescribible por entorno):
#   CPU_GOVERNOR     performance | schedutil | powersave
#   CPU_EPP          performance | balance_performance | balance_power | power
#   THROTTLE_POLICY  ASUS: 0=Balanced (dynamic fans), 1=Turbo (loud), 2=Silent
#   PPD_PROFILE      power-profiles-daemon: balanced | performance | power-saver
#   SWAPPINESS       0-200; 10 favorece RAM, 60 es el default conservador
#
# Note: power-profiles-daemon overwrites THROTTLE_POLICY; use PPD_PROFILE instead.
#   balanced→0 (dynamic), performance→1 (loud), power-saver→2 (silent)
CPU_GOVERNOR="${CPU_GOVERNOR:-performance}"
CPU_EPP="${CPU_EPP:-performance}"
THROTTLE_POLICY="${THROTTLE_POLICY:-0}"
PPD_PROFILE="${PPD_PROFILE:-balanced}"
SWAPPINESS="${SWAPPINESS:-10}"
SYSCTL_FILE="/etc/sysctl.d/99-linux-hardware-settings.conf"

# === COLORS ===
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'
info()  { echo -e "${BLUE}ℹ${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

# === DETECTION ===

has_battery() {
  for bat in /sys/class/power_supply/BAT*; do
    [[ -d "$bat" ]] && return 0
  done
  return 1
}

is_asus() {
  local vendor
  vendor="$(cat /sys/class/dmi/id/board_vendor 2>/dev/null || true)"
  vendor="$(printf '%s' "$vendor" | tr '[:lower:]' '[:upper:]')"
  [[ "$vendor" == *"ASUS"* ]]
}

has_charge_control() {
  for bat in /sys/class/power_supply/BAT*; do
    [[ -f "$bat/charge_control_end_threshold" ]] && return 0
  done
  return 1
}

has_asus_throttle() {
  [[ -f /sys/devices/platform/asus-nb-wmi/throttle_thermal_policy ]]
}

has_dgpu_disable() {
  [[ -f /sys/devices/platform/asus-nb-wmi/dgpu_disable ]]
}

is_root() {
  [[ "$(id -u)" -eq 0 ]]
}

# === APPLY SETTINGS ===

apply_cpu_governor() {
  info "Setting CPU governor to '$CPU_GOVERNOR'..."

  if command -v cpupower &>/dev/null; then
    if cpupower frequency-set -g "$CPU_GOVERNOR" &>/dev/null; then
      ok "CPU governor set to $CPU_GOVERNOR (cpupower)"
      apply_cpu_epp
      return 0
    fi
    warn "cpupower failed, falling back to sysfs..."
  fi

  local ok=true
  for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    if [[ -f "$gov" ]] && [[ -w "$gov" ]]; then
      echo "$CPU_GOVERNOR" > "$gov"
    elif [[ -f "$gov" ]] && [[ ! -w "$gov" ]]; then
      ok=false
    fi
  done
  [[ "$ok" == true ]] && ok "CPU governor set to $CPU_GOVERNOR (sysfs)" || warn "CPU governor needs root (try with sudo)"
  apply_cpu_epp
}

apply_cpu_epp() {
  local ok=true
  for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    if [[ -f "$epp" ]] && [[ -w "$epp" ]]; then
      echo "$CPU_EPP" > "$epp"
    elif [[ -f "$epp" ]] && [[ ! -w "$epp" ]]; then
      ok=false
    fi
  done
  [[ "$ok" == true ]] && ok "Energy Performance Preference → $CPU_EPP"
}

apply_ppd_profile() {
  if ! command -v powerprofilesctl &>/dev/null; then
    return 0
  fi

  # Timeout corto: si PPD aún no levantó (boot temprano), no colgamos el
  # servicio 75s esperando dbus. La unit ya tiene After=power-profiles-daemon
  # pero esto es defensa en profundidad.
  local current
  current="$(timeout 3 powerprofilesctl get 2>/dev/null || echo "")"

  if [[ -z "$current" ]]; then
    warn "power-profiles-daemon no responde (timeout). Skipping PPD profile."
    return 0
  fi

  if [[ "$current" == "$PPD_PROFILE" ]]; then
    ok "power-profiles-daemon already at $PPD_PROFILE"
    return 0
  fi

  if timeout 3 powerprofilesctl set "$PPD_PROFILE" 2>/dev/null; then
    ok "power-profiles-daemon → $PPD_PROFILE (throttle_thermal_policy mapped accordingly)"
  else
    warn "Failed to set PPD profile to $PPD_PROFILE (timeout o no permitido)"
    return 1
  fi
}

apply_asus_throttle() {
  if ! has_asus_throttle; then
    warn "ASUS throttle_thermal_policy not found"
    return 1
  fi

  local current
  current="$(cat /sys/devices/platform/asus-nb-wmi/throttle_thermal_policy 2>/dev/null || true)"

  if [[ "$current" == "$THROTTLE_POLICY" ]]; then
    ok "ASUS throttle_thermal_policy already at $THROTTLE_POLICY"
    return 0
  fi

  if ! is_root; then
    warn "Need root to set throttle_thermal_policy (try with sudo)"
    return 1
  fi

  local pol_val="$THROTTLE_POLICY"
  local pol_names=("Balanced" "Turbo" "Silent")

  if echo "$pol_val" > /sys/devices/platform/asus-nb-wmi/throttle_thermal_policy 2>/dev/null; then
    ok "ASUS throttle_thermal_policy → ${pol_names[$pol_val]:-$pol_val}"
  else
    warn "Failed to set throttle_thermal_policy (manual: echo 0 | sudo tee /sys/devices/platform/asus-nb-wmi/throttle_thermal_policy)"
  fi
}

apply_swappiness() {
  if ! is_root; then
    warn "Need root to set swappiness (try with sudo)"
    return 1
  fi

  local current
  current="$(sysctl -n vm.swappiness 2>/dev/null || echo "")"

  if [[ "$current" == "$SWAPPINESS" ]]; then
    ok "vm.swappiness already at $SWAPPINESS"
  else
    sysctl -w "vm.swappiness=$SWAPPINESS" &>/dev/null && {
      ok "vm.swappiness → $SWAPPINESS"
    } || {
      warn "Failed to set vm.swappiness"
      return 1
    }
  fi

  mkdir -p "$(dirname "$SYSCTL_FILE")"
  if grep -q "vm.swappiness" "$SYSCTL_FILE" 2>/dev/null; then
    sed -i "s/^.*vm.swappiness.*/vm.swappiness = $SWAPPINESS/" "$SYSCTL_FILE"
  else
    echo "vm.swappiness = $SWAPPINESS" >> "$SYSCTL_FILE"
  fi
  ok "vm.swappiness persisted in $SYSCTL_FILE"
}

apply_asus_dgpu_disable() {
  if ! has_dgpu_disable; then
    return 0
  fi

  if ! is_root; then
    return 1
  fi

  local current
  current="$(cat /sys/devices/platform/asus-nb-wmi/dgpu_disable 2>/dev/null || echo "0")"

  if [[ "$current" != "1" ]]; then
    warn "ASUS dGPU is enabled. To disable: echo 1 | sudo tee /sys/devices/platform/asus-nb-wmi/dgpu_disable"
    info "Skipping dGPU disable (system may need GPU for external monitors)"
  fi
}

# === MAIN ===

print_summary() {
  echo ""
  info "=== System Summary ==="
  info "  Battery:       $(has_battery && echo 'Yes' || echo 'No')"
  info "  ASUS hardware: $(is_asus && echo 'Yes' || echo 'No')"
  info "  Charge ctrl:   $(has_charge_control && echo 'Yes' || echo 'No')"
  info "  ASUS throttle: $(has_asus_throttle && echo 'Yes' || echo 'No')"
  echo ""
}

show_help() {
  cat <<'HELP'
Usage: optimize.sh [OPTIONS]

Applies a chosen hardware profile. These are the author's preferences for one
ASUS TUF laptop, NOT universal optimisations. Review them with --list first.

The script only writes settings the hardware exposes and skips the rest. It
never touches networking, users, firewall, shell or production software.

OPTIONS:
  --list, --dry-run       Print the active profile and exit without writing
  -a, --apply             Apply the profile (default action)
  -h, --help              Show this help message and exit

ENVIRONMENT (each value is overridable):
  CPU_GOVERNOR     performance | schedutil | powersave     (default: performance)
  CPU_EPP          performance | balance_performance | ... (default: performance)
  PPD_PROFILE      balanced | performance | power-saver    (default: balanced)
  SWAPPINESS       0-200                                   (default: 10)
  THROTTLE_POLICY  ASUS 0=Balanced 1=Turbo 2=Silent        (default: 0)

EXAMPLES:
  sudo ./optimize.sh --list
  sudo ./optimize.sh --apply
  sudo CPU_GOVERNOR=schedutil SWAPPINESS=60 ./optimize.sh --apply
HELP
}

show_profile() {
  echo "Perfil de hardware que se aplicaría:"
  echo "  CPU_GOVERNOR     = $CPU_GOVERNOR"
  echo "  CPU_EPP          = $CPU_EPP"
  echo "  PPD_PROFILE      = $PPD_PROFILE"
  echo "  SWAPPINESS       = $SWAPPINESS  (persistido en $SYSCTL_FILE)"
  echo "  THROTTLE_POLICY  = $THROTTLE_POLICY  (solo hardware ASUS)"
  echo
  echo "Batería: gestionada por la regla udev 99-battery-charge-threshold.rules,"
  echo "  no por este script. Revisa ese archivo antes de instalarlo: el umbral"
  echo "  y el dispositivo están fijados para un equipo concreto."
  echo
  echo "Estos valores son una preferencia personal, no una optimización universal."
}

main() {
  if [[ $# -gt 0 ]]; then
    case "$1" in
      -a|--apply) ;;
      --list|--dry-run) show_profile; exit 0 ;;
      -h|--help) show_help; exit 0 ;;
      *) error "Unknown option: $1"; show_help; exit 1 ;;
    esac
  fi

  show_profile
  echo
  print_summary

  echo "━━━ Power Profile (PPD) ━━━"
  apply_ppd_profile || true

  echo ""
  echo "━━━ CPU Governor ━━━"
  apply_cpu_governor || true

  echo ""
  echo "━━━ Memory Tuning ━━━"
  apply_swappiness || true

  echo ""
  echo "━━━ Battery & Charging ━━━"
  info "Límite de carga gestionado por udev (99-battery-charge-threshold.rules), no por este script"

  echo ""
  echo "━━━ ASUS Hardware ━━━"
  if is_asus; then
    apply_asus_throttle || true
    apply_asus_dgpu_disable || true
  else
    info "Not an ASUS system, skipping ASUS-specific settings"
  fi

  echo ""
  ok "Optimization complete"
}

main "$@"
