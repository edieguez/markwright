; extends

; The markdown grammar has no footnotes: `[^1]: [docs](https://x.io)` (a text
; without spaces) is read as a link reference definition with the label `^1`,
; so the footnote's text is never parsed as inline Markdown. Parse it, so
; links in it are links (conceal, render-markdown.nvim, markview.nvim, gx).
((link_reference_definition
  (link_label) @_label
  (link_destination) @injection.content)
  (#lua-match? @_label "^%[%^")
  (#set! injection.language "markdown_inline"))
