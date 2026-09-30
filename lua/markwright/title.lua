-- Async page-title fetching for links. Spec: SPEC.md section 7.3.
local config = require("markwright.config")

local M = {}

M.user_agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
  .. "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"

local NAMED = {
  amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ",
  ndash = "–", mdash = "—", hellip = "…", laquo = "«", raquo = "»",
  lsquo = "‘", rsquo = "’", ldquo = "“", rdquo = "”", middot = "·", bull = "•",
  copy = "©", reg = "®", trade = "™",
}

function M.decode_entities(s)
  s = s:gsub("&#[xX](%x+);", function(h)
    return vim.fn.nr2char(tonumber(h, 16))
  end)
  s = s:gsub("&#(%d+);", function(d)
    return vim.fn.nr2char(tonumber(d))
  end)
  s = s:gsub("&(%a+);", function(name)
    return NAMED[name]
  end)
  return s
end

local function clean(s)
  if not s then
    return nil
  end
  s = M.decode_entities(s):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  return s ~= "" and s or nil
end

--- Extract a title from HTML: <title>, falling back to og:title.
---@return string?
function M.parse(html)
  local lower = html:lower()
  local _, e = lower:find("<title[^>]*>")
  if e then
    local cs = lower:find("</title>", e + 1, true)
    local t = cs and clean(html:sub(e + 1, cs - 1))
    if t then
      return t
    end
  end
  for _, pat in ipairs({
    "<meta[^>]-property=[\"']og:title[\"'][^>]-content=[\"']([^\"']*)[\"']",
    "<meta[^>]-content=[\"']([^\"']*)[\"'][^>]-property=[\"']og:title[\"']",
  }) do
    local s, e2 = lower:find(pat)
    if s then
      local chunk = html:sub(s, e2)
      local t = clean(chunk:match("[Cc][Oo][Nn][Tt][Ee][Nn][Tt]=[\"']([^\"']*)[\"']"))
      if t then
        return t
      end
    end
  end
end

--- Fetch the page title of `url` asynchronously. `cb(title|nil)` runs on the main loop.
---@param url string
---@param cb fun(title: string?)
function M.fetch(url, cb)
  if vim.fn.executable("curl") == 0 then
    return cb(nil)
  end
  local timeout = config.options.links.title_timeout_ms
  local cmd = {
    "curl", "-sL", "--compressed",
    "--max-time", tostring(math.max(1, math.ceil(timeout / 1000))),
    "-A", M.user_agent,
    "-r", "0-65535", -- first 64 KB is plenty for <head>
    url,
  }
  local ok = pcall(vim.system, cmd, { text = true, timeout = timeout + 1000 }, function(res)
    vim.schedule(function()
      if res.code ~= 0 or not res.stdout or res.stdout == "" then
        return cb(nil)
      end
      cb(M.parse(res.stdout))
    end)
  end)
  if not ok then
    cb(nil)
  end
end

return M
