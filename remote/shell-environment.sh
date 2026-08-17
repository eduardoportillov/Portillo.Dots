#!/usr/bin/env bash
set -euo pipefail

HOME_REAL="$(cd -P "$HOME" && pwd -P)"
REMOTE_BASE="${PORTILLO_REMOTE_BASE:-$HOME_REAL/.portillo-remote}"
STATE_DIR="${PORTILLO_REMOTE_STATE:-$HOME_REAL/.portillo-dots-remote-state}"
DIRCOLORS_SOURCE="$REMOTE_BASE/zsh/.dircolors"
COLORS_SOURCE="$REMOTE_BASE/.ls-colors.sh"
BASHRC_SOURCE="$REMOTE_BASE/.remote-bashrc"
DIRCOLORS_DEST="$HOME_REAL/.dircolors"
export PATH="$REMOTE_BASE/bin:$HOME_REAL/.local/bin:$PATH"

SENTINEL='Portillo.Dots remote shell state v1'
BLOCK_START='# >>> Portillo.Dots ls colors >>>'
BLOCK_END='# <<< Portillo.Dots ls colors <<<'
ACTIVE_TRANSACTION=""
REMOVE_EMPTY_STATE_ON_EXIT=0
DIRCOLORS_TEMP=""

ok() { printf '[OK] %s\n' "$1"; }
fail() { printf '[ERROR] %s\n' "$1" >&2; }

path_in_home() {
  local path="$1"
  local parent

  [[ "$path" == /* ]] || return 1
  parent="$(dirname -- "$path")" || return 1
  [[ -d "$parent" ]] || return 1
  parent="$(cd -P -- "$parent" && pwd -P)" || return 1

  if [[ "$HOME_REAL" == "/" ]]; then
    return 0
  fi
  [[ "$parent" == "$HOME_REAL" || "$parent" == "$HOME_REAL"/* ]]
}

assert_regular_or_missing() {
  local path="$1"
  if [[ -L "$path" ]] || { [[ -e "$path" ]] && [[ ! -f "$path" ]]; }; then
    fail "Expected a regular file or missing path: $path"
    return 1
  fi
  if [[ -e "$path" ]] && [[ ! -O "$path" ]]; then
    fail "Refusing to edit a file not owned by the current user: $path"
    return 1
  fi
}

validate_state_dir() {
  [[ -e "$STATE_DIR" || -L "$STATE_DIR" ]] || return 1
  if [[ -L "$STATE_DIR" ]] || [[ ! -d "$STATE_DIR" ]] || [[ ! -O "$STATE_DIR" ]]; then
    fail "Unsafe persistent state directory: $STATE_DIR"
    return 2
  fi
  if [[ ! -f "$STATE_DIR/.managed-by-portillo-dots" ]] \
    || [[ -L "$STATE_DIR/.managed-by-portillo-dots" ]] \
    || [[ "$(<"$STATE_DIR/.managed-by-portillo-dots")" != "$SENTINEL" ]]; then
    fail "Persistent state is not owned by this installer: $STATE_DIR"
    return 2
  fi

  local name
  for name in initialized dircolors-original-state dircolors.original \
    dircolors.deployed ls-colors.sh colors-fragment.checksum shell-version.sh bashrc rc-block \
    rc-paths rc-created-paths shell-name tmux-remote.conf; do
    if [[ -L "$STATE_DIR/$name" ]] \
      || { [[ -e "$STATE_DIR/$name" ]] && [[ ! -f "$STATE_DIR/$name" ]]; } \
      || { [[ -e "$STATE_DIR/$name" ]] && [[ ! -O "$STATE_DIR/$name" ]]; }; then
      fail "Unsafe file in persistent state: $STATE_DIR/$name"
      return 2
    fi
  done
  return 0
}

require_complete_state() {
  local name
  for name in initialized dircolors-original-state dircolors.deployed \
    ls-colors.sh colors-fragment.checksum shell-version.sh bashrc rc-block rc-paths \
    rc-created-paths shell-name tmux-remote.conf; do
    if [[ ! -f "$STATE_DIR/$name" ]]; then
      fail "Persistent state is incomplete: $STATE_DIR/$name"
      return 1
    fi
  done
  local original_state
  original_state="$(<"$STATE_DIR/dircolors-original-state")"
  if [[ "$original_state" != "absent" ]] && [[ ! -f "$STATE_DIR/dircolors.original" ]]; then
    fail "Persistent state is missing the original ~/.dircolors backup"
    return 1
  fi
}

validate_state_contents() {
  local entry name
  shopt -s nullglob
  for entry in "$STATE_DIR"/* "$STATE_DIR"/.[!.]* "$STATE_DIR"/..?*; do
    name="${entry##*/}"
    case "$name" in
      .managed-by-portillo-dots|initialized|dircolors-original-state|dircolors.original|\
      dircolors.deployed|ls-colors.sh|colors-fragment.checksum|shell-version.sh|bashrc|rc-block|\
      rc-paths|rc-created-paths|shell-name|tmux-remote.conf|\
      .stage.*|.teardown.*|.rc-block.*|.block.*|.status-block.*|.write.*) ;;
      *)
        fail "Unknown file in persistent state: $entry"
        shopt -u nullglob
        return 1
        ;;
    esac
  done
  shopt -u nullglob
}

kill_dedicated_tmux() {
  if command -v tmux &>/dev/null; then
    tmux -L portillo-dots kill-server 2>/dev/null || true
  fi
}

create_state_dir() {
  if validate_state_dir; then
    chmod 0700 "$STATE_DIR"
    return 0
  else
    local rc=$?
    [[ "$rc" -eq 1 ]] || return "$rc"
  fi

  mkdir -m 0700 "$STATE_DIR"
  printf '%s\n' "$SENTINEL" > "$STATE_DIR/.managed-by-portillo-dots"
  chmod 0600 "$STATE_DIR/.managed-by-portillo-dots"
}

write_atomic() {
  local destination="$1"
  local mode="$2"
  local source="$3"
  local tmp
  tmp="$(mktemp "$STATE_DIR/.write.XXXXXX")"
  install -m "$mode" "$source" "$tmp"
  mv -f "$tmp" "$destination"
}

managed_state_files() {
  printf '%s\n' \
    initialized dircolors-original-state dircolors.original dircolors.deployed \
    ls-colors.sh colors-fragment.checksum shell-version.sh bashrc rc-block \
    rc-paths rc-created-paths shell-name tmux-remote.conf
}

cleanup_transient_files() {
  if [[ -n "$DIRCOLORS_TEMP" ]]; then
    rm -f "$DIRCOLORS_TEMP"
    DIRCOLORS_TEMP=""
  fi
  [[ -d "$STATE_DIR" && ! -L "$STATE_DIR" && -O "$STATE_DIR" ]] || return 0
  [[ -f "$STATE_DIR/.managed-by-portillo-dots" ]] \
    && [[ ! -L "$STATE_DIR/.managed-by-portillo-dots" ]] \
    && [[ "$(<"$STATE_DIR/.managed-by-portillo-dots")" == "$SENTINEL" ]] \
    || return 0
  rm -rf \
    "$STATE_DIR"/.stage.* \
    "$STATE_DIR"/.teardown.* \
    "$STATE_DIR"/.rc-block.* \
    "$STATE_DIR"/.block.* \
    "$STATE_DIR"/.status-block.* \
    "$STATE_DIR"/.write.*
  rm -f "$HOME_REAL"/.dircolors.portillo.*
}

begin_transaction() {
  local state_preexisting="$1"
  shift
  local path
  for path in "$@"; do
    path_in_home "$path" || {
      fail "Unsafe shell config path: $path"
      return 1
    }
  done

  local transaction
  transaction="$(mktemp -d "$HOME_REAL/.portillo-dots-transaction.XXXXXX")" || return 1
  if ! chmod 0700 "$transaction" \
    || ! mkdir "$transaction/state" "$transaction/rc" \
    || ! printf '%s\n' "$state_preexisting" > "$transaction/state-preexisting"; then
    rm -rf "$transaction"
    return 1
  fi

  local name
  while IFS= read -r name; do
    if [[ -f "$STATE_DIR/$name" ]]; then
      if ! cp -p "$STATE_DIR/$name" "$transaction/state/$name"; then
        rm -rf "$transaction"
        return 1
      fi
    fi
  done < <(managed_state_files)

  if [[ -L "$DIRCOLORS_DEST" ]]; then
    if ! printf 'symlink\n' > "$transaction/dircolors-state" \
      || ! readlink "$DIRCOLORS_DEST" > "$transaction/dircolors-target"; then
      rm -rf "$transaction"
      return 1
    fi
  elif [[ -f "$DIRCOLORS_DEST" ]]; then
    if ! printf 'regular\n' > "$transaction/dircolors-state" \
      || ! cp -p "$DIRCOLORS_DEST" "$transaction/dircolors-file"; then
      rm -rf "$transaction"
      return 1
    fi
  else
    if ! printf 'absent\n' > "$transaction/dircolors-state"; then
      rm -rf "$transaction"
      return 1
    fi
  fi

  local index=0
  if ! : > "$transaction/rc-paths"; then
    rm -rf "$transaction"
    return 1
  fi
  for path in "$@"; do
    if ! printf '%s\n' "$path" >> "$transaction/rc-paths"; then
      rm -rf "$transaction"
      return 1
    fi
    if [[ -f "$path" ]]; then
      if ! printf 'regular\n' > "$transaction/rc/$index.state" \
        || ! cp -p "$path" "$transaction/rc/$index.file"; then
        rm -rf "$transaction"
        return 1
      fi
    else
      if ! printf 'absent\n' > "$transaction/rc/$index.state"; then
        rm -rf "$transaction"
        return 1
      fi
    fi
    index=$((index + 1))
  done

  ACTIVE_TRANSACTION="$transaction"
}

rollback_transaction() {
  local transaction="$1"
  [[ -d "$transaction" ]] || return 0
  set +e

  local path state index=0
  while IFS= read -r path; do
    path_in_home "$path" || {
      fail "Unsafe transaction path; skipping rollback: $path"
      index=$((index + 1))
      continue
    }
    state="$(<"$transaction/rc/$index.state")"
    if [[ "$state" == "regular" ]]; then
      replace_rc_file "$path" "$transaction/rc/$index.file"
    else
      rm -f "$path"
    fi
    index=$((index + 1))
  done < "$transaction/rc-paths"

  rm -f "$DIRCOLORS_DEST"
  case "$(<"$transaction/dircolors-state")" in
    regular) cp -p "$transaction/dircolors-file" "$DIRCOLORS_DEST" ;;
    symlink) ln -s "$(<"$transaction/dircolors-target")" "$DIRCOLORS_DEST" ;;
  esac

  local name
  while IFS= read -r name; do
    rm -f "$STATE_DIR/$name"
    if [[ -f "$transaction/state/$name" ]]; then
      cp -p "$transaction/state/$name" "$STATE_DIR/$name"
    fi
  done < <(managed_state_files)

  local state_preexisting
  state_preexisting="$(<"$transaction/state-preexisting")"
  rm -rf "$transaction"
  mkdir -p "$STATE_DIR"
  chmod 0700 "$STATE_DIR"
  cleanup_transient_files
  if [[ "$state_preexisting" == "0" ]]; then
    rm -f "$STATE_DIR/.managed-by-portillo-dots"
    rmdir "$STATE_DIR" 2>/dev/null || true
    REMOVE_EMPTY_STATE_ON_EXIT=0
  else
    printf '%s\n' "$SENTINEL" > "$STATE_DIR/.managed-by-portillo-dots"
    chmod 0600 "$STATE_DIR/.managed-by-portillo-dots"
  fi
  set -e
}

commit_transaction() {
  [[ -n "$ACTIVE_TRANSACTION" ]] || return 0
  rm -rf "$ACTIVE_TRANSACTION"
  ACTIVE_TRANSACTION=""
  REMOVE_EMPTY_STATE_ON_EXIT=0
}

rollback_active_transaction_on_exit() {
  local rc=$?
  trap - EXIT
  if [[ -n "$ACTIVE_TRANSACTION" ]]; then
    rollback_transaction "$ACTIVE_TRANSACTION"
  fi
  cleanup_transient_files
  if [[ "$REMOVE_EMPTY_STATE_ON_EXIT" -eq 1 ]]; then
    rm -f "$STATE_DIR/.managed-by-portillo-dots"
    rmdir "$STATE_DIR" 2>/dev/null || true
  fi
  exit "$rc"
}

generate_rc_block() {
  cat <<'EOF'
# >>> Portillo.Dots ls colors >>>
# Managed by Portillo.Dots. Changes inside this block are replaced on deploy.
if [ -r "$HOME/.portillo-dots-remote-state/ls-colors.sh" ]; then
  . "$HOME/.portillo-dots-remote-state/ls-colors.sh"
fi
if [ -d "$HOME/.portillo-remote/bin" ]; then
  case ":$PATH:" in
    *":$HOME/.portillo-remote/bin:"*) ;;
    *) PATH="$HOME/.portillo-remote/bin:$PATH" ;;
  esac
  export NVIM_APPNAME="portillo-remote/nvim"
  export EDITOR="nvim"
  export VISUAL="nvim"
fi
if command ls --color=auto -d . >/dev/null 2>&1; then
  alias ls='ls --color=auto'
elif command -v gls >/dev/null 2>&1; then
  alias ls='gls --color=auto'
fi
# <<< Portillo.Dots ls colors <<<
EOF
}

validate_block_order() {
  local rc_file="$1"
  awk -v start="$BLOCK_START" -v end="$BLOCK_END" '
    $0 == start {
      if (state != 0 || starts != 0) exit 2
      state = 1
      starts++
      next
    }
    $0 == end {
      if (state != 1 || ends != 0) exit 2
      state = 2
      ends++
      next
    }
    END {
      if (state == 1 || starts != ends) exit 2
    }
  ' "$rc_file"
}

remove_managed_block() {
  local rc_file="$1"
  local output="$2"
  validate_block_order "$rc_file" || {
    fail "Malformed managed block in $rc_file"
    return 1
  }

  awk -v start="$BLOCK_START" -v end="$BLOCK_END" '
    $0 == start { managed = 1; next }
    $0 == end { managed = 0; next }
    !managed { print }
  ' "$rc_file" > "$output"
}

extract_managed_block() {
  local rc_file="$1"
  local output="$2"
  validate_block_order "$rc_file" || return 1
  awk -v start="$BLOCK_START" -v end="$BLOCK_END" '
    $0 == start { managed = 1 }
    managed { print }
    $0 == end { managed = 0 }
  ' "$rc_file" > "$output"
}

resolve_shell_config() {
  local shell_path="${SHELL:-/bin/bash}"
  local shell_name="${shell_path##*/}"
  local paths=()
  local home_real
  home_real="$(cd -P "$HOME" && pwd -P)"

  case "$shell_name" in
    bash)
      paths+=("$home_real/.bashrc")
      if [[ -e "$home_real/.bash_profile" ]]; then
        paths+=("$home_real/.bash_profile")
      elif [[ -e "$home_real/.bash_login" ]]; then
        paths+=("$home_real/.bash_login")
      elif [[ -e "$home_real/.profile" ]]; then
        paths+=("$home_real/.profile")
      else
        paths+=("$home_real/.bash_profile")
      fi
      ;;
    zsh)
      local zsh_bin zdotdir
      zsh_bin="$(command -v zsh || true)"
      [[ -n "$zsh_bin" ]] || {
        fail "The login shell is Zsh but zsh is not available"
        return 1
      }
      zdotdir="$(HOME="$home_real" "$zsh_bin" -c 'printf "%s" "${ZDOTDIR:-$HOME}"')"
      if [[ ! -d "$zdotdir" ]]; then
        fail "ZDOTDIR does not exist or is not a directory: $zdotdir"
        return 1
      fi
      zdotdir="$(cd -P "$zdotdir" && pwd -P)"
      case "$zdotdir/" in
        "$home_real"/*) paths+=("$zdotdir/.zshrc") ;;
        *)
          fail "ZDOTDIR must be inside HOME for managed SSH integration: $zdotdir"
          return 1
          ;;
      esac
      ;;
    *)
      fail "Direct SSH integration supports Bash and Zsh, not $shell_name"
      return 1
      ;;
  esac

  printf '%s\n' "$shell_name"
  printf '%s\n' "${paths[@]}"
}

prepare_rc_install() {
  local rc_file="$1"
  local block_file="$2"
  local output="$3"

  assert_regular_or_missing "$rc_file"
  if [[ -f "$rc_file" ]]; then
    remove_managed_block "$rc_file" "$output"
  else
    : > "$output"
  fi

  if [[ -s "$output" ]]; then
    local last_byte
    last_byte="$(od -An -tuC -j "$(( $(wc -c < "$output") - 1 ))" -N 1 "$output" \
      | tr -d '[:space:]')"
    [[ "$last_byte" == "10" ]] || printf '\n' >> "$output"
  fi
  cat "$block_file" >> "$output"
}

prepare_rc_remove() {
  local rc_file="$1"
  local expected_block="$2"
  local output="$3"
  local actual_block

  assert_regular_or_missing "$rc_file"
  [[ -f "$rc_file" ]] || {
    fail "Managed shell file is missing: $rc_file"
    return 1
  }

  actual_block="$(mktemp "$STATE_DIR/.block.XXXXXX")"
  extract_managed_block "$rc_file" "$actual_block" || {
    rm -f "$actual_block"
    fail "Malformed managed block in $rc_file"
    return 1
  }
  if ! cmp -s "$actual_block" "$expected_block"; then
    rm -f "$actual_block"
    fail "Managed shell block was modified in $rc_file; refusing teardown"
    return 1
  fi
  rm -f "$actual_block"
  remove_managed_block "$rc_file" "$output"
}

generate_tmux_conf() {
  local src="$REMOTE_BASE/tmux/tmux.conf"
  local dst="$1"
  [[ -f "$src" ]] || {
    : > "$dst"
    return 0
  }

  cat "$src" > "$dst"
}

backup_original_dircolors() {
  [[ -f "$STATE_DIR/initialized" ]] && return 0

  if [[ -L "$DIRCOLORS_DEST" ]]; then
    readlink "$DIRCOLORS_DEST" > "$STATE_DIR/dircolors.original"
    printf 'symlink\n' > "$STATE_DIR/dircolors-original-state"
  elif [[ -f "$DIRCOLORS_DEST" ]]; then
    cp -p "$DIRCOLORS_DEST" "$STATE_DIR/dircolors.original"
    printf 'regular\n' > "$STATE_DIR/dircolors-original-state"
  else
    printf 'absent\n' > "$STATE_DIR/dircolors-original-state"
  fi
  : > "$STATE_DIR/initialized"
}

validate_install_inputs() {
  local required
  for required in "$DIRCOLORS_SOURCE" "$COLORS_SOURCE" "$BASHRC_SOURCE"; do
    assert_regular_or_missing "$required"
    [[ -f "$required" ]] || {
      fail "Missing deployment input: $required"
      return 1
    }
  done
  bash -n "$BASHRC_SOURCE" || {
    fail "Generated remote bashrc is invalid"
    return 1
  }
  bash -n "$COLORS_SOURCE" || {
    fail "Generated LS_COLORS fragment is invalid"
    return 1
  }
  if [[ -d "$DIRCOLORS_DEST" && ! -L "$DIRCOLORS_DEST" ]]; then
    fail "$DIRCOLORS_DEST is a directory; refusing to replace it"
    return 1
  fi
  if [[ -L "$DIRCOLORS_DEST" ]] && [[ -d "$DIRCOLORS_DEST" ]]; then
    fail "$DIRCOLORS_DEST points to a directory; refusing to replace it"
    return 1
  fi
  if [[ -e "$DIRCOLORS_DEST" && ! -f "$DIRCOLORS_DEST" && ! -L "$DIRCOLORS_DEST" ]]; then
    fail "$DIRCOLORS_DEST has an unsupported file type"
    return 1
  fi
}

replace_rc_file() {
  local destination="$1"
  local source="$2"
  local parent base tmp
  parent="$(dirname "$destination")"
  base="$(basename "$destination")"
  tmp="$(mktemp "$parent/.${base}.portillo.XXXXXX")"

  if [[ -f "$destination" ]]; then
    cp -p "$destination" "$tmp"
    cat "$source" > "$tmp"
  else
    install -m 0644 "$source" "$tmp"
  fi
  mv -f "$tmp" "$destination"
}

install_environment() {
  validate_install_inputs

  local shell_config shell_name
  shell_config="$(resolve_shell_config)"
  shell_name="${shell_config%%$'\n'*}"
  local rc_paths_text="${shell_config#*$'\n'}"
  local rc_paths=()
  while IFS= read -r path; do
    [[ -n "$path" ]] && rc_paths+=("$path")
  done <<< "$rc_paths_text"

  local path
  for path in "${rc_paths[@]}"; do
    assert_regular_or_missing "$path"
  done

  local state_preexisting=0 state_rc=0
  if validate_state_dir; then
    state_preexisting=1
    validate_state_contents
  else
    state_rc=$?
    [[ "$state_rc" -eq 1 ]] || return "$state_rc"
  fi
  [[ "$state_preexisting" -eq 1 ]] || REMOVE_EMPTY_STATE_ON_EXIT=1
  create_state_dir
  validate_state_contents

  if [[ -f "$STATE_DIR/dircolors.deployed" ]]; then
    if [[ ! -f "$DIRCOLORS_DEST" ]] || [[ -L "$DIRCOLORS_DEST" ]] \
      || ! cmp -s "$DIRCOLORS_DEST" "$STATE_DIR/dircolors.deployed"; then
      fail "$DIRCOLORS_DEST changed after deployment; run teardown or resolve it manually"
      return 1
    fi
  fi

  local block_file
  block_file="$(mktemp "$STATE_DIR/.rc-block.XXXXXX")"
  generate_rc_block > "$block_file"

  local stage_dir
  stage_dir="$(mktemp -d "$STATE_DIR/.stage.XXXXXX")"

  # Keep every previously managed shell path so switching between Bash and Zsh
  # does not orphan blocks and teardown can restore all of them.
  if [[ -f "$STATE_DIR/rc-paths" ]]; then
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      path_in_home "$path" || {
        fail "Unsafe rc path in state: $path"
        rm -rf "$stage_dir"
        return 1
      }
      local already_managed=0 current
      for current in "${rc_paths[@]}"; do
        [[ "$current" == "$path" ]] && already_managed=1
      done
      if [[ "$already_managed" -eq 0 ]]; then
        rc_paths+=("$path")
      fi
    done < "$STATE_DIR/rc-paths"
  fi

  local created_paths=()
  if [[ -f "$STATE_DIR/rc-created-paths" ]]; then
    while IFS= read -r path; do
      [[ -n "$path" ]] && created_paths+=("$path")
    done < "$STATE_DIR/rc-created-paths"
  fi

  local i
  for i in "${!rc_paths[@]}"; do
    path="${rc_paths[$i]}"
    if [[ ! -e "$path" ]]; then
      created_paths+=("$path")
    fi
    prepare_rc_install "$path" "$block_file" "$stage_dir/rc.$i"
  done
  generate_tmux_conf "$stage_dir/tmux-remote.conf"

  begin_transaction "$state_preexisting" "${rc_paths[@]}" || {
    rm -rf "$stage_dir" "$block_file"
    return 1
  }

  backup_original_dircolors
  DIRCOLORS_TEMP="$(mktemp "$HOME_REAL/.dircolors.portillo.XXXXXX")"
  install -m 0644 "$DIRCOLORS_SOURCE" "$DIRCOLORS_TEMP"
  mv -f "$DIRCOLORS_TEMP" "$DIRCOLORS_DEST"
  DIRCOLORS_TEMP=""

  write_atomic "$STATE_DIR/dircolors.deployed" 0644 "$DIRCOLORS_SOURCE"
  write_atomic "$STATE_DIR/ls-colors.sh" 0600 "$COLORS_SOURCE"
  cksum "$COLORS_SOURCE" | awk '{ print $1, $2 }' \
    > "$STATE_DIR/colors-fragment.checksum"
  write_atomic "$STATE_DIR/bashrc" 0600 "$BASHRC_SOURCE"
  local shell_checksum shell_size
  read -r shell_checksum shell_size _ < <(cat "$COLORS_SOURCE" "$BASHRC_SOURCE" | cksum)
  printf "PORTILLO_SHELL_ENV_VERSION='%s-%s'\nexport PORTILLO_SHELL_ENV_VERSION\n" \
    "$shell_checksum" "$shell_size" > "$STATE_DIR/shell-version.sh"
  chmod 0600 "$STATE_DIR/shell-version.sh"
  write_atomic "$STATE_DIR/rc-block" 0600 "$block_file"
  write_atomic "$STATE_DIR/tmux-remote.conf" 0600 "$stage_dir/tmux-remote.conf"
  printf '%s\n' "$shell_name" > "$STATE_DIR/shell-name"
  printf '%s\n' "${rc_paths[@]}" > "$STATE_DIR/rc-paths"

  for i in "${!rc_paths[@]}"; do
    path="${rc_paths[$i]}"
    replace_rc_file "$path" "$stage_dir/rc.$i"
  done
  printf '%s\n' "${created_paths[@]}" | awk 'NF && !seen[$0]++' \
    > "$STATE_DIR/rc-created-paths"

  rm -rf "$stage_dir"
  rm -f "$block_file"
  commit_transaction
  ok "Persistent SSH colors installed for $shell_name"
}

check_effective_colors() {
  local effective=""
  effective="$(TERM=xterm-256color COLORTERM=truecolor \
    bash --noprofile --rcfile "$STATE_DIR/bashrc" -ic \
    'printf "%s\n" "$LS_COLORS"' 2>/dev/null || true)"

  local expected
  for expected in \
    'ow=01;38;2;228;104;118' \
    'tw=01;38;2;228;104;118' \
    'st=01;38;2;230;195;132' \
    'su=38;2;13;12;12;48;2;228;104;118' \
    '*.zip=38;2;182;146;123'; do
    [[ ":$effective:" == *":$expected:"* ]] || return 1
  done
}

status_environment() {
  validate_state_dir || {
    fail "Persistent SSH integration is not installed"
    return 1
  }
  require_complete_state || return 1
  validate_state_contents || return 1
  local rc=0

  if [[ -f "$DIRCOLORS_DEST" ]] && [[ ! -L "$DIRCOLORS_DEST" ]] \
    && cmp -s "$DIRCOLORS_DEST" "$STATE_DIR/dircolors.deployed"; then
    ok "~/.dircolors matches the deployed map"
  else
    fail "~/.dircolors is missing, modified, or unsafe"
    rc=1
  fi

  if [[ -f "$STATE_DIR/ls-colors.sh" ]] && bash -n "$STATE_DIR/ls-colors.sh"; then
    local current_checksum expected_checksum
    current_checksum="$(cksum "$STATE_DIR/ls-colors.sh" | awk '{ print $1, $2 }')"
    expected_checksum="$(<"$STATE_DIR/colors-fragment.checksum")"
    if [[ "$current_checksum" == "$expected_checksum" ]]; then
      ok "Persistent LS_COLORS fragment is valid and unchanged"
    else
      fail "Persistent LS_COLORS fragment was modified"
      rc=1
    fi
  else
    fail "Persistent LS_COLORS fragment is missing or invalid"
    rc=1
  fi

  if [[ -n "${PORTILLO_EXPECTED_DIRCOLORS_VERSION:-}" ]]; then
    local installed_version=""
    installed_version="$(bash -c 'source "$1"; printf "%s" "$PORTILLO_DIRCOLORS_VERSION"' _ \
      "$STATE_DIR/ls-colors.sh" 2>/dev/null || true)"
    if [[ "$installed_version" == "$PORTILLO_EXPECTED_DIRCOLORS_VERSION" ]]; then
      ok "Remote color map matches the current repository version"
    else
      fail "Remote color map is stale; run remote.sh deploy or connect"
      rc=1
    fi
  fi

  if [[ -f "$STATE_DIR/bashrc" ]] && bash -n "$STATE_DIR/bashrc"; then
    ok "Persistent remote bashrc is valid"
  else
    fail "Persistent remote bashrc is missing or invalid"
    rc=1
  fi

  local path actual_block
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    path_in_home "$path" || {
      fail "Unsafe rc path in state: $path"
      rc=1
      continue
    }
    actual_block="$(mktemp "$STATE_DIR/.status-block.XXXXXX")"
    if [[ -f "$path" ]] && [[ ! -L "$path" ]] \
      && extract_managed_block "$path" "$actual_block" \
      && cmp -s "$actual_block" "$STATE_DIR/rc-block"; then
      ok "Direct SSH block is current in $path"
    else
      fail "Direct SSH block is missing or modified in $path"
      rc=1
    fi
    rm -f "$actual_block"
  done < "$STATE_DIR/rc-paths"

  if check_effective_colors; then
    ok "Effective Bash colors match Kanagawa Dragon"
  else
    fail "Effective Bash colors do not match"
    rc=1
  fi

  return "$rc"
}

teardown_environment() {
  local state_rc=0
  if validate_state_dir; then
    :
  else
    state_rc=$?
    if [[ "$state_rc" -eq 1 ]]; then
      kill_dedicated_tmux
      ok "Persistent SSH color integration is already absent"
      return 0
    fi
    return "$state_rc"
  fi
  require_complete_state || return 1
  validate_state_contents || return 1

  if [[ ! -f "$DIRCOLORS_DEST" ]] || [[ -L "$DIRCOLORS_DEST" ]] \
    || ! cmp -s "$DIRCOLORS_DEST" "$STATE_DIR/dircolors.deployed"; then
    fail "$DIRCOLORS_DEST was modified; refusing to overwrite it during teardown"
    return 1
  fi

  local stage_dir
  rm -rf \
    "$STATE_DIR"/.stage.* \
    "$STATE_DIR"/.teardown.* \
    "$STATE_DIR"/.rc-block.* \
    "$STATE_DIR"/.block.* \
    "$STATE_DIR"/.status-block.* \
    "$STATE_DIR"/.write.*
  stage_dir="$(mktemp -d "$STATE_DIR/.teardown.XXXXXX")"
  local rc_paths=() created_paths=()
  local path
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    path_in_home "$path" || {
      fail "Unsafe rc path in state: $path"
      return 1
    }
    rc_paths+=("$path")
  done < "$STATE_DIR/rc-paths"
  while IFS= read -r path; do
    [[ -n "$path" ]] && created_paths+=("$path")
  done < "$STATE_DIR/rc-created-paths"

  begin_transaction 1 "${rc_paths[@]}" || {
    rm -rf "$stage_dir"
    return 1
  }

  local i
  for i in "${!rc_paths[@]}"; do
    path="${rc_paths[$i]}"
    path_in_home "$path" || {
      fail "Unsafe rc path in state: $path"
      rm -rf "$stage_dir"
      return 1
    }
    prepare_rc_remove "$path" "$STATE_DIR/rc-block" "$stage_dir/rc.$i"
  done

  for i in "${!rc_paths[@]}"; do
    path="${rc_paths[$i]}"
    local was_created=0 created
    for created in "${created_paths[@]}"; do
      [[ "$created" == "$path" ]] && was_created=1
    done
    if [[ "$was_created" -eq 1 ]] && ! grep -q '[^[:space:]]' "$stage_dir/rc.$i"; then
      rm -f "$path"
    else
      replace_rc_file "$path" "$stage_dir/rc.$i"
    fi
  done

  rm -f "$DIRCOLORS_DEST"
  case "$(<"$STATE_DIR/dircolors-original-state")" in
    regular)
      cp -p "$STATE_DIR/dircolors.original" "$DIRCOLORS_DEST"
      ok "Original ~/.dircolors restored"
      ;;
    symlink)
      ln -s "$(<"$STATE_DIR/dircolors.original")" "$DIRCOLORS_DEST"
      ok "Original ~/.dircolors symlink restored"
      ;;
    absent) ok "Managed ~/.dircolors removed" ;;
    *) fail "Invalid original dircolors state"; return 1 ;;
  esac

  rm -rf "$stage_dir"
  rm -f \
    "$STATE_DIR/.managed-by-portillo-dots" \
    "$STATE_DIR/initialized" \
    "$STATE_DIR/dircolors-original-state" \
    "$STATE_DIR/dircolors.original" \
    "$STATE_DIR/dircolors.deployed" \
    "$STATE_DIR/ls-colors.sh" \
    "$STATE_DIR/colors-fragment.checksum" \
    "$STATE_DIR/shell-version.sh" \
    "$STATE_DIR/bashrc" \
    "$STATE_DIR/rc-block" \
    "$STATE_DIR/rc-paths" \
    "$STATE_DIR/rc-created-paths" \
    "$STATE_DIR/shell-name" \
    "$STATE_DIR/tmux-remote.conf"
  cleanup_transient_files
  rmdir "$STATE_DIR" || {
    fail "Unexpected files remain in $STATE_DIR; refusing recursive deletion"
    return 1
  }
  commit_transaction
  kill_dedicated_tmux
  ok "Persistent SSH color integration removed"
}

trap rollback_active_transaction_on_exit EXIT

case "${1:-}" in
  install)  install_environment ;;
  status)   status_environment ;;
  teardown) teardown_environment ;;
  *)
    fail "Usage: shell-environment.sh {install|status|teardown}"
    exit 2
    ;;
esac
