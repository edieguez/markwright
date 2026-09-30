# Changelog

All notable changes to markwright are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). Before 1.0, minor versions may change default keys or options; those changes are always listed here.

## [Unreleased]

### Fixed

- CSV → table (`<leader>mtc`) put each line in a single cell when the data used a separator other than comma, tab or semicolon (for example `|` or `:`), including CSV exported by `<leader>mtx` with a custom separator.

### Changed

- CSV → table now asks for the separator, prefilled with the detected one (Enter accepts it), like table → CSV. Detection also recognizes `|` and `:`, and looks at all selected lines instead of only the first.
- CSV separators can be several characters long (`::`, `; `).

## [0.1.0] - 2026-09-30

First public release. Requires Neovim 0.10 or later (tested on 0.10.0, 0.10.4 and 0.11).

### Added

- **Inline formatting** toggles for italic, bold, strikethrough, inline code and highlight (`<leader>mi`, `mb`, `ms`, `mc`, `mh`): word under the cursor, visual selections and operator + motion (`<leader>mI`…); removes the whole span from anywhere inside it, nests formats, wraps multi-line selections line by line, escalates backtick fences, skips code; dot-repeatable, one undo step.
- **Formatting while typing**: `;;` then `i`/`b`/`s`/`c`/`h`/`l` in insert mode opens a pair or jumps out of it, with no delay on normal `;` typing. Trigger configurable (`insert.trigger`, any 2+ characters or a key like `<C-g>`).
- **Links** (`<leader>ml`): wrap text with a URL from the clipboard or a prompt, turn bare URLs into `[Page Title](url)` (titles fetched asynchronously with `curl`), remove links keeping their text. Smart `p`/`P` paste URLs as links.
- **`gx`** follows `#anchors` (GitHub slugs), local files (creating missing `.md` files), `file.md#anchor`, images, URLs, reference links and footnotes, with jumplist support.
- **Lists**: `<CR>`, `o` and `O` continue lists; `<Tab>`/`<S-Tab>` nest items with their children; ordered lists renumber themselves; `<CR>` in normal mode toggles checkboxes. Completion menus, snippets and existing `<CR>`/`<Tab>` mappings keep working.
- **Headings**: `<leader>m=` / `<leader>m-` add or remove a `#`, with counts; setext headings are converted.
- **Code fences** (`<leader>mf`): typed language, wrap selected lines, container-aware (lists, blockquotes).
- **Tables** (`<leader>mt…`): create from a size, CSV/TSV → table, table → CSV with a chosen separator, add/delete rows and columns, `<Tab>` between cells, automatic alignment (display-width aware) when leaving insert mode.
- **Footnotes** (`<leader>mn`): insert the next number and jump to its definition.
- **Table of contents** (`<leader>mT`) between `<!-- toc -->` markers, refreshed on save.
- **Link diagnostics** on open and save: missing files and images, missing anchors, undefined references, orphan footnotes; `:Markwright check`.
- **Image paste** on macOS (`<leader>mp`): screenshots, copied images, Finder files, image paths and URLs; saved to `assets/` with a name prompt and relative links.
- `:Markwright` command with completion, `:checkhealth markwright`, and a configuration for every feature (see README).

### Known limitations

- Image paste is macOS only.
- The operator keys and the behavior for selections that partly cover a formatted span may change before 1.0.

[Unreleased]: https://github.com/edieguez/markwright/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/edieguez/markwright/releases/tag/v0.1.0
