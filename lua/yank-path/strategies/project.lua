-- Built-in strategy: return the buffer's path relative to the project
-- root, where "root" means the first ancestor directory containing one of
-- the configured root markers (default `.git`). Picker shortcut `p`.

local util = require("yank-path.util")

---Strip a leading prefix from a path and remove the residual leading slash.
---Pure string ops, no vim regex — avoids the escape gymnastics the legacy
---plugin needed when prefixes contained special characters.
---@param path string
---@param prefix string
---@return string
local function strip_prefix(path, prefix)
  if path:sub(1, #prefix) == prefix then
    local rest = path:sub(#prefix + 1)
    return rest:gsub("^/+", "")
  end
  return path
end

---@type yank-path.Strategy
return {
  key = "p",
  name = "Project",
  desc = "Path relative to project root",
  transform = function(absolute, ctx)
    local root = util.find_project_root(ctx.bufnr, ctx.config.project)
    if not root then
      local markers = table.concat(ctx.config.project.markers or {}, ", ")
      return nil, "project root not found (markers: " .. markers .. ")"
    end
    return strip_prefix(absolute, root), nil
  end,
}
