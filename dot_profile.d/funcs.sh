#!/bin/bash

# Wait until the number of background jobs drops below the limit.
function pwait() {
  local max_jobs="${1:-1}"
  while [ "$(jobs -p | wc -l)" -ge "$max_jobs" ]; do
    sleep 0.1
  done
}

# Sum values in the specified column (default: column 1).
function tally() {
  awk -v col="${1:-1}" '{ sum += $col } END { OFMT="%.9g"; print sum }'
}

# Run git commands inside ~/.dotfiles using its dedicated SSH key.
function dg() {
  (
    cd ~/.dotfiles || return 1

    local gitcmd="ssh -o IdentitiesOnly=yes "
    if [[ -e "${HOME}/.dotfiles_conf/gogs_home_dotfiles_ssh" ]]; then
      gitcmd+="-i ${HOME}/.dotfiles_conf/gogs_home_dotfiles_ssh "
    elif [[ -e "${HOME}/.dotfiles_conf/gogs_work_dotfiles_ssh" ]]; then
      gitcmd+="-i ${HOME}/.dotfiles_conf/gogs_work_dotfiles_ssh "
    fi

    if ! host gogs >/dev/null 2>&1; then
      gitcmd+="-p 3022 "
    fi

    SHELL=/bin/sh GIT_SSH_COMMAND="${gitcmd}" git "$@"
  )
}

# Prompt for a new filename when mv is called with a single regular file.
function mv() {
  if [[ "$#" -eq 1 && -f "$1" ]]; then
    local newfilename
    read -re -i "$1" -p "Rename to: " newfilename || return 0
    [[ -z "$newfilename" || "$1" == "$newfilename" ]] && return 0
    command mv -v -- "$1" "$newfilename"
  else
    command mv "$@"
  fi
}

# Prompt for a destination filename when cp is called with a single regular file.
function cp() {
  if [[ "$#" -eq 1 && -f "$1" ]]; then
    local newfilename
    read -re -i "$1" -p "Copy to: " newfilename || return 0
    [[ -z "$newfilename" || "$1" == "$newfilename" ]] && return 0
    command cp -v -- "$1" "$newfilename"
  else
    command cp "$@"
  fi
}

# Search with ripgrep and fzf, then open the selected match in EDITOR.
function frg() {
  local result file linenumber
  result="$(rg --ignore-case --color=always --line-number --no-heading "$@" |
    fzf --ansi \
        --color 'hl:-1:underline,hl+:-1:underline:reverse' \
        --delimiter ':' \
        --preview "bat --color=always {1} --theme='Solarized (light)' --highlight-line {2}" \
        --preview-window 'up,60%,border-bottom,+{2}+3/3,~3')"
  [[ -z "$result" ]] && return 0

  file="$(printf '%s\n' "$result" | cut -d: -f1)"
  linenumber="$(printf '%s\n' "$result" | cut -d: -f2)"

  "${EDITOR:-vi}" +"${linenumber}" "$file"
}

# Load additional function files from ~/.profile.d/funcs.
if [[ -d "${HOME}/.profile.d/funcs" ]]; then
  for f in "${HOME}/.profile.d/funcs"/*; do
    if [[ -f "$f" && -r "$f" ]]; then
      # shellcheck source=/dev/null
      . "$f"
    fi
  done
  unset f
fi

# Run a command across each revision matched by a jj revset in the current workspace.
function jjexec() {
  # Examples:
  # - mutable ancestors: ::mutable()
  # - exported: (remote_bookmarks()..exported)
  if [[ "$#" -lt 2 ]]; then
    printf '%s\n' 'Usage: jjexec <revset> <command> [args...]' >&2
    return 1
  fi
  local revsets="$1"
  shift

  local -a revs=()
  mapfile -t revs < <(jj log -r "${revsets}" --no-graph --reversed -T 'change_id ++ "\n"')
  if [[ "${#revs[@]}" -eq 0 ]]; then
    printf 'No revisions found for revset: %s\n' "${revsets}" >&2
    return 0
  fi

  local originalRev rev
  originalRev="$(jj log -r @ --no-graph -T 'change_id ++ "\n"')"

  for rev in "${revs[@]}"; do
    jj edit "$rev"
    "$@"
  done

  jj edit "${originalRev}"
}

# Run a command across each revision matched by a jj revset in a temporary workspace.
function jjexecp() {
  if [[ "$#" -lt 2 ]]; then
    printf '%s\n' 'Usage: jjexecp <revset> <command> [args...]' >&2
    return 1
  fi
  local revsets="$1"
  shift

  local -a revs=()
  mapfile -t revs < <(jj log -r "${revsets}" --no-graph --reversed -T 'change_id ++ "\n"')
  if [[ "${#revs[@]}" -eq 0 ]]; then
    printf 'No revisions found for revset: %s\n' "${revsets}" >&2
    return 0
  fi

  local is_piper=0
  if jj help 2>/dev/null | grep -q piper; then
    is_piper=1
  fi

  local tmp_parent tmpname tmpdir
  tmp_parent="$(mktemp -d "${TMPDIR:-/tmp}/jjexecp-XXXXXXXXXX")" || return 1
  tmpname="$(basename "$tmp_parent")"
  tmpdir="${tmp_parent}/${tmpname}"

  if (( is_piper )); then
    if ! jj piper citc workspace add "${tmpname}"; then
      rm -rf "${tmp_parent}"
      return 1
    fi
  else
    if ! jj workspace add --name "${tmpname}" "${tmpdir}" -r "${revs[0]}"; then
      rm -rf "${tmp_parent}"
      return 1
    fi
  fi

  # Use a subshell so directory changes do not affect the caller's shell.
  (
    # shellcheck disable=SC2317
    cleanup_ws() {
      jj workspace forget "${tmpname}" 2>/dev/null || true
      if (( is_piper )); then
        local citc_ws
        citc_ws="$(jj piper citc list 2>/dev/null | grep -F "${tmpname}" || true)"
        if [ -n "$citc_ws" ]; then
          # shellcheck disable=SC2086
          jj piper citc delete $citc_ws || true
        fi
      fi
      cd / || true
      rm -rf "${tmp_parent}"
    }
    trap cleanup_ws EXIT

    if (( is_piper )); then
      jjd "${tmpname}" || exit 1
    else
      cd "${tmpdir}" || exit 1
    fi

    local rev
    for rev in "${revs[@]}"; do
      printf 'Running in %s\n' "$rev"
      jj edit "$rev"
      "$@"
    done
    printf '%s\n' 'Done'
  )
}
