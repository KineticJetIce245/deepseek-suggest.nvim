--- blink.cmp source that requests inline code suggestions from the DeepSeek
--- API. The suggestion is returned as a single item with a `textEdit` at the
--- cursor, so blink.cmp renders it as ghost text and it ranks on top thanks to
--- the provider `score_offset`.
---
--- The module has no load-time dependency on blink.cmp, so it can be loaded by
--- blink.cmp itself (`module = "deepseek-suggest.source"`) without issues.

local config = require("deepseek-suggest.config")
local context = require("deepseek-suggest.context")
local api = require("deepseek-suggest.api")

local CompletionItemKind = vim.lsp.protocol.CompletionItemKind
local PlainText = vim.lsp.protocol.InsertTextFormat.PlainText

local source = {}

---@type table<number, { timer: uv_timer_t, cancel: fun()|nil }>
local pending = {}

---@param bufnr number
local function cancel_pending(bufnr)
  local state = pending[bufnr]
  if not state then
    return
  end
  pending[bufnr] = nil
  local timer = state.timer
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
  if state.cancel then
    local c = state.cancel
    state.cancel = nil
    pcall(c)
  end
end

function source.new(opts)
  local self = setmetatable({}, { __index = source })
  self.opts = opts or {}
  return self
end

---@param bufnr? number buffer to check (defaults to the current buffer)
function source:enabled(bufnr)
  local cfg = config.get()
  if not cfg.enabled then
    return false
  end
  bufnr = bufnr or 0
  local buftype = vim.bo[bufnr].buftype
  if buftype ~= "" and buftype ~= "acwrite" then
    return false
  end
  local ft = vim.bo[bufnr].filetype
  if cfg.filetypes and not vim.tbl_contains(cfg.filetypes, ft) then
    return false
  end
  if cfg.excluded_filetypes and vim.tbl_contains(cfg.excluded_filetypes, ft) then
    return false
  end
  return true
end

function source:get_completions(ctx, callback)
  local cfg = config.get()

  local bufnr = ctx.bufnr or vim.api.nvim_get_current_buf()

  if not self:enabled(bufnr) then
    callback({ items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
    return
  end

  local manual = config.consume_manual()
  local auto = cfg.auto
  if self.opts.auto ~= nil then
    auto = self.opts.auto
  end
  if not auto and not manual then
    -- manual-only mode: stay silent unless explicitly requested
    callback({ items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
    return
  end

  cancel_pending(bufnr)

  -- ctx.cursor is { 1-indexed row, 0-indexed column } (nvim_win_get_cursor)
  local cursor = ctx.cursor or { 1, 0 }
  local line = cursor[1] - 1
  local col = cursor[2]

  local prefix, suffix = context.build(bufnr, { line = line, character = col }, cfg)
  if #prefix < cfg.min_prefix_len then
    callback({ items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
    return
  end

  -- keyword is only used as the fuzzy filter text so the item always matches
  local keyword = ""
  if ctx.line and ctx.bounds then
    keyword = string.sub(ctx.line, ctx.bounds.start_col, ctx.bounds.start_col + (ctx.bounds.length or 0) - 1)
  end

  local state = { timer = nil, cancel = nil }
  pending[bufnr] = state

  local timer = vim.uv.new_timer()
  state.timer = timer
  timer:start(cfg.debounce, 0, function()
    timer:stop()
    timer:close()
    if pending[bufnr] ~= state then
      return
    end

    local cancel = api.complete({ prefix = prefix, suffix = suffix, config = cfg }, function(err, text)
      if pending[bufnr] ~= state then
        return
      end
      pending[bufnr] = nil
      if err then
        if cfg.notify_errors then
          vim.notify("deepseek-suggest: " .. err, vim.log.levels.ERROR, { title = "DeepSeekSuggest" })
        end
        callback({ items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
        return
      end

      text = text:gsub("%s+$", "")
      if text == "" then
        callback({ items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
        return
      end

      local first_line = text:match("^[^\r\n]*") or ""
      local label = first_line
      if vim.str_utfindex(first_line) > 80 then
        label = first_line:sub(1, vim.str_byteindex(first_line, 80)) .. "…"
      end
      if label == "" then
        label = "DeepSeek suggestion"
      end

      local item = {
        label = label,
        kind = CompletionItemKind.Text,
        insertText = text,
        insertTextFormat = PlainText,
        textEdit = {
          newText = text,
          range = {
            start = { line = line, character = col },
            ["end"] = { line = line, character = col },
          },
        },
      }
      -- only filter on the keyword when one exists; otherwise let blink fall
      -- back to the label so the item is never dropped by an empty filterText
      if keyword ~= "" then
        item.filterText = keyword
      end

      -- give the item a dedicated kind/icon in the completion menu (like the
      -- copilot source does); false leaves the blink.cmp default in place
      if cfg.kind_name then
        item.kind_name = cfg.kind_name
      end
      if cfg.kind_icon then
        item.kind_icon = cfg.kind_icon
      end
      if cfg.kind_hl then
        item.kind_hl = cfg.kind_hl
      end

      callback({
        items = { item },
        is_incomplete_forward = cfg.revalidate_on_keyword,
        is_incomplete_backward = false,
      })
    end)
    if pending[bufnr] == state then
      state.cancel = cancel
    end
  end)

  return function()
    cancel_pending(bufnr)
  end
end

return source
