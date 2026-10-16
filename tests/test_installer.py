import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InstallerTests(unittest.TestCase):
    def isolated(self, directory):
        env = os.environ.copy()
        env.update(HOME=directory, XDG_CONFIG_HOME=directory + '/.config',
                   XDG_STATE_HOME=directory + '/.state', SHELL='/bin/bash')
        return env

    def test_dry_run_has_no_writes(self):
        for profile in ('server', 'workstation'):
            with self.subTest(profile=profile), tempfile.TemporaryDirectory() as directory:
                result = subprocess.run(['bash', str(ROOT / 'setup.sh'), '--profile', profile, '--dry-run'],
                                        env=self.isolated(directory), capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(list(Path(directory).iterdir()), [])

    def test_rejects_invalid_or_conflicting_arguments(self):
        cases = [[], ['--wat'], ['--profile'], ['--profile', 'unknown'],
                 ['--profile', 'server', '--hardware'], ['--profile', 'server', '--change-shell'],
                 ['--profile', 'server', '--config-only', '--upgrade'],
                 ['--profile', 'server', '--check-sudo', '--config-only'],
                 ['--profile', 'server', '--check-sudo', '--check'],
                 ['--profile', 'server', '--check-sudo', '--upgrade'],
                 ['--profile', 'server', '--harden-existing-service'],
                 ['--profile', 'workstation', '--harden-existing-service', '--hardware'],
                 ['--profile', 'workstation', '--harden-existing-service', '--check-sudo'],
                 ['--profile', 'workstation', '--apply-linux', '--config-only']]
        for args in cases:
            with self.subTest(args=args), tempfile.TemporaryDirectory() as directory:
                result = subprocess.run(['bash', str(ROOT / 'setup.sh'), *args], input='',
                                        env=self.isolated(directory), capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(list(Path(directory).iterdir()), [])

    def configure_server(self, directory):
        script = '''
            source "$1/setup.sh"
            PROFILE=server; PACKAGE_MANAGER=native; CONFIG_ONLY=true
            detect_platform; initialize_state
            trap cleanup_setup EXIT
            configure_profile
            verify_configs
        '''
        return subprocess.run(['bash', '-euc', script, '_', str(ROOT)],
                              env=self.isolated(directory), capture_output=True, text=True)

    def test_server_is_lightweight_and_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            (home / '.bashrc').write_text('export MY_SETTING=preserved\n')
            (home / '.zshrc').write_text('untouched zsh\n')
            for _ in range(2):
                result = self.configure_server(directory)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual((home / '.zshrc').read_text(), 'untouched zsh\n')
            self.assertIn('MY_SETTING=preserved', (home / '.bashrc').read_text())
            self.assertEqual((home / '.bashrc').read_text().count('# >>> Portillo.Dots Remote Server >>>'), 1)
            self.assertFalse((home / '.config/alacritty').exists())
            self.assertFalse((home / '.config/zed').exists())
            self.assertFalse((home / '.config/systemd').exists())
            self.assertFalse((home / '.oh-my-zsh').exists())
            self.assertEqual((home / '.tmux.conf').resolve(), ROOT / 'server/tmux.conf')

    def test_preserves_independent_opencode_config(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / '.config/opencode/opencode.jsonc'
            config.parent.mkdir(parents=True)
            original = '{"model":"custom/model","permissions":[{"action":"shell","resource":"*","effect":"ask"},{"action":"edit","resource":"*","effect":"ask"}]}\n'
            config.write_text(original)
            result = self.configure_server(directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(config.is_symlink())
            self.assertEqual(config.read_text(), original)

    def test_preserved_permissive_server_config_fails_verification(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / '.config/opencode/opencode.jsonc'
            config.parent.mkdir(parents=True)
            config.write_text('{"permissions":[{"action":"shell","resource":"*","effect":"allow"}]}')
            result = self.configure_server(directory)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Independent config preserved', result.stderr)
            self.assertFalse(config.is_symlink())

    def test_nvim_directory_symlink_is_not_written_through(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            original = home / 'original-editor'
            original.mkdir()
            (original / 'init.lua').write_text('original config\n')
            (home / '.config').mkdir()
            (home / '.config/nvim').symlink_to(original)
            result = self.configure_server(directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((original / 'init.lua').read_text(), 'original config\n')
            self.assertFalse((home / '.config/nvim').is_symlink())

    def test_backups_do_not_collide_on_basename(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            for name in ('first', 'second'):
                (home / name).mkdir()
                (home / name / 'settings.json').write_text(name)
            script = '''source "$1/setup.sh"; initialize_state; backup "$HOME/first/settings.json";
                backup "$HOME/second/settings.json"; cleanup_setup'''
            result = subprocess.run(['bash', '-euc', script, '_', str(ROOT)],
                                    env=self.isolated(directory), capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            contents = {p.read_text() for p in (home / '.state').rglob('settings.json')}
            self.assertEqual(contents, {'first', 'second'})

    def test_privileged_helper_rejects_direct_invocation(self):
        result = subprocess.run(['bash', str(ROOT / 'installer/privileged.sh')],
                                env={**os.environ, 'SUDO_USER': ''}, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)

    def test_privileged_failure_stops_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'log'
            script = '''source "$1/setup.sh"; PROFILE=server; LOG="$2";
                sudo() { printf 'mock system failure\\n'; return 57; }
                privileged_phase
                printf 'MUST NOT RUN\\n' '''
            result = subprocess.run(['bash', '-euc', script, '_', str(ROOT), str(log)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 57)
            self.assertNotIn('MUST NOT RUN', result.stdout)

    def test_server_preserves_symlinked_shell_config(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            original = home / 'shell-original'
            original.write_text('do not overwrite\n')
            (home / '.bashrc').symlink_to(original)
            result = self.configure_server(directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(original.read_text(), 'do not overwrite\n')
            self.assertTrue((home / '.bashrc').is_symlink())

    def test_single_sudo_invocation_and_no_sudoers_writer(self):
        shell = '\n'.join(p.read_text() for p in (ROOT / 'installer').glob('*.sh'))
        invocations = [line.strip() for line in shell.splitlines() if line.strip().startswith('sudo ')]
        self.assertEqual(len(invocations), 1)
        self.assertNotIn('sudo tee', shell)
        self.assertNotIn('timestamp_timeout', shell)
        self.assertNotIn('NOPASSWD: ALL" |', shell)


if __name__ == '__main__':
    unittest.main()
