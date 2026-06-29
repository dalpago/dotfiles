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
