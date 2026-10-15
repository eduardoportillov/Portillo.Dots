#!/usr/bin/env python3
"""Check local JSONC and explicit global defaults, not merged runtime policy."""
import sys
from pathlib import Path

sys.dont_write_bytecode = True
from importlib.util import module_from_spec, spec_from_file_location

spec = spec_from_file_location('renderer', Path(__file__).with_name('render-config.py'))
renderer = module_from_spec(spec)
spec.loader.exec_module(renderer)


def validate(config, profile):
    if not isinstance(config, dict):
        raise ValueError('OpenCode config must be an object')
    if profile != 'server':
        return
    legacy = config.get('permission', {})
    native = config.get('permissions', [])
    if not isinstance(native, list) or not isinstance(legacy, dict):
        raise ValueError('Malformed permissions configuration')
    for rule in native:
        if (not isinstance(rule, dict)
                or not all(isinstance(rule.get(field), str) for field in ('action', 'resource', 'effect'))
                or rule['effect'] not in ('ask', 'allow', 'deny')):
            raise ValueError('Malformed native permission rule')
    for action, old_name in [('shell', 'bash'), ('edit', 'edit')]:
        effect = legacy.get(old_name, 'allow')
        if isinstance(effect, dict):
            effect = effect.get('*', 'allow')
        for rule in native:
            if rule['action'] in (action, '*') and rule['resource'] == '*':
                effect = rule.get('effect')
        if effect not in ('ask', 'deny'):
            raise ValueError(f'Server global policy needs {action}: * → ask/deny; merge server.jsonc manually')


if __name__ == '__main__':
    if len(sys.argv) != 3 or sys.argv[2] not in ('server', 'workstation'):
        sys.exit('Usage: check-config.py CONFIG server|workstation')
    try:
        validate(renderer.load_jsonc(Path(sys.argv[1]).read_text()), sys.argv[2])
    except (OSError, ValueError):
        # Do not include parse input, which may contain credentials.
        sys.exit('OpenCode config check failed: invalid JSONC or missing conservative Server shell/edit policy. '
                 'Independent config preserved; merge opencode/server.jsonc manually.')
