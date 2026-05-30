-- Configuration management for yank-path.nvim.
--
-- Holds the active config table, validates user-supplied overrides, and
-- exposes `setup(user_config)` for one-time initialization. Validation
-- failures surface through `util.notify_err` rather than `error()` so a
-- mistyped option never crashes the host editor; the previous value is
-- preserved when validation fails.

local util = require("yank-path.util")

local M = {}

---@class yank-path.ProjectConfig
---@field markers string[] filenames or directories that mark a project root
---@field find_root (fun(bufnr: integer): string|nil)|nil custom root resolver
---@field cache boolean cache root results per buffer directory

---@class yank-path.Config
---@field register string target register for `setreg`; defaults to the system clipboard
---@field picker string|string[] backend name, ordered list, or `"auto"`
---@field project yank-path.ProjectConfig

---Frozen default config. Always treated as the source of truth when merging.
---@type yank-path.Config
M.default_config = {
  register = "+",
  picker = "auto",
  project = {
    markers = { ".git" },
    find_root = nil,
    cache = true,
  },
}

---Live config. Initialized to a deep copy of the defaults so mutating
---`M.config` cannot leak back into `M.default_config`.
---@type yank-path.Config
M.config = vim.deepcopy(M.default_config)

---Validate a user-supplied config table. Returns `(true, nil)` when the
---input is acceptable or `(false, err)` with a human-readable description
---of the first problem found.
---@param user_config table|nil
---@return boolean ok
---@return string|nil err
local function validate(user_config)
  if user_config == nil then
    return true, nil
  end
  if type(user_config) ~= "table" then
    return false, "setup() expects a table, got " .. type(user_config)
  end

  if user_config.register ~= nil and type(user_config.register) ~= "string" then
    return false, "config.register must be a string"
  end

  if user_config.picker ~= nil then
    local picker = user_config.picker
    if type(picker) ~= "string" and type(picker) ~= "table" then
      return false, "config.picker must be a string or an array of strings"
    end
    if type(picker) == "table" then
      for i, name in ipairs(picker) do
        if type(name) ~= "string" then
          return false, "config.picker[" .. i .. "] must be a string"
        end
      end
    end
  end

  if user_config.project ~= nil then
    local project = user_config.project
    if type(project) ~= "table" then
      return false, "config.project must be a table"
    end
    if project.markers ~= nil then
      if type(project.markers) ~= "table" then
        return false, "config.project.markers must be an array of strings"
      end
      for i, marker in ipairs(project.markers) do
        if type(marker) ~= "string" then
          return false, "config.project.markers[" .. i .. "] must be a string"
        end
      end
    end
    if project.find_root ~= nil and not util.is_callable(project.find_root) then
      return false, "config.project.find_root must be a function or callable"
    end
    if project.cache ~= nil and type(project.cache) ~= "boolean" then
      return false, "config.project.cache must be a boolean"
    end
  end

  return true, nil
end

---Replace the live config with the merge of defaults + user overrides.
---On validation failure the existing config is left untouched and a
---notification is emitted so misconfiguration never silently corrupts state.
---@param user_config yank-path.Config|table|nil partial overrides; nil resets to defaults
function M.setup(user_config)
  local ok, err = validate(user_config)
  if not ok then
    util.notify_err("invalid config: " .. err)
    return
  end

  local merged = vim.tbl_deep_extend("force", vim.deepcopy(M.default_config), user_config or {})

  -- Replace in place so any module that captured a reference to `M.config`
  -- continues to see the latest values.
  for k in pairs(M.config) do
    M.config[k] = nil
  end
  for k, v in pairs(merged) do
    M.config[k] = v
  end
end

return M
