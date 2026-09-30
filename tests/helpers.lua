local api = vim.api
local H = {}

local function fresh_buf(lines)
  vim.cmd("enew!")
  local buf = api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].undolevels = vim.bo[buf].undolevels -- undo break after the fixture
  return buf
end

local function feed(keys)
  for _, k in ipairs(type(keys) == "table" and keys or { keys }) do
    api.nvim_feedkeys(api.nvim_replace_termcodes(k, true, false, true), "mx", false)
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
      local buf = fresh_buf(lines)
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
          .. "        want: " .. vim.inspect(want) .. (want_cur and (" @" .. vim.inspect(want_cur)) or "") .. "\n"
          .. "        got:  " .. vim.inspect(got) .. " @" .. vim.inspect(got_cur)
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
