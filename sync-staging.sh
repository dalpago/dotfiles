#!/bin/bash
# chezmoi pre-hook: merge public source + private overlay into a staging dir
# that chezmoi reads from.
#
# Strategy: wipe-and-rebuild. Cheaper to reason about than incremental rsync
# with --delete, and at this scale (<1MB) the cost is negligible. Removed
# files in either layer disappear from staging on the next apply.
#
# Symlinks (not copies) are used for the secrets/ tree and the machine-local
# .chezmoi.toml.local so chezmoi reads live private content rather than a
# stale snapshot.

set -euo pipefail

PUBLIC_REPO="${CHEZMOI_PUBLIC_REPO:-$HOME/.local/share/chezmoi}"
LOCAL_OVERLAY="$PUBLIC_REPO/.local"
STAGING="${CHEZMOI_STAGING:-$HOME/.local/share/chezmoi-staging}"

rm -rf "$STAGING"
mkdir -p "$STAGING"

rsync --archive \
    --exclude='.git' --exclude='.git/**' \
    --exclude='.local' --exclude='.local/**' \
    "$PUBLIC_REPO/" "$STAGING/"

if [[ -d "$LOCAL_OVERLAY" ]]; then
    rsync --archive \
        --exclude='.git' --exclude='.git/**' \
        --exclude='secrets' --exclude='secrets/**' \
        --exclude='.chezmoi.toml.local' \
        "$LOCAL_OVERLAY/" "$STAGING/"
fi

if [[ -d "$LOCAL_OVERLAY/secrets" ]]; then
    mkdir -p "$STAGING/.local"
    ln -s "$LOCAL_OVERLAY/secrets" "$STAGING/.local/secrets"
fi

if [[ -f "$LOCAL_OVERLAY/.chezmoi.toml.local" ]]; then
    mkdir -p "$STAGING/.local"
    ln -s "$LOCAL_OVERLAY/.chezmoi.toml.local" "$STAGING/.local/.chezmoi.toml.local"
fi
