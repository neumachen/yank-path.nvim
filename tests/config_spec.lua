-- Unit tests for lua/yank-path/config.lua.

local config_mod = require("yank-path.config")

describe("yank-path.config", function()
  local original_notify
  local notifications

  before_each(function()
    -- Reset to a known good baseline before every test so cross-spec
    -- pollution cannot mask validation failures.
    config_mod.setup()

    original_notify = vim.notify
    notifications = {}
    vim.notify = function(msg, level)
      notifications[#notifications + 1] = { msg = msg, level = level }
    end
  end)

  after_each(function()
    vim.notify = original_notify
    config_mod.setup()
  end)

  it("populates defaults when called with nil", function()
    config_mod.setup()
    assert.equals("+", config_mod.config.register)
    assert.equals("auto", config_mod.config.picker)
    assert.same({ ".git" }, config_mod.config.project.markers)
    assert.is_nil(config_mod.config.project.find_root)
    assert.is_true(config_mod.config.project.cache)
  end)

  it("populates defaults when called with an empty table", function()
    config_mod.setup({})
    assert.equals("+", config_mod.config.register)
    assert.same({ ".git" }, config_mod.config.project.markers)
    assert.is_true(config_mod.config.project.cache)
  end)

  it("deep-merges user overrides with defaults", function()
    config_mod.setup({
      project = { markers = { ".git", "Cargo.toml" } },
    })
    assert.same({ ".git", "Cargo.toml" }, config_mod.config.project.markers)
    -- Unspecified nested fields must still hold their default values.
    assert.is_true(config_mod.config.project.cache)
  end)

  it("accepts a single picker name", function()
    config_mod.setup({ picker = "fzf-lua" })
    assert.equals("fzf-lua", config_mod.config.picker)
  end)

  it("accepts an ordered picker list", function()
    config_mod.setup({ picker = { "fzf-lua", "vim.ui.select" } })
    assert.same({ "fzf-lua", "vim.ui.select" }, config_mod.config.picker)
  end)

  it("accepts a custom register", function()
    config_mod.setup({ register = "*" })
    assert.equals("*", config_mod.config.register)
  end)

  it("accepts a callable find_root", function()
    local fn = function()
      return "/r"
    end
    config_mod.setup({ project = { find_root = fn } })
    assert.equals(fn, config_mod.config.project.find_root)
  end)

  describe("validation", function()
    it("rejects non-table input", function()
      config_mod.setup("oops")
      assert.equals(1, #notifications)
      assert.equals(vim.log.levels.ERROR, notifications[1].level)
      assert.matches("setup%(%) expects a table", notifications[1].msg)
    end)

    it("rejects a non-string register", function()
      config_mod.setup({ register = 42 })
      assert.equals(1, #notifications)
      assert.matches("config.register must be a string", notifications[1].msg)
    end)

    it("rejects a picker that is neither string nor table", function()
      config_mod.setup({ picker = 42 })
      assert.equals(1, #notifications)
      assert.matches("config.picker must be a string or an array of strings", notifications[1].msg)
    end)

    it("rejects a picker list containing non-strings", function()
      config_mod.setup({ picker = { "fzf-lua", 42 } })
      assert.equals(1, #notifications)
      assert.matches("config.picker%[2%] must be a string", notifications[1].msg)
    end)

    it("rejects a non-table project", function()
      config_mod.setup({ project = "oops" })
      assert.equals(1, #notifications)
      assert.matches("config.project must be a table", notifications[1].msg)
    end)

    it("rejects non-table project.markers", function()
      config_mod.setup({ project = { markers = ".git" } })
      assert.equals(1, #notifications)
      assert.matches("config.project.markers must be an array of strings", notifications[1].msg)
    end)

    it("rejects non-string entries in project.markers", function()
      config_mod.setup({ project = { markers = { ".git", 42 } } })
      assert.equals(1, #notifications)
      assert.matches("config.project.markers%[2%] must be a string", notifications[1].msg)
    end)

    it("rejects a non-callable find_root", function()
      config_mod.setup({ project = { find_root = "not_callable" } })
      assert.equals(1, #notifications)
      assert.matches("config.project.find_root must be a function or callable", notifications[1].msg)
    end)

    it("rejects a non-boolean cache flag", function()
      config_mod.setup({ project = { cache = "yes" } })
      assert.equals(1, #notifications)
      assert.matches("config.project.cache must be a boolean", notifications[1].msg)
    end)

    it("leaves existing config untouched when validation fails", function()
      config_mod.setup({ register = "*" })
      config_mod.setup({ register = 42 })

      assert.equals("*", config_mod.config.register)
    end)
  end)
end)
