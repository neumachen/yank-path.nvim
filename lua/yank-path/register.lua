-- Write a transformed path into a Neovim register. Notifications happen at
-- the pipeline level, not here, so this module stays trivially mockable in
-- tests and never side-effects beyond the register write.

local M = {}

---Write text to a register.
---
---When `register` is nil the system clipboard (`"+"`) is used so the common
---case requires no caller boilerplate. `vim.fn.setreg` accepts any valid
---register name including `"*"`, `"+"`, `"""`, or a single alphanumeric.
---@param text string content to write
---@param register string|nil destination register; defaults to `"+"`
function M.write(text, register)
  vim.fn.setreg(register or "+", text)
end

return M
