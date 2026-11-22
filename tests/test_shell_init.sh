#!/usr/bin/env bash
# shellcheck disable=SC2016
# Single-quoted sh/bash -c payloads intentionally expand variables inside the child shell.
set -euo pipefail

# Test dot_bashrc and dot_profile behavior across interactive and non-interactive shells.

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TMP_ROOT="$(mktemp -d)"
cleanup() {
    chmod -R u+rwx "$TMP_ROOT" 2>/dev/null || true
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

# 1. Verify dot_profile adds ~/bin to PATH in non-interactive shells and deduplicates it.
HOME_1="$TMP_ROOT/home1"
mkdir -p "$HOME_1/bin" "$HOME_1/.profile.d"
cp "$REPO_ROOT/dot_profile" "$HOME_1/.profile"
cp "$REPO_ROOT/dot_bashrc" "$HOME_1/.bashrc"
printf 'HOOK_RAN=yes\n' > "$HOME_1/.profile.d/01-hook.sh"

out="$(env -i HOME="$HOME_1" PATH="/usr/bin:/bin" sh -c '. "$HOME/.profile"; . "$HOME/.profile"; printf "%s|%s|%s|%s" "$PATH" "${HOOK_RAN:-no}" "${DEBUG-unset}" "${profile_file-unset}"')"
assert_eq "$out" "$HOME_1/bin:/usr/bin:/bin|no|unset|unset" "dot_profile non-interactive PATH, dedupe, and env hygiene"

# 2. Verify dot_profile skips ~/bin when ~/bin does not exist.
HOME_2="$TMP_ROOT/home2"
mkdir -p "$HOME_2"
cp "$REPO_ROOT/dot_profile" "$HOME_2/.profile"

out="$(env -i HOME="$HOME_2" PATH="/usr/bin:/bin" sh -c '. "$HOME/.profile"; printf "%s" "$PATH"')"
assert_eq "$out" "/usr/bin:/bin" "dot_profile omits missing ~/bin from PATH"

# 3. Verify dot_bashrc loads ~/.profile when readable and succeeds when ~/.profile is missing.
out="$(env -i HOME="$HOME_1" PATH="/usr/bin:/bin" bash -c '. "$HOME/.bashrc"; printf "%s" "$PATH"')"
assert_eq "$out" "$HOME_1/bin:/usr/bin:/bin" "dot_bashrc sources readable ~/.profile"

HOME_NO_PROFILE="$TMP_ROOT/home_no_profile"
mkdir -p "$HOME_NO_PROFILE"
cp "$REPO_ROOT/dot_bashrc" "$HOME_NO_PROFILE/.bashrc"
env -i HOME="$HOME_NO_PROFILE" PATH="/usr/bin:/bin" bash -c '. "$HOME/.bashrc"' || fail "dot_bashrc should succeed when ~/.profile is missing."

# 4. Verify interactive shell loads ~/.profile.d/*.sh including spaces, skips unreadable files and *.sh dirs.
HOME_3="$TMP_ROOT/home3"
mkdir -p "$HOME_3/bin" "$HOME_3/.profile.d/not a file.sh"
cp "$REPO_ROOT/dot_profile" "$HOME_3/.profile"
printf 'FIRST_HOOK="loaded"\n' > "$HOME_3/.profile.d/01 basic.sh"
printf 'SECOND_HOOK="loaded"\n' > "$HOME_3/.profile.d/02_second.sh"
printf 'UNREADABLE_HOOK="loaded"\n' > "$HOME_3/.profile.d/03_unreadable.sh"
chmod 000 "$HOME_3/.profile.d/03_unreadable.sh"

out="$(env -i HOME="$HOME_3" PATH="/usr/bin:/bin" bash -i -c '. "$HOME/.profile"; printf "%s|%s|%s" "${FIRST_HOOK:-no}" "${SECOND_HOOK:-no}" "${UNREADABLE_HOOK:-no}"' 2>/dev/null)"
assert_eq "$out" "loaded|loaded|no" "interactive dot_profile loads readable hooks with spaces and skips unreadable files"

# 5. Verify interactive shell with empty ~/.profile.d succeeds cleanly.
HOME_4="$TMP_ROOT/home4"
mkdir -p "$HOME_4/.profile.d"
cp "$REPO_ROOT/dot_profile" "$HOME_4/.profile"
env -i HOME="$HOME_4" PATH="/usr/bin:/bin" bash -i -c '. "$HOME/.profile"' 2>/dev/null || fail "interactive dot_profile should succeed with empty ~/.profile.d."

# 6. Verify PROGNAME prevents interactive hooks from loading.
out="$(env -i HOME="$HOME_3" PATH="/usr/bin:/bin" PROGNAME="testprog" bash -i -c '. "$HOME/.profile"; printf "%s" "${FIRST_HOOK:-no}"' 2>/dev/null)"
assert_eq "$out" "no" "PROGNAME skips interactive ~/.profile.d hooks"

# 7. Verify realpath fallback works when realpath binary is absent from PATH.
FAKE_BIN="$TMP_ROOT/fake_bin"
mkdir -p "$FAKE_BIN"
PERL_PATH="$(command -v perl)"
ln -s "$PERL_PATH" "$FAKE_BIN/perl"
TARGET_DIR="$TMP_ROOT/real_target"
mkdir -p "$TARGET_DIR"
printf 'ok\n' > "$TARGET_DIR/file.txt"
ln -s "$TARGET_DIR/file.txt" "$TMP_ROOT/link.txt"

resolved="$(env -i HOME="$HOME_1" PATH="$FAKE_BIN" /bin/sh -c '. "$HOME/.profile"; realpath "$1"' -- "$TMP_ROOT/link.txt")"
expected_real="$(perl -MCwd=abs_path -e 'print abs_path($ARGV[0])' "$TARGET_DIR/file.txt")"
assert_eq "$resolved" "$expected_real" "realpath fallback resolves symlinks via perl"

if env -i HOME="$HOME_1" PATH="$FAKE_BIN" /bin/sh -c '. "$HOME/.profile"; realpath' 2>/dev/null; then
    fail "realpath fallback should fail when called with no arguments."
fi

if env -i HOME="$HOME_1" PATH="$FAKE_BIN" /bin/sh -c '. "$HOME/.profile"; realpath ""' 2>/dev/null; then
    fail "realpath fallback should fail when called with an empty path."
fi

if env -i HOME="$HOME_1" PATH="$FAKE_BIN" /bin/sh -c '. "$HOME/.profile"; realpath "$1"' -- "$TMP_ROOT/does/not/exist" 2>/dev/null; then
    fail "realpath fallback should fail on non-existent path."
fi

# 8. Verify empty PATH does not produce a trailing colon.
out="$(env -i HOME="$HOME_1" PATH="" /bin/sh -c '. "$HOME/.profile"; printf "%s" "$PATH"')"
assert_eq "$out" "$HOME_1/bin" "empty PATH avoids trailing colon"

# 9. Verify unset PATH under set -u succeeds without unbound-variable error.
out="$(env -i HOME="$HOME_1" /bin/sh -u -c 'unset PATH; . "$HOME/.profile"; printf "%s" "$PATH"')"
assert_eq "$out" "$HOME_1/bin" "unset PATH under set -u sets HOME/bin cleanly"

# 10. Verify HOME containing spaces works in non-interactive and interactive shells.
HOME_SPACES="$TMP_ROOT/home with spaces"
mkdir -p "$HOME_SPACES/bin" "$HOME_SPACES/.profile.d"
cp "$REPO_ROOT/dot_profile" "$HOME_SPACES/.profile"
printf 'SPACE_HOOK=loaded\n' > "$HOME_SPACES/.profile.d/10-space.sh"

out="$(env -i HOME="$HOME_SPACES" PATH="/usr/bin:/bin" /bin/sh -c '. "$HOME/.profile"; printf "%s" "$PATH"')"
assert_eq "$out" "$HOME_SPACES/bin:/usr/bin:/bin" "HOME with spaces adds bin to PATH"

out="$(env -i HOME="$HOME_SPACES" PATH="/usr/bin:/bin" bash -i -c '. "$HOME/.profile"; printf "%s" "${SPACE_HOOK:-no}"' 2>/dev/null)"
assert_eq "$out" "loaded" "HOME with spaces loads interactive hooks"

# 11. Verify PROFILE_DEBUG=1 writes debug logs to stderr.
debug_nonint_err="$TMP_ROOT/debug_nonint.err"
env -i HOME="$HOME_1" PATH="/usr/bin:/bin" PROFILE_DEBUG=1 /bin/sh -c '. "$HOME/.profile"' 2>"$debug_nonint_err"
grep -q 'dot_profile: skip interactive hooks in non-interactive shell.' "$debug_nonint_err" || fail "PROFILE_DEBUG=1 should log non-interactive skip."
grep -q 'dot_profile: finished loading.' "$debug_nonint_err" || fail "PROFILE_DEBUG=1 should log completion."

debug_int_err="$TMP_ROOT/debug_int.err"
env -i HOME="$HOME_1" PATH="/usr/bin:/bin" PROFILE_DEBUG=1 bash -i -c '. "$HOME/.profile"' 2>"$debug_int_err"
grep -q "dot_profile: load $HOME_1/.profile.d/01-hook.sh" "$debug_int_err" || fail "PROFILE_DEBUG=1 should log loaded hook file."

# 12. Verify realpath fallback fails closed when perl is missing.
EMPTY_BIN="$TMP_ROOT/empty_bin"
mkdir -p "$EMPTY_BIN"
no_perl_err="$TMP_ROOT/no_perl.err"
if env -i HOME="$HOME_1" PATH="$EMPTY_BIN" /bin/sh -c '. "$HOME/.profile"; realpath "$1"' -- "$TARGET_DIR/file.txt" 2>"$no_perl_err"; then
    fail "realpath fallback should fail when perl is missing."
fi
grep -q 'Error: perl is not installed.' "$no_perl_err" || fail "realpath fallback should report missing perl on stderr."

# 13. Verify realpath fallback handles leading-dash paths cleanly.
printf 'dash\n' > "$TARGET_DIR/-file"
resolved_dash="$(cd "$TARGET_DIR" && env -i HOME="$HOME_1" PATH="$FAKE_BIN" /bin/sh -c '. "$HOME/.profile"; realpath "$1"' -- "-file")"
expected_dash="$(perl -MCwd=abs_path -e 'print abs_path($ARGV[0])' -- "$TARGET_DIR/-file")"
assert_eq "$resolved_dash" "$expected_dash" "realpath fallback resolves leading-dash filename"

# 14. Verify empty HOME does not prepend /bin to PATH or source /.profile.
out="$(env -i HOME="" PATH="/usr/bin" /bin/sh -c '. "$1"; printf "%s" "$PATH"' -- "$REPO_ROOT/dot_profile")"
assert_eq "$out" "/usr/bin" "dot_profile ignores empty HOME and does not prepend /bin"

out="$(env -i HOME="" PATH="/usr/bin" bash -c '. "$1"; printf "%s" "$PATH"' -- "$REPO_ROOT/dot_bashrc")"
assert_eq "$out" "/usr/bin" "dot_bashrc ignores empty HOME and does not source /.profile"

# 15. Verify unset HOME under set -u succeeds for dot_profile and dot_bashrc.
out="$(env -i PATH="/usr/bin" /bin/sh -u -c 'unset HOME; . "$1"; printf "%s" "$PATH"' -- "$REPO_ROOT/dot_profile")"
assert_eq "$out" "/usr/bin" "dot_profile handles unset HOME under set -u"

env -i PATH="/usr/bin" bash -i -u -c 'unset HOME; . "$1"' -- "$REPO_ROOT/dot_profile" 2>/dev/null || fail "interactive dot_profile should succeed with unset HOME under set -u."

out="$(env -i PATH="/usr/bin" bash -u -c 'unset HOME; . "$1"; printf "%s" "$PATH"' -- "$REPO_ROOT/dot_bashrc")"
assert_eq "$out" "/usr/bin" "dot_bashrc handles unset HOME under set -u"

printf 'All shell initialization tests passed.\n'
