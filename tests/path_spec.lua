-- Unit tests for lua/yank-path/path.lua.

local path = require("yank-path.path")

describe("yank-path.path", function()
  local original_get_name
  local original_fnamemodify
  local original_resolve

  before_each(function()
    original_get_name = vim.api.nvim_buf_get_name
    original_fnamemodify = vim.fn.fnamemodify
    original_resolve = vim.fn.resolve
  end)

  after_each(function()
    vim.api.nvim_buf_get_name = original_get_name
    vim.fn.fnamemodify = original_fnamemodify
    vim.fn.resolve = original_resolve
  end)

  it("returns the absolute resolved path for a named buffer", function()
    vim.api.nvim_buf_get_name = function(bufnr)
      assert.equals(7, bufnr)
      return "src/file.lua"
    end
    vim.fn.fnamemodify = function(name, mods)
      assert.equals("src/file.lua", name)
      assert.equals(":p", mods)
      return "/proj/src/file.lua"
    end
    vim.fn.resolve = function(p)
      return p
    end

    local result, err = path.get(7)
    assert.equals("/proj/src/file.lua", result)
    assert.is_nil(err)
  end)

  it("returns nil + err when the buffer has no associated file", function()
    vim.api.nvim_buf_get_name = function()
      return ""
    end

    local result, err = path.get(0)
    assert.is_nil(result)
    assert.matches("no associated file", err)
  end)

  it("follows symlinks via vim.fn.resolve", function()
    vim.api.nvim_buf_get_name = function()
      return "/tmp/link"
    end
    vim.fn.fnamemodify = function(_, _)
      return "/tmp/link"
    end
    vim.fn.resolve = function(p)
      if p == "/tmp/link" then
        return "/real/target"
      end
      return p
    end

    local result, err = path.get(0)
    assert.equals("/real/target", result)
    assert.is_nil(err)
  end)
end)
