import os
from pathlib import Path
import shutil
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
                 ['--profile', 'server', '--hardware'],
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
            (home / '.zshrc').write_text('previous zsh\n')
            for _ in range(2):
                result = self.configure_server(directory)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            # The shared shell identity is managed like tmux.conf: the link is
            # installed and the previous file survives in the backup.
            self.assertEqual((home / '.zshrc').resolve(), ROOT / 'zsh/.zshrc')
            self.assertTrue((home / '.p10k.zsh').is_symlink())
            backups = list((home / '.state').rglob('.zshrc'))
            self.assertTrue(any(p.read_text() == 'previous zsh\n' for p in backups))
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


class CatalogInstallTests(unittest.TestCase):
    """install_source_tools owns the npm/uv-tool channels end to end.

    pi is the reference consumer: adding an npm tool to the catalog must
    install, depend and upgrade without installer changes.
    """

    COREUTILS = ['awk', 'basename', 'cat', 'chmod', 'cut', 'dirname', 'env', 'grep',
                 'head', 'id', 'ln', 'mkdir', 'mktemp', 'mv', 'readlink', 'rm',
                 'sed', 'sort', 'stat', 'touch', 'tr', 'uname', 'wc']

    def harness(self, directory, node='22.19.0', installed_pi=False, upgrade=False):
        home = Path(directory)
        stubs = home / 'bin'
        stubs.mkdir()
        coreutils = home / 'coreutils'
        coreutils.mkdir()
        for name in self.COREUTILS:
            target = shutil.which(name)
            if target:
                (coreutils / name).symlink_to(target)
        (stubs / 'npm').write_text(
            '#!/bin/bash\n'
            'printf \'npm %s\\n\' "$*" >> "$MOCK_CALLS"\n'
            'mkdir -p "$HOME/.local/bin"\n'
            'printf \'#!/bin/sh\\necho pi-stub\\n\' > "$HOME/.local/bin/pi"\n'
            'chmod +x "$HOME/.local/bin/pi"\n')
        (stubs / 'fnm').write_text(
            '#!/bin/bash\n'
            'printf \'fnm %s\\n\' "$*" >> "$MOCK_CALLS"\n'
            'if [ "$1" = "env" ]; then echo ":"; fi\n'
            'if [ "$1" = "install" ]; then\n'
            '  printf \'#!/bin/sh\\nif [ "$1" = "--version" ]; then echo "v24.0.0"; fi\\n\' > "$MOCK_BIN/node"\n'
            '  chmod +x "$MOCK_BIN/node"\n'
            'fi\n')
        if node:
            (stubs / 'node').write_text(
                f'#!/bin/sh\nif [ "$1" = "--version" ]; then echo "v{node}"; fi\n')
        for name in ['npm', 'fnm', 'node']:
            path = stubs / name
            if path.exists():
                path.chmod(0o755)
        if installed_pi:
            (home / '.local/bin').mkdir(parents=True)
            (home / '.local/bin/pi').write_text(
                '#!/bin/bash\nprintf \'pi %s\\n\' "$*" >> "$MOCK_CALLS"\n')
            (home / '.local/bin/pi').chmod(0o755)
        script = ('source "$1/setup.sh"; LOG="$HOME/install.log"; '
                  f'UPGRADE={"true" if upgrade else "false"}; install_source_tools server')
        env = {**os.environ, 'HOME': directory,
               'PATH': f'{home / ".local/bin"}:{stubs}:{coreutils}',
               'MOCK_CALLS': str(home / 'calls'), 'MOCK_BIN': str(stubs)}
        result = subprocess.run([shutil.which('bash'), '-euc', script, '_', str(ROOT)],
                                env=env, capture_output=True, text=True, timeout=30)
        calls = (home / 'calls').read_text().splitlines() if (home / 'calls').exists() else []
        return result, calls

    def test_npm_tool_installs_with_ignored_scripts(self):
        with tempfile.TemporaryDirectory() as directory:
            result, calls = self.harness(directory)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('npm install --global --ignore-scripts --prefix '
                          f'{directory}/.local @earendil-works/pi-coding-agent', calls)
            self.assertTrue((Path(directory) / '.local/bin/pi').exists())

    def test_missing_node_is_provisioned_through_fnm(self):
        with tempfile.TemporaryDirectory() as directory:
            result, calls = self.harness(directory, node=None)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('fnm install 24', calls)
            self.assertTrue(any(call.startswith('npm install') for call in calls), calls)

    def test_node_below_the_floor_is_provisioned_through_fnm(self):
        with tempfile.TemporaryDirectory() as directory:
            result, calls = self.harness(directory, node='18.19.0')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('fnm install 24', calls)
            self.assertTrue(any(call.startswith('npm install') for call in calls), calls)

    def test_upgrade_runs_the_declared_updater_only(self):
        with tempfile.TemporaryDirectory() as directory:
            result, calls = self.harness(directory, installed_pi=True, upgrade=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('pi update', calls)
            self.assertFalse(any(call.startswith('npm install') for call in calls), calls)

    def test_installed_tool_is_left_untouched_without_upgrade(self):
        with tempfile.TemporaryDirectory() as directory:
            result, calls = self.harness(directory, installed_pi=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(calls, [])


if __name__ == '__main__':
    unittest.main()


class HomebrewBootstrapTests(unittest.TestCase):
    """Homebrew is a dependency like any other: provisioned, never assumed."""

    def test_linux_bootstraps_homebrew_self_contained(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            prefix = base / 'home/linuxbrew/.linuxbrew'
            prefix.parent.mkdir(parents=True)
            mocks = base / 'bin'
            mocks.mkdir()
            coreutils = base / 'coreutils'
            coreutils.mkdir()
            for name in ['cp', 'dirname', 'readlink', 'cat', 'grep', 'sed', 'mkdir', 'mktemp', 'mv', 'rm', 'stat']:
                target = shutil.which(name)
                if target:
                    (coreutils / name).symlink_to(target)
            brew_stub = base / 'brew-stub'
            brew_stub.write_text(
                '#!/bin/bash\n'
                'if [ "$1" = "shellenv" ]; then\n'
                '  printf \'export PATH="%s:$PATH"\\n\' "$(dirname "$0")"\n'
                'else\n'
                '  printf \'brew %s\\n\' "$*" >> "$MOCK_CALLS"\n'
                'fi\n')
            brew_stub.chmod(0o755)
            (mocks / 'git').write_text(
                '#!/bin/bash\n'
                'printf \'git %s\\n\' "$*" >> "$MOCK_CALLS"\n'
                'mkdir -p "$5/bin"\n'
                'cp "$MOCK_BREW_STUB" "$5/bin/brew"\n')
            (mocks / 'git').chmod(0o755)
            script = ('source "$1/setup.sh"; PLATFORM=linux; LOG="$HOME/log"; '
                      'ensure_homebrew "$2"')
            env = {**os.environ, 'HOME': directory, 'PATH': f'{mocks}:{coreutils}',
                   'MOCK_CALLS': str(base / 'calls'), 'MOCK_BREW_STUB': str(brew_stub)}
            result = subprocess.run([shutil.which('bash'), '-euc', script, '_', str(ROOT), str(prefix)],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            calls = (base / 'calls').read_text()
            self.assertIn(f'git clone --depth 1 https://github.com/Homebrew/brew {prefix}', calls)
            self.assertIn('brew update', calls)

    def test_macos_keeps_the_preinstalled_homebrew_requirement(self):
        with tempfile.TemporaryDirectory() as directory:
            script = ('source "$1/setup.sh"; PLATFORM=mac; LOG="$HOME/log"; '
                      'ensure_homebrew "$HOME/nonexistent" ; exit 0')
            env = {**os.environ, 'HOME': directory, 'PATH': '/usr/bin:/bin'}
            result = subprocess.run([shutil.which('bash'), '-euc', script, '_', str(ROOT)],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Homebrew is required on macOS', result.stderr)
