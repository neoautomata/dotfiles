#!/bin/bash

# Set interactive terminal options.
if [ "${PROFILE_DEBUG:-0}" = "1" ]; then
    printf '%s\n' '05-term_opts: set terminal options.' >&2
fi

# Update LINES and COLUMNS after each command when the window size changes.
shopt -s checkwinsize

set -o vi
set -o ignoreeof

# Disable XON/XOFF flow control (Ctrl-S/Ctrl-Q) when stdin is a terminal.
if [ -t 0 ]; then
    stty -ixon
fi

# Enable programmable completion features when available.
if ! shopt -oq posix; then
    if [ -r /usr/share/bash-completion/bash_completion ]; then
        # shellcheck source=/dev/null
        . /usr/share/bash-completion/bash_completion
    elif [ -r /etc/bash_completion ]; then
        # shellcheck source=/dev/null
        . /etc/bash_completion
    fi
fi

# Set the default file creation mask.
if [ "${PROFILE_DEBUG:-0}" = "1" ]; then
    printf '%s\n' '05-term_opts: set umask.' >&2
fi
umask 022

# Append to the history file instead of overwriting it.
shopt -s histappend
