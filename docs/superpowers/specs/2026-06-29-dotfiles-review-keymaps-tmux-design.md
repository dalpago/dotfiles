# Dotfiles review, key mappings & tmux integration — design

**Date:** 2026-06-29
**Author:** Daniele Alpago
**Status:** Approved (pending written-spec review)

## Context

Chezmoi-managed dotfiles using a three-tier layout: public repo (`dalpago/dotfiles`),
private overlay (`dalpago/dotfiles-private`), merged into a `chezmoi-staging` symlink
tree by a `sync-staging.sh` pre-hook. The setup will be exercised on two new targets:

1. A second macOS account (`daniele`) on the **same** physical Mac (already exists).
2. A **native Ubuntu desktop** (GNOME) on the office PC — currently Windows + WSL,
   to be reinstalled as native Ubuntu.

This is the first real cross-account and second-OS shakedown, so the goals are
(a) simplify and harden the foundation, (b) capture and extend keyboard remapping,
and (c) integrate tmux.

## Decisions that shape this work

- **Account model: independent copies, synced via GitHub.** Each account/machine runs
  its own `chezmoi init` and holds its own checkout in its own `$HOME`. Accounts stay
  in sync by commit → push in one, then `git pull` + `chezmoi apply` in the other.
  This is what the chezmoi config template *already* does (`sourceDir` is under
  `.chezmoi.homeDir`), so the shared-live-copy permission machinery is **not** doing
  anything load-bearing for chezmoi and can be removed.
- **Extend the same model to `~/Resources/Notes`.** It is its own git repo; each account
  clones its own copy and syncs via git. No shared live copy, so the cross-account
  ownership workaround (`safe.directory`) is no longer needed.
- **The setgid / `staff`-group / `umask` apparatus is being retired**, not preserved.

## Goals

- A clean, verified foundation that bootstraps on the `daniele` account and on native
  Ubuntu with no manual permission surgery.
- Keyboard remapping captured in chezmoi as the single source of truth, drift fixed,
  Caps Lock → Control added, cross-platform.
- tmux + oh-my-tmux integrated using the same patterns already in the repo.

## Non-goals

- No change to the symlink-tree merge mechanism (`sync-staging.sh`) or its test harness.
- No change to secrets/age encryption design.
- No new shared-live-copy editing between accounts.
- No tmux plugin manager (tpm) or heavy tmux customization beyond oh-my-tmux defaults.

---

## Workstream 1 — Review, simplify & cross-platform hardening

### 1A. Remove the shared-copy machinery

Independent copies make group-writable shared trees unnecessary. Remove:

- **`dot_zshrc.tmpl`**
  - The `_umask_for_pwd` function and its `chpwd_functions` hook (current lines ~40–48).
  - The `chezmoi() { (umask 022; command chezmoi "$@"); }` wrapper (current line ~53).
  - Net result: the shell uses the OS default `umask 022` everywhere, which is correct
    for the independent-copy model.
- **`dot_gitconfig.tmpl`**
  - Remove the `[safe] directory = /Users/work/Resources/Notes` block (current lines
    ~167–172) **and** its explanatory comment.
  - **Keep** `[includeIf "gitdir:~/Resources/Notes/"]` — that scopes personal identity
    to notes and is unrelated to ownership.
- **`README.md`**
  - Remove the "Cross-account dotfile editing" section and its permission-replication
    snippet.

The setgid bits and `staff` group already on disk become inert leftovers. **Normalize
them as an active step:** reset the chezmoi public repo, the private overlay, and
`~/Resources/Notes` to default single-user ownership and `umask 022` modes — strip the
setgid bit from directories (dirs → `755`, files → `644`), leaving `.git/` untouched.
Provide this as a small, idempotent `normalize-perms.sh` helper under `scripts/` (run
manually, ignored by chezmoi), and document running it once per account after the
shared-copy machinery is removed.

### 1B. Cross-platform correctness fixes (Ubuntu)

- **`bat` / `fd` command names.** On Debian/Ubuntu, apt installs these as `batcat` /
  `fdfind`. The `.zshrc` lines `export PAGER="bat"` and `MANPAGER="... bat ..."`, and
  the `fd`-based global tooling, silently never fire under those names. Fix by creating
  `~/.local/bin/bat` and `~/.local/bin/fd` shims on Linux (symlinks to `batcat`/`fdfind`),
  created in the Debian branch of the package install script. macOS keeps native names,
  so behavior converges.
- **`tea` (Forgejo CLI) on Linux.** Currently macOS-only in `packages.yaml`, but the
  Ubuntu setup docs call `tea login`. Add a Linux install for `tea` (manual install
  block in the Debian branch, mirroring the existing `eza`/`delta` pattern) so Forgejo
  access works on the office PC.

### 1C. Documentation cleanup (`README.md`)

- Rename the "WSL Ubuntu" setup section to "Ubuntu (native desktop)"; retain WSL-specific
  notes only where still relevant (the `.zshrc` already gates WSL bits on
  `WSL_DISTRO_NAME`, so those stay).
- Fix duplicate step numbers (macOS has two step "6"; the WSL section has two step "5").
- Update the "What's Managed" inventory to include tmux/oh-my-tmux and the keymap files.
- Update the daily-workflow / cross-account section to describe the **git-sync** model
  (push from one account, pull + apply in the other) instead of shared editing.

### 1E. Fix the dotfiles repo git identity mismatch

The dotfiles repo pushes to `git@github-personal:dalpago/dotfiles.git`, but the global
`~/.gitconfig` (deployed with `profile=work`) forces `user.email = dalpago@swissblock.net`
and `user.signingkey = ~/.ssh/github-work`. There is no `includeIf` for the dotfiles
path, so commits are authored/signed as **work** while pushed to the **personal**
account. **Decision: align to personal.**

- Add a chezmoi-managed `[includeIf "gitdir:~/.local/share/chezmoi/"]` (mirroring the
  existing Notes `includeIf`) pointing at a personal identity fragment that sets
  `user.email = daniele.alpago3@gmail.com` and `user.signingkey = ~/.ssh/github-personal`.
  This makes the dotfiles repo use personal identity on every machine, consistently.
- The reusable personal fragment is `~/.config/git/personal.gitconfig` — already
  referenced by the Notes `includeIf`. Confirm it sets both email and signing key; if it
  only sets email today, add the personal `signingkey` there.
- Existing history remains work-signed; only new commits change. No history rewrite.

### 1D. Hygiene & bootstrap

- **Commit existing uncommitted work first.** The public repo currently has 4 modified
  files (`.chezmoidata/packages.yaml`, three `dot_config/nvim/...` files). Review and
  commit these in their own focused commit(s) before refactoring, so the tree is clean.
  This is separate from the spec commit, which stages only the spec + `.chezmoiignore`.
- **`bootstrap.sh` (included).** A script that pre-creates
  `~/.local/share/chezmoi-staging`, installs the chezmoi prerequisite if missing, and
  runs `chezmoi init --apply git@github-personal:dalpago/dotfiles.git` in one step,
  retiring the documented cold-start gotcha. Lives at repo root (ignored by chezmoi,
  like `sync-staging.sh`); README points new machines at it. Must be safe to re-run.

---

## Workstream 2 — Capture key mappings & add Caps Lock → Control

### Current state (findings)

- A LaunchAgent at `~/Library/LaunchAgents/com.local.keyremap.plist` exists **outside**
  chezmoi. It runs `hidutil` at login to map HID `0x64` → `0x35` (ISO extra key →
  backtick) — but **only one direction**.
- Live `hidutil` shows a **two-way** swap (`0x64 ↔ 0x35`), so the persisted plist has
  drifted from the running state: after a reboot the mapping is incomplete.

### Plan

- **Bring the plist into chezmoi** as a macOS-only template:
  `Library/LaunchAgents/com.local.keyremap.plist` (the existing `.chezmoiignore` rule
  ignores `Library/` on non-macOS, so it is automatically Mac-only).
- **Fix the drift and extend the mapping.** The `UserKeyMapping` array holds the
  complete set:
  - ISO swap as a proper **two-way** swap: `0x700000064 → 0x700000035` **and**
    `0x700000035 → 0x700000064`.
  - **Caps Lock → Control:** `0x700000039 → 0x7000000E0`.
- **Apply immediately on change (macOS).** Add a `run_onchange_` script (macOS-gated)
  that runs `hidutil property --set` with the same mapping and reloads the LaunchAgent,
  so edits take effect without logout. The script's content hash includes the mapping,
  so chezmoi re-runs it whenever the mapping changes.
- **Ubuntu (GNOME).** Add a Linux-gated `run_onchange_` script that sets
  `gsettings set org.gnome.desktop.input-sources xkb-options "['ctrl:nocaps']"` for
  **Caps Lock → Control only**. The ISO `0x64 ↔ 0x35` swap is specific to the Mac's
  ISO keyboard and is **not** applied on the office PC.

### Mechanism rationale

`run_onchange_` fits "re-apply a system setting when I edit its definition" because
chezmoi re-runs the script only when its rendered content changes. The plist is a
managed dotfile (declarative, deployed to disk); the script is the imperative "make it
live now" companion.

---

## Workstream 3 — tmux + oh-my-tmux

- **Vendor oh-my-tmux** (`gpakosz/.tmux`) as a chezmoi external (`type = "archive"`,
  `refreshPeriod = "168h"`), matching the existing oh-my-zsh plugin pattern, into
  `~/.config/tmux/oh-my-tmux/`.
- **`~/.tmux.conf`** is a chezmoi symlink pointing at the vendored
  `oh-my-tmux/.tmux.conf` (oh-my-tmux's documented install layout).
- **`dot_tmux.conf.local`** is managed as a normal tracked file — this is the single
  file the user edits for personal overrides.
- **Promote `tmux` to `base`** in `packages.yaml` (currently in the `cli-tools`
  category) so it is guaranteed on every machine regardless of enabled categories.
- **Starting defaults** (to be tweaked later in `.tmux.conf.local`): prefix stays
  `C-b`, mouse enabled, theme aligned with the existing Catppuccin shell aesthetic.

### Mechanism rationale

An `external` is for vendored upstream code the user does not edit (oh-my-tmux,
oh-my-zsh) — chezmoi keeps it fresh on a schedule. A tracked `dot_tmux.conf.local`
is the editable surface. This mirrors the oh-my-zsh model already in the repo, so no
new pattern is introduced.

---

## Cross-cutting: how OS-gating stays consistent

Every platform-specific piece uses mechanisms already present in the repo:

- macOS-only files via `Library/` ignore rule + `eq .chezmoi.os "darwin"` /
  `eq .osid "darwin"` guards.
- Linux-only behavior via `eq .chezmoi.os "linux"` / `eq .osid "debian"` guards.
- No new gating pattern is introduced.

## Testing & verification

- **Local (work account):** `chezmoi diff` then `chezmoi apply` is clean; shell starts
  without errors; key remap applies immediately; tmux launches with oh-my-tmux.
- **`sync-staging.sh` test harness** still passes (no merge-logic changes expected;
  run it as a regression guard).
- **daniele account:** fresh `chezmoi init --apply` from GitHub produces a working
  environment with no permission surgery; Caps → Ctrl active.
- **Native Ubuntu:** fresh bootstrap installs packages (including Linux `tea`, `bat`/`fd`
  shims), shell + tmux work, `gsettings` Caps → Ctrl active under GNOME.

## Risks & mitigations

- **Removing the umask hook could regress the Notes shared-edit workflow** — mitigated
  by the explicit decision to move Notes to independent copies too; no shared editing
  remains.
- **hidutil immediate-apply script** must be idempotent and not conflict with the
  LaunchAgent at login — both set the identical mapping, so converge to the same state.
- **oh-my-tmux external symlink layout** must match upstream's expected paths — verify
  against current gpakosz/.tmux README during implementation.

## Sequencing

Implement in the stated order: Workstream 1 (clean foundation) → 2 (keymaps) → 3 (tmux).
Each is independently testable. The daniele and Ubuntu bring-ups happen after
Workstream 1 lands, since they validate the simplified foundation.
