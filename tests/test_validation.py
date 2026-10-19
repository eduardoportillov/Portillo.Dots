"""Syntax and format validation across every language the repo ships.

Runs with the standard library wherever possible so CI needs no extra tooling;
the one exception is Lua, which is skipped when no interpreter is installed.
"""
import ast
import json
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[1]


def tracked(pattern=None):
    out = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '-z']).decode()
    names = [n for n in out.split('\0') if n]
    if pattern:
        names = [n for n in names if Path(n).match(pattern)]
    return names


class SyntaxValidationTests(unittest.TestCase):
    def test_every_tracked_bash_script_parses(self):
        names = [n for n in tracked() if n.endswith('.sh')]
        self.assertGreater(len(names), 10)
        for name in names:
            with self.subTest(file=name):
                result = subprocess.run(['bash', '-n', str(ROOT / name)],
                                        capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_zsh_configs_parse(self):
        zsh = shutil.which('zsh')
        if not zsh:
            self.skipTest('zsh is required to validate the Zsh configs')
        for name in ['zsh/.zshrc', 'zsh/p10k.zsh']:
            with self.subTest(file=name):
                result = subprocess.run([zsh, '-n', str(ROOT / name)],
                                        capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_every_tracked_python_file_parses(self):
        names = [n for n in tracked() if n.endswith('.py')]
        self.assertGreater(len(names), 15)
        for name in names:
            with self.subTest(file=name):
                ast.parse((ROOT / name).read_text(), filename=name)

    def test_every_tracked_toml_file_parses(self):
        names = [n for n in tracked() if n.endswith('.toml')]
        self.assertGreater(len(names), 2)
        for name in names:
            with self.subTest(file=name):
                tomllib.loads((ROOT / name).read_text())

    def test_every_jsonc_config_parses(self):
        spec = importlib.util.spec_from_file_location(
            'renderer', ROOT / 'opencode/render-config.py')
        renderer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(renderer)
        names = [n for n in tracked() if n.endswith('.jsonc') or n.endswith('cli.json')]
        self.assertGreater(len(names), 3)
        for name in names:
            with self.subTest(file=name):
                config = renderer.load_jsonc((ROOT / name).read_text())
                self.assertIsInstance(config, dict, f'{name} must decode to an object')

    def test_plain_json_files_parse(self):
        # JSONC files (cli.json, zed/settings.json) carry comments and are
        # covered by the JSONC test above.
        jsonc = {'opencode/cli.json', 'zed/settings.json'}
        names = [n for n in tracked()
                 if n.endswith('.json') and not n.endswith('.jsonc') and n not in jsonc]
        self.assertGreater(len(names), 3)
        for name in names:
            with self.subTest(file=name):
                json.loads((ROOT / name).read_text())

    def test_every_tracked_lua_file_compiles(self):
        lua = shutil.which('luajit') or shutil.which('lua')
        if not lua:
            self.skipTest('LuaJIT or Lua is required to compile the Neovim configs')
        names = [n for n in tracked() if n.endswith('.lua')]
        self.assertGreater(len(names), 15)
        for name in names:
            with self.subTest(file=name):
                result = subprocess.run([lua, '-e', f'assert(loadfile("{name}"))'],
                                        cwd=ROOT, capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_executable_shell_scripts_have_a_shebang(self):
        for name in tracked():
            if not name.endswith('.sh'):
                continue
            path = ROOT / name
            first = path.read_text().splitlines()[0] if path.read_text() else ''
            with self.subTest(file=name):
                if path.stat().st_mode & 0o111:
                    self.assertTrue(first.startswith('#!'),
                                    f'{name} is executable but has no shebang')
                else:
                    # A non-executable entrypoint is legitimate: several remote
                    # scripts are shipped over SSH and run as `bash < file`.
                    self.assertTrue(first.startswith('#!') or first.startswith('#'),
                                    f'{name} should open with a shebang or an explanatory comment')


class ManifestConsistencyTests(unittest.TestCase):
    def test_tracked_files_are_not_empty_or_accidentally_huge(self):
        for name in tracked():
            path = ROOT / name
            if not path.is_file() or path.is_symlink():
                continue
            size = path.stat().st_size
            with self.subTest(file=name):
                if name.endswith('.gitkeep'):
                    continue
                self.assertGreater(size, 0, f'{name} is empty')
                self.assertLess(size, 2_000_000,
                                f'{name} is unexpectedly large ({size} bytes)')

    def test_no_file_leaves_trailing_whitespace_or_tabs_in_indentation(self):
        offenders = []
        for name in tracked():
            if not name.endswith(('.sh', '.py', '.toml', '.jsonc', '.rules', '.service', '.conf')):
                continue
            for number, line in enumerate((ROOT / name).read_text(errors='replace').splitlines(), 1):
                if line != line.rstrip():
                    offenders.append(f'{name}:{number} trailing whitespace')
                if '\t' in line and name.endswith(('.py',)):
                    offenders.append(f'{name}:{number} tab in Python indentation')
        self.assertEqual(offenders, [], '\n'.join(offenders[:20]))

    def test_every_doc_is_listed_in_the_docs_index(self):
        docs = [n for n in tracked()
                if n.startswith('docs/') and n.endswith('.md') and n != 'docs/README.md']
        self.assertGreaterEqual(len(docs), 10,
                                'the refactor documents each audited area')
        index = (ROOT / 'docs/README.md').read_text()
        for name in docs:
            with self.subTest(doc=name):
                self.assertIn(Path(name).name, index,
                              f'{name} is not listed in docs/README.md')
