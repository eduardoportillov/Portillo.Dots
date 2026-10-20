"""Operation modes, diagnostics and outcome reporting."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from _support import tempdir
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which('bash')


class OperationModeTests(unittest.TestCase):
    # Files the installer itself manages. Querying a tool may legitimately
    # create its own XDG directories; what must never appear is the installer's
    # config, state or symlinks.
    INSTALLER_OWNED = [
        '.config/opencode/opencode.jsonc', '.config/opencode/opencode.json',
        '.config/opencode/cli.json', '.config/opencode/load-secrets.sh',
        '.config/opencode/secrets.env',
        '.config/nvim', '.config/portillo-dots', '.local/state/portillo-dots',
        '.dircolors', '.tmux.conf', '.zshrc', '.bashrc',
        '.config/zed', '.config/alacritty',
    ]

    def installer_footprint(self, home):
        return [p for p in self.INSTALLER_OWNED
                if (home / p).exists() or (home / p).is_symlink()]

    def isolated(self, directory):
        env = os.environ.copy()
        env.update(HOME=directory, XDG_CONFIG_HOME=directory + '/.config',
                   XDG_STATE_HOME=directory + '/.state', SHELL='/bin/bash')
        platform_bin = Path(directory) / '.test-bin'
        platform_bin.mkdir(exist_ok=True)
        uname = platform_bin / 'uname'
        uname.write_text('#!/bin/sh\ncase "$1" in -s) echo Linux ;; -m) echo x86_64 ;; esac\n')
        uname.chmod(0o755)
        env['PATH'] = f'{platform_bin}:{env["PATH"]}'
        return env

    def run_setup(self, directory, args, env=None):
        return subprocess.run([BASH, str(ROOT / 'setup.sh'), *args],
                              env=env or self.isolated(directory),
                              capture_output=True, text=True, timeout=60)

    def test_dry_run_creates_no_files_and_starts_nothing(self):
        for profile in ('server', 'workstation'):
            for args in [['--profile', profile, '--dry-run'],
                         ['--profile', profile, '--check-sudo', '--dry-run'],
                         ['--profile', 'workstation', '--harden-existing-service', '--dry-run']]:
                with self.subTest(args=args), tempdir() as directory:
                    home = Path(directory)
                    result = self.run_setup(directory, args)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(self.installer_footprint(home), [],
                                     f'{args} must not create installer files')

    def test_dry_run_previews_linux_only_actions_on_macos_without_writes(self):
        with tempdir() as directory:
            home = Path(directory)
            mac_bin = home / 'mac-bin'
            mac_bin.mkdir()
            uname = mac_bin / 'uname'
            uname.write_text('#!/bin/sh\ncase "$1" in -s) echo Darwin ;; -m) echo arm64 ;; esac\n')
            uname.chmod(0o755)
            env = self.isolated(directory)
            env['PATH'] = f'{mac_bin}:{env["PATH"]}'
            result = self.run_setup(directory,
                                    ['--profile', 'workstation', '--dry-run', '--hardware'], env=env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('Platform: mac/aarch64', result.stdout)
            self.assertIn('Preview only: hardware settings are unavailable on this platform',
                          result.stdout)
            self.assertEqual(self.installer_footprint(home), [])
            result = self.run_setup(directory,
                                    ['--profile', 'workstation', '--dry-run',
                                     '--harden-existing-service'], env=env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('Preview only: service hardening is unavailable on this platform',
                          result.stdout)
            self.assertEqual(self.installer_footprint(home), [])

    def test_check_is_read_only(self):
        for profile in ('server', 'workstation'):
            with self.subTest(profile=profile), tempdir() as directory:
                home = Path(directory)
                result = self.run_setup(directory, ['--profile', profile, '--check'])
                # A missing profile is expected to fail verification, not to write.
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.installer_footprint(home), [],
                                 '--check must never write config or state')

    def test_check_exit_code_is_nonzero_when_a_required_tool_is_missing(self):
        with tempdir() as directory:
            home = Path(directory)
            stubs = home / 'bin'
            stubs.mkdir()
            coreutils = home / 'coreutils'
            coreutils.mkdir()
            # Real coreutils so setup.sh can resolve its own paths; stub only the
            # manifest tools so a required one can be deliberately absent.
            for name in ['awk', 'basename', 'cat', 'chmod', 'dirname', 'env', 'find',
                         'grep', 'head', 'id', 'ln', 'mkdir', 'mktemp', 'readlink',
                         'rm', 'sed', 'sort', 'stat', 'touch', 'tr', 'cut', 'uname', 'wc', 'xargs']:
                target = shutil.which(name)
                if target:
                    (coreutils / name).symlink_to(target)
            versions = {'tmux': '3.6b', 'nvim': '0.11.0', 'opencode': '2.0.28'}
            for name in ['curl', 'ssh', 'rsync', 'tmux', 'nvim', 'rg', 'fd',
                         'fzf', 'bat', 'jq', 'htop', 'python3', 'opencode', 'pi']:
                path = stubs / name
                if name in versions:
                    path.write_text(f'#!/bin/sh\necho "{name} {versions[name]}"\n')
                elif name == 'python3':
                    path.symlink_to(shutil.which('python3'))
                else:
                    path.write_text('#!/bin/sh\nexit 0\n')
                if not path.is_symlink():
                    # chmod on a symlink would target the real interpreter, which
                    # may be root-owned on other hosts.
                    path.chmod(0o755)
            env = self.isolated(str(home))
            env['PATH'] = f'{stubs}:{coreutils}'
            result = self.run_setup(directory, ['--profile', 'server', '--check'], env=env)
            self.assertEqual(result.returncode, 1,
                             'a missing required tool must produce a failing exit code')
            self.assertIn('Missing required tool: git', result.stderr)
            self.assertIn('Verification FAILED', result.stderr)
            self.assertNotIn('Verification passed', result.stdout)

    def test_summary_names_created_preserved_and_failed_events(self):
        with tempdir() as directory:
            home = Path(directory)
            result = self.run_setup(directory, ['--profile', 'server', '--config-only'])
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('Outcome for server', result.stdout)
            self.assertIn('created ', result.stdout)
            self.assertIn('unchanged ', result.stdout)
            self.assertIn('[+] link', result.stdout)

    def test_summary_reports_a_preserved_independent_config(self):
        with tempdir() as directory:
            home = Path(directory)
            config = home / '.config/opencode/opencode.jsonc'
            config.parent.mkdir(parents=True)
            config.write_text('{"permissions":[{"action":"shell","resource":"*","effect":"ask"},'
                              '{"action":"edit","resource":"*","effect":"ask"}]}\n')
            result = self.run_setup(directory, ['--profile', 'server', '--config-only'])
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('preserved ', result.stdout)
            self.assertIn('[!] ', result.stdout)
            self.assertIn('independent config kept', result.stdout)
            self.assertFalse(config.is_symlink())

    def test_summary_reports_failures_and_the_run_exits_nonzero(self):
        with tempdir() as directory:
            home = Path(directory)
            config = home / '.config/opencode/opencode.jsonc'
            config.parent.mkdir(parents=True)
            # Permissive Server policy: verification must fail and be reported.
            config.write_text('{"permissions":[{"action":"shell","resource":"*","effect":"allow"}]}\n')
            result = self.run_setup(directory, ['--profile', 'server', '--config-only'])
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('failed ', result.stdout)
            self.assertIn('[x] ', result.stdout)
            self.assertIn('Completed WITH FAILURES', result.stderr)

    def test_config_only_never_invokes_sudo(self):
        with tempdir() as directory:
            home = Path(directory)
            mocks = home / 'bin'
            mocks.mkdir()
            sudo = mocks / 'sudo'
            sudo.write_text('#!/bin/sh\necho "SUDO CALLED" >&2\nexit 99\n')
            sudo.chmod(0o755)
            env = self.isolated(str(home))
            env['PATH'] = f'{mocks}:{env["PATH"]}'
            result = self.run_setup(directory, ['--profile', 'server', '--config-only'], env=env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn('SUDO CALLED', result.stdout + result.stderr)


class ArgumentValidationTests(unittest.TestCase):
    def run_setup(self, args, env=None):
        # stdin is closed: a host running the suite from a terminal must see the
        # same behaviour as CI (no interactive menu can block the run).
        return subprocess.run([BASH, str(ROOT / 'setup.sh'), *args], stdin=subprocess.DEVNULL,
                              env=env, capture_output=True, text=True, timeout=30)

    def temp_env(self, directory):
        env = os.environ.copy()
        env.update(HOME=directory, XDG_CONFIG_HOME=directory + '/.config',
                   XDG_STATE_HOME=directory + '/.state', SHELL='/bin/bash')
        return env

    def test_missing_flag_values_are_rejected(self):
        cases = [['--profile'], ['--profile', '--check'], ['--package-manager'],
                 ['--package-manager', '--dry-run'], ['--profile', ''],
                 ['--package-manager', '']]
        for args in cases:
            with self.subTest(args=args), tempdir() as d:
                result = self.run_setup(args, env=self.temp_env(d))
                self.assertNotEqual(result.returncode, 0, args)
                self.assertIn('Missing value', result.stderr)

    def test_invalid_enum_values_are_rejected(self):
        cases = [['--profile', 'desktop'], ['--profile', 'SERVER'],
                 ['--package-manager', 'apt'], ['--package-manager', 'native!']]
        for args in cases:
            with self.subTest(args=args), tempdir() as d:
                result = self.run_setup(args, env=self.temp_env(d))
                self.assertNotEqual(result.returncode, 0, args)

    def test_unknown_flags_and_positional_arguments_are_rejected(self):
        cases = [['--nope'], ['extra'], ['--profile', 'server', 'extra'],
                 ['--profile', 'server', '--check', 'trailing']]
        for args in cases:
            with self.subTest(args=args), tempdir() as d:
                result = self.run_setup(args, env=self.temp_env(d))
                self.assertNotEqual(result.returncode, 0, args)

    def test_conflicting_modes_are_rejected(self):
        cases = [
            ['--profile', 'server', '--config-only', '--check'],
            ['--profile', 'server', '--check', '--dry-run', '--upgrade'],
            ['--profile', 'workstation', '--apply-linux', '--check-sudo'],
            ['--profile', 'server', '--harden-existing-service', '--config-only'],
            ['--profile', 'server', '--check-sudo', '--harden-existing-service'],
            ['--profile', 'workstation', '--config-only', '--hardware'],
        ]
        for args in cases:
            with self.subTest(args=args), tempdir() as d:
                result = self.run_setup(args, env=self.temp_env(d))
                self.assertNotEqual(result.returncode, 0, args)

    def test_help_exits_zero_and_documents_every_mode(self):
        with tempdir() as directory:
            result = self.run_setup(['--help'], env=self.temp_env(directory))
            self.assertEqual(result.returncode, 0, result.stderr)
            for flag in ['--dry-run', '--check', '--config-only', '--upgrade',
                         '--hardware', '--change-shell', '--check-sudo']:
                self.assertIn(flag, result.stdout)

    def test_help_exits_zero_without_creating_state(self):
        with tempdir() as directory:
            result = self.run_setup(['-h'], env=self.temp_env(directory))
            self.assertEqual(result.returncode, 0)
            self.assertEqual([p for p in Path(directory).iterdir()
                              if p.name.startswith('.') and 'cache' not in p.name
                              and 'state' not in p.name], [])


class DiagnosticOutputTests(unittest.TestCase):
    def test_dry_run_prints_the_plan_including_gated_actions(self):
        with tempdir() as directory:
            env = os.environ.copy()
            env.update(HOME=directory, XDG_CONFIG_HOME=directory + '/.config',
                       XDG_STATE_HOME=directory + '/.state', SHELL='/bin/bash')
            result = subprocess.run(
                [BASH, str(ROOT / 'setup.sh'), '--profile', 'workstation', '--dry-run',
                 '--hardware', '--change-shell'],
                env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('OPT-IN: CPU/memory settings', result.stdout)
            self.assertIn('OPT-IN: change login shell', result.stdout)
            self.assertIn('Required tools', result.stdout)
            self.assertIn('Declared minimum versions', result.stdout)

    def test_no_false_completion_after_a_failed_requirement(self):
        with tempdir() as directory:
            home = Path(directory)
            config = home / '.config/opencode/opencode.jsonc'
            config.parent.mkdir(parents=True)
            config.write_text('{"permissions":[{"action":"shell","resource":"*","effect":"allow"}]}\n')
            env = os.environ.copy()
            env.update(HOME=directory, XDG_CONFIG_HOME=directory + '/.config',
                       XDG_STATE_HOME=directory + '/.state', SHELL='/bin/bash')
            result = subprocess.run([BASH, str(ROOT / 'setup.sh'), '--profile', 'server', '--config-only'],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('Completed: server', result.stdout + result.stderr)
            self.assertNotIn('Verification passed', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
