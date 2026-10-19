from pathlib import Path
import shutil
import subprocess
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DesktopTests(unittest.TestCase):
    def test_alacritty_linux_launches_the_login_shell_from_session_path(self):
        linux = tomllib.loads((ROOT / 'alacritty/alacritty.toml').read_text())
        shell = linux['terminal']['shell']
        self.assertEqual(shell, {'program': '/usr/bin/env', 'args': ['zsh', '--login']})
        # /usr/bin/env is the portable resolver; the Zsh binary location varies
        # by platform (/bin/zsh, Linuxbrew, Homebrew on macOS Intel).
        self.assertTrue(Path('/usr/bin/env').is_file(), '/usr/bin/env must exist')
        self.assertIsInstance(linux['hints']['enabled'][0]['command'], dict)
        self.assertEqual(linux['hints']['enabled'][0]['command']['program'], 'xdg-open')

    @unittest.skipUnless(shutil.which('zsh'), 'Zsh must be installed to probe the launch path')
    def test_alacritty_launch_command_actually_resolves_zsh(self):
        result = subprocess.run(['bash', '-c', 'command -v zsh'],
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.strip(), 'the configured launch command must find Zsh')

    def test_macos_alacritty_config_uses_builtin_zsh_and_valid_hint_command(self):
        mac = tomllib.loads((ROOT / 'alacritty/alacritty.macos.toml').read_text())
        self.assertEqual(mac['terminal']['shell']['program'], '/bin/zsh')
        self.assertIsInstance(mac['hints']['enabled'][0]['command'], dict)
        self.assertEqual(mac['hints']['enabled'][0]['command']['program'], 'open')

    def test_theme_file_referenced_by_both_configs_exists(self):
        for name in ['alacritty/alacritty.toml', 'alacritty/alacritty.macos.toml']:
            config = tomllib.loads((ROOT / name).read_text())
            for imported in config['general']['import']:
                # Imports use the runtime path (~/.config/alacritty/...); the
                # versioned file lives under alacritty/themes/.
                self.assertTrue((ROOT / 'alacritty/themes' / Path(imported).name).is_file(),
                                f'{name} imports a missing theme: {imported}')
