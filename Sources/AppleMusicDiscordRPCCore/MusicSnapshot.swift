import Foundation

public enum MusicPlayerState: String, Equatable {
    case playing
    case paused
    case stopped
    case fastForwarding
    case rewinding
    case unknown

    public init(appleScriptValue: String) {
        let normalized =
            appleScriptValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "playing":
            self = .playing
        case "paused":
            self = .paused
        case "stopped":
            self = .stopped
        case "fast forwarding":
            self = .fastForwarding
        case "rewinding":
            self = .rewinding
        default:
            self = .unknown
        }
    }
}

public struct RawMusicSnapshot: Equatable {
    public let appIsRunning: Bool
    public let playerState: MusicPlayerState
    public let title: String
    public let artist: String
    public let album: String
    public let durationMilliseconds: Int
    public let positionMilliseconds: Int
    public let persistentID: String

    public init(
        appIsRunning: Bool,
        playerState: MusicPlayerState = .stopped,
        title: String = "",
        artist: String = "",
        album: String = "",
        durationMilliseconds: Int = 0,
        positionMilliseconds: Int = 0,
        persistentID: String = ""
    ) {
        self.appIsRunning = appIsRunning
        self.playerState = playerState
        self.title = title
        self.artist = artist
        self.album = album
        self.durationMilliseconds = durationMilliseconds
        self.positionMilliseconds = positionMilliseconds
        self.persistentID = persistentID
    }
}

public struct MusicSnapshot: Equatable {
    public let trackID: String
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval?
    public let position: TimeInterval?
    public let capturedAt: Date
    public let artworkURL: URL?
    public let artistImageURL: URL?

    public init(
        trackID: String,
        title: String,
        artist: String,
        album: String = "",
        duration: TimeInterval?,
        position: TimeInterval?,
        capturedAt: Date,
        artworkURL: URL? = nil,
        artistImageURL: URL? = nil
    ) {
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.position = position
        self.capturedAt = capturedAt
        self.artworkURL = artworkURL
        self.artistImageURL = artistImageURL
    }

    public func discordActivity() -> DiscordActivity {
        DiscordActivity(
            details: title,
            state: displayArtist,
            timestamps: discordTimestamps(),
            assets: discordAssets()
        )
    }

    public func withArtworkURL(_ artworkURL: URL?) -> MusicSnapshot {
        withArtworkURLs(albumArtworkURL: artworkURL, artistImageURL: artistImageURL)
    }

    public func withArtworkURLs(albumArtworkURL: URL?, artistImageURL: URL?) -> MusicSnapshot {
        MusicSnapshot(
            trackID: trackID,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: position,
            capturedAt: capturedAt,
            artworkURL: albumArtworkURL,
            artistImageURL: artistImageURL
        )
    }

    private func discordTimestamps() -> DiscordActivityTimestamps? {
        guard let position else {
            return nil
        }

        let start = Int64((capturedAt.timeIntervalSince1970 - position).rounded())
        let end: Int64?
        if let duration, duration > 0 {
            end = Int64((capturedAt.timeIntervalSince1970 - position + duration).rounded())
        } else {
            end = nil
        }

        let timestamps = DiscordActivityTimestamps(start: start, end: end)
        return timestamps.isEmpty ? nil : timestamps
    }

    private func discordAssets() -> DiscordActivityAssets? {
        guard artworkURL != nil || artistImageURL != nil else {
            return nil
        }

        return DiscordActivityAssets(
            largeImage: artworkURL?.absoluteString,
            largeText: artworkURL == nil || album.isEmpty ? nil : album,
            smallImage: artistImageURL?.absoluteString,
            smallText: artistImageURL == nil ? nil : artist
        )
    }

    private var displayArtist: String {
        let artists = artist.creditedArtistNames
        guard artists.count > 2 else {
            return artist
        }

        return "\(artists[0]) + \(artists.count - 1) more"
    }
}

public enum MusicSnapshotNormalizer {
    static let unknownArtist = "Unknown Artist"

    public static func normalize(_ raw: RawMusicSnapshot, capturedAt: Date) -> MusicSnapshot? {
        guard raw.appIsRunning, raw.playerState == .playing else {
            return nil
        }

        let title = raw.title.trimmed
        guard !title.isEmpty else {
            return nil
        }

        let artist = normalizedArtist(raw.artist)
        let album = raw.album.trimmed
        let duration = seconds(fromMilliseconds: raw.durationMilliseconds)
        let position = normalizedPosition(
            milliseconds: raw.positionMilliseconds,
            duration: duration
        )
        let trackID = raw.persistentID.trimmed

        return MusicSnapshot(
            trackID: trackID.isEmpty ? title : trackID,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: position,
            capturedAt: capturedAt
        )
    }

    private static func seconds(fromMilliseconds milliseconds: Int) -> TimeInterval? {
        guard milliseconds > 0 else {
            return nil
        }
        return TimeInterval(milliseconds) / 1000
    }

    private static func normalizedArtist(_ artist: String) -> String {
        let artist = artist.trimmed
        return artist.isEmpty ? unknownArtist : artist
    }

    private static func normalizedPosition(
        milliseconds: Int,
        duration: TimeInterval?
    ) -> TimeInterval? {
        guard milliseconds >= 0 else {
            return 0
        }

        let position = TimeInterval(milliseconds) / 1000
        if let duration, duration > 0 {
            return min(position, duration)
        }
        return position
    }
}
