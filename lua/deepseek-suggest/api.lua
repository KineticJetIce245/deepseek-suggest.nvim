local M = {}

--- Builds the request body for the FIM completion endpoint.
---@param prefix string
---@param suffix string
---@param cfg table
---@return string encoded JSON body
function M.build_fim_body(prefix, suffix, cfg)
  local body = {
    model = cfg.model,
    prompt = prefix,
    max_tokens = cfg.max_tokens,
    temperature = cfg.temperature,
  }
  if suffix ~= nil and #suffix > 0 then
    body.suffix = suffix
  end
  if cfg.stop then
    body.stop = cfg.stop
  end
  return vim.json.encode(body)
end

--- Builds the request body for the chat prefix completion endpoint.
---@param prefix string
---@param suffix string
---@param cfg table
---@return string encoded JSON body
function M.build_chat_body(prefix, suffix, cfg)
  local user_content =
    "Fill in the missing code between the text before the cursor and the text after the cursor. "
    .. "Return only the code that goes in the middle, with no explanation, no fences and no code block markers."
  if suffix ~= nil and #suffix > 0 then
    user_content = user_content .. "\n\nCode after the cursor (suffix):\n```\n" .. suffix .. "\n```"
  end

  local body = {
    model = cfg.model,
    messages = {
      { role = "user", content = user_content },
      { role = "assistant", content = prefix, prefix = true },
    },
    max_tokens = cfg.max_tokens,
    temperature = cfg.temperature,
  }
  if cfg.stop then
    body.stop = cfg.stop
  end
  return vim.json.encode(body)
end

--- Sends a completion request to the DeepSeek API.
---@param opts { prefix: string, suffix: string, config: table }
---@param cb fun(err: string?, text: string?)
---@return fun()|nil cancel function to abort the request
function M.complete(opts, cb)
  local cfg = opts.config
  if not cfg.api_key or cfg.api_key == "" then
    cb("no API key configured (set DEEPSEEK_API_KEY or pass `api_key`)", nil)
    return
  end
  local endpoint = cfg.base_url .. (cfg.mode == "chat" and "/beta/chat/completions" or "/beta/completions")
  local body = cfg.mode == "chat"
      and M.build_chat_body(opts.prefix, opts.suffix, cfg)
    or M.build_fim_body(opts.prefix, opts.suffix, cfg)

  return M.request({
    url = endpoint,
    method = "POST",
    headers = { ["Authorization"] = "Bearer " .. cfg.api_key },
    body = body,
    timeout_ms = cfg.timeout_ms,
  }, function(err, res)
    if err then
      return cb(err, nil)
    end
    local ok, data = pcall(vim.json.decode, res)
    if not ok or type(data) ~= "table" then
      return cb("invalid JSON response from API", nil)
    end
    if data.error then
      local msg = data.error.message or data.error.type or vim.inspect(data.error)
      return cb("API error: " .. tostring(msg), nil)
    end

    local choice = data.choices and data.choices[1]
    local text
    if cfg.mode == "chat" then
      text = choice and choice.message and choice.message.content
    else
      text = choice and choice.text
    end
    if type(text) ~= "string" then
      return cb("API returned an empty completion", nil)
    end
    cb(nil, text)
  end)
end

--- Low level HTTP request via `curl` (cross platform, no external Lua deps).
--- Requires a `curl` executable in PATH (bundled with Windows 10 1803+,
--- macOS and virtually all Linux distros).
---@param opts { url: string, method: string, headers: table, body: string, timeout_ms: number }
---@param cb fun(err: string?, response: string?)
---@return fun()|nil cancel function to abort the request
function M.request(opts, cb)
  if vim.fn.executable("curl") == 0 then
    cb("`curl` executable not found on this system", nil)
    return
  end
  if not opts.body then
    cb("no request body", nil)
    return
  end

  -- write the body to a temp file to avoid any argument escaping issues
  -- (`os.tmpname` is safe in fast event contexts, unlike `vim.fn.tempname`)
  local tmpfile = os.tmpname() .. ".json"
  local f = io.open(tmpfile, "w")
  if not f then
    cb("could not create temp file for request", nil)
    return
  end
  f:write(opts.body)
  f:close()

  local args = { "curl", "-sS", "--max-time", tostring(math.max(1, math.floor((opts.timeout_ms or 30000) / 1000))) }
  args[#args + 1] = "-X"
  args[#args + 1] = opts.method or "POST"
  args[#args + 1] = "-H"
  args[#args + 1] = "Content-Type: application/json"
  for k, v in pairs(opts.headers or {}) do
    args[#args + 1] = "-H"
    args[#args + 1] = k .. ": " .. v
  end
  args[#args + 1] = "--data-binary"
  args[#args + 1] = "@" .. tmpfile
  args[#args + 1] = opts.url

  local handle = vim.system(args, { text = true, timeout = opts.timeout_ms or 30000 }, function(process)
    pcall(vim.fn.delete, tmpfile)
    local code = process.code
    if code ~= 0 then
      local detail = (process.stderr or ""):gsub("%s+$", "")
      if process.signal == "timeout" or process.signal == "kill" then
        cb("request timed out", nil)
      elseif detail == "" then
        cb("curl exited with code " .. tostring(code), nil)
      else
        cb("curl exited with code " .. tostring(code) .. ": " .. detail, nil)
      end
      return
    end
    cb(nil, process.stdout or "")
  end)

  return function()
    pcall(function()
      if handle and handle.kill then
        handle:kill()
      end
    end)
  end
end

return M
