import Foundation

public final class DeezerTrackArtworkResolver: AlbumArtworkResolver {
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
                logger.log("Resolved Deezer album art: \(url.absoluteString)")
            }
            return url
        } catch {
            logger.log("Deezer album art lookup failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func searchRequest(for snapshot: MusicSnapshot) -> URLRequest? {
        guard let term = snapshot.artworkSearchTerm else {
            return nil
        }

        var components = URLComponents(string: "https://api.deezer.com/search/track")
        components?.queryItems = [
            URLQueryItem(name: "q", value: term),
            URLQueryItem(name: "limit", value: "10"),
        ]

        guard let url = components?.url else {
            return nil
        }

        return URLRequest.acceptingJSON(from: url)
    }

    static func bestArtworkURL(from data: Data, for snapshot: MusicSnapshot) throws -> URL? {
        let response = try JSONDecoder().decode(DeezerTrackSearchResponse.self, from: data)
        let target = ArtworkSearchTarget(snapshot: snapshot)

        return response.data
            .compactMap { result in
                TrackArtworkMatch(
                    title: result.title,
                    artist: result.artist.name,
                    album: result.album.title,
                    artworkURL: result.album.artworkURL,
                    target: target
                )
            }
            .filter { $0.score >= minimumMatchScore && $0.titleMatched }
            .max { $0.score < $1.score }?
            .artworkURL
    }
}

public final class DeezerArtistImageResolver: ArtistImageResolver {
    private static let minimumMatchScore = 3

    private let dataLoader: HTTPDataLoading
    private let logger: Logger

    public init(
        dataLoader: HTTPDataLoading = URLSessionHTTPDataLoader(),
        logger: Logger = .quiet
    ) {
        self.dataLoader = dataLoader
        self.logger = logger
    }

    public func artistImageURL(for snapshot: MusicSnapshot) -> URL? {
        guard let request = Self.searchRequest(for: snapshot) else {
            return nil
        }

        do {
            let data = try dataLoader.data(for: request)
            let url = try Self.bestArtistImageURL(from: data, for: snapshot)
            if let url {
                logger.log("Resolved Deezer artist image: \(url.absoluteString)")
            }
            return url
        } catch {
            logger.log("Deezer artist image lookup failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func searchRequest(for snapshot: MusicSnapshot) -> URLRequest? {
        let artist = snapshot.artist.primaryArtistNameForLookup
        guard !artist.isEmpty, !artist.isUnknownArtist else {
            return nil
        }

        var components = URLComponents(string: "https://api.deezer.com/search/artist")
        components?.queryItems = [
            URLQueryItem(name: "q", value: artist),
            URLQueryItem(name: "limit", value: "5"),
        ]

        guard let url = components?.url else {
            return nil
        }

        return URLRequest.acceptingJSON(from: url)
    }

    static func bestArtistImageURL(from data: Data, for snapshot: MusicSnapshot) throws -> URL? {
        let response = try JSONDecoder().decode(DeezerArtistSearchResponse.self, from: data)
        let targetArtist = ArtworkTextMatcher.comparable(snapshot.artist.primaryArtistNameForLookup)

        return response.data
            .compactMap { result -> ArtistImageMatch? in
                guard let imageURL = result.imageURL else {
                    return nil
                }

                let score = ArtworkTextMatcher.score(
                    ArtworkTextMatcher.comparable(result.name),
                    against: targetArtist,
                    exact: 8,
                    partial: 3
                )
                return ArtistImageMatch(score: score, imageURL: imageURL)
            }
            .filter { $0.score >= minimumMatchScore }
            .max { $0.score < $1.score }?
            .imageURL
    }
}

private struct ArtistImageMatch {
    let score: Int
    let imageURL: URL
}

private struct DeezerTrackSearchResponse: Decodable {
    let data: [DeezerTrackResult]
}

private struct DeezerTrackResult: Decodable {
    let title: String
    let artist: DeezerNamedResource
    let album: DeezerAlbumResource
}

private struct DeezerAlbumResource: Decodable {
    let title: String
    let coverXL: String?
    let coverBig: String?
    let coverMedium: String?

    var artworkURL: URL? {
        [coverXL, coverBig, coverMedium]
            .compactMap { $0.flatMap(URL.init(string:))?.httpsPreferred }
            .first
    }

    enum CodingKeys: String, CodingKey {
        case title
        case coverXL = "cover_xl"
        case coverBig = "cover_big"
        case coverMedium = "cover_medium"
    }
}

private struct DeezerArtistSearchResponse: Decodable {
    let data: [DeezerArtistResult]
}

private struct DeezerArtistResult: Decodable {
    let name: String
    let pictureXL: String?
    let pictureBig: String?
    let pictureMedium: String?

    var imageURL: URL? {
        [pictureXL, pictureBig, pictureMedium]
            .compactMap { $0.flatMap(URL.init(string:))?.httpsPreferred }
            .first
    }

    enum CodingKeys: String, CodingKey {
        case name
        case pictureXL = "picture_xl"
        case pictureBig = "picture_big"
        case pictureMedium = "picture_medium"
    }
}

private struct DeezerNamedResource: Decodable {
    let name: String
}

private extension URLRequest {
    static func acceptingJSON(from url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
