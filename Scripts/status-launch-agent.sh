#!/bin/zsh
set -euo pipefail

label="com.chase.apple-music-discord-rpc"
user_domain="gui/$(id -u)"

if ! launchctl print "$user_domain/$label"; then
    echo "$label is not loaded." >&2
    exit 1
fi
