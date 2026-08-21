return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    branch = "main",
    dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.icons" },
    ---@module 'render-markdown'
    ---@type render.md.UserConfig
    opts = {
      file_types = { "markdown" },
      anti_conceal = { enabled = true, above = 0, below = 0 },
      indent = {
        enabled = true,
        per_level = 2,
        skip_level = 1,
        skip_heading = false,
      },
      heading = {
        sign = false,
        icons = { "", "", "", "", "", "" },
        width = "full",
        border = true,
        border_virtual = false,
        above = "▄",
        below = "▀",
        backgrounds = {
          "RenderMarkdownH1Bg",
          "RenderMarkdownH2Bg",
          "RenderMarkdownH3Bg",
          "RenderMarkdownH4Bg",
          "RenderMarkdownH5Bg",
          "RenderMarkdownH6Bg",
        },
        foregrounds = {
          "RenderMarkdownH1",
          "RenderMarkdownH2",
          "RenderMarkdownH3",
          "RenderMarkdownH4",
          "RenderMarkdownH5",
          "RenderMarkdownH6",
        },
        left_pad = 0,
        right_pad = 0,
      },
      bullet = { icons = { "•", "◦", "▪", "▫" } },
      checkbox = {
        unchecked = { icon = "☐ ", highlight = "RenderMarkdownUnchecked" },
        checked = { icon = "☑ ", highlight = "RenderMarkdownChecked" },
        custom = {
          todo = { raw = "[-]", rendered = "◐ ", highlight = "RenderMarkdownTodo" },
        },
      },
      code = {
        sign = false,
        style = "full",
        position = "right",
        width = "full",
        border = "thick",
        left_pad = 1,
        right_pad = 1,
      },
      pipe_table = { style = "full", cell = "padded" },
      callout = {
        note      = { raw = "[!NOTE]",      rendered = "󰋽 Note",      highlight = "RenderMarkdownInfo"    },
        tip       = { raw = "[!TIP]",       rendered = "󰌶 Tip",       highlight = "RenderMarkdownSuccess" },
        important = { raw = "[!IMPORTANT]", rendered = "󰅾 Important", highlight = "RenderMarkdownHint"    },
        warning   = { raw = "[!WARNING]",   rendered = "󰀪 Warning",   highlight = "RenderMarkdownWarn"    },
        caution   = { raw = "[!CAUTION]",   rendered = "󰳦 Caution",   highlight = "RenderMarkdownError"   },
      },
    },
    config = function(_, opts)
      require("render-markdown").setup(opts)
      local apply_code_highlights = function()
        vim.api.nvim_set_hl(0, "RenderMarkdownCode",         { bg = "#313244" })
        vim.api.nvim_set_hl(0, "RenderMarkdownCodeFallback", { bg = "#313244" })
        vim.api.nvim_set_hl(0, "RenderMarkdownCodeBorder",   { fg = "#89B4FA", bg = "#1E1E2E" })
      end
      apply_code_highlights()
      vim.api.nvim_create_autocmd("ColorScheme", { callback = apply_code_highlights })
    end,
  },

  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    build = "cd app && yarn install",
    ft = { "markdown" },
    keys = {
      { "<leader>mp", "<cmd>MarkdownPreviewToggle<cr>", desc = "Markdown preview toggle" },
    },
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
      vim.g.mkdp_theme = "dark"
      vim.g.mkdp_auto_close = 0
    end,
  },

  {
    "HakonHarnes/img-clip.nvim",
    event = "VeryLazy",
    keys = {
      { "<leader>pi", "<cmd>PasteImage<cr>", desc = "Paste clipboard image" },
    },
    opts = {
      default = {
        dir_path = "figures",
        relative_to_current_file = true,
        file_name = "%Y-%m-%d_%H-%M-%S",
        extension = "png",
        url_encode_path = true,
        prompt_for_file_name = true,
        use_absolute_path = false,
      },
      filetypes = {
        markdown = {
          template = "![$CURSOR]($FILE_PATH)",
          download_images = false,
        },
        tex = {
          template = "\\includegraphics{$FILE_PATH}",
        },
      },
    },
  },
}
