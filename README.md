# mdtools.nvim

Markdown editing for Neovim that feels native: one key adds a format, the same key removes it. It works on the word under the cursor, on a visual selection or with any motion. It also understands the Markdown structure through Treesitter instead of guessing with regular expressions.

Built for LazyVim, and it works with any Neovim ≥ 0.10 setup.

> **Status: early development.** The inline formatting engine is complete and tested. Links, lists, headings, tables, footnotes, TOC and diagnostics are designed (see [SPEC.md](SPEC.md)) and are being implemented in that order. See [Roadmap](#roadmap).

---

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Keymaps](#keymaps)
- [Inline formatting in detail](#inline-formatting-in-detail)
- [Commands](#commands)
- [Configuration](#configuration)
- [Custom keymaps and Lua API](#custom-keymaps-and-lua-api)
- [Health check](#health-check)
- [Troubleshooting](#troubleshooting)
- [Roadmap](#roadmap)
- [Development](#development)
- [Project layout](#project-layout)

---

## Features

### Available now

| Feature | Markers |
|---|---|
| Italic | `*text*` (also removes `_text_`) |
| Bold | `**text**` (also removes `__text__`) |
| Strikethrough | `~~text~~` |
| Inline code | `` `text` ``, with automatic longer fences |
| Highlight | `==text==` |

All five share one engine, so they behave the same way:

- **Toggle.** The same key adds or removes the format.
- **Three ways to target text.** They work on the word under the cursor, on a visual selection (charwise, linewise or blockwise), and as an operator with any motion.
- **Removes the whole span from anywhere inside it.** The cursor on `world` in `**hello world**` gives `hello world`.
- **Formats nest.** Italic on `**word**` gives `***word***`.
- **Knows Markdown structure.** List markers, checkboxes, `>` and `#` are never wrapped.
- **Skips code.** Nothing gets broken inside code blocks or code spans.
- **Behaves like a native command.** Every action is dot-repeatable (`.`) and undoes in a single `u`.

### Coming next

Links (from the clipboard, with page titles), smart paste, `gx` link following, list continuation, checkboxes, heading levels, code fences, tables, footnotes, TOC and broken-link diagnostics. Details are in [Roadmap](#roadmap).

---

## Requirements

| Requirement | Why |
|---|---|
| Neovim **≥ 0.10** | Modern Treesitter API, `vim.system`, `vim.ui.open` |
| Treesitter parsers **`markdown`** and **`markdown_inline`** | Structure detection. Bundled with Neovim 0.10+ and also installed by LazyVim's markdown extra |
| `curl` *(optional, future)* | Fetching page titles for links |
| A clipboard provider *(optional, future)* | Creating links from a copied URL |

Run `:checkhealth mdtools` to verify everything.

---

## Installation

### LazyVim / lazy.nvim, local checkout

Create `~/.config/nvim/lua/plugins/mdtools.lua`:

```lua
return {
  {
    dir = "~/code/mdtools.nvim", -- the folder that contains lua/ and plugin/
    name = "mdtools.nvim",
    ft = "markdown",
    opts = {},
  },
}
```

Restart Neovim and open any `.md` file. lazy.nvim does not auto-update `dir` plugins. After editing the plugin, run `:Lazy reload mdtools.nvim` or restart.

### LazyVim / lazy.nvim, from a Git repository

Once the repo is on GitHub (replace `you/mdtools.nvim`):

```lua
return {
  { "you/mdtools.nvim", ft = "markdown", opts = {} },
}
```

### Plain Neovim (no plugin manager)

```lua
-- init.lua
vim.opt.rtp:prepend(vim.fn.expand("~/code/mdtools.nvim"))
require("mdtools").setup({})
```

Or clone it into a native package directory:

```sh
git clone <repo> ~/.local/share/nvim/site/pack/local/start/mdtools.nvim
```

Then call `require("mdtools").setup({})` in your config.

### Verifying the install

1. `:Lazy` lists `mdtools.nvim` as loaded (lazy.nvim users).
2. `:checkhealth mdtools` shows all parsers as OK.
3. In a Markdown buffer, `<leader>m` opens the which-key **markdown** group.

---

## Quick start

Open a Markdown file, put the cursor on a word and try:

```
<leader>mb      bold the word           hello  →  **hello**
<leader>mb      again: remove it        **hello**  →  hello
<leader>mi      italic                  hello  →  *hello*
viw<leader>mc   inline code (visual)    hello  →  `hello`
<leader>mB2e    bold the next 2 words   one two three  →  **one two** three
.               repeat the last toggle
u               undo it (one step)
```

On an empty line or on whitespace, `<leader>mb` inserts `****` and puts you in insert mode between the markers, so you can type the bold text right away.

---

## Keymaps

Keymaps are **buffer-local** and only exist in Markdown buffers (see `filetypes` in [Configuration](#configuration)). The prefix defaults to `<leader>m`. With LazyVim's default leader that is `Space m`.

| Keys | Mode | Action |
|---|---|---|
| `<leader>mi` | normal, visual | Toggle **italic** |
| `<leader>mb` | normal, visual | Toggle **bold** |
| `<leader>ms` | normal, visual | Toggle **strikethrough** |
| `<leader>mc` | normal, visual | Toggle **inline code** |
| `<leader>mh` | normal, visual | Toggle **highlight** |
| `<leader>mI` + motion | normal | Italic operator |
| `<leader>mB` + motion | normal | Bold operator |
| `<leader>mS` + motion | normal | Strikethrough operator |
| `<leader>mC` + motion | normal | Inline code operator |
| `<leader>mH` + motion | normal | Highlight operator |

**Operator examples:**

| Keys | Acts on |
|---|---|
| `<leader>mBiw` | inner word (same as `<leader>mb`) |
| `<leader>mB2e` | to the end of the second word |
| `<leader>mB$` | to the end of the line |
| `<leader>mBip` | the whole paragraph, wrapped line by line |
| `<leader>mIi"` | inside the quotes (with a quote text object) |

If which-key is installed (it is in LazyVim), the prefix is registered as a **markdown** group so the keys show up in the popup.

---

## Inline formatting in detail

### What gets targeted

| Mode | Target |
|---|---|
| Normal, cursor on a word | The word under the cursor (`iw`, so `snake_case_word` stays one word) |
| Normal, cursor on whitespace or an empty line | Nothing to wrap: inserts an empty pair and enters insert mode between the markers |
| Visual charwise (`v`) | The selection |
| Visual linewise (`V`) | Each selected line (see [Multi-line](#multi-line-selections)) |
| Visual blockwise (`<C-v>`) | The block's columns on each line |
| Operator + motion | The motion's range |

### Toggle rules

For each piece of text, the plugin decides in this order:

1. **Inside code?** If the text is in a fenced or indented code block, or in a code span, it does nothing and shows a warning. The exception is the inline-code key, which removes the code span it is in.
2. **Inside a span of that format?** It removes the whole span, wherever the cursor or selection is inside it.
3. **Otherwise** it wraps the text with the configured marker.

Removal works whichever cursor position you use:

```
**hello world**      cursor on "world"   <leader>mb  →  hello world
**hello world**      cursor on "**"      <leader>mb  →  hello world
x **bold** y         select "bold"       <leader>mb  →  x bold y
```

### Recognized markers

| Format | Inserted | Also recognized when removing |
|---|---|---|
| Italic | `*text*` | `_text_` |
| Bold | `**text**` | `__text__` |
| Strikethrough | `~~text~~` | — |
| Inline code | `` `text` `` | any backtick fence length |
| Highlight | `==text==` | — |

Intraword underscores are not emphasis, so `snake_case_word` is safe. Escaped markers like `\*` are treated as literal text.

### Nesting

Formats are independent layers:

```
**word**     <leader>mi  →  ***word***
***word***   <leader>mb  →  *word*
***word***   <leader>mi  →  **word**
```

### Multi-line selections

Markdown emphasis cannot span blank lines, so a multi-line target is wrapped **line by line**:

- Blank lines are skipped.
- Block prefixes are never wrapped: indentation, `>` blockquotes, `-` `*` `+` `1.` `1)` list markers, `[ ]` / `[x]` checkboxes and `#` heading markers.
- In a charwise selection, the first and last lines respect the selection's columns.
- Each line is toggled independently.

```
- item one            V4j<leader>mb     - **item one**
- [ ] task two                          - [ ] **task two**
                         →
# Heading                               # **Heading**
> quoted                                > **quoted**
```

### Whitespace

Spaces at the edges of a selection stay outside the markers, because `*word *` is not valid emphasis:

```
select "two " in "one two three"   <leader>mb  →  one **two** three
```

### Inline code and backticks

If the text already contains backticks, a longer fence is used automatically. Padding spaces are added when the text starts or ends with a backtick:

```
a`b   →  ``a`b``
`x    →  `` `x ``
```

Removing the code span strips the padding again.

### Empty markers on whitespace

With the cursor on whitespace or an empty line in normal mode, the key inserts an empty pair and starts insert mode between the markers. A separating space is added if the next character would touch the closing marker:

```
""       <leader>mb  →  **|**
"foo "   <leader>mi  →  foo *|*
"a b"    <leader>mb  →  a **|** b        (cursor on the space)
```

### Cursor, repeat and undo

- In normal mode, the cursor stays on the same character it was on.
- After a visual or operator toggle, the cursor moves to the start of the text.
- `.` repeats the last toggle on the word or text under the new cursor position.
- Each toggle is a single undo step, even when it changes many lines.

---

## Commands

| Command | Description |
|---|---|
| `:Mdtools bold` | Toggle bold on the word under the cursor |
| `:Mdtools italic` | Toggle italic |
| `:Mdtools strike` | Toggle strikethrough |
| `:Mdtools code` | Toggle inline code |
| `:Mdtools highlight` | Toggle highlight |
| `:Mdtools health` | Run `:checkhealth mdtools` |

Subcommands tab-complete. New subcommands (`toc`, `table create`, `check`, …) will be added as features land.

---

## Configuration

Pass options to `setup()`, or through `opts` with lazy.nvim. Everything is optional and these are the defaults.

```lua
require("mdtools").setup({
  -- Filetypes the plugin attaches to
  filetypes = { "markdown" },

  keymaps = {
    enabled = true,         -- false: define no keymaps (map them yourself)
    prefix = "<leader>m",   -- prefix for all default mappings
  },

  format = {
    italic    = { marker = "*" },   -- use "_" if you prefer _italic_
    bold      = { marker = "**" },  -- or "__"
    strike    = { marker = "~~" },
    code      = { marker = "`" },   -- longer fences are chosen automatically when needed
    highlight = { marker = "==" },
    trim_whitespace = true,         -- keep edge spaces outside the markers
    multiline = "per_line",         -- only supported mode
    warn_in_code = true,            -- notify when formatting is skipped inside code
  },

  -- The sections below are accepted now and used by upcoming features.
  links = {
    use_clipboard = true,           -- link key uses a URL from the clipboard
    fetch_title = true,             -- bare URL → [Page Title](url)
    title_timeout_ms = 5000,
    smart_paste_visual = true,      -- visual p with a URL → [selection](url)
    smart_paste_normal = true,      -- normal p with a URL → [Title](url)
  },
  follow = {
    key = "gx",
    create_missing_md = true,       -- gx on a missing .md opens a new buffer
  },
  lists = {
    continue_on_enter = true,
    tab_indent = true,
    auto_renumber = true,
    checkbox_add = true,
  },
  tables = {
    align_on_insert_leave = true,
  },
  toc = {
    update_on_save = true,
    marker_start = "<!-- toc -->",
    marker_end = "<!-- tocstop -->",
    min_level = 2,
    max_level = 4,
  },
  diagnostics = {
    enabled = true,
    on_save = true,
    severity = vim.diagnostic.severity.WARN,
  },
})
```

**Examples**

Underscore italics and a different prefix:

```lua
opts = {
  keymaps = { prefix = "<leader>k" },
  format = { italic = { marker = "_" } },
}
```

Enable for other filetypes too:

```lua
opts = { filetypes = { "markdown", "quarto", "rmd" } }
```

Silence the code warning:

```lua
opts = { format = { warn_in_code = false } }
```

Invalid options (an empty marker, an unsupported `multiline` value) raise an error at startup with a clear message.

---

## Custom keymaps and Lua API

To choose your own keys, disable the defaults and map the entry points yourself. They must be **`expr = true`** mappings, because they return the keys that drive Vim's operator machinery. That is what makes `.` repeat work.

```lua
opts = { keymaps = { enabled = false } },
config = function(_, opts)
  require("mdtools").setup(opts)
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "markdown",
    callback = function(ev)
      local f = require("mdtools.format")
      local map = function(mode, lhs, fn, desc)
        vim.keymap.set(mode, lhs, fn, { buffer = ev.buf, expr = true, desc = desc })
      end
      map("n", "<C-b>", function() return f.expr_normal("bold") end, "Bold word")
      map("x", "<C-b>", function() return f.expr_operator("bold") end, "Bold selection")
      map("n", "gb",    function() return f.expr_operator("bold") end, "Bold operator")
    end,
  })
end,
```

| Function | Use |
|---|---|
| `require("mdtools.format").expr_normal(fmt)` | Normal-mode `expr` mapping: word under the cursor, or empty markers on whitespace |
| `require("mdtools.format").expr_operator(fmt)` | `expr` mapping for visual mode, or a normal-mode operator that waits for a motion |
| `require("mdtools.format").toggle(fmt)` | Toggle on the word under the cursor from any Lua code (not an `expr` mapping) |
| `require("mdtools.format").apply(buf, fmt, mtype, srow, scol, erow, ecol)` | Low-level: toggle over a range. Rows and columns are 0-based bytes, `ecol` is inclusive, `mtype` is `"char"`, `"line"` or `"block"` |

`fmt` is one of `"italic"`, `"bold"`, `"strike"`, `"code"`, `"highlight"`.

---

## Health check

```
:checkhealth mdtools
```

It checks:

- Neovim version
- the `markdown` and `markdown_inline` parsers
- `curl`
- a clipboard provider
- `vim.ui.open`

Warnings for `curl` and the clipboard only affect upcoming link features.

---

## Troubleshooting

**The keymaps don't exist.**
- Make sure the buffer's filetype is `markdown` (`:set ft?`). Keymaps are buffer-local.
- Check `:Lazy` to see whether the plugin loaded, and that `dir` points at the folder containing `lua/` and `plugin/`.
- Check for conflicts with `:verbose nmap <leader>mb`.

**The which-key group doesn't show.** The group is registered only when which-key is loaded at the moment the buffer attaches. The keymaps work regardless.

**Nothing happens and a warning says "formatting skipped inside code".** The cursor is inside a code block or code span, which is intended. Use `<leader>mc` to remove a code span first.

**Toggling doesn't detect an existing format.** Detection relies on the `markdown_inline` parser. Run `:checkhealth mdtools`, and `:TSInstall markdown markdown_inline` if they are missing. Without the parsers, the plugin falls back to a simpler text check.

**The wrong word boundaries are used.** Normal mode uses Vim's `iw`, which follows `'iskeyword'`. To target something else, use visual mode or an operator with a motion (`<leader>mBiW` for a WORD).

**Another plugin's key conflicts with `<leader>m`.** Change `keymaps.prefix`, or disable the defaults and map your own (see [Custom keymaps and Lua API](#custom-keymaps-and-lua-api)).

---

## Roadmap

Implementation follows [SPEC.md](SPEC.md) §12. Each item links to its spec section.

| # | Feature | Highlights | Status |
|---|---|---|---|
| 1 | Skeleton | `setup()`, config, buffer attach, `:Mdtools`, health | ✅ Done |
| 2 | Inline formatting (§6) | italic, bold, strike, code, highlight | ✅ Done |
| 3 | Links (§7) | `<leader>ml` from clipboard or prompt; bare URL → `[Page Title](url)`; remove link keeps text; smart `p` | ⏳ Next |
| 4 | Follow (§8) | `gx` for URLs, `.md` files (created if missing), `#anchors`, images, footnotes | ⏳ Planned |
| 5 | Lists & headings (§9.1–9.2) | `<CR>` continuation, `<Tab>` nesting, checkbox toggle, auto-renumber, promote/demote headings | ⏳ Planned |
| 6 | Code fences & footnotes (§9.3, §9.5) | fence with typed language; `[^n]` insert and jump | ⏳ Planned |
| 7 | Tables (§9.4) | create, CSV → table, row/column edit, cell navigation, align on leaving insert mode | ⏳ Planned |
| 8 | TOC & diagnostics (§9.6, §10) | auto-updating TOC between markers; broken link/anchor/footnote warnings on save | ⏳ Planned |
| — | Image paste (§13.1) | clipboard images → file + `![](path)` | 💤 Parked |
| — | Insert-mode formatting keys (§13.2) | `**\|**` pairs while typing | 💤 Parked |

Out of scope: wiki-style `[[links]]` and rendering or preview. Use `render-markdown.nvim` or `markview.nvim` for rendering.

---

## Development

### Running the tests

```sh
make test
# or with a specific binary
make test NVIM=/path/to/nvim
```

The suite starts a headless Neovim with `tests/minimal_init.lua`, sets `<Space>` as leader, and **feeds real keystrokes through the mappings**. The tests therefore cover the keymaps, operators, dot-repeat and undo, not just the internal functions.

A test case is one table row in `tests/format_spec.lua`:

```lua
{ "bold toggles off", { "hello **world**" }, { 1, 9 }, " mb", { "hello world" }, { 1, 7 } },
--  name              buffer before         cursor   keys   buffer after       cursor after (optional)
```

Keys can be a list of strings to feed in separate chunks, for example `{ " mb", " mi", "u" }`.

### Design notes

- **Treesitter first.** Span detection uses `markdown_inline` nodes (`emphasis`, `strong_emphasis`, `strikethrough`, `code_span`). Code detection uses `markdown` block nodes (`fenced_code_block`, `indented_code_block`, `html_block`). Highlight (`==`) is not in the grammar, so it uses a line scan.
- **Operators everywhere.** Normal, visual and operator mappings all go through `g@` and `operatorfunc`. That is what makes `.` work without depending on vim-repeat.
- **Bottom-up edits.** Multi-line toggles are applied from the last line up so row numbers stay valid. An edit tracker keeps the cursor on the same character through the column shifts.
- **One undo step.** An explicit undo break starts each action, because API edits would otherwise merge with the previous change.

---

## Project layout

```
mdtools.nvim/
├── plugin/mdtools.lua        :Mdtools command
├── lua/mdtools/
│   ├── init.lua              setup(), attaches to markdown buffers
│   ├── config.lua            defaults, merge, validation
│   ├── keymaps.lua           buffer-local mappings + which-key group
│   ├── format.lua            formatting toggle engine
│   ├── ts.lua                Treesitter helpers
│   ├── util.lua              prefixes, edit tracker, undo, notify
│   └── health.lua            :checkhealth mdtools
├── tests/
│   ├── minimal_init.lua
│   ├── helpers.lua           key-feeding test runner
│   └── format_spec.lua       formatting cases
├── SPEC.md                   full design and decisions
├── Makefile
└── README.md
```
