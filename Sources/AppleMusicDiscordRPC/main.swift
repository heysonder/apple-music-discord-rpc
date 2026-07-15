import AppleMusicDiscordRPCCore
import Darwin
import Dispatch
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    let options = try CommandLineOptions.parse(arguments: arguments)
    let logger = Logger(verbose: options.verbose)
    let discordClient = DiscordIPCClient(appID: options.appID, logger: logger)
    let daemon = AppleMusicDiscordRPCDaemon(
        musicClient: makeMusicClient(options: options, logger: logger),
        discordClient: discordClient,
        pollInterval: options.pollInterval,
        logger: logger
    )

    if options.clear {
        try daemon.clear()
    } else if options.runOnce {
        try daemon.runOnce()
    } else {
        let stopController = StopController()
        let signalTrap = SignalTrap(stopController: stopController)
        withExtendedLifetime(signalTrap) {
            daemon.runUntilStopped {
                stopController.isStopRequested
            }
        }
    }
} catch CLIError.helpRequested {
    print(CommandLineOptions.helpText)
    exit(EXIT_SUCCESS)
} catch let error as CLIError {
    FileHandle.standardError.writeLine(error.localizedDescription)
    FileHandle.standardError.writeLine("")
    FileHandle.standardError.writeLine(CommandLineOptions.helpText)
    exit(EX_USAGE)
} catch {
    FileHandle.standardError.writeLine(error.localizedDescription)
    exit(EXIT_FAILURE)
}

private func makeMusicClient(
    options: CommandLineOptions,
    logger: Logger
) -> MusicSnapshotProvider {
    let appleMusicClient = AppleScriptMusicClient()
    guard options.albumArtEnabled else {
        return appleMusicClient
    }

    return ArtworkEnrichingMusicSnapshotProvider(
        baseProvider: appleMusicClient,
        artworkResolver: CascadingAlbumArtworkResolver(
            resolvers: [
                ITunesSearchArtworkResolver(logger: logger),
                DeezerTrackArtworkResolver(logger: logger),
                MusicBrainzCoverArtResolver(logger: logger),
            ],
            logger: logger
        ),
        artistImageResolver: DeezerArtistImageResolver(logger: logger)
    )
}

private final class StopController {
    private let lock = NSLock()
    private var stopped = false

    var isStopRequested: Bool {
        lock.withLock {
            stopped
        }
    }

    func requestStop() {
        lock.withLock {
            stopped = true
        }
    }
}

private final class SignalTrap {
    private var sources: [DispatchSourceSignal] = []

    init(stopController: StopController) {
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)

            let source = DispatchSource.makeSignalSource(
                signal: signalNumber,
                queue: DispatchQueue.global(qos: .utility)
            )
            source.setEventHandler {
                stopController.requestStop()
            }
            source.resume()
            sources.append(source)
        }
    }
}
