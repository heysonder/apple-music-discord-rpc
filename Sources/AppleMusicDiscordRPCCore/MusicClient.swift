import AppKit
import Foundation

public protocol MusicSnapshotProvider {
    func currentSnapshot(at date: Date) throws -> MusicSnapshot?
}

public final class AppleScriptMusicClient: MusicSnapshotProvider {
    private let bundleIdentifier = "com.apple.Music"

    public init() {}

    public func currentSnapshot(at date: Date = Date()) throws -> MusicSnapshot? {
        let rawSnapshot = try rawSnapshot()
        return MusicSnapshotNormalizer.normalize(rawSnapshot, capturedAt: date)
    }

    private func rawSnapshot() throws -> RawMusicSnapshot {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty else {
            return RawMusicSnapshot(appIsRunning: false)
        }

        guard let script = NSAppleScript(source: Self.scriptSource) else {
            throw MusicClientError.scriptInitializationFailed
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            throw MusicClientError.appleScriptFailed(errorInfo.description)
        }

        guard descriptor.numberOfItems >= 7 else {
            throw MusicClientError.unexpectedScriptResult
        }

        let state = MusicPlayerState(appleScriptValue: descriptor.stringValue(at: .playerState))
        let title = descriptor.stringValue(at: .title)
        let artist = descriptor.stringValue(at: .artist)
        let album = descriptor.stringValue(at: .album)
        let durationMilliseconds = descriptor.integerValue(at: .durationMilliseconds)
        let positionMilliseconds = descriptor.integerValue(at: .positionMilliseconds)
        let persistentID = descriptor.stringValue(at: .persistentID)

        return RawMusicSnapshot(
            appIsRunning: true,
            playerState: state,
            title: title,
            artist: artist,
            album: album,
            durationMilliseconds: durationMilliseconds,
            positionMilliseconds: positionMilliseconds,
            persistentID: persistentID
        )
    }

    private static let scriptSource = """
        tell application id "com.apple.Music"
            set trackName to ""
            set trackArtist to ""
            set trackAlbum to ""
            set trackDurationMilliseconds to "0"
            set trackPositionMilliseconds to "0"
            set trackPersistentID to ""

            try
                set trackPositionMilliseconds to ((round ((player position) * 1000)) as integer) as text
            end try

            if player state is playing then
                try
                    set currentTrack to current track
                    set trackName to (name of currentTrack) as text
                    set trackArtist to (artist of currentTrack) as text
                    set trackAlbum to (album of currentTrack) as text
                    set trackDurationMilliseconds to ((round ((duration of currentTrack) * 1000)) as integer) as text
                    set trackPersistentID to (persistent ID of currentTrack) as text
                end try
            end if

            return {(player state as text), trackName, trackArtist, trackAlbum, trackDurationMilliseconds, trackPositionMilliseconds, trackPersistentID}
        end tell
        """
}

public enum MusicClientError: LocalizedError, Equatable {
    case scriptInitializationFailed
    case appleScriptFailed(String)
    case unexpectedScriptResult

    public var errorDescription: String? {
        switch self {
        case .scriptInitializationFailed:
            return "Failed to initialize AppleScript for Music."
        case .appleScriptFailed(let message):
            return "Music AppleScript failed: \(message)"
        case .unexpectedScriptResult:
            return "Music AppleScript returned an unexpected result."
        }
    }
}

private extension NSAppleEventDescriptor {
    func stringValue(at index: MusicScriptResultIndex) -> String {
        atIndex(index.rawValue)?.stringValue ?? ""
    }

    func integerValue(at index: MusicScriptResultIndex) -> Int {
        Int(stringValue(at: index)) ?? 0
    }
}

private enum MusicScriptResultIndex: Int {
    case playerState = 1
    case title
    case artist
    case album
    case durationMilliseconds
    case positionMilliseconds
    case persistentID
}
