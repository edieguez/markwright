# mdtools.nvim — Specification

A Neovim plugin (LazyVim-friendly) for editing Markdown: inline formatting toggles, links, lists, headings, tables, code fences, footnotes, TOC and link diagnostics.

Status: **Draft v0.1** — decisions below were agreed on 2026-09-29. Items marked **[OPEN]** still need a decision; section 13 lists parked features.

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

A `:checkhealth mdtools` module (`lua/mdtools/health.lua`) verifies parsers, `curl`, clipboard provider and opener.

---

## 3. Architecture

```
mdtools.nvim/
├── plugin/mdtools.lua          -- defines :Mdtools command, lazy entry point
├── lua/mdtools/
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
│   └── health.lua
└── tests/                      -- mini.test or plenary/busted specs
```

**Attachment:** `setup()` registers a `FileType markdown` autocmd; each feature attaches buffer-local keymaps and autocmds only for that buffer. Nothing is global except the user command.

**User command:** `:Mdtools <subcommand>` with completion (e.g. `:Mdtools toc`, `:Mdtools table create`, `:Mdtools check`).

**Repeat:** operators use `operatorfunc` (`g@`) so `.` works natively. Non-operator actions set `operatorfunc` too, or use `vim-repeat` if available.

---

## 4. Configuration (defaults)

```lua
require("mdtools").setup({
  filetypes = { "markdown" },
  keymaps = {
    enabled = true,
    prefix = "<leader>m",   -- used to build default mappings below
  },
  format = {
    italic    = { marker = "*",  recognize = { "*", "_" } },
    bold      = { marker = "**", recognize = { "**", "__" } },
    strike    = { marker = "~~" },
    code      = { marker = "`" },
    highlight = { marker = "==" },
    trim_whitespace = true,        -- markers go inside leading/trailing spaces
    multiline = "per_line",        -- only mode for now
    warn_in_code = true,           -- notify when formatting inside code is skipped
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
    checkbox_add = true,           -- toggle key on plain item adds "[ ]"
  },
  tables = {
    align_on_insert_leave = true,
  },
  toc = {
    update_on_save = true,
    marker_start = "<!-- toc -->",
    marker_end = "<!-- tocstop -->",
    min_level = 2,                 -- [OPEN] default depth range
    max_level = 4,
  },
  diagnostics = {
    enabled = true,
    on_save = true,
    severity = vim.diagnostic.severity.WARN,
  },
})
```

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
| n, x | `<P>l` | Link: create / convert URL / remove |
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
If the target is inside `code_span`, `fenced_code_block` or `indented_code_block`, do nothing and `vim.notify("mdtools: formatting skipped inside code", WARN)` (when `warn_in_code = true`). Toggling **code itself** off inside a code span is allowed.

### 6.9 Edge cases to test
- Word adjacent to punctuation: `hello,` → `*hello*,`.
- Intraword underscore: `snake_case_word` must not be read as italic.
- Cursor on the marker characters themselves.
- Selection partially overlapping an existing span → **[OPEN]** proposed: extend to the whole span and remove.
- Escaped markers `\*` are literal.

---

## 7. Links (`links.lua`, `title.lua`)

### 7.1 Link key (`<P>l`)
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
- **CSV → table** (`<P>tc`): visual selection; auto-detect delimiter (`,` / `\t` / `;`), honor quoted fields; first line becomes the header; escape `|` in cells.
- **Row/column editing:** add row below / delete row; add column right / delete column (updates delimiter row).
- **Cell navigation:** `<Tab>` / `<S-Tab>` in insert mode inside a table → next/previous cell; `<Tab>` in the last cell adds a new row.
- **Align:** pad cells so pipes line up, using display width (`vim.fn.strdisplaywidth`, for accents/CJK/emoji); respect alignment markers (`:---`, `:---:`, `---:`). Runs on `InsertLeave` when the cursor was in a table, after row/col edits, and via `<P>ta`.
- Detection via Treesitter `pipe_table` node.

### 9.5 Footnotes (`footnotes.lua`)
- Insert (`<P>n`): next number = max existing numeric footnote + 1. Insert `[^n]` at the cursor, append `[^n]: ` at the end of the file (after a blank line, grouped with other definitions), jump there in insert mode. Set a jumplist entry so `<C-o>` returns.
- Navigation via `gx` (section 8).

### 9.6 TOC (`toc.lua`)
- `<P>T` / `:Mdtools toc`: insert TOC at cursor between `<!-- toc -->` and `<!-- tocstop -->`, or regenerate if markers exist.
- On `BufWritePre`, if markers exist and `update_on_save`, regenerate (no-op if unchanged, so the buffer isn't modified needlessly).
- Nested `-` list of `[Heading](#slug)` entries, respecting `min_level`/`max_level`. Skip headings inside code blocks and the TOC itself.

---

## 10. Diagnostics (`diagnostics.lua`)

On `BufWritePost` (and on attach), publish `vim.diagnostic` entries in namespace `mdtools` for:
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

## 12. Implementation order (suggested)

1. Skeleton: `setup`, config, FileType attach, keymaps, `:Mdtools`, health.
2. `ts.lua` + `format.lua` (engine, operators, repeat) — everything else builds on it.
3. `links.lua` + `title.lua` + smart paste.
4. `follow.lua` + `slug.lua`.
5. `lists.lua`, `headings.lua`.
6. `fence.lua`, `footnotes.lua`.
7. `tables.lua`.
8. `toc.lua`, `diagnostics.lua`.
9. Docs (`doc/mdtools.txt`, README), CI.

---

## 13. Pending / parked features

### 13.1 Image paste — **parked**
Agreed in principle, details deferred. To decide:
- Target platforms and clipboard backends: Wayland (`wl-paste`), X11 (`xclip`), macOS (`pngpaste` / `osascript`), WSL/Windows (`powershell.exe`).
- Save location: relative to file (`./assets/`), project root, or configurable per project.
- File naming: timestamp template vs prompt.
- Alt text: prompt or empty.
- Also accept a file path or URL from the clipboard (copy vs link)?
- Optional compression/conversion (WebP/PNG) and max width.
- Cleanup of unreferenced images.
- Relative vs absolute paths in the inserted `![alt](path)`.

### 13.2 Insert-mode formatting keys — **parked**
Keys that insert `**|**` around the cursor, or close the pair if already inside one. Key choice must avoid `<C-i>` (= `<Tab>`) and LazyVim insert mappings.

### 13.3 `<Tab>` conflict with completion/snippets — **resolved for tables (2026-09-29)**
Implemented in `tables.lua`: insert-mode `<Tab>`/`<S-Tab>` act only when the cursor is in a table and no completion menu (blink.cmp, nvim-cmp, pum) or snippet is active. Otherwise they call the mapping that existed when the buffer attached (captured with `maparg`), or insert a native `<Tab>`. blink.cmp wrapping our mapping as its fallback also works. Lists (9.2) must reuse the same helper.

### 13.4 Open questions collected
- Operator keymap names (section 5).
- ~~Heading keys (9.1)~~ — resolved: `<P>=` adds `#`, `<P>-` removes.
- Partial-overlap selection behavior (6.9).
- ~~Link key on whitespace (7.1)~~ — resolved: prompt URL, then text; empty text → page title.
- ~~Checkbox key on a non-list line (9.2)~~ — resolved: native `<CR>`.
- Fence language prompt completion (9.3) — not implemented; plain prompt for now.
- TOC default level range (4 / 9.6) — shipped with 2–4.
- ~~Diagnostics lifetime between saves (10)~~ — implemented as proposed: kept until the next save; `:Mdtools check` re-runs on demand.
- Checkbox 3-state (`[-]`) — declined for now; could be optional later.
- External URL checking in diagnostics — declined for now; could be an on-demand async command later.

### 13.5 Explicitly out of scope
- Wiki-style `[[links]]`.
- Rendering/preview.
