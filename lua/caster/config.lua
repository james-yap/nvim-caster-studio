local M = {}

M.defaults = {
  host = "127.0.0.1",
  port = 8765,
  root = nil,
  max_entries = 48,
  max_scan_entries = 5000,
  max_depth = 8,
  show_hidden = false,
  open_browser = false,
  ignore = {
    [".git"] = true,
    [".hg"] = true,
    [".svn"] = true,
    [".DS_Store"] = true,
    ["node_modules"] = true,
    ["vendor"] = true,
    ["dist"] = true,
    ["build"] = true,
    ["target"] = true,
    [".cache"] = true,
  },
}

function M.resolve(opts)
  return vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

return M
