# Changelog

All notable changes to markwright are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). Changes to default keys or options come in major versions and are always listed here.

## [Unreleased]

### Added

- **Rename image files**: `<leader>mr` (or `:Markwright image rename`) on an image renames the file on disk and updates every link to it in the buffer. The prompt is prefilled with the current name; the extension is kept if you don't type one.

### Changed

- **Table keys use `h`/`j`/`k`/`l`**: `<leader>mth` / `<leader>mtl` add a column left / right, `<leader>mtj` / `<leader>mtk` add a row below / above (new). Deleting moved to `<leader>mtdr` (row) and `<leader>mtdc` (column). The old `<leader>mtr`, `mtR`, `mtK` are gone, and `<leader>mtk` now adds a row above instead of a column. New commands `:Markwright table rowabove` and `colleft`.

### Fixed

- `<leader>mk` on a callout marker (`> [!WARNING]`) treated it as a link and removed the brackets, breaking the callout. Callout markers are no longer links for `<leader>mk`, `:Markwright link`, the `ik`/`ak` text objects or `gx`; `<leader>mk` there just warns.
- Undo: a link's page title that arrived after you had already made another change was merged into that change's undo step, so one `u` undid both. The late title now gets its own undo step.
- Undo breaks from picker and prompt callbacks (callouts, links, images…) now always apply to the Markdown buffer, even if the picker's window is still focused when the callback runs.

## [1.0.0] - 2026-10-02

First release. Requires Neovim 0.10 or later (tested on 0.10.0 and 0.11).

### Added

- **Inline formatting** for italic, bold, strikethrough, inline code and highlight (`<leader>mi`, `mb`, `ms`, `mc`, `mh`). The key acts at once when there's nothing to choose: inside a span of that format it removes it, on whitespace it inserts an empty pair and starts insert mode between the markers. On plain text it's an operator, like `d` or `gu`: `<leader>mbiw`, `<leader>mb$`, `<leader>mb_` for the line, `3<leader>mb_` for three lines. Visual mode wraps the selection. Formats nest, multi-line targets are wrapped line by line (list markers, checkboxes, `>` and `#` stay outside), backtick fences escalate, code is skipped; dot-repeatable, one undo step.
- **Formatting while typing**: `;;` then `i`/`b`/`s`/`c`/`h`/`k` in insert mode opens a pair or jumps out of it, with no delay on normal `;` typing. Trigger configurable (`insert.trigger`).
- **Links** (`<leader>mk`): on a link it removes it, on a bare URL it makes `[Page Title](url)` (titles fetched asynchronously with `curl`), on whitespace it inserts a new link (URL prompt prefilled with the clipboard URL, then the text; empty = page title), all at once. On plain text it waits for a motion (`<leader>mkiw`) and wraps the text with the clipboard URL or a prompted one. Smart `p`/`P` paste URLs as links.
- **Text objects** for operators and visual mode: `ik`/`ak` link (images, autolinks and bare URLs too), `iu` link URL, `ic`/`ac` inline code or code block, `ih`/`ah` heading section, `i|`/`a|` table cell, `iL`/`aL` list item, `i*`/`a*` emphasis. Counts reach outward; when the cursor isn't inside one, the next one is used, even on later lines.
- **Heading navigation**: `]]`/`[[`, `][`/`[]` same level, `[u` parent, with counts, jumplist, visual mode and operators; `<leader>mo` / `:Markwright outline` picks a heading from the outline.
- **`gx`** follows `#anchors` (GitHub slugs), local files (creating missing `.md` files), `file.md#anchor`, images, URLs, reference links and footnotes, with jumplist support.
- **Lists**: `<CR>`, `o` and `O` continue lists; `<Tab>`/`<S-Tab>` nest items with their children; ordered lists renumber themselves; `<CR>` in normal mode toggles checkboxes. Completion menus, snippets and existing `<CR>`/`<Tab>` mappings keep working.
- **Blockquotes and GitHub callouts**: `<leader>ma` wraps the paragraph (or selection, or code block) in `> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]` or `[!CAUTION]` (picked from a list), changes the type of an existing callout, or turns a plain `>` quote into one; `<leader>mA` removes it. `<CR>`, `o` and `O` continue quotes; `<CR>` on an empty `>` line ends them.
- **Headings**: `<leader>m=` / `<leader>m-` add or remove a `#`, with counts; setext headings are converted.
- **Code fences** (`<leader>mf`): typed language, wrap selected lines, container-aware (lists, blockquotes).
- **Tables** (`<leader>mt…`): create from a size, CSV/TSV → table (separator detected and confirmed, multi-character separators, quoted fields), table → CSV, add/delete rows and columns, `<Tab>` between cells, automatic alignment (display-width aware) when leaving insert mode.
- **Footnotes** (`<leader>mn`): insert the next number and jump to its definition.
- **Table of contents** (`<leader>mT`) between `<!-- toc -->` markers, refreshed on save.
- **Link diagnostics** on open and save: missing files and images, missing anchors, undefined references, orphan footnotes; `:Markwright check`. `:Markwright check urls` checks external links in the background, on demand.
- **Image paste** on macOS (`<leader>mp`): screenshots, copied images, Finder files, image paths and URLs; saved to `assets/` with a name prompt and relative links.
- `:Markwright` command with completion, `:checkhealth markwright`, and a configuration for every feature (see README).

### Known limitations

- Image paste is macOS only.
- When a selection only partly covers a formatted span, the whole span is removed; this may change.

[Unreleased]: https://github.com/edieguez/markwright/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/edieguez/markwright/releases/tag/v1.0.0
