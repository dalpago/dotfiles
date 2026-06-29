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
    # Capital X preserves the executable bit where it already exists (e.g. the
    # sync-staging.sh pre-hook), so we strip only the group-write bit. A plain
    # 644 would break executable scripts and, for the pre-hook, chezmoi itself.
    find "$repo" -path '*/.git' -prune -o -type f -print0 \
        | xargs -0 chmod u=rwX,go=rX
done
echo "Done. Verify with: ls -ld <repo> (expect drwxr-xr-x, no 's')."
