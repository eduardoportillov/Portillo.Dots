#!/usr/bin/env python3
"""Merge the repository's Pi compaction policy without replacing other settings."""
import json
import os
from pathlib import Path
import stat
import sys
import tempfile


def merge(target, policy):
    for key, value in policy.items():
        if isinstance(value, dict):
            if key in target and not isinstance(target[key], dict):
                raise ValueError(f'{key} must be an object')
            merge(target.setdefault(key, {}), value)
        else:
            target[key] = value


def main():
    policy = json.loads(Path(sys.argv[1]).read_text())
    destination = Path(sys.argv[2])
    if destination.is_symlink():
        raise ValueError(f'refusing symlinked settings: {destination}')
    if destination.exists():
        metadata = destination.stat()
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid():
            raise ValueError(f'refusing non-regular or unowned settings: {destination}')
        original = destination.read_text()
        settings = json.loads(original)
        mode = stat.S_IMODE(metadata.st_mode)
    else:
        original = None
        settings = {}
        mode = 0o600
    if not isinstance(settings, dict) or not isinstance(policy, dict):
        raise ValueError('settings and policy must be JSON objects')
    before = json.dumps(settings, sort_keys=True)
    # Remove only the global values installed by earlier repository policies.
    # Independently changed values and other model overrides remain untouched.
    compaction = settings.get('compaction')
    if isinstance(compaction, dict):
        if compaction.get('enabled') is True:
            del compaction['enabled']
        if compaction.get('reserveTokens') in (100000, 600000):
            del compaction['reserveTokens']
        if compaction.get('keepRecentTokens') == 20000:
            del compaction['keepRecentTokens']
    merge(settings, {'compaction': policy})
    if original is not None and before == json.dumps(settings, sort_keys=True):
        print('unchanged')
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=destination.parent,
                                         prefix='.settings-', delete=False) as output:
            temporary = Path(output.name)
            os.fchmod(output.fileno(), mode)
            json.dump(settings, output, indent=2, ensure_ascii=False)
            output.write('\n')
        os.replace(temporary, destination)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()
    print('updated')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as error:
        print(f'Pi configuration not changed: {error}', file=sys.stderr)
        sys.exit(1)
