-- Built-in strategy: return just the filename portion of the buffer's path.
-- Maps to the picker shortcut `f`.

---@type yank-path.Strategy
return {
  key = "f",
  name = "Filename",
  desc = "Just the filename, no directory",
  transform = function(absolute, _ctx)
    return vim.fn.fnamemodify(absolute, ":t"), nil
  end,
}
