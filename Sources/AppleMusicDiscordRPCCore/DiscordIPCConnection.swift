import Darwin
import Foundation

final class DiscordIPCConnection {
    private var fileDescriptor: Int32

    private init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        close()
    }

    static func connect(path: String) throws -> DiscordIPCConnection {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw DiscordIPCError.socketFailure("socket", errno)
        }

        do {
            try configure(descriptor: descriptor)
            try connect(descriptor: descriptor, path: path)
            return DiscordIPCConnection(fileDescriptor: descriptor)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    func writeFrame(opcode: DiscordOpcode, payload: Data) throws {
        try writeAll(DiscordIPCFrameCoder.encode(opcode: opcode, payload: payload))
    }

    func readFrame() throws -> DiscordIPCFrame {
        let header = try readExact(byteCount: DiscordIPCFrameCoder.headerLength)
        let decodedHeader = try DiscordIPCFrameCoder.readHeader(header)
        let payload = try readExact(byteCount: decodedHeader.payloadLength)
        return DiscordIPCFrame(opcode: decodedHeader.opcode, payload: payload)
    }

    func close() {
        guard fileDescriptor >= 0 else {
            return
        }

        Darwin.close(fileDescriptor)
        fileDescriptor = -1
    }

    private static func configure(descriptor: Int32) throws {
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        try setSocketOption(
            descriptor: descriptor,
            option: SO_RCVTIMEO,
            value: &timeout,
            operation: "setsockopt SO_RCVTIMEO"
        )
        try setSocketOption(
            descriptor: descriptor,
            option: SO_SNDTIMEO,
            value: &timeout,
            operation: "setsockopt SO_SNDTIMEO"
        )

        var enabled: Int32 = 1
        try setSocketOption(
            descriptor: descriptor,
            option: SO_NOSIGPIPE,
            value: &enabled,
            operation: "setsockopt SO_NOSIGPIPE"
        )
    }

    private static func setSocketOption<Value>(
        descriptor: Int32,
        option: Int32,
        value: inout Value,
        operation: String
    ) throws {
        let result = withUnsafePointer(to: &value) { pointer in
            setsockopt(
                descriptor,
                SOL_SOCKET,
                option,
                UnsafeRawPointer(pointer),
                socklen_t(MemoryLayout<Value>.size)
            )
        }
        guard result == 0 else {
            throw DiscordIPCError.socketFailure(operation, errno)
        }
    }

    private static func connect(descriptor: Int32, path: String) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = Array(path.utf8) + [0]
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw DiscordIPCError.socketPathTooLong(path)
        }

        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.copyBytes(from: pathBytes)
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(
                    descriptor,
                    sockaddrPointer,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }

        guard result == 0 else {
            throw DiscordIPCError.socketFailure("connect", errno)
        }
    }

    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }

            var offset = 0
            while offset < data.count {
                let result = Darwin.write(
                    fileDescriptor,
                    baseAddress.advanced(by: offset),
                    data.count - offset
                )

                if result > 0 {
                    offset += result
                } else if result == -1 && errno == EINTR {
                    continue
                } else {
                    throw DiscordIPCError.socketFailure("write", errno)
                }
            }
        }
    }

    private func readExact(byteCount: Int) throws -> Data {
        guard byteCount > 0 else {
            return Data()
        }

        var data = Data(count: byteCount)
        try data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }

            var offset = 0
            while offset < byteCount {
                let result = Darwin.read(
                    fileDescriptor,
                    baseAddress.advanced(by: offset),
                    byteCount - offset
                )

                if result > 0 {
                    offset += result
                } else if result == 0 {
                    throw DiscordIPCError.disconnected
                } else if errno == EINTR {
                    continue
                } else {
                    throw DiscordIPCError.socketFailure("read", errno)
                }
            }
        }

        return data
    }
}
