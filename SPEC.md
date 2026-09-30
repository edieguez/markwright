# markwright.nvim — Specification

A Neovim plugin (LazyVim-friendly) for editing Markdown: inline formatting toggles, links, lists, headings, tables, code fences, footnotes, TOC, link diagnostics, image paste and formatting while typing.

Status: **v0.2** — updated 2026-09-30. Sections 1–13 describe what is built (decisions agreed 2026-09-29/30); section 14 specifies planned features. The **status tracker** below is the single place to see what is done. Items marked **[OPEN]** still need a decision.

---

## 0. Status tracker

`[x]` implemented and tested (headless suite) · `[ ]` not implemented. Section numbers point to the detailed spec.

### Implemented

- [x] **Skeleton** — `setup()`, config + validation, buffer-local attach, `:Markwright` with completion, `:checkhealth markwright` (§3, §4)
- [x] **Inline formatting** (§6)
  - [x] italic, bold, strikethrough, inline code, highlight toggles
  - [x] word under cursor, visual (char/line/block), operator + motion
  - [x] remove whole span from anywhere inside; `_`/`__` recognized; nesting (`***`)
  - [x] per-line multi-line wrapping, prefix skipping, whitespace trimming
  - [x] backtick escalation for inline code; code guard
  - [x] dot-repeat; one undo step per action
- [x] **Formatting while typing** — `;;` + `i`/`b`/`s`/`c`/`h`/`k`, jump out, configurable trigger (§13.2)
- [x] **Heading navigation** — `]]`/`[[`, `][`/`[]` same level, `[u` parent, `<P>o` outline via `vim.ui.select`; counts, jumplist, operators (§14.9)
- [x] **Text objects** — `ik`/`ak` link, `iu` URL, `ic`/`ac` code, `ih`/`ah` section, `i|`/`a|` cell, `iL`/`aL` list item, `i*`/`a*` emphasis; counts, empty objects, dot-repeat (§14.8)
- [x] **Links** (§7)
  - [x] link key: clipboard URL / prompt / bare URL → titled link / unlink
  - [x] async page titles (curl), domain fallback
  - [x] smart paste (`p`/`P`, visual `p`)
  - [x] macOS clipboard (`pbpaste` fallback)
- [x] **Follow (`gx`)** — anchors, files (create missing `.md`), `file.md#anchor`, images, URLs, reference links, footnotes, jumplist (§8)
- [x] **Headings** — add/remove `#`, counts, visual ranges, setext → ATX (§9.1)
- [x] **Lists** (§9.2)
  - [x] `<CR>` / `o` / `O` continuation; end on empty item; split
  - [x] `<Tab>`/`<S-Tab>` nesting with subtree
  - [x] checkbox toggle on normal `<CR>` (visual: range)
  - [x] auto-renumber (joined undo, lazy lists kept)
  - [x] completion/snippet-aware `<Tab>`/`<CR>` fallback (§13.3)
- [x] **Code fences** — typed language, wrap selection, container-aware, fence escalation (§9.3)
- [x] **Tables** — create, CSV/TSV → table, table → CSV (asks for the separator), add/delete row/column, `<Tab>` cells, align on InsertLeave (§9.4)
- [x] **Footnotes** — insert + jump (§9.5)
- [x] **TOC** — markers, nested entries, refresh on save (§9.6)
- [x] **Link diagnostics** — files, anchors, references, footnotes; on open/save; `:Markwright check` (§10)
- [x] **Image paste, macOS** — screenshots, Finder files, paths, URLs; `assets/`; alt text (§13.1)
- [x] **Tests** — 414 headless cases feeding real keys; pass on Neovim 0.10.0, 0.10.4 and 0.11 (§11)
- [x] **Verified on macOS + LazyVim** (2026-09-30): clipboard links, live titles, `gx`, image paste (screenshot / Finder / browser), `<CR>` with blink.cmp + mini.pairs, `<Tab>` in snippets/lists/tables, `;;` hint with noice, no duplicate diagnostics

### Release 0.1.0

- [x] Minimum Neovim version verified: full suite on 0.10.0, 0.10.4 and 0.11
- [x] Formatting and lint: `.stylua.toml`, `selene.toml` + `vim.yml`; code formatted, 0 selene findings
- [x] README for the public repo: installation for all major managers, keys markwright changes, known limitations, license (MPL-2.0)
- [x] `CHANGELOG.md`
- [x] `v0.1.0` git tag
- [ ] CI workflow and `Makefile` targets (`fmt`, `lint`, `check`) added to the repo — files are written; they are protected from remote writes, so they're added by hand
- [ ] Pushed to GitHub (`git push && git push --tags`)

### Not implemented

**Project / platform**
- [ ] Image paste on Linux (Wayland/X11) and WSL (§14.1)
- [ ] `:help markwright` vimdoc (§14.2)
- [ ] CI: GitHub Actions on Neovim 0.10.0, stable and nightly × Linux/macOS, plus stylua/selene (§14.3) — workflow written, see Release 0.1.0
- [x] Rename the plugin to **markwright.nvim** (§14.4)

**Small follow-ups**
- [ ] Language completion in the code fence prompt (§14.5)
- [ ] Image extras: resize/compress/convert, unused-image report (§14.6)
- [ ] Decide operator keymap names (§14.7)
- [ ] Decide partial-overlap selection behavior (§14.7)

**New features — priority 1**
- [ ] Rich-text paste (HTML → Markdown) (§14.10)

**New features — priority 2**
- [ ] GitHub callouts (§14.11)
- [ ] List tools: move items with children, sort, cycle bullets, lines ↔ list (§14.12)
- [ ] Checkbox progress counters `[2/5]` / `[40%]` (§14.13)
- [ ] Completion dates on checked tasks (§14.14)
- [ ] Table extras: sort by column, move columns, transpose, copy as CSV to the clipboard (§14.15)
- [ ] Section operations: move heading sections, promote/demote with children (§14.16)
- [ ] Inline ↔ reference link conversion (§14.17)
- [ ] Footnote renumbering (§14.18)

**New features — priority 3**
- [ ] Front matter helpers (§14.19)
- [ ] Word count / reading time (§14.20)
- [ ] Link completion for paths and `#anchors` (§14.21)
- [ ] Optional: 3-state checkboxes `[-]` (§14.22)
- [ ] Optional: external URL checker (§14.23)

---

## 1. Goals and non-goals

**Goals**
- Toggle-based editing: every formatting key adds the format if absent and removes it if present.
- Native Vim feel: works on word under cursor, visual selection and as an operator with motions; dot-repeatable.
- Treesitter-aware: decisions are made from the syntax tree, not regex guesses, wherever the grammar allows.
- Zero required dependencies beyond Neovim and the Markdown Treesitter parsers.
- Keymaps are buffer-local to Markdown and fully configurable or disableable.

**Non-goals (for now)**
- Rendering/previewing Markdown (use `render-markdown.nvim`, `markview.nvim`, a browser previewer, etc.).
- Image preview (use `snacks.nvim` / `image.nvim`).
- Wiki-style `[[note]]` links — explicitly out of scope.

---

## 2. Requirements

| Requirement | Notes |
|---|---|
| Neovim ≥ 0.10 | `vim.system`, `vim.ui.open`, modern Treesitter API |
| Treesitter parsers `markdown` and `markdown_inline` | Installed by default in LazyVim's markdown extra |
| `curl` | Only for page-title fetching; feature degrades gracefully if missing |
| System opener | `vim.ui.open` (xdg-open / open / wslview) for URLs and images |

A `:checkhealth markwright` module (`lua/markwright/health.lua`) verifies parsers, `curl`, clipboard provider and opener.

---

## 3. Architecture

```
markwright.nvim/
├── plugin/markwright.lua          -- defines :Markwright command, lazy entry point
├── lua/markwright/
│   ├── init.lua                -- setup(), attaches to markdown buffers (FileType autocmd)
│   ├── config.lua              -- defaults + user merge + validation
│   ├── keymaps.lua             -- buffer-local mappings from config
│   ├── util.lua                -- ranges, text get/set, notify, repeat helpers
│   ├── ts.lua                  -- Treesitter helpers (node at cursor, ancestors, context checks)
│   ├── format.lua              -- toggle engine (italic, bold, strike, code, highlight)
│   ├── links.lua               -- create/remove links, smart paste
│   ├── title.lua               -- async page-title fetching
│   ├── follow.lua              -- gx: URLs, files, anchors, images, footnotes
│   ├── headings.lua            -- promote/demote
│   ├── lists.lua               -- continuation, indent, checkbox, renumber
│   ├── fence.lua               -- code fence insertion
│   ├── tables.lua              -- create, CSV→table, row/col edit, align, cell nav
│   ├── footnotes.lua           -- insert, jump
│   ├── toc.lua                 -- generate/update TOC
│   ├── diagnostics.lua         -- broken link diagnostics
│   ├── slug.lua                -- GitHub-style heading anchor slugs (shared by follow/toc/diagnostics)
│   ├── doc.lua                 -- headings, definitions, footnotes, code rows (shared queries)
│   ├── images.lua              -- image paste (platform backends)
│   ├── insert.lua              -- formatting while typing (;; trigger)
│   └── health.lua
└── tests/                      -- headless specs: run.lua, helpers.lua, *_spec.lua

Planned modules (§14): textobjects.lua, nav.lua, richpaste.lua, callouts.lua, tasks.lua,
sections.lua, frontmatter.lua, stats.lua, completion.lua; images.lua gains linux/wsl backends.
```

**Attachment:** `setup()` registers a `FileType markdown` autocmd; each feature attaches buffer-local keymaps and autocmds only for that buffer. Nothing is global except the user command.

**User command:** `:Markwright <subcommand>` with completion (e.g. `:Markwright toc`, `:Markwright table create`, `:Markwright check`).

**Repeat:** operators use `operatorfunc` (`g@`) so `.` works natively. Non-operator actions set `operatorfunc` too, or use `vim-repeat` if available.

---

## 4. Configuration (defaults)

```lua
require("markwright").setup({
  filetypes = { "markdown" },
  keymaps = {
    enabled = true,
    prefix = "<leader>m",          -- used to build default mappings below
  },
  format = {
    italic    = { marker = "*" },  -- removal also recognizes _x_
    bold      = { marker = "**" }, -- removal also recognizes __x__
    strike    = { marker = "~~" },
    code      = { marker = "`" },
    highlight = { marker = "==" },
    trim_whitespace = true,        -- markers go inside leading/trailing spaces
    multiline = "per_line",        -- only mode for now
    warn_in_code = true,           -- notify when formatting inside code is skipped
  },
  insert = {
    trigger = ";;",                -- 2+ chars, a key like "<C-g>", or "" to disable
  },
  links = {
    use_clipboard = true,          -- use a URL from + register if present
    fetch_title = true,
    title_timeout_ms = 5000,
    smart_paste_visual = true,     -- visual p with URL → [sel](url)
    smart_paste_normal = true,     -- normal p with bare URL → [Title](url)
  },
  follow = {
    key = "gx",
    create_missing_md = true,      -- open buffer for non-existent .md; written on :w (mkdir -p)
  },
  lists = {
    continue_on_enter = true,
    tab_indent = true,
    auto_renumber = true,
    checkbox_add = true,           -- checkbox key on plain item adds "[ ]"
    checkbox_key = "<CR>",         -- normal/visual; "" to disable
  },
  tables = {
    align_on_insert_leave = true,
  },
  images = {
    dir = "assets",                -- relative to the file; absolute, ~, or function(buf)
    name = "image-%Y%m%d-%H%M%S",  -- default name (os.date format)
    prompt_name = true,
    alt = "name",                  -- "name" | "prompt" | "empty"
    smart_paste = false,           -- plain p pastes an image when the clipboard has one and no text
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

Planned options for §14 features are listed in each subsection and are not accepted yet.

---

## 5. Default keymaps

All buffer-local, Markdown only. `<P>` = configured prefix (default `<leader>m`). LazyVim has no default `<leader>m` group; register a which-key group `"markdown"`.

| Mode | Key | Action |
|---|---|---|
| n, x | `<P>i` | Toggle italic |
| n, x | `<P>b` | Toggle bold |
| n, x | `<P>s` | Toggle strikethrough |
| n, x | `<P>c` | Toggle inline code |
| n, x | `<P>h` | Toggle highlight |
| n | `<P>I` / `<P>B` / `<P>S` / `<P>C` / `<P>H` | Operator versions (+ motion) **[OPEN]** key choice |
| n, x | `<P>k` | Link: create / convert URL / remove |
| x | `p` | Smart paste (URL over selection → link) |
| n | `p` / `P` | Smart paste (bare URL → titled link) |
| n | `gx` | Follow link / anchor / file / image / footnote |
| n, x | `<P>=` | Heading: add a `#` (plain line → `#`; counts) |
| n, x | `<P>-` | Heading: remove a `#` (`#` → plain line) |
| n, x | `<CR>` | Toggle checkbox on list items (native elsewhere) — `lists.checkbox_key` |
| i | `<CR>` | List continuation (and `o`/`O` in normal) |
| i | `<Tab>` / `<S-Tab>` | Indent/outdent list item; next/prev table cell |
| n, x | `<P>f` | Insert / wrap code fence |
| n | `<P>n` | Insert footnote |
| n | `<P>tt` | Create table |
| x | `<P>tc` | CSV/TSV selection → table |
| n | `<P>tr` / `<P>tR` | Add row below / delete row |
| n | `<P>tk` / `<P>tK` | Add column right / delete column |
| n | `<P>ta` | Align table now |
| n | `<P>T` | Insert/update TOC |
| n, x | `<P>p` | Paste image (visual: selection = alt text) |
| i | `;;` + `i`/`b`/`s`/`c`/`h`/`k` | Formatting while typing (trigger configurable) |
| n, x, o | `]]`/`[[`, `][`/`[]`, `[u` | Heading navigation (§14.9; configurable under `nav`) |
| n | `<P>o` | Outline picker (§14.9) |
| o, x | `ik`/`ak`, `iu`, `ic`/`ac`, `ih`/`ah`, `i\|`/`a\|`, `iL`/`aL`, `i*`/`a*` | Text objects (§14.8; letters configurable under `textobjects`) |

**Planned keys** (§14; all **[OPEN]** until implemented): `<P>v` rich paste; `<P>a`/`<P>A` callouts; `<M-j>`/`<M-k>` move list items/sections; `<P>*` cycle bullet; `<P>L`/`<P>N` lines ↔ bullet/numbered list; `<P>+`/`<P>_` promote/demote with children; `<P>ts` sort table; `<P>t<`/`<P>t>` move column; `<P>r` inline ↔ reference link.

Keys already taken under `<P>`: `i b s c h I B S C H l = - f n p T tt tc tr tR tk tK ta`.

---

## 6. Formatting engine (`format.lua`)

Applies to: **italic, bold, strikethrough, inline code, highlight**.

### 6.1 Markers
| Format | Inserts | Recognized when removing | TS node |
|---|---|---|---|
| Italic | `*text*` | `*text*`, `_text_` | `emphasis` |
| Bold | `**text**` | `**text**`, `__text__` | `strong_emphasis` |
| Strike | `~~text~~` | `~~text~~` | `strikethrough` |
| Code | `` `text` `` | any backtick fence length | `code_span` |
| Highlight | `==text==` | `==text==` | none in grammar → text scan fallback |

### 6.2 Targets
- **Normal mode, no selection:** acts on the word under the cursor (`iw` semantics). If the cursor is on whitespace or an empty line, insert empty markers (`**`) and enter insert mode between them.
- **Visual mode (charwise):** acts on the selection.
- **Visual line / block:** treated as per-line (see 6.4).
- **Operator:** `<op>{motion}`, e.g. operator-italic + `ap`. Dot-repeatable.

### 6.3 Toggle logic
1. Get target range.
2. Walk Treesitter ancestors of the range start. If a node of the target format **contains the cursor/range**, remove **the whole span's** markers (e.g. cursor on "world" in `**hello world**` → `hello world`).
3. Otherwise, check whether markers sit immediately outside or at the edges of the range (covers text-level cases TS misses, and highlight). If so, remove them.
4. Otherwise, wrap the range with the configured marker.

### 6.4 Multi-line
Emphasis cannot cross blank lines, so multi-line ranges are applied **per line**:
- Skip blank lines.
- Skip leading indentation, list markers (`-`, `*`, `+`, `1.`), checkbox (`[ ]`/`[x]`), blockquote `>`, and heading `#`s.
- Wrap the remaining content of each line; within the first/last line respect the selection's column bounds.
- Toggle decision is made per line.

### 6.5 Whitespace trimming
If the selected text has leading/trailing whitespace, markers are placed inside it: `word ` → `*word* `.

### 6.6 Nesting
Formats are independent layers. Italic on `**word**` → `***word***`; removing bold from `***word***` → `*word*`. Parse combined `***`/`___` correctly.

### 6.7 Inline code specifics
- If content contains backticks, use a fence one longer than the longest backtick run inside, and pad with a space when content starts/ends with a backtick: ``a`b`` → ``` ``a`b`` ```.
- Inside a code span, other formats are not applied (see 6.8).

### 6.8 Code context guard
If the target is inside `code_span`, `fenced_code_block` or `indented_code_block`, do nothing and `vim.notify("markwright: formatting skipped inside code", WARN)` (when `warn_in_code = true`). Toggling **code itself** off inside a code span is allowed.

### 6.9 Edge cases to test
- Word adjacent to punctuation: `hello,` → `*hello*,`.
- Intraword underscore: `snake_case_word` must not be read as italic.
- Cursor on the marker characters themselves.
- Selection partially overlapping an existing span → **[OPEN]** proposed: extend to the whole span and remove.
- Escaped markers `\*` are literal.

---

## 7. Links (`links.lua`, `title.lua`)

### 7.1 Link key (`<P>k`)
| Situation | Result |
|---|---|
| Text/word, clipboard (`+`) contains a URL | `[text](url)` immediately |
| Text/word, clipboard has no URL | Prompt (`vim.ui.input`) for URL; cancel = no-op |
| Target is a bare URL | `[Page Title](url)` via async title fetch |
| Cursor on existing link (`inline_link`, reference link, `<autolink>`) | Remove link, keep text (`[text](url)` → `text`; `<url>` → `url`) |
| Nothing (whitespace) | Prompt for URL, then text; empty text → titled link (decided 2026-09-29) |
| Image `![alt](src)` | No-op with warning |

URL detection: `^%a[%w+.-]*://%S+$` plus `www.`-prefixed and `mailto:`. Trim whitespace and surrounding `<>`.

### 7.2 Smart paste
- **Visual `p`:** if `+`/unnamed register (whichever `p` would use) is a single-line URL and selection is non-empty → `[selection](url)`. Otherwise fall back to native `p` exactly (register semantics preserved, counts supported).
- **Normal `p`/`P`:** if the register is a bare URL → insert a titled link. Otherwise native behavior.
- Must not trigger inside code spans/blocks (paste URL as-is there).

### 7.3 Title fetching (`title.lua`)
- `vim.system({ "curl", "-sL", "--max-time", N, "-A", <UA>, url })`, async.
- Insert immediately as `[url](url)` (or a placeholder with an extmark tracking its position); when the title arrives, replace the text part. If the buffer changed at that location, use the extmark to find it; if the extmark is gone, drop the update.
- Parse `<title>` (also `og:title` as fallback), decode HTML entities, collapse whitespace, escape `[`/`]`.
- Failure/timeout/no curl → fall back to the domain name (`example.com`).
- Only read the first ~64 KB of the response.

---

## 8. Follow (`follow.lua`, `gx`)

Resolution order for the thing under the cursor:
1. **Footnote reference** `[^n]` → jump to `[^n]:` definition; on a definition → jump back to the (first) reference. Set a jumplist entry (`m'`) so `<C-o>` returns.
2. **Anchor** `#slug` → jump to the heading whose slug matches (see `slug.lua`).
3. **Local file** (relative to the current file's directory; absolute paths and `~` supported):
   - `.md` → `:edit` it; `path.md#anchor` → edit and jump to anchor. If missing and `create_missing_md` → open new buffer; create parent dirs on first write (`BufWritePre` mkdir -p).
   - Image extensions (`png jpg jpeg gif webp svg`) → `vim.ui.open`.
   - Other files → `:edit`.
4. **URL** → `vim.ui.open(url)`.
5. Not a link → fall back to Neovim's default `gx` behavior.

Works on inline links, reference links (resolve `[text][ref]` via `[ref]: url` definitions), autolinks, bare URLs and image links.

### Slugs (`slug.lua`)
GitHub style: lowercase, strip punctuation except `-` and `_`, spaces → `-`, keep Unicode letters (accents like `á` preserved), duplicate headings get `-1`, `-2`… suffixes.

---

## 9. Structure editing

### 9.1 Headings (`headings.lua`)
- Decided 2026-09-29: keys work on the `#` count. `<P>=` adds a `#` (plain line → `# x`, `## x` → `### x`, capped at 6); `<P>-` removes one (`# x` → plain line).
- Current line only (children are not shifted).
- Works on visual line ranges (each heading line). Setext headings (`===`/`---`) are converted to ATX first.
- Accepts a count.

### 9.2 Lists (`lists.lua`)
- **`<CR>` in insert mode on a list item:** new item with the same indentation and marker; ordered lists increment; checkboxes continue as `- [ ] `. If the current item is **empty** (only marker), remove the marker and end the list (plain empty line).
- `o`/`O` in normal mode behave the same.
- Splitting: `<CR>` in the middle of an item moves the rest of the text into the new item.
- **`<Tab>` / `<S-Tab>` in insert mode on a list item:** indent/outdent by the list's indent unit (detect from context; default 2 spaces, or content-width for ordered lists). Ordered items restart numbering at `1.` when nested.
- Must not steal `<Tab>` when the completion menu is visible or a snippet is active — see 13.3.
- **Checkbox key: `<CR>` in normal mode** (decided 2026-09-29, configurable as `lists.checkbox_key`): `- [ ] x` ↔ `- [x] x` (also `[X]`); on plain `- x` → `- [ ] x`; on a non-list line or in code → the previous/native `<CR>`. Visual: check all items in the range, or uncheck all if all are checked.
- **Renumber start rule:** the first item's number is the list's start; lazy lists (all the same number) are left alone; renumbering never runs after undo/redo and joins the triggering edit's undo step.
- **Nesting:** `<Tab>` indents to the previous sibling's content column and moves the subtree; the first item of a new ordered sublist becomes `1.` (CommonMark only lets a nested list starting at 1 interrupt a paragraph).
- **Auto-renumber:** ordered lists renumber after `<CR>`, item deletion (`TextChanged`), indent/outdent. Preserve the list's starting number and delimiter (`.` or `)`). Only the list containing the cursor, per nesting level. Debounce.

### 9.3 Code fences (`fence.lua`)
- Prompt with `vim.ui.input({ prompt = "Language: " })` — user types the language (empty allowed).
- Normal mode: insert
  ````
  ```lang
  |
  ```
  ````
  with the cursor inside, in insert mode.
- Visual (line) mode: wrap selected lines.
- If content contains ```` ``` ````, use a longer fence (```` ```` ````) or `~~~`.
- **[OPEN]** Optional completion in the prompt from installed Treesitter parser names.

### 9.4 Tables (`tables.lua`)
- **Create** (`<P>tt`): prompt `rows x cols` (e.g. `3x4`), insert header row, delimiter row and empty body rows, cursor in first header cell.
- **CSV → table** (`<P>tc`, `:'<,'>Markwright table csv`): visual selection; asks `Separator:` prefilled with the detected one (candidates `\t` `,` `;` `|` `:`; a candidate that splits every line into the same number > 1 of fields wins, most fields first; else the one splitting the first line most; else `,`). Any typed separator works, including multi-character ones; `\t`/`tab` = tab; cancel does nothing. Honor quoted fields; trim fields; first line becomes the header; escape `|` in cells. (Changed 2026-09-30: detection used to consider only `\t , ;` on the first line, so other separators produced a single column.)
- **Table → CSV** (`<P>tx`, `:Markwright table tocsv`; implemented 2026-09-30): replaces the table under the cursor with CSV lines — the opposite of `<P>tc`. Asks `Separator:` prefilled with `tables.csv_separator` (default `,`); `\t`/`tab` mean a tab, empty input means the default, cancel does nothing. Delimiter row dropped; short rows padded; fields quoted when they contain the separator, a `"` or edge spaces (quotes doubled); `\|` unescaped; indentation kept (tables in list items). One undo step; CSV → table → CSV round-trips.
- **Row/column editing:** add row below / delete row; add column right / delete column (updates delimiter row).
- **Cell navigation:** `<Tab>` / `<S-Tab>` in insert mode inside a table → next/previous cell; `<Tab>` in the last cell adds a new row.
- **Align:** pad cells so pipes line up, using display width (`vim.fn.strdisplaywidth`, for accents/CJK/emoji); respect alignment markers (`:---`, `:---:`, `---:`). Runs on `InsertLeave` when the cursor was in a table, after row/col edits, and via `<P>ta`.
- Detection via Treesitter `pipe_table` node.

### 9.5 Footnotes (`footnotes.lua`)
- Insert (`<P>n`): next number = max existing numeric footnote + 1. Insert `[^n]` at the cursor, append `[^n]: ` at the end of the file (after a blank line, grouped with other definitions), jump there in insert mode. Set a jumplist entry so `<C-o>` returns.
- Navigation via `gx` (section 8).

### 9.6 TOC (`toc.lua`)
- `<P>T` / `:Markwright toc`: insert TOC at cursor between `<!-- toc -->` and `<!-- tocstop -->`, or regenerate if markers exist.
- On `BufWritePre`, if markers exist and `update_on_save`, regenerate (no-op if unchanged, so the buffer isn't modified needlessly).
- Nested `-` list of `[Heading](#slug)` entries, respecting `min_level`/`max_level`. Skip headings inside code blocks and the TOC itself.

---

## 10. Diagnostics (`diagnostics.lua`)

On `BufWritePost` (and on attach), publish `vim.diagnostic` entries in namespace `markwright` for:
- Relative file links/images whose target doesn't exist.
- `#anchor` links (local or `file.md#anchor`) with no matching heading.
- Footnote references without definitions, and definitions never referenced.
- Reference links `[text][ref]` with no `[ref]:` definition.

External URLs are **not** checked. Skip code blocks/spans. Diagnostics are kept until the next save (decided 2026-09-29).

Implementation note: the markdown grammar has no footnotes, and a `[ref]: url` line directly after a footnote definition is parsed as paragraph text, so footnotes and link reference definitions are found by a line scan that skips code rows and code spans.

---

## 11. Testing

- Framework: `mini.test` (or plenary/busted) with headless Neovim in CI (GitHub Actions, Neovim stable + nightly, parsers installed).
- Each feature gets table-driven cases: input buffer + cursor/selection + keys → expected buffer + cursor.
- Required cases include all edge cases in 6.9, nesting in 6.6, multi-line in 6.4, backtick escalation, smart paste fallbacks, list continuation/termination, renumbering, table alignment with multibyte text, slug generation with accents and duplicates.
- Title fetching tested with a mocked `vim.system`.

---

## 12. Implementation order

- [x] 1. Skeleton: `setup`, config, FileType attach, keymaps, `:Markwright`, health.
- [x] 2. `ts.lua` + `format.lua` (engine, operators, repeat).
- [x] 3. `links.lua` + `title.lua` + smart paste.
- [x] 4. `follow.lua` + `slug.lua`.
- [x] 5. `lists.lua`, `headings.lua`.
- [x] 6. `fence.lua`, `footnotes.lua`.
- [x] 7. `tables.lua`.
- [x] 8. `toc.lua`, `diagnostics.lua`.
- [x] 9. `images.lua` (macOS), `insert.lua`.
- [x] 10. Rename to markwright.nvim (§14.4).
- [ ] 11. Priority-1 features: ~~text objects~~, ~~heading navigation~~ (done), rich-text paste (§14.8–14.10).
- [ ] 12. Priority-2 features (§14.11–14.18).
- [ ] 13. Linux/WSL image paste, image extras, fence completion (§14.1, §14.5, §14.6).
- [x] 10b. Release 0.1.0 preparation: Neovim 0.10 check, stylua/selene, CHANGELOG, tag (see §0 Release 0.1.0).
- [ ] 14. Docs (`doc/markwright.txt`) and CI (§14.2, §14.3) — CI workflow written, to be added to the repo.
- [ ] 15. Priority-3 and optional features (§14.19–14.23).

---

## 13. Pending / parked features

### 13.1 Image paste — **implemented for macOS (2026-09-29)**
Decisions (all configurable under `images`):
- Key `<P>p` (normal; visual = selection becomes alt text and is replaced), `:Markwright image`; opt-in plain `p` when the clipboard holds an image and no text (`smart_paste`).
- Sources: image data (saved as PNG), a Finder file (copied, format kept; detected via `«class furl»` before the icon image), a copied local image path (copied), a copied image URL (linked, not downloaded).
- Backend: `pngpaste` when installed, else `osascript` (built in). Async via `vim.system`.
- Save to `assets/` next to the file (relative, absolute, `~` or function); created on demand; name prompt prefilled with `image-%Y%m%d-%H%M%S` (Finder: original name); sanitized; never overwrites (`-1`, `-2`…).
- Link path relative to the file, spaces/parens URL-encoded. Alt text from a typed name (default timestamp → empty), or `prompt` / `empty`.
- Still open: Linux/WSL backends (`wl-paste`, `xclip`, `powershell.exe`), compression/WebP, cleanup of unreferenced images.

### 13.2 Insert-mode formatting keys — **implemented (2026-09-30)**
- Trigger `;;` (config `insert.trigger`: 2+ characters, a key like `<C-g>`, or `""` to disable), then `i` `b` `s` `c` `h` `k`. Chosen for portability: plain characters work in every terminal and layout; `<C-m>` (= Enter), `<C-i>` (= Tab), Option/Meta keys and completion-plugin keys were ruled out.
- No timeout: only the trigger's last character is mapped, and it fires only when the preceding characters were just typed in sequence (tracked with InsertCharPre). The menu then waits for the key with no time limit (`getcharstr`) and shows a hint.
- Unknown key → the trigger text plus that key are typed as-is; `<Esc>` restores the trigger and leaves insert mode. Key triggers pass unknown keys to their previous meaning (`<C-g>u`, plugin mappings).
- Pressing the same format again right before its closing marker jumps out (tracked with extmarks; falls back to the text shape for pairs typed by hand). Links go text → URL → out; a clipboard URL skips the URL stage.
- Off in code blocks; in inline code only `c` (jump out) right before the closing backtick.

### 13.3 `<Tab>`/`<CR>` conflict with completion/snippets — **resolved (2026-09-29)**
Shared helper in `util.lua` (`completion_active`, `save_fallback`, `fallback`): insert-mode `<Tab>`/`<S-Tab>`/`<CR>` act only in a table or on a list item and when no completion menu (blink.cmp, nvim-cmp, pum) or snippet is active. Otherwise they call the mapping that existed when the buffer attached (captured with `maparg`, e.g. mini.pairs `<CR>`), or the native key. Verified on macOS with blink.cmp and mini.pairs (2026-09-30).

### 13.4 Open questions collected
- Operator keymap names (section 5) — see §14.7.
- ~~Heading keys (9.1)~~ — resolved: `<P>=` adds `#`, `<P>-` removes.
- Partial-overlap selection behavior (6.9) — see §14.7.
- ~~Link key on whitespace (7.1)~~ — resolved: prompt URL, then text; empty text → page title.
- ~~Checkbox key on a non-list line (9.2)~~ — resolved: native `<CR>`.
- Fence language prompt completion (9.3) — planned, §14.5.
- TOC default level range (4 / 9.6) — shipped with 2–4.
- ~~Diagnostics lifetime between saves (10)~~ — implemented as proposed: kept until the next save; `:Markwright check` re-runs on demand.
- Checkbox 3-state (`[-]`) — optional, §14.22.
- External URL checking — optional on-demand command, §14.23.

### 13.5 Explicitly out of scope
- Wiki-style `[[links]]`.
- Rendering/preview.

---

## 14. Planned features

Conventions for everything below (same as the built features): buffer-local, Markdown only; code blocks/spans are skipped unless stated; each action is one undo step; normal-mode actions are dot-repeatable where it makes sense; every key and behavior is configurable or can be disabled; keys marked **[OPEN]** are proposals. Each feature ships with a `*_spec.lua` and README section.

### 14.1 Image paste on Linux and WSL
Extends §13.1 with backends behind the same `backend()` interface (`info`, `save_image`, `file_path`).

| Platform | Detect | Save image data | Copied file |
|---|---|---|---|
| Wayland | `wl-paste --list-types` | `wl-paste --type image/png > path` (convert other types if listed) | `text/uri-list` → `file://` path |
| X11 | `xclip -selection clipboard -t TARGETS -o` | `xclip -selection clipboard -t image/png -o > path` | `text/uri-list` |
| WSL | `powershell.exe` `Get-Clipboard -Format Image` | .NET `Image.Save()` to a Windows temp path, then `wslpath -u` and move | `Get-Clipboard -Format FileDropList` + `wslpath` |

- Backend choice: `$WAYLAND_DISPLAY` → wl-paste; `$DISPLAY` → xclip; `/proc/version` contains `microsoft` → WSL. Config `images.backend = "auto"` (or force one).
- `:checkhealth` reports the detected backend and missing tools.
- Tests: fake executables per backend, like the macOS ones.

### 14.2 `:help markwright`
- `doc/markwright.txt` in vimdoc format with tags (`markwright`, `markwright-config`, `markwright-keymaps`, `markwright-<feature>`, `:Markwright`).
- Generated from README.md with panvimdoc in CI (commit the result) so the two never drift; README stays the source.
- Acceptance: `:helptags` runs clean; every config key and command has a tag.

### 14.3 CI
- GitHub Actions: matrix Neovim `v0.10.x` (minimum), `stable`, `nightly` × `ubuntu-latest`, `macos-latest`.
- Steps: install Neovim, `make test`, `stylua --check`, `selene` (lint).
- Run on push and pull requests; badge in README.

### 14.4 Rename the plugin — **done (2026-09-30)**
- New name **markwright.nvim** (a "wright" is a craftsman, as in playwright). Checked 2026-09-30: no Neovim plugin uses it; unrelated projects share the name (a Flask Markdown viewer, a desktop-publishing app).
- Renamed: `lua/markwright/`, `plugin/markwright.lua`, `require("markwright")`, `:Markwright`, `:checkhealth markwright`, namespaces/augroups (`markwright_*`), notification prefix, diagnostic source, README, SPEC, tests.
- No `require("mdtools")` compatibility shim: the plugin was never published.

### 14.5 Code fence language completion
- The `Language:` prompt completes from: installed Treesitter parsers (`vim.api.nvim_get_runtime_file("parser/*.so", true)`), languages already used in fences in the current buffer (first), and a short common list.
- Uses `vim.ui.input({ completion = "customlist,..." })` so it works with the native prompt and with snacks/dressing inputs.
- Typing stays free-form; completion is only a help.

### 14.6 Image extras
- **Resize/compress/convert** after saving (§13.1): `images.max_width` (pixels, nil = keep), `images.convert = nil | "jpeg" | "webp" | "png"`, `images.quality = 85`.
  - macOS: built-in `sips` (`sips -Z <max> -s format jpeg -s formatOptions <q>`); WebP via `cwebp` when installed.
  - Linux: ImageMagick `magick`/`convert`, `cwebp`.
  - Missing tool → keep the original and warn once.
- **Unused images**: `:Markwright images unused` scans Markdown files under the project root (git root, else cwd) for references into the image folders, lists files nothing links to in the quickfix list. Never deletes on its own; `:Markwright images unused!` asks for confirmation per file.

### 14.7 Pending decisions on built features
- **Operator keys**: currently `<P>I`/`<P>B`/`<P>S`/`<P>C`/`<P>H` + motion. Options: keep; or `gm` + format letter + motion (`gmbiw`), freeing uppercase `<P>` keys for the features below.
- **Partial-overlap selections** (selection covers part of a span): currently removes the whole span. Alternative: shrink the span to exclude the selection (`**hello world**`, select `world` → `**hello** world`). Decide, then test both edge directions.

### 14.8 Text objects — **implemented (2026-09-30)**

| Object | `i` (inner) | `a` (around) | Keys |
|---|---|---|---|
| Link | link text; image alt text; the URL inside `<…>`; a bare URL | whole `[text](url)` / `![alt](src)` / `<url>` / reference link | `ik` / `ak` |
| Link URL | destination (inside `<…>` if bracketed); for reference links, the URL on the `[ref]:` line | — | `iu` |
| Code | inline code: content (without padding spaces) · block: lines between the fences | with backticks · whole block (trailing blank lines excluded) | `ic` / `ac` |
| Heading section | content under the heading, blank lines at both ends trimmed | heading + content up to the next heading of the same or higher level | `ih` / `ah` |
| Table cell | trimmed cell text | cell incl. padding (between the pipes) | `i\|` / `a\|` |
| List item | item text (no marker/checkbox), incl. continuation lines of its paragraph | item + its children (line-wise) | `iL` / `aL` |
| Emphasis | inside `*`, `**`, `~~`, `==` (innermost) | including the markers | `i*` / `a*` |

- Decided 2026-09-30: link text uses **`ik`/`ak`** (not `il`/`al`, which mini.ai uses as its "last" prefix); `k` also became the link key everywhere (`<P>k`, `;;k`).
- Operator-pending and visual modes, buffer-local in Markdown. Implemented as `expr` mappings: the range is computed, then selected through a `<Cmd>` that recomputes it at execution time, so dot-repeat works at the new cursor position.
- Counts climb outward: `2ah` parent section, `2aL` parent item, `2i*` next enclosing span.
- Links, bare URLs and emphasis fall back to the first match after the cursor on the same line (like `ci"`).
- Empty objects (`[](u)`, empty fence, empty cell): the operator is cancelled; for `c`, insert mode starts at the spot.
- Section, code-block and around-item objects are line-wise; the rest are character-wise.
- Config `textobjects = { enabled, link, url, code, section, cell, item, emphasis }` (letters; `false`/`""` disables one). In Markdown buffers `ic`/`ac` and `iu` take priority over LazyVim mini.ai's class / function-call objects.
- Built on Treesitter nodes (`inline_link`, `image`, `link_text`, `image_description`, `link_destination`, `code_span`, `fenced_code_block`, `indented_code_block`, `list_item`, `emphasis`, `strong_emphasis`, `strikethrough`), `doc.headings()` for sections, `tables.split_row()` for cells, and a line scan for `==highlight==`.

### 14.9 Heading navigation — **implemented (2026-09-30)**
- `]]` / `[[`: next / previous heading of any level; counts; skips headings inside code blocks; setext headings count; jumplist entry in normal/visual mode; column 0. Replace the markdown ftplugin's buffer-local `]]`/`[[`.
- `][` / `[]`: next / previous heading of the **same level** as the current section, never crossing a lower-level (parent) heading. From inside a section, `[]` first goes to the section's own heading (like Vim's `[[`). Before any heading, `][` goes to the first heading.
- `[u`: parent heading (nearest previous heading of a lower level); counts climb further.
- All motions work in normal, visual and operator-pending mode (`<Cmd>` motions → exclusive; Vim's exclusive-linewise rule makes `d]]` linewise, like the built-in `]]`).
- `<P>o` / `:Markwright outline`: `vim.ui.select` over all headings, labelled `› ` (current section) + indentation + `#`×level + text; jumps with a jumplist entry and `zv`. Decided: `vim.ui.select` instead of picker-specific code — LazyVim routes it to snacks.picker; telescope/fzf-lua when registered; built-in list otherwise.
- Config `nav = { enabled, next, prev, next_sibling, prev_sibling, parent, outline }`; `outline = nil` means `<prefix>o`; `false`/`""` disables a key.

### 14.10 Rich-text paste (priority 1)
- `<P>v` **[OPEN]** / `:Markwright paste`: paste the clipboard's HTML (copied from a browser, Google Docs, Notion, Word…) converted to Markdown: headings, bold/italic, links, lists, tables, code.
- Reading HTML: macOS via JXA `NSPasteboard.generalPasteboard.stringForType("public.html")`; Wayland `wl-paste -t text/html`; X11 `xclip -t text/html -o`; WSL `Get-Clipboard -TextFormatType Html`.
- Conversion: `pandoc -f html -t gfm-raw_html --wrap=none`; post-process to the plugin's style (bullet `-`, `**`/`*` markers, strip empty links and tracking parameters optional).
- No HTML on the clipboard → normal paste of the text. No pandoc → plain-text paste + one warning; `:checkhealth` reports pandoc.
- Optional: `rich_paste.smart = false` — when true, plain `p` converts automatically if HTML is present.
- Pasted block is one undo step; relative links in the HTML are resolved against its source URL when the clipboard provides it.

### 14.11 GitHub callouts (priority 2)
- `<P>a` **[OPEN]**: wrap the current paragraph (normal) or selected lines (visual) in a callout; types `NOTE`, `TIP`, `IMPORTANT`, `WARNING`, `CAUTION` via a picker (default `NOTE`).
- On an existing callout, `<P>a` cycles the type; `<P>A` removes the callout (unwraps the `>` prefix).
- Handles nested blockquotes and keeps list/code content intact; `:Markwright callout [type]`.

### 14.12 List tools (priority 2)
- Move an item with its children: `<M-j>`/`<M-k>` **[OPEN]** on a list item swaps it with the next/previous sibling subtree and renumbers; elsewhere falls back to the existing mapping (LazyVim's move-line). Also `:Markwright list up|down`.
- Sort: `:Markwright list sort [alpha|checked|reverse]` sorts the siblings under the cursor (children move with their parent; `checked` puts done tasks last).
- Cycle bullet style for the list under the cursor: `<P>*` **[OPEN]** `-` → `*` → `+` → `1.` → `-`.
- Lines ↔ list: `<P>L` **[OPEN]** toggles plain lines ↔ bullet list, `<P>N` **[OPEN]** plain lines ↔ numbered list (visual or current paragraph).

### 14.13 Checkbox progress (priority 2)
- A parent item containing a cookie `[/]` or `[%]` (typed by the user, org-mode style) shows its children's progress: `- Release [2/5]` / `- Release [40%]`.
- Updated whenever a child checkbox is toggled by the plugin, and on save; nested counts roll up. Items without a cookie are never changed.
- Config `lists.progress = true`.

### 14.14 Completion dates (priority 2)
- Opt-in `lists.done_date = false | "✅ %Y-%m-%d"`: checking an item appends the formatted date; unchecking removes it. Compatible with the Obsidian Tasks format.

### 14.15 Table extras (priority 2)
- `<P>ts` **[OPEN]**: sort body rows by the column under the cursor (ascending; again → descending); numeric- and date-aware; header and delimiter stay.
- `<P>t<` / `<P>t>` **[OPEN]**: move the current column left/right (alignment markers move with it).
- Table → CSV in the buffer is implemented (§9.4). Still open: a variant that copies the CSV to the clipboard instead of replacing the table (`:Markwright table tocsv!` **[OPEN]**).
- `:Markwright table transpose`.

### 14.16 Section operations (priority 2)
- Move the heading section under the cursor (heading + content + sub-sections) past the previous/next sibling section: `<M-k>`/`<M-j>` **[OPEN]** on a heading line (shares keys with §14.12), `:Markwright section up|down`.
- Promote/demote a heading together with all its sub-headings: `<P>+` / `<P>_` **[OPEN]** (the single-line `<P>=`/`<P>-` stay).
- TOC updates on save as usual.

### 14.17 Inline ↔ reference links (priority 2)
- `<P>r` **[OPEN]** on a link toggles inline `[text](url)` ↔ reference `[text][label]` with `[label]: url` collected in a block at the end of the file (label from the text's slug; numeric labels optional).
- `:Markwright links reference` / `:Markwright links inline` convert the whole buffer; duplicate URLs share one definition; unused definitions are removed.

### 14.18 Footnote renumbering (priority 2)
- `:Markwright footnote renumber`: renumber numeric footnotes by order of first reference and reorder their definitions; named footnotes are left alone.
- Optional `footnotes.renumber_on_save = false`.

### 14.19 Front matter helpers (priority 3)
- `:Markwright frontmatter`: insert a YAML block from a template (config `frontmatter.template`, placeholders `{title}` from the first heading or file name, `{date}`, `{tags}`).
- `frontmatter.update_on_save = false`: when enabled, refresh an existing `updated:`/`lastmod:` field on save (never adds one).
- Front matter is ignored by TOC, slugs, diagnostics and word count.

### 14.20 Word count / reading time (priority 3)
- `require("markwright").stats(buf?)` → `{ words, chars, reading_minutes }`, excluding front matter, code blocks, URLs and markup; uses the visual selection when active.
- `:Markwright stats` shows the numbers; README includes a lualine component snippet. Reading speed configurable (`stats.wpm = 200`).

### 14.21 Link completion (priority 3)
- blink.cmp / nvim-cmp source: file paths after `](`, headings after `#` (`](#` and `](file.md#`), reference labels after `][`.
- Low priority because LazyVim's marksman language server already provides most of this; the source is off by default and documented as the alternative when marksman isn't used.

### 14.22 Optional: 3-state checkboxes (priority 3)
- `lists.checkbox_states = { " ", "x" }` by default; setting `{ " ", "-", "x" }` makes the checkbox key cycle `[ ]` → `[-]` → `[x]`. Visual range and progress (§14.13) count `[-]` as not done.

### 14.23 Optional: external URL checker (priority 3)
- `:Markwright check urls`: async HEAD (falling back to GET) requests with `curl` for every external link in the buffer, limited concurrency and timeout; results as diagnostics (`link returns 404`) and in the quickfix list. Never runs automatically.
