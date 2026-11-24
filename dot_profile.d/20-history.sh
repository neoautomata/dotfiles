#!/bin/bash

# Configure Bash history behavior and Ctrl-R search.
if [ "${PROFILE_DEBUG:-0}" = "1" ]; then
    printf '%s\n' '20-history: set history options.' >&2
fi

# Ignore duplicate lines and lines starting with space.
HISTCONTROL=ignoreboth:erasedups

HISTSIZE=1000000
HISTFILESIZE=1000000
# Record timestamps with 3 whitespace-separated fields (matches cpcmd).
HISTTIMEFORMAT="%F %T %Z "

# Append to history instead of overwriting it, and preserve multiline commands.
shopt -s histappend
shopt -s cmdhist lithist

if [ ! -d "$HOME/.hist.d" ]; then
    mkdir -p "$HOME/.hist.d"
    chmod 0700 "$HOME/.hist.d"
fi
if [ -n "${HOSTNAME:-}" ]; then
    HISTFILE="$HOME/.hist.d/$HOSTNAME"
fi
HISTIGNORE="jj x:jj st:jj upload:jj describe:uptime:cd .:pa"
echo "Using history file: ${HISTFILE}"

# Use fzf for Ctrl-R history search only when fzf is available.
if command -v fzf >/dev/null 2>&1; then
    _fzf_key_bindings="$(fzf --bash 2>/dev/null | sed '/^### completion\.bash ###$/,$d' || true)"
    if [ -n "$_fzf_key_bindings" ]; then
        FZF_CTRL_T_COMMAND="" FZF_ALT_C_COMMAND="" eval "$_fzf_key_bindings"
    elif [ -r /usr/share/doc/fzf/examples/key-bindings.bash ]; then
        # shellcheck source=/dev/null
        FZF_CTRL_T_COMMAND="" FZF_ALT_C_COMMAND="" source /usr/share/doc/fzf/examples/key-bindings.bash
    fi
    unset _fzf_key_bindings
fi
