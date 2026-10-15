import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ShellHelperTests(unittest.TestCase):
    def test_memtop_sorts_numeric_rss_and_respects_limit(self):
        sources = {
            'zsh': (ROOT / 'zsh/.zshrc').read_text().split('function memtop() {', 1)[1].split('\n}', 1)[0],
            'bash': (ROOT / 'remote/generate-rc.sh').read_text().split('memtop() {', 1)[1].split('\n}', 1)[0],
        }
        for shell, body in sources.items():
            if not shutil.which(shell):
                continue
            with self.subTest(shell=shell), tempfile.TemporaryDirectory() as directory:
                mock = Path(directory) / 'ps'
                mock.write_text('#!/bin/sh\nprintf "101 1024 alpha\\n202 3072 beta\\n303 2048 gamma\\n"\n')
                mock.chmod(0o755)
                env = {**os.environ, 'PATH': directory + ':' + os.environ['PATH']}
                script = 'memtop() {' + body + '\n}\nmemtop 2\n'
                args = [shell, '-f'] if shell == 'zsh' else [shell, '--noprofile', '--norc']
                result = subprocess.run(args, input=script, env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                lines = result.stdout.splitlines()
                self.assertEqual(len(lines), 3)
                self.assertIn('beta', lines[1])
                self.assertIn('gamma', lines[2])
                invalid = subprocess.run(args, input=script.replace('memtop 2\n', 'memtop invalid\n'),
                                         env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(invalid.returncode, 2)
                self.assertIn('usage: memtop', invalid.stderr)

    @unittest.skipUnless(shutil.which('tmux'), 'tmux is needed to check its copy bindings')
    def test_tmux_clipboard_backend_selection_without_touching_real_clipboard(self):
        text = (ROOT / 'tmux/tmux.conf').read_text()
        block = text.split('# Modo vim\n', 1)[1].split('\n# Keymaps', 1)[0]
        cases = [('Darwin', '', '', 'pbcopy'), ('Linux', ':0', '', 'xclip'),
                 ('Linux', ':0', 'wayland-test', 'wl-copy'), ('Linux', '', '', 'copy-selection-and-cancel')]
        for platform, display, wayland, expected in cases:
            with self.subTest(backend=expected), tempfile.TemporaryDirectory() as directory:
                base = Path(directory)
                socket = str(base / 'tmux.sock')
                for name in ['pbcopy', 'xclip', 'wl-copy']:
                    mock = base / name
                    mock.write_text('#!/bin/sh\necho unexpected-clipboard-access >> "$MOCK_LOG"\nexit 98\n')
                    mock.chmod(0o755)
                uname = base / 'uname'
                uname.write_text('#!/bin/sh\nprintf "%s\\n" "$MOCK_UNAME"\n')
                uname.chmod(0o755)
                config = base / 'tmux.conf'
                config.write_text(block)
                env = {**os.environ, 'HOME': directory, 'XDG_CONFIG_HOME': directory,
                       'PATH': directory + ':' + os.environ['PATH'], 'MOCK_UNAME': platform,
                       'MOCK_LOG': str(base / 'clipboard-access')}
                for name in ['TMUX', 'ZDOTDIR', 'DISPLAY', 'WAYLAND_DISPLAY']:
                    env.pop(name, None)
                if display:
                    env['DISPLAY'] = display
                if wayland:
                    env['WAYLAND_DISPLAY'] = wayland
                tmux = [shutil.which('tmux'), '-S', socket]
                try:
                    subprocess.run([*tmux, '-f', str(config), 'new-session', '-d', '-s', 'test', '/bin/cat'],
                                   env=env, check=True, capture_output=True, text=True, timeout=10)
                    result = subprocess.run([*tmux, 'list-keys', '-T', 'copy-mode-vi', 'y'], env=env,
                                            check=True, capture_output=True, text=True, timeout=10)
                    self.assertIn(expected, result.stdout)
                    self.assertFalse((base / 'clipboard-access').exists())
                finally:
                    subprocess.run([*tmux, 'kill-server'], env=env, capture_output=True, timeout=10)
