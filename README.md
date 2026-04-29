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

A `sync-staging.sh` pre-hook runs before chezmoi reads source files. It rsyncs
the public source into a staging directory, then overlays the private `.local/`
on top. Chezmoi reads from staging, so it sees the merged result.

```
┌─────────────┐     rsync      ┌──────────────────┐     chezmoi     ┌──────┐
│ Public repo  │───────────────>│                  │    apply        │      │
│ (dotfiles)   │                │  Staging dir     │────────────────>│  ~/  │
└─────────────┘                │  (merged)        │                 │      │
┌─────────────┐     overlay    │                  │                 └──────┘
│ Private repo │───────────────>│                  │
│ (dotfiles-   │                └──────────────────┘
│  private)    │
└─────────────┘
```

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
  disk. Weekly refresh via `refreshPeriod = "168h"`.
- **`~/.claude`**: `type=git-repo` from mirus-tech/claude-config with
  `exact=false` so local-only files (settings.local.json, projects/, memory/)
  survive `chezmoi apply`.

Only `settings.json`, `mcp-servers.json`, `.git/**`, and `.gitignore` are
excluded from the external. Everything else syncs: CLAUDE.md, agents, skills,
rules, scripts, docs, output-styles, upstream, LICENSE, README.

- **`settings.json`** — excluded because it contains machine-local env vars
  (`CLAUDE_CODE_EFFORT_LEVEL`, etc.) that would be overwritten on every apply.
  Managed manually.
- **`mcp-servers.json`** — excluded because it has hardcoded paths in the
  upstream repo. Instead, the chezmoi setup script generates it with correct
  paths from template data, then calls `scripts/setup-mcp-servers.sh` to merge
  into `~/.claude.json`.

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
- SSH key added to GitHub (for cloning via SSH)

### macOS

```bash
# 1. Install chezmoi and age
brew install chezmoi age

# 2. Initialize and apply dotfiles
chezmoi init --apply git@github.com:dalpago/dotfiles.git

# 3. Copy the age decryption key (transfer securely from existing machine)
mkdir -p ~/.config/chezmoi
# Paste your age key into ~/.config/chezmoi/key.txt

# 4. Clone private overlay (contains encrypted ~/.secrets with API keys)
git clone git@github.com:dalpago/dotfiles-private.git \
    ~/.local/share/chezmoi/.local

# 5. Re-apply to decrypt secrets and install all packages
chezmoi apply

# 6. Generate SSH keys (if not restoring from private overlay)
ssh-keygen -t ed25519 -C "daniele.alpago3@gmail.com" -f ~/.ssh/github-personal
ssh-keygen -t ed25519 -C "dalpago@swissblock.net" -f ~/.ssh/github-work
ssh-keygen -t ed25519 -C "dalpago@swissblock.net" -f ~/.ssh/csi-data

# 7. Add SSH keys to agent
ssh-add ~/.ssh/github-personal
ssh-add ~/.ssh/github-work

# 8. Configure tea CLI for Forgejo (tokens from password manager)
tea login add --name mirus-tech --url https://git.mirus-tech.com --token "$FORGEJO_MIRUS_TOKEN" --no-version-check
tea login add --name onca-karat --url https://git.onca-karat.ts.net --token "$FORGEJO_ONCA_TOKEN" --no-version-check

# 9. Set gh CLI to use SSH
gh config set git_protocol ssh
```

### WSL Ubuntu

```bash
# 1. Install chezmoi
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin

# 2. Install age
sudo apt update && sudo apt install -y age

# 3. Install zsh and dependencies
sudo apt install -y zsh git curl

# 4. Initialize dotfiles
~/.local/bin/chezmoi init --apply git@github.com:dalpago/dotfiles.git

# 5. Copy age key (same as macOS step 3)

# 6. Clone private overlay
git clone git@github.com:dalpago/dotfiles-private.git \
    ~/.local/share/chezmoi/.local

# 7. Re-apply
chezmoi apply

# 8. Set zsh as default shell
chsh -s $(which zsh)

# 9. Generate SSH keys (or copy from Mac / restore from private overlay)
ssh-keygen -t ed25519 -C "daniele.alpago3@gmail.com" -f ~/.ssh/github-personal
ssh-keygen -t ed25519 -C "dalpago@swissblock.net" -f ~/.ssh/github-work

# 10. Configure tea CLI and gh (same as macOS steps 9-10)
```

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
| `git.onca-karat.ts.net` | `.netrc` token | `git clone https://git.onca-karat.ts.net/org/repo.git` |

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
| `.chezmoiscripts/` | Install scripts (packages, MCP servers) |
| `dot_zshrc.tmpl` | Zsh config: oh-my-zsh, starship, eza, bat, uv venv |
| `dot_config/starship.toml` | Starship prompt with Catppuccin Mocha palette |
| `dot_config/bat/config` | bat pager config with Catppuccin Mocha theme |

## What's Managed

Chezmoi manages 100+ files including:

- **Shell**: `.zshrc`, oh-my-zsh + 5 plugins, Starship prompt
- **Git**: `.gitconfig` (SSH signing, delta pager, `osxkeychain` credential helper), `.gitignore-global`
- **Editor/Pager**: bat (Catppuccin Mocha), eza theme
- **SSH**: `~/.ssh/config` (multi-account GitHub, `IdentitiesOnly yes`), `allowed_signers` for commit verification
- **Claude Code**: via mirus-tech/claude-config git-repo external:
  - `CLAUDE.md` — global development guidelines
  - `agents/` — 9 agents (debugger, developer, coder, researcher, etc.)
  - `skills/` — 17+ skills (planner, codebase-analysis, refactor, etc.)
  - `rules/` — language-specific conventions (python, typescript, rust, fastapi, nextjs)
  - `scripts/` — utilities (MCP setup, upstream sync, validation, cleanup)
  - `docs/` — architecture and integration guides
  - `upstream/` — vendored solatis/claude-config (synced via git subtree)
- **Packages**: Homebrew (macOS) / apt (Debian) with categorized install
