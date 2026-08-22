--- Statusline integration. Shows a hint like `🐋 V4 Flash 󰝥` in the status bar
--- (via lualine, like LazyVim's Copilot indicator) whenever the plugin is
--- active for the current buffer. The trailing `󰝥` wifi icon is colored by the
--- connection state:
---   green  = connected (API key present, requests succeeding)
---   red    = no API key configured
---   yellow = no balance left (API returned 402)

local config = require("deepseek-suggest.config")
local source = require("deepseek-suggest.source")
local state = require("deepseek-suggest.state")
local cost = require("deepseek-suggest.cost")

local M = {}

local injected = false
local attempts = 0
local group = "DeepSeekSuggestStatusline"

---@type table<string, { name: string, fallback: string }>
local COLOR_MAP = {
  ok = { name = "DiagnosticOk", fallback = "#3fb950" },
  no_key = { name = "DiagnosticError", fallback = "#f85149" },
  no_balance = { name = "DiagnosticWarn", fallback = "#d29922" },
}

--- Resolves the foreground color of a highlight group as a hex string.
---@param name string
---@param fallback string
---@return string
local function hl_color(name, fallback)
  local hl = vim.api.nvim_get_hl(0, { name = name })
  if hl.fg then
    return string.format("#%06x", hl.fg)
  end
  return fallback
end

--- "deepseek-v4-flash" -> "V4 Flash", "deepseek-v4-pro" -> "V4 Pro"
---@param model string
---@return string
local function format_model(model)
  local name = (model or ""):gsub("^deepseek%-", "")
  local parts = {}
  for part in name:gmatch("[^%-]+") do
    parts[#parts + 1] = part:sub(1, 1):upper() .. part:sub(2)
  end
  return table.concat(parts, " ")
end

--- 10000 -> "10.0K", 1234567 -> "1.2M"
---@param n number
---@return string
local function format_tokens(n)
  if n >= 1000000 then
    return string.format("%.1fM", n / 1000000)
  elseif n >= 1000 then
    return string.format("%.1fK", n / 1000)
  end
  return tostring(n)
end

--- Current connection state for the current buffer.
---@return nil|"ok"|"no_key"|"no_balance"
function M.status()
  local cfg = config.get()
  if not cfg.statusline or not cfg.enabled then
    return nil
  end
  local bufnr = vim.api.nvim_get_current_buf()
  if not source.new({}):enabled(bufnr) then
    return nil
  end
  if not cfg.api_key or cfg.api_key == "" then
    return "no_key"
  end
  local kind = state.get()
  if kind == "no_key" or kind == "no_balance" then
    return kind
  end
  return "ok"
end

---@return table
function M.lualine_component()
  local cfg = config.get()
  return {
    function()
      local text = cfg.statusline_icon .. " " .. format_model(cfg.model)
      if cfg.statusline_tokens then
        local used = state.get_usage(cfg.model)
        if used > 0 then
          text = text .. " " .. format_tokens(used)
        end
      end
      if cfg.statusline_cost then
        local c = state.get_cost(cfg.model)
        if c > 0 then
          text = text .. " " .. cost.format_cost(c)
        end
      end
      return text
    end,
    cond = function()
      return M.status() ~= nil
    end,
  }
end

---@return table
function M.lualine_status_icon()
  return {
    function()
      return "󰝥" -- nf-cod-wifi (Nerd Font)
    end,
    cond = function()
      return M.status() ~= nil
    end,
    color = function()
      local entry = COLOR_MAP[M.status() or "ok"]
      return { fg = hl_color(entry.name, entry.fallback) }
    end,
  }
end

--- Injects the status hint into lualine. Safe to call repeatedly.
---@return boolean
function M.inject()
  if injected then
    return true
  end
  if not config.get().statusline then
    return true
  end
  local ok, lualine = pcall(require, "lualine")
  if not ok then
    return false
  end
  local conf = lualine.get_config()
  local sections = conf.sections and conf.sections.lualine_x
  if sections then
    for _, comp in ipairs(sections) do
      if type(comp) == "table" and comp.__deepseek_suggest then
        injected = true
        return true
      end
    end
    local comp = M.lualine_component()
    comp.__deepseek_suggest = true
    comp.separator = { left = "", right = " " }
    table.insert(sections, 1, comp)
    local icon = M.lualine_status_icon()
    icon.__deepseek_suggest = true
    icon.separator = { left = "", right = "" }
    table.insert(sections, 2, icon)
  end
  lualine.setup(conf)
  injected = true
  return true
end

--- Ensures the status hint is registered, waiting for lualine to load if needed.
function M.ensure()
  if injected or attempts > 20 then
    return
  end
  if M.inject() then
    return
  end
  attempts = attempts + 1
  vim.api.nvim_create_augroup(group, { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "LazyLoad",
    callback = function(event)
      if event.data == "nvim-lualine/lualine.nvim" and M.inject() then
        return true
      end
    end,
  })
  vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    callback = function()
      attempts = attempts + 1
      if M.inject() or attempts > 20 then
        vim.api.nvim_del_augroup_by_name(group)
        return true
      end
    end,
  })
end

return M
