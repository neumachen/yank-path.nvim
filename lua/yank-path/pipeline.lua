-- Linear pipeline composing the leaf modules:
--
--   path.get  →  strategy.transform  →  range.append (if visual)
--                                                    →  register.write
--
-- The pipeline is the only place that knows the whole flow; every other
-- module has a single responsibility and can be tested or replaced in
-- isolation.
--
-- Strategies may be synchronous or asynchronous:
--   - Sync strategy returns `(result, err)`; the pipeline finishes
--     immediately.
--   - Async strategy returns `(nil, nil)` and calls `ctx.continue(result,
--     err)` later (e.g. after a vim.ui.input prompt). The pipeline waits
--     for that callback.
--
-- The visual range is captured BEFORE any picker interaction because the
-- act of opening a picker leaves visual mode and the marks become stale.

local path = require("yank-path.path")
local range_mod = require("yank-path.range")
local register = require("yank-path.register")
local config_mod = require("yank-path.config")
local util = require("yank-path.util")

local M = {}

---@param strategy yank-path.Strategy
---@param opts { register: string|nil, range: yank-path.Range|nil }|nil
function M.run(strategy, opts)
  opts = opts or {}

  local bufnr = vim.api.nvim_get_current_buf()
  local absolute, err = path.get(bufnr)
  if err then
    util.notify_err(err)
    return
  end

  -- Caller may pre-capture the range (the public `yank()` entry does this
  -- before opening the picker because the picker leaves visual mode). If
  -- no range was supplied, fall back to a fresh detection so direct
  -- programmatic calls still pick up an active selection.
  local rng = opts.range
  if rng == nil then
    rng = range_mod.get()
  end

  local config = config_mod.config

  -- `finalize` is called by both the sync and async paths. It handles the
  -- terminal stages (range append, register write, notification) once and
  -- only once so a buggy strategy that calls `continue` twice does not
  -- produce duplicate notifications.
  local done = false
  local function finalize(result, finalize_err)
    if done then
      return
    end
    done = true

    if finalize_err then
      util.notify_err(finalize_err)
      return
    end
    if result == nil then
      -- A nil result with no error means the user cancelled the strategy
      -- (e.g. dismissed the vim.ui.input prompt). Silent return.
      return
    end

    if rng then
      result = range_mod.append(result, rng)
    end

    register.write(result, opts.register or config.register)
    util.notify_info("yanked: " .. result)
  end

  local ctx = {
    bufnr = bufnr,
    absolute = absolute,
    range = rng,
    config = config,
    continue = finalize,
  }

  -- Run the strategy under pcall so a broken user-registered strategy
  -- never crashes the editor; the failure surfaces as a notification and
  -- the pipeline ends cleanly.
  local ok, result, transform_err = pcall(strategy.transform, absolute, ctx)
  if not ok then
    util.notify_err("strategy '" .. strategy.name .. "' raised: " .. tostring(result))
    done = true
    return
  end

  if result == nil and transform_err == nil then
    -- Async strategy: it will call `ctx.continue` itself. Nothing more to
    -- do synchronously.
    return
  end

  finalize(result, transform_err)
end

return M
