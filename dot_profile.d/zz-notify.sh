#!/bin/bash

# Show login notifications.
if [ "${PROFILE_DEBUG:-0}" = "1" ]; then
    printf '%s\n' 'zz-notify: list screen sessions.' >&2
fi

if [ -z "${STY:-}" ] && command -v screen >/dev/null 2>&1; then
    screen -list || true
fi
