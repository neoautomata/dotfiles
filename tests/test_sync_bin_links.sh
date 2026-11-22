#!/usr/bin/env bash
set -euo pipefail

# Test run_after_sync-bin-links.sh.tmpl behavior across normal and edge cases.

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TMP_ROOT="$(mktemp -d)"
cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT; trap 'exit 130' INT; trap 'exit 143' TERM

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local actual="$1"
    local expected="$2"
    local message="$3"
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s (expected=%q, actual=%q)\n' "$message" "$expected" "$actual" >&2
        exit 1
    fi
}

RENDERED_SCRIPT="$TMP_ROOT/sync-bin-links.sh"
if command -v chezmoi >/dev/null 2>&1; then
    chezmoi execute-template < "$REPO_ROOT/run_after_sync-bin-links.sh.tmpl" > "$RENDERED_SCRIPT"
else
    # Strip template guard lines when chezmoi is unavailable.
    sed -e '/^{{- /d' -e "s|{{ \.chezmoi\.destDir }}|$TMP_ROOT|g" \
        "$REPO_ROOT/run_after_sync-bin-links.sh.tmpl" > "$RENDERED_SCRIPT"
fi
chmod +x "$RENDERED_SCRIPT"

# Source the script to invoke sync_bin_links directly in tests.
# shellcheck source=/dev/null
source "$RENDERED_SCRIPT"

# 1. Missing ~/bin directory exits cleanly without creating it.
MISSING_DIR="$TMP_ROOT/does_not_exist"
sync_bin_links "$MISSING_DIR"
[ ! -e "$MISSING_DIR" ] || fail "sync_bin_links should not create a missing bin directory."

# 2. Build a realistic ~/bin tree covering all link and skip conditions.
BIN_DIR="$TMP_ROOT/bin"
mkdir -p "$BIN_DIR/pkg_a" "$BIN_DIR/pkg_b" "$BIN_DIR/my tools" "$BIN_DIR/.hidden_dir" "$BIN_DIR/pkg_a/nested"

# Normal executable in pkg_a.
printf '#!/bin/sh\necho a\n' > "$BIN_DIR/pkg_a/tool_a"
chmod +x "$BIN_DIR/pkg_a/tool_a"

# Non-executable file in pkg_a (sync_bin_links skips it).
printf 'readme\n' > "$BIN_DIR/pkg_a/not_exec"

# Hidden executable in pkg_a (sync_bin_links skips it).
printf '#!/bin/sh\necho hidden\n' > "$BIN_DIR/pkg_a/.hidden_exec"
chmod +x "$BIN_DIR/pkg_a/.hidden_exec"

# Executable in hidden directory (sync_bin_links skips it).
printf '#!/bin/sh\necho git\n' > "$BIN_DIR/.hidden_dir/hook"
chmod +x "$BIN_DIR/.hidden_dir/hook"

# Executable at depth 3 (sync_bin_links skips it).
printf '#!/bin/sh\necho deep\n' > "$BIN_DIR/pkg_a/nested/deep_tool"
chmod +x "$BIN_DIR/pkg_a/nested/deep_tool"

# Executable with spaces in directory and filename.
printf '#!/bin/sh\necho space\n' > "$BIN_DIR/my tools/my script"
chmod +x "$BIN_DIR/my tools/my script"

# Basename collision between pkg_a and pkg_b.
printf '#!/bin/sh\necho first\n' > "$BIN_DIR/pkg_a/dup_tool"
chmod +x "$BIN_DIR/pkg_a/dup_tool"
printf '#!/bin/sh\necho second\n' > "$BIN_DIR/pkg_b/dup_tool"
chmod +x "$BIN_DIR/pkg_b/dup_tool"

# Existing regular file in ~/bin (sync_bin_links preserves it).
printf 'local regular file\n' > "$BIN_DIR/local_file"
printf '#!/bin/sh\necho sub\n' > "$BIN_DIR/pkg_a/local_file"
chmod +x "$BIN_DIR/pkg_a/local_file"

# Existing valid symlink in ~/bin pointing outside (sync_bin_links preserves it).
EXTERNAL_TARGET="$TMP_ROOT/external_tool"
printf '#!/bin/sh\necho ext\n' > "$EXTERNAL_TARGET"
chmod +x "$EXTERNAL_TARGET"
ln -s "$EXTERNAL_TARGET" "$BIN_DIR/valid_link"
printf '#!/bin/sh\necho sub_valid\n' > "$BIN_DIR/pkg_a/valid_link"
chmod +x "$BIN_DIR/pkg_a/valid_link"

# Broken symlink whose name matches a new executable (sync_bin_links updates it).
ln -s "$TMP_ROOT/gone_tool" "$BIN_DIR/relinked_tool"
printf '#!/bin/sh\necho relinked\n' > "$BIN_DIR/pkg_b/relinked_tool"
chmod +x "$BIN_DIR/pkg_b/relinked_tool"

# Broken symlink with no matching executable (sync_bin_links removes it).
ln -s "$TMP_ROOT/stale_gone" "$BIN_DIR/stale_link"

# Run sync_bin_links and capture stdout/stderr.
stderr_file="$TMP_ROOT/stderr.txt"
sync_bin_links "$BIN_DIR" 2>"$stderr_file" >/dev/null

# Verify expected symlinks exist and point to expected targets.
[ -L "$BIN_DIR/tool_a" ] || fail "sync_bin_links did not create tool_a symlink."
assert_eq "$(readlink "$BIN_DIR/tool_a")" "$BIN_DIR/pkg_a/tool_a" "tool_a symlink target"

[ -L "$BIN_DIR/my script" ] || fail "sync_bin_links did not create my script symlink."
assert_eq "$(readlink "$BIN_DIR/my script")" "$BIN_DIR/my tools/my script" "my script symlink target"

# Verify skipped entries do not exist in ~/bin.
[ ! -e "$BIN_DIR/not_exec" ] || fail "sync_bin_links must not link a non-executable file."
[ ! -e "$BIN_DIR/.hidden_exec" ] || fail "sync_bin_links must not link a hidden file."
[ ! -e "$BIN_DIR/hook" ] || fail "sync_bin_links must not link a file in a hidden directory."
[ ! -e "$BIN_DIR/deep_tool" ] || fail "sync_bin_links must not link a file at depth 3."

# Verify sync_bin_links preserves the regular file and valid symlink.
if [ -L "$BIN_DIR/local_file" ] || [ ! -f "$BIN_DIR/local_file" ]; then
    fail "sync_bin_links must preserve a regular file in ~/bin."
fi
assert_eq "$(cat "$BIN_DIR/local_file")" "local regular file" "sync_bin_links preserves regular file contents"
assert_eq "$(readlink "$BIN_DIR/valid_link")" "$EXTERNAL_TARGET" "sync_bin_links preserves valid symlink"

# Verify sync_bin_links updates the matched broken symlink and removes the stale broken symlink.
assert_eq "$(readlink "$BIN_DIR/relinked_tool")" "$BIN_DIR/pkg_b/relinked_tool" "sync_bin_links updates broken symlink"
[ ! -L "$BIN_DIR/stale_link" ] || fail "sync_bin_links must remove a stale broken symlink."

# Verify basename collision kept first match and emitted warning on stderr.
assert_eq "$(readlink "$BIN_DIR/dup_tool")" "$BIN_DIR/pkg_a/dup_tool" "collision keeps first executable"
grep -q 'Warning: skip duplicate executable' "$stderr_file" || fail "collision should warn on stderr."

# 3. Verify idempotency on second run.
second_out="$TMP_ROOT/second_stdout.txt"
sync_bin_links "$BIN_DIR" >"$second_out" 2>/dev/null
if grep -qE 'Created symlink:|Updated symlink:|Removed broken symlink:' "$second_out"; then
    fail "second run should not modify any symlinks."
fi

# 4. Verify direct script execution with positional bin_dir argument works.
BIN_DIR_2="$TMP_ROOT/bin2"
mkdir -p "$BIN_DIR_2/sub"
printf '#!/bin/sh\necho ok\n' > "$BIN_DIR_2/sub/cli"
chmod +x "$BIN_DIR_2/sub/cli"
"$RENDERED_SCRIPT" "$BIN_DIR_2" >/dev/null
assert_eq "$(readlink "$BIN_DIR_2/cli")" "$BIN_DIR_2/sub/cli" "direct invocation links executable"

# 5. Verify sync_bin_links preserves an existing directory at ~/bin/<name>.
DIR_COLLISION_BIN="$TMP_ROOT/bin_dir_collision"
mkdir -p "$DIR_COLLISION_BIN/existing_dir" "$DIR_COLLISION_BIN/pkg"
printf 'keep me\n' > "$DIR_COLLISION_BIN/existing_dir/marker.txt"
printf '#!/bin/sh\necho collide\n' > "$DIR_COLLISION_BIN/pkg/existing_dir"
chmod +x "$DIR_COLLISION_BIN/pkg/existing_dir"
sync_bin_links "$DIR_COLLISION_BIN" >/dev/null
if [ -L "$DIR_COLLISION_BIN/existing_dir" ] || [ ! -d "$DIR_COLLISION_BIN/existing_dir" ]; then
    fail "sync_bin_links must preserve an existing directory in ~/bin."
fi
assert_eq "$(cat "$DIR_COLLISION_BIN/existing_dir/marker.txt")" "keep me" "sync_bin_links preserves existing directory contents"

# 6. Verify leading-dash executable name and leading-dash relative bin_dir work cleanly.
DASH_WORK="$TMP_ROOT/dash_work"
mkdir -p "$DASH_WORK/-bin/sub"
printf '#!/bin/sh\necho dash\n' > "$DASH_WORK/-bin/sub/-tool"
chmod +x "$DASH_WORK/-bin/sub/-tool"
ln -s "$TMP_ROOT/missing_dash_target" "$DASH_WORK/-bin/-broken"
(
    cd "$DASH_WORK"
    sync_bin_links "-bin" >/dev/null
)
[ -L "$DASH_WORK/-bin/-tool" ] || fail "sync_bin_links did not create the leading-dash executable symlink."
[ -e "$DASH_WORK/-bin/-tool" ] || fail "leading-dash executable symlink must resolve to a valid target."
assert_eq "$(readlink -- "$DASH_WORK/-bin/-tool")" "$DASH_WORK/-bin/sub/-tool" "leading-dash executable symlink target"
[ ! -L "$DASH_WORK/-bin/-broken" ] || fail "sync_bin_links must remove a leading-dash broken symlink."

# 7. Verify symlinked ~/bin directory works cleanly.
REAL_BIN="$TMP_ROOT/real_bin_target"
LINKED_BIN="$TMP_ROOT/symlinked_bin"
mkdir -p "$REAL_BIN/pkg"
printf '#!/bin/sh\necho linked\n' > "$REAL_BIN/pkg/linked_tool"
chmod +x "$REAL_BIN/pkg/linked_tool"
ln -s "$TMP_ROOT/stale_in_linked_bin" "$REAL_BIN/stale_linked"
ln -s "$REAL_BIN" "$LINKED_BIN"
sync_bin_links "$LINKED_BIN" >/dev/null
[ -L "$LINKED_BIN/linked_tool" ] || fail "sync_bin_links must create executable symlink in symlinked ~/bin."
[ -e "$LINKED_BIN/linked_tool" ] || fail "symlink in symlinked ~/bin must resolve to a valid target."
[ ! -L "$LINKED_BIN/stale_linked" ] || fail "sync_bin_links must remove broken symlinks in symlinked ~/bin."

# 8. Verify CDPATH does not corrupt relative bin_dir resolution.
CDPATH_WORK="$TMP_ROOT/cdpath_work"
mkdir -p "$CDPATH_WORK/mybin/sub"
printf '#!/bin/sh\necho cdpath\n' > "$CDPATH_WORK/mybin/sub/cdtool"
chmod +x "$CDPATH_WORK/mybin/sub/cdtool"
(
    cd "$CDPATH_WORK"
    CDPATH=".:/tmp" sync_bin_links "mybin" >/dev/null
)
[ -L "$CDPATH_WORK/mybin/cdtool" ] || fail "sync_bin_links did not create symlink when CDPATH is set."
assert_eq "$(readlink -- "$CDPATH_WORK/mybin/cdtool")" "$CDPATH_WORK/mybin/sub/cdtool" "CDPATH relative bin_dir symlink target"

printf 'All sync-bin-links tests passed.\n'
