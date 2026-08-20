local config = {
  completion = {
    ghost_text = { enabled = false },
  },
  sources = {
    default = { "lsp", "path", "snippets", "buffer" },
    providers = {},
  },
}

return setmetatable({}, {
  __index = function(_, k)
    return config[k]
  end,
})
