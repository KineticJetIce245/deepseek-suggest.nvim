local M = {}

local config = require("deepseek-suggest.config")

local setup_done = false
local registered = false
local retry_group = nil

--- Registers the LazyVim AI integration so `<Tab>` accepts our suggestion and
--- `vim.g.ai_cmp` enables ghost text in LazyVim's blink.cmp config.
local function lazyvim_integration()
  local ok, cmp_util = pcall(require, "lazyvim.util.cmp")
  if not ok then
    return
  end
  local cfg = config.get()
  if not cfg.lazyvim_integration then
    return
  end
  vim.g.ai_cmp = true
  if type(cmp_util.actions) ~= "table" or cmp_util.actions.ai_accept ~= nil then
    return
  end
  cmp_util.actions.ai_accept = function()
    local ok_blink, blink = pcall(require, "blink.cmp")
    if not ok_blink then
      return false
    end
    local item = blink.get_selected_item()
    if item and item.source_id == "deepseek-suggest" then
      blink.accept({ force = true })
      return true
    end
    return false
  end
end

--- Registers the `deepseek-suggest` source provider with blink.cmp, enables
--- ghost text and appends the source to the default sources list.
---@return boolean
local function register()
  if registered then
    return true
  end
  local ok, blink = pcall(require, "blink.cmp")
  if not ok then
    return false
  end

  local cfg = config.get()

  local ok_add = pcall(blink.add_source_provider, "deepseek-suggest", {
    name = "DeepSeek",
    module = "deepseek-suggest.source",
    async = true,
    max_items = 1,
    score_offset = cfg.score_offset,
    timeout_ms = cfg.timeout_ms,
  })
  if not ok_add then
    return false
  end

  -- ensure ghost text is on (that's how suggestions are shown)
  local bcfg = require("blink.cmp.config")
  if cfg.ghost_text and bcfg.completion and bcfg.completion.ghost_text then
    bcfg.completion.ghost_text.enabled = true
  end

  -- enable the source by default (works when `sources.default` is a list)
  local defaults = bcfg.sources and bcfg.sources.default
  if type(defaults) == "table" and not vim.tbl_contains(defaults, "deepseek-suggest") then
    table.insert(defaults, "deepseek-suggest")
  elseif type(defaults) == "function" then
    vim.notify(
      "deepseek-suggest: your blink.cmp `sources.default` is a function; add the 'deepseek-suggest' source manually (see README)",
      vim.log.levels.WARN,
      { title = "DeepSeekSuggest" }
    )
  end

  lazyvim_integration()
  registered = true
  return true
end

--- blink.cmp is lazy loaded, so retry registering on each insert until it
--- becomes available.
local function schedule_retry()
  if retry_group then
    return
  end
  retry_group = vim.api.nvim_create_augroup("DeepSeekSuggestRegister", { clear = true })
  vim.api.nvim_create_autocmd({ "InsertEnter", "CmdlineEnter" }, {
    group = retry_group,
    callback = function()
      if register() then
        vim.api.nvim_del_augroup_by_id(retry_group)
        retry_group = nil
      end
    end,
  })
end

---@param cfg table
local function setup_keymaps(cfg)
  local kms = cfg.keymaps
  if kms == false or kms == nil then
    return
  end
  if type(kms) == "string" then
    kms = { suggest = kms }
  end
  if kms.suggest then
    vim.keymap.set("i", kms.suggest, function()
      M.manual_trigger()
    end, { desc = "DeepSeekSuggest: request suggestion" })
  end
end

--- Main entry point. Called automatically by lazy.nvim when `opts` is given,
--- or via `require("deepseek-suggest").setup(opts)`.
---@param opts? table
function M.setup(opts)
  config.setup(opts)
  setup_done = true
  setup_keymaps(config.get())
  if not register() then
    schedule_retry()
  end
end

--- Ensures `setup()` ran (called from the plugin script at VeryLazy).
function M.ensure_setup()
  if not setup_done then
    M.setup()
  elseif not register() then
    schedule_retry()
  end
end

--- Requests a suggestion at the cursor (works in both auto and manual modes).
function M.manual_trigger()
  register()
  config.request_manual()
  local ok, blink = pcall(require, "blink.cmp")
  if not ok then
    vim.notify("deepseek-suggest: blink.cmp is not loaded yet", vim.log.levels.WARN, { title = "DeepSeekSuggest" })
    return
  end
  blink.show({ providers = { "deepseek-suggest" } })
end

---@return boolean
function M.toggle_auto()
  local val = config.toggle("auto")
  vim.notify("DeepSeekSuggest: auto-suggest " .. (val and "on" or "off"), vim.log.levels.INFO, { title = "DeepSeekSuggest" })
  return val
end

---@param enabled boolean
function M.set_enabled(enabled)
  config.set("enabled", enabled)
  vim.notify(
    "DeepSeekSuggest: " .. (enabled and "enabled" or "disabled"),
    vim.log.levels.INFO,
    { title = "DeepSeekSuggest" }
  )
end

---@return string
function M.status()
  local cfg = config.get()
  return string.format(
    "DeepSeekSuggest | enabled: %s | auto-suggest: %s | mode: %s | model: %s",
    cfg.enabled and "yes" or "no",
    cfg.auto and "on" or "off",
    cfg.mode,
    cfg.model
  )
end

return M
