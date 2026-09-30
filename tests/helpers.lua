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

--- Each case: { name, lines, cursor, keys, expected_lines, expected_cursor? }
function H.run(cases)
  local failed, warnings = 0, {}
  local orig_notify = vim.notify
  vim.notify = function(msg)
    table.insert(warnings, msg)
  end
  for _, c in ipairs(cases) do
    local name, lines, cursor, keys, want, want_cur = unpack(c)
    local buf = fresh_buf(lines)
    api.nvim_win_set_cursor(0, cursor)
    local ok, err = pcall(function()
      for _, k in ipairs(type(keys) == "table" and keys or { keys }) do
        api.nvim_feedkeys(api.nvim_replace_termcodes(k, true, false, true), "mx", false)
      end
    end)
    if vim.fn.mode() ~= "n" then
      vim.cmd("stopinsert")
    end
    local got = api.nvim_buf_get_lines(buf, 0, -1, false)
    local got_cur = api.nvim_win_get_cursor(0)
    local pass = ok and vim.deep_equal(got, want) and (not want_cur or vim.deep_equal(got_cur, want_cur))
    if pass then
      print("  ok    " .. name .. "\n")
    else
      failed = failed + 1
      print("  FAIL  " .. name)
      if not ok then
        print("        error: " .. tostring(err))
      end
      print("        want: " .. vim.inspect(want) .. (want_cur and (" @" .. vim.inspect(want_cur)) or ""))
      print("        got:  " .. vim.inspect(got) .. " @" .. vim.inspect(got_cur))
    end
  end
  vim.notify = orig_notify
  print(("\n%d/%d passed"):format(#cases - failed, #cases))
  vim.cmd(failed == 0 and "qa!" or "cq!")
end

return H
