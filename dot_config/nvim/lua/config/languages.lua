-- Single source of truth for per-language coding-tool integration, read by
-- treesitter.lua and lsp.lua. Notes/prose tooling (LaTeX, Markdown) is
-- intentionally NOT here — see docs/superpowers/specs/2026-07-07-nvim-python-dev-design.md.
return {
  python = {
    filetypes = { "python" },
    treesitter = { "python" },
    mason_lsp = { "basedpyright", "ruff" },
  },
}
