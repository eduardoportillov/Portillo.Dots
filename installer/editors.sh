#!/usr/bin/env bash

# Shared editor payload: changing profiles must not downgrade the editor.
configure_nvim() {
  prepare_config_directory "$CONFIG_HOME/nvim"
  local file
  for file in init.lua lua lazy-lock.json lazyvim.json stylua.toml .gitignore .neoconf.json db_ui; do
    symlink_file "$REPO_DIR/nvim/$file" "$CONFIG_HOME/nvim/$file"
  done
  symlink_file "$REPO_DIR/.markdownlint.jsonc" "$HOME/.markdownlint.jsonc"
}

run_managed_nvim() {
  # Ignore an inherited remote NVIM_APPNAME and use this setup's XDG paths.
  # Bound the process on macOS too, where GNU timeout is not available.
  local mode="$1"
  python3 - "$mode" "$CONFIG_HOME" "$REPO_DIR/installer/nvim-health.lua" <<'PY'
import os
import subprocess
import sys
import tempfile
import shutil
import hashlib
import json
from pathlib import Path

mode, config, health = sys.argv[1:]
env = dict(os.environ, XDG_CONFIG_HOME=config, NVIM_APPNAME='nvim',
           PORTILLO_NVIM_SETUP='1', PORTILLO_NVIM_HEALTH=health)
env['PORTILLO_NVIM_CHECK'] = '1' if mode == 'check' else '0'
state = Path(env.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'portillo-dots/nvim-identity.json'
def fingerprint():
    root = Path(config) / 'nvim'
    paths = [root / name for name in ('init.lua', 'lazy-lock.json', 'lazyvim.json', 'stylua.toml', '.neoconf.json')]
    paths += sorted((root / 'lua').rglob('*.lua'))
    paths += [Path(config) / 'portillo-dots/nvim-base.lua']
    hashes = {}
    for path in paths:
        data = path.read_bytes()
        if path.name == 'lazyvim.json':
            metadata = json.loads(data)
            # Read-news/install bookkeeping is host-local, not config drift.
            data = json.dumps({key: metadata.get(key) for key in ('extras', 'version')}, sort_keys=True).encode()
        hashes[str(path.relative_to(Path(config)))] = hashlib.sha256(data).hexdigest()
    return hashes
try:
    # lazy.nvim rewrites its lockfile even during restore. Never let provisioning
    # mutate the tracked lockfile through the managed config symlink.
    preferred = '/tmp/opencode' if os.path.isdir('/tmp/opencode') and os.access('/tmp/opencode', os.W_OK) else None
    with tempfile.TemporaryDirectory(prefix='portillo-nvim-', dir=preferred) as work:
        lock = os.path.join(work, 'lazy-lock.json')
        shutil.copyfile(os.path.join(config, 'nvim', 'lazy-lock.json'), lock)
        env['PORTILLO_NVIM_LOCKFILE'] = lock
        metadata = os.path.join(work, 'lazyvim.json')
        shutil.copyfile(os.path.join(config, 'nvim', 'lazyvim.json'), metadata)
        env['PORTILLO_NVIM_JSON'] = metadata
        receipt = Path(work) / 'identity.json'
        env['PORTILLO_NVIM_RECEIPT'] = str(receipt)
        args = ['nvim', '--headless', '-i', 'NONE', '-n']
        if mode == 'install':
            state.unlink(missing_ok=True)
            args += ['+Lazy! restore']
        else:
            saved = json.loads(state.read_text())
            if saved['config'] != fingerprint():
                raise ValueError('Editor configuration changed since provisioning; rerun normal setup')
            receipt.write_text(json.dumps(saved))
            env['XDG_STATE_HOME'] = os.path.join(work, 'state')
            env['XDG_CACHE_HOME'] = os.path.join(work, 'cache')
            # Do not execute user init or plugin startup hooks during --check.
            args += ['-u', 'NONE']
        args += ['+lua dofile(vim.env.PORTILLO_NVIM_HEALTH)', '+qa!']
        result = subprocess.run(args, env=env, timeout=900 if mode == 'install' else 60)
        if mode == 'install' and result.returncode == 0:
            saved = json.loads(receipt.read_text())
            saved['config'] = fingerprint()
            state.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(mode='w', dir=state.parent, delete=False) as out:
                json.dump(saved, out)
            os.replace(out.name, state)
    sys.exit(result.returncode)
except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
    print(f'Neovim {mode} failed: {error}', file=sys.stderr)
    sys.exit(1)
PY
}

provision_nvim() {
  local installed
  installed="$(tool_version nvim)" || die 'Cannot detect Neovim version'
  version_at_least "$installed" 0.11.2 || die 'Shared LazyVim requires Neovim >=0.11.2; update Neovim and rerun setup'
  if run_managed_nvim check >>"$LOG" 2>&1; then
    info 'Shared Neovim plugins/theme already match the configuration and lockfile'
    return 0
  fi
  info 'Restoring shared Neovim plugins from lazy-lock.json (both profiles)'
  run_managed_nvim install >>"$LOG" 2>&1 \
    || die "Neovim plugin provisioning failed; see $LOG"
}

verify_terminal_identity() {
  local failed=0 plugin
  for plugin in tpm tmux-sensible tmux-yank vim-tmux-navigator tmux-which-key extrakto tmux-kanagawa; do
    if [[ ! -d "$HOME/.tmux/plugins/$plugin/.git" ]]; then
      warn "Missing shared tmux plugin: $plugin"
      record_event failed "missing tmux plugin: $plugin"
      failed=1
    fi
  done
  if ! run_managed_nvim check; then
    warn 'Neovim identity check failed: rerun setup without --config-only to restore plugins'
    record_event failed 'Neovim plugins/theme failed runtime verification'
    failed=1
  fi
  return "$failed"
}
