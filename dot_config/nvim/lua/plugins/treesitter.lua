-- Languages we want highlighted but neovim core doesn't bundle.
-- nvim 0.12+ ships parsers + queries for: c, lua, markdown, markdown_inline,
-- query, vim, vimdoc. Everything else needs explicit install via
-- nvim-treesitter (which fetches parser source AND links queries onto
-- runtimepath at ~/.local/share/nvim/site/queries/<lang>/).
local languages = require("config.languages")

local ensure_installed = {
  "latex",
  "bash",
  "json",
  "yaml",
}
for _, lang in pairs(languages) do
  vim.list_extend(ensure_installed, lang.treesitter or {})
end

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = function()
      require("nvim-treesitter").install(ensure_installed, { summary = true })
    end,
    init = function()
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(ev)
          pcall(vim.treesitter.start, ev.buf)
        end,
      })
    end,
    config = function()
      -- Idempotent backfill: if a required language's queries aren't on
      -- runtimepath (e.g. after `chezmoi apply` on a fresh machine, where
      -- lazy's build hook ran before parsers were generated), install them
      -- on the spot. Cost is zero when everything is already in place.
      local missing = {}
      for _, lang in ipairs(ensure_installed) do
        if #vim.api.nvim_get_runtime_file("queries/" .. lang .. "/highlights.scm", false) == 0 then
          table.insert(missing, lang)
        end
      end
      if #missing > 0 then
        require("nvim-treesitter").install(missing, { summary = true })
      end
    end,
  },
}
