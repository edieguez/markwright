-- Insert-mode trigger specs (SPEC.md section 13.2).
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local api = vim.api
local config = require("markwright.config")
local links = require("markwright.links")
local eq = H.eq

local real_clip = links.read_clipboard
local clip = ""
local function before_each()
  config.options.insert.trigger = ";;"
  clip = ""
  links.read_clipboard = function()
    return clip
  end
end

local function with_trigger(t)
  return function()
    config.options.insert.trigger = t
    -- re-attach the fresh buffer with the new trigger
    local buf = api.nvim_get_current_buf()
    pcall(vim.keymap.del, "i", ";", { buffer = buf })
    require("markwright.insert").attach(buf)
  end
end

local cases = {
  -- pairs
  { "bold pair", { "" }, { 1, 0 }, "i;;bword<Esc>", { "**word**" } },
  { "italic pair", { "" }, { 1, 0 }, "i;;iword<Esc>", { "*word*" } },
  { "strike / code / highlight", { "" }, { 1, 0 }, "i;;sa;;s ;;cb;;c ;;hc;;h<Esc>", { "~~a~~ `b` ==c==" } },
  { "jump out of the pair", { "" }, { 1, 0 }, "i;;bword;;b rest<Esc>", { "**word** rest" } },
  { "nested pairs", { "" }, { 1, 0 }, "i;;bx;;iy;;iz;;bw<Esc>", { "**x*y*z**w" } },
  { "in the middle of a line", { "see here" }, { 1, 3 }, "a;;bthis;;b <Esc>", { "see **this** here" } },
  { "jump out of a pair typed by hand", { "**x**" }, { 1, 2 }, "a;;b!<Esc>", { "**x**!" } },
  { "multibyte text", { "" }, { 1, 0 }, "i;;iaçã;;iü<Esc>", { "*açã*ü" } },

  -- the README examples, typed exactly
  { "readme: bold/italic sentence", { "" }, { 1, 0 }, "i;;bimportant;;b and ;;ialso;;i this<Esc>",
    { "**important** and *also* this" } },
  { "readme: link", { "" }, { 1, 0 }, "i;;lthe docs;;lhttps://x.io;;l<Esc>", { "[the docs](https://x.io)" } },
  { "readme: nested", { "" }, { 1, 0 }, "i;;bbold ;;iboth;;i;;b<Esc>", { "**bold *both***" } },

  -- links
  { "link without clipboard: text, url, out", { "" }, { 1, 0 }, "i;;ldocs;;lhttps://x.io;;l ok<Esc>",
    { "[docs](https://x.io) ok" } },
  { "link with clipboard URL skips the url stage", { "" }, { 1, 0 }, "i;;ldocs;;l!<Esc>", { "[docs](https://c.io)!" },
    setup = function()
      clip = "https://c.io"
    end },
  { "link jump by text shape", { "[t]()" }, { 1, 1 }, "a;;lu;;l.<Esc>", { "[t](u)." } },

  -- anything else is typed as-is
  { "unknown key keeps ;; and the key", { "" }, { 1, 0 }, "i;;x<Esc>", { ";;x" } },
  { "three semicolons", { "" }, { 1, 0 }, "i;;;<Esc>", { ";;;" } },
  { "single semicolons untouched", { "" }, { 1, 0 }, "ia; b; c;<Esc>", { "a; b; c;" } },
  { "Esc restores ;; and leaves insert", { "" }, { 1, 0 }, "i;;<Esc>", { ";;" } },
  { "<CR> after ;; still continues lists", { "- a" }, { 1, 0 }, "A;;<CR>b<Esc>", { "- a;;", "- b" } },
  { "existing ; before the cursor doesn't count", { "a;" }, { 1, 0 }, "A;b<Esc>", { "a;;b" } },

  -- code
  { "off inside code blocks", { "```c", "", "```" }, { 2, 0 }, "ifor(;;b)<Esc>", { "```c", "for(;;b)", "```" } },
  { "off while typing inside inline code", { "`for()`" }, { 1, 4 }, "a;;<Esc>", { "`for(;;)`" } },
  { "jump out of inline code", { "" }, { 1, 0 }, "i;;cfoo;;c bar<Esc>", { "`foo` bar" } },
  { "in a code span only c is offered", { "`x`" }, { 1, 1 }, "a;;b<Esc>", { "`x;;b`" } },

  -- undo
  { "undo removes the whole insert", { "a" }, { 1, 0 }, { "A ;;bword;;b<Esc>", "u" }, { "a" } },

  -- other triggers
  { "custom character trigger jj", { "" }, { 1, 0 }, "ijjbx<Esc>", { "**x**" }, setup = with_trigger("jj") },
  { "jj trigger keeps single j", { "" }, { 1, 0 }, "ijam<Esc>", { "jam" }, setup = with_trigger("jj") },
  { "key trigger <C-g>", { "" }, { 1, 0 }, "i<C-g>bx<C-g>by<Esc>", { "**x**y" }, setup = with_trigger("<C-g>") },
  { "<C-g> passes other keys to Vim (<C-g>j)", { "ab", "cd" }, { 1, 1 }, "i<C-g>jX<Esc>", { "ab", "cXd" },
    setup = with_trigger("<C-g>") },
  { "config rejects a one-character trigger", fn = function()
    local ok = pcall(config.setup, { insert = { trigger = ";" } })
    eq(ok, false)
    config.setup({})
  end },
}

local failed, total = H.run("insert trigger", cases, { before_each = before_each })
links.read_clipboard = real_clip
config.options.insert.trigger = ";;"
return failed, total
