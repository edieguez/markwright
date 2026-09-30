# mdtools.nvim

Markdown editing tools for Neovim: toggle-based inline formatting, links, lists, headings, tables, code fences, footnotes, TOC and link diagnostics. The full design is in [SPEC.md](SPEC.md).

## Status

| Area | State |
|---|---|
| Skeleton: `setup()`, config, buffer attach, `:Mdtools`, `:checkhealth mdtools` | ✅ done |
| Formatting engine: italic, bold, strikethrough, inline code, highlight | ✅ done, tested |
| Links, smart paste, title fetch | ⏳ next |
| `gx` follow, anchors, slugs | ⏳ |
| Lists, headings | ⏳ |
| Code fences, footnotes | ⏳ |
| Tables | ⏳ |
| TOC, diagnostics | ⏳ |
| Image paste, insert-mode keys | 💤 parked |

## Requirements

- Neovim ≥ 0.10
- Treesitter parsers `markdown` and `markdown_inline` (bundled with Neovim, also installed by LazyVim's markdown extra)

## Install (LazyVim / lazy.nvim)

From a local checkout:

```lua
-- ~/.config/nvim/lua/plugins/mdtools.lua
return {
  {
    dir = "~/code/mdtools.nvim", -- wherever you put it
    ft = "markdown",
    opts = {},
  },
}
```

## Formatting keymaps

Buffer-local in Markdown files. Prefix defaults to `<leader>m` (which-key group "markdown").

| Keys | Mode | Action |
|---|---|---|
| `<leader>mi` | n, x | Toggle italic `*text*` |
| `<leader>mb` | n, x | Toggle bold `**text**` |
| `<leader>ms` | n, x | Toggle strikethrough `~~text~~` |
| `<leader>mc` | n, x | Toggle inline code `` `text` `` |
| `<leader>mh` | n, x | Toggle highlight `==text==` |
| `<leader>mI` `mB` `mS` `mC` `mH` | n | Operator versions: add a motion, e.g. `<leader>mB2e` |

Behavior:

- **Normal mode** acts on the word under the cursor. On whitespace or an empty line it inserts an empty pair and starts insert mode between the markers.
- **Toggle:** pressing a key anywhere inside an existing span removes the whole span. `_text_` and `__text__` are recognized too.
- **Nesting:** formats combine, so italic on `**word**` gives `***word***`.
- **Multi-line** selections are wrapped line by line, skipping indentation, list markers, checkboxes, `>` and `#`.
- **Whitespace** at the edges of a selection stays outside the markers.
- **Inline code** switches to a longer fence when the text contains backticks: `` a`b `` becomes ` ``a`b`` `.
- **Code:** formatting inside code blocks or code spans is skipped with a warning.
- **Repeat and undo:** every action is dot-repeatable and undoes in one step.

## Commands

- `:Mdtools bold|italic|strike|code|highlight` toggles the format on the word under the cursor.
- `:Mdtools health` runs `:checkhealth mdtools`.

## Configuration

See `lua/mdtools/config.lua` or SPEC.md section 4 for all options. Example:

```lua
opts = {
  keymaps = { prefix = "<leader>m" },
  format = {
    italic = { marker = "_" },
    warn_in_code = false,
  },
}
```

Set `keymaps.enabled = false` to map everything yourself using `require("mdtools.format").expr_normal(fmt)` and `expr_operator(fmt)` as `expr = true` mappings.

## Tests

```sh
make test
```

The tests run headless Neovim with `tests/minimal_init.lua` and feed real keys through the mappings.
