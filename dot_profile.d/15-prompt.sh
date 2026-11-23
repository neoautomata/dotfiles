#!/bin/bash

# Return the current epoch time in integer milliseconds.
function nowMs() {
  if [ -n "${EPOCHREALTIME:-}" ]; then
    local rt="$EPOCHREALTIME"
    local sec="${rt%%.*}"
    local frac="${rt#*.}"
    printf '%s%s\n' "$sec" "${frac:0:3}"
  else
    local ms
    ms="$(date "+%s%3N" 2>/dev/null)"
    if [[ "$ms" =~ ^[0-9]+$ ]]; then
      printf '%s\n' "$ms"
    else
      printf '%s000\n' "$(date "+%s")"
    fi
  fi
}

# Format a number of elapsed seconds for display.
function formatElapsed() {
  local t="${1%.*}"
  local d=$(( t / 86400 ))
  local h=$(( t / 3600 % 24 ))
  local m=$(( t / 60 % 60 ))
  local s=$(( t % 60 ))

  (( d > 0 )) && printf '%dd ' "$d"
  (( h > 0 )) && printf '%dh ' "$h"
  (( m > 0 )) && printf '%dm ' "$m"
  printf '%d' "$s"
}

# Print a full-width "-" line with optional elapsed time and current timestamp.
# Syntax: timeLine [start_ms end_ms]
function timeLine() {
  local elapsedStr=""
  if [[ "$#" -gt 1 && -n "$1" && -n "$2" ]]; then
    local start="$1" end="$2"
    local diffMs=$(( end - start ))
    if (( diffMs < 0 )); then
      diffMs=0
    fi
    local elapsedSec=$(( diffMs / 1000 ))
    local elapsedFrac
    printf -v elapsedFrac '%03d' "$(( diffMs % 1000 ))"
    elapsedStr=" $(formatElapsed "$elapsedSec").${elapsedFrac}s ---"
  fi

  local nowStr
  if [ -n "${EPOCHREALTIME:-}" ]; then
    local rt="$EPOCHREALTIME"
    local sec="${rt%%.*}"
    local frac="${rt#*.}"
    printf -v nowStr '%(%F %H:%M:%S)T.%s' "$sec" "${frac:0:3}"
  else
    nowStr="$(date "+%F %H:%M:%S.%03N" 2>/dev/null)"
    if [[ "$nowStr" == *N* ]]; then
      nowStr="$(date "+%F %H:%M:%S.000")"
    fi
  fi

  local text="${elapsedStr} ${nowStr}"
  local cols="${COLUMNS:-}"
  if [ -z "$cols" ]; then
    cols="$(tput cols 2>/dev/null || printf '80')"
  fi
  local need=$(( cols - ${#text} ))

  local line=""
  if (( need > 0 )); then
    printf -v line "%${need}s" ""
    line="${line// /-}"
  fi
  printf '%s' "${line}${text}"
}

# Set the terminal or screen window title if possible.
title_functions=()
screenTitle() {
  \echo -ne "\033k${1}\033\0134"
}

termTitle() {
  \echo -ne "\033]0;${1}\007"
}

winTitle() {
  local inScreen=0 remote=0 titleFunc=termTitle
  if [[ -n "${STY:-}" || -n "${LC_SENDSTY:-}" ]]; then
    titleFunc=screenTitle
    inScreen=1
  fi
  if [[ -n "${SSH_TTY:-}" && -n "${SSH_CLIENT:-}" ]]; then
    remote=1
  fi

  local title="" func
  for func in "${title_functions[@]}"; do
    title="$($func)"
    if [ -n "$title" ]; then
      break
    fi
  done

  # Treat a remote screen session as local so the hostname is not duplicated.
  if [[ "$remote" -ne 0 && -n "${STY:-}" ]]; then
    remote=0
  fi

  if [[ "$remote" -eq 0 ]]; then
    if [[ -z "$title" ]]; then
      if [[ "$inScreen" -eq 0 ]]; then
        title="${HOSTNAME:-}"
      else
        title="sh"
      fi
    fi
  else
    if [[ -z "$title" ]]; then
      if [[ "$inScreen" -eq 0 ]]; then
        title="${HOSTNAME:-}"
      else
        title="${HOSTNAME:-} sh"
      fi
    else
      title="${HOSTNAME:-} ${title}"
    fi
  fi

  $titleFunc "$title"
}

cmdTitle() {
  [[ "${inPreExec:-0}" -ne 1 ]] && return

  local cmd_name="${BASH_COMMAND%% *}"
  local resolved
  resolved="$(type -t "$cmd_name")"

  if [[ "$resolved" == "alias" ]]; then
    local alias_def
    alias_def="$(alias "$cmd_name")"
    cmd_name="$(echo "${alias_def#*=}" | tr -d "'\"" | awk '{print $1}')"
  fi

  if [[ -z "$cmd_name" || "$cmd_name" == "screen" || "$cmd_name" == "ssh" || "$cmd_name" == "prompt_command_func" ]]; then
    return
  fi

  local actual_path
  actual_path="$(type -p "$cmd_name")"

  if [[ -n "$actual_path" ]]; then
    echo "${actual_path##*/}"
  else
    echo "$cmd_name"
  fi
}
title_functions+=(cmdTitle)

# Print a timeline before running a command.
inPreExec=1 # Suppress preexec until the first prompt finishes.
preExecTime="" # Epoch milliseconds recorded before a command runs.
preexec() { echo -e "\033[38;5;244m$(timeLine)$(fmtTxt reset)"; }
preexec_invoke_exec() {
  # Skip during completion, prompt rendering, or internal hooks.
  [[ -n "${COMP_LINE:-}" ]] && return
  [[ "${BASH_COMMAND:-}" == "${PROMPT_COMMAND:-}" ]] && return
  [[ "${BASH_COMMAND:-}" == "prompt_command_func" ]] && return
  [[ "${BASH_COMMAND:-}" == __* ]] && return

  [[ "${inPreExec:-0}" -eq 1 ]] && return
  inPreExec=1 # Reset by prompt_command_func.

  preexec
  winTitle
  preExecTime="$(nowMs)"
}
trap 'preexec_invoke_exec' DEBUG

# Configure the prompt command and powerline hooks.
prompt_run=()
prompt_powerline=() # 3-part powerline specs: fg, bg, text.
prompt_dir_run=()
prompt_dir=""
escaped_home="${HOME//\//\\\/}"
function prompt_command_func() {
  last_exit_status=$?

  # Print the timeline with elapsed duration since the last command.
  echo -e -n "\033[38;5;244m"
  local t
  t="$(nowMs)"
  timeLine "$preExecTime" "$t"
  fmtTxt reset
  echo

  # Sync history across terminals via a shared history file.
  history -a
  history -c
  history -r

  # Build powerline segments for remote status, user, and host.
  prompt_powerline=()
  if [[ -n "${SSH_CLIENT:-}" ]]; then
    prompt_powerline+=("white" "blue" " \u260E  ")
  fi
  prompt_powerline+=(
    "black" "green" " $(id -nu)"
    "black" "yellow" "$(hostname -s) "
  )

  # Build powerline segments for the current working directory.
  local func d i
  prompt_dir="${PWD/#$escaped_home/\~}"
  for func in "${prompt_dir_run[@]}"; do
    $func
  done
  if [[ "$prompt_dir" == "/" ]]; then
    prompt_powerline+=("default" "dgrey" " / ")
  else
    local curpath=()
    prompt_dir="${prompt_dir/#\/}"
    IFS='/' read -r -a curpath <<< "$prompt_dir"
    for d in "${curpath[@]}"; do
      prompt_powerline+=("default" "dgrey" " $d ")
    done
  fi

  # Add the count of background jobs when one or more jobs are running.
  local jobCnt
  jobCnt="$(jobs -p | wc -l)"
  if (( jobCnt > 0 )); then
    prompt_powerline+=("dgrey" "lyellow" " ${jobCnt} \U1F477 ")
  fi

  # Run registered prompt hooks that may append powerline segments.
  for func in "${prompt_run[@]}"; do
    $func
  done

  # Render the powerline segments.
  i=0
  while (( i < ${#prompt_powerline[@]} - 3 )); do
    powerline "${prompt_powerline[i]}" "${prompt_powerline[i + 1]}" "${prompt_powerline[i + 4]}" "${prompt_powerline[i + 2]}"
    i=$(( i + 3 ))
  done
  powerline "${prompt_powerline[i]}" "${prompt_powerline[i + 1]}" "default" "${prompt_powerline[i + 2]}"
  echo

  if [[ "$(id -u)" -eq 0 ]]; then
    PS1="# "
  else
    PS1="$ "
  fi
  inPreExec=0
  preExecTime=""
  winTitle
}
PROMPT_COMMAND='prompt_command_func'

# Display a reboot indicator when /var/run/reboot-required exists.
function prompt_reboot_required() {
  if [[ -e "/var/run/reboot-required" ]]; then
    prompt_powerline+=("black" "red" " rbt ")
  fi
}
prompt_run+=(prompt_reboot_required)

# Display the exit code of the previous command when non-zero.
function prompt_error_code() {
  if (( last_exit_status != 0 )); then
    prompt_powerline+=("black" "red" " ${last_exit_status} (ಠ_ಠ) ")
  fi
}
prompt_run+=(prompt_error_code)
