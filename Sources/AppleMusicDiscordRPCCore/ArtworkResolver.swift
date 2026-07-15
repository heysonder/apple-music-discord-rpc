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

        return snapshot.withArtworkURLs(
            albumArtworkURL: albumArtworkCache.value(for: ArtworkCacheKey(snapshot: snapshot)) {
                artworkResolver.artworkURL(for: snapshot)
            },
            artistImageURL: resolvedArtistImage(for: snapshot)
        )
    }

    private func resolvedArtistImage(for snapshot: MusicSnapshot) -> URL? {
        guard let artistImageResolver else {
            return nil
        }

        return artistImageCache.value(for: ArtistImageCacheKey(snapshot: snapshot)) {
            artistImageResolver.artistImageURL(for: snapshot)
        }
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

private struct ResolutionCache<Key: Hashable, Value> {
    private var storage: [Key: Value?] = [:]

    mutating func value(for key: Key, resolve: () -> Value?) -> Value? {
        if case .some(let cachedValue) = storage[key] {
            return cachedValue
        }

        let resolvedValue = resolve()
        storage.updateValue(resolvedValue, forKey: key)
        return resolvedValue
    }
}
