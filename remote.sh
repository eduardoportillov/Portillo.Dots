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
VERBOSE=0
FORCE=0
SKIP_BINS=0
CLEANUP=1
NO_CD=0
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
  connect             Deploy + connect via SSH (with tmux)
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
  local ssh_args="ssh -o ConnectTimeout=10 -o ControlMaster=auto -o ControlPath=$SSH_SOCKET -o ControlPersist=10m"
  [[ -n "$SSH_PORT" ]] && ssh_args+=" -p $SSH_PORT"
  [[ -n "$SSH_IDENTITY" ]] && ssh_args+=" -i $SSH_IDENTITY"
  local args=(rsync -az)
  [[ "$VERBOSE" -eq 1 ]] && args+=(-v)
  args+=(-e "$ssh_args" "$@")
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
}

cleanup_ssh() {
  if [[ -n "$SSH_SOCKET" ]]; then
    ssh -o ControlPath="$SSH_SOCKET" -O exit "$HOST" 2>/dev/null || true
    rm -rf "$(dirname "$SSH_SOCKET")" 2>/dev/null || true
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

deploy_configs() {
  info "Syncing dotfiles to $HOST..."
  rsync_cmd \
    --delete \
    --exclude='.git' \
    --exclude='.backup' \
    --exclude='setup.sh' \
    --exclude='alacritty/' \
    --exclude='remote/' \
    --exclude='remote.sh' \
    --exclude='README.md' \
    --exclude='nvim/db_ui/connections.lua' \
    "$REPO_DIR/" \
    "$HOST:~/.portillo-remote/"
  ok "Dotfiles synced"
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

deploy_bashrc() {
  info "Generating remote bashrc..."
  local rc_content
  rc_content="$(bash "$REMOTE_DIR/generate-rc.sh")"
  if [[ -z "$rc_content" ]]; then
    error "Failed to generate bashrc"
    return 1
  fi

  echo "$rc_content" | ssh_cmd "cat > ~/.portillo-remote/.remote-bashrc"
  ok "Remote bashrc deployed"
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

  # tmux
  info "tmux..."
  if [[ ! -f "$dl_dir/tmux" ]] && [[ ! -f "$dl_dir/tmux.tar.gz" ]]; then
    local tag
    tag="$(get_remote_version "tmux/tmux")"
    local tmux_url
    case "$arch" in
      x86_64)  tmux_url="https://github.com/tmux/tmux/releases/latest/download/tmux-x86_64" ;;
      aarch64) tmux_url="https://github.com/tmux/tmux/releases/latest/download/tmux-arm64" ;;
      armv7l)  tmux_url="https://github.com/tmux/tmux/releases/latest/download/tmux-armv7" ;;
    esac
    info "Downloading tmux..."
    if curl -fSL --connect-timeout 15 --max-time 120 -o "$dl_dir/tmux-dl" "$tmux_url" 2>/dev/null; then
      mv "$dl_dir/tmux-dl" "$dl_dir/tmux"
      ok "tmux downloaded"
    else
      rm -f "$dl_dir/tmux-dl"
      if [[ -n "$tag" ]]; then
        warn "Static binary not found, trying tarball..."
        local tmux_tgz_url="https://github.com/tmux/tmux/releases/download/v${tag}/tmux-v${tag}-x86_64.tar.gz"
        if curl -fSL --connect-timeout 15 --max-time 120 -o "$dl_dir/tmux.tar.gz" "$tmux_tgz_url" 2>/dev/null; then
          ok "tmux tarball downloaded"
        else
          warn "Failed to download tmux"
          rm -f "$dl_dir/tmux.tar.gz"
        fi
      else
        warn "Failed to download tmux"
      fi
    fi
  else
    ok "tmux (cached)"
  fi

  # ripgrep
  info "ripgrep..."
  if [[ ! -f "$dl_dir/rg.tar.gz" ]]; then
    local rg_arch
    case "$arch" in
      x86_64)  rg_arch="x86_64-unknown-linux-musl" ;;
      aarch64) rg_arch="aarch64-unknown-linux-musl" ;;
      armv7l)  rg_arch="arm-unknown-linux-gnueabihf" ;;
    esac
    info "Downloading ripgrep..."
    if curl -fSL --connect-timeout 15 --max-time 120 -o "$dl_dir/rg.tar.gz" \
      "https://github.com/BurntSushi/ripgrep/releases/latest/download/rg-${rg_arch}.tar.gz" 2>/dev/null; then
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
    local fd_arch
    case "$arch" in
      x86_64)  fd_arch="x86_64-unknown-linux-musl" ;;
      aarch64) fd_arch="aarch64-unknown-linux-musl" ;;
      armv7l)  fd_arch="arm-unknown-linux-gnueabihf" ;;
    esac
    info "Downloading fd..."
    if curl -fSL --connect-timeout 15 --max-time 120 -o "$dl_dir/fd.tar.gz" \
      "https://github.com/sharkdp/fd/releases/latest/download/fd-${fd_arch}.tar.gz" 2>/dev/null; then
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
    local lg_suffix
    case "$arch" in
      x86_64)  lg_suffix="x86_64" ;;
      aarch64) lg_suffix="arm64" ;;
      armv7l)  lg_suffix="armv7" ;;
    esac
    info "Downloading lazygit..."
    if curl -fSL --connect-timeout 15 --max-time 120 -o "$dl_dir/lazygit.tar.gz" \
      "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${lg_suffix}.tar.gz" 2>/dev/null; then
      ok "lazygit downloaded"
    else
      warn "Failed to download lazygit"
      rm -f "$dl_dir/lazygit.tar.gz"
    fi
  else
    ok "lazygit (cached)"
  fi
}

deploy_binaries() {
  if [[ $SKIP_BINS -eq 1 ]]; then
    info "Skipping binary installation (--skip-bins)"
    return 0
  fi

  local LOCAL_CACHE
  LOCAL_CACHE="$(mktemp -d)"

  info "Downloading binaries locally..."
  download_binaries_locally "$LOCAL_CACHE"

  info "Transferring binaries to $HOST..."
  rsync_cmd "$LOCAL_CACHE/" "$HOST:~/.portillo-remote/downloads/"

  info "Installing binaries on remote host..."
  cat "$REMOTE_DIR/lib.sh" "$REMOTE_DIR/install-binaries.sh" | ssh_cmd "bash -s"

  rm -rf "$LOCAL_CACHE"
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
  deploy_configs
  deploy_linux_optimizations
  deploy_bashrc
  deploy_binaries

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
  deploy_configs
  deploy_linux_optimizations
  deploy_bashrc
  deploy_binaries

  echo ""
  ok "Deployment complete"

  local cleanup_handler=""
  if [[ $CLEANUP -eq 1 ]]; then
    cleanup_handler="echo ''; info 'Cleaning up remote...'; ssh -o ControlPath='$SSH_SOCKET' -o ControlPersist=10m '$HOST' 'rm -rf ~/.portillo-remote' 2>/dev/null; ok 'Remote cleaned up'; cleanup_ssh;"
  fi

  echo ""
  if [[ -n "$selected_path" ]]; then
    info "Connecting to $HOST (cd $selected_path)..."
  else
    info "Connecting to $HOST..."
  fi

  local cd_line=""
  if [[ -n "$selected_path" ]]; then
    cd_line="cd \"$selected_path\""
  fi

  local connect_script
  connect_script=$(cat <<CONNECT_EOF
#!/usr/bin/env bash
export PATH="\$HOME/.portillo-remote/bin:\$HOME/.local/bin:\$PATH"
export NVIM_APPNAME="portillo-remote/nvim"
$cd_line
if command -v tmux &>/dev/null; then
  if [[ -f "\$HOME/.portillo-remote/tmux-remote.conf" ]]; then
    exec tmux -f "\$HOME/.portillo-remote/tmux-remote.conf" new-session -A -s portillo
  else
    exec tmux new-session -A -s portillo
  fi
else
  exec bash --rcfile "\$HOME/.portillo-remote/.remote-bashrc" -i
fi
CONNECT_EOF
)

  echo "$connect_script" | ssh_cmd "cat > ~/.portillo-remote/.connect.sh && chmod +x ~/.portillo-remote/.connect.sh"

  if [[ $CLEANUP -eq 1 ]]; then
    trap 'eval "$cleanup_handler"' EXIT
  fi

  ssh_interactive "bash ~/.portillo-remote/.connect.sh"

  if [[ $CLEANUP -eq 1 ]]; then
    trap - EXIT
    eval "$cleanup_handler"
  else
    cleanup_ssh
  fi
}

cmd_teardown() {
  init_ssh_socket
  confirm_action "Remove ~/.portillo-remote from $HOST?" || { info "Cancelled"; cleanup_ssh; return 0; }
  info "Removing deployment from $HOST..."
  ssh_cmd "rm -rf ~/.portillo-remote"
  ok "Teardown complete"
  cleanup_ssh
}

cmd_status() {
  init_ssh_socket
  info "Checking status on $HOST..."
  echo ""

  ssh_cmd bash -s <<'STATUS_EOF'
RC=0
REMOTE_BASE="$HOME/.portillo-remote"

if [[ -d "$REMOTE_BASE" ]]; then
  echo -e "\033[0;32m✓\033[0m Directory $REMOTE_BASE exists"
else
  echo -e "\033[0;31m✗\033[0m Directory $REMOTE_BASE missing"
  exit 1
fi

for bin in nvim tmux rg fd fzf lazygit; do
  if [[ -x "$REMOTE_BASE/bin/$bin" ]]; then
    echo -e "\033[0;32m✓\033[0m $bin"
  elif command -v "$bin" &>/dev/null; then
    echo -e "\033[0;32m✓\033[0m $bin (system)"
  else
    echo -e "\033[0;31m✗\033[0m $bin"
    RC=1
  fi
done

if [[ -f "$REMOTE_BASE/.remote-bashrc" ]]; then
  echo -e "\033[0;32m✓\033[0m .remote-bashrc"
else
  echo -e "\033[0;31m✗\033[0m .remote-bashrc"
  RC=1
fi

if [[ -f "$REMOTE_BASE/tmux-remote.conf" ]]; then
  echo -e "\033[0;32m✓\033[0m tmux-remote.conf"
else
  echo -e "\033[0;33m⚠\033[0m tmux-remote.conf (optional)"
fi

if command -v tmux &>/dev/null && tmux has-session -t portillo 2>/dev/null; then
  echo -e "\033[0;32m✓\033[0m tmux session 'portillo' active"
else
  echo -e "\033[0;33m⚠\033[0m no tmux session 'portillo'"
fi

exit $RC
STATUS_EOF
  cleanup_ssh
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
