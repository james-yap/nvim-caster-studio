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
local state = Tree.build(root, root .. "/src/deep/focused.lua", config)

check(state.active_path == "src/deep/focused.lua", "active path is relative to the project root")
check(#state.entries <= 8, "visible tree honors max_entries")
check(state.total > #state.entries, "large trees report their full scanned size")
check(vim.tbl_contains(vim.tbl_map(function(entry)
  return entry.path
end, state.entries), "src/deep/focused.lua"), "truncated tree retains the focused file")
check(not vim.tbl_contains(vim.tbl_map(function(entry)
  return entry.path
end, state.entries), ".git"), "hidden directories are ignored")

local outside = Tree.build(root, root .. "/missing/current.lua", config)
local forced
for _, entry in ipairs(outside.entries) do
  if entry.active then
    forced = entry
  end
end
check(forced and forced.path == "missing/current.lua" and forced.forced, "focused files excluded from the scan are forced into view")
check(Tree.relative(root .. "/src/file-01.lua", root) == "src/file-01.lua", "relative paths strip the exact root prefix")
check(Tree.relative(root .. "-other/file.lua", root) == nil, "relative paths reject sibling prefix collisions")

vim.fn.delete(root, "rf")

if #failures > 0 then
  error("Caster Studio tests failed:\n- " .. table.concat(failures, "\n- "))
end

print("Caster Studio tree contracts passed")
