-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Shared baseline (options, leader, core keymaps, SSH clipboard): identical on
-- every host, deployed by setup.sh or by the remote runtime. LazyVim layers on
-- top of it. The dynamic clipboard below then replaces the baseline's copy
-- behaviour with its desktop-aware superset.
for _, candidate in ipairs({
  vim.fn.expand("~/.config/portillo-dots/nvim-base.lua"),
  vim.fn.expand("~/.portillo-remote/shared/nvim/base.lua"),
}) do
  if vim.fn.filereadable(candidate) == 1 then
    dofile(candidate)
    break
  end
end

-- Format on save. Edit this option here if you want to disable it later.
-- LazyVim uses this global option to call conform.nvim automatically.
vim.g.autoformat = true

vim.opt.runtimepath:prepend(vim.fn.stdpath("data") .. "/site")

-- Dynamic clipboard, chosen by what is actually available:
--   SSH              -> OSC 52, copy-only (never request reads from the client)
--   Wayland          -> wl-clipboard
--   X11              -> xclip
--   macOS / fallback -> Neovim's built-in provider, or the unnamed register
-- A tool is only selected when its display server is present: wl-copy without
-- WAYLAND_DISPLAY, or xclip without DISPLAY, would silently fail to yank.
local has_osc52, osc52 = pcall(require, "vim.ui.clipboard.osc52")
if (vim.env.SSH_TTY or vim.env.SSH_CONNECTION or vim.env.NVIM_APPNAME == "portillo-remote/nvim") and has_osc52 then
  vim.g.clipboard = {
    name = "SSH OSC 52 (copy only)",
    copy = {
      ["+"] = osc52.copy("+"),
      ["*"] = osc52.copy("*"),
    },
    -- Copy only: OSC 52 paste would ask the terminal for the client clipboard.
    paste = {
      ["+"] = function() return { vim.fn.getreg('"', 1, true), vim.fn.getregtype('"') } end,
      ["*"] = function() return { vim.fn.getreg('"', 1, true), vim.fn.getregtype('"') } end,
    },
  }
elseif vim.env.WAYLAND_DISPLAY and vim.fn.executable("wl-copy") == 1 then
  vim.g.clipboard = {
    name = "wl-clipboard",
    copy = { ["+"] = "wl-copy", ["*"] = "wl-copy --primary" },
    paste = { ["+"] = "wl-paste --no-newline", ["*"] = "wl-paste --no-newline --primary" },
    cache_enabled = 0,
  }
elseif vim.env.DISPLAY and vim.fn.executable("xclip") == 1 then
  vim.g.clipboard = {
    name = "xclip",
    copy = { ["+"] = "xclip -selection clipboard", ["*"] = "xclip -selection primary" },
    paste = { ["+"] = "xclip -selection clipboard -o", ["*"] = "xclip -selection primary -o" },
    cache_enabled = 0,
  }
end
vim.opt.clipboard = "unnamedplus"
