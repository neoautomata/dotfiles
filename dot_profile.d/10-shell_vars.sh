#!/bin/bash

# Set common shell environment variables.
if [ "${PROFILE_DEBUG:-0}" = "1" ]; then
    printf '%s\n' '10-shell_vars: set shell variables.' >&2
fi

# Export the short hostname.
if [ "${PROFILE_DEBUG:-0}" = "1" ]; then
    printf '%s\n' '10-shell_vars: export HOSTNAME.' >&2
fi
if command -v hostname >/dev/null 2>&1; then
    HOSTNAME="$(hostname -s)"
elif [ -n "${HOSTNAME:-}" ]; then
    HOSTNAME="${HOSTNAME%%.*}"
fi
if [ -n "${HOSTNAME:-}" ]; then
    export HOSTNAME
fi

add_to_path() {
    if [ -d "$1" ] && [[ ":${PATH:-}:" != *":$1:"* ]]; then
        PATH="$1${PATH:+:$PATH}"
        export PATH
    fi
}

# Prepend directories so PATH precedence is:
# ~/.local/bin > ~/bin > ~/.dotfiles/bin > /usr/local/go/bin > existing PATH.
if [ "${PROFILE_DEBUG:-0}" = "1" ]; then
    printf '%s\n' '10-shell_vars: export PATH.' >&2
fi
add_to_path "/usr/local/go/bin"
add_to_path "${HOME}/.dotfiles/bin"
add_to_path "${HOME}/bin"
add_to_path "${HOME}/.local/bin"

# Export OS, kernel release, and CPU architecture.
if [ "${PROFILE_DEBUG:-0}" = "1" ]; then
    printf '%s\n' '10-shell_vars: export OS, Release, Processor.' >&2
fi
OS="$(uname -s)"
Release="$(uname -r)"
Processor="$(uname -m)"
export OS Release Processor

# Export default pager and less options.
if [ "${PROFILE_DEBUG:-0}" = "1" ]; then
    printf '%s\n' '10-shell_vars: export PAGER.' >&2
fi
PAGER="$(command -v less || command -v more || true)"
if [ -n "$PAGER" ]; then
    export PAGER
    if [[ "$PAGER" == */less ]]; then
        LESS="-SRi"
        export LESS
    fi
fi

# Export default editor.
if [ "${PROFILE_DEBUG:-0}" = "1" ]; then
    printf '%s\n' '10-shell_vars: export EDITOR.' >&2
fi
EDITOR="$(command -v vim || command -v vi || true)"
if [ -n "$EDITOR" ]; then
    export EDITOR
fi

# Set a fallback terminal type when TERM is empty.
if [ "${PROFILE_DEBUG:-0}" = "1" ]; then
    printf '%s\n' '10-shell_vars: export TERM.' >&2
fi
if [ -z "${TERM:-}" ]; then
    TERM="xterm-256color"
    export TERM
fi

# Pass GNU Screen session ID over SSH via LC_* when inside screen.
if [ -n "${STY:-}" ]; then
    LC_SENDSTY="$STY"
    export LC_SENDSTY
fi
