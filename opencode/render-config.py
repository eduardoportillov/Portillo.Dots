#!/usr/bin/env python3
"""Render OpenCode configuration without executing or logging dotenv values."""
import argparse
import json
import os
from pathlib import Path
import re
import tempfile


def load_jsonc(text):
    # Remove comments and trailing commas only outside quoted strings.
    tokens = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/')
    text = tokens.sub(lambda m: m[0] if m[0].startswith('"') else ' ', text)
    commas = re.compile(r'"(?:\\.|[^"\\])*"|,(?=\s*[}\]])')
    return json.loads(commas.sub(lambda m: m[0] if m[0].startswith('"') else '', text))


def read_env(path):
    values = {}
    for number, line in enumerate(path.read_text().splitlines(), 1):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        match = re.fullmatch(r'(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)', line)
        if not match:
            raise ValueError(f'Invalid dotenv assignment on line {number}')
        key, value = match.groups()
        value = value.strip()
        if value.startswith(('"', "'")):
            if len(value) < 2 or value[-1] != value[0]:
                raise ValueError(f'Unclosed dotenv quote on line {number}')
            value = value[1:-1]
        values[key] = value
    return values


def render(value, values):
    if isinstance(value, dict):
        return {k: render(v, values) for k, v in value.items()}
    if isinstance(value, list):
        return [render(v, values) for v in value]
    if isinstance(value, str):
        def substitute(match):
            key = match[1]
            if not values.get(key):
                raise ValueError(f'Missing required variable: {key}')
            return values[key]
        return re.sub(r'\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}', substitute, value)
    return value


# Legacy V1 keys that must not reach a V2 server. Keeping them would make the
# configuration look complete while silently dropping the settings.
LEGACY_TOP_LEVEL = {
    'agent': 'agents', 'permission': 'permissions', 'plugin': 'plugins',
    'mode': 'agents', 'snapshot': 'snapshots', 'attachment': 'media',
    'command': 'commands', 'reference': 'references', 'provider': 'providers',
}
LEGACY_AGENT_FIELDS = {'prompt': 'system', 'permission': 'permissions',
                       'disable': 'disabled', 'maxSteps': 'steps', 'tools': None}


def validate_v2(config):
    """Fail closed on V1-only shapes so they are migrated, not silently ignored."""
    if not isinstance(config, dict):
        raise ValueError('OpenCode config must be an object')
    for legacy, native in LEGACY_TOP_LEVEL.items():
        if legacy in config:
            hint = f'use "{native}"' if native else 'remove it'
            raise ValueError(f'Legacy V1 key "{legacy}"; {hint}')
    mcp = config.get('mcp')
    if mcp is not None:
        if not isinstance(mcp, dict) or not isinstance(mcp.get('servers'), dict):
            raise ValueError('MCP servers must be nested under "mcp.servers"')
        for name, server in mcp['servers'].items():
            if not isinstance(server, dict):
                raise ValueError(f'MCP server "{name}" must be an object')
            if 'enabled' in server:
                raise ValueError(f'MCP server "{name}" uses legacy "enabled"; use "disabled"')
            if server.get('type') not in ('local', 'remote'):
                raise ValueError(f'MCP server "{name}" needs type local|remote')
            if server.get('type') == 'remote' and not isinstance(server.get('url'), str):
                raise ValueError(f'Remote MCP server "{name}" needs an absolute url')
            if server.get('type') == 'local' and not isinstance(server.get('command'), list):
                raise ValueError(f'Local MCP server "{name}" needs a command array')
    agents = config.get('agents')
    if agents is not None:
        if not isinstance(agents, dict):
            raise ValueError('"agents" must be an object')
        for name, agent in agents.items():
            if not isinstance(agent, dict):
                raise ValueError(f'Agent "{name}" must be an object')
            for legacy, native in LEGACY_AGENT_FIELDS.items():
                if legacy in agent:
                    hint = f'use "{native}"' if native else 'use permissions instead'
                    raise ValueError(f'Agent "{name}" uses legacy "{legacy}"; {hint}')
    plugins = config.get('plugins')
    if plugins is not None:
        if not isinstance(plugins, list):
            raise ValueError('"plugins" must be an array')
        for entry in plugins:
            if not isinstance(entry, str) and not (isinstance(entry, dict) and isinstance(entry.get('package'), str)):
                raise ValueError('Each plugin must be a package string or {package, options}')
    permissions = config.get('permissions')
    if permissions is not None:
        if not isinstance(permissions, list):
            raise ValueError('"permissions" must be an array')
        for rule in permissions:
            if (not isinstance(rule, dict)
                    or not all(isinstance(rule.get(field), str) for field in ('action', 'resource', 'effect'))
                    or rule['effect'] not in ('allow', 'ask', 'deny')):
                raise ValueError('Malformed native permission rule')
    # A leftover {{VAR}} means a placeholder was never resolved.
    if re.search(r'\{\{[A-Za-z_][A-Za-z0-9_]*\}\}', json.dumps(config)):
        raise ValueError('Unresolved {{VAR}} placeholder in generated configuration')


def main():
    base = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--template', type=Path, default=base / 'opencode.template.jsonc')
    parser.add_argument('--env', type=Path, default=base / '.env')
    parser.add_argument('--output', type=Path, default=base / 'opencode.jsonc')
    parser.add_argument('--overlay', type=Path, action='append', default=[])
    args = parser.parse_args()
    try:
        if args.env.is_symlink() or args.output.is_symlink():
            raise ValueError('Refusing symlinked credential input or generated output')
        config = render(load_jsonc(args.template.read_text()), read_env(args.env) if args.env.exists() else {})
        for overlay in args.overlay:
            extra = load_jsonc(overlay.read_text())
            # Native ordered rules follow the base rules: last matching rule wins.
            rules = config.get('permissions', []) + extra.get('permissions', [])
            config.update(extra)
            config['permissions'] = rules
        validate_v2(config)
        if args.env.exists():
            args.env.chmod(0o600)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix='.opencode-', dir=args.output.parent)
        try:
            with os.fdopen(fd, 'w') as output:
                json.dump(config, output, indent=2)
                output.write('\n')
            os.replace(temporary, args.output)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        print('OpenCode configuration generated (0600); no credential values logged.')
    except (OSError, ValueError) as error:
        # JSON decoder errors can contain input fragments; never echo them.
        message = 'Invalid JSON/JSONC template' if isinstance(error, json.JSONDecodeError) else str(error)
        parser.exit(1, f'Configuration generation failed: {message}\n')


if __name__ == '__main__':
    main()
