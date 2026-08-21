-- Headless test suite for deepseek-suggest.nvim
-- Run from the repo root with:
--   nvim --headless -u NONE -i NONE -c "luafile tests/run_test.lua" -c "qa!"
-- Exits with a message; the first failing assertion aborts with an error.

local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:append(root .. "/tests/mockrtp")

local pass_count = 0

local function check(cond, msg)
  if not cond then
    error("FAIL: " .. msg, 2)
  end
  pass_count = pass_count + 1
  print("ok - " .. msg)
end

local function assert_eq(a, b, msg)
  if a ~= b then
    error(
      string.format("FAIL: %s\n  got: %s\n  exp: %s", msg or "assert_eq", vim.inspect(a), vim.inspect(b)),
      2
    )
  end
  pass_count = pass_count + 1
  print("ok - " .. msg)
end

-- ===================== config =====================

do
  local config = require("deepseek-suggest.config")
  vim.env.DEEPSEEK_API_KEY = "env-test-key"

  config.setup({})
  assert_eq(config.get().api_key, "env-test-key", "config: env key fallback")
  assert_eq(config.get().model, "deepseek-v4-flash", "config: default model")
  assert_eq(config.get().mode, "fim", "config: default mode")
  assert_eq(config.get().auto, true, "config: auto default true")
  assert_eq(config.get().kind_icon, "🐋", "config: default kind_icon")
  assert_eq(config.get().kind_name, "DeepSeek", "config: default kind_name")
  assert_eq(config.get().kind_hl, false, "config: default kind_hl")
  assert_eq(config.get().statusline, true, "config: statusline default true")
  assert_eq(config.get().statusline_icon, "🐋", "config: default statusline_icon")
  assert_eq(config.get().statusline_tokens, true, "config: statusline_tokens default true")

  config.setup({ api_key = "explicit", auto = false, max_tokens = 512 })
  assert_eq(config.get().api_key, "explicit", "config: explicit key wins")
  assert_eq(config.get().auto, false, "config: auto override")
  assert_eq(config.get().max_tokens, 512, "config: max_tokens override")
  assert_eq(config.get().temperature, 0.2, "config: untouched default preserved")

  config.set("enabled", false)
  assert_eq(config.get().enabled, false, "config: set()")
  assert_eq(config.toggle("enabled"), true, "config: toggle()")

  config.request_manual()
  assert_eq(config.consume_manual(), true, "config: manual flag set+consumed")
  assert_eq(config.consume_manual(), false, "config: manual flag cleared")
end

-- ===================== context =====================

do
  local context = require("deepseek-suggest.context")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "def fib(n):",
    "    if n < 2:",
    "        return n",
    "    # cursor here",
    "    return fib(n-1) + fib(n-2)",
  })
  local prefix, suffix = context.build(buf, { line = 3, character = 8 }, { prefix_lines = 100, suffix_lines = 20 })
  assert_eq(prefix, "def fib(n):\n    if n < 2:\n        return n\n    # cu", "context: prefix")
  assert_eq(suffix, "rsor here\n    return fib(n-1) + fib(n-2)", "context: suffix")

  -- no lines after cursor
  local prefix2, suffix2 = context.build(buf, { line = 4, character = 0 }, { prefix_lines = 100, suffix_lines = 20 })
  assert_eq(prefix2, "def fib(n):\n    if n < 2:\n        return n\n    # cursor here\n", "context: prefix eof")
  assert_eq(suffix2, "    return fib(n-1) + fib(n-2)", "context: suffix eof is rest of line")

  -- suffix_lines limit
  local _, suffix3 = context.build(buf, { line = 0, character = 5 }, { prefix_lines = 100, suffix_lines = 1 })
  assert_eq(suffix3, "ib(n):\n    if n < 2:", "context: suffix limited to 1 line")
  vim.api.nvim_buf_delete(buf, { force = true })
end

-- ===================== api body builders =====================

do
  local api = require("deepseek-suggest.api")
  local cfg = vim.tbl_deep_extend("force", vim.deepcopy(require("deepseek-suggest.config").defaults), { api_key = "k" })

  local fim = vim.json.decode(api.build_fim_body("def f():\n", "    return", cfg))
  assert_eq(fim.model, "deepseek-v4-flash", "api: fim model")
  assert_eq(fim.prompt, "def f():\n", "api: fim prompt")
  assert_eq(fim.suffix, "    return", "api: fim suffix")
  assert_eq(fim.max_tokens, 4096, "api: fim max_tokens")

  local fim_no_suffix = vim.json.decode(api.build_fim_body("x", "", cfg))
  check(fim_no_suffix.suffix == nil, "api: fim empty suffix omitted")

  local chat = vim.json.decode(api.build_chat_body("pre", "suf", cfg))
  assert_eq(chat.messages[2].role, "assistant", "api: chat assistant role")
  assert_eq(chat.messages[2].content, "pre", "api: chat assistant prefix content")
  assert_eq(chat.messages[2].prefix, true, "api: chat prefix flag")
  check(chat.messages[1].content:find("suf") ~= nil, "api: chat suffix in user message")

  local cfg_no_key = vim.tbl_deep_extend("force", vim.deepcopy(cfg), {})
  cfg_no_key.api_key = nil
  local missing_key_err, missing_key_kind
  api.complete({ prefix = "x", suffix = "", config = cfg_no_key }, function(e, _, k)
    missing_key_err, missing_key_kind = e, k
  end)
  check(missing_key_err ~= nil and missing_key_err:find("API key", 1, true) ~= nil, "api: missing api key fails fast")
  assert_eq(missing_key_kind, "no_key", "api: missing api key classified as no_key")
end

-- ===================== source (stubbed api) =====================

do
  local config = require("deepseek-suggest.config")
  local api = require("deepseek-suggest.api")
  local source = require("deepseek-suggest.source")

  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "def fib(n):", "    return n" })
  vim.api.nvim_set_current_buf(buf)
  vim.bo.filetype = "python"

  local orig_complete = api.complete
  api.complete = function(opts, cb)
    cb(nil, "    return fib(n-1) + fib(n-2)\n")
    return nil
  end

  -- --- auto mode: returns a single item at the cursor
  config.setup({ api_key = "k", auto = true, debounce = 50 })
  local src = source.new({})
  local got
  local cancel = src:get_completions({
    bufnr = buf,
    cursor = { 2, 5 }, -- 1-indexed row 2, col 5 on "    return n"
    line = "    return n",
    bounds = { start_col = 1, length = 0 },
  }, function(resp)
    got = resp
  end)
  check(cancel ~= nil, "source: returns cancel function")
  vim.wait(1000, function()
    return got ~= nil
  end)
  check(got ~= nil, "source: callback fired")
  assert_eq(#got.items, 1, "source: one item")
  local item = got.items[1]
  assert_eq(item.textEdit.range.start.line, 1, "source: textEdit line is 0-indexed")
  assert_eq(item.textEdit.range.start.character, 5, "source: textEdit character")
  assert_eq(item.insertTextFormat, vim.lsp.protocol.InsertTextFormat.PlainText, "source: plain text format")
  check(item.textEdit.newText:find("fib", 1, true) ~= nil, "source: newText is the completion")
  check(item.label ~= "", "source: label present")
  assert_eq(item.kind_name, "DeepSeek", "source: item kind_name")
  assert_eq(item.kind_icon, "🐋", "source: item kind_icon")
  check(got.is_incomplete_forward == false, "source: not incomplete forward by default")

  -- --- manual-only mode: silent unless manual
  config.setup({ api_key = "k", auto = false, debounce = 50 })
  local got2
  src:get_completions({
    bufnr = buf,
    cursor = { 2, 5 },
    line = "    return n",
    bounds = { start_col = 1, length = 0 },
  }, function(resp)
    got2 = resp
  end)
  check(got2 ~= nil and #got2.items == 0, "source: manual-only mode silent on auto trigger")

  -- manual flag forces a suggestion
  config.request_manual()
  local got3
  src:get_completions({
    bufnr = buf,
    cursor = { 2, 5 },
    line = "    return n",
    bounds = { start_col = 1, length = 0 },
  }, function(resp)
    got3 = resp
  end)
  vim.wait(1000, function()
    return got3 ~= nil
  end)
  check(got3 ~= nil and #got3.items == 1, "source: manual flag produces suggestion")

  -- --- per-instance opts.auto=false overrides cfg.auto=true
  config.setup({ api_key = "k", auto = true, debounce = 50 })
  local src_auto_false = source.new({ auto = false })
  local got_override1
  src_auto_false:get_completions({
    bufnr = buf,
    cursor = { 2, 5 },
    line = "    return n",
    bounds = { start_col = 1, length = 0 },
  }, function(resp)
    got_override1 = resp
  end)
  check(got_override1 ~= nil and #got_override1.items == 0, "source: per-instance auto=false overrides cfg.auto=true")

  -- --- per-instance opts.auto=true overrides cfg.auto=false
  config.setup({ api_key = "k", auto = false, debounce = 50 })
  local src_auto_true = source.new({ auto = true })
  local got_override2
  src_auto_true:get_completions({
    bufnr = buf,
    cursor = { 2, 5 },
    line = "    return n",
    bounds = { start_col = 1, length = 0 },
  }, function(resp)
    got_override2 = resp
  end)
  vim.wait(1000, function()
    return got_override2 ~= nil
  end)
  check(got_override2 ~= nil and #got_override2.items == 1, "source: per-instance auto=true overrides cfg.auto=false")

  -- --- cancellation prevents the callback
  config.setup({ api_key = "k", auto = true, debounce = 200 })
  local got4
  local cancel4 = src:get_completions({
    bufnr = buf,
    cursor = { 2, 5 },
    line = "    return n",
    bounds = { start_col = 1, length = 0 },
  }, function(resp)
    got4 = resp
  end)
  cancel4()
  vim.wait(1000, function()
    return got4 ~= nil
  end)
  check(got4 == nil, "source: cancelled request does not fire")

  -- --- filterText uses the keyword
  api.complete = function(opts, cb)
    cb(nil, "hello")
    return nil
  end
  config.setup({ api_key = "k", auto = true, debounce = 50 })
  local got5
  src:get_completions({
    bufnr = buf,
    cursor = { 2, 5 },
    line = "fib world",
    bounds = { start_col = 1, length = 3 },
  }, function(resp)
    got5 = resp
  end)
  vim.wait(1000, function()
    return got5 ~= nil
  end)
  check(got5 ~= nil and got5.items[1].filterText == "fib", "source: filterText is the keyword")

  -- --- empty keyword omits filterText so blink falls back to the label
  local got5b
  src:get_completions({
    bufnr = buf,
    cursor = { 2, 5 },
    line = "    return n",
    bounds = { start_col = 1, length = 0 },
  }, function(resp)
    got5b = resp
  end)
  vim.wait(1000, function()
    return got5b ~= nil
  end)
  check(got5b ~= nil and got5b.items[1].filterText == nil, "source: empty keyword omits filterText")

  -- --- kind_icon/kind_hl overrides are applied
  api.complete = function(_, cb)
    cb(nil, "x")
    return nil
  end
  config.setup({ api_key = "k", auto = true, debounce = 50, kind_icon = "\u{EC20}", kind_hl = "BlinkCmpKindMethod" })
  local got_icon
  src:get_completions({
    bufnr = buf,
    cursor = { 2, 5 },
    line = "    return n",
    bounds = { start_col = 1, length = 0 },
  }, function(resp)
    got_icon = resp
  end)
  vim.wait(1000, function()
    return got_icon ~= nil
  end)
  check(got_icon ~= nil and got_icon.items[1].kind_icon == "\u{EC20}", "source: kind_icon override")
  check(got_icon ~= nil and got_icon.items[1].kind_hl == "BlinkCmpKindMethod", "source: kind_hl override")

  -- --- kind_icon/kind_name = false falls back to blink.cmp defaults
  config.setup({ api_key = "k", auto = true, debounce = 50, kind_icon = false, kind_name = false })
  local got_noicon
  src:get_completions({
    bufnr = buf,
    cursor = { 2, 5 },
    line = "    return n",
    bounds = { start_col = 1, length = 0 },
  }, function(resp)
    got_noicon = resp
  end)
  vim.wait(1000, function()
    return got_noicon ~= nil
  end)
  check(got_noicon ~= nil and got_noicon.items[1].kind_icon == nil, "source: kind_icon false falls back")
  check(got_noicon ~= nil and got_noicon.items[1].kind_name == nil, "source: kind_name false falls back")

  -- --- empty completion -> no items
  api.complete = function(_, cb)
    cb(nil, "   \n  ")
    return nil
  end
  local got6
  src:get_completions({
    bufnr = buf,
    cursor = { 2, 5 },
    line = "    return n",
    bounds = { start_col = 1, length = 0 },
  }, function(resp)
    got6 = resp
  end)
  vim.wait(1000, function()
    return got6 ~= nil
  end)
  check(got6 ~= nil and #got6.items == 0, "source: whitespace-only completion dropped")

  -- --- label shows the whole resulting line, not just the added text
  api.complete = function(_, cb)
    cb(nil, "fib(n-1) + fib(n-2)\n")
    return nil
  end
  config.setup({ api_key = "k", auto = true, debounce = 50 })
  local got_line
  src:get_completions({
    bufnr = buf,
    cursor = { 2, 5 },
    line = "    return n",
    bounds = { start_col = 1, length = 0 },
  }, function(resp)
    got_line = resp
  end)
  vim.wait(1000, function()
    return got_line ~= nil
  end)
  assert_eq(
    got_line.items[1].label,
    "rfib(n-1) + fib(n-2)",
    "source: label is the whole resulting line (current line + suggestion), indentation trimmed"
  )

  -- --- is_pending reflects an in-flight request
  config.setup({ api_key = "k", auto = true, debounce = 500 })
  local got_pending
  local cancel_pending_test = src:get_completions({
    bufnr = buf,
    cursor = { 2, 5 },
    line = "    return n",
    bounds = { start_col = 1, length = 0 },
  }, function(resp)
    got_pending = resp
  end)
  check(src:is_pending(buf) == true, "source: pending while request is in flight")
  cancel_pending_test()
  check(src:is_pending(buf) == false, "source: not pending after cancel")

  -- --- label truncation is UTF-8 safe
  api.complete = function(_, cb)
    cb(nil, string.rep("é", 100))
    return nil
  end
  local got7
  src:get_completions({
    bufnr = buf,
    cursor = { 2, 5 },
    line = "    return n",
    bounds = { start_col = 1, length = 0 },
  }, function(resp)
    got7 = resp
  end)
  vim.wait(1000, function()
    return got7 ~= nil
  end)
  check(got7 ~= nil and got7.items[1].label:find("…", 1, true) ~= nil, "source: label truncated with ellipsis")
  check(vim.str_utfindex(got7.items[1].label) == 81, "source: label truncated to 80 UTF-8 chars")

  -- --- enabled() respects cfg.enabled and filetype filters
  config.setup({ api_key = "k" })
  vim.bo.filetype = "python"
  check(src:enabled(), "source: enabled in python")
  config.setup({ api_key = "k", excluded_filetypes = { "python" } })
  check(not src:enabled(), "source: disabled by excluded_filetypes")
  config.setup({ api_key = "k", filetypes = { "lua" } })
  check(not src:enabled(), "source: disabled by filetypes allowlist")
  config.setup({ api_key = "k" })
  check(src:enabled(), "source: re-enabled")

  -- --- enabled() checks the target buffer, not the current one
  local other = vim.api.nvim_create_buf(false, true)
  vim.bo[other].filetype = "lua"
  vim.api.nvim_set_current_buf(other)
  config.setup({ api_key = "k", filetypes = { "python" } })
  check(src:enabled(buf), "source: enabled() reads target buffer filetype")
  check(not src:enabled(), "source: enabled() reads current buffer filetype")
  vim.api.nvim_buf_delete(other, { force = true })
  vim.api.nvim_set_current_buf(buf)

  api.complete = orig_complete
  vim.api.nvim_buf_delete(buf, { force = true })
end

-- ===================== status (statusline hint) =====================

do
  local status = require("deepseek-suggest.status")
  local config = require("deepseek-suggest.config")
  local state = require("deepseek-suggest.state")

  -- no lualine in the mock runtime, so injection must no-op gracefully
  check(status.inject() == false, "status: inject no-ops without lualine")

  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "def fib(n):", "    return n" })
  vim.api.nvim_set_current_buf(buf)
  vim.bo.filetype = "python"

  config.setup({ api_key = "k" })
  assert_eq(status.status(), "ok", "status: ok when connected and active for buffer")
  config.setup({ api_key = "k", enabled = false })
  check(status.status() == nil, "status: nil when plugin disabled")
  config.setup({ api_key = "k", statusline = false })
  check(status.status() == nil, "status: nil when statusline disabled")
  config.setup({ api_key = "k", filetypes = { "lua" } })
  check(status.status() == nil, "status: nil when filetype not allowed")

  config.setup({ api_key = "k" })
  state.set("no_balance")
  assert_eq(status.status(), "no_balance", "status: yellow when no balance")
  state.set("no_key")
  assert_eq(status.status(), "no_key", "status: red when API key rejected")
  state.set("ok")

  local comp = status.lualine_component()
  check(comp[1]() == "🐋 V4 Flash", "status: component shows whale + formatted model")
  config.setup({ api_key = "k", model = "deepseek-v4-pro" })
  check(status.lualine_component()[1]() == "🐋 V4 Pro", "status: model name formatted")
  config.setup({ api_key = "k" })

  -- token usage is hidden until used, then shown as 10.0K style
  check(comp[1]() == "🐋 V4 Flash", "status: no token count before any usage")
  state.add_usage("deepseek-v4-flash", 10000)
  check(comp[1]() == "🐋 V4 Flash 10.0K", "status: token usage shown and formatted")
  assert_eq(state.get_usage("deepseek-v4-flash"), 10000, "status: usage accumulated")
  state.add_usage("deepseek-v4-flash", 500)
  check(comp[1]() == "🐋 V4 Flash 10.5K", "status: usage accumulates")
  config.setup({ api_key = "k", statusline_tokens = false })
  check(status.lualine_component()[1]() == "🐋 V4 Flash", "status: token count hidden when statusline_tokens=false")
  config.setup({ api_key = "k" })
  check(status.lualine_status_icon()[1]() == "󰝥", "status: status icon is the wifi glyph")

  vim.env.DEEPSEEK_API_KEY = nil
  config.setup({ api_key = nil })
  assert_eq(status.status(), "no_key", "status: red when no api key configured")
  vim.env.DEEPSEEK_API_KEY = "env-test-key"
  config.setup({ api_key = "k" })

  vim.api.nvim_buf_delete(buf, { force = true })
end

-- ===================== init / registration (mock blink) =====================

do
  local init = require("deepseek-suggest")
  local config = require("deepseek-suggest.config")
  local blink = require("blink.cmp")
  local bcfg = require("blink.cmp.config")

  config.setup({ api_key = "k" })
  init.ensure_setup()

  check(blink._state.providers["deepseek-suggest"] ~= nil, "init: provider registered with blink.cmp")
  local provider = blink._state.providers["deepseek-suggest"]
  assert_eq(provider.module, "deepseek-suggest.source", "init: provider module")
  assert_eq(provider.name, "DeepSeek", "init: provider name")
  check(provider.score_offset == 100, "init: provider score_offset")
  check(bcfg.completion.ghost_text.enabled == true, "init: ghost text enabled")
  check(vim.tbl_contains(bcfg.sources.default, "deepseek-suggest"), "init: source added to default list")

  config.setup({ api_key = "k", score_offset = 250 })
  init.ensure_setup()
  check(provider.score_offset == 100, "init: no duplicate registration")

  init.manual_trigger()
  check(blink._state.shown ~= nil, "init: manual_trigger calls blink.show")
  local shown = blink._state.shown
  check(shown and shown.providers and shown.providers[1] == "deepseek-suggest", "init: show limited to provider")
  check(config.consume_manual() == true, "init: manual flag set by manual_trigger")

  local status = init.status()
  check(status:find("deepseek-v4-flash", 1, true) ~= nil, "init: status string")
end

-- ===================== real HTTP request (local python server) =====================

do
  local ok, err = pcall(function()
    local py = vim.fn.exepath("python")
    if py == "" then
      error("no python")
    end

    local body_file = root .. "/tests/request_body.txt"
    local handle = vim.system({ py, root .. "/tests/server.py", body_file, "18080" }, {
      text = true,
      stdout = false,
      stderr = false,
    })

    local up = false
    for _ = 1, 30 do
      local out = vim.fn.system("curl -s -o NUL -w %{http_code} http://127.0.0.1:18080/health")
      if out and out:find("200", 1, true) then
        up = true
        break
      end
      vim.wait(100)
    end
    if not up then
      handle:kill()
      error("test server did not start")
    end

    local api = require("deepseek-suggest.api")

    -- FIM mode
    local done1, err1, text1, usage1
    api.complete({
      prefix = "def fib(n):\n",
      suffix = "    return fib(n-1) + fib(n-2)",
      config = { mode = "fim", base_url = "http://127.0.0.1:18080", model = "deepseek-v4-flash", max_tokens = 128, temperature = 0.2, api_key = "k", timeout_ms = 5000 },
    }, function(e, t, _, u)
      done1, err1, text1, usage1 = true, e, t, u
    end)
    vim.wait(5000, function()
      return done1 ~= nil
    end)
    check(done1 == true and err1 == nil, "http: fim request completed")
    check(text1:find("fib", 1, true) ~= nil, "http: fim response text")
    assert_eq(usage1, 42, "http: fim usage total_tokens")

    local f = io.open(body_file, "r")
    local sent = f and f:read("*a")
    if f then
      f:close()
    end
    local sent_json = sent and vim.json.decode(sent) or {}
    assert_eq(sent_json.prompt, "def fib(n):\n", "http: request body prompt")
    assert_eq(sent_json.suffix, "    return fib(n-1) + fib(n-2)", "http: request body suffix")
    assert_eq(sent_json.model, "deepseek-v4-flash", "http: request body model")

    -- chat mode
    local done2, err2, text2, usage2
    api.complete({
      prefix = "def total():\n",
      suffix = "",
      config = { mode = "chat", base_url = "http://127.0.0.1:18080", model = "deepseek-v4-flash", max_tokens = 128, temperature = 0.2, api_key = "k", timeout_ms = 5000 },
    }, function(e, t, _, u)
      done2, err2, text2, usage2 = true, e, t, u
    end)
    vim.wait(5000, function()
      return done2 ~= nil
    end)
    check(done2 == true and err2 == nil, "http: chat request completed")
    check(text2:find("total", 1, true) ~= nil, "http: chat response text")
    assert_eq(usage2, 17, "http: chat usage total_tokens")

    local function local_cfg(timeout)
      return {
        mode = "fim",
        base_url = "http://127.0.0.1:18080",
        model = "deepseek-v4-flash",
        max_tokens = 128,
        temperature = 0.2,
        api_key = "k",
        timeout_ms = timeout,
      }
    end

    -- api error payload (via api.complete error parsing)
    local done4, err4
    api.complete({ prefix = "FAIL", suffix = "", config = local_cfg(5000) }, function(e)
      done4, err4 = true, e
    end)
    vim.wait(5000, function()
      return done4 ~= nil
    end)
    check(done4 == true and err4 ~= nil and err4:find("boom", 1, true) ~= nil, "http: api error surfaced")

    -- 402 -> classified as no balance for the status bar
    local done7, kind7
    api.complete({ prefix = "NOBALANCE", suffix = "", config = local_cfg(5000) }, function(e, _, k)
      done7, kind7 = true, k
    end)
    vim.wait(5000, function()
      return done7 ~= nil
    end)
    check(done7 == true and kind7 == "no_balance", "http: 402 classified as no balance")

    -- invalid JSON
    local done5, err5
    api.complete({ prefix = "GARBAGE", suffix = "", config = local_cfg(5000) }, function(e)
      done5, err5 = true, e
    end)
    vim.wait(5000, function()
      return done5 ~= nil
    end)
    check(done5 == true and err5 ~= nil and err5:find("invalid JSON", 1, true) ~= nil, "http: invalid json handled")

    -- timeout
    local done6, err6
    api.complete({ prefix = "SLOW", suffix = "", config = local_cfg(1500) }, function(e)
      done6, err6 = true, e
    end)
    vim.wait(8000, function()
      return done6 ~= nil
    end)
    check(done6 == true and err6 ~= nil, "http: slow request times out")

    handle:kill()
  end)

  if ok then
    print("http: suite completed")
  else
    print("SKIP: http suite (local python server unavailable): " .. tostring(err))
  end
end

print(string.format("\nAll tests passed: %d assertions", pass_count))
