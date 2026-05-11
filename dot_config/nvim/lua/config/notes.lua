local notes_dir = vim.fn.expand("~/Resources/Notes")

local function builtin()
  local ok, b = pcall(require, "telescope.builtin")
  if not ok then
    vim.notify("telescope.builtin not available", vim.log.levels.WARN)
    return nil
  end
  return b
end

vim.keymap.set("n", "<leader>nf", function()
  local b = builtin()
  if b then b.find_files({ cwd = notes_dir, hidden = true }) end
end, { desc = "Notes: find files" })

vim.keymap.set("n", "<leader>ng", function()
  local b = builtin()
  if b then b.live_grep({ cwd = notes_dir }) end
end, { desc = "Notes: live grep" })

vim.keymap.set("n", "<leader>nr", function()
  local b = builtin()
  if b then b.oldfiles({ cwd = notes_dir, cwd_only = true }) end
end, { desc = "Notes: recent files" })

vim.keymap.set("n", "<leader>nn", function()
  vim.ui.input({ prompt = "New note (under inbox/): " }, function(name)
    if not name or name == "" then return end
    local inbox = notes_dir .. "/inbox"
    vim.fn.mkdir(inbox, "p")
    vim.cmd.edit(inbox .. "/" .. name)
  end)
end, { desc = "Notes: new note in inbox" })
