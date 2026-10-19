import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which('bash')

spec = importlib.util.spec_from_file_location('renderer', ROOT / 'opencode/render-config.py')
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)
check_spec = importlib.util.spec_from_file_location('config_check', ROOT / 'opencode/check-config.py')
checker = importlib.util.module_from_spec(check_spec)
check_spec.loader.exec_module(checker)


class TemplateShapeTests(unittest.TestCase):
    def test_template_is_native_v2_with_no_baked_secrets(self):
        config = renderer.load_jsonc((ROOT / 'opencode/opencode.template.jsonc').read_text())
        renderer.validate_v2(config)
        for legacy in renderer.LEGACY_TOP_LEVEL:
            self.assertNotIn(legacy, config)
        self.assertIn('mcp', config)
        self.assertIn('servers', config['mcp'])
        self.assertNotIn('enabled', json.dumps(config['mcp']))
        self.assertIsInstance(config.get('agents'), dict)
        for agent in config['agents'].values():
            for legacy in renderer.LEGACY_AGENT_FIELDS:
                self.assertNotIn(legacy, agent)
        rendered = json.dumps(config)
        self.assertNotIn('{{', rendered, 'no dotenv placeholder may survive into the config')
        for name, server in config['mcp']['servers'].items():
            for section in ('environment', 'headers'):
                for key, value in (server.get(section) or {}).items():
                    if not isinstance(value, str) or not value:
                        continue
                    if checker.looks_credential_key(key) or checker.looks_credential_value(value):
                        self.assertTrue(value.startswith('{env:'),
                                        f'{name}.{section}.{key} must use {{env:NAME}}')
        # Remote header-auth servers must disable OAuth or the key is ignored.
        for name, server in config['mcp']['servers'].items():
            if server.get('type') == 'remote' and server.get('headers'):
                self.assertIs(server.get('oauth'), False,
                              f'{name} uses header credentials so oauth must be false')

    def test_env_substitution_is_deliberately_not_applied_to_env_references(self):
        config = renderer.render({'key': '{env:API_KEY}', 'other': '{{LEGACY}}'},
                                {'API_KEY': 'value', 'LEGACY': 'resolved'})
        self.assertEqual(config['key'], '{env:API_KEY}')
        self.assertEqual(config['other'], 'resolved')

    def test_validate_v2_rejects_legacy_shapes(self):
        bad = [
            {'agent': {}},
            {'permission': {}},
            {'plugin': []},
            {'mcp': {'server': {}}},
            {'mcp': {'servers': {'x': {'type': 'local', 'command': ['x'], 'enabled': True}}}},
            {'mcp': {'servers': {'x': {'type': 'remote'}}}},
            {'mcp': {'servers': {'x': {'type': 'local'}}}},
            {'agents': {'a': {'prompt': 'x'}}},
            {'agents': {'a': {'tools': {}}}},
            {'permissions': [{'action': 'shell'}]},
            {'plugins': [42]},
        ]
        for config in bad:
            with self.subTest(config=config), self.assertRaises(ValueError):
                renderer.validate_v2(config)
        renderer.validate_v2({'mcp': {'servers': {'x': {'type': 'local', 'command': ['x']}}}})

    def test_unresolved_dotenv_placeholder_fails_generation(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            template, env, output = (base / n for n in ('t.jsonc', '.env', 'out.jsonc'))
            template.write_text('{"key":"{{MISSING}}"}')
            env.write_text('')
            result = subprocess.run([sys.executable, '-B', str(ROOT / 'opencode/render-config.py'),
                                     '--template', str(template), '--env', str(env), '--output', str(output)],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())


class PluginCompatTests(unittest.TestCase):
    def test_compat_table_flags_v1_only_plugins(self):
        table = renderer.load_jsonc((ROOT / 'opencode/plugin-compat.json').read_text())
        packages = table['packages']
        self.assertIs(packages['@franlol/opencode-md-table-formatter']['v2'], False)
        self.assertIs(packages['opencode-pty']['v2'], False)
        self.assertIs(packages['@mohak34/opencode-notifier']['v2'], True)

    def test_package_names_are_normalised_from_both_entry_shapes(self):
        config = {'plugins': ['scope/name@1.2.3', {'package': 'plain@^2'}, {'package': '@scope/pkg@3'}]}
        self.assertEqual(checker.plugin_packages(config), ['scope/name', 'plain', '@scope/pkg'])

    def test_v1_only_plugin_fails_template_mode_but_is_a_note_for_independent_configs(self):
        config = {'plugins': ['opencode-pty']}
        notes = checker.plugin_compatibility_notes(config)
        self.assertEqual(len(notes), 1)
        self.assertIn('V1-only', notes[0])
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'opencode.jsonc'
            path.write_text('{"plugins":["opencode-pty"]}')
            strict = subprocess.run([sys.executable, '-B', str(ROOT / 'opencode/check-config.py'),
                                     str(path), 'workstation', '--template'],
                                    capture_output=True, text=True)
            self.assertNotEqual(strict.returncode, 0)
            self.assertIn('V1-only', strict.stderr)
            tolerant = subprocess.run([sys.executable, '-B', str(ROOT / 'opencode/check-config.py'),
                                       str(path), 'workstation'], capture_output=True, text=True)
            self.assertEqual(tolerant.returncode, 0, tolerant.stderr)
            self.assertIn('V1-only', tolerant.stderr)

    def test_template_contains_no_known_v1_only_plugin(self):
        config = renderer.load_jsonc((ROOT / 'opencode/opencode.template.jsonc').read_text())
        table = renderer.load_jsonc((ROOT / 'opencode/plugin-compat.json').read_text())['packages']
        for name in checker.plugin_packages(config):
            entry = table.get(name)
            if entry is not None:
                self.assertIs(entry['v2'], True, f'template ships a V1-only plugin: {name}')


class ClientSeparationTests(unittest.TestCase):
    def test_cli_json_is_client_only_and_secret_free(self):
        config = renderer.load_jsonc((ROOT / 'opencode/cli.json').read_text())
        self.assertIn('$schema', config)
        self.assertIn('opencode.ai/v2/cli.json', config['$schema'])
        text = json.dumps(config).lower()
        for forbidden in ['api_key', 'apikey', 'secret', 'token', 'password', 'authorization']:
            self.assertNotIn(forbidden, text)
        # Server/project settings do not belong in the client file.
        for forbidden in ['permissions', 'mcp', 'agents', 'plugins', 'providers']:
            self.assertNotIn(forbidden, config)

    def test_client_and_server_configs_are_different_files(self):
        self.assertTrue((ROOT / 'opencode/cli.json').is_file())
        self.assertTrue((ROOT / 'opencode/opencode.template.jsonc').is_file())
        self.assertNotEqual((ROOT / 'opencode/cli.json').read_text(),
                            (ROOT / 'opencode/opencode.template.jsonc').read_text())


class SecretsHandlingTests(unittest.TestCase):
    def render_secrets(self, directory, source_text):
        home = Path(directory)
        source = home / '.env'
        source.write_text(source_text)
        source.chmod(0o600)
        destination = home / '.config/opencode/secrets.env'
        script = '''
            source "$1/setup.sh"
            WORK_DIR="$HOME/work"; LOG="$HOME/log"; mkdir -p "$WORK_DIR"
            initialize_state
            trap cleanup_setup EXIT
            install_opencode_secrets "$HOME/.env" "$HOME/.config/opencode/secrets.env"
        '''
        env = {**os.environ, 'HOME': str(home), 'XDG_STATE_HOME': str(home / '.state'),
               'XDG_CONFIG_HOME': str(home / '.config')}
        result = subprocess.run([BASH, '-euc', script, '_', str(ROOT)],
                                env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return destination

    def test_secrets_env_is_0600_and_safe_to_source(self):
        with tempfile.TemporaryDirectory() as directory:
            payload = 'A=plain\nB="quoted value"\nC=$(touch pwned)\nD=`touch pwned2`\n'
            destination = self.render_secrets(directory, payload)
            self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o600)
            check = subprocess.run([BASH, '-c',
                                    f'. "{destination}"; printf "%s\\n" "$A" "$B" "$C" "$D"'],
                                   capture_output=True, text=True, timeout=10)
            self.assertEqual(check.returncode, 0, check.stderr)
            # Command substitutions are data, never executed while sourcing.
            self.assertEqual(check.stdout.splitlines(),
                             ['plain', 'quoted value', '$(touch pwned)', '`touch pwned2`'])
            base = Path(directory)
            self.assertFalse((base / 'pwned').exists())
            self.assertFalse((base / 'pwned2').exists())

    def test_load_secrets_refuses_symlink_bad_owner_and_bad_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = home / '.config/opencode'
            config.mkdir(parents=True)
            real = home / 'real.env'
            real.write_text('export A=real\n')
            real.chmod(0o600)
            target = config / 'secrets.env'
            target.symlink_to(real)
            env = {**os.environ, 'HOME': str(home), 'XDG_CONFIG_HOME': str(home / '.config')}
            run = subprocess.run([BASH, '-c',
                                  f'. "{ROOT}/opencode/load-secrets.sh"; printf "%s" "${{A:-unset}}"'],
                                 env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(run.stdout, 'unset')
            self.assertIn('not a plain file owned by this user', run.stderr)

            target.unlink()
            target.write_text('export A=loose\n')
            target.chmod(0o644)
            run = subprocess.run([BASH, '-c',
                                  f'. "{ROOT}/opencode/load-secrets.sh"; printf "%s" "${{A:-unset}}"'],
                                 env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(run.stdout, 'unset')
            self.assertIn('expected mode 0600', run.stderr)

            target.chmod(0o600)
            run = subprocess.run([BASH, '-c',
                                  f'. "{ROOT}/opencode/load-secrets.sh"; printf "%s" "${{A:-unset}}"'],
                                 env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(run.stdout, 'loose')
            self.assertEqual(run.stderr, '')

    def test_missing_secrets_file_is_silent(self):
        with tempfile.TemporaryDirectory() as directory:
            env = {**os.environ, 'HOME': directory, 'XDG_CONFIG_HOME': str(Path(directory) / '.config')}
            run = subprocess.run([BASH, '-c', f'. "{ROOT}/opencode/load-secrets.sh"; echo ok'],
                                 env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(run.stdout, 'ok\n')
            self.assertEqual(run.stderr, '')


BASELINE = ('{"permissions":[{"action":"shell","resource":"*","effect":"ask"},'
            '{"action":"edit","resource":"*","effect":"ask"}]')


class SyncSafetyTests(unittest.TestCase):
    FORBIDDEN = re.compile(r'(^|/)(\.env($|\.)|secrets\.env$|opencode\.jsonc$|opencode\.db$|.*\.sqlite3?$)', re.I)

    def test_repo_never_tracks_credentials_or_generated_configs(self):
        tracked = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '-z']).decode().split('\0')
        # .env.example is the documented placeholder and is intentionally tracked.
        candidates = [n for n in tracked if n and n != 'opencode/.env.example']
        offenders = [name for name in candidates if self.FORBIDDEN.search(name)]
        self.assertEqual(offenders, [], 'credentials/generated state must never be committed')
        self.assertIn('opencode/.env.example', tracked)
        self.assertIn('opencode/plugin-compat.json', tracked)
        self.assertIn('opencode/cli.json', tracked)

    def test_generated_config_is_not_the_synced_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            env = base / '.env'
            env.write_text('A=super-secret-value\n')
            env.chmod(0o600)
            output = base / 'opencode.jsonc'
            template = ROOT / 'opencode/opencode.template.jsonc'
            result = subprocess.run([sys.executable, '-B', str(ROOT / 'opencode/render-config.py'),
                                     '--template', str(template), '--env', str(env), '--output', str(output)],
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('super-secret-value', output.read_text())
            self.assertIn('{env:Z_AI_API_KEY}', output.read_text())

    def test_template_secrets_check_rejects_literal_values(self):
        config = {'mcp': {'servers': {'x': {'type': 'remote', 'url': 'https://e',
                                           'headers': {'Authorization': 'raw-secret'}}}}}
        with self.assertRaises(ValueError):
            checker.validate_no_baked_secrets(config, template=True)
        checker.validate_no_baked_secrets(config, template=False)

    def test_mcp_dependency_check_reports_missing_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = home / 'opencode.jsonc'
            config.write_text(BASELINE + ',"mcp":{"servers":{"x":{"type":"local","command":["definitely-not-here-xyz"]}}}}')
            result = subprocess.run(
                [sys.executable, '-B', str(ROOT / 'opencode/check-config.py'),
                 str(config), 'server', '--deps'],
                capture_output=True, text=True, timeout=30,
                env={**os.environ, 'PATH': '/usr/bin:/bin'})
            self.assertEqual(result.returncode, 3)
            self.assertIn('definitely-not-here-xyz', result.stderr)
            # Without --deps the config is still valid: dependencies are opt-in.
            ok = subprocess.run(
                [sys.executable, '-B', str(ROOT / 'opencode/check-config.py'),
                 str(config), 'server'],
                capture_output=True, text=True, timeout=30,
                env={**os.environ, 'PATH': '/usr/bin:/bin'})
            self.assertEqual(ok.returncode, 0, ok.stderr)

    def test_mcp_dependency_check_passes_when_the_command_exists(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = home / 'opencode.jsonc'
            config.write_text(BASELINE + ',"mcp":{"servers":{"x":{"type":"local","command":["sh","-c","true"]}}}}')
            result = subprocess.run(
                [sys.executable, '-B', str(ROOT / 'opencode/check-config.py'),
                 str(config), 'server', '--deps'],
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
