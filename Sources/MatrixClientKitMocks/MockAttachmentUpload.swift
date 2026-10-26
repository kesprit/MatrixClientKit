import Foundation
import MatrixClientKitCore

/// An attachment upload for tests: ``waitUntilQueued()`` returns at once, throws ``waitError``, or
/// throws `CancellationError` once ``cancel()`` was called.
public final class MockAttachmentUpload: AttachmentUpload, @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelCount = 0
    private var _waitError: MatrixError?

    public init() {}

    /// How many times ``cancel()`` was called.
    public var cancelCount: Int { lock.withLock { _cancelCount } }

    /// The error ``waitUntilQueued()`` throws when the upload was not cancelled. `nil` by default,
    /// meaning the media is queued.
    public var waitError: MatrixError? {
        get { lock.withLock { _waitError } }
        set { lock.withLock { _waitError = newValue } }
    }

    public func cancel() {
        lock.withLock { _cancelCount += 1 }
    }

    public func waitUntilQueued() async throws {
        let (cancelled, error) = lock.withLock { (_cancelCount > 0, _waitError) }
        if cancelled { throw CancellationError() }
        if let error { throw error }
    }
}
