local M = {}

--- Builds the FIM prefix/suffix from the buffer around the cursor.
---
---@param bufnr number
---@param cursor { line: number, character: number } 0-indexed cursor position
---@param opts { prefix_lines: number, suffix_lines: number }
---@return string prefix Text before the cursor
---@return string suffix Text after the cursor (may be empty)
function M.build(bufnr, cursor, opts)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local current = vim.api.nvim_buf_get_lines(bufnr, cursor.line, cursor.line + 1, false)[1] or ""

  local prefix_parts = {}
  local start = math.max(0, cursor.line - opts.prefix_lines + 1)
  for i = start, cursor.line do
    local l = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1] or ""
    prefix_parts[#prefix_parts + 1] = l
  end
  -- truncate the current line at the cursor
  prefix_parts[#prefix_parts] = current:sub(1, cursor.character)
  local prefix = table.concat(prefix_parts, "\n")

  -- everything after the cursor on the current line, then the following lines
  local suffix = current:sub(cursor.character + 1)
  local stop = math.min(line_count - 1, cursor.line + opts.suffix_lines)
  for i = cursor.line + 1, stop do
    local l = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1] or ""
    suffix = suffix .. "\n" .. l
  end

  return prefix, suffix
end

return M
