import Darwin
import Foundation

public protocol DiscordPresenceClient: AnyObject {
    func setActivity(_ activity: DiscordActivity) throws
    func clearActivity() throws
}

public final class DiscordIPCClient: DiscordPresenceClient {
    private let appID: String
    private let processID: Int32
    private let environment: [String: String]
    private let fileManager: FileManager
    private let logger: Logger

    private var connection: DiscordIPCConnection?
    private var reconnectDelay: TimeInterval = 1
    private var nextReconnectAttempt = Date.distantPast

    public init(
        appID: String,
        processID: Int32 = getpid(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        logger: Logger = .quiet
    ) {
        self.appID = appID
        self.processID = processID
        self.environment = environment
        self.fileManager = fileManager
        self.logger = logger
    }

    public func setActivity(_ activity: DiscordActivity) throws {
        let nonce = UUID().uuidString
        let payload = try DiscordRPCPayloadFactory.setActivityPayload(
            processID: processID,
            activity: activity,
            nonce: nonce
        )
        try sendCommand(payload: payload, nonce: nonce)
    }

    public func clearActivity() throws {
        let nonce = UUID().uuidString
        let payload = try DiscordRPCPayloadFactory.clearActivityPayload(
            processID: processID,
            nonce: nonce
        )
        try sendCommand(payload: payload, nonce: nonce)
    }

    public static func candidateSocketPaths(environment: [String: String]) -> [String] {
        ipcDirectories(environment: environment)
            .flatMap { directory in
                (0...9).map { index in
                    URL(fileURLWithPath: directory)
                        .appendingPathComponent("discord-ipc-\(index)")
                        .path
                }
            }
    }

    private static func ipcDirectories(environment: [String: String]) -> [String] {
        let rawDirectories = [
            environment["XDG_RUNTIME_DIR"],
            environment["TMPDIR"],
            environment["TMP"],
            environment["TEMP"],
            "/tmp",
        ]

        var seen = Set<String>()
        return rawDirectories.compactMap { rawDirectory in
            guard let directory = rawDirectory?.trimmed,
                !directory.isEmpty,
                !seen.contains(directory)
            else {
                return nil
            }

            seen.insert(directory)
            return directory
        }
    }

    private func sendCommand(payload: Data, nonce: String) throws {
        do {
            let connection = try ensureConnection()
            try connection.writeFrame(opcode: .frame, payload: payload)
            let response = try connection.readFrame()
            try validateCommandResponse(response, nonce: nonce)
            resetBackoff()
        } catch {
            closeConnection()
            scheduleReconnect()
            throw error
        }
    }

    private func ensureConnection() throws -> DiscordIPCConnection {
        if let connection {
            return connection
        }

        let now = Date()
        guard now >= nextReconnectAttempt else {
            throw DiscordIPCError.reconnectBackoff(nextReconnectAttempt.timeIntervalSince(now))
        }

        var lastError: Error?
        let paths = Self.candidateSocketPaths(environment: environment)

        for path in paths where fileManager.fileExists(atPath: path) {
            do {
                logger.log("Trying Discord IPC socket: \(path)")
                let connection = try DiscordIPCConnection.connect(path: path)
                let handshakePayload = try DiscordRPCPayloadFactory.handshakePayload(appID: appID)
                try connection.writeFrame(opcode: .handshake, payload: handshakePayload)
                let readyFrame = try connection.readFrame()
                try validateReadyFrame(readyFrame)

                self.connection = connection
                resetBackoff()
                logger.log("Connected to Discord IPC socket: \(path)")
                return connection
            } catch {
                lastError = error
                logger.log("Discord IPC socket failed: \(path) - \(error.localizedDescription)")
            }
        }

        throw lastError ?? DiscordIPCError.noSocketFound(paths)
    }

    private func validateReadyFrame(_ frame: DiscordIPCFrame) throws {
        let response = try decodeFramePayload(frame, expectedDescription: "READY frame")

        if response.event == .ready {
            return
        }

        if response.event == .error {
            throw DiscordIPCError.discordError(response.errorMessage)
        }

        throw DiscordIPCError.invalidFrame("Expected READY event from Discord IPC.")
    }

    private func validateCommandResponse(_ frame: DiscordIPCFrame, nonce: String) throws {
        if frame.opcode == .ping {
            guard let connection else {
                throw DiscordIPCError.disconnected
            }
            try connection.writeFrame(opcode: .pong, payload: frame.payload)
            let response = try connection.readFrame()
            try validateCommandResponse(response, nonce: nonce)
            return
        }

        let response = try decodeFramePayload(frame, expectedDescription: "command response frame")

        if response.event == .error {
            throw DiscordIPCError.discordError(response.errorMessage)
        }

        if let responseNonce = response.nonce, responseNonce != nonce {
            throw DiscordIPCError.invalidFrame("Discord response nonce did not match request nonce.")
        }
    }

    private func decodeFramePayload(
        _ frame: DiscordIPCFrame,
        expectedDescription: String
    ) throws -> DiscordRPCResponse {
        guard frame.opcode == .frame else {
            throw DiscordIPCError.invalidFrame(
                "Expected \(expectedDescription), got opcode \(frame.opcode.rawValue)."
            )
        }

        do {
            return try JSONDecoder().decode(DiscordRPCResponse.self, from: frame.payload)
        } catch {
            throw DiscordIPCError.invalidFrame("\(expectedDescription) payload is not a valid Discord RPC response.")
        }
    }

    private func resetBackoff() {
        reconnectDelay = 1
        nextReconnectAttempt = .distantPast
    }

    private func scheduleReconnect() {
        nextReconnectAttempt = Date().addingTimeInterval(reconnectDelay)
        reconnectDelay = min(reconnectDelay * 2, 30)
    }

    private func closeConnection() {
        connection?.close()
        connection = nil
    }
}

private struct DiscordRPCResponse: Decodable {
    let evt: String?
    let nonce: String?
    let data: DiscordRPCResponseData?

    var event: DiscordRPCEvent? {
        evt.flatMap(DiscordRPCEvent.init(rawValue:))
    }

    var errorMessage: String {
        data?.message ?? "Discord returned an error response."
    }
}

private struct DiscordRPCResponseData: Decodable {
    let message: String?
}

private enum DiscordRPCEvent: String {
    case ready = "READY"
    case error = "ERROR"
}

public enum DiscordIPCError: LocalizedError, Equatable {
    case noSocketFound([String])
    case socketPathTooLong(String)
    case socketFailure(String, Int32)
    case invalidFrame(String)
    case disconnected
    case reconnectBackoff(TimeInterval)
    case discordError(String)

    public var errorDescription: String? {
        switch self {
        case .noSocketFound:
            return "Discord IPC socket was not found. Make sure Discord Desktop is running."
        case .socketPathTooLong(let path):
            return "Discord IPC socket path is too long: \(path)"
        case .socketFailure(let operation, let errorNumber):
            return "\(operation) failed: \(String(cString: strerror(errorNumber)))"
        case .invalidFrame(let message):
            return message
        case .disconnected:
            return "Discord IPC socket disconnected."
        case .reconnectBackoff(let seconds):
            return "Waiting \(String(format: "%.1f", max(0, seconds)))s before reconnecting to Discord."
        case .discordError(let message):
            return message
        }
    }
}
