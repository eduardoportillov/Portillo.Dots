-- Remote Server Neovim: the shared baseline only — no plugin manager,
-- toolchain downloads or background updates. The baseline is deployed to
-- ~/.config/portillo-dots/nvim-base.lua by setup.sh.
local shared = vim.fn.expand("~/.config/portillo-dots/nvim-base.lua")
if vim.fn.filereadable(shared) == 1 then
  dofile(shared)
else
  vim.notify("Portillo.Dots: shared Neovim baseline missing at " .. shared, vim.log.levels.WARN)
end
