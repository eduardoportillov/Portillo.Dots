"""Independent hardware and o-tiling scripts.

Every desktop/extension command is stubbed: the tests never touch GNOME, dconf,
udev, sysfs or the network.
"""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

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
    def make_install(self, directory, patch_body=None):
        base = Path(directory) / 'src'
        (base / 'patches').mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / 'o-tiling/install.sh', base / 'install.sh')
        if patch_body is None:
            (base / 'patches/apply-patches.sh').write_text('#!/usr/bin/env bash\nexit 0\n')
        else:
            (base / 'patches/apply-patches.sh').write_text(patch_body)
        return base / 'install.sh'

    def run_install(self, directory, args=(), patch_body=None, extra_env=None):
        install = self.make_install(directory, patch_body)
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

    def calls(self, path):
        return path.read_text()

    def test_default_run_touches_no_other_extension_or_global_setting(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            result, calls = self.run_install(directory, ['--force'])
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            log = self.calls(calls)
            self.assertNotIn('rm -rf', log)
            self.assertNotIn('disable-extension-version-validation', log)
            self.assertNotIn('ding@rastersoft.com', log)
            self.assertIn('Tiling Shell intacta', result.stdout)
            self.assertIn('usa --remove-tiling-shell', result.stdout)

    def test_destructive_actions_are_gated_behind_flags(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            result, calls = self.run_install(
                directory, ['--force', '--remove-tiling-shell', '--disable-ding',
                            '--allow-version-mismatch'])
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            log = self.calls(calls)
            self.assertIn('disable-extension-version-validation', log)
            self.assertIn('ding@rastersoft.com', log)
            self.assertIn('Desmontando Tiling Shell', result.stdout)

    def test_patch_failure_fails_the_install_and_writes_no_marker(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            result, calls = self.run_install(directory, ['--force'],
                                             patch_body='#!/usr/bin/env bash\necho "patch failed" >&2\nexit 1\n')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('NO se considera completa', result.stdout + result.stderr)
            home = Path(directory) / 'home'
            markers = list(home.glob('.local/share/gnome-shell/extensions/*/.installed-version'))
            self.assertEqual(markers, [], 'a failed install must not record a success marker')

    def test_marker_records_the_patch_digest(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            result, calls = self.run_install(directory, ['--force'])
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            home = Path(directory) / 'home'
            marker = next(home.glob('.local/share/gnome-shell/extensions/*/.installed-version'))
            content = marker.read_text().strip()
            self.assertTrue(content.startswith('version=v2.9.21 patches='))
            digest = content.split('patches=', 1)[1]
            source = Path(directory) / 'src/patches/apply-patches.sh'
            self.assertEqual(digest, hashlib.sha256(source.read_bytes()).hexdigest())

    def test_changed_patches_retrigger_without_redownloading(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            self.run_install(directory, ['--force'])
            install = self.make_install(directory, 'exit 0')  # new digest
            stubs = Path(directory) / 'stubs2'
            stubs.mkdir()
            (Path(directory) / 'calls2').write_text('')
            home = Path(directory) / 'home'
            env = {**os.environ, 'HOME': str(home), 'STUB_DIR': str(stubs),
                   'CALLS': str(Path(directory) / 'calls2'), 'PATH': f'{stubs}:/usr/bin:/bin'}
            prelude = STUBS.replace('$STUB_DIR', str(stubs))
            result = subprocess.run([BASH, '-euc', prelude + f'\nbash "{install}"', '_'],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('cambiaron los patches', result.stdout)
            self.assertNotIn('Descargando', result.stdout)

    def test_unknown_option_is_rejected(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            result, _ = self.run_install(directory, ['--delete-everything'])
            self.assertEqual(result.returncode, 2)
            self.assertIn('Opción desconocida', result.stderr)


class ApplyPatchesTests(unittest.TestCase):
    def run_patches(self, directory, patch_text, files=None):
        base = Path(directory) / 'ext'
        base.mkdir(parents=True, exist_ok=True)
        for name, body in (files or {}).items():
            path = base / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(body)
        script = ROOT / 'o-tiling/patches/apply-patches.sh'
        return subprocess.run([BASH, str(script), str(base)],
                              capture_output=True, text=True, timeout=30)

    def test_missing_target_file_is_a_failure_not_a_skip(self):
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            # The extension directory exists but neither target file does.
            result = self.run_patches(directory, '', files={})
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('NO se aplicó', result.stdout + result.stderr)
            self.assertNotIn('Patches aplicados correctamente', result.stdout)

    def test_success_is_only_announced_when_every_patch_applies(self):
        # Give patch 1 a real target so it can run, but leave patch 2 missing.
        with tempfile.TemporaryDirectory(dir='/tmp/opencode') as directory:
            files = {'engine/tiling.js': 'function move_window_or_monitor() {}\n'}
            result = self.run_patches(directory, '', files=files)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('Patches aplicados correctamente', result.stdout)
            self.assertIn('un patch no se aplicó', (result.stdout + result.stderr).lower())


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
        # The unconditional forms of these commands must not exist.
        self.assertNotIn('\nrm -rf "$HOME', text)
        self.assertNotIn('gsettings set org.gnome.shell disable-extension-version-validation true 2>/dev/null || true\n[[ "$OTILING_AUTO_ENABLE"',
                         text)
        self.assertIn('--remove-tiling-shell', text)
        self.assertIn('--allow-version-mismatch', text)


if __name__ == '__main__':
    unittest.main()
