# Neovim Python development environment — design

**Date:** 2026-07-07
**Author:** Daniele Alpago
**Status:** Approved (pending written-spec review)

## Context

The current nvim config (chezmoi-managed, `dot_config/nvim`, lives entirely in the
public repo since nothing in it is sensitive) is built around a notes-writing
workflow: LaTeX (VimTeX) + Markdown authoring, Telescope-based note search,
lazy.nvim plugin management, catppuccin/lualine UI, and `mini.nvim`
(surround/pairs/comment). There is no LSP client, no project-tree browser, and
no code-execution tooling. Treesitter's `python` parser is already installed,
but it only provides syntax highlighting — no semantic navigation.

Goal: bring the config to lightweight-IDE parity for Python — project-tree
browsing, goto-definition/references, and running scripts — without debugging
support (explicitly out of scope) and without adding plugins beyond what's
needed. Python tooling is `uv`-managed (`.venv` per project, `uv run` for
execution; confirmed present: `uv 0.8.22`, `ruff 0.13.3` with `ruff server`
support, Neovim `0.12.3`).

## Decisions that shape this work

- **Single source of truth for per-language facts.** A new
  `lua/config/languages.lua` table holds `{filetypes, treesitter parser, mason
  LSP servers}` per language. `treesitter.lua` and the new `lsp.lua` both read
  from it instead of hardcoding Python. Adding a second language later is one
  table row, not a multi-file edit.
- **Treesitter stays the one place notes-parsers and coding-parsers share a
  list** — this is already true today (`latex` sits alongside `bash`/`json`/
  `yaml` in `ensure_installed`), because treesitter is content-blind about
  *why* a parser is needed. Merging is natural there, and only there.
- **LSP semantics stay coding-only.** Interpreter resolution and "run this
  file" are concepts specific to executable code. LaTeX/Markdown tooling
  (VimTeX today; a future `texlab`/`marksman` if ever wanted) stays in its own
  existing plugin files, not folded into `languages.lua`.
- **Running scripts stays zero-plugin.** No toggleterm/overseer — a manual
  tmux pane or `:terminal` running `uv run <file>`, documented as a
  convention, not automated in nvim config.
- **`uv` is the interpreter/dependency authority.** `basedpyright` resolves
  `<root>/.venv/bin/python3` (uv's default venv location) rather than
  whichever `python3` happens to be first on `PATH`.
- **Mason owns editor-tooling binary versions**, independent of the
  system-installed `ruff`/`uv` on `PATH` — intentional isolation, not
  duplication, since this config syncs across multiple machines via chezmoi.
- **Format-on-save is in scope; gitsigns is explicitly deferred** — gitsigns
  is editor-wide, not Python-specific, and was deliberately left out of this
  round.

## Goals

- `mini.files` for project-tree browsing.
- Goto-definition (`gd`), plus references/rename/implementation/hover — the
  latter four already ship as Neovim 0.12 defaults (`grr`/`grn`/`gri`/`K`),
  verified against the running install rather than assumed.
- Format-on-save for Python via ruff.
- A documented, zero-plugin script-running convention (`uv run <file>` in a
  tmux pane).
- An architecture where a second language is added via one data-table row,
  not a multi-file patch.

## Non-goals

- No debugging (DAP) — explicitly deferred by the user.
- No gitsigns / git-gutter integration — explicitly deferred.
- No toggleterm/overseer/test-runner plugins — the zero-plugin baseline was
  chosen deliberately over the added convenience.
- No changes to LaTeX/Markdown tooling (`latex.lua`, `markdown.lua`,
  `filetypes.lua`, `notes.lua`) beyond treesitter's shared `ensure_installed`
  list gaining a merge step.
- No change to `sync-staging.sh` or the chezmoi three-tier merge mechanism —
  this config lives entirely in the public repo already.

---

## Component 1 — `lua/config/languages.lua` (new)

Single source of truth, minimal by design:

```lua
return {
  python = {
    filetypes = { "python" },
    treesitter = { "python" },
    mason_lsp = { "basedpyright", "ruff" },
  },
}
```

Consumers (`treesitter.lua`, `lsp.lua`) iterate this table; nothing else
references Python by name.

## Component 2 — `treesitter.lua` (modified)

Remove the hardcoded `"python"` entry from `ensure_installed`; append parsers
collected from `languages.lua` at setup time instead. `latex`/`bash`/`json`/
`yaml` remain hardcoded — they serve the notes/config concern, which
`languages.lua` is not responsible for.

## Component 3 — `lua/plugins/lsp.lua` (new)

`mason.nvim` + `mason-lspconfig.nvim` + `nvim-lspconfig`, following the
existing one-file-per-concern convention:

- `mason-lspconfig`'s `ensure_installed` is built by flattening `mason_lsp`
  across `languages.lua`.
- `basedpyright`: `root_dir` via `nvim-lspconfig`'s existing default pattern
  (`pyproject.toml`/`.git`); interpreter resolved via a small helper —
  `<root_dir>/.venv/bin/python3` if present, else `vim.fn.exepath("python3")`.
- `ruff`: attached via `ruff server`; its `hover` capability explicitly
  disabled so `basedpyright` remains the single hover/goto-definition
  authority (avoids duplicate popups — a known gotcha with this pairing).
- Shared `on_attach`: one new keymap, `gd` → `vim.lsp.buf.definition()`. No
  other keymaps are added — rename/references/implementation/
  type-definition/document-symbols/hover are already bound by Neovim 0.12's
  built-in LSP defaults (`grn`/`grr`/`gri`/`grt`/`gO`/`K`, confirmed in
  `_core/defaults.lua`).

## Component 4 — Format-on-save

A `BufWritePre` autocmd scoped to the `python` filetype:
`vim.lsp.buf.format({ filter = function(c) return c.name == "ruff" end })`.
The filter is explicit because two LSP clients are attached to the same
buffer and only one implements formatting.

## Component 5 — `completion.lua` (modified)

Add `{ name = "nvim_lsp" }` to the existing `cmp.config.sources` list.
Generic, not Python-specific — any future LSP client's completions flow
through this one line.

## Component 6 — `mini.lua` (modified)

Add `require("mini.files").setup()` alongside the existing `mini.surround`/
`mini.pairs`/`mini.comment` calls, plus a keymap (`<leader>e`) to open the
tree at the current file. This is a module of the already-installed
`mini.nvim` — no new dependency.

## Component 7 — Running scripts (documentation only, no code)

Documented convention, not automated: open a tmux pane (or `:terminal`) and
run `uv run <file>`. `uv run` resolves the project's `.venv`/dependencies
automatically, and also supports PEP 723 inline-metadata scripts for
throwaway one-off files with zero project setup. No nvim keymap, no new
plugin — deliberately, per the zero-plugin baseline.

---

## Data flow: adding a language later

Adding, say, Rust means one new row in `languages.lua`:

```lua
rust = { filetypes = { "rust" }, treesitter = { "rust" }, mason_lsp = { "rust_analyzer" } },
```

`treesitter.lua` and `lsp.lua` both already iterate the table, so the parser
and LSP server install themselves on next launch — no other file changes.
This is the property that proves the architecture avoided clutter.

## Error handling

- **No `.venv` present** → interpreter resolution falls back to system
  `python3`; LSP still attaches, with degraded import accuracy only, not a
  failure.
- **Mason install fails** (offline, first run on a new machine) → only the
  two LSP servers fail to attach. Treesitter, `mini.files`, and notes tooling
  are unaffected, since none of it depends on LSP — a direct payoff of
  keeping these concerns decoupled.
- **Version drift between system `ruff`** (`~/.local/bin/ruff`, via `uv tool`)
  **and mason-managed `ruff`** is intentional isolation, not a bug — editor
  tooling is pinned per-machine independent of `PATH`.
- **`root_dir` detection** reuses `nvim-lspconfig`'s existing default pattern
  matching rather than a bespoke implementation.

## Testing & verification

Manual checklist (this is editor config, not application code — no automated
test suite applies):

1. Apply config, relaunch, `:Lazy sync` — new plugin specs load.
2. `:Mason` — confirms `basedpyright`/`ruff` installed.
3. Open a uv-managed `.py` file with a third-party import; `gd` on that
   import jumps into the `.venv`'s installed package (proves interpreter
   resolution, not just client attachment).
4. Save a badly formatted file — confirms ruff format-on-save fires.
5. `<leader>e` — confirms `mini.files` opens at the current file.
6. Open a `.py` file outside any `.venv` — confirms the fallback path doesn't
   error.
7. Open a `.md`/`.tex` file — confirms nothing new attaches and spellcheck/
   wrap still work (regression check that the decoupling actually held).

## Risks & mitigations

- **Two ruff installs (system + mason) could confuse future-you if versions
  diverge** — mitigated by treating this as expected isolation (documented
  above), not a defect to fix.
- **The ruff hover-disable workaround could break on a future ruff release**
  if its LSP capability behavior changes — re-verify if hover popups
  duplicate after a `ruff` version bump.
- **`basedpyright` and `ruff` both produce diagnostics** — no conflict is
  expected (they cover different classes: type errors vs. lint rules), but
  worth confirming there's no duplicate diagnostic spam during verification
  steps 3–4.

## Sequencing

Implement in one pass — the components are small and interdependent (the
language table has no effect until `treesitter.lua`/`lsp.lua` consume it).
Verify with the checklist above before considering the work done.
