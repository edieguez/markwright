-- Formatting engine specs (SPEC.md section 6). Leader is <Space>, prefix " m".
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")

local cases = {
  -- word under cursor
  { "italic word", { "hello world" }, { 1, 0 }, " mi", { "*hello* world" }, { 1, 1 } },
  { "bold word, cursor mid-word", { "hello world" }, { 1, 8 }, " mb", { "hello **world**" }, { 1, 10 } },
  { "bold toggles off", { "hello **world**" }, { 1, 9 }, " mb", { "hello world" }, { 1, 7 } },
  { "remove whole span from inner word", { "**hello world**" }, { 1, 9 }, " mb", { "hello world" }, { 1, 7 } },
  { "cursor on marker", { "**hello**" }, { 1, 0 }, " mb", { "hello" } },
  { "punctuation stays outside", { "hello, there" }, { 1, 1 }, " mi", { "*hello*, there" } },
  { "heading word", { "# Title" }, { 1, 3 }, " mb", { "# **Title**" } },
  { "multibyte word", { "una canción aquí" }, { 1, 6 }, " mi", { "una *canción* aquí" } },
  { "escaped markers are literal", { [[\*word\*]] }, { 1, 3 }, " mi", { [[\**word*\*]] } },

  -- recognition of _ and __
  { "underscore italic off", { "_word_" }, { 1, 2 }, " mi", { "word" } },
  { "double underscore bold off", { "__word__" }, { 1, 3 }, " mb", { "word" } },
  { "snake_case is not italic", { "snake_case_word" }, { 1, 6 }, " mi", { "*snake_case_word*" } },

  -- nesting
  { "italic on bold combines", { "**word**" }, { 1, 3 }, " mi", { "***word***" } },
  { "bold off from ***", { "***word***" }, { 1, 4 }, " mb", { "*word*" } },
  { "italic off from ***", { "***word***" }, { 1, 4 }, " mi", { "**word**" } },

  -- other formats
  { "strike on", { "del" }, { 1, 0 }, " ms", { "~~del~~" } },
  { "strike off", { "~~del~~" }, { 1, 3 }, " ms", { "del" } },
  { "code on", { "foo" }, { 1, 0 }, " mc", { "`foo`" } },
  { "code off", { "`foo`" }, { 1, 2 }, " mc", { "foo" } },
  { "code escalates on backtick", { "a`b" }, { 1, 0 }, "v$ mc", { "``a`b``" } },
  { "code pads leading backtick", { "`x" }, { 1, 0 }, "v$ mc", { "`` `x ``" } },
  { "code off removes padding", { "`` `x ``" }, { 1, 4 }, " mc", { "`x" } },
  { "highlight on", { "word" }, { 1, 0 }, " mh", { "==word==" } },
  { "highlight off", { "a ==two words== b" }, { 1, 9 }, " mh", { "a two words b" } },

  -- visual
  { "visual trims trailing space", { "one two three" }, { 1, 4 }, "vlll mb", { "one **two** three" } },
  { "visual across words", { "one two three" }, { 1, 0 }, "v6l mb", { "**one two** three" } },
  {
    "visual line: per line, prefixes skipped",
    { "- item one", "- [ ] task two", "", "# Heading", "> quoted" },
    { 1, 0 },
    "V4j mb",
    { "- **item one**", "- [ ] **task two**", "", "# **Heading**", "> **quoted**" },
  },
  {
    "charwise multi-line",
    { "alpha beta", "gamma delta" },
    { 1, 6 },
    "vjhh mb",
    { "alpha **beta**", "**gamma** delta" },
  },
  { "visual toggles off", { "x **bold** y" }, { 1, 4 }, "vll mb", { "x bold y" } },

  -- operator + dot repeat + undo
  { "operator with motion", { "one two three" }, { 1, 0 }, " mB2e", { "**one two** three" } },
  { "dot repeat", { "a b c" }, { 1, 0 }, " mbW.", { "**a** **b** c" } },
  { "single undo step", { "hello" }, { 1, 0 }, " mbu", { "hello" } },
  { "undo reverts one toggle", { "hello" }, { 1, 0 }, { " mb", " mi", "u" }, { "**hello**" } },
  {
    "undo multi-line op at once",
    { "one", "two" },
    { 1, 0 },
    "Vj mbu",
    { "one", "two" },
  },

  -- code guard
  { "skip in fenced block", { "```lua", "x = 1", "```" }, { 2, 0 }, " mb", { "```lua", "x = 1", "```" } },
  { "skip in code span", { "`code here`" }, { 1, 2 }, " mb", { "`code here`" } },
  { "code off inside span", { "`code here`" }, { 1, 2 }, " mc", { "code here" } },

  -- empty markers on whitespace
  { "empty line inserts markers", { "" }, { 1, 0 }, " mbx\27", { "**x**" } },
  { "trailing space", { "foo " }, { 1, 3 }, " mix\27", { "foo *x*" } },
  { "middle space keeps spacing", { "a b" }, { 1, 1 }, " mbx\27", { "a **x** b" } },
}

return H.run("format", cases)
