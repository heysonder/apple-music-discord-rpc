import Foundation

public final class MusicBrainzCoverArtResolver: AlbumArtworkResolver {
    private static let minimumMatchScore = 10
    private static let userAgent =
        "AppleMusicDiscordRPC/1.0 (local personal macOS Apple Music Discord Rich Presence)"

    private let dataLoader: HTTPDataLoading
    private let logger: Logger
    private let rateLimitInterval: TimeInterval
    private let rateLimitLock = NSLock()

    private var lastMusicBrainzRequestAt = Date.distantPast

    public init(
        dataLoader: HTTPDataLoading = URLSessionHTTPDataLoader(),
        logger: Logger = .quiet,
        rateLimitInterval: TimeInterval = 1.05
    ) {
        self.dataLoader = dataLoader
        self.logger = logger
        self.rateLimitInterval = rateLimitInterval
    }

    public func artworkURL(for snapshot: MusicSnapshot) -> URL? {
        guard let searchRequest = Self.searchRequest(for: snapshot) else {
            return nil
        }

        do {
            let searchData = try musicBrainzData(for: searchRequest)
            let candidates = try Self.releaseGroupCandidates(from: searchData, for: snapshot)

            for candidate in candidates {
                guard let coverArtRequest = Self.coverArtRequest(releaseGroupID: candidate.releaseGroupID) else {
                    continue
                }

                do {
                    let coverArtData = try dataLoader.data(for: coverArtRequest)
                    if let url = try Self.bestCoverArtURL(from: coverArtData) {
                        logger.log("Resolved MusicBrainz album art: \(url.absoluteString)")
                        return url
                    }
                } catch ArtworkResolverError.httpStatus(404) {
                    continue
                } catch {
                    logger.log(
                        "Cover Art Archive lookup failed for \(candidate.releaseGroupID): "
                            + error.localizedDescription
                    )
                }
            }

            return nil
        } catch {
            logger.log("MusicBrainz album art lookup failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func searchRequest(for snapshot: MusicSnapshot) -> URLRequest? {
        guard snapshot.artworkSearchTerm != nil else {
            return nil
        }

        let query = [
            "recording:\"\(luceneEscaped(snapshot.title))\"",
            "artist:\"\(luceneEscaped(snapshot.artist))\"",
        ].joined(separator: " AND ")

        var components = URLComponents(string: "https://musicbrainz.org/ws/2/recording")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "10"),
        ]

        guard let url = components?.url else {
            return nil
        }

        return jsonRequest(url: url)
    }

    static func coverArtRequest(releaseGroupID: String) -> URLRequest? {
        guard let url = URL(string: "https://coverartarchive.org/release-group/\(releaseGroupID)") else {
            return nil
        }

        return jsonRequest(url: url)
    }

    static func releaseGroupCandidates(
        from data: Data,
        for snapshot: MusicSnapshot
    ) throws -> [MusicBrainzReleaseGroupCandidate] {
        let response = try JSONDecoder().decode(MusicBrainzRecordingSearchResponse.self, from: data)
        let target = ArtworkSearchTarget(snapshot: snapshot)
        let candidates = response.recordings.flatMap { recording in
            MusicBrainzRecordingMatch(recording: recording, target: target).releaseGroupCandidates
        }

        let bestByReleaseGroupID =
            candidates
            .filter { $0.score >= minimumMatchScore }
            .reduce(into: [String: MusicBrainzReleaseGroupCandidate]()) { bestByID, candidate in
                if candidate.score > (bestByID[candidate.releaseGroupID]?.score ?? .min) {
                    bestByID[candidate.releaseGroupID] = candidate
                }
            }

        return bestByReleaseGroupID.values.sorted { left, right in
            left.score == right.score
                ? left.releaseGroupID < right.releaseGroupID
                : left.score > right.score
        }
    }

    static func bestCoverArtURL(from data: Data) throws -> URL? {
        let response = try JSONDecoder().decode(CoverArtArchiveResponse.self, from: data)

        return response.images
            .filter { $0.approved != false }
            .sorted { left, right in
                left.isFrontCover == right.isFrontCover
                    ? left.image.absoluteString < right.image.absoluteString
                    : left.isFrontCover
            }
            .compactMap(\.preferredArtworkURL)
            .first
    }

    private static func jsonRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func luceneEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\"#, with: #"\\"#)
            .replacingOccurrences(of: #"""#, with: #"\""#)
    }

    private func musicBrainzData(for request: URLRequest) throws -> Data {
        waitForRateLimit()
        return try dataLoader.data(for: request)
    }

    private func waitForRateLimit() {
        guard rateLimitInterval > 0 else {
            return
        }

        let delay = rateLimitLock.withLock { () -> TimeInterval in
            let now = Date()
            let nextAllowedRequestAt = lastMusicBrainzRequestAt.addingTimeInterval(rateLimitInterval)
            let delay = max(0, nextAllowedRequestAt.timeIntervalSince(now))
            lastMusicBrainzRequestAt = now.addingTimeInterval(delay)
            return delay
        }

        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
    }
}

struct MusicBrainzReleaseGroupCandidate: Equatable {
    let releaseGroupID: String
    let score: Int
}

private struct MusicBrainzRecordingSearchResponse: Decodable {
    let recordings: [MusicBrainzRecording]

    enum CodingKeys: String, CodingKey {
        case recordings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordings = try container.decodeIfPresent([MusicBrainzRecording].self, forKey: .recordings) ?? []
    }
}

private struct MusicBrainzRecording: Decodable {
    let score: Int
    let title: String
    let lengthMilliseconds: Int?
    let artistCredits: [MusicBrainzArtistCredit]
    let releases: [MusicBrainzRelease]

    var artistName: String {
        artistCredits
            .map(\.displayName)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case score
        case title
        case lengthMilliseconds = "length"
        case artistCredits = "artist-credit"
        case releases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = try container.decodeFlexibleIntIfPresent(forKey: .score) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        lengthMilliseconds = try container.decodeFlexibleIntIfPresent(forKey: .lengthMilliseconds)
        artistCredits = try container.decodeIfPresent([MusicBrainzArtistCredit].self, forKey: .artistCredits) ?? []
        releases = try container.decodeIfPresent([MusicBrainzRelease].self, forKey: .releases) ?? []
    }
}

private struct MusicBrainzArtistCredit: Decodable {
    let name: String?
    let artist: MusicBrainzArtist?

    var displayName: String {
        name ?? artist?.name ?? ""
    }
}

private struct MusicBrainzArtist: Decodable {
    let name: String
}

private struct MusicBrainzRelease: Decodable {
    let title: String
    let status: String
    let releaseGroup: MusicBrainzReleaseGroup?

    enum CodingKeys: String, CodingKey {
        case title
        case status
        case releaseGroup = "release-group"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        releaseGroup = try container.decodeIfPresent(MusicBrainzReleaseGroup.self, forKey: .releaseGroup)
    }
}

private struct MusicBrainzReleaseGroup: Decodable {
    let id: String
    let secondaryTypes: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case secondaryTypes = "secondary-types"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        secondaryTypes = try container.decodeIfPresent([String].self, forKey: .secondaryTypes) ?? []
    }
}

private struct MusicBrainzRecordingMatch {
    let recording: MusicBrainzRecording
    let target: ArtworkSearchTarget
    let titleScore: Int
    let artistScore: Int
    let durationScore: Int
    let searchScore: Int

    init(recording: MusicBrainzRecording, target: ArtworkSearchTarget) {
        self.recording = recording
        self.target = target
        titleScore = ArtworkTextMatcher.score(
            ArtworkTextMatcher.comparable(recording.title),
            against: target.title,
            exact: 8,
            partial: 3
        )
        artistScore = ArtworkTextMatcher.score(
            ArtworkTextMatcher.comparable(recording.artistName),
            against: target.artist,
            exact: 5,
            partial: 2
        )
        durationScore = Self.durationScore(
            recordingMilliseconds: recording.lengthMilliseconds,
            targetSeconds: target.duration
        )
        searchScore = min(recording.score / 20, 5)
    }

    var releaseGroupCandidates: [MusicBrainzReleaseGroupCandidate] {
        guard titleScore > 0, artistScore > 0 else {
            return []
        }

        return recording.releases.compactMap { release in
            guard let releaseGroup = release.releaseGroup, !releaseGroup.id.isEmpty else {
                return nil
            }

            let albumScore =
                target.album.isEmpty
                ? 0
                : ArtworkTextMatcher.score(
                    ArtworkTextMatcher.comparable(release.title),
                    against: target.album,
                    exact: 3,
                    partial: 1
                )
            let statusScore = release.status.caseInsensitiveCompare("Official") == .orderedSame ? 1 : 0
            let typeScore =
                releaseGroup.secondaryTypes.contains {
                    $0.caseInsensitiveCompare("Compilation") == .orderedSame
                } ? -1 : 1

            return MusicBrainzReleaseGroupCandidate(
                releaseGroupID: releaseGroup.id,
                score: titleScore + artistScore + albumScore + durationScore + searchScore + statusScore + typeScore
            )
        }
    }

    private static func durationScore(
        recordingMilliseconds: Int?,
        targetSeconds: TimeInterval?
    ) -> Int {
        guard let recordingMilliseconds, let targetSeconds, targetSeconds > 0 else {
            return 0
        }

        let recordingSeconds = TimeInterval(recordingMilliseconds) / 1000
        return abs(recordingSeconds - targetSeconds) <= 3 ? 2 : 0
    }
}

private struct CoverArtArchiveResponse: Decodable {
    let images: [CoverArtArchiveImage]

    enum CodingKeys: String, CodingKey {
        case images
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        images = try container.decodeIfPresent([CoverArtArchiveImage].self, forKey: .images) ?? []
    }
}

private struct CoverArtArchiveImage: Decodable {
    let image: URL
    let thumbnails: [String: URL]
    let types: [String]
    let front: Bool
    let approved: Bool?

    var isFrontCover: Bool {
        front || types.contains { $0.caseInsensitiveCompare("Front") == .orderedSame }
    }

    var preferredArtworkURL: URL? {
        [
            thumbnails["1200"],
            thumbnails["500"],
            thumbnails["large"],
            thumbnails["250"],
            thumbnails["small"],
            image,
        ]
        .compactMap { $0?.httpsPreferred }
        .first
    }

    enum CodingKeys: String, CodingKey {
        case image
        case thumbnails
        case types
        case front
        case approved
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        image = try container.decode(URL.self, forKey: .image)
        thumbnails = try container.decodeIfPresent([String: URL].self, forKey: .thumbnails) ?? [:]
        types = try container.decodeIfPresent([String].self, forKey: .types) ?? []
        front = try container.decodeIfPresent(Bool.self, forKey: .front) ?? false
        approved = try container.decodeIfPresent(Bool.self, forKey: .approved)
    }
}
