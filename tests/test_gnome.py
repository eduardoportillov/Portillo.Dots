import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class GnomeTests(unittest.TestCase):
    def run_configuration(self, directory, bindings, enabled=''):
        mock = Path(directory) / 'gsettings'
        mock.write_text('''#!/bin/sh
if [ "$1" = get ]; then
  printf '%s\\n' "$MOCK_BINDINGS"
else
  printf '%s\\n' "$*" >> "$MOCK_LOG"
fi
''')
        mock.chmod(0o755)
        extensions = Path(directory) / 'gnome-extensions'
        extensions.write_text('#!/bin/sh\nprintf "%s\\n" "$MOCK_ENABLED"\n')
        extensions.chmod(0o755)
        log = Path(directory) / 'calls'
        result = subprocess.run(['bash', str(ROOT / 'gnome/configure.sh')],
                                env={**os.environ, 'PATH': directory + ':' + os.environ['PATH'],
                                     'MOCK_LOG': str(log), 'MOCK_BINDINGS': bindings, 'MOCK_ENABLED': enabled},
                                capture_output=True, text=True)
        return result, log.read_text()

    def test_preserves_custom_shortcuts_and_inactive_native_tiling(self):
        with tempfile.TemporaryDirectory() as directory:
            result, calls = self.run_configuration(directory,
                "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom9/']")
            self.assertEqual(result.returncode, 0, result.stderr)
            bindings = next(line for line in calls.splitlines() if ' custom-keybindings [' in line)
            self.assertIn('custom9/', bindings)
            self.assertIn('portillo-terminal/', bindings)
            self.assertNotIn('toggle-tiled-left', calls)

    def test_existing_managed_entries_are_not_duplicated(self):
        prefix = '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/'
        with tempfile.TemporaryDirectory() as directory:
            result, calls = self.run_configuration(directory,
                repr([prefix + 'portillo-terminal/', prefix + 'portillo-tiling-reset/']))
            self.assertEqual(result.returncode, 0, result.stderr)
            bindings = next(line for line in calls.splitlines() if ' custom-keybindings [' in line)
            self.assertEqual(bindings.count('portillo-terminal/'), 1)
            self.assertEqual(bindings.count('portillo-tiling-reset/'), 1)

    def test_empty_gvariant_array_is_supported(self):
        with tempfile.TemporaryDirectory() as directory:
            result, calls = self.run_configuration(directory, '@as []')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('portillo-terminal/', calls)

    def test_malformed_list_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            result, calls = self.run_configuration(directory, "{'unexpected': 'mapping'}")
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn(' custom-keybindings [', calls)

    def test_native_tiling_is_disabled_only_when_otiling_is_enabled(self):
        with tempfile.TemporaryDirectory() as directory:
            result, calls = self.run_configuration(directory, '@as []', 'o-tiling@oliwebd.github.com')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('toggle-tiled-left []', calls)


if __name__ == '__main__':
    unittest.main()
