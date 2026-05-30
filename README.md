# yank-path.nvim

[![CI](https://github.com/neumachen/yank-path.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/neumachen/yank-path.nvim/actions/workflows/ci.yml)

A small, single-command Neovim plugin for yanking the current buffer's path
into a register through a picker-driven menu. Path transformations are
pluggable strategies; the picker auto-detects `fzf-lua`, `snacks.nvim`, and
`vim.ui.select` and uses whichever is available.

## Features

- One user command (`:YankPath`) that works in normal and visual mode
- Four built-in path strategies selected via single-letter shortcut:
  - `f` filename
  - `a` absolute path
  - `r` relative N levels up (interactive prompt for N)
  - `p` project-root relative (auto-detects `.git`, configurable markers)
- Visual-mode range is automatically appended (`path:start-end` or `path:line`)
- Backend-agnostic picker: `fzf-lua` → `snacks.nvim` → `vim.ui.select`
- Configurable destination register (defaults to the system clipboard `+`)
- Runtime strategy registration API for custom transformations
- Lazy, per-directory cached project-root lookup with user-overridable resolver
- No default keymaps — bind whatever you prefer

## Requirements

- Neovim ≥ 0.11 (the project CI matrix tests on 0.11, 0.12, and nightly)
- Optional: [`fzf-lua`](https://github.com/ibhagwan/fzf-lua) and/or
  [`snacks.nvim`](https://github.com/folke/snacks.nvim) for a richer picker UX

## Installation

### lazy.nvim

```lua
{
  "neumachen/yank-path.nvim",
  cmd = "YankPath",
  opts = {},
}
```

With overrides:

```lua
{
  "neumachen/yank-path.nvim",
  cmd = "YankPath",
  opts = {
    register = "+",
    picker = "auto",
    project = {
      markers = { ".git", "Cargo.toml", "go.mod" },
    },
  },
}
```

### packer.nvim

```lua
use({
  "neumachen/yank-path.nvim",
  config = function()
    require("yank-path").setup()
  end,
})
```

### vim-plug

```vim
Plug 'neumachen/yank-path.nvim'

lua << EOF
require("yank-path").setup()
EOF
```

## Usage

Open any file buffer and run:

```vim
:YankPath
```

A picker appears with the registered strategies. Pick one and the result is
written to the configured register (default `+`).

In visual mode, the current selection's line range is appended to the result
automatically:

```
foo/bar.lua:42        " single-line visual selection
foo/bar.lua:10-25     " multi-line visual selection
```

### Built-in strategies

| Key | Name       | Example output                       |
| --- | ---------- | ------------------------------------ |
| `f` | Filename   | `bar.lua`                            |
| `a` | Absolute   | `/home/user/proj/src/bar.lua`        |
| `r` | Relative   | `src/bar.lua` (prompts for N levels) |
| `p` | Project    | `src/bar.lua` (relative to git root) |

For `r`, the plugin prompts `Levels up:` and accepts a non-negative integer.
The result keeps the last `N + 1` path segments — so `N = 0` returns just the
filename and `N = 2` returns the file plus its two parent directories.

### Skipping the picker

Bind keymaps to specific strategies via the programmatic API:

```lua
vim.keymap.set({ "n", "x" }, "<leader>ya", function()
  require("yank-path").yank_with("absolute")
end, { desc = "Yank absolute path" })

vim.keymap.set({ "n", "x" }, "<leader>yp", function()
  require("yank-path").yank_with("project")
end, { desc = "Yank project-relative path" })
```

`yank_with` accepts either the key (`"a"`) or the display name
(`"absolute"`, case-insensitive). It also accepts a per-call register
override:

```lua
require("yank-path").yank_with("absolute", { register = "*" })
```

## Configuration

```lua
require("yank-path").setup({
  -- Destination register. Anything vim.fn.setreg accepts.
  register = "+",

  -- Picker backend selection.
  --   "auto"                                  -- default priority
  --   "fzf-lua" | "snacks" | "vim.ui.select"  -- force a single backend
  --   { "fzf-lua", "vim.ui.select" }          -- ordered fallback list
  --
  -- Default priority for "auto": fzf-lua -> snacks -> vim.ui.select.
  picker = "auto",

  project = {
    -- Filenames or directory names that mark a project root.
    markers = { ".git" },

    -- Optional custom resolver. If set, this function fully owns root
    -- lookup; markers and the built-in cache are bypassed.
    --
    --   find_root = function(bufnr)
    --     return vim.fs.root(bufnr, { ".git", "Cargo.toml" })
    --   end,
    find_root = nil,

    -- Cache root lookups per buffer directory. Invalidated on BufFilePost.
    cache = true,
  },
})
```

All values are optional; calling `setup()` with no arguments uses the
defaults shown above.

## Registering custom strategies

```lua
require("yank-path").register_strategy({
  key = "u",                                    -- single alphanumeric character
  name = "Upper",
  desc = "Upper-case the absolute path",
  transform = function(absolute, ctx)
    return absolute:upper(), nil                -- (result, err)
  end,
})
```

Strategies are pure functions of the absolute path and a context table.
Return `(result, nil)` to write `result` to the register, `(nil, err)` to
surface an error notification, or `(nil, nil)` to indicate the strategy is
asynchronous (it must then call `ctx.continue(result, err)` itself; see
`lua/yank-path/strategies/relative.lua` for an example).

The `ctx` table contains:

| Field      | Description                                          |
| ---------- | ---------------------------------------------------- |
| `bufnr`    | Source buffer number                                 |
| `absolute` | Absolute path of the buffer                          |
| `range`    | Visual range table or `nil` when not in visual mode  |
| `config`   | Live plugin config                                   |
| `continue` | Async completion callback `(result, err)`            |

A planned future built-in is a remote-URL strategy that builds a permalink
(e.g. GitHub blob URL) for the current buffer's branch. It is not shipped
in the current version; the registration API is designed to support adding
it without changing the core.

## Architecture

The plugin composes a strict linear pipeline:

```
path.get(bufnr)
  -> transform(absolute, ctx)
  -> append_range_if_visual(result, range)
  -> register.write(result, register)
```

Each step is a single-responsibility module under `lua/yank-path/`:

| File                          | Responsibility                                   |
| ----------------------------- | ------------------------------------------------ |
| `init.lua`                    | Public API and built-in registration             |
| `config.lua`                  | Config schema, defaults, validation              |
| `pipeline.lua`                | Linear pipeline composition                      |
| `path.lua`                    | Buffer → absolute path                           |
| `range.lua`                   | Visual mode detection and range append           |
| `register.lua`                | Register write                                   |
| `util.lua`                    | Notifications, callable check, root cache        |
| `strategies/init.lua`         | Strategy registry                                |
| `strategies/{f,a,r,p}.lua`    | Built-in strategies                              |
| `picker/init.lua`             | Backend resolver                                 |
| `picker/{ui_select,fzf_lua,snacks}.lua` | Backend adapters                       |

The picker adapter interface is `is_available()` + `select(items, on_choice)`.
Adding a new backend is a single file under `lua/yank-path/picker/`.

## Development

```bash
make test          # run the plenary spec suite
make lint          # luacheck
make format        # stylua --in-place
make format-check  # stylua --check
make check         # lint + format-check + test
```

Tests live under `tests/`, one spec file per module plus
`tests/integration_spec.lua` for end-to-end flows. Tests must pass on the
full CI matrix (Neovim 0.11, 0.12, nightly).

## Security

Reporting policy: [`SECURITY.md`](./SECURITY.md). Disclose privately via
GitHub Security Advisories.

## License

MIT. See [`LICENSE`](./LICENSE).
