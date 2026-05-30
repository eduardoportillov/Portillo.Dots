#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════
# Portillo Linux Optimizer
# Detects hardware and applies optimal settings.
# Safe to run on any Linux (desktop, laptop, server).
# ═══════════════════════════════════════════════════

# === CONFIGURATION ===
# NOTA: el límite de carga de batería NO se maneja acá. Es responsabilidad
# exclusiva de la regla udev linux/99-battery-charge-threshold.rules (se dispara
# en boot, suspensión y hotplug). Antes esto escribía charge_control_end_threshold
# y charge_mode, pero era redundante con udev y la lógica de charge_mode era
# incorrecta (es un atributo de solo-lectura). Ver TODO.md.
# Throttle policy: 0=Balanced (dynamic fans), 1=Turbo (loud), 2=Silent
# Note: power-profiles-daemon overwrites this; use PPD_PROFILE instead.
THROTTLE_POLICY=0
# PPD profile drives throttle_thermal_policy on ASUS:
#   balanced→0 (dynamic), performance→1 (loud), power-saver→2 (silent)
PPD_PROFILE=balanced
SWAPPINESS=10
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
  [[ "${vendor^^}" == *"ASUS"* ]]
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
  info "Setting CPU governor to 'performance'..."

  if command -v cpupower &>/dev/null; then
    if cpupower frequency-set -g performance &>/dev/null; then
      ok "CPU governor set to performance (cpupower)"
      apply_cpu_epp
      return 0
    fi
    warn "cpupower failed, falling back to sysfs..."
  fi

  local ok=true
  for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    if [[ -f "$gov" ]] && [[ -w "$gov" ]]; then
      echo "performance" > "$gov"
    elif [[ -f "$gov" ]] && [[ ! -w "$gov" ]]; then
      ok=false
    fi
  done
  [[ "$ok" == true ]] && ok "CPU governor set to performance (sysfs)" || warn "CPU governor needs root (try with sudo)"
  apply_cpu_epp
}

apply_cpu_epp() {
  local ok=true
  for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    if [[ -f "$epp" ]] && [[ -w "$epp" ]]; then
      echo "performance" > "$epp"
    elif [[ -f "$epp" ]] && [[ ! -w "$epp" ]]; then
      ok=false
    fi
  done
  [[ "$ok" == true ]] && ok "Energy Performance Preference → performance"
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

Detects hardware and applies optimal Linux settings.
Safe to run on any Linux (desktop, laptop, server).
Unsupported features are skipped silently.

OPTIONS:
  -h, --help              Show this help message

EXAMPLES:
  sudo ./optimize.sh
  sudo ./optimize.sh --apply
HELP
}

main() {
  if [[ $# -gt 0 ]]; then
    case "$1" in
      -a|--apply) ;;
      -h|--help) show_help; exit 0 ;;
      *) error "Unknown option: $1"; show_help; exit 1 ;;
    esac
  fi

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
