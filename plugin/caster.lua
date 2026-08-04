if vim.g.loaded_caster_studio then
  return
end
vim.g.loaded_caster_studio = true

vim.api.nvim_create_user_command("CasterStart", function(command)
  local root = command.args ~= "" and command.args or nil
  require("caster").start(root)
end, {
  nargs = "?",
  complete = "dir",
  desc = "Start the Caster Studio OBS overlay",
})

vim.api.nvim_create_user_command("CasterStop", function()
  require("caster").stop()
end, {
  desc = "Stop the Caster Studio OBS overlay",
})

vim.api.nvim_create_user_command("CasterRefresh", function()
  require("caster").refresh()
end, {
  desc = "Refresh the Caster Studio file tree",
})

vim.api.nvim_create_user_command("CasterUrl", function()
  local caster = require("caster")
  if caster.url then
    vim.notify(caster.url)
  else
    vim.notify("Caster Studio is not running", vim.log.levels.WARN)
  end
end, {
  desc = "Show the Caster Studio browser source URL",
})
