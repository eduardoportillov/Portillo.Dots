-- Setup works on copies of LazyVim's mutable metadata, not tracked symlinks.
if vim.env.PORTILLO_NVIM_JSON then
  vim.g.lazyvim_json = vim.env.PORTILLO_NVIM_JSON
end
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  if vim.env.PORTILLO_NVIM_CHECK == "1" then
    error("lazy.nvim missing; run setup without --config-only")
  end
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

if vim.env.PORTILLO_NVIM_SETUP == "1" then
  -- Automatic missing-plugin installs run before :Lazy restore. Lazy's update
  -- mutates both its file AND in-memory lock, dropping pins not installed yet.
  -- Keep the supplied lock immutable throughout every cold-start install round.
  require("lazy.manage.lock").update = function() end
end

require("lazy").setup({
  lockfile = vim.env.PORTILLO_NVIM_LOCKFILE or (vim.fn.stdpath("config") .. "/lazy-lock.json"),
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  install = { missing = vim.env.PORTILLO_NVIM_CHECK ~= "1", colorscheme = { "kanagawa", "habamax" } },
  checker = {
    enabled = false, -- updates are explicit; every host follows the same lockfile
    notify = false, -- notify on update
  },
  rocks = {
    enabled = false,
  },
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
