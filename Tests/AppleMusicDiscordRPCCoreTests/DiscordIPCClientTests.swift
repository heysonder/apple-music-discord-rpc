import Testing

@testable import AppleMusicDiscordRPCCore

@Suite
struct DiscordIPCClientTests {
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
}
