-- Unit tests for lua/yank-path/picker/init.lua (resolver) and the three
-- adapter modules. Availability of the optional backends is faked by
-- preloading short stubs into `package.loaded` so the real modules never
-- have to exist on the test runner.

local picker = require("yank-path.picker")
local ui_select_adapter = require("yank-path.picker.ui_select")
local fzf_adapter = require("yank-path.picker.fzf_lua")
local snacks_adapter = require("yank-path.picker.snacks")

local function with_package(name, mod, fn)
  local original = package.loaded[name]
  package.loaded[name] = mod
  local ok, err = pcall(fn)
  package.loaded[name] = original
  if not ok then
    error(err)
  end
end

describe("yank-path.picker resolver", function()
  it("'auto' resolves to fzf-lua when present", function()
    with_package("fzf-lua", { fzf_exec = function() end }, function()
      local adapter, err = picker.resolve("auto")
      assert.is_nil(err)
      assert.equals(fzf_adapter, adapter)
    end)
  end)

  it("'auto' falls through to snacks when fzf-lua is absent", function()
    local original_fzf = package.loaded["fzf-lua"]
    package.loaded["fzf-lua"] = nil
    with_package("snacks", { picker = { select = function() end } }, function()
      local adapter, err = picker.resolve("auto")
      assert.is_nil(err)
      assert.equals(snacks_adapter, adapter)
    end)
    package.loaded["fzf-lua"] = original_fzf
  end)

  it("'auto' falls through to vim.ui.select when fzf-lua and snacks are absent", function()
    local original_fzf = package.loaded["fzf-lua"]
    local original_snacks = package.loaded["snacks"]
    package.loaded["fzf-lua"] = nil
    package.loaded["snacks"] = nil

    local adapter, err = picker.resolve("auto")
    assert.is_nil(err)
    assert.equals(ui_select_adapter, adapter)

    package.loaded["fzf-lua"] = original_fzf
    package.loaded["snacks"] = original_snacks
  end)

  it("returns an error for an unknown backend name", function()
    local adapter, err = picker.resolve("does-not-exist")
    assert.is_nil(adapter)
    assert.matches("unknown picker backend", err)
  end)

  it("resolves an explicit single backend", function()
    local adapter, err = picker.resolve("vim.ui.select")
    assert.is_nil(err)
    assert.equals(ui_select_adapter, adapter)
  end)

  it("respects the order of an explicit list", function()
    with_package("fzf-lua", { fzf_exec = function() end }, function()
      local adapter, err = picker.resolve({ "vim.ui.select", "fzf-lua" })
      assert.is_nil(err)
      -- vim.ui.select is always available so it wins even though fzf-lua
      -- is also loaded.
      assert.equals(ui_select_adapter, adapter)
    end)
  end)

  it("falls back through a list when earlier entries are unavailable", function()
    local original_fzf = package.loaded["fzf-lua"]
    package.loaded["fzf-lua"] = nil

    local adapter, err = picker.resolve({ "fzf-lua", "vim.ui.select" })
    assert.is_nil(err)
    assert.equals(ui_select_adapter, adapter)

    package.loaded["fzf-lua"] = original_fzf
  end)

  it("reports when no backend in the list is available", function()
    local original_fzf = package.loaded["fzf-lua"]
    local original_snacks = package.loaded["snacks"]
    package.loaded["fzf-lua"] = nil
    package.loaded["snacks"] = nil

    local adapter, err = picker.resolve({ "fzf-lua", "snacks" })
    assert.is_nil(adapter)
    assert.matches("no picker backend available", err)
    assert.matches("fzf%-lua", err)
    assert.matches("snacks", err)

    package.loaded["fzf-lua"] = original_fzf
    package.loaded["snacks"] = original_snacks
  end)
end)

describe("yank-path.picker.ui_select", function()
  local original_select

  before_each(function()
    original_select = vim.ui.select
  end)

  after_each(function()
    vim.ui.select = original_select
  end)

  it("is_available always returns true", function()
    assert.is_true(ui_select_adapter.is_available())
  end)

  it("calls vim.ui.select with formatted items and forwards the choice", function()
    local captured_items
    local captured_opts
    local items = {
      { key = "a", name = "Absolute", desc = "x", transform = function() end },
      { key = "f", name = "Filename", desc = "y", transform = function() end },
    }
    vim.ui.select = function(passed_items, opts, on_choice)
      captured_items = passed_items
      captured_opts = opts
      on_choice(passed_items[2])
    end

    local got
    ui_select_adapter.select(items, function(choice)
      got = choice
    end)

    assert.equals(items, captured_items)
    assert.equals("Yank path as:", captured_opts.prompt)
    assert.equals("a — Absolute", captured_opts.format_item(items[1]))
    assert.equals("f", got.key)
  end)
end)

describe("yank-path.picker.fzf_lua", function()
  it("is_available returns false when fzf-lua is not installed", function()
    local original = package.loaded["fzf-lua"]
    package.loaded["fzf-lua"] = nil
    assert.is_false(fzf_adapter.is_available())
    package.loaded["fzf-lua"] = original
  end)

  it("is_available returns true when fzf-lua is installed", function()
    with_package("fzf-lua", { fzf_exec = function() end }, function()
      assert.is_true(fzf_adapter.is_available())
    end)
  end)

  it("select forwards the chosen line to its strategy via the lookup", function()
    local items = {
      { key = "a", name = "Absolute", desc = "full", transform = function() end },
      { key = "f", name = "Filename", desc = "base", transform = function() end },
    }

    local fake = {
      fzf_exec = function(display, opts)
        -- Emulate the user picking the second display line.
        assert.equals(2, #display)
        assert.equals("a — Absolute : full", display[1])
        opts.actions["default"]({ display[2] })
      end,
    }

    with_package("fzf-lua", fake, function()
      local got
      fzf_adapter.select(items, function(choice)
        got = choice
      end)
      assert.equals("f", got.key)
    end)
  end)

  it("select forwards nil when the user cancels", function()
    local items = { { key = "a", name = "Absolute", desc = "x", transform = function() end } }
    local fake = {
      fzf_exec = function(_, opts)
        opts.actions["default"]({})
      end,
    }
    with_package("fzf-lua", fake, function()
      local got = "sentinel"
      fzf_adapter.select(items, function(choice)
        got = choice
      end)
      assert.is_nil(got)
    end)
  end)
end)

describe("yank-path.picker.snacks", function()
  it("is_available returns false when snacks is not installed", function()
    local original = package.loaded["snacks"]
    package.loaded["snacks"] = nil
    assert.is_false(snacks_adapter.is_available())
    package.loaded["snacks"] = original
  end)

  it("is_available returns false when snacks has no picker.select", function()
    with_package("snacks", { picker = {} }, function()
      assert.is_false(snacks_adapter.is_available())
    end)
  end)

  it("is_available returns true when snacks.picker.select exists", function()
    with_package("snacks", { picker = { select = function() end } }, function()
      assert.is_true(snacks_adapter.is_available())
    end)
  end)

  it("select forwards the choice from snacks.picker.select", function()
    local items = {
      { key = "a", name = "Absolute", desc = "x", transform = function() end },
      { key = "p", name = "Project", desc = "y", transform = function() end },
    }

    local fake = {
      picker = {
        select = function(passed_items, opts, on_choice)
          assert.equals(items, passed_items)
          assert.equals("Yank path as:", opts.prompt)
          assert.equals("a — Absolute", opts.format_item(items[1]))
          on_choice(passed_items[2])
        end,
      },
    }

    with_package("snacks", fake, function()
      local got
      snacks_adapter.select(items, function(choice)
        got = choice
      end)
      assert.equals("p", got.key)
    end)
  end)
end)
