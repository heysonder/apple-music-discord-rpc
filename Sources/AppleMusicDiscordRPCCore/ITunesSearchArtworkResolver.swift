import Foundation

public final class ITunesSearchArtworkResolver: AlbumArtworkResolver {
    private static let minimumMatchScore = 8

    private let dataLoader: HTTPDataLoading
    private let logger: Logger

    public init(
        dataLoader: HTTPDataLoading = URLSessionHTTPDataLoader(),
        logger: Logger = .quiet
    ) {
        self.dataLoader = dataLoader
        self.logger = logger
    }

    public func artworkURL(for snapshot: MusicSnapshot) -> URL? {
        guard let request = Self.searchRequest(for: snapshot) else {
            return nil
        }

        do {
            let data = try dataLoader.data(for: request)
            let url = try Self.bestArtworkURL(from: data, for: snapshot)
            if let url {
                logger.log("Resolved Apple album art: \(url.absoluteString)")
            }
            return url
        } catch {
            logger.log("Apple album art lookup failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func searchRequest(for snapshot: MusicSnapshot) -> URLRequest? {
        guard let term = snapshot.artworkSearchTerm else {
            return nil
        }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10"),
        ]

        guard let url = components?.url else {
            return nil
        }

        return URLRequest(url: url)
    }

    static func bestArtworkURL(from data: Data, for snapshot: MusicSnapshot) throws -> URL? {
        let response = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
        let target = ArtworkSearchTarget(snapshot: snapshot)

        return response.results
            .compactMap { result in
                TrackArtworkMatch(
                    title: result.trackName,
                    artist: result.artistName,
                    album: result.collectionName ?? "",
                    artworkURL: result.artworkURL.map(Self.normalizedArtworkURL),
                    target: target
                )
            }
            .filter { $0.score >= minimumMatchScore && $0.titleMatched && $0.artistMatched }
            .max { $0.score < $1.score }?
            .artworkURL
    }

    static func normalizedArtworkURL(_ url: URL) -> URL {
        let basename = url.deletingPathExtension().lastPathComponent
        guard basename.range(of: #"^\d+x\d+bb$"#, options: .regularExpression) != nil else {
            return url
        }

        let pathExtension = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        return
            url
            .deletingLastPathComponent()
            .appendingPathComponent("1024x1024bb.\(pathExtension)")
    }
}

private struct ITunesSearchResponse: Decodable {
    let results: [ITunesSearchResult]
}

private struct ITunesSearchResult: Decodable {
    let trackName: String
    let artistName: String
    let collectionName: String?
    let artworkUrl100: String?

    var artworkURL: URL? {
        artworkUrl100.flatMap(URL.init(string:))
    }
}
