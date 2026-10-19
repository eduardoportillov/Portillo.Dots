"""End-to-end remote deployment tests against a fake SSH/rsync transport.

No network, no real remote host and no real tmux: ssh_cmd/rsync_cmd are replaced
so every remote script executes against a temporary HOME that models the server.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which('bash')

FAKE_TRANSPORT = r"""
# --- fake transport: run remote commands against $FAKE_HOME, never over the wire
ssh_cmd() {
  printf '%s\n' "$*" >> "$FAKE_CALLS"
  local cmd="$*"
  case "$cmd" in
    'uname -s') printf '%s\n' "${FAKE_PLATFORM:-Linux}"; return 0 ;;
    'uname -m') printf '%s\n' "${FAKE_ARCH:-x86_64}"; return 0 ;;
    'true') return 0 ;;
  esac
  HOME="$FAKE_HOME" USER="${USER:-test}" bash -c "$cmd"
}
rsync_cmd() {
  printf 'rsync %s\n' "$*" >> "$FAKE_CALLS"
  local args=() a dest
  for a in "$@"; do
    case "$a" in
      "$HOST:"*)
        dest="${a#*:}"
        # The real transport resolves ~ on the remote side; resolve it locally.
        args+=("${dest/#\~/$FAKE_HOME}")
        ;;
      *) args+=("$a") ;;
    esac
  done
  command rsync -az "${args[@]}"
}
ssh_interactive() {
  printf 'interactive %s\n' "$*" >> "$FAKE_CALLS"
  HOME="$FAKE_HOME" USER="${USER:-test}" bash -c "$*"
}
"""


class FakeRemote:
    def __init__(self, directory, arch='x86_64', platform='Linux'):
        self.home = Path(directory) / 'remote-home'
        self.home.mkdir(parents=True, exist_ok=True)
        self.calls = Path(directory) / 'calls'
        self.calls.write_text('')
        self.arch = arch
        self.platform = platform

    def run(self, script, extra_env=None, check=True, timeout=60):
        env = {**os.environ, 'FAKE_HOME': str(self.home), 'FAKE_CALLS': str(self.calls),
               'FAKE_ARCH': self.arch, 'FAKE_PLATFORM': self.platform, 'HOME': str(self.home),
               'SHELL': '/bin/bash'}
        env.update(extra_env or {})
        result = subprocess.run([BASH, '-euc', f'source "$1/remote.sh"\n{FAKE_TRANSPORT}\n{script}',
                                 '_', str(ROOT)], env=env, capture_output=True, text=True, timeout=timeout)
        if check and result.returncode != 0:
            raise AssertionError(f'{result.returncode}\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}')
        return result

    def runtime(self):
        return self.home / '.portillo-remote'

    def calls_text(self):
        return self.calls.read_text()


class DeployLifecycleTests(unittest.TestCase):
    def fake(self, directory, **kwargs):
        return FakeRemote(directory, **kwargs)

    def deploy(self, remote, skip_bins=True, check=True):
        skip = 'SKIP_BINS=1;' if skip_bins else 'SKIP_BINS=0;'
        script = f'''
            HOST="fakehost"
            {skip}
            init_ssh_socket
            check_prerequisites
            check_ssh_connection
            prepare_remote_base
            deploy_configs
            deploy_shell_environment
            finalize_remote_deploy
            cleanup_ssh
        '''
        return remote.run(script, check=check)

    def test_full_deploy_builds_runtime_and_never_touches_host_tmux(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = self.fake(directory)
            self.deploy(remote)
            runtime = remote.runtime()
            self.assertTrue((runtime / 'zsh/.dircolors').is_file())
            self.assertTrue((runtime / 'server/tmux.conf').is_file())
            self.assertTrue((runtime / 'nvim/init.lua').is_file())
            self.assertFalse((remote.home / '.tmux.conf').exists(),
                             'remote deploy must not own the host tmux config')
            self.assertFalse((remote.home / '.tmux/plugins').exists())
            shipped = [p.name for p in runtime.rglob('*') if p.is_file()]
            self.assertNotIn('npm', shipped)
            self.assertNotIn('connections.lua', shipped)
            # Managed shell block is installed in the user's bashrc.
            self.assertIn('Portillo.Dots', (remote.home / '.bashrc').read_text())
            # The shell environment never leaks credential files.
            for name in shipped:
                self.assertNotIn('.env', name)

    def test_transfer_failure_rolls_back_and_keeps_previous_runtime(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = self.fake(directory)
            self.deploy(remote)
            marker = remote.runtime() / 'zsh/.dircolors'
            first = marker.read_text()
            result = remote.run('''
                HOST="fakehost"
                SKIP_BINS=1
                init_ssh_socket
                check_ssh_connection
                prepare_remote_base
                rsync_cmd() { printf 'rsync failed\n' >&2; return 12; }
                deploy_configs || { abort_remote_deploy || true; exit 42; }
                printf 'MUST NOT REACH\n'
            ''', check=False)
            self.assertEqual(result.returncode, 42)
            self.assertNotIn('MUST NOT REACH', result.stdout)
            self.assertEqual(marker.read_text(), first, 'the previous deploy must survive')
            self.assertFalse(any(remote.home.glob('.portillo-remote-stage-*')),
                             'partial staging must be rolled back')

    def test_binary_install_failure_rolls_back_to_previous_runtime(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = self.fake(directory)
            self.deploy(remote)
            first = (remote.runtime() / 'zsh/.dircolors').read_text()
            result = remote.run('''
                HOST="fakehost"
                SKIP_BINS=0
                init_ssh_socket
                check_ssh_connection
                prepare_remote_base
                deploy_configs
                deploy_shell_environment
                deploy_binaries() { printf 'binary install failed\n' >&2; return 9; }
                deploy_binaries || { abort_remote_deploy || true; exit 43; }
                printf 'MUST NOT REACH\n'
            ''', check=False)
            self.assertEqual(result.returncode, 43)
            self.assertEqual((remote.runtime() / 'zsh/.dircolors').read_text(), first)
            self.assertFalse(any(remote.home.glob('.portillo-remote-old-*')),
                             'rollback must not leave the old directory behind')

    def test_teardown_removes_only_the_managed_runtime(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = self.fake(directory)
            self.deploy(remote)
            unrelated = remote.home / 'unrelated-file'
            unrelated.write_text('keep me')
            result = remote.run('''
                HOST="fakehost"
                FORCE=1
                init_ssh_socket
                cmd_teardown
                cleanup_ssh
            ''')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(remote.runtime().exists())
            self.assertEqual(unrelated.read_text(), 'keep me')

    def test_cleanup_preserves_runtime_while_dedicated_tmux_is_active(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = self.fake(directory)
            self.deploy(remote)
            # Simulate an active dedicated tmux session through the runtime binary.
            tmux_dir = remote.runtime() / 'bin'
            tmux_dir.mkdir(parents=True, exist_ok=True)
            fake_tmux = tmux_dir / 'tmux'
            fake_tmux.write_text('#!/bin/sh\nexit 0\n')
            fake_tmux.chmod(0o755)
            result = remote.run('cleanup_remote_runtime')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(remote.runtime().exists(),
                            'an active dedicated tmux session must preserve the runtime')
            self.assertIn('preserved', result.stdout + result.stderr)

    def test_cleanup_removes_runtime_without_active_session(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = self.fake(directory)
            self.deploy(remote)
            result = remote.run('cleanup_remote_runtime')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(remote.runtime().exists())


class ManifestTransportTests(unittest.TestCase):
    def test_rsync_payload_is_allowlisted_and_free_of_secrets(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = FakeRemote(directory)
            secret = ROOT / 'opencode' / '.env'
            existed = secret.exists()
            if not existed:
                secret.write_text('FAKE_SECRET_VALUE=do-not-ship\n')
            try:
                remote.run('''
                    HOST="fakehost"
                    SKIP_BINS=1
                    init_ssh_socket
                    prepare_remote_base
                    deploy_configs
                    cleanup_ssh
                ''')
            finally:
                if not existed:
                    secret.unlink()
            runtime = remote.runtime()
            self.assertTrue(runtime.is_dir())
            shipped = [str(p.relative_to(runtime)) for p in runtime.rglob('*') if p.is_file()]
            self.assertTrue(shipped)
            for name in shipped:
                # The OpenCode config directory and credential files never ship.
                self.assertFalse(name.startswith('opencode/'), name)
                self.assertNotIn('.env', Path(name).name)
                self.assertNotIn('secrets.env', name)
                self.assertNotIn('connections.lua', name)
            for path in runtime.rglob('*'):
                if path.is_file():
                    self.assertNotIn('do-not-ship', path.read_text(errors='ignore'))

    def test_paths_with_spaces_round_trip_through_the_host_table(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = FakeRemote(directory)
            table = Path(directory) / 'hosts.local.conf'
            result = remote.run(f'''
                HOSTS_LOCAL_CONF="{table}"
                save_host_path "host two" "/srv/my app (v2)/dir"
                get_host_path "host two"
            ''')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines()[-1].strip(), '/srv/my app (v2)/dir')

    def test_equals_sign_in_a_path_round_trips(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = FakeRemote(directory)
            table = Path(directory) / 'hosts.local.conf'
            result = remote.run(f'''
                HOSTS_LOCAL_CONF="{table}"
                save_host_path "host" "/srv/build=release/dir"
                get_host_path "host"
            ''')
            self.assertEqual(result.stdout.splitlines()[-1].strip(), '/srv/build=release/dir')

    def test_paths_with_delimiters_are_rejected(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = FakeRemote(directory)
            table = Path(directory) / 'hosts.local.conf'
            for index, path in enumerate(['/srv/a|b', '/srv/a\nb']):
                result = remote.run(f'''
                    HOSTS_LOCAL_CONF="{table}"
                    save_host_path "host" "$TEST_PATH_{index}"
                ''', extra_env={f'TEST_PATH_{index}': path}, check=False)
                self.assertNotEqual(result.returncode, 0, repr(path))
            self.assertFalse(table.exists(), 'a rejected path must not be recorded')


class PlatformGateTests(unittest.TestCase):
    def test_unsupported_remote_platform_refuses_binaries_without_skip(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = FakeRemote(directory, platform='Darwin')
            result = remote.run('''
                HOST="fakehost"
                SKIP_BINS=0
                init_ssh_socket
                deploy_binaries
            ''', check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('skip-bins', result.stdout + result.stderr)
            self.assertNotIn('Downloading', result.stdout,
                             'no download may start before the platform gate')

    def test_unsupported_remote_architecture_is_reported(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = FakeRemote(directory, arch='mips64')
            result = remote.run('''
                HOST="fakehost"
                SKIP_BINS=0
                init_ssh_socket
                deploy_binaries
            ''', check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Unsupported remote architecture', result.stdout + result.stderr)

    def test_skip_bins_leaves_configs_without_downloading(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = FakeRemote(directory)
            result = remote.run('''
                HOST="fakehost"
                SKIP_BINS=1
                init_ssh_socket
                prepare_remote_base
                deploy_configs
                deploy_binaries
                finalize_remote_deploy
                cleanup_ssh
            ''')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((remote.runtime() / 'zsh/.dircolors').is_file())
            self.assertFalse((remote.runtime() / 'downloads').exists(),
                             'skip-bins must not download anything')
            self.assertNotIn('Downloading', result.stdout)


class CacheLifecycleTests(unittest.TestCase):
    CACHE_FILES = ['nvim.tar.gz', 'rg.tar.gz', 'fd.tar.gz', 'fzf.tar.gz',
                   'lazygit.tar.gz', 'node.tar.xz', 'zig.tar.xz', 'stylua.zip']

    def cache_dir(self, directory):
        cache = Path(directory) / 'cache/portillo-remote-downloads/linux-x86_64'
        cache.mkdir(parents=True)
        return cache

    def test_refresh_bins_clears_only_known_artifacts(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = FakeRemote(directory)
            cache = self.cache_dir(directory)
            for name in self.CACHE_FILES + ['.integrity.json', 'user-notes.txt', 'keep-me.tar.gz']:
                (cache / name).write_text('cached')
            result = remote.run('''
                HOST="fakehost"
                SKIP_BINS=0
                init_ssh_socket
                REMOTE_ARCH=x86_64
                REFRESH_BINS=1
                download_binaries_locally() { return 0; }
                python3() { return 0; }
                rsync_cmd() { return 0; }
                ssh_cmd() { case "$*" in 'uname -s') echo Linux ;; 'uname -m') echo x86_64 ;;
                            *) cat >/dev/null; return 0 ;; esac; }
                deploy_binaries
            ''', extra_env={'XDG_CACHE_HOME': str(cache.parent.parent)}, check=False)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            remaining = sorted(p.name for p in cache.iterdir())
            self.assertIn('user-notes.txt', remaining, 'unknown cache files must survive')
            self.assertIn('keep-me.tar.gz', remaining)
            for name in self.CACHE_FILES:
                self.assertNotIn(name, remaining)
            self.assertNotIn('.integrity.json', remaining)

    def test_without_refresh_existing_cache_is_kept(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = FakeRemote(directory)
            cache = self.cache_dir(directory)
            for name in self.CACHE_FILES + ['.integrity.json']:
                (cache / name).write_text('cached')
            result = remote.run('''
                HOST="fakehost"
                SKIP_BINS=0
                init_ssh_socket
                REMOTE_ARCH=x86_64
                REFRESH_BINS=0
                download_binaries_locally() { return 0; }
                python3() { return 0; }
                rsync_cmd() { return 0; }
                ssh_cmd() { case "$*" in 'uname -s') echo Linux ;; 'uname -m') echo x86_64 ;;
                            *) cat >/dev/null; return 0 ;; esac; }
                deploy_binaries
            ''', extra_env={'XDG_CACHE_HOME': str(cache.parent.parent)}, check=False)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            remaining = sorted(p.name for p in cache.iterdir())
            for name in self.CACHE_FILES + ['.integrity.json']:
                self.assertIn(name, remaining)

    def test_corrupt_cached_download_is_rejected_before_transfer(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = FakeRemote(directory)
            cache = self.cache_dir(directory)
            import hashlib
            import json
            pins = {}
            for name in self.CACHE_FILES:
                (cache / name).write_bytes(b'cached payload')
                pins[name] = {'sha256': hashlib.sha256(b'cached payload').hexdigest(), 'version': 'test'}
            (cache / 'node.tar.xz').write_bytes(b'CORRUPTED')
            (cache / '.integrity.json').write_text(json.dumps(pins))
            result = remote.run('''
                HOST="fakehost"
                SKIP_BINS=0
                init_ssh_socket
                REMOTE_ARCH=x86_64
                download_binaries_locally() { return 0; }
                rsync_cmd() { printf 'TRANSFERRED\n' >&2; return 0; }
                deploy_binaries
            ''', extra_env={'XDG_CACHE_HOME': str(cache.parent.parent)}, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Checksum mismatch', result.stdout + result.stderr)
            self.assertNotIn('TRANSFERRED', result.stdout + result.stderr,
                             'a corrupt archive must never be transferred')


class RedeployTests(unittest.TestCase):
    def test_redeploy_updates_the_runtime_in_place(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = FakeRemote(directory)
            script = '''
                HOST="fakehost"
                SKIP_BINS=1
                init_ssh_socket
                prepare_remote_base
                deploy_configs
                deploy_shell_environment
                finalize_remote_deploy
                cleanup_ssh
            '''
            remote.run(script)
            runtime = remote.runtime()
            dircolors = runtime / 'zsh/.dircolors'
            original = dircolors.read_text()
            # Simulate a source change so the second deploy must replace content.
            dircolors.write_text(original + '\n# changed by test\n')
            remote.run(script)
            self.assertEqual(dircolors.read_text(), original,
                             'redeploy must restore the tracked source content')
            self.assertFalse(any(remote.home.glob('.portillo-remote-stage-*')))
            self.assertFalse(any(remote.home.glob('.portillo-remote-old-*')),
                             'a successful redeploy must not leave rollback dirs')
            self.assertTrue((runtime / 'server/tmux.conf').is_file())


class TmuxIsolationTests(unittest.TestCase):
    REMOTE_SCRIPTS = ['remote.sh', 'remote/install-binaries.sh', 'remote/shell-environment.sh',
                      'remote/connect.sh', 'remote/generate-rc.sh', 'remote/lib.sh']

    @staticmethod
    def strip_strings(line):
        """Blank out quoted literals so message text is not mistaken for a call."""
        return re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', '""', line)

    def test_every_remote_tmux_invocation_uses_the_dedicated_socket(self):
        invocation = re.compile(r'(?:^|[;&|(]|\$\()\s*tmux\s+\S')
        offenders = []
        for name in self.REMOTE_SCRIPTS:
            for number, line in enumerate((ROOT / name).read_text().splitlines(), 1):
                stripped = line.strip()
                if stripped.startswith('#') or re.match(r'^\w+\)', stripped):
                    continue  # comments and case labels
                code = self.strip_strings(line)
                if not invocation.search(code):
                    continue
                if '-L ' in code or 'TMUX_SOCKET' in code or 'ptmux' in code:
                    continue
                offenders.append(f'{name}:{number}: {stripped}')
        self.assertEqual(offenders, [],
                         'remote tmux must always use the dedicated socket:\n' + '\n'.join(offenders))

    def test_no_remote_script_writes_the_host_tmux_config(self):
        offenders = []
        for name in self.REMOTE_SCRIPTS:
            for number, line in enumerate((ROOT / name).read_text().splitlines(), 1):
                if line.strip().startswith('#'):
                    continue
                code = self.strip_strings(line)
                if re.search(r'(>|>>|cp|mv|ln)\s+\S*\.tmux\.conf', code):
                    offenders.append(f'{name}:{number}: {line.strip()}')
        self.assertEqual(offenders, [], 'remote deploy must not own ~/.tmux.conf')


class ConnectFlowTests(unittest.TestCase):
    def test_connect_deploys_then_cleans_up_by_default(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = FakeRemote(directory)
            result = remote.run('''
                HOST="fakehost"
                SKIP_BINS=1
                NO_CD=1
                CLEANUP=1
                NO_TMUX=1
                init_ssh_socket
                ssh_interactive() { printf 'interactive %s\n' "$*" >> "$FAKE_CALLS"; return 0; }
                cmd_connect
                cleanup_ssh
            ''')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('interactive', remote.calls_text())
            self.assertFalse(remote.runtime().exists(),
                             'default --cleanup must remove the transient runtime')
            self.assertTrue((remote.home / '.portillo-dots-remote-state').is_dir(),
                            'persistent shell state survives the transient cleanup')

    def test_connect_no_cleanup_preserves_the_runtime(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = FakeRemote(directory)
            result = remote.run('''
                HOST="fakehost"
                SKIP_BINS=1
                NO_CD=1
                CLEANUP=0
                NO_TMUX=1
                init_ssh_socket
                ssh_interactive() { printf 'interactive %s\n' "$*" >> "$FAKE_CALLS"; return 0; }
                cmd_connect
                cleanup_ssh
            ''')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(remote.runtime().is_dir(),
                            '--no-cleanup must keep the runtime for later use')

    def test_connect_failure_still_cleans_the_transient_runtime(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = FakeRemote(directory)
            result = remote.run('''
                HOST="fakehost"
                SKIP_BINS=1
                NO_CD=1
                CLEANUP=1
                NO_TMUX=1
                init_ssh_socket
                ssh_interactive() { printf 'interactive failed\n' >> "$FAKE_CALLS"; return 7; }
                cmd_connect
                status=$?
                cleanup_ssh
                exit "$status"
            ''', check=False)
            self.assertEqual(result.returncode, 7)
            self.assertFalse(remote.runtime().exists(),
                             'a failed session must not leave a transient runtime behind')

    def test_connect_stages_only_the_allowlisted_files(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            remote = FakeRemote(directory)
            secret = ROOT / 'opencode' / '.env'
            existed = secret.exists()
            if not existed:
                secret.write_text('FAKE_SECRET_VALUE=do-not-ship\n')
            try:
                remote.run('''
                    HOST="fakehost"
                    SKIP_BINS=1
                    NO_CD=1
                    CLEANUP=0
                    NO_TMUX=1
                    init_ssh_socket
                    ssh_interactive() { return 0; }
                    cmd_connect
                    cleanup_ssh
                ''')
            finally:
                if not existed:
                    secret.unlink()
            for path in remote.runtime().rglob('*'):
                if path.is_file():
                    self.assertNotIn('do-not-ship', path.read_text(errors='ignore'))
            self.assertFalse((remote.runtime() / 'opencode').exists())


if __name__ == '__main__':
    unittest.main()
