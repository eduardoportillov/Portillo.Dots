import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class WorkstationTests(unittest.TestCase):
    def test_macos_casks_target_user_applications_without_sudo(self):
        for upgrade in [False, True]:
            with self.subTest(upgrade=upgrade), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                binaries = home / 'bin'
                binaries.mkdir()
                sdkman = home / '.sdkman/bin/sdkman-init.sh'
                sdkman.parent.mkdir(parents=True)
                sdkman.write_text('# already installed\n')
                (home / '.oh-my-zsh').mkdir()
                log = home / 'calls'
                stub = f'#!{sys.executable}\n' + '''import json, os, sys
name = os.path.basename(sys.argv[0])
with open(os.environ['MOCK_CALLS'], 'a') as output:
    output.write(json.dumps([name, *sys.argv[1:]]) + '\\n')
if name == 'fnm' and sys.argv[1] == 'env': print(':')
if name == 'uv' and sys.argv[1:] == ['tool', 'list']: print('markitdown v1.0')
if name == 'brew' and sys.argv[1] == 'list':
    if os.environ['MOCK_INSTALLED'] == 'true':
        for app in ('alacritty', 'zed', 'aerospace', 'copyq'):
            print(app + ' 1.0.0')
    sys.exit(0 if os.environ['MOCK_INSTALLED'] == 'true' else 1)
if name == 'sudo': sys.exit(99)
'''
                for name in ['fnm', 'node', 'pnpm', 'rustup', 'uv', 'claude', 'brew', 'sudo']:
                    path = binaries / name
                    path.write_text(stub)
                    path.chmod(0o755)
                script = '''source "$1/setup.sh"; PLATFORM=mac; UPGRADE="$2"; LOG="$HOME/install.log";
                    sync_git_dependency() { return 0; }; install_fonts() { return 0; }
                    run_installer() { printf 'Unexpected downloaded installer\\n' >&2; return 99; }
                    install_workstation'''
                result = subprocess.run(['bash', '-euc', script, '_', str(ROOT), str(upgrade).lower()],
                                        env={**os.environ, 'HOME': directory,
                                             'PATH': str(binaries) + ':' + os.environ['PATH'],
                                             'MOCK_CALLS': str(log), 'MOCK_INSTALLED': str(upgrade).lower()},
                                        capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = [json.loads(line) for line in log.read_text().splitlines()]
                self.assertFalse(any(call[0] == 'sudo' for call in calls))
                casks = [call for call in calls if call[:2] == ['brew', 'upgrade' if upgrade else 'install']]
                self.assertEqual(len(casks), 4)
                self.assertTrue(all('--appdir=' + str(home / 'Applications') in call for call in casks))
                if upgrade:
                    self.assertIn(['rustup', 'update'], calls)

    def test_neovim_version_gate(self):
        cases = [('0.10.4', '0.11.0', False), ('0.11.0', '0.11.0', True),
                 ('0.12.0', '0.11.0', True), ('1.0.0', '0.11.0', True),
                 ('0.11.0', '0.12.0', False), ('3.6.0', '3.3.0', True),
                 ('2.0.28', '2.0.0', True), ('24.19.0', '20.0.0', True)]
        for have, want, accepted in cases:
            with self.subTest(have=have, want=want):
                script = ('source "$1/installer/components.sh"; source "$1/installer/common.sh"; '
                          'version_at_least "$2" "$3"')
                result = subprocess.run(['bash', '-euc', script, '_', str(ROOT), have, want],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, accepted, result.stderr)

    def test_version_extraction_normalises_vendor_suffixes(self):
        for text, expected in [('NVIM v0.11.0', '0.11.0'), ('tmux 3.6b', '3.6.0'),
                               ('opencode v2.0.28', '2.0.28'), ('v24.19.0', '24.19.0'),
                               ('alacritty 0.16.1', '0.16.1'), ('not a version', None)]:
            with self.subTest(text=text):
                script = 'source "$1/installer/common.sh"; extract_version "$2"'
                result = subprocess.run(['bash', '-euc', script, '_', str(ROOT), text],
                                        capture_output=True, text=True)
                if expected is None:
                    self.assertNotEqual(result.returncode, 0)
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.strip(), expected)

    def test_linux_diagnostics_are_not_installed_on_macos(self):
        for platform in ['linux', 'mac']:
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                env = {**os.environ, 'HOME': directory, 'SHELL': '/bin/bash',
                       'XDG_CONFIG_HOME': directory + '/.config', 'XDG_STATE_HOME': directory + '/.state'}
                for name in ['DISPLAY', 'WAYLAND_DISPLAY']:
                    env.pop(name, None)
                script = '''source "$1/setup.sh"; PLATFORM="$2"; CONFIG_ONLY=true;
                    CONFIG_HOME="$HOME/.config"; initialize_state; trap cleanup_setup EXIT;
                    configure_workstation'''
                result = subprocess.run(['bash', '-euc', script, '_', str(ROOT), platform],
                                        env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                for name in ['dots-fix-tiling', 'dots-diag']:
                    self.assertEqual((home / '.local/bin' / name).is_symlink(), platform == 'linux')
                selected = 'alacritty.macos.toml' if platform == 'mac' else 'alacritty.toml'
                self.assertEqual((home / '.config/alacritty/alacritty.toml').resolve(), ROOT / 'alacritty' / selected)
