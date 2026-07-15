#!/bin/zsh
set -euo pipefail

label="com.chase.apple-music-discord-rpc"
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
binary_path="$project_dir/.build/release/apple-music-discord-rpc"
launch_agents_dir="$HOME/Library/LaunchAgents"
log_dir="$HOME/Library/Logs/AppleMusicDiscordRPC"
plist_path="$launch_agents_dir/$label.plist"
user_domain="gui/$(id -u)"

app_id="${DISCORD_APP_ID:-}"
poll_interval="10"
verbose="0"

usage() {
    cat <<USAGE
Usage:
  install-launch-agent.sh --app-id <discord application id> [options]

Options:
  --app-id <id>              Discord application ID. Can also be set with DISCORD_APP_ID.
  --poll-interval <seconds>  Poll interval used by launchd. Defaults to 10.
  --verbose                  Write daemon debug logs to stderr.log.
  --help                     Show this help text.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-id)
            shift
            if [[ $# -eq 0 || -z "$1" ]]; then
                echo "Missing value for --app-id." >&2
                exit 64
            fi
            app_id="$1"
            ;;
        --poll-interval)
            shift
            if [[ $# -eq 0 || -z "$1" ]]; then
                echo "Missing value for --poll-interval." >&2
                exit 64
            fi
            poll_interval="$1"
            ;;
        --verbose)
            verbose="1"
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
    shift
done

if [[ -z "$app_id" ]]; then
    echo "Missing Discord application ID. Pass --app-id <id> or set DISCORD_APP_ID." >&2
    exit 64
fi

if ! [[ "$poll_interval" =~ '^[0-9]+([.][0-9]+)?$' ]] || (( poll_interval <= 0 )); then
    echo "Invalid poll interval: $poll_interval" >&2
    exit 64
fi

xml_escape() {
    local value="$1"
    value="${value//&/&amp;}"
    value="${value//</&lt;}"
    value="${value//>/&gt;}"
    printf "%s" "$value"
}

escaped_binary_path="$(xml_escape "$binary_path")"
escaped_project_dir="$(xml_escape "$project_dir")"
escaped_app_id="$(xml_escape "$app_id")"
escaped_poll_interval="$(xml_escape "$poll_interval")"
escaped_stdout_path="$(xml_escape "$log_dir/stdout.log")"
escaped_stderr_path="$(xml_escape "$log_dir/stderr.log")"

verbose_argument=""
if [[ "$verbose" == "1" ]]; then
    verbose_argument="        <string>--verbose</string>"
fi

echo "Building release binary..."
swift build -c release --package-path "$project_dir"

mkdir -p "$launch_agents_dir" "$log_dir"

launchctl bootout "$user_domain" "$plist_path" >/dev/null 2>&1 || true

cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>

    <key>ProgramArguments</key>
    <array>
        <string>$escaped_binary_path</string>
        <string>--app-id</string>
        <string>$escaped_app_id</string>
        <string>--poll-interval</string>
        <string>$escaped_poll_interval</string>
$verbose_argument
    </array>

    <key>WorkingDirectory</key>
    <string>$escaped_project_dir</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <false/>

    <key>ProcessType</key>
    <string>Background</string>

    <key>Nice</key>
    <integer>10</integer>

    <key>LowPriorityIO</key>
    <true/>

    <key>StandardOutPath</key>
    <string>$escaped_stdout_path</string>

    <key>StandardErrorPath</key>
    <string>$escaped_stderr_path</string>
</dict>
</plist>
PLIST

chmod 644 "$plist_path"
plutil -lint "$plist_path" >/dev/null

launchctl bootstrap "$user_domain" "$plist_path"
launchctl enable "$user_domain/$label"
launchctl kickstart -k "$user_domain/$label"

cat <<DONE
Installed and started $label.

LaunchAgent:
  $plist_path

Logs:
  $log_dir/stdout.log
  $log_dir/stderr.log

Useful commands:
  ./Scripts/status-launch-agent.sh
  ./Scripts/uninstall-launch-agent.sh
DONE
