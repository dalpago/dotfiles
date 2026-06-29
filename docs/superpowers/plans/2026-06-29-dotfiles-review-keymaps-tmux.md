# Dotfiles Review, Key Mappings & tmux Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simplify the chezmoi dotfiles to a robust independent-copies model, capture and extend keyboard remapping (add Caps Lock → Control), and integrate tmux + oh-my-tmux — all cross-platform for macOS and native Ubuntu.

**Architecture:** Three-tier chezmoi (public repo + private overlay merged into a staging symlink tree) stays as-is. We remove the now-unneeded shared-live-copy machinery (umask hook, chezmoi umask wrapper, setgid/`staff` permissions, git `safe.directory`), fix the dotfiles repo's git identity to personal via a chezmoi-managed `includeIf`, harden cross-platform package parity, and add keymaps (single-source-of-truth via `.chezmoidata/keymap.yaml`) and tmux (vendored as a chezmoi external).

**Tech Stack:** chezmoi v2.70, Go text/template, zsh, git (SSH-signed commits), Homebrew/apt, `hidutil` (macOS), `gsettings`/xkb (GNOME), gpakosz/.tmux (oh-my-tmux).

## Global Constraints

- **Commit conventions (from user's CLAUDE.md):** Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`), imperative mood, atomic. **Never mention Claude/AI** in any commit message — no `Co-Authored-By` trailer, no footer.
- **Tools:** use `fd` not `find`, `rg` not `grep` where running ad-hoc commands.
- **Dotfiles repo git identity = personal:** author `Daniele Alpago <daniele.alpago3@gmail.com>`, sign with `~/.ssh/github-personal`. Commits are SSH-signed (`commit.gpgSign = true`). **Until Task 2 is applied**, prepend each commit with the override `git -c user.email=daniele.alpago3@gmail.com -c user.name="Daniele Alpago" -c user.signingkey=~/.ssh/github-personal commit ...`. **After Task 2's `chezmoi apply`**, the `includeIf` makes this automatic — plain `git commit` works.
- **Repo location:** all paths below are relative to the public source repo `~/.local/share/chezmoi` unless absolute. Edits to source files must go through `chezmoi edit` OR direct edit of the canonical file in this repo (both are equivalent here since the staging symlinks point back to canonical).
- **OS gating:** macOS via `eq .chezmoi.os "darwin"` / `eq .osid "darwin"` and the `Library/` rule in `.chezmoiignore`; Linux via `eq .chezmoi.os "linux"` / `eq .osid "debian"`. Introduce no new gating pattern.
- **Verification baseline:** after any source change, `chezmoi diff` must show only intended changes, `zsh -i -c 'exit'` must print no errors, and `bash test-sync-staging.sh` must still pass (regression guard for the merge hook).
- **Do not push.** All commits stay local unless the user explicitly asks to push.

---

## File Structure

**Workstream 1 — foundation**
- Modify: `dot_zshrc.tmpl` (remove umask hook + chezmoi wrapper)
- Modify: `dot_gitconfig.tmpl` (remove `safe.directory`, add dotfiles `includeIf`)
- Modify: `dot_config/git/personal.gitconfig` (add personal `signingkey`)
- Modify: `.chezmoidata/packages.yaml` (bat/fd/tea on Linux; tmux → base — Task 10)
- Modify: `.chezmoiscripts/run_onchange_install-packages.sh.tmpl` (bat/fd shims, tea install)
- Create: `scripts/normalize-perms.sh` (idempotent permission reset; ignored by chezmoi)
- Create: `bootstrap.sh` (cold-start; ignored by chezmoi)
- Modify: `.chezmoiignore` (ignore `scripts/`, `bootstrap.sh`)
- Modify: `README.md` (docs cleanup)

**Workstream 2 — keymaps**
- Create: `.chezmoidata/keymap.yaml` (single source of truth for HID pairs + xkb options)
- Create: `Library/LaunchAgents/com.local.keyremap.plist.tmpl` (macOS, templated from keymap.yaml)
- Create: `.chezmoiscripts/run_onchange_after_apply-keymap.sh.tmpl` (macOS hidutil apply + Linux gsettings)

**Workstream 3 — tmux**
- Modify: `.chezmoiexternal.toml.tmpl` (vendor oh-my-tmux)
- Create: `symlink_dot_tmux.conf` (chezmoi symlink → vendored config)
- Create: `dot_tmux.conf.local` (user-editable overrides)

---

## Task 1: Commit pre-existing in-progress work (hygiene)

There are 4 uncommitted files unrelated to this project. Commit them first so the tree is clean and our changes stay isolated. **Do not** sweep them into our commits.

**Files:**
- Commit (already modified, not by us): `.chezmoidata/packages.yaml`, `dot_config/nvim/lua/config/filetypes.lua`, `dot_config/nvim/lua/plugins/latex.lua`, `dot_config/nvim/lua/plugins/markdown.lua`

- [ ] **Step 1: Inspect the diffs to understand intent**

Run:
```bash
cd ~/.local/share/chezmoi && git diff -- .chezmoidata/packages.yaml dot_config/nvim/
```
Read the changes. They are nvim filetype/plugin tweaks plus a packages edit. Group them into one or two logical conventional commits based on what you see.

- [ ] **Step 2: Stage and commit the nvim changes**

```bash
git add dot_config/nvim/
git -c user.email=daniele.alpago3@gmail.com -c user.name="Daniele Alpago" -c user.signingkey=~/.ssh/github-personal \
  commit -m "feat(nvim): update latex, markdown, and filetype config"
```
(Adjust the message to match what the diff actually does.)

- [ ] **Step 3: Stage and commit the packages change**

```bash
git add .chezmoidata/packages.yaml
git -c user.email=daniele.alpago3@gmail.com -c user.name="Daniele Alpago" -c user.signingkey=~/.ssh/github-personal \
  commit -m "chore(packages): <describe the change>"
```

- [ ] **Step 4: Verify clean tree**

Run: `git status -s`
Expected: empty output (nothing uncommitted).

---

## Task 2: Fix dotfiles repo git identity (personal) + remove `safe.directory`

Aligns authoring/signing with the `github-personal` remote via a chezmoi-managed `includeIf`, and removes the shared-ownership `safe.directory` workaround. After this task's apply, all later commits sign with the personal key automatically.

**Files:**
- Modify: `dot_config/git/personal.gitconfig` (add `signingkey`)
- Modify: `dot_gitconfig.tmpl:164-172` (remove `[safe]` block, add dotfiles `includeIf`)

**Interfaces:**
- Produces: a deployed `~/.gitconfig` where `gitdir:~/.local/share/chezmoi/` and `gitdir:~/Resources/Notes/` both resolve `user.signingkey = ~/.ssh/github-personal` and `user.email = daniele.alpago3@gmail.com`.

- [ ] **Step 1: Verify current (wrong) signing identity for the dotfiles repo**

Run:
```bash
cd ~/.local/share/chezmoi && git config user.signingkey
```
Expected (current, to be changed): `~/.ssh/github-work`

- [ ] **Step 2: Add personal signing key to the shared personal fragment**

Edit `dot_config/git/personal.gitconfig` so the `[user]` block includes the signing key:

```ini
[user]
    name = Daniele Alpago
    email = daniele.alpago3@gmail.com
    signingkey = ~/.ssh/github-personal
[url "git@github-personal:dalpago/"]
    insteadOf = git@github.com:dalpago/
```

- [ ] **Step 3: In `dot_gitconfig.tmpl`, remove the `[safe]` block and add the dotfiles `includeIf`**

Replace the trailing block (currently lines ~164-172):

```ini
[includeIf "gitdir:~/Resources/Notes/"]
    path = ~/.config/git/personal.gitconfig

# ~/Resources/Notes is owned by the `daniele` macOS account but worked from
# `work`; git's repository-discovery refuses to trust mismatched-owner repos
# unless explicitly allowed here. safe.directory is consulted at discovery
# time (before includeIf triggers), so it lives in the top-level config.
[safe]
    directory = /Users/work/Resources/Notes
```

with:

```ini
# Personal identity + signing key for personal repos (dotfiles and notes).
# Both repos push to github-personal; this keeps authoring and SSH-signing
# consistent with that remote on every machine.
[includeIf "gitdir:~/.local/share/chezmoi/"]
    path = ~/.config/git/personal.gitconfig

[includeIf "gitdir:~/Resources/Notes/"]
    path = ~/.config/git/personal.gitconfig
```

> ⚠️ **Sequencing:** Removing `[safe] directory` drops git's trust for the
> legacy `daniele`-owned `~/Resources/Notes` repo. After this task, git
> commands inside Notes will fail with "dubious ownership" from the `work`
> account **until** Notes is chowned to `work` (Task 5, Step 0). If you need
> to use Notes before completing Task 5, do that chown first.

- [ ] **Step 4: Preview the change**

Run: `chezmoi diff -- ~/.gitconfig ~/.config/git/personal.gitconfig`
Expected: `~/.gitconfig` loses the `[safe]` block and gains the dotfiles `includeIf`; `personal.gitconfig` gains the `signingkey` line.

- [ ] **Step 5: Apply**

Run: `chezmoi apply -- ~/.gitconfig ~/.config/git/personal.gitconfig`
Expected: no errors.

- [ ] **Step 6: Verify the dotfiles repo now uses the personal key**

Run:
```bash
cd ~/.local/share/chezmoi && git config user.signingkey && git config user.email
```
Expected: `~/.ssh/github-personal` and `daniele.alpago3@gmail.com`

- [ ] **Step 7: Commit (now automatically personal-signed)**

```bash
git add dot_gitconfig.tmpl dot_config/git/personal.gitconfig
git commit -m "refactor(git): use personal identity for dotfiles, drop safe.directory"
git log -1 --pretty='%GS'    # expect: daniele.alpago3@gmail.com
```

---

## Task 3: Remove the shared-live-copy umask machinery from zsh

With independent copies, group-writable defaults are unneeded; the OS default `umask 022` is correct. Removing the `chezmoi` umask wrapper is safe because normalized `755` runtime dirs satisfy oh-my-zsh's `compinit` security check.

**Files:**
- Modify: `dot_zshrc.tmpl:36-53` (remove the umask block and chezmoi wrapper)

- [ ] **Step 1: Remove the per-directory umask hook and chezmoi wrapper**

In `dot_zshrc.tmpl`, delete the block that currently spans from the comment `# Scope umask 002 ...` through the closing of the `chezmoi()` function. Concretely, remove these lines:

```bash
# Scope umask 002 (group-writable defaults) to directories where cross-account
# editing is intentional; default to 022 everywhere else. A global umask 002
# would propagate to every child process (Claude Code, brew, vim, etc.) and
# create group-writable files even in private paths like ~/.claude.json.
function _umask_for_pwd() {
    case "$PWD" in
        "$HOME/Resources/Notes"|"$HOME/Resources/Notes/"*) umask 002 ;;
        "$HOME/.local/share/chezmoi"|"$HOME/.local/share/chezmoi/"*) umask 002 ;;
        *) umask 022 ;;
    esac
}
chpwd_functions+=(_umask_for_pwd)
_umask_for_pwd  # set initial umask based on the directory the shell starts in

# Defense-in-depth: pin umask 022 for chezmoi regardless of $PWD. Chezmoi
# writes to $HOME (not the invoking directory), so it must not use the
# group-writable umask that's active inside the shared trees.
chezmoi() { (umask 022; command chezmoi "$@"); }
```

Leave the `export EDITOR="nvim"` / `LANG` lines above it and the `if command -v bat ...` block below it intact.

- [ ] **Step 2: Preview**

Run: `chezmoi diff -- ~/.zshrc`
Expected: only the umask function, `chpwd` hook, and `chezmoi()` wrapper are removed.

- [ ] **Step 3: Apply and verify a clean interactive shell**

```bash
chezmoi apply -- ~/.zshrc
zsh -i -c 'echo "umask=$(umask)"; exit'
```
Expected: prints `umask=022` (macOS default) with no compinit/insecure-directory warnings.

- [ ] **Step 4: Commit**

```bash
git add dot_zshrc.tmpl
git commit -m "refactor(zsh): drop shared-copy umask hook and chezmoi wrapper"
```

---

## Task 4: Cross-platform package parity (bat/fd names + tea on Linux)

On Debian/Ubuntu, apt installs `bat`→`batcat` and `fd`→`fdfind`, so the `PAGER`/`MANPAGER`/`fd` usage silently breaks. Add shims. Also add a Linux install for the `tea` Forgejo CLI (currently macOS-only) since the Ubuntu PC needs Forgejo access.

**Files:**
- Modify: `.chezmoiscripts/run_onchange_install-packages.sh.tmpl` (Debian branch)

- [ ] **Step 1: Add bat/fd shims to the Debian branch**

In `.chezmoiscripts/run_onchange_install-packages.sh.tmpl`, inside the `{{ else if eq .osid "debian" -}}` branch, after the apt install line, add:

```bash
# --- Debian command-name shims: apt ships bat as batcat, fd as fdfind ---
mkdir -p "$HOME/.local/bin"
if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
    ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
fi
if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
fi
```

- [ ] **Step 2: Add a Linux `tea` install (mirroring the eza/delta manual-install pattern)**

In the same Debian branch, after the existing `git-delta` block, add:

```bash
# tea (Gitea/Forgejo CLI) — not in apt; install the release binary
if ! command -v tea &>/dev/null; then
    echo "Installing tea (Forgejo CLI)..."
    TEA_VERSION=$(curl -sSf https://gitea.com/api/v1/repos/gitea/tea/releases | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
    ARCH=$(dpkg --print-architecture)
    curl -sSfLo "$HOME/.local/bin/tea" \
      "https://dl.gitea.com/tea/${TEA_VERSION#v}/tea-${TEA_VERSION#v}-linux-${ARCH}"
    chmod +x "$HOME/.local/bin/tea"
fi
```

- [ ] **Step 3: Lint the rendered template**

Run:
```bash
chezmoi execute-template < .chezmoiscripts/run_onchange_install-packages.sh.tmpl | bash -n
```
Expected: no output (script parses cleanly). Note: `bash -n` only syntax-checks; it does not run installs.

- [ ] **Step 4: Commit**

```bash
git add .chezmoiscripts/run_onchange_install-packages.sh.tmpl
git commit -m "fix(packages): add Linux bat/fd shims and tea install"
```

---

## Task 5: Permission normalization script + run it

Strip the now-inert setgid/group-writable state from the source repos and Notes, returning them to single-user `755`/`644`. Provide an idempotent helper, then run it for the work account.

**Files:**
- Create: `scripts/normalize-perms.sh`
- Modify: `.chezmoiignore` (ignore `scripts/`)

- [ ] **Step 0: Claim ~/Resources/Notes for the working account (one-time, needs sudo)**

The legacy Notes repo is owned by `daniele`. Under independent copies, the
working account owns its own copy. Re-own it so git trusts it without
`safe.directory` (removed in Task 2):

```bash
if [[ -d ~/Resources/Notes && ! -O ~/Resources/Notes ]]; then
    sudo chown -R "$USER:staff" ~/Resources/Notes
fi
cd ~/Resources/Notes && git status -s >/dev/null && echo "Notes git OK"
```
Expected: "Notes git OK" (no "dubious ownership" error). Skip silently if Notes
doesn't exist on this machine.

- [ ] **Step 1: Write the normalization script**

Create `scripts/normalize-perms.sh`:

```bash
#!/usr/bin/env bash
# Reset chezmoi source repos (and optionally ~/Resources/Notes) from the old
# shared-edit permission model (setgid dirs, 664/775, group staff) back to
# single-user defaults: dirs 755, files 644, no setgid. Leaves .git untouched.
# Idempotent and safe to re-run. Does NOT chown across users (see README for
# the one-time sudo chown needed if a repo is owned by another account).
set -euo pipefail

repos=(
    "$HOME/.local/share/chezmoi"
    "$HOME/.local/share/chezmoi/.local"
)
# Include Notes only if it exists and is owned by the current user.
if [[ -d "$HOME/Resources/Notes" && -O "$HOME/Resources/Notes" ]]; then
    repos+=("$HOME/Resources/Notes")
fi

for repo in "${repos[@]}"; do
    [[ -d "$repo" ]] || continue
    echo "Normalizing $repo ..."
    # Working tree only; never touch .git internals.
    find "$repo" -path '*/.git' -prune -o -type d -print0 \
        | xargs -0 chmod 755
    find "$repo" -path '*/.git' -prune -o -type f -print0 \
        | xargs -0 chmod u=rw,go=r
done
echo "Done. Verify with: ls -ld <repo> (expect drwxr-xr-x, no 's')."
```

- [ ] **Step 2: Ignore `scripts/` so chezmoi never deploys it to $HOME**

In `.chezmoiignore`, under the `docs/` entry added earlier, add:

```
# Helper scripts run manually, not user dotfiles.
scripts/
bootstrap.sh
```

- [ ] **Step 3: Make executable and run it for the work account**

```bash
chmod +x scripts/normalize-perms.sh
bash scripts/normalize-perms.sh
```
Expected: prints "Normalizing ..." lines and "Done."

- [ ] **Step 4: Verify setgid is gone and modes are single-user**

```bash
ls -ld ~/.local/share/chezmoi ~/.local/share/chezmoi/.local
find ~/.local/share/chezmoi -path '*/.git' -prune -o -type d -perm -2000 -print
```
Expected: roots show `drwxr-xr-x` (no `s`); the `find` prints nothing (no setgid dirs remain).

- [ ] **Step 5: Confirm chezmoi + compinit still happy**

```bash
chezmoi diff >/dev/null && echo "chezmoi OK"
zsh -i -c 'exit'
```
Expected: "chezmoi OK" and no insecure-directory warnings.

- [ ] **Step 6: Commit**

```bash
git add scripts/normalize-perms.sh .chezmoiignore
git commit -m "chore(perms): add normalize-perms helper and ignore scripts/"
```

---

## Task 6: Cold-start `bootstrap.sh`

One command to provision a fresh machine: install chezmoi+age if missing, pre-create the staging dir (the cold-start gotcha), and `chezmoi init --apply` the public repo over HTTPS (no SSH key needed since the repo is public). Prints next-steps for the age key + private overlay.

**Files:**
- Create: `bootstrap.sh` (repo root; already ignored via Task 5 Step 2)

- [ ] **Step 1: Write bootstrap.sh**

Create `bootstrap.sh`:

```bash
#!/usr/bin/env bash
# Cold-start bootstrap for a fresh machine (macOS or Debian/Ubuntu).
# Public dotfiles only — clones over HTTPS so no SSH key is required yet.
# Re-runnable. Secrets (age key + private overlay) are a documented follow-up.
set -euo pipefail

PUBLIC_REPO="https://github.com/dalpago/dotfiles.git"

install_prereqs() {
    if command -v brew &>/dev/null; then
        brew install chezmoi age
    elif command -v apt &>/dev/null; then
        sudo apt update -y && sudo apt install -y age curl git
        if ! command -v chezmoi &>/dev/null; then
            sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
        fi
    else
        echo "Unsupported platform: need brew or apt." >&2; exit 1
    fi
}

command -v chezmoi &>/dev/null || install_prereqs

# Cold-start gotcha: chezmoi stats sourceDir before the pre-hook runs, so the
# staging dir must exist before the first chezmoi command.
mkdir -p "$HOME/.local/share/chezmoi-staging"

CHEZMOI="$(command -v chezmoi || echo "$HOME/.local/bin/chezmoi")"
"$CHEZMOI" init --apply "$PUBLIC_REPO"

cat <<'NEXT'

──────────────────────────────────────────────────────────────
Public dotfiles applied. To finish (secrets + private overlay):

  1. Place your age key:  ~/.config/chezmoi/key.txt
  2. Clone the private overlay:
       git clone git@github-personal:dalpago/dotfiles-private.git \
         ~/.local/share/chezmoi/.local
  3. Re-apply to decrypt secrets and install all packages:
       chezmoi apply
──────────────────────────────────────────────────────────────
NEXT
```

- [ ] **Step 2: Syntax-check and verify idempotency on this machine**

```bash
chmod +x bootstrap.sh
bash -n bootstrap.sh && echo "syntax OK"
```
Expected: "syntax OK". (Do not run it fully here — chezmoi is already initialized; it's exercised on the daniele/Ubuntu bring-ups.)

- [ ] **Step 3: Commit**

```bash
git add bootstrap.sh
git commit -m "feat(bootstrap): add cold-start bootstrap script"
```

---

## Task 7: Documentation cleanup (README)

Bring the README in line with the new model: independent copies, native Ubuntu, fixed step numbering, bootstrap usage, tmux/keymaps in the inventory.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Remove the "Cross-account dotfile editing" section**

Delete the entire section (heading `## Cross-account dotfile editing` through its permission-replication code block and the Notes paragraph that follows it).

- [ ] **Step 2: Replace the shared-edit daily workflow with the git-sync model**

In the "Daily Workflow" section, after the push commands, replace any shared-editing description with:

```markdown
Each account/machine has its own checkout. To sync changes made elsewhere:

    cd ~/.local/share/chezmoi && git pull && chezmoi apply

`~/Resources/Notes` follows the same model — its own clone per account, synced
via `git pull`.
```

- [ ] **Step 3: Rename WSL section and add bootstrap + native-Ubuntu notes; fix step numbers**

Rename `### WSL Ubuntu` to `### Ubuntu (native desktop)`. At the top of both the macOS and Ubuntu setup blocks, add:

```markdown
The quickest path is the bootstrap script:

    sh -c "$(curl -fsLS https://raw.githubusercontent.com/dalpago/dotfiles/master/bootstrap.sh)"

Then follow the printed next-steps (age key + private overlay). The manual
steps below are the equivalent expanded form.
```

Renumber the manual steps so each block has a single ascending sequence (the macOS block currently has two "6"; the Ubuntu block has two "5"). Keep WSL-only notes (e.g. Windows clipboard) clearly marked as WSL-specific under the native-Ubuntu section.

- [ ] **Step 4: Add a one-time chown note for Notes under the new model**

Add a short subsection noting that if `~/Resources/Notes` is owned by another account (legacy shared setup), the work account claims its own copy with:

```markdown
    sudo chown -R "$USER:staff" ~/Resources/Notes
    bash ~/.local/share/chezmoi/scripts/normalize-perms.sh
```

- [ ] **Step 5: Update the "What's Managed" inventory**

Add bullets for: tmux + oh-my-tmux (vendored external + `~/.tmux.conf.local`), and macOS/Linux keyboard remapping (`.chezmoidata/keymap.yaml` → LaunchAgent plist / gsettings).

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs: update README for independent-copies model and native Ubuntu"
```

---

## Task 8: Capture & extend macOS keyboard remapping (single source of truth)

Bring the orphaned LaunchAgent into chezmoi, store the mapping once in `.chezmoidata/keymap.yaml`, template the plist from it, fix the one-way→two-way ISO drift, add Caps→Ctrl, and apply immediately via a `run_onchange` script.

**Files:**
- Create: `.chezmoidata/keymap.yaml`
- Create: `Library/LaunchAgents/com.local.keyremap.plist.tmpl`
- Create: `.chezmoiscripts/run_onchange_after_apply-keymap.sh.tmpl`

**Interfaces:**
- Produces: chezmoi data key `keymap.macos_hid` (list of `{src, dst}` hex-string pairs) consumed by both the plist template and the apply script; `keymap.linux_xkb_options` (list of strings) consumed in Task 9.

- [ ] **Step 1: Create the single-source-of-truth data file**

Create `.chezmoidata/keymap.yaml`:

```yaml
keymap:
  # macOS hidutil UserKeyMapping pairs (HID usage IDs, page 0x07).
  macos_hid:
    # ISO extra key (0x64) <-> backtick/tilde (0x35) — two-way swap.
    - { src: "0x700000064", dst: "0x700000035" }
    - { src: "0x700000035", dst: "0x700000064" }
    # Caps Lock (0x39) -> Left Control (0xE0).
    - { src: "0x700000039", dst: "0x7000000E0" }
  # GNOME/X11 xkb options applied on Linux (Caps -> Ctrl only).
  linux_xkb_options:
    - "ctrl:nocaps"
```

- [ ] **Step 2: Create the LaunchAgent plist template**

Create `Library/LaunchAgents/com.local.keyremap.plist.tmpl`:

```xml
{{- /* macOS-only via the Library/ rule in .chezmoiignore */ -}}
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.keyremap</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/hidutil</string>
        <string>property</string>
        <string>--set</string>
        <string>{"UserKeyMapping":[{{ range $i, $p := .keymap.macos_hid }}{{ if $i }},{{ end }}{"HIDKeyboardModifierMappingSrc":{{ $p.src }},"HIDKeyboardModifierMappingDst":{{ $p.dst }}}{{ end }}]}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 3: Create the immediate-apply run_onchange script**

Create `.chezmoiscripts/run_onchange_after_apply-keymap.sh.tmpl`:

```bash
#!/usr/bin/env bash
# keymap.yaml hash: {{ include ".chezmoidata/keymap.yaml" | sha256sum }}
set -euo pipefail

{{ if eq .chezmoi.os "darwin" -}}
MAPPING='{"UserKeyMapping":[{{ range $i, $p := .keymap.macos_hid }}{{ if $i }},{{ end }}{"HIDKeyboardModifierMappingSrc":{{ $p.src }},"HIDKeyboardModifierMappingDst":{{ $p.dst }}}{{ end }}]}'
echo "Applying hidutil key mapping..."
/usr/bin/hidutil property --set "$MAPPING" >/dev/null
# Reload the LaunchAgent so the mapping also survives reboot.
PLIST="$HOME/Library/LaunchAgents/com.local.keyremap.plist"
if [[ -f "$PLIST" ]]; then
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST" 2>/dev/null || true
fi
{{ else if eq .chezmoi.os "linux" -}}
# Linux handled in Task 9's gsettings block below (kept in this same script).
{{ end -}}
```

(Task 9 extends this same file's Linux branch.)

- [ ] **Step 4: Validate template rendering and plist syntax**

```bash
chezmoi execute-template < Library/LaunchAgents/com.local.keyremap.plist.tmpl > /tmp/keymap.plist
plutil -lint /tmp/keymap.plist
```
Expected: `/tmp/keymap.plist: OK`. Inspect that the `UserKeyMapping` array has **3** entries (two ISO directions + Caps→Ctrl).

- [ ] **Step 5: Apply and verify the live mapping**

```bash
chezmoi apply -- ~/Library/LaunchAgents/com.local.keyremap.plist
hidutil property --get "UserKeyMapping"
```
Expected: the live mapping shows all three pairs (0x64↔0x35 both directions, and 0x39→0xE0). Press Caps Lock → it now behaves as Control.

- [ ] **Step 6: Commit**

```bash
git add .chezmoidata/keymap.yaml Library/LaunchAgents/com.local.keyremap.plist.tmpl .chezmoiscripts/run_onchange_after_apply-keymap.sh.tmpl
git commit -m "feat(keymap): manage hidutil mapping from single source, add caps->ctrl"
```

---

## Task 9: Ubuntu (GNOME) Caps Lock → Control

Add the Linux branch to the keymap apply script using `gsettings` xkb-options, reading the option list from the same `keymap.yaml`. Caps→Ctrl only (the ISO swap is Mac-specific).

**Files:**
- Modify: `.chezmoiscripts/run_onchange_after_apply-keymap.sh.tmpl` (Linux branch)

**Interfaces:**
- Consumes: `keymap.linux_xkb_options` from Task 8's `keymap.yaml`.

- [ ] **Step 1: Fill in the Linux branch**

Replace the `{{ else if eq .chezmoi.os "linux" -}}` placeholder branch in `.chezmoiscripts/run_onchange_after_apply-keymap.sh.tmpl` with:

```bash
{{ else if eq .chezmoi.os "linux" -}}
# GNOME: set xkb options (Caps -> Ctrl). Needs an active session bus; skip
# gracefully on headless/SSH applies.
if command -v gsettings &>/dev/null && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    OPTS="[{{ range $i, $o := .keymap.linux_xkb_options }}{{ if $i }}, {{ end }}'{{ $o }}'{{ end }}]"
    echo "Setting GNOME xkb-options: $OPTS"
    gsettings set org.gnome.desktop.input-sources xkb-options "$OPTS"
else
    echo "gsettings/session bus unavailable — skipping xkb-options (re-run inside a desktop session)."
fi
{{ end -}}
```

- [ ] **Step 2: Verify both rendered branches**

```bash
# macOS rendering (current machine):
chezmoi execute-template < .chezmoiscripts/run_onchange_after_apply-keymap.sh.tmpl | bash -n && echo "darwin syntax OK"
```
Expected: "darwin syntax OK". (The Linux branch is exercised on the Ubuntu box; it is syntactically validated by the same template renderer there.)

- [ ] **Step 3: Commit**

```bash
git add .chezmoiscripts/run_onchange_after_apply-keymap.sh.tmpl
git commit -m "feat(keymap): add GNOME caps->ctrl via gsettings on Linux"
```

---

## Task 10: Promote tmux to the base package set

Guarantee `tmux` on every machine regardless of enabled categories.

**Files:**
- Modify: `.chezmoidata/packages.yaml`

- [ ] **Step 1: Move tmux from `cli-tools` to `base`**

In `.chezmoidata/packages.yaml`: remove `tmux` from `categories.cli-tools.darwin.brews` and `categories.cli-tools.debian.apt`; add `tmux` to `base.darwin.brews` and `base.debian.apt` (keep lists alphabetically sorted, matching existing style).

- [ ] **Step 2: Verify the merge still parses**

```bash
chezmoi execute-template < .chezmoiscripts/run_onchange_install-packages.sh.tmpl | bash -n && echo "OK"
```
Expected: "OK".

- [ ] **Step 3: Commit**

```bash
git add .chezmoidata/packages.yaml
git commit -m "chore(packages): promote tmux to base"
```

---

## Task 11: Integrate tmux + oh-my-tmux

Vendor oh-my-tmux as a chezmoi external, symlink `~/.tmux.conf` to it, and manage the user-editable `~/.tmux.conf.local`. oh-my-tmux locates the override as `<main-config-path>.local`, i.e. `~/.tmux.conf.local`, so the vendored copy can live under `~/.config/tmux/oh-my-tmux/`.

**Files:**
- Modify: `.chezmoiexternal.toml.tmpl` (add oh-my-tmux archive)
- Create: `symlink_dot_tmux.conf` (target: vendored `.tmux.conf`)
- Create: `dot_tmux.conf.local` (seeded from upstream defaults)

- [ ] **Step 1: Add the oh-my-tmux external**

In `.chezmoiexternal.toml.tmpl`, before the "Private overlay externals" block at the end, add:

```toml
# oh-my-tmux (gpakosz/.tmux)
[".config/tmux/oh-my-tmux"]
    type = "archive"
    url = "https://github.com/gpakosz/.tmux/archive/refs/heads/master.tar.gz"
    stripComponents = 1
    refreshPeriod = "168h"
```

- [ ] **Step 2: Create the chezmoi symlink to the vendored config**

Create `symlink_dot_tmux.conf` with this single-line content (the symlink target, relative to `$HOME`):

```
.config/tmux/oh-my-tmux/.tmux.conf
```

- [ ] **Step 3: Apply to fetch oh-my-tmux and create the symlink**

```bash
chezmoi apply -- ~/.config/tmux ~/.tmux.conf
ls -l ~/.tmux.conf                       # expect symlink -> .config/tmux/oh-my-tmux/.tmux.conf
test -f ~/.config/tmux/oh-my-tmux/.tmux.conf.local && echo "upstream local present"
```
Expected: symlink exists; "upstream local present".

- [ ] **Step 4: Seed `dot_tmux.conf.local` from the upstream default**

```bash
cp ~/.config/tmux/oh-my-tmux/.tmux.conf.local ~/.local/share/chezmoi/dot_tmux.conf.local
```
This captures oh-my-tmux's documented, fully-commented defaults as the editable base (prefix `C-b`, mouse on, default theme). Leave defaults as-is for now; you'll tweak this one file later.

- [ ] **Step 5: Apply and verify tmux loads cleanly**

```bash
chezmoi apply -- ~/.tmux.conf.local
tmux -f ~/.tmux.conf kill-server 2>/dev/null || true
tmux -f ~/.tmux.conf new-session -d -s smoke && tmux has-session -t smoke && echo "tmux OK"
tmux kill-session -t smoke 2>/dev/null || true
```
Expected: "tmux OK" with no config-parse errors printed.

- [ ] **Step 6: Commit**

```bash
git add .chezmoiexternal.toml.tmpl symlink_dot_tmux.conf dot_tmux.conf.local
git commit -m "feat(tmux): vendor oh-my-tmux and manage tmux.conf.local"
```

---

## Final verification (after all tasks)

- [ ] **Regression: merge hook harness**

Run: `cd ~/.local/share/chezmoi && bash test-sync-staging.sh`
Expected: all assertions pass.

- [ ] **Full dry-run is clean**

Run: `chezmoi diff`
Expected: no unexpected pending changes (only things you intend to apply).

- [ ] **Shell + tmux smoke**

```bash
zsh -i -c 'exit'           # no errors/warnings
tmux new-session -d -s f && tmux kill-session -t f && echo ok
```

- [ ] **daniele account bring-up** (manual, after the above): from the `daniele` login, run `bootstrap.sh`, transfer the age key, clone the private overlay, `chezmoi apply`; confirm Caps→Ctrl active and no permission surgery needed.

- [ ] **Ubuntu bring-up** (manual): on the native Ubuntu desktop, run `bootstrap.sh`; confirm packages (incl. `tea`, `bat`/`fd` shims), shell, tmux, and GNOME Caps→Ctrl all work.

---

## Self-review notes (coverage map)

| Spec item | Task |
|---|---|
| 1A remove umask/wrapper/safe.directory/README section | Tasks 2, 3, 7 |
| 1B bat/fd shims + Linux tea | Task 4 |
| 1C README cleanup + step numbering | Task 7 |
| 1D commit in-progress work + bootstrap.sh | Tasks 1, 6 |
| 1E personal identity includeIf + signingkey | Task 2 |
| 1A normalize perms (active step) | Task 5 |
| 2 capture plist, fix drift, caps→ctrl, immediate apply | Task 8 |
| 2 Ubuntu gsettings caps→ctrl | Task 9 |
| 3 tmux→base | Task 10 |
| 3 oh-my-tmux external + symlink + local | Task 11 |
