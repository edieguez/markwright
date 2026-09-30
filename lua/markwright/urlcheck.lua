-- External URL checker (on demand). Spec: SPEC.md section 14.23.
local api = vim.api
local config = require("markwright.config")
local ts = require("markwright.ts")
local doc = require("markwright.doc")
local util = require("markwright.util")

local M = {}

M.ns = api.nvim_create_namespace("markwright_urls")

local function opts()
  return config.options.url_check
end

-- Collecting ------------------------------------------------------------------------

---@class markwright.UrlRef
---@field url string normalized http(s) URL
---@field row integer 0-based
---@field col integer 0-based start of the URL text
---@field ecol integer exclusive end

local function normalize(raw)
  local url = vim.trim(raw):gsub("^<(.*)>$", "%1")
  if url:match("^www%.") then
    url = "https://" .. url
  end
  if url:match("^[Hh][Tt][Tt][Pp][Ss]?://") then
    return url
  end
end

local function ignored(url)
  for _, pat in ipairs(opts().ignore or {}) do
    if url:find(pat) then
      return true
    end
  end
  return false
end

local URL_STARTS = { "[Hh][Tt][Tt][Pp][Ss]?://", "www%." }

--- External links in the buffer (code blocks and code spans excluded).
---@return markwright.UrlRef[]
function M.collect(buf)
  local refs, taken = {}, {}
  local function add(raw, row, col, ecol)
    local url = normalize(raw)
    if url and not ignored(url) then
      table.insert(refs, { url = url, row = row, col = col, ecol = ecol })
    end
    taken[row] = taken[row] or {}
    table.insert(taken[row], { col, ecol })
  end

  local p = ts.parser(buf)
  if not p then
    return refs
  end
  p:parse(true)
  local inl = p:children()["markdown_inline"]
  if inl then
    for _, tree in ipairs(inl:trees()) do
      local function walk(n)
        local t = n:type()
        if t == "inline_link" or t == "image" then
          for c in n:iter_children() do
            if c:type() == "link_destination" then
              local r, sc, _, ec = c:range()
              add(vim.treesitter.get_node_text(c, buf), r, sc, ec)
            end
          end
        elseif t == "uri_autolink" then
          local r, sc, _, ec = n:range()
          add(vim.treesitter.get_node_text(n, buf), r, sc + 1, ec - 1)
        end
        for c in n:iter_children() do
          walk(c)
        end
      end
      walk(tree:root())
    end
  end

  local code = doc.code_rows(buf)
  for _, d in pairs(doc.definitions(buf, code)) do
    add(d.dest, d.row, d.col, d.col + #d.dest)
  end

  -- bare URLs, skipping code and anything already found above
  local links = require("markwright.links")
  for i, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local row = i - 1
    if not code[row] then
      local scan = doc.strip_code_spans(line)
      for _, pat in ipairs(URL_STARTS) do
        local init = 1
        while true do
          local s = scan:find(pat, init)
          if not s then
            break
          end
          local sc, ec, url = links.url_at(scan, s - 1)
          if sc then
            local overlap = false
            for _, t in ipairs(taken[row] or {}) do
              if sc < t[2] and ec > t[1] then
                overlap = true
              end
            end
            if not overlap and scan:sub(sc, sc) ~= "<" then
              add(url, row, sc, ec)
            end
          end
          init = s + 1
        end
      end
    end
  end

  table.sort(refs, function(a, b)
    return a.row < b.row or (a.row == b.row and a.col < b.col)
  end)
  return refs
end

-- Checking --------------------------------------------------------------------------

local function curl_cmd(url, method)
  local secs = tostring(math.max(1, math.ceil(opts().timeout_ms / 1000)))
  local cmd = { "curl", "-sS", "-o", "/dev/null", "-L", "--max-redirs", "10", "--max-time", secs }
  vim.list_extend(cmd, { "-A", require("markwright.title").user_agent, "-w", "%{http_code}" })
  if method == "HEAD" then
    table.insert(cmd, "-I")
  else
    vim.list_extend(cmd, { "-r", "0-0" }) -- first byte only
  end
  table.insert(cmd, url)
  return cmd
end

---@class markwright.UrlResult
---@field code integer HTTP status (0 when no response)
---@field exit integer curl exit code

--- One request (overridable in tests). `cb(result)` runs on the main loop.
---@param method "HEAD"|"GET"
function M.request(url, method, cb)
  local ok = pcall(vim.system, curl_cmd(url, method), { text = true }, function(res)
    vim.schedule(function()
      cb({ code = tonumber(res.stdout) or 0, exit = res.code })
    end)
  end)
  if not ok then
    cb({ code = 0, exit = -1 })
  end
end

--- HEAD first; on any error status fall back to a GET (many servers answer
--- HEAD badly).
function M.check_url(url, cb)
  M.request(url, "HEAD", function(res)
    if res.exit == 0 and res.code >= 200 and res.code < 400 then
      return cb(res)
    end
    if res.exit == 28 or res.exit == 6 or res.exit == 7 then
      return cb(res) -- timeout / unknown host / refused: GET won't help
    end
    M.request(url, "GET", cb)
  end)
end

local CURL_ERRORS = {
  [6] = "host not found",
  [7] = "connection refused",
  [28] = "timed out",
  [35] = "TLS error",
  [51] = "certificate problem",
  [58] = "certificate problem",
  [60] = "certificate problem",
  [47] = "too many redirects",
}

--- "ok" | "restricted" | "broken", and a message.
function M.classify(res)
  if res.exit ~= 0 then
    return "broken", CURL_ERRORS[res.exit] or ("request failed (curl exit " .. res.exit .. ")")
  end
  local c = res.code
  if (c >= 200 and c < 400) or c == 416 then
    return "ok"
  end
  if c == 401 or c == 403 or c == 429 then
    return "restricted", ("HTTP %d: needs a login or blocks automated checks"):format(c)
  end
  if c == 0 then
    return "broken", "no response"
  end
  return "broken", ("HTTP %d"):format(c)
end

M._running = {} ---@type table<integer, boolean>

--- Check every external link in `buf` and report the results.
---@param on_done? fun(summary: {total: integer, broken: integer, restricted: integer})
function M.run(buf, on_done)
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  if M._running[buf] then
    return util.notify("a URL check is already running for this buffer")
  end
  if vim.fn.executable("curl") == 0 and M.request == M._real_request then
    return util.warn("curl is needed to check URLs")
  end
  local refs = M.collect(buf)
  vim.diagnostic.reset(M.ns, buf)
  local by_url, urls = {}, {}
  for _, r in ipairs(refs) do
    if not by_url[r.url] then
      by_url[r.url] = {}
      table.insert(urls, r.url)
    end
    table.insert(by_url[r.url], r)
  end
  if #urls == 0 then
    util.notify("no external links to check")
    if on_done then
      on_done({ total = 0, broken = 0, restricted = 0 })
    end
    return
  end
  M._running[buf] = true
  util.notify(("checking %d link%s…"):format(#urls, #urls == 1 and "" or "s"))

  local results, next_i, active, finished = {}, 1, 0, 0
  local limit = math.max(1, opts().concurrency)

  local function report()
    M._running[buf] = nil
    if not api.nvim_buf_is_valid(buf) then
      return
    end
    local diags, qf = {}, {}
    local broken, restricted = 0, 0
    local name = api.nvim_buf_get_name(buf)
    for _, url in ipairs(urls) do
      local kind, msg = M.classify(results[url])
      if kind ~= "ok" then
        if kind == "broken" then
          broken = broken + 1
        else
          restricted = restricted + 1
        end
        local sev = kind == "broken" and opts().severity or vim.diagnostic.severity.INFO
        for _, r in ipairs(by_url[url]) do
          table.insert(diags, {
            lnum = r.row,
            col = r.col,
            end_col = r.ecol,
            severity = sev,
            source = "markwright",
            message = msg .. ": " .. url,
          })
          table.insert(qf, {
            bufnr = buf,
            filename = name ~= "" and name or nil,
            lnum = r.row + 1,
            col = r.col + 1,
            text = msg .. ": " .. url,
            type = kind == "broken" and "W" or "I",
          })
        end
      end
    end
    table.sort(qf, function(a, b)
      return a.lnum < b.lnum or (a.lnum == b.lnum and a.col < b.col)
    end)
    vim.diagnostic.set(M.ns, buf, diags)
    vim.fn.setqflist({}, " ", { title = "markwright: external links", items = qf })
    local summary = { total = #urls, broken = broken, restricted = restricted }
    if broken + restricted == 0 then
      util.notify(("all %d link%s OK"):format(#urls, #urls == 1 and "" or "s"))
    else
      local parts = {}
      if broken > 0 then
        table.insert(parts, ("%d broken"):format(broken))
      end
      if restricted > 0 then
        table.insert(parts, ("%d restricted"):format(restricted))
      end
      util.notify(
        ("%d link%s checked: %s (quickfix list)"):format(#urls, #urls == 1 and "" or "s", table.concat(parts, ", "))
      )
      if opts().open_quickfix and buf == api.nvim_get_current_buf() then
        local win = api.nvim_get_current_win()
        vim.cmd("botright copen")
        pcall(api.nvim_set_current_win, win)
      end
    end
    if on_done then
      on_done(summary)
    end
  end

  local function pump()
    while active < limit and next_i <= #urls do
      local url = urls[next_i]
      next_i = next_i + 1
      active = active + 1
      M.check_url(url, function(res)
        results[url] = res
        active = active - 1
        finished = finished + 1
        if finished == #urls then
          report()
        else
          pump()
        end
      end)
    end
  end
  pump()
end

M._real_request = M.request

return M
