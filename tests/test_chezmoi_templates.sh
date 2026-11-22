#!/usr/bin/env bash
set -euo pipefail

# Test chezmoi templates, rendered TOML, .chezmoiignore, and massren build filter.

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

if ! command -v chezmoi >/dev/null 2>&1; then
    printf 'SKIP: PATH lacks chezmoi. Skip template and ignore tests.\n'
    exit 0
fi

# 1. Test .chezmoi.toml.tmpl with subl absent and subl present.
EMPTY_PATH_BIN="$TMP_ROOT/no_subl"
mkdir -p "$EMPTY_PATH_BIN"
NO_SUBL_TOML="$TMP_ROOT/chezmoi_no_subl.toml"
PATH="$EMPTY_PATH_BIN" "$(command -v chezmoi)" execute-template < "$REPO_ROOT/.chezmoi.toml.tmpl" > "$NO_SUBL_TOML"

python3 - "$NO_SUBL_TOML" <<'EOF'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
assert data["git"]["autoCommit"] is True
assert data["git"]["autoPush"] is True
assert "edit" not in data, f"Unexpected edit section: {data}"
EOF

WITH_SUBL_BIN="$TMP_ROOT/with_subl"
mkdir -p "$WITH_SUBL_BIN"
printf '#!/bin/sh\nexit 0\n' > "$WITH_SUBL_BIN/subl"
chmod +x "$WITH_SUBL_BIN/subl"
WITH_SUBL_TOML="$TMP_ROOT/chezmoi_with_subl.toml"
PATH="$WITH_SUBL_BIN" "$(command -v chezmoi)" execute-template < "$REPO_ROOT/.chezmoi.toml.tmpl" > "$WITH_SUBL_TOML"

python3 - "$WITH_SUBL_TOML" <<'EOF'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
assert data["edit"]["command"] == "subl"
assert data["edit"]["args"] == ["--wait"]
EOF

# 2. Test run_after_sync-bin-links.sh.tmpl across linux, darwin, and windows.
for os in linux darwin; do
    rendered="$TMP_ROOT/sync_${os}.sh"
    chezmoi execute-template --override-data "{\"chezmoi\":{\"os\":\"${os}\",\"destDir\":\"/tmp/test\"}}" \
        < "$REPO_ROOT/run_after_sync-bin-links.sh.tmpl" > "$rendered"
    bash -n "$rendered" || fail "bash -n rejected the rendered sync script for $os."
    if command -v shellcheck >/dev/null 2>&1; then
        shellcheck "$rendered" || fail "shellcheck rejected the rendered sync script for $os."
    fi
done

win_rendered="$(chezmoi execute-template --override-data '{"chezmoi":{"os":"windows","destDir":"C:/Users/test"}}' < "$REPO_ROOT/run_after_sync-bin-links.sh.tmpl")"
if [ -n "$win_rendered" ]; then
    fail "run_after_sync-bin-links.sh.tmpl must render empty on windows."
fi

# Stage an offline source directory without .chezmoiexternal.toml.tmpl for offline chezmoi commands.
OFFLINE_SOURCE="$TMP_ROOT/offline-source"
mkdir -p "$OFFLINE_SOURCE"
while IFS= read -r -d '' entry; do
    base="$(basename "$entry")"
    case "$base" in
        .chezmoiexternal.toml.tmpl|.git) continue ;;
    esac
    cp -R -p "$entry" "$OFFLINE_SOURCE/$base"
done < <(find "$REPO_ROOT" -mindepth 1 -maxdepth 1 -print0)

# 3. Verify that .chezmoiignore excludes repository-only files from chezmoi.
managed_list="$(chezmoi managed --source "$OFFLINE_SOURCE" --config "$NO_SUBL_TOML")"
printf '%s\n' "$managed_list" | grep -qx '.bashrc' || fail "chezmoi must manage .bashrc."
printf '%s\n' "$managed_list" | grep -qx '.profile' || fail "chezmoi must manage .profile."
if printf '%s\n' "$managed_list" | grep -Eq '^(README\.md|tests(/|$))'; then
    fail ".chezmoiignore must exclude README.md and tests/."
fi

# 4. Test .chezmoiexternal.toml.tmpl on Windows offline without GitHub API calls.
WIN_EXT="$TMP_ROOT/external_windows.toml"
chezmoi execute-template --override-data '{"chezmoi":{"os":"windows","arch":"amd64"}}' \
    < "$REPO_ROOT/.chezmoiexternal.toml.tmpl" > "$WIN_EXT"

python3 - "$WIN_EXT" <<'EOF'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
assert "bin/bw_scripts" in data
for excluded in ("bin/bw.bin", "bin/chezmoi", "bin/jj", "bin/massren"):
    assert excluded not in data, f"Template must omit {excluded} on windows"
EOF

# 5. Test .chezmoiexternal.toml.tmpl across linux and darwin platforms with GitHub API.
for combo in "linux:amd64" "linux:arm64" "darwin:amd64" "darwin:arm64"; do
    os="${combo%%:*}"
    arch="${combo##*:}"
    ext_file="$TMP_ROOT/external_${os}_${arch}.toml"
    err_file="$TMP_ROOT/external_${os}_${arch}.err"
    if ! chezmoi execute-template --override-data "{\"chezmoi\":{\"os\":\"${os}\",\"arch\":\"${arch}\"}}" \
        < "$REPO_ROOT/.chezmoiexternal.toml.tmpl" > "$ext_file" 2>"$err_file"; then
        if grep -qiE 'rate limit|no such host|dial tcp|timeout' "$err_file"; then
            printf 'SKIP: GitHub API returned a rate limit or network error for %s/%s.\n' "$os" "$arch"
            continue
        fi
        cat "$err_file" >&2
        fail "chezmoi failed to render .chezmoiexternal.toml.tmpl for $os/$arch."
    fi

    python3 - "$ext_file" "$os" "$arch" <<'EOF'
import sys, tomllib
path, os_name, arch_name = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "rb") as f:
    data = tomllib.load(f)

for key in ("bin/bw_scripts", "bin/bw.bin", "bin/chezmoi", "bin/jj", "bin/massren"):
    assert key in data, f"Missing {key} for {os_name}/{arch_name}"
    assert data[key]["url"].startswith("https://"), f"Invalid URL for {key}: {data[key]['url']}"

bw_os = "macos" if os_name == "darwin" else "linux"
assert bw_os in data["bin/bw.bin"]["url"], f"Wrong OS in bw URL: {data['bin/bw.bin']['url']}"
if arch_name == "arm64":
    assert "arm64" in data["bin/bw.bin"]["url"], f"Expected arm64 in bw URL: {data['bin/bw.bin']['url']}"
else:
    assert "arm64" not in data["bin/bw.bin"]["url"], f"Unexpected arm64 in amd64 bw URL: {data['bin/bw.bin']['url']}"

assert f"{os_name}_{arch_name}.tar.gz" in data["bin/chezmoi"]["url"]
EOF
done

# 6. Extract and test the massren filter script offline.
if ! MASSREN_FILTER_SCRIPT="$(python3 - "$REPO_ROOT/.chezmoiexternal.toml.tmpl" <<'EOF'
import re, sys, tomllib

with open(sys.argv[1], "r", encoding="utf-8") as f:
    lines = f.readlines()

table_lines = []
in_table = False
for line in lines:
    stripped = line.strip()
    if not in_table:
        if stripped == '["bin/massren"]':
            in_table = True
            table_lines.append(line)
        continue
    if stripped.startswith("{{") or re.match(r"^\s*\[.+\]\s*$", line):
        break
    if re.match(r"^\s*url\s*=", line):
        table_lines.append('    url = "https://example.invalid/massren.tar.gz"\n')
        continue
    table_lines.append(line)

if not table_lines:
    sys.exit('Missing ["bin/massren"] table in .chezmoiexternal.toml.tmpl.')

data = tomllib.loads("".join(table_lines))
script = data["bin/massren"]["filter"]["args"][2]
if not script.strip():
    sys.exit("Empty massren filter script.")
print(script)
EOF
)" || [ -z "$MASSREN_FILTER_SCRIPT" ]; then
    fail "The test failed to extract the massren filter script from .chezmoiexternal.toml.tmpl."
fi

if command -v shellcheck >/dev/null 2>&1; then
    printf '#!/bin/sh\n%s\n' "$MASSREN_FILTER_SCRIPT" | shellcheck -s sh - || fail "shellcheck rejected the massren filter script."
fi

# Fail closed when go is absent.
filter_err="$TMP_ROOT/massren_missing_go.err"
if env -i PATH="$EMPTY_PATH_BIN" /bin/sh -eu -c "$MASSREN_FILTER_SCRIPT" </dev/null >/dev/null 2>"$filter_err"; then
    fail "The massren filter must fail when PATH lacks go."
fi
grep -q 'Error: go is not installed.' "$filter_err" || fail "The massren filter must report missing go on stderr."

# Fail closed when tar is absent.
GO_ONLY_BIN="$TMP_ROOT/massren_go_only"
mkdir -p "$GO_ONLY_BIN"
printf '#!/bin/sh\nexit 0\n' > "$GO_ONLY_BIN/go"
chmod +x "$GO_ONLY_BIN/go"
filter_err="$TMP_ROOT/massren_missing_tar.err"
if env -i PATH="$GO_ONLY_BIN" /bin/sh -eu -c "$MASSREN_FILTER_SCRIPT" </dev/null >/dev/null 2>"$filter_err"; then
    fail "The massren filter must fail when PATH lacks tar."
fi
grep -q 'Error: tar is not installed.' "$filter_err" || fail "The massren filter must report missing tar on stderr."

# Fail closed when no C compiler exists on PATH or in CC.
GO_TAR_BIN="$TMP_ROOT/massren_go_tar"
mkdir -p "$GO_TAR_BIN"
ln -s "$GO_ONLY_BIN/go" "$GO_TAR_BIN/go"
ln -s "$(command -v tar)" "$GO_TAR_BIN/tar"
filter_err="$TMP_ROOT/massren_missing_cc.err"
if env -i PATH="$GO_TAR_BIN" /bin/sh -eu -c "$MASSREN_FILTER_SCRIPT" </dev/null >/dev/null 2>"$filter_err"; then
    fail "The massren filter must fail when PATH lacks a C compiler."
fi
grep -q 'Error: No C compiler is installed.' "$filter_err" || fail "The massren filter must report a missing C compiler on stderr."

filter_err="$TMP_ROOT/massren_bad_cc.err"
if env -i PATH="$GO_TAR_BIN" CC="/nonexistent/cc" /bin/sh -eu -c "$MASSREN_FILTER_SCRIPT" </dev/null >/dev/null 2>"$filter_err"; then
    fail "The massren filter must fail when CC points to a missing binary."
fi
grep -q 'Error: No C compiler is installed.' "$filter_err" || fail "The massren filter must report a missing CC binary on stderr."

filter_err="$TMP_ROOT/massren_bad_multiword_cc.err"
if env -i PATH="$GO_TAR_BIN" CC="nonexistent-cc -flag" /bin/sh -eu -c "$MASSREN_FILTER_SCRIPT" </dev/null >/dev/null 2>"$filter_err"; then
    fail "The massren filter must fail when multi-word CC names a missing binary."
fi
grep -q 'Error: No C compiler is installed.' "$filter_err" || fail "The massren filter must report a missing multi-word CC binary on stderr."

# Create stub go and cc binaries for extraction and TAPE tests.
STUB_BUILD_BIN="$TMP_ROOT/massren_stub_bin"
mkdir -p "$STUB_BUILD_BIN"
cat > "$STUB_BUILD_BIN/go" <<'EOF'
#!/bin/sh
set -eu
[ -f main.go ] || exit 1
printf 'built-massren-binary\n' > massren
EOF
chmod +x "$STUB_BUILD_BIN/go"
printf '#!/bin/sh\nexit 0\n' > "$STUB_BUILD_BIN/cc"
chmod +x "$STUB_BUILD_BIN/cc"
printf '#!/bin/sh\nexit 0\n' > "$STUB_BUILD_BIN/my-cc-wrapper"
chmod +x "$STUB_BUILD_BIN/my-cc-wrapper"

# Fail closed on an invalid tarball and delete the temporary build directory.
BAD_TAR_TMP="$TMP_ROOT/massren_bad_tar_tmp"
mkdir -p "$BAD_TAR_TMP"
if printf 'not-a-valid-tarball\n' | env -i PATH="$STUB_BUILD_BIN:$PATH" TMPDIR="$BAD_TAR_TMP" /bin/sh -eu -c "$MASSREN_FILTER_SCRIPT" >/dev/null 2>/dev/null; then
    fail "The massren filter must fail on invalid tarball input."
fi
if [ -n "$(ls -A "$BAD_TAR_TMP")" ]; then
    fail "The massren filter must delete the temporary build directory after tarball failure."
fi

# Verify that TAPE=/dev/nonexistent does not break stdin extraction with tar -xzf -.
SRC_STAGE="$TMP_ROOT/massren_src_stage"
mkdir -p "$SRC_STAGE/massren-1.0"
printf 'package main\n' > "$SRC_STAGE/massren-1.0/main.go"
VALID_TAR="$TMP_ROOT/massren.tar.gz"
tar -czf "$VALID_TAR" -C "$SRC_STAGE" massren-1.0

TAPE_TMP="$TMP_ROOT/massren_tape_tmp"
mkdir -p "$TAPE_TMP"
built_out="$(env -i PATH="$STUB_BUILD_BIN:$PATH" TMPDIR="$TAPE_TMP" TAPE="/dev/nonexistent" /bin/sh -eu -c "$MASSREN_FILTER_SCRIPT" < "$VALID_TAR" 2>/dev/null)"
if [ "$built_out" != "built-massren-binary" ]; then
    fail "The massren filter must read the tarball from stdin when TAPE has a value."
fi
if [ -n "$(ls -A "$TAPE_TMP")" ]; then
    fail "The massren filter must delete the temporary build directory after the build."
fi

# Verify that multi-word CC with an existing wrapper succeeds.
MULTIWORD_CC_TMP="$TMP_ROOT/massren_multiword_cc_tmp"
mkdir -p "$MULTIWORD_CC_TMP"
built_out="$(env -i PATH="$STUB_BUILD_BIN:$PATH" TMPDIR="$MULTIWORD_CC_TMP" CC="my-cc-wrapper -flag" /bin/sh -eu -c "$MASSREN_FILTER_SCRIPT" < "$VALID_TAR" 2>/dev/null)"
if [ "$built_out" != "built-massren-binary" ]; then
    fail "The massren filter must accept multi-word CC when the compiler command exists."
fi
if [ -n "$(ls -A "$MULTIWORD_CC_TMP")" ]; then
    fail "The massren filter must delete the temporary build directory after a multi-word CC build."
fi

# 7. Verify that chezmoi apply targets the destination directory instead of HOME.
E2E_HOME="$TMP_ROOT/e2e_home"
E2E_DEST="$TMP_ROOT/e2e_dest"
E2E_STATE="$TMP_ROOT/e2e_state.boltdb"
mkdir -p "$E2E_HOME/bin/pkg" "$E2E_DEST/bin/pkg"
printf '#!/bin/sh\necho home\n' > "$E2E_HOME/bin/pkg/home_only_tool"
chmod +x "$E2E_HOME/bin/pkg/home_only_tool"
printf '#!/bin/sh\necho dest\n' > "$E2E_DEST/bin/pkg/dest_only_tool"
chmod +x "$E2E_DEST/bin/pkg/dest_only_tool"

HOME="$E2E_HOME" chezmoi apply \
    --source "$OFFLINE_SOURCE" \
    --destination "$E2E_DEST" \
    --config "$NO_SUBL_TOML" \
    --persistent-state "$E2E_STATE" \
    --exclude=externals \
    --force >/dev/null

[ -f "$E2E_DEST/.bashrc" ] || fail "chezmoi apply must write .bashrc to the destination directory."
[ -f "$E2E_DEST/.profile" ] || fail "chezmoi apply must write .profile to the destination directory."
[ -L "$E2E_DEST/bin/dest_only_tool" ] || fail "run_after_sync-bin-links must link executables in the destination bin directory."
if [ "$(readlink -- "$E2E_DEST/bin/dest_only_tool")" != "$E2E_DEST/bin/pkg/dest_only_tool" ]; then
    fail "run_after_sync-bin-links must point the symlink to the destination executable."
fi
if [ -e "$E2E_HOME/bin/home_only_tool" ] || [ -L "$E2E_HOME/bin/home_only_tool" ]; then
    fail "run_after_sync-bin-links must not modify HOME/bin when destination differs."
fi

printf 'All chezmoi template tests passed.\n'
