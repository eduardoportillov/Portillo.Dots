import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from _support import tempdir
import unittest

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / 'installer/privileged-core.sh'
CATALOG = ROOT / 'installer/components.sh'
BASH = shutil.which('bash')


class PrivilegedCoreTests(unittest.TestCase):
    def fixture_directory(self):
        # /tmp/opencode is group-writable in the harness. Do not weaken the
        # production ownership guard just to allow that ancestor in these tests.
        # A private mkdtemp under the OS sticky /tmp exercises the real checks.
        return tempfile.TemporaryDirectory(prefix='portillo-root-copy-', dir='/tmp')

    def shell(self, script, *args, env=None):
        return subprocess.run([BASH, '-euc', 'source "$1"; ' + script, '_', str(CORE), *map(str, args)],
                              env=env, capture_output=True, text=True, timeout=10)

    def test_library_is_inert_when_sourced(self):
        result = self.shell('printf "loaded\\n"')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'loaded\n')

    def test_atomic_copy_preserves_original_backup_and_permissions(self):
        with self.fixture_directory() as directory:
            base = Path(directory)
            source, destination = base / 'source', base / 'target'
            source.write_text('replacement')
            destination.write_text('original')
            result = self.shell('root_copy "$2" "$3" 0644', source, destination)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(destination.read_text(), 'replacement')
            self.assertEqual(destination.stat().st_mode & 0o777, 0o644)
            self.assertEqual(destination.stat().st_uid, os.getuid())
            self.assertEqual([p.read_text() for p in base.glob('.portillo-backup.*/target')], ['original'])
            again = self.shell('root_copy "$2" "$3" 0644', source, destination)
            self.assertEqual(again.returncode, 0, again.stderr)
            self.assertEqual(len(list(base.glob('.portillo-backup.*'))), 1)
            self.assertEqual(list(base.glob('.portillo.*')), [])

    def test_symlink_to_regular_file_is_replaced_without_writing_through(self):
        with self.fixture_directory() as directory:
            base = Path(directory)
            source, destination, unrelated = (base / name for name in ['source', 'target', 'unrelated'])
            source.write_text('replacement')
            unrelated.write_text('keep')
            destination.symlink_to(unrelated)
            result = self.shell('root_copy "$2" "$3" 0644', source, destination)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(destination.is_symlink())
            self.assertEqual(unrelated.read_text(), 'keep')
            backup = next(base.glob('.portillo-backup.*/target'))
            self.assertTrue(backup.is_symlink())
            self.assertEqual(backup.readlink(), unrelated)

    def test_writable_old_inode_is_replaced_even_when_contents_match(self):
        with self.fixture_directory() as directory:
            base = Path(directory)
            source, destination = base / 'source', base / 'target'
            source.write_text('same contents')
            destination.write_text('same contents')
            destination.chmod(0o666)
            old_inode = destination.stat().st_ino
            with destination.open('r+') as old_descriptor:
                result = self.shell('root_copy "$2" "$3" 0644', source, destination)
                self.assertEqual(result.returncode, 0, result.stderr)
                old_descriptor.seek(0)
                old_descriptor.write('modified old inode')
                old_descriptor.flush()
                self.assertNotEqual(destination.stat().st_ino, old_inode)
                self.assertEqual(destination.read_text(), 'same contents')

    def test_directories_and_symlinked_directories_are_rejected(self):
        with self.fixture_directory() as directory:
            base = Path(directory)
            source = base / 'source'
            source.write_text('replacement')
            folder = base / 'folder'
            folder.mkdir()
            link = base / 'link'
            link.symlink_to(folder, target_is_directory=True)
            for destination in [folder, link]:
                result = self.shell('root_copy "$2" "$3" 0644', source, destination)
                self.assertNotEqual(result.returncode, 0)
            self.assertEqual(list(folder.iterdir()), [])
            self.assertTrue(link.is_symlink())

    def test_writable_parent_is_rejected_before_copy(self):
        with self.fixture_directory() as directory:
            base = Path(directory)
            source = base / 'source'
            source.write_text('replacement')
            destination = base / 'unsafe' / 'target'
            destination.parent.mkdir(mode=0o777)
            destination.parent.chmod(0o777)
            result = self.shell('root_copy "$2" "$3" 0644', source, destination)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(destination.exists())

    def test_missing_parents_are_created_only_below_a_safe_ancestor(self):
        with self.fixture_directory() as directory:
            base = Path(directory)
            source = base / 'source'
            source.write_text('replacement')
            destination = base / 'new' / 'nested' / 'target'
            result = self.shell('root_copy "$2" "$3" 0644', source, destination)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(destination.read_text(), 'replacement')

    def test_failed_install_keeps_original_and_cleans_staging_even_in_or_context(self):
        with self.fixture_directory() as directory:
            base = Path(directory)
            source, destination = base / 'source', base / 'target'
            source.write_text('replacement')
            destination.write_text('original')
            result = self.shell('install() { return 41; }; root_copy "$2" "$3" 0644 || exit 42', source, destination)
            self.assertEqual(result.returncode, 42, result.stderr)
            self.assertEqual(destination.read_text(), 'original')
            self.assertEqual(list(base.glob('.portillo.*')), [])

    def test_termination_keeps_original_and_cleans_staging(self):
        for signal, status in [('INT', 130), ('TERM', 143)]:
            with self.subTest(signal=signal), self.fixture_directory() as directory:
                base = Path(directory)
                source, destination = base / 'source', base / 'target'
                source.write_text('replacement')
                destination.write_text('original')
                result = self.shell('install() { /bin/sh -c \'kill -"$FIXTURE_SIGNAL" "$PPID"\'; }; root_copy "$2" "$3" 0644',
                                    source, destination, env={**os.environ, 'FIXTURE_SIGNAL': signal})
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertEqual(destination.read_text(), 'original')
                self.assertEqual(list(base.glob('.portillo.*')), [])

    def test_only_exact_legacy_rule_is_retired_as_a_comment(self):
        with self.fixture_directory() as directory:
            base = Path(directory)
            fragment = base / 'legacy'
            fragment.write_text('fixture-user ALL=(ALL) NOPASSWD: ALL\n')
            result = self.shell('visudo() { return 0; }; retire_legacy_rule "$2" fixture-user', fragment)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(fragment.read_text().startswith('# Portillo.Dots:'))
            self.assertEqual(fragment.stat().st_mode & 0o777, 0o440)
            self.assertIn('fixture-user ALL=(ALL) NOPASSWD: ALL', next(base.glob('.portillo-backup.*/legacy')).read_text())
            self.assertEqual(list(base.glob('.portillo-retired.*')), [])

    def test_unrelated_and_symlinked_sudoers_fragments_are_preserved(self):
        with self.fixture_directory() as directory:
            base = Path(directory)
            fragment = base / 'legacy'
            for text in ['other-user ALL=(ALL) NOPASSWD: ALL\n',
                         'fixture-user ALL=(ALL) NOPASSWD: ALL\n# additional policy\n']:
                fragment.write_text(text)
                result = self.shell('retire_legacy_rule "$2" fixture-user', fragment)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(fragment.read_text(), text)
            link = base / 'link'
            link.symlink_to(fragment)
            result = self.shell('retire_legacy_rule "$2" fixture-user', link)
            self.assertEqual(result.returncode, 0)
            self.assertTrue(link.is_symlink())

    def test_invalid_retirement_candidate_preserves_original(self):
        with self.fixture_directory() as directory:
            fragment = Path(directory) / 'legacy'
            original = 'fixture-user ALL=(ALL) NOPASSWD: ALL\n'
            fragment.write_text(original)
            result = self.shell('visudo() { return 1; }; retire_legacy_rule "$2" fixture-user', fragment)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(fragment.read_text(), original)

    def test_existing_service_link_is_hardened_without_executing_the_script(self):
        with self.fixture_directory() as directory:
            base = Path(directory)
            source, target, unit, template = (base / name for name in ['script', 'installed', 'service', 'template'])
            marker = base / 'must-not-execute'
            source.write_text(f'#!/bin/bash\ntouch "{marker}"\n')
            unit.write_text('ExecStart=/usr/local/bin/apply-linux-hardware-settings.sh --apply\n')
            unit.chmod(0o644)
            template.write_bytes(unit.read_bytes())
            target.symlink_to(source)
            result = self.shell('harden_existing_service "$2" "$3" "$4" "$5"', target, unit, source, template)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(target.is_symlink())
            self.assertEqual(target.stat().st_mode & 0o777, 0o755)
            self.assertEqual(target.read_bytes(), source.read_bytes())
            self.assertEqual(unit.read_bytes(), template.read_bytes())
            self.assertFalse(marker.exists())
            self.assertTrue(next(base.glob('.portillo-backup.*/installed')).is_symlink())
            again = self.shell('harden_existing_service "$2" "$3" "$4" "$5"', target, unit, source, template)
            self.assertEqual(again.returncode, 0, again.stderr)
            self.assertEqual(len(list(base.glob('.portillo-backup.*'))), 1)

    def test_unrecognized_service_and_script_are_preserved(self):
        with self.fixture_directory() as directory:
            base = Path(directory)
            source, target, unit, template = (base / name for name in ['script', 'installed', 'service', 'template'])
            source.write_text('#!/bin/bash\ntrue\n')
            unit.write_text('custom-service\n')
            unit.chmod(0o644)
            template.write_text('managed-service\n')
            target.symlink_to(source)
            result = self.shell('harden_existing_service "$2" "$3" "$4" "$5"', target, unit, source, template)
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(target.is_symlink())
            unit.write_bytes(template.read_bytes())
            target.unlink()
            target.write_text('independent-installed-script')
            result = self.shell('harden_existing_service "$2" "$3" "$4" "$5"', target, unit, source, template)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(target.read_text(), 'independent-installed-script')


class PrivilegedPackageTests(unittest.TestCase):
    def run_packages(self, backend, profile='server', manager='native', upgrade=False, fail_arg=''):
        with tempdir() as directory:
            base = Path(directory)
            mock = base / backend
            mock.write_text(f'#!{sys.executable}\n' + '''import json, os, sys
with open(os.environ['CALLS'], 'a') as output:
    output.write(json.dumps(sys.argv[1:]) + '\\n')
if os.environ.get('FAIL_ARG') in sys.argv[1:]:
    sys.exit(47)
''')
            mock.chmod(0o755)
            # The catalog emits the manifest through cat(1); keep the PATH
            # minimal but complete enough for the privileged package logic.
            (base / 'cat').symlink_to(shutil.which('cat'))
            log = base / 'calls'
            env = {**os.environ, 'PATH': directory, 'CALLS': str(log), 'FAIL_ARG': fail_arg}
            script = ('source "$1"; source "$2"; install_packages "$3" "$4" "$5"')
            result = subprocess.run([BASH, '-euc', script, '_', str(CATALOG), str(CORE),
                                     profile, manager, str(upgrade).lower()],
                                    env=env, capture_output=True, text=True, timeout=10)
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, calls

    @staticmethod
    def package_names(calls):
        return [value for call in calls for value in call]

    def test_supported_backends_do_not_install_desktop_in_server_profile(self):
        python = {'apt-get': 'python3', 'dnf': 'python3', 'pacman': 'python'}
        for backend in ['apt-get', 'dnf', 'pacman']:
            with self.subTest(backend=backend):
                result, calls = self.run_packages(backend)
                self.assertEqual(result.returncode, 0, result.stderr)
                packages = self.package_names(calls)
                for name in ['git', python[backend], 'neovim', 'tmux']:
                    self.assertIn(name, packages)
                for name in ['alacritty', 'copyq', 'zsh', 'golang-go', 'base-devel']:
                    self.assertNotIn(name, packages)

    def test_native_package_names_come_from_the_catalog(self):
        expectations = {
            'apt-get': (['openssh-client', 'fd-find', 'bat', 'python3'],
                        ['openssh', 'fd', 'python']),
            'dnf': (['openssh-clients', 'fd-find', 'bat', 'python3'],
                    ['openssh', 'fd', 'python']),
            'pacman': (['openssh', 'fd', 'bat', 'python'],
                       ['openssh-client', 'fd-find', 'python3']),
        }
        for backend, (expected, forbidden) in expectations.items():
            with self.subTest(backend=backend):
                result, calls = self.run_packages(backend)
                self.assertEqual(result.returncode, 0, result.stderr)
                packages = self.package_names(calls)
                for name in expected:
                    self.assertIn(name, packages)
                for name in forbidden:
                    self.assertNotIn(name, packages)

    def test_workstation_native_adds_optional_tools_and_go(self):
        go = {'apt-get': 'golang-go', 'dnf': 'golang', 'pacman': 'go'}
        treesitter = {'apt-get': 'tree-sitter-cli', 'dnf': 'tree-sitter-cli',
                      'pacman': 'tree-sitter'}
        for backend in ['apt-get', 'dnf', 'pacman']:
            with self.subTest(backend=backend):
                result, calls = self.run_packages(backend, profile='workstation')
                self.assertEqual(result.returncode, 0, result.stderr)
                packages = self.package_names(calls)
                for name in ['lazygit', go[backend], treesitter[backend]]:
                    self.assertIn(name, packages)

    def test_packages_fail_closed_without_the_provisioning_catalog(self):
        result, calls = self.run_packages_without_catalog()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Incomplete privileged payload', result.stderr)
        self.assertEqual(calls, [])

    def run_packages_without_catalog(self):
        with tempdir() as directory:
            base = Path(directory)
            mock = base / 'apt-get'
            mock.write_text(f'#!{sys.executable}\n' + 'import json, os, sys\n'
                            'with open(os.environ["CALLS"], "a") as output:\n'
                            '    output.write(json.dumps(sys.argv[1:]) + "\\n")\n')
            mock.chmod(0o755)
            (base / 'cat').symlink_to(shutil.which('cat'))
            env = {**os.environ, 'PATH': directory, 'CALLS': str(base / 'calls')}
            script = 'source "$1"; install_packages server native false'
            result = subprocess.run([BASH, '-euc', script, '_', str(CORE)],
                                    env=env, capture_output=True, text=True, timeout=10)
            log = base / 'calls'
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, calls

    def test_apt_preserves_conffiles_and_does_not_upgrade_implicitly(self):
        result, calls = self.run_packages('apt-get')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--no-upgrade', calls[1])
        self.assertIn('Dpkg::Options::=--force-confold', calls[1])
        result, upgraded = self.run_packages('apt-get', upgrade=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('--no-upgrade', upgraded[1])

    def test_failure_of_required_packages_stops_and_is_not_retried(self):
        for backend in ['apt-get', 'dnf', 'pacman']:
            with self.subTest(backend=backend):
                result, calls = self.run_packages(backend, fail_arg='git')
                self.assertEqual(result.returncode, 47, result.stderr)
                self.assertEqual(sum('git' in call for call in calls), 1)

    def test_failed_apt_index_refresh_does_not_install_any_package(self):
        result, calls = self.run_packages('apt-get', fail_arg='update')
        self.assertEqual(result.returncode, 47)
        self.assertEqual(calls, [['update']])

    def test_optional_failure_is_reported_without_retrying_authentication(self):
        result, calls = self.run_packages('apt-get', profile='workstation', fail_arg='lazygit')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Optional packages unavailable: lazygit', result.stderr)
        self.assertEqual(sum('lazygit' in call for call in calls), 1)


class SudoTransportTests(unittest.TestCase):
    def test_invalid_payload_is_rejected_before_authentication(self):
        with tempdir() as directory:
            base = Path(directory)
            (base / 'installer').mkdir()
            (base / 'installer/privileged-core.sh').write_text('broken() {\n')
            (base / 'installer/privileged.sh').write_text('# no actions\n')
            script = '''source "$1/setup.sh"; REPO_DIR="$2"; PROFILE=server; PACKAGE_MANAGER=native; LOG="$2/log";
                sudo() { touch "$REPO_DIR/sudo-called"; cat >/dev/null; }
                privileged_phase'''
            result = subprocess.run([BASH, '-euc', script, '_', str(ROOT), str(base)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((base / 'sudo-called').exists())
            self.assertIn('sudo was not invoked', result.stderr)

    @unittest.skipIf(os.geteuid() == 0, 'The installer must be invoked by a normal user')
    def test_read_only_cli_probe_does_not_create_user_state(self):
        with tempdir() as directory:
            base = Path(directory)
            home, bin_dir = base / 'home', base / 'bin'
            home.mkdir()
            bin_dir.mkdir()
            sudo = bin_dir / 'sudo'
            sudo.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$MOCK_CALLS"\ncat >/dev/null\necho mock-identity-checked\n')
            sudo.chmod(0o755)
            env = {**os.environ, 'HOME': str(home), 'XDG_STATE_HOME': str(home / '.state'),
                   'XDG_CONFIG_HOME': str(home / '.config'), 'PATH': str(bin_dir) + ':' + os.environ['PATH'],
                   'MOCK_CALLS': str(base / 'calls')}
            result = subprocess.run([BASH, str(ROOT / 'setup.sh'), '--profile', 'server', '--check-sudo'],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('mock-identity-checked', result.stdout)
            self.assertEqual(list(home.iterdir()), [])
            calls = (base / 'calls').read_text().splitlines()
            self.assertEqual(len(calls), 1)
            self.assertTrue(calls[0].endswith(' check'))

    def test_read_only_probe_dry_run_does_not_invoke_sudo(self):
        with tempdir() as directory:
            base = Path(directory)
            home = base / 'home'
            home.mkdir()
            result = subprocess.run([BASH, str(ROOT / 'setup.sh'), '--profile', 'server', '--check-sudo', '--dry-run'],
                                    env={**os.environ, 'HOME': str(home)}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Read-only privileged identity check', result.stdout)
            self.assertEqual(list(home.iterdir()), [])

    def test_one_privileged_bash_invocation_with_payload_on_stdin(self):
        with tempdir() as directory:
            base = Path(directory)
            script = '''source "$1/setup.sh"; PROFILE=server; PACKAGE_MANAGER=native; LOG="$2/log";
                fixture="$2"
                sudo() { printf '%s\\n' "$*" >> "$fixture/calls"; cat > "$fixture/payload"; }
                privileged_phase check'''
            result = subprocess.run([BASH, '-euc', script, '_', str(ROOT), str(base)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = (base / 'calls').read_text().splitlines()
            self.assertEqual(len(calls), 1)
            self.assertIn('/bin/bash -p -s -- server native false false false false', calls[0])
            self.assertTrue(calls[0].endswith(' check'))
            payload = (base / 'payload').read_text()
            self.assertIn('root_copy()', payload)
            self.assertIn('tool_packages()', payload)
            self.assertIn('profile_components()', payload)
            self.assertIn('privileged_main "$@" </dev/null', payload)

    def test_authentication_failure_and_interrupt_do_not_retry_or_continue(self):
        for status in [1, 130, 143]:
            with self.subTest(status=status), tempdir() as directory:
                base = Path(directory)
                script = '''source "$1/setup.sh"; PROFILE=server; PACKAGE_MANAGER=native; LOG="$2/log";
                    fixture="$2"; status="$3"
                    sudo() { printf 'attempt\\n' >> "$fixture/calls"; cat >/dev/null; return "$status"; }
                    privileged_phase
                    printf 'MUST NOT CONTINUE\\n' '''
                result = subprocess.run([BASH, '-euc', script, '_', str(ROOT), str(base), str(status)],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertEqual((base / 'calls').read_text(), 'attempt\n')
                self.assertNotIn('MUST NOT CONTINUE', result.stdout)

    def test_privileged_bash_does_not_execute_bash_env_before_identity_guard(self):
        with tempdir() as directory:
            base = Path(directory)
            untrusted = base / 'untrusted.sh'
            untrusted.write_text('touch "$MOCK_MARKER"\n')
            script = '''source "$1/setup.sh"; PROFILE=server; PACKAGE_MANAGER=native; LOG="$2/log";
                fixture="$2"
                sudo() { BASH_ENV="$fixture/untrusted.sh" MOCK_MARKER="$fixture/executed" "$@"; }
                privileged_phase check'''
            result = subprocess.run([BASH, '-euc', script, '_', str(ROOT), str(base)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)  # It is still an unprivileged test process.
            self.assertFalse((base / 'executed').exists())


if __name__ == '__main__':
    unittest.main()


class HomebrewPrefixTests(unittest.TestCase):
    """The privileged phase prepares the brew prefix root, nothing more."""

    def shell(self, script, *args):
        return subprocess.run([BASH, '-euc', 'source "$1"; ' + script, '_', str(CORE), *map(str, args)],
                              capture_output=True, text=True, timeout=10)

    def test_missing_prefix_root_is_created_for_the_invoking_user(self):
        with tempdir() as directory:
            root = Path(directory) / 'home/linuxbrew'
            result = self.shell('prepare_homebrew_prefix "$2" "$USER"', root)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(root.is_dir())
            self.assertEqual(root.stat().st_uid, os.getuid())

    def test_relative_or_root_paths_are_refused(self):
        for path in ['relative/path', '/']:
            with self.subTest(path=path):
                result = self.shell('prepare_homebrew_prefix "$2" "$USER"', path)
                self.assertEqual(result.returncode, 2)

    def test_non_directory_root_is_refused(self):
        with tempdir() as directory:
            root = Path(directory) / 'home/linuxbrew'
            root.parent.mkdir(parents=True)
            root.write_text('not a directory\n')
            result = self.shell('prepare_homebrew_prefix "$2" "$USER"', root)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('refusing changes', result.stderr)

    def test_privileged_entry_prepares_only_the_homebrew_literal(self):
        # Root code must never prepare a path that comes from a variable: the
        # call site is pinned to the fixed literal, like systemctl's guard.
        text = (ROOT / 'installer/privileged.sh').read_text()
        calls = [line.strip() for line in text.splitlines()
                 if re.search(r'prepare_homebrew_prefix\s+[/~$.]', line)]
        self.assertEqual(calls, ['prepare_homebrew_prefix /home/linuxbrew "$SUDO_USER" || return 1'],
                         'the prefix root must be a fixed literal, never user-controlled')


if __name__ == '__main__':
    unittest.main()
