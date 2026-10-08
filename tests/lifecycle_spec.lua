-- Buffer lifecycle: the plugin keeps working when a buffer is unloaded and
-- reopened (:bdelete, :bunload, LazyVim's <leader>bd), or reloaded (:e!).
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local api = vim.api
local eq = H.eq

local dir = H.tmpdir({ ["a.md"] = { "1. a", "2. b", "3. c", "", "word" } })
local file = dir .. "/a.md"

local function open()
  vim.cmd("silent edit! " .. vim.fn.fnameescape(file))
  return api.nvim_get_current_buf()
end

local function works()
  -- a key, list renumbering (TextChanged) and the ;; trigger
  api.nvim_buf_set_lines(0, 0, -1, false, { "1. a", "2. b", "3. c", "", "word" })
  api.nvim_win_set_cursor(0, { 5, 0 })
  H.feed(" mbiw")
  eq(api.nvim_buf_get_lines(0, 4, 5, false)[1], "**word**")
  api.nvim_win_set_cursor(0, { 1, 0 })
  H.feed("dd")
  eq(api.nvim_buf_get_lines(0, 0, 2, false), { "1. b", "2. c" })
  H.feed("Go;;bx;;b<Esc>")
  eq(api.nvim_buf_get_lines(0, -2, -1, false)[1], "**x**")
end

local function autocmd_count(buf)
  return #api.nvim_get_autocmds({ buffer = buf })
end

local cases = {
  {
    ":bdelete, then reopening the file",
    fn = function()
      local buf = open()
      local n = autocmd_count(buf)
      vim.cmd("enew!")
      vim.cmd("bdelete! " .. buf)
      eq(open(), buf) -- the buffer number is reused
      works()
      eq(autocmd_count(buf), n)
    end,
  },
  {
    ":bunload, then reopening",
    fn = function()
      local buf = open()
      vim.cmd("enew!")
      vim.cmd("bunload! " .. buf)
      open()
      works()
    end,
  },
  {
    ":e! keeps everything",
    fn = function()
      local buf = open()
      local n = autocmd_count(buf)
      vim.cmd("silent edit!")
      works()
      eq(autocmd_count(buf), n)
    end,
  },
  {
    "filetype set again doesn't attach twice",
    fn = function()
      local buf = open()
      local n = autocmd_count(buf)
      vim.bo.filetype = "markdown"
      eq(autocmd_count(buf), n)
      works()
    end,
  },
}

local failed, total = H.run("buffer lifecycle", cases)
vim.cmd("silent! %bwipeout!")
return failed, total
