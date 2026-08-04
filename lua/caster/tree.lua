local uv = vim.uv or vim.loop

local M = {}

local function normalize(path)
  return vim.fs.normalize(path):gsub("/$", "")
end

local function relative(path, root)
  path, root = normalize(path), normalize(root)
  if path == root then
    return ""
  end
  local prefix = root .. "/"
  if path:sub(1, #prefix) ~= prefix then
    return nil
  end
  return path:sub(#prefix + 1)
end

local function is_ignored(name, config)
  if config.ignore[name] then
    return true
  end
  return not config.show_hidden and name:sub(1, 1) == "."
end

local function scan(root, config)
  local entries = {}
  local truncated_scan = false

  local function walk(directory, depth, prefix)
    if depth > config.max_depth or #entries >= config.max_scan_entries then
      truncated_scan = true
      return
    end

    local children = {}
    local handle = uv.fs_scandir(directory)
    if not handle then
      return
    end

    while true do
      local name, kind = uv.fs_scandir_next(handle)
      if not name then
        break
      end
      if not is_ignored(name, config) and (kind == "file" or kind == "directory" or kind == "link") then
        children[#children + 1] = { name = name, kind = kind }
      end
    end

    table.sort(children, function(a, b)
      local ad, bd = a.kind == "directory", b.kind == "directory"
      if ad ~= bd then
        return ad
      end
      return a.name:lower() < b.name:lower()
    end)

    for _, child in ipairs(children) do
      if #entries >= config.max_scan_entries then
        truncated_scan = true
        return
      end

      local path = prefix == "" and child.name or (prefix .. "/" .. child.name)
      entries[#entries + 1] = {
        path = path,
        name = child.name,
        depth = depth,
        kind = child.kind == "directory" and "directory" or "file",
      }
      if child.kind == "directory" then
        walk(directory .. "/" .. child.name, depth + 1, path)
      end
    end
  end

  walk(root, 0, "")
  return entries, truncated_scan
end

local function omission(count, position)
  return {
    kind = "omission",
    name = string.format("%d item%s omitted", count, count == 1 and "" or "s"),
    depth = 0,
    path = "__omission_" .. position,
  }
end

function M.build(root, current_file, config)
  root = normalize(root)
  local entries, truncated_scan = scan(root, config)
  local active_path = current_file and relative(current_file, root) or nil
  local active_index

  for index, entry in ipairs(entries) do
    entry.position = index
    if entry.kind == "file" and entry.path == active_path then
      active_index = index
    end
  end

  if active_path and active_path ~= "" and not active_index then
    local name = vim.fs.basename(active_path)
    entries[#entries + 1] = {
      path = active_path,
      name = name,
      depth = math.max(0, select(2, active_path:gsub("/", "/"))),
      kind = "file",
      position = #entries + 1,
      forced = true,
    }
    active_index = #entries
    truncated_scan = true
  end

  local total = #entries
  local limit = math.max(3, config.max_entries)
  local visible = entries

  if total > limit then
    local center = active_index or 1
    local start_index = math.max(1, center - math.floor((limit - 1) / 2))
    local end_index = math.min(total, start_index + limit - 1)
    start_index = math.max(1, end_index - limit + 1)
    local has_before = start_index > 1
    local has_after = end_index < total
    visible = {}

    if has_before then
      visible[#visible + 1] = omission(start_index, "before")
      start_index = start_index + 1
    end
    if has_after then
      end_index = end_index - 1
    end
    for index = start_index, end_index do
      visible[#visible + 1] = entries[index]
    end
    if has_after then
      visible[#visible + 1] = omission(total - end_index, "after")
    end
  end

  for _, entry in ipairs(visible) do
    entry.active = entry.kind == "file" and entry.path == active_path or false
  end

  return {
    root = root,
    root_name = vim.fs.basename(root),
    active_path = active_path,
    active_position = active_index,
    total = total,
    scan_truncated = truncated_scan,
    entries = visible,
  }
end

M.relative = relative

return M
