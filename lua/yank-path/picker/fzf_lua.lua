-- fzf-lua picker adapter.
--
-- Renders each strategy as `key — name : desc` and uses fzf-lua's action
-- table to call back into the pipeline with the original spec rather than
-- the rendered string.

local M = {}

---@return boolean
function M.is_available()
  return pcall(require, "fzf-lua")
end

---Open the picker.
---@param items yank-path.Strategy[]
---@param on_choice fun(choice: yank-path.Strategy|nil)
function M.select(items, on_choice)
  local fzf = require("fzf-lua")

  -- Build the display strings and a lookup back to the original spec.
  -- The lookup key is the rendered line so the action callback can resolve
  -- the user's pick without parsing.
  local display = {}
  local by_display = {}
  for _, item in ipairs(items) do
    local line = item.key .. " — " .. item.name .. " : " .. item.desc
    display[#display + 1] = line
    by_display[line] = item
  end

  fzf.fzf_exec(display, {
    prompt = "Yank path as> ",
    winopts = { height = 0.4, width = 0.5 },
    actions = {
      ["default"] = function(selected)
        if not selected or #selected == 0 then
          on_choice(nil)
          return
        end
        on_choice(by_display[selected[1]])
      end,
    },
  })
end

return M
