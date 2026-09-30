local M = {}

---@class mdtools.Config
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
    -- Insert mode: type the trigger, then i/b/s/c/h/l. Two or more characters
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
  },
  tables = {
    align_on_insert_leave = true,
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
  diagnostics = {
    enabled = true,
    on_save = true,
    severity = vim.diagnostic.severity.WARN,
  },
}

---@type mdtools.Config
M.options = vim.deepcopy(M.defaults)

local function validate(opts)
  local f = opts.format
  for _, name in ipairs({ "italic", "bold", "strike", "code", "highlight" }) do
    local m = f[name] and f[name].marker
    if type(m) ~= "string" or m == "" then
      error(("mdtools: format.%s.marker must be a non-empty string"):format(name))
    end
  end
  if f.multiline ~= "per_line" then
    error("mdtools: format.multiline only supports 'per_line'")
  end
  local t = opts.insert and opts.insert.trigger
  if type(t) ~= "string" then
    error("mdtools: insert.trigger must be a string")
  end
  if t ~= "" and not t:match("^<.+>$") and vim.fn.strchars(t) < 2 then
    error("mdtools: insert.trigger must be at least two characters (or a key like '<C-g>')")
  end
  if type(opts.filetypes) ~= "table" then
    error("mdtools: filetypes must be a list")
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
