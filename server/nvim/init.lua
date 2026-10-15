-- Remote Server: no plugin manager, toolchain downloads or background updates.
vim.opt.number = true
vim.opt.mouse = "a"
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.updatetime = 300
vim.opt.signcolumn = "yes"
vim.opt.termguicolors = true
vim.g.mapleader = " "
vim.keymap.set("n", "<leader>w", "<cmd>write<cr>")
vim.keymap.set("n", "<leader>q", "<cmd>quit<cr>")
local has_osc52, osc52 = pcall(require, "vim.ui.clipboard.osc52")
if vim.env.SSH_CONNECTION and has_osc52 then
  -- Copy only: don't request reads from the client's clipboard.
  vim.g.clipboard = {
    name = "SSH OSC 52",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = function() return { vim.fn.getreg('"', 1, true), vim.fn.getregtype('"') } end,
      ["*"] = function() return { vim.fn.getreg('"', 1, true), vim.fn.getregtype('"') } end },
  }
end
