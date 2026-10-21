"""Shared terminal identity, migrations and bounded/offline editor checks."""
import json
import re
import os
from pathlib import Path
import shutil
import subprocess
import unittest

from _support import tempdir

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which('bash')


class TerminalIdentityTests(unittest.TestCase):
    def test_server_and_workstation_have_the_same_interactive_tmux_plugins(self):
        def plugins(path):
            return set(re.findall(r"set -g @plugin '([^']+)'", path.read_text()))
        workstation = plugins(ROOT / 'tmux/tmux.conf')
        server = plugins(ROOT / 'shared/tmux/visual.conf')
        self.assertEqual(server, workstation - {'tmux-plugins/tmux-resurrect', 'tmux-plugins/tmux-continuum'})

    def environment(self, home):
        return {**os.environ, 'HOME': str(home), 'XDG_CONFIG_HOME': str(home / 'config'),
                'XDG_STATE_HOME': str(home / 'state'), 'XDG_DATA_HOME': str(home / 'data'),
                'XDG_CACHE_HOME': str(home / 'cache'), 'SHELL': '/bin/bash'}

    def run_shell(self, script, env):
        return subprocess.run([BASH, '-euc', 'source "$1/setup.sh"\nCONFIG_HOME="$XDG_CONFIG_HOME"\n' + script, '_', str(ROOT)],
                              env=env, capture_output=True, text=True, timeout=30)

    def test_profiles_deploy_identical_editor_and_theme_idempotently(self):
        with tempdir() as directory:
            home = Path(directory)
            env = self.environment(home)
            script = '''
                CONFIG_ONLY=true; PLATFORM=linux
                trap cleanup_setup EXIT
                configure_opencode() { return 0; }
                secure_known_secrets() { return 0; }
                configure_workstation() { symlink_file "$REPO_DIR/tmux/tmux.conf" "$HOME/.tmux.conf"; }
                for PROFILE in server workstation server server; do
                    initialize_state; configure_profile; cleanup_setup
                done
            '''
            result = self.run_shell(script, env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            config = home / 'config'
            for name in ('init.lua', 'lua', 'lazy-lock.json', 'lazyvim.json', 'db_ui'):
                self.assertEqual((config / 'nvim' / name).resolve(), ROOT / 'nvim' / name)
            self.assertEqual((config / 'portillo-dots/tmux-visual.conf').resolve(),
                             ROOT / 'shared/tmux/visual.conf')
            self.assertEqual((home / '.tmux.conf').resolve(), ROOT / 'server/tmux.conf')
            self.assertFalse((home / 'data').exists(), 'config-only must not bootstrap plugins')

    def test_migration_backs_up_old_directory_symlink_without_writing_through_it(self):
        with tempdir() as directory:
            home = Path(directory)
            previous = home / 'previous'
            previous.mkdir()
            (previous / 'init.lua').write_text('-- personal config\n')
            (home / 'config').mkdir()
            (home / 'config/nvim').symlink_to(previous)
            result = self.run_shell('''
                initialize_state; trap cleanup_setup EXIT
                configure_nvim; configure_nvim
            ''', self.environment(home))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual((previous / 'init.lua').read_text(), '-- personal config\n')
            backups = list((home / 'state').rglob('nvim'))
            self.assertTrue(any(path.is_symlink() and path.resolve() == previous for path in backups))
            self.assertEqual((home / 'config/nvim/init.lua').resolve(), ROOT / 'nvim/init.lua')

    def fake_editor(self, home):
        binary = home / 'bin/nvim'
        binary.parent.mkdir()
        binary.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
assert os.environ['NVIM_APPNAME'] == 'nvim'
lock = pathlib.Path(os.environ['PORTILLO_NVIM_LOCKFILE'])
assert not lock.is_symlink()
with open(os.environ['CALLS'], 'a') as out:
    out.write(json.dumps(sys.argv[1:]) + '\\n')
if os.environ['PORTILLO_NVIM_CHECK'] == '0':
    lock.write_text('{}')  # simulate lazy.nvim rewriting its working lockfile
    pathlib.Path(os.environ['PORTILLO_NVIM_RECEIPT']).write_text('{"plugins":{}}')
sys.exit(int(os.environ.get('EDITOR_EXIT', '0')))
''')
        binary.chmod(0o755)
        env = self.environment(home)
        env.update(PATH=f'{binary.parent}:{env["PATH"]}', CALLS=str(home / 'calls'),
                   NVIM_APPNAME='portillo-remote/nvim')
        return env

    def test_provision_uses_working_lock_and_check_never_runs_plugin_startup(self):
        with tempdir() as directory:
            home = Path(directory)
            env = self.fake_editor(home)
            original = (ROOT / 'nvim/lazy-lock.json').read_bytes()
            result = self.run_shell('''
                CONFIG_HOME="$XDG_CONFIG_HOME"
                initialize_state; trap cleanup_setup EXIT
                configure_nvim
                mkdir -p "$CONFIG_HOME/portillo-dots"
                symlink_file "$REPO_DIR/shared/nvim/base.lua" "$CONFIG_HOME/portillo-dots/nvim-base.lua"
                run_managed_nvim install
                run_managed_nvim check
            ''', env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            calls = [json.loads(line) for line in (home / 'calls').read_text().splitlines()]
            self.assertIn('+Lazy! restore', calls[0])
            self.assertNotIn('+Lazy! restore', calls[1])
            self.assertIn('NONE', calls[1])
            self.assertEqual((ROOT / 'nvim/lazy-lock.json').read_bytes(), original)
            self.assertTrue((home / 'state/portillo-dots/nvim-identity.json').is_file())

    def test_missing_receipt_fails_offline_without_launching_editor(self):
        with tempdir() as directory:
            home = Path(directory)
            env = self.fake_editor(home)
            result = self.run_shell('''
                initialize_state; trap cleanup_setup EXIT
                configure_nvim
                run_managed_nvim check
            ''', env)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((home / 'calls').exists())

    def test_editor_failure_propagates_and_never_creates_success_receipt(self):
        with tempdir() as directory:
            home = Path(directory)
            env = self.fake_editor(home)
            env['EDITOR_EXIT'] = '7'
            result = self.run_shell('''
                initialize_state; trap cleanup_setup EXIT
                configure_nvim
                run_managed_nvim install
            ''', env)
            self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
            self.assertFalse((home / 'state/portillo-dots/nvim-identity.json').exists())


@unittest.skipUnless(shutil.which('nvim') and shutil.which('git'), 'Neovim and Git required')
class OfflineEditorHealthTests(unittest.TestCase):
    def fixture(self, home):
        plugins = home / 'data/nvim/lazy'
        receipt = {'plugins': {}}
        for name in ('LazyVim', 'kanagawa'):
            directory = plugins / name
            directory.mkdir(parents=True)
            if name == 'kanagawa':
                (directory / 'colors').mkdir()
                (directory / 'colors/kanagawa-dragon.lua').write_text(
                    'vim.g.colors_name="kanagawa"; package.loaded.kanagawa={_CURRENT_THEME="dragon"}\n')
            subprocess.run(['git', 'init', '-q', str(directory)], check=True)
            subprocess.run(['git', '-C', str(directory), 'add', '.'], check=True)
            subprocess.run(['git', '-C', str(directory), '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                            'commit', '-qm', 'fixture', '--allow-empty'], check=True)
            commit = subprocess.check_output(['git', '-C', str(directory), 'rev-parse', 'HEAD'], text=True).strip()
            receipt['plugins'][name] = {'dir': str(directory), 'commit': commit}
        path = home / 'receipt.json'
        path.write_text(json.dumps(receipt))
        return path, plugins

    def check_health(self, home, receipt):
        env = {**os.environ, 'HOME': str(home), 'XDG_CONFIG_HOME': str(home / 'config'),
               'XDG_DATA_HOME': str(home / 'data'), 'XDG_STATE_HOME': str(home / 'state'),
               'XDG_CACHE_HOME': str(home / 'cache'), 'NVIM_APPNAME': 'nvim',
               'PORTILLO_NVIM_CHECK': '1', 'PORTILLO_NVIM_RECEIPT': str(receipt),
               'PORTILLO_NVIM_HEALTH': str(ROOT / 'installer/nvim-health.lua')}
        return subprocess.run(['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-n',
                               '+lua dofile(vim.env.PORTILLO_NVIM_HEALTH)', '+qa!'],
                              env=env, capture_output=True, text=True, timeout=30)

    def test_real_neovim_offline_health_checks_theme_and_git_revisions(self):
        with tempdir() as directory:
            home = Path(directory)
            receipt, _ = self.fixture(home)
            result = self.check_health(home, receipt)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_real_neovim_rejects_missing_plugin(self):
        with tempdir() as directory:
            home = Path(directory)
            receipt, plugins = self.fixture(home)
            (plugins / 'LazyVim/.git').rename(plugins / 'LazyVim/git-hidden')
            result = self.check_health(home, receipt)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Plugin differs from lockfile or is missing: LazyVim', result.stderr)

    def test_real_neovim_rejects_changed_revision(self):
        with tempdir() as directory:
            home = Path(directory)
            receipt, _ = self.fixture(home)
            data = json.loads(receipt.read_text())
            data['plugins']['LazyVim']['commit'] = '0' * 40
            receipt.write_text(json.dumps(data))
            result = self.check_health(home, receipt)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Plugin differs from lockfile', result.stderr)
