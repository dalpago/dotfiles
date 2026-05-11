local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node

return {
  -- fenced code block
  s("cb", {
    t("```"),
    i(1, "language"),
    t({ "", "" }),
    i(2),
    t({ "", "```" }),
  }),

  -- hyperlink
  s("lnk", {
    t("["),
    i(1, "text"),
    t("]("),
    i(2, "url"),
    t(")"),
  }),

  -- image
  s("img", {
    t("!["),
    i(1, "alt"),
    t("]("),
    i(2, "path"),
    t(")"),
  }),
}
