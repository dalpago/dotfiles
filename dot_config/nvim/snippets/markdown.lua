local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local c = ls.choice_node
local f = ls.function_node

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

  -- colored text: <color>text</color> (rendered in the <leader>mp preview).
  -- Cycle the color at node 1 with LuaSnip's choice-node keys; the closing
  -- tag mirrors the chosen color automatically.
  s("col", {
    t("<"),
    c(1, {
      t("red"), t("green"), t("blue"), t("yellow"),
      t("peach"), t("mauve"), t("teal"), t("pink"),
      t("lavender"), t("sky"), t("sapphire"), t("maroon"),
      t("flamingo"), t("rosewater"),
    }),
    t(">"),
    i(2, "text"),
    t("</"),
    f(function(args)
      return args[1][1]
    end, { 1 }),
    t(">"),
  }),
}
