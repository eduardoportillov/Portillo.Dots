#!/usr/bin/env bash

install_opencode() {
  if command -v opencode >/dev/null 2>&1; then
    opencode --version | grep -Eq '(^|v)2\.' \
      || die 'Existing OpenCode is not V2; migrate/remove it explicitly before installing'
    [[ "$UPGRADE" == true ]] || return 0
  fi
  # Official V2 installer, always as the invoking user. No npm global root writes.
  run_installer opencode https://opencode.ai/v2/install
  export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$PATH"
  command -v opencode >/dev/null 2>&1 || die 'OpenCode installer did not expose the executable'
  opencode --version | grep -Eq '(^|v)2\.' || die 'OpenCode V2 verification failed'
}

configure_opencode() {
  local directory="$CONFIG_HOME/opencode" generated="$STATE_DIR/opencode-$PROFILE.jsonc"
  local destination="$directory/opencode.jsonc" template="$REPO_DIR/opencode/base.jsonc"
  local env_file="$WORK_DIR/unused.env"
  local overlays=()
  mkdir -p "$directory"
  # Preserve any independent JSON/JSONC setup. Changing a profile doesn't grant
  # permission to overwrite the user's actual credentials or custom plugins.
  if [[ -e "$directory/opencode.json" || -L "$directory/opencode.json" ]]; then
    warn 'Preserving existing opencode.json; merge profile permissions manually'
    return 0
  fi
  if [[ -e "$destination" || -L "$destination" ]]; then
    if [[ ! -L "$destination" || "$(readlink "$destination")" != "$STATE_DIR"/opencode-*.jsonc ]]; then
      warn 'Preserving independent opencode.jsonc; merge profile permissions manually'
      return 0
    fi
  fi
  if [[ "$OPENCODE_TEMPLATE" == true ]]; then
    template="$REPO_DIR/opencode/opencode.template.jsonc"
    env_file="$REPO_DIR/opencode/.env"
  fi
  [[ "$PROFILE" != server ]] || overlays=(--overlay "$REPO_DIR/opencode/server.jsonc")
  python3 "$REPO_DIR/opencode/render-config.py" --template "$template" \
    --env "$env_file" --output "$generated" ${overlays[@]+"${overlays[@]}"}
  symlink_file "$generated" "$destination"
  # Remove only the exact legacy link this repository used to install.
  if [[ -L "$directory/config.jsonc" && "$(readlink "$directory/config.jsonc")" == "$REPO_DIR/opencode/opencode.jsonc" ]]; then
    backup "$directory/config.jsonc"
  fi
}
