local uv = vim.uv or vim.loop

local Config = require("caster.config")
local Server = require("caster.server")
local Tree = require("caster.tree")

local M = {
  config = Config.resolve(),
  server = nil,
  root = nil,
  url = nil,
  last_file = nil,
  refresh_timer = nil,
  refresh_callback = nil,
}

local function plugin_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))
end

local function read_overlay()
  local path = plugin_root() .. "/overlay/index.html"
  local file, error_message = io.open(path, "rb")
  if not file then
    error("could not read overlay at " .. path .. ": " .. tostring(error_message))
  end
  local html = file:read("*a")
  file:close()
  return html
end

local function canonical_path(path)
  local absolute = vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/$", "")
  return uv.fs_realpath(absolute) or absolute
end

local function resolve_root(override)
  local configured = override or M.config.root
  if type(configured) == "function" then
    configured = configured()
  end
  local root = canonical_path(configured or vim.fn.getcwd())
  if vim.fn.isdirectory(root) ~= 1 then
    error("caster root is not a directory: " .. root)
  end
  return root
end

local function current_file()
  local name = vim.api.nvim_buf_get_name(0)
  if name ~= "" and vim.bo.buftype == "" then
    M.last_file = canonical_path(name)
  end
  return M.last_file
end

function M.state(max_entries)
  local config = M.config
  if max_entries then
    config = vim.tbl_extend("force", {}, config, { max_entries = max_entries })
  end
  return Tree.build(M.root, current_file(), config)
end

function M.refresh()
  if not M.server then
    return
  end
  if not M.config.root then
    local next_root = resolve_root()
    if next_root ~= M.root then
      M.root = next_root
      M.last_file = nil
    end
  end
  M.server:broadcast(M.state())
end

local function install_autocommands()
  local group = vim.api.nvim_create_augroup("CasterStudioSession", { clear = true })
  M.refresh_timer = uv.new_timer()
  M.refresh_callback = vim.schedule_wrap(function()
    M.refresh()
  end)
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "DirChanged" }, {
    group = group,
    callback = function()
      M.refresh_timer:stop()
      M.refresh_timer:start(30, 0, M.refresh_callback)
    end,
    desc = "Update the Caster Studio overlay",
  })
end

function M.start(root_override)
  if M.server then
    vim.notify("Caster Studio is already running at " .. M.url)
    return M.url
  end

  M.root = resolve_root(root_override)
  M.last_file = nil
  local initial_state = M.state()
  local server = Server.new(M.config, read_overlay(), initial_state, function(max_entries)
    return M.state(max_entries)
  end)
  local ok, port_or_error = pcall(server.start, server)
  if not ok then
    error("Caster Studio: " .. tostring(port_or_error))
  end

  M.server = server
  M.url = string.format("http://%s:%d/", M.config.host, port_or_error)
  install_autocommands()
  vim.notify("Caster Studio overlay: " .. M.url)

  if M.config.open_browser and vim.ui.open then
    vim.ui.open(M.url)
  end
  return M.url
end

function M.stop()
  if not M.server then
    return
  end
  if M.refresh_timer and not M.refresh_timer:is_closing() then
    M.refresh_timer:stop()
    M.refresh_timer:close()
  end
  M.refresh_timer = nil
  M.refresh_callback = nil
  M.server:stop()
  M.server = nil
  M.root = nil
  M.url = nil
  M.last_file = nil
  pcall(vim.api.nvim_del_augroup_by_name, "CasterStudioSession")
  vim.notify("Caster Studio stopped")
end

function M.setup(opts)
  M.config = Config.resolve(opts)
  return M
end

return M
