return {
  {
    "catppuccin/nvim",
    branch = "main",
    name = "catppuccin",
    priority = 1000,
    opts = {
      flavour = "mocha",
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
      vim.cmd.colorscheme("catppuccin")
    end,
  },
  {
    "nvim-lualine/lualine.nvim",
    branch = "master",
    dependencies = {
      { "nvim-tree/nvim-web-devicons", branch = "master" },
    },
    opts = {
      options = {
        theme = "catppuccin-mocha",
      },
    },
  },
}
