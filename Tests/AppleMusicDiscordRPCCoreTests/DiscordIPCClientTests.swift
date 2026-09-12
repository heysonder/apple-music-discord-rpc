import Foundation
import Testing

@testable import AppleMusicDiscordRPCCore

@Suite
struct DiscordIPCClientTests {
    @Test(arguments: [
        #"{"evt":"READY"}"#,
        #"{"cmd":"SET_ACTIVITY"}"#,
        #"{"cmd":"SET_ACTIVITY","nonce":"wrong"}"#,
        #"{"cmd":"DISPATCH","nonce":"expected","evt":"READY"}"#,
    ])
    func rejectsFramesThatDoNotAcknowledgeTheActivity(json: String) {
        let client = DiscordIPCClient(appID: "123")
        #expect(throws: DiscordIPCError.self) {
            try client.validateCommandResponse(
                DiscordIPCFrame(opcode: .frame, payload: Data(json.utf8)), nonce: "expected"
            )
        }
    }

    @Test
    func acceptsMatchingActivityAcknowledgement() throws {
        let client = DiscordIPCClient(appID: "123")
        try client.validateCommandResponse(
            DiscordIPCFrame(
                opcode: .frame,
                payload: Data(#"{"cmd":"SET_ACTIVITY","nonce":"expected","evt":null}"#.utf8)
            ), nonce: "expected"
        )
    }

    @Test
    func buildsOrderedSocketPathsFromUniqueRuntimeDirectories() {
        let paths = DiscordIPCClient.candidateSocketPaths(
            environment: [
                "XDG_RUNTIME_DIR": " /run/user/501 ",
                "TMPDIR": "/tmp",
                "TMP": "/tmp",
                "TEMP": "   ",
            ]
        )

        #expect(paths.count == 20)
        #expect(paths.first == "/run/user/501/discord-ipc-0")
        #expect(paths[9] == "/run/user/501/discord-ipc-9")
        #expect(paths[10] == "/tmp/discord-ipc-0")
        #expect(paths.last == "/tmp/discord-ipc-9")
    }

    @Test
    func failedConnectionAttemptSchedulesBackoff() {
        let clock = MutableClock(timeIntervalSince1970: 0)
        let client = makeClient(clock: clock)

        #expect(sendError(from: client) == .noSocketFound(expectedPaths))

        clock.advance(by: 0.5)
        #expect(sendError(from: client) == .reconnectBackoff(0.5))
    }

    @Test
    func skippedAttemptsDoNotExtendBackoffWindow() {
        let clock = MutableClock(timeIntervalSince1970: 0)
        let client = makeClient(clock: clock)

        #expect(sendError(from: client) == .noSocketFound(expectedPaths))

        clock.advance(by: 0.25)
        #expect(sendError(from: client) == .reconnectBackoff(0.75))

        clock.advance(by: 0.25)
        #expect(sendError(from: client) == .reconnectBackoff(0.5))

        clock.advance(by: 0.75)
        #expect(sendError(from: client) == .noSocketFound(expectedPaths))
    }

    @Test
    func reconnectDelayGrowsOnlyWithRealAttempts() {
        let clock = MutableClock(timeIntervalSince1970: 0)
        let client = makeClient(clock: clock)

        #expect(sendError(from: client) == .noSocketFound(expectedPaths))

        clock.advance(by: 1)
        #expect(sendError(from: client) == .noSocketFound(expectedPaths))

        clock.advance(by: 1)
        #expect(sendError(from: client) == .reconnectBackoff(1))

        clock.advance(by: 1)
        #expect(sendError(from: client) == .noSocketFound(expectedPaths))
    }

    private var expectedPaths: [String] {
        (0...9).map { "/tmp/discord-ipc-\($0)" }
    }

    private func makeClient(clock: MutableClock) -> DiscordIPCClient {
        DiscordIPCClient(
            appID: "123",
            environment: [:],
            fileManager: NoSocketFileManager(),
            now: { clock.now }
        )
    }

    private func sendError(from client: DiscordIPCClient) -> DiscordIPCError? {
        do {
            try client.clearActivity()
            Issue.record("Expected clearActivity to fail without a Discord socket.")
            return nil
        } catch let error as DiscordIPCError {
            return error
        } catch {
            Issue.record("Expected DiscordIPCError, got \(error).")
            return nil
        }
    }
}

private final class MutableClock {
    private(set) var now: Date

    init(timeIntervalSince1970: TimeInterval) {
        now = Date(timeIntervalSince1970: timeIntervalSince1970)
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

private final class NoSocketFileManager: FileManager {
    override func fileExists(atPath path: String) -> Bool {
        false
    }
}
