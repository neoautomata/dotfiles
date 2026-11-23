#!/bin/bash

#|-----------------|
#| Color variables |
#|-----------------|
declare -A COLORS

# Text Formatting
COLORS[reset]=0
COLORS[bold]=1
COLORS[dim]=2
COLORS[under]=4
COLORS[invert]=7
COLORS[hide]=8

COLORS[no_bold]=21
COLORS[no_dim]=22
COLORS[no_under]=24
COLORS[no_invert]=27
COLORS[no_hide]=28

# Foreground Colors
COLORS[default]=39
COLORS[black]=30
COLORS[red]=31
COLORS[green]=32
COLORS[yellow]=33
COLORS[blue]=34
COLORS[magenta]=35
COLORS[cyan]=36
COLORS[lgray]=37 # light gray
COLORS[lgrey]=${COLORS[lgray]}
COLORS[dgray]=90 # dark gray
COLORS[dgrey]=${COLORS[dgray]}
COLORS[lred]=91
COLORS[lgreen]=92
COLORS[lyellow]=93
COLORS[lblue]=94
COLORS[lmagenta]=95
COLORS[lcyan]=96
COLORS[white]=97

# Background colors
COLORS[on_default]=49
COLORS[on_black]=40
COLORS[on_red]=41
COLORS[on_green]=42
COLORS[on_yellow]=43
COLORS[on_blue]=44
COLORS[on_magenta]=45
COLORS[on_cyan]=46
COLORS[on_lgray]=47 # light gray
COLORS[on_lgrey]=${COLORS[on_lgray]}
COLORS[on_dgray]=100 # dark gray
COLORS[on_dgrey]=${COLORS[on_dgray]}
COLORS[on_lred]=101
COLORS[on_lgreen]=102
COLORS[on_lyellow]=103
COLORS[on_lblue]=104
COLORS[on_lmagenta]=105
COLORS[on_lcyan]=106
COLORS[on_white]=107

function fmtTxt() {
  if [ "$#" -lt 1 ]; then return; fi  

  # check the words are valid
  for word in "$@"; do
    if [ -z "${COLORS[$word]}" ]; then
      echo "Unknown formatting attribute: $word" 1>&2
      return
    fi
  done

  echo -ne '\e['
  while [ $# -gt 1 ]; do
    echo -ne "${COLORS[$1]};"
    shift
  done
  echo -ne "${COLORS[$1]}m"
}

function powerline() {
  local fg=$1; shift
  local bg=$1; shift
  local next=$1; shift;

  for word in "$fg" "$bg" "$next"; do
    if [ -z "${COLORS[$word]}" ]; then
      echo "Unknown formatting attribute: $word" 1>&2
      return
    fi
  done

  echo -n -e "$(fmtTxt "$fg" "on_$bg")$*"

  if [[ "$bg" != "$next" ]]; then
    echo -n -e "$(fmtTxt "$bg" "on_$next")\uE0B0$(fmtTxt reset)";
  else
    echo -n -e "$(fmtTxt "$fg" "on_$next")\uE0B1$(fmtTxt reset)";
  fi
  
}
