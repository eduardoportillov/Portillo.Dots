import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('config_check', ROOT / 'opencode/check-config.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class OpenCodeChecksTests(unittest.TestCase):
    def rule(self, action, effect):
        return {'action': action, 'resource': '*', 'effect': effect}

    def test_server_requires_both_global_defaults(self):
        for rules in [[], [self.rule('shell', 'ask')], [self.rule('edit', 'ask')],
                      [self.rule('shell', 'allow'), self.rule('edit', 'ask')]]:
            with self.subTest(rules=rules), self.assertRaises(ValueError):
                checker.validate({'permissions': rules}, 'server')
        checker.validate({'permissions': [self.rule('shell', 'ask'), self.rule('edit', 'deny')]}, 'server')

    def test_last_matching_default_wins(self):
        with self.assertRaises(ValueError):
            checker.validate({'permissions': [self.rule('*', 'ask'), self.rule('shell', 'allow')]}, 'server')
        checker.validate({'permissions': [self.rule('*', 'allow'), self.rule('*', 'ask')]}, 'server')

    def test_specific_exceptions_do_not_replace_global_defaults(self):
        checker.validate({'permissions': [self.rule('*', 'ask'),
                         {'action': 'shell', 'resource': 'git status *', 'effect': 'allow'}]}, 'server')

    def test_legacy_defaults_and_native_override(self):
        config = {'permission': {'bash': {'*': 'ask'}, 'edit': 'ask'}}
        checker.validate(config, 'server')
        with self.assertRaises(ValueError):
            checker.validate({**config, 'permissions': [self.rule('edit', 'allow')]}, 'server')

    def test_malformed_rules_fail_closed(self):
        for rules in ['allow', None, [None], [{}], [self.rule('*', 'unknown')]]:
            with self.subTest(rules=rules), self.assertRaises(ValueError):
                checker.validate({'permissions': rules}, 'server')
        with self.assertRaises(ValueError):
            checker.validate([], 'workstation')

    def test_invalid_input_does_not_expose_config_fragments(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'opencode.jsonc'
            config.write_text('{"credential":"fake-sensitive-value", INVALID}')
            result = subprocess.run(['python3', '-B', str(ROOT / 'opencode/check-config.py'),
                                     str(config), 'server'], capture_output=True, text=True,
                                    env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('fake-sensitive-value', result.stdout + result.stderr)
            self.assertNotIn('Traceback', result.stderr)
