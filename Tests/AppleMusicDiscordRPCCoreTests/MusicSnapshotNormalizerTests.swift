import Foundation
import Testing

@testable import AppleMusicDiscordRPCCore

@Suite
struct MusicSnapshotNormalizerTests {
    @Test
    func returnsNilWhenMusicIsNotRunning() {
        let snapshot = MusicSnapshotNormalizer.normalize(
            RawMusicSnapshot(appIsRunning: false),
            capturedAt: Date(timeIntervalSince1970: 100)
        )

        #expect(snapshot == nil)
    }

    @Test
    func returnsNilWhenMusicIsPaused() {
        let snapshot = MusicSnapshotNormalizer.normalize(
            RawMusicSnapshot(
                appIsRunning: true,
                playerState: .paused,
                title: "Song",
                artist: "Artist"
            ),
            capturedAt: Date(timeIntervalSince1970: 100)
        )

        #expect(snapshot == nil)
    }

    @Test
    func returnsNilWhenTitleIsMissing() {
        let snapshot = MusicSnapshotNormalizer.normalize(
            RawMusicSnapshot(
                appIsRunning: true,
                playerState: .playing,
                title: "   ",
                artist: "Artist"
            ),
            capturedAt: Date(timeIntervalSince1970: 100)
        )

        #expect(snapshot == nil)
    }

    @Test
    func normalizesPlayingTrack() throws {
        let date = Date(timeIntervalSince1970: 100)
        let snapshot = try #require(
            MusicSnapshotNormalizer.normalize(
                RawMusicSnapshot(
                    appIsRunning: true,
                    playerState: .playing,
                    title: "  Song \"A&B\"  ",
                    artist: "  Artist / Name  ",
                    album: "  Album Name  ",
                    durationMilliseconds: 180_000,
                    positionMilliseconds: 12_500,
                    persistentID: "track-1"
                ),
                capturedAt: date
            ))

        #expect(snapshot.trackID == "track-1")
        #expect(snapshot.title == "Song \"A&B\"")
        #expect(snapshot.artist == "Artist / Name")
        #expect(snapshot.album == "Album Name")
        #expect(snapshot.duration == 180)
        #expect(snapshot.position == 12.5)
        #expect(snapshot.capturedAt == date)
    }

    @Test
    func usesUnknownArtistFallbackAndClampsPosition() throws {
        let snapshot = try #require(
            MusicSnapshotNormalizer.normalize(
                RawMusicSnapshot(
                    appIsRunning: true,
                    playerState: .playing,
                    title: "Song",
                    artist: "",
                    durationMilliseconds: 100_000,
                    positionMilliseconds: 120_000,
                    persistentID: ""
                ),
                capturedAt: Date(timeIntervalSince1970: 100)
            ))

        #expect(snapshot.trackID == "Song")
        #expect(snapshot.artist == "Unknown Artist")
        #expect(snapshot.position == 100)
    }

    @Test
    func discordActivityIncludesDerivedTimestamps() throws {
        let snapshot = MusicSnapshot(
            trackID: "track-1",
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 180,
            position: 15,
            capturedAt: Date(timeIntervalSince1970: 1_000),
            artworkURL: URL(string: "https://example.com/cover.jpg"),
            artistImageURL: URL(string: "https://example.com/artist.jpg")
        )

        let activity = snapshot.discordActivity()

        #expect(activity.details == "Song")
        #expect(activity.state == "Artist")
        #expect(activity.timestamps?.start == 985)
        #expect(activity.timestamps?.end == 1_165)
        #expect(activity.assets?.largeImage == "https://example.com/cover.jpg")
        #expect(activity.assets?.largeText == "Album")
        #expect(activity.assets?.smallImage == "https://example.com/artist.jpg")
        #expect(activity.assets?.smallText == "Artist")
    }

    @Test
    func discordActivityCompactsLongArtistCredits() throws {
        let snapshot = MusicSnapshot(
            trackID: "track-1",
            title: "ICONIC BY MISTAKE",
            artist: "LE SSERAFIM, ILLIT & KATSEYE",
            album: "ICONIC BY MISTAKE - Single",
            duration: 178,
            position: 14,
            capturedAt: Date(timeIntervalSince1970: 1_000),
            artworkURL: URL(string: "https://example.com/cover.jpg"),
            artistImageURL: URL(string: "https://example.com/artist.jpg")
        )

        let activity = snapshot.discordActivity()

        #expect(activity.details == "ICONIC BY MISTAKE")
        #expect(activity.state == "LE SSERAFIM + 2 more")
        #expect(activity.assets?.largeText == "ICONIC BY MISTAKE - Single")
        #expect(activity.assets?.smallText == "LE SSERAFIM, ILLIT & KATSEYE")
    }

    @Test
    func discordActivityCanSendOnlyArtistImage() throws {
        let snapshot = MusicSnapshot(
            trackID: "track-1",
            title: "Song",
            artist: "Artist",
            duration: 180,
            position: 15,
            capturedAt: Date(timeIntervalSince1970: 1_000),
            artistImageURL: URL(string: "https://example.com/artist.jpg")
        )

        let activity = snapshot.discordActivity()

        #expect(activity.assets?.largeImage == nil)
        #expect(activity.assets?.smallImage == "https://example.com/artist.jpg")
        #expect(activity.assets?.smallText == "Artist")
    }

    @Test
    func discordActivityDoesNotSplitSingleArtistCommaNames() throws {
        let snapshot = MusicSnapshot(
            trackID: "track-1",
            title: "Song",
            artist: "Tyler, The Creator",
            duration: 180,
            position: 15,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(snapshot.discordActivity().state == "Tyler, The Creator")
    }
}
