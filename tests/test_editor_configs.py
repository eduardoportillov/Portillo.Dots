"""Desktop, tmux and Neovim configuration behaviour.

The Lua specs are loaded with stubs so no plugin manager, editor or desktop
session is required, and no real clipboard is ever read or written.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from _support import tempdir
import unittest

ROOT = Path(__file__).resolve().parents[1]
LUA = shutil.which('luajit') or shutil.which('lua')
NVIM_ROOT = ROOT / 'nvim'

VIM_STUB = r'''
local captured = { keymaps = {}, opts = {}, g = {} }
local env = {}
local executables = {}
local osc_available = true

local function parse_env(spec)
  for pair in string.gmatch(spec or "", "[^,]+") do
    local k, v = pair:match("^([^=]+)=(.*)$")
    if k then env[k] = v end
  end
end
local function parse_exes(spec)
  for name in string.gmatch(spec or "", "[^,]+") do executables[name] = true end
end
parse_env(arg[2])
parse_exes(arg[3])
osc_available = (arg[4] ~= "no-osc")

local function opt_value()
  return {
    prepend = function() end,
    append = function() end,
    remove = function() end,
    get = function() return nil end,
  }
end
local opts_proxy = setmetatable({}, {
  __newindex = function(_, k, v) captured.opts[k] = v end,
  __index = function() return opt_value() end,
})
vim = {
  env = setmetatable({}, { __index = function(_, k) return env[k] end }),
  g = captured.g,
  opt = opts_proxy,
  o = {},
  bo = {},
  fn = {
    executable = function(name) return executables[name] and 1 or 0 end,
    getreg = function() return { "register-text" } end,
    getregtype = function() return "v" end,
    stdpath = function() return "/nonexistent" end,
    filereadable = function() return 0 end,
    fnamemodify = function(p) return p end,
    resolve = function(p) return p end,
    expand = function(p) return p end,
    input = function() return "" end,
    fnameescape = function(p) return p end,
    bufnr = function() return -1 end,
    bufadd = function() return 0 end,
    bufload = function() end,
    mkdir = function() end,
  },
  api = setmetatable({
    nvim_set_keymap = function(mode, lhs) table.insert(captured.keymaps, { mode = mode, lhs = lhs, src = "set_keymap" }) end,
    nvim_set_hl = function() end,
    nvim_create_user_command = function() end,
    nvim_create_autocmd = function() end,
    nvim_echo = function() end,
    nvim_win_get_config = function() return { relative = "" } end,
    nvim_win_set_width = function() end,
    nvim_win_set_height = function() end,
    nvim_win_get_width = function() return 80 end,
    nvim_win_get_height = function() return 24 end,
    nvim_win_get_cursor = function() end,
    nvim_get_current_win = function() return 1 end,
    nvim_tabpage_list_wins = function() return {} end,
  }, { __index = function() return function() end end }),
  keymap = {
    set = function(mode, lhs)
      table.insert(captured.keymaps, { mode = mode, lhs = lhs, src = "keymap.set" })
    end,
  },
  ui = { clipboard = {} },
  loop = {
    fs_stat = function() return nil end,
    fs_open = function() return nil end,
    fs_close = function() end,
    fs_read = function() end,
  },
  cmd = function() end,
  schedule = function(fn) end,
  deepcopy = function(v) return v end,
  json = { encode = function() return "{}" end, decode = function() return {} end },
  o = {},
}
vim.o = opts_proxy
vim.opt_local = opts_proxy
package.preload["vim.ui.clipboard.osc52"] = function()
  if not osc_available then error("old Neovim") end
  return {
    copy = function() return function() end end,
    paste = function() error("OSC52 paste must not be requested") end,
  }
end
LazyVim = { has = function() return false end, opts = function() return {} end, config = { icons = {} } }

local path = arg[1]
local chunk, loaderr = loadfile(path)
if not chunk then
  io.stderr:write("load failed: " .. tostring(loaderr) .. "\n")
  os.exit(2)
end
local ok, result = pcall(chunk)
if not ok then
  io.stderr:write("run failed: " .. tostring(result) .. "\n")
  os.exit(3)
end
local function norm_mode(m)
  if type(m) == "table" then return table.concat(m, "") end
  return tostring(m)
end
if type(result) == "table" then
  local function walk_deep(spec, seen)
    if type(spec) ~= "table" or seen[spec] then return end
    seen[spec] = true
    -- Some specs register keymaps inside init/config; run them on the stubs.
    for _, hook in ipairs({"init", "config"}) do
      if type(spec[hook]) == "function" then pcall(spec[hook], spec, spec) end
    end
    if type(spec.keys) == "table" then
      for _, entry in ipairs(spec.keys) do
        if type(entry) == "table" and type(entry[1]) == "string" then
          table.insert(captured.keymaps, { mode = norm_mode(entry.mode or "n"), lhs = entry[1], src = "keys" })
        end
      end
    end
    for k, v in pairs(spec) do
      if k ~= "keys" then walk_deep(v, seen) end
    end
  end
  walk_deep(result, {})
end
local json = require("dkjson") or nil
print("KEYMAPS " .. #captured.keymaps)
for _, k in ipairs(captured.keymaps) do
  print("KM\t" .. norm_mode(k.mode) .. "\t" .. tostring(k.lhs))
end
print("CLIPBOARD\t" .. tostring(captured.g.clipboard and captured.g.clipboard.name or "none"))
print("OPT_CLIPBOARD\t" .. tostring(captured.opts.clipboard))
'''


def run_lua(path, env_spec='', exes_spec='', osc='with-osc'):
    if not LUA:
        raise unittest.SkipTest('Lua interpreter not available')
    with tempdir() as directory:
        harness = Path(directory) / 'stub.lua'
        harness.write_text(VIM_STUB)
        # dkjson stub so the harness can require it without a dependency.
        (Path(directory) / 'dkjson.lua').write_text('return { }\n')
        result = subprocess.run(
            [LUA, str(harness), str(path), env_spec, exes_spec, osc],
            capture_output=True, text=True, timeout=20,
            env={**os.environ, 'LUA_PATH': directory + '/?.lua;;'})
        return result


class ClipboardMatrixTests(unittest.TestCase):
    OPTIONS = NVIM_ROOT / 'lua/config/options.lua'

    def clipboard(self, env_spec, exes_spec, osc='with-osc'):
        result = run_lua(self.OPTIONS, env_spec, exes_spec, osc)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        line = next(l for l in result.stdout.splitlines() if l.startswith('CLIPBOARD\t'))
        return line.split('\t', 1)[1]

    def test_ssh_uses_osc52_copy_only(self):
        for env_spec in ['SSH_CONNECTION=host', 'SSH_TTY=/dev/pts/2',
                         'NVIM_APPNAME=portillo-remote/nvim']:
            with self.subTest(env=env_spec):
                name = self.clipboard(env_spec, 'wl-copy,wl-paste,xclip')
                self.assertIn('OSC 52', name)
                self.assertIn('copy only', name)

    def test_ssh_with_old_neovim_falls_back_without_erroring(self):
        # No osc52 on this Neovim: fall through to the local provider instead of
        # erroring at config load time.
        name = self.clipboard('SSH_CONNECTION=host,WAYLAND_DISPLAY=wayland-0', 'wl-copy', osc='no-osc')
        self.assertEqual(name, 'wl-clipboard')
        self.assertEqual(self.clipboard('SSH_CONNECTION=host', 'wl-copy', osc='no-osc'), 'none')

    def test_wayland_requires_the_wayland_display(self):
        self.assertEqual(self.clipboard('WAYLAND_DISPLAY=wayland-0', 'wl-copy,wl-paste'), 'wl-clipboard')
        # wl-copy alone is not enough: without any display server neither
        # wl-copy nor xclip can reach a clipboard, so no provider is selected.
        self.assertEqual(self.clipboard('', 'wl-copy,wl-paste,xclip'), 'none')
        self.assertEqual(self.clipboard('DISPLAY=:0', 'wl-copy,wl-paste,xclip'), 'xclip')

    def test_x11_requires_the_display(self):
        self.assertEqual(self.clipboard('DISPLAY=:0', 'xclip'), 'xclip')
        self.assertEqual(self.clipboard('', 'xclip'), 'none')

    def test_wayland_wins_over_x11_when_both_are_present(self):
        name = self.clipboard('WAYLAND_DISPLAY=wayland-0,DISPLAY=:0', 'wl-copy,xclip')
        self.assertEqual(name, 'wl-clipboard')

    def test_macos_or_no_provider_leaves_the_builtin_default(self):
        self.assertEqual(self.clipboard('', ''), 'none')

    def test_osc52_paste_is_never_invoked(self):
        # The OSC52 stub raises on paste; loading must still succeed.
        result = run_lua(self.OPTIONS, 'SSH_CONNECTION=host', 'wl-copy')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('CLIPBOARD\tSSH OSC 52 (copy only)', result.stdout)


class KeymapConflictTests(unittest.TestCase):
    MODE_WORDS = {'n', 'v', 'i', 'x', 's', 'o', 'c', 't', 'nv', 'nvo'}

    def collect(self):
        bindings = []
        for path in sorted(NVIM_ROOT.rglob('*.lua')):
            result = run_lua(path)
            if result.returncode != 0:
                continue
            for line in result.stdout.splitlines():
                if line.startswith('KM\t'):
                    _, mode, lhs = line.split('\t', 2)
                    bindings.append((path.relative_to(ROOT), mode, lhs))
        return bindings

    def test_no_duplicate_keybindings_across_the_configuration(self):
        bindings = self.collect()
        self.assertGreater(len(bindings), 5, 'the scan must actually find keybindings')
        seen = {}
        duplicates = []
        for path, mode, lhs in bindings:
            # Mode markers like "n"/"v" are not key sequences.
            if lhs in self.MODE_WORDS or len(lhs) < 2:
                continue
            key = (mode, lhs)
            if key in seen and seen[key] != path:
                duplicates.append(f'{key}: {seen[key]} and {path}')
            seen[key] = path
        self.assertEqual(duplicates, [], 'duplicate keybindings:\n' + '\n'.join(duplicates))

    def test_debug_and_database_bindings_stay_separate(self):
        bindings = {(mode, lhs) for _, mode, lhs in self.collect()}
        self.assertIn(('n', '<leader>db'), bindings, 'debug breakpoint mapping must remain')
        self.assertIn(('n', '<leader>Db'), bindings, 'database mapping must not steal the debug one')
        self.assertNotIn(('n', '<leader>DB'), bindings)


class ServerIsolationTests(unittest.TestCase):
    FORBIDDEN = re.compile(
        r'(require\(["\']lazy|lazy\.nvim|git\s+clone|install_plugins|tpm|\bmarkitdown\b'
        r'|cargo|rustup|npm\s+install|npx|curl\s|wget\s|uv\s+tool)')

    def test_server_editor_bootstraps_nothing(self):
        text = (ROOT / 'server/nvim/init.lua').read_text()
        self.assertIsNone(self.FORBIDDEN.search(text),
                          'server Neovim must not clone plugins or toolchains')
        self.assertNotIn('lazy-lock', text)

    def test_server_tmux_has_no_plugin_manager_or_autoboot(self):
        raw = (ROOT / 'server/tmux.conf').read_text()
        text = '\n'.join(l for l in raw.splitlines() if not l.strip().startswith('#'))
        self.assertNotIn('@plugin', text)
        self.assertNotIn('tpm', text.lower())
        self.assertNotIn('continuum', text.lower())
        self.assertNotIn('resurrect', text.lower())
        self.assertNotIn('.config/systemd', text)


class TmuxStartupTests(unittest.TestCase):
    def test_continuum_loads_after_its_dependencies(self):
        lines = (ROOT / 'tmux/tmux.conf').read_text().splitlines()
        positions = {}
        for i, line in enumerate(lines):
            if line.strip().startswith('#'):
                continue
            for name in ['tmux-resurrect', 'tmux-kanagawa', 'tmux-continuum']:
                if name in line and '@plugin' in line:
                    positions.setdefault(name, i)
        self.assertIn('tmux-resurrect', positions)
        self.assertIn('tmux-kanagawa', positions)
        self.assertIn('tmux-continuum', positions)
        self.assertGreater(positions['tmux-continuum'], positions['tmux-resurrect'],
                           'continuum depends on resurrect')
        self.assertGreater(positions['tmux-continuum'], positions['tmux-kanagawa'],
                           'the kanagawa theme would clear continuum hooks if it loaded later')

    def test_autorestore_and_autoboot_are_explicit(self):
        text = (ROOT / 'tmux/tmux.conf').read_text()
        self.assertIn("set -g @continuum-restore 'on'", text)
        self.assertIn("set -g @continuum-boot 'on'", text)
        self.assertIn('run \'~/.tmux/plugins/tpm/tpm\'', text)
        # The autoboot systemd drop-in the comments depend on must exist.
        dropin = ROOT / 'linux/tmux.service.d/continuum-autoboot-fixes.conf'
        self.assertTrue(dropin.is_file(), 'the documented continuum drop-in must be versioned')
        self.assertIn('ExecStartPre', dropin.read_text())

    def test_tpm_initializes_last(self):
        lines = [l for l in (ROOT / 'tmux/tmux.conf').read_text().splitlines()
                 if 'tpm/tpm' in l and not l.strip().startswith('#')]
        self.assertEqual(len(lines), 1)
        last_index = (ROOT / 'tmux/tmux.conf').read_text().splitlines().index(lines[0])
        plugin_lines = [i for i, l in enumerate((ROOT / 'tmux/tmux.conf').read_text().splitlines())
                        if '@plugin' in l and not l.strip().startswith('#')]
        self.assertTrue(plugin_lines)
        self.assertGreater(last_index, max(plugin_lines), 'TPM must initialize after all @plugin lines')


class AlacrittyRegressionTests(unittest.TestCase):
    def test_linux_and_macos_configs_stay_valid_and_platform_correct(self):
        import tomllib
        linux = tomllib.loads((ROOT / 'alacritty/alacritty.toml').read_text())
        mac = tomllib.loads((ROOT / 'alacritty/alacritty.macos.toml').read_text())
        for name, cfg in [('linux', linux), ('macos', mac)]:
            with self.subTest(platform=name):
                self.assertIn('osc52', cfg['terminal'])
                self.assertEqual(cfg['terminal']['osc52'], 'onlycopy')
                self.assertIsInstance(cfg['hints']['enabled'][0]['command'], dict)
        self.assertEqual(linux['terminal']['shell']['program'], '/usr/bin/env')
        self.assertEqual(mac['terminal']['shell']['program'], '/bin/zsh')
        self.assertTrue((ROOT / 'alacritty/themes/kanagawa_dragon.toml').is_file())


if __name__ == '__main__':
    unittest.main()
