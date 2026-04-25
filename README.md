# dotfiles

Chezmoi-managed dotfiles for macOS and Debian/Ubuntu. Uses a public/private
overlay pattern to keep machine-specific and sensitive config out of the public
repo.

## Architecture

```
~/.local/share/chezmoi/        <- public source (this repo)
~/.local/share/chezmoi/.local/ <- private overlay (dalpago/dotfiles-private)
~/.local/share/chezmoi-staging/ <- merged staging dir (chezmoi sourceDir)
```

`sync-staging.sh` runs as the `hooks.read-source-state.pre` hook before chezmoi
reads any source files. It rsyncs the public source into staging, then overlays
the private `.local/` directory on top. Chezmoi reads from staging, so it sees
the merged result.

## Package Management

`.chezmoidata/packages.yaml` has two top-level sections:

- `base` — installed on every machine
- `categories` — optional groups enabled per machine

Per-machine category selection lives in `.local/.chezmoidata/packages.yaml`
(private overlay). The install script merges base + enabled categories at
runtime.

Python packages are managed via uv into `~/.venvs/default`, which is activated
in zshrc.

## External Dependencies

`.chezmoiexternal.toml.tmpl` manages:

- oh-my-zsh and plugins: `type=archive` to avoid leaving `.git` dirs on disk.
  Weekly refresh via `refreshPeriod = "168h"`.
- `~/.claude`: `type=git-repo` with `exact=false` so local-only files
  (settings.local.json, projects/, memory/) survive `chezmoi apply`.

`settings.json` and `mcp-servers.json` are excluded from the claude-config
external and managed manually.

## First-time Setup

```sh
# 1. Install chezmoi
sh -c "$(curl -fsLS get.chezmoi.io)"

# 2. Initialize from this repo
chezmoi init git@github.com:dalpago/dotfiles.git

# 3. Clone private overlay (requires dalpago/dotfiles-private to exist)
git clone git@github.com:dalpago/dotfiles-private.git \
    ~/.local/share/chezmoi/.local

# 4. Apply
chezmoi apply
```

Always run `chezmoi diff` before `chezmoi apply` to review changes.

## Key Files

| File | Purpose |
|------|---------|
| `sync-staging.sh` | Pre-hook: merges public + private overlay into staging |
| `.chezmoi.toml.tmpl` | Chezmoi config template; sets sourceDir to staging |
| `.chezmoidata/packages.yaml` | All managed packages (base + categories) |
| `.chezmoiexternal.toml.tmpl` | External git/archive dependencies |
| `.chezmoiignore` | Files chezmoi must not manage (Claude runtime data) |
| `dot_zshrc.tmpl` | Zsh config: oh-my-zsh, starship, eza, bat, uv venv |
| `dot_config/starship.toml` | Starship prompt with Catppuccin Mocha palette |
| `dot_config/bat/config` | bat pager config with Catppuccin Mocha theme |

## Setup on a New Machine

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

# 4. Clone private overlay
git clone git@github.com:dalpago/dotfiles-private.git \
    ~/.local/share/chezmoi/.local

# 5. Re-apply to decrypt secrets and install all packages
chezmoi apply

# 6. Generate SSH keys (if not copying from another machine)
ssh-keygen -t ed25519 -C "daniele.alpago3@gmail.com" -f ~/.ssh/github-personal
ssh-keygen -t ed25519 -C "dalpago@swissblock.net" -f ~/.ssh/github-work
ssh-keygen -t ed25519 -C "dalpago@swissblock.net" -f ~/.ssh/csi-data

# 7. Add SSH keys to agent
ssh-add ~/.ssh/github-personal
ssh-add ~/.ssh/github-work
```

### WSL Ubuntu

```bash
# 1. Install chezmoi
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin

# 2. Install age
sudo apt update && sudo apt install -y age

# 3. Install zsh and oh-my-zsh dependencies
sudo apt install -y zsh git curl

# 4. Initialize dotfiles
~/.local/bin/chezmoi init --apply git@github.com:dalpago/dotfiles.git

# 5. Copy the age decryption key (transfer securely from Mac)
mkdir -p ~/.config/chezmoi
# Paste your age key into ~/.config/chezmoi/key.txt

# 6. Clone private overlay
git clone git@github.com:dalpago/dotfiles-private.git \
    ~/.local/share/chezmoi/.local

# 7. Re-apply to decrypt secrets and install all packages
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

# Commit and push
chezmoi cd && git add -A && git commit -m "Update dotfiles" && git push
```

## Secrets Management

Secrets are encrypted with [age](https://github.com/FiloSottile/age).

The age key must be transferred securely to new machines:
1. **Password Manager** - Copy from secure note
2. **Secure Copy** - `scp ~/.config/chezmoi/key.txt user@newmachine:~/.config/chezmoi/`
3. **Manual** - Display on old machine, type on new machine

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
