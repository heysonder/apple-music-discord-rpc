import Foundation

public struct Logger: Sendable {
    public static let quiet = Logger(verbose: false)

    private let verbose: Bool

    public init(verbose: Bool) {
        self.verbose = verbose
    }

    public func log(_ message: String) {
        guard verbose else {
            return
        }

        FileHandle.standardError.writeLine(message)
    }
}

public extension FileHandle {
    func writeLine(_ line: String) {
        guard let data = "\(line)\n".data(using: .utf8) else {
            return
        }
        write(data)
    }
}
