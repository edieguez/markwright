# mdtools.nvim

Markdown editing for Neovim that feels native: one key adds a format, the same key removes it. It works on the word under the cursor, on a visual selection or with any motion. It also understands the Markdown structure through Treesitter instead of guessing with regular expressions.

Built for LazyVim, and it works with any Neovim ≥ 0.10 setup.

> **Status: early development.** Inline formatting and links are complete and tested. `gx` following, lists, headings, tables, footnotes, TOC and diagnostics are designed (see [SPEC.md](SPEC.md)) and are being implemented in that order. See [Roadmap](#roadmap).

---

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Keymaps](#keymaps)
- [Inline formatting in detail](#inline-formatting-in-detail)
- [Links in detail](#links-in-detail)
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

**Links** (`<leader>ml`) follow the same toggle idea:

- **On a word or selection** it wraps the text as `[text](url)`. The URL comes from the clipboard if it holds one; otherwise you're prompted.
- **On a bare URL** it turns the URL into `[Page Title](url)`, fetching the title in the background.
- **On an existing link** it removes the link and keeps the text.
- **Smart paste.** `p` with a URL over a selection makes a link; `p` of a bare URL in normal mode inserts a titled link. Anything else pastes normally.

### Coming next

`gx` link following, list continuation, checkboxes, heading levels, code fences, tables, footnotes, TOC and broken-link diagnostics. Details are in [Roadmap](#roadmap).

---

## Requirements

| Requirement | Why |
|---|---|
| Neovim **≥ 0.10** | Modern Treesitter API, `vim.system`, `vim.ui.open` |
| Treesitter parsers **`markdown`** and **`markdown_inline`** | Structure detection. Bundled with Neovim 0.10+ and also installed by LazyVim's markdown extra |
| `curl` *(optional)* | Fetching page titles for links. Preinstalled on macOS; without it, links use the domain name as text |
| A clipboard provider *(optional)* | Creating links from a copied URL. Built in on macOS (`pbcopy`/`pbpaste`) |

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

For links, copy a URL in your browser, then:

```
<leader>ml      link the word           docs  →  [docs](https://copied.url)
vip<leader>ml   link the selection
<leader>ml      on a bare URL           https://neovim.io  →  [Neovim — hyperextensible…](https://neovim.io)
<leader>ml      on a link: remove it    [docs](https://…)  →  docs
viwp            paste URL over a word   here  →  [here](https://copied.url)
```

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
| `<leader>ml` | normal, visual | **Link**: create, convert a bare URL, or remove |
| `p` | visual | Paste; a URL over the selection makes `[selection](url)` |
| `p` / `P` | normal | Paste; a bare URL becomes `[Page Title](url)` |

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

## Links in detail

### What `<leader>ml` does

The link key looks at what's under the cursor (or selected) and picks one action:

| Target | Result |
|---|---|
| Existing link (inline, reference, collapsed, shortcut, `<autolink>`) | **Remove** the link, keep the text: `[text](url)` → `text`, `<url>` → `url` |
| Bare URL (`https://…`, `www.…`, `mailto:…`) | **Convert** to `[Page Title](url)` |
| Word or selection, clipboard holds a URL | **Wrap** immediately: `[text](url)` |
| Word or selection, clipboard has no URL | **Prompt** for the URL, then wrap. Relative paths like `./notes.md` are accepted |
| Whitespace or empty line | **Prompt** for the URL, then for the text. Empty text means "use the page title" |
| Image `![alt](src)` | Nothing (warning): images aren't links |
| Inside code | Nothing (warning) |

Removal works from anywhere in the link: the text, the brackets or the URL part.

```
see docs here        clipboard: https://ex.com/docs    → see [docs](https://ex.com/docs) here
go https://ex.com/a now                                → go [Example A](https://ex.com/a) now
a [text *em*](http://x.io) b                           → a text *em* b
[r][ref]                                               → r
```

### Targets

Like the formatting keys, the link key works on the word under the cursor, on a visual selection and on linewise selections. In a linewise selection, list markers and other prefixes are skipped: `- item text` → `- [item text](url)`. Spaces at the edges of a selection stay outside the brackets.

### Bare URLs and page titles

When the cursor is on a bare URL, the plugin works out where the URL ends. Trailing sentence punctuation (`.`, `,`, `)` and so on) stays outside the link. Parentheses that are part of the URL are kept, so Wikipedia links work:

```
see https://ex.com.                             → see [Title](https://ex.com).
(https://en.wikipedia.org/wiki/Foo_(bar))       → ([Title](https://en.wikipedia.org/wiki/Foo_(bar)))
www.ex.com                                      → [Title](https://www.ex.com)
mailto:me@x.io                                  → [me@x.io](mailto:me@x.io)
```

How the title is filled in:

1. The link is inserted **immediately**, with the domain as a placeholder: `[neovim.io](https://neovim.io)`.
2. `curl` fetches the page in the background. Editing is never blocked.
3. When the title arrives, it replaces the placeholder. The plugin reads `<title>`, falls back to `og:title`, and decodes HTML entities (`&amp;`, `&mdash;`, `&#8212;`…).
4. If the fetch fails or times out (`links.title_timeout_ms`), or you edited or undid the link meanwhile, the placeholder stays as it is.

Brackets in titles are escaped (`\[`, `\]`) so they can't break the link. The link and its title undo together in one `u`. Set `links.fetch_title = false` to always keep the domain as the text.

### Clipboard

The link key reads the system clipboard (the `+` register). On macOS that uses `pbpaste` through Neovim's built-in clipboard provider. If Neovim has no provider, the plugin calls `pbpaste` directly. Set `links.use_clipboard = false` to always be prompted instead.

### Smart paste

`p` and `P` are overridden in Markdown buffers, and fall back to the native commands unless all of these hold:

- the register being pasted holds a **single-line URL**
- it was copied **characterwise** (a yanked line with `yy` pastes normally)
- the cursor isn't inside code or an existing link

| Situation | Result |
|---|---|
| Visual `p` over text with a URL in the register | `[selection](url)` |
| Visual `p` over an existing link | Normal paste |
| Normal `p` / `P` with a URL | `[Page Title](url)` after / before the cursor |
| Normal `p` right after `(` or `<` | Normal paste, so typing `[text](` then `p` works as expected |
| Anything else | Normal paste, with registers (`"ap`) and counts (`3p`) respected |

LazyVim sets `clipboard=unnamedplus`, so a URL copied in the browser is what plain `p` pastes. To keep your `p` untouched, set `links.smart_paste_normal = false` and/or `links.smart_paste_visual = false`.

---

## Commands

| Command | Description |
|---|---|
| `:Mdtools bold` | Toggle bold on the word under the cursor |
| `:Mdtools italic` | Toggle italic |
| `:Mdtools strike` | Toggle strikethrough |
| `:Mdtools code` | Toggle inline code |
| `:Mdtools highlight` | Toggle highlight |
| `:Mdtools link` | Same as `<leader>ml` on the cursor position |
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

  links = {
    use_clipboard = true,           -- link key uses a URL from the clipboard (else prompts)
    fetch_title = true,             -- bare URL → [Page Title](url); false keeps the domain
    title_timeout_ms = 5000,        -- give up on the title after this long
    smart_paste_visual = true,      -- visual p with a URL → [selection](url)
    smart_paste_normal = true,      -- normal p/P with a URL → [Title](url)
  },

  -- The sections below are accepted now and used by upcoming features.
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

Link entry points (all `expr = true` except where noted):

| Function | Use |
|---|---|
| `require("mdtools.links").expr_normal()` | Normal-mode link key |
| `require("mdtools.links").expr_visual()` | Visual-mode link key |
| `require("mdtools.links").expr_paste(after)` | Normal `p` (`after = true`) or `P` (`false`) |
| `require("mdtools.links").expr_paste_visual()` | Visual `p` |
| `require("mdtools.links").is_url(s)` / `url_at(line, col)` | Plain helpers (not mappings) |
| `require("mdtools.title").fetch(url, cb)` | Async title fetch; `cb(title | nil)` runs on the main loop |

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

Warnings for `curl` and the clipboard only affect links: without `curl` the link text is the domain name, and without a clipboard the link key always prompts (on macOS the plugin still tries `pbpaste`).

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

**The link key prompts even though I copied a URL.** The clipboard must hold only the URL, on one line. Check with `:echo getreg('+')`. If it's empty, Neovim can't see the system clipboard: run `:checkhealth provider`.

**Links keep the domain instead of the page title.**
- Run `:checkhealth mdtools` to confirm `curl` is found.
- Some sites block non-browser requests or build their title with JavaScript. The domain is kept in that case.
- A slow site may exceed `links.title_timeout_ms`.
- You can test a URL from the shell with `curl -sL <url> | grep -i '<title'`.

**My `p` behaves differently in Markdown.** Only a single-line URL in the register triggers smart paste; everything else is native. If you use yanky.nvim, mdtools' buffer-local `p`/`P` take priority in Markdown buffers. Disable them with `links.smart_paste_normal = false` and `links.smart_paste_visual = false`.

---

## Roadmap

Implementation follows [SPEC.md](SPEC.md) §12. Each item links to its spec section.

| # | Feature | Highlights | Status |
|---|---|---|---|
| 1 | Skeleton | `setup()`, config, buffer attach, `:Mdtools`, health | ✅ Done |
| 2 | Inline formatting (§6) | italic, bold, strike, code, highlight | ✅ Done |
| 3 | Links (§7) | `<leader>ml` from clipboard or prompt; bare URL → `[Page Title](url)`; remove link keeps text; smart `p` | ✅ Done |
| 4 | Follow (§8) | `gx` for URLs, `.md` files (created if missing), `#anchors`, images, footnotes | ⏳ Next |
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

The suite starts a headless Neovim with `tests/minimal_init.lua`, sets `<Space>` as leader, and **feeds real keystrokes through the mappings**. The tests therefore cover the keymaps, operators, dot-repeat and undo, not just the internal functions. `tests/run.lua` runs every `*_spec.lua` file.

A test case is one table row, for example in `tests/format_spec.lua`:

```lua
{ "bold toggles off", { "hello **world**" }, { 1, 9 }, " mb", { "hello world" }, { 1, 7 } },
--  name              buffer before         cursor   keys   buffer after       cursor after (optional)
```

Keys can be a list of strings to feed in separate chunks, for example `{ " mb", " mi", "u" }`. A case can also carry `setup = function() … end`, run just before the keys. Plain unit checks use `{ "name", fn = function() … end }`.

In `tests/links_spec.lua` the clipboard, `vim.ui.input` and the title fetcher are mocked, so the tests are deterministic and need no network.

### Design notes

- **Treesitter first.** Span detection uses `markdown_inline` nodes (`emphasis`, `strong_emphasis`, `strikethrough`, `code_span`). Code detection uses `markdown` block nodes (`fenced_code_block`, `indented_code_block`, `html_block`). Highlight (`==`) is not in the grammar, so it uses a line scan.
- **Operators everywhere.** Normal, visual and operator mappings all go through `g@` and `operatorfunc`. That is what makes `.` work without depending on vim-repeat.
- **Bottom-up edits.** Multi-line toggles are applied from the last line up so row numbers stay valid. An edit tracker keeps the cursor on the same character through the column shifts.
- **One undo step.** An explicit undo break starts each action, because API edits would otherwise merge with the previous change.
- **Async titles.** A titled link is inserted at once with the domain as a placeholder, tracked by an extmark. When `curl` returns, the placeholder is replaced only if it is still intact, joined to the same undo step with `:undojoin`.
- **Bare URLs** aren't in the `markdown_inline` grammar (no GFM autolink extension), so they're found with a line scan that trims sentence punctuation and balances parentheses.

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
│   ├── links.lua             link key, bare URLs, unlink, smart paste
│   ├── title.lua             async page-title fetching (curl)
│   ├── ts.lua                Treesitter helpers
│   ├── util.lua              prefixes, edit tracker, undo, notify
│   └── health.lua            :checkhealth mdtools
├── tests/
│   ├── minimal_init.lua
│   ├── run.lua               runs every *_spec.lua
│   ├── helpers.lua           key-feeding test runner
│   ├── format_spec.lua       formatting cases
│   └── links_spec.lua        link cases (mocked clipboard/prompt/network)
├── SPEC.md                   full design and decisions
├── Makefile
└── README.md
```
