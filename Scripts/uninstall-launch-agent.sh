#!/bin/zsh
set -euo pipefail

label="com.chase.apple-music-discord-rpc"
plist_path="$HOME/Library/LaunchAgents/$label.plist"
user_domain="gui/$(id -u)"

launchctl bootout "$user_domain" "$plist_path" >/dev/null 2>&1 || true
rm -f "$plist_path"

echo "Uninstalled $label."
