local M = {}

---@class markwright.Config
M.defaults = {
  filetypes = { "markdown" },
  keymaps = {
    enabled = true,
    prefix = "<leader>m",
  },
  format = {
    italic = { marker = "*" },
    bold = { marker = "**" },
    strike = { marker = "~~" },
    code = { marker = "`" },
    highlight = { marker = "==" },
    trim_whitespace = true, -- markers go inside leading/trailing spaces
    multiline = "per_line", -- only mode for now
    warn_in_code = true, -- notify when formatting inside code is skipped
  },
  insert = {
    -- Insert mode: type the trigger, then i/b/s/c/h/k. Two or more characters
    -- (";;", "jj", ",,") or a key like "<C-g>". "" disables.
    trigger = ";;",
  },
  links = {
    use_clipboard = true,
    fetch_title = true,
    title_timeout_ms = 5000,
    smart_paste_visual = true,
    smart_paste_normal = true,
  },
  follow = {
    key = "gx",
    create_missing_md = true,
  },
  lists = {
    continue_on_enter = true,
    tab_indent = true,
    auto_renumber = true,
    checkbox_add = true,
    checkbox_key = "<CR>", -- normal mode; "" to disable
    -- checking an item appends this (os.date format), unchecking removes it;
    -- false = off. "✅ %Y-%m-%d" is the Obsidian Tasks format.
    done_date = "✅ %Y-%m-%d %H:%M",
    -- fill progress cookies `[/]` / `[%]` on parent items: `- Release [2/5]`
    progress = true,
    -- markers for new items made by the list converters (<P>lb / <P>ln / <P>lc)
    bullet = "-", -- "-", "*" or "+"
    number_delim = ".", -- "." or ")"
    -- optional keys that move a list item (with its children) on list items and
    -- run their previous mapping elsewhere, e.g. { down = "<M-j>", up = "<M-k>" }
    move_keys = nil,
  },
  nav = {
    -- heading motions (normal, visual and operator-pending); false or "" disables one
    enabled = true,
    next = "]]",
    prev = "[[",
    next_sibling = "][", -- same level, within the parent section
    prev_sibling = "[]",
    parent = "[u",
    outline = nil, -- nil: <prefix>o; false or "" disables
  },
  textobjects = {
    -- letters after i/a in operator-pending and visual mode; false or "" disables one
    enabled = true,
    link = "k", -- ik/ak: link text / whole link (images and autolinks too)
    url = "u", -- iu: link destination
    code = "c", -- ic/ac: inline code or code block content / whole
    section = "h", -- ih/ah: heading section content / heading + content
    cell = "|", -- i|/a|: table cell text / cell with padding
    item = "L", -- iL/aL: list item text / item with its children
    emphasis = "*", -- i*/a*: inside / around *, **, ~~, ==
    search_lines = 500, -- not inside an object: use the next one within this many lines
  },
  blockquotes = {
    continue_on_enter = true, -- <CR>, o, O keep the `>`; <CR> on an empty `>` line ends the quote
  },
  callouts = {
    types = { "NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION" }, -- order in the picker
    default = nil, -- a type here skips the picker when wrapping (changing a type always asks)
  },
  tables = {
    align_on_insert_leave = true,
    csv_separator = ",", -- default offered by table → CSV (<P>tx); "\t" for tab
  },
  images = {
    dir = "assets", -- relative to the markdown file's folder; absolute, ~, or function(buf) -> path
    name = "image-%Y%m%d-%H%M%S", -- default file name (os.date format), without extension
    prompt_name = true, -- ask for the name (prefilled with the default)
    alt = "name", -- alt text: "name" (from a typed name), "prompt", or "empty"
    smart_paste = false, -- plain `p` pastes an image when the clipboard holds one and no text
  },
  toc = {
    update_on_save = true,
    marker_start = "<!-- toc -->",
    marker_end = "<!-- tocstop -->",
    min_level = 2,
    max_level = 4,
  },
  url_check = {
    -- :Markwright check urls (never automatic)
    concurrency = 8, -- requests at the same time
    timeout_ms = 10000, -- per request
    ignore = {}, -- Lua patterns of URLs to skip, e.g. { "^https://localhost" }
    open_quickfix = true, -- open the quickfix list when something is broken
    severity = vim.diagnostic.severity.WARN, -- for broken links (restricted ones are INFO)
  },
  diagnostics = {
    enabled = true,
    on_save = true,
    severity = vim.diagnostic.severity.WARN,
  },
}

---@type markwright.Config
M.options = vim.deepcopy(M.defaults)

local function validate(opts)
  local f = opts.format
  for _, name in ipairs({ "italic", "bold", "strike", "code", "highlight" }) do
    local m = f[name] and f[name].marker
    if type(m) ~= "string" or m == "" then
      error(("markwright: format.%s.marker must be a non-empty string"):format(name))
    end
  end
  if f.multiline ~= "per_line" then
    error("markwright: format.multiline only supports 'per_line'")
  end
  local t = opts.insert and opts.insert.trigger
  if type(t) ~= "string" then
    error("markwright: insert.trigger must be a string")
  end
  if t ~= "" and not t:match("^<.+>$") and vim.fn.strchars(t) < 2 then
    error("markwright: insert.trigger must be at least two characters (or a key like '<C-g>')")
  end
  local lo = opts.lists or {}
  if not vim.tbl_contains({ "-", "*", "+" }, lo.bullet) then
    error("markwright: lists.bullet must be '-', '*' or '+'")
  end
  if not vim.tbl_contains({ ".", ")" }, lo.number_delim) then
    error("markwright: lists.number_delim must be '.' or ')'")
  end
  local dd = opts.lists and opts.lists.done_date
  if dd ~= false and dd ~= nil and (type(dd) ~= "string" or dd == "") then
    error("markwright: lists.done_date must be a non-empty os.date format or false")
  end
  if type(opts.filetypes) ~= "table" then
    error("markwright: filetypes must be a list")
  end
end

function M.setup(user)
  local opts = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user or {})
  -- lists are replaced, not merged
  if user and user.filetypes then
    opts.filetypes = user.filetypes
  end
  validate(opts)
  M.options = opts
  return opts
end

return M
