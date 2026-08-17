#!/usr/bin/env bash
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_DIR="$REPO_DIR/remote"
HOSTS_CONF="$REMOTE_DIR/hosts.conf"
HOSTS_LOCAL_CONF="$REMOTE_DIR/hosts.local.conf"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

info()  { echo -e "${BLUE}ℹ${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }

SSH_PORT=""
SSH_IDENTITY=""
SSH_SOCKET=""
RSYNC_SSH_WRAPPER=""
REMOTE_DEPLOY_ID=""
VERBOSE=0
FORCE=0
SKIP_BINS=0
CLEANUP=1
NO_CD=0
NO_TMUX=1
CD_PATH=""
HOST=""
COMMAND=""

confirm_action() {
  local msg="$1"
  if [[ $FORCE -eq 1 ]]; then
    return 0
  fi
  read -p "$(echo -e ${YELLOW}?)${NC} $msg [y/N]: " -r response
  [[ "$response" =~ ^[Yy]$ ]]
}

usage() {
  cat <<EOF
Usage: remote.sh <command> [host] [options]

Commands:
  deploy              Deploy dotfiles and binaries to remote host
  connect             Deploy + connect via SSH (direct Bash by default)
  teardown            Remove all deployed files from remote host
  status              Check deployment status on remote host
  path <host> <path>  Save path for host
  path <host>         Show paths for host
  path ls             List all saved paths (with connect prompt)
  path d <host>       Delete all local paths for host
  path d <host> <p>   Delete specific path for host

Options:
  --cleanup           Auto-cleanup on disconnect (default)
  --no-cleanup        Keep configs on remote after disconnect
  --tmux              Connect inside dedicated tmux session
  --no-tmux           Connect directly into Bash (default)
  --skip-bins         Skip binary installation
  --cd PATH           Override path this session + auto-save
  --no-cd             Ignore saved paths this session
  --port PORT         SSH port (overrides SSH config)
  --identity FILE     SSH identity file
  -f, --force         Skip confirmation prompts
  -v, --verbose       Verbose output
  -h, --help          Show this help

Examples:
  remote.sh connect ruddy
  remote.sh connect ruddy --cd /var/www/pbx
  remote.sh connect aws-uplabs --port 2222
  remote.sh path ruddy /var/www/pbx
  remote.sh path ls
  remote.sh path d ruddy -f
  remote.sh teardown ruddy -f
EOF
}

parse_args() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  COMMAND="$1"
  shift

  if [[ "$COMMAND" == "-h" ]] || [[ "$COMMAND" == "--help" ]]; then
    usage
    exit 0
  fi

  if [[ "$COMMAND" == "path" ]]; then
    parse_path_args "$@"
    return
  fi

  if [[ $# -lt 1 ]] && [[ "$COMMAND" != "help" ]]; then
    error "Missing host argument"
    usage
    exit 1
  fi

  HOST="$1"
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cleanup)    CLEANUP=1; shift ;;
      --no-cleanup) CLEANUP=0; shift ;;
      --no-tmux)    NO_TMUX=1; shift ;;
      --tmux)       NO_TMUX=0; shift ;;
      --skip-bins)  SKIP_BINS=1; shift ;;
      --no-cd)      NO_CD=1; shift ;;
      --cd)         CD_PATH="$2"; shift 2 ;;
      --port)       SSH_PORT="$2"; shift 2 ;;
      --identity)   SSH_IDENTITY="$2"; shift 2 ;;
      -f|--force)   FORCE=1; shift ;;
      -v|--verbose) VERBOSE=1; shift ;;
      -h|--help)    usage; exit 0 ;;
      *) error "Unknown option: $1"; usage; exit 1 ;;
    esac
  done
}

parse_path_args() {
  PATH_SUBCMD=""
  PATH_ARG1=""
  PATH_ARG2=""

  if [[ $# -lt 1 ]]; then
    error "path requires a subcommand: ls, d, <host>"
    exit 1
  fi

  PATH_SUBCMD="$1"
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--force) FORCE=1; shift ;;
      -h|--help)  usage; exit 0 ;;
      *)
        if [[ -z "$PATH_ARG1" ]]; then
          PATH_ARG1="$1"
        elif [[ -z "$PATH_ARG2" ]]; then
          PATH_ARG2="$1"
        fi
        shift
        ;;
    esac
  done
}

ssh_cmd() {
  local args=(ssh -o ConnectTimeout=10 -o BatchMode=no)
  args+=(
    -o ControlMaster=auto
    -o ControlPath="$SSH_SOCKET"
    -o ControlPersist=10m
  )
  [[ -n "$SSH_PORT" ]] && args+=(-p "$SSH_PORT")
  [[ -n "$SSH_IDENTITY" ]] && args+=(-i "$SSH_IDENTITY")
  [[ "$VERBOSE" -eq 1 ]] && args+=(-v)
  args+=("$HOST")
  "${args[@]}" "$@"
}

rsync_cmd() {
  if [[ -z "$RSYNC_SSH_WRAPPER" ]]; then
    RSYNC_SSH_WRAPPER="$(mktemp)"
    local socket_q port_q identity_q
    printf -v socket_q '%q' "$SSH_SOCKET"
    printf -v port_q '%q' "$SSH_PORT"
    printf -v identity_q '%q' "$SSH_IDENTITY"
    cat > "$RSYNC_SSH_WRAPPER" <<EOF
#!/usr/bin/env bash
args=(ssh -o ConnectTimeout=10 -o BatchMode=no -o ControlMaster=auto -o ControlPath=$socket_q -o ControlPersist=10m)
[[ -n $port_q ]] && args+=(-p $port_q)
[[ -n $identity_q ]] && args+=(-i $identity_q)
exec "\${args[@]}" "\$@"
EOF
    chmod 0700 "$RSYNC_SSH_WRAPPER"
  fi
  local args=(rsync -az)
  [[ "$VERBOSE" -eq 1 ]] && args+=(-v)
  args+=(-e "$RSYNC_SSH_WRAPPER" "$@")
  "${args[@]}"
}

ssh_interactive() {
  local args=(ssh -t -o ConnectTimeout=10 -o BatchMode=no)
  args+=(
    -o ControlMaster=auto
    -o ControlPath="$SSH_SOCKET"
    -o ControlPersist=10m
  )
  [[ -n "$SSH_PORT" ]] && args+=(-p "$SSH_PORT")
  [[ -n "$SSH_IDENTITY" ]] && args+=(-i "$SSH_IDENTITY")
  args+=("$HOST")
  "${args[@]}" "$@"
}

init_ssh_socket() {
  SSH_SOCKET="$(mktemp -d)/control"
  REMOTE_DEPLOY_ID="portillo-dots-$(date +%s)-$$-$RANDOM"
}

cleanup_ssh() {
  if [[ -n "$SSH_SOCKET" ]]; then
    ssh -o ControlPath="$SSH_SOCKET" -O exit "$HOST" 2>/dev/null || true
    rm -rf "$(dirname "$SSH_SOCKET")" 2>/dev/null || true
    [[ -z "$RSYNC_SSH_WRAPPER" ]] || rm -f "$RSYNC_SSH_WRAPPER"
    RSYNC_SSH_WRAPPER=""
  fi
}

check_prerequisites() {
  local missing=()
  command -v rsync &>/dev/null || missing+=("rsync")
  command -v ssh &>/dev/null   || missing+=("ssh")
  command -v curl &>/dev/null  || missing+=("curl")

  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Missing local commands: ${missing[*]}"
    exit 1
  fi
}

check_ssh_connection() {
  info "Testing SSH connection to $HOST..."
  if ssh_cmd true 2>/dev/null; then
    ok "SSH connection OK"
  else
    error "Cannot connect to $HOST"
    exit 1
  fi
}

prepare_remote_base() {
  ssh_cmd "REMOTE_DEPLOY_ID='$REMOTE_DEPLOY_ID' bash -s" <<'REMOTE_BASE_EOF'
set -euo pipefail
base="$HOME/.portillo-remote"
stage="$HOME/.portillo-remote-stage-$REMOTE_DEPLOY_ID"
sentinel='.managed-by-portillo-dots-runtime'
deploy_marker='.portillo-dots-deploy-id'
if [[ -L "$base" ]] || { [[ -e "$base" ]] && [[ ! -d "$base" ]]; }; then
  printf 'Unsafe deployment path: %s\n' "$base" >&2
  exit 1
fi
if [[ -d "$base" && -L "$base/$sentinel" ]]; then
  printf 'Unsafe deployment sentinel: %s\n' "$base/$sentinel" >&2
  exit 1
fi
if [[ -d "$base" && -e "$base/$sentinel" && ! -f "$base/$sentinel" ]]; then
  printf 'Unsafe deployment sentinel: %s\n' "$base/$sentinel" >&2
  exit 1
fi
if [[ -d "$base" && -f "$base/$sentinel" ]] \
  && [[ "$(<"$base/$sentinel")" != 'Portillo.Dots remote runtime v1' ]]; then
  printf 'Unrecognized deployment sentinel: %s\n' "$base/$sentinel" >&2
  exit 1
fi
if [[ -d "$base" && ! -f "$base/$sentinel" ]]; then
  [[ -O "$base" ]] || {
    printf 'Unsafe deployment path ownership: %s\n' "$base" >&2
    exit 1
  }
  if [[ -f "$base/.remote-bashrc" ]] \
    && grep -qF '# Portillo Remote bashrc - auto-generated' "$base/.remote-bashrc"; then
    printf 'Portillo.Dots remote runtime v1\n' > "$base/$sentinel"
  else
    printf 'Unmanaged deployment path: %s\n' "$base" >&2
    exit 1
  fi
fi
[[ ! -e "$stage" && ! -L "$stage" ]] || {
  printf 'Staging path already exists: %s\n' "$stage" >&2
  exit 1
}
if ! mkdir -m 0700 "$stage" \
  || ! printf 'Portillo.Dots remote runtime v1\n' > "$stage/$sentinel" \
  || ! printf '%s\n' "$REMOTE_DEPLOY_ID" > "$stage/$deploy_marker" \
  || ! [[ -O "$stage" ]]; then
  rm -rf "$stage"
  printf 'Staging path is not owned by the current user: %s\n' "$stage" >&2
  exit 1
fi
REMOTE_BASE_EOF
}

rollback_remote_deploy() {
  [[ -n "$REMOTE_DEPLOY_ID" ]] || return 0
  ssh_cmd "REMOTE_DEPLOY_ID='$REMOTE_DEPLOY_ID' bash -s" <<'REMOTE_ROLLBACK_EOF'
set -euo pipefail
base="$HOME/.portillo-remote"
stage="$HOME/.portillo-remote-stage-$REMOTE_DEPLOY_ID"
old="$HOME/.portillo-remote-old-$REMOTE_DEPLOY_ID"
sentinel='.managed-by-portillo-dots-runtime'
deploy_marker='.portillo-dots-deploy-id'

remove_managed_dir() {
  local dir="$1"
  [[ -e "$dir" || -L "$dir" ]] || return 0
  [[ -d "$dir" && ! -L "$dir" && -O "$dir" \
    && -f "$dir/$sentinel" && ! -L "$dir/$sentinel" \
    && "$(<"$dir/$sentinel")" == 'Portillo.Dots remote runtime v1' ]] || {
    printf 'Refusing to remove unmanaged runtime path: %s\n' "$dir" >&2
    return 1
  }
  rm -rf "$dir"
}

if [[ -e "$old" || -L "$old" ]]; then
  [[ -d "$old" && ! -L "$old" && -O "$old" \
    && -f "$old/$sentinel" && ! -L "$old/$sentinel" \
    && "$(<"$old/$sentinel")" == 'Portillo.Dots remote runtime v1' ]] || {
    printf 'Refusing to restore unmanaged rollback path: %s\n' "$old" >&2
    exit 1
  }
  remove_managed_dir "$base"
  mv "$old" "$base"
elif [[ -f "$base/$deploy_marker" && ! -L "$base/$deploy_marker" ]] \
  && [[ "$(<"$base/$deploy_marker")" == "$REMOTE_DEPLOY_ID" ]]; then
  remove_managed_dir "$base"
fi
remove_managed_dir "$stage"
REMOTE_ROLLBACK_EOF
}

finalize_remote_deploy() {
  ssh_cmd "REMOTE_DEPLOY_ID='$REMOTE_DEPLOY_ID' bash -s" <<'REMOTE_FINALIZE_EOF'
set -euo pipefail
old="$HOME/.portillo-remote-old-$REMOTE_DEPLOY_ID"
sentinel='.managed-by-portillo-dots-runtime'
deploy_marker='.portillo-dots-deploy-id'
base="$HOME/.portillo-remote"
[[ -d "$base" && ! -L "$base" && -O "$base" \
  && -f "$base/$sentinel" && ! -L "$base/$sentinel" \
  && "$(<"$base/$sentinel")" == 'Portillo.Dots remote runtime v1' ]] || {
  printf 'Current runtime is not managed by Portillo.Dots\n' >&2
  exit 1
}
if [[ -e "$old" || -L "$old" ]]; then
  [[ -d "$old" && ! -L "$old" && -O "$old" \
    && -f "$old/$sentinel" && ! -L "$old/$sentinel" \
    && "$(<"$old/$sentinel")" == 'Portillo.Dots remote runtime v1' ]] || {
    printf 'Refusing to remove unmanaged rollback path: %s\n' "$old" >&2
    exit 1
  }
fi
if [[ -f "$base/$deploy_marker" && ! -L "$base/$deploy_marker" ]] \
  && [[ "$(<"$base/$deploy_marker")" == "$REMOTE_DEPLOY_ID" ]]; then
  rm -f "$base/$deploy_marker"
else
  printf 'Current runtime does not match deployment transaction\n' >&2
  exit 1
fi
if [[ -e "$old" || -L "$old" ]]; then
  rm -rf "$old"
fi
REMOTE_FINALIZE_EOF
}

abort_remote_deploy() {
  rollback_remote_deploy || warn "Remote runtime rollback needs manual review"
  cleanup_ssh
  return 1
}

cleanup_remote_runtime() {
  info "Cleaning up remote runtime..."
  local rc=0
  ssh_cmd bash -s <<'REMOTE_CLEANUP_EOF' || rc=$?
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
base="$HOME/.portillo-remote"
sentinel='.managed-by-portillo-dots-runtime'
tmux_bin=""
if [[ -e "$base" || -L "$base" ]]; then
  [[ -d "$base" && ! -L "$base" && -O "$base" \
    && -f "$base/$sentinel" && ! -L "$base/$sentinel" \
    && "$(<"$base/$sentinel")" == 'Portillo.Dots remote runtime v1' ]] || {
    printf 'Refusing to remove unmanaged runtime: %s\n' "$base" >&2
    exit 1
  }
fi
if [[ -x "$base/bin/tmux" ]]; then
  tmux_bin="$base/bin/tmux"
elif [[ -x "$HOME/.local/bin/tmux" ]]; then
  tmux_bin="$HOME/.local/bin/tmux"
elif command -v tmux &>/dev/null; then
  tmux_bin="$(command -v tmux)"
fi

if [[ -n "$tmux_bin" ]] && "$tmux_bin" -L portillo-dots list-sessions &>/dev/null; then
  rm -rf "$base/downloads"
  printf 'Portillo.Dots tmux session is active; runtime preserved.\n' >&2
  exit 3
fi

if [[ -e "$base" || -L "$base" ]]; then
  rm -rf "$base"
fi
REMOTE_CLEANUP_EOF
  if [[ "$rc" -eq 0 ]]; then
    ok "Remote runtime cleaned"
    return 0
  fi

  if [[ "$rc" -eq 3 ]]; then
    warn "Remote runtime preserved for the active Portillo.Dots tmux session"
    return 0
  fi
  error "Remote runtime cleanup failed"
  return "$rc"
}

deploy_configs() {
  info "Syncing dotfiles to $HOST..."
  if rsync_cmd \
    --delete \
    --exclude='.git' \
    --exclude='.backup' \
    --exclude='setup.sh' \
    --exclude='alacritty/' \
    --exclude='remote/' \
    --exclude='remote.sh' \
    --exclude='README.md' \
    --exclude='nvim/db_ui/connections.lua' \
    --exclude='.managed-by-portillo-dots-runtime' \
    --exclude='.portillo-dots-deploy-id' \
    "$REPO_DIR/" \
    "$HOST:~/.portillo-remote-stage-$REMOTE_DEPLOY_ID/" \
    && ssh_cmd "REMOTE_DEPLOY_ID='$REMOTE_DEPLOY_ID' bash -s" <<'REMOTE_SWAP_EOF'
set -euo pipefail
base="$HOME/.portillo-remote"
stage="$HOME/.portillo-remote-stage-$REMOTE_DEPLOY_ID"
old="$HOME/.portillo-remote-old-$REMOTE_DEPLOY_ID"
sentinel='.managed-by-portillo-dots-runtime'
deploy_marker='.portillo-dots-deploy-id'
[[ -d "$stage" && ! -L "$stage" && -O "$stage" \
  && -f "$stage/$sentinel" && ! -L "$stage/$sentinel" \
  && "$(<"$stage/$sentinel")" == 'Portillo.Dots remote runtime v1' \
  && -f "$stage/$deploy_marker" && ! -L "$stage/$deploy_marker" \
  && "$(<"$stage/$deploy_marker")" == "$REMOTE_DEPLOY_ID" ]] || exit 1
if [[ -e "$base" || -L "$base" ]]; then
  [[ -d "$base" && ! -L "$base" && -O "$base" \
    && -f "$base/$sentinel" && ! -L "$base/$sentinel" \
    && "$(<"$base/$sentinel")" == 'Portillo.Dots remote runtime v1' ]] || exit 1
fi

preserve_dir() {
  local source="$1"
  local destination="$2"
  [[ -e "$source" || -L "$source" ]] || return 0
  [[ -d "$source" && ! -L "$source" && -O "$source" ]] || {
    printf 'Unsafe managed runtime asset: %s\n' "$source" >&2
    exit 1
  }
  if [[ -e "$destination" || -L "$destination" ]]; then
    [[ -d "$destination" && ! -L "$destination" ]] || {
      printf 'Unsafe staging asset: %s\n' "$destination" >&2
      exit 1
    }
  else
    mkdir -p "$(dirname "$destination")"
    mkdir -m 0700 "$destination"
  fi
  cp -a "$source/." "$destination/"
}

preserve_dir "$base/bin" "$stage/bin"
preserve_dir "$base/downloads" "$stage/downloads"
preserve_dir "$base/fzf" "$stage/fzf"
preserve_dir "$base/node" "$stage/node"
preserve_dir "$base/zig" "$stage/zig"
preserve_dir "$base/tmux/plugins" "$stage/tmux/plugins"

[[ ! -e "$old" && ! -L "$old" ]] || exit 1
[[ ! -e "$base" ]] || mv "$base" "$old"
if mv "$stage" "$base"; then
  :
else
  [[ ! -e "$old" ]] || mv "$old" "$base"
  exit 1
fi
REMOTE_SWAP_EOF
  then
    ok "Dotfiles synced atomically"
  else
    error "Dotfile sync failed"
    return 1
  fi
}

deploy_linux_optimizations() {
  info "Applying Linux optimizations on $HOST..."
  local result
  result="$(ssh_cmd "bash ~/.portillo-remote/linux/optimize.sh --apply 2>&1" 2>/dev/null)" || true
  if echo "$result" | grep -q "Optimization complete"; then
    ok "Linux optimizations applied on $HOST"
  else
    info "Linux optimizations: auto-skipped (root may be needed for some settings)"
  fi
}

deploy_shell_environment() {
  info "Generating remote shell environment..."
  local rc_file colors_file
  rc_file="$(mktemp)"
  colors_file="$(mktemp)"

  if ! bash "$REMOTE_DIR/generate-rc.sh" > "$rc_file" \
    || ! bash -n "$rc_file"; then
    rm -f "$rc_file" "$colors_file"
    error "Failed to generate a valid remote bashrc"
    return 1
  fi

  if ! bash "$REMOTE_DIR/generate-ls-colors.sh" "$REPO_DIR/zsh/.dircolors" > "$colors_file" \
    || ! bash -n "$colors_file"; then
    rm -f "$rc_file" "$colors_file"
    error "Failed to generate a valid LS_COLORS fragment"
    return 1
  fi

  ssh_cmd 'set -e; umask 077; tmp=$(mktemp ~/.portillo-remote/.remote-bashrc.XXXXXX); cat > "$tmp"; mv -f "$tmp" ~/.portillo-remote/.remote-bashrc' < "$rc_file" \
    && ssh_cmd 'set -e; umask 077; tmp=$(mktemp ~/.portillo-remote/.ls-colors.XXXXXX); cat > "$tmp"; mv -f "$tmp" ~/.portillo-remote/.ls-colors.sh' < "$colors_file" \
    && ssh_cmd "bash -s -- install" < "$REMOTE_DIR/shell-environment.sh"
  local rc=$?
  rm -f "$rc_file" "$colors_file"

  if [[ $rc -ne 0 ]]; then
    error "Failed to install remote shell environment"
    return "$rc"
  fi

  ok "Remote shell environment deployed"
}

get_remote_version() {
  local repo="$1"
  local location
  location="$(curl -sI -o /dev/null -w '%{redirect_url}' \
    "https://github.com/$repo/releases/latest" 2>/dev/null)"
  local tag="${location##*/}"
  tag="${tag#v}"
  echo "$tag"
}

download_binaries_locally() {
  local dl_dir="$1"
  mkdir -p "$dl_dir"

  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)  arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    armv7l|armhf)  arch="armv7l" ;;
  esac

  # neovim
  info "neovim..."
  if [[ ! -f "$dl_dir/nvim.appimage" ]]; then
    local nvim_url
    case "$arch" in
      x86_64)  nvim_url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage" ;;
      aarch64) nvim_url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-arm64.appimage" ;;
      armv7l)  nvim_url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-armv7l.tar.gz" ;;
    esac
    info "Downloading neovim..."
    if curl -fSL --connect-timeout 15 --max-time 300 -o "$dl_dir/nvim-download" "$nvim_url" 2>/dev/null; then
      case "$arch" in
        armv7l) mv "$dl_dir/nvim-download" "$dl_dir/nvim.tar.gz" ;;
        *)      mv "$dl_dir/nvim-download" "$dl_dir/nvim.appimage" ;;
      esac
      ok "neovim downloaded"
    else
      warn "Failed to download neovim"
      rm -f "$dl_dir/nvim-download"
    fi
  else
    ok "neovim (cached)"
  fi

  # ripgrep
  info "ripgrep..."
  if [[ ! -f "$dl_dir/rg.tar.gz" ]]; then
    local rg_ver rg_arch
    rg_ver="$(get_remote_version "BurntSushi/ripgrep")"
    case "$arch" in
      x86_64)  rg_arch="x86_64-unknown-linux-musl" ;;
      aarch64) rg_arch="aarch64-unknown-linux-musl" ;;
      armv7l)  rg_arch="armv7-unknown-linux-gnueabihf" ;;
    esac
    info "Downloading ripgrep..."
    if [[ -n "$rg_ver" ]] && curl -fSL --connect-timeout 15 --max-time 120 -o "$dl_dir/rg.tar.gz" \
      "https://github.com/BurntSushi/ripgrep/releases/download/${rg_ver}/ripgrep-${rg_ver}-${rg_arch}.tar.gz" 2>/dev/null; then
      ok "ripgrep downloaded"
    else
      warn "Failed to download ripgrep"
      rm -f "$dl_dir/rg.tar.gz"
    fi
  else
    ok "ripgrep (cached)"
  fi

  # fd
  info "fd..."
  if [[ ! -f "$dl_dir/fd.tar.gz" ]]; then
    local fd_ver fd_arch
    fd_ver="$(get_remote_version "sharkdp/fd")"
    case "$arch" in
      x86_64)  fd_arch="x86_64-unknown-linux-musl" ;;
      aarch64) fd_arch="aarch64-unknown-linux-musl" ;;
      armv7l)  fd_arch="arm-unknown-linux-gnueabihf" ;;
    esac
    info "Downloading fd..."
    if [[ -n "$fd_ver" ]] && curl -fSL --connect-timeout 15 --max-time 120 -o "$dl_dir/fd.tar.gz" \
      "https://github.com/sharkdp/fd/releases/download/v${fd_ver}/fd-v${fd_ver}-${fd_arch}.tar.gz" 2>/dev/null; then
      ok "fd downloaded"
    else
      warn "Failed to download fd"
      rm -f "$dl_dir/fd.tar.gz"
    fi
  else
    ok "fd (cached)"
  fi

  # fzf
  info "fzf..."
  if [[ ! -f "$dl_dir/fzf.tar.gz" ]]; then
    local fzf_ver
    fzf_ver="$(get_remote_version "junegunn/fzf")"
    local fzf_arch
    case "$arch" in
      x86_64)  fzf_arch="linux_amd64" ;;
      aarch64) fzf_arch="linux_arm64" ;;
      armv7l)  fzf_arch="linux_armv7" ;;
    esac
    info "Downloading fzf..."
    if curl -fSL --connect-timeout 15 --max-time 120 -o "$dl_dir/fzf.tar.gz" \
      "https://github.com/junegunn/fzf/releases/download/v${fzf_ver}/fzf-${fzf_ver}-${fzf_arch}.tar.gz" 2>/dev/null; then
      ok "fzf downloaded"
    else
      warn "Failed to download fzf"
      rm -f "$dl_dir/fzf.tar.gz"
    fi
  else
    ok "fzf (cached)"
  fi

  # lazygit
  info "lazygit..."
  if [[ ! -f "$dl_dir/lazygit.tar.gz" ]]; then
    local lg_ver lg_suffix
    lg_ver="$(get_remote_version "jesseduffield/lazygit")"
    case "$arch" in
      x86_64)  lg_suffix="linux_x86_64" ;;
      aarch64) lg_suffix="linux_arm64" ;;
      armv7l)  lg_suffix="linux_armv6" ;;
    esac
    info "Downloading lazygit..."
    if [[ -n "$lg_ver" ]] && curl -fSL --connect-timeout 15 --max-time 120 -o "$dl_dir/lazygit.tar.gz" \
      "https://github.com/jesseduffield/lazygit/releases/download/v${lg_ver}/lazygit_${lg_ver}_${lg_suffix}.tar.gz" 2>/dev/null; then
      ok "lazygit downloaded"
    else
      warn "Failed to download lazygit"
      rm -f "$dl_dir/lazygit.tar.gz"
    fi
  else
    ok "lazygit (cached)"
  fi

  # node & npm
  info "node & npm..."
  if [[ ! -f "$dl_dir/node.tar.xz" ]]; then
    local node_arch
    case "$arch" in
      x86_64)  node_arch="x64" ;;
      aarch64) node_arch="arm64" ;;
      armv7l)  node_arch="armv7l" ;;
    esac
    local node_ver
    node_ver="$(curl -sL https://nodejs.org/dist/index.json | grep -E '"lts":"[A-Za-z]+"' | head -1 | grep -oE '"version":"v[0-9.]+"' | sed 's/"version":"v//;s/"//' || true)"
    [[ -n "$node_ver" ]] || node_ver="24.19.0"
    info "Downloading node & npm (v$node_ver)..."
    if curl -fSL --connect-timeout 15 --max-time 300 -o "$dl_dir/node.tar.xz" \
      "https://nodejs.org/dist/v${node_ver}/node-v${node_ver}-linux-${node_arch}.tar.xz" 2>/dev/null; then
      ok "node & npm downloaded"
    else
      warn "Failed to download node & npm"
      rm -f "$dl_dir/node.tar.xz"
    fi
  else
    ok "node & npm (cached)"
  fi

  # zig (C compiler for treesitter)
  info "C compiler (zig cc)..."
  if [[ ! -f "$dl_dir/zig.tar.xz" ]]; then
    local zig_arch
    case "$arch" in
      x86_64)  zig_arch="x86_64-linux" ;;
      aarch64) zig_arch="aarch64-linux" ;;
      *)       zig_arch="" ;;
    esac
    if [[ -n "$zig_arch" ]]; then
      local zig_ver="0.14.0"
      info "Downloading C compiler (zig cc v$zig_ver)..."
      if curl -fSL --connect-timeout 15 --max-time 300 -o "$dl_dir/zig.tar.xz" \
        "https://ziglang.org/download/${zig_ver}/zig-linux-${zig_arch%-linux}-${zig_ver}.tar.xz" 2>/dev/null; then
        ok "C compiler (zig cc) downloaded"
      else
        warn "Failed to download C compiler"
        rm -f "$dl_dir/zig.tar.xz"
      fi
    fi
  else
    ok "C compiler (cached)"
  fi

  # stylua
  info "stylua..."
  if [[ ! -f "$dl_dir/stylua.zip" ]]; then
    local stylua_arch
    case "$arch" in
      x86_64)  stylua_arch="linux-x86_64" ;;
      aarch64) stylua_arch="linux-aarch64" ;;
      *)       stylua_arch="" ;;
    esac
    if [[ -n "$stylua_arch" ]]; then
      local stylua_ver
      stylua_ver="$(get_remote_version "JohnnyMorganz/StyLua")"
      info "Downloading stylua..."
      if [[ -n "$stylua_ver" ]] && curl -fSL --connect-timeout 15 --max-time 120 -o "$dl_dir/stylua.zip" \
        "https://github.com/JohnnyMorganz/StyLua/releases/download/v${stylua_ver}/stylua-${stylua_arch}.zip" 2>/dev/null; then
        ok "stylua downloaded"
      else
        warn "Failed to download stylua"
        rm -f "$dl_dir/stylua.zip"
      fi
    fi
  else
    ok "stylua (cached)"
  fi
}

deploy_binaries() {
  if [[ $SKIP_BINS -eq 1 ]]; then
    info "Skipping binary installation (--skip-bins)"
    return 0
  fi

  local LOCAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/portillo-remote-downloads"
  mkdir -p "$LOCAL_CACHE"

  info "Preparing binaries..."
  download_binaries_locally "$LOCAL_CACHE"

  info "Transferring binaries to $HOST..."
  if ! rsync_cmd "$LOCAL_CACHE/" "$HOST:~/.portillo-remote/downloads/"; then
    error "Binary transfer failed"
    return 1
  fi

  info "Installing binaries on remote host..."
  cat "$REMOTE_DIR/lib.sh" "$REMOTE_DIR/install-binaries.sh" | ssh_cmd "bash -s"
  local rc=$?

  if [[ $rc -ne 0 ]]; then
    error "Remote binary installation failed"
    return "$rc"
  fi
}

load_host_config() {
  local host_filter="${1:-}"

  local conf_files=("$HOSTS_CONF" "$HOSTS_LOCAL_CONF")
  local current_file=""

  for conf_file in "${conf_files[@]}"; do
    if [[ -f "$conf_file" ]]; then
      current_file="$conf_file"
      while IFS='=' read -r h p || [[ -n "$h" ]]; do
        h="$(echo "$h" | xargs)"
        p="$(echo "$p" | xargs)"
        [[ -z "$h" || -z "$p" ]] && continue
        [[ "$h" =~ ^# ]] && continue
        if [[ -z "$host_filter" ]] || [[ "$h" == "$host_filter" ]]; then
          local source="tracked"
          [[ "$current_file" == "$HOSTS_LOCAL_CONF" ]] && source="local"
          echo "$h|$p|$source"
        fi
      done < "$conf_file"
    fi
  done
}

save_host_path() {
  local host="$1"
  local path="$2"

  touch "$HOSTS_LOCAL_CONF"
  echo "$host=$path" >> "$HOSTS_LOCAL_CONF"
  ok "Saved $host → $path"
}

delete_host_path() {
  local host="$1"
  local specific_path="${2:-}"
  local tmpfile

  if [[ ! -f "$HOSTS_LOCAL_CONF" ]]; then
    warn "No local paths file found"
    return 1
  fi

  tmpfile="$(mktemp)"

  if [[ -n "$specific_path" ]]; then
    local count
    count="$(grep -c "^${host}=${specific_path}" "$HOSTS_LOCAL_CONF" 2>/dev/null || echo "0")"
    if [[ "$count" -eq 0 ]]; then
      warn "$specific_path not found for $host"
      rm -f "$tmpfile"
      return 1
    fi

    confirm_action "Delete $specific_path from $host?" || { info "Cancelled"; rm -f "$tmpfile"; return 0; }

    grep -v "^${host}=${specific_path}" "$HOSTS_LOCAL_CONF" > "$tmpfile"
  else
    local count
    count="$(grep -c "^${host}=" "$HOSTS_LOCAL_CONF" 2>/dev/null || echo "0")"
    if [[ "$count" -eq 0 ]]; then
      warn "No paths found for $host"
      rm -f "$tmpfile"
      return 1
    fi

    confirm_action "Delete all $count paths for $host?" || { info "Cancelled"; rm -f "$tmpfile"; return 0; }

    grep -v "^${host}=" "$HOSTS_LOCAL_CONF" > "$tmpfile"
  fi

  mv "$tmpfile" "$HOSTS_LOCAL_CONF"
  ok "Path(s) deleted"
}

get_host_path() {
  local host="$1"
  local entries
  entries="$(load_host_config "$host")"

  if [[ -z "$entries" ]]; then
    return 0
  fi

  local count
  count="$(echo "$entries" | wc -l)"

  if [[ "$count" -eq 1 ]]; then
    echo "$entries" | head -1 | cut -d'|' -f2
    return 0
  fi

  echo ""
  echo -e "  ${YELLOW}Multiple paths for $host:${NC}"
  echo ""

  local i=1
  while IFS='|' read -r h p s; do
    echo -e "    ${BLUE}$i)${NC} $p"
    i=$((i + 1))
  done <<< "$entries"

  echo ""
  read -p "  Which path? [1-$count / q]: " -r choice

  if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$count" ]]; then
    echo "$entries" | sed -n "${choice}p" | cut -d'|' -f2
    return 0
  fi

  info "Cancelled"
  return 1
}

cmd_path() {
  case "$PATH_SUBCMD" in
    ls)
      local entries
      entries="$(load_host_config)"

      if [[ -z "$entries" ]]; then
        echo ""
        warn "No saved paths."
        info "Usage: ./remote.sh path <host> <path>"
        echo ""
        return 0
      fi

      echo ""
      local current_host=""
      local i=1
      local host_list=()
      local path_list=()

      while IFS='|' read -r h p s; do
        if [[ "$h" != "$current_host" ]]; then
          [[ -n "$current_host" ]] && echo ""
          echo -e "  ${GREEN}$h${NC}"
          current_host="$h"
        fi
        local tag="(tracked)"
        [[ "$s" == "local" ]] && tag="(local)"
        echo -e "    ${BLUE}$i)${NC} $p  ${YELLOW}$tag${NC}"
        host_list+=("$h")
        path_list+=("$p")
        i=$((i + 1))
      done <<< "$entries"

      echo ""
      local total=${#host_list[@]}

      if [[ $FORCE -eq 1 ]] || ! [[ -t 0 ]]; then
        return 0
      fi

      if command -v fzf &>/dev/null; then
        local selection
        selection="$(echo "$entries" | awk -F'|' '{printf "%s  %s  (%s)\n", $1, $2, $3}' | fzf --prompt="Connect > " --height=~20 --reverse --no-multi 2>/dev/null)"
        if [[ -n "$selection" ]]; then
          local sel_host sel_path
          sel_host="$(echo "$selection" | awk '{print $1}')"
          sel_path="$(echo "$selection" | awk '{print $3}')"
          HOST="$sel_host"
          CD_PATH="$sel_path"
          cmd_connect
        fi
      else
        read -p "  Connect? [1-$total / q]: " -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$total" ]]; then
          HOST="${host_list[$((choice - 1))]}"
          CD_PATH="${path_list[$((choice - 1))]}"
          cmd_connect
        fi
      fi
      ;;

    d)
      if [[ -z "$PATH_ARG1" ]]; then
        error "path d requires a host"
        info "Usage: ./remote.sh path d <host> [path]"
        exit 1
      fi
      delete_host_path "$PATH_ARG1" "$PATH_ARG2"
      ;;

    *)
      if [[ -z "$PATH_SUBCMD" ]]; then
        error "path requires a subcommand"
        exit 1
      fi

      local host_entries
      host_entries="$(load_host_config "$PATH_SUBCMD")"

      if [[ -n "$PATH_ARG1" ]]; then
        save_host_path "$PATH_SUBCMD" "$PATH_ARG1"
      elif [[ -n "$host_entries" ]]; then
        echo ""
        echo -e "  ${GREEN}$PATH_SUBCMD${NC}"
        while IFS='|' read -r h p s; do
          local tag="(tracked)"
          [[ "$s" == "local" ]] && tag="(local)"
          echo -e "    $p  ${YELLOW}$tag${NC}"
        done <<< "$host_entries"
        echo ""
      else
        warn "No paths saved for $PATH_SUBCMD"
        info "Usage: ./remote.sh path $PATH_SUBCMD /path/to/dir"
      fi
      ;;
  esac
}

cmd_deploy() {
  echo ""
  echo "=== Deploying to $HOST ==="
  echo ""

  init_ssh_socket
  check_prerequisites
  check_ssh_connection
  prepare_remote_base || { cleanup_ssh; return 1; }
  deploy_configs || { abort_remote_deploy; return 1; }
  deploy_linux_optimizations
  deploy_binaries || { abort_remote_deploy; return 1; }
  deploy_shell_environment || { abort_remote_deploy; return 1; }
  finalize_remote_deploy || { abort_remote_deploy; return 1; }

  echo ""
  ok "Deployment complete"
  cleanup_ssh
}

cmd_connect() {
  local selected_path=""

  if [[ $NO_CD -eq 0 ]] && [[ -z "$CD_PATH" ]]; then
    selected_path="$(get_host_path "$HOST")" || selected_path=""
  fi

  if [[ -n "$CD_PATH" ]]; then
    selected_path="$CD_PATH"
    save_host_path "$HOST" "$CD_PATH" 2>/dev/null
  fi

  init_ssh_socket

  echo ""
  echo "=== Deploying to $HOST ==="
  echo ""

  check_prerequisites
  check_ssh_connection
  prepare_remote_base || { cleanup_ssh; return 1; }
  deploy_configs || { abort_remote_deploy; return 1; }
  deploy_linux_optimizations
  deploy_binaries || { abort_remote_deploy; return 1; }
  deploy_shell_environment || { abort_remote_deploy; return 1; }
  finalize_remote_deploy || { abort_remote_deploy; return 1; }

  echo ""
  ok "Deployment complete"

  echo ""
  if [[ -n "$selected_path" ]]; then
    info "Connecting to $HOST (cd $selected_path)..."
  else
    info "Connecting to $HOST..."
  fi

  ssh_cmd 'set -e; umask 077; tmp=$(mktemp ~/.portillo-remote/.connect.XXXXXX); cat > "$tmp"; chmod 0700 "$tmp"; mv -f "$tmp" ~/.portillo-remote/.connect.sh' \
    < "$REMOTE_DIR/connect.sh" \
    || { cleanup_ssh; return 1; }
  local selected_path_arg
  printf -v selected_path_arg '%q' "$selected_path"

  if [[ $CLEANUP -eq 1 ]]; then
    trap 'cleanup_remote_runtime || true; cleanup_ssh' EXIT
  fi

  local connect_rc=0
  ssh_interactive "PORTILLO_NO_TMUX=$NO_TMUX bash ~/.portillo-remote/.connect.sh $selected_path_arg" || connect_rc=$?

  if [[ $CLEANUP -eq 1 ]]; then
    trap - EXIT
    local cleanup_rc=0
    cleanup_remote_runtime || cleanup_rc=$?
    cleanup_ssh
    [[ "$connect_rc" -ne 0 ]] && return "$connect_rc"
    return "$cleanup_rc"
  else
    cleanup_ssh
    return "$connect_rc"
  fi
}

cmd_teardown() {
  init_ssh_socket
  confirm_action "Remove ~/.portillo-remote and restore the previous SSH color config on $HOST?" \
    || { info "Cancelled"; cleanup_ssh; return 0; }
  info "Removing deployment from $HOST..."
  if ! ssh_cmd "bash -s -- teardown" < "$REMOTE_DIR/shell-environment.sh"; then
    error "Could not restore the previous remote shell configuration"
    cleanup_ssh
    return 1
  fi
  if ! ssh_cmd bash -s <<'REMOTE_TEARDOWN_RUNTIME_EOF'
set -euo pipefail
base="$HOME/.portillo-remote"
sentinel='.managed-by-portillo-dots-runtime'
if [[ -e "$base" || -L "$base" ]]; then
  [[ -d "$base" && ! -L "$base" && -O "$base" \
    && -f "$base/$sentinel" && ! -L "$base/$sentinel" \
    && "$(<"$base/$sentinel")" == 'Portillo.Dots remote runtime v1' ]] || exit 1
  rm -rf "$base"
fi
REMOTE_TEARDOWN_RUNTIME_EOF
  then
    error "Could not remove ~/.portillo-remote"
    cleanup_ssh
    return 1
  fi
  ok "Teardown complete"
  cleanup_ssh
}

cmd_status() {
  init_ssh_socket
  info "Checking status on $HOST..."
  echo ""

  local rc=0
  local expected_version
  if ! expected_version="$(bash "$REMOTE_DIR/generate-ls-colors.sh" "$REPO_DIR/zsh/.dircolors" \
    | bash -c 'source /dev/stdin; printf "%s" "$PORTILLO_DIRCOLORS_VERSION"')" \
    || [[ -z "$expected_version" ]]; then
    error "Could not calculate the current dircolors version"
    cleanup_ssh
    return 1
  fi
  ssh_cmd "PORTILLO_EXPECTED_DIRCOLORS_VERSION='$expected_version' bash -s -- status" \
    < "$REMOTE_DIR/shell-environment.sh" || rc=1
  echo ""

  ssh_cmd bash -s <<'STATUS_EOF' || rc=1
RC=0
REMOTE_BASE="$HOME/.portillo-remote"
STATE_DIR="$HOME/.portillo-dots-remote-state"

if [[ -d "$REMOTE_BASE" ]]; then
  echo -e "\033[0;32m✓\033[0m Directory $REMOTE_BASE exists"
else
  echo -e "\033[0;33m⚠\033[0m $REMOTE_BASE absent (expected after --cleanup)"
fi

if [[ -d "$REMOTE_BASE" ]]; then
  for bin in nvim rg fd fzf lazygit node npm stylua; do
    if [[ -x "$REMOTE_BASE/bin/$bin" ]]; then
      echo -e "\033[0;32m✓\033[0m $bin"
    elif command -v "$bin" &>/dev/null; then
      echo -e "\033[0;32m✓\033[0m $bin (system)"
    else
      echo -e "\033[0;31m✗\033[0m $bin"
      RC=1
    fi
  done

  if [[ -x "$REMOTE_BASE/bin/cc" ]] || command -v gcc &>/dev/null || command -v clang &>/dev/null; then
    echo -e "\033[0;32m✓\033[0m C compiler (for treesitter)"
  else
    echo -e "\033[0;33m⚠\033[0m C compiler not found"
  fi

  if command -v git &>/dev/null; then
    echo -e "\033[0;32m✓\033[0m git"
  else
    echo -e "\033[0;31m✗\033[0m git (required for LazyVim/TPM plugins: sudo apt install -y git)"
    RC=1
  fi

  if [[ -x "$REMOTE_BASE/bin/tmux" ]] || command -v tmux &>/dev/null; then
    echo -e "\033[0;32m✓\033[0m tmux (optional)"
  else
    echo -e "\033[0;33m⚠\033[0m tmux unavailable; connect will use Bash"
  fi

  if [[ -f "$REMOTE_BASE/.remote-bashrc" ]] && bash -n "$REMOTE_BASE/.remote-bashrc"; then
    echo -e "\033[0;32m✓\033[0m transient .remote-bashrc"
  else
    echo -e "\033[0;31m✗\033[0m transient .remote-bashrc"
    RC=1
  fi

  if [[ -f "$STATE_DIR/tmux-remote.conf" ]]; then
    echo -e "\033[0;32m✓\033[0m persistent tmux-remote.conf"
  else
    echo -e "\033[0;31m✗\033[0m persistent tmux-remote.conf"
    RC=1
  fi
fi

tmux_bin=""
if [[ -x "$REMOTE_BASE/bin/tmux" ]]; then
  tmux_bin="$REMOTE_BASE/bin/tmux"
elif [[ -x "$HOME/.local/bin/tmux" ]]; then
  tmux_bin="$HOME/.local/bin/tmux"
elif command -v tmux &>/dev/null; then
  tmux_bin="$(command -v tmux)"
fi

if [[ -n "$tmux_bin" ]] && "$tmux_bin" -L portillo-dots list-sessions &>/dev/null; then
  session_id="$("$tmux_bin" -L portillo-dots \
    list-sessions -f '#{==:#{session_name},portillo}' -F '#{session_id}' \
    | command head -n 1)"
  if [[ -z "$session_id" ]]; then
    echo -e "\033[0;33m⚠\033[0m dedicated tmux server has no exact 'portillo' session"
    exit $RC
  fi

  default_command="$("$tmux_bin" -L portillo-dots show-options -v -t "$session_id" default-command 2>/dev/null || true)"
  bash_bin="$(command -v bash)"
  printf -v expected_command 'exec %q --rcfile %q -i' "$bash_bin" "$STATE_DIR/bashrc"
  expected_version="$(bash -c 'source "$1"; printf "%s" "$PORTILLO_DIRCOLORS_VERSION"' _ \
    "$STATE_DIR/ls-colors.sh" 2>/dev/null || true)"
  tmux_version="$("$tmux_bin" -L portillo-dots show-environment -g PORTILLO_DIRCOLORS_VERSION 2>/dev/null || true)"
  tmux_version="${tmux_version#PORTILLO_DIRCOLORS_VERSION=}"
  expected_shell_version="$(bash -c 'source "$1"; printf "%s" "$PORTILLO_SHELL_ENV_VERSION"' _ \
    "$STATE_DIR/shell-version.sh" 2>/dev/null || true)"
  tmux_shell_version="$("$tmux_bin" -L portillo-dots show-environment -g PORTILLO_SHELL_ENV_VERSION 2>/dev/null || true)"
  tmux_shell_version="${tmux_shell_version#PORTILLO_SHELL_ENV_VERSION=}"
  expected_conf_version="$(cksum "$STATE_DIR/tmux-remote.conf" | awk '{ print $1 "-" $2 }')"
  tmux_conf_version="$("$tmux_bin" -L portillo-dots show-environment -g PORTILLO_TMUX_CONFIG_VERSION 2>/dev/null || true)"
  tmux_conf_version="${tmux_conf_version#PORTILLO_TMUX_CONFIG_VERSION=}"
  managed_window="$("$tmux_bin" -L portillo-dots list-windows -t "$session_id" -F '#{@portillo_dircolors_version}' 2>/dev/null \
    | grep -Fx "$expected_shell_version" || true)"

  if [[ "$default_command" == "$expected_command" ]] \
    && [[ -n "$expected_version" ]] \
    && [[ "$tmux_version" == "$expected_version" ]] \
    && [[ -n "$expected_shell_version" ]] \
    && [[ "$tmux_shell_version" == "$expected_shell_version" ]] \
    && [[ "$tmux_conf_version" == "$expected_conf_version" ]] \
    && [[ -n "$managed_window" ]]; then
    echo -e "\033[0;32m✓\033[0m dedicated tmux session 'portillo' uses the current color map"
  else
    echo -e "\033[0;31m✗\033[0m dedicated tmux session 'portillo' needs reconnecting"
    RC=1
  fi
else
  echo -e "\033[0;33m⚠\033[0m no dedicated Portillo.Dots tmux server"
fi

exit $RC
STATUS_EOF
  cleanup_ssh
  return "$rc"
}

parse_args "$@"

case "$COMMAND" in
  deploy)   cmd_deploy ;;
  connect)  cmd_connect ;;
  teardown) cmd_teardown ;;
  status)   cmd_status ;;
  path)     cmd_path ;;
  help)     usage ;;
  *)        error "Unknown command: $COMMAND"; usage; exit 1 ;;
esac
