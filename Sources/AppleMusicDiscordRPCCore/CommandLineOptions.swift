import Foundation

public struct CommandLineOptions: Equatable {
    private static let defaultPollInterval: TimeInterval = 5

    public let appID: String
    public let pollInterval: TimeInterval
    public let runOnce: Bool
    public let clear: Bool
    public let verbose: Bool
    public let albumArtEnabled: Bool

    public init(
        appID: String,
        pollInterval: TimeInterval,
        runOnce: Bool,
        clear: Bool,
        verbose: Bool,
        albumArtEnabled: Bool
    ) {
        self.appID = appID
        self.pollInterval = pollInterval
        self.runOnce = runOnce
        self.clear = clear
        self.verbose = verbose
        self.albumArtEnabled = albumArtEnabled
    }

    public static func parse(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> CommandLineOptions {
        var appID = environment["DISCORD_APP_ID"]?.trimmed
        var pollInterval = Self.defaultPollInterval
        var runOnce = false
        var clear = false
        var verbose = false
        var albumArtEnabled = true

        var cursor = ArgumentCursor(arguments: arguments)
        while let argument = cursor.next() {
            switch argument {
            case "--help", "-h":
                throw CLIError.helpRequested
            case "--app-id":
                appID = try cursor.requiredValue(after: argument).trimmed
            case "--poll-interval":
                let value = try cursor.requiredValue(after: argument)
                guard let parsed = TimeInterval(value), parsed.isFinite, parsed > 0 else {
                    throw CLIError.invalidPollInterval(value)
                }
                pollInterval = parsed
            case "--once":
                runOnce = true
            case "--clear":
                clear = true
            case "--verbose":
                verbose = true
            case "--no-album-art":
                albumArtEnabled = false
            default:
                throw CLIError.unknownArgument(argument)
            }
        }

        guard let finalAppID = appID, !finalAppID.isEmpty else {
            throw CLIError.missingAppID
        }

        return CommandLineOptions(
            appID: finalAppID,
            pollInterval: pollInterval,
            runOnce: runOnce,
            clear: clear,
            verbose: verbose,
            albumArtEnabled: albumArtEnabled
        )
    }

    public static let helpText = """
        Usage:
          apple-music-discord-rpc --app-id <discord application id> [options]

        Options:
          --app-id <id>              Discord application ID. Can also be set with DISCORD_APP_ID.
          --poll-interval <seconds>  Poll interval for Music updates. Defaults to 5.
          --once                     Read Music once, update Discord once, then exit.
          --clear                    Clear Discord Rich Presence and exit.
          --verbose                  Print connection and update details.
          --no-album-art             Disable album and artist image lookup and send text-only presence.
          --help                     Show this help text.
        """
}

private struct ArgumentCursor {
    let arguments: [String]
    private var index = 0

    mutating func next() -> String? {
        guard index < arguments.count else {
            return nil
        }

        defer { index += 1 }
        return arguments[index]
    }

    mutating func requiredValue(after option: String) throws -> String {
        guard let value = next(), !value.hasPrefix("--"), value != "-h" else {
            throw CLIError.missingValue(option)
        }

        return value
    }
}

public enum CLIError: LocalizedError, Equatable {
    case helpRequested
    case missingAppID
    case missingValue(String)
    case invalidPollInterval(String)
    case unknownArgument(String)

    public var errorDescription: String? {
        switch self {
        case .helpRequested:
            return nil
        case .missingAppID:
            return "Missing Discord application ID. Pass --app-id <id> or set DISCORD_APP_ID."
        case .missingValue(let option):
            return "Missing value for \(option)."
        case .invalidPollInterval(let value):
            return "Invalid poll interval '\(value)'. Use a positive number of seconds."
        case .unknownArgument(let argument):
            return "Unknown argument '\(argument)'."
        }
    }
}
