import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
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

    @unittest.skipUnless(shutil.which('tmux'), 'tmux is needed to check modified-key forwarding')
    def test_shared_tmux_baseline_delivers_shift_enter_as_csi_u(self):
        # Pi requests modifyOtherKeys mode 2 and binds newLine to shift+enter:
        # the baseline must deliver S-Enter as CSI-u (ESC [ 13 ; 2 u) and a
        # plain Enter as CR, never collapsing both into CR (which submits).
        reader = '''import os, select, sys, termios, tty, time
tty.setraw(0)
# Publish readiness in the same output stream after requesting mode 2.
# pane_title works on tmux 3.3/3.4, unlike the newer pane_key_mode format.
os.write(2, b'\x1b[>4;2m\x1b]2;portillo-key-reader-ready\x07')
data = b''
end = time.time() + 8
while time.time() < end and not data:
    ready, _, _ = select.select([0], [], [], 0.2)
    if ready:
        data += os.read(0, 64)
        while True:
            more, _, _ = select.select([0], [], [], 0.15)
            if not more:
                break
            data += os.read(0, 64)
open(sys.argv[1], 'w').write(data.hex())
'''
        text = (ROOT / 'shared/tmux/base.conf').read_text()
        cases = [('S-Enter', '1b5b31333b3275'), ('Enter', '0d')]
        for key, expected in cases:
            with self.subTest(key=key), tempfile.TemporaryDirectory() as directory:
                base = Path(directory)
                socket = str(base / 'tmux.sock')
                reader_path = base / 'reader.py'
                reader_path.write_text(reader)
                received = base / 'received.hex'
                config = base / 'tmux.conf'
                config.write_text(text)
                env = {**os.environ, 'HOME': directory, 'XDG_CONFIG_HOME': directory,
                       'PATH': directory + ':' + os.environ['PATH']}
                for name in ['TMUX', 'ZDOTDIR', 'DISPLAY', 'WAYLAND_DISPLAY']:
                    env.pop(name, None)
                tmux = [shutil.which('tmux'), '-S', socket]
                try:
                    subprocess.run([*tmux, '-f', str(config), 'new-session', '-d', '-s', 'test',
                                    'python3', str(reader_path), str(received)],
                                   env=env, check=True, capture_output=True, text=True, timeout=10)
                    # The title marker proves tmux processed the preceding
                    # mode request; the received bytes below verify its effect.
                    deadline = time.time() + 10
                    mode = ''
                    while time.time() < deadline:
                        result = subprocess.run([*tmux, 'display-message', '-p', '-t', 'test',
                                                 '#{pane_title}'],
                                                env=env, capture_output=True, text=True, timeout=10)
                        mode = result.stdout.strip()
                        if mode == 'portillo-key-reader-ready':
                            break
                        time.sleep(0.1)
                    self.assertEqual(mode, 'portillo-key-reader-ready',
                                     'the pane reader must be ready before sending keys')
                    subprocess.run([*tmux, 'send-keys', '-t', 'test', key], env=env,
                                   check=True, capture_output=True, text=True, timeout=10)
                    deadline = time.time() + 10
                    while time.time() < deadline and not (received.exists() and received.read_text().strip()):
                        time.sleep(0.1)
                    self.assertTrue(received.exists(), f'pane received nothing for {key}')
                    self.assertEqual(received.read_text().strip(), expected,
                                     f'{key} must arrive as {expected} for Pi to split submit from newline')
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

    def test_shared_tmux_baseline_forwards_modified_keys(self):
        base = (ROOT / 'shared/tmux/base.conf').read_text()
        self.assertIn('set -s extended-keys on', base, 'apps must be able to request modified keys')
        self.assertNotIn('set -s extended-keys off', base, 'off collapses Shift+Enter into plain Enter')
        self.assertIn('extkeys', base, 'tmux must tell the outer terminal to report modified keys')
        self.assertIn('extended-keys-format csi-u', base, 'CSI-u is the format Pi parses most reliably')

    def test_alacritty_sends_shift_enter_as_csi_u(self):
        # Multiple aliases may match one physical key. Keep exactly one
        # Shift+Enter binding so the terminal cannot emit two newline events.
        for name in ('alacritty/alacritty.toml', 'alacritty/alacritty.macos.toml'):
            with self.subTest(config=name):
                text = (ROOT / name).read_text()
                bindings = [line for line in text.splitlines()
                            if re.search(r'key = "(?:Enter|Return)"', line) and 'mods = "Shift"' in line]
                self.assertEqual(len(bindings), 1,
                                 f'{name} must not bind Shift+Enter more than once: {bindings}')
                self.assertIn(r'\u001b[13;2u', bindings[0],
                              f'{name} must emit CSI-u Shift+Enter, not ESC CR: {bindings[0]}')

    def test_both_nvim_consumers_load_the_shared_baseline(self):
        server = (ROOT / 'server/nvim/init.lua').read_text()
        self.assertIn('require("config.lazy")', server, 'legacy server init must use the shared editor')
        workstation = (ROOT / 'nvim/lua/config/options.lua').read_text()
        self.assertIn('nvim-base.lua', workstation, 'LazyVim must layer on the same base')


class PhysicalConsolePromptTests(unittest.TestCase):
    def test_kernel_console_uses_ascii_fallback_and_skips_p10k_glyphs(self):
        text = (ROOT / 'zsh/.zshrc').read_text()
        self.assertIn('"${TERM:-}" != linux', text,
                      'instant prompt must not print Nerd Font glyphs on tty')
        self.assertIn('ZSH_THEME=""', text,
                      'Powerlevel10k must not initialize in the kernel console')
        self.assertIn("PROMPT='%F{cyan}%n@%m%f:%F{white}%~%f %D{%H:%M:%S} %# '", text)
        self.assertIn('[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh', text)


class OptionalTmuxVisualOverlayTests(unittest.TestCase):
    def test_server_overlay_is_shared_and_has_no_services(self):
        overlay = (ROOT / 'shared/tmux/visual.conf').read_text()
        server = (ROOT / 'server/tmux.conf').read_text()
        for setting in ("set -g @plugin 'Nybkox/tmux-kanagawa'",
                        "set -g @kanagawa-plugins 'git cpu-usage ram-usage'"):
            self.assertIn(setting, overlay)
        active = '\n'.join(line for line in overlay.splitlines()
                             if not line.lstrip().startswith('#')).lower()
        for forbidden in ('continuum', 'resurrect', 'systemd', 'tmux.service', '@continuum-boot'):
            self.assertNotIn(forbidden, active,
                             f'the server visual overlay must not enable {forbidden}')
        self.assertIn('source-file ~/.config/portillo-dots/tmux-visual.conf', server)
        self.assertNotIn('if-shell', server)
