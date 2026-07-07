# Neovim Python Development Environment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the existing notes-focused Neovim config to lightweight-IDE parity for Python — project-tree browsing, goto-definition/references, format-on-save — without debugging support and without cluttering the setup with Python-only patches.

**Architecture:** A new `lua/config/languages.lua` table is the single source of truth for per-language facts (treesitter parser, mason LSP servers). `treesitter.lua` and a new `lsp.lua` both read from it instead of hardcoding Python, so a second language later is one table row, not a multi-file edit. LSP is `basedpyright` (types/goto-def, uv-aware interpreter resolution) + `ruff` (diagnostics/format-on-save, hover disabled to avoid duplicate popups). Running scripts stays zero-plugin (`uv run <file>` in a manual tmux pane), documented in the README, not automated in config.

**Tech Stack:** Neovim 0.12.3, lazy.nvim, `mason.nvim`/`mason-lspconfig.nvim`/`nvim-lspconfig`, `basedpyright`, `ruff` (0.13.3, via `ruff server`), `mini.nvim`'s `mini.files` module, `uv` (0.8.22).

## Global Constraints

- **Repo location:** all paths below are relative to `~/.local/share/chezmoi` (the public canonical repo). `dot_config/nvim/...` in this repo is the same file the running config reads — edit it directly; the `chezmoi-staging` symlink tree points straight back to it (confirmed: nothing under `dot_config/nvim` is private-overlay content).
- **Commit conventions (from user's CLAUDE.md):** Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`), imperative mood, atomic commits. **Never mention Claude/AI** in any commit message — no `Co-Authored-By` trailer, no footer.
- **Tools:** use `fd` not `find`, `rg` not `grep` for any ad-hoc inspection commands.
- **Sync workflow:** after editing a file under `dot_config/nvim`, run `chezmoi apply -- ~/.config/nvim` to sync it into the live config, then (for new/changed plugin specs) run `:Lazy sync` inside Neovim before verifying behavior.
- **Verification baseline:** after every task, `nvim --headless -c 'qa'` against the real config must exit 0 with no startup errors, and opening a `.md` or `.tex` file must show no regression (spellcheck/wrap still active, no unexpected LSP attaching).
- **Do not push.** Commits stay local unless explicitly requested.

---

## File Structure

- Create: `dot_config/nvim/lua/config/languages.lua` — single source of truth (per-language treesitter parser + mason LSP servers)
- Modify: `dot_config/nvim/lua/plugins/treesitter.lua` — merge parsers from `languages.lua` instead of hardcoding `python`
- Create: `dot_config/nvim/lua/plugins/lsp.lua` — `mason.nvim` + `mason-lspconfig.nvim` + `nvim-lspconfig`, `basedpyright` + `ruff` setup, format-on-save
- Modify: `dot_config/nvim/lua/plugins/completion.lua` — add `nvim_lsp` cmp source
- Modify: `dot_config/nvim/lua/plugins/mini.lua` — add `mini.files` module setup
- Modify: `dot_config/nvim/lua/config/keymaps.lua` — add `<leader>e` to open `mini.files`
- Modify: `README.md` — document the Python dev workflow (tree/goto-def/run)

---

## Task 1: Shared language table + treesitter integration

**Files:**
- Create: `dot_config/nvim/lua/config/languages.lua`
- Modify: `dot_config/nvim/lua/plugins/treesitter.lua:1-12`

**Interfaces:**
- Produces: `require("config.languages")` → `{ <name> = { filetypes = {...}, treesitter = {...}, mason_lsp = {...} } }`. Task 2 consumes the `mason_lsp` field; this task's own `treesitter.lua` change consumes `treesitter`.

- [ ] **Step 1: Create the language table**

Create `dot_config/nvim/lua/config/languages.lua`:

```lua
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
```

- [ ] **Step 2: Verify it loads cleanly in isolation**

Run:
```bash
nvim --headless --clean -c "set rtp+=~/.local/share/chezmoi/dot_config/nvim" \
  -c "lua local ok, t = pcall(require, 'config.languages'); print(ok, vim.inspect(t))" -c "qa"
```
Expected: prints `true` followed by the table, showing `python.mason_lsp = { "basedpyright", "ruff" }`.

- [ ] **Step 3: Update `treesitter.lua` to merge parsers from the table**

Replace the top of `dot_config/nvim/lua/plugins/treesitter.lua` (currently lines 1-12, the `ensure_installed` block) with:

```lua
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
```

Leave the rest of the file (the `return { { "nvim-treesitter/nvim-treesitter", ... } }` block with its `build`/`init`/`config` functions) unchanged — it already references the local `ensure_installed`, which now includes `"python"` via the merge instead of a hardcoded entry.

- [ ] **Step 4: Apply and confirm python is still (re-)installed as a parser**

```bash
chezmoi apply -- ~/.config/nvim
nvim --headless -c "Lazy! sync" -c "qa" 2>&1 | tail -5
nvim --headless -c "lua print(#vim.api.nvim_get_runtime_file('queries/python/highlights.scm', false) > 0)" -c "qa"
```
Expected: the last command prints `true` (python treesitter queries are on the runtime path — the actual end-to-end proof that highlighting still works after removing the hardcoded entry).

- [ ] **Step 5: Regression check — notes files still highlight/parse correctly**

```bash
nvim --headless -c "lua print(#vim.api.nvim_get_runtime_file('queries/latex/highlights.scm', false) > 0)" -c "qa"
```
Expected: `true` — `latex` (a notes-only parser, not in `languages.lua`) is unaffected by the refactor.

- [ ] **Step 6: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_config/nvim/lua/config/languages.lua dot_config/nvim/lua/plugins/treesitter.lua
git commit -m "feat(nvim): add languages table as single source of truth for treesitter"
```

---

## Task 2: LSP for Python — basedpyright with uv-aware interpreter resolution

**Files:**
- Create: `dot_config/nvim/lua/plugins/lsp.lua`
- Modify: `dot_config/nvim/lua/plugins/completion.lua:44-49`

**Interfaces:**
- Consumes: `require("config.languages")` from Task 1 (for `mason_lsp`).
- Produces (for Task 3, which edits the same file): a local `on_attach(client, bufnr)` function and a local `mason_ensure_installed` list, both defined at the top of `lsp.lua`.

- [ ] **Step 1: Create `lsp.lua` with mason + basedpyright**

Create `dot_config/nvim/lua/plugins/lsp.lua`:

```lua
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
  local venv_python = root_dir .. "/.venv/bin/python3"
  if vim.fn.executable(venv_python) == 1 then
    return venv_python
  end
  return vim.fn.exepath("python3")
end

return {
  {
    "mason-org/mason.nvim",
    opts = {},
  },
  {
    "mason-org/mason-lspconfig.nvim",
    dependencies = { "mason-org/mason.nvim" },
    opts = {
      ensure_installed = mason_ensure_installed,
      -- We call lspconfig.<server>.setup() ourselves below for full control
      -- over on_attach/settings; automatic_enable would double-attach.
      automatic_enable = false,
    },
  },
  {
    "neovim/nvim-lspconfig",
    dependencies = { "mason-org/mason-lspconfig.nvim" },
    config = function()
      local lspconfig = require("lspconfig")

      lspconfig.basedpyright.setup({
        on_attach = on_attach,
        on_new_config = function(new_config, new_root_dir)
          new_config.settings = new_config.settings or {}
          new_config.settings.python = new_config.settings.python or {}
          new_config.settings.python.pythonPath = python_path(new_root_dir)
        end,
      })
    end,
  },
}
```

- [ ] **Step 2: Add `nvim_lsp` to the completion sources**

In `dot_config/nvim/lua/plugins/completion.lua`, replace the `sources` block (currently lines 44-49):

```lua
        sources = cmp.config.sources({
          { name = "luasnip" },
          { name = "vimtex" },
          { name = "buffer" },
          { name = "path" },
        }),
```

with:

```lua
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "vimtex" },
          { name = "buffer" },
          { name = "path" },
        }),
```

- [ ] **Step 3: Apply and let mason install basedpyright**

```bash
chezmoi apply -- ~/.config/nvim
nvim --headless -c "Lazy! sync" -c "qa" 2>&1 | tail -5
nvim --headless -c "MasonInstall basedpyright" -c "qa" 2>&1 | tail -10
```
Expected: no errors; `basedpyright` reports installed (run `nvim --headless -c "lua print(require('mason-registry').is_installed('basedpyright'))" -c "qa"` → `true`).

- [ ] **Step 4: Set up a throwaway uv project to verify interpreter resolution**

```bash
mkdir -p /private/tmp/claude-502/-Users-work/6d4302a8-75d3-4dd6-be3c-156851db0e28/scratchpad/pytest-lsp
cd /private/tmp/claude-502/-Users-work/6d4302a8-75d3-4dd6-be3c-156851db0e28/scratchpad/pytest-lsp
uv init --bare
uv add requests
printf 'import requests\n\nrequests.get\n' > example.py
```

- [ ] **Step 5: Manually verify goto-definition resolves into the uv venv (interactive — requires a real terminal)**

```bash
nvim example.py
```
In Neovim: place the cursor on `get` in `requests.get` and press `gd`. Expected: it jumps into a file under `.venv/lib/python*/site-packages/requests/...` — this proves `basedpyright` resolved the *project's* interpreter, not a system one. Close with `:qa`.

- [ ] **Step 6: Regression check — Markdown/LaTeX unaffected**

```bash
nvim --headless -c "e /tmp/scratch.md" -c "lua print(vim.bo.spell)" -c "qa"
```
Expected: `true` (notes filetype behavior from `filetypes.lua` still applies; no LSP attaches to a `.md` buffer).

- [ ] **Step 7: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_config/nvim/lua/plugins/lsp.lua dot_config/nvim/lua/plugins/completion.lua
git commit -m "feat(nvim): add LSP (basedpyright) with uv-aware interpreter resolution"
```

---

## Task 3: LSP for Python — ruff diagnostics and format-on-save

**Files:**
- Modify: `dot_config/nvim/lua/plugins/lsp.lua` (same file created in Task 2)

**Interfaces:**
- Consumes: the local `on_attach` function already defined at the top of `lsp.lua` (Task 2).

- [ ] **Step 1: Add ruff setup and format-on-save to `lsp.lua`**

In `dot_config/nvim/lua/plugins/lsp.lua`, inside the `"neovim/nvim-lspconfig"` plugin's `config` function, after the existing `lspconfig.basedpyright.setup({...})` call, add:

```lua
      lspconfig.ruff.setup({
        on_attach = function(client, bufnr)
          -- basedpyright stays the single hover/goto-definition authority;
          -- without this both clients answer K and popups duplicate.
          client.server_capabilities.hoverProvider = false
          on_attach(client, bufnr)
        end,
      })

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
```

- [ ] **Step 2: Apply and let mason install ruff**

```bash
chezmoi apply -- ~/.config/nvim
nvim --headless -c "MasonInstall ruff" -c "qa" 2>&1 | tail -10
```
Expected: no errors.

- [ ] **Step 3: Verify diagnostics — headless, scriptable**

Using the throwaway project from Task 2 Step 4:

```bash
cd /private/tmp/claude-502/-Users-work/6d4302a8-75d3-4dd6-be3c-156851db0e28/scratchpad/pytest-lsp
printf 'import os\nimport requests\n\nrequests.get\n' > unused_import.py
nvim --headless unused_import.py \
  -c "lua vim.wait(3000)" \
  -c "lua local d = vim.diagnostic.get(0); print('diagnostics:', #d)" \
  -c "qa"
```
Expected: `diagnostics: 1` or more (ruff flags the unused `os` import — `F401`).

- [ ] **Step 4: Verify format-on-save — headless, scriptable**

```bash
cd /private/tmp/claude-502/-Users-work/6d4302a8-75d3-4dd6-be3c-156851db0e28/scratchpad/pytest-lsp
printf 'x=1\ny  =2\n' > messy.py
nvim --headless messy.py \
  -c "lua vim.wait(2000)" \
  -c "wq" 2>&1
cat messy.py
```
Expected: `messy.py` now reads `x = 1\ny = 2\n` (ruff's formatter normalized the spacing on save).

- [ ] **Step 5: Regression check — no duplicate hover popups**

```bash
nvim --headless /private/tmp/claude-502/-Users-work/6d4302a8-75d3-4dd6-be3c-156851db0e28/scratchpad/pytest-lsp/example.py \
  -c "lua vim.wait(2000); for _, c in ipairs(vim.lsp.get_clients()) do print(c.name, c.server_capabilities.hoverProvider) end" \
  -c "qa"
```
Expected: `basedpyright` line shows a truthy hover capability; `ruff` line shows `false`.

- [ ] **Step 6: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_config/nvim/lua/plugins/lsp.lua
git commit -m "feat(nvim): add ruff LSP diagnostics and format-on-save"
```

---

## Task 4: Project-tree browsing via mini.files

**Files:**
- Modify: `dot_config/nvim/lua/plugins/mini.lua:5-9`
- Modify: `dot_config/nvim/lua/config/keymaps.lua`

- [ ] **Step 1: Enable the `mini.files` module**

In `dot_config/nvim/lua/plugins/mini.lua`, replace the `config` function (currently lines 5-9):

```lua
    config = function()
      require("mini.surround").setup()
      require("mini.pairs").setup()
      require("mini.comment").setup()
    end,
```

with:

```lua
    config = function()
      require("mini.surround").setup()
      require("mini.pairs").setup()
      require("mini.comment").setup()
      require("mini.files").setup()
    end,
```

- [ ] **Step 2: Add the open keymap**

In `dot_config/nvim/lua/config/keymaps.lua`, append at the end of the file:

```lua

-- mini.files
map("n", "<leader>e", function()
  MiniFiles.open(vim.api.nvim_buf_get_name(0))
end, { desc = "File explorer (mini.files)" })
```

- [ ] **Step 3: Apply and verify it opens (interactive — requires a real terminal)**

```bash
chezmoi apply -- ~/.config/nvim
nvim /private/tmp/claude-502/-Users-work/6d4302a8-75d3-4dd6-be3c-156851db0e28/scratchpad/pytest-lsp/example.py
```
In Neovim, press `<space>e`. Expected: a tree browser opens showing `pytest-lsp/`'s contents with `example.py` highlighted. Press `q` to close, `:qa` to quit.

- [ ] **Step 4: Regression check — headless startup still clean**

```bash
nvim --headless -c "qa"
echo "exit code: $?"
```
Expected: `exit code: 0`.

- [ ] **Step 5: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_config/nvim/lua/plugins/mini.lua dot_config/nvim/lua/config/keymaps.lua
git commit -m "feat(nvim): add mini.files project tree with <leader>e"
```

---

## Task 5: Document the workflow in README

**Files:**
- Modify: `README.md:369` (Editor/Pager bullet)
- Modify: `README.md` (append a short workflow note after the "What's Managed" list, currently ending at line 380)

- [ ] **Step 1: Extend the Editor/Pager bullet**

In `README.md`, replace line 369:

```markdown
- **Editor/Pager**: Neovim (incl. markdown rendering/preview stack), bat (Catppuccin Mocha), eza theme
```

with:

```markdown
- **Editor/Pager**: Neovim (incl. markdown rendering/preview stack, and Python dev tooling — LSP via basedpyright+ruff with uv-aware interpreter resolution, `mini.files` project tree, format-on-save; see below), bat (Catppuccin Mocha), eza theme
```

- [ ] **Step 2: Append the workflow note**

At the end of `README.md` (after the `- **Packages**: ...` line), add:

```markdown

### Neovim Python development workflow

- **Project tree:** `<leader>e` opens `mini.files` at the current file.
- **Navigate code:** `gd` jumps to a definition; `grr` (references), `grn`
  (rename), `gri` (implementation), `gO` (document symbols), and `K` (hover)
  are Neovim 0.12's built-in LSP defaults — no extra keymaps needed for those.
- **Format:** Python files auto-format on save via `ruff`.
- **Run a script:** no plugin for this — open a tmux pane (or `:terminal`) and
  run `uv run <file>`. `uv run` resolves the project's `.venv`/dependencies
  automatically, and also runs standalone PEP 723 scripts with zero project
  setup.
```

- [ ] **Step 3: Commit**

```bash
cd ~/.local/share/chezmoi
git add README.md
git commit -m "docs: document nvim Python dev workflow (LSP, tree, uv run)"
```

---

## Final verification (after all tasks)

- [ ] **Full dry-run is clean**

Run: `chezmoi diff`
Expected: no unexpected pending changes.

- [ ] **Clean headless startup**

```bash
nvim --headless -c "qa"; echo "exit: $?"
```
Expected: `exit: 0`.

- [ ] **End-to-end Python session (interactive)**

Open the throwaway `pytest-lsp/example.py`: confirm `<leader>e` opens the tree, `gd` on `requests.get` jumps into `.venv/lib/python*/site-packages/requests`, saving a messily-formatted line reformats it, and no duplicate hover popup appears on `K`.

- [ ] **Regression: notes workflow untouched**

Open a real `.md` and `.tex` file from `~/Resources/Notes`; confirm spellcheck/wrap/VimTeX behavior is exactly as before, and `:LspInfo` shows no client attached to either buffer.

- [ ] **Clean up the throwaway test project**

```bash
rm -rf /private/tmp/claude-502/-Users-work/6d4302a8-75d3-4dd6-be3c-156851db0e28/scratchpad/pytest-lsp
```

---

## Self-review notes (coverage map)

| Spec item | Task |
|---|---|
| Component 1 — `languages.lua` single source of truth | Task 1 |
| Component 2 — `treesitter.lua` merge, drop hardcoded `python` | Task 1 |
| Component 3 — `lsp.lua`: mason/mason-lspconfig/nvim-lspconfig, basedpyright + uv interpreter resolution, `gd` keymap | Task 2 |
| Component 3 — ruff attach, hover-disable | Task 3 |
| Component 4 — format-on-save | Task 3 |
| Component 5 — `nvim_lsp` cmp source | Task 2 |
| Component 6 — `mini.files` + keymap | Task 4 |
| Component 7 — documented `uv run` workflow | Task 5 |
| Data flow (adding a language later) | Proven structurally by Task 1's design; no separate task needed |
| Error handling (no `.venv`, mason offline, root_dir) | Covered by Task 2's `python_path` fallback and Task 2/3's decoupled plugin specs |
| Testing & verification checklist from the spec | Folded into each task's own verification steps + Final verification |
