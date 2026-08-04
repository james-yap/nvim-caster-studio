local M = {}

M.defaults = {
  host = "127.0.0.1",
  port = 8765,
  root = nil,
  opacity = 0.8,
  font_size = nil,
  max_entries = 32,
  max_scan_entries = 5000,
  max_depth = 8,
  show_hidden = false,
  respect_gitignore = true,
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
  local config = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
  if type(config.opacity) ~= "number" or config.opacity < 0 or config.opacity > 1 then
    error("caster: opacity must be a number between 0 and 1")
  end
  if config.font_size ~= nil and (type(config.font_size) ~= "number" or config.font_size <= 0) then
    error("caster: font_size must be a positive number or nil")
  end
  return config
end

return M
