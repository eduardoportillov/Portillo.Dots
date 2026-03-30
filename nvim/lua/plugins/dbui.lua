-- Plugin config for vim-dadbod and vim-dadbod-ui
-- Loads connections from nvim/db_ui/connections.lua if present
local M = {
  {
    "kristijanhusak/vim-dadbod-ui",
    dependencies = {
      { "tpope/vim-dadbod", lazy = true },
      { "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" }, lazy = true },
    },
    cmd = {
      "DBUI",
      "DBUIToggle",
      "DBUIAddConnection",
      "DBUIFindBuffer",
    },
    init = function()
      -- Use nerd fonts in the drawer if available
      vim.g.db_ui_use_nerd_fonts = 1
      -- Default drawer width
      vim.g.db_ui_winwidth = 40

      -- Save location for queries inside the repo (relative to config)
      local repo_queries = vim.fn.stdpath("config") .. "/db_ui/queries"
      vim.g.db_ui_save_location = repo_queries

      -- Try to load connections from a repo-local file first
      -- Location: stdpath('config') .. '/db_ui/connections.lua'
      local cfg_path = vim.fn.stdpath("config") .. "/db_ui/connections.lua"
      local conns = nil
      if vim.loop.fs_stat and vim.loop.fs_stat(cfg_path) then
        local ok2, t = pcall(dofile, cfg_path)
        if ok2 and type(t) == "table" then
          conns = t
        end
      else
        -- Fallback: try require('db_ui.connections') if it's in runtimepath (lua/db_ui/connections.lua)
        local ok, t = pcall(require, "db_ui.connections")
        if ok and type(t) == "table" then
          conns = t
        end
      end

      if conns and type(conns) == "table" then
        vim.g.dbs = conns
      end

      -- Provide a convenience mapping to toggle DBUI
      vim.api.nvim_set_keymap("n", "<leader>db", ":DBUI<CR>", { noremap = true, silent = true })
    end,
  },
}

return M
