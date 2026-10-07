# markwright.nvim

[![CI](https://github.com/edieguez/markwright/actions/workflows/ci.yml/badge.svg)](https://github.com/edieguez/markwright/actions/workflows/ci.yml)

Markdown editing for Neovim that feels native: one key adds a format, the same key removes it. It works on the word under the cursor, on a visual selection or with any motion. It also understands the Markdown structure through Treesitter instead of guessing with regular expressions.

Built for LazyVim, and it works with any Neovim setup from 0.10 on (tested on 0.10.0, 0.10.4 and 0.11).

> **Status:** Inline formatting (also while typing), links, `gx`, text objects, heading navigation, callouts, lists and list tools, checkboxes with completion dates and progress counters, headings, code fences, footnotes, tables, TOC, link diagnostics and image paste (macOS) are implemented. A headless test suite covers them and runs in CI on Neovim 0.10.0, stable and nightly, on Linux and macOS. Image paste is macOS only for now. [Issues](https://github.com/edieguez/markwright/issues) are welcome; see [Roadmap](#roadmap) for what's planned.

```lua
-- lazy.nvim / LazyVim
{ "edieguez/markwright", ft = "markdown", opts = {} }
```

---

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Keys markwright changes](#keys-markwright-changes)
- [Quick start](#quick-start)
- [Keymaps](#keymaps)
- [Inline formatting in detail](#inline-formatting-in-detail)
- [Formatting while typing](#formatting-while-typing)
- [Text objects](#text-objects)
- [Links in detail](#links-in-detail)
- [Following links with gx](#following-links-with-gx)
- [Code fences](#code-fences)
- [Footnotes](#footnotes)
- [Tables](#tables)
- [Table of contents](#table-of-contents)
- [Link diagnostics](#link-diagnostics)
- [Lists and checkboxes](#lists-and-checkboxes)
- [Headings](#headings)
- [Heading navigation](#heading-navigation)
- [Callouts](#callouts)
- [Pasting images](#pasting-images)
- [Word count and reading time](#word-count-and-reading-time)
- [Commands](#commands)
- [Configuration](#configuration)
- [Custom keymaps and Lua API](#custom-keymaps-and-lua-api)
- [Health check](#health-check)
- [Troubleshooting](#troubleshooting)
- [Known limitations](#known-limitations)
- [Roadmap](#roadmap)
- [Development](#development)
- [Project layout](#project-layout)
- [License](#license)

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
- **Acts at once, or waits for a motion.** With nothing to choose, the key acts right away: inside a span it removes it, on whitespace it inserts an empty pair. On plain text it's an operator, like `d` or `gu`, and waits for a motion or text object (`<leader>mbiw`, `<leader>mb$`; `_` is the current line, `3<leader>mb_` three lines). Visual mode wraps the selection (charwise, linewise or blockwise). Links work the same way. Block keys (code fence, callout, CSV → table) and inserts (footnote, table, TOC, image) act right away instead.
- **Removes the whole span from anywhere inside it.** The cursor on `world` in `**hello world**` gives `hello world`.
- **Formats nest.** Italic on `**word**` gives `***word***`.
- **Knows Markdown structure.** List markers, checkboxes, `>` and `#` are never wrapped.
- **Skips code.** Nothing gets broken inside code blocks or code spans.
- **Behaves like a native command.** Every action that changes the buffer is dot-repeatable (`.`), reusing the answers to its prompts, and undoes in a single `u`.
- **While typing, too.** In insert mode, type `;;` then `b` for `**|**` (or `i`, `s`, `c`, `h`, `k`). The same keys jump past the closing marker. `;;n` drops a footnote and `;;p` pastes an image without leaving insert mode. There's no delay on normal `;` typing, and it works in any terminal.
- **Text objects.** `cik` changes a link's text, `yiu` copies its URL, `da#` deletes a section, `ciz` a table cell, `dax` a list item with its children, `dif` a code block's content, `ci*` the text inside `**…**`.

**Links** follow the same idea. `<leader>mk` acts at once on a link, a bare URL or whitespace, and waits for a motion on plain text (`<leader>mkiw`, `<leader>mk$`):

- **On text (with a motion) or a selection** it wraps the text as `[text](url)`. The URL comes from the clipboard if it holds one; otherwise you're prompted.
- **On whitespace or an empty line** it inserts a new link: it asks for the URL (prefilled with the clipboard URL, so Enter accepts it), then for the text (empty = the page title).
- **On a bare URL** it turns the URL into `[Page Title](url)`, fetching the title in the background.
- **On an existing link** it removes the link and keeps the text.
- **Smart paste.** `p` with a URL over a selection makes a link; `p` of a bare URL in normal mode inserts a titled link. Anything else pastes normally.

**Navigation and structure:**

- **`gx` follows anything.** It opens URLs, opens local `.md` files (creating missing ones) and images, jumps to `#anchors` (including `file.md#anchor`), resolves reference links, and jumps between a footnote and its definition. `<C-o>` takes you back.
- **Code fences** (`<leader>mf`): wrap the paragraph under the cursor or the selected lines in a fence, or get an empty block on an empty line; you type the language.
- **Footnotes** (`<leader>mn`): inserts `[^n]` with the next number, adds the definition at the end of the file and puts you there.
- **Tables** (`<leader>mt…`):
  - create from a `rows x cols` size, or convert CSV/TSV lines (the paragraph under the cursor, or a selection), and back to CSV
  - add rows and columns with `h`/`j`/`k`/`l` (left / below / above / right), move them with `H`/`J`/`K`/`L`, and delete them
  - sort by a column, transpose, and copy as CSV to the clipboard
  - `<Tab>`/`<S-Tab>` move between cells
  - columns realign when you leave insert mode, accounting for accents, CJK text and alignment markers
- **Table of contents** (`<leader>mO`): a nested list of heading links between `<!-- toc -->` markers, updated on every save.
- **Link diagnostics:** on save, broken file links, missing anchors, undefined references and orphan footnotes show up as warnings. `:Markwright check urls` checks external links too, on demand.
- **Lists:**
  - `<CR>` and `o`/`O` continue a list (bullets, numbers, checkboxes); `<CR>` on an empty item ends it.
  - `<Tab>`/`<S-Tab>` nest and un-nest items together with their children.
  - Ordered lists renumber themselves.
  - `<leader>ml…` moves an item with its children, sorts a list, and converts lines to bullets, numbers or checkboxes and back.
- **Checkboxes:**
  - **`<CR>` in normal mode** toggles `[ ]` ↔ `[x]`, and adds a checkbox to a plain list item.
  - Checking an item stamps when it was done (`✅ 2026-10-02 15:52`); unchecking removes the stamp.
  - `[/]` or `[%]` on a parent item, a heading or a line above a checklist fills in its progress: `[2/3]`, `[66%]`.
- **Heading navigation:** `]]`/`[[` jump between headings, `][`/`[]` between headings of the same level, `[u` to the parent, and `<leader>mo` opens an outline to pick from.
- **GitHub callouts:** `<leader>ma` wraps a paragraph in `> [!NOTE]` (or TIP, IMPORTANT, WARNING, CAUTION), changes the type of an existing one (same picker), and `<leader>mA` removes it.
- **Headings:** `<leader>m=` adds a `#`, `<leader>m-` removes one. They take counts and convert setext headings.
- **Sections:** `<leader>m#j`/`<leader>m#k` move a section (heading, text and sub-sections) past its sibling; `<leader>m#=`/`<leader>m#-` add or remove a `#` on the heading and all its sub-headings.
- **Image paste** (`<leader>mp`, macOS): saves a screenshot, copied image or Finder file into `assets/` next to the file and inserts `![alt](assets/name.png)`. `<leader>mP` on an image renames its file on disk and updates the links.
- **Word count and reading time:** `:Markwright stats`, or a statusline component that shows the words in the document or the selection.

### Not yet available

Image paste on Linux and WSL, a `:help` file and more are planned. See [Roadmap](#roadmap).

---

## Requirements

| Requirement | Why |
|---|---|
| Neovim **≥ 0.10** (tested on 0.10.0, 0.10.4 and 0.11) | Modern Treesitter API, `vim.system`, `vim.ui.open` |
| Treesitter parsers **`markdown`** and **`markdown_inline`** | Structure detection. Bundled with Neovim 0.10+ and also installed by LazyVim's markdown extra |
| `curl` *(optional)* | Fetching page titles for links. Preinstalled on macOS; without it, links use the domain name as text |
| A clipboard provider *(optional)* | Creating links from a copied URL. Built in on macOS (`pbcopy`/`pbpaste`) |
| macOS *(for image paste)* | Image paste uses `osascript` (built in) or `pngpaste` if installed. Other platforms: planned |

Run `:checkhealth markwright` to verify everything.

---

## Installation

markwright needs `setup()` to be called (it registers the Markdown autocommands). With lazy.nvim, `opts = {}` does that for you; with other managers, call `require("markwright").setup()` yourself.

### lazy.nvim / LazyVim

Create `~/.config/nvim/lua/plugins/markwright.lua`:

```lua
return {
  {
    "edieguez/markwright",
    ft = "markdown", -- load when a Markdown file opens
    opts = {
      -- your options, see Configuration; {} uses the defaults
    },
  },
}
```

To stay on tagged releases instead of the latest commit on `master`, add `version = "*"` (lazy.nvim then uses the newest `v*` tag).

### mini.deps

```lua
MiniDeps.add({ source = "edieguez/markwright" })
require("markwright").setup()
```

### packer.nvim

```lua
use({
  "edieguez/markwright",
  config = function()
    require("markwright").setup()
  end,
})
```

### vim-plug

```vim
Plug 'edieguez/markwright'
" after plug#end():
lua require("markwright").setup()
```

### Native packages (no plugin manager)

```sh
git clone https://github.com/edieguez/markwright \
  ~/.local/share/nvim/site/pack/plugins/start/markwright
```

Then add `require("markwright").setup()` to your `init.lua`.

### Verifying the install

1. Open a Markdown file.
2. `:checkhealth markwright` shows Neovim, the Treesitter parsers and the optional tools.
3. `<leader>m` opens the which-key **markdown** group (if you use which-key), and `<leader>mbiw` on a word makes it bold.

### Updating

With lazy.nvim, `:Lazy update markwright`. What changed in each release is in [CHANGELOG.md](CHANGELOG.md); every change is in the [commit history](https://github.com/edieguez/markwright/commits/master).

---

## Keys markwright changes

Besides the `<leader>m…` keys, markwright maps a few everyday keys **in Markdown buffers only**. Each one does something extra in a specific place and behaves exactly as before everywhere else (it calls whatever mapping existed before, such as blink.cmp or mini.pairs, or the built-in key):

| Key                                                | Mode                             | Extra behavior                                                                                                                                             | Only when                                                          | Turn off with                                                               |
| -------------------------------------------------- | -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| `<CR>`                                             | normal, visual                   | Toggle checkboxes                                                                                                                                          | On a list item                                                     | `lists.checkbox_key = ""`                                                   |
| `<CR>`                                             | insert                           | **Continue the list or blockquote** (native `<CR>` elsewhere)                                                                                              | On a list item or a `>` line, no completion menu open              | `lists.continue_on_enter = false` / `blockquotes.continue_on_enter = false` |
| `o` / `O`                                          | normal                           | Start a new list item or `>` line                                                                                                                          | On a list item or a `>` line                                       | `lists.continue_on_enter = false` / `blockquotes.continue_on_enter = false` |
| `<Tab>` / `<S-Tab>`                                | insert                           | Next/previous table cell; nest/un-nest list item                                                                                                           | In a table or on a list item, no completion menu or snippet active | `lists.tab_indent = false` (lists)                                          |
| `p` / `P`                                          | normal, visual                   | Paste a URL as a link                                                                                                                                      | The register holds a single URL                                    | `links.smart_paste_normal = false`, `links.smart_paste_visual = false`      |
| `gx`                                               | normal                           | Follow anchors, local files, footnotes, references                                                                                                         | On a link or footnote (otherwise the default `gx`)                 | `follow.key = ""`                                                           |
| `ik` `iu` `ic` `if` `i#` `iz` `ix` `i*` (and `a…`) | operator-pending, visual         | Markdown text objects (see [Text objects](#text-objects)); `ic`, `if`, `iu` replace mini.ai's class / function / function-call objects in Markdown buffers | Always, in Markdown buffers                                        | `textobjects = { enabled = false }` or per object                           |
| `]]` `[[` `][` `[]` `[u`                           | normal, visual, operator-pending | Heading navigation (see [Heading navigation](#heading-navigation)); replaces the markdown ftplugin's `]]`/`[[`                                             | Always, in Markdown buffers                                        | `nav = { enabled = false }` or per key                                      |
| `;`                                                | insert                           | `;;` + letter formats while typing                                                                                                                         | Right after typing `;` (a single `;` is never delayed)             | `insert.trigger = ""`                                                       |

To opt out of every default key at once, set `keymaps = { enabled = false }` and map only what you want (see [Custom keymaps and Lua API](#custom-keymaps-and-lua-api)).

---

## Quick start

Open a Markdown file, put the cursor on a word and try. On plain text the formatting keys are operators, like `d` or `gu`: they wait for a motion or a text object. Inside a formatted span or on whitespace they act at once.

```
<leader>mbiw    bold the word           hello  →  **hello**
<leader>mb      inside: remove it       **hello**  →  hello
<leader>miiw    italic                  hello  →  *hello*
<leader>mc$     code to end of line     say hi there  →  say `hi there`
<leader>mb2e    bold the next 2 words   one two three  →  **one two** three
<leader>mb_     bold the whole line     - task  →  - **task**
viw<leader>mc   inline code (visual)    hello  →  `hello`
.               repeat the last toggle
u               undo it (one step)
<leader>mb      on an empty line        →  **|**  (insert mode between the markers)
```

While typing, you don't need to leave insert mode:

```
typed exactly:   ;;bbold;;b           →  **bold**|      (;;b opens the pair, ;;b again jumps out)
                 ;;kdocs;;kurl;;k     →  [docs](url)|
```

For links, copy a URL in your browser, then:

```
<leader>mkiw    link the word           docs  →  [docs](https://copied.url)
<leader>mk$     link to end of line     read the docs  →  [read the docs](https://copied.url)
vip<leader>mk   link the selection
<leader>mk      on a bare URL           https://neovim.io  →  [Neovim — hyperextensible…](https://neovim.io)
<leader>mk      on a link: remove it    [docs](https://…)  →  docs
<leader>mk      on an empty line        →  [text](https://copied.url)  (Enter accepts the copied URL; empty text = page title)
viwp            paste URL over a word   here  →  [here](https://copied.url)
```

And for structure:

```
gx              follow the link, anchor or footnote under the cursor (<C-o> to come back)
<leader>mf      fence the paragraph (asks for the language); on an empty line, an empty block
<leader>ma      wrap the paragraph in a callout (pick NOTE, TIP, …)
<leader>mn      footnote: inserts [^1], jumps to its definition
<leader>mtt     new table (asks for rows x cols); <Tab> moves between cells
<leader>mO      insert or refresh the table of contents
```

And for lists and headings:

```
- [ ] buy milk  <CR> (normal)     →  - [x] buy milk
1. first        A<CR>             →  1. first
                                     2. |
- child         i<Tab>            →    - child      (nested under the item above)
Title           <leader>m=        →  # Title       (again: ## Title; <leader>m- goes back)
```

And images (take a screenshot with ⌘⇧⌃4 first):

```
<leader>mp      name it "login"   →  ![login](assets/login.png)   (file saved in ./assets/)
```

---

## Keymaps

Keymaps are **buffer-local** and only exist in Markdown buffers (see `filetypes` in [Configuration](#configuration)). The prefix defaults to `<leader>m`. With LazyVim's default leader that is `Space m`.

| Keys                                               | Mode                             | Action                                                                                                      | Mnemonic                                                  |
| -------------------------------------------------- | -------------------------------- | ----------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| `<leader>mi`                                       | normal                           | Toggle **italic** (on plain text, + motion: `<leader>miiw`)                                                 | **i**talic                                                |
| `<leader>mb`                                       | normal                           | Toggle **bold** (`<leader>mbiw`, `<leader>mb_`)                                                             | **b**old                                                  |
| `<leader>ms`                                       | normal                           | Toggle **strikethrough**                                                                                    | **s**trike                                                |
| `<leader>mc`                                       | normal                           | Toggle **inline code**                                                                                      | **c**ode                                                  |
| `<leader>mh`                                       | normal                           | Toggle **highlight**                                                                                        | **h**ighlight                                             |
| `<leader>mi` `mb` `ms` `mc` `mh`                   | visual                           | Toggle the format on the selection                                                                          | Same letters                                              |
| `;;` then `i` `b` `s` `c` `h` `k` `n` `p`          | insert                           | **Formatting while typing**: open a pair or jump out of it; footnote, image                                 | Same letters as `<leader>m…`                              |
| `<leader>mk`                                       | normal                           | **Link**: create, convert a bare URL, or remove (`<leader>mkiw` on text)                                    | lin**k** (`l` is the list menu)                           |
| `<leader>mk`                                       | visual                           | **Link** the selection, or remove the link it's in                                                          | lin**k** (`l` is the list menu)                           |
| `<leader>mr`                                       | normal, visual                   | **Link**: inline `[text](url)` ↔ reference `[text][label]` (visual: every link in the selection)            | **r**eference                                             |
| `]]` / `[[` · `][` / `[]` · `[u`                   | normal, visual, operator-pending | Next / previous heading · same-level heading · parent heading                                               | Vim's `]]` / `[[`; **u**p                                 |
| `<leader>mo`                                       | normal                           | **Outline**: pick a heading to jump to                                                                      | **o**utline                                               |
| `<leader>ma`                                       | normal                           | **Callout**: wrap the paragraph, or change the type of the one under the cursor                             | GitHub **a**lert (callout)                                |
| `<leader>ma`                                       | visual                           | **Callout**: wrap the selected lines                                                                        | GitHub **a**lert (callout)                                |
| `<leader>mA`                                       | normal                           | Remove the callout                                                                                          | Uppercase: the reverse of `a`                             |
| `ik` `iu` `ic` `if` `i#` `iz` `ix` `i*` (and `a…`) | operator-pending, visual         | **Text objects** (see below)                                                                                | See [Text objects](#text-objects)                         |
| `p`                                                | visual                           | Paste; a URL over the selection makes `[selection](url)`                                                    | —                                                         |
| `p` / `P`                                          | normal                           | Paste; a bare URL becomes `[Page Title](url)`                                                               | —                                                         |
| `gx`                                               | normal                           | **Follow** link, anchor, file, image or footnote                                                            | Vim's `gx`                                                |
| `<leader>mf`                                       | normal                           | **Code fence**: wrap the paragraph, or insert an empty block on an empty line                               | **f**ence                                                 |
| `<leader>mf`                                       | visual                           | Wrap the selected lines in a code fence                                                                     | **f**ence                                                 |
| `<leader>mn`                                       | normal                           | Insert a **footnote**                                                                                       | foot**n**ote                                              |
| `<leader>mtt`                                      | normal                           | Create a **table**                                                                                          | **t**able, **t**able                                      |
| `<leader>mtc`                                      | normal, visual                   | Convert CSV/TSV lines to a table (the paragraph under the cursor, or the selection)                         | **C**SV → table                                           |
| `<leader>mtC`                                      | normal                           | Convert the table under the cursor to CSV (asks for the separator)                                          | Uppercase: the reverse of `c`                             |
| `<leader>mth` / `<leader>mtl`                      | normal                           | Add a column left / right                                                                                   | `h` / `l`: left / right, as in Vim                        |
| `<leader>mtj` / `<leader>mtk`                      | normal                           | Add a row below / above                                                                                     | `j` / `k`: down / up, as in Vim                           |
| `<leader>mtdr` / `<leader>mtdc`                    | normal, visual                   | Delete the row / column (visual: the selected ones)                                                         | **d**elete **r**ow / **c**olumn                           |
| `<leader>mtH` / `<leader>mtL`                      | normal, visual                   | Move the column left / right                                                                                | Uppercase `h` / `l`: move instead of add                  |
| `<leader>mtJ` / `<leader>mtK`                      | normal, visual                   | Move the row down / up                                                                                      | Uppercase `j` / `k`: move instead of add                  |
| `<leader>mts` / `<leader>mtS`                      | normal, visual                   | Sort by the column under the cursor, ascending / descending                                                 | **s**ort; uppercase reverses                              |
| `<leader>mtf`                                      | normal                           | **Flip**: transpose rows ↔ columns                                                                          | **f**lip                                                  |
| `<leader>mty`                                      | normal                           | Copy the table as CSV to the clipboard                                                                      | **y**ank, as in Vim                                       |
| `<leader>mta`                                      | normal                           | Align the table now                                                                                         | **a**lign                                                 |
| `<Tab>` / `<S-Tab>`                                | insert                           | Next / previous table cell; nest / un-nest a list item (native `<Tab>` elsewhere)                           | —                                                         |
| `<leader>mO`                                       | normal                           | Insert or update the **table of contents**                                                                  | Uppercase `o`: the outline, written into the file         |
| `<CR>`                                             | normal                           | **Toggle checkbox** on a list item (native `<CR>` elsewhere)                                                | —                                                         |
| `<CR>`                                             | visual                           | Check all list items in the selection (or uncheck if all are checked)                                       | —                                                         |
| `<CR>`                                             | insert                           | **Continue the list** (native `<CR>` elsewhere)                                                             | —                                                         |
| `o` / `O`                                          | normal                           | Open a line below / above; continues lists and blockquotes                                                  | —                                                         |
| `<leader>mlJ` / `<leader>mlK`                      | normal                           | **Move** the list item down / up, with its children                                                         | `J` / `K`: down / up, like `j` / `k`                      |
| `<leader>mls` / `<leader>mlS` / `<leader>mld`      | normal                           | **Sort** the list A→Z / Z→A / done items last                                                               | **s**ort; uppercase reverses; **d**one last               |
| `<leader>mlb` / `<leader>mln` / `<leader>mlc`      | normal, visual                   | Convert to bullets / numbers / checkboxes: the cursor's level (uppercase `B` `N` `C`: that level and below) | **b**ullets, **n**umbers, **c**heckboxes                  |
| `<leader>m=`                                       | normal, visual                   | **Heading**: add a `#` (count works: `2<leader>m=`)                                                         | `=` is `+` without Shift: add                             |
| `<leader>m-`                                       | normal, visual                   | **Heading**: remove a `#`                                                                                   | `-`: remove                                               |
| `<leader>m#j` / `<leader>m#k`                      | normal                           | **Move the section** (heading, text and sub-sections) down / up past its sibling                            | `#` section (as in `i#`); `j` / `k`: down / up, as in Vim |
| `<leader>m#=` / `<leader>m#-`                      | normal                           | **Section**: add / remove a `#` on the heading and all its sub-headings                                     | `=` / `-` like `<leader>m=` / `<leader>m-`                |
| `<leader>mp`                                       | normal                           | **Paste image** from the clipboard (macOS)                                                                  | **p**aste, as in Vim                                      |
| `<leader>mp`                                       | visual                           | Paste image; the selection becomes the alt text                                                             | **p**aste, as in Vim                                      |
| `<leader>mP`                                       | normal                           | **Rename** the image file under the cursor (on disk) and update its links                                   | Uppercase `p`: on a pasted image                          |

**Operator examples** (on plain text, the key waits for one of these):

| Keys           | Acts on                                                                         |
| -------------- | ------------------------------------------------------------------------------- |
| `<leader>mbiw` | inner word                                                                      |
| `<leader>mbiW` | inner WORD (`foo.bar/baz`)                                                      |
| `<leader>mb2e` | to the end of the second word                                                   |
| `<leader>mc$`  | to the end of the line                                                          |
| `<leader>mb_`  | the current line, without its list marker, checkbox, `#` or `>`                 |
| `3<leader>ms_` | three lines, each wrapped on its own                                            |
| `<leader>mbip` | the whole paragraph, wrapped line by line                                       |
| `<leader>mii"` | inside the quotes                                                               |
| `<leader>mbik` | the text of the next link (markwright's [text objects](#text-objects) work too) |
| `<leader>mkiw` | link the word                                                                   |

The key acts at once, without a motion, when there's nothing to choose: inside a span of that format (it removes the span, from anywhere inside it, markers included), inside code (warning), or on whitespace (empty pair). `_` means "the current line" for every markwright operator, just as `d_` does for `d`. Keys are never doubled: `<leader>mbb` is `<leader>mb` followed by the `b` motion, and `<leader>mii…` starts an `i…` text object (`<leader>miiw`).

If which-key is installed (it is in LazyVim), the prefix is registered as a **markdown** group, with `<leader>mt` (**table**), `<leader>mtd` (**delete**), `<leader>ml` (**list**) and `<leader>m#` (**section**) as subgroups, so the keys show up in the popup.

### How the keys are organized

The keys follow a few rules, so most of them can be guessed:

- **One letter, from the action's name.** Under `<leader>m`: **i**talic, **b**old, **s**trike, **c**ode, **h**ighlight, lin**k**, **r**eference link, **f**ence, foot**n**ote, c**a**llout (GitHub calls them **a**lerts), **o**utline, **p**aste image.
- **Uppercase is the companion of the lowercase key:** its reverse (`A` removes a callout, `tC` turns a table back into CSV, `S` sorts Z→A), a stronger version (`O` writes the outline into the file as a TOC; `lB` `lN` `lC` also convert the sub-lists), or the same object acted on differently (`P` renames a pasted image; `tH` `tJ` `tK` `tL` move instead of add).
- **Submenus group related tools:** `<leader>mt…` for **t**ables, `<leader>ml…` for **l**ists, `<leader>m#…` for sections (`#`, as in the `i#` text object). Inside a submenu a letter has its own meaning: `<leader>mtc` is **C**SV, not code.
- **Vim's own keys keep their meaning:** `h` `j` `k` `l` are left, down, up, right; `J` / `K` move down / up in tables and lists, where `j` / `k` add rows (the section menu adds nothing, so there `j` / `k` move); `y` yanks; `d` deletes (`<leader>mtdr`, `<leader>mtdc`); `_` is the current line.
- **A letter keeps its meaning across normal mode, insert mode and text objects:** `c` is inline code in `<leader>mc`, `;;c` and `ic`; `f` is a code fence in `<leader>mf` and `if`; `k` is a link in `<leader>mk`, `;;k` and `ik`; `n` is a footnote in `<leader>mn` and `;;n`; `p` pastes an image in `<leader>mp` and `;;p`.

The text objects use the same letters where they can: `ik` link, `iu` **U**RL, `ic` code, `if` fence, `i#` heading section, `iz` table cell ("**z**ell", since `c` is code), `ix` list item (the **x** in `- [x]`), `i*` emphasis.

### Repeating with `.`

Every `<leader>m…` key that changes the buffer repeats with `.`, from the new cursor position, as one undo step each:

```
<leader>mtk  .  .      three new rows above the cursor's row
<leader>mlJ  .         move the item down twice
<CR>  j.  j.           check three items in a row
<leader>mk  f[.        remove this link, then the next one
```

- **Counts work as in Vim:** `2<leader>mtJ` then `.` moves the row two more places, and a count on `.` replaces the original one: `<leader>mtJ` then `3.` moves it three places, and later `.` keep using 3.
- **Visual mode** repeats over as many lines as were selected, starting at the cursor: `Vj<leader>m=` then `jj.` makes the next two lines headings as well.
- **Answers are reused:** `.` doesn't ask again what the first run asked. A callout repeats with the type you picked, CSV → table with the same separator, a code fence around a selection with the same language, a new link on an empty line with the same URL and text. A repeat only asks what it needs and doesn't know yet, such as the checklist question of a list conversion the first run didn't need.
- **Not repeatable:** keys that put you in insert mode or create something from a prompt (`<leader>mf` on an empty line, `<leader>mn` in normal mode, `<leader>mtt`, `<leader>mp`, `<leader>mP`, `<leader>mO`), and keys that don't change the buffer (`<leader>mo`, `<leader>mty`, `gx`). After the insert-mode ones, `.` repeats the text you typed, as with Vim's own `o`.

---

## Inline formatting in detail

### What gets targeted

| Mode                                          | Target                                                                                    |
| --------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Normal, cursor inside a span of that format   | The span: it's removed at once, no motion                                                 |
| Normal, cursor on whitespace or an empty line | Nothing to wrap: inserts an empty pair and enters insert mode between the markers         |
| Normal, key + motion or text object           | The motion's range (`<leader>mbiw`: the word, so `snake_case_word` stays one word)        |
| Normal, key + `_` (`<leader>mb_`)             | The current line, `[count]` lines with a count (see [Multi-line](#multi-line-selections)) |
| Visual charwise (`v`)                         | The selection                                                                             |
| Visual linewise (`V`)                         | Each selected line (see [Multi-line](#multi-line-selections))                             |
| Visual blockwise (`<C-v>`)                    | The block's columns on each line                                                          |

### Toggle rules

For each piece of text, the plugin decides in this order:

1. **Inside code?** If the text is in a fenced or indented code block, or in a code span, it does nothing and shows a warning. The exception is the inline-code key, which removes the code span it is in.
2. **Inside a span of that format?** It removes the whole span, wherever the cursor or selection is inside it.
3. **Otherwise** it wraps the text with the configured marker.

Removal works whichever cursor position you use:

```
**hello world**      cursor on "world"   <leader>mbiw  →  hello world
**hello world**      cursor on "**"      <leader>mbiw  →  hello world
x **bold** y         select "bold"       <leader>mb    →  x bold y
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
**word**     <leader>miiw  →  ***word***
***word***   <leader>mbiw  →  *word*
***word***   <leader>miiw  →  **word**
```

### Multi-line selections

Markdown emphasis cannot span blank lines, so a multi-line target (`V`, `<leader>mb_`, `3<leader>mb_`, `<leader>mbip`, …) is wrapped **line by line**:

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

### Empty markers

With the cursor on whitespace or an empty line in normal mode, the key inserts an empty pair and starts insert mode between the markers (`:Markwright bold` does the same; while typing, use [`;;`](#formatting-while-typing)). A separating space is added if the next character would touch the closing marker:

```
""       <leader>mb  →  **|**
"foo "   <leader>mi  →  foo *|*
"a b"    <leader>mb  →  a **|** b        (cursor on the space)
```

### Cursor, repeat and undo

- In normal mode, the cursor stays on the same character it was on.
- After a visual toggle, the cursor moves to the start of the text.
- `.` repeats the last toggle with the same motion from the new cursor position (`<leader>mbiw`, `w`, `.` bolds the next word; a removal at once repeats on the span under the new cursor).
- Each toggle is a single undo step, even when it changes many lines.

---

## Text objects

Text objects work with any operator (`d`, `c`, `y`, `>`, `gu`, `<leader>mb`, …) and in visual mode (`v`, `V`). `i` selects the inside, `a` the whole thing:

| Keys        | `i` (inner)                                                           | `a` (around)                                                                    | Mnemonic                   |
| ----------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------- | -------------------------- |
| `ik` / `ak` | link text, image alt text, the URL inside `<…>`                       | the whole link or image                                                         | lin**k**, as `<leader>mk`  |
| `iu`        | the link's URL (for `[text][ref]`, the URL on its `[ref]:` line)      | —                                                                               | **U**RL                    |
| `ic` / `ac` | inline code: its text                                                 | inline code with its backticks                                                  | **c**ode, as `<leader>mc`  |
| `if` / `af` | code block: the lines between the fences                              | the whole block, fences included                                                | **f**ence, as `<leader>mf` |
| `i#` / `a#` | the section's content, without the heading or surrounding blank lines | the heading and everything up to the next heading of the same or a higher level | the heading's `#`          |
| `iz` / `az` | the table cell's text                                                 | the cell including its padding                                                  | "**z**ell" (`c` is code)   |
| `ix` / `ax` | the list item's text, without marker or checkbox                      | the item with its children                                                      | the **x** in `- [x]`       |
| `i*` / `a*` | text inside `*`, `**`, `~~` or `==` (the innermost)                   | including the markers                                                           | the emphasis marker        |

```
cik       change a link's text        see [the docs](url)   →  see [|](url)
yiu       copy a link's URL
dak       delete a link or image
cif       rewrite a code block, keeping its fences
da#       delete a whole section (heading + content + subsections)
ci#       rewrite a section, keeping its heading
ciz       change a table cell (the table realigns when you leave insert mode)
dax       delete a list item and its children
ci*       change the bold/italic text, keep the markers
va*       select an emphasized span, markers included
```

- **Where the cursor can be:** anywhere inside the object. For a link that includes the brackets and the URL; for a section, any line in it, the heading included.
- **Not inside one? The next one is used**, even several lines below, like LazyVim's mini.ai text objects: with the cursor on a paragraph, `cik` changes the next link's text, `ciz` the first cell of the next table, `da#` (before the first heading) the first section. The search looks up to 500 lines ahead (`textobjects.search_lines`) and never backwards; if nothing is found, nothing happens. In visual mode, `vik` moves the selection to that next link.
- **Counts reach outward:** `2a#` is the parent section, `2ax` the parent list item, `2i*` the next enclosing span (in `***x***`, `i*` is inside `**`, `2i*` inside `*`).
- **Empty objects:** `cik` on `[](url)`, or `cif` on an empty code block, starts insert mode at the right spot. `d` and `y` do nothing.
- **Dot-repeat:** `.` repeats the change on the object under the new cursor position (`cikNew<Esc>` then `f[.`).
- **Code:** `ic`/`ac` is inline code and `if`/`af` a code block (fenced or indented), matching `<leader>mc` and `<leader>mf`. Headings inside code blocks never count as sections.
- **Line-wise vs character-wise:** section, code-block and around-list-item objects are line-wise (like `ap`); the others are character-wise.

Change the letters with `textobjects = { link = "k", url = "u", code = "c", fence = "f", section = "#", cell = "z", item = "x", emphasis = "*" }`. Set one to `false` to drop it, or `textobjects = { enabled = false }` to drop all.

> **LazyVim's mini.ai** also defines `ic`/`ac` (class), `if`/`af` (function) and `iu`/`au` (function call). In Markdown buffers markwright's versions take priority; in every other filetype mini.ai's are unchanged. Link text uses `ik` rather than `il` because mini.ai uses `il`/`al` as its "last" prefix (`cil)`).

---

## Formatting while typing

In insert mode, type **`;;`** and then a letter:

| Key | Inserts | Again (cursor before the closing marker) |
|---|---|---|
| `i` | `*\|*` | jumps past `*` |
| `b` | `**\|**` | jumps past `**` |
| `s` | `~~\|~~` | jumps past `~~` |
| `c` | `` `\|` `` | jumps past the backtick |
| `h` | `==\|==` | jumps past `==` |
| `k` | `[\|]()`, or `[\|](url)` when the clipboard holds a URL | 1st: into the `()`; 2nd: past `)` |
| `n` | `[^1]\|`: a footnote reference, with its empty definition added at the end of the file | — (each press adds a new footnote) |
| `p` | `![alt](assets/name.png)\|`: the clipboard image, saved as with [`<leader>mp`](#pasting-images) (macOS) | — |

(`|` is the cursor.) `n` and `p` keep you typing after what they insert: fill in the footnote later with `gx` on the reference, which jumps to its definition.

Keys typed exactly as shown:

```
;;bimportant;;b and ;;ialso;;i this   →   **important** and *also* this
;;kthe docs;;khttps://x.io;;k         →   [the docs](https://x.io)
;;bbold ;;iboth;;i;;b                 →   **bold *both***
```

### How it waits

- **No time limit.** After `;;` the command line shows the options (`i italic · b bold · … · n footnote · p image`) and waits as long as you like for the letter.
- **No lag when typing a single `;`.** The plugin doesn't use a Vim mapping for `;;`, which would pause after every semicolon for `timeoutlen`. Only the second `;` is checked, and only if the first one was typed right before it. An existing `;` you moved the cursor next to doesn't count.
- **Nothing you type is lost.** If the key after `;;` isn't one of the letters, you get `;;` plus that key, exactly as typed: `;;x` stays `;;x`, `;;;` stays `;;;`, and `;;<CR>` inserts `;;` and then does whatever Enter does (including continuing a list). `<Esc>` puts back the `;;` and leaves insert mode normally.

### Jumping out

- **Nesting works.** Each pair remembers where its closing marker is, so pressing the same key again always jumps past the right one, even inside other formats.
- **Pairs typed by hand.** It also works on text you typed yourself: with the cursor right before a closing `**`, `;;b` jumps past it.
- **Links** go in stages: text, then URL, then out. If the clipboard held a URL when you opened the link, the URL stage is skipped.

### Code

- **Code blocks:** the trigger is off, so `for (;;)` or OCaml's `;;` type normally.
- **Inline code:** the trigger only works right before the closing backtick, where the only option is `c` (jump out). Typing `;;` anywhere else inside inline code is literal.

### Choosing another trigger

`insert.trigger` accepts:

- **Any two or more characters:** `;;`, `jj`, `,,`, `qq`… The same no-lag detection applies.
- **A key like `"<C-g>"`:** press it, then the letter. Other keys after it keep their Vim meaning, so `<C-g>u` and `<C-g>j` still work, as do plugin mappings like nvim-surround's `<C-g>s`.
- **`""`:** turns the feature off.

Avoid `<C-m>` (it's Enter in most terminals) and `<C-i>` (it's Tab).

---

## Links in detail

### What `<leader>mk` does

`<leader>mk` acts at once on a link, an image, a bare URL, code or whitespace. On plain text it waits for a motion or text object (`<leader>mkiw`, `<leader>mk$`), and in visual mode it acts on the selection. (`:Markwright link` uses the word under the cursor instead of waiting.) In every case it picks one action:

| Target                                                               | Result                                                                                                                                                                      |
| -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Existing link (inline, reference, collapsed, shortcut, `<autolink>`) | **Remove** the link, keep the text: `[text](url)` → `text`, `<url>` → `url`                                                                                                 |
| Bare URL (`https://…`, `www.…`, `mailto:…`)                          | **Convert** to `[Page Title](url)`                                                                                                                                          |
| Word, range or selection, clipboard holds a URL                      | **Wrap** immediately: `[text](url)`                                                                                                                                         |
| Word, range or selection, clipboard has no URL                       | **Prompt** for the URL, then wrap. Relative paths like `./notes.md` are accepted                                                                                            |
| Whitespace or an empty line                                          | **New link**: prompt for the URL, prefilled with the clipboard URL if it holds one (Enter accepts it, or edit it); then for the text. Empty text means "use the page title" |
| Image `![alt](src)`                                                  | Nothing (warning): images aren't links                                                                                                                                      |
| Inside code                                                          | Nothing (warning)                                                                                                                                                           |

Removal works from anywhere in the link: the text, the brackets or the URL part.

```
see docs here        clipboard: https://ex.com/docs    → see [docs](https://ex.com/docs) here
go https://ex.com/a now                                → go [Example A](https://ex.com/a) now
a [text *em*](http://x.io) b                           → a text *em* b
[r][ref]                                               → r
```

### Targets

Like the formatting keys, the link key takes any motion or text object (`<leader>mkiw`, `<leader>mk$`, `<leader>mk_` for the line) and works on visual selections, linewise ones included. In a linewise selection, list markers and other prefixes are skipped: `- item text` → `- [item text](url)`. Spaces at the edges of a selection stay outside the brackets.

### Inline ↔ reference links

`<leader>mr` on a link switches it between inline and reference style:

```
See [Neovim docs](https://neovim.io) now.      <leader>mr     See [Neovim docs][neovim-docs] now.
                                                   ⇄
                                                              [neovim-docs]: https://neovim.io
```

- **Labels come from the link text**, as a slug (`Neovim docs` → `neovim-docs`). A URL that already has a definition reuses its label, and a label that's taken by another URL gets a suffix (`docs-2`). Titles move with the URL (`[x]: http://u "Title"`).
- **Definitions go at the end of the file**, after the existing reference definitions when the file ends with them, otherwise in a new block after a blank line. Footnote definitions aren't reordered.
- **Back to inline**, the definition is removed once no reference uses it any more.
- Images work the same way (`![alt](src)` ⇄ `![alt][label]`). Collapsed (`[docs][]`) and shortcut (`[docs]`) references are converted too, but only when their label has a definition: a plain `[word]` isn't a link.
- **Visual mode** converts every link in the selected lines: inline links become references; if there are none, references become inline. `:Markwright links reference` / `inline` do the same for the whole file, or a `:range`.
- Each conversion is one undo step and repeats with `.`.

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

## Following links with gx

`gx` in a Markdown buffer looks at what's under the cursor and does the right thing:

| Under the cursor | Action |
|---|---|
| Footnote reference `[^n]` | Jump to its definition `[^n]: …` |
| Footnote definition `[^n]:` | Jump back to the first reference |
| `[text](#anchor)` | Jump to the heading with that anchor |
| `[text](other.md)` | Open the file in a buffer |
| `[text](other.md#anchor)` | Open the file and jump to the heading |
| `[text](missing.md)` | Open a new buffer for it; parent folders are created when you `:w` |
| `[text](notes)` (no extension) | Open `notes.md` if it exists |
| `![alt](pic.png)`, `.pdf`, media | Open with the system viewer (`open` on macOS) |
| `[text](https://…)`, bare URL, `<autolink>`, `www.…` | Open in the browser |
| `<me@x.io>`, `mailto:` | Open the mail client |
| `[text][ref]`, `[ref][]`, `[ref]` | Resolve the `[ref]: url` definition, then follow it |
| A `[ref]: url` definition line | Follow its URL |
| Other schemes (`zotero://`, `obsidian://`, `file://`…) | Hand them to the system opener |
| Anything else | The default `gx`: open the file or URL under the cursor |

Details:

- **Paths** are relative to the current file's folder. Absolute paths and `~` work too, and `%20` style escapes are decoded (`my%20notes.md` → `my notes.md`).
- **Anchors** use GitHub's rules: lowercase, punctuation removed, spaces become `-`, accents kept, and duplicate headings get `-1`, `-2` suffixes. `## Café Olé!` is `#café-olé`, and the second one is `#café-olé-1`. Headings inside code blocks are ignored.
- **Jumps** are added to the jumplist, so `<C-o>` / `<C-i>` move back and forth. That includes jumps into other files.
- **Warnings** appear when the target can't be found (missing anchor, missing image, undefined reference). Nothing moves in that case.

Change the key with `follow.key`, or set it to `""` to keep your own `gx`. Set `follow.create_missing_md = false` to get a warning instead of a new buffer.

---

## Code fences

`<leader>mf` asks for a language (type it; empty is fine, `<Esc>` cancels), then, like `<leader>ma` for callouts:

- **On a paragraph** it wraps the paragraph (the run of non-blank lines around the cursor) in a fence.
- **On an empty line** the line becomes an empty block and you're in insert mode inside it. An empty line inside a container keeps the block in it: an indented line under a list item, or a bare `>` line in a blockquote.
- **In visual mode** it wraps the selected lines.

````
print("hi")     <leader>mf  py  →  ```py
                                   print("hi")
                                   ```

- item                          - item
  |   (indented empty line)  →    ```sh
      <leader>mf  sh               |
                                  ```
````

- **Wrapping** uses the lines' shared indentation and blockquote prefix (`> a` → `> ```py`), and grows to four backticks when the content already contains a ` ``` ` line.
- **Inside a code block** it does nothing (warning).
- **`.`** wraps the next paragraph with the same language. Inserting an empty block ends in insert mode, so there `.` repeats what you typed, as with `o`.

The same is available as `:Markwright fence` (wraps the paragraph or inserts on an empty line), or `:'<,'>Markwright fence` for a range.

---

## Footnotes

`<leader>mn`:

1. Inserts `[^n]` after the cursor. `n` is one more than the highest numbered footnote in the file; named ones like `[^note]` don't affect the numbering.
2. Adds `[^n]: ` at the end of the file, grouped right after existing definitions (or after a blank line if there are none).
3. Jumps there in insert mode so you can type the note.
4. `<C-o>` brings you back to the reference.

```
Text here.       <leader>mn  →   Text here.[^1]

                                 [^1]: |
```

While typing, `;;n` inserts the reference and the definition the same way but leaves the cursor after the reference, so you can finish the sentence first (see [Formatting while typing](#formatting-while-typing)).

### Renumbering

Footnotes added out of order (`[^3]` before `[^1]`, or gaps after deleting one) can be put back in order with `:Markwright footnote renumber`:

```
b[^2] then a[^1]           b[^1] then a[^2]
                    →
[^1]: one                  [^1]: two
[^2]: two                  [^2]: one
```

- **Numbered by first reference:** the first footnote in the text becomes `[^1]`, the next new one `[^2]`, and so on. Every reference and definition is updated.
- **Definitions follow:** definitions that stand together (only blank lines between them, as at the end of a file) are put in the new order, with their continuation lines. A definition on its own elsewhere (say, under its paragraph) is relabeled where it is.
- **Named footnotes** (`[^note]`) keep their name and place. Numbered definitions nobody references are numbered after the referenced ones.
- References inside code are left alone. It's one undo step.

Use `gx` on a reference or definition to jump between them. Link diagnostics warn about references without a definition and definitions nobody references.

---

## Tables

### Creating

- **`<leader>mtt`** asks for a size such as `3x4` (`3 x 4`, `3,4` and `3*4` work too): 3 body rows and 4 columns. The table goes on the current line if it's empty, otherwise below it, and you start typing in the first header cell.
- **`<leader>mtc`** converts the paragraph under the cursor (the block of non-blank lines) to a table; in visual mode, or with `:'<,'>Markwright table csv`, it converts the selected lines. It asks `Separator:`, prefilled with the separator it detects: comma, tab, semicolon, `|` or `:`, choosing the one that splits every line into the same number of columns. Enter accepts it; type any other separator, including multi-character ones like `::` or `; `, or `\t` for a tab; `<Esc>` cancels. Quoted fields (`"Doe, J"`, `""` escapes) are handled, spaces around fields are trimmed, the first line becomes the header, and `|` inside values is escaped.

```
name,age              V<leader>mtc     | name   | age |
"Doe, J",42              →             | ------ | --- |
                                       | Doe, J | 42  |
```

### Back to CSV

**`<leader>mtC`** (or `:Markwright table tocsv`) with the cursor anywhere in a table replaces the table with CSV, the opposite of `<leader>mtc`:

1. It asks `Separator:`, prefilled with `,` (change the default with `tables.csv_separator`). Type any separator: `;`, `|`, or `\t` (or `tab`) for a tab. Enter on an empty prompt uses the default; `<Esc>` cancels.
2. The header and body rows become CSV lines; the delimiter row (and with it the column alignment) is dropped.
3. Fields are quoted when they contain the separator or a `"` (quotes are doubled, as in standard CSV), and `\|` escapes become plain `|`.
4. Short rows are padded with empty fields, so every line has the same number of columns. A table inside a list item keeps its indentation.

```
| name   | note     |    <leader>mtC  ,     name,note
| ------ | -------- |         →             "Doe, J","say ""hi"""
| Doe, J | say "hi" |
```

It's one undo step: `u` brings the table back. Converting CSV → table → CSV returns the original text (apart from quoting normalization).

**`<leader>mty`** (or `:Markwright table yank`) does the same conversion but **copies** the CSV to the clipboard (and the unnamed register) and leaves the table as it is: handy for pasting into a spreadsheet.

### Editing

| Keys               | Action                                                                     |
| ------------------ | -------------------------------------------------------------------------- |
| `<Tab>` (insert)   | Next cell. From the last cell, a new row is added                          |
| `<S-Tab>` (insert) | Previous cell                                                              |
| `<leader>mth`      | Add a column to the left                                                   |
| `<leader>mtj`      | Add a row below; on the header, the row goes below the delimiter           |
| `<leader>mtk`      | Add a row above (not above the header: the first row is always the header) |
| `<leader>mtl`      | Add a column to the right                                                  |
| `<leader>mtdr`     | Delete the current row (not the header or the delimiter)                   |
| `<leader>mtdc`     | Delete the current column (not the last remaining one)                     |
| `<leader>mta`      | Align now                                                                  |

Counts work as with Vim's `o` and `dd`: `3<leader>mtj` adds three rows, `2<leader>mtl` two columns, `2<leader>mtdr` deletes the cursor's row and the one below, `2<leader>mtdc` the cursor's column and the one to its right. The header, the delimiter row and the last column are never deleted.

The navigation skips the delimiter row and puts the cursor at the end of the cell's text.

### Moving, sorting and transposing

| Keys                          | Action                                                                           |
| ----------------------------- | -------------------------------------------------------------------------------- |
| `<leader>mtH` / `<leader>mtL` | Move the column under the cursor left / right; its alignment moves with it       |
| `<leader>mtJ` / `<leader>mtK` | Move the row under the cursor down / up (body rows only: the header stays first) |
| `<leader>mts` / `<leader>mtS` | Sort the body rows by the column under the cursor, ascending / descending        |
| `<leader>mtf`                 | **Flip** (transpose): rows become columns, the first column becomes the header   |

- **Visual mode** acts on the selection: `Vjj<leader>mtdr` deletes the three selected rows, `Vj<leader>mtJ` moves both rows down together, `Vjj<leader>mts` sorts just those rows (the rest of the table stays put), and with a charwise or blockwise selection across cells (`v` or `<C-v>`), `<leader>mtdc` deletes those columns and `<leader>mtH` / `<leader>mtL` move them together. The header and the delimiter row are never moved, sorted or deleted, even when selected.
- **Counts** work for moves: `3<leader>mtJ` moves the row (or the selected rows) three down. The cursor follows the cell it was on.
- **Sorting:** `<leader>mts` sorts ascending and `<leader>mtS` descending (the same `s`/`S` pair as for lists). When every cell in the column is a number, they compare as numbers (`9` before `10`); `$`, `€`, `£`, `¥`, `%`, thousands commas and emphasis markers are ignored. Otherwise the text is compared without case. ISO dates (`2026-10-02`) sort correctly as text. Empty cells always go last, and equal cells keep their order. The cursor can be anywhere in the column, the header included.
- **Transposing** resets the column alignments, since they belonged to the old columns. Transposing twice gives the original table back.

```
| n   |   v |                          | n   |   v |
| --- | --: |    <leader>mts on "v"    | --- | --: |
| b   |  10 |            →             | a   |   9 |
| a   |   9 |                          | b   |  10 |
| c   | 100 |                          | c   | 100 |

then <leader>mtf  →  | n   | a   | b   | c   |
                     | --- | --- | --- | --- |
                     | v   | 9   | 10  | 100 |
```

Each of these is one undo step. `:Markwright table sort [desc]`, `transpose` and `yank` do the same from the command line.

### Alignment

Tables are realigned automatically when you leave insert mode inside one. The realignment joins the same undo step as your typing, so one `u` undoes both. It:

- pads cells so the pipes line up, measuring **display width** so `ñandú` and `日本` line up correctly
- keeps alignment markers and pads accordingly (`:---` left, `:---:` centered, `---:` right)
- adds missing leading and trailing pipes, and fills short rows with empty cells
- keeps `\|` escaped pipes inside cells
- works for tables nested in list items, keeping their indentation
- keeps the cursor in the same cell

Set `tables.align_on_insert_leave = false` to align only with `<leader>mta`.

### `<Tab>` and completion

`<Tab>` in insert mode only moves between cells when the cursor is in a table **and** no completion menu (blink.cmp, nvim-cmp, the built-in popup) or snippet is active. Otherwise it does exactly what it did before markwright: the mapping that existed when the buffer attached is called, or a plain `<Tab>` is inserted. LazyVim's completion and snippet jumping keep working.

---

## Table of contents

`<leader>mO` (the **O**utline, written into the file) inserts a table of contents at the cursor:

```markdown
<!-- toc -->
- [Installation](#installation)
  - [LazyVim](#lazyvim)
- [Usage](#usage)
<!-- tocstop -->
```

- Entries are nested by heading level. The range comes from `toc.min_level` and `toc.max_level` (default: levels 2–4, so the `#` document title is left out).
- Headings in code blocks are skipped. Links inside headings become plain text, so the entries never contain nested links.
- The anchors follow the same GitHub rules as `gx`, including `-1` suffixes for duplicate headings.
- If the markers already exist, `<leader>mO` regenerates the list in place.
- **On every save** the TOC between the markers is refreshed. If nothing changed, the buffer isn't touched. Turn this off with `toc.update_on_save = false`.

The marker text is configurable (`toc.marker_start` / `toc.marker_end`).

---

## Link diagnostics

When a Markdown buffer is opened and every time it's saved, markwright checks its links and shows problems as regular Neovim diagnostics (source `markwright`). They appear in the sign column, `]d`/`[d` navigation, and pickers like Trouble or `<leader>sd`:

| Problem                                     | Example message                     |
| ------------------------------------------- | ----------------------------------- |
| Local file doesn't exist                    | `file not found: missing.md`        |
| `#anchor` has no matching heading           | `no heading for #nope`              |
| Anchor missing in another file              | `no heading #zzz in exists.md`      |
| Missing image                               | `file not found: gone.png`          |
| `[text][ref]` without a `[ref]:` definition | `undefined reference [ref]`         |
| `[^n]` without a definition                 | `no definition for [^n]`            |
| Footnote defined but never used             | `footnote [^n] is never referenced` |

What is **not** checked:

- external URLs: they're checked on demand with `:Markwright check urls` (below)
- anything inside code blocks or code spans
- relative paths in unsaved buffers, which have no folder to resolve against

The diagnostics stay until the next save, even if you fix the link in the meantime. `:Markwright check` re-runs the check immediately and reports the count. Disable with `diagnostics.enabled = false`, or keep only the check on open with `diagnostics.on_save = false`. `diagnostics.severity` sets the level.

### Checking external links

The automatic check never touches the network. To check that external links still work, run **`:Markwright check urls`**:

- **What's checked:** every `http(s)` link in the buffer: inline links, images, `<autolinks>`, `[ref]:` definitions and bare URLs (`www.…` too). Links inside code, local files, `mailto:` and other schemes are skipped. Each URL is requested once, however often it appears.
- **How:** in the background with `curl`, 8 at a time, 10 seconds each, following redirects. A light `HEAD` request comes first; if the server answers it with an error, a normal `GET` (of the first byte only) is tried before calling the link broken, because many servers handle `HEAD` badly.
- **Results:**

  | Result                                       | Shown as                                                                                           |
  | -------------------------------------------- | -------------------------------------------------------------------------------------------------- |
  | 2xx / 3xx                                    | fine, nothing shown                                                                                |
  | 404, 410, 5xx, other errors                  | **warning**: `HTTP 404: https://…`                                                                 |
  | unknown host, refused, timeout, TLS problems | **warning**: `host not found: https://…`                                                           |
  | 401, 403, 429                                | **info**: `HTTP 403: needs a login or blocks automated checks` (the page may be fine in a browser) |

  They appear as diagnostics on the links themselves (every occurrence) and in the **quickfix list** (`:copen`, `]q`/`[q`), which opens automatically when something is wrong. A notification sums it up: `12 links checked: 1 broken, 1 restricted`.
- **Separate from the automatic check:** these results stay until you run the check again (a new run replaces them), and saving the file doesn't clear them.

Options under `url_check`: `concurrency`, `timeout_ms`, `ignore` (Lua patterns of URLs to skip, e.g. `{ "^https://localhost", "internal%.corp" }`), `open_quickfix`, `severity`.

---

## Lists and checkboxes

### Continuing lists

In insert mode, `<CR>` on a list item starts the next item:

| On this line      | `<CR>` gives                                                             |
| ----------------- | ------------------------------------------------------------------------ |
| `- one`           | `- ` (same bullet: `-`, `*` or `+`, same spacing)                        |
| `1. one` / `3) c` | `2. ` / `4) `                                                            |
| `- [x] done`      | `- [ ] ` (new checkboxes start unchecked)                                |
| `  - nested`      | `  - ` (same indentation)                                                |
| `> - quoted`      | `> - ` (inside the blockquote)                                           |
| `- ` (empty item) | Ends the list: the marker is removed and you keep typing on a plain line |

- **In the middle of an item**, `<CR>` splits it: `- hello|world` becomes `- hello` and `- world`.
- **At the very start of the line**, `<CR>` behaves like a plain `<CR>` and opens a blank line above.
- **`o` and `O`** in normal mode do the same: open a new item below or above the current one. Elsewhere they are the normal `o`/`O`, counts included.
- **Lazily numbered lists** (`1.` `1.` `1.`) keep using the same number.
- **Outside list items** (and in code blocks), `<CR>` is whatever it was before markwright, such as the mini.pairs / nvim-autopairs behavior. When the completion menu is open, `<CR>` belongs to the completion.

### Nesting

`<Tab>` / `<S-Tab>` in insert mode on a list item:

- **`<Tab>`** nests the item under the one above. It's indented to that item's content column, which is what CommonMark requires: 2 columns under `- `, 3 under `1. `.
- **`<S-Tab>`** moves it back to its parent's level.
- **Children and continuation lines move with it.**
- **An ordered item that becomes the first of a new sublist restarts at `1.`**, and both lists renumber.
- **The cursor stays on the same text.**

```shell
- a              - a
- b      <Tab>     - b
  - c    →           - c
```

`<Tab>` checks completion and snippets first, then tables, then lists. Anywhere else it's the native `<Tab>`, which in markdown buffers inserts spaces (the ftplugin sets `expandtab`).

### Renumbering

Ordered lists are renumbered automatically in these cases:

- after `<CR>`, `o`/`O`, `<Tab>`/`<S-Tab>`
- after normal-mode edits such as `dd`, `p` or `x`, and Ex commands such as `:m`, `:g` or `:d`, wherever the list is (not only around the cursor)
- when leaving insert mode

Other details:

- **The renumbering joins the same undo step** as the edit that caused it, so `u` undoes both.
- **A list keeps its start number.** `5.` `6.` `7.` stays a list starting at 5. Deleting or moving the first item doesn't change it: `1.` `2.` `3.` minus its first item is `1.` `2.`, and an item pasted above the first one becomes the new `1.`. To start from another number, type it on the first item.
- **Nested lists are renumbered too.** When a number gets wider (`9.` → `10.`), the item's continuation lines shift to stay aligned.
- **Lazily numbered lists** (all the same number) are left alone.
- **Changes from undo and redo** never trigger renumbering, so undo always works.

Set `lists.auto_renumber = false` to turn it off.

### Checkboxes

**`<CR>` in normal mode** on a list item:

| Line                       | After `<CR>`                                                 |
| -------------------------- | ------------------------------------------------------------ |
| `- [ ] task`               | `- [x] task ✅ 2026-10-02 15:52` (completion date and time)  |
| `- [x] task ✅ …` or `[X]` | `- [ ] task` (the date goes away)                            |
| `- task`                   | `- [ ] task` (set `lists.checkbox_add = false` to skip this) |
| Plain text, code blocks    | Native `<CR>` (moves down)                                   |

In visual mode `<CR>` checks every list item in the selection, or unchecks them all if they're already all checked. The cursor doesn't move, and each toggle is one undo step. Pick another key with `lists.checkbox_key` (normal and visual), or `""` for none.

#### Completion dates

Checking an item appends when it was done, in your local time; unchecking removes it again:

```
- [ ] Write the README     <CR>  →  - [x] Write the README ✅ 2026-10-02 15:52
```

- The stamp goes at the end of the item's first line, and it's part of the same undo step as the check.
- An item that already has a stamp isn't stamped twice. Adding a checkbox to a plain item (`- task` → `- [ ] task`) doesn't stamp.
- Change the format with `lists.done_date`, using [`os.date`](https://www.lua.org/manual/5.1/manual.html#pdf-os.date) codes (`%Y %m %d %H %M %S %F %R %T` …), or set it to `false` to turn stamps off:

```lua
opts = { lists = { done_date = "✅ %Y-%m-%d" } }   -- date only: the Obsidian Tasks format
opts = { lists = { done_date = "(done %d/%m %R)" } }
opts = { lists = { done_date = false } }
```

Unchecking removes stamps in the current format, and also the default and Obsidian ones (`✅ 2026-10-02 15:52`, `✅ 2026-10-02`), so changing the format later doesn't strand old stamps.

#### Progress counters

Type `[/]` or `[%]` (or both, e.g. `- Release [/] [%]` → `- Release [2/3] [66%]`) anywhere in a parent item, or on the heading or line of text right above a checklist, and markwright fills in how many of the tasks are done:

```
- Release [/]            - Release [2/3]            - Release [%]            - Release [66%]
  - [x] docs       →       - [x] docs                 - [x] docs       →       - [x] docs
  - [x] tag                - [x] tag                  - [x] tag                - [x] tag
  - [ ] announce           - [ ] announce             - [ ] announce           - [ ] announce
```

```
## Launch [/]            ## Launch [1/2]            Groceries [%]            Groceries [33%]
                   →                                - [x] milk         →     - [x] milk
- [x] docs               - [x] docs                 - [ ] eggs               - [ ] eggs
- [ ] tag                - [ ] tag                  - [ ] bread              - [ ] bread
```

- **What counts:** the item's direct sub-items that have a checkbox; checked ones are done. For a heading or line above a list, the list's top-level items. Plain sub-items (`- note`) are ignored, and deeper levels count toward their own parent.
- **Counts roll up:** a sub-item without a checkbox but with its own cookie (`- Phase 1 [0/0]`) counts as one task, done when all of its tasks are. A parent with its own checkbox (`- [ ] Docs [0/0]`) is never checked automatically.
- **When it updates:** right after you toggle a checkbox, when you leave insert mode (so a cookie you just typed fills in), after normal-mode edits such as `dd`, and on save. The update joins the same undo step as the change that caused it.
- **Above a list** means the block right before it: an ATX or setext heading, the last line of a paragraph, or a callout title (`> [!NOTE] Todo [/]`). Blank lines between are fine; a heading followed by other text first isn't a label.
- Items without a cookie are never changed, `[1/2](url)` is a link, and `` `[/]` `` in inline code is just text. Set `lists.progress = false` to turn it off.

### List tools

| Keys                          | Action                                                                                                     |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `<leader>mlJ` / `<leader>mlK` | Move the item under the cursor down / up past its next sibling, **with its children** (`[count]` siblings) |
| `<leader>mls` / `<leader>mlS` | Sort the list under the cursor A→Z / Z→A                                                                   |
| `<leader>mld`                 | Sort so **done** items go last (unchecked and plain items keep their order first)                          |
| `<leader>mlb`                 | Lines ↔ **bullets** (`- item`)                                                                             |
| `<leader>mln`                 | Lines ↔ **numbers** (`1. item`)                                                                            |
| `<leader>mlc`                 | Lines ↔ **checkboxes** (`- [ ] item`)                                                                      |

```
- a              <leader>mlJ      - b
  - a1               →            - a
- b                                 - a1
```

- **"The list under the cursor"** is the cursor's item and its siblings: on a child, only the children move. A child never leaves its parent, and moving stops at the first and last sibling.
- **Numbered lists** are renumbered after moving or sorting, from the list's first number.
- **Sorting** compares the item text without case, ignoring checkboxes and emphasis markers. Blank lines between items stay where they are.

**Converters** turn lines into bullets (`b`), numbers (`n`) or checkboxes (`c`):

| Keys                                          | Converts                                                                                                                               |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `<leader>mlb` / `<leader>mln` / `<leader>mlc` | **The cursor's level**: its item and that item's siblings. Parents and sub-lists stay as they are. On plain lines: the paragraph       |
| `<leader>mlB` / `<leader>mlN` / `<leader>mlC` | **The cursor's level and every sub-list below it**, at any depth. Parents stay as they are; on a top-level item this is the whole list |
| visual `<leader>mlb` (or `B`, …)              | Exactly the selected lines                                                                                                             |

```
Buy milk        <leader>mlc    - [ ] Buy milk     <leader>mln    1. Buy milk
Call mom            →          - [ ] Call mom         →          2. Call mom
```

```
- Groceries            <leader>mln on "Groceries"     1. Groceries
  - [x] milk                     →                       - [x] milk        (the checklist is
  - [ ] eggs                                             - [ ] eggs         left alone)
- Chores                                              2. Chores
```

- Plain lines get the style; items of another style switch to it. When **every** item being converted already has the style, it comes off and you're back to plain lines, so the same key toggles.
- **Checklists are protected:** whenever a conversion would remove checkboxes (`- [ ] …` → `- …`, `1. …` or plain text), checked or not, markwright asks first: "3 checklist items (2 done) would lose their checkbox. Convert them?"
  - **Yes** converts the checklists too.
  - **No** converts the rest and leaves the checklists exactly as they are (re-indented only if needed to stay nested). It's offered only when there is something else to convert, so with the lowercase keys (a single level) the choice is Yes or Cancel.
  - **Cancel** (or `<Esc>`) changes nothing.

  A list level is converted all or nothing, so a list never ends up mixing checkboxes with bullets or numbers. Turning lines *into* checkboxes never asks.
- Existing markers are kept: a `*` list stays `*` when it becomes a checklist, and a numbered list stays numbered (`1. [ ] item`). New markers use `lists.bullet` (`-`, `*` or `+`) and `lists.number_delim` (`.` or `)`), so every Markdown list style is available.
- Sub-items and continuation lines are re-indented when their parent's marker changes width, so they stay inside it. With the uppercase keys and in visual mode, the sub-lists are converted too (numbers restart for each level), and indented plain lines become sub-items.
- Headings, code fences and blank lines are skipped, and a `>` prefix is kept.

Each action is one undo step, and progress counters follow.

**Moving with `<M-j>`/`<M-k>`.** LazyVim uses these to move lines. To move list items with them instead, and keep LazyVim's line move everywhere else:

```lua
opts = { lists = { move_keys = { down = "<M-j>", up = "<M-k>" } } }
```

From the command line: `:Markwright list up|down|sort [desc|done]`, and `:[range]Markwright list bullet|number|checkbox [all]`.

---

## Headings

`<leader>m=` adds a `#`, `<leader>m-` removes one:

```shell
Title       <leader>m=   →   # Title
# Title     <leader>m=   →   ## Title
## Title    <leader>m-   →   # Title
# Title     <leader>m-   →   Title
Title       3<leader>m=  →   ### Title
```

- **Counts** work (`3<leader>m=`). The level stops at 6.
- **Setext headings** (`Title` over `===` or `---`) are converted to `#` style first.
- **Closing hashes** (`## Title ##`) are kept.
- **Visual mode** changes every non-blank line in the selection. Lines in code blocks are skipped.
- **Only the current line changes**; sub-headings don't shift with it. To shift them too, use `<leader>m#=` / `<leader>m#-` (below).

### Sections

A section is a heading with everything under it, up to the next heading of the same or a higher level: its text and its sub-sections.

| Keys                          | Action                                                                               |
| ----------------------------- | ------------------------------------------------------------------------------------ |
| `<leader>m#j` / `<leader>m#k` | Move the section down / up past its next / previous sibling (`[count]` siblings)     |
| `<leader>m#=` / `<leader>m#-` | Add / remove a `#` on the section's heading and every sub-heading (`[count]` levels) |

```
# A                          # A
## A.1        <leader>m#j    ## A.2
one              on A.1      two
## A.2            →          ## A.1
two                          one
```

- **The cursor can be anywhere in the section**, the heading or its text. It moves with the section.
- **Siblings only:** a section moves within its parent and stops at the first and last sibling. Blank lines between sections stay where they are.
- **Footnote and reference definitions** at the end of the file stay at the end when the last section moves.
- **Promote / demote** is refused when a sub-heading would go past level 6, or when the section's heading is already level 1 (it would stop being a heading). Setext headings are converted to `#` style.
- Headings inside code blocks don't count. Each action is one undo step and repeats with `.`.
- With `lists.move_keys` (e.g. `<M-j>`/`<M-k>`), those keys move the section when the cursor is on a heading line.
- From the command line: `:Markwright section up|down|add|remove [N]`.

---

## Heading navigation

| Keys         | Moves to                                                                              |
| ------------ | ------------------------------------------------------------------------------------- |
| `]]` / `[[`  | the next / previous heading, any level                                                |
| `][` / `[]`  | the next / previous heading of the **same level**, without leaving the parent section |
| `[u`         | the parent heading (one level up)                                                     |
| `<leader>mo` | a heading you pick from an outline of the document                                    |

```
# A
## A.1        ][ → A.2        [u → A
## A.2        [] → A.1
### A.2.1     [u → A.2        [[ → A.2
## A.3        ][ stays (no more siblings under A)
# B
```

- **Counts:** `3]]` moves three headings, `2[u` goes up two levels.
- **The jumplist:** every jump is added, so `<C-o>` takes you back.
- **Code blocks:** lines like `# comment` inside fenced code are not headings and are skipped. Setext headings (`Title` over `===`/`---`) count.
- **`[]` from the middle of a section** goes to that section's own heading first, like Vim's `[[`; press it again for the previous sibling.
- **Operators and visual mode:** `d]]`, `y[[`, `V]]` and friends work. As with Vim's built-in `]]`, a motion that ends at the start of a line becomes linewise, so `d]]` deletes whole lines up to the next heading.

### Outline

`<leader>mo` (or `:Markwright outline`) lists every heading, indented by level with the current section marked `›`, and jumps to the one you choose. It uses `vim.ui.select`, so with LazyVim it opens in the snacks picker with fuzzy search; telescope and fzf-lua users get their picker if they've registered it for `vim.ui.select` (`telescope-ui-select`, fzf-lua's `register_ui_select()`), and everyone else gets Neovim's built-in list.

These keys replace the simpler `]]`/`[[` that Neovim's own markdown ftplugin defines. Change or disable any of them under `nav` (for example `nav = { parent = "", outline = "<leader>fo" }`).

---

## Callouts

GitHub renders blockquotes that start with `[!TYPE]` as highlighted callouts (also called alerts):

```markdown
> [!WARNING]
> Back up your config before upgrading.
```

| Keys                              | Action                                                                                                                                                 |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `<leader>ma`                      | **Wrap** the paragraph under the cursor in a callout. You pick the type: `NOTE` (first, so Enter takes it), `TIP`, `IMPORTANT`, `WARNING` or `CAUTION` |
| `<leader>ma` on a callout         | **Change** its type: the picker opens again, with the current type marked `(current)`                                                                  |
| `<leader>ma` on a plain `>` quote | Turn it into a callout (you pick the type)                                                                                                             |
| `<leader>ma` in visual mode       | Wrap the selected lines                                                                                                                                |
| `<leader>mA`                      | **Remove** the callout: the `[!TYPE]` line goes and the content loses one `>` level                                                                    |

- **What gets wrapped in normal mode:** the paragraph (the block of non-blank lines) around the cursor. Inside a fenced code block, the whole block is wrapped, fences included. On an empty line, an empty callout is inserted and you start typing inside it.
- **Content is kept intact:** blank lines become `>` so the callout isn't split, lists and code keep their structure, and an indented paragraph (for example under a list item) keeps its indentation with the `>` after it.
- **Types** are recognized in any case (`[!warning]`) and written in uppercase. A title after the marker (`> [!NOTE] Heads up`, as Obsidian uses) is kept when changing the type, and kept as a line of text when removing.
- **Undo:** each action is one undo step.

### Typing inside callouts and quotes

`<CR>` in insert mode continues any blockquote, callouts included, the same way lists continue:

```
> [!NOTE]|            <CR>  →  > [!NOTE]
                               > |
> some text|          <CR>  →  > some text
                               > |
> |  (empty)          <CR>  →  |           the `>` is removed: the quote ends here
```

- **In the middle of a line**, `<CR>` splits it and both halves keep the `>`.
- **Nested quotes** keep their level (`> > `); on an empty `> >` line, `<CR>` removes one level at a time.
- **`o` / `O`** open a new `> ` line below / above.
- **Lists inside a quote** (`> - item`) continue as lists, and **code blocks inside a callout** keep the `>`. A line starting with `>` inside an ordinary code block (a shell prompt, say) is left alone.
- Turn it off with `blockquotes = { continue_on_enter = false }`.

From the command line: `:Markwright callout warning` wraps (or retypes) with that type directly, `:'<,'>Markwright callout tip` wraps a range, and `:Markwright callout remove` unwraps. Types tab-complete.

To skip the picker when wrapping, set a default type: `callouts = { default = "NOTE" }` (changing the type of an existing callout still asks). `callouts.types` sets the list and its order; add your own if your renderer supports more (Obsidian has many).

---

## Pasting images

`<leader>mp` saves the image on the clipboard into your project and links it. macOS only for now.

### What it can paste

| On the clipboard                                                       | What happens                                                      |
| ---------------------------------------------------------------------- | ----------------------------------------------------------------- |
| Image data: a screenshot (⌘⇧⌃4), "Copy Image" from a browser, Preview… | Saved as PNG                                                      |
| An image file copied in Finder (⌘C)                                    | The file is copied, keeping its format (`.jpg`, `.gif`, `.webp`…) |
| A copied path to an image (`/Users/me/pic.png`, `~/…`, `file://…`)     | The file is copied                                                |
| A copied image URL (`https://…/pic.png`)                               | Linked as is: `![](https://…/pic.png)` (nothing downloaded)       |
| Anything else                                                          | Warning: "the clipboard has no image"                             |

### How it's saved

1. **Name:** you're asked for a file name, prefilled with a timestamp (`image-20260929-215400`), so Enter accepts it. Spaces become `-` and characters that aren't allowed in file names are removed. For a Finder file, the prefill is its original name.
2. **Folder:** the image goes into `assets/` next to the Markdown file, created if needed. Configure it with `images.dir`: a relative folder, an absolute path, `~/…`, or a function `function(buf) return "img/2026" end`.
3. **Collisions:** an existing file is never overwritten: `login.png` becomes `login-1.png`, `login-2.png`…
4. **The link** is inserted after the cursor, like `p`. Its path is relative to the Markdown file (`assets/login.png`, or `../img/x.png` for a folder outside), with spaces and parentheses URL-encoded so the link never breaks.

### Alt text

- **Name you typed:** `login-page` gives the alt text `login page`.
- **Default timestamp name:** no alt text, because a timestamp isn't a description.
- **Finder file:** alt text from its file name.
- **Visual mode:** select some text, press `<leader>mp`, and the selection becomes the alt text and suggests the file name. The image link replaces the selection.
- **`images.alt = "prompt"`:** asks for the alt text separately. `"empty"` never sets it.

Other details:

- Inside code blocks nothing is pasted.
- One `u` removes the link; the saved file stays.
- `:Markwright image` does the same as `<leader>mp`.
- **In insert mode,** `;;p` pastes at the cursor (not after it) and you keep typing after the link, prompts included.

### Renaming an image

`<leader>mP` (or `:Markwright image rename`) with the cursor on an image `![alt](assets/shot.png)` asks for a new name, prefilled with the current one, and then:

- **renames the file on disk**, in the same folder. Without an extension, the old one is kept; spaces become `-`, as when pasting.
- **updates every link to it in the buffer**: images, links and `[ref]: …` definitions, however the path is written (`./assets/…`, encoded spaces), but not inside code.
- refuses to overwrite an existing file, and does nothing for remote images (`https://…`) or missing files.

```
![login](assets/shot.png)    <leader>mP  "login-page"  →  ![login](assets/login-page.png)
```

Links in **other files** aren't updated; `:Markwright check` (or saving them) flags the ones that broke. One `u` reverts the text, but **not** the file name.

### Under the hood (macOS)

- `osascript` (built in) reads the clipboard type and writes image data as PNG. The alternative is [pngpaste](https://github.com/jcsalterego/pngpaste) (`brew install pngpaste`), which is used automatically when installed.
- A file copied in Finder is recognized by its file reference, which is checked before the icon image macOS also puts on the clipboard.
- Everything runs asynchronously: Neovim doesn't freeze while the image is written.

### Plain `p` for images (opt-in)

With `images.smart_paste = true`, pressing `p` (with `clipboard=unnamedplus`, as in LazyVim) when the clipboard holds an image and no text runs the image paste instead of pasting nothing.

---

## Word count and reading time

`:Markwright stats` shows how long the document is:

```
markwright: 1,234 words · 7,012 characters · 7 min read
```

- **What counts:** the text a reader sees. Front matter, code blocks, HTML blocks, link and image URLs, bare URLs, reference definitions, image alt text, completion stamps and Markdown markup (`**`, `#`, list markers, checkboxes, table pipes…) are left out. Link text, headings, table cells, inline code and footnote text count.
- **Words:** hyphenated words, contractions and numbers like `3.14` count once; Chinese and Japanese characters count one word each. **Characters** include one space between words.
- **Reading time** rounds up at 200 words per minute; change it with `stats.wpm`.
- **Part of the document:** `:'<,'>Markwright stats` (or any range) counts those lines.

### In the statusline

`require("markwright.stats").statusline()` returns `1,234 words · 7 min`, or `52 words selected` in visual mode, and an empty string outside Markdown buffers. Counts are cached and only edited lines are counted again, so it's cheap to call on every redraw. With lualine (LazyVim):

```lua
{
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    table.insert(opts.sections.lualine_x, 1, {
      function() return require("markwright.stats").statusline() end,
      cond = function() return vim.bo.filetype == "markdown" end,
    })
  end,
}
```

For your own format, `require("markwright").stats()` returns `{ words, chars, reading_minutes }` for the current buffer, or for the visual selection (with `selection = true`) when one is active.

---

## Commands

| Command                                                        | Description                                                                                             |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `:Markwright bold`                                             | Toggle bold on the word under the cursor                                                                |
| `:Markwright italic`                                           | Toggle italic                                                                                           |
| `:Markwright strike`                                           | Toggle strikethrough                                                                                    |
| `:Markwright code`                                             | Toggle inline code                                                                                      |
| `:Markwright highlight`                                        | Toggle highlight                                                                                        |
| `:[range]Markwright links reference\|inline`                   | Convert every link in the file (or the range) to reference / inline style                               |
| `:Markwright link`                                             | Like `<leader>mk`, but links the word under the cursor instead of waiting for a motion                  |
| `:Markwright follow`                                           | Same as `gx`                                                                                            |
| `:Markwright fence`                                            | Insert a code fence; with a range (`:'<,'>Markwright fence`) wrap those lines                           |
| `:Markwright callout [type\|remove]`                           | Wrap in / retype / remove a callout; with a range, wrap those lines                                     |
| `:Markwright outline`                                          | Pick a heading from an outline and jump to it                                                           |
| `:Markwright footnote`                                         | Insert a footnote                                                                                       |
| `:Markwright footnote renumber`                                | Renumber the numbered footnotes by first reference and reorder their definitions                        |
| `:Markwright image`                                            | Paste the clipboard image (macOS)                                                                       |
| `:Markwright image rename`                                     | Rename the image file under the cursor and update its links                                             |
| `:Markwright toc`                                              | Insert or update the table of contents                                                                  |
| `:Markwright section up\|down\|add\|remove [N]`                | Move the section, or add / remove a `#` on its heading and sub-headings                                 |
| `:[range]Markwright heading add\|remove [N]`                   | Add or remove N `#` on the line (or every line in the range)                                            |
| `:[range]Markwright checkbox`                                  | Toggle the checkbox on the list item (or every item in the range, like visual `<CR>`)                   |
| `:[range]Markwright stats`                                     | Word count, characters and reading time (of the range, if given)                                        |
| `:Markwright check`                                            | Run link diagnostics now and report the count                                                           |
| `:Markwright check urls`                                       | Check external links (in the background) and report broken ones as diagnostics and in the quickfix list |
| `:Markwright table create`                                     | Create a table                                                                                          |
| `:[range]Markwright table fromcsv`                             | Convert the range (or the paragraph under the cursor) from CSV/TSV; `csv` is the old name               |
| `:Markwright table tocsv`                                      | Convert the table under the cursor to CSV (asks for the separator)                                      |
| `:Markwright table align`                                      | Align the table under the cursor                                                                        |
| `:Markwright table row` / `rowabove` `[N]`                     | Add N rows below / above                                                                                |
| `:[range]Markwright table delrow [N]`                          | Delete the row and the N - 1 below it, or the rows in the range                                         |
| `:[range]Markwright table sort [desc]`                         | Sort by the column under the cursor (only the rows in the range, if given)                              |
| `:Markwright table transpose` / `yank`                         | Transpose / copy as CSV                                                                                 |
| `:Markwright table col` / `colleft` / `delcol` `[N]`           | Add N columns right / left, delete N columns                                                            |
| `:[range]Markwright table move up\|down\|left\|right [N]`      | Move the row (or the rows in the range) or the column N places                                          |
| `:Markwright list up` / `down` `[N]` / `sort [desc\|done]`     | Move the list item N places / sort the list (see [List tools](#list-tools))                             |
| `:[range]Markwright list bullet` / `number` / `checkbox [all]` | Convert to bullets / numbers / checkboxes; `all` includes the sub-lists                                 |
| `:Markwright health`                                           | Run `:checkhealth markwright`                                                                           |

Subcommands tab-complete, including the `table` and `list` actions. Every key that changes the buffer has a command, for setups that turn the default keys off.

---

## Configuration

Pass options to `setup()`, or through `opts` with lazy.nvim. Everything is optional and these are the defaults.

```lua
require("markwright").setup({
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

  insert = {
    trigger = ";;",                 -- insert-mode prefix: 2+ characters, a key like "<C-g>", or "" to disable
  },

  links = {
    use_clipboard = true,           -- link key uses a URL from the clipboard (else prompts)
    fetch_title = true,             -- bare URL → [Page Title](url); false keeps the domain
    title_timeout_ms = 5000,        -- give up on the title after this long
    smart_paste_visual = true,      -- visual p with a URL → [selection](url)
    smart_paste_normal = true,      -- normal p/P with a URL → [Title](url)
  },

  follow = {
    key = "gx",                     -- "" keeps your own gx
    create_missing_md = true,       -- gx on a missing .md opens a new buffer
  },
  nav = {
    enabled = true,
    next = "]]",                    -- any level
    prev = "[[",
    next_sibling = "][",            -- same level, within the parent section
    prev_sibling = "[]",
    parent = "[u",
    outline = nil,                  -- nil = <prefix>o; false or "" disables
  },
  textobjects = {
    enabled = true,
    link = "k",                     -- ik / ak   (false or "" drops one object)
    url = "u",                      -- iu
    code = "c",                     -- ic / ac: inline code
    fence = "f",                    -- if / af: code block
    section = "#",                  -- i# / a#: heading section
    cell = "z",                     -- iz / az: table cell ("zell")
    item = "x",                     -- ix / ax: list item (the x in [x])
    emphasis = "*",                 -- i* / a*
    search_lines = 500,             -- not inside an object: use the next one within this many lines
  },
  blockquotes = {
    continue_on_enter = true,       -- <CR>/o/O keep the `>`; <CR> on an empty `>` line ends the quote
  },
  callouts = {
    types = { "NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION" }, -- picker order
    default = nil,                  -- a type here skips the picker
  },
  tables = {
    align_on_insert_leave = true,   -- realign when leaving insert mode in a table
    csv_separator = ",",            -- default separator for table → CSV (<leader>mtC); "\t" = tab
  },
  images = {
    dir = "assets",                 -- relative to the markdown file; absolute, ~/..., or function(buf) -> path
    name = "image-%Y%m%d-%H%M%S",   -- default file name (os.date format), no extension
    prompt_name = true,             -- ask for the name (prefilled with the default)
    alt = "name",                   -- alt text: "name" (from a typed name), "prompt", or "empty"
    smart_paste = false,            -- plain p pastes an image when the clipboard has one and no text
  },
  toc = {
    update_on_save = true,          -- refresh the TOC between the markers on :w
    marker_start = "<!-- toc -->",
    marker_end = "<!-- tocstop -->",
    min_level = 2,                  -- heading levels included
    max_level = 4,
  },
  url_check = {                   -- :Markwright check urls
    concurrency = 8,
    timeout_ms = 10000,
    ignore = {},                    -- Lua patterns of URLs to skip
    open_quickfix = true,
    severity = vim.diagnostic.severity.WARN,
  },
  diagnostics = {
    enabled = true,                 -- check links on open (and on save, see below)
    on_save = true,
    severity = vim.diagnostic.severity.WARN,
  },
  stats = {
    wpm = 200,                      -- reading speed for the reading time
  },

  lists = {
    continue_on_enter = true,       -- <CR> / o / O continue lists
    tab_indent = true,              -- <Tab> / <S-Tab> nest list items
    auto_renumber = true,           -- keep ordered lists numbered
    checkbox_add = true,            -- checkbox key adds [ ] to plain items
    checkbox_key = "<CR>",          -- normal/visual key that toggles checkboxes; "" = none
    done_date = "✅ %Y-%m-%d %H:%M", -- stamp appended when checking (os.date format); false = off
    progress = true,                -- fill [/] and [%] cookies on parent items
    move_keys = nil,                -- e.g. { down = "<M-j>", up = "<M-k>" }: move items on list items
    bullet = "-",                   -- new bullets from the converters: "-", "*" or "+"
    number_delim = ".",             -- new numbers from the converters: "." or ")"
  },
})
```

## Examples

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
  require("markwright").setup(opts)
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "markdown",
    callback = function(ev)
      local f = require("markwright.format")
      local map = function(mode, lhs, fn, desc)
        vim.keymap.set(mode, lhs, fn, { buffer = ev.buf, expr = true, desc = desc })
      end
      map("n", "gb",    function() return f.expr_smart("bold") end, "Bold (like <leader>mb)")
      map("n", "gB",    function() return f.expr_operator("bold") end, "Bold operator (always waits)")
      map("x", "gb",    function() return f.expr_operator("bold") end, "Bold selection")
      map("n", "<C-b>", function() return f.expr_normal("bold") end, "Bold word")
    end,
  })
end,
```

| Function                                                                      | Use                                                                                                                                 |
| ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `require("markwright.format").expr_smart(fmt)`                                | The default normal-mode key: removes the span under the cursor or inserts empty markers at once, otherwise waits for a motion       |
| `require("markwright.format").expr_normal(fmt)`                               | Normal-mode `expr` mapping: word under the cursor, or empty markers on whitespace                                                   |
| `require("markwright.format").expr_operator(fmt)`                             | `expr` mapping for visual mode, or a normal-mode operator that waits for a motion                                                   |
| `require("markwright.format").toggle(fmt)`                                    | Toggle on the word under the cursor from any Lua code (not an `expr` mapping)                                                       |
| `require("markwright.format").apply(buf, fmt, mtype, srow, scol, erow, ecol)` | Low-level: toggle over a range. Rows and columns are 0-based bytes, `ecol` is inclusive, `mtype` is `"char"`, `"line"` or `"block"` |

`fmt` is one of `"italic"`, `"bold"`, `"strike"`, `"code"`, `"highlight"`.

Link entry points (all `expr = true` except where noted):

| Function                                                                      | Use                                                                                                                                       |
| ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `require("markwright.refs").toggle()` / `convert_range(buf, srow, erow, to?)` | Inline ↔ reference for the link at the cursor / the links in 0-based rows (`to` = `"reference"` or `"inline"`; nil picks by what's there) |
| `require("markwright.links").expr_smart()`                                    | The default normal-mode link key: acts at once on a link, bare URL or whitespace, otherwise waits for a motion                            |
| `require("markwright.links").expr_operator()`                                 | Link operator that always waits for a motion                                                                                              |
| `require("markwright.links").expr_normal()`                                   | Link at the cursor (`:Markwright link`)                                                                                                   |
| `require("markwright.links").expr_visual()`                                   | Visual-mode link key                                                                                                                      |
| `require("markwright.links").expr_paste(after)`                               | Normal `p` (`after = true`) or `P` (`false`)                                                                                              |
| `require("markwright.links").expr_paste_visual()`                             | Visual `p`                                                                                                                                |
| `require("markwright.links").is_url(s)` / `url_at(line, col)`                 | Plain helpers (not mappings)                                                                                                              |
| `require("markwright.title").fetch(url, cb)`                                  | Async title fetch; `cb(title)` runs on the main loop (`title` is `nil` on failure)                                                        |

Other features are plain functions, suitable for normal (non-`expr`) mappings. To make one repeatable with `.`, as the default keys are, wrap it: `vim.keymap.set("n", lhs, require("markwright.util").repeatable(function() require("markwright.tables").add_row() end), { buffer = ev.buf, expr = true })` (`repeatable_visual(function(_, srow, erow) … end)` for visual mode, over the selected rows).

The functions:

| Function                                                                                                                   | Use                                                                                                                                            |
| -------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `require("markwright.follow").follow()`                                                                                    | `gx` behavior at the cursor                                                                                                                    |
| `require("markwright.follow").open_target(buf, dest)`                                                                      | Follow a destination string (`#anchor`, path, URL)                                                                                             |
| `require("markwright.fence").insert()` / `wrap(buf, srow, erow)`                                                           | Code fence at the cursor / around 0-based rows                                                                                                 |
| `require("markwright.callouts").toggle(type?)`                                                                             | Callout at the cursor: wrap the paragraph or change the type (`type` skips the picker)                                                         |
| `require("markwright.footnotes").renumber(buf)`                                                                            | Renumber numbered footnotes by first reference (returns whether anything changed)                                                              |
| `require("markwright.footnotes").insert()`                                                                                 | Footnote at the cursor                                                                                                                         |
| `require("markwright.tables").create()` / `align()` / `add_row(above)` / `delete_row()` / `add_col(left)` / `delete_col()` | Table commands at the cursor                                                                                                                   |
| `require("markwright.tables").from_csv(buf, srow, erow)`                                                                   | Convert 0-based rows from CSV/TSV                                                                                                              |
| `require("markwright.tables").from_csv_paragraph()`                                                                        | CSV → table for the paragraph under the cursor (prompts for the separator)                                                                     |
| `require("markwright.tables").to_csv()` / `to_csv_lines(model, sep)`                                                       | Table under the cursor → CSV (prompts) / CSV lines for a model from `read(buf, srow, erow)`                                                    |
| `require("markwright.tables").move_row(dir)` / `move_col(dir)` / `sort(desc)` / `transpose()` / `yank_csv()`               | Table tools at the cursor (`dir` = `1` / `-1`, count from `vim.v.count1`)                                                                      |
| `require("markwright.tables").expr_tab(dir)`                                                                               | `expr` mapping for insert-mode cell navigation (`1` / `-1`)                                                                                    |
| `require("markwright.toc").insert()` / `update(buf)`                                                                       | Insert or refresh the TOC                                                                                                                      |
| `require("markwright.diagnostics").check(buf)` / `collect(buf)`                                                            | Publish / just compute link diagnostics                                                                                                        |
| `require("markwright").stats(buf?)` / `require("markwright.stats").statusline()` / `count(buf, range)`                     | Word count and reading time: current buffer or visual selection / statusline text / any range (see [Word count](#word-count-and-reading-time)) |
| `require("markwright.slug").slug(text)`                                                                                    | GitHub-style anchor for heading text                                                                                                           |
| `require("markwright.textobjects").expr(name, inner)`                                                                      | `expr` mapping (modes `o`, `x`) for a text object; `name` is `link`, `url`, `code`, `fence`, `section`, `cell`, `item` or `emphasis`           |
| `require("markwright.nav").heading(dir)` / `sibling(dir)` / `parent()` / `outline()`                                       | Heading motions (`dir` = `1` / `-1`, count from `vim.v.count1`) and the outline picker                                                         |
| `require("markwright.lists").expr_enter()` / `expr_open(below)` / `expr_checkbox()` / `expr_tab(dir)`                      | `expr` mappings for insert `<CR>`, `o`/`O`, the checkbox key and insert `<Tab>` (tables + lists)                                               |
| `require("markwright.lists").toggle_range(srow, erow)` / `renumber(buf, row)`                                              | Check or uncheck a range of 0-based rows / renumber the list around a row                                                                      |
| `require("markwright.listtools").move(dir)` / `sort(mode)`                                                                 | Move the list item (`dir` = `1` / `-1`) / sort its list (`mode` = `"asc"`, `"desc"` or `"done"`)                                               |
| `require("markwright.listtools").convert(style, all)` / `convert_lines(style, srow, erow)`                                 | Convert to `"bullet"`, `"number"` or `"checkbox"`: the cursor's level (`all`: and the sub-lists) / 0-based rows                                |
| `require("markwright.sections").move(dir)` / `change(delta)`                                                               | Move the section at the cursor (`dir` = `1` / `-1`) / add or remove `#` on it and its sub-headings                                             |
| `require("markwright.headings").change(buf, srow, erow, delta)`                                                            | Add (`delta > 0`) or remove `#` on 0-based rows                                                                                                |

---

## Health check

```shell
:checkhealth markwright
```

It checks:

- Neovim version
- the `markdown` and `markdown_inline` parsers
- `curl`
- a clipboard provider
- `vim.ui.open`
- on macOS: `pngpaste` or `osascript` for image paste

Warnings for `curl` and the clipboard only affect links: without `curl` the link text is the domain name, and without a clipboard the link key always prompts (on macOS the plugin still tries `pbpaste`).

---

## Troubleshooting

**The keymaps don't exist.**

- Make sure the buffer's filetype is `markdown` (`:set ft?`). Keymaps are buffer-local.
- Check `:Lazy` to see whether the plugin loaded (with a local checkout, check that `dir` points at the folder containing `lua/` and `plugin/`).
- Check for conflicts with `:verbose nmap <leader>mb`.

**The which-key group doesn't show.** The group is registered only when which-key is loaded at the moment the buffer attaches. The keymaps work regardless.

**Nothing happens and a warning says "formatting skipped inside code".** The cursor is inside a code block or code span, which is intended. Use `<leader>mc` to remove a code span first.

**Toggling doesn't detect an existing format.** Detection relies on the `markdown_inline` parser. Run `:checkhealth markwright`, and `:TSInstall markdown markdown_inline` if they are missing. Without the parsers, the plugin falls back to a simpler text check.

**The wrong word boundaries are used.** `iw` follows `'iskeyword'`. To target something else, use another motion (`<leader>mbiW` for a WORD) or visual mode.

**Another plugin's key conflicts with `<leader>m`.** Change `keymaps.prefix`, or disable the defaults and map your own (see [Custom keymaps and Lua API](#custom-keymaps-and-lua-api)).

**The link key prompts even though I copied a URL.** The clipboard must hold only the URL, on one line. Check with `:echo getreg('+')`. If it's empty, Neovim can't see the system clipboard: run `:checkhealth provider`.

**Links keep the domain instead of the page title.**

- Run `:checkhealth markwright` to confirm `curl` is found.
- Some sites block non-browser requests or build their title with JavaScript. The domain is kept in that case.
- A slow site may exceed `links.title_timeout_ms`.
- You can test a URL from the shell with `curl -sL <url> | grep -i '<title'`.

**My `p` behaves differently in Markdown.** Only a single-line URL in the register triggers smart paste; everything else is native. If you use yanky.nvim, markwright's buffer-local `p`/`P` take priority in Markdown buffers. Disable them with `links.smart_paste_normal = false` and `links.smart_paste_visual = false`.

**`gx` does something different from before.** In Markdown buffers markwright owns `gx` and falls back to the default behavior when the cursor isn't on a link. To keep your own mapping, set `follow.key = ""` (or another key).

**`<Tab>` doesn't accept my completion.** markwright checks for a visible blink.cmp or nvim-cmp menu, the built-in popup and active snippets before touching `<Tab>`. If your completion plugin maps `<Tab>` in a way it can't detect, disable table navigation by overriding it: `vim.keymap.set("i", "<Tab>", "<Tab>", { buffer = true })` in a `FileType markdown` autocmd, or map completion to another key.

**`:Markwright check urls` reports a link that opens fine in the browser.** Some sites refuse requests that don't come from a browser, or answer `HEAD` requests with errors. 401/403/429 answers are only shown as info for that reason. For a site that always fails, add it to `url_check.ignore`.

**Diagnostics complain about a link that works on GitHub.**

- Anchors are compared with GitHub's slug rules; headings with unusual Unicode punctuation may differ slightly.
- Relative links are resolved from the file's folder, not the repository root. Root-relative `/docs/x.md` paths are treated as absolute filesystem paths.
- `:Markwright check` shows the current count after a fix. Diagnostics otherwise refresh on save.

**The TOC isn't updated.** It only updates between an exact `<!-- toc -->` … `<!-- tocstop -->` pair (or your configured markers), each on its own line.

**`<CR>` in normal mode toggles checkboxes, but I use it for something else.** It only acts on list items; elsewhere your previous `<CR>` mapping (or the native one) runs. To move it, set `lists.checkbox_key = "<leader>mx"` (or `""` to disable).

**`o`, `<CR>` or `<Tab>` interfere with another plugin.** Turn the list behaviors off individually with `lists.continue_on_enter = false` (`<CR>`, `o`, `O`) and `lists.tab_indent = false` (`<Tab>` for lists; tables keep it).

**`<leader>mp` says "the clipboard has no image".** Check what's on the clipboard with `osascript -e 'clipboard info'` in a terminal. It should list `«class PNGf»` or `TIFF picture` for image data, or `«class furl»` for a copied file. Some apps copy images in formats macOS can't convert to PNG; `brew install pngpaste` handles more of them.

**`;;` shows the menu when I wanted two semicolons.** Press `;` again: `;;` then any key that isn't a command types `;;` plus that key. If you type `;;` often, pick another trigger with `insert.trigger` (for example `",,"` or `"<C-g>"`).

**Pasted images land in the wrong folder.** The folder is relative to the Markdown file, not the working directory (unsaved buffers use the working directory). Set `images.dir` to an absolute path or a function to use one shared folder.

**A nested ordered item didn't become a sublist.** In CommonMark a nested ordered list can only start inside a paragraph if its first number is 1. `<Tab>` resets the first nested item to `1.` for you. If you type the indentation by hand, start with `1.`.

---

## Known limitations

- **Image paste is macOS only** for now. On Linux and WSL, `<leader>mp` shows a warning; backends for `wl-paste`, `xclip` and PowerShell are planned.
- **Link diagnostics refresh on open and save**, not while typing. `:Markwright check` re-runs them on demand.
- **Retyping the first item of a numbered list with `cc`** keeps the list's old start number: `cc` replaces the whole line, which looks like deleting the item. To restart the list from another number, change just the number (`r5`, `ciw`).
- **One behavior is provisional** and may change in a future version: when a selection only partly covers a formatted span, the whole span is removed.
- **`<leader>m…` keys don't wait for the next key while you record a macro** (with which-key). which-key steps aside during macros, so Neovim's `timeoutlen` applies: LazyVim sets it to 300 ms, and a slower `m` after `<Space>` runs the plain `<Space>` (cursor right) instead. Type the keys quickly while recording (replaying with `@` is unaffected), or turn the timeout off while recording:

  ```lua
  local saved
  vim.api.nvim_create_autocmd("RecordingEnter", { callback = function() saved = vim.o.timeout; vim.o.timeout = false end })
  vim.api.nvim_create_autocmd("RecordingLeave", { callback = function() vim.o.timeout = saved end })
  ```
- **If you use the marksman language server** (LazyVim's markdown extra installs it), it has its own link checks. If you ever see the same broken link reported twice, disable one of them (`diagnostics.enabled = false` here).

---

## Roadmap

The full plan lives in [SPEC.md](SPEC.md): **§0 is a checklist** of what's implemented and what isn't, and **§14** describes every planned feature in detail.

**Done:** inline formatting, formatting while typing, text objects, heading navigation, section moves and promote / demote, footnote renumbering, inline ↔ reference links, callouts, links and titles, smart paste, `gx`, headings, lists and checkboxes, list tools (move, sort, convert), completion dates, progress counters, word count and reading time, code fences, tables and table tools (move, sort, transpose, CSV), footnotes, TOC, link diagnostics, image paste (macOS).

**Planned:**

| Priority | Features                                                                                               |
| -------- | ------------------------------------------------------------------------------------------------------ |
| Later    | Front matter helpers, link completion, three-state checkboxes `[-]`, rich-text paste (HTML → Markdown) |
| Platform | Image paste on Linux/WSL, `:help markwright`                                                           |

Out of scope: wiki-style `[[links]]` and rendering or preview. Use `render-markdown.nvim` or `markview.nvim` for rendering.

---

## Development

### Working on a local checkout

```sh
git clone https://github.com/edieguez/markwright ~/code/markwright
```

Point lazy.nvim at the folder instead of GitHub:

```lua
{ dir = "~/code/markwright", name = "markwright", ft = "markdown", opts = {} }
```

lazy.nvim doesn't update `dir` plugins; after editing, run `:Lazy reload markwright` or restart Neovim.

### Contributing

Issues and pull requests are welcome. For changes in behavior, please:

1. Check [SPEC.md](SPEC.md): it records the design decisions, and new features are specified in §14 before they're built.
2. Add or update cases in `tests/*_spec.lua`, and run `make check` (lint + tests).
3. Update the README section for the feature.

### Running the tests, formatting and lint

```sh
make test                        # headless test suite
make test NVIM=/path/to/nvim     # with a specific Neovim binary
make fmt                         # format with stylua
make lint                        # stylua --check + selene
make check                       # lint, then tests
```

Formatting follows `.stylua.toml` (2 spaces, 120 columns, double quotes). selene uses `selene.toml` with the `vim.yml` standard library. CI runs the tests on Neovim 0.10.0, stable and nightly on Linux and macOS, plus stylua and selene, for every push and pull request.

The suite starts a headless Neovim with `tests/minimal_init.lua`, sets `<Space>` as leader, and **feeds real keystrokes through the mappings**. The tests therefore cover the keymaps, operators, dot-repeat and undo, not just the internal functions. `tests/run.lua` runs every `*_spec.lua` file.

A test case is one table row, for example in `tests/format_spec.lua`:

```lua
{ "bold toggles off", { "hello **world**" }, { 1, 9 }, " mb", { "hello world" }, { 1, 7 } },
--  name              buffer before         cursor   keys   buffer after       cursor after (optional)
```

Keys can be a list of strings to feed in separate chunks, for example `{ " mb", " mi", "u" }`. A case can also carry `setup = function() … end`, run just before the keys. Plain unit checks use `{ "name", fn = function() … end }`.

In `tests/links_spec.lua` the clipboard, `vim.ui.input` and the title fetcher are mocked, so the tests are deterministic and need no network. Other specs mock the system opener (`follow_spec.lua`) and prompts, and create real temporary files for path, anchor and diagnostics checks.

| Spec                   | Covers                                                                                                      |
| ---------------------- | ----------------------------------------------------------------------------------------------------------- |
| `format_spec.lua`      | inline formatting                                                                                           |
| `refs_spec.lua`        | inline ↔ reference links: labels, reuse, definitions, images, visual, commands                              |
| `links_spec.lua`       | link key, titles, smart paste                                                                               |
| `follow_spec.lua`      | `gx`, slugs                                                                                                 |
| `blocks_spec.lua`      | code fences, footnotes                                                                                      |
| `tables_spec.lua`      | tables, table tools, `<Tab>` fallback                                                                       |
| `doc_spec.lua`         | TOC, diagnostics                                                                                            |
| `lists_spec.lua`       | lists, checkboxes, completion dates, progress counters, renumbering, headings                               |
| `listtools_spec.lua`   | list tools: move, sort, converters and the checklist prompt                                                 |
| `nav_spec.lua`         | heading motions, counts, siblings, parents, operators, outline                                              |
| `callouts_spec.lua`    | callouts: wrap, pick, change type, convert, remove, commands                                                |
| `sections_spec.lua`    | moving sections, promote / demote with sub-headings, definitions kept at the end                            |
| `stats_spec.lua`       | word count, markup and code exclusion, ranges, selection, statusline                                        |
| `urlcheck_spec.lua`    | external URL checker (mocked requests, plus real curl against a local server)                               |
| `repeat_spec.lua`      | dot-repeat of every buffer-changing key, counts, visual mode, reused prompt answers                         |
| `textobjects_spec.lua` | text objects: every object with d/c/y/visual, counts, empty objects, dot-repeat                             |
| `insert_spec.lua`      | formatting while typing: pairs, jump out, links, fall-through, code, other triggers                         |
| `images_spec.lua`      | image paste (mocked clipboard; the real macOS backend runs against fake `osascript`/`pngpaste` executables) |

The runner fires `TextChanged` after each key chunk that changed the buffer in normal mode. Real Neovim does this in its main loop between keystrokes, but not while a headless script runs, and the auto-renumbering depends on it.

### Design notes

- **Treesitter first.** Span detection uses `markdown_inline` nodes (`emphasis`, `strong_emphasis`, `strikethrough`, `code_span`). Code detection uses `markdown` block nodes (`fenced_code_block`, `indented_code_block`, `html_block`). Highlight (`==`) is not in the grammar, so it uses a line scan.
- **Operators everywhere.** Normal, visual and operator mappings all go through `g@` and `operatorfunc`. That is what makes `.` work without depending on vim-repeat.
- **Bottom-up edits.** Multi-line toggles are applied from the last line up so row numbers stay valid. An edit tracker keeps the cursor on the same character through the column shifts.
- **One undo step.** An explicit undo break starts each action, because API edits would otherwise merge with the previous change.
- **Async titles.** A titled link is inserted at once with the domain as a placeholder, tracked by an extmark. When `curl` returns, the placeholder is replaced only if it is still intact, joined to the same undo step with `:undojoin`.
- **Bare URLs** aren't in the `markdown_inline` grammar (no GFM autolink extension), so they're found with a line scan that trims sentence punctuation and balances parentheses.
- **Footnotes and reference definitions** use a line scan too. The grammar has no footnote support, and a `[ref]: url` line right after a footnote definition gets swallowed into a paragraph. Code blocks and code spans are excluded from the scan.
- **Tables** are located from the lines (a run of non-blank lines whose header is followed by a valid delimiter row), with Treesitter only ruling out code blocks: the grammar reads a row of empty cells after a body row as a new delimiter row and splits the table. They're then split into cells by hand (unescaped `|`, as GFM does) and re-rendered from a model. Rendering records where each cell starts, which is how the cursor stays in its cell.

---

## Project layout

```shell
markwright/
├── plugin/markwright.lua     :Markwright command
├── lua/markwright/
│   ├── init.lua              setup(), attaches to markdown buffers
│   ├── config.lua            defaults, merge, validation
│   ├── keymaps.lua           buffer-local mappings + which-key group
│   ├── format.lua            formatting toggle engine
│   ├── links.lua             link key, bare URLs, unlink, smart paste
│   ├── refs.lua              inline ↔ reference links
│   ├── title.lua             async page-title fetching (curl)
│   ├── follow.lua            gx: files, anchors, URLs, images, footnotes
│   ├── fence.lua             code fences
│   ├── footnotes.lua         footnote insertion
│   ├── tables.lua            tables: parse, render, edit, navigate
│   ├── lists.lua             list continuation, nesting, checkboxes, renumbering, progress
│   ├── listtools.lua         move, sort and convert list items
│   ├── headings.lua          add / remove #
│   ├── sections.lua          move / promote / demote heading sections
│   ├── images.lua            image paste (macOS backend)
│   ├── insert.lua            formatting while typing (;; trigger)
│   ├── textobjects.lua       ik iu ic if i# iz ix i* text objects
│   ├── nav.lua               ]] [[ ][ [] [u motions and the outline
│   ├── callouts.lua          GitHub callouts > [!NOTE]
│   ├── urlcheck.lua          :Markwright check urls
│   ├── toc.lua               table of contents
│   ├── diagnostics.lua       broken-link diagnostics
│   ├── doc.lua               headings, definitions, footnotes, code rows
│   ├── slug.lua              GitHub-style anchors
│   ├── stats.lua             word count and reading time
│   ├── ts.lua                Treesitter helpers
│   ├── util.lua              prefixes, edit tracker, undo, notify
│   └── health.lua            :checkhealth markwright
├── tests/
│   ├── minimal_init.lua
│   ├── run.lua               runs every *_spec.lua
│   ├── helpers.lua           key-feeding test runner, mocks, temp files
│   └── *_spec.lua            one spec per feature
├── .github/workflows/ci.yml  tests (0.10/stable/nightly × Linux/macOS) + lint
├── .stylua.toml              formatting
├── selene.toml, vim.yml      lint configuration
├── CHANGELOG.md              release notes
├── SPEC.md                   full design, decisions and status checklist
├── LICENSE                   MPL-2.0
├── Makefile                  test, fmt, lint, check
└── README.md
```

---

## License

markwright is licensed under the [Mozilla Public License 2.0](https://mozilla.org/MPL/2.0/) (MPL-2.0). See [LICENSE](LICENSE).

In short: you can use it in any configuration, private or commercial. If you distribute modified versions of markwright's files, those files must stay under the MPL-2.0 and their source must be available. This summary isn't legal advice; the license text is what counts.
