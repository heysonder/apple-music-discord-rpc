import Foundation

public enum DiscordOpcode: UInt32 {
    case handshake = 0
    case frame = 1
    case close = 2
    case ping = 3
    case pong = 4
}

public struct DiscordIPCFrame: Equatable {
    public let opcode: DiscordOpcode
    public let payload: Data

    public init(opcode: DiscordOpcode, payload: Data) {
        self.opcode = opcode
        self.payload = payload
    }
}

public enum DiscordIPCFrameCoder {
    public static let headerLength = 8

    public static func encode(opcode: DiscordOpcode, payload: Data) -> Data {
        var data = Data()
        data.appendLittleEndianUInt32(opcode.rawValue)
        data.appendLittleEndianUInt32(UInt32(payload.count))
        data.append(payload)
        return data
    }

    public static func decode(_ data: Data) throws -> DiscordIPCFrame {
        guard data.count >= headerLength else {
            throw DiscordIPCError.invalidFrame("Frame is shorter than the 8-byte Discord IPC header.")
        }

        let bytes = [UInt8](data)
        let opcodeValue = readLittleEndianUInt32(bytes[0..<4])
        let payloadLength = Int(readLittleEndianUInt32(bytes[4..<8]))
        let expectedLength = headerLength + payloadLength

        guard data.count == expectedLength else {
            throw DiscordIPCError.invalidFrame(
                "Frame length \(data.count) does not match header length \(expectedLength).")
        }

        guard let opcode = DiscordOpcode(rawValue: opcodeValue) else {
            throw DiscordIPCError.invalidFrame("Unknown Discord IPC opcode \(opcodeValue).")
        }

        return DiscordIPCFrame(opcode: opcode, payload: data.subdata(in: headerLength..<data.count))
    }

    public static func readHeader(_ data: Data) throws -> (opcode: DiscordOpcode, payloadLength: Int) {
        guard data.count == headerLength else {
            throw DiscordIPCError.invalidFrame("Header must be exactly 8 bytes.")
        }

        let bytes = [UInt8](data)
        let opcodeValue = readLittleEndianUInt32(bytes[0..<4])
        guard let opcode = DiscordOpcode(rawValue: opcodeValue) else {
            throw DiscordIPCError.invalidFrame("Unknown Discord IPC opcode \(opcodeValue).")
        }

        return (opcode, Int(readLittleEndianUInt32(bytes[4..<8])))
    }

    private static func readLittleEndianUInt32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var result: UInt32 = 0
        for (offset, byte) in bytes.enumerated() {
            result |= UInt32(byte) << UInt32(offset * 8)
        }
        return result
    }
}

private extension Data {
    mutating func appendLittleEndianUInt32(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
