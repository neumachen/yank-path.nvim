-- Unit tests for lua/yank-path/strategies/init.lua and each built-in
-- strategy under lua/yank-path/strategies/.

local strategies = require("yank-path.strategies")
local filename = require("yank-path.strategies.filename")
local absolute = require("yank-path.strategies.absolute")
local relative = require("yank-path.strategies.relative")
local project = require("yank-path.strategies.project")
local util = require("yank-path.util")

describe("yank-path.strategies registry", function()
  before_each(function()
    strategies.clear()
  end)

  after_each(function()
    strategies.clear()
    -- Restore the built-ins so any later spec that requires yank-path
    -- still finds them.
    strategies.register(filename)
    strategies.register(absolute)
    strategies.register(relative)
    strategies.register(project)
  end)

  describe("register", function()
    it("accepts a well-formed spec", function()
      local ok, err = strategies.register({
        key = "x",
        name = "X",
        desc = "test",
        transform = function() end,
      })
      assert.is_true(ok)
      assert.is_nil(err)
      assert.is_not_nil(strategies.get("x"))
    end)

    it("rejects non-table specs", function()
      local ok, err = strategies.register("nope")
      assert.is_false(ok)
      assert.matches("strategy must be a table", err)
    end)

    it("rejects multi-character keys", function()
      local ok, err = strategies.register({
        key = "xx",
        name = "X",
        desc = "test",
        transform = function() end,
      })
      assert.is_false(ok)
      assert.matches("single%-character", err)
    end)

    it("rejects non-alphanumeric keys", function()
      local ok, err = strategies.register({
        key = "!",
        name = "X",
        desc = "test",
        transform = function() end,
      })
      assert.is_false(ok)
      assert.matches("alphanumeric", err)
    end)

    it("rejects an empty name", function()
      local ok, err = strategies.register({
        key = "x",
        name = "",
        desc = "test",
        transform = function() end,
      })
      assert.is_false(ok)
      assert.matches("non%-empty string", err)
    end)

    it("rejects a non-callable transform", function()
      local ok, err = strategies.register({
        key = "x",
        name = "X",
        desc = "test",
        transform = "nope",
      })
      assert.is_false(ok)
      assert.matches("function or callable", err)
    end)
  end)

  describe("get / find", function()
    it("get returns nil for an unknown key", function()
      assert.is_nil(strategies.get("z"))
    end)

    it("find resolves by key", function()
      strategies.register(absolute)
      assert.equals("a", strategies.find("a").key)
    end)

    it("find resolves by display name", function()
      strategies.register(absolute)
      assert.equals("a", strategies.find("Absolute").key)
    end)

    it("find resolves by display name case-insensitively", function()
      strategies.register(absolute)
      assert.equals("a", strategies.find("absolute").key)
      assert.equals("a", strategies.find("ABSOLUTE").key)
    end)

    it("find returns nil when nothing matches", function()
      assert.is_nil(strategies.find("nope"))
    end)
  end)

  describe("list", function()
    it("returns specs sorted by key alphabetically", function()
      strategies.register(absolute)
      strategies.register(filename)
      strategies.register(project)
      strategies.register(relative)

      local out = strategies.list()
      local keys = {}
      for i, spec in ipairs(out) do
        keys[i] = spec.key
      end
      assert.same({ "a", "f", "p", "r" }, keys)
    end)
  end)
end)

describe("yank-path.strategies built-ins", function()
  local original_fnamemodify

  before_each(function()
    original_fnamemodify = vim.fn.fnamemodify
  end)

  after_each(function()
    vim.fn.fnamemodify = original_fnamemodify
    util.clear_all_root_cache()
  end)

  describe("filename", function()
    it("returns the :t basename", function()
      vim.fn.fnamemodify = function(p, mods)
        assert.equals(":t", mods)
        return p:match("([^/]+)$")
      end

      local out, err = filename.transform("/proj/src/file.lua", {})
      assert.equals("file.lua", out)
      assert.is_nil(err)
    end)
  end)

  describe("absolute", function()
    it("returns its input unchanged", function()
      local out, err = absolute.transform("/proj/src/file.lua", {})
      assert.equals("/proj/src/file.lua", out)
      assert.is_nil(err)
    end)
  end)

  describe("relative", function()
    local original_input

    before_each(function()
      original_input = vim.ui.input
    end)

    after_each(function()
      vim.ui.input = original_input
    end)

    it("strips down to N levels above the file", function()
      vim.ui.input = function(_opts, cb)
        cb("2")
      end

      local captured
      local ctx = {
        continue = function(result, err)
          captured = { result = result, err = err }
        end,
      }
      relative.transform("/a/b/c/d/file.lua", ctx)

      assert.equals("c/d/file.lua", captured.result)
      assert.is_nil(captured.err)
    end)

    it("returns just the filename for N = 0", function()
      vim.ui.input = function(_opts, cb)
        cb("0")
      end

      local captured
      local ctx = {
        continue = function(result, err)
          captured = { result = result, err = err }
        end,
      }
      relative.transform("/a/b/c/file.lua", ctx)

      assert.equals("file.lua", captured.result)
      assert.is_nil(captured.err)
    end)

    it("returns nil result silently when the user cancels", function()
      vim.ui.input = function(_opts, cb)
        cb(nil)
      end

      local captured
      local ctx = {
        continue = function(result, err)
          captured = { result = result, err = err }
        end,
      }
      relative.transform("/a/b/file.lua", ctx)

      assert.is_nil(captured.result)
      assert.is_nil(captured.err)
    end)

    it("notifies and cancels when the input is not a non-negative integer", function()
      vim.ui.input = function(_opts, cb)
        cb("not-a-number")
      end

      local original_notify = vim.notify
      local notified
      vim.notify = function(msg, level)
        notified = { msg = msg, level = level }
      end

      local captured
      local ctx = {
        continue = function(result, err)
          captured = { result = result, err = err }
        end,
      }
      relative.transform("/a/b/file.lua", ctx)

      vim.notify = original_notify

      assert.is_not_nil(notified)
      assert.equals(vim.log.levels.ERROR, notified.level)
      assert.matches("invalid level count", notified.msg)
      assert.is_nil(captured.result)
    end)
  end)

  describe("project", function()
    local original_get_name
    local original_find
    local original_dirname

    before_each(function()
      original_get_name = vim.api.nvim_buf_get_name
      original_find = vim.fs.find
      original_dirname = vim.fs.dirname
    end)

    after_each(function()
      vim.api.nvim_buf_get_name = original_get_name
      vim.fs.find = original_find
      vim.fs.dirname = original_dirname
    end)

    it("strips the project root prefix from the absolute path", function()
      vim.api.nvim_buf_get_name = function()
        return "/proj/src/file.lua"
      end
      vim.fs.dirname = function(p)
        if p == "/proj/src/file.lua" then
          return "/proj/src"
        elseif p == "/proj/.git" then
          return "/proj"
        end
        return original_dirname(p)
      end
      vim.fs.find = function()
        return { "/proj/.git" }
      end

      local ctx = {
        bufnr = 0,
        config = { project = { markers = { ".git" }, cache = false } },
      }
      local out, err = project.transform("/proj/src/file.lua", ctx)
      assert.equals("src/file.lua", out)
      assert.is_nil(err)
    end)

    it("reports an error when no root marker is found", function()
      vim.api.nvim_buf_get_name = function()
        return "/lonely/file.lua"
      end
      vim.fs.dirname = function(p)
        if p == "/lonely/file.lua" then
          return "/lonely"
        end
        return original_dirname(p)
      end
      vim.fs.find = function()
        return {}
      end

      local ctx = {
        bufnr = 0,
        config = { project = { markers = { ".git" }, cache = false } },
      }
      local out, err = project.transform("/lonely/file.lua", ctx)
      assert.is_nil(out)
      assert.matches("project root not found", err)
      assert.matches("%.git", err)
    end)
  end)
end)
