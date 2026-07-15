import Testing

@testable import AppleMusicDiscordRPCCore

@Suite
struct CommandLineOptionsTests {
    @Test
    func parsesAppIDFromEnvironment() throws {
        let options = try CommandLineOptions.parse(
            arguments: [],
            environment: ["DISCORD_APP_ID": "123"]
        )

        #expect(options.appID == "123")
        #expect(options.pollInterval == 5)
        #expect(!options.runOnce)
        #expect(!options.clear)
        #expect(!options.verbose)
        #expect(options.albumArtEnabled)
    }

    @Test
    func parsesExplicitOptions() throws {
        let options = try CommandLineOptions.parse(
            arguments: [
                "--app-id", "456",
                "--poll-interval", "2.5",
                "--once",
                "--verbose",
                "--no-album-art",
            ],
            environment: [:]
        )

        #expect(options.appID == "456")
        #expect(options.pollInterval == 2.5)
        #expect(options.runOnce)
        #expect(!options.clear)
        #expect(options.verbose)
        #expect(!options.albumArtEnabled)
    }

    @Test
    func requiresAppID() {
        do {
            _ = try CommandLineOptions.parse(arguments: [], environment: [:])
            Issue.record("Expected missing app ID error.")
        } catch let error as CLIError {
            #expect(error == .missingAppID)
        } catch {
            Issue.record("Expected CLIError, got \(error).")
        }
    }

    @Test
    func reportsMissingOptionValueBeforeParsingNextFlag() {
        #expect(throws: CLIError.missingValue("--app-id")) {
            try CommandLineOptions.parse(
                arguments: ["--app-id", "--once"],
                environment: [:]
            )
        }
    }

    @Test
    func rejectsNonPositivePollInterval() {
        #expect(throws: CLIError.invalidPollInterval("0")) {
            try CommandLineOptions.parse(
                arguments: ["--app-id", "123", "--poll-interval", "0"],
                environment: [:]
            )
        }

        #expect(throws: CLIError.invalidPollInterval("-1")) {
            try CommandLineOptions.parse(
                arguments: ["--app-id", "123", "--poll-interval", "-1"],
                environment: [:]
            )
        }
    }
}
