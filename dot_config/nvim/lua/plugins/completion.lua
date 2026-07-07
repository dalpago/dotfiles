return {
  {
    "hrsh7th/nvim-cmp",
    branch = "main",
    dependencies = {
      { "hrsh7th/cmp-nvim-lsp", branch = "main" },
      { "hrsh7th/cmp-buffer", branch = "main" },
      { "hrsh7th/cmp-path", branch = "main" },
      { "saadparwaiz1/cmp_luasnip", branch = "master" },
      { "micangl/cmp-vimtex", branch = "master" },
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "vimtex" },
          { name = "buffer" },
          { name = "path" },
        }),
      })
    end,
  },
}
