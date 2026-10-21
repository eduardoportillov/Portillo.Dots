import os
from pathlib import Path
import shutil
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
        for name in ['wl-paste', 'xdpyinfo']:
            command = base / name
            command.write_text('#!/bin/sh\nexit 0\n')
            command.chmod(0o755)
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
            base = Path(directory)
            env, authority = self.fixture(base)
            env.update(DISPLAY=':99', XAUTHORITY=str(authority), WAYLAND_DISPLAY='alternate',
                       XDG_RUNTIME_DIR=str(base))
            with socket.socket(socket.AF_UNIX) as server:
                server.bind(str(base / 'alternate'))
                result = self.run_helper(env)
                self.assertNotIn('export DISPLAY=:0', result.stdout)
                self.assertNotIn('export WAYLAND_DISPLAY=wayland-test', result.stdout)
            for changed in [{'SSH_CONNECTION': 'host forwarded'}, {'SSH_TTY': '/dev/pts/2'}]:
                with self.subTest(changed=changed):
                    self.assertEqual(self.run_helper({**env, **changed}).stdout, '')

    def test_ignores_missing_authority_and_socket(self):
        with tempfile.TemporaryDirectory() as directory:
            env, authority = self.fixture(Path(directory))
            authority.unlink()
            result = self.run_helper(env)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, '')

    def test_replaces_stale_local_displays_but_never_ssh(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            env, authority = self.fixture(base)
            (base / 'session.env').write_text(
                f'DISPLAY=:0\nXAUTHORITY={authority}\nWAYLAND_DISPLAY=wayland-test\n'
                f'XDG_RUNTIME_DIR={base}\nXDG_SESSION_TYPE=wayland\n')
            env.update(DISPLAY=':99', XAUTHORITY='/missing/old-auth', WAYLAND_DISPLAY='old-wayland',
                       XDG_RUNTIME_DIR='/old/runtime')
            with socket.socket(socket.AF_UNIX) as server:
                server.bind(str(base / 'wayland-test'))
                result = self.run_helper(env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('export DISPLAY=:0', result.stdout)
            self.assertIn(f'export XAUTHORITY={str(authority).replace(" ", "\\ ")}', result.stdout)
            self.assertIn('export WAYLAND_DISPLAY=wayland-test', result.stdout)
            ssh_result = self.run_helper({**env, 'SSH_CONNECTION': 'host forwarded'})
            self.assertEqual(ssh_result.stdout, '')

    @unittest.skipUnless(shutil.which('zsh'), 'Zsh is needed to test shell startup integration')
    def test_restored_zsh_recovers_metadata_through_dotfile_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            env, authority = self.fixture(base)
            home = base / 'home'
            checkout = base / 'checkout'
            home.mkdir()
            (checkout / 'zsh').mkdir(parents=True)
            (checkout / 'linux').mkdir()
            (checkout / 'linux/graphical-environment.sh').symlink_to(HELPER)
            # Exercise the actual startup block, but never run personal plugins,
            # prompts or SDK managers during an isolated regression test.
            startup = (ROOT / 'zsh/.zshrc').read_text().split('# OS detection', 1)[0]
            (checkout / 'zsh/.zshrc').write_text(startup)
            (home / '.zshrc').symlink_to(checkout / 'zsh/.zshrc')
            env.update(HOME=str(home), XDG_CACHE_HOME=str(home / '.cache'), DISPLAY=':0',
                       TMUX='restored-test-panel', XDG_SESSION_TYPE='wayland')
            with socket.socket(socket.AF_UNIX) as server:
                server.bind(str(base / 'wayland-test'))
                result = subprocess.run([
                    'zsh', '-f', '-c',
                    'source "$HOME/.zshrc"; printf "%s\\n" "$DISPLAY" "$XAUTHORITY" "$WAYLAND_DISPLAY"',
                ], env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), [':0', str(authority), 'wayland-test'])
            self.assertEqual(result.stderr, '')

    def test_x11_metadata_works_without_a_wayland_socket(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            env, authority = self.fixture(base)
            (base / 'session.env').write_text(f'DISPLAY=:0\nXAUTHORITY={authority}\nXDG_SESSION_TYPE=x11\n')
            result = self.run_helper(env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('WAYLAND_DISPLAY', result.stdout)
            check = subprocess.run([
                'bash', '-c', result.stdout + '\nprintf "%s\\n" "$DISPLAY" "$XAUTHORITY"',
            ], env=env, capture_output=True, text=True)
            self.assertEqual(check.stdout.splitlines(), [':0', str(authority)])

    def test_unavailable_session_manager_does_not_pollute_terminal(self):
        with tempfile.TemporaryDirectory() as directory:
            env, _ = self.fixture(Path(directory))
            (Path(directory) / 'systemctl').write_text('#!/bin/sh\necho "no user bus" >&2\nexit 1\n')
            result = self.run_helper(env)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, '')
            self.assertEqual(result.stderr, '')


if __name__ == '__main__':
    unittest.main()
