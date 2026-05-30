-- Unit tests for lua/yank-path/register.lua.

local register = require("yank-path.register")

describe("yank-path.register", function()
  local original_setreg
  local captured

  before_each(function()
    original_setreg = vim.fn.setreg
    captured = {}
    vim.fn.setreg = function(reg, text)
      captured[#captured + 1] = { register = reg, text = text }
    end
  end)

  after_each(function()
    vim.fn.setreg = original_setreg
  end)

  it("defaults to the + register when none is supplied", function()
    register.write("hello")
    assert.equals(1, #captured)
    assert.equals("+", captured[1].register)
    assert.equals("hello", captured[1].text)
  end)

  it("writes to the explicitly provided register", function()
    register.write("hi", "*")
    assert.equals(1, #captured)
    assert.equals("*", captured[1].register)
    assert.equals("hi", captured[1].text)
  end)

  it("accepts arbitrary named registers", function()
    register.write("yo", "a")
    assert.equals("a", captured[1].register)
  end)
end)
