import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which('bash')


def components(profile, platform='linux'):
    script = ('source "$1/installer/components.sh"; '
              'profile_components "$2" "$3"')
    result = subprocess.run([BASH, '-euc', script, '_', str(ROOT), profile, platform],
                            capture_output=True, text=True, check=True)
    parsed = []
    for line in result.stdout.splitlines():
        if line.strip():
            kind, name, description = line.split(' ', 2)
            parsed.append((kind, name, description))
    return parsed


class ProfileManifestTests(unittest.TestCase):
    def test_server_has_no_workstation_only_tools(self):
        server = {name for _, name, _ in components('server')}
        workstation = {name for _, name, _ in components('workstation')}
        for name in ['zsh', 'node', 'pnpm', 'go', 'rustup', 'uv', 'claude', 'zed',
                     'lazygit', 'lazydocker', 'zoxide', 'atuin']:
            self.assertNotIn(name, server)
            self.assertIn(name, workstation)
        for name in ['git', 'tmux', 'nvim', 'rg', 'fd', 'fzf', 'bat', 'opencode', 'python3']:
            self.assertIn(name, server)
            self.assertIn(name, workstation)

    def test_workstation_distinguishes_required_from_optional(self):
        by_kind = {}
        for kind, name, _ in components('workstation'):
            by_kind.setdefault(kind, set()).add(name)
        self.assertIn('opencode', by_kind['required'])
        self.assertIn('zed', by_kind['required'])
        self.assertEqual(by_kind['optional'] & by_kind['required'], set())
        self.assertLessEqual({'lazygit', 'lazydocker', 'zoxide', 'atuin'}, by_kind['optional'])

    def test_every_line_is_well_formed_and_commands_are_executable_names(self):
        for profile in ('server', 'workstation'):
            with self.subTest(profile=profile):
                entries = components(profile)
                self.assertTrue(entries)
                for kind, name, description in entries:
                    self.assertIn(kind, ('required', 'optional'))
                    self.assertRegex(name, r'^[a-z0-9][a-z0-9_-]*$')
                    self.assertTrue(description.strip())
                names = [name for _, name, _ in entries]
                self.assertEqual(len(names), len(set(names)))

    def test_minimum_versions_are_profile_specific(self):
        def minimum(profile):
            for _, name, rest in components(profile):
                if name == 'nvim':
                    return rest.split(' ', 1)[0]
            self.fail('nvim missing from the manifest')
        # LazyVim (workstation) needs 0.11; the server config only needs 0.10 for
        # vim.ui.clipboard.osc52 and degrades gracefully below it (pcall guard).
        self.assertEqual(minimum('workstation'), '0.11')
        self.assertEqual(minimum('server'), '0.10')

    def test_manifest_drives_both_display_and_verification(self):
        profiles = (ROOT / 'installer/profiles.sh').read_text()
        display = profiles.split('show_components() {', 1)[1].split('\n}', 1)[0]
        verify = profiles.split('verify_profile() {', 1)[1].split('\n}', 1)[0]
        self.assertIn('profile_components', display)
        self.assertIn('profile_components', verify)
        self.assertNotIn('binaries=(', verify)

    def test_manifest_rejects_unknown_profile_or_platform(self):
        for args in [('server', 'plan9'), ('desktop', 'linux'), ('', '')]:
            with self.subTest(args=args):
                script = 'source "$1/installer/components.sh"; profile_components "$2" "$3"'
                result = subprocess.run([BASH, '-euc', script, '_', str(ROOT), *args],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, '')


class ProfileBoundaryTests(unittest.TestCase):
    def isolated(self, directory):
        env = os.environ.copy()
        env.update(HOME=directory, XDG_CONFIG_HOME=directory + '/.config',
                   XDG_STATE_HOME=directory + '/.state', SHELL='/bin/bash')
        return env

    def configure_server(self, directory):
        script = '''
            source "$1/setup.sh"
            PROFILE=server; PACKAGE_MANAGER=native; CONFIG_ONLY=true
            detect_platform; initialize_state
            trap cleanup_setup EXIT
            configure_profile
        '''
        return subprocess.run([BASH, '-euc', script, '_', str(ROOT)],
                              env=self.isolated(directory), capture_output=True, text=True)

    def test_server_profile_never_removes_workstation_tools_or_configs(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = home / '.config'
            workstation_files = [config / 'zed/settings.json', config / 'alacritty/alacritty.toml']
            workstation_dirs = [config / 'nvim/lua/config', home / '.oh-my-zsh', home / '.cargo']
            for path in workstation_files:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(f'managed-by-workstation:{path.name}\n')
            for path in workstation_dirs:
                path.mkdir(parents=True, exist_ok=True)
                (path / '.keep').write_text('workstation content\n')
            (home / '.zshrc').write_text('# workstation zshrc\n')
            (home / '.tmux.conf').write_text('# workstation tmux.conf\n')
            original_tmux = (home / '.tmux.conf').read_text()

            result = self.configure_server(directory)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

            # Workstation-only configs the Server profile does not own stay intact.
            for path in workstation_files:
                self.assertEqual(path.read_text(), f'managed-by-workstation:{path.name}\n')
            for path in workstation_dirs:
                self.assertTrue(path.is_dir(), f'{path} must survive a Server profile')
                self.assertEqual((path / '.keep').read_text(), 'workstation content\n')
            self.assertIn('# workstation zshrc', (home / '.zshrc').read_text())

            # Server does replace the tmux config it owns, but never silently:
            # the original is preserved in the run's backup directory.
            self.assertEqual((home / '.tmux.conf').resolve(), ROOT / 'server/tmux.conf')
            backups = list((home / '.state').rglob('.tmux.conf'))
            self.assertTrue(any(p.read_text() == original_tmux for p in backups))

    def test_server_profile_does_not_invoke_package_removal_or_service_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            mocks = home / 'bin'
            mocks.mkdir()
            calls = home / 'calls'
            stub = '''#!/usr/bin/env python3
import json, os, sys
with open(os.environ["MOCK_CALLS"], "a") as out:
    out.write(json.dumps([os.path.basename(sys.argv[0]), *sys.argv[1:]]) + "\\n")
if os.path.basename(sys.argv[0]) in ("apt-get", "dnf", "pacman", "systemctl", "ufw",
                                     "iptables", "nft", "sshd", "userdel", "chsh"):
    sys.exit(91)
'''
            for name in ['apt-get', 'dnf', 'pacman', 'systemctl', 'ufw', 'iptables', 'nft',
                         'sshd', 'userdel', 'chsh', 'sudo']:
                path = mocks / name
                path.write_text(stub)
                path.chmod(0o755)
            script = '''
                source "$1/setup.sh"
                PROFILE=server; PACKAGE_MANAGER=native; CONFIG_ONLY=false; UPGRADE=false
                HARDWARE=false; HARDWARE_ONLY=false; CHANGE_SHELL=false
                detect_platform; initialize_state
                trap cleanup_setup EXIT
                # Only exercise the profile's install/configure paths with the
                # network/package side effects stubbed out.
                run_installer() { printf 'download:%s\\n' "$1" >> "$MOCK_CALLS"; return 0; }
                install_opencode() { return 0; }
                install_profile
                configure_profile
            '''
            env = self.isolated(directory)
            env.update(PATH=str(mocks) + ':' + env['PATH'], MOCK_CALLS=str(calls))
            result = subprocess.run([BASH, '-euc', script, '_', str(ROOT)],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            log = calls.read_text() if calls.exists() else ''
            for forbidden in ['apt-get', 'dnf', 'pacman', 'systemctl', 'ufw', 'iptables',
                              'nft', 'sshd', 'userdel', 'chsh']:
                self.assertNotIn(f'"{forbidden}"', log)

    def test_installer_has_no_firewall_ssh_or_removal_management(self):
        sources = [ROOT / 'setup.sh'] + sorted((ROOT / 'installer').glob('*.sh'))
        forbidden = re.compile(
            r'\b(ufw|firewall-cmd|iptables|nft\s|sshd|ssh\.service|nftables'
            r'|apt-get\s+(remove|purge|autoremove)|dnf\s+remove|pacman\s+-R|brew\s+(uninstall|remove)'
            r'|userdel|gpasswd)\b')
        for path in sources:
            with self.subTest(file=path.name):
                for number, line in enumerate(path.read_text().splitlines(), 1):
                    self.assertIsNone(forbidden.search(line),
                                      f'{path.name}:{number} manages system surface outside the profile scope')

    def test_systemctl_only_appears_inside_the_hardware_guard(self):
        path = ROOT / 'installer/privileged.sh'
        text = path.read_text()
        guard_lines = [i for i, line in enumerate(text.splitlines())
                       if 'if [[ "$hardware" == true ]]' in line]
        self.assertTrue(guard_lines, 'the hardware guard must exist')
        guard = guard_lines[0]
        for number, line in enumerate(text.splitlines()):
            if 'systemctl' in line:
                self.assertGreater(number, guard,
                                   'systemctl must stay behind the explicit hardware opt-in')

    def test_show_actions_prints_the_exact_manifest(self):
        for profile, expected_required, absent in [
            ('server', ['git', 'tmux', 'nvim', 'opencode'], ['zed', 'node', 'lazygit']),
            ('workstation', ['git', 'tmux', 'nvim', 'opencode', 'zed', 'node'], []),
        ]:
            with self.subTest(profile=profile), tempfile.TemporaryDirectory() as directory:
                result = subprocess.run([BASH, str(ROOT / 'setup.sh'), '--profile', profile, '--dry-run'],
                                        env=self.isolated(directory), capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                required = [name for kind, name, _ in components(profile) if kind == 'required']
                optional = [name for kind, name, _ in components(profile) if kind == 'optional']
                self.assertIn(f'Required tools ({len(required)}): {" ".join(required)}', result.stdout)
                for name in expected_required:
                    self.assertIn(name, result.stdout)
                for name in absent:
                    self.assertNotIn(f' {name} ', result.stdout + ' ')
                if optional:
                    self.assertIn(f'Optional tools ({len(optional)}, absence is not fatal): {" ".join(optional)}',
                                  result.stdout)

    def test_verify_reports_missing_required_and_tolerates_missing_optional(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            stubs = home / 'bin'
            stubs.mkdir()
            # Restrict PATH so the omitted tools cannot be found on the host, but
            # keep the few external helpers the manifest and checks need.
            coreutils = home / 'coreutils'
            coreutils.mkdir()
            for name in ['cat', 'grep', 'sed', 'readlink']:
                target = shutil.which(name)
                if target:
                    (coreutils / name).symlink_to(target)
            entries = components('workstation')
            omitted_required = 'zed'
            omitted_optional = 'atuin'
            for kind, name, _ in entries:
                if name in (omitted_required, omitted_optional):
                    continue
                stub = stubs / name
                stub.write_text('#!/bin/sh\nif [ "$1" = --version ]; then echo "tool v2.0.0"; fi\n')
                stub.chmod(0o755)
            script = '''
                source "$1/installer/common.sh"
                source "$1/installer/components.sh"
                source "$1/installer/profiles.sh"
                PROFILE=workstation; PLATFORM=linux
                verify_configs() { return 0; }
                verify_profile
            '''
            env = self.isolated(directory)
            env.update(PATH=f'{stubs}:{coreutils}')
            result = subprocess.run([BASH, '-euc', script, '_', str(ROOT)],
                                    env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(f'Missing required tool: {omitted_required}', result.stderr)
            self.assertIn(f'Optional tool not present: {omitted_optional}', result.stdout)
            self.assertNotIn(f'Missing required tool: {omitted_optional}', result.stderr)


if __name__ == '__main__':
    unittest.main()
