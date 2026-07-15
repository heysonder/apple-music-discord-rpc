import Foundation

public struct DiscordActivity: Encodable, Equatable {
    public let type: DiscordActivityType
    public let details: String
    public let state: String
    public let timestamps: DiscordActivityTimestamps?
    public let assets: DiscordActivityAssets?
    public let statusDisplayType: DiscordStatusDisplayType

    public init(
        type: DiscordActivityType = .listening,
        details: String,
        state: String,
        timestamps: DiscordActivityTimestamps?,
        assets: DiscordActivityAssets? = nil,
        statusDisplayType: DiscordStatusDisplayType = .details
    ) {
        self.type = type
        self.details = details
        self.state = state
        self.timestamps = timestamps
        self.assets = assets
        self.statusDisplayType = statusDisplayType
    }

    enum CodingKeys: String, CodingKey {
        case type
        case details
        case state
        case timestamps
        case assets
        case statusDisplayType = "status_display_type"
    }
}

public enum DiscordActivityType: Int, Encodable, Equatable {
    case playing = 0
    case listening = 2
    case watching = 3
    case competing = 5
}

public enum DiscordStatusDisplayType: Int, Encodable, Equatable {
    case name = 0
    case state = 1
    case details = 2
}

public struct DiscordActivityAssets: Encodable, Equatable {
    public let largeImage: String?
    public let largeText: String?
    public let smallImage: String?
    public let smallText: String?

    public init(
        largeImage: String? = nil,
        largeText: String? = nil,
        smallImage: String? = nil,
        smallText: String? = nil
    ) {
        self.largeImage = largeImage
        self.largeText = largeText
        self.smallImage = smallImage
        self.smallText = smallText
    }

    enum CodingKeys: String, CodingKey {
        case largeImage = "large_image"
        case largeText = "large_text"
        case smallImage = "small_image"
        case smallText = "small_text"
    }
}

public struct DiscordActivityTimestamps: Encodable, Equatable {
    public let start: Int64?
    public let end: Int64?

    public init(start: Int64?, end: Int64?) {
        self.start = start
        self.end = end
    }

    public var isEmpty: Bool {
        start == nil && end == nil
    }
}

public enum DiscordRPCPayloadFactory {
    public static func handshakePayload(appID: String) throws -> Data {
        let payload = HandshakePayload(v: 1, clientID: appID)
        return try jsonEncoder.encode(payload)
    }

    public static func setActivityPayload(
        processID: Int32,
        activity: DiscordActivity,
        nonce: String
    ) throws -> Data {
        let payload = CommandPayload(
            cmd: "SET_ACTIVITY",
            args: SetActivityArguments(pid: processID, activity: activity),
            nonce: nonce
        )
        return try jsonEncoder.encode(payload)
    }

    public static func clearActivityPayload(processID: Int32, nonce: String) throws -> Data {
        let payload = CommandPayload(
            cmd: "SET_ACTIVITY",
            args: SetActivityArguments(pid: processID, activity: nil),
            nonce: nonce
        )
        return try jsonEncoder.encode(payload)
    }

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private struct HandshakePayload: Encodable {
    let v: Int
    let clientID: String

    enum CodingKeys: String, CodingKey {
        case v
        case clientID = "client_id"
    }
}

private struct CommandPayload: Encodable {
    let cmd: String
    let args: SetActivityArguments
    let nonce: String
}

private struct SetActivityArguments: Encodable {
    let pid: Int32
    let activity: DiscordActivity?

    enum CodingKeys: String, CodingKey {
        case pid
        case activity
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pid, forKey: .pid)

        if let activity {
            try container.encode(activity, forKey: .activity)
        } else {
            try container.encodeNil(forKey: .activity)
        }
    }
}
