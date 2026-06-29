vim.g.vimtex_view_method = vim.fn.has("mac") == 1 and "skim" or "zathura"
vim.g.vimtex_compiler_method = "latexmk"
vim.g.vimtex_quickfix_mode = 0
vim.g.vimtex_view_automatic = 1

return {
  {
    "lervag/vimtex",
    branch = "master",
    lazy = false,
  },
}
