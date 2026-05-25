#!/usr/bin/env bash
set -uo pipefail

# === Regenerate OpenCode Configuration ===
# Dynamically rebuilds opencode.jsonc from template using ALL variables from .env
# .env is the source of truth - all variables are injected without hardcoding
# Usage: ./regenerate-config.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/opencode.template.jsonc"
ENV_FILE="$SCRIPT_DIR/.env"
OUTPUT_FILE="$SCRIPT_DIR/opencode.jsonc"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

error() {
  echo -e "${RED}✗${NC} $1" >&2
}

ok() {
  echo -e "${GREEN}✓${NC} $1"
}

info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

# Check if template exists
if [[ ! -f "$TEMPLATE_FILE" ]]; then
  error "Template not found: $TEMPLATE_FILE"
  exit 1
fi

# Check if .env exists
if [[ ! -f "$ENV_FILE" ]]; then
  error ".env file not found: $ENV_FILE"
  exit 1
fi

info "Generating OpenCode configuration..."
info "Template: $TEMPLATE_FILE"
info "Environment: $ENV_FILE"
info "Output: $OUTPUT_FILE"
echo ""

# Read template
config_content="$(<"$TEMPLATE_FILE")"

# Replace ALL variables from .env dynamically
# This ensures .env is the single source of truth
variable_count=0
while IFS='=' read -r key value; do
  # Skip empty lines and comments
  [[ -z "$key" ]] && continue
  [[ "$key" =~ ^#.* ]] && continue
  
  # Trim whitespace
  key="$(echo "$key" | xargs)"
  value="$(echo "$value" | xargs)"
  
  # Replace {{VARIABLE}} with the value from .env
  if [[ "$config_content" == *"\{\{$key\}\}"* ]]; then
    config_content="${config_content//\{\{$key\}\}/$value}"
    info "Injected {{$key}} = ${value:0:20}${value:20:+...}"
    variable_count=$((variable_count + 1))
  fi
done < "$ENV_FILE"

# Write to output file (NOT to ~/.config - this is just the generated artifact)
echo "$config_content" > "$OUTPUT_FILE"

ok "OpenCode configuration generated successfully"
echo ""
echo "Variables injected: $variable_count"
echo "Output file: $OUTPUT_FILE"
echo ""
warn "Remember: This file is generated from .env and template"
warn "To configure OpenCode: edit opencode.template.jsonc or .env, then regenerate"
