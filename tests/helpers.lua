local api = vim.api
local H = {}

local function fresh_buf(lines, name)
  vim.cmd("enew!")
  local buf = api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  if name then
    local old = vim.fn.bufnr(name)
    if old ~= -1 and old ~= buf then
      vim.cmd("bwipeout! " .. old)
    end
    api.nvim_buf_set_name(buf, name)
  end
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].undolevels = vim.bo[buf].undolevels -- undo break after the fixture
  return buf
end

--- Feed keys chunk by chunk. After each chunk, fire TextChanged if the buffer
--- changed in normal mode: the main loop does this between real keystrokes,
--- but not while a headless script is running.
local function feed(keys)
  for _, k in ipairs(type(keys) == "table" and keys or { keys }) do
    local buf = api.nvim_get_current_buf()
    local tick = api.nvim_buf_get_changedtick(buf)
    api.nvim_feedkeys(api.nvim_replace_termcodes(k, true, false, true), "mx", false)
    buf = api.nvim_get_current_buf()
    if vim.fn.mode() == "n" and api.nvim_buf_get_changedtick(buf) ~= tick then
      api.nvim_exec_autocmds("TextChanged", { buffer = buf, modeline = false })
    end
  end
end

H.feed = feed

--- Scratch markdown buffer with the cursor placed; returns the buffer.
function H.buf(lines, cursor, name)
  local buf = fresh_buf(lines, name)
  api.nvim_win_set_cursor(0, cursor or { 1, 0 })
  return buf
end

--- vim.ui.input answers, consumed in order (nil = cancel).
H.queue = {}
function H.mock_input()
  H._real_input = H._real_input or vim.ui.input
  vim.ui.input = function(_, cb)
    cb(table.remove(H.queue, 1))
  end
end
function H.restore_input()
  if H._real_input then
    vim.ui.input = H._real_input
  end
end
function H.answers(...)
  local list = { ... }
  local n = select("#", ...)
  return function()
    H.queue = {}
    for i = 1, n do
      H.queue[i] = list[i]
    end
    H.queue.n = nil
  end
end

--- Temporary directory with files: { ["a.md"] = { "line", ... } }.
function H.tmpdir(files)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  for name, lines in pairs(files or {}) do
    local path = dir .. "/" .. name
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(lines, path)
  end
  return vim.fs.normalize(vim.fn.resolve(dir))
end

function H.eq(a, b)
  if not vim.deep_equal(a, b) then
    error(("expected %s, got %s"):format(vim.inspect(b), vim.inspect(a)), 2)
  end
end

--- Run a list of cases. Returns the number of failures.
--- Buffer case: { name, lines, cursor, keys, expected_lines, expected_cursor?, setup = fn? }
--- Unit case:   { name, fn = function() ... error() on failure ... end }
---@param opts? { before_each?: fun() }
function H.run(title, cases, opts)
  opts = opts or {}
  print("\n" .. title .. "\n")
  local failed = 0
  local orig_notify = vim.notify
  vim.notify = function() end
  for _, c in ipairs(cases) do
    if opts.before_each then
      opts.before_each()
    end
    local name = c[1]
    local pass, detail
    if c.fn then
      local ok, err = pcall(c.fn)
      pass, detail = ok, (not ok) and ("        error: " .. tostring(err)) or nil
    else
      local _, lines, cursor, keys, want, want_cur = unpack(c)
      local buf = fresh_buf(lines, c.name)
      api.nvim_win_set_cursor(0, cursor)
      if c.setup then
        c.setup()
      end
      local ok, err = pcall(feed, keys)
      if vim.fn.mode() ~= "n" then
        vim.cmd("stopinsert")
      end
      local got = api.nvim_buf_get_lines(buf, 0, -1, false)
      local got_cur = api.nvim_win_get_cursor(0)
      pass = ok and vim.deep_equal(got, want) and (not want_cur or vim.deep_equal(got_cur, want_cur))
      if not pass then
        detail = (not ok and ("        error: " .. tostring(err) .. "\n") or "")
          .. "        want: "
          .. vim.inspect(want)
          .. (want_cur and (" @" .. vim.inspect(want_cur)) or "")
          .. "\n"
          .. "        got:  "
          .. vim.inspect(got)
          .. " @"
          .. vim.inspect(got_cur)
      end
    end
    if pass then
      print("  ok    " .. name .. "\n")
    else
      failed = failed + 1
      print("  FAIL  " .. name .. "\n" .. (detail or "") .. "\n")
    end
  end
  vim.notify = orig_notify
  print(("%d/%d passed\n"):format(#cases - failed, #cases))
  return failed, #cases
end

return H
