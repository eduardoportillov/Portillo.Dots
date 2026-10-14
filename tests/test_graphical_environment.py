import os
from pathlib import Path
import socket
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'linux/graphical-environment.sh'


class GraphicalEnvironmentTests(unittest.TestCase):
    def fixture(self, base):
        authority = base / 'authority with spaces'
        authority.write_text('fake-cookie-never-printed')
        mock = base / 'systemctl'
        mock.write_text('#!/bin/sh\ncat "$MOCK_ENVIRONMENT"\n')
        mock.chmod(0o755)
        metadata = base / 'session.env'
        metadata.write_text(f'DISPLAY=:0\nXAUTHORITY={authority}\nWAYLAND_DISPLAY=wayland-test\n'
                            f'XDG_RUNTIME_DIR={base}\nXDG_SESSION_TYPE=wayland\n'
                            'UNRELATED_SECRET=must-not-export\n')
        env = dict(os.environ)
        for key in ['DISPLAY', 'WAYLAND_DISPLAY', 'XAUTHORITY', 'SSH_CONNECTION', 'SSH_TTY']:
            env.pop(key, None)
        env.update(PATH=str(base) + ':' + env['PATH'], MOCK_ENVIRONMENT=str(metadata))
        return env, authority

    def run_helper(self, env):
        return subprocess.run(['bash', str(HELPER)], env=env, capture_output=True, text=True)

    def test_recovers_graphical_metadata_without_exporting_cookies(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            env, authority = self.fixture(base)
            with socket.socket(socket.AF_UNIX) as server:
                server.bind(str(base / 'wayland-test'))
                result = self.run_helper(env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn('fake-cookie', result.stdout)
                self.assertNotIn('UNRELATED_SECRET', result.stdout)
                check = subprocess.run(['bash', '-c', result.stdout + '\nprintf "%s\\n" "$XAUTHORITY" "$WAYLAND_DISPLAY"'],
                                       env=env, capture_output=True, text=True)
                self.assertEqual(check.stdout.splitlines(), [str(authority), 'wayland-test'])

    def test_never_overrides_ssh_or_alternative_displays(self):
        with tempfile.TemporaryDirectory() as directory:
            env, _ = self.fixture(Path(directory))
            for changed in [{'SSH_CONNECTION': 'host forwarded'}, {'SSH_TTY': '/dev/pts/2'},
                            {'DISPLAY': ':99'}, {'WAYLAND_DISPLAY': 'another-session'}]:
                with self.subTest(changed=changed):
                    self.assertEqual(self.run_helper({**env, **changed}).stdout, '')

    def test_ignores_missing_authority_and_socket(self):
        with tempfile.TemporaryDirectory() as directory:
            env, authority = self.fixture(Path(directory))
            authority.unlink()
            result = self.run_helper(env)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, '')


if __name__ == '__main__':
    unittest.main()
