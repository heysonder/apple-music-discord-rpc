import Foundation

public protocol HTTPDataLoading {
    func data(for request: URLRequest) throws -> Data
}

public final class URLSessionHTTPDataLoader: HTTPDataLoading {
    private let session: URLSession
    private let timeout: TimeInterval

    public init(
        session: URLSession = .shared,
        timeout: TimeInterval = 5
    ) {
        self.session = session
        self.timeout = timeout
    }

    public func data(for request: URLRequest) throws -> Data {
        var request = request
        request.timeoutInterval = timeout

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = LockedResultBox<Data>()
        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error {
                resultBox.set(.failure(error))
                return
            }

            if let response = response as? HTTPURLResponse,
                !(200..<300).contains(response.statusCode)
            {
                resultBox.set(.failure(ArtworkResolverError.httpStatus(response.statusCode)))
                return
            }

            resultBox.set(.success(data ?? Data()))
        }

        task.resume()

        guard semaphore.wait(timeout: .now() + timeout) != .timedOut else {
            task.cancel()
            throw ArtworkResolverError.timeout
        }

        guard let result = resultBox.get() else {
            throw ArtworkResolverError.emptyResponse
        }

        return try result.get()
    }
}

public enum ArtworkResolverError: LocalizedError, Equatable {
    case timeout
    case emptyResponse
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "Artwork lookup timed out."
        case .emptyResponse:
            return "Artwork lookup returned no data."
        case .httpStatus(let statusCode):
            return "Artwork lookup failed with HTTP \(statusCode)."
        }
    }
}

private final class LockedResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func set(_ result: Result<Value, Error>) {
        lock.withLock {
            self.result = result
        }
    }

    func get() -> Result<Value, Error>? {
        lock.withLock {
            result
        }
    }
}
