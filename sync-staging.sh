#!/bin/bash
set -euo pipefail

PUBLIC_REPO="${CHEZMOI_PUBLIC_REPO:-$HOME/.local/share/chezmoi}"
LOCAL_OVERLAY="$PUBLIC_REPO/.local"
STAGING="${CHEZMOI_STAGING:-$HOME/.local/share/chezmoi-staging}"

mkdir -p "$STAGING"

rsync --archive --delete \
    --exclude='.git' \
    --exclude='.git/**' \
    --exclude='.local' \
    --exclude='.local/**' \
    "$PUBLIC_REPO/" "$STAGING/"

if [[ -d "$LOCAL_OVERLAY" ]]; then
    rsync --archive \
        --exclude='.git' \
        --exclude='.git/**' \
        --exclude='secrets' \
        --exclude='secrets/**' \
        --exclude='.chezmoi.toml.local' \
        "$LOCAL_OVERLAY/" "$STAGING/"
fi

if [[ -d "$LOCAL_OVERLAY/secrets" ]]; then
    mkdir -p "$STAGING/.local"
    rm -rf "$STAGING/.local/secrets"
    ln -s "$LOCAL_OVERLAY/secrets" "$STAGING/.local/secrets"
fi

if [[ -f "$LOCAL_OVERLAY/.chezmoi.toml.local" ]]; then
    mkdir -p "$STAGING/.local"
    rm -f "$STAGING/.local/.chezmoi.toml.local"
    ln -s "$LOCAL_OVERLAY/.chezmoi.toml.local" "$STAGING/.local/.chezmoi.toml.local"
fi
