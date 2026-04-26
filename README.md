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
| `dalpago/dotfiles` (public) | Shell config, git config, packages, externals, scripts | Yes — public |
| `dalpago/dotfiles-private` (private) | Enabled categories, encrypted secrets, age key paths | Yes — private |
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

`settings.json` is excluded from the claude-config external and managed
manually. MCP servers are configured in `~/.claude.json` (not tracked).

## Secrets Management

Secrets are handled at two levels:

1. **API keys used in chezmoi templates** (e.g. `context7_api_key`) go in
   `~/.config/chezmoi/chezmoi.toml` under `[data]`. This file is machine-local
   and not tracked by any git repo.

2. **Encrypted files deployed to disk** (e.g. `~/.secrets`) use
   [age](https://github.com/FiloSottile/age) encryption. The encrypted source
   lives in `dotfiles-private` under `secrets/`.

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

# 4. Add machine-local secrets to chezmoi config
#    Edit ~/.config/chezmoi/chezmoi.toml and add API keys under [data]:
#      context7_api_key = "your-key-here"

# 5. Clone private overlay
git clone git@github.com:dalpago/dotfiles-private.git \
    ~/.local/share/chezmoi/.local

# 6. Re-apply to decrypt secrets and install all packages
chezmoi apply

# 7. Generate SSH keys (if not copying from another machine)
ssh-keygen -t ed25519 -C "daniele.alpago3@gmail.com" -f ~/.ssh/github-personal
ssh-keygen -t ed25519 -C "dalpago@swissblock.net" -f ~/.ssh/github-work
ssh-keygen -t ed25519 -C "dalpago@swissblock.net" -f ~/.ssh/csi-data

# 8. Add SSH keys to agent
ssh-add ~/.ssh/github-personal
ssh-add ~/.ssh/github-work
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

# 5. Copy age key and add machine-local config (same as macOS steps 3-4)

# 6. Clone private overlay
git clone git@github.com:dalpago/dotfiles-private.git \
    ~/.local/share/chezmoi/.local

# 7. Re-apply
chezmoi apply

# 8. Set zsh as default shell
chsh -s $(which zsh)

# 9. Generate SSH keys (or copy from Mac)
ssh-keygen -t ed25519 -C "daniele.alpago3@gmail.com" -f ~/.ssh/github-personal
ssh-keygen -t ed25519 -C "dalpago@swissblock.net" -f ~/.ssh/github-work
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

| Host | Account | Key |
|------|---------|-----|
| `github.com` | dalpago (personal) | `~/.ssh/github-personal` |
| `github-work` | dalpago-sbt (work) | `~/.ssh/github-work` |
| `ftp.csidata.com` | CSI Data | `~/.ssh/csi-data` |

```bash
# Clone work repos using the github-work alias
git clone github-work:dalpago-sbt/repo-name.git
```

## Key Files

| File | Purpose |
|------|---------|
| `sync-staging.sh` | Pre-hook: merges public + private overlay into staging |
| `.chezmoi.toml.tmpl` | Chezmoi config template; sets sourceDir to staging |
| `.chezmoidata/packages.yaml` | All managed packages (base + categories) |
| `.chezmoiexternal.toml.tmpl` | External git/archive dependencies |
| `.chezmoiignore` | Files chezmoi must not manage (Claude runtime data, SSH keys) |
| `.chezmoiscripts/` | Install scripts (packages, MCP servers) |
| `dot_zshrc.tmpl` | Zsh config: oh-my-zsh, starship, eza, bat, uv venv |
| `dot_config/starship.toml` | Starship prompt with Catppuccin Mocha palette |
| `dot_config/bat/config` | bat pager config with Catppuccin Mocha theme |

## What's Managed

Chezmoi manages 100+ files including:

- **Shell**: `.zshrc`, oh-my-zsh + 5 plugins, Starship prompt
- **Git**: `.gitconfig` (SSH signing, delta pager), `.gitignore-global`
- **Editor/Pager**: bat (Catppuccin Mocha), eza theme
- **SSH**: `~/.ssh/config` (multi-account GitHub)
- **Claude Code**: agents, skills, conventions, plugins (via mirus-tech external)
- **Packages**: Homebrew (macOS) / apt (Debian) with categorized install
