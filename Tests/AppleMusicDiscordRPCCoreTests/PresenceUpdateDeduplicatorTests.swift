import Foundation
import Testing

@testable import AppleMusicDiscordRPCCore

@Suite
struct PresenceUpdateDeduplicatorTests {
    @Test
    func setsFirstSnapshotThenSkipsUnchangedPlayback() {
        var deduplicator = PresenceUpdateDeduplicator(
            seekDriftThreshold: 5,
            refreshInterval: 60
        )
        let firstDate = Date(timeIntervalSince1970: 100)
        let firstSnapshot = snapshot(position: 10, capturedAt: firstDate)

        assertSet(deduplicator.action(for: firstSnapshot, at: firstDate))
        deduplicator.markSet(firstSnapshot, at: firstDate)

        let secondDate = Date(timeIntervalSince1970: 105)
        let secondSnapshot = snapshot(position: 15, capturedAt: secondDate)

        #expect(deduplicator.action(for: secondSnapshot, at: secondDate) == .skip)
    }

    @Test
    func setsWhenTrackChanges() {
        var deduplicator = PresenceUpdateDeduplicator()
        let date = Date(timeIntervalSince1970: 100)
        let firstSnapshot = snapshot(trackID: "track-1", position: 10, capturedAt: date)
        let secondSnapshot = snapshot(trackID: "track-2", title: "Other Song", position: 11, capturedAt: date)

        deduplicator.markSet(firstSnapshot, at: date)

        assertSet(deduplicator.action(for: secondSnapshot, at: date))
    }

    @Test
    func setsWhenArtistImageChanges() {
        var deduplicator = PresenceUpdateDeduplicator()
        let date = Date(timeIntervalSince1970: 100)
        let firstSnapshot = snapshot(
            position: 10,
            capturedAt: date,
            artistImageURL: URL(string: "https://example.com/artist-1.jpg")
        )
        let secondSnapshot = snapshot(
            position: 10,
            capturedAt: date,
            artistImageURL: URL(string: "https://example.com/artist-2.jpg")
        )

        deduplicator.markSet(firstSnapshot, at: date)

        assertSet(deduplicator.action(for: secondSnapshot, at: date))
    }

    @Test
    func setsWhenSeekDriftIsMaterial() {
        var deduplicator = PresenceUpdateDeduplicator(
            seekDriftThreshold: 5,
            refreshInterval: 60
        )
        let firstDate = Date(timeIntervalSince1970: 100)
        let firstSnapshot = snapshot(position: 10, capturedAt: firstDate)

        deduplicator.markSet(firstSnapshot, at: firstDate)

        let secondDate = Date(timeIntervalSince1970: 105)
        let seekedSnapshot = snapshot(position: 60, capturedAt: secondDate)

        assertSet(deduplicator.action(for: seekedSnapshot, at: secondDate))
    }

    @Test
    func refreshesAfterRefreshInterval() {
        var deduplicator = PresenceUpdateDeduplicator(
            seekDriftThreshold: 5,
            refreshInterval: 60
        )
        let firstDate = Date(timeIntervalSince1970: 100)
        let firstSnapshot = snapshot(position: 10, capturedAt: firstDate)

        deduplicator.markSet(firstSnapshot, at: firstDate)

        let secondDate = Date(timeIntervalSince1970: 161)
        let secondSnapshot = snapshot(position: 71, capturedAt: secondDate)

        assertSet(deduplicator.action(for: secondSnapshot, at: secondDate))
    }

    @Test
    func clearsInitialNilSnapshotOnce() {
        var deduplicator = PresenceUpdateDeduplicator()
        let date = Date(timeIntervalSince1970: 100)

        #expect(deduplicator.action(for: nil, at: date) == .clear)
        deduplicator.markCleared()
        #expect(deduplicator.action(for: nil, at: date) == .skip)
    }

    @Test
    func clearsOnceWhenPlaybackStops() {
        var deduplicator = PresenceUpdateDeduplicator()
        let date = Date(timeIntervalSince1970: 100)
        let firstSnapshot = snapshot(position: 10, capturedAt: date)

        deduplicator.markSet(firstSnapshot, at: date)

        #expect(deduplicator.action(for: nil, at: date) == .clear)
        deduplicator.markCleared()
        #expect(deduplicator.action(for: nil, at: date) == .skip)
    }

    private func snapshot(
        trackID: String = "track-1",
        title: String = "Song",
        artist: String = "Artist",
        position: TimeInterval,
        capturedAt: Date,
        artistImageURL: URL? = nil
    ) -> MusicSnapshot {
        MusicSnapshot(
            trackID: trackID,
            title: title,
            artist: artist,
            duration: 180,
            position: position,
            capturedAt: capturedAt,
            artistImageURL: artistImageURL
        )
    }

    private func assertSet(_ action: PresenceUpdateAction) {
        guard case .set = action else {
            Issue.record("Expected set action, got \(action).")
            return
        }
    }
}
