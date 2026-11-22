#!/usr/bin/env bash
set -euo pipefail

# Run all dotfiles tests and static checks from one entrypoint.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT

PASS_COUNT=0
FAIL_COUNT=0

run_suite() {
    local suite_path="$1"
    local suite_name
    suite_name="$(basename "$suite_path")"

    printf '=== Running %s ===\n' "$suite_name"
    if "$suite_path"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        printf 'PASS: %s\n\n' "$suite_name"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        printf 'FAIL: %s\n\n' "$suite_name" >&2
    fi
}

run_suite "$SCRIPT_DIR/test_lint.sh"
run_suite "$SCRIPT_DIR/test_shell_init.sh"
run_suite "$SCRIPT_DIR/test_sync_bin_links.sh"
run_suite "$SCRIPT_DIR/test_chezmoi_templates.sh"

printf 'Summary: %d passed, %d failed.\n' "$PASS_COUNT" "$FAIL_COUNT"
if [ "$FAIL_COUNT" -ne 0 ]; then
    exit 1
fi
