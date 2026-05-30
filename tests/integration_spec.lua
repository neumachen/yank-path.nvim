-- End-to-end integration tests covering the user-facing flows described
-- in the PRD. Mocks the filesystem and picker backends so the suite never
-- depends on which adapters or repos are present on the runner.

local yp = require("yank-path")
local config_mod = require("yank-path.config")
local strategies = require("yank-path.strategies")
local util = require("yank-path.util")

describe("yank-path integration", function()
  local original_get_name
  local original_fnamemodify
  local original_resolve
  local original_mode
  local original_line
  local original_setreg
  local original_notify
  local original_get_current_buf
  local original_ui_select
  local original_ui_input
  local original_fs_find
  local original_fs_dirname

  local clipboard
  local notifications

  local function reset_runtime()
    config_mod.setup()
    strategies.clear()
    -- Re-register built-ins through setup() because that is the runtime
    -- contract: clear + setup repopulates the registry.
    yp.setup()
    util.clear_all_root_cache()
  end

  before_each(function()
    original_get_name = vim.api.nvim_buf_get_name
    original_fnamemodify = vim.fn.fnamemodify
    original_resolve = vim.fn.resolve
    original_mode = vim.fn.mode
    original_line = vim.fn.line
    original_setreg = vim.fn.setreg
    original_notify = vim.notify
    original_get_current_buf = vim.api.nvim_get_current_buf
    original_ui_select = vim.ui.select
    original_ui_input = vim.ui.input
    original_fs_find = vim.fs.find
    original_fs_dirname = vim.fs.dirname

    vim.api.nvim_get_current_buf = function()
      return 42
    end
    vim.api.nvim_buf_get_name = function()
      return "/proj/src/file.lua"
    end
    vim.fn.fnamemodify = function(p, mods)
      if mods == ":p" then
        return p
      elseif mods == ":t" then
        return p:match("([^/]+)$")
      end
      return p
    end
    vim.fn.resolve = function(p)
      return p
    end
    vim.fn.mode = function()
      return "n"
    end
    vim.fn.line = function()
      return 0
    end

    clipboard = {}
    vim.fn.setreg = function(reg, text)
      clipboard[#clipboard + 1] = { register = reg, text = text }
    end

    notifications = {}
    vim.notify = function(msg, level)
      notifications[#notifications + 1] = { msg = msg, level = level }
    end

    -- Force vim.ui.select as the picker so tests do not depend on whether
    -- fzf-lua / snacks happen to be present on the runner.
    config_mod.setup({ picker = "vim.ui.select" })
  end)

  after_each(function()
    vim.api.nvim_buf_get_name = original_get_name
    vim.fn.fnamemodify = original_fnamemodify
    vim.fn.resolve = original_resolve
    vim.fn.mode = original_mode
    vim.fn.line = original_line
    vim.fn.setreg = original_setreg
    vim.notify = original_notify
    vim.api.nvim_get_current_buf = original_get_current_buf
    vim.ui.select = original_ui_select
    vim.ui.input = original_ui_input
    vim.fs.find = original_fs_find
    vim.fs.dirname = original_fs_dirname
    reset_runtime()
  end)

  it("(1) :YankPath picker -> 'a' -> absolute path lands in + register", function()
    vim.ui.select = function(items, _opts, on_choice)
      -- Simulate the user picking the 'a' strategy from the menu.
      for _, item in ipairs(items) do
        if item.key == "a" then
          on_choice(item)
          return
        end
      end
      on_choice(nil)
    end

    yp.yank()

    assert.equals(1, #clipboard)
    assert.equals("+", clipboard[1].register)
    assert.equals("/proj/src/file.lua", clipboard[1].text)
  end)

  it("(2) visual mode invocation appends the range", function()
    -- The range is captured by yank() BEFORE opening the picker, so the
    -- mode mock fires during the synchronous prelude.
    vim.fn.mode = function()
      return "V"
    end
    vim.fn.line = function(expr)
      if expr == "'<" then
        return 5
      elseif expr == "'>" then
        return 7
      end
      return 0
    end

    vim.ui.select = function(items, _opts, on_choice)
      for _, item in ipairs(items) do
        if item.key == "a" then
          on_choice(item)
          return
        end
      end
    end

    yp.yank()

    assert.equals("/proj/src/file.lua:5-7", clipboard[1].text)
  end)

  it("(3) 'r' strategy prompts for N and strips correctly", function()
    vim.ui.select = function(items, _opts, on_choice)
      for _, item in ipairs(items) do
        if item.key == "r" then
          on_choice(item)
          return
        end
      end
    end
    vim.ui.input = function(_opts, cb)
      cb("3")
    end

    yp.yank()

    -- /proj/src/file.lua with N=3 keeps the last 4 segments: proj/src/file.lua
    -- but the path has only three useful segments after the leading /, so we
    -- get the full relative tail.
    assert.equals(1, #clipboard)
    assert.equals("proj/src/file.lua", clipboard[1].text)
  end)

  it("(4) 'p' strategy resolves the git root and caches it on second invocation", function()
    vim.fs.find = function(_markers, _opts)
      return { "/proj/.git" }
    end
    vim.fs.dirname = function(p)
      if p == "/proj/src/file.lua" then
        return "/proj/src"
      elseif p == "/proj/.git" then
        return "/proj"
      end
      return original_fs_dirname(p)
    end

    -- Spy on find to verify the cache.
    local find_calls = 0
    local original_find = vim.fs.find
    vim.fs.find = function(...)
      find_calls = find_calls + 1
      return original_find(...)
    end

    vim.ui.select = function(items, _opts, on_choice)
      for _, item in ipairs(items) do
        if item.key == "p" then
          on_choice(item)
          return
        end
      end
    end

    yp.yank()
    yp.yank()

    assert.equals(2, #clipboard)
    assert.equals("src/file.lua", clipboard[1].text)
    assert.equals("src/file.lua", clipboard[2].text)
    -- One filesystem walk; the second invocation hit the cache.
    assert.equals(1, find_calls)
  end)

  it("(5) yank_with('absolute') skips the picker and yanks directly", function()
    -- vim.ui.select must NOT be called for this flow.
    local picker_calls = 0
    vim.ui.select = function()
      picker_calls = picker_calls + 1
    end

    local ok = yp.yank_with("absolute")
    assert.is_true(ok)
    assert.equals(0, picker_calls)
    assert.equals(1, #clipboard)
    assert.equals("/proj/src/file.lua", clipboard[1].text)
  end)

  it("(5b) yank_with by key shortcut also bypasses the picker", function()
    vim.ui.select = function() end
    yp.yank_with("a")
    assert.equals(1, #clipboard)
    assert.equals("/proj/src/file.lua", clipboard[1].text)
  end)

  it("(5c) yank_with on an unknown strategy reports an error and returns false", function()
    local ok = yp.yank_with("does-not-exist")
    assert.is_false(ok)
    assert.equals(0, #clipboard)
    assert.equals(1, #notifications)
    assert.equals(vim.log.levels.ERROR, notifications[1].level)
    assert.matches("unknown strategy", notifications[1].msg)
  end)

  it("(6) a user-registered strategy appears in the picker and runs through the pipeline", function()
    local ok = yp.register_strategy({
      key = "u",
      name = "Upper",
      desc = "uppercase",
      transform = function(absolute, _ctx)
        return absolute:upper(), nil
      end,
    })
    assert.is_true(ok)

    local saw_u = false
    vim.ui.select = function(items, _opts, on_choice)
      for _, item in ipairs(items) do
        if item.key == "u" then
          saw_u = true
          on_choice(item)
          return
        end
      end
    end

    yp.yank()

    assert.is_true(saw_u)
    assert.equals("/PROJ/SRC/FILE.LUA", clipboard[1].text)
  end)

  it("(7) explicit picker = 'vim.ui.select' wins even if fzf-lua is loadable", function()
    -- Pre-load a fake fzf-lua so its adapter would otherwise be selected.
    local original_fzf = package.loaded["fzf-lua"]
    package.loaded["fzf-lua"] = {
      fzf_exec = function()
        error("should not be called")
      end,
    }

    local ui_called = false
    vim.ui.select = function(items, _opts, on_choice)
      ui_called = true
      for _, item in ipairs(items) do
        if item.key == "a" then
          on_choice(item)
          return
        end
      end
    end

    yp.yank()

    package.loaded["fzf-lua"] = original_fzf

    assert.is_true(ui_called)
    assert.equals(1, #clipboard)
  end)

  it("(8) ordered list with no available backends notifies and yanks nothing", function()
    -- Build a config that names only an absent backend and one with a
    -- guaranteed-false availability check.
    config_mod.setup({ picker = { "fzf-lua", "snacks" } })

    -- Force both adapters to report unavailable by unloading their fakes.
    local original_fzf = package.loaded["fzf-lua"]
    local original_snacks = package.loaded["snacks"]
    package.loaded["fzf-lua"] = nil
    package.loaded["snacks"] = nil

    yp.yank()

    package.loaded["fzf-lua"] = original_fzf
    package.loaded["snacks"] = original_snacks

    assert.equals(0, #clipboard)
    assert.equals(1, #notifications)
    assert.equals(vim.log.levels.ERROR, notifications[1].level)
    assert.matches("no picker backend available", notifications[1].msg)
  end)

  it("(9) strategy returning an error notifies at ERROR level without crashing", function()
    yp.register_strategy({
      key = "e",
      name = "Erroring",
      desc = "fails",
      transform = function()
        return nil, "deliberately broken"
      end,
    })

    vim.ui.select = function(items, _opts, on_choice)
      for _, item in ipairs(items) do
        if item.key == "e" then
          on_choice(item)
          return
        end
      end
    end

    yp.yank()

    assert.equals(0, #clipboard)
    assert.equals(1, #notifications)
    assert.equals(vim.log.levels.ERROR, notifications[1].level)
    assert.matches("deliberately broken", notifications[1].msg)
  end)

  it("(9b) strategy that raises is caught by pcall and reported", function()
    yp.register_strategy({
      key = "b",
      name = "Boom",
      desc = "raises",
      transform = function()
        error("uncaught failure")
      end,
    })

    vim.ui.select = function(items, _opts, on_choice)
      for _, item in ipairs(items) do
        if item.key == "b" then
          on_choice(item)
          return
        end
      end
    end

    yp.yank()

    assert.equals(0, #clipboard)
    assert.equals(1, #notifications)
    assert.equals(vim.log.levels.ERROR, notifications[1].level)
    assert.matches("strategy 'Boom' raised", notifications[1].msg)
  end)

  it("(10) custom register config writes to that register, not +", function()
    config_mod.setup({ register = "x", picker = "vim.ui.select" })

    vim.ui.select = function(items, _opts, on_choice)
      for _, item in ipairs(items) do
        if item.key == "a" then
          on_choice(item)
          return
        end
      end
    end

    yp.yank()

    assert.equals(1, #clipboard)
    assert.equals("x", clipboard[1].register)
  end)

  it("(10b) register_strategy with malformed input reports error and refuses to register", function()
    local ok = yp.register_strategy({ key = "!", name = "bad", desc = "x", transform = function() end })
    assert.is_false(ok)
    assert.equals(1, #notifications)
    assert.equals(vim.log.levels.ERROR, notifications[1].level)
    assert.matches("alphanumeric", notifications[1].msg)
  end)
end)
