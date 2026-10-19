#!/usr/bin/env bash

install_opencode() {
  local reported=""
  if command -v opencode >/dev/null 2>&1; then
    # Probe the version once; a second call would spawn the CLI again.
    reported="$(opencode --version 2>/dev/null || true)"
    [[ "$reported" =~ (^|v)2\. ]] \
      || die 'Existing OpenCode is not V2; migrate/remove it explicitly before installing'
    if [[ "$UPGRADE" == false ]]; then
      record_event unchanged 'opencode V2 already installed'
      return 0
    fi
    record_event updated "opencode V2 ($reported)"
    return 0
  fi
  # Official V2 installer, always as the invoking user. No npm global root writes.
  run_installer opencode https://opencode.ai/v2/install
  export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$PATH"
  command -v opencode >/dev/null 2>&1 || die 'OpenCode installer did not expose the executable'
  opencode --version | grep -Eq '(^|v)2\.' || die 'OpenCode V2 verification failed'
  record_event installed 'opencode V2'
}

# The generated config references secrets as {env:NAME}; it must never contain
# their values. This writes the per-host environment file separately, mode 0600,
# and only when the custom template is selected. Values are emitted as safe shell
# exports so sourcing the file cannot execute anything from the dotenv values.
install_opencode_secrets() {
  local source="$1" destination="$2"
  [[ -f "$source" && ! -L "$source" ]] || return 0
  if [[ -e "$destination" || -L "$destination" ]]; then
    [[ -f "$destination" && ! -L "$destination" && -O "$destination" ]] \
      || { warn "Not replacing unowned or symlinked $destination"; return 0; }
  fi
  local parent temporary
  parent="$(dirname "$destination")"
  mkdir -p "$parent"
  temporary="$(mktemp "$parent/.secrets.XXXXXXXX")"
  if ! python3 -B - "$source" > "$temporary" <<'PY'
import re
import shlex
import sys
from pathlib import Path

for number, line in enumerate(Path(sys.argv[1]).read_text().splitlines(), 1):
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    match = re.fullmatch(r'(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)', line)
    if not match:
        raise SystemExit(f'Invalid dotenv assignment on line {number}')
    key, value = match.groups()
    value = value.strip()
    if value[:1] in ('"', "'") and len(value) >= 2 and value[-1] == value[0]:
        value = value[1:-1]
    print(f'export {key}={shlex.quote(value)}')
PY
  then
    rm -f "$temporary"
    warn 'Could not render the OpenCode secrets env; leaving the previous file in place'
    return 1
  fi
  chmod 0600 "$temporary"
  mv -f "$temporary" "$destination"
  chmod 0600 "$destination"
  info "Wrote $destination (0600); loaded automatically by ~/.config/opencode/load-secrets.sh"
  record_event installed "opencode secrets env (0600)"
}

# Client preferences (cli.json) are separate from server/project configuration
# (opencode.jsonc). Only create the file when the user does not already have one.
configure_opencode_client() {
  local template="$REPO_DIR/opencode/cli.json" destination="$CONFIG_HOME/opencode/cli.json"
  mkdir -p "$(dirname "$destination")"
  if [[ -e "$destination" || -L "$destination" ]]; then
    [[ ! -L "$destination" && -f "$destination" ]] \
      || { warn "Preserving existing cli.json: $destination"
           record_event preserved "$destination (independent client config)"
           return 0; }
    info "Preserving independent cli.json: $destination"
    record_event preserved "$destination (independent client config)"
    return 0
  fi
  symlink_file "$template" "$destination"
  symlink_file "$REPO_DIR/opencode/load-secrets.sh" "$CONFIG_HOME/opencode/load-secrets.sh"
}

configure_opencode() {
  local directory="$CONFIG_HOME/opencode" generated="$STATE_DIR/opencode-$PROFILE.jsonc"
  local destination="$directory/opencode.jsonc" template="$REPO_DIR/opencode/base.jsonc"
  local env_file="$WORK_DIR/unused.env" check_args=()
  local overlays=()
  mkdir -p "$directory"
  # Preserve any independent JSON/JSONC setup. Changing a profile doesn't grant
  # permission to overwrite the user's actual credentials or custom plugins.
  if [[ -e "$directory/opencode.json" || -L "$directory/opencode.json" ]]; then
    warn 'Preserving existing opencode.json; merge profile permissions manually'
    record_event preserved "$directory/opencode.json (independent config kept)"
    configure_opencode_client
    return 0
  fi
  if [[ -e "$destination" || -L "$destination" ]]; then
    if [[ ! -L "$destination" || "$(readlink "$destination")" != "$STATE_DIR"/opencode-*.jsonc ]]; then
      warn 'Preserving independent opencode.jsonc; merge profile permissions manually'
      record_event preserved "$destination (independent config kept; merge manually)"
      configure_opencode_client
      return 0
    fi
  fi
  if [[ "$OPENCODE_TEMPLATE" == true ]]; then
    template="$REPO_DIR/opencode/opencode.template.jsonc"
    env_file="$REPO_DIR/opencode/.env"
    check_args=(--template)
  fi
  [[ "$PROFILE" != server ]] || overlays=(--overlay "$REPO_DIR/opencode/server.jsonc")
  python3 "$REPO_DIR/opencode/render-config.py" --template "$template" \
    --env "$env_file" --output "$generated" ${overlays[@]+"${overlays[@]}"} || return 1
  python3 -B "$REPO_DIR/opencode/check-config.py" "$generated" "$PROFILE" "${check_args[@]+"${check_args[@]}"}" \
    || die 'Generated OpenCode config failed its own checks; not installing it'
  symlink_file "$generated" "$destination"
  record_event installed "opencode config ($PROFILE)"
  if [[ "$OPENCODE_TEMPLATE" == true ]]; then
    install_opencode_secrets "$REPO_DIR/opencode/.env" "$directory/secrets.env"
  fi
  configure_opencode_client
  # Remove only the exact legacy link this repository used to install.
  if [[ -L "$directory/config.jsonc" && "$(readlink "$directory/config.jsonc")" == "$REPO_DIR/opencode/opencode.jsonc" ]]; then
    backup "$directory/config.jsonc"
  fi
}
