# Apple Music Discord RPC

A lightweight macOS Swift CLI that mirrors the currently playing Apple Music track into Discord Rich Presence.

The first version is intentionally small:

- Reads Apple Music with AppleScript.
- Talks to Discord Desktop through its local IPC RPC socket.
- Shows song title, compact artist credits, album, elapsed time, total duration, album cover, and a small artist image when public artwork can be resolved.
- Clears the presence when Music is paused, stopped, closed, or the daemon exits.
- Uses no bot token, OAuth token, client secret, server, or third-party package.

## Requirements

- macOS
- Apple Music
- Discord Desktop running locally
- A Discord Developer application ID

Discord Rich Presence over local RPC only works with the Discord desktop client.

## Discord Setup

1. Open the [Discord Developer Portal](https://discord.com/developers/applications).
2. Create a new application.
3. Copy the application's **Application ID**.
4. Use that ID with `--app-id` or `DISCORD_APP_ID`.

You do not need a bot token, OAuth token, or client secret.

You do not need to upload images to Discord. The CLI sends public image URLs to Discord:

- Album cover lookup tries Apple first, then Deezer, then MusicBrainz + Cover Art Archive.
- Artist image lookup tries Deezer and is shown as Discord's small circular image when available.

If no confident image match is found, Discord still receives the text presence and duration bar.

## Build

```sh
swift build
```

## Run

Run once:

```sh
DISCORD_APP_ID=123456789012345678 swift run apple-music-discord-rpc --once
```

Run as a foreground daemon:

```sh
DISCORD_APP_ID=123456789012345678 swift run apple-music-discord-rpc
```

Clear the current Rich Presence:

```sh
DISCORD_APP_ID=123456789012345678 swift run apple-music-discord-rpc --clear
```

Use a different poll interval:

```sh
DISCORD_APP_ID=123456789012345678 swift run apple-music-discord-rpc --poll-interval 2
```

Disable all image lookup:

```sh
DISCORD_APP_ID=123456789012345678 swift run apple-music-discord-rpc --no-album-art
```

## Start at Login

For everyday use, install it as a low-impact macOS LaunchAgent:

```sh
./Scripts/install-launch-agent.sh --app-id 123456789012345678
```

The installer builds the release binary and starts it in the background with:

- `--poll-interval 10`, so it wakes less often than the foreground default.
- `ProcessType=Background`, `Nice=10`, and `LowPriorityIO=true`, so macOS treats it as low priority.
- `KeepAlive=false`, so launchd does not aggressively restart it in a loop.

The daemon does not request power assertions, so it should not keep the Mac awake. It will sleep when macOS sleeps and continue after wake.

Check whether the LaunchAgent is loaded:

```sh
./Scripts/status-launch-agent.sh
```

Remove it:

```sh
./Scripts/uninstall-launch-agent.sh
```

Logs are written to:

```text
~/Library/Logs/AppleMusicDiscordRPC/stdout.log
~/Library/Logs/AppleMusicDiscordRPC/stderr.log
```

## Options

```text
--app-id <id>              Discord application ID. Can also be set with DISCORD_APP_ID.
--poll-interval <seconds>  Poll interval for Music updates. Defaults to 5.
--once                     Read Music once, update Discord once, then exit.
--clear                    Clear Discord Rich Presence and exit.
--verbose                  Print connection and update details.
--no-album-art             Disable album and artist image lookup and send text-only presence.
--help                     Show help text.
```

## macOS Automation Permission

The first run may ask for permission to let the terminal control Music. Allow it.

If permission was denied, reset it in:

System Settings -> Privacy & Security -> Automation

Then allow your terminal app to control Music and run the command again.

## Test

```sh
swift test
```

Check formatting and style rules:

```sh
swift format lint --recursive --strict Sources Tests Package.swift
```

If `xcode-select -p` points at Command Line Tools and `swift test` cannot find the Swift Testing plugin, run with a full Xcode developer directory:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
```

If this repo is stored in a File Provider backed Documents folder and codesign reports `resource fork, Finder information, or similar detritus not allowed`, use a temporary scratch path:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --scratch-path /private/tmp/apple-music-discord-rpc-build
```

Manual verification:

1. Start Discord Desktop.
2. Start Apple Music and play a song.
3. Run `DISCORD_APP_ID=... swift run apple-music-discord-rpc --once`.
4. Confirm Discord shows the song title, compact artist credits, album, album cover, small artist image when available, and duration bar.
5. Run the daemon without `--once`, pause Music, and confirm the presence clears.
