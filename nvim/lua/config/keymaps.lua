-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<C-w>>", "<cmd>vertical resize +10<cr>", { desc = "Increase window width" })
vim.keymap.set("n", "<C-w><lt>", "<cmd>vertical resize -10<cr>", { desc = "Decrease window width" })
vim.keymap.set("n", "<C-w>+", "<cmd>resize +5<cr>", { desc = "Increase window height" })
vim.keymap.set("n", "<C-w>-", "<cmd>resize -5<cr>", { desc = "Decrease window height" })

-- Equalizes regular editable splits in the current layout. Fixed sidebars such as
-- Explorer/Neo-tree can keep their configured width, so they may not become equal.
vim.keymap.set("n", "<C-w>=", "<C-w>=", { desc = "Equally high and wide" })
