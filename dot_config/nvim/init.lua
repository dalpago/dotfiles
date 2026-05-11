-- leader must be set before lazy loads so all keymaps register correctly
vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("config.options")
require("config.keymaps")
require("config.lazy")
require("config.notes")
require("config.filetypes")
