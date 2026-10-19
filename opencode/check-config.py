#!/usr/bin/env python3
"""Check an installed OpenCode config: Server baseline, no baked secrets, V2 notes.

Unlike the renderer, this inspects a config that may legitimately use V1 syntax
(OpenCode still normalises it at runtime), so legacy shapes are reported as
notes rather than treated as fatal. What must never pass is a missing Server
baseline or a generated file carrying credential values.
"""
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
from importlib.util import module_from_spec, spec_from_file_location

spec = spec_from_file_location('renderer', Path(__file__).with_name('render-config.py'))
renderer = module_from_spec(spec)
spec.loader.exec_module(renderer)


def plugin_packages(config):
    """Return normalised package names from native `plugins` entries."""
    names = []
    for entry in config.get('plugins') or []:
        raw = entry if isinstance(entry, str) else entry.get('package') if isinstance(entry, dict) else None
        if not isinstance(raw, str):
            continue
        name = raw.rsplit('@', 1)[0] if raw.count('@') > 1 or not raw.startswith('@') \
            else raw.rsplit('@', 1)[0] if '@' in raw[1:] else raw
        if raw.startswith('@') and '@' in raw[1:]:
            name = raw[:raw.index('@', 1)]
        names.append(name)
    return names


def plugin_compatibility_notes(config):
    """Flag configured plugins whose packages are known V1-only."""
    try:
        table = renderer.load_jsonc(Path(__file__).with_name('plugin-compat.json').read_text())
    except (OSError, ValueError):
        return []
    packages = table.get('packages', {})
    notes = []
    for name in plugin_packages(config):
        entry = packages.get(name)
        if entry and entry.get('v2') is False:
            notes.append(f'plugin "{name}" is V1-only and will not run in V2: {entry.get("reason", "")}')
    return notes


def legacy_notes(config):
    """Describe V1 shapes worth migrating. Informational: they still run."""
    notes = []
    for legacy, native in renderer.LEGACY_TOP_LEVEL.items():
        if legacy in config:
            notes.append(f'legacy V1 key "{legacy}" (native form is "{native}")')
    for name, agent in (config.get('agents') or config.get('agent') or {}).items() if isinstance(
            config.get('agents') or config.get('agent'), dict) else []:
        for legacy in renderer.LEGACY_AGENT_FIELDS:
            if isinstance(agent, dict) and legacy in agent:
                notes.append(f'agent "{name}" uses legacy "{legacy}"')
    mcp = config.get('mcp')
    if isinstance(mcp, dict) and 'servers' not in mcp:
        notes.append('MCP servers are declared in the legacy flat form')
    return notes


def permission_rules(config):
    """Return (action, resource, effect) rules from native or legacy syntax."""
    rules = []
    native = config.get('permissions')
    if isinstance(native, list):
        for rule in native:
            if isinstance(rule, dict) and all(isinstance(rule.get(f), str)
                                              for f in ('action', 'resource', 'effect')):
                rules.append((rule['action'], rule['resource'], rule['effect']))
    return rules


def legacy_effect(config, old_name):
    legacy = config.get('permission')
    if not isinstance(legacy, dict):
        return None
    effect = legacy.get(old_name)
    if isinstance(effect, dict):
        effect = effect.get('*')
    return effect


def validate_server_baseline(config):
    rules = permission_rules(config)
    if not isinstance(config.get('permissions', []), list):
        raise ValueError('Malformed permissions configuration')
    for action, old_name in [('shell', 'bash'), ('edit', 'edit')]:
        effect = legacy_effect(config, old_name) or 'allow'
        for rule_action, rule_resource, rule_effect in rules:
            if rule_action in (action, '*') and rule_resource == '*':
                effect = rule_effect
        if effect not in ('ask', 'deny'):
            raise ValueError(f'Server global policy needs {action}: * -> ask/deny; merge server.jsonc manually')


def looks_credential_key(key):
    return re.search(r'(?i)(key|secret|token|auth|password|credential)', key) is not None


def looks_credential_value(value):
    """A long, dense, non-URL string is treated as a credential regardless of key."""
    if value.startswith('{env:'):
        return False
    if value.startswith(('http://', 'https://')):
        return False
    return len(value) >= 24 and ' ' not in value


def validate_no_baked_secrets(config, template=False):
    if not template:
        return
    mcp = config.get('mcp', {}).get('servers', {})
    if not isinstance(mcp, dict):
        return
    for name, server in mcp.items():
        if not isinstance(server, dict):
            continue
        for section in ('environment', 'headers'):
            values = server.get(section)
            if not isinstance(values, dict):
                continue
            for key, value in values.items():
                if not isinstance(value, str) or not value or value.startswith('{env:'):
                    continue
                if looks_credential_key(key) or looks_credential_value(value):
                    raise ValueError(
                        f'MCP server "{name}" {section}.{key} stores a literal credential; '
                        'use {env:NAME} so secrets stay out of the generated file')


def validate(config, profile, template=False):
    if not isinstance(config, dict):
        raise ValueError('OpenCode config must be an object')
    native = config.get('permissions')
    if native is not None and not isinstance(native, list):
        raise ValueError('Malformed permissions configuration')
    for rule in permission_rules(config):
        if rule[2] not in ('allow', 'ask', 'deny'):
            raise ValueError('Malformed native permission rule')
    validate_no_baked_secrets(config, template=template)
    if profile == 'server':
        validate_server_baseline(config)


def local_mcp_commands(config):
    """Executable names the configured local MCP servers expect on PATH."""
    commands = []
    servers = (config.get('mcp') or {}).get('servers')
    if not isinstance(servers, dict):
        return commands
    for server in servers.values():
        if not isinstance(server, dict) or server.get('type') != 'local':
            continue
        command = server.get('command')
        if isinstance(command, list) and command and isinstance(command[0], str):
            commands.append(command[0])
    return commands


def missing_commands(config):
    import shutil as _shutil
    return [c for c in local_mcp_commands(config) if _shutil.which(c) is None]


if __name__ == '__main__':
    argv = sys.argv[1:]
    check_deps = False
    if '--deps' in argv:
        check_deps = True
        argv = [a for a in argv if a != '--deps']
    if len(argv) not in (2, 3) or argv[1] not in ('server', 'workstation'):
        sys.exit('Usage: check-config.py CONFIG server|workstation [--template] [--deps]')
    is_template = len(argv) == 3 and argv[2] == '--template'
    try:
        parsed = renderer.load_jsonc(Path(argv[0]).read_text())
    except (OSError, ValueError):
        sys.exit('OpenCode config check failed: invalid JSONC. Content is not echoed because it may hold credentials.')
    for note in legacy_notes(parsed):
        print(f'Note: {note}', file=sys.stderr)
    incompatibility = plugin_compatibility_notes(parsed)
    for note in incompatibility:
        print(f'Note: {note}', file=sys.stderr)
    if is_template and incompatibility:
        sys.exit('OpenCode config check failed: the template lists V1-only plugins that cannot run in V2. '
                 'Remove them or replace them with V2 ports.')
    try:
        validate(parsed, argv[1], template=is_template)
    except ValueError:
        sys.exit('OpenCode config check failed: malformed rules, literal secrets, or a missing '
                 'conservative Server shell/edit policy. Independent config preserved; '
                 'merge opencode/server.jsonc manually.')
    if check_deps:
        missing = missing_commands(parsed)
        if missing:
            print('MCP servers need commands not on PATH: ' + ' '.join(missing)
                  + ' (install them or disable those servers)', file=sys.stderr)
            sys.exit(3)
