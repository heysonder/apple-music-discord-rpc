import Foundation

public protocol AlbumArtworkResolver {
    func artworkURL(for snapshot: MusicSnapshot) -> URL?
}

public protocol ArtistImageResolver {
    func artistImageURL(for snapshot: MusicSnapshot) -> URL?
}

public final class CascadingAlbumArtworkResolver: AlbumArtworkResolver {
    private let resolvers: [AlbumArtworkResolver]
    private let logger: Logger

    public init(
        resolvers: [AlbumArtworkResolver],
        logger: Logger = .quiet
    ) {
        self.resolvers = resolvers
        self.logger = logger
    }

    public func artworkURL(for snapshot: MusicSnapshot) -> URL? {
        for resolver in resolvers {
            if let url = resolver.artworkURL(for: snapshot) {
                return url
            }
        }

        logger.log("No album art match found for \(snapshot.title) - \(snapshot.artist).")
        return nil
    }
}

public final class ArtworkEnrichingMusicSnapshotProvider: MusicSnapshotProvider {
    private let baseProvider: MusicSnapshotProvider
    private let artworkResolver: AlbumArtworkResolver
    private let artistImageResolver: ArtistImageResolver?

    private var albumArtworkCache = ResolutionCache<ArtworkCacheKey, URL>()
    private var artistImageCache = ResolutionCache<ArtistImageCacheKey, URL>()

    public init(
        baseProvider: MusicSnapshotProvider,
        artworkResolver: AlbumArtworkResolver,
        artistImageResolver: ArtistImageResolver? = nil
    ) {
        self.baseProvider = baseProvider
        self.artworkResolver = artworkResolver
        self.artistImageResolver = artistImageResolver
    }

    public func currentSnapshot(at date: Date) throws -> MusicSnapshot? {
        guard let snapshot = try baseProvider.currentSnapshot(at: date) else {
            return nil
        }

        var didResolve = false
        let albumURL = albumArtworkCache.value(for: ArtworkCacheKey(snapshot: snapshot), at: date) {
            didResolve = true
            return artworkResolver.artworkURL(for: snapshot)
        }
        let artistURL = artistImageCache.value(for: ArtistImageCacheKey(snapshot: snapshot), at: date) {
            guard let artistImageResolver else { return nil }
            didResolve = true
            return artistImageResolver.artistImageURL(for: snapshot)
        }

        // Network lookups can outlast a pause or track change. Never publish stale music.
        let current: MusicSnapshot
        if didResolve {
            guard let refreshed = try baseProvider.currentSnapshot(at: Date()) else { return nil }
            guard ArtworkCacheKey(snapshot: refreshed) == ArtworkCacheKey(snapshot: snapshot) else {
                return refreshed
            }
            current = refreshed
        } else {
            current = snapshot
        }
        return current.withArtworkURLs(albumArtworkURL: albumURL, artistImageURL: artistURL)
    }
}

private struct ArtworkCacheKey: Hashable {
    let trackID: String
    let title: String
    let artist: String
    let album: String

    init(snapshot: MusicSnapshot) {
        trackID = snapshot.trackID
        title = snapshot.title
        artist = snapshot.artist
        album = snapshot.album
    }
}

private struct ArtistImageCacheKey: Hashable {
    let artist: String

    init(snapshot: MusicSnapshot) {
        artist = ArtworkTextMatcher.comparable(snapshot.artist.primaryArtistNameForLookup)
    }
}

// Bounded URL metadata only. Misses expire so a temporary outage is recoverable.
struct ResolutionCache<Key: Hashable, Value> {
    private struct Entry {
        let value: Value?
        let expiresAt: Date
    }

    private let capacity: Int
    private let missLifetime: TimeInterval
    private var storage: [Key: Entry] = [:]
    private var insertionOrder: [Key] = []

    init(capacity: Int = 256, missLifetime: TimeInterval = 300) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.missLifetime = missLifetime
    }

    mutating func value(for key: Key, at date: Date, resolve: () -> Value?) -> Value? {
        if let entry = storage[key], date < entry.expiresAt {
            return entry.value
        }

        let resolvedValue = resolve()
        if storage[key] != nil {
            insertionOrder.removeAll { $0 == key }
        } else if storage.count >= capacity {
            storage.removeValue(forKey: insertionOrder.removeFirst())
        }
        insertionOrder.append(key)
        storage[key] = Entry(
            value: resolvedValue,
            expiresAt: resolvedValue == nil ? date.addingTimeInterval(missLifetime) : .distantFuture
        )
        return resolvedValue
    }
}
