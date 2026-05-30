-- yank-path.nvim Neovim autoload entry.
--
-- Registers the single user command :YankPath. The command works in both
-- normal and visual mode; visual mode is detected by the pipeline via the
-- '< / '> marks before the picker is opened.

if vim.g.loaded_yank_path then
  return
end
vim.g.loaded_yank_path = true

vim.api.nvim_create_user_command("YankPath", function()
  require("yank-path").yank()
end, {
  range = true,
  desc = "Yank a path representation of the current buffer",
})
