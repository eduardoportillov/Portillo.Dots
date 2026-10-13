#!/usr/bin/env bash
set -euo pipefail

# Never source .env or print its values. The renderer validates before replacing
# the output, escapes JSON strings, and writes secrets with mode 0600.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/render-config.py" "$@"
