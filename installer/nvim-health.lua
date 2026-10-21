-- Fail setup/check instead of silently accepting a bare or half-installed editor.
local ok, err = pcall(function()
  assert(vim.v.errmsg == "", vim.v.errmsg)
  local receipt = { plugins = {} }
  if vim.env.PORTILLO_NVIM_CHECK == "1" then
    -- The receipt records only the active plugins from a successful real start,
    -- not obsolete/disabled entries still present in the lockfile.
    receipt = vim.json.decode(table.concat(vim.fn.readfile(vim.env.PORTILLO_NVIM_RECEIPT), "\n"))
    assert(receipt.plugins.LazyVim and receipt.plugins.kanagawa, "Incomplete editor receipt")
    for name, plugin in pairs(receipt.plugins) do
      assert(plugin.dir == vim.fn.stdpath("data") .. "/lazy/" .. name, "Plugin data location changed: " .. name)
    end
    vim.opt.rtp:prepend(receipt.plugins.kanagawa.dir)
    vim.cmd.colorscheme("kanagawa-dragon")
  else
    assert(package.loaded["lazy"], "lazy.nvim did not load")
    local config = require("lazy.core.config")
    assert(config.plugins.LazyVim, "LazyVim missing")
    local lock = vim.json.decode(table.concat(vim.fn.readfile(vim.fn.stdpath("config") .. "/lazy-lock.json"), "\n"))
    for name, plugin in pairs(config.plugins) do
      if not plugin.virtual then
        assert(vim.fn.isdirectory(plugin.dir) == 1, "Missing plugin: " .. name)
        assert(not (plugin._ and plugin._.build), "Unfinished plugin build: " .. name)
        for _, task in ipairs(plugin._.tasks or {}) do
          assert(not task:has_errors(), "Plugin restore/build failed: " .. name)
        end
        if plugin.url then
          assert(lock[name], "Active plugin is not pinned in lazy-lock.json: " .. name)
          receipt.plugins[name] = { dir = plugin.dir, commit = lock[name].commit }
        end
      end
    end
    local colorscheme = require("lazyvim.config").colorscheme
    assert(colorscheme == "kanagawa-dragon", "Configured theme is not kanagawa-dragon")
    -- Restore can invalidate the previously loaded colorscheme.
    vim.cmd.colorscheme(colorscheme)
  end
  for name, plugin in pairs(receipt.plugins) do
    local head = vim.fn.system({ "git", "-C", plugin.dir, "rev-parse", "HEAD" }):gsub("%s+$", "")
    assert(vim.v.shell_error == 0 and head == plugin.commit, "Plugin differs from lockfile or is missing: " .. name)
  end
  assert(vim.g.colors_name == "kanagawa" and require("kanagawa")._CURRENT_THEME == "dragon",
    "Expected Kanagawa Dragon, got " .. tostring(vim.g.colors_name))
  if vim.env.PORTILLO_NVIM_CHECK ~= "1" then
    vim.fn.writefile({ vim.json.encode(receipt) }, vim.env.PORTILLO_NVIM_RECEIPT)
  end
end)
if not ok then
  vim.api.nvim_err_writeln("Portillo.Dots: " .. tostring(err))
  vim.cmd("cquit 1")
end
