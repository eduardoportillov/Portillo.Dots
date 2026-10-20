import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which('bash')

# Build a PATH that is complete enough to run the installer but cannot leak real
# tools whose presence/absence the test is asserting.
SYSTEM_TOOLS = [
    'awk', 'basename', 'cat', 'chmod', 'chown', 'cp', 'cut', 'date', 'dirname',
    'env', 'expr', 'find', 'grep', 'head', 'id', 'ln', 'ls', 'mkdir', 'mktemp',
    'mv', 'printf', 'readlink', 'realpath', 'rm', 'sed', 'sort', 'stat', 'tail',
    'test', 'touch', 'tr', 'uname', 'uniq', 'wc', 'xargs',
]


def controlled_path(directory, stubs, exclude=(), extra=()):
    core = Path(directory) / 'coreutils'
    core.mkdir(exist_ok=True)
    for name in SYSTEM_TOOLS:
        if name in exclude:
            continue
        target = shutil.which(name)
        if target:
            (core / name).symlink_to(target)
    for name in extra:
        target = shutil.which(name)
        if target:
            (core / name).symlink_to(target)
    return f'{stubs}:{core}'



class PlatformPathTests(unittest.TestCase):
    def test_homebrew_prefix_matches_documented_locations(self):
        for platform, arch, expected in [
            ('mac', 'aarch64', '/opt/homebrew'),
            ('mac', 'x86_64', '/usr/local'),
            ('linux', 'x86_64', '/home/linuxbrew/.linuxbrew'),
            ('linux', 'aarch64', '/home/linuxbrew/.linuxbrew'),
        ]:
            with self.subTest(platform=platform, arch=arch):
                script = 'source "$1/installer/components.sh"; homebrew_prefix "$2" "$3"'
                result = subprocess.run([BASH, '-euc', script, '_', str(ROOT), platform, arch],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected)

    def test_homebrew_prefix_rejects_unknown_platform(self):
        script = 'source "$1/installer/components.sh"; homebrew_prefix plan9 x86_64'
        result = subprocess.run([BASH, '-euc', script, '_', str(ROOT)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')

    def test_macos_install_requires_preinstalled_homebrew(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            mocks = home / 'bin'
            mocks.mkdir()
            for name in ['uname', 'xcode-select', 'brew']:
                stub = mocks / name
                if name == 'uname':
                    stub.write_text('#!/bin/sh\ncase "$1" in -s) echo Darwin ;; -m) echo arm64 ;; *) echo Darwin ;; esac\n')
                elif name == 'xcode-select':
                    stub.write_text('#!/bin/sh\nexit 0\n')
                else:
                    # A brew that exists but is not on PATH in the child: remove it later.
                    stub.write_text('#!/bin/sh\nexit 0\n')
                stub.chmod(0o755)
            (mocks / 'brew').unlink()  # simulate "Homebrew is not installed"
            script = ('source "$1/setup.sh"; PROFILE=workstation; PACKAGE_MANAGER=brew; '
                      'CONFIG_ONLY=false; UPGRADE=false; HARDWARE=false; CHANGE_SHELL=false; '
                      'PLATFORM=mac; ARCH=aarch64; WORK_DIR="$HOME/work"; LOG="$HOME/log"; '
                      'mkdir -p "$WORK_DIR"; install_brew_tools')
            env = {**os.environ, 'HOME': str(home), 'PATH': str(mocks) + ':/usr/bin:/bin',
                   'XDG_STATE_HOME': str(home / '.state')}
            result = subprocess.run([BASH, '-euc', script, '_', str(ROOT)],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Homebrew is required on macOS', result.stderr)
            self.assertIn('Homebrew/install', result.stderr)
            self.assertFalse((home / 'Applications').exists(), 'no app dir is created before Homebrew exists')

    def test_macos_preflight_requires_apple_command_line_tools(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            mocks = home / 'bin'
            mocks.mkdir()
            (mocks / 'uname').write_text('#!/bin/sh\ncase "$1" in -s) echo Darwin ;; -m) echo arm64 ;; *) echo Darwin ;; esac\n')
            (mocks / 'uname').chmod(0o755)
            (mocks / 'xcode-select').write_text('#!/bin/sh\nexit 1\n')
            (mocks / 'xcode-select').chmod(0o755)
            (mocks / 'brew').write_text('#!/bin/sh\necho /opt/homebrew\n')
            (mocks / 'brew').chmod(0o755)
            script = ('source "$1/setup.sh"; PROFILE=workstation; PACKAGE_MANAGER=brew; '
                      'CONFIG_ONLY=false; UPGRADE=false; HARDWARE=false; CHANGE_SHELL=false; '
                      'PLATFORM=mac; ARCH=aarch64; preflight')
            env = {**os.environ, 'HOME': str(home), 'PATH': str(mocks) + ':/usr/bin:/bin'}
            result = subprocess.run([BASH, '-euc', script, '_', str(ROOT)],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Apple Command Line Tools are required', result.stderr)

    def test_privileged_phase_is_skipped_on_macos_without_system_changes(self):
        cases = [('mac', False, False, False), ('mac', False, False, True),
                 ('mac', True, False, False), ('mac', False, True, False),
                 ('linux', False, False, False), ('linux', False, False, True)]
        for platform, hardware, change_shell, config_only in cases:
            with self.subTest(platform=platform, hardware=hardware, change_shell=change_shell,
                              config_only=config_only):
                script = ('source "$1/installer/components.sh"; source "$1/installer/common.sh"; '
                          'PLATFORM="$2"; HARDWARE="$3"; CHANGE_SHELL="$4"; CONFIG_ONLY="$5"; '
                          'needs_privileged_phase')
                result = subprocess.run([BASH, '-euc', script, '_', str(ROOT), platform,
                                         str(hardware).lower(), str(change_shell).lower(),
                                         str(config_only).lower()], capture_output=True, text=True)
                expected = hardware or change_shell or (platform == 'linux' and not config_only)
                self.assertEqual(result.returncode == 0, expected, result.stderr)


class ExecutableAliasTests(unittest.TestCase):
    def test_aliases_cover_known_distro_renames(self):
        for command_name, aliases in [('fd', ['fdfind']), ('bat', ['batcat']),
                                      ('git', []), ('nvim', [])]:
            with self.subTest(command=command_name):
                script = 'source "$1/installer/components.sh"; tool_aliases "$2"'
                result = subprocess.run([BASH, '-euc', script, '_', str(ROOT), command_name],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual([line for line in result.stdout.splitlines() if line], aliases)

    def test_shims_are_created_only_when_the_canonical_name_is_absent(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            mocks = home / 'bin'
            mocks.mkdir()
            (mocks / 'fdfind').write_text('#!/bin/sh\necho fdfind\n')
            (mocks / 'fdfind').chmod(0o755)
            script = '''
                source "$1/setup.sh"
                PROFILE=server; PLATFORM=linux; PACKAGE_MANAGER=native; CONFIG_ONLY=true
                detect_platform; initialize_state
                trap cleanup_setup EXIT
                install_opencode() { return 0; }
                install_source_tools() { return 0; }
                install_shell_identity() { return 0; }
                install_profile
            '''
            env = {**os.environ, 'HOME': str(home), 'PATH': controlled_path(directory, mocks, exclude=('fd', 'bat')),
                   'XDG_STATE_HOME': str(home / '.state'), 'XDG_CONFIG_HOME': str(home / '.config'),
                   'SHELL': '/bin/bash'}
            result = subprocess.run([BASH, '-euc', script, '_', str(ROOT)],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            shim = home / '.local/bin/fd'
            self.assertTrue(shim.is_symlink())
            self.assertEqual(shim.resolve(), (mocks / 'fdfind').resolve())
            self.assertFalse((home / '.local/bin/npm').exists(),
                             'the installer must never create an npm shim or alias')
            self.assertFalse((home / '.local/bin/bat').exists(),
                             'a shim is not created when the alternate is absent too')

    def test_existing_user_binary_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            mocks = home / 'bin'
            mocks.mkdir()
            (mocks / 'fdfind').write_text('#!/bin/sh\necho fdfind\n')
            (mocks / 'fdfind').chmod(0o755)
            user_bin = home / '.local/bin'
            user_bin.mkdir(parents=True)
            existing = user_bin / 'fd'
            existing.write_text('#!/bin/sh\necho user-provided\n')
            existing.chmod(0o755)
            script = '''
                source "$1/setup.sh"
                PROFILE=server; PLATFORM=linux; PACKAGE_MANAGER=native; CONFIG_ONLY=true
                detect_platform; initialize_state
                trap cleanup_setup EXIT
                install_opencode() { return 0; }
                install_source_tools() { return 0; }
                install_shell_identity() { return 0; }
                install_profile
            '''
            env = {**os.environ, 'HOME': str(home), 'PATH': controlled_path(directory, mocks, exclude=('fd', 'bat')),
                   'XDG_STATE_HOME': str(home / '.state'), 'XDG_CONFIG_HOME': str(home / '.config'),
                   'SHELL': '/bin/bash'}
            result = subprocess.run([BASH, '-euc', script, '_', str(ROOT)],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            # The user's own executable is already on PATH and wins: no shim is
            # written and the file is untouched.
            self.assertEqual(existing.read_text(), '#!/bin/sh\necho user-provided\n')
            self.assertFalse(existing.is_symlink())

    def test_stale_non_executable_placeholder_is_left_alone_with_a_warning(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            mocks = home / 'bin'
            mocks.mkdir()
            (mocks / 'fdfind').write_text('#!/bin/sh\necho fdfind\n')
            (mocks / 'fdfind').chmod(0o755)
            user_bin = home / '.local/bin'
            user_bin.mkdir(parents=True)
            placeholder = user_bin / 'fd'
            placeholder.write_text('not executable\n')
            placeholder.chmod(0o644)
            script = '''
                source "$1/setup.sh"
                PROFILE=server; PLATFORM=linux; PACKAGE_MANAGER=native; CONFIG_ONLY=true
                detect_platform; initialize_state
                trap cleanup_setup EXIT
                install_opencode() { return 0; }
                install_source_tools() { return 0; }
                install_shell_identity() { return 0; }
                install_profile
            '''
            env = {**os.environ, 'HOME': str(home), 'PATH': controlled_path(directory, mocks, exclude=('fd', 'bat')),
                   'XDG_STATE_HOME': str(home / '.state'), 'XDG_CONFIG_HOME': str(home / '.config'),
                   'SHELL': '/bin/bash'}
            result = subprocess.run([BASH, '-euc', script, '_', str(ROOT)],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('Not replacing non-executable', result.stderr)
            self.assertEqual(placeholder.read_text(), 'not executable\n')
            self.assertFalse(placeholder.is_symlink(), 'the placeholder must never be replaced by a shim')


class VersionGateTests(unittest.TestCase):
    def make_stubs(self, stubs, versions):
        for name, version in versions.items():
            stub = stubs / name
            stub.write_text(f'#!/bin/sh\nif [ "$1" = "--version" ] || [ "$1" = "-V" ]; then echo "{version}"; fi\n')
            stub.chmod(0o755)

    def run_verify(self, directory, versions, profile='workstation'):
        stubs = Path(directory) / 'bin'
        stubs.mkdir(exist_ok=True)
        self.make_stubs(stubs, versions)
        coreutils = Path(directory) / 'coreutils'
        coreutils.mkdir(exist_ok=True)
        for name in ['cat', 'grep', 'sed', 'readlink', 'head']:
            target = shutil.which(name)
            if target:
                (coreutils / name).symlink_to(target)
        script = '''
            source "$1/installer/components.sh"
            source "$1/installer/common.sh"
            source "$1/installer/profiles.sh"
            PROFILE="$2"; PLATFORM=linux
            verify_configs() { return 0; }
            verify_profile
        '''
        env = {**os.environ, 'PATH': f'{stubs}:{coreutils}'}
        return subprocess.run([BASH, '-euc', script, '_', str(ROOT), profile],
                              env=env, capture_output=True, text=True, timeout=30)

    @staticmethod
    def versions(nvim, tmux='3.6b'):
        return {'git': '2.39.0', 'curl': '8.0.0', 'ssh': '9.0.0', 'rsync': '3.2.0',
                'tmux': tmux, 'nvim': nvim, 'rg': '14.0.0', 'fd': '9.0.0',
                'fzf': '0.45.0', 'bat': '0.24.0', 'jq': '1.7.0', 'htop': '3.2.0',
                'python3': '3.12.0', 'opencode': '2.0.28', 'pi': '1.0.0',
                # Workstation-only manifest entries, so both profiles can verify.
                'zsh': '5.9', 'node': '22.11.0', 'pnpm': '9.0.0', 'go': '1.23.0',
                'rustup': '1.27.0', 'uv': '0.5.0', 'claude': '1.0.0', 'zed': '0.150.0',
                'alacritty': '0.13.5'}

    def test_declared_minimums_are_enforced(self):
        # Neovim minimum is per profile: LazyVim needs 0.11 on workstation, while
        # the managed server config only needs 0.10 (OSC52, pcall-guarded).
        cases = [('workstation', '0.10.4',
                  'nvim 0.10.4 is older than the declared minimum 0.11'),
                 ('server', '0.9.5',
                  'nvim 0.9.5 is older than the declared minimum 0.10')]
        for profile, nvim, expected in cases:
            with self.subTest(profile=profile), tempfile.TemporaryDirectory() as directory:
                result = self.run_verify(directory, self.versions(nvim), profile=profile)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(expected, result.stderr)
                self.assertNotIn('tmux', result.stderr)

    def test_passing_minimums_verify_cleanly(self):
        # Each profile accepts exactly its declared boundary.
        cases = [('workstation', '0.11.0'), ('server', '0.10.4')]
        for profile, nvim in cases:
            with self.subTest(profile=profile), tempfile.TemporaryDirectory() as directory:
                result = self.run_verify(directory, self.versions(nvim, tmux='3.3.0'),
                                         profile=profile)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(f'Verification passed: {profile}', result.stdout)

    def test_undetectable_version_is_informational_not_fatal(self):
        with tempfile.TemporaryDirectory() as directory:
            stubs = Path(directory) / 'bin'
            stubs.mkdir()
            versions = {'git': '2.39.0', 'curl': '8.0.0', 'ssh': '9.0.0', 'rsync': '3.2.0',
                        'nvim': '0.11.0', 'rg': '14.0.0', 'fd': '9.0.0',
                        'fzf': '0.45.0', 'bat': '0.24.0', 'jq': '1.7.0', 'htop': '3.2.0',
                        'python3': '3.12.0', 'zsh': '5.9', 'opencode': '2.0.28', 'pi': '1.0.0'}
            self.make_stubs(stubs, versions)
            # tmux exists but prints no parsable version.
            (stubs / 'tmux').write_text('#!/bin/sh\nif [ "$1" = "-V" ]; then echo "custom build"; fi\n')
            (stubs / 'tmux').chmod(0o755)
            coreutils = Path(directory) / 'coreutils'
            coreutils.mkdir()
            for name in ['cat', 'grep', 'sed', 'readlink', 'head']:
                target = shutil.which(name)
                if target:
                    (coreutils / name).symlink_to(target)
            script = ('source "$1/installer/components.sh"; source "$1/installer/common.sh"; '
                      'source "$1/installer/profiles.sh"; PROFILE=server; PLATFORM=linux; '
                      'verify_configs() { return 0; }; verify_profile')
            env = {**os.environ, 'PATH': f'{stubs}:{coreutils}'}
            result = subprocess.run([BASH, '-euc', script, '_', str(ROOT)],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('Version not detectable for tmux; declared minimum is 3.3', result.stdout)


class ToolchainBehaviourTests(unittest.TestCase):
    def test_rustup_targets_are_fetched_only_when_missing(self):
        for installed_output, expected_calls in [
            ('wasm32-wasip1\nwasm32-wasip2\n', 0),
            ('wasm32-wasip1\n', 1),
            ('', 1),
        ]:
            with self.subTest(installed_output=installed_output):
                with tempfile.TemporaryDirectory() as directory:
                    home = Path(directory)
                    mocks = home / 'bin'
                    mocks.mkdir()
                    calls = home / 'calls'
                    stub = f'#!{sys.executable}\n' + '''import os, sys
name = os.path.basename(sys.argv[0])
with open(os.environ["MOCK_CALLS"], "a") as out:
    out.write(name + " " + " ".join(sys.argv[1:]) + "\\n")
if name == "fnm" and sys.argv[1] == "env": print(":")
if name == "fnm": raise SystemExit(0)
if name == "rustup" and sys.argv[:2] == ["target", "list"]: raise SystemExit(0)
if name == "rustup": raise SystemExit(0)
if name == "uv" and sys.argv[1:] == ["tool", "list"]: print("markitdown v1.0")
raise SystemExit(0)
'''
                    for name in ['fnm', 'node', 'npm', 'pnpm', 'rustup', 'uv', 'claude',
                                 'brew', 'fc-match', 'git']:
                        path = mocks / name
                        path.write_text(stub)
                        path.chmod(0o755)
                    (mocks / 'rustup').write_text(
                        f'#!{sys.executable}\n'
                        'import os, sys\n'
                        'with open(os.environ["MOCK_CALLS"], "a") as out:\n'
                        '    out.write("rustup " + " ".join(sys.argv[1:]) + "\\n")\n'
                        'if sys.argv[1:3] == ["target", "list"]:\n'
                        f'    print({installed_output!r})\n'
                        'raise SystemExit(0)\n')
                    (mocks / 'rustup').chmod(0o755)
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
                    env = {**os.environ, 'HOME': str(home),
                           'PATH': controlled_path(directory, mocks, extra=('python3',)),
                           'MOCK_CALLS': str(calls)}
                    result = subprocess.run([BASH, '-euc', script, '_', str(ROOT)],
                                            env=env, capture_output=True, text=True, timeout=30)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    log = calls.read_text() if calls.exists() else ''
                    self.assertEqual(log.count('rustup target add'), expected_calls)


if __name__ == '__main__':
    unittest.main()
