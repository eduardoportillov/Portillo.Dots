-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Format on save. Edit this option here if you want to disable it later.
-- LazyVim uses this global option to call conform.nvim automatically.
vim.g.autoformat = true

vim.opt.runtimepath:prepend(vim.fn.stdpath("data") .. "/site")

vim.g.clipboard = {
  name = "wl-clipboard",
  copy  = { ["+"] = "wl-copy", ["*"] = "wl-copy --primary" },
  paste = { ["+"] = "wl-paste --no-newline", ["*"] = "wl-paste --no-newline --primary" },
  cache_enabled = 0,
}
vim.opt.clipboard = "unnamedplus"
