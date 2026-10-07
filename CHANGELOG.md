# Changelog

All notable changes to markwright are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). Changes to default keys or options come in major versions and are always listed here.

## [Unreleased]

## [4.1.0] - 2026-10-06

### Added

- **Sections** (`<leader>m#…`, `#` as in the `i#` text object): `<leader>m#J` / `<leader>m#K` move the section under the cursor (heading, text and sub-sections) past its next / previous sibling, and `<leader>m#=` / `<leader>m#-` add or remove a `#` on the heading and all its sub-headings. Counts and `.` work; footnote and reference definitions at the end of the file stay there. `lists.move_keys` also move sections on a heading line. Also `:Markwright section up|down|add|remove [N]`.

## [4.0.0] - 2026-10-06

### Changed

- **`<leader>mf` on a paragraph wraps it in a fence**, like `<leader>ma` does for callouts and `<leader>mtc` for CSV, instead of inserting an empty block below the line. On an empty line it still inserts an empty block, including an indented line inside a list item or a bare `>` line in a blockquote, which keeps the block in that container. Wrapping repeats with `.` (same language), and keeps a blockquote prefix (`> a` → `> ```py`). `:Markwright fence` without a range behaves the same way.

  | Before (3.x)                               | Now                                                        |
  | ------------------------------------------ | ---------------------------------------------------------- |
  | `<leader>mf` on text: empty block below it | wraps the paragraph; for an empty block, open a line first |
  | `vip<leader>mf` to fence the paragraph     | `<leader>mf` (visual mode still wraps the selection)       |

## [3.5.0] - 2026-10-06

### Added

- **Commands for every key that changes the buffer**, for setups without the default keys: `:[range]Markwright heading add|remove [N]`, `:[range]Markwright checkbox`, `:[range]Markwright table move up|down|left|right [N]`, and `:Markwright table fromcsv` (CSV → table for the range or the paragraph; `csv` still works). `table row`, `rowabove`, `col`, `colleft`, `delrow`, `delcol` and `list up`/`down` take a count; `table delrow`, `sort` and `move up|down` take a range.

### Changed

- Warnings use the same wording throughout ("code fence skipped inside code", "can't move the header row", "that's a callout marker, not a link").

## [3.4.0] - 2026-10-06

### Added

- **Table keys in visual mode**: `<leader>mtdr` deletes the selected rows, `<leader>mtJ` / `<leader>mtK` move them together, `<leader>mts` / `<leader>mtS` sort just those rows; with a charwise or blockwise selection across cells, `<leader>mtdc` deletes the selected columns and `<leader>mtH` / `<leader>mtL` move them together. Counts and `.` work as in normal mode. The header and the delimiter row are never moved, sorted or deleted.
- **Counts on table row and column keys**, as with Vim's `o` and `dd`: `3<leader>mtj` / `3<leader>mtk` add three rows, `2<leader>mth` / `2<leader>mtl` two columns, `2<leader>mtdr` deletes the cursor's row and the one below, `2<leader>mtdc` the cursor's column and the one to its right. The header, the delimiter row and the last column are never deleted. They repeat with `.` like the move keys.

## [3.3.4] - 2026-10-06

### Fixed

- **Tables with an empty row** (`|     |`) right after another body row were split in two, or not seen as a table at all with more than one column, so aligning, `<Tab>`, sorting, moving and adding or deleting rows only saw part of the table, and `<leader>mtj` then `.` added just one row. The Markdown parser reads such a row as a delimiter row; markwright now finds tables from the lines themselves.

## [3.3.3] - 2026-10-06

### Fixed

- A count on `.` replaces the count of the repeated action, as with Vim's own commands: `<leader>mtJ` then `3.` moves the row three places, and later `.` keep using 3. It used to reuse the original count.

## [3.3.2] - 2026-10-06

### Fixed

- **`.` repeats every `<leader>m…` key that changes the buffer.** Only formatting and the link operator repeated before; table, list, heading, callout and checkbox keys, the CSV converters, visual code fences and the link key's at-once actions (remove a link, convert a bare URL, new link) now do too, with their count, and visual keys over as many lines. A repeat reuses the answers to the first run's prompts (callout type, CSV separator, fence language, link URL and text). Keys that start insert mode or create something from a prompt (`<leader>mf`/`<leader>mn` in normal mode, `<leader>mtt`, `<leader>mp`, `<leader>mP`, `<leader>mO`) aren't repeatable.

### Documentation

- Known limitation: with which-key, `<leader>m…` keys don't wait for the next key while a macro is recorded; the README has a workaround.

## [3.3.1] - 2026-10-06

### Fixed

- **Ordered lists left with stale numbers:**
  - Deleting or moving a list's first item no longer shifts the whole list: `1.` `2.` `3.` without its first item is `1.` `2.` (it used to stay `2.` `3.`), moving the first item to the end gives `1.` `2.` `3.`, and an item pasted above the first one becomes `1.`. A list that starts at another number (`5.`) keeps it; typing a new number on the first item still restarts the list.
  - Lists changed away from the cursor (`:g/…/d`, `:m`, `:2d`, `.` repeated elsewhere) are renumbered too.
  - Deleting the first item of a sub-list (or of a list right after a paragraph) no longer turns the rest into plain text: the new first item becomes `1.`, which CommonMark needs for it to stay a list.
  - Duplicating the only item of a list (`yyp`) numbers the copy `2.`.

## [3.3.0] - 2026-10-06

### Added

- **Word count and reading time**: `:Markwright stats` (with a range: those lines) shows words, characters and reading time. Code blocks, front matter, HTML, URLs, image alt text, completion stamps and Markdown markup aren't counted. `require("markwright.stats").statusline()` gives `1,234 words · 7 min` (or `52 words selected` in visual mode) for lualine or any statusline, and `require("markwright").stats()` returns the numbers. Reading speed: `stats.wpm` (200).

## [3.2.0] - 2026-10-05

### Added

- **Progress counters above a list**: `[/]` and `[%]` also work on a heading or a line of text right above a checklist (blank lines between are fine): `## Tasks [2/3]`, `Groceries [66%]`, `> [!NOTE] Todo [1/2]`. They count the list's items the same way a parent item counts its sub-items.

### Fixed

- A progress cookie written in inline code (`` `[/]` ``) is no longer filled in.

## [3.1.0] - 2026-10-03

### Added

- **Footnotes and images while typing**: in insert mode, `;;n` inserts the next footnote reference (`[^3]`) and its empty definition at the end of the file, and `;;p` pastes the clipboard image at the cursor (macOS), with the same name prompt as `<leader>mp`. Both leave you typing right after what they inserted; `gx` on the reference jumps to the definition when you're ready to write it.

## [3.0.0] - 2026-10-03

### Changed

- **Keymap review: consistent mnemonics.** Each letter now means one thing at the top level, in insert mode and in text objects, and uppercase at the top level is the companion of lowercase. The README has a Mnemonic column and a "How the keys are organized" section. Keys that changed:

  | Old                         | New                   | Since | Action                                                                        |
  | --------------------------- | --------------------- | ----- | ----------------------------------------------------------------------------- |
  | `<leader>mT`                | `<leader>mO`          | 1.0.0 | Table of contents (the **O**utline written into the file; `<leader>mo` jumps) |
  | `<leader>mtx`               | `<leader>mtC`         | 1.0.0 | Table → CSV (the reverse of `<leader>mtc`)                                    |
  | `<leader>mtT`               | `<leader>mtf`         | 2.1.0 | Transpose (**f**lip)                                                          |
  | `<leader>mts` twice         | `<leader>mtS`         | 2.1.0 | Sort the table descending                                                     |
  | `<leader>mr`                | `<leader>mP`          | 2.0.0 | Rename the image file (`p` pastes it)                                         |
  | `<leader>mlj` / `mlk`       | `<leader>mlJ` / `mlK` | 2.4.0 | Move a list item down / up, like `<leader>mtJ` / `mtK`                        |
  | `<leader>mls` twice         | `<leader>mlS`         | 2.4.0 | Sort the list Z→A                                                             |
  | `ic` / `ac` on a code block | `if` / `af`           | 1.0.0 | Code block (**f**ence); `ic` / `ac` is inline code only                       |
  | `ih` / `ah`                 | `i#` / `a#`           | 1.0.0 | Heading section (`h` is highlight)                                            |
  | `i\|` / `a\|`               | `iz` / `az`           | 1.0.0 | Table cell ("**z**ell")                                                       |
  | `iL` / `aL`                 | `ix` / `ax`           | 1.0.0 | List item (the **x** in `[x]`)                                                |

  Text object letters are configurable under `textobjects` (new `fence` entry).
- **Sorting uses `s` / `S`** for lists and tables: `s` sorts ascending (pressing it again keeps the order), `S` descending. The commands take an optional `desc`: `:Markwright list sort [desc|done]`, `:Markwright table sort [desc]`.
- **List converters work on one level.** `<leader>mlb` / `<leader>mln` / `<leader>mlc` convert the cursor's level of a list (its item and siblings) and leave parents and sub-lists of another style alone. The new `<leader>mlB` / `mlN` / `mlC` convert that level and every sub-list below it (`:Markwright list bullet|number|checkbox all`). Plain lines (the paragraph) and visual selections convert as before.
- **Checklists are protected.** A conversion that would remove checkboxes, checked or not, asks first: Yes converts the checklists too, No converts the rest and leaves every checklist level whole, Cancel stops. A list never mixes checkboxes with bullets or numbers. Converting into checkboxes never asks.

## [2.4.0] - 2026-10-02

### Added

- **List tools** (`<leader>ml…`): `<leader>mlj` / `<leader>mlk` move an item with its children (with counts; numbered lists renumber), `<leader>mls` sorts a list A→Z (again for Z→A), `<leader>mld` puts done items last, and the converters `<leader>mlb` / `<leader>mln` / `<leader>mlc` turn the paragraph or selection into bullets / numbers / checkboxes and back (`lists.bullet` and `lists.number_delim` choose new markers). Opt-in `lists.move_keys` to move items with `<M-j>`/`<M-k>`. Also `:Markwright list …`.

## [2.3.0] - 2026-10-02

### Added

- **Checkbox progress counters**: type `[/]` or `[%]` (or both) in a parent list item and it shows how many of its sub-tasks are done (`- Release [2/3]`, `- Release [66%]`, `- Release [2/3] [66%]`). Updated when you toggle a checkbox, leave insert mode, edit in normal mode and save; counts roll up through sub-items that have their own counter. `lists.progress = false` turns it off.

## [2.2.0] - 2026-10-02

### Added

- **Completion dates**: checking a checkbox appends the date and time it was done (`- [x] task ✅ 2026-10-02 15:52`); unchecking removes it. Set the format with `lists.done_date` (any `os.date` format, e.g. `"✅ %Y-%m-%d"` for Obsidian Tasks), or `false` to turn it off.

## [2.1.0] - 2026-10-02

### Added

- **Table extras**: `<leader>mtH` / `<leader>mtL` move the column left / right and `<leader>mtJ` / `<leader>mtK` move the row down / up (with counts); `<leader>mts` sorts by the column under the cursor (again for descending; numbers compare as numbers, empty cells last); `<leader>mtT` transposes; `<leader>mty` copies the table as CSV to the clipboard without changing it. Also `:Markwright table sort`, `transpose` and `yank`.

## [2.0.0] - 2026-10-02

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

[Unreleased]: https://github.com/edieguez/markwright/compare/v4.1.0...HEAD
[4.1.0]: https://github.com/edieguez/markwright/compare/v4.0.0...v4.1.0
[4.0.0]: https://github.com/edieguez/markwright/compare/v3.5.0...v4.0.0
[3.5.0]: https://github.com/edieguez/markwright/compare/v3.4.0...v3.5.0
[3.4.0]: https://github.com/edieguez/markwright/compare/v3.3.4...v3.4.0
[3.3.4]: https://github.com/edieguez/markwright/compare/v3.3.3...v3.3.4
[3.3.3]: https://github.com/edieguez/markwright/compare/v3.3.2...v3.3.3
[3.3.2]: https://github.com/edieguez/markwright/compare/v3.3.1...v3.3.2
[3.3.1]: https://github.com/edieguez/markwright/compare/v3.3.0...v3.3.1
[3.3.0]: https://github.com/edieguez/markwright/compare/v3.2.0...v3.3.0
[3.2.0]: https://github.com/edieguez/markwright/compare/v3.1.0...v3.2.0
[3.1.0]: https://github.com/edieguez/markwright/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/edieguez/markwright/compare/v2.4.0...v3.0.0
[2.4.0]: https://github.com/edieguez/markwright/compare/v2.3.0...v2.4.0
[2.3.0]: https://github.com/edieguez/markwright/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/edieguez/markwright/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/edieguez/markwright/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/edieguez/markwright/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/edieguez/markwright/releases/tag/v1.0.0
