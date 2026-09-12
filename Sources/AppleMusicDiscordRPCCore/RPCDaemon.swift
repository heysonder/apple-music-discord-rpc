import CoreFoundation
import Foundation

public final class AppleMusicDiscordRPCDaemon {
    private let musicClient: MusicSnapshotProvider
    private let discordClient: DiscordPresenceClient
    private let pollInterval: TimeInterval
    private let logger: Logger
    private var deduplicator: PresenceUpdateDeduplicator
    private var lastUpdateError: String?

    public init(
        musicClient: MusicSnapshotProvider,
        discordClient: DiscordPresenceClient,
        pollInterval: TimeInterval,
        logger: Logger = .quiet,
        deduplicator: PresenceUpdateDeduplicator = PresenceUpdateDeduplicator()
    ) {
        self.musicClient = musicClient
        self.discordClient = discordClient
        self.pollInterval = pollInterval
        self.logger = logger
        self.deduplicator = deduplicator
    }

    public func runOnce() throws {
        try updateOnce()
    }

    public func clear() throws {
        try discordClient.clearActivity()
        deduplicator.markCleared()
        logger.log("Cleared Discord Rich Presence.")
    }

    public func runUntilStopped(shouldStop: () -> Bool) {
        defer {
            do {
                try clear()
            } catch {
                logger.error("Failed to clear Discord Rich Presence on exit: \(error.localizedDescription)")
            }
        }

        while !shouldStop() {
            autoreleasepool {
                do {
                    try updateOnce()
                    lastUpdateError = nil
                } catch DiscordIPCError.reconnectBackoff {
                    // The original failure is already logged; wait for the retry window.
                } catch {
                    let message = error.localizedDescription
                    if message != lastUpdateError {
                        logger.error("Update failed: \(message)")
                        lastUpdateError = message
                    }
                }
            }

            sleepRespectingStop(shouldStop: shouldStop)
        }
    }

    private func updateOnce() throws {
        let now = Date()
        let snapshot = try musicClient.currentSnapshot(at: now)
        let action = deduplicator.action(for: snapshot, at: now)

        try apply(action, at: now)
    }

    private func apply(_ action: PresenceUpdateAction, at date: Date) throws {
        switch action {
        case .set(let activity, let snapshot):
            try discordClient.setActivity(activity)
            deduplicator.markSet(snapshot, at: date)
            logger.log("Updated Discord Rich Presence: \(snapshot.title) - \(snapshot.artist)")
        case .clear:
            try clear()
        case .skip:
            break
        }
    }

    private func sleepRespectingStop(shouldStop: () -> Bool) {
        let deadline = Date().addingTimeInterval(pollInterval)
        while !shouldStop(), Date() < deadline {
            let interval = min(1, max(0, deadline.timeIntervalSinceNow))
            autoreleasepool {
                // AppKit refreshes running-application state on the main run loop.
                // Sleeping alone leaves Music launch/quit information stale.
                let result = CFRunLoopRunInMode(.defaultMode, interval, false)
                if result == .finished {
                    Thread.sleep(forTimeInterval: interval)
                }
            }
        }
    }
}
