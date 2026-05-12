#!/bin/bash
# chezmoi pre-hook: bi-directional merge between public source + private
# overlay and a staging dir that chezmoi reads from.
#
# v2: symlink-tree staging + propagation of writes back to canonical.
#
# Read path (chezmoi -> staging -> canonical):
#   staging/<rel> is a SYMLINK to either $PUBLIC_REPO/<rel> or $LOCAL_OVERLAY/<rel>
#   so chezmoi-edit / cat / diff all see canonical content live.
#
# Write path (chezmoi add / re-add):
#   chezmoi atomically renames into staging/<rel>, replacing the symlink with
#   a regular file. On the next read, this hook runs first: it detects the
#   regular file, copies it back to the appropriate canonical source, then
#   wipes staging and rebuilds the symlink mirror.
#
# Conflict resolution for `rel`:
#   1. Special path: `<basename>` at staging root matching $LOCAL_OVERLAY/secrets/<basename>
#      -> propagate to $LOCAL_OVERLAY/secrets/<basename>
#   2. Special path: `.local/.chezmoi.toml.local` -> $LOCAL_OVERLAY/.chezmoi.toml.local
#   3. If $LOCAL_OVERLAY/<rel> exists -> private wins
#   4. Else if $PUBLIC_REPO/<rel> exists -> public
#   5. Else (new file): if `rel` matches a private pattern (encrypted_*.age,
#      private_*, secrets/*) -> warn + skip (user must edit canonical directly);
#      else create in $PUBLIC_REPO/<rel>.
#
# Symlinks (not copies) are used uniformly so chezmoi-edit writes propagate
# to canonical transparently via the $EDITOR's follow-symlink semantics.

{
set -euo pipefail

PUBLIC_REPO="${CHEZMOI_PUBLIC_REPO:-$HOME/.local/share/chezmoi}"
LOCAL_OVERLAY="$PUBLIC_REPO/.local"
STAGING="${CHEZMOI_STAGING:-$HOME/.local/share/chezmoi-staging}"

# Resolve the canonical path of this script so we can avoid propagating
# over ourselves mid-execution (would cause bash to read past EOF and
# silently exit before the wipe+rebuild phase). The whole script body is
# wrapped in { } as a second-layer guard against the same hazard.
SELF_CANONICAL="$PUBLIC_REPO/sync-staging.sh"

log() { printf '[sync-staging] %s\n' "$*" >&2; }

is_private_only_pattern() {
    local rel="$1"
    case "$rel" in
        encrypted_*.age|secrets/*|*.gpg) return 0 ;;
        private_dot_ssh/encrypted_*|.chezmoi.toml.local) return 0 ;;
        .local/*) return 0 ;;
    esac
    return 1
}

resolve_canonical() {
    local rel="$1"
    local base
    base=$(basename "$rel")

    if [[ "$rel" != */* ]] && [[ -e "$LOCAL_OVERLAY/secrets/$base" ]]; then
        echo "$LOCAL_OVERLAY/secrets/$base"
        return 0
    fi
    if [[ "$rel" == ".local/.chezmoi.toml.local" ]]; then
        echo "$LOCAL_OVERLAY/.chezmoi.toml.local"
        return 0
    fi
    if [[ -e "$LOCAL_OVERLAY/$rel" ]]; then
        echo "$LOCAL_OVERLAY/$rel"
        return 0
    fi
    if [[ -e "$PUBLIC_REPO/$rel" ]]; then
        echo "$PUBLIC_REPO/$rel"
        return 0
    fi
    if is_private_only_pattern "$rel"; then
        return 1
    fi
    echo "$PUBLIC_REPO/$rel"
    return 0
}

propagate_from_staging() {
    [[ -d "$STAGING" ]] || return 0
    local staging_path rel canonical
    while IFS= read -r -d '' staging_path; do
        [[ -L "$staging_path" ]] && continue
        [[ -f "$staging_path" ]] || continue
        rel="${staging_path#$STAGING/}"
        if ! canonical=$(resolve_canonical "$rel"); then
            log "skipping (unresolvable private pattern, edit canonical directly): $rel"
            continue
        fi
        if [[ "$canonical" == "$SELF_CANONICAL" ]]; then
            continue
        fi
        if [[ ! -e "$canonical" ]]; then
            mkdir -p "$(dirname "$canonical")"
            cp -p "$staging_path" "$canonical"
            log "new file -> $canonical"
            continue
        fi
        if ! cmp -s "$staging_path" "$canonical"; then
            cp -p "$staging_path" "$canonical"
            log "propagated -> $canonical"
        fi
    done < <(find "$STAGING" -type f -print0)
}

symlink_tree() {
    local src="$1"
    shift
    local pruned=("$@")
    local find_args=()
    local p
    for p in "${pruned[@]}"; do
        find_args+=(-path "$src/$p" -prune -o)
    done
    local entry rel
    while IFS= read -r -d '' entry; do
        [[ "$entry" == "$src" ]] && continue
        rel="${entry#$src/}"
        if [[ -d "$entry" ]]; then
            mkdir -p "$STAGING/$rel"
        elif [[ -f "$entry" ]]; then
            ln -sf "$entry" "$STAGING/$rel"
        fi
    done < <(find "$src" "${find_args[@]}" \( -type d -o -type f \) -print0)
}

propagate_from_staging

rm -rf "$STAGING"
mkdir -p "$STAGING"

symlink_tree "$PUBLIC_REPO" .git .local

if [[ -d "$LOCAL_OVERLAY" ]]; then
    symlink_tree "$LOCAL_OVERLAY" .git secrets .chezmoi.toml.local
fi

if [[ -d "$LOCAL_OVERLAY/secrets" ]]; then
    for f in "$LOCAL_OVERLAY/secrets"/*; do
        [[ -e "$f" ]] || continue
        ln -sf "$f" "$STAGING/$(basename "$f")"
    done
fi

if [[ -f "$LOCAL_OVERLAY/.chezmoi.toml.local" ]]; then
    mkdir -p "$STAGING/.local"
    ln -s "$LOCAL_OVERLAY/.chezmoi.toml.local" "$STAGING/.local/.chezmoi.toml.local"
fi
}
