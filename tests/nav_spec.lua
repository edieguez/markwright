-- Heading navigation specs (SPEC.md section 14.9).
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local api = vim.api
local nav = require("markwright.nav")
local eq = H.eq

local DOC = {
  "intro", -- 1
  "# A", -- 2
  "a text", -- 3
  "## A.1", -- 4
  "x", -- 5
  "```", -- 6
  "# not a heading", -- 7
  "```", -- 8
  "## A.2", -- 9
  "### A.2.1", -- 10
  "y", -- 11
  "## A.3", -- 12
  "# B", -- 13
  "Setext", -- 14
  "------", -- 15
  "end", -- 16
}

local function row()
  return api.nvim_win_get_cursor(0)[1]
end

local function at(keys, cursor)
  return function()
    H.buf(DOC, cursor or { 1, 0 })
    H.feed(keys)
    return row()
  end
end

local function expect(name, keys, cursor, want)
  return {
    name,
    fn = function()
      eq(at(keys, cursor)(), want)
    end,
  }
end

local cases = {
  -- ]] / [[
  expect("]] from the top", "]]", { 1, 0 }, 2),
  expect("]] skips headings in code", "]]", { 4, 0 }, 9),
  expect("3]]", "3]]", { 1, 0 }, 9),
  expect("]] reaches setext headings", "]]", { 13, 0 }, 14),
  expect("]] at the last heading stays", "]]", { 16, 0 }, 16),
  expect("[[ from body text", "[[", { 11, 0 }, 10),
  expect("[[ from a heading", "[[", { 10, 0 }, 9),
  expect("2[[", "2[[", { 11, 0 }, 9),
  expect("[[ before the first heading stays", "[[", { 1, 0 }, 1),
  expect("column goes to 0", "]]", { 3, 3 }, 4),

  -- ][ / []
  expect("][ next sibling", "][", { 4, 0 }, 9),
  expect("][ from body text", "][", { 5, 0 }, 9),
  expect("2][", "2][", { 4, 0 }, 12),
  expect("][ doesn't leave the parent", "][", { 12, 0 }, 12),
  expect("][ at level 1", "][", { 3, 0 }, 13),
  expect("[] previous sibling", "[]", { 12, 0 }, 9),
  expect("[] from body goes to own heading first", "[]", { 11, 0 }, 10),
  expect("2[] from body", "2[]", { 5, 0 }, 4),
  expect("[] at the first sibling stays", "[]", { 4, 0 }, 4),
  expect("][ before any heading goes to the first", "][", { 1, 0 }, 2),

  -- [u
  expect("[u parent", "[u", { 10, 0 }, 9),
  expect("[u from body", "[u", { 11, 0 }, 9),
  expect("2[u", "2[u", { 11, 0 }, 2),
  expect("[u at top level stays", "[u", { 13, 0 }, 13),
  expect("[u under a setext h2 goes to its parent", "[u", { 16, 0 }, 13),

  -- jumplist, visual, operators
  expect("<C-o> returns after ]]", { "]]", "<C-o>" }, { 1, 0 }, 1),
  { "d]] deletes up to the next heading", { "a", "b", "# H", "c" }, { 1, 0 }, "d]]", { "# H", "c" } },
  { "V]]d extends to the heading line", { "a", "# H", "c" }, { 1, 0 }, "V]]d", { "c" } },
  -- like built-in ]]: an exclusive motion ending in column 0 becomes linewise
  { "c]] replaces the lines before the heading", { "a", "b", "# H" }, { 1, 0 }, "c]]x<Esc>", { "x", "# H" } },

  -- outline
  {
    "outline items",
    fn = function()
      H.buf(DOC, { 11, 0 })
      local items = nav.outline_items(0)
      eq(#items, 7)
      eq(items[1].label, "  # A")
      eq(items[4].label, "›     ### A.2.1")
      eq(items[7].label, "    ## Setext")
    end,
  },
  {
    "outline jumps to the chosen heading",
    fn = function()
      local real = vim.ui.select
      vim.ui.select = function(items, opts, cb)
        eq(opts.format_item(items[2]), "    ## A.1")
        cb(items[5])
      end
      H.buf(DOC, { 1, 0 })
      H.feed(" mo")
      vim.ui.select = real
      eq(row(), 12)
      H.feed("<C-o>")
      eq(row(), 1)
    end,
  },
  {
    "outline cancelled",
    fn = function()
      local real = vim.ui.select
      vim.ui.select = function(_, _, cb)
        cb(nil)
      end
      H.buf(DOC, { 3, 0 })
      vim.cmd("Markwright outline")
      vim.ui.select = real
      eq(row(), 3)
    end,
  },

  -- configuration
  {
    "keys are buffer-local and override the ftplugin",
    fn = function()
      H.buf({ "x" })
      eq(vim.fn.maparg("]]", "n", false, true).desc, "markwright: Next heading")
      eq(vim.fn.maparg("[u", "o", false, true).desc, "markwright: Parent heading")
      eq(vim.fn.maparg(" mo", "n", false, true).desc, "markwright: Outline (jump to a heading)")
    end,
  },
}

return H.run("heading navigation", cases)
