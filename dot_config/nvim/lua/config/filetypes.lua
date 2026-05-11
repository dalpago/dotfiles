local group = vim.api.nvim_create_augroup("notes_filetypes", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = { "tex", "markdown" },
  callback = function(ev)
    vim.opt_local.spell = true
    vim.opt_local.spelllang = "en"
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.textwidth = 0
    if ev.match == "markdown" then
      vim.opt_local.conceallevel = 2
    end
  end,
})
