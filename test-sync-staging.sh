#!/bin/bash
# Test harness for sync-staging.sh.
#
# Builds a synthetic public+private layout in /tmp and runs the merge
# script against it, asserting correct behavior across all scenarios:
# fresh build, re-add propagation (public/private/secrets), new-file
# creation, private-pattern detection, conflict resolution, missing
# overlay, and the self-modifying-script guard.
#
# Override the script under test with:
#   SYNC_STAGING_SCRIPT=/path/to/sync-staging.sh bash test-sync-staging.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="${TEST_ROOT:-/tmp/chezmoi-merge-test}"
SCRIPT="${SYNC_STAGING_SCRIPT:-$HERE/sync-staging.sh}"

PUBLIC="$TEST_ROOT/public"
PRIVATE="$PUBLIC/.local"
STAGING="$TEST_ROOT/staging"

PASS=0
FAIL=0
assert() {
    local desc="$1"; shift
    if "$@"; then
        echo "  PASS: $desc"
        PASS=$((PASS+1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL+1))
    fi
}

setup_layout() {
    rm -rf "$TEST_ROOT"
    mkdir -p "$PUBLIC/dot_config/nvim" "$PUBLIC/.chezmoidata"
    mkdir -p "$PRIVATE/secrets" "$PRIVATE/private_dot_ssh" "$PRIVATE/.chezmoidata"

    echo "zshrc original" > "$PUBLIC/dot_zshrc.tmpl"
    echo "bashrc original" > "$PUBLIC/dot_bashrc"
    echo "init.lua original" > "$PUBLIC/dot_config/nvim/init.lua"
    echo "packages original" > "$PUBLIC/.chezmoidata/packages.yaml"

    echo "ENCRYPTED_SECRETS_BLOB" > "$PRIVATE/secrets/encrypted_private_dot_secrets.age"
    echo "ENCRYPTED_NETRC_BLOB" > "$PRIVATE/encrypted_private_dot_netrc.age"
    echo "ENCRYPTED_SSH_KEY" > "$PRIVATE/private_dot_ssh/encrypted_github-work.age"
    echo "local config" > "$PRIVATE/.chezmoi.toml.local"
    echo "local data" > "$PRIVATE/.chezmoidata/local.yaml"
}

run_sync() {
    CHEZMOI_PUBLIC_REPO="$PUBLIC" CHEZMOI_STAGING="$STAGING" \
        HOME="$TEST_ROOT/fake-home" \
        bash "$SCRIPT" 2>&1
}

echo "==========================================="
echo "TEST 1: Fresh staging build"
echo "==========================================="
setup_layout
run_sync >/dev/null

assert "dot_zshrc.tmpl is symlink to public" \
    test -L "$STAGING/dot_zshrc.tmpl"
assert "dot_zshrc.tmpl symlink points to public canonical" \
    bash -c "[ \"\$(readlink \"$STAGING/dot_zshrc.tmpl\")\" = \"$PUBLIC/dot_zshrc.tmpl\" ]"
assert "dot_bashrc is symlink to public" \
    test -L "$STAGING/dot_bashrc"
assert "dot_config/nvim/init.lua is symlink" \
    test -L "$STAGING/dot_config/nvim/init.lua"
assert ".chezmoidata/packages.yaml is symlink to public" \
    bash -c "[ \"\$(readlink \"$STAGING/.chezmoidata/packages.yaml\")\" = \"$PUBLIC/.chezmoidata/packages.yaml\" ]"
assert ".chezmoidata/local.yaml is symlink to private" \
    bash -c "[ \"\$(readlink \"$STAGING/.chezmoidata/local.yaml\")\" = \"$PRIVATE/.chezmoidata/local.yaml\" ]"
assert "encrypted_private_dot_netrc.age is symlink to private" \
    bash -c "[ \"\$(readlink \"$STAGING/encrypted_private_dot_netrc.age\")\" = \"$PRIVATE/encrypted_private_dot_netrc.age\" ]"
assert "private_dot_ssh/encrypted_github-work.age is symlink" \
    test -L "$STAGING/private_dot_ssh/encrypted_github-work.age"
assert "secrets file is at staging root (special-cased)" \
    test -L "$STAGING/encrypted_private_dot_secrets.age"
assert "secrets file symlink points to private/secrets/" \
    bash -c "[ \"\$(readlink \"$STAGING/encrypted_private_dot_secrets.age\")\" = \"$PRIVATE/secrets/encrypted_private_dot_secrets.age\" ]"
assert ".local/.chezmoi.toml.local symlink exists" \
    test -L "$STAGING/.local/.chezmoi.toml.local"
assert ".local/.chezmoi.toml.local symlink points to private root" \
    bash -c "[ \"\$(readlink \"$STAGING/.local/.chezmoi.toml.local\")\" = \"$PRIVATE/.chezmoi.toml.local\" ]"
assert "no .git in staging from public" \
    bash -c "[ ! -e \"$STAGING/.git\" ]"
assert "no secrets/ directory in staging" \
    bash -c "[ ! -d \"$STAGING/secrets\" ]"

echo ""
echo "==========================================="
echo "TEST 2: Re-add propagation (public file)"
echo "==========================================="
setup_layout
run_sync >/dev/null
rm "$STAGING/dot_zshrc.tmpl"
echo "zshrc MODIFIED by re-add" > "$STAGING/dot_zshrc.tmpl"

run_sync

assert "canonical public file updated by propagation" \
    bash -c "[ \"\$(cat \"$PUBLIC/dot_zshrc.tmpl\")\" = \"zshrc MODIFIED by re-add\" ]"
assert "staging file is again a symlink after rebuild" \
    test -L "$STAGING/dot_zshrc.tmpl"
assert "staging symlink resolves to updated content" \
    bash -c "[ \"\$(cat \"$STAGING/dot_zshrc.tmpl\")\" = \"zshrc MODIFIED by re-add\" ]"

echo ""
echo "==========================================="
echo "TEST 3: Re-add propagation (private overlay file)"
echo "==========================================="
setup_layout
run_sync >/dev/null
rm "$STAGING/encrypted_private_dot_netrc.age"
echo "NETRC_MODIFIED_BLOB" > "$STAGING/encrypted_private_dot_netrc.age"

run_sync

assert "private overlay netrc updated by propagation" \
    bash -c "[ \"\$(cat \"$PRIVATE/encrypted_private_dot_netrc.age\")\" = \"NETRC_MODIFIED_BLOB\" ]"
assert "public is untouched (no spurious propagation)" \
    bash -c "[ ! -e \"$PUBLIC/encrypted_private_dot_netrc.age\" ]"
assert "staging file is again a symlink to private" \
    bash -c "[ \"\$(readlink \"$STAGING/encrypted_private_dot_netrc.age\")\" = \"$PRIVATE/encrypted_private_dot_netrc.age\" ]"

echo ""
echo "==========================================="
echo "TEST 4: Re-add propagation (secrets special-case)"
echo "==========================================="
setup_layout
run_sync >/dev/null
rm "$STAGING/encrypted_private_dot_secrets.age"
echo "SECRETS_MODIFIED_BLOB" > "$STAGING/encrypted_private_dot_secrets.age"

run_sync

assert "secrets canonical (in .local/secrets/) updated" \
    bash -c "[ \"\$(cat \"$PRIVATE/secrets/encrypted_private_dot_secrets.age\")\" = \"SECRETS_MODIFIED_BLOB\" ]"
assert "secrets staging file is again a symlink to private/secrets/" \
    bash -c "[ \"\$(readlink \"$STAGING/encrypted_private_dot_secrets.age\")\" = \"$PRIVATE/secrets/encrypted_private_dot_secrets.age\" ]"

echo ""
echo "==========================================="
echo "TEST 5: New file (chezmoi add of unmanaged file, public)"
echo "==========================================="
setup_layout
run_sync >/dev/null
echo "new file content" > "$STAGING/dot_newfile"

run_sync

assert "new file created in public canonical" \
    test -f "$PUBLIC/dot_newfile"
assert "new file content correct" \
    bash -c "[ \"\$(cat \"$PUBLIC/dot_newfile\")\" = \"new file content\" ]"
assert "staging file now a symlink to public" \
    bash -c "[ \"\$(readlink \"$STAGING/dot_newfile\")\" = \"$PUBLIC/dot_newfile\" ]"

echo ""
echo "==========================================="
echo "TEST 6: New private-pattern file is warned + skipped"
echo "==========================================="
setup_layout
run_sync >/dev/null
echo "would be a secret" > "$STAGING/encrypted_private_dot_newsecret.age"

OUTPUT=$(run_sync 2>&1)

assert "no spurious creation in public" \
    bash -c "[ ! -e \"$PUBLIC/encrypted_private_dot_newsecret.age\" ]"
assert "no spurious creation in private root" \
    bash -c "[ ! -e \"$PRIVATE/encrypted_private_dot_newsecret.age\" ]"
assert "no spurious creation in private/secrets/" \
    bash -c "[ ! -e \"$PRIVATE/secrets/encrypted_private_dot_newsecret.age\" ]"
assert "warning message present" \
    bash -c "echo \"$OUTPUT\" | grep -q 'unresolvable private pattern'"

echo ""
echo "==========================================="
echo "TEST 7: Direct canonical edit (no propagation needed)"
echo "==========================================="
setup_layout
run_sync >/dev/null
echo "directly edited canonical" > "$PUBLIC/dot_zshrc.tmpl"

run_sync

assert "canonical content preserved (not clobbered)" \
    bash -c "[ \"\$(cat \"$PUBLIC/dot_zshrc.tmpl\")\" = \"directly edited canonical\" ]"
assert "staging symlink reflects new canonical content" \
    bash -c "[ \"\$(cat \"$STAGING/dot_zshrc.tmpl\")\" = \"directly edited canonical\" ]"

echo ""
echo "==========================================="
echo "TEST 8: Conflict — file in both, private wins"
echo "==========================================="
setup_layout
echo "public version" > "$PUBLIC/dot_conflictfile"
echo "private version" > "$PRIVATE/dot_conflictfile"
run_sync >/dev/null

assert "private version is the active symlink target" \
    bash -c "[ \"\$(readlink \"$STAGING/dot_conflictfile\")\" = \"$PRIVATE/dot_conflictfile\" ]"
assert "reading through staging shows private content" \
    bash -c "[ \"\$(cat \"$STAGING/dot_conflictfile\")\" = \"private version\" ]"

# Now re-add this conflict file → should write to private (winner)
rm "$STAGING/dot_conflictfile"
echo "re-add MODIFIED content" > "$STAGING/dot_conflictfile"
run_sync

assert "re-add propagated to PRIVATE (the winner)" \
    bash -c "[ \"\$(cat \"$PRIVATE/dot_conflictfile\")\" = \"re-add MODIFIED content\" ]"
assert "PUBLIC was NOT clobbered" \
    bash -c "[ \"\$(cat \"$PUBLIC/dot_conflictfile\")\" = \"public version\" ]"

echo ""
echo "==========================================="
echo "TEST 9: Missing private overlay (fresh-bootstrap, public-only)"
echo "==========================================="
rm -rf "$TEST_ROOT"
mkdir -p "$PUBLIC"
echo "zshrc only-public" > "$PUBLIC/dot_zshrc.tmpl"

run_sync

assert "staging built successfully without overlay" \
    test -L "$STAGING/dot_zshrc.tmpl"
assert "no private content in staging" \
    bash -c "[ ! -e \"$STAGING/encrypted_private_dot_secrets.age\" ]"
assert "no .local in staging" \
    bash -c "[ ! -e \"$STAGING/.local\" ]"

echo ""
echo "==========================================="
echo "TEST 10: Self-modifying script guard"
echo "==========================================="
# Regression test for the bash-reads-script-line-by-line gotcha:
# When sync-staging.sh lives inside the public repo it manages, and an
# older copy sits in staging (e.g. after a sync-staging.sh content change
# committed manually), the propagation phase used to copy the OLD staging
# version over the NEW canonical, silently reverting itself. The script
# now (a) excludes its own canonical path from propagation and (b) wraps
# the body in { ... } so bash parses the whole script up-front.
setup_layout
# Place an OLD-looking version of sync-staging.sh in public so the script
# being managed includes a different version of itself in staging.
cp "$SCRIPT" "$PUBLIC/sync-staging.sh"
run_sync >/dev/null
# Now corrupt staging to simulate a stale rsync copy
rm "$STAGING/sync-staging.sh"
echo "VERY DIFFERENT OLD CONTENT" > "$STAGING/sync-staging.sh"

# Modify canonical to simulate a "freshly deployed" new version
echo "FRESHLY DEPLOYED NEW VERSION" > "$PUBLIC/sync-staging.sh"

run_sync >/dev/null

assert "canonical sync-staging.sh was NOT overwritten by stale staging" \
    bash -c "[ \"\$(cat \"$PUBLIC/sync-staging.sh\")\" = \"FRESHLY DEPLOYED NEW VERSION\" ]"
assert "staging was wiped and rebuilt (symlink restored)" \
    test -L "$STAGING/sync-staging.sh"
assert "staging symlink points to canonical" \
    bash -c "[ \"\$(readlink \"$STAGING/sync-staging.sh\")\" = \"$PUBLIC/sync-staging.sh\" ]"

echo ""
echo "==========================================="
echo "TEST SUMMARY"
echo "==========================================="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
exit $FAIL
