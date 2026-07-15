import Foundation

public enum PresenceUpdateAction: Equatable {
    case set(DiscordActivity, MusicSnapshot)
    case clear
    case skip
}

public struct PresenceUpdateDeduplicator {
    private let seekDriftThreshold: TimeInterval
    private let refreshInterval: TimeInterval
    private var lastSentSnapshot: MusicSnapshot?
    private var lastSentAt: Date?
    private var hasActivePresence = false
    private var hasObservedTerminalState = false

    public init(
        seekDriftThreshold: TimeInterval = 5,
        refreshInterval: TimeInterval = 60
    ) {
        self.seekDriftThreshold = seekDriftThreshold
        self.refreshInterval = refreshInterval
    }

    public func action(for snapshot: MusicSnapshot?, at date: Date) -> PresenceUpdateAction {
        guard let snapshot else {
            return (hasActivePresence || !hasObservedTerminalState) ? .clear : .skip
        }

        guard let lastSentSnapshot else {
            return .set(snapshot.discordActivity(), snapshot)
        }

        if shouldResend(previous: lastSentSnapshot, current: snapshot, at: date) {
            return .set(snapshot.discordActivity(), snapshot)
        }

        return .skip
    }

    public mutating func markSet(_ snapshot: MusicSnapshot, at date: Date) {
        lastSentSnapshot = snapshot
        lastSentAt = date
        hasActivePresence = true
        hasObservedTerminalState = true
    }

    public mutating func markCleared() {
        lastSentSnapshot = nil
        lastSentAt = nil
        hasActivePresence = false
        hasObservedTerminalState = true
    }

    private func shouldResend(previous: MusicSnapshot, current: MusicSnapshot, at date: Date) -> Bool {
        metadataChanged(from: previous, to: current) || seekDriftExceeded(from: previous, to: current, at: date)
            || refreshIntervalElapsed(at: date)
    }

    private func metadataChanged(from previous: MusicSnapshot, to current: MusicSnapshot) -> Bool {
        previous.trackID != current.trackID || previous.title != current.title || previous.artist != current.artist
            || previous.album != current.album || previous.duration != current.duration
            || previous.artworkURL != current.artworkURL || previous.artistImageURL != current.artistImageURL
    }

    private func seekDriftExceeded(
        from previous: MusicSnapshot,
        to current: MusicSnapshot,
        at date: Date
    ) -> Bool {
        switch (previous.position, current.position) {
        case (.none, .none):
            return false
        case (.some, .none), (.none, .some):
            return true
        case (.some(let previousPosition), .some(let currentPosition)):
            let elapsed = max(0, date.timeIntervalSince(previous.capturedAt))
            let expectedPosition = min(
                previousPosition + elapsed,
                previous.duration ?? .greatestFiniteMagnitude
            )
            return abs(currentPosition - expectedPosition) >= seekDriftThreshold
        }
    }

    private func refreshIntervalElapsed(at date: Date) -> Bool {
        guard let lastSentAt else {
            return false
        }

        return date.timeIntervalSince(lastSentAt) >= refreshInterval
    }
}
