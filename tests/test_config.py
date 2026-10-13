import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ConfigTests(unittest.TestCase):
    def run_renderer(self, template, env, output):
        return subprocess.run([
            'python3', str(ROOT / 'opencode/render-config.py'),
            '--template', str(template), '--env', str(env), '--output', str(output),
        ], capture_output=True, text=True)

    def test_secrets_are_escaped_private_and_not_logged(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            template, env, output = (base / name for name in ('template', '.env', 'output'))
            template.write_text('{"key": "{{KEY}}"}')
            secret = 'fake"key\\with spaces=and&symbols'
            env.write_text(f"KEY='{secret}'")
            result = self.run_renderer(template, env, output)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(output.read_text())['key'], secret)
            self.assertNotIn(secret, result.stdout + result.stderr)
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            self.assertEqual(env.stat().st_mode & 0o777, 0o600)

    def test_failure_preserves_existing_output(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            template, env, output = (base / name for name in ('template', '.env', 'output'))
            template.write_text('{"key": "{{KEY}}"}')
            env.write_text('OTHER=value\n')
            output.write_text('previous config')
            result = self.run_renderer(template, env, output)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_text(), 'previous config')

    def test_dotenv_is_not_executed(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            template, env, output = (base / name for name in ('template', '.env', 'output'))
            sentinel = base / 'must-not-exist'
            template.write_text('{"key": "{{KEY}}"}')
            env.write_text(f'KEY=$(touch {sentinel})\n')
            self.assertEqual(self.run_renderer(template, env, output).returncode, 0)
            self.assertFalse(sentinel.exists())

    def test_refuses_symlink_output(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            template, env, output = (base / name for name in ('template', '.env', 'output'))
            template.write_text('{}')
            env.write_text('KEY=value\n')
            target = base / 'unrelated'
            target.write_text('keep')
            output.symlink_to(target)
            self.assertNotEqual(self.run_renderer(template, env, output).returncode, 0)
            self.assertEqual(target.read_text(), 'keep')


if __name__ == '__main__':
    unittest.main()
