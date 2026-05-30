-- Unit tests for lua/yank-path/util.lua.
--
-- Covers the notification helpers, the is_callable predicate, and the
-- project root resolver with its per-directory cache. Each test restores
-- any monkey-patched vim API in after_each so cross-spec leakage cannot
-- create false positives.

local util = require("yank-path.util")

describe("yank-path.util", function()
  local original_notify

  before_each(function()
    original_notify = vim.notify
  end)

  after_each(function()
    vim.notify = original_notify
    util.clear_all_root_cache()
  end)

  describe("notify helpers", function()
    it("notify_info prefixes the message and uses INFO level", function()
      local captured
      vim.notify = function(msg, level)
        captured = { msg = msg, level = level }
      end

      util.notify_info("hello")

      assert.equals("[yank-path] hello", captured.msg)
      assert.equals(vim.log.levels.INFO, captured.level)
    end)

    it("notify_warn uses WARN level", function()
      local captured
      vim.notify = function(msg, level)
        captured = { msg = msg, level = level }
      end

      util.notify_warn("careful")

      assert.equals("[yank-path] careful", captured.msg)
      assert.equals(vim.log.levels.WARN, captured.level)
    end)

    it("notify_err uses ERROR level", function()
      local captured
      vim.notify = function(msg, level)
        captured = { msg = msg, level = level }
      end

      util.notify_err("boom")

      assert.equals("[yank-path] boom", captured.msg)
      assert.equals(vim.log.levels.ERROR, captured.level)
    end)
  end)

  describe("is_callable", function()
    it("returns true for plain functions", function()
      assert.is_true(util.is_callable(function() end))
    end)

    it("returns true for tables with __call metatable", function()
      local t = setmetatable({}, { __call = function() end })
      assert.is_true(util.is_callable(t))
    end)

    it("returns false for plain tables", function()
      assert.is_false(util.is_callable({}))
    end)

    it("returns false for strings, numbers, nil and booleans", function()
      assert.is_false(util.is_callable("fn"))
      assert.is_false(util.is_callable(42))
      assert.is_false(util.is_callable(nil))
      assert.is_false(util.is_callable(true))
    end)
  end)

  describe("find_project_root", function()
    local original_buf_get_name
    local original_dirname
    local original_find

    before_each(function()
      original_buf_get_name = vim.api.nvim_buf_get_name
      original_dirname = vim.fs.dirname
      original_find = vim.fs.find
    end)

    after_each(function()
      vim.api.nvim_buf_get_name = original_buf_get_name
      vim.fs.dirname = original_dirname
      vim.fs.find = original_find
    end)

    it("delegates to user-supplied find_root when callable", function()
      local called_with
      local user_root = function(bufnr)
        called_with = bufnr
        return "/custom/root"
      end

      local root = util.find_project_root(7, {
        markers = { ".git" },
        find_root = user_root,
        cache = true,
      })

      assert.equals("/custom/root", root)
      assert.equals(7, called_with)
    end)

    it("does not cache results from a user-supplied find_root", function()
      local calls = 0
      local user_root = function()
        calls = calls + 1
        return "/some/root"
      end

      util.find_project_root(1, { markers = { ".git" }, find_root = user_root, cache = true })
      util.find_project_root(1, { markers = { ".git" }, find_root = user_root, cache = true })

      assert.equals(2, calls)
    end)

    it("returns nil when the buffer has no name", function()
      vim.api.nvim_buf_get_name = function()
        return ""
      end

      local root = util.find_project_root(0, { markers = { ".git" }, cache = true })
      assert.is_nil(root)
    end)

    it("walks up looking for the configured markers via vim.fs.find", function()
      vim.api.nvim_buf_get_name = function()
        return "/proj/sub/file.lua"
      end
      vim.fs.dirname = function(path)
        if path == "/proj/sub/file.lua" then
          return "/proj/sub"
        elseif path == "/proj/.git" then
          return "/proj"
        end
        return original_dirname(path)
      end
      vim.fs.find = function(markers, opts)
        assert.same({ ".git" }, markers)
        assert.is_true(opts.upward)
        assert.equals("/proj/sub", opts.path)
        return { "/proj/.git" }
      end

      local root = util.find_project_root(0, { markers = { ".git" }, cache = true })
      assert.equals("/proj", root)
    end)

    it("returns nil and caches the negative result when no marker is found", function()
      vim.api.nvim_buf_get_name = function()
        return "/lonely/file.lua"
      end
      vim.fs.dirname = function(path)
        if path == "/lonely/file.lua" then
          return "/lonely"
        end
        return original_dirname(path)
      end
      local calls = 0
      vim.fs.find = function()
        calls = calls + 1
        return {}
      end

      local root1 = util.find_project_root(0, { markers = { ".git" }, cache = true })
      local root2 = util.find_project_root(0, { markers = { ".git" }, cache = true })

      assert.is_nil(root1)
      assert.is_nil(root2)
      assert.equals(1, calls)
    end)

    it("hits the cache on a second lookup with the same directory", function()
      vim.api.nvim_buf_get_name = function()
        return "/proj/sub/file.lua"
      end
      vim.fs.dirname = function(path)
        if path == "/proj/sub/file.lua" then
          return "/proj/sub"
        elseif path == "/proj/.git" then
          return "/proj"
        end
        return original_dirname(path)
      end
      local calls = 0
      vim.fs.find = function()
        calls = calls + 1
        return { "/proj/.git" }
      end

      local r1 = util.find_project_root(0, { markers = { ".git" }, cache = true })
      local r2 = util.find_project_root(0, { markers = { ".git" }, cache = true })

      assert.equals("/proj", r1)
      assert.equals("/proj", r2)
      assert.equals(1, calls)
    end)

    it("bypasses the cache when project.cache is false", function()
      vim.api.nvim_buf_get_name = function()
        return "/proj/sub/file.lua"
      end
      vim.fs.dirname = function(path)
        if path == "/proj/sub/file.lua" then
          return "/proj/sub"
        elseif path == "/proj/.git" then
          return "/proj"
        end
        return original_dirname(path)
      end
      local calls = 0
      vim.fs.find = function()
        calls = calls + 1
        return { "/proj/.git" }
      end

      util.find_project_root(0, { markers = { ".git" }, cache = false })
      util.find_project_root(0, { markers = { ".git" }, cache = false })

      assert.equals(2, calls)
    end)
  end)

  describe("clear_root_cache / clear_all_root_cache", function()
    it("clear_root_cache evicts a single directory entry", function()
      vim.api.nvim_buf_get_name = function()
        return "/a/file.lua"
      end
      local original_dirname = vim.fs.dirname
      vim.fs.dirname = function(path)
        if path == "/a/file.lua" then
          return "/a"
        end
        return original_dirname(path)
      end
      vim.fs.find = function()
        return { "/a/.git" }
      end

      util.find_project_root(0, { markers = { ".git" }, cache = true })
      assert.is_not_nil(util._root_cache()["/a"])

      util.clear_root_cache("/a")
      assert.is_nil(util._root_cache()["/a"])
    end)

    it("clear_all_root_cache evicts every entry", function()
      vim.api.nvim_buf_get_name = function()
        return "/x/file.lua"
      end
      vim.fs.dirname = function(path)
        if path == "/x/file.lua" then
          return "/x"
        end
        return "/"
      end
      vim.fs.find = function()
        return { "/x/.git" }
      end

      util.find_project_root(0, { markers = { ".git" }, cache = true })

      util.clear_all_root_cache()
      assert.same({}, util._root_cache())
    end)
  end)
end)
