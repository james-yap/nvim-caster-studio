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

local function new_model()
  local root = { path = "", name = "", depth = -1, kind = "directory", children = {} }
  return root, { [""] = root }, 0
end

local function sorted_children(node)
  table.sort(node.children, function(a, b)
    local ad, bd = a.kind == "directory", b.kind == "directory"
    if ad ~= bd then
      return ad
    end
    return a.name:lower() < b.name:lower()
  end)
end

local function git_ignored(root, paths)
  if not vim.system then
    return nil
  end
  local input = table.concat(paths, "\0") .. "\0"
  local ok, result = pcall(function()
    return vim.system({
      "git",
      "-C",
      root,
      "check-ignore",
      "--no-index",
      "--stdin",
      "-z",
    }, { stdin = input, text = false }):wait(10000)
  end)
  if not ok or not result or (result.code ~= 0 and result.code ~= 1) then
    return nil
  end

  local ignored = {}
  for path in (result.stdout or ""):gmatch("([^%z]+)") do
    ignored[path:gsub("^%./", "")] = true
  end
  return ignored
end

local function scan_git(root, config)
  if not config.respect_gitignore then
    return nil
  end

  local model_root, nodes, count = new_model()
  local truncated = false
  local parents = { { directory = root, node = model_root } }
  local depth = 0

  while #parents > 0 and depth <= config.max_depth do
    local candidates = {}
    for _, parent in ipairs(parents) do
      local handle = uv.fs_scandir(parent.directory)
      if handle then
        while true do
          local name, kind = uv.fs_scandir_next(handle)
          if not name then
            break
          end
          if not is_ignored(name, config) and (kind == "file" or kind == "directory" or kind == "link") then
            local path = parent.node.path == "" and name or (parent.node.path .. "/" .. name)
            candidates[#candidates + 1] = {
              name = name,
              kind = kind,
              path = path,
              directory = parent.directory .. "/" .. name,
              parent = parent.node,
            }
          end
        end
      end
    end
    if #candidates == 0 then
      break
    end

    local paths = {}
    for index, candidate in ipairs(candidates) do
      paths[index] = candidate.path
    end
    local ignored = git_ignored(root, paths)
    if not ignored then
      return nil
    end

    table.sort(candidates, function(a, b)
      if a.parent.path ~= b.parent.path then
        return a.parent.path < b.parent.path
      end
      local ad, bd = a.kind == "directory", b.kind == "directory"
      if ad ~= bd then
        return ad
      end
      return a.name:lower() < b.name:lower()
    end)

    local next_parents = {}
    for _, candidate in ipairs(candidates) do
      if not ignored[candidate.path] then
        if count >= config.max_scan_entries then
          truncated = true
          break
        end
        local node = {
          path = candidate.path,
          name = candidate.name,
          depth = depth,
          kind = candidate.kind == "directory" and "directory" or "file",
          children = {},
          parent = candidate.parent,
        }
        nodes[node.path] = node
        candidate.parent.children[#candidate.parent.children + 1] = node
        count = count + 1
        if candidate.kind == "directory" then
          next_parents[#next_parents + 1] = {
            directory = candidate.directory,
            node = node,
          }
        end
      end
    end
    if truncated then
      break
    end
    parents = next_parents
    depth = depth + 1
  end
  if #parents > 0 and depth > config.max_depth then
    truncated = true
  end
  return model_root, nodes, count, truncated
end

local function scan_filesystem(root, config)
  local model_root, nodes, count = new_model()
  local truncated = false

  local function walk(directory, parent, depth)
    if depth > config.max_depth or count >= config.max_scan_entries then
      truncated = true
      return
    end
    local handle = uv.fs_scandir(directory)
    if not handle then
      return
    end

    local children = {}
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
      if count >= config.max_scan_entries then
        truncated = true
        return
      end
      local path = parent.path == "" and child.name or (parent.path .. "/" .. child.name)
      local node = {
        path = path,
        name = child.name,
        depth = depth,
        kind = child.kind == "directory" and "directory" or "file",
        children = {},
        parent = parent,
      }
      nodes[path] = node
      parent.children[#parent.children + 1] = node
      count = count + 1
      if child.kind == "directory" then
        walk(directory .. "/" .. child.name, node, depth + 1)
      end
    end
  end

  walk(root, model_root, 0)
  return model_root, nodes, count, truncated
end

local function assign_positions(root)
  local position = 0
  local function visit(parent)
    sorted_children(parent)
    for _, child in ipairs(parent.children) do
      position = position + 1
      child.position = position
      visit(child)
    end
  end
  visit(root)
end

-- Broot fills the viewport breadth-first, rotating across every directory at a
-- depth before descending. This keeps shallow project structure represented.
local function breadth_first_selection(root, limit)
  local selected = {}
  local count = 0
  local parents = { root }

  while #parents > 0 and count < limit do
    local indices = {}
    local next_directories = {}
    for index = 1, #parents do
      indices[index] = 1
    end

    while count < limit do
      local progressed = false
      for parent_index, parent in ipairs(parents) do
        local child = parent.children[indices[parent_index]]
        if child then
          progressed = true
          indices[parent_index] = indices[parent_index] + 1
          selected[child] = true
          count = count + 1
          if child.kind == "directory" then
            next_directories[#next_directories + 1] = child
          end
          if count >= limit then
            break
          end
        end
      end
      if not progressed then
        break
      end
    end
    parents = next_directories
  end

  return selected, count
end

local function preserve_active_branch(selected, count, active_node)
  local required = {}
  local node = active_node
  while node and node.parent do
    required[node] = true
    if not selected[node] then
      selected[node] = true
      count = count + 1
    end
    node = node.parent
  end
  return required, count
end

-- Equivalent to broot's post-gather leaf trimming: parents cannot disappear
-- before their selected children, and the focused branch has the best score.
local function trim_selected(selected, required, count, limit)
  while count > limit do
    local candidate
    for node in pairs(selected) do
      if not required[node] then
        local has_selected_child = false
        for _, child in ipairs(node.children) do
          if selected[child] then
            has_selected_child = true
            break
          end
        end
        if not has_selected_child and (not candidate or node.position > candidate.position) then
          candidate = node
        end
      end
    end
    if not candidate then
      break
    end
    selected[candidate] = nil
    count = count - 1
  end
end

local function visible_entries(root, selected, required, active_path)
  local replacements = {}
  local unlisted = {}

  local function prepare(parent)
    local listed = {}
    for _, child in ipairs(parent.children) do
      if selected[child] then
        listed[#listed + 1] = child
      end
    end
    local hidden_count = #parent.children - #listed
    if hidden_count > 0 then
      local last = listed[#listed]
      local last_has_selected_children = false
      if last then
        for _, child in ipairs(last.children) do
          if selected[child] then
            last_has_selected_children = true
            break
          end
        end
      end
      if last and not last_has_selected_children and not required[last] then
        replacements[last] = hidden_count + 1
      else
        unlisted[parent] = hidden_count
      end
    end
    for _, child in ipairs(listed) do
      if not replacements[child] then
        prepare(child)
      end
    end
  end
  prepare(root)

  local entries = {}
  local function emit(parent)
    for _, child in ipairs(parent.children) do
      if selected[child] then
        local omitted = replacements[child]
        if omitted then
          entries[#entries + 1] = {
            kind = "omission",
            name = string.format("%d unlisted", omitted),
            depth = child.depth,
            path = "__omission_" .. parent.path,
          }
        else
          entries[#entries + 1] = {
            path = child.path,
            name = child.name,
            depth = child.depth,
            kind = child.kind,
            position = child.position,
            active = child.kind == "file" and child.path == active_path or false,
            unlisted = unlisted[child] or 0,
          }
          emit(child)
        end
      end
    end
  end
  emit(root)
  return entries, unlisted[root] or 0
end

function M.build(root, current_file, config)
  root = normalize(root)
  local model_root, nodes, total, truncated_scan = scan_git(root, config)
  if not model_root then
    model_root, nodes, total, truncated_scan = scan_filesystem(root, config)
  end
  assign_positions(model_root)

  local active_path = current_file and relative(current_file, root) or nil
  local active_node = active_path and nodes[active_path] or nil
  local limit = math.max(3, config.max_entries)
  local selected, selected_count = breadth_first_selection(model_root, limit)
  local required
  required, selected_count = preserve_active_branch(selected, selected_count, active_node)
  trim_selected(selected, required, selected_count, limit)
  local entries, root_unlisted = visible_entries(model_root, selected, required, active_path)

  return {
    root = root,
    root_name = vim.fs.basename(root),
    root_unlisted = root_unlisted,
    active_path = active_node and active_path or nil,
    active_position = active_node and active_node.position or nil,
    total = total,
    scan_truncated = truncated_scan,
    entries = entries,
  }
end

M.relative = relative

return M
