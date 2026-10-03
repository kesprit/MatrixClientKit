import Foundation
import MatrixClientKitCore

/// A drivable ``OAuthLoginFlow``: ``complete(callbackURL:)`` returns or throws ``completeResult``
/// and records the URL; ``cancel()`` is counted.
public final class MockOAuthLoginFlow: OAuthLoginFlow, @unchecked Sendable {
    private let lock = NSLock()

    public let authorizationURL: URL
    private var _completeResult: Result<MockMatrixSession, MatrixError>
    private var _completedCallbackURLs: [URL] = []
    private var _cancelCount = 0

    public init(
        authorizationURL: URL = URL(string: "https://auth.example.org/authorize")!,
        completeResult: Result<MockMatrixSession, MatrixError> = .success(MockMatrixSession())
    ) {
        self.authorizationURL = authorizationURL
        self._completeResult = completeResult
    }

    /// What ``complete(callbackURL:)`` returns or throws.
    public var completeResult: Result<MockMatrixSession, MatrixError> {
        get { lock.withLock { _completeResult } }
        set { lock.withLock { _completeResult = newValue } }
    }

    /// Every URL passed to ``complete(callbackURL:)``, in order.
    public var completedCallbackURLs: [URL] { lock.withLock { _completedCallbackURLs } }

    /// How many times ``cancel()`` was called.
    public var cancelCount: Int { lock.withLock { _cancelCount } }

    public func complete(callbackURL: URL) async throws -> any MatrixSession {
        let result = lock.withLock {
            _completedCallbackURLs.append(callbackURL)
            return _completeResult
        }
        return try result.get()
    }

    public func cancel() async {
        lock.withLock { _cancelCount += 1 }
    }
}
