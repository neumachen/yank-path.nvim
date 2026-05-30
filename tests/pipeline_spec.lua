-- Unit tests for lua/yank-path/pipeline.lua.

local pipeline = require("yank-path.pipeline")
local config_mod = require("yank-path.config")

describe("yank-path.pipeline", function()
  local original_get_name
  local original_fnamemodify
  local original_resolve
  local original_mode
  local original_line
  local original_setreg
  local original_notify
  local original_get_current_buf

  local clipboard
  local notifications

  before_each(function()
    config_mod.setup()

    original_get_name = vim.api.nvim_buf_get_name
    original_fnamemodify = vim.fn.fnamemodify
    original_resolve = vim.fn.resolve
    original_mode = vim.fn.mode
    original_line = vim.fn.line
    original_setreg = vim.fn.setreg
    original_notify = vim.notify
    original_get_current_buf = vim.api.nvim_get_current_buf

    vim.api.nvim_get_current_buf = function()
      return 42
    end
    vim.api.nvim_buf_get_name = function()
      return "/proj/src/file.lua"
    end
    vim.fn.fnamemodify = function(p, _mods)
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
    config_mod.setup()
  end)

  local function sync_strategy(name)
    return {
      key = "z",
      name = name or "Sync",
      desc = "test",
      transform = function(absolute, _ctx)
        return absolute, nil
      end,
    }
  end

  it("runs the happy path: path -> transform -> write -> notify", function()
    pipeline.run(sync_strategy("Sync"))

    assert.equals(1, #clipboard)
    assert.equals("+", clipboard[1].register)
    assert.equals("/proj/src/file.lua", clipboard[1].text)

    -- Exactly one INFO notification on success.
    assert.equals(1, #notifications)
    assert.equals(vim.log.levels.INFO, notifications[1].level)
    assert.matches("yanked: /proj/src/file%.lua", notifications[1].msg)
  end)

  it("short-circuits when path.get fails", function()
    vim.api.nvim_buf_get_name = function()
      return ""
    end

    pipeline.run(sync_strategy())

    assert.equals(0, #clipboard)
    assert.equals(1, #notifications)
    assert.equals(vim.log.levels.ERROR, notifications[1].level)
  end)

  it("short-circuits when the strategy returns an error", function()
    local errored = {
      key = "z",
      name = "Erroring",
      desc = "x",
      transform = function()
        return nil, "kaboom"
      end,
    }

    pipeline.run(errored)

    assert.equals(0, #clipboard)
    assert.equals(1, #notifications)
    assert.equals(vim.log.levels.ERROR, notifications[1].level)
    assert.matches("kaboom", notifications[1].msg)
  end)

  it("appends a range when one is supplied via opts.range", function()
    local rng = { start = 10, end_ = 20, is_visual = true }
    pipeline.run(sync_strategy(), { range = rng })

    assert.equals(1, #clipboard)
    assert.equals("/proj/src/file.lua:10-20", clipboard[1].text)
  end)

  it("appends a range detected from visual mode when opts.range is absent", function()
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

    pipeline.run(sync_strategy())

    assert.equals("/proj/src/file.lua:5-7", clipboard[1].text)
  end)

  it("honours opts.register over config.register", function()
    pipeline.run(sync_strategy(), { register = "*" })
    assert.equals("*", clipboard[1].register)
  end)

  it("honours config.register when opts.register is absent", function()
    config_mod.setup({ register = "a" })
    pipeline.run(sync_strategy())
    assert.equals("a", clipboard[1].register)
  end)

  it("routes async strategies through ctx.continue", function()
    local async = {
      key = "z",
      name = "Async",
      desc = "x",
      transform = function(absolute, ctx)
        -- Defer through vim.schedule to mirror real async strategies.
        vim.schedule(function()
          ctx.continue(absolute .. ":async", nil)
        end)
        return nil, nil
      end,
    }

    pipeline.run(async)
    vim.wait(50, function()
      return #clipboard > 0
    end)

    assert.equals(1, #clipboard)
    assert.equals("/proj/src/file.lua:async", clipboard[1].text)
  end)

  it("notifies and does not write when a strategy raises", function()
    local boom = {
      key = "z",
      name = "Boom",
      desc = "x",
      transform = function()
        error("nope")
      end,
    }

    pipeline.run(boom)

    assert.equals(0, #clipboard)
    assert.equals(1, #notifications)
    assert.equals(vim.log.levels.ERROR, notifications[1].level)
    assert.matches("strategy 'Boom' raised", notifications[1].msg)
  end)

  it("silently finishes when the strategy returns nil result with no error", function()
    local cancelled = {
      key = "z",
      name = "Cancelled",
      desc = "x",
      transform = function()
        return nil, nil
      end,
    }

    -- Sync nil/nil is interpreted by the pipeline as 'wait for ctx.continue',
    -- so an entirely sync cancellation needs to go through ctx.continue.
    local async_cancel = {
      key = "z",
      name = "AsyncCancel",
      desc = "x",
      transform = function(_absolute, ctx)
        ctx.continue(nil, nil)
        return nil, nil
      end,
    }

    pipeline.run(cancelled)
    -- Pipeline waits for continue; nothing written, nothing notified.
    assert.equals(0, #clipboard)
    assert.equals(0, #notifications)

    pipeline.run(async_cancel)
    assert.equals(0, #clipboard)
    assert.equals(0, #notifications)
  end)

  it("finalize is idempotent so a double-call from continue does not duplicate", function()
    local doubled = {
      key = "z",
      name = "Doubled",
      desc = "x",
      transform = function(absolute, ctx)
        ctx.continue(absolute, nil)
        ctx.continue(absolute, nil)
        return nil, nil
      end,
    }

    pipeline.run(doubled)

    assert.equals(1, #clipboard)
    assert.equals(1, #notifications)
  end)
end)
