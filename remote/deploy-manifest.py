#!/usr/bin/env python3
"""Emit a NUL-delimited allowlist of tracked, non-secret runtime files."""
from pathlib import Path
import subprocess
import sys

EXACT = {
    'nvim/init.lua', 'nvim/lazy-lock.json', 'nvim/lazyvim.json',
    'nvim/stylua.toml', 'nvim/.neoconf.json',
    'zsh/.dircolors', '.markdownlint.jsonc', 'server/tmux.conf',
    'shared/shell/common.sh',
}


def manifest(repo):
    repo = repo.resolve()
    result = subprocess.run(['git', '-C', str(repo), 'ls-files', '-z'],
                            check=True, capture_output=True)
    allowed = []
    for raw in result.stdout.split(b'\0'):
        if not raw:
            continue
        name = raw.decode()
        if name not in EXACT and not (name.startswith('nvim/lua/') and name.endswith('.lua')):
            continue
        if Path(name).name == 'connections.lua' or '/db_ui/' in name:
            continue
        path = repo / name
        if path.is_symlink() or not path.is_file() or repo not in path.resolve().parents:
            raise ValueError(f'Unsafe tracked runtime file: {name}')
        allowed.append(name)
    missing = EXACT - set(allowed)
    if missing:
        raise ValueError('Missing tracked runtime files: ' + ', '.join(sorted(missing)))
    return sorted(allowed)


if __name__ == '__main__':
    try:
        files = manifest(Path(sys.argv[1]))
        sys.stdout.buffer.write(b'\0'.join(name.encode() for name in files) + b'\0')
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f'Cannot build safe deployment manifest: {error}')
