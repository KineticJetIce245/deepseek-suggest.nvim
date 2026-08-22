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

	-- fetch the whole prefix/suffix ranges in one RPC round-trip instead of
	-- per-line calls (cheaper on Windows where each call crosses a pipe)
	local start = math.max(0, cursor.line - opts.prefix_lines + 1)
	local prefix_lines = vim.api.nvim_buf_get_lines(bufnr, start, cursor.line + 1, false)
	local prefix_parts = {}
	for i, l in ipairs(prefix_lines) do
		prefix_parts[i] = l
	end
	-- truncate the current line at the cursor
	local current = prefix_parts[#prefix_parts] or ""
	prefix_parts[#prefix_parts] = current:sub(1, cursor.character)
	local prefix = table.concat(prefix_parts, "\n")

	-- everything after the cursor on the current line, then the following lines
	local suffix = current:sub(cursor.character + 1)
	local stop = math.min(line_count - 1, cursor.line + opts.suffix_lines)
	if cursor.line < stop then
		local after = vim.api.nvim_buf_get_lines(bufnr, cursor.line + 1, stop + 1, false)
		suffix = suffix .. "\n" .. table.concat(after, "\n")
	end

	return prefix, suffix
end

return M
