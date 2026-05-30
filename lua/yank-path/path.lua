-- Resolve a buffer to its absolute, symlink-followed filesystem path.
-- Single-responsibility: this module knows nothing about strategies, ranges,
-- or registers — those are higher up the pipeline.

local M = {}

---Get the absolute path of a buffer.
---
---Errors are returned Go-style as `(nil, err)` so the pipeline can
---short-circuit without `pcall` boilerplate at every call site. The only
---failure mode is an unnamed buffer (e.g. a scratch or terminal buffer);
---`nvim_buf_get_name` returns an empty string for those.
---
---The result is always absolute (`:p`) and symlinks are resolved so paths
---compare equal regardless of how the user opened the file.
---@param bufnr integer buffer number; pass `0` for the current buffer
---@return string|nil absolute resolved absolute path, or nil on failure
---@return string|nil err error message when `absolute` is nil
function M.get(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return nil, "buffer has no associated file"
  end

  local absolute = vim.fn.fnamemodify(name, ":p")
  return vim.fn.resolve(absolute), nil
end

return M
