-- GitHub-style heading anchors. Spec: SPEC.md section 8 (Slugs).
local M = {}

-- Non-ASCII punctuation GitHub drops from anchors.
local UNICODE_PUNCT =
  { "—", "–", "«", "»", "“", "”", "‘", "’", "…", "¿", "¡", "·", "•", "©", "®", "™" }

--- Replace links/images with their text (keeps other inline formatting).
function M.strip_links(text)
  local s = text
  s = s:gsub("!%[(.-)%]%b()", "%1")
  s = s:gsub("%[(.-)%]%b()", "%1")
  s = s:gsub("%[(.-)%]%b[]", "%1")
  s = s:gsub("<(%a[%w+.-]*:[^>]*)>", "%1")
  return s
end

--- Inline markup outside code spans → plain text.
local function plain_text(s)
  s = s:gsub("</?%a[^>]*>", "") -- html tags
  s = s:gsub("[*~]", ""):gsub("==", "")
  -- underscores used for emphasis sit at word boundaries; intraword ones stay
  s = s:gsub("^_+", ""):gsub("_+$", ""):gsub("(%s)_+", "%1"):gsub("_+(%s)", "%1")
  s = s:gsub("\\(%p)", "%1")
  return s
end

--- Inline markdown → plain text, as a renderer would show it. Code spans
--- keep their content as written.
function M.plain(text)
  local s = M.strip_links(text)
  local out, pos = {}, 1
  while true do
    local a, b = s:find("`+", pos)
    local c, d = b, nil
    while c do -- the closing run has the same length
      c, d = s:find("`+", c + 1)
      if c and d - c == b - a then
        break
      end
      c = d
    end
    if not c then
      table.insert(out, plain_text(s:sub(pos)))
      break
    end
    table.insert(out, plain_text(s:sub(pos, a - 1)))
    table.insert(out, s:sub(b + 1, c - 1))
    pos = d + 1
  end
  return table.concat(out)
end

---@param text string heading text (inline markdown)
---@return string
function M.slug(text)
  local s = vim.fn.tolower(M.plain(text))
  s = s:gsub("%p", function(c)
    return (c == "-" or c == "_") and c or ""
  end)
  for _, u in ipairs(UNICODE_PUNCT) do
    s = s:gsub(vim.pesc(u), "")
  end
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  s = s:gsub(" ", "-")
  return s
end

--- Make slugs unique in document order: x, x-1, x-2 ...
---@param slugs string[]
---@return string[]
function M.unique(slugs)
  local seen, out = {}, {}
  for i, s in ipairs(slugs) do
    local n = seen[s]
    if n then
      local candidate
      repeat
        candidate = s .. "-" .. n
        n = n + 1
      until not seen[candidate]
      seen[s] = n
      seen[candidate] = 1
      out[i] = candidate
    else
      seen[s] = 1
      out[i] = s
    end
  end
  return out
end

return M
