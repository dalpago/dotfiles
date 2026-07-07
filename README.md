# dotfiles

Chezmoi-managed dotfiles for macOS and Debian/Ubuntu. Uses a public/private
overlay pattern to keep machine-specific and sensitive config out of the public
repo.

## Architecture

```
~/.local/share/chezmoi/          <- public source (this repo)
~/.local/share/chezmoi/.local/   <- private overlay (dalpago/dotfiles-private)
~/.local/share/chezmoi-staging/  <- merged staging dir (chezmoi sourceDir)
~/.config/chezmoi/chezmoi.toml   <- machine-local config (not in any repo)
```

A `sync-staging.sh` pre-hook runs before chezmoi reads source state. It
builds the staging directory as a **symlink tree** mirroring the public
source plus the private `.local/` overlay. Chezmoi reads through the
symlinks to the canonical sources in each repo. This means `chezmoi edit`
opens the canonical file in your editor (writes propagate through the
symlink), and `chezmoi add` / `re-add` writes go via the bi-directional
propagation phase of `sync-staging.sh` — see below.

```
┌──────────────┐  symlink mirror   ┌────────────────┐  chezmoi  ┌─────┐
│ Public repo  │──────────────────>│                │   apply   │     │
│ (dotfiles)   │                   │  Staging dir   │──────────>│  ~/ │
└──────────────┘                   │  (symlinks to  │           │     │
┌──────────────┐  overlay symlinks │   canonical)   │           └─────┘
│ Private repo │──────────────────>│                │
│ (dotfiles-   │                   └────────────────┘
│  private)    │
└──────────────┘
```

### Bi-directional source propagation

`chezmoi add` and `chezmoi re-add` atomically rename files into the source
dir, which replaces staging symlinks with regular files. The pre-hook
detects these on the next chezmoi command and propagates them back to the
appropriate canonical repo (private wins for paths that exist in both;
files matching private patterns like `encrypted_*.age` won't be created
in public). After propagation, staging is wiped and rebuilt as symlinks
to the now-updated canonical sources.

The test harness at `test-sync-staging.sh` (run with
`bash test-sync-staging.sh`) verifies all merge scenarios — fresh build,
re-add propagation across public/private/secrets-special-case paths,
new-file routing, private-pattern protection, conflict resolution,
direct-canonical-edit safety, missing-overlay bootstrap, and the
self-modifying-script regression guard.

### What goes where

| Location | Contents | Git tracked? |
|----------|----------|--------------|
| `dalpago/dotfiles` (public) | Shell config, git config, packages, externals, scripts, SSH public keys | Yes — public |
| `dalpago/dotfiles-private` (private) | Enabled categories, encrypted secrets, encrypted SSH private keys, encrypted `.netrc` | Yes — private |
| `~/.config/chezmoi/chezmoi.toml` | Machine-local: name, email, profile, API keys | No |

## Package Management

`.chezmoidata/packages.yaml` defines all packages in two sections:

- **`base`** — installed on every machine (age, chezmoi, git, vim, zsh, etc.)
- **`categories`** — optional groups: `development`, `cli-tools`, `security`,
  `desktop-apps`, `work`

Per-machine category selection lives in `.local/.chezmoidata/local.yaml`
(private overlay). The install script merges base + enabled categories at
runtime.

Python packages are managed via uv into `~/.venvs/default`, which is activated
in zshrc.

## External Dependencies

`.chezmoiexternal.toml.tmpl` manages:

- **oh-my-zsh and plugins**: `type=archive` to avoid leaving `.git` dirs on
  disk. Weekly refresh via `refreshPeriod = "168h"`. oh-my-zsh's own CI files
  (`.oh-my-zsh/.github/**`) are ignored — they drift on each refresh and would
  otherwise trigger chezmoi's "changed since last wrote it" prompt.
- **oh-my-tmux**: `type=archive` (gpakosz/.tmux) into `~/.config/tmux/oh-my-tmux/`.
- **`~/.claude`**: `type=git-repo` from **your own fork**
  `git.mirus-tech.com/dalpago/claude-config` with `exact=false` so local-only
  files (projects/, memory/, etc.) survive `chezmoi apply`.

### Why a fork (and how to pull upstream)

`~/.claude` is a fork of the shared `jmz/claude-config`, **not** Joerg's repo
directly. Owning the upstream means `chezmoi apply` only ever pulls **your**
changes, so editing `~/.claude` no longer collides with upstream on every
apply. Joerg's repo is wired as the `upstream` remote in the local clone; pull
his updates **on your schedule**:

```bash
cd ~/.claude
git fetch upstream && git merge upstream/master   # resolve once, on your terms
git push                                           # to your fork (origin)
```

Day-to-day, commit your `~/.claude` edits and push them to your fork; the next
`chezmoi apply` pulls them back cleanly on your other machines.

The external's `exclude` list drops `.git/**`, `.gitignore`, `docs/**`, and the
helper scripts. The two config files need care:

- **`settings.json`** — your machine/Claude settings (model, theme, effort,
  permissions, plugins). Committed to your fork so it syncs across your
  machines. Contains no secrets.
- **`mcp-servers.json`** — **generated locally** by `run_onchange_after_setup-mcp.sh`,
  which injects the real API key (e.g. Context7) from `~/.secrets`. It is
  therefore **git-rm'd and gitignored in the fork — never commit it.** On a new
  machine the setup script regenerates it from your decrypted secrets.

> Note: `~/.claude` commits are made **unsigned** (`-c commit.gpgSign=false`)
> because the work signing key is usually locked. The dotfiles repo itself
> auto-signs with your personal key via the `includeIf`.

## Secrets Management

All secrets — API keys, tokens, passwords — live in age-encrypted files.
There is no plaintext-in-config layer; the canonical source for runtime
secrets is `~/.secrets`, which scripts and zshrc source as env vars.

1. **API keys and tokens** live as `export FOO=...` lines inside the
   age-encrypted `~/.secrets` file. The encrypted source is in
   `dotfiles-private` at `secrets/encrypted_private_dot_secrets.age`.
   Scripts that need a key (e.g. the MCP setup script) read it from the
   environment after sourcing `~/.secrets`.

   To add a new key:
   ```bash
   chezmoi edit ~/.secrets        # opens the decrypted file
   # add: export NEW_API_KEY="..."
   chezmoi apply                   # re-encrypts, redeploys
   ```

2. **Other encrypted files deployed to disk** (e.g. `~/.netrc`) use the same
   [age](https://github.com/FiloSottile/age) encryption. Encrypted sources
   live in the private overlay as `encrypted_*.age` files.

3. **SSH private keys** are age-encrypted in the private overlay under
   `private_dot_ssh/encrypted_*.age`. Chezmoi decrypts them on `apply`.

The age decryption key must be transferred securely to new machines:
- **Password Manager** — copy from secure note
- **Secure Copy** — `scp ~/.config/chezmoi/key.txt user@newmachine:~/.config/chezmoi/`
- **Manual** — display on old machine, type on new machine

## First-time Setup

### Prerequisites

- Git installed
- An SSH key on GitHub is only needed later (for the private overlay and pushing);
  the public dotfiles clone over HTTPS, so the bootstrap works with no key.

### macOS

The fastest path is the bootstrap script — it installs chezmoi + age, pre-creates
the staging dir, and applies the public dotfiles over HTTPS (no SSH key needed yet):

```bash
sh -c "$(curl -fsLS https://raw.githubusercontent.com/dalpago/dotfiles/master/bootstrap.sh)"
```

Then complete the secrets + identity steps below. The manual sequence (equivalent
to what bootstrap automates in steps 1–3) is:

```bash
# 1. Install chezmoi and age
brew install chezmoi age

# 2. Pre-create the staging dir. chezmoi stats sourceDir before running
#    the pre-hook on the first read, so staging must exist beforehand.
mkdir -p ~/.local/share/chezmoi-staging

# 3. Initialize and apply public dotfiles (HTTPS — no SSH key required)
chezmoi init --apply https://github.com/dalpago/dotfiles.git

# 4. Copy the age decryption key (transfer securely from existing machine)
mkdir -p ~/.config/chezmoi
# Paste your age key into ~/.config/chezmoi/key.txt

# 5. Clone private overlay (contains encrypted ~/.secrets with API keys)
git clone git@github-personal:dalpago/dotfiles-private.git \
    ~/.local/share/chezmoi/.local

# 6. Re-apply to decrypt secrets and install all packages
chezmoi apply

# 7. Generate SSH keys (if not restoring from private overlay)
ssh-keygen -t ed25519 -C "daniele.alpago3@gmail.com" -f ~/.ssh/github-personal
ssh-keygen -t ed25519 -C "dalpago@swissblock.net" -f ~/.ssh/github-work
ssh-keygen -t ed25519 -C "dalpago@swissblock.net" -f ~/.ssh/csi-data

# 8. Add SSH keys to agent
ssh-add ~/.ssh/github-personal
ssh-add ~/.ssh/github-work

# 9. Configure tea CLI for Forgejo (tokens from password manager)
tea login add --name mirus-tech --url https://git.mirus-tech.com --token "$FORGEJO_MIRUS_TOKEN" --no-version-check
tea login add --name sgm --url http://git.sgm.internal --token "$FORGEJO_SGM_TOKEN" --no-version-check

# 10. Set gh CLI to use SSH
gh config set git_protocol ssh
```

### Ubuntu (native desktop)

The bootstrap script works on Debian/Ubuntu too (installs chezmoi + age, applies
public dotfiles over HTTPS):

```bash
sh -c "$(curl -fsLS https://raw.githubusercontent.com/dalpago/dotfiles/master/bootstrap.sh)"
```

The equivalent manual sequence:

```bash
# 1. Install chezmoi
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin

# 2. Install age, zsh, and dependencies
sudo apt update && sudo apt install -y age zsh git curl

# 3. Pre-create the staging dir (see macOS step 2 for rationale)
mkdir -p ~/.local/share/chezmoi-staging

# 4. Initialize public dotfiles (HTTPS — no SSH key required)
~/.local/bin/chezmoi init --apply https://github.com/dalpago/dotfiles.git

# 5. Copy age key (same as macOS step 4)

# 6. Clone private overlay
git clone git@github-personal:dalpago/dotfiles-private.git \
    ~/.local/share/chezmoi/.local

# 7. Re-apply to decrypt secrets and install all packages
chezmoi apply

# 8. Set zsh as default shell
chsh -s $(which zsh)

# 9. Generate SSH keys (or copy from Mac / restore from private overlay)
ssh-keygen -t ed25519 -C "daniele.alpago3@gmail.com" -f ~/.ssh/github-personal
ssh-keygen -t ed25519 -C "dalpago@swissblock.net" -f ~/.ssh/github-work

# 10. Configure tea CLI and gh (same as macOS steps 9-10)
```

> **Caps Lock → Control** on GNOME is applied automatically by the keymap
> `run_onchange` script (via `gsettings`) during `chezmoi apply`, provided you
> run it inside a desktop session.

> **WSL note:** under WSL the steps above still work, but keyboard remapping is
> handled by Windows (not these dotfiles), and the WSL-specific shell aliases
> (`explorer`, `clip`, `open`) activate automatically when `$WSL_DISTRO_NAME` is set.

## Daily Workflow

```bash
# Edit a dotfile
chezmoi edit ~/.zshrc

# Preview changes before applying
chezmoi diff

# Apply changes
chezmoi apply

# Commit and push public changes
cd ~/.local/share/chezmoi && git add -A && git commit -m "Update dotfiles" && git push

# Commit and push private changes (if any)
cd ~/.local/share/chezmoi/.local && git add -A && git commit -m "Update private overlay" && git push
```

`chezmoi edit` and `chezmoi re-add` both write back to the canonical source
repos transparently. `chezmoi edit` opens the canonical file in `$EDITOR`
via a symlink, so saves land in the right repo immediately. `chezmoi
re-add` writes to staging (atomic-rename replaces the symlink with a
regular file), and the next chezmoi command's pre-hook propagates the
content back to the appropriate canonical source before rebuilding the
symlink tree.

## Multiple machines and accounts

Each machine — and each account on a shared Mac (`work`, `daniele`) — keeps its
**own** checkout under its own `$HOME`. There is no shared live copy; accounts
stay in sync through GitHub:

```bash
# After making and pushing changes from another account/machine:
cd ~/.local/share/chezmoi && git pull && chezmoi apply
```

`~/Resources/Notes` follows the same model — its own clone per account, synced
via `git pull`.

If a directory is a leftover from the old shared-editing setup (owned by another
account, with setgid bits), claim it for the current account once:

```bash
sudo chown -R "$USER:staff" ~/Resources/Notes      # only if owned by another user
bash ~/.local/share/chezmoi/scripts/normalize-perms.sh
```

`normalize-perms.sh` resets the source repos (and Notes, if you own it) to
single-user modes — directories `755`, files `644`, no setgid — while preserving
the executable bit on scripts like the `sync-staging.sh` pre-hook.

## SSH Configuration

| Host alias | Account | Key | Protocol |
|------------|---------|-----|----------|
| `github-personal` | dalpago (personal) | `~/.ssh/github-personal` | SSH |
| `github-work` | dalpago-sbt (work) | `~/.ssh/github-work` | SSH |
| `ftp.csidata.com` | CSI Data | `~/.ssh/csi-data` | SSH |

Forgejo instances use HTTPS + `.netrc` token authentication (not SSH):

| Instance | Auth | Usage |
|----------|------|-------|
| `git.mirus-tech.com` | `.netrc` token | `git clone https://git.mirus-tech.com/org/repo.git` |
| `git.sgm.internal` | `.netrc` token | `git clone http://git.sgm.internal/org/repo.git` |

```bash
# Clone personal GitHub repos
git clone github-personal:dalpago/repo-name.git

# Clone work GitHub repos
git clone github-work:dalpago-sbt/repo-name.git

# Clone Forgejo repos (HTTPS, auth via ~/.netrc)
git clone https://git.mirus-tech.com/org/repo-name.git
```

## Key Files

| File | Purpose |
|------|---------|
| `sync-staging.sh` | Pre-hook: merges public + private overlay into staging |
| `.chezmoi.toml.tmpl` | Chezmoi config template; sets sourceDir to staging |
| `.chezmoidata/packages.yaml` | All managed packages (base + categories) |
| `.chezmoiexternal.toml.tmpl` | External git/archive dependencies |
| `.chezmoiignore` | Files chezmoi must not manage (Claude runtime data, SSH keys) |
| `private_dot_ssh/allowed_signers` | SSH public keys trusted for commit signature verification |
| `.chezmoiscripts/` | Install scripts (packages, MCP servers, keymap apply) |
| `.chezmoidata/keymap.yaml` | Linux xkb options for keyboard remapping (Caps→Ctrl); macOS remapping lives in the Karabiner config below |
| `dot_config/karabiner/create_karabiner.json` | macOS key remap via Karabiner-Elements (Caps→Ctrl on all keyboards + built-in-only §/` swap); seeded once, Karabiner owns the file afterward |
| `symlink_dot_tmux.conf` | Symlinks `~/.tmux.conf` to the vendored oh-my-tmux config |
| `dot_tmux.conf.local` | User-editable tmux overrides |
| `scripts/normalize-perms.sh` | Resets repos to single-user permissions (run manually) |
| `bootstrap.sh` | Cold-start: install chezmoi, apply public dotfiles over HTTPS |
| `dot_zshrc.tmpl` | Zsh config: oh-my-zsh, starship, eza, bat, uv venv |
| `dot_config/starship.toml` | Starship prompt with Catppuccin Mocha palette |
| `dot_config/bat/config` | bat pager config with Catppuccin Mocha theme |

## What's Managed

Chezmoi manages 100+ files including:

- **Shell**: `.zshrc`, oh-my-zsh + 5 plugins, Starship prompt
- **Multiplexer**: tmux via oh-my-tmux (vendored external) + editable `~/.tmux.conf.local`
- **Git**: `.gitconfig` (SSH signing, delta pager, `osxkeychain` credential helper), `.gitignore-global`; personal identity scoped to the dotfiles and notes repos via `includeIf`
- **Editor/Pager**: Neovim (incl. markdown rendering/preview stack, and Python dev tooling — LSP via basedpyright+ruff with uv-aware interpreter resolution, `mini.files` project tree, format-on-save; see below), bat (Catppuccin Mocha), eza theme
- **SSH**: `~/.ssh/config` (multi-account GitHub, `IdentitiesOnly yes`), `allowed_signers` for commit verification
- **Keyboard remapping**: macOS via Karabiner-Elements (`dot_config/karabiner/create_karabiner.json`, seeded once — Caps→Ctrl on all keyboards + built-in-only §/` swap); Linux via GNOME `gsettings` (Caps→Ctrl), sourced from `.chezmoidata/keymap.yaml`
- **Claude Code**: via your fork (`dalpago/claude-config`) git-repo external, with `jmz/claude-config` as the `upstream` remote (merge on demand):
  - `CLAUDE.md` — global development guidelines
  - `agents/` — 9 agents (debugger, developer, coder, researcher, etc.)
  - `skills/` — 17+ skills (planner, codebase-analysis, refactor, etc.)
  - `rules/` — language-specific conventions (python, typescript, rust, fastapi, nextjs)
  - `scripts/` — utilities (MCP setup, upstream sync, validation, cleanup)
  - `docs/` — architecture and integration guides
  - `upstream/` — vendored solatis/claude-config (synced via git subtree)
- **Packages**: Homebrew (macOS) / apt (Debian) with categorized install

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
