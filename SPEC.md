# markwright.nvim — Specification

A Neovim plugin (LazyVim-friendly) for editing Markdown: inline formatting toggles, links, lists, headings, tables, code fences, footnotes, TOC, link diagnostics, image paste and formatting while typing.

Status: **4.0.0 released** — updated 2026-10-06. Sections 1–13 describe what is built (decisions agreed 2026-09-29/30); section 14 specifies planned features. The **status tracker** below is the single place to see what is done. Items marked **[OPEN]** still need a decision.

---

## 0. Status tracker

`[x]` implemented and tested (headless suite) · `[ ]` not implemented. Section numbers point to the detailed spec.

### Implemented

- [x] **Skeleton** — `setup()`, config + validation, buffer-local attach, `:Markwright` with completion, `:checkhealth markwright` (§3, §4)
- [x] **Inline formatting** (§6)
  - [x] italic, bold, strikethrough, inline code, highlight toggles
  - [x] smart key: at once inside a span (removes it) or on whitespace (empty pair), else operator + motion (`<P>biw`, `<P>b$`, `_` = line, count = lines); no doubled keys; visual (char/line/block)
  - [x] remove whole span from anywhere inside; `_`/`__` recognized; nesting (`***`)
  - [x] per-line multi-line wrapping, prefix skipping, whitespace trimming
  - [x] backtick escalation for inline code; code guard
  - [x] dot-repeat; one undo step per action
- [x] **Formatting while typing** — `;;` + `i`/`b`/`s`/`c`/`h`/`k`, jump out, configurable trigger; `;;n` footnote, `;;p` image (§13.2)
- [x] **External URL checker** — `:Markwright check urls`: async curl HEAD→GET, concurrency/timeout, broken = warning, 401/403/429 = info, diagnostics + quickfix (§14.23)
- [x] **GitHub callouts** — `<P>a` wrap paragraph / selection / code block (type picker) or change type (picker again), `<P>A` remove, plain quote → callout, `:Markwright callout`, `<CR>`/`o`/`O` continue quotes (§14.11)
- [x] **Heading navigation** — `]]`/`[[`, `][`/`[]` same level, `[u` parent, `<P>o` outline via `vim.ui.select`; counts, jumplist, operators (§14.9)
- [x] **Text objects** — `ik`/`ak` link, `iu` URL, `ic`/`ac` inline code, `if`/`af` code block, `i#`/`a#` section, `iz`/`az` cell, `ix`/`ax` list item, `i*`/`a*` emphasis; counts, empty objects, dot-repeat (§14.8)
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
- [x] **Tables** — create, CSV/TSV → table, table → CSV (asks for the separator), add row below/above (`<P>tj`/`<P>tk`), column left/right (`<P>th`/`<P>tl`), delete (`<P>tdr`/`<P>tdc`), `<Tab>` cells, align on InsertLeave (§9.4)
- [x] **Footnotes** — insert + jump (§9.5)
- [x] **TOC** — markers, nested entries, refresh on save (§9.6)
- [x] **Link diagnostics** — files, anchors, references, footnotes; on open/save; `:Markwright check` (§10)
- [x] **Image paste, macOS** — screenshots, Finder files, paths, URLs; `assets/`; alt text (§13.1)
- [x] **Tests** — 658 headless cases feeding real keys; pass on Neovim 0.10.0, 0.10.4 and 0.11 (§11)
- [x] **Verified on macOS + LazyVim** (2026-09-30): clipboard links, live titles, `gx`, image paste (screenshot / Finder / browser), `<CR>` with blink.cmp + mini.pairs, `<Tab>` in snippets/lists/tables, `;;` hint with noice, no duplicate diagnostics

### Release 1.0.0

- [x] Minimum Neovim version verified: full suite on 0.10.0 and 0.11
- [x] Formatting and lint: `.stylua.toml`, `selene.toml` + `vim.yml`; code formatted, 0 selene findings
- [x] README for the public repo: installation for all major managers, keys markwright changes, known limitations, license (MPL-2.0)
- [x] CI workflow and `Makefile` targets (`fmt`, `lint`, `check`)
- [x] `CHANGELOG.md`, `v1.0.0` git tag (2026-10-02; earlier tags v0.1.0, v0.1.1 and v2.0.0 were removed and folded into 1.0.0)
- [x] Pushed to GitHub with the `v1.0.0` tag (2026-10-02)

### Releases after 1.0.0

Tagged on the commits that introduced them; details in `CHANGELOG.md`. A major version marks every release that changed default keys.

- [x] `v2.0.0` — table keys on `h`/`j`/`k`/`l`, image rename, callout-marker and undo fixes
- [x] `v2.1.0` — table extras (move, sort, transpose, copy as CSV)
- [x] `v2.2.0` — completion dates
- [x] `v2.3.0` — checkbox progress counters
- [x] `v2.4.0` — list tools (move, sort, converters)
- [x] `v3.0.0` — keymap review with mnemonics, `s`/`S` sorting, one-level converters with checklist protection
- [x] `v3.1.0` — `;;n` footnote and `;;p` image while typing
- [x] `v3.2.0` — progress counters on the heading or line above a checklist
- [x] `v3.3.0` — word count and reading time
- [x] `v3.3.1` — list renumbering: remembered start numbers, edits away from the cursor
- [x] `v3.3.2` — dot-repeat for every buffer-changing key, with reused prompt answers
- [x] `v3.3.3` — `N.` repeats with the new count
- [x] `v3.3.4` — tables with empty rows found from the lines, not the tree
- [x] `v3.4.0` — counts on table add/delete keys; table keys in visual mode (delete, move, sort the selection)
- [x] `v3.5.0` — a command for every buffer-changing key (heading, checkbox, table move, fromcsv; counts and ranges); consistent warnings
- [x] `v4.0.0` — `<P>f` on a paragraph wraps it (like `<P>a`); empty line → empty block

### Not implemented

**Project / platform**
- [ ] Image paste on Linux (Wayland/X11) and WSL (§14.1)
- [ ] `:help markwright` vimdoc (§14.2)
- [x] CI: GitHub Actions on Neovim 0.10.0, stable and nightly × Linux/macOS, plus stylua/selene (§14.3)
- [x] Rename the plugin to **markwright.nvim** (§14.4)

**Small follow-ups**
- [ ] Language completion in the code fence prompt (§14.5)
- [ ] Image extras: resize/compress/convert, unused-image report (§14.6)
- [x] Decide operator keymap names (§14.7) — `<P>{i,b,s,c,h}` are operators; uppercase variants removed (2026-09-30)
- [ ] Decide partial-overlap selection behavior (§14.7)

**New features — priority 2**
- [x] List tools: move items with children, sort, convert lines ↔ bullets / numbers / checkboxes — `<P>l…` (§14.12)
- [x] Checkbox progress counters `[2/5]` / `[40%]`, on parent items and on the heading or line above a list (§14.13)
- [x] Completion dates on checked tasks, with time: `lists.done_date` (§14.14)
- [x] Table extras: move columns/rows (`<P>tH/tL/tJ/tK`), sort (`<P>ts`), flip/transpose (`<P>tf`), copy as CSV (`<P>ty`) (§14.15)
- [ ] Section operations: move heading sections, promote/demote with children (§14.16)
- [ ] Inline ↔ reference link conversion (§14.17)
- [ ] Footnote renumbering (§14.18)

**New features — priority 3**
- [ ] Front matter helpers (§14.19)
- [x] Word count / reading time: `:Markwright stats`, statusline component (§14.20)
- [ ] Link completion for paths and `#anchors` (§14.21)
- [ ] Optional: 3-state checkboxes `[-]` (§14.22)

**Later (a future major version)**
- [ ] Rich-text paste (HTML → Markdown) (§14.10) — set aside 2026-09-30 as too large; planned for a later major version

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
| n | `<P>i` / `<P>b` / `<P>s` / `<P>c` / `<P>h` | Toggle italic / bold / strikethrough / inline code / highlight: at once inside a span of that format (remove) or on whitespace (empty pair); on text, operator (`<P>biw`, `<P>c$`, `<P>b_`) |
| x | `<P>i` / `<P>b` / `<P>s` / `<P>c` / `<P>h` | Toggle on the selection |
| n | `<P>k` | Link: at once on a link (remove), bare URL (titled link), whitespace (new link: URL prompt prefilled with a clipboard URL, then text); on text, operator (`<P>kiw`, `<P>k$`) |
| x | `<P>k` | Link the selection, or remove the link it's in |
| x | `p` | Smart paste (URL over selection → link) |
| n | `p` / `P` | Smart paste (bare URL → titled link) |
| n | `gx` | Follow link / anchor / file / image / footnote |
| n, x | `<P>=` | Heading: add a `#` (plain line → `#`; counts) |
| n, x | `<P>-` | Heading: remove a `#` (`#` → plain line) |
| n, x | `<CR>` | Toggle checkbox on list items (native elsewhere) — `lists.checkbox_key` |
| i | `<CR>` | List continuation (and `o`/`O` in normal) |
| i | `<Tab>` / `<S-Tab>` | Indent/outdent list item; next/prev table cell |
| n, x | `<P>f` | Insert / wrap code fence (block key: acts at once) |
| n | `<P>n` | Insert footnote |
| n | `<P>tt` | Create table |
| n, x | `<P>tc` | CSV/TSV lines → table: the paragraph under the cursor (n) or the selection (x) |
| n | `<P>tC` | Table → CSV (asks for the separator); `<P>ty` copies instead |
| n | `<P>th` / `<P>tl` | Add column left / right |
| n | `<P>tj` / `<P>tk` | Add row below / above (not above the header) |
| n | `<P>tdr` / `<P>tdc` | Delete row / column |
| n | `<P>tH` / `<P>tL` · `<P>tJ` / `<P>tK` | Move column left / right · row down / up (`[count]`) |
| n | `<P>ts` / `<P>tS` · `<P>tf` · `<P>ty` | Sort by column ascending / descending · flip (transpose) · copy as CSV (§14.15) |
| n | `<P>ta` | Align table now |
| n | `<P>O` | Insert/update the table of contents (the outline written into the file) |
| n, x | `<P>p` | Paste image (visual: selection = alt text) |
| n | `<P>P` | Rename the image file under the cursor and update its links in the buffer (§13.1) |
| i | `;;` + `i`/`b`/`s`/`c`/`h`/`k` | Formatting while typing (trigger configurable) |
| n, x, o | `]]`/`[[`, `][`/`[]`, `[u` | Heading navigation (§14.9; configurable under `nav`) |
| n | `<P>o` | Outline picker (§14.9) |
| n | `<P>lJ` / `<P>lK` · `<P>ls` / `<P>lS` · `<P>ld` | List: move item with children · sort A→Z / Z→A · done last (§14.12) |
| n, x | `<P>lb` / `<P>ln` / `<P>lc` (`B`/`N`/`C`) | List converters: this level (and below) → bullets / numbers / checkboxes (§14.12) |
| n, x | `<P>a` | Callout: wrap paragraph (n) / selection (x), or change type, both with the type picker (§14.11). Block key: acts at once |
| n | `<P>A` | Remove callout (§14.11) |
| o, x | `ik`/`ak`, `iu`, `ic`/`ac`, `if`/`af`, `i#`/`a#`, `iz`/`az`, `ix`/`ax`, `i*`/`a*` | Text objects (§14.8; letters configurable under `textobjects`) |

**Planned keys** (§14; all **[OPEN]** until implemented): `<P>v` rich paste (later); move sections; `<P>+`/`<P>_` promote/demote with children; inline ↔ reference link (`<P>r`, free since image rename moved to `<P>P`). (List tools ended up under `<P>l…`, table extras under `<P>t…`.)

**Mnemonic rules** (keymap review, 2026-10-03): each letter means one thing at the top level and in text objects (`c` inline code, `f` fence, `h` highlight, `k` link, `#` heading section); inside a submenu (`<P>t…`, `<P>l…`) letters may mean something else (`tc` CSV, `lc` checkbox, `tf` flip). At the top level uppercase is the companion or reverse of lowercase (`a`/`A` callout wrap/remove, `o`/`O` outline / table of contents, `p`/`P` paste / rename image); in submenus uppercase moves (`tH tJ tK tL`, `lJ lK`), sorts descending (`S`), reverses (`tC`) or reaches deeper (`lB lN lC`).

Keys taken under `<P>`: `i b s c h k f n = - a A o O p P t… l…` (`r` reserved for inline ↔ reference links).

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
- **Normal mode (smart key, 2026-10-01):** act at once when there's nothing to choose, wait for a motion when there's text to choose. On whitespace / an empty line → insert empty markers and enter insert mode between them. Inside a span of that format (markers included), or in code → toggle the word under the cursor at once (removes the span / warns in code). Otherwise → operator: waits for a motion or text object (`<P>biw`, `<P>b2e`, `<P>c$`, `<P>bip`); `_` is the current line (`<P>b_`, `[count]` lines). No doubled keys (`<P>ii` would shadow `i{object}`). The cursor stays on the same character. Dot-repeatable. (History 2026-09-30: the key used to act on the word at once, with uppercase `<P>B` etc. as operators; then it was a pure operator for a day.)
- **Empty markers:** the key (or `:Markwright bold`, etc.) on whitespace or an empty line inserts an empty pair and enters insert mode between them; in insert mode, `;;b`.
- **Visual mode (charwise):** acts on the selection.
- **Visual line / block:** treated as per-line (see 6.4).

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
`<P>k` is a smart key (2026-10-01): at once on a link (remove), an image or code (warning), a bare URL (titled link) or whitespace (new link: a URL prompt prefilled with the clipboard URL when it holds one, so it's visible before use and Enter accepts it; then a prompt for the text, empty = page title); on plain text it waits for a motion (`<P>kiw`, `<P>k$`). Visual acts on the selection. `:Markwright link` uses the word under the cursor instead of waiting.

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
- **Renumber start rule** (revised 2026-10-06): each ordered list's start is remembered on an extmark spanning its first item's line (`invalidate = true`, right gravity), refreshed after every pass. If that line is still the first item, its number is the start (so typing a new first number restarts the list). If the first item was deleted (the mark is invalid) or lines were pasted above it (the mark moved down), the remembered start is used. Lists never seen before start at their first number. Lazy lists (all the same number) are left alone, except a list remembered as non-lazy (`1. a` duplicated with `yyp` becomes `1.` `2.`). Renumbering never runs after undo/redo (the starts are re-remembered) and joins the triggering edit's undo step.
- **Sub-lists that lose their first item:** CommonMark only lets an ordered list interrupt a paragraph when it starts at 1, so deleting `   1. x` under `1. a` would turn `   2. y` into paragraph text. When a list remembered as starting at 1 lost its first item and the line now in its place isn't a list item, its number is set back to 1.
- **Nesting:** `<Tab>` indents to the previous sibling's content column and moves the subtree; the first item of a new ordered sublist becomes `1.` (CommonMark only lets a nested list starting at 1 interrupt a paragraph).
- **Auto-renumber:** ordered lists renumber after `<CR>`, `o`/`O`, indent/outdent, normal-mode changes and Ex commands (`TextChanged`) and on InsertLeave. Changed rows are tracked with `nvim_buf_attach` `on_lines`, so every list touched since the last pass is renumbered, not only the one at the cursor (`:g`, `:m`, `:d` elsewhere). Preserve the list's starting number and delimiter (`.` or `)`).

### 9.3 Code fences (`fence.lua`)
- **Revised 2026-10-06 (4.0.0):** normal-mode `<P>f` follows the block-key rule of `<P>a`: on a paragraph (run of non-empty lines; a line that is only `>`/spaces counts as empty) it wraps the paragraph, repeatable with `.` reusing the language; on an empty line it inserts an empty block, prefixed with the line's indentation or `>` prefix so it stays in a list item or quote. Wrapping uses the lines' common `^[%s>]*` prefix. The bullets below describe the original 1.x–3.x behavior where they differ.
- Prompt with `vim.ui.input({ prompt = "Language: " })` — user types the language (empty allowed).
- Normal mode: insert
  ````
  ```lang
  |
  ```
  ````
  with the cursor inside, in insert mode.
- Visual (line) mode: wrap selected lines. (Considered and rejected 2026-09-30: `<P>f` as an operator. Inserting a new fence is the common case and would become `<P>f_`; keys that insert something new stay direct actions.)
- If content contains ```` ``` ````, use a longer fence (```` ```` ````) or `~~~`.
- **[OPEN]** Optional completion in the prompt from installed Treesitter parser names.

### 9.4 Tables (`tables.lua`)
- **Counts and visual mode** (2026-10-06): add/delete row and column keys take a count (`3<P>tj`, `2<P>tdr`, like `o`/`dd`; the header, delimiter row and last column stay). In visual mode `<P>tdr`, `<P>tJ`/`tK`, `<P>ts`/`tS` act on the selected body rows (moved as a block; sort only within the selection); `<P>tdc`, `<P>tH`/`tL` on the columns under a charwise/blockwise selection (`V` warns). All repeat with `.` over as many lines.
- **Finding a table** (revised 2026-10-06): from the lines, not the `pipe_table` node. tree-sitter-markdown reads a row of empty cells (`|   |`) after a body row as a delimiter row (GFM needs at least one `-`), which splits the table or makes it an ERROR. A table is the run of non-blank lines around the cursor: up through any lines that don't start another block, the header is the line above the first valid delimiter row (`:?-+:?` cells) with the same cell count, and the body goes on, through lines without a pipe, until a blank line or another block (heading, fence, quote, list item, HTML). Treesitter only rules out code blocks.
- **Create** (`<P>tt`): prompt `rows x cols` (e.g. `3x4`), insert header row, delimiter row and empty body rows, cursor in first header cell.
- **CSV → table** (`<P>tc`: the paragraph under the cursor in normal mode, the selection in visual mode; `:'<,'>Markwright table csv`): the lines; asks `Separator:` prefilled with the detected one (candidates `\t` `,` `;` `|` `:`; a candidate that splits every line into the same number > 1 of fields wins, most fields first; else the one splitting the first line most; else `,`). Any typed separator works, including multi-character ones; `\t`/`tab` = tab; cancel does nothing. Honor quoted fields; trim fields; first line becomes the header; escape `|` in cells. (Changed 2026-09-30: detection used to consider only `\t , ;` on the first line, so other separators produced a single column.)
- **Table → CSV** (`<P>tC`, changed 2026-10-03 from `<P>tx` to pair with `<P>tc`; `:Markwright table tocsv`; implemented 2026-09-30): replaces the table under the cursor with CSV lines — the opposite of `<P>tc`. Asks `Separator:` prefilled with `tables.csv_separator` (default `,`); `\t`/`tab` mean a tab, empty input means the default, cancel does nothing. Delimiter row dropped; short rows padded; fields quoted when they contain the separator, a `"` or edge spaces (quotes doubled); `\|` unescaped; indentation kept (tables in list items). One undo step; CSV → table → CSV round-trips.
- **Row/column editing (keys changed 2026-10-02, hjkl):** `<P>th` / `<P>tl` add a column left / right; `<P>tj` / `<P>tk` add a row below / above (above the header is refused: a table's first row is its header; below the header goes below the delimiter); `<P>tdr` / `<P>tdc` delete the row / column (updates the delimiter row). Commands: `:Markwright table row|rowabove|delrow|col|colleft|delcol`. (Previously `<P>tr`/`<P>tR`/`<P>tk`/`<P>tK`.)
- **Cell navigation:** `<Tab>` / `<S-Tab>` in insert mode inside a table → next/previous cell; `<Tab>` in the last cell adds a new row.
- **Align:** pad cells so pipes line up, using display width (`vim.fn.strdisplaywidth`, for accents/CJK/emoji); respect alignment markers (`:---`, `:---:`, `---:`). Runs on `InsertLeave` when the cursor was in a table, after row/col edits, and via `<P>ta`.
- Detection via Treesitter `pipe_table` node.

### 9.5 Footnotes (`footnotes.lua`)
- Insert (`<P>n`): next number = max existing numeric footnote + 1. Insert `[^n]` at the cursor, append `[^n]: ` at the end of the file (after a blank line, grouped with other definitions), jump there in insert mode. Set a jumplist entry so `<C-o>` returns.
- Navigation via `gx` (section 8).

### 9.6 TOC (`toc.lua`)
- `<P>O` (changed 2026-10-03 from `<P>T`: the outline `<P>o`, written into the file) / `:Markwright toc`: insert TOC at cursor between `<!-- toc -->` and `<!-- tocstop -->`, or regenerate if markers exist.
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
- [x] 11. Priority-1 features: text objects, heading navigation (§14.8, §14.9); rich-text paste moved to a later version (§14.10).
- [ ] 12. Priority-2 features (§14.11–14.18) — callouts done.
- [ ] 13. Linux/WSL image paste, image extras, fence completion (§14.1, §14.5, §14.6).
- [x] 10b. Release preparation: Neovim 0.10 check, stylua/selene, CHANGELOG, tag (see §0 Release 1.0.0).
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

- **Rename** (`<P>P`, changed 2026-10-03 from `<P>r`; `:Markwright image rename`; implemented 2026-10-02): cursor on an inline image with a local destination; `vim.ui.input` prefilled with the file name; renames the file in its folder with `vim.uv.fs_rename` (no extension typed → old one kept; name sanitized like paste: spaces → `-`, no path separators), then rewrites every destination in the buffer that resolves to the old file (images, links, `[ref]:` definitions; `./`, `%20`, `<…>` forms; `#fragment` kept; skips code) as one undo step. Refuses existing targets (a case-only change on a case-insensitive disk is allowed), remote URLs and missing files. Other files aren't updated (link diagnostics flag them); undo doesn't rename the file back.

### 13.2 Insert-mode formatting keys — **implemented (2026-09-30)**
- Trigger `;;` (config `insert.trigger`: 2+ characters, a key like `<C-g>`, or `""` to disable), then `i` `b` `s` `c` `h` `k`. Chosen for portability: plain characters work in every terminal and layout; `<C-m>` (= Enter), `<C-i>` (= Tab), Option/Meta keys and completion-plugin keys were ruled out.
- No timeout: only the trigger's last character is mapped, and it fires only when the preceding characters were just typed in sequence (tracked with InsertCharPre). The menu then waits for the key with no time limit (`getcharstr`) and shows a hint.
- Unknown key → the trigger text plus that key are typed as-is; `<Esc>` restores the trigger and leaves insert mode. Key triggers pass unknown keys to their previous meaning (`<C-g>u`, plugin mappings).
- Pressing the same format again right before its closing marker jumps out (tracked with extmarks; falls back to the text shape for pairs typed by hand). Links go text → URL → out; a clipboard URL skips the URL stage.
- Off in code blocks; in inline code only `c` (jump out) right before the closing backtick.
- `n` and `p` (added 2026-10-03, same letters as `<P>n` / `<P>p`) insert at the cursor and keep insert mode after what they insert: `n` adds `[^n]` and its empty definition at the end of the file without jumping there (`gx` jumps later); `p` runs the image paste at the insert cursor, prompts included, and returns to insert mode after the link (also when a floating prompt stopped insert mode, or was cancelled). Block-level actions (fence, callout, heading, table) are not offered: they start at the beginning of a line, where typing them is as short as `;;` + a letter.

### 13.3 `<Tab>`/`<CR>` conflict with completion/snippets — **resolved (2026-09-29)**
Shared helper in `util.lua` (`completion_active`, `save_fallback`, `fallback`): insert-mode `<Tab>`/`<S-Tab>`/`<CR>` act only in a table or on a list item and when no completion menu (blink.cmp, nvim-cmp, pum) or snippet is active. Otherwise they call the mapping that existed when the buffer attached (captured with `maparg`, e.g. mini.pairs `<CR>`), or the native key. Verified on macOS with blink.cmp and mini.pairs (2026-09-30).

### 13.3a Dot-repeat — **implemented (2026-10-06)**
- Every key that changes the buffer repeats with `.`. Inline keys are operators already. Other actions run from an operator function (`util.repeatable` / `util.repeatable_visual`): the normal-mode key returns `g@l` (the cursor stays where it is, and `l` works on empty lines and at the end of a line), the visual key returns `g@` (the selected rows). The count is the `g@l` count, given to the action through `util.count1()`: the key's count on the first run, and like Vim's `.`, `N.` replaces it (later `.` keep N). Visual keys keep the count they were pressed with.
- Prompts go through `util.input` / `util.select`: the first run records the answers in order (a cancel counts as an answer), `.` replays them and only asks for prompts it has no answer for. A callback of a recorded prompt runs with the same recording active, so chained prompts (link URL → text) are recorded too.
- Not repeatable: actions that end in insert mode or create from a prompt (fence/footnote in normal mode, create table, image paste/rename, TOC) and non-changing ones (outline, copy as CSV, follow).

### 13.4 Open questions collected
- ~~Operator keymap names (section 5)~~ — resolved: every range key is an operator, `_` = line, no doubled keys (§14.7).
- ~~Heading keys (9.1)~~ — resolved: `<P>=` adds `#`, `<P>-` removes.
- Partial-overlap selection behavior (6.9) — see §14.7.
- ~~Link key on whitespace (7.1)~~ — resolved: prompt URL, then text; empty text → page title.
- ~~Checkbox key on a non-list line (9.2)~~ — resolved: native `<CR>`.
- Fence language prompt completion (9.3) — planned, §14.5.
- TOC default level range (4 / 9.6) — shipped with 2–4.
- ~~Diagnostics lifetime between saves (10)~~ — implemented as proposed: kept until the next save; `:Markwright check` re-runs on demand.
- Checkbox 3-state (`[-]`) — optional, §14.22.
- ~~External URL checking~~ — implemented as the on-demand `:Markwright check urls`, §14.23.

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
- ~~**Operator keys**~~ — resolved 2026-09-30: `<P>i/b/s/c/h` are operators (`<P>biw`, `<P>c$`), `_` is the current line (`<P>b_`, count = lines), visual mode unchanged. No doubled keys anywhere (`<P>ii` would shadow text objects; the others were dropped for consistency). Rule: **inline keys are smart operators** (formatting, links: at once when there's nothing to choose, otherwise wait for a motion); **block keys and inserts act at once** (code fence, callout, CSV → table, footnote, table, TOC, image). Callouts and fences were tried as operators and reverted the same day: their common case (wrap the paragraph, insert a fence) became longer. The uppercase variants are gone, freeing `<P>I`/`<P>B`/`<P>S`/`<P>C`/`<P>H`.
- **Partial-overlap selections** (selection covers part of a span): currently removes the whole span. Alternative: shrink the span to exclude the selection (`**hello world**`, select `world` → `**hello** world`). Decide, then test both edge directions.

### 14.8 Text objects — **implemented (2026-09-30)**

| Object | `i` (inner) | `a` (around) | Keys |
|---|---|---|---|
| Link | link text; image alt text; the URL inside `<…>`; a bare URL | whole `[text](url)` / `![alt](src)` / `<url>` / reference link | `ik` / `ak` |
| Link URL | destination (inside `<…>` if bracketed); for reference links, the URL on the `[ref]:` line | — | `iu` |
| Inline code | content (without padding spaces) | with backticks | `ic` / `ac` |
| Code block | lines between the fences (indented block: its lines) | whole block, fences included (trailing blank lines excluded) | `if` / `af` (**f**ence) |
| Heading section | content under the heading, blank lines at both ends trimmed | heading + content up to the next heading of the same or higher level | `i#` / `a#` |
| Table cell | trimmed cell text | cell incl. padding (between the pipes) | `iz` / `az` ("zell") |
| List item | item text (no marker/checkbox), incl. continuation lines of its paragraph | item + its children (line-wise) | `ix` / `ax` (the x in `[x]`) |
| Emphasis | inside `*`, `**`, `~~`, `==` (innermost) | including the markers | `i*` / `a*` |

- Changed 2026-10-03 (keymap review): `ic`/`ac` is inline code only and code blocks moved to `if`/`af` (matching `<P>c` / `<P>f`); sections `ih` → `i#` (`h` is highlight); cells `i|` → `iz` (the pipe read as "between pipes"); list items `iL` → `ix` (lowercase; `il` is mini.ai's "last" prefix).
- Decided 2026-09-30: link text uses **`ik`/`ak`** (not `il`/`al`, which mini.ai uses as its "last" prefix); `k` also became the link key everywhere (`<P>k`, `;;k`).
- Operator-pending and visual modes, buffer-local in Markdown. Implemented as `expr` mappings: the range is computed, then selected through a `<Cmd>` that recomputes it at execution time, so dot-repeat works at the new cursor position.
- Counts climb outward: `2a#` parent section, `2ax` parent item, `2i*` next enclosing span.
- Not inside an object → the **next** one after the cursor, across lines (like mini.ai's default `cover_or_next`), within `textobjects.search_lines` (default 500) lines; never backwards; nothing found → the operator is cancelled. Implemented with per-object anchor lists (start positions of links/bare URLs, code spans and blocks, headings, tables, list items, emphasis and `==` spans); the object is evaluated at the first anchor after the cursor. ~6–8 ms per search over 500 lines of the README. (Fixed 2026-09-30: the first version only searched the rest of the current line.)
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

### 14.10 Rich-text paste (later)
- `<P>v` **[OPEN]** / `:Markwright paste`: paste the clipboard's HTML (copied from a browser, Google Docs, Notion, Word…) converted to Markdown: headings, bold/italic, links, lists, tables, code.
- Reading HTML: macOS via JXA `NSPasteboard.generalPasteboard.stringForType("public.html")`; Wayland `wl-paste -t text/html`; X11 `xclip -t text/html -o`; WSL `Get-Clipboard -TextFormatType Html`.
- Conversion: `pandoc -f html -t gfm-raw_html --wrap=none`; post-process to the plugin's style (bullet `-`, `**`/`*` markers, strip empty links and tracking parameters optional).
- No HTML on the clipboard → normal paste of the text. No pandoc → plain-text paste + one warning; `:checkhealth` reports pandoc.
- Optional: `rich_paste.smart = false` — when true, plain `p` converts automatically if HTML is present.
- Pasted block is one undo step; relative links in the HTML are resolved against its source URL when the clipboard provides it.

### 14.11 GitHub callouts — **implemented (2026-09-30)**
- `<P>a` normal mode:
  - on a callout (`> [!TYPE]`, any case) → pick a new type from the same picker, the current one labelled `(current)`; `callouts.default` doesn't apply here; a title after the marker is kept. (Changed 2026-09-30: first version cycled NOTE → TIP → … without a picker.)
  - on a plain blockquote → add the `[!TYPE]` line (type picker);
  - in a fenced code block → wrap the whole block; elsewhere → wrap the paragraph (contiguous non-blank lines); on a blank line → insert an empty callout and start insert mode.
- `<P>a` visual: wrap the selected lines. Blank lines become `>`; the common indentation stays before the `>` (callouts inside list items).
- Type picker: `vim.ui.select(callouts.types)`, NOTE first; `callouts.default` skips it.
- `<P>A`: remove the callout/blockquote under the cursor — drops the marker line (keeping a title as text) and one `>` level from every line (nested quotes keep their inner level).
- `:Markwright callout [type|remove]` with completion; with a range, wraps those lines.
- Each action is one undo step. Blockquotes are found by line scan (contiguous `>` lines, up to 3 spaces of indent).
- **Continuing quotes** (added 2026-09-30): insert `<CR>` on a `>` line (callout or plain quote) continues with the same prefix (`> `, `> > `), splitting the line at the cursor; on an empty `>` line it removes one `>` level without adding a line; `o`/`O` open a `> ` line. Lists inside quotes keep list continuation; code blocks inside a quote continue the `>`, while `>` lines in ordinary code blocks are left alone (Treesitter: code block with a `block_quote` ancestor). Option `blockquotes.continue_on_enter`.
- Tree-sitter parses the marker `[!TYPE]` as a `shortcut_link`. `ts.is_callout_marker(node, src)` (a `shortcut_link` `[!word]` preceded only by `>`/spaces on its line) excludes it from link handling: `<P>k` and `:Markwright link` warn instead of unlinking it (fixed 2026-10-02: it used to turn `[!WARNING]` into `!WARNING`), the `ik`/`ak` text objects and their forward search skip it, and `gx` ignores it.

### 14.12 List tools (priority 2) — **implemented (2026-10-02)**
Keys chosen 2026-10-02: a `<P>l` submenu (which-key group "list"), like `<P>t` for tables. New module `listtools.lua`, built on the tree-sitter `list_item` tree.
- `<P>lJ` / `<P>lK` (changed 2026-10-03 from `lj`/`lk`, matching the table row moves `<P>tJ`/`<P>tK`; `:Markwright list down|up`): move the item under the cursor, with its children, past `[count]` siblings; clamped at the first/last sibling (a child never leaves its parent). Item blocks exclude trailing blank lines; the blank gaps between items stay in place. Ordered lists are renumbered from the list's original first number (re-indenting children when a number's width changes). Cursor follows. Opt-in `lists.move_keys = { down = "<M-j>", up = "<M-k>" }`: on list items they move the item, elsewhere they run the previously defined mapping (LazyVim's move-line).
- `<P>ls` / `<P>lS` (`:Markwright list sort [desc]`): sort the siblings A→Z / Z→A (case-insensitive, checkbox and emphasis markers ignored; decided 2026-10-02: `s`/`S`, replacing the "again → Z→A" toggle). `<P>ld` (`:Markwright list sort done`): stable partition, done (`[x]`/`[X]`) items last. Children move with their parent; renumbered.
- Converters `<P>lb` / `<P>ln` / `<P>lc` → bullets / numbers / checkboxes (`:[range]Markwright list bullet|number|checkbox [all]`). Scope (decided 2026-10-02, after use): lowercase = the cursor's level, i.e. the list item under the cursor (also from a continuation line) and its siblings; their children and continuation lines are only re-indented by the marker width change, so nested lists of another style are left alone. Uppercase `<P>lB` / `<P>lN` / `<P>lC` = the cursor's level and every sub-list below it, any depth (the rows from the first sibling to the end of the last sibling's subtree); parents and anything above are untouched, and on a top-level item this is the whole list (decided 2026-10-02). On plain lines (no list): the paragraph. Visual: exactly the selected lines, every level. Plain lines get the style, items of another style switch; if every converted item already has the style it is removed (plain lines), so each key toggles. Existing bullet characters and number delimiters are kept (a `*` list becomes `* [ ]`, a numbered list stays numbered as `1. [ ]`); new markers come from `lists.bullet` (`-` `*` `+`, default `-`) and `lists.number_delim` (`.` `)`, default `.`). In every-level mode, indented lines nest under the closest less-indented line at its new content column, numbering restarts per level. Blank lines, headings, fences and code blocks are skipped; `>` prefixes kept.
- **Checklists are protected** (decided 2026-10-02): whenever a conversion would remove checkboxes, checked or not (→ bullets, numbers or plain), `vim.ui.select` asks "N checklist items (D done) would lose their checkbox. Convert them?". Yes converts everything; No converts the rest and leaves every list level containing such an item (a checklist; levels = tree-sitter `list` nodes) exactly as it is, re-indented only to stay nested; Cancel or `<Esc>` changes nothing. No is offered only when something outside the checklists would change (never for a single level). Levels are all-or-nothing, so a list never mixes checkboxes with bullets or numbers. Converting into checkboxes never asks. The plan is computed first and applied only if the lines are unchanged when the answer comes. Converting into checkboxes never asks.
- Each action is one undo step; progress cookies are refreshed.

### 14.13 Checkbox progress (priority 2) — **implemented (2026-10-02)**
- A list item whose first line contains a cookie `[/]`, `[n/m]`, `[%]` or `[n%]` (after its own checkbox; a cookie followed by `(` is a link; every cookie on the line is filled, so `[/] [%]` shows both) shows its direct children's progress: `- Release [2/5]` / `- Release [40%]` (percent rounded down; no children → `[0/0]` / `[0%]`).
- Counted children: direct sub-items with a checkbox (done when checked). A sub-item without a checkbox but with a cookie counts as one task, done when complete, so counts roll up (post-order over the tree-sitter `list_item` tree). Items without a cookie are never changed; a parent's own checkbox isn't auto-checked.
- Updated after the plugin toggles a checkbox (same undo step), on InsertLeave and normal-mode TextChanged (joined, not after undo/redo), and on save. Cheap pre-check: nothing is parsed unless some line contains a cookie. Lists in code blocks aren't list items, so they're left alone.
- **Labels above a list** (added 2026-10-05): a heading, or the last line of a paragraph, that is the block right before a list (blank lines between are fine) labels that list. Its cookies count the list's top-level items by the same rules (checkbox items; items with their own cookie roll up). Works for ATX and setext headings, plain paragraphs and callout titles (`> [!NOTE] Todo [/]`). A heading followed by other text before the list is not a label. Cookies inside inline code (`` `[/]` ``) are never filled, on labels or items.
- Config `lists.progress = true` (default).

### 14.14 Completion dates (priority 2) — **implemented (2026-10-02)**
- `lists.done_date = "✅ %Y-%m-%d %H:%M"` by default (decided 2026-10-02: on, with the time); `false` turns it off; any `os.date` format (local time). `"✅ %Y-%m-%d"` is the Obsidian Tasks format.
- Checking an item (`<CR>`, visual `<CR>`) appends `" " .. os.date(fmt)` to the end of the item's first line (trailing spaces dropped); unchecking removes it. Same undo step as the toggle. Not stamped twice; adding a checkbox to a plain item doesn't stamp.
- Removal recognizes stamps of the current format (converted to a Lua pattern: `%Y %y %m %d %e %H %I %M %S %p %j %F %R %T` → digits, other conversions loosely) and of the default and Obsidian formats, at the end of the line.

### 14.15 Table extras (priority 2) — **implemented (2026-10-02)**
Keys chosen 2026-10-02, matching the `h`/`j`/`k`/`l` add keys:
- `<P>tH` / `<P>tL`: move the current column left / right, `[count]` steps (alignment markers move with it; the cursor follows; clamped at the edges).
- `<P>tJ` / `<P>tK`: move the current body row down / up, `[count]` steps (header and delimiter stay; clamped).
- `<P>ts` / `<P>tS` (`:Markwright table sort [desc]`): sort body rows by the column under the cursor (cursor anywhere in the column, header included), ascending / descending (decided 2026-10-02: `s`/`S` like list sorting, replacing the first version's "again → descending" toggle). Numeric when every non-empty cell is a number after removing emphasis markers, a leading `$ € £ ¥`, a trailing `%` and thousands commas; else case-insensitive text (ISO dates sort as text). Empty cells last in both directions; stable.
- `<P>tf` (**f**lip; changed 2026-10-03 from `<P>tT`; `:Markwright table transpose`): rows ↔ columns over header + body; the first column becomes the header; alignments reset to none; the cursor follows its cell.
- `<P>ty` (`:Markwright table yank`): copy the table as CSV (same separator prompt and quoting as `<P>tC`) to the `"` register, and to `+` when a clipboard provider exists; the table is untouched.
- Each edit is one undo step.

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

### 14.20 Word count / reading time — **implemented (2026-10-06)**
- `require("markwright").stats(buf?)` → `{ words, chars, reading_minutes }` (plus `selection = true` when the visual selection is active, which is used then). `require("markwright.stats").count(buf, range)` for any line range or character range; `statusline()` → `1,234 words · 7 min` / `52 words selected` / `""` outside markwright buffers.
- Excluded, from the tree-sitter block tree: front matter (`minus_metadata`/`plus_metadata`), fenced and indented code, HTML blocks, reference definitions (footnote definitions are kept), thematic breaks, setext underlines, table delimiter rows. Per line, with patterns: block prefixes (`>`, list markers, checkboxes, `#`, callout markers, footnote labels), completion stamps, HTML comments/tags/entities, images (alt text too), link destinations (link text counts), autolinks, bare URLs, footnote references, progress cookies, emphasis/code/highlight markers, escapes, table pipes.
- Words: runs of letters/digits; `'` `’` `-` `_` `.` `,` `:` `/` inside a run don't split it (`don't`, `well-known`, `3.14`, `15:30`); other punctuation and symbols do. CJK ideographs and kana count one word each. Characters: the cleaned text, one space between words, line breaks not counted.
- Reading time: `ceil(words / stats.wpm)` (default 200), 0 for an empty document.
- `:[range]Markwright stats` notifies `N words · N characters · N min read`. No default key.
- Cached per changedtick; per-line counts are memoized by line text, so after an edit only changed lines are recounted (≈7 ms for a 1,700-line file in the test VM; cached calls are free).
- README includes a lualine snippet.

### 14.21 Link completion (priority 3)
- blink.cmp / nvim-cmp source: file paths after `](`, headings after `#` (`](#` and `](file.md#`), reference labels after `][`.
- Low priority because LazyVim's marksman language server already provides most of this; the source is off by default and documented as the alternative when marksman isn't used.

### 14.22 Optional: 3-state checkboxes (priority 3)
- `lists.checkbox_states = { " ", "x" }` by default; setting `{ " ", "-", "x" }` makes the checkbox key cycle `[ ]` → `[-]` → `[x]`. Visual range and progress (§14.13) count `[-]` as not done.

### 14.23 External URL checker — **implemented (2026-09-30)**
- `:Markwright check urls` (completion under `check`); never automatic.
- Collects `http(s)` URLs from inline links, images, `<autolinks>`, `[ref]:` definitions and bare URLs (`www.` → `https://`); skips code blocks/spans, local paths, `mailto:` and other schemes, and `url_check.ignore` patterns; a URL inside link text isn't counted twice. Each unique URL is requested once.
- Requests: `curl -sS -o /dev/null -L --max-redirs 10 --max-time T -A <browser UA> -w %{http_code}`; `HEAD` (`-I`) first, then `GET -r 0-0` when HEAD returns an error status (not for unknown host / refused / timeout). Async via `vim.system`, at most `url_check.concurrency` (8) at once, `timeout_ms` 10000 each.
- Classification: 2xx/3xx/416 ok; 401/403/429 "restricted" (INFO: needs a login or blocks automated checks); other statuses and curl errors (6 host not found, 7 refused, 28 timed out, 35/51/58/60 TLS/certificate, 47 redirects) "broken" (`url_check.severity`, WARN).
- Output: diagnostics in their own namespace `markwright_urls` on every occurrence (kept until the next run; unaffected by the on-save link diagnostics), the quickfix list titled "markwright: external links" (opened without stealing focus when something is wrong, `url_check.open_quickfix`), and a summary notification.
- Tests mock the request function; one test runs real curl against a local `python3 -m http.server` (skipped when curl or python3 is missing).
