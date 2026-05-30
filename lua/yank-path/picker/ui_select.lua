-- vim.ui.select picker adapter — the always-available fallback.
--
-- This adapter is also the indirect beneficiary of any ui.select override
-- the user has installed (e.g. dressing.nvim, snacks.ui_select, fzf-lua's
-- register_ui_select); when those are configured, picking up this adapter
-- automatically routes through the user's preferred UX without extra code.

local M = {}

---@return boolean
function M.is_available()
  -- vim.ui.select has shipped with Neovim since 0.6; on the supported
  -- 0.11+ matrix it is always present.
  return true
end

---Open the picker.
---@param items yank-path.Strategy[]
---@param on_choice fun(choice: yank-path.Strategy|nil)
function M.select(items, on_choice)
  vim.ui.select(items, {
    prompt = "Yank path as:",
    format_item = function(item)
      return item.key .. " — " .. item.name
    end,
  }, function(choice)
    on_choice(choice)
  end)
end

return M
