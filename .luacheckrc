-- Luacheck configuration for yank-path.nvim
std = luajit
cache = true

-- Global objects defined by the C code
read_globals = {
  "vim",
}

-- Global objects defined by the test framework
globals = {
  "describe",
  "it",
  "before_each",
  "after_each",
  "setup",
  "teardown",
  "pending",
  "assert",
}

-- Ignore some pedantic warnings
ignore = {
  "212/_.*",     -- unused argument, for vars with "_" prefix
  "214",         -- used variable with unused hint ("_" prefix)
  "121",         -- setting read-only global variable 'vim'
  "122",         -- setting read-only field of global variable 'vim'
  "581",         -- negation of a relational operator- operator can be flipped (not for tables)
}

-- Don't report unused self arguments of methods
self = false

-- Neovim lua API
files["tests/*"] = {
  std = "+busted"
}

-- Allow vim global in all files
files["**/*.lua"] = {
  globals = { "vim" }
}

-- Plugin files
files["lua/yank-path/*.lua"] = {
  globals = { "vim" },
}

files["lua/yank-path/strategies/*.lua"] = {
  globals = { "vim" },
}

files["lua/yank-path/picker/*.lua"] = {
  globals = { "vim" },
}

-- Test files
files["tests/*.lua"] = {
  globals = {
    "vim",
    "describe",
    "it", 
    "before_each",
    "after_each",
    "setup",
    "teardown",
    "pending",
    "assert"
  }
}
