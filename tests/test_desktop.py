from pathlib import Path
import subprocess
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DesktopTests(unittest.TestCase):
    def test_alacritty_launch_shell_resolves_on_linuxbrew_host(self):
        linux = tomllib.loads((ROOT / 'alacritty/alacritty.toml').read_text())
        shell = linux['terminal']['shell']
        self.assertEqual(shell, {'program': '/usr/bin/env', 'args': ['zsh', '--login']})
        self.assertTrue(Path('/usr/bin/env').is_file())
        self.assertTrue(subprocess.run(['bash', '-lc', 'command -v zsh'], capture_output=True, text=True).stdout.strip())
        self.assertIsInstance(linux['hints']['enabled'][0]['command'], dict)
        self.assertEqual(linux['hints']['enabled'][0]['command']['program'], 'xdg-open')

    def test_macos_alacritty_config_uses_builtin_zsh_and_valid_hint_command(self):
        mac = tomllib.loads((ROOT / 'alacritty/alacritty.macos.toml').read_text())
        self.assertEqual(mac['terminal']['shell']['program'], '/bin/zsh')
        self.assertIsInstance(mac['hints']['enabled'][0]['command'], dict)

if __name__ == '__main__':
    unittest.main()
