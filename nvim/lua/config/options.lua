-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Format on save. Edit this option here if you want to disable it later.
-- LazyVim uses this global option to call conform.nvim automatically.
vim.g.autoformat = true

vim.opt.runtimepath:prepend(vim.fn.stdpath("data") .. "/site")

-- Dynamic clipboard: use OSC 52 over SSH so yank copies to host system clipboard,
-- wl-clipboard on Wayland (Linux local), or xclip on X11.
if vim.env.SSH_TTY or vim.env.SSH_CONNECTION or vim.env.NVIM_APPNAME == "portillo-remote/nvim" then
  vim.g.clipboard = {
    name = "OSC 52",
    copy = {
      ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
      ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
    },
    paste = {
      ["+"] = require("vim.ui.clipboard.osc52").paste("+"),
      ["*"] = require("vim.ui.clipboard.osc52").paste("*"),
    },
  }
elseif vim.fn.executable("wl-copy") == 1 then
  vim.g.clipboard = {
    name = "wl-clipboard",
    copy = { ["+"] = "wl-copy", ["*"] = "wl-copy --primary" },
    paste = { ["+"] = "wl-paste --no-newline", ["*"] = "wl-paste --no-newline --primary" },
    cache_enabled = 0,
  }
elseif vim.fn.executable("xclip") == 1 then
  vim.g.clipboard = {
    name = "xclip",
    copy = { ["+"] = "xclip -selection clipboard", ["*"] = "xclip -selection primary" },
    paste = { ["+"] = "xclip -selection clipboard -o", ["*"] = "xclip -selection primary -o" },
    cache_enabled = 0,
  }
end
vim.opt.clipboard = "unnamedplus"
