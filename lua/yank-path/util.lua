-- Shared helpers used across the yank-path pipeline. Kept dependency-free so
-- this module sits at the bottom of the import graph and every other module
-- can rely on it without introducing cycles.

local M = {}

local PREFIX = "[yank-path] "

---Emit an INFO-level notification with the plugin prefix.
---@param msg string user-visible message
function M.notify_info(msg)
  vim.notify(PREFIX .. msg, vim.log.levels.INFO)
end

---Emit a WARN-level notification with the plugin prefix.
---@param msg string user-visible message
function M.notify_warn(msg)
  vim.notify(PREFIX .. msg, vim.log.levels.WARN)
end

---Emit an ERROR-level notification with the plugin prefix.
---Strategies and the pipeline route all failures through here so the user
---experience stays uniform and tests can assert against a single channel.
---@param msg string user-visible message
function M.notify_err(msg)
  vim.notify(PREFIX .. msg, vim.log.levels.ERROR)
end

---Detect whether a value can be invoked as a function.
---Used by config validation so users can supply either a plain function or
---a table with a `__call` metatable (common with class-style wrappers).
---@param v any
---@return boolean
function M.is_callable(v)
  if type(v) == "function" then
    return true
  end
  if type(v) == "table" then
    local mt = getmetatable(v)
    return mt ~= nil and type(mt.__call) == "function"
  end
  return false
end

---Per-directory cache for project-root lookups. Keyed by the buffer's parent
---directory; populated lazily by `find_project_root` and invalidated by the
---`BufFilePost` autocmd wired in `init.lua`.
---@type table<string, string|false>
local root_cache = {}

---Clear a single cached root entry.
---Stored as module-level so tests can reach in and verify state.
---@param dir string parent directory whose cache entry should be evicted
function M.clear_root_cache(dir)
  root_cache[dir] = nil
end

---Clear every cached root entry. Primarily useful for tests; runtime users
---should not need this since the autocmd handles invalidation.
function M.clear_all_root_cache()
  root_cache = {}
end

---Expose the cache for inspection in tests. The pipeline never reads from
---this directly — it goes through `find_project_root`.
---@return table<string, string|false>
function M._root_cache()
  return root_cache
end

---Resolve the project root for a buffer.
---
---Resolution order:
---  1. If the user supplied `project_config.find_root`, call it and return
---     whatever it produces. User-supplied roots are not cached because the
---     user controls their own caching strategy.
---  2. Otherwise walk upward from the buffer's parent directory looking for
---     the first of `project_config.markers`. Uses `vim.fs.find` so the
---     traversal stops at filesystem boundaries Neovim already knows about.
---
---Cached lookups store `false` for negative results so we do not re-walk the
---tree on every invocation of the `p` strategy in a directory without a
---root marker.
---@param bufnr integer source buffer; used to derive the starting directory
---@param project_config { markers: string[], find_root: (fun(bufnr: integer): string|nil)|nil, cache: boolean }
---@return string|nil root absolute path to the project root, or nil if not found
function M.find_project_root(bufnr, project_config)
  if M.is_callable(project_config.find_root) then
    return project_config.find_root(bufnr)
  end

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname == "" then
    return nil
  end

  local dir = vim.fs.dirname(bufname)
  if not dir or dir == "" then
    return nil
  end

  if project_config.cache and root_cache[dir] ~= nil then
    local cached = root_cache[dir]
    if cached == false then
      return nil
    end
    return cached
  end

  local found = vim.fs.find(project_config.markers, { upward = true, path = dir })[1]
  local root = found and vim.fs.dirname(found) or nil

  if project_config.cache then
    root_cache[dir] = root or false
  end

  return root
end

return M
