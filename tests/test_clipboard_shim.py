import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHIM = ROOT / 'linux/clipboard-shim.sh'


class ClipboardShimTests(unittest.TestCase):
    def test_repairs_stale_environment_and_runs_real_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            shims, real = base / 'shims', base / 'real'
            runtime = base / 'run'
            for d in (shims, real, runtime):
                d.mkdir()
            auth = base / 'xauth'
            auth.write_text('cookie-never-printed')
            # Real tool reports the environment it received.
            tool = real / 'xclip'
            tool.write_text('#!/bin/sh\necho "$DISPLAY|$XAUTHORITY|$WAYLAND_DISPLAY|$*"\n')
            tool.chmod(0o755)
            pgrep = real / 'pgrep'
            pgrep.write_text(f'#!/bin/sh\necho "123 /usr/bin/Xwayland :7 -rootless -auth {auth} -listenfd 4"\n')
            pgrep.chmod(0o755)
            import socket
            sock = socket.socket(socket.AF_UNIX)
            sock.bind(str(runtime / 'wayland-9'))
            (shims / 'xclip').symlink_to(SHIM)
            env = {k: v for k, v in os.environ.items()
                   if k not in ('DISPLAY', 'XAUTHORITY', 'WAYLAND_DISPLAY', 'SSH_CONNECTION', 'SSH_TTY')}
            env.update(PATH=f'{shims}:{real}:{env["PATH"]}', XDG_RUNTIME_DIR=str(runtime), DISPLAY=':7',
                       XAUTHORITY=str(base / 'gone'))
            result = subprocess.run([str(shims / 'xclip'), '-o'], env=env, capture_output=True, text=True)
            sock.close()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), f':7|{auth}|wayland-9|-o')
            self.assertNotIn('cookie', result.stdout + result.stderr)

    def test_leaves_ssh_untouched(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            shims, real = base / 'shims', base / 'real'
            shims.mkdir(); real.mkdir()
            tool = real / 'xclip'
            tool.write_text('#!/bin/sh\necho "$DISPLAY"\n')
            tool.chmod(0o755)
            (shims / 'xclip').symlink_to(SHIM)
            env = dict(os.environ, PATH=f'{shims}:{real}:{os.environ["PATH"]}',
                       SSH_CONNECTION='a b c d', DISPLAY='localhost:10.0')
            result = subprocess.run([str(shims / 'xclip')], env=env, capture_output=True, text=True)
            self.assertEqual(result.stdout.strip(), 'localhost:10.0')


if __name__ == '__main__':
    unittest.main()
