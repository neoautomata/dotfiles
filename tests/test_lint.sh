#!/usr/bin/env bash
set -euo pipefail

# Run static analysis and formatting checks on repository files.

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

bash -n "$REPO_ROOT/dot_bashrc" || fail "bash syntax check failed for dot_bashrc."
sh -n "$REPO_ROOT/dot_profile" || fail "sh syntax check failed for dot_profile."

for test_script in "$REPO_ROOT"/tests/*.sh; do
    bash -n "$test_script" || fail "bash syntax check failed for $test_script."
done

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$REPO_ROOT/dot_bashrc" || fail "shellcheck failed for dot_bashrc."
    shellcheck -s sh "$REPO_ROOT/dot_profile" || fail "shellcheck failed for dot_profile."
    shellcheck "$REPO_ROOT"/tests/*.sh || fail "shellcheck failed for tests/*.sh."
else
    printf 'SKIP: shellcheck is not installed.\n'
fi

if [ -f "$REPO_ROOT/README.md" ]; then
    if command -v mdformat >/dev/null 2>&1; then
        mdformat --check "$REPO_ROOT/README.md" || fail "mdformat check failed for README.md."
    else
        printf 'SKIP: mdformat is not installed.\n'
    fi
fi

printf 'All static checks passed.\n'
