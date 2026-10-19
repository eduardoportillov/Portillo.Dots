"""Security of configuration, logs, backups and committed content."""
import math
import collections
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which('bash')

PLACEHOLDER = re.compile(
    r'(?i)(example|sample|dummy|placeholder|fake|test|xxxx|your[_-]|<[^>]+>|\{\{|\{env:|do-not|redact)')

SECRET_PATTERNS = [
    ('AWS access key', re.compile(r'AKIA[0-9A-Z]{16}')),
    ('GitHub token', re.compile(r'gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}')),
    ('OpenAI/Anthropic key', re.compile(r'\bsk-(?:ant-)?[A-Za-z0-9_-]{20,}')),
    ('Slack token', re.compile(r'\bxox[baprs]-[A-Za-z0-9-]{10,}')),
    ('Google API key', re.compile(r'\bAIza[0-9A-Za-z_-]{35}')),
    ('Stripe live key', re.compile(r'\b[rs]k_live_[0-9a-zA-Z]{20,}')),
    ('JWT', re.compile(r'\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}')),
    ('Private key block', re.compile(r'-----BEGIN [A-Z ]*PRIVATE KEY-----')),
    ('Credential assignment', re.compile(
        r'(?i)(?:api[_-]?key|authorization|secret|token)\s*[:=]\s*["\']?(?:Bearer\s+)?[A-Za-z0-9_\-./+=]{32,}')),
]

SECRET_NAME = re.compile(r'(?i)(\.env|secret|credential|opencode\.jsonc|\.pem$|id_rsa|id_ed25519|\.key$)')


def scan_text(label, text):
    hits = []
    for name, rx in SECRET_PATTERNS:
        for match in rx.finditer(text):
            value = match.group(0)
            context = text[max(0, match.start() - 80):match.start()]
            if PLACEHOLDER.search(value) or PLACEHOLDER.search(context):
                continue
            hits.append(f'{label}: {name}: {value[:6]}...{value[-4:]}')
    return hits


class SecretScanTests(unittest.TestCase):
    def test_repository_credential_files_are_private(self):
        for name in ['opencode/.env', 'opencode/opencode.jsonc']:
            path = ROOT / name
            if not path.exists() or path.is_symlink():
                continue
            mode = stat.S_IMODE(path.stat().st_mode)
            self.assertEqual(mode & 0o077, 0, f'{name} must not be group/world accessible (mode {oct(mode)})')
        logs = ROOT / 'logs'
        if logs.is_dir() and not logs.is_symlink():
            mode = stat.S_IMODE(logs.stat().st_mode)
            self.assertEqual(mode & 0o077, 0, f'logs/ must not be group/world accessible (mode {oct(mode)})')

    def test_no_secret_patterns_in_tracked_content(self):
        tracked = [p for p in subprocess.check_output(
            ['git', '-C', str(ROOT), 'ls-files', '-z']).decode().split('\0') if p]
        hits = []
        for name in tracked:
            path = ROOT / name
            if not path.is_file() or path.is_symlink():
                continue
            hits += scan_text(name, path.read_text(errors='replace'))
        self.assertEqual(hits, [], 'tracked content must contain no secret patterns')

    def test_no_secret_patterns_in_history_blobs_with_secret_names(self):
        commits = subprocess.run(['git', '-C', str(ROOT), 'rev-list', '--count', '--all'],
                                 capture_output=True, text=True)
        if commits.returncode != 0 or commits.stdout.strip() in ('', '0'):
            self.skipTest('repository has no history to scan (fresh or shallow checkout)')
        lines = subprocess.check_output(
            ['git', '-C', str(ROOT), 'rev-list', '--objects', '--all'], text=True).splitlines()
        seen = set()
        hits = []
        scanned = 0
        for line in lines:
            parts = line.split(' ', 1)
            if len(parts) != 2:
                continue
            sha, name = parts
            if sha in seen or not name or name.endswith('/'):
                continue
            seen.add(sha)
            if not SECRET_NAME.search(name):
                continue
            blob = subprocess.run(['git', '-C', str(ROOT), 'cat-file', '-p', sha],
                                  capture_output=True, text=True)
            if blob.returncode != 0:
                continue
            scanned += 1
            hits += scan_text('HISTORY:' + name, blob.stdout)
        self.assertGreater(scanned, 0, 'the scan must actually inspect history')
        self.assertEqual(hits, [], 'git history must contain no secret patterns')

    def test_secret_bearing_names_are_never_tracked(self):
        tracked = subprocess.check_output(
            ['git', '-C', str(ROOT), 'ls-files', '-z']).decode().split('\0')
        offenders = []
        for name in filter(None, tracked):
            if name.endswith('.env.example') or name in ('opencode/load-secrets.sh',):
                continue
            if re.search(r'(^|/)(\.env($|\.)|secrets\.env$|opencode\.jsonc$)', name):
                offenders.append(name)
        self.assertEqual(offenders, [])


class PermissionTests(unittest.TestCase):
    def run_security(self, script, home, extra=None):
        env = {**os.environ, 'HOME': str(home), 'XDG_STATE_HOME': str(home / '.state'),
               'XDG_CONFIG_HOME': str(home / '.config')}
        env.update(extra or {})
        return subprocess.run([BASH, '-euc', 'source "$1/setup.sh"\n' + script, '_', str(ROOT)],
                              env=env, capture_output=True, text=True, timeout=30)

    def test_secure_file_tightens_only_when_needed(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            home = Path(directory)
            loose = home / 'loose.env'
            loose.write_text('A=value\n')
            loose.chmod(0o664)
            tight = home / 'tight.env'
            tight.write_text('A=value\n')
            tight.chmod(0o400)
            result = self.run_security('secure_file "$HOME/loose.env"; secure_file "$HOME/tight.env"', home)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(stat.S_IMODE(loose.stat().st_mode), 0o600)
            self.assertIn('Restricted', result.stdout)
            # Already-private stays exactly as it is: never broaden permissions.
            self.assertEqual(stat.S_IMODE(tight.stat().st_mode), 0o400)

    def test_secure_file_ignores_symlinks_and_foreign_files(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            home = Path(directory)
            target = home / 'target.env'
            target.write_text('A=value\n')
            target.chmod(0o666)
            link = home / 'link.env'
            link.symlink_to(target)
            result = self.run_security('secure_file "$HOME/link.env"', home)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o666,
                             'a symlink must never be followed by the permission fixer')
            self.assertEqual(result.stdout, '')

    def test_verify_reports_group_accessible_credentials(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            home = Path(directory)
            env_file = home / 'repo' / 'opencode/.env'
            env_file.parent.mkdir(parents=True)
            env_file.write_text('A=value\n')
            env_file.chmod(0o664)
            script = 'REPO_DIR="$HOME/repo"; verify_secret_permissions'
            result = self.run_security(script, home)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('group/world accessible', result.stderr)
            env_file.chmod(0o600)
            result = self.run_security(script, home)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_known_secrets_are_restricted_after_configuration(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            home = Path(directory)
            env_file = home / 'repo' / 'opencode/.env'
            env_file.parent.mkdir(parents=True)
            env_file.write_text('A=value\n')
            env_file.chmod(0o664)
            logs = home / 'repo/logs'
            logs.mkdir(parents=True)
            logs.chmod(0o775)
            script = 'REPO_DIR="$HOME/repo"; secure_known_secrets'
            result = self.run_security(script, home)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(stat.S_IMODE(env_file.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(logs.stat().st_mode), 0o700)

    def test_symlinked_credential_path_is_reported_not_followed(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            home = Path(directory)
            real = home / 'elsewhere.env'
            real.write_text('A=value\n')
            real.chmod(0o666)
            link = home / 'repo' / 'opencode/.env'
            link.parent.mkdir(parents=True)
            link.symlink_to(real)
            script = 'REPO_DIR="$HOME/repo"; secure_known_secrets'
            result = self.run_security(script, home)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('symlink', result.stderr)
            self.assertEqual(stat.S_IMODE(real.stat().st_mode), 0o666)


class BackupSafetyTests(unittest.TestCase):
    def run_backup(self, script, home):
        env = {**os.environ, 'HOME': str(home), 'XDG_STATE_HOME': str(home / '.state'),
               'XDG_CONFIG_HOME': str(home / '.config'), 'SHELL': '/bin/bash'}
        return subprocess.run([BASH, '-euc', 'source "$1/setup.sh"; initialize_state\n' + script,
                               '_', str(ROOT)], env=env, capture_output=True, text=True, timeout=30)

    def test_backup_preserves_full_path_and_content(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            home = Path(directory)
            original = home / 'deep/nested/settings.json'
            original.parent.mkdir(parents=True)
            original.write_text('original content')
            result = self.run_backup('backup "$HOME/deep/nested/settings.json"', home)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(original.exists())
            saved = list((home / '.state').rglob('settings.json'))
            self.assertEqual(len(saved), 1)
            self.assertEqual(saved[0].read_text(), 'original content')
            # The backup tree mirrors the absolute path, so equal basenames never collide.
            self.assertIn('deep/nested', str(saved[0]))

    def test_equal_basenames_in_different_directories_never_collide(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            home = Path(directory)
            for folder in ['first', 'second']:
                path = home / folder / 'settings.json'
                path.parent.mkdir(parents=True)
                path.write_text(folder)
            result = self.run_backup(
                'backup "$HOME/first/settings.json"; backup "$HOME/second/settings.json"', home)
            self.assertEqual(result.returncode, 0, result.stderr)
            contents = sorted(p.read_text() for p in (home / '.state').rglob('settings.json'))
            self.assertEqual(contents, ['first', 'second'])

    def test_repeated_backups_stop_at_the_collision_instead_of_overwriting(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            home = Path(directory)
            path = home / 'settings.json'
            path.write_text('version-1')
            result = self.run_backup('backup "$HOME/settings.json"; printf "dir=%s\\n" "$BACKUP_DIR"', home)
            self.assertEqual(result.returncode, 0, result.stderr)
            backup_dir = Path(result.stdout.splitlines()[-1].split('=', 1)[1])
            saved = list(backup_dir.rglob('settings.json'))
            self.assertEqual(saved[0].read_text(), 'version-1')
            # Recreate the source and back it up again into the SAME run: the
            # mirrored absolute path collides and must stop, not overwrite.
            path.write_text('version-2')
            env = {**os.environ, 'HOME': str(home), 'XDG_STATE_HOME': str(home / '.state'),
                   'XDG_CONFIG_HOME': str(home / '.config'), 'SHELL': '/bin/bash'}
            result = subprocess.run(
                [BASH, '-euc',
                 'source "$1/setup.sh"; BACKUP_DIR="$2"; backup "$HOME/settings.json"', '_',
                 str(ROOT), str(backup_dir)],
                env=env, capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Backup collision', result.stderr)
            self.assertEqual(saved[0].read_text(), 'version-1',
                             'the first backup must never be overwritten')
            self.assertEqual(path.read_text(), 'version-2',
                             'the source must survive a refused backup')

    def test_backup_directory_is_private_to_the_owner(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            home = Path(directory)
            (home / 'file').write_text('x')
            result = self.run_backup('backup "$HOME/file"; printf "%s\\n" "$BACKUP_DIR"', home)
            self.assertEqual(result.returncode, 0, result.stderr)
            backup_dir = Path(result.stdout.splitlines()[-1])
            self.assertEqual(stat.S_IMODE(backup_dir.stat().st_mode), 0o700)
            state = home / '.state/portillo-dots'
            self.assertEqual(stat.S_IMODE(state.stat().st_mode), 0o700)


class LogSafetyTests(unittest.TestCase):
    def test_log_is_owner_only_and_receives_no_credential_values(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            home = Path(directory)
            env_file = home / 'repo' / 'opencode/.env'
            env_file.parent.mkdir(parents=True)
            secret = 'SUPER-SECRET-VALUE-DO-NOT-LOG'
            env_file.write_text(f'API_KEY={secret}\n')
            env_file.chmod(0o600)
            script = '''
                REPO_DIR="$HOME/repo"
                initialize_state
                trap cleanup_setup EXIT
                install_opencode_secrets "$HOME/repo/opencode/.env" "$HOME/.config/opencode/secrets.env"
                printf 'log=%s\\n' "$LOG"
            '''
            env = {**os.environ, 'HOME': str(home), 'XDG_STATE_HOME': str(home / '.state'),
                   'XDG_CONFIG_HOME': str(home / '.config')}
            result = subprocess.run([BASH, '-euc', 'source "$1/setup.sh"\n' + script, '_', str(ROOT)],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            log = home / '.state/portillo-dots/setup.log'
            self.assertTrue(log.is_file())
            self.assertEqual(stat.S_IMODE(log.stat().st_mode), 0o600)
            self.assertNotIn(secret, log.read_text(errors='replace'))
            self.assertNotIn(secret, result.stdout + result.stderr)

    def test_run_installer_writes_script_to_the_temporary_work_dir(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            home = Path(directory)
            script = '''
                REPO_DIR="$HOME/repo"; mkdir -p "$REPO_DIR"
                initialize_state
                trap cleanup_setup EXIT
                curl() { local out=""; while [ $# -gt 0 ]; do
                    case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac; done
                    printf '#!/bin/sh\\necho installer-ran\\n' > "$out"; }
                run_installer demo https://example.invalid/demo.sh
                printf 'work=%s exists=%s\\n' "$WORK_DIR" "$([ -f "$WORK_DIR/demo.sh" ] && echo yes || echo no)"
            '''
            env = {**os.environ, 'HOME': str(home), 'XDG_STATE_HOME': str(home / '.state'),
                   'XDG_CONFIG_HOME': str(home / '.config')}
            result = subprocess.run([BASH, '-euc', 'source "$1/setup.sh"\n' + script, '_', str(ROOT)],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('exists=yes', result.stdout)
            self.assertIn('/setup.', result.stdout)
            self.assertTrue(result.stdout.split('work=')[1].startswith(str(home / '.state')),
                            'downloaded scripts must live under the private state dir')


class FailurePreservationTests(unittest.TestCase):
    def test_failed_generation_leaves_the_previous_config_untouched(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            base = Path(directory)
            template, env_file, output = (base / n for n in ('template', '.env', 'output.jsonc'))
            previous = '{"model":"keep-me"}\n'
            output.write_text(previous)
            template.write_text('{"key":"{{MISSING}}"}')
            env_file.write_text('')
            result = subprocess.run(
                [str(shutil.which('python3')), '-B', str(ROOT / 'opencode/render-config.py'),
                 '--template', str(template), '--env', str(env_file), '--output', str(output)],
                capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_text(), previous)
            self.assertEqual([p.name for p in base.iterdir() if p.name.startswith('.opencode-')], [],
                             'no staging file may survive a failed generation')


if __name__ == '__main__':
    unittest.main()
