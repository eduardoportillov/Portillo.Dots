from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LUA = shutil.which('luajit')


@unittest.skipUnless(LUA, 'LuaJIT is needed for isolated Lua configuration tests')
class LuaConfigTests(unittest.TestCase):
    def run_lua(self, script, *args):
        result = subprocess.run([LUA, '-', *map(str, args)], input=script,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_tracked_lua_files_compile_without_loading_plugins(self):
        names = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '-z', '--', '*.lua']).decode().split('\0')
        for name in filter(None, names):
            with self.subTest(file=name):
                self.run_lua('assert(loadfile(arg[1]))', ROOT / name)

    def test_database_shortcut_does_not_override_debug_breakpoint(self):
        self.run_lua('''
            local key
            vim = {g={}, fn={stdpath=function() return '/nonexistent' end},
              loop={fs_stat=function() return nil end},
              keymap={set=function(mode, binding) key=binding end}}
            local database = assert(loadfile(arg[1] .. '/nvim/lua/plugins/dbui.lua'))()
            database[1].init()
            assert(key == '<leader>Db')
            local debugger = assert(loadfile(arg[1] .. '/nvim/lua/plugins/nvim-dap.lua'))()
            local found = false
            for _, binding in ipairs(debugger[1].keys) do
              if binding[1] == '<leader>db' then found = true end
            end
            assert(found, 'Debug breakpoint mapping must remain available')
        ''', ROOT)

    def test_debugger_env_preserves_values_without_executing_them(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            (base / '.env').write_text('URL="postgresql://user:pass@host:5432/db?ssl=on"\n'
                                      'TEXT=hello world\nEMPTY=\nLITERAL=$(touch marker)\n# COMMENT=ignored\n')
            self.run_lua('''
                local dap = {configurations={go={{}}}, toggle_breakpoint=function() end, set_breakpoint=function() end}
                package.preload['dap'] = function() return dap end
                package.preload['dap.ext.vscode'] = function() return {} end
                package.preload['dap.breakpoints'] = function() return {} end
                package.preload['dap-python'] = function() error('not installed') end
                package.preload['plenary.json'] = function() error('not installed') end
                LazyVim = {has=function() return false end}
                vim = {fn={getcwd=function() return arg[2] end, environ=function() return {KEEP='existing'} end},
                  api={nvim_set_hl=function() end, nvim_create_user_command=function() end, nvim_create_autocmd=function() end}}
                local plugins = assert(loadfile(arg[1]))()
                plugins[1].config()
                local env = dap.configurations.go[1].env()
                assert(env.URL == 'postgresql://user:pass@host:5432/db?ssl=on')
                assert(env.TEXT == 'hello world' and env.EMPTY == '')
                assert(env.LITERAL == '$(touch marker)' and env.KEEP == 'existing')
                assert(env.COMMENT == nil)
            ''', ROOT / 'nvim/lua/plugins/nvim-dap.lua', base)
            self.assertFalse((base / 'marker').exists())

    def test_server_clipboard_has_copy_only_and_old_version_fallback(self):
        for available in [True, False]:
            with self.subTest(available=available):
                self.run_lua('''
                    vim = {opt={}, env={SSH_CONNECTION='mock'}, g={}, keymap={set=function() end},
                      fn={getreg=function() return {'local register'} end, getregtype=function() return 'v' end}}
                    package.preload['vim.ui.clipboard.osc52'] = function()
                      if arg[2] == 'false' then error('old Neovim') end
                      return {copy=function() return function() end end,
                        paste=function() error('Remote clipboard reads must not be requested') end}
                    end
                    assert(loadfile(arg[1]))()
                    if arg[2] == 'true' then
                      local copied = vim.g.clipboard.paste['+']()
                      assert(copied[1][1] == 'local register' and copied[2] == 'v')
                      assert(type(vim.g.clipboard.copy['+']) == 'function')
                    else
                      assert(vim.g.clipboard == nil)
                    end
                ''', ROOT / 'server/nvim/init.lua', str(available).lower())
