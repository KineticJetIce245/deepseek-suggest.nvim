local M = {}

M.defaults = {
  --- Master switch for the plugin.
  enabled = true,
  --- Suggest automatically while typing (copilot style).
  --- When `false`, suggestions are only requested via the manual trigger
  --- (`:DeepseekSuggest` or the configured keymap).
  auto = true,
  --- DeepSeek API key. Falls back to the `DEEPSEEK_API_KEY` environment
  --- variable when not set here.
  api_key = nil,
  --- DeepSeek API base URL.
  base_url = "https://api.deepseek.com",
  --- Model used for completion.
  model = "deepseek-v4-flash",
  --- `fim` uses the fill-in-the-middle endpoint (`/beta/completions`, fastest,
  --- best for code). `chat` uses the chat prefix completion endpoint
  --- (`/beta/chat/completions`).
  mode = "fim",
  --- Maximum number of tokens in the suggestion (FIM caps at 4096).
  max_tokens = 256,
  temperature = 0.2,
  --- Debounce in milliseconds before a request is sent while typing.
  debounce = 300,
  --- Timeout in milliseconds for the HTTP request.
  timeout_ms = 20000,
  --- Number of lines of code sent before the cursor as context.
  prefix_lines = 100,
  --- Number of lines of code sent after the cursor as context (the FIM suffix).
  suffix_lines = 20,
  --- Minimum length of the prefix before a suggestion is attempted.
  min_prefix_len = 1,
  --- When `true`, re-request a suggestion as you keep typing inside a keyword
  --- (more responsive, costs more API calls). When `false` (default), the
  --- suggestion stays until the keyword is left.
  revalidate_on_keyword = false,
  --- Boost used to rank the suggestion above LSP/buffer items so ghost text
  --- shows it first.
  score_offset = 100,
  --- Only suggest in these filetypes (`nil` = all).
  filetypes = nil,
  --- Never suggest in these filetypes.
  excluded_filetypes = {},
  --- Extra stop sequences passed to the API.
  stop = nil,
  --- Show API errors with `vim.notify`.
  notify_errors = true,
  --- Force blink.cmp ghost text on when this plugin is used.
  ghost_text = true,
  --- Icon shown in the completion menu for the suggestion item. Defaults to a
  --- whale (DeepSeek's logo); set to the Nerd Font robot glyph (`\u{EC20}`) for
  --- a plain AI look, or `false` to fall back to blink.cmp's default icon.
  kind_icon = "🐋",
  --- Kind name shown in the completion menu.
  kind_name = "DeepSeek",
  --- Highlight group for the menu icon (`false` = use the default kind
  --- highlight group).
  kind_hl = false,
  --- Integrate with LazyVim's AI keymaps (`<Tab>` accepts the suggestion,
  --- enables `vim.g.ai_cmp`). Only takes effect when LazyVim is detected.
  lazyvim_integration = true,
  --- Insert mode keymaps. Set to `false` to disable them.
  --- `suggest` forces a suggestion at the cursor.
  keymaps = {
    suggest = "<C-g>",
  },
}

local opts = {}
local is_setup = false

---@param overrides? table
function M.setup(overrides)
  opts = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), overrides or {})
  if not opts.api_key then
    opts.api_key = vim.env.DEEPSEEK_API_KEY
  end
  is_setup = true
end

---@return table
function M.get()
  if not is_setup then
    M.setup()
  end
  return opts
end

---@param key string
---@param value any
function M.set(key, value)
  opts[key] = value
end

---@param key string
---@return any
function M.toggle(key)
  opts[key] = not opts[key]
  return opts[key]
end

--- Marks that the next source request was requested manually.
function M.request_manual()
  opts._manual_requested = true
end

--- Returns and clears the manual request flag.
---@return boolean
function M.consume_manual()
  local v = opts._manual_requested or false
  opts._manual_requested = false
  return v
end

return M
