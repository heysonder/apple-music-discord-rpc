import Foundation
import Testing

@testable import AppleMusicDiscordRPCCore

@Suite
struct AlbumArtworkResolverTests {
    @Test
    func buildsITunesSearchRequest() throws {
        let request = try #require(
            ITunesSearchArtworkResolver.searchRequest(
                for: snapshot(title: "Song Name", artist: "Artist Name", album: "Album Name")
            ))
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) }
        )

        #expect(components.scheme == "https")
        #expect(components.host == "itunes.apple.com")
        #expect(components.path == "/search")
        #expect(queryItems["term"] == "Song Name Artist Name Album Name")
        #expect(queryItems["media"] == "music")
        #expect(queryItems["entity"] == "song")
        #expect(queryItems["limit"] == "10")
    }

    @Test
    func skipsSearchWhenArtistIsUnknown() {
        let request = ITunesSearchArtworkResolver.searchRequest(
            for: snapshot(title: "Song Name", artist: "Unknown Artist", album: "Album Name")
        )

        #expect(request == nil)
    }

    @Test
    func buildsDeezerTrackSearchRequest() throws {
        let request = try #require(
            DeezerTrackArtworkResolver.searchRequest(
                for: snapshot(title: "Sun Has Set", artist: "beabadoobee", album: "")
            ))
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) }
        )

        #expect(components.scheme == "https")
        #expect(components.host == "api.deezer.com")
        #expect(components.path == "/search/track")
        #expect(queryItems["q"] == "Sun Has Set beabadoobee")
        #expect(queryItems["limit"] == "10")
    }

    @Test
    func buildsDeezerArtistSearchRequestFromPrimaryArtist() throws {
        let request = try #require(
            DeezerArtistImageResolver.searchRequest(
                for: snapshot(title: "ICONIC BY MISTAKE", artist: "LE SSERAFIM, ILLIT & KATSEYE")
            ))
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) }
        )

        #expect(components.scheme == "https")
        #expect(components.host == "api.deezer.com")
        #expect(components.path == "/search/artist")
        #expect(queryItems["q"] == "LE SSERAFIM")
        #expect(queryItems["limit"] == "5")
    }

    @Test
    func buildsMusicBrainzSearchRequest() throws {
        let request = try #require(
            MusicBrainzCoverArtResolver.searchRequest(
                for: snapshot(title: "Sun Has Set", artist: "beabadoobee", album: "")
            ))
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) }
        )

        #expect(components.scheme == "https")
        #expect(components.host == "musicbrainz.org")
        #expect(components.path == "/ws/2/recording")
        #expect(queryItems["query"] == #"recording:"Sun Has Set" AND artist:"beabadoobee""#)
        #expect(queryItems["fmt"] == "json")
        #expect(queryItems["limit"] == "10")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.isEmpty == false)
    }

    @Test
    func picksBestArtworkMatchAndExpandsImageSize() throws {
        let data = Data(
            """
            {
              "resultCount": 2,
              "results": [
                {
                  "trackName": "Other Song",
                  "artistName": "Artist Name",
                  "collectionName": "Album Name",
                  "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/other/source/100x100bb.jpg"
                },
                {
                  "trackName": "Song Name",
                  "artistName": "Artist Name",
                  "collectionName": "Album Name",
                  "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/match/source/100x100bb.jpg"
                }
              ]
            }
            """.utf8)

        let url = try #require(
            try ITunesSearchArtworkResolver.bestArtworkURL(
                from: data,
                for: snapshot(title: "Song Name", artist: "Artist Name", album: "Album Name")
            ))

        #expect(
            url.absoluteString == "https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/match/source/1024x1024bb.jpg")
    }

    @Test
    func picksBestDeezerArtworkMatch() throws {
        let data = Data(
            """
            {
              "data": [
                {
                  "title": "Other Song",
                  "artist": { "name": "beabadoobee" },
                  "album": {
                    "title": "Sun Has Set",
                    "cover_xl": "http://e-cdns-images.dzcdn.net/images/cover/other/1000x1000-000000-80-0-0.jpg"
                  }
                },
                {
                  "title": "Sun Has Set",
                  "artist": { "name": "beabadoobee" },
                  "album": {
                    "title": "Sun Has Set",
                    "cover_xl": "http://e-cdns-images.dzcdn.net/images/cover/match/1000x1000-000000-80-0-0.jpg"
                  }
                }
              ]
            }
            """.utf8)

        let url = try #require(
            try DeezerTrackArtworkResolver.bestArtworkURL(
                from: data,
                for: snapshot(title: "Sun Has Set", artist: "beabadoobee", album: "")
            ))

        #expect(url.absoluteString == "https://e-cdns-images.dzcdn.net/images/cover/match/1000x1000-000000-80-0-0.jpg")
    }

    @Test
    func picksBestDeezerArtistImageMatch() throws {
        let data = Data(
            """
            {
              "data": [
                {
                  "name": "Other Artist",
                  "picture_xl": "https://e-cdns-images.dzcdn.net/images/artist/other/1000x1000-000000-80-0-0.jpg"
                },
                {
                  "name": "beabadoobee",
                  "picture_xl": "https://e-cdns-images.dzcdn.net/images/artist/match/1000x1000-000000-80-0-0.jpg"
                }
              ]
            }
            """.utf8)

        let url = try #require(
            try DeezerArtistImageResolver.bestArtistImageURL(
                from: data,
                for: snapshot(title: "Sun Has Set", artist: "beabadoobee", album: "")
            ))

        #expect(url.absoluteString == "https://e-cdns-images.dzcdn.net/images/artist/match/1000x1000-000000-80-0-0.jpg")
    }

    @Test
    func picksMusicBrainzReleaseGroupCandidate() throws {
        let data = Data(
            """
            {
              "recordings": [
                {
                  "score": "100",
                  "title": "Sun Has Set",
                  "length": 142000,
                  "artist-credit": [
                    { "name": "beabadoobee", "artist": { "name": "beabadoobee" } }
                  ],
                  "releases": [
                    {
                      "title": "Sun Has Set",
                      "status": "Official",
                      "release-group": {
                        "id": "release-group-1",
                        "primary-type": "Single",
                        "secondary-types": []
                      }
                    }
                  ]
                }
              ]
            }
            """.utf8)

        let candidates = try MusicBrainzCoverArtResolver.releaseGroupCandidates(
            from: data,
            for: snapshot(title: "Sun Has Set", artist: "beabadoobee", album: "", duration: 142)
        )

        #expect(candidates.first?.releaseGroupID == "release-group-1")
    }

    @Test
    func picksFrontCoverArtArchiveImage() throws {
        let data = Data(
            """
            {
              "images": [
                {
                  "approved": true,
                  "front": false,
                  "types": ["Back"],
                  "image": "http://coverartarchive.org/release/back.jpg",
                  "thumbnails": {
                    "500": "http://coverartarchive.org/release/back-500.jpg"
                  }
                },
                {
                  "approved": true,
                  "front": true,
                  "types": ["Front"],
                  "image": "http://coverartarchive.org/release/front.jpg",
                  "thumbnails": {
                    "500": "http://coverartarchive.org/release/front-500.jpg"
                  }
                }
              ]
            }
            """.utf8)

        let url = try #require(try MusicBrainzCoverArtResolver.bestCoverArtURL(from: data))

        #expect(url.absoluteString == "https://coverartarchive.org/release/front-500.jpg")
    }

    @Test
    func cascadesAlbumArtworkResolvers() {
        let firstResolver = StubArtworkResolver(url: nil)
        let secondResolver = StubArtworkResolver(url: URL(string: "https://example.com/fallback.jpg"))
        let resolver = CascadingAlbumArtworkResolver(
            resolvers: [firstResolver, secondResolver]
        )

        let url = resolver.artworkURL(for: snapshot())

        #expect(url?.absoluteString == "https://example.com/fallback.jpg")
        #expect(firstResolver.callCount == 1)
        #expect(secondResolver.callCount == 1)
    }

    @Test
    func cachesArtworkAndArtistImageLookups() throws {
        let provider = StubMusicSnapshotProvider(snapshot: snapshot())
        let resolver = StubArtworkResolver(url: URL(string: "https://example.com/cover.jpg"))
        let artistResolver = StubArtistImageResolver(url: URL(string: "https://example.com/artist.jpg"))
        let enrichedProvider = ArtworkEnrichingMusicSnapshotProvider(
            baseProvider: provider,
            artworkResolver: resolver,
            artistImageResolver: artistResolver
        )

        let first = try #require(try enrichedProvider.currentSnapshot(at: Date(timeIntervalSince1970: 100)))
        let second = try #require(try enrichedProvider.currentSnapshot(at: Date(timeIntervalSince1970: 101)))

        #expect(first.artworkURL?.absoluteString == "https://example.com/cover.jpg")
        #expect(first.artistImageURL?.absoluteString == "https://example.com/artist.jpg")
        #expect(second.artworkURL?.absoluteString == "https://example.com/cover.jpg")
        #expect(second.artistImageURL?.absoluteString == "https://example.com/artist.jpg")
        #expect(resolver.callCount == 1)
        #expect(artistResolver.callCount == 1)
    }

    @Test
    func cachesMissingArtworkLookups() throws {
        let provider = StubMusicSnapshotProvider(snapshot: snapshot())
        let resolver = StubArtworkResolver(url: nil)
        let artistResolver = StubArtistImageResolver(url: nil)
        let enrichedProvider = ArtworkEnrichingMusicSnapshotProvider(
            baseProvider: provider,
            artworkResolver: resolver,
            artistImageResolver: artistResolver
        )

        _ = try enrichedProvider.currentSnapshot(at: Date(timeIntervalSince1970: 100))
        _ = try enrichedProvider.currentSnapshot(at: Date(timeIntervalSince1970: 101))

        #expect(resolver.callCount == 1)
        #expect(artistResolver.callCount == 1)
    }

    private func snapshot(
        title: String = "Song Name",
        artist: String = "Artist Name",
        album: String = "Album Name",
        duration: TimeInterval? = 180
    ) -> MusicSnapshot {
        MusicSnapshot(
            trackID: "track-1",
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: 15,
            capturedAt: Date(timeIntervalSince1970: 100)
        )
    }
}

private final class StubMusicSnapshotProvider: MusicSnapshotProvider {
    private let snapshot: MusicSnapshot

    init(snapshot: MusicSnapshot) {
        self.snapshot = snapshot
    }

    func currentSnapshot(at date: Date) throws -> MusicSnapshot? {
        MusicSnapshot(
            trackID: snapshot.trackID,
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            duration: snapshot.duration,
            position: snapshot.position,
            capturedAt: date,
            artworkURL: snapshot.artworkURL,
            artistImageURL: snapshot.artistImageURL
        )
    }
}

private final class StubArtworkResolver: AlbumArtworkResolver {
    private let url: URL?
    private(set) var callCount = 0

    init(url: URL?) {
        self.url = url
    }

    func artworkURL(for snapshot: MusicSnapshot) -> URL? {
        callCount += 1
        return url
    }
}

private final class StubArtistImageResolver: ArtistImageResolver {
    private let url: URL?
    private(set) var callCount = 0

    init(url: URL?) {
        self.url = url
    }

    func artistImageURL(for snapshot: MusicSnapshot) -> URL? {
        callCount += 1
        return url
    }
}
