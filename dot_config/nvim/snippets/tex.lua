local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node

return {
  -- inline math
  s("mk", {
    t("$"),
    i(1),
    t("$"),
  }),

  -- display math
  s("dm", {
    t({ "\\[", "\t" }),
    i(1),
    t({ "", "\\]" }),
  }),

  -- bold text
  s("bf", {
    t("\\textbf{"),
    i(1),
    t("}"),
  }),

  -- italic text
  s("it", {
    t("\\textit{"),
    i(1),
    t("}"),
  }),

  -- align* environment
  s("align", {
    t({ "\\begin{align*}", "\t" }),
    i(1),
    t({ "", "\\end{align*}" }),
  }),

  -- fraction
  s("frac", {
    t("\\frac{"),
    i(1),
    t("}{"),
    i(2),
    t("}"),
  }),

  -- sum
  s("sum", {
    t("\\sum_{"),
    i(1),
    t("}^{"),
    i(2),
    t("}"),
  }),

  -- limit
  s("lim", {
    t("\\lim_{"),
    i(1),
    t("}"),
  }),
}
