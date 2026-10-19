"""Independent hardware and o-tiling scripts.

Every desktop/extension command is stubbed: the tests never touch GNOME, dconf,
udev, sysfs or the network. o-tiling is installed byte-for-byte from its upstream
release — these tests assert that no local patch mechanism exists at all.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

from _support import tempdir

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which('bash')

STUBS = r'''
for name in gnome-extensions gsettings curl udevadm systemctl cpupower powerprofilesctl; do
  cat > "$STUB_DIR/$name" <<'STUB'
#!/bin/sh
printf '%s %s\n' "$(basename "$0")" "$*" >> "$CALLS"
exit 0
STUB
  chmod +x "$STUB_DIR/$name"
done
'''


class OtiringInstallTests(unittest.TestCase):
    def make_install(self, directory):
        base = Path(directory) / 'src'
        base.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / 'o-tiling/install.sh', base / 'install.sh')
        return base / 'install.sh'

    def run_install(self, directory, args=(), extra_env=None):
        install = self.make_install(directory)
        stubs = Path(directory) / 'stubs'
        stubs.mkdir(exist_ok=True)
        (Path(directory) / 'calls').write_text('')
        prelude = STUBS.replace('$STUB_DIR', str(stubs))
        home = Path(directory) / 'home'
        home.mkdir(exist_ok=True)
        env = {**os.environ, 'HOME': str(home), 'STUB_DIR': str(stubs),
               'CALLS': str(Path(directory) / 'calls'),
               'PATH': f'{stubs}:/usr/bin:/bin'}
        env.update(extra_env or {})
        result = subprocess.run([BASH, '-euc', prelude + f'\nbash "{install}" "$@"', '_', *args],
                               env=env, capture_output=True, text=True, timeout=30)
        return result, Path(directory) / 'calls'

    def test_default_run_touches_no_other_extension_or_global_setting(self):
        with tempdir() as directory:
            result, calls = self.run_install(directory, ['--force'])
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            log = calls.read_text()
            self.assertNotIn('rm -rf', log)
            self.assertNotIn('disable-extension-version-validation', log)
            self.assertNotIn('ding@rastersoft.com', log)
            self.assertIn('Tiling Shell intacta', result.stdout)
            self.assertIn('usa --remove-tiling-shell', result.stdout)

    def test_destructive_actions_are_gated_behind_flags(self):
        with tempdir() as directory:
            result, calls = self.run_install(
                directory, ['--force', '--remove-tiling-shell', '--disable-ding',
                            '--allow-version-mismatch'])
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            log = calls.read_text()
            self.assertIn('disable-extension-version-validation', log)
            self.assertIn('ding@rastersoft.com', log)
            self.assertIn('Desmontando Tiling Shell', result.stdout)

    def test_marker_records_only_the_upstream_version(self):
        with tempdir() as directory:
            result, _ = self.run_install(directory, ['--force'])
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            home = Path(directory) / 'home'
            marker = next(home.glob('.local/share/gnome-shell/extensions/*/.installed-version'))
            self.assertEqual(marker.read_text().strip(), 'version=v2.12.01',
                             'the marker tracks the upstream release and nothing else')

    def test_install_writes_only_the_marker_into_the_extension_dir(self):
        with tempdir() as directory:
            result, _ = self.run_install(directory, ['--force'])
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            home = Path(directory) / 'home'
            ext_dir = next(home.glob('.local/share/gnome-shell/extensions/*'))
            entries = sorted(p.name for p in ext_dir.iterdir())
            self.assertEqual(entries, ['.installed-version'],
                             f'no patch or edit may land in the extension dir: {entries}')
            self.assertFalse((Path(directory) / 'src/patches').exists(),
                             'the patches directory must not exist')

    def test_no_local_patch_mechanism_exists(self):
        self.assertFalse((ROOT / 'o-tiling/patches').exists(),
                         'local patches are out of scope: upstream only')
        text = (ROOT / 'o-tiling/install.sh').read_text()
        for forbidden in ['apply_local_patches', 'PATCH_SCRIPT', 'apply-patches',
                         'patch_digest', 'reapply_only']:
            self.assertNotIn(forbidden, text,
                             f'install.sh still references local patching: {forbidden}')

    def test_pinned_version_is_the_latest_known_release(self):
        text = (ROOT / 'o-tiling/install.sh').read_text()
        self.assertIn('OTILING_VERSION="${OTILING_VERSION:-v2.12.01}"', text)
        self.assertIn('version=${OTILING_VERSION}', text)

    def test_help_states_that_the_extension_is_not_patched(self):
        with tempdir() as directory:
            install = self.make_install(directory)
            result = subprocess.run([BASH, str(install), '--help'],
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('No parchea ni modifica ningún archivo', result.stdout)
            self.assertIn('verify.sh', result.stdout)

    def test_unknown_option_is_rejected(self):
        with tempdir() as directory:
            result, _ = self.run_install(directory, ['--delete-everything'])
            self.assertEqual(result.returncode, 2)
            self.assertIn('Opción desconocida', result.stderr)


class VerifyScriptTests(unittest.TestCase):
    SCRIPT = ROOT / 'o-tiling/verify.sh'

    def fake_gnome(self, directory):
        stubs = Path(directory) / 'bin'
        stubs.mkdir(parents=True, exist_ok=True)
        calls = Path(directory) / 'calls'
        calls.write_text('')
        stub = (
            '#!/bin/sh\n'
            f'printf \'%s %s\\n\' "$1" "$2" >> "{calls}"\n'
            'case "$1" in\n'
            '  info) echo "  State:        ENABLED" ;;\n'
            '  install|enable|disable) exit 0 ;;\n'
            'esac\n'
        )
        gnome = stubs / 'gnome-extensions'
        gnome.write_text(stub)
        gnome.chmod(0o755)
        return stubs

    def prepared_env(self, directory, journal_output):
        stubs = self.fake_gnome(directory)
        state = Path(directory) / '.state/portillo-dots/otiling-verify'
        state.mkdir(parents=True, exist_ok=True)
        (state / 'started-at').write_text('2026-10-16T00:00:00Z\n')
        journal = stubs / 'journalctl'
        journal.write_text('#!/bin/sh\ncat <<JOURNAL\n' + journal_output + 'JOURNAL\n')
        journal.chmod(0o755)
        return {**os.environ, 'HOME': str(directory),
                'XDG_STATE_HOME': str(Path(directory) / '.state'),
                'PATH': f'{stubs}:/usr/bin:/bin'}

    def test_verify_script_exists_is_executable_and_documents_the_flow(self):
        self.assertTrue(self.SCRIPT.is_file())
        self.assertTrue(os.access(self.SCRIPT, os.X_OK), 'verify.sh must be executable')
        result = subprocess.run([BASH, str(self.SCRIPT), 'help'],
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        for expected in ['prepare', 'integrity', 'report', 'status', 'logout + login']:
            self.assertIn(expected, result.stdout)

    def test_report_without_prepare_fails_clearly(self):
        with tempdir() as directory:
            env = self.prepared_env(directory, '')
            (Path(directory) / '.state/portillo-dots/otiling-verify/started-at').unlink()
            result = subprocess.run([BASH, str(self.SCRIPT), 'report'],
                                    env=env, capture_output=True, text=True, timeout=20)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('prepare', result.stderr)

    def test_journal_assertion_disables_the_extension(self):
        with tempdir() as directory:
            env = self.prepared_env(
                directory,
                'meta_window_set_stack_position_no_sync: assertion failed\n')
            result = subprocess.run([BASH, str(self.SCRIPT), 'report'],
                                    env=env, input='PASS\nPASS\nskip\nskip\nskip\n',
                                    capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Deshabilitando la extensión', result.stdout)
            self.assertIn('espera de upstream', result.stdout)
            self.assertIn('disable', (Path(directory) / 'calls').read_text())

    def test_core_block_failure_disables_the_extension(self):
        with tempdir() as directory:
            env = self.prepared_env(directory, '')
            result = subprocess.run([BASH, str(self.SCRIPT), 'report'],
                                    env=env, input='FAIL\nA1\nPASS\nskip\nskip\nskip\n',
                                    capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Deshabilitando la extensión', result.stdout)

    def test_clean_run_keeps_the_extension_enabled(self):
        with tempdir() as directory:
            env = self.prepared_env(directory, '')
            result = subprocess.run([BASH, str(self.SCRIPT), 'report'],
                                    env=env, input='PASS\nPASS\nPASS\nPASS\nPASS\n',
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('queda HABILITADA', result.stdout)
            self.assertNotIn('disable', (Path(directory) / 'calls').read_text())

    def test_c2_monitor_crossing_is_not_treated_as_core_failure(self):
        with tempdir() as directory:
            env = self.prepared_env(directory, '')
            # Block C fails on C2 — upstream behaviour after removing the local
            # patch — while core blocks A/B pass. Not a failure.
            result = subprocess.run(
                [BASH, str(self.SCRIPT), 'report'], env=env,
                input='PASS\nPASS\nFAIL\nC2\nPASS\nPASS\n',
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('queda HABILITADA', result.stdout)

    def test_status_reports_without_mutating(self):
        with tempdir() as directory:
            env = self.prepared_env(directory, '')
            result = subprocess.run([BASH, str(self.SCRIPT), 'status'],
                                    env=env, capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Versión pin', result.stdout)
            self.assertNotIn('disable', (Path(directory) / 'calls').read_text())


class HardwareProfileTests(unittest.TestCase):
    SCRIPT = ROOT / 'linux/optimize.sh'

    def run_optimize(self, args=(), env=None):
        return subprocess.run([BASH, str(self.SCRIPT), *args],
                              env={**os.environ, **(env or {})},
                              capture_output=True, text=True, timeout=30)

    def test_list_shows_the_profile_without_writing(self):
        result = self.run_optimize(['--list'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('CPU_GOVERNOR', result.stdout)
        self.assertIn('SWAPPINESS', result.stdout)
        self.assertIn('preferencia personal', result.stdout)
        self.assertIn('no por este script', result.stdout)
        self.assertNotIn('Setting CPU governor', result.stdout)

    def test_values_are_overridable_by_environment(self):
        result = self.run_optimize(['--list'], env={
            'CPU_GOVERNOR': 'schedutil', 'SWAPPINESS': '60', 'PPD_PROFILE': 'power-saver'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('CPU_GOVERNOR     = schedutil', result.stdout)
        self.assertIn('SWAPPINESS       = 60', result.stdout)
        self.assertIn('PPD_PROFILE      = power-saver', result.stdout)

    def test_help_does_not_claim_universal_optimisation(self):
        result = self.run_optimize(['--help'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('optimal settings', result.stdout)
        self.assertNotIn('Safe to run on any Linux', result.stdout)
        self.assertIn('NOT universal optimisations', result.stdout)
        self.assertIn('--list', result.stdout)

    def test_battery_rule_is_labelled_per_machine(self):
        text = (ROOT / 'linux/99-battery-charge-threshold.rules').read_text()
        self.assertIn('CONFIGURACIÓN DE UN EQUIPO CONCRETO', text)
        self.assertIn('KERNEL=="BAT1"', text)
        self.assertIn('NO es una optimización universal', text)
        self.assertIn('revisa y ajusta', text)


class IndependentScriptsTests(unittest.TestCase):
    def test_hardware_script_manages_no_services_by_itself(self):
        text = (ROOT / 'linux/optimize.sh').read_text()
        for forbidden in ['systemctl', 'ufw', 'iptables', 'sshd', 'userdel', 'chsh']:
            self.assertNotIn(forbidden, text,
                             'optimize.sh must not manage services or accounts')

    def test_otiling_script_defaults_to_non_destructive(self):
        text = (ROOT / 'o-tiling/install.sh').read_text()
        self.assertNotIn('\nrm -rf "$HOME', text)
        self.assertIn('--remove-tiling-shell', text)
        self.assertIn('--allow-version-mismatch', text)
