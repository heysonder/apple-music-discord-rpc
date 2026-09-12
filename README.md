# Apple Music Discord RPC

A lightweight macOS Swift CLI that mirrors the currently playing Apple Music track into Discord Rich Presence.

It runs locally in the background with no third-party dependencies:

- Reads Apple Music with AppleScript, including Radio tracks when Music provides song metadata.
- Talks to Discord Desktop through its local IPC RPC socket.
- Shows song title, compact artist credits, album, elapsed time, total duration, album cover, and a small artist image when public artwork can be resolved.
- Clears the presence when Music is paused, stopped, closed, or the daemon exits.
- Uses no bot token, OAuth token, client secret, server, or third-party package.

## Requirements

- macOS 13 or later
- Swift 6 toolchain (Xcode or Command Line Tools) to build
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

Album cover matching requires both title and artist agreement. If no confident image match is found, Discord still receives text presence, with timing information when Music provides it.

Artwork lookup is synchronous: slow services can delay an initial update. Each HTTP request has a five-second timeout, and Cover Art Archive fallback checks at most three release groups. After lookup, playback is read again to avoid publishing a song that has been paused or changed.

## Build

```sh
swift build
```

## Run

Run once (the process exits after sending the update; use daemon mode for persistent presence):

```sh
DISCORD_APP_ID=123456789012345678 swift run apple-music-discord-rpc --once
```

Run as a foreground daemon:

```sh
DISCORD_APP_ID=123456789012345678 swift run apple-music-discord-rpc
```

Send a one-time clear request (stop the installed service first if you want presence to stay cleared):

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
- `KeepAlive=true` with a 30-second restart throttle, so it recovers if the process exits.

The daemon does not request power assertions, so it should not keep the Mac awake. It will sleep when macOS sleeps and continue after wake.

Rerun the installer after updating the source to rebuild and reload the service. The installed agent points at this checkout’s release binary, so keep the project in place or reinstall after moving it.

Check whether the LaunchAgent is loaded:

```sh
./Scripts/status-launch-agent.sh
```

Stop it and remove automatic startup:

```sh
./Scripts/uninstall-launch-agent.sh
```

Update failures are logged even without `--verbose`; repeated identical failures are suppressed until recovery. Use `--verbose` for track and artwork diagnostics.

Logs are written to:

```text
~/Library/Logs/AppleMusicDiscordRPC/stdout.log
~/Library/Logs/AppleMusicDiscordRPC/stderr.log
```

## Resource Use and Recovery

- Polls Music every 10 seconds when installed, or every 5 seconds in foreground mode by default.
- Reuses its AppleScript instance and releases temporary Objective-C objects after each poll.
- Services the main run loop between polls so Music launch and quit information stays current.
- Skips unchanged presence updates, with a periodic refresh every 60 seconds.
- Stores at most 256 entries in each artwork cache. These contain URLs, not image files; missing images can be retried after five minutes.
- Retries Discord connections with exponential backoff capped at 30 seconds.
- Restarts through launchd if the installed service exits, with a 30-second launch throttle.
- Logs update failures with timestamps even in normal mode, while suppressing consecutive identical errors.

Resource use varies with playback and artwork requests. No power assertions or additional runtime packages are required.

## Troubleshooting

If presence stops updating:

1. Confirm Discord Desktop is running and Music is playing a track with a title.
2. Run `./Scripts/status-launch-agent.sh` to check the service. A running process alone does not confirm successful updates.
3. Read the error log:

   ```sh
   tail -n 50 ~/Library/Logs/AppleMusicDiscordRPC/stderr.log
   ```

4. For connection, song, and artwork diagnostics, reinstall with verbose logging:

   ```sh
   ./Scripts/install-launch-agent.sh --app-id 123456789012345678 --verbose
   ```

   Rerun without `--verbose` to return to normal error logging.

For a one-time restart of the installed service:

```sh
launchctl kickstart -k "gui/$(id -u)/com.chase.apple-music-discord-rpc"
```

If the log reports an Automation permission error, check the permissions below. Artwork failures do not require restarting the daemon; unsuccessful lookups expire from the cache after five minutes.

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

The regression suite covers playback normalization, update deduplication and retries, run-loop servicing, artwork matching and cache eviction/expiry, track changes during lookups, IPC validation, and CLI parsing. Tests use local fixtures and stubs.

Manual verification:

1. Start Discord Desktop.
2. Start Apple Music and play a song.
3. Run `DISCORD_APP_ID=... swift run apple-music-discord-rpc --verbose` (stop the installed service first to avoid running two copies).
4. Confirm Discord shows the song title, compact artist credits, album, album cover, small artist image when available, and duration bar.
5. Pause Music and confirm the presence clears; resume playback and confirm it returns.
6. Quit and reopen Music, then restart Discord, and confirm the daemon resumes updates.
7. Try an Apple Music Radio track with song metadata and confirm the title and artist appear.
