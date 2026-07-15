import Foundation

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isUnknownArtist: Bool {
        trimmed.caseInsensitiveCompare(MusicSnapshotNormalizer.unknownArtist) == .orderedSame
    }

    var creditedArtistNames: [String] {
        guard contains(" & ") else {
            return [trimmed].filter { !$0.isEmpty }
        }

        return components(separatedBy: " & ")
            .flatMap { component in
                component
                    .components(separatedBy: ",")
                    .map(\.trimmed)
            }
            .filter { !$0.isEmpty }
    }

    var primaryArtistNameForLookup: String {
        creditedArtistNames.first ?? trimmed
    }
}
