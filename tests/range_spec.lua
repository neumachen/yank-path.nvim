-- Unit tests for lua/yank-path/range.lua.

local range = require("yank-path.range")

describe("yank-path.range", function()
  local original_mode
  local original_line

  before_each(function()
    original_mode = vim.fn.mode
    original_line = vim.fn.line
  end)

  after_each(function()
    vim.fn.mode = original_mode
    vim.fn.line = original_line
  end)

  describe("get", function()
    it("returns nil in normal mode", function()
      vim.fn.mode = function()
        return "n"
      end
      assert.is_nil(range.get())
    end)

    it("returns a range for linewise visual mode", function()
      vim.fn.mode = function()
        return "V"
      end
      vim.fn.line = function(expr)
        if expr == "'<" then
          return 10
        elseif expr == "'>" then
          return 20
        end
        return 0
      end

      local rng = range.get()
      assert.same({ start = 10, end_ = 20, is_visual = true }, rng)
    end)

    it("returns a single-line range when start == end", function()
      vim.fn.mode = function()
        return "V"
      end
      vim.fn.line = function(expr)
        if expr == "'<" or expr == "'>" then
          return 15
        end
        return 0
      end

      local rng = range.get()
      assert.same({ start = 15, end_ = 15, is_visual = true }, rng)
    end)

    it("handles characterwise visual mode", function()
      vim.fn.mode = function()
        return "v"
      end
      vim.fn.line = function(expr)
        if expr == "'<" then
          return 3
        elseif expr == "'>" then
          return 5
        end
        return 0
      end

      assert.same({ start = 3, end_ = 5, is_visual = true }, range.get())
    end)

    it("handles blockwise visual mode (CTRL-V)", function()
      vim.fn.mode = function()
        return "\22"
      end
      vim.fn.line = function(expr)
        if expr == "'<" then
          return 2
        elseif expr == "'>" then
          return 4
        end
        return 0
      end

      assert.same({ start = 2, end_ = 4, is_visual = true }, range.get())
    end)

    it("normalises swapped endpoints", function()
      vim.fn.mode = function()
        return "V"
      end
      vim.fn.line = function(expr)
        if expr == "'<" then
          return 20
        elseif expr == "'>" then
          return 10
        end
        return 0
      end

      local rng = range.get()
      assert.equals(10, rng.start)
      assert.equals(20, rng.end_)
    end)

    it("returns nil when the visual marks are unpopulated", function()
      vim.fn.mode = function()
        return "V"
      end
      vim.fn.line = function()
        return 0
      end

      assert.is_nil(range.get())
    end)
  end)

  describe("append", function()
    it("appends :line for a single-line range", function()
      local rng = { start = 42, end_ = 42, is_visual = true }
      assert.equals("foo.lua:42", range.append("foo.lua", rng))
    end)

    it("appends :start-end for a multi-line range", function()
      local rng = { start = 10, end_ = 20, is_visual = true }
      assert.equals("foo.lua:10-20", range.append("foo.lua", rng))
    end)
  end)
end)
