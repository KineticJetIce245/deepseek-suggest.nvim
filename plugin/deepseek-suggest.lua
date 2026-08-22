-- Ensures the plugin is set up even when lazy.nvim never calls `setup()`
-- (i.e. when the user did not pass `opts` to the plugin spec).
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  once = true,
  callback = function()
    require("deepseek-suggest").ensure_setup()
  end,
})

vim.api.nvim_create_user_command("DeepseekSuggest", function()
  require("deepseek-suggest").manual_trigger()
end, { desc = "DeepSeekSuggest: request a code suggestion" })

vim.api.nvim_create_user_command("DeepseekSuggestToggle", function()
  require("deepseek-suggest").toggle_auto()
end, { desc = "DeepSeekSuggest: toggle automatic suggestions" })

vim.api.nvim_create_user_command("DeepseekSuggestEnable", function()
  require("deepseek-suggest").set_enabled(true)
end, { desc = "DeepSeekSuggest: enable suggestions" })

vim.api.nvim_create_user_command("DeepseekSuggestDisable", function()
  require("deepseek-suggest").set_enabled(false)
end, { desc = "DeepSeekSuggest: disable suggestions" })

vim.api.nvim_create_user_command("DeepseekSuggestStatus", function()
  vim.notify(require("deepseek-suggest").status(), vim.log.levels.INFO, { title = "DeepSeekSuggest" })
end, { desc = "DeepSeekSuggest: show status" })

vim.api.nvim_create_user_command("DeepseekSuggestUsage", function()
  vim.notify(require("deepseek-suggest").usage(), vim.log.levels.INFO, { title = "DeepSeekSuggest" })
end, { desc = "DeepSeekSuggest: show session token usage and estimated cost" })
