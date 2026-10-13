import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('manifest', ROOT / 'remote/deploy-manifest.py')
manifest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manifest)


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


if __name__ == '__main__':
    unittest.main()
