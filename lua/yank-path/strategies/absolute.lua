-- Built-in strategy: return the buffer's absolute path unchanged.
-- The pipeline already resolves the path via `path.get`, so the strategy is
-- a pass-through. Maps to the picker shortcut `a`.

---@type yank-path.Strategy
return {
  key = "a",
  name = "Absolute",
  desc = "Full absolute path",
  transform = function(absolute, _ctx)
    return absolute, nil
  end,
}
