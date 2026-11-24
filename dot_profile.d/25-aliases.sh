#!/bin/bash

# Keep scrollback when clearing the terminal.
alias clear='clear -x'

# Listing aliases.
alias la='ls -AlF'
alias ll='ls -lF'
alias lsdev='lsblk -lmt'

# Prefer nawk or gawk when installed.
if command -v nawk >/dev/null 2>&1; then
    alias awk='nawk'
elif command -v gawk >/dev/null 2>&1; then
    alias awk='gawk'
fi

# Prefer vim over vi when installed.
if command -v vim >/dev/null 2>&1; then
    alias vi='vim'
fi

# Common command aliases.
alias aptup!='sudo sh -c "apt-get update && apt-get upgrade -y && apt-get dist-upgrade -y && apt-get autoremove -y && apt-get clean"'
alias cpcmd='tee >({ echo -n "\$ "; history 1 | perl -lane "print \"@F[4..\$#F]\"" | perl -pe "s/\\|\\&?\s*cpcmd\$//;"; cat; } | setclip >/dev/null)'
alias ers='stty erase "^?"'
alias getclip='xclip -selection clipboard -o'
alias grep='grep -E --color=auto'
alias pdate='TZ=America/Los_Angeles date'
alias pstree_self='pstree -AachlnpsU $$'
alias s='sudo '
alias setclip='tee >(xclip -selection c)'
alias ts.ssh='tailscale ssh'
alias udate='date -u'
alias uncol='xargs echo'
