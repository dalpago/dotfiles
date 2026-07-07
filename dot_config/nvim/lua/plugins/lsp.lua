local languages = require("config.languages")

local mason_ensure_installed = {}
for _, lang in pairs(languages) do
  vim.list_extend(mason_ensure_installed, lang.mason_lsp or {})
end

local function on_attach(_, bufnr)
  vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = bufnr, desc = "vim.lsp.buf.definition()" })
end

-- uv puts a project's virtualenv at <root>/.venv; fall back to whatever
-- python3 is on PATH for files outside a uv-managed project.
local function python_path(root_dir)
  if not root_dir then
    return vim.fn.exepath("python3")
  end
  local venv_python = root_dir .. "/.venv/bin/python3"
  if vim.fn.executable(venv_python) == 1 then
    return venv_python
  end
  return vim.fn.exepath("python3")
end

return {
  {
    "mason-org/mason-lspconfig.nvim",
    dependencies = {
      { "mason-org/mason.nvim", opts = {} },
      "neovim/nvim-lspconfig",
      { "hrsh7th/cmp-nvim-lsp", branch = "main" },
    },
    opts = {
      ensure_installed = mason_ensure_installed,
      automatic_enable = true,
    },
    config = function(_, opts)
      vim.lsp.config("*", {
        capabilities = require("cmp_nvim_lsp").default_capabilities(),
      })

      vim.lsp.config("basedpyright", {
        on_attach = on_attach,
        -- Must be a real table here, not nil: before_init mutates it in
        -- place below. Neovim snapshots config.settings into the client at
        -- creation time, before before_init ever runs — reassigning
        -- config.settings inside before_init would not reach that snapshot.
        settings = {},
        before_init = function(_, config)
          config.settings.python = config.settings.python or {}
          config.settings.python.pythonPath = python_path(config.root_dir)
        end,
      })

      vim.lsp.config("ruff", {
        on_attach = function(client, bufnr)
          -- basedpyright stays the single hover/goto-definition authority;
          -- without this both clients answer K and popups duplicate.
          client.server_capabilities.hoverProvider = false
          on_attach(client, bufnr)
        end,
      })

      require("mason-lspconfig").setup(opts)

      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = "*.py",
        callback = function(args)
          vim.lsp.buf.format({
            bufnr = args.buf,
            filter = function(client)
              return client.name == "ruff"
            end,
          })
        end,
      })
    end,
  },
}
