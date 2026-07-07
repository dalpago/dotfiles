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

      require("mason-lspconfig").setup(opts)
    end,
  },
}
```

> **Note (corrected during implementation):** the plan originally specified
> `require("lspconfig").basedpyright.setup({ on_new_config = ... })`. That API
> is deprecated (removed in nvim-lspconfig v3.0.0) and prints a startup
> warning; the code above is the verified modern replacement — `vim.lsp.config()`
> plus mason-lspconfig's `automatic_enable` (default `true`), with `before_init`
> (a core `vim.lsp.ClientConfig` field, unrelated to the deprecated framework)
> standing in for `on_new_config`. This also collapses three top-level plugin
> entries into one, matching mason-lspconfig's own recommended lazy.nvim layout.
> Additionally, `config.settings` must be pre-declared as `settings = {}` (not
> `nil`) and mutated in place via `before_init`, rather than reassigned, so
> Neovim's snapshot of the config (which happens before `before_init` runs)
> receives the updated values.

- [ ] **Step 2: Add `nvim_lsp` completion support**

In `dot_config/nvim/lua/plugins/completion.lua`:

1. Add `{ "hrsh7th/cmp-nvim-lsp", branch = "main" }` to the existing `dependencies` list (alongside `cmp-buffer`/`cmp-path`/`cmp_luasnip`/`cmp-vimtex`) — this is the plugin that actually backs the `nvim_lsp` source name; omitting it means the source is registered nowhere and silently never completes.
2. Replace the `sources` block (currently lines 44-49):

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

- [ ] **Step 5: Verify goto-definition resolves into the uv venv**

Open `example.py` and jump on `requests.get` (`gd`, or in a scripted/headless
check: wait for the `basedpyright` client to attach via
`vim.lsp.get_clients()`, position the cursor on `get` — line 3, column 10 —
and call `vim.lsp.buf.definition()` or
`vim.lsp.buf_request_sync(0, "textDocument/definition", vim.lsp.util.make_position_params(0, "utf-16"), 5000)`).
Expected: it resolves into a file under `.venv/lib/python*/site-packages/requests/...`
— this proves `basedpyright` resolved the *project's* interpreter, not a
system one.

- [ ] **Step 6: Regression check — Markdown/LaTeX unaffected**

```bash
nvim --headless -c "e /tmp/scratch.md" -c "lua print(vim.wo.spell)" -c "qa"
```
Expected: `true` (notes filetype behavior from `filetypes.lua` still applies; no LSP attaches to a `.md` buffer). Note: `spell` is a window-local option — `vim.wo.spell`, not `vim.bo.spell` (the latter raises `E5108` on Neovim 0.12).

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
- Consumes: the local `on_attach` function and the `mason-lspconfig.nvim` plugin spec's `config` function, both already defined in `lsp.lua` (Task 2). Task 2 also left `opts.automatic_enable = { exclude = { "ruff" } }` specifically so ruff would not auto-attach with nvim-lspconfig's bundled defaults before this task configured it — this task removes that exclusion.

> **Note:** the code below reflects `lsp.lua`'s actual current content after Task 2's review fix rounds (a settings-propagation bug was found and fixed — `before_init` now mutates `config.settings.python` in place against a pre-declared `settings = {}` table, rather than reassigning `config.settings`; a `vim.lsp.config("*", {...})` capabilities wildcard was added; `automatic_enable` gained the `exclude = { "ruff" }` this task removes). Read the current file yourself before editing — do not work from an older recollection of its shape.

- [ ] **Step 1: Add ruff setup and format-on-save to `lsp.lua`**

In `dot_config/nvim/lua/plugins/lsp.lua`:

1. In the `opts` table, change `automatic_enable = { exclude = { "ruff" } }` to plain `automatic_enable = true` (or remove the field entirely — `true` is the default) — now that ruff will have its own registered config, it's safe to let it auto-enable.
2. Inside the `config` function, add a second `vim.lsp.config(...)` call for `ruff`, positioned **before** the `require("mason-lspconfig").setup(opts)` line, and add the format-on-save autocmd after it. The full function should read:

```lua
    config = function(_, opts)
      vim.lsp.config("*", {
        capabilities = require("cmp_nvim_lsp").default_capabilities(),
      })

      vim.lsp.config("basedpyright", {
        on_attach = on_attach,
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
```

(The `vim.lsp.config("*", ...)` and `basedpyright` blocks above are unchanged from Task 2 — shown again so the whole function reads as one piece. Only the `automatic_enable` change, the `ruff` block, and the autocmd are new in this task.)

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
