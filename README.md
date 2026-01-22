# Dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## Quick Reference

| Machine | Shell | Config Location |
|---------|-------|-----------------|
| macOS | zsh | `~/.zshrc` |
| WSL Ubuntu | zsh | `~/.zshrc` |

---

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
# The key starts with: AGE-SECRET-KEY-...

# 4. Re-apply to decrypt secrets
chezmoi apply

# 5. Generate SSH keys (if not copying from another machine)
ssh-keygen -t ed25519 -C "daniele.alpago3@gmail.com" -f ~/.ssh/github-personal
ssh-keygen -t ed25519 -C "dalpago@swissblock.net" -f ~/.ssh/github-work
ssh-keygen -t ed25519 -C "dalpago@swissblock.net" -f ~/.ssh/csi-data

# 6. Add SSH keys to agent
ssh-add ~/.ssh/github-personal
ssh-add ~/.ssh/github-work

# 7. Add public keys to GitHub
cat ~/.ssh/github-personal.pub  # Add to github.com/settings/keys (dalpago)
cat ~/.ssh/github-work.pub      # Add to github.com/settings/keys (dalpago-sbt)
```

### WSL Ubuntu

```bash
# 1. Install chezmoi
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin

# 2. Install age
sudo apt update && sudo apt install -y age

# 3. Install zsh and oh-my-zsh dependencies
sudo apt install -y zsh git curl

# 4. Initialize dotfiles (oh-my-zsh will be installed automatically)
~/.local/bin/chezmoi init --apply git@github.com:dalpago/dotfiles.git

# 5. Copy the age decryption key (transfer securely from Mac)
mkdir -p ~/.config/chezmoi
# Paste your age key into ~/.config/chezmoi/key.txt

# 6. Re-apply to decrypt secrets
chezmoi apply

# 7. Set zsh as default shell
chsh -s $(which zsh)

# 8. Generate SSH keys (or copy from Mac)
ssh-keygen -t ed25519 -C "daniele.alpago3@gmail.com" -f ~/.ssh/github-personal
ssh-keygen -t ed25519 -C "dalpago@swissblock.net" -f ~/.ssh/github-work
ssh-keygen -t ed25519 -C "dalpago@swissblock.net" -f ~/.ssh/csi-data

# 9. Start ssh-agent and add keys
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/github-personal
ssh-add ~/.ssh/github-work

# 10. Add public keys to GitHub (same keys as Mac, or new ones)
cat ~/.ssh/github-personal.pub
cat ~/.ssh/github-work.pub
```

---

## Daily Workflow

### macOS

```bash
# Edit a dotfile (opens in editor, updates chezmoi source)
chezmoi edit ~/.zshrc

# Preview changes before applying
chezmoi diff

# Apply changes to home directory
chezmoi apply

# Commit and push changes to GitHub
chezmoi cd && git add -A && git commit -m "Update dotfiles" && git push
```

### WSL Ubuntu

```bash
# Same workflow as macOS!
chezmoi edit ~/.zshrc
chezmoi diff
chezmoi apply
chezmoi cd && git add -A && git commit -m "Update dotfiles" && git push
```

### Pulling Changes (from another machine)

```bash
# Pull latest dotfiles from GitHub and apply
chezmoi update
```

---

## Useful Commands

| Command | Description |
|---------|-------------|
| `chezmoi diff` | Preview changes before applying |
| `chezmoi apply` | Apply dotfiles to home directory |
| `chezmoi update` | Pull from GitHub and apply |
| `chezmoi edit ~/.zshrc` | Edit a dotfile |
| `chezmoi cd` | Enter chezmoi source directory |
| `chezmoi managed` | List all managed files |
| `chezmoi add ~/.config/app/config` | Add a new file to chezmoi |
| `chezmoi add --encrypt ~/.secrets` | Add encrypted file |
| `chezmoi forget ~/.file` | Stop managing a file |

---

## File Structure

```
~/.local/share/chezmoi/           # chezmoi source directory
├── .chezmoi.toml.tmpl            # Machine-specific config template
├── .chezmoiexternal.toml         # External dependencies (oh-my-zsh)
├── .chezmoiignore                # Files to ignore per OS
├── dot_zshrc.tmpl                # ~/.zshrc template
├── dot_gitconfig.tmpl            # ~/.gitconfig template
├── dot_gitignore-global          # ~/.gitignore-global
├── encrypted_private_dot_secrets.age  # Encrypted API keys
└── private_dot_ssh/
    └── config.tmpl               # ~/.ssh/config template
```

### Naming Conventions

| Prefix | Meaning | Example |
|--------|---------|---------|
| `dot_` | Becomes `.` | `dot_zshrc` → `.zshrc` |
| `private_` | Set 600 permissions | `private_dot_ssh` → `.ssh` (mode 600) |
| `encrypted_` | Encrypted with age | Decrypted on apply |
| `.tmpl` | Template file | Processed with Go templates |

---

## SSH Configuration

### Hosts

| Host | Account | Key |
|------|---------|-----|
| `github.com` | dalpago (personal) | `~/.ssh/github-personal` |
| `github-work` | dalpago-sbt (work) | `~/.ssh/github-work` |
| `ftp.csidata.com` | CSI Data | `~/.ssh/csi-data` |

### Cloning Work Repos

```bash
# Use the github-work alias for work repositories
git clone github-work:dalpago-sbt/repo-name.git

# Or change remote for existing repo
git remote set-url origin github-work:dalpago-sbt/repo-name.git
```

---

## Secrets Management

Secrets are encrypted with [age](https://github.com/FiloSottile/age) encryption.

### Adding a New Secret

```bash
# Edit the secrets file
chezmoi edit ~/.secrets

# Add your secret
export NEW_API_KEY="..."

# Save and apply
chezmoi apply

# Commit (the file is encrypted in the repo)
chezmoi cd && git add -A && git commit -m "Add new secret" && git push
```

### Transferring Age Key to New Machine

The age key must be transferred securely (it's the only way to decrypt secrets):

1. **Option A: Password Manager** - Copy from secure note
2. **Option B: Secure Copy** - `scp ~/.config/chezmoi/key.txt user@newmachine:~/.config/chezmoi/`
3. **Option C: Manual** - Display on old machine, type on new machine

```bash
# On old machine - display key
cat ~/.config/chezmoi/key.txt

# On new machine - create key file
mkdir -p ~/.config/chezmoi
nano ~/.config/chezmoi/key.txt  # Paste the key
chmod 600 ~/.config/chezmoi/key.txt
```

---

## Troubleshooting

### SSH Permission Denied

```bash
# Check which account you're authenticating as
ssh -T git@github.com
ssh -T github-work

# List keys in agent
ssh-add -l

# Add keys if missing
ssh-add ~/.ssh/github-personal
ssh-add ~/.ssh/github-work
```

### Template Errors

```bash
# Check template syntax
chezmoi execute-template < ~/.local/share/chezmoi/dot_zshrc.tmpl

# View generated output
chezmoi cat ~/.zshrc
```

### Reset to Clean State

```bash
# Remove all chezmoi-managed files (careful!)
chezmoi purge

# Re-apply everything
chezmoi apply
```
