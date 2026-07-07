return {
  {
    "echasnovski/mini.nvim",
    branch = "main",
    config = function()
      require("mini.surround").setup()
      require("mini.pairs").setup()
      require("mini.comment").setup()
      require("mini.files").setup()
    end,
  },
}
