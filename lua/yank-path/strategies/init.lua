-- Registry for path-transformation strategies.
--
-- Built-in strategies and user-registered ones live in the same flat
-- namespace keyed by `key` (the single-letter shortcut shown in the picker).
-- The registry validates inputs aggressively so a broken spec is rejected
-- with a clear error rather than crashing the picker later.

local util = require("yank-path.util")

---@class yank-path.Context
---@field bufnr integer source buffer
---@field absolute string absolute, symlink-resolved path of the buffer
---@field range yank-path.Range|nil active visual range when invoked from visual mode
---@field config yank-path.Config live plugin config
---@field continue fun(result: string|nil, err: string|nil) async completion callback

---@class yank-path.Strategy
---@field key string single-character shortcut shown in the picker
---@field name string short display name
---@field desc string longer description shown in the preview slot
---@field transform fun(absolute: string, ctx: yank-path.Context): string|nil, string|nil

local M = {}

---@type table<string, yank-path.Strategy>
local registry = {}

---Validate a strategy spec. Returns `(true, nil)` on success or
---`(false, err)` with the first problem encountered. Kept verbose so the
---error message tells the user exactly which field is broken.
---@param spec any
---@return boolean ok
---@return string|nil err
local function validate(spec)
  if type(spec) ~= "table" then
    return false, "strategy must be a table, got " .. type(spec)
  end
  if type(spec.key) ~= "string" or #spec.key ~= 1 then
    return false, "strategy.key must be a single-character string"
  end
  if not spec.key:match("^[%w]$") then
    return false, "strategy.key must be alphanumeric"
  end
  if type(spec.name) ~= "string" or spec.name == "" then
    return false, "strategy.name must be a non-empty string"
  end
  if type(spec.desc) ~= "string" then
    return false, "strategy.desc must be a string"
  end
  if not util.is_callable(spec.transform) then
    return false, "strategy.transform must be a function or callable"
  end
  return true, nil
end

---Register a strategy. Returns `(true, nil)` on success or `(false, err)`
---when validation fails so callers (especially `init.register_strategy`)
---can route the error to a notification without re-implementing the rules.
---@param spec yank-path.Strategy
---@return boolean ok
---@return string|nil err
function M.register(spec)
  local ok, err = validate(spec)
  if not ok then
    return false, err
  end
  registry[spec.key] = spec
  return true, nil
end

---Look up a strategy by its `key`.
---@param key string
---@return yank-path.Strategy|nil
function M.get(key)
  return registry[key]
end

---Look up a strategy by either its `key` or its display `name`. Used by the
---programmatic `yank_with` API so users can call `yank_with("absolute")`
---without needing to remember the single-letter shortcut.
---@param key_or_name string
---@return yank-path.Strategy|nil
function M.find(key_or_name)
  if registry[key_or_name] then
    return registry[key_or_name]
  end
  for _, spec in pairs(registry) do
    if spec.name == key_or_name then
      return spec
    end
  end
  return nil
end

---Return every registered strategy in alphabetical order by key. Sorting
---keeps the picker output deterministic across invocations and Neovim
---versions where `pairs()` order would otherwise drift.
---@return yank-path.Strategy[]
function M.list()
  local keys = {}
  for k in pairs(registry) do
    keys[#keys + 1] = k
  end
  table.sort(keys)

  local out = {}
  for i, k in ipairs(keys) do
    out[i] = registry[k]
  end
  return out
end

---Reset the registry. Primarily a test affordance — the runtime contract
---is that built-ins are re-registered by `init.lua` on every `setup()` so
---tests can clear state and re-bootstrap without leaking.
function M.clear()
  registry = {}
end

return M
