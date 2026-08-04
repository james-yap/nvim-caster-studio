local uv = vim.uv or vim.loop

local Server = {}
Server.__index = Server

local function response(status, content_type, body, extra)
  local headers = {
    "HTTP/1.1 " .. status,
    "Content-Type: " .. content_type,
    "Content-Length: " .. #body,
    "Cache-Control: no-store",
    "Access-Control-Allow-Origin: *",
    "Connection: close",
  }
  for _, header in ipairs(extra or {}) do
    headers[#headers + 1] = header
  end
  return table.concat(headers, "\r\n") .. "\r\n\r\n" .. body
end

local function close_socket(socket)
  if socket and not socket:is_closing() then
    socket:shutdown(function()
      if not socket:is_closing() then
        socket:close()
      end
    end)
  end
end

function Server.new(config, html, initial_state, state_provider)
  return setmetatable({
    config = config,
    html = html,
    state = initial_state,
    state_provider = state_provider,
    tcp = nil,
    clients = {},
  }, Server)
end

function Server:_remove_client(socket)
  self.clients[socket] = nil
  if socket and not socket:is_closing() then
    socket:close()
  end
end

function Server:_send_event(socket)
  local max_entries = self.clients[socket]
  local state = max_entries and self.state_provider and self.state_provider(max_entries) or self.state
  local payload = "data: " .. vim.json.encode(state) .. "\n\n"
  socket:write(payload, function(error)
    if error then
      self:_remove_client(socket)
    end
  end)
end

function Server:broadcast(state)
  self.state = state
  for socket in pairs(self.clients) do
    self:_send_event(socket)
  end
end

function Server:_handle(socket, request)
  local method, target = request:match("^(%u+)%s+([^%s]+)")
  if method ~= "GET" then
    socket:write(response("405 Method Not Allowed", "text/plain; charset=utf-8", "Method not allowed"), function()
      close_socket(socket)
    end)
    return
  end

  local requested_entries = tonumber((target or ""):match("[?&]max_entries=(%d+)"))
  if requested_entries then
    requested_entries = math.max(3, math.min(requested_entries, self.config.max_scan_entries))
  end
  target = (target or "/"):match("^[^?]+")
  if target == "/events" then
    self.clients[socket] = requested_entries or false
    socket:write(table.concat({
      "HTTP/1.1 200 OK",
      "Content-Type: text/event-stream",
      "Cache-Control: no-cache",
      "Access-Control-Allow-Origin: *",
      "Connection: keep-alive",
      "X-Accel-Buffering: no",
      "\r\n",
    }, "\r\n"), function(error)
      if error then
        self:_remove_client(socket)
      else
        vim.schedule(function()
          if not socket:is_closing() then
            self:_send_event(socket)
          end
        end)
      end
    end)
    return
  end

  local body, content_type, status
  if target == "/" or target == "/index.html" then
    body, content_type, status = self.html, "text/html; charset=utf-8", "200 OK"
  elseif target == "/state" then
    body, content_type, status = vim.json.encode(self.state), "application/json; charset=utf-8", "200 OK"
  elseif target == "/health" then
    body, content_type, status = '{"ok":true}', "application/json; charset=utf-8", "200 OK"
  else
    body, content_type, status = "Not found", "text/plain; charset=utf-8", "404 Not Found"
  end

  socket:write(response(status, content_type, body), function()
    close_socket(socket)
  end)
end

function Server:start()
  local tcp = uv.new_tcp()
  local ok, bind_error = tcp:bind(self.config.host, self.config.port)
  if not ok then
    tcp:close()
    error(string.format("could not bind %s:%d: %s", self.config.host, self.config.port, bind_error))
  end

  local listen_ok, listen_error = tcp:listen(32, function(error)
    if error then
      vim.schedule(function()
        vim.notify("Caster server error: " .. error, vim.log.levels.ERROR)
      end)
      return
    end

    local socket = uv.new_tcp()
    tcp:accept(socket)
    local chunks = {}
    socket:read_start(function(read_error, chunk)
      if read_error then
        self:_remove_client(socket)
        return
      end
      if not chunk then
        if not self.clients[socket] then
          self:_remove_client(socket)
        end
        return
      end

      chunks[#chunks + 1] = chunk
      local request = table.concat(chunks)
      if request:find("\r\n\r\n", 1, true) then
        socket:read_stop()
        vim.schedule(function()
          if not socket:is_closing() then
            self:_handle(socket, request)
          end
        end)
      end
    end)
  end)

  if not listen_ok then
    tcp:close()
    error(string.format("could not listen on %s:%d: %s", self.config.host, self.config.port, listen_error))
  end

  self.tcp = tcp
  local address = tcp:getsockname()
  self.port = address and address.port or self.config.port
  return self.port
end

function Server:stop()
  for socket in pairs(self.clients) do
    self:_remove_client(socket)
  end
  self.clients = {}
  if self.tcp and not self.tcp:is_closing() then
    self.tcp:close()
  end
  self.tcp = nil
end

return Server
