import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ShellHelperTests(unittest.TestCase):
    def test_memtop_sorts_numeric_rss_and_respects_limit(self):
        # One shared definition (shared/shell/common.sh) must behave identically
        # in every shell that sources it.
        text = (ROOT / 'shared/shell/common.sh').read_text()
        body = text.split('memtop() {', 1)[1].split('\n}', 1)[0]
        for shell in ('bash', 'zsh'):
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
        text = (ROOT / 'shared/tmux/base.conf').read_text()
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


class SharedBaselineTests(unittest.TestCase):
    """The shared shell baseline is the single source of the common feel."""

    def test_every_shell_context_consumes_the_shared_baseline(self):
        # Installed hosts link it as portillo-dots/shell-common.sh; the remote
        # runtime deploys the tree and sources shared/shell/common.sh.
        pattern = re.compile(r'shared/shell/common\.sh|shell-common\.sh')
        for name in ('zsh/.zshrc', 'server/shell.sh', 'remote/generate-rc.sh'):
            with self.subTest(consumer=name):
                text = (ROOT / name).read_text()
                self.assertRegex(text, pattern,
                                 f'{name} must source the shared baseline')

    def test_no_context_redefines_the_shared_surface(self):
        for name in ('zsh/.zshrc', 'remote/generate-rc.sh', 'server/shell.sh'):
            with self.subTest(consumer=name):
                text = (ROOT / name).read_text()
                for snippet in ('alias ll=', 'alias mkdir=', 'memtop()', 'alias vim='):
                    self.assertNotIn(snippet, text,
                                     f'{name} must not duplicate {snippet}')

    def test_shared_prompt_matches_the_tmux_status_palette(self):
        shared = (ROOT / 'shared/shell/common.sh').read_text()
        tmux = (ROOT / 'shared/tmux/base.conf').read_text()
        for color in ('8ba4b0', 'c5c9c5'):
            self.assertIn(color, shared, 'the shared prompt must use the Kanagawa palette')
            self.assertIn(color, tmux, 'tmux status must use the same Kanagawa palette')


class SharedConfigBaselineTests(unittest.TestCase):
    """tmux and Neovim behave the same because both consume the shared base."""

    def test_both_tmux_configs_source_the_shared_baseline(self):
        for name in ('tmux/tmux.conf', 'server/tmux.conf'):
            with self.subTest(config=name):
                text = (ROOT / name).read_text()
                self.assertIn('source-file ~/.config/portillo-dots/tmux-base.conf', text)

    def test_shared_tmux_baseline_is_plugin_free(self):
        base = (ROOT / 'shared/tmux/base.conf').read_text()
        self.assertNotIn('@plugin', base, 'the baseline must not carry plugin stack')
        self.assertNotIn('tpm', base.lower(), 'the baseline must not boot a plugin manager')

    def test_both_nvim_consumers_load_the_shared_baseline(self):
        server = (ROOT / 'server/nvim/init.lua').read_text()
        self.assertIn('nvim-base.lua', server, 'the server profile layers nothing on the base')
        workstation = (ROOT / 'nvim/lua/config/options.lua').read_text()
        self.assertIn('nvim-base.lua', workstation, 'LazyVim must layer on the same base')
