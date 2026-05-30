-- Public API for yank-path.nvim.
--
-- Exposes the configuration entry point, the strategy registration API,
-- the picker-driven `yank()` flow, and the programmatic `yank_with(key)`
-- shortcut. Also registers the four built-in strategies on first load and
-- wires the BufFilePost autocmd that invalidates the project-root cache
-- when a buffer is renamed.

local config_mod = require("yank-path.config")
local strategies = require("yank-path.strategies")
local picker = require("yank-path.picker")
local pipeline = require("yank-path.pipeline")
local range_mod = require("yank-path.range")
local util = require("yank-path.util")

local M = {}

---Register the four built-in strategies. Idempotent: re-registering a key
---simply overwrites the previous spec, so calling this after `clear()` in
---tests bootstraps the registry cleanly.
local function register_builtins()
  strategies.register(require("yank-path.strategies.filename"))
  strategies.register(require("yank-path.strategies.absolute"))
  strategies.register(require("yank-path.strategies.relative"))
  strategies.register(require("yank-path.strategies.project"))
end

register_builtins()

---Apply user configuration. Repopulates the built-in registry afterwards
---in case the user cleared it (e.g. in tests) before calling setup.
---@param user_config yank-path.Config|table|nil
function M.setup(user_config)
  config_mod.setup(user_config)
  -- Re-register built-ins after setup so the registry is guaranteed to
  -- contain them even if `strategies.clear()` was called earlier.
  if not strategies.get("f") then
    register_builtins()
  end
end

---Register a custom strategy at runtime.
---Invalid specs are reported via `util.notify_err` rather than raising so
---a typo in user config does not crash the editor.
---@param spec yank-path.Strategy
---@return boolean ok true when the strategy was accepted
function M.register_strategy(spec)
  local ok, err = strategies.register(spec)
  if not ok then
    util.notify_err("register_strategy: " .. err)
    return false
  end
  return true
end

---Open the picker and run the chosen strategy.
---
---Captures the visual range BEFORE opening the picker because every
---picker backend leaves visual mode the moment it takes focus, after
---which `vim.fn.mode()` would report normal mode and the marks would no
---longer reflect the user's selection.
function M.yank()
  local items = strategies.list()
  if #items == 0 then
    util.notify_warn("no strategies registered")
    return
  end

  local rng = range_mod.get()

  local err = picker.pick(items, function(choice)
    if not choice then
      return
    end
    pipeline.run(choice, { range = rng })
  end, config_mod.config.picker)

  if err then
    util.notify_err(err)
  end
end

---Run a specific strategy by key or display name, skipping the picker.
---Intended for users who want to bind keymaps directly to a single
---strategy without going through the popup.
---@param key_or_name string
---@param opts { register: string|nil }|nil
---@return boolean ok false when no matching strategy was found
function M.yank_with(key_or_name, opts)
  local spec = strategies.find(key_or_name)
  if not spec then
    util.notify_err("unknown strategy: " .. tostring(key_or_name))
    return false
  end
  pipeline.run(spec, opts or {})
  return true
end

-- Install the BufFilePost autocmd so the project-root cache invalidates
-- when a buffer is renamed (which can move it into or out of a project).
-- The augroup is keyed by name with `clear = true` so this is idempotent
-- across reloads.
local augroup = vim.api.nvim_create_augroup("yank-path", { clear = true })
vim.api.nvim_create_autocmd("BufFilePost", {
  group = augroup,
  callback = function(args)
    local name = vim.api.nvim_buf_get_name(args.buf)
    if name == "" then
      return
    end
    util.clear_root_cache(vim.fs.dirname(name))
  end,
})

return M
