vim.opt.runtimepath:prepend(vim.fn.getcwd())

local Config = require("caster.config")
local Tree = require("caster.tree")

local failures = {}
local function check(condition, message)
  if not condition then
    failures[#failures + 1] = message
  end
end

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/src/deep", "p")
vim.fn.mkdir(root .. "/.git", "p")
vim.fn.mkdir(root .. "/node_modules/pkg", "p")
for index = 1, 18 do
  vim.fn.writefile({ "file " .. index }, string.format("%s/src/file-%02d.lua", root, index))
end
vim.fn.writefile({ "focused" }, root .. "/src/deep/focused.lua")
vim.fn.writefile({ "ignored" }, root .. "/.git/config")
vim.fn.writefile({ "ignored" }, root .. "/node_modules/pkg/index.js")

local config = Config.resolve({ max_entries = 8 })
check(config.opacity == 0.8, "panel opacity defaults to 0.8")
check(config.font_size == nil, "tree font size uses the responsive overlay default")
local transparent_config = Config.resolve({ opacity = 0.35 })
check(transparent_config.opacity == 0.35, "panel opacity accepts values between zero and one")
check(not pcall(Config.resolve, { opacity = 1.1 }), "panel opacity rejects values above one")
check(not pcall(Config.resolve, { opacity = "opaque" }), "panel opacity rejects non-numeric values")
local sized_config = Config.resolve({ max_entries = 8, font_size = 14 })
check(sized_config.font_size == 14, "tree font size accepts positive pixel values")
check(not pcall(Config.resolve, { font_size = 0 }), "tree font size rejects non-positive values")
check(not pcall(Config.resolve, { font_size = "large" }), "tree font size rejects non-numeric values")
local state = Tree.build(root, root .. "/src/deep/focused.lua", config)

check(state.active_path == "src/deep/focused.lua", "active path is relative to the project root")
check(state.opacity == 0.8, "tree state publishes the configured panel opacity")
local sized_state = Tree.build(root, root .. "/src/deep/focused.lua", sized_config)
check(sized_state.font_size == 14, "tree state publishes the configured font size")
check(#state.entries <= 8, "visible tree honors max_entries")
check(state.total > #state.entries, "large trees report their full scanned size")
check(vim.tbl_contains(vim.tbl_map(function(entry)
  return entry.path
end, state.entries), "src/deep/focused.lua"), "truncated tree retains the focused file")
check(not vim.tbl_contains(vim.tbl_map(function(entry)
  return entry.path
end, state.entries), ".git"), "hidden directories are ignored")

local outside = Tree.build(root, root .. "/missing/current.lua", config)
check(outside.active_path == nil, "files absent from the scanned project remain excluded")
check(Tree.relative(root .. "/src/file-01.lua", root) == "src/file-01.lua", "relative paths strip the exact root prefix")
check(Tree.relative(root .. "-other/file.lua", root) == nil, "relative paths reject sibling prefix collisions")

local breadth_root = vim.fn.tempname()
for _, directory in ipairs({ "alpha", "beta", "gamma" }) do
  vim.fn.mkdir(breadth_root .. "/" .. directory, "p")
  for index = 1, 3 do
    vim.fn.writefile({ directory }, string.format("%s/%s/file-%d.lua", breadth_root, directory, index))
  end
end
local breadth_state = Tree.build(breadth_root, nil, Config.resolve({
  max_entries = 6,
  respect_gitignore = false,
}))
local breadth_paths = {}
local pruning_rows = 0
for _, entry in ipairs(breadth_state.entries) do
  breadth_paths[entry.path] = true
  if entry.kind == "omission" then
    pruning_rows = pruning_rows + 1
  end
end
check(breadth_paths.alpha and breadth_paths.beta and breadth_paths.gamma, "breadth-first compaction represents every shallow branch")
check(pruning_rows == 3, "partially expanded branches become broot-style unlisted rows")
check(#breadth_state.entries == 6, "broot-style compaction exactly fills its row target")

local git_root = vim.fn.tempname()
vim.fn.mkdir(git_root .. "/cache", "p")
vim.fn.mkdir(git_root .. "/sub", "p")
vim.fn.mkdir(git_root .. "/empty", "p")
vim.fn.writefile({ "*.log", "cache/", "!important.log" }, git_root .. "/.gitignore")
vim.fn.writefile({ "*.tmp" }, git_root .. "/sub/.gitignore")
vim.fn.writefile({ "keep" }, git_root .. "/keep.lua")
vim.fn.writefile({ "ignored" }, git_root .. "/ignored.log")
vim.fn.writefile({ "included" }, git_root .. "/important.log")
vim.fn.writefile({ "tracked" }, git_root .. "/tracked.log")
vim.fn.writefile({ "ignored" }, git_root .. "/cache/generated.lua")
vim.fn.writefile({ "ignored" }, git_root .. "/sub/generated.tmp")
vim.fn.writefile({ "keep" }, git_root .. "/sub/keep.lua")
vim.system({ "git", "-C", git_root, "init", "-q" }):wait()
vim.system({ "git", "-C", git_root, "add", "-f", "tracked.log" }):wait()

local ignored_state = Tree.build(git_root, nil, Config.resolve({ max_entries = 32 }))
local ignored_paths = {}
for _, entry in ipairs(ignored_state.entries) do
  ignored_paths[entry.path] = true
end
check(ignored_paths["keep.lua"], "gitignore scanning retains ordinary untracked files")
check(ignored_paths["important.log"], "gitignore negation rules re-include matching files")
check(not ignored_paths["tracked.log"], "broot-style ignore patterns also hide matching tracked files")
check(ignored_paths["sub/keep.lua"], "nested non-ignored files remain visible")
check(ignored_paths.empty, "unignored empty directories remain represented")
check(not ignored_paths["ignored.log"], "root gitignore patterns exclude matching files")
check(not ignored_paths.cache, "ignored directories and their contents are excluded")
check(not ignored_paths["sub/generated.tmp"], "nested gitignore files are respected")

local unignored_state = Tree.build(git_root, nil, Config.resolve({
  max_entries = 32,
  respect_gitignore = false,
}))
local unignored_paths = {}
for _, entry in ipairs(unignored_state.entries) do
  unignored_paths[entry.path] = true
end
check(unignored_paths["ignored.log"], "gitignore filtering can be disabled explicitly")

local Caster = require("caster")
Caster.setup({ max_entries = 8 })
Caster.root = (vim.uv or vim.loop).fs_realpath(root)
Caster.last_file = nil
vim.cmd.edit(vim.fn.fnameescape(root .. "/src/file-01.lua"))
local normal_state = Caster.state()
check(normal_state.active_path == "src/file-01.lua", "normal file buffers become the active overlay file")
local expanded_state = Caster.state(12)
check(#expanded_state.entries > #normal_state.entries, "viewport row overrides loosen tree compaction")

local transient_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(transient_buffer)
local transient_state = Caster.state()
check(transient_state.active_path == "src/file-01.lua", "transient buffers retain the last normal file focus")

vim.cmd.edit(vim.fn.fnameescape(root .. "/src/file-02.lua"))
local selected_state = Caster.state()
check(selected_state.active_path == "src/file-02.lua", "the next selected normal file replaces retained focus")
vim.cmd.enew({ bang = true })

vim.fn.delete(root, "rf")
vim.fn.delete(breadth_root, "rf")
vim.fn.delete(git_root, "rf")

if #failures > 0 then
  error("Caster Studio tests failed:\n- " .. table.concat(failures, "\n- "))
end

print("Caster Studio tree contracts passed")
