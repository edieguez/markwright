-- Runs every *_spec.lua in tests/ and exits non-zero on failure.
local dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local failed, total = 0, 0
for _, file in ipairs(vim.fn.glob(dir .. "/*_spec.lua", false, true)) do
  local ok, f, n = pcall(dofile, file)
  if not ok then
    print("\nERROR loading " .. file .. ": " .. tostring(f) .. "\n")
    failed = failed + 1
  else
    failed, total = failed + f, total + n
  end
end
print(("\nTOTAL %d/%d passed\n"):format(total - failed, total))
vim.cmd(failed == 0 and "qa!" or "cq!")
