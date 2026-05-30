-- Picker backend resolver.
--
-- Takes the user's `picker` config and returns the first adapter whose
-- `is_available()` reports true. Configuration shapes:
--
--   "auto"                                  -- walk the default priority
--   "fzf-lua" | "snacks" | "vim.ui.select"  -- force a single backend
--   { "fzf-lua", "vim.ui.select" }          -- ordered list with fallback

local M = {}

-- The default priority is fzf-lua first because it is the most common
-- explicit fuzzy-finder install in practice; snacks second so users who
-- have already adopted the snacks ecosystem get its UI without configuring;
-- vim.ui.select last so the always-available baseline catches everyone
-- else (including users who have wired their own ui.select replacement).
local DEFAULT_PRIORITY = { "fzf-lua", "snacks", "vim.ui.select" }

local ADAPTERS = {
  ["fzf-lua"] = "yank-path.picker.fzf_lua",
  ["snacks"] = "yank-path.picker.snacks",
  ["vim.ui.select"] = "yank-path.picker.ui_select",
}

---Normalize the picker config into an ordered list of backend names.
---@param picker_config string|string[]
---@return string[]|nil names ordered backend names, or nil for an invalid shape
---@return string|nil err
local function normalize(picker_config)
  if picker_config == "auto" then
    return DEFAULT_PRIORITY, nil
  end
  if type(picker_config) == "string" then
    return { picker_config }, nil
  end
  if type(picker_config) == "table" then
    for _, name in ipairs(picker_config) do
      if type(name) ~= "string" then
        return nil, "picker config contains a non-string entry"
      end
    end
    return picker_config, nil
  end
  return nil, "picker config must be a string or array of strings"
end

---@class yank-path.PickerAdapter
---@field is_available fun(): boolean
---@field select fun(items: yank-path.Strategy[], on_choice: fun(choice: yank-path.Strategy|nil))

---Resolve to the first available adapter for the given config.
---Returns `(adapter, nil)` on success or `(nil, err)` describing why no
---backend could be selected.
---@param picker_config string|string[]
---@return yank-path.PickerAdapter|nil
---@return string|nil
function M.resolve(picker_config)
  local names, err = normalize(picker_config)
  if err then
    return nil, err
  end

  local tried = {}
  for _, name in ipairs(names) do
    local module_name = ADAPTERS[name]
    if not module_name then
      return nil, "unknown picker backend: " .. name
    end
    local adapter = require(module_name)
    tried[#tried + 1] = name
    if adapter.is_available() then
      return adapter, nil
    end
  end

  return nil, "no picker backend available (tried: " .. table.concat(tried, ", ") .. ")"
end

---Open the picker by resolving the configured backend and delegating.
---@param items yank-path.Strategy[]
---@param on_choice fun(choice: yank-path.Strategy|nil)
---@param picker_config string|string[]
---@return string|nil err non-nil when no backend could be resolved
function M.pick(items, on_choice, picker_config)
  local adapter, err = M.resolve(picker_config)
  if not adapter then
    return err
  end
  adapter.select(items, on_choice)
  return nil
end

return M
