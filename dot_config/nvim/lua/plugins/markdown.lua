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

      -- Colored text in the browser preview via semantic tags: write
      -- <red>text</red> (any Catppuccin accent name) in markdown. The CSS is
      -- generated from the live Catppuccin palette, so note colors track the
      -- editor / tmux / terminal theme. Browser preview only — GitHub strips
      -- the tags (text survives, uncolored). Shortcuts: <leader>c<key> wraps a
      -- visual selection; the `col` snippet types a fresh tag. See
      -- Resources/Notes/docs/nvim_markdown_improvements.md.
      local accents = {
        "rosewater", "flamingo", "pink", "mauve", "red", "maroon", "peach",
        "yellow", "green", "teal", "sky", "sapphire", "blue", "lavender",
      }
      local css_path = vim.fn.stdpath("cache") .. "/notes-colors.css"
      vim.g.mkdp_markdown_css = css_path

      local function write_notes_css()
        local palette
        local ok, palettes = pcall(require, "catppuccin.palettes")
        if ok then
          local ok2, p = pcall(palettes.get_palette)
          palette = ok2 and p or nil
        end
        palette = palette or {
          rosewater = "#f5e0dc", flamingo = "#f2cdcd", pink = "#f5c2e7",
          mauve = "#cba6f7", red = "#f38ba8", maroon = "#eba0ac", peach = "#fab387",
          yellow = "#f9e2af", green = "#a6e3a1", teal = "#94e2d5", sky = "#89dceb",
          sapphire = "#74c7ec", blue = "#89b4fa", lavender = "#b4befe",
        }
        -- Unscoped element selector: mkdp's content container is not
        -- `.markdown-body` (minified classes), and a direct colour rule on the
        -- custom element beats the container's inherited colour regardless.
        local lines = {}
        for _, name in ipairs(accents) do
          local hex = palette[name]
          if hex then
            lines[#lines + 1] = string.format("%s { color: %s; }", name, hex)
          end
        end

        -- g:mkdp_markdown_css *replaces* mkdp's bundled markdown.css (fonts,
        -- sizes, code-block backgrounds, theme vars) rather than adding to it,
        -- and mkdp has no "extra css" hook. So start from a copy of the bundled
        -- stylesheet and append our colour rules — otherwise the preview loses
        -- all default styling. Read the installed file (lazy layout, with an
        -- rtp fallback); the file exists on disk even before mkdp is loaded.
        local base = ""
        local base_path = vim.fn.stdpath("data")
          .. "/lazy/markdown-preview.nvim/app/_static/markdown.css"
        if vim.fn.filereadable(base_path) ~= 1 then
          base_path = vim.api.nvim_get_runtime_file("app/_static/markdown.css", false)[1]
        end
        if base_path and vim.fn.filereadable(base_path) == 1 then
          local bf = io.open(base_path, "r")
          if bf then
            base = bf:read("*a")
            bf:close()
          end
        end

        local fd = io.open(css_path, "w")
        if fd then
          fd:write(base
            .. "\n\n/* notes colour tags (generated from Catppuccin) */\n"
            .. table.concat(lines, "\n")
            .. "\n")
          fd:close()
        end
      end

      write_notes_css()
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("notes_markdown_colors", { clear = true }),
        callback = write_notes_css,
      })
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
