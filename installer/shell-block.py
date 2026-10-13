#!/usr/bin/env python3
"""Install one managed shell block without replacing unrelated shell settings."""
import os
from pathlib import Path
import shutil
import sys
import tempfile

START = '# >>> Portillo.Dots Remote Server >>>'
END = '# <<< Portillo.Dots Remote Server <<<'
BLOCK = START + '\n' + '. "${XDG_CONFIG_HOME:-$HOME/.config}/portillo-dots/server.sh"\n' + END + '\n'


def install(rc, backups):
    if rc.is_symlink() or (rc.exists() and not rc.is_file()):
        raise ValueError('Shell config must be a regular file')
    original = rc.read_text() if rc.exists() else ''
    lines = original.splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if line.rstrip('\r\n') == START]
    ends = [i for i, line in enumerate(lines) if line.rstrip('\r\n') == END]
    if starts or ends:
        if len(starts) != 1 or len(ends) != 1 or starts[0] >= ends[0]:
            raise ValueError('Malformed managed shell block; refusing to edit')
        text = ''.join(lines[:starts[0]]) + BLOCK + ''.join(lines[ends[0] + 1:])
    else:
        text = original + ('\n' if original and not original.endswith('\n') else '') + BLOCK
    if text == original:
        return
    if rc.exists():
        backup = backups / str(rc).lstrip('/')
        backup.parent.mkdir(parents=True, exist_ok=True)
        if backup.exists():
            raise ValueError('Backup collision')
        shutil.copy2(rc, backup)
    rc.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.portillo-shell-', dir=rc.parent)
    try:
        with os.fdopen(fd, 'w') as output:
            output.write(text)
        os.chmod(name, (rc.stat().st_mode & 0o777) if rc.exists() else 0o600)
        os.replace(name, rc)
    finally:
        if os.path.exists(name):
            os.unlink(name)


if __name__ == '__main__':
    try:
        install(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, ValueError) as error:
        sys.exit(f'Shell integration failed: {error}')
