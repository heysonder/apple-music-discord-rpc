import Foundation

struct ArtworkSearchTarget {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval?

    init(snapshot: MusicSnapshot) {
        title = ArtworkTextMatcher.comparable(snapshot.title)
        artist = ArtworkTextMatcher.comparable(snapshot.artist)
        album = ArtworkTextMatcher.comparable(snapshot.album)
        duration = snapshot.duration
    }
}

struct TrackArtworkMatch {
    let score: Int
    let titleMatched: Bool
    let artworkURL: URL

    init?(
        title: String,
        artist: String,
        album: String,
        artworkURL: URL?,
        target: ArtworkSearchTarget
    ) {
        guard let artworkURL else {
            return nil
        }

        let titleScore = ArtworkTextMatcher.score(
            ArtworkTextMatcher.comparable(title),
            against: target.title,
            exact: 8,
            partial: 3
        )
        let artistScore = ArtworkTextMatcher.score(
            ArtworkTextMatcher.comparable(artist),
            against: target.artist,
            exact: 5,
            partial: 2
        )
        let albumScore =
            target.album.isEmpty
            ? 0
            : ArtworkTextMatcher.score(
                ArtworkTextMatcher.comparable(album),
                against: target.album,
                exact: 3,
                partial: 1
            )

        score = titleScore + artistScore + albumScore
        titleMatched = titleScore > 0
        self.artworkURL = artworkURL
    }
}

enum ArtworkTextMatcher {
    static func comparable(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func score(
        _ value: String,
        against target: String,
        exact: Int,
        partial: Int
    ) -> Int {
        guard !value.isEmpty, !target.isEmpty else {
            return 0
        }

        if value == target {
            return exact
        }

        if value.contains(target) || target.contains(value) {
            return partial
        }

        return 0
    }
}

extension MusicSnapshot {
    var artworkSearchTerm: String? {
        guard !title.isEmpty, !artist.isEmpty, !artist.isUnknownArtist else {
            return nil
        }

        return [title, artist, album]
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

extension URL {
    var httpsPreferred: URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false),
            components.scheme == "http"
        else {
            return self
        }

        components.scheme = "https"
        return components.url ?? self
    }
}

extension KeyedDecodingContainer {
    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return intValue
        }

        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return Int(stringValue)
        }

        return nil
    }
}
