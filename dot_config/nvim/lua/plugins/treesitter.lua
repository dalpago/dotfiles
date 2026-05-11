return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "master",
    build = ":TSUpdate",
    opts = {
      ensure_installed = {
        "latex",
        "markdown",
        "markdown_inline",
        "lua",
        "python",
        "bash",
        "json",
        "yaml",
        "vim",
        "vimdoc",
      },
      highlight = { enable = true },
      indent = { enable = true },
    },
    config = function(_, opts)
      require("nvim-treesitter.install").ts_generate_args = {
        "generate",
        "--abi",
        tostring(vim.treesitter.language_version),
      }
      require("nvim-treesitter.configs").setup(opts)

      -- nvim-treesitter master ships directives in query_predicates.lua that use the
      -- pre-0.11 single-node match API. Neovim 0.11+ returns a list of nodes per
      -- capture, so match[id]:method() crashes. Re-register the affected directives
      -- with handlers that accept either shape.
      local query = require("vim.treesitter.query")
      local force = { force = true, all = false }
      local function unwrap(match, id)
        local m = match[id]
        if type(m) == "table" then return m[#m] end
        return m
      end

      local html_types = {
        importmap = "json",
        module = "javascript",
        ["application/ecmascript"] = "javascript",
        ["text/ecmascript"] = "javascript",
      }
      local md_aliases = {
        ex = "elixir", pl = "perl", sh = "bash", uxn = "uxntal", ts = "typescript",
      }

      query.add_directive("set-lang-from-info-string!", function(match, _, bufnr, pred, metadata)
        local node = unwrap(match, pred[2])
        if not node then return end
        local alias = vim.treesitter.get_node_text(node, bufnr):lower()
        metadata["injection.language"] = vim.filetype.match({ filename = "a." .. alias })
          or md_aliases[alias]
          or alias
      end, force)

      query.add_directive("set-lang-from-mimetype!", function(match, _, bufnr, pred, metadata)
        local node = unwrap(match, pred[2])
        if not node then return end
        local mt = vim.treesitter.get_node_text(node, bufnr)
        if html_types[mt] then
          metadata["injection.language"] = html_types[mt]
        else
          local parts = vim.split(mt, "/", {})
          metadata["injection.language"] = parts[#parts]
        end
      end, force)

      query.add_directive("downcase!", function(match, _, bufnr, pred, metadata)
        local id = pred[2]
        local node = unwrap(match, id)
        if not node then return end
        local text = vim.treesitter.get_node_text(node, bufnr, { metadata = metadata[id] }) or ""
        if not metadata[id] then metadata[id] = {} end
        metadata[id].text = string.lower(text)
      end, force)
    end,
  },
}
