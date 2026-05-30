-- Detect and format a line range derived from the active visual selection.
--
-- This module is intentionally narrow: it inspects `vim.fn.mode()` and the
-- `'<` / `'>` marks, returns a small range table, and appends it to a path.
-- The pipeline calls `get()` BEFORE opening the picker because the act of
-- opening any picker leaves visual mode, after which the live mode is `"n"`
-- and the selection state is unreachable.

local M = {}

---@class yank-path.Range
---@field start integer 1-indexed start line
---@field end_ integer 1-indexed end line
---@field is_visual boolean true when derived from visual-mode marks

---Detect the active visual selection.
---
---Returns a Range when `mode()` reports any visual variant — characterwise
---(`"v"`), linewise (`"V"`), or blockwise (`"\22"` / Ctrl-V). Returns nil in
---normal mode and when the visual marks are unpopulated (line 0).
---@return yank-path.Range|nil rng visual range, or nil when not in visual mode
function M.get()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    return nil
  end

  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  if start_line == 0 or end_line == 0 then
    return nil
  end

  if end_line < start_line then
    start_line, end_line = end_line, start_line
  end

  return {
    start = start_line,
    end_ = end_line,
    is_visual = true,
  }
end

---Append a range suffix to a path string.
---
---Format mirrors the de-facto convention used by tools like `grep` and
---editor jump-to-line URLs: `path:line` for a single line and
---`path:start-end` for a multi-line range.
---@param path string formatted path
---@param rng yank-path.Range range to append
---@return string suffixed `path:line` or `path:start-end`
function M.append(path, rng)
  if rng.start == rng.end_ then
    return path .. ":" .. rng.start
  end
  return path .. ":" .. rng.start .. "-" .. rng.end_
end

return M
