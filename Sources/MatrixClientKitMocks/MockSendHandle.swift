import Foundation
import MatrixClientKitCore

/// A send handle for tests: counts calls to ``cancel()`` and ``retry()``, and returns or throws
/// what you configure.
public final class MockSendHandle: SendHandle, @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelResult = true
    private var _cancelError: MatrixError?
    private var _retryError: MatrixError?
    private var _cancelCount = 0
    private var _retryCount = 0

    public init() {}

    /// What ``cancel()`` returns when ``cancelError`` is not set. `true` by default.
    public var cancelResult: Bool {
        get { lock.withLock { _cancelResult } }
        set { lock.withLock { _cancelResult = newValue } }
    }

    /// The error ``cancel()`` throws. `nil` by default, meaning it succeeds.
    public var cancelError: MatrixError? {
        get { lock.withLock { _cancelError } }
        set { lock.withLock { _cancelError = newValue } }
    }

    /// The error ``retry()`` throws. `nil` by default, meaning it succeeds.
    public var retryError: MatrixError? {
        get { lock.withLock { _retryError } }
        set { lock.withLock { _retryError = newValue } }
    }

    /// How many times ``cancel()`` was called, whether it threw or not.
    public var cancelCount: Int { lock.withLock { _cancelCount } }

    /// How many times ``retry()`` was called, whether it threw or not.
    public var retryCount: Int { lock.withLock { _retryCount } }

    @discardableResult
    public func cancel() async throws -> Bool {
        let (result, error) = lock.withLock {
            _cancelCount += 1
            return (_cancelResult, _cancelError)
        }
        if let error { throw error }
        return result
    }

    public func retry() async throws {
        let error = lock.withLock {
            _retryCount += 1
            return _retryError
        }
        if let error { throw error }
    }
}
