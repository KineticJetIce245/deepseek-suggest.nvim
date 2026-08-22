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
	if cfg.stream then
		body.stream = true
		body.stream_options = { include_usage = true }
	end
	return vim.json.encode(body)
end

--- Builds the request body for the chat prefix completion endpoint.
---@param prefix string
---@param suffix string
---@param cfg table
---@return string encoded JSON body
function M.build_chat_body(prefix, suffix, cfg)
	local user_content = "Fill in the missing code between the text before the cursor and the text after the cursor. "
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
	if cfg.stream then
		body.stream = true
		body.stream_options = { include_usage = true }
	end
	return vim.json.encode(body)
end

--- Sends a completion request to the DeepSeek API.
---@param opts { prefix: string, suffix: string, config: table }
---@param cb fun(err: string?, text: string?, status?: nil|"ok"|"no_key"|"no_balance"|"error", usage?: number)
---@return fun()|nil cancel function to abort the request
function M.complete(opts, cb)
	local cfg = opts.config
	if not cfg.api_key or cfg.api_key == "" then
		cb("no API key configured (set DEEPSEEK_API_KEY or pass `api_key`)", nil, "no_key")
		return
	end
	local endpoint = cfg.base_url .. (cfg.mode == "chat" and "/beta/chat/completions" or "/beta/completions")
	local body = cfg.mode == "chat" and M.build_chat_body(opts.prefix, opts.suffix, cfg)
		or M.build_fim_body(opts.prefix, opts.suffix, cfg)

	return M.request({
		url = endpoint,
		method = "POST",
		headers = { ["Authorization"] = "Bearer " .. cfg.api_key },
		body = body,
		timeout_ms = cfg.timeout_ms,
		streaming = cfg.stream,
		on_stream = opts.on_stream,
	}, function(err, res, http_code, meta)
		if err then
			return cb(err, nil, "error")
		end
		-- SSE path: the completion text was already delivered progressively via
		-- `opts.on_stream`; here we just hand over the full text and usage.
		if meta and meta.streamed then
			return cb(nil, meta.text or "", "ok", meta.usage)
		end
		-- Non-SSE path (one-shot responses and streaming requests that answered
		-- with a plain JSON error body, e.g. 401/402): parse the body as JSON.
		local ok, data = pcall(vim.json.decode, res)
		if not ok or type(data) ~= "table" then
			return cb("invalid JSON response from API", nil, "error")
		end
		if data.error then
			local msg = data.error.message or data.error.type or vim.inspect(data.error)
			local kind = http_code == 401 and "no_key" or http_code == 402 and "no_balance" or "error"
			return cb("API error: " .. tostring(msg), nil, kind)
		end

		local choice = data.choices and data.choices[1]
		local text
		if cfg.mode == "chat" then
			text = choice and choice.message and choice.message.content
		else
			text = choice and choice.text
		end
		if type(text) ~= "string" then
			return cb("API returned an empty completion", nil, "error")
		end
		cb(nil, text, "ok", data.usage)
	end)
end

--- Low level HTTP request via `curl` (cross platform, no external Lua deps).
--- Requires a `curl` executable in PATH (bundled with Windows 10 1803+,
--- macOS and virtually all Linux distros).
--- When `opts.streaming` is set, the response is consumed as a stream: SSE
--- `data:` payloads are parsed as they arrive and `opts.on_stream(partial_text)`
--- is invoked with the text accumulated so far. Non-SSE responses (error bodies,
--- plain JSON from mock servers) still work: they are delivered whole at the end.
---@param opts { url: string, method: string, headers: table, body: string, timeout_ms: number, streaming?: boolean, on_stream?: fun(text: string) }
---@param cb fun(err: string?, response: string?, http_code?: number)
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
	if opts.streaming then
		args[#args + 1] = "-N" -- disable output buffering so chunks stream through
	end
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
	-- append the HTTP status code after the response body so we can tell a 401
	-- (bad key) apart from a 402 (no balance)
	args[#args + 1] = "-w"
	args[#args + 1] = "\n%{http_code}"
	args[#args + 1] = opts.url

	local handle
	if not opts.streaming then
		handle = vim.system(args, { text = true, timeout = opts.timeout_ms or 30000 }, function(process)
			pcall(vim.fn.delete, tmpfile)
			M._finish(process, cb)
		end)
	else
		local buf = {}
		local total = ""
		local usage
		local saw_event = false
		local function on_stdout(err, data)
			if data == nil then
				return -- EOF
			end
			buf[#buf + 1] = data
			-- parse any complete SSE events and forward the text so far
			local streamed = table.concat(buf, "")
			local complete = streamed:match("^(.*\n\n)") or ""
			if #complete > 0 then
				buf = { streamed:sub(#complete + 1) }
				local pieces, u, seen = M._parse_sse(complete)
				if seen then
					saw_event = true
				end
				if u then
					usage = u
				end
				if #pieces > 0 then
					total = total .. pieces
					if opts.on_stream then
						opts.on_stream(total)
					end
				end
			end
		end
		handle = vim.system(args, { text = true, timeout = opts.timeout_ms or 30000, stdout = on_stdout }, function(process)
			pcall(vim.fn.delete, tmpfile)
			local pieces, u, seen = M._parse_sse(table.concat(buf, ""))
			if seen then
				saw_event = true
			end
			if u then
				usage = u
			end
			if #pieces > 0 then
				total = total .. pieces
				if opts.on_stream then
					opts.on_stream(total)
				end
			end
			local code = process.code
			if code ~= 0 then
				local detail = (process.stderr or ""):gsub("%s+$", "")
				if process.signal == "timeout" or process.signal == "kill" then
					return cb("request timed out", nil)
				elseif detail == "" then
					return cb("curl exited with code " .. tostring(code), nil)
				end
				return cb("curl exited with code " .. tostring(code) .. ": " .. detail, nil)
			end
			-- curl appended "\n<http_code>" after the body; pull it off the tail
			local tail = table.concat(buf, "")
			local _, http_code = tail:match("^(.*)\n(%d+)$")
			http_code = http_code and tonumber(http_code) or 0
			-- pass the leftover raw body (error bodies) and the streamed text along
			-- via `meta`; `streamed` is true only if an actual SSE stream was seen.
			local meta = {
				streamed = saw_event,
				text = total,
				usage = usage,
			}
			local leftover = tail:gsub("\n%d+$", "")
			cb(nil, leftover, http_code, meta)
		end)
	end

	return function()
		pcall(function()
			if handle and handle.kill then
				handle:kill()
			end
		end)
	end
end

--- Parses raw SSE text, returning the concatenated text deltas, the usage table
--- (from an `include_usage` chunk, when present) and whether any `data:` event
--- was seen at all (so an empty-but-valid stream can be told apart from a plain
--- JSON body).
---@param sse string
---@return string pieces
---@return table? usage
---@return boolean saw_event
local function parse_sse(sse)
	local pieces = {}
	local usage
	local saw_event = false
	for block in sse:gmatch("(.-)\n\n") do
		local data = block:match("^data:%s*(.*)$")
		if data then
			saw_event = true
		end
		if data and data ~= "[DONE]" then
			local ok, payload = pcall(vim.json.decode, data)
			if ok and type(payload) == "table" then
				if type(payload.usage) == "table" then
					usage = payload.usage
				end
				local choice = payload.choices and payload.choices[1]
				local piece = choice and (choice.text or (choice.delta and choice.delta.content)) or nil
				if type(piece) == "string" and #piece > 0 then
					pieces[#pieces + 1] = piece
				end
			end
		end
	end
	return table.concat(pieces), usage, saw_event
end
M._parse_sse = parse_sse

--- Builds the final result from a finished one-shot curl process and invokes the callback.
---@param process { code: integer, signal: string, stdout: string? }
---@param cb fun(err: string?, response: string?, http_code?: number)
local function finish(process, cb)
	local code = process.code
	if code ~= 0 then
		local detail = (process.stderr or ""):gsub("%s+$", "")
		if process.signal == "timeout" or process.signal == "kill" then
			return cb("request timed out", nil)
		elseif detail == "" then
			return cb("curl exited with code " .. tostring(code), nil)
		end
		return cb("curl exited with code " .. tostring(code) .. ": " .. detail, nil)
	end

	-- the response body is followed by a newline + the HTTP status code
	local resp = process.stdout or ""
	local body, http_code = resp:match("^(.*)\n(%d+)$")
	if body == nil then
		body = resp
		http_code = 0
	else
		http_code = tonumber(http_code)
	end
	return cb(nil, body, http_code)
end
M._finish = finish

return M
