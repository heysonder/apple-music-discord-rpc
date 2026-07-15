import Foundation
import Testing

@testable import AppleMusicDiscordRPCCore

@Suite
struct DiscordIPCFrameTests {
    @Test
    func frameEncodingUsesLittleEndianHeader() throws {
        let payload = Data("{}".utf8)
        let encoded = DiscordIPCFrameCoder.encode(opcode: .handshake, payload: payload)

        #expect(Array(encoded.prefix(8)) == [0, 0, 0, 0, 2, 0, 0, 0])

        let decoded = try DiscordIPCFrameCoder.decode(encoded)
        #expect(decoded.opcode == .handshake)
        #expect(decoded.payload == payload)
    }

    @Test
    func handshakePayload() throws {
        let payload = try DiscordRPCPayloadFactory.handshakePayload(appID: "123456")
        let object = try jsonObject(payload)

        #expect(object["v"] as? Int == 1)
        #expect(object["client_id"] as? String == "123456")
    }

    @Test
    func setActivityPayload() throws {
        let activity = DiscordActivity(
            details: "Test Song",
            state: "Test Artist",
            timestamps: DiscordActivityTimestamps(start: 10, end: 70),
            assets: DiscordActivityAssets(
                largeImage: "https://example.com/cover.jpg",
                largeText: "Test Album",
                smallImage: "https://example.com/artist.jpg",
                smallText: "Test Artist"
            )
        )
        let payload = try DiscordRPCPayloadFactory.setActivityPayload(
            processID: 999,
            activity: activity,
            nonce: "abc"
        )
        let object = try jsonObject(payload)
        let args = try #require(object["args"] as? [String: Any])
        let activityObject = try #require(args["activity"] as? [String: Any])
        let timestamps = try #require(activityObject["timestamps"] as? [String: Any])
        let assets = try #require(activityObject["assets"] as? [String: Any])

        #expect(object["cmd"] as? String == "SET_ACTIVITY")
        #expect(object["nonce"] as? String == "abc")
        #expect(args["pid"] as? Int == 999)
        #expect(activityObject["type"] as? Int == 2)
        #expect(activityObject["details"] as? String == "Test Song")
        #expect(activityObject["state"] as? String == "Test Artist")
        #expect(activityObject["status_display_type"] as? Int == 2)
        #expect(timestamps["start"] as? Int == 10)
        #expect(timestamps["end"] as? Int == 70)
        #expect(assets["large_image"] as? String == "https://example.com/cover.jpg")
        #expect(assets["large_text"] as? String == "Test Album")
        #expect(assets["small_image"] as? String == "https://example.com/artist.jpg")
        #expect(assets["small_text"] as? String == "Test Artist")
    }

    @Test
    func clearActivityPayloadEncodesNullActivity() throws {
        let payload = try DiscordRPCPayloadFactory.clearActivityPayload(
            processID: 999,
            nonce: "abc"
        )
        let object = try jsonObject(payload)
        let args = try #require(object["args"] as? [String: Any])

        #expect(object["cmd"] as? String == "SET_ACTIVITY")
        #expect(args["pid"] as? Int == 999)
        #expect(args["activity"] is NSNull)
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
