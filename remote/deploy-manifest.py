#!/usr/bin/env python3
"""Emit a NUL-delimited allowlist of tracked, non-secret runtime files.

Usage: deploy-manifest.py REPO [workstation|server]

Both runtime profiles carry the same LazyVim tree and shared identity.
"""
from pathlib import Path
import subprocess
import sys

# Always deployed: the shared baseline every host must feel the same with.
BASE = {
    'zsh/.dircolors', '.markdownlint.jsonc',
    'shared/shell/common.sh', 'shared/tmux/base.conf', 'shared/tmux/visual.conf',
    'shared/tmux/visual-enabled', 'shared/nvim/base.lua',
}

# LazyVim editor tree, shared by both runtime profiles.
LAZYVIM = {
    'nvim/init.lua', 'nvim/lazy-lock.json', 'nvim/lazyvim.json',
    'nvim/stylua.toml', 'nvim/.neoconf.json',
}


def manifest(repo, profile='workstation'):
    repo = repo.resolve()
    if profile not in ('workstation', 'server'):
        raise ValueError(f'Unknown runtime profile: {profile}')
    result = subprocess.run(['git', '-C', str(repo), 'ls-files', '-z'],
                            check=True, capture_output=True)
    exact = BASE | LAZYVIM
    allowed = []
    for raw in result.stdout.split(b'\0'):
        if not raw:
            continue
        name = raw.decode()
        lazy_file = name.startswith('nvim/lua/') and name.endswith('.lua')
        if name not in exact and not lazy_file:
            continue
        if Path(name).name == 'connections.lua' or '/db_ui/' in name:
            continue
        path = repo / name
        if path.is_symlink() or not path.is_file() or repo not in path.resolve().parents:
            raise ValueError(f'Unsafe tracked runtime file: {name}')
        allowed.append(name)
    missing = exact - set(allowed)
    if missing:
        raise ValueError('Missing tracked runtime files: ' + ', '.join(sorted(missing)))
    return allowed


if __name__ == '__main__':
    try:
        profile = sys.argv[2] if len(sys.argv) > 2 else 'workstation'
        files = manifest(Path(sys.argv[1]), profile)
        sys.stdout.buffer.write(b'\0'.join(name.encode() for name in files) + b'\0')
    except (IndexError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f'Cannot build safe deployment manifest: {error}')
