import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class WorkstationTests(unittest.TestCase):
    def test_neovim_version_gate(self):
        for version, accepted in [('NVIM v0.10.4', False), ('NVIM v0.11.0', True),
                                  ('NVIM v0.12.0-dev', True), ('NVIM v1.0.0', True), ('unexpected', False)]:
            with self.subTest(version=version):
                script = 'source "$1/setup.sh"; nvim() { printf "%s\\n" "$MOCK_VERSION"; }; check_workstation_neovim'
                result = subprocess.run(['bash', '-euc', script, '_', str(ROOT)],
                                        env={**os.environ, 'MOCK_VERSION': version}, capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, accepted, result.stderr)

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
