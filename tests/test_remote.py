import importlib.util
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import tarfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('manifest', ROOT / 'remote/deploy-manifest.py')
manifest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manifest)
integrity_spec = importlib.util.spec_from_file_location('integrity', ROOT / 'remote/verify-downloads.py')
integrity = importlib.util.module_from_spec(integrity_spec)
integrity_spec.loader.exec_module(integrity)


class RemoteTests(unittest.TestCase):
    def create_repo(self, directory):
        repo = Path(directory)
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)
        for name in manifest.EXACT | {'nvim/lua/config/options.lua'}:
            path = repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('runtime\n')
        subprocess.run(['git', '-C', str(repo), 'add', '.'], check=True)
        return repo

    def test_allowlist_excludes_local_and_tracked_secrets(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.create_repo(directory)
            secrets = ['opencode/.env', 'opencode/opencode.jsonc', '.claude/settings.local.json',
                       'logs/setup.log', 'nvim/db_ui/connections.lua', 'nvim/lua/db_ui/connections.lua']
            for name in secrets:
                path = repo / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('fake-secret\n')
            subprocess.run(['git', '-C', str(repo), 'add', '.'], check=True)
            files = manifest.manifest(repo)
            self.assertTrue(manifest.EXACT.issubset(files))
            self.assertFalse(set(secrets) & set(files))
            self.assertNotIn('linux/optimize.sh', files)

    def test_refuses_symlinked_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.create_repo(directory)
            path = repo / 'nvim/init.lua'
            path.unlink()
            path.symlink_to(repo / 'nvim/lazyvim.json')
            with self.assertRaises(ValueError):
                manifest.manifest(repo)

    def test_remote_platform_drives_cache_and_downloads(self):
        with tempfile.TemporaryDirectory() as directory:
            script = '''
                source "$1/remote.sh"
                ssh_cmd() { case "$*" in 'uname -s') echo Linux ;; 'uname -m') echo aarch64 ;; *) cat >/dev/null ;; esac; }
                download_binaries_locally() { printf 'arch=%s cache=%s\\n' "$REMOTE_ARCH" "$1"; }
                python3() { return 0; }
                rsync_cmd() { return 0; }
                deploy_binaries
            '''
            result = subprocess.run(['bash', '-euc', script, '_', str(ROOT)],
                                    env={**os.environ, 'HOME': directory, 'XDG_CACHE_HOME': directory + '/cache'},
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('arch=aarch64', result.stdout)
            self.assertIn('/linux-aarch64', result.stdout)

    def test_path_menu_returns_only_the_selected_path(self):
        script = '''source "$1/remote.sh";
            load_host_config() { printf 'host|/path one|local\\nhost|/path two|local\\n'; }
            get_host_path host'''
        result = subprocess.run(['bash', '-euc', script, '_', str(ROOT)], input='2\n', capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '/path two\n')

    def test_neovim_preserves_runtime_and_skips_reextracting(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            downloads = home / '.portillo-remote/downloads'
            downloads.mkdir(parents=True)
            with tarfile.open(downloads / 'nvim.tar.gz', 'w:gz') as archive:
                for name, body, mode in [('bin/nvim', b'#!/bin/sh\necho NVIM-v0.11.0\n', 0o755),
                                         ('share/nvim/runtime/filetype.lua', b'-- keep runtime\n', 0o644)]:
                    member = tarfile.TarInfo('nvim-linux-arm64/' + name)
                    member.size, member.mode = len(body), mode
                    archive.addfile(member, io.BytesIO(body))
            script = '''
                export PORTILLO_INSTALLER_LIBRARY=1
                source "$1/remote/install-binaries.sh"
                mkdir -p "$REMOTE_BIN"
                install_neovim
                install_neovim
            '''
            result = subprocess.run(['bash', '-euc', script, '_', str(ROOT)],
                                    env={**os.environ, 'HOME': directory}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((home / '.portillo-remote/nvim-runtime/share/nvim/runtime/filetype.lua').exists())
            self.assertIn('extraction skipped', result.stdout)

    def test_cached_integrity_detects_corruption_without_network(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            pins = {}
            for name in integrity.FILES:
                path = cache / name
                path.write_bytes(b'cached bytes')
                pins[name] = {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'version': 'test'}
            (cache / '.integrity.json').write_text(json.dumps(pins))
            with patch.object(integrity, 'fetch', side_effect=AssertionError('No network expected')):
                with patch('builtins.print'):
                    integrity.verify(cache, 'aarch64')
                    (cache / 'node.tar.xz').write_bytes(b'corrupt')
                    with self.assertRaises(ValueError):
                        integrity.verify(cache, 'aarch64')

    def test_rejects_archive_traversal_and_escape_links(self):
        with self.assertRaises(ValueError):
            integrity.safe_member('../outside')
        with self.assertRaises(ValueError):
            integrity.safe_member('package/bin/tool', '../../../outside')
        integrity.safe_member('package/bin/npm', '../lib/node_modules/npm/bin/npm-cli.js')

    def test_path_deletion_is_literal_and_preserves_other_hosts(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'hosts.local.conf'
            config.write_text('host.2=/path[one]\nhostX2=/path[one]\nhost.2=/another\n')
            script = '''source "$1/remote.sh"; HOSTS_LOCAL_CONF="$2"; FORCE=1;
                delete_host_path host.2 '/path[one]'; save_host_path host.2 /another'''
            result = subprocess.run(['bash', '-euc', script, '_', str(ROOT), str(config)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(config.read_text(), 'hostX2=/path[one]\nhost.2=/another\n')


class RuntimeToolsetTests(unittest.TestCase):
    def test_runtime_toolset_comes_from_the_catalog(self):
        script = 'source "$1/installer/components.sh"; remote_runtime_components'
        result = subprocess.run(['bash', '-euc', script, '_', str(ROOT)],
                                capture_output=True, text=True, check=True)
        required = [line.split()[1] for line in result.stdout.splitlines()
                    if line.startswith('required ')]
        self.assertEqual(required, ['nvim', 'rg', 'fd', 'fzf', 'lazygit', 'node', 'npm', 'stylua'])
        for path in (ROOT / 'remote.sh', ROOT / 'remote/install-binaries.sh'):
            text = path.read_text()
            self.assertNotIn('for bin in nvim rg', text)
            self.assertNotIn('for binary in nvim rg', text)
            self.assertIn('PORTILLO_RUNTIME_BINS', text,
                          f'{path.name} must take the toolset from the catalog')


if __name__ == '__main__':
    unittest.main()
