"""Reproducible ShellCheck run.

Prefers a local `shellcheck`, then $SHELLCHECK_BIN, then a pinned release
download whose published SHA-256 is verified before it is executed. Skips with a
clear reason when neither is reachable, so the suite never fails just because a
developer is offline.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
import unittest

from _support import tempdir

ROOT = Path(__file__).resolve().parents[1]
PIN = 'v0.11.0'
ASSET = 'shellcheck-v0.11.0.linux.x86_64.tar.xz'
API = f'https://api.github.com/repos/koalaman/shellcheck/releases/tags/{PIN}'

SHELL_FILES = [
    'setup.sh',
    'installer/common.sh', 'installer/components.sh', 'installer/profiles.sh',
    'installer/workstation.sh', 'installer/opencode.sh',
    'installer/privileged.sh', 'installer/privileged-core.sh',
    'remote.sh', 'remote/lib.sh', 'remote/install-binaries.sh',
    'remote/shell-environment.sh', 'remote/generate-rc.sh', 'remote/connect.sh',
    'opencode/regenerate-config.sh', 'opencode/load-secrets.sh',
    'server/shell.sh', 'linux/graphical-environment.sh',
    'linux/optimize.sh', 'linux/dots-diag.sh', 'linux/dots-fix-tiling.sh',
    'linux/restore-gnome-keybindings.sh',
    'o-tiling/install.sh', 'o-tiling/configure.sh', 'o-tiling/verify.sh',
    'remote/generate-ls-colors.sh',
    'gnome/configure.sh',
]


def resolve_shellcheck():
    explicit = os.environ.get('SHELLCHECK_BIN')
    if explicit and Path(explicit).is_file():
        return explicit, 'env'
    found = shutil.which('shellcheck')
    if found:
        return found, 'path'
    # Linux x86_64 only: macOS ships arm64/x86_64 with different assets, so the
    # runner is expected to provide shellcheck via brew/apt instead.
    import platform as _platform
    if _platform.system() != 'Linux' or _platform.machine() not in ('x86_64', 'AMD64'):
        return None, 'unsupported-platform'
    try:
        request = urllib.request.Request(API, headers={'User-Agent': 'Portillo.Dots-ci'})
        with urllib.request.urlopen(request, timeout=30) as response:
            release = json.load(response)
        asset = next(a for a in release['assets'] if a['name'] == ASSET)
        with urllib.request.urlopen(asset['browser_download_url'], timeout=60) as response:
            data = response.read()
    except Exception as error:  # network or API unavailable
        return None, f'download-failed: {type(error).__name__}'
    expected = asset.get('digest') or ''
    if expected != 'sha256:' + hashlib.sha256(data).hexdigest():
        return None, 'digest-mismatch'
    with tempdir() as directory:
        archive = Path(directory) / ASSET
        archive.write_bytes(data)
        with tarfile.open(archive) as bundle:
            bundle.extractall(directory, filter='data')
        binary = Path(directory) / 'shellcheck-v0.11.0' / 'shellcheck'
        if not binary.is_file():
            return None, 'asset-layout'
        # Keep a copy outside the temporary directory so it survives.
        cache = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'portillo-dots' / 'shellcheck'
        cache.mkdir(parents=True, exist_ok=True)
        target = cache / 'shellcheck'
        shutil.copy2(binary, target)
        target.chmod(0o755)
        return str(target), 'downloaded'


class ShellCheckTests(unittest.TestCase):
    def test_shellcheck_reports_no_warnings_at_warning_severity(self):
        binary, source = resolve_shellcheck()
        if not binary:
            self.skipTest(f'shellcheck unavailable ({source}); '
                          'install it or set SHELLCHECK_BIN to run this test')
        missing = [name for name in SHELL_FILES if not (ROOT / name).is_file()]
        self.assertEqual(missing, [], 'the ShellCheck target list drifted from the repo')
        result = subprocess.run([binary, '--severity=warning', '-x',
                                 *[str(ROOT / name) for name in SHELL_FILES]],
                                capture_output=True, text=True, timeout=180)
        self.assertEqual(result.returncode, 0,
                         f'shellcheck via {source} reported:\n{result.stdout}\n{result.stderr}')

    def test_every_tracked_shell_file_is_covered_by_the_lint_target_list(self):
        tracked = [n for n in subprocess.check_output(
            ['git', '-C', str(ROOT), 'ls-files', '-z']).decode().split('\0')
            if n.endswith('.sh')]
        uncovered = [n for n in tracked if n not in SHELL_FILES]
        self.assertEqual(uncovered, [],
                         'add new shell files to SHELL_FILES so they are linted')
