-- Built-in strategy: return the path starting N parent directories above
-- the file. Picker shortcut `r`.
--
-- Async by design: the strategy prompts the user with `vim.ui.input` for
-- the number of levels and then routes the result through `ctx.continue`
-- so the pipeline can append a range (when invoked from visual mode) and
-- write to the register without the strategy knowing about either step.

local util = require("yank-path.util")

---Compute the suffix consisting of the last `levels + 1` path segments.
---Returns the suffix joined by `/` with no leading slash, e.g. for
---`/a/b/c/d/file.lua` with levels=2 -> `c/d/file.lua`. When levels exceeds
---the available depth the full relative segment list is returned.
---@param absolute string
---@param levels integer non-negative integer
---@return string
local function strip_to_depth(absolute, levels)
  local segments = {}
  for segment in absolute:gmatch("[^/]+") do
    segments[#segments + 1] = segment
  end

  local total = #segments
  local take = math.min(levels + 1, total)
  local first = total - take + 1

  local out = {}
  for i = first, total do
    out[#out + 1] = segments[i]
  end
  return table.concat(out, "/")
end

---@type yank-path.Strategy
return {
  key = "r",
  name = "Relative (N up)",
  desc = "Path starting N parents up from the file",
  transform = function(absolute, ctx)
    vim.ui.input({ prompt = "Levels up: ", default = "1" }, function(input)
      if input == nil or input == "" then
        ctx.continue(nil, nil)
        return
      end

      local n = tonumber(input)
      if not n or n < 0 or math.floor(n) ~= n then
        util.notify_err("invalid level count: " .. tostring(input))
        ctx.continue(nil, nil)
        return
      end

      ctx.continue(strip_to_depth(absolute, n), nil)
    end)

    -- Signal async completion: the pipeline waits for `ctx.continue`.
    return nil, nil
  end,
}
