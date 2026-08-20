# deepseek-suggest.nvim

![vibe coded](https://img.shields.io/badge/vibe--coded-true-7c3aed)

> **Vibe coded** — this project was built with the help of AI assistants.

Copilot-style inline code suggestions in Neovim powered by the
[DeepSeek API](https://platform.deepseek.com), integrated with
[blink.cmp](https://github.com/Saghen/blink.cmp) as a completion source.

Suggests code **automatically** as you type, or **on demand** with a keypress.
Works on any platform (Windows, macOS, Linux).

It uses DeepSeek's official **FIM (fill-in-the-middle)** beta endpoint, which is
purpose-built for code completion: it receives the code before *and* after the
cursor and returns exactly the text that fits in between.

## Requirements

- Neovim 0.10+
- [blink.cmp](https://github.com/Saghen/blink.cmp) (LazyVim ships it by default)
- `curl` on your `PATH` (bundled with Windows 10 1803+, macOS and most Linux distros)
- A [DeepSeek API key](https://platform.deepseek.com/api_keys)
  (set `DEEPSEEK_API_KEY` or pass `api_key`)

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim) + LazyVim, add this to
`~/.config/nvim/lua/plugins/deepseek-suggest.lua`:

```lua
return {
  {
    "deepseek-suggest/deepseek-suggest.nvim",
    event = "VeryLazy",
    opts = {
      api_key = "sk-...", -- or rely on the DEEPSEEK_API_KEY env var
      -- auto = true,  -- suggest automatically while typing
    },
  },
}
```

The plugin registers a `deepseek-suggest` blink.cmp source, adds it to
`sources.default` and enables ghost text automatically. No manual blink.cmp
setup is required.

Plain lazy.nvim (non-LazyVim):

```lua
{
  "deepseek-suggest/deepseek-suggest.nvim",
  event = "VeryLazy",
  config = function()
    require("deepseek-suggest").setup({
      api_key = vim.env.DEEPSEEK_API_KEY,
    })
  end,
}
```

> If your blink.cmp config defines `sources.default` as a **function** instead
> of a list, add the source manually in your blink.cmp config:
>
> ```lua
> sources = {
>   default = { "lsp", "path", "snippets", "buffer", "deepseek-suggest" },
>   providers = {
>     ["deepseek-suggest"] = {
>       name = "DeepSeek",
>       module = "deepseek-suggest.source",
>       async = true,
>       score_offset = 100,
>     },
>   },
> },
> ```

## Usage

### Automatic mode (default)

While typing, a ghost-text suggestion appears after a short debounce. Accept
with `<C-y>` (blink.cmp default) or `<Tab>` (LazyVim's AI integration when the
plugin detects LazyVim). Cancel with `<C-e>`.

For a cleaner "ghost text only" experience (no inline preview while typing),
you may want to disable `auto_insert` in your blink.cmp config:

```lua
completion = {
  list = { selection = { auto_insert = false } },
  ghost_text = { enabled = true },
},
```

### Completion menu icon

Like the copilot source, the suggestion gets its own icon (a whale, DeepSeek's
logo) in the completion popup. To switch to a Nerd Font robot AI icon or disable
the custom icon:

```lua
opts = {
  kind_icon = "\u{EC20}", -- Nerd Font robot AI icon
  -- kind_icon = false,   -- fall back to blink.cmp's default kind icon
}
```

### Manual mode

Set `auto = false` and suggestions will only appear when you ask for them:

```lua
opts = { auto = false }
```

Press `<C-g>` (insert mode) or run `:DeepseekSuggest` to request a suggestion
at the cursor.

### Commands

| Command                       | Action                                   |
| ----------------------------- | ---------------------------------------- |
| `:DeepseekSuggest`             | Request a suggestion at the cursor       |
| `:DeepseekSuggestToggle`       | Toggle automatic suggestions on/off      |
| `:DeepseekSuggestEnable`       | Enable suggestions                       |
| `:DeepseekSuggestDisable`      | Disable suggestions                      |
| `:DeepseekSuggestStatus`       | Show plugin status                       |

## Options

All options are passed to `setup()` (or via `opts` in the plugin spec).

| Option                     | Default                 | Description                                                       |
| -------------------------- | ----------------------- | ----------------------------------------------------------------- |
| `enabled`                  | `true`                  | Master switch                                                     |
| `auto`                     | `true`                  | Suggest automatically while typing                                |
| `api_key`                  | `nil` (`DEEPSEEK_API_KEY`) | DeepSeek API key                                             |
| `base_url`                 | `https://api.deepseek.com` | API base URL                                                  |
| `model`                    | `deepseek-v4-flash`     | Model (`deepseek-v4-flash`, `deepseek-v4-pro`)                    |
| `mode`                     | `"fim"`                 | `"fim"` (fast, fill-in-the-middle) or `"chat"` (chat prefix)      |
| `max_tokens`               | `256`                   | Max tokens in the suggestion (FIM caps at 4096)                   |
| `temperature`              | `0.2`                   | Sampling temperature                                              |
| `debounce`                 | `300`                   | ms to wait after the last keystroke before requesting             |
| `timeout_ms`               | `20000`                 | HTTP request timeout                                              |
| `prefix_lines`             | `100`                   | Lines of context sent before the cursor                           |
| `suffix_lines`             | `20`                    | Lines of context sent after the cursor                            |
| `min_prefix_len`           | `1`                     | Min prefix length before attempting a suggestion                  |
| `revalidate_on_keyword`    | `false`                 | Re-request as you keep typing inside a keyword (costs more tokens)|
| `score_offset`             | `100`                   | Ranks the suggestion above LSP/buffer items                       |
| `filetypes`                | `nil`                   | Restrict suggestions to these filetypes (`nil` = all)             |
| `excluded_filetypes`       | `{}`                    | Never suggest in these filetypes                                  |
| `stop`                     | `nil`                   | Extra stop sequences for the API                                  |
| `notify_errors`            | `true`                  | Show API errors with `vim.notify`                                 |
| `ghost_text`               | `true`                  | Force blink.cmp ghost text on                                      |
| `kind_icon`                | `"🐋"`                  | Menu icon for the suggestion (`false` = blink.cmp default; `"\u{EC20}"` = Nerd Font robot AI icon) |
| `kind_name`                | `"DeepSeek"`            | Kind text shown in the completion menu (`false` = default)         |
| `kind_hl`                  | `false`                 | Highlight group for the menu icon                                  |
| `lazyvim_integration`      | `true`                  | Enable LazyVim `<Tab>` accept + `vim.g.ai_cmp`                    |
| `keymaps`                  | `{ suggest = "<C-g>" }` | Insert-mode keymaps (`false` disables all)                        |

## How it works

1. blink.cmp triggers the `deepseek-suggest` source (on keyword typing, or when
   the manual trigger calls `blink.cmp.show()`).
2. The buffer text before/after the cursor is collected (`prefix_lines` /
   `suffix_lines`).
3. After `debounce` ms, a request is sent with `curl` to
   `POST {base_url}/beta/completions` (`{ model, prompt, suffix, max_tokens,
   temperature }`).
4. The returned text becomes a single completion item with a `textEdit` at the
   cursor. blink.cmp renders it as ghost text; accepting inserts it.

Requests are cancelled when you keep typing or leave insert mode, so no
stale suggestions appear.

## Troubleshooting

- **No suggestions**: check `:DeepseekSuggestStatus`, confirm `curl` exists
  (`where curl`), and enable ghost text in blink.cmp:
  `completion.ghost_text = { enabled = true }` (the plugin does this for you).
- **`source 'deepseek-suggest' not configured`**: your `sources.default` is
  probably a function. Add the provider manually (see Installation).
- **Nothing on manual trigger**: the plugin registers itself once blink.cmp is
  loaded (it is lazy loaded on `InsertEnter`). If you used it before entering
  insert mode once, just enter insert mode and try again.
- **Cost**: lower `debounce` impact by keeping `revalidate_on_keyword = false`,
  and cap `max_tokens` to what you need.

## License

MIT
