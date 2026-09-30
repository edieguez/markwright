-- External URL checker specs (SPEC.md section 14.23). Requests are mocked,
-- except in the last case, which runs curl against a local web server.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local uc = require("markwright.urlcheck")
local config = require("markwright.config")
local eq = H.eq

local real_request = uc.request
local calls, answers, max_active
local function before_each()
  calls, answers, max_active = {}, {}, 0
  config.options.url_check.open_quickfix = false
  config.options.url_check.ignore = {}
  local active = 0
  uc.request = function(url, method, cb)
    table.insert(calls, method .. " " .. url)
    active = active + 1
    max_active = math.max(max_active, active)
    local a = answers[method .. " " .. url] or answers[url] or { code = 200, exit = 0 }
    vim.schedule(function()
      active = active - 1
      cb(a)
    end)
  end
end

local function run_sync(buf)
  local summary
  uc.run(buf or 0, function(s)
    summary = s
  end)
  vim.wait(3000, function()
    return summary ~= nil
  end, 5)
  return summary
end

local function urls(buf)
  return vim.tbl_map(function(r)
    return ("%d:%d %s"):format(r.row + 1, r.col, r.url)
  end, uc.collect(buf or 0))
end

local DOC = {
  "[a](https://a.io/x) ![i](http://b.io/i.png) <https://c.io>",
  "bare https://d.io/page. and www.e.io too",
  "[local](./file.md) [anchor](#top) [mail](mailto:x@y.z) [other](ftp://f.io)",
  "`https://code.io` in code",
  "```",
  "https://block.io",
  "```",
  "[r][ref]",
  "",
  "[ref]: https://g.io/ref",
}

local cases = {
  -- collecting
  {
    "collects every kind of external link, skips code and local links",
    fn = function()
      H.buf(DOC)
      eq(urls(), {
        "1:4 https://a.io/x",
        "1:25 http://b.io/i.png",
        "1:45 https://c.io",
        "2:5 https://d.io/page",
        "2:28 https://www.e.io",
        "10:7 https://g.io/ref",
      })
    end,
  },
  {
    "a URL inside a link isn't counted twice",
    fn = function()
      H.buf({ "[https://x.io](https://x.io)" })
      eq(urls(), { "1:15 https://x.io" })
    end,
  },
  {
    "ignore patterns",
    fn = function()
      config.options.url_check.ignore = { "^https://a%.io" }
      H.buf({ "https://a.io/1 https://b.io" })
      eq(urls(), { "1:15 https://b.io" })
    end,
  },

  -- classifying
  {
    "classify",
    fn = function()
      eq({ uc.classify({ code = 200, exit = 0 }) }, { "ok" })
      eq({ uc.classify({ code = 301, exit = 0 }) }, { "ok" })
      eq({ uc.classify({ code = 416, exit = 0 }) }, { "ok" })
      eq({ uc.classify({ code = 404, exit = 0 }) }, { "broken", "HTTP 404" })
      eq({ uc.classify({ code = 500, exit = 0 }) }, { "broken", "HTTP 500" })
      eq(select(1, uc.classify({ code = 403, exit = 0 })), "restricted")
      eq(select(1, uc.classify({ code = 429, exit = 0 })), "restricted")
      eq({ uc.classify({ code = 0, exit = 6 }) }, { "broken", "host not found" })
      eq({ uc.classify({ code = 0, exit = 28 }) }, { "broken", "timed out" })
      eq({ uc.classify({ code = 0, exit = 99 }) }, { "broken", "request failed (curl exit 99)" })
    end,
  },

  -- requests
  {
    "HEAD first, GET only when HEAD fails",
    fn = function()
      H.buf({ "https://ok.io https://nohead.io" })
      answers["HEAD https://nohead.io"] = { code = 405, exit = 0 }
      local s = run_sync()
      eq(calls, { "HEAD https://ok.io", "HEAD https://nohead.io", "GET https://nohead.io" })
      eq(s, { total = 2, broken = 0, restricted = 0 })
    end,
  },
  {
    "no GET retry for unknown hosts or timeouts",
    fn = function()
      H.buf({ "https://gone.io" })
      answers["https://gone.io"] = { code = 0, exit = 6 }
      run_sync()
      eq(calls, { "HEAD https://gone.io" })
    end,
  },
  {
    "each URL is checked once, however often it appears",
    fn = function()
      H.buf({ "https://x.io", "[a](https://x.io) <https://x.io>" })
      local s = run_sync()
      eq(#calls, 1)
      eq(s.total, 1)
    end,
  },
  {
    "concurrency limit",
    fn = function()
      config.options.url_check.concurrency = 3
      local lines = {}
      for i = 1, 20 do
        lines[i] = ("https://h%d.io"):format(i)
      end
      H.buf(lines)
      local s = run_sync()
      config.options.url_check.concurrency = 8
      eq(s.total, 20)
      eq(max_active <= 3, true)
      eq(max_active, 3)
    end,
  },

  -- reporting
  {
    "diagnostics and quickfix",
    fn = function()
      H.buf({ "ok https://ok.io", "[x](https://dead.io/404) and <https://priv.io>", "again https://dead.io/404" })
      answers["https://dead.io/404"] = { code = 404, exit = 0 }
      answers["https://priv.io"] = { code = 403, exit = 0 }
      local s = run_sync()
      eq(s, { total = 3, broken = 1, restricted = 1 })
      local d = vim.diagnostic.get(0, { namespace = uc.ns })
      table.sort(d, function(a, b)
        return a.lnum < b.lnum or (a.lnum == b.lnum and a.col < b.col)
      end)
      eq(#d, 3)
      eq({ d[1].lnum, d[1].col, d[1].end_col, d[1].severity }, { 1, 4, 23, vim.diagnostic.severity.WARN })
      eq(d[1].message, "HTTP 404: https://dead.io/404")
      eq(d[2].severity, vim.diagnostic.severity.INFO)
      eq(d[3].lnum, 2)
      local qf = vim.fn.getqflist({ title = 1, items = 1 })
      eq(qf.title, "markwright: external links")
      eq(#qf.items, 3)
      eq({ qf.items[1].lnum, qf.items[1].col, qf.items[1].type }, { 2, 5, "W" })
    end,
  },
  {
    "a new run replaces old results",
    fn = function()
      H.buf({ "https://x.io" })
      answers["https://x.io"] = { code = 500, exit = 0 }
      run_sync()
      eq(#vim.diagnostic.get(0, { namespace = uc.ns }), 1)
      answers["https://x.io"] = { code = 200, exit = 0 }
      run_sync()
      eq(#vim.diagnostic.get(0, { namespace = uc.ns }), 0)
    end,
  },
  {
    "no links",
    fn = function()
      H.buf({ "just text", "[local](a.md)" })
      eq(run_sync(), { total = 0, broken = 0, restricted = 0 })
      eq(#calls, 0)
    end,
  },
  {
    ":Markwright check urls and completion",
    fn = function()
      H.buf({ "https://dead.io" })
      answers["https://dead.io"] = { code = 404, exit = 0 }
      vim.cmd("Markwright check urls")
      vim.wait(3000, function()
        return #vim.diagnostic.get(0, { namespace = uc.ns }) == 1
      end, 5)
      eq(#vim.diagnostic.get(0, { namespace = uc.ns }), 1)
      eq(vim.fn.getcompletion("Markwright check ", "cmdline"), { "urls" })
    end,
  },
  {
    "file diagnostics (on save) and URL diagnostics are separate",
    fn = function()
      H.buf({ "[x](#nope) https://dead.io" })
      answers["https://dead.io"] = { code = 404, exit = 0 }
      run_sync()
      require("markwright.diagnostics").check(0)
      eq(#vim.diagnostic.get(0, { namespace = uc.ns }), 1)
      eq(#vim.diagnostic.get(0, { namespace = require("markwright.diagnostics").ns }), 1)
    end,
  },

  -- real curl against a local server
  {
    "real requests with curl",
    fn = function()
      if vim.fn.executable("curl") == 0 or vim.fn.executable("python3") == 0 then
        print("        (skipped: needs curl and python3)")
        return
      end
      uc.request = real_request
      local dir = H.tmpdir({ ["index.html"] = { "<title>ok</title>" } })
      local port = 18000 + math.random(0, 999)
      local job = vim.fn.jobstart(
        { "python3", "-m", "http.server", tostring(port), "--bind", "127.0.0.1" },
        { cwd = dir }
      )
      local base = ("http://127.0.0.1:%d"):format(port)
      vim.wait(3000, function()
        return vim.system({ "curl", "-s", "-o", "/dev/null", base .. "/" }):wait().code == 0
      end, 50)
      local ok, err = pcall(function()
        H.buf({ base .. "/ ok", base .. "/missing.html gone", "http://127.0.0.1:9/ refused" })
        local s = run_sync()
        vim.wait(15000, function()
          return s ~= nil
        end, 20)
        eq(s, { total = 3, broken = 2, restricted = 0 })
        local msgs = vim.tbl_map(function(d)
          return d.message
        end, vim.diagnostic.get(0, { namespace = uc.ns }))
        table.sort(msgs)
        eq(msgs, { "HTTP 404: " .. base .. "/missing.html", "connection refused: http://127.0.0.1:9/" })
      end)
      vim.fn.jobstop(job)
      assert(ok, err)
    end,
  },
}

local failed, total = H.run("url check", cases, { before_each = before_each })
uc.request = real_request
config.options.url_check.open_quickfix = true
return failed, total
