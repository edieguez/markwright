-- Image paste specs (SPEC.md section 13.1). The clipboard backend is mocked;
-- the real macOS backend runs against fake osascript/pngpaste executables.
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")
local api = vim.api
local images = require("markwright.images")
local config = require("markwright.config")
local eq = H.eq
local A = H.answers

local dir = H.tmpdir({
  ["src/Photo One.JPG"] = { "jpg" },
  ["src/doc.pdf"] = { "pdf" },
  ["src/pic.png"] = { "png" },
})
local other = H.tmpdir()
local defaults = vim.deepcopy(config.options.images)
local real_backend, real_text = images.backend, images.clipboard_text

local mock
local function before_each()
  mock = { info = "", furl = nil, text = "" }
  config.options.images = vim.deepcopy(defaults)
  config.options.images.name = "shot"
  images.backend = function()
    return {
      info = function(cb)
        cb(mock.info)
      end,
      save_image = function(path, cb)
        vim.fn.writefile({ "PNGDATA" }, path)
        cb(true)
      end,
      file_path = function(cb)
        cb(mock.furl)
      end,
    }
  end
  images.clipboard_text = function()
    return mock.text
  end
  H.queue = {}
  vim.fn.delete(dir .. "/assets", "rf")
end

local SHOT = "«class PNGf», 1234, «class 8BPS», 5678, TIFF picture, 9999"
local FINDER = "«class furl», 60, «class icns», 1000, TIFF picture, 2000, «class utf8», 40"

local function doc(lines, cursor)
  return H.buf(lines or { "" }, cursor or { 1, 0 }, dir .. "/notes.md")
end
local function lines()
  return api.nvim_buf_get_lines(0, 0, -1, false)
end
local function exists(p)
  return vim.uv.fs_stat(p) ~= nil
end

local cases = {
  -- helpers
  { "relpath", fn = function()
    eq(images.relpath("/a/b", "/a/b/assets/x.png"), "assets/x.png")
    eq(images.relpath("/a/b/c", "/a/img/x.png"), "../../img/x.png")
    eq(images.relpath("/a/b/", "/a/b/x.png"), "x.png")
  end },
  { "sanitize / encode", fn = function()
    eq(images.sanitize("  My Shot.png "), "My-Shot")
    eq(images.sanitize('a/b:c*?"d'), "abcd")
    eq(images.encode_path("my assets/a (1).png"), "my%20assets/a%20%281%29.png")
  end },

  -- image data (screenshots)
  { "screenshot with a typed name", fn = function()
    mock.info = SHOT
    doc()
    A("My Shot")()
    H.feed(" mp")
    eq(lines(), { "![My Shot](assets/My-Shot.png)" })
    eq(exists(dir .. "/assets/My-Shot.png"), true)
  end },
  { "default name accepted → empty alt", fn = function()
    mock.info = SHOT
    doc()
    A("shot")()
    H.feed(" mp")
    eq(lines(), { "![](assets/shot.png)" })
  end },
  { "name collision gets a suffix", fn = function()
    mock.info = SHOT
    vim.fn.mkdir(dir .. "/assets", "p")
    vim.fn.writefile({ "old" }, dir .. "/assets/shot.png")
    doc()
    A("shot")()
    H.feed(" mp")
    eq(lines(), { "![](assets/shot-1.png)" })
    eq(vim.fn.readfile(dir .. "/assets/shot.png"), { "old" })
  end },
  { "inserted after the cursor like p", fn = function()
    mock.info = SHOT
    doc({ "see here" }, { 1, 3 })
    A("x")()
    H.feed(" mp")
    eq(lines(), { "see ![x](assets/x.png)here" })
  end },
  { "visual selection becomes the alt text", fn = function()
    mock.info = SHOT
    doc({ "a big diagram b" }, { 1, 2 })
    A("big-diagram")()
    H.feed("vee mp")
    eq(lines(), { "a ![big diagram](assets/big-diagram.png) b" })
  end },
  { "cancel keeps everything", fn = function()
    mock.info = SHOT
    doc({ "x" })
    A(nil)()
    H.feed(" mp")
    eq(lines(), { "x" })
    eq(exists(dir .. "/assets"), false)
  end },
  { "one undo step", fn = function()
    mock.info = SHOT
    doc({ "x" })
    A("y")()
    H.feed({ " mp", "u" })
    eq(lines(), { "x" })
  end },

  -- files and text
  { "file copied in Finder is copied into assets", fn = function()
    mock.info, mock.furl = FINDER, dir .. "/src/Photo One.JPG"
    doc()
    A("Photo-One")()
    H.feed(" mp")
    eq(lines(), { "![Photo One](assets/Photo-One.jpg)" })
    eq(vim.fn.readfile(dir .. "/assets/Photo-One.jpg"), { "jpg" })
  end },
  { "non-image file is refused", fn = function()
    mock.info, mock.furl = FINDER, dir .. "/src/doc.pdf"
    doc({ "x" })
    H.feed(" mp")
    eq(lines(), { "x" })
  end },
  { "copied image path", fn = function()
    mock.info, mock.text = "«class utf8», 20, string, 20", dir .. "/src/pic.png"
    doc()
    A("pic")()
    H.feed(" mp")
    eq(lines(), { "![pic](assets/pic.png)" })
  end },
  { "copied image URL is linked, not downloaded", fn = function()
    mock.info, mock.text = "«class utf8», 30", "https://x.io/a.png?w=2"
    doc()
    H.feed(" mp")
    eq(lines(), { "![](https://x.io/a.png?w=2)" })
  end },
  { "no image on the clipboard", fn = function()
    mock.info, mock.text = "«class utf8», 5", "hello"
    doc({ "x" })
    H.feed(" mp")
    eq(lines(), { "x" })
  end },

  -- configuration
  { "absolute dir outside the document", fn = function()
    mock.info = SHOT
    config.options.images.dir = other
    doc()
    A("x")()
    H.feed(" mp")
    eq(lines(), { ("![x](%s/x.png)"):format(images.relpath(dir, other)) })
    eq(exists(other .. "/x.png"), true)
  end },
  { "dir as a function", fn = function()
    mock.info = SHOT
    config.options.images.dir = function()
      return "img/2026"
    end
    doc()
    A("x")()
    H.feed(" mp")
    eq(lines(), { "![x](img/2026/x.png)" })
  end },
  { "spaces in dir are encoded", fn = function()
    mock.info = SHOT
    config.options.images.dir = "my assets"
    doc()
    A("x")()
    H.feed(" mp")
    eq(lines(), { "![x](my%20assets/x.png)" })
    vim.fn.delete(dir .. "/my assets", "rf")
  end },
  { "alt = prompt", fn = function()
    mock.info = SHOT
    config.options.images.alt = "prompt"
    doc()
    A("x", "An [X]")()
    H.feed(" mp")
    eq(lines(), { [=[![An \[X\]](assets/x.png)]=] })
  end },
  { "alt = empty", fn = function()
    mock.info = SHOT
    config.options.images.alt = "empty"
    doc()
    A("named")()
    H.feed(" mp")
    eq(lines(), { "![](assets/named.png)" })
  end },
  { "prompt_name = false uses the default name", fn = function()
    mock.info = SHOT
    config.options.images.prompt_name = false
    doc()
    H.feed(" mp")
    eq(lines(), { "![](assets/shot.png)" })
  end },
  { "unsaved buffer saves relative to cwd", fn = function()
    mock.info = SHOT
    local old = vim.fn.getcwd()
    vim.fn.chdir(other)
    H.buf({ "" })
    A("u")()
    H.feed(" mp")
    vim.fn.chdir(old)
    eq(lines(), { "![u](assets/u.png)" })
    eq(exists(other .. "/assets/u.png"), true)
  end },
  { "skipped inside code", fn = function()
    mock.info = SHOT
    doc({ "```", "x", "```" }, { 2, 0 })
    A("x")()
    H.feed(" mp")
    eq(lines(), { "```", "x", "```" })
  end },
  { "unsupported platform warns", fn = function()
    images.backend = function()
      return nil
    end
    doc({ "x" })
    H.feed(" mp")
    eq(lines(), { "x" })
  end },
  { "smart p pastes the image when the clipboard has no text", fn = function()
    mock.info = SHOT
    config.options.images.smart_paste = true
    local getreg = vim.fn.getreg
    vim.fn.getreg = function(r, ...)
      if r == "+" then
        return ""
      end
      return getreg(r, ...)
    end
    local ok, err = pcall(function()
      doc()
      A("s")()
      H.feed('"+p')
    end)
    vim.fn.getreg = getreg
    assert(ok, err)
    eq(lines(), { "![s](assets/s.png)" })
  end },

  -- the real macOS backend against fake executables
  { "macOS backend: osascript path", fn = function()
    local bin = H.tmpdir()
    vim.fn.writefile({
      "#!/bin/sh",
      'if [ "$2" = "clipboard info" ]; then echo "$FAKE_INFO"; exit 0; fi',
      'last=""; for a in "$@"; do last="$a"; done',
      'case "$*" in',
      '  *PNGf*) if [ -n "$FAKE_NOIMAGE" ]; then echo noimage; else printf PNG > "$last"; echo ok; fi ;;',
      '  *furl*) echo "$FAKE_FURL" ;;',
      "esac",
    }, bin .. "/osascript")
    vim.fn.setfperm(bin .. "/osascript", "rwxr-xr-x")
    local path_env = vim.env.PATH
    vim.env.PATH = bin .. ":" .. path_env
    vim.env.FAKE_INFO, vim.env.FAKE_FURL = SHOT, "/Users/me/My Pic.png"
    local got = {}
    local out = other .. "/with space.png"
    images.macos.info(function(i) got.info = i end)
    images.macos.file_path(function(p) got.furl = p end)
    images.macos.save_image(out, function(ok, e) got.save = { ok, e } end)
    vim.wait(3000, function() return got.info and got.furl and got.save end, 10)
    vim.env.FAKE_NOIMAGE = "1"
    images.macos.save_image(other .. "/none.png", function(ok, e) got.none = { ok, e } end)
    vim.wait(3000, function() return got.none end, 10)
    vim.env.PATH, vim.env.FAKE_NOIMAGE = path_env, nil
    eq(got.info, SHOT)
    eq(got.furl, "/Users/me/My Pic.png")
    eq(got.save, { true, nil })
    eq(vim.fn.readfile(out), { "PNG" })
    eq(got.none, { false, "the clipboard has no image" })
  end },
  { "macOS backend: prefers pngpaste", fn = function()
    local bin = H.tmpdir()
    vim.fn.writefile({ "#!/bin/sh", 'printf PNG2 > "$1"' }, bin .. "/pngpaste")
    vim.fn.setfperm(bin .. "/pngpaste", "rwxr-xr-x")
    local path_env = vim.env.PATH
    vim.env.PATH = bin .. ":" .. path_env
    local got
    local out = other .. "/pp.png"
    images.macos.save_image(out, function(ok) got = ok end)
    vim.wait(3000, function() return got ~= nil end, 10)
    vim.env.PATH = path_env
    eq(got, true)
    eq(vim.fn.readfile(out), { "PNG2" })
  end },
  { "osascript script shape", fn = function()
    local cmd = images.osascript_cmd({ "a", "b" }, { "/p q.png" })
    eq(cmd, { "osascript", "-e", "a", "-e", "b", "/p q.png" })
  end },
}

H.mock_input()
local failed, total = H.run("images", cases, { before_each = before_each })
H.restore_input()
images.backend, images.clipboard_text = real_backend, real_text
config.options.images = defaults
return failed, total
