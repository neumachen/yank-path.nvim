-- snacks.nvim picker adapter.
--
-- Uses Snacks.picker.select which mirrors vim.ui.select but renders inside
-- the snacks picker UI. Availability check is two-stage so the adapter
-- gracefully bows out on older snacks versions that predate the picker
-- module.

local M = {}

---@return boolean
function M.is_available()
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    return false
  end
  return snacks.picker ~= nil and type(snacks.picker.select) == "function"
end

---Open the picker.
---@param items yank-path.Strategy[]
---@param on_choice fun(choice: yank-path.Strategy|nil)
function M.select(items, on_choice)
  local snacks = require("snacks")

  snacks.picker.select(items, {
    prompt = "Yank path as:",
    format_item = function(item)
      return item.key .. " — " .. item.name
    end,
  }, function(choice)
    on_choice(choice)
  end)
end

return M
