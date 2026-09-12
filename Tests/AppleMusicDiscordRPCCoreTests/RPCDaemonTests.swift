import Foundation
import Testing

@testable import AppleMusicDiscordRPCCore

@Suite
struct RPCDaemonTests {
    @Test
    func processesRunLoopEventsBetweenPolls() {
        let fired = TimerFlag()
        let timer = Timer(timeInterval: 0.01, repeats: false) { _ in fired.markFired() }
        RunLoop.current.add(timer, forMode: .default)
        defer { timer.invalidate() }
        let daemon = makeDaemon(snapshot: nil, discordClient: SpyDiscordClient())
        let deadline = Date().addingTimeInterval(0.1)
        daemon.runUntilStopped { fired.hasFired || Date() >= deadline }
        #expect(fired.hasFired)
    }

    @Test
    func runOnceSetsActivityForPlayingTrack() throws {
        let discordClient = SpyDiscordClient()
        let daemon = makeDaemon(snapshot: snapshot(), discordClient: discordClient)

        try daemon.runOnce()

        #expect(discordClient.setActivities.count == 1)
        #expect(discordClient.setActivities.first?.details == "Song")
        #expect(discordClient.clearCount == 0)
    }

    @Test
    func runOnceSkipsDuplicateUpdates() throws {
        let discordClient = SpyDiscordClient()
        let daemon = makeDaemon(snapshot: snapshot(), discordClient: discordClient)

        try daemon.runOnce()
        try daemon.runOnce()

        #expect(discordClient.setActivities.count == 1)
    }

    @Test
    func failedSetActivityIsRetriedOnNextUpdate() throws {
        let discordClient = SpyDiscordClient()
        discordClient.setActivityError = DiscordIPCError.disconnected
        let daemon = makeDaemon(snapshot: snapshot(), discordClient: discordClient)

        #expect(throws: DiscordIPCError.disconnected) {
            try daemon.runOnce()
        }

        discordClient.setActivityError = nil
        try daemon.runOnce()

        #expect(discordClient.setActivities.count == 1)
    }

    @Test
    func runOnceClearsWhenNothingIsPlaying() throws {
        let discordClient = SpyDiscordClient()
        let daemon = makeDaemon(snapshot: nil, discordClient: discordClient)

        try daemon.runOnce()

        #expect(discordClient.setActivities.isEmpty)
        #expect(discordClient.clearCount == 1)
    }

    @Test
    func runUntilStoppedClearsPresenceOnExit() {
        let discordClient = SpyDiscordClient()
        let daemon = makeDaemon(snapshot: snapshot(), discordClient: discordClient)

        var updates = 0
        daemon.runUntilStopped {
            updates += 1
            return updates > 1
        }

        #expect(discordClient.setActivities.count == 1)
        #expect(discordClient.clearCount == 1)
    }

    private func makeDaemon(
        snapshot: MusicSnapshot?,
        discordClient: SpyDiscordClient
    ) -> AppleMusicDiscordRPCDaemon {
        AppleMusicDiscordRPCDaemon(
            musicClient: StubSnapshotProvider(snapshot: snapshot),
            discordClient: discordClient,
            pollInterval: 0.01
        )
    }

    private func snapshot() -> MusicSnapshot {
        MusicSnapshot(
            trackID: "track-1",
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 180,
            position: 15,
            capturedAt: Date(timeIntervalSince1970: 100)
        )
    }
}

private final class StubSnapshotProvider: MusicSnapshotProvider {
    private let snapshot: MusicSnapshot?

    init(snapshot: MusicSnapshot?) {
        self.snapshot = snapshot
    }

    func currentSnapshot(at date: Date) throws -> MusicSnapshot? {
        guard let snapshot else {
            return nil
        }

        return MusicSnapshot(
            trackID: snapshot.trackID,
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            duration: snapshot.duration,
            position: snapshot.position,
            capturedAt: date
        )
    }
}

private final class SpyDiscordClient: DiscordPresenceClient {
    private(set) var setActivities: [DiscordActivity] = []
    private(set) var clearCount = 0
    var setActivityError: Error?

    func setActivity(_ activity: DiscordActivity) throws {
        if let setActivityError {
            throw setActivityError
        }
        setActivities.append(activity)
    }

    func clearActivity() throws {
        clearCount += 1
    }
}

private final class TimerFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    var hasFired: Bool { lock.withLock { fired } }
    func markFired() { lock.withLock { fired = true } }
}
