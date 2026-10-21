"""Performance guards.

These assert structure rather than wall-clock timing, so they stay stable on a
loaded CI runner: they count subprocess launches and cache hits, which is what
the optimisations actually change.
"""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from _support import tempdir
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which('bash')

COREUTILS = ['awk', 'basename', 'cat', 'chmod', 'dirname', 'env', 'find', 'grep',
             'head', 'id', 'ln', 'mkdir', 'mktemp', 'readlink', 'rm', 'sed',
             'sort', 'stat', 'touch', 'tr', 'cut', 'uname', 'wc', 'xargs']


class ToolVersionCacheTests(unittest.TestCase):
    def make_tool(self, directory, name, version, counter):
        tool = Path(directory) / 'bin' / name
        tool.parent.mkdir(parents=True, exist_ok=True)
        tool.write_text(f'#!/bin/sh\necho ran >> "{counter}"\necho "{name} {version}"\n')
        tool.chmod(0o755)
        return tool

    def run_version(self, directory, name, env_extra=None):
        env = {**os.environ, 'HOME': str(Path(directory) / 'home'),
               'XDG_CACHE_HOME': str(Path(directory) / 'cache'),
               'PATH': f'{Path(directory) / "bin"}:{os.environ["PATH"]}'}
        env.update(env_extra or {})
        script = ('source "$1/installer/components.sh"; source "$1/installer/common.sh"; '
                  'tool_version "$2"')
        return subprocess.run([BASH, '-euc', script, '_', str(ROOT), name],
                              env=env, capture_output=True, text=True, timeout=20)

    def test_repeat_queries_hit_the_cache_instead_of_spawning_the_tool(self):
        with tempdir() as directory:
            counter = Path(directory) / 'invocations'
            counter.write_text('')
            self.make_tool(directory, 'slowtool', '2.0.32', counter)
            first = self.run_version(directory, 'slowtool')
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(first.stdout.strip(), '2.0.32')
            self.assertEqual(counter.read_text().count('ran'), 1)

            for _ in range(4):
                repeat = self.run_version(directory, 'slowtool')
                self.assertEqual(repeat.stdout.strip(), '2.0.32')
            self.assertEqual(counter.read_text().count('ran'), 1,
                             'a cached version must not spawn the tool again')

    def test_changing_the_executable_invalidates_the_entry(self):
        with tempdir() as directory:
            counter = Path(directory) / 'invocations'
            counter.write_text('')
            tool = self.make_tool(directory, 'slowtool', '1.0.0', counter)
            self.assertEqual(self.run_version(directory, 'slowtool').stdout.strip(), '1.0.0')
            # Rewrite with a different size and mtime: the key must change.
            import time
            time.sleep(1.1)
            tool.write_text('#!/bin/sh\necho ran >> "%s"\necho "slowtool 3.0.0"\n' % counter)
            tool.chmod(0o755)
            self.assertEqual(self.run_version(directory, 'slowtool').stdout.strip(), '3.0.0')
            self.assertEqual(counter.read_text().count('ran'), 2)

    def test_cache_is_not_created_when_the_tool_reports_no_version(self):
        with tempdir() as directory:
            counter = Path(directory) / 'invocations'
            counter.write_text('')
            tool = Path(directory) / 'bin' / 'quiet'
            tool.parent.mkdir(parents=True, exist_ok=True)
            tool.write_text('#!/bin/sh\necho ran >> "%s"\nexit 0\n' % counter)
            tool.chmod(0o755)
            result = self.run_version(directory, 'quiet')
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((Path(directory) / 'cache/portillo-dots/tool-versions.tsv').exists())

    def test_cache_holds_no_credential_material(self):
        with tempdir() as directory:
            counter = Path(directory) / 'invocations'
            counter.write_text('')
            self.make_tool(directory, 'slowtool', '2.0.32', counter)
            self.run_version(directory, 'slowtool')
            cache = Path(directory) / 'cache/portillo-dots/tool-versions.tsv'
            self.assertTrue(cache.is_file())
            self.assertEqual(cache.stat().st_mode & 0o777, 0o600)
            text = cache.read_text()
            self.assertIn('2.0.32', text)
            self.assertNotIn('KEY', text)
            self.assertNotIn('SECRET', text)


class PackageManagerBatchingTests(unittest.TestCase):
    def brew_env(self, directory):
        home = Path(directory) / 'home'
        home.mkdir(exist_ok=True)
        stubs = Path(directory) / 'bin'
        stubs.mkdir(exist_ok=True)
        calls = Path(directory) / 'calls'
        calls.write_text('')
        brew = stubs / 'brew'
        brew.write_text(f'''#!{sys.executable}
import sys
with open({str(calls)!r}, "a") as out:
    out.write(" ".join(sys.argv) + "\\n")
if sys.argv[1:3] == ["list", "--versions"]:
    for name in ("git", "curl", "tmux", "neovim", "python"):
        print(name + " 1.0")
raise SystemExit(0)
''')
        brew.chmod(0o755)
        return home, stubs, calls

    def test_brew_queries_the_package_set_once_not_once_per_package(self):
        with tempdir() as directory:
            home, stubs, calls = self.brew_env(directory)
            script = '''
                source "$1/setup.sh"
                PROFILE=workstation; PLATFORM=mac; ARCH=aarch64; UPGRADE=false
                LOG="$HOME/log"; CONFIG_HOME="$HOME/.config"
                # macos-latest has a real Homebrew at /opt/homebrew. Keep this
                # package batching unit test hermetic and exercise only its stub.
                homebrew_prefix() { printf '%s\\n' "$HOME/fake-homebrew"; }
                install_brew_tools
            '''
            env = {**os.environ, 'HOME': str(home), 'PATH': f'{stubs}:/usr/bin:/bin',
                   'XDG_STATE_HOME': str(home / '.state')}
            try:
                result = subprocess.run([BASH, '-euc', script, '_', str(ROOT)],
                                        env=env, capture_output=True, text=True, timeout=30)
            except subprocess.TimeoutExpired as error:
                stdout = error.stdout.decode(errors='replace') if isinstance(error.stdout, bytes) else (error.stdout or '')
                stderr = error.stderr.decode(errors='replace') if isinstance(error.stderr, bytes) else (error.stderr or '')
                self.fail(f'brew batching test timed out; child output:\n{stdout}\n{stderr}')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            lines = [l for l in calls.read_text().splitlines() if l.strip()]
            list_calls = [l for l in lines if 'brew list' in l]
            self.assertEqual(len(list_calls), 1,
                             'one bulk query, not one invocation per package:\n' + '\n'.join(lines))
            install_calls = [l for l in lines if 'brew install' in l]
            # Only the packages absent from the bulk listing are installed.
            self.assertTrue(install_calls)
            self.assertLess(len(install_calls), 20)

    def test_rustup_target_list_is_queried_once_per_run(self):
        with tempdir() as directory:
            home = Path(directory) / 'home'
            stubs = Path(directory) / 'bin'
            stubs.mkdir(parents=True)
            calls = Path(directory) / 'calls'
            calls.write_text('')
            stub = f'''#!{sys.executable}
import sys, os
name = os.path.basename(sys.argv[0])
with open({str(calls)!r}, "a") as out:
    out.write(name + " " + " ".join(sys.argv[1:]) + "\\n")
if name == "fnm" and sys.argv[1] == "env": print(":")
if name == "uv" and sys.argv[1:] == ["tool", "list"]: print("markitdown v1")
if name == "rustup" and sys.argv[1:3] == ["target", "list"]: print("wasm32-wasip1")
if name == "brew" and sys.argv[1] == "list": sys.exit(1)
raise SystemExit(0)
'''
            for name in ['fnm', 'node', 'npm', 'pnpm', 'rustup', 'uv', 'claude', 'brew',
                         'fc-match', 'git', 'python3']:
                path = stubs / name
                path.write_text(stub)
                path.chmod(0o755)
            (home / '.sdkman/bin/sdkman-init.sh').parent.mkdir(parents=True)
            (home / '.sdkman/bin/sdkman-init.sh').write_text('# installed\n')
            (home / '.oh-my-zsh').mkdir()
            script = '''
                source "$1/setup.sh"; PLATFORM=mac; UPGRADE=false; LOG="$HOME/log"
                sync_git_dependency() { return 0; }
                install_fonts() { return 0; }
                run_installer() { return 0; }
                install_workstation
            '''
            env = {**os.environ, 'HOME': str(home), 'PATH': f'{stubs}:/usr/bin:/bin',
                   'XDG_STATE_HOME': str(home / '.state'), 'MOCK_CALLS': str(calls)}
            result = subprocess.run([BASH, '-euc', script, '_', str(ROOT)],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            log = calls.read_text()
            self.assertEqual(log.count('rustup target list'), 1,
                             'the installed-target list is queried once, then both targets are checked against it')


class SinglePassVerificationTests(unittest.TestCase):
    def test_opencode_checks_use_one_python_invocation(self):
        with tempdir() as directory:
            home = Path(directory) / 'home'
            home.mkdir()
            config = home / '.config/opencode'
            config.mkdir(parents=True)
            (config / 'opencode.jsonc').write_text(
                '{"permissions":[{"action":"shell","resource":"*","effect":"ask"},'
                '{"action":"edit","resource":"*","effect":"ask"}]}\n')
            for name, source in [('.dircolors', 'zsh/.dircolors'), ('.tmux.conf', 'server/tmux.conf'),
                                 ('.zshrc', 'zsh/.zshrc'), ('.p10k.zsh', 'zsh/p10k.zsh'),
                                 ('.config/portillo-dots/shell-common.sh', 'shared/shell/common.sh'),
                                 ('.config/portillo-dots/tmux-base.conf', 'shared/tmux/base.conf'),
                                 ('.config/portillo-dots/nvim-base.lua', 'shared/nvim/base.lua')]:
                link = home / name
                link.parent.mkdir(parents=True, exist_ok=True)
                link.symlink_to(ROOT / source)
            nvim = home / '.config/nvim'
            nvim.mkdir(parents=True, exist_ok=True)
            for name in ('init.lua', 'lua', 'lazy-lock.json', 'lazyvim.json', 'stylua.toml', '.gitignore', '.neoconf.json', 'db_ui'):
                (nvim / name).symlink_to(ROOT / 'nvim' / name)
            shared = home / '.config/portillo-dots'
            (shared / 'tmux-visual.conf').symlink_to(ROOT / 'shared/tmux/visual.conf')
            (shared / 'tmux-visual-enabled').symlink_to(ROOT / 'shared/tmux/visual-enabled')
            wrappers = Path(directory) / 'bin'
            wrappers.mkdir()
            log = Path(directory) / 'python-calls'
            log.write_text('')
            python = wrappers / 'python3'
            python.write_text(f'''#!/bin/sh
echo "$*" >> "{log}"
exec {sys.executable!r} "$@"
''')
            python.chmod(0o755)
            for name in COREUTILS:
                target = shutil.which(name)
                if target:
                    (wrappers / name).symlink_to(target)
            script = '''
                source "$1/setup.sh"
                PROFILE=server; PLATFORM=linux; CONFIG_HOME="$HOME/.config"
                verify_configs
            '''
            env = {**os.environ, 'HOME': str(home), 'PATH': str(wrappers),
                   'XDG_STATE_HOME': str(home / '.state'), 'SHELL': '/bin/bash'}
            result = subprocess.run([BASH, '-euc', script, '_', str(ROOT)],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            calls = [l for l in log.read_text().splitlines() if 'check-config.py' in l]
            self.assertEqual(len(calls), 1,
                             'shape, baseline, secrets and MCP deps must share one process:\n'
                             + log.read_text())


class ShellStartupTests(unittest.TestCase):
    def test_graphical_helper_is_skipped_outside_tmux(self):
        # The gate lives in zsh/.zshrc: the helper itself always queries the
        # session manager, so what must not run outside tmux is the whole block.
        zshrc = (ROOT / 'zsh/.zshrc').read_text()
        start = zshrc.index('if [[ -n "${TMUX:-}"')
        end = zshrc.index('unset _portillo_graphical_helper', start)
        end = zshrc.index('fi', end) + 2
        block = zshrc[start:end]
        with tempdir() as directory:
            stubs = Path(directory) / 'bin'
            stubs.mkdir()
            marker = Path(directory) / 'called'
            marker.write_text('')
            systemctl = stubs / 'systemctl'
            systemctl.write_text(f'#!/bin/sh\necho called >> "{marker}"\nexit 0\n')
            systemctl.chmod(0o755)
            helper = ROOT / 'linux/graphical-environment.sh'

            zsh = shutil.which('zsh')
            if not zsh:
                self.skipTest('zsh is required to exercise the .zshrc startup block')
            # The block resolves the helper relative to the script (%N), so lay
            # the script out like the real repo: <root>/zsh/x.zsh + <root>/linux/.
            fake_root = Path(directory) / 'repo'
            (fake_root / 'zsh').mkdir(parents=True)
            (fake_root / 'linux').mkdir()
            (fake_root / 'linux/graphical-environment.sh').write_text(helper.read_text())

            def run(tmux):
                env = {**os.environ, 'PATH': f'{stubs}:/usr/bin:/bin', 'HOME': directory}
                for key in ['TMUX', 'SSH_CONNECTION', 'SSH_TTY']:
                    env.pop(key, None)
                if tmux:
                    env['TMUX'] = '/tmp/tmux-1000/default,1,1'
                script = fake_root / 'zsh' / ('inside.zsh' if tmux else 'outside.zsh')
                script.write_text(f'{block}\necho ok\n')
                return subprocess.run([zsh, '-f', str(script)], env=env,
                                      capture_output=True, text=True, timeout=20)

            outside = run(tmux=False)
            self.assertEqual(outside.returncode, 0, outside.stderr)
            self.assertEqual(outside.stdout, 'ok\n')
            self.assertEqual(marker.read_text(), '',
                             'outside tmux no session lookup may run at shell startup')

            inside = run(tmux=True)
            self.assertEqual(inside.returncode, 0, inside.stderr)
            self.assertIn('called', marker.read_text(),
                          'inside tmux the session lookup is expected to run once')

    def test_secrets_loader_runs_no_subprocess_when_absent(self):
        with tempdir() as directory:
            stubs = Path(directory) / 'bin'
            stubs.mkdir()
            marker = Path(directory) / 'called'
            marker.write_text('')
            for name in ['stat', 'cat', 'awk']:
                real = shutil.which(name)
                if real:
                    wrap = stubs / name
                    wrap.write_text(f'#!/bin/sh\necho {name} >> "{marker}"\nexec "{real}" "$@"\n')
                    wrap.chmod(0o755)
            env = {**os.environ, 'HOME': directory,
                   'XDG_CONFIG_HOME': str(Path(directory) / '.config'),
                   'PATH': f'{stubs}:/usr/bin:/bin'}
            result = subprocess.run([BASH, '-c', f'. "{ROOT}/opencode/load-secrets.sh"; echo ok'],
                                    env=env, capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, 'ok\n')
            self.assertEqual(marker.read_text(), '',
                             'a missing secrets file must not spawn any helper process')


if __name__ == '__main__':
    unittest.main()
