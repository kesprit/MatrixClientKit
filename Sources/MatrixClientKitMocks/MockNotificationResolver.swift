import Foundation
import MatrixClientKitCore

/// A drivable ``NotificationContentResolving`` for testing a notification service extension.
public final class MockNotificationResolver: NotificationContentResolving, @unchecked Sendable {
    private let lock = NSLock()

    private var _results: [MatrixPushPayload: NotificationResult] = [:]
    private var _defaultResult: NotificationResult = .notFound
    private var _error: MatrixError?
    private var _requests: [MatrixPushPayload] = []

    public init() {}

    /// What an event without a result of its own resolves to. ``NotificationResult/notFound`` by
    /// default.
    public var defaultResult: NotificationResult {
        get { lock.withLock { _defaultResult } }
        set { lock.withLock { _defaultResult = newValue } }
    }

    /// The error every resolution throws. `nil` by default.
    public var error: MatrixError? {
        get { lock.withLock { _error } }
        set { lock.withLock { _error = newValue } }
    }

    /// Every event asked for, in order, including those that threw.
    public var requests: [MatrixPushPayload] { lock.withLock { _requests } }

    /// Sets what one event resolves to.
    public func setResult(_ result: NotificationResult, roomID: RoomID, eventID: EventID) {
        lock.withLock { _results[MatrixPushPayload(roomID: roomID, eventID: eventID)] = result }
    }

    public func notification(roomID: RoomID, eventID: EventID) async throws -> NotificationResult {
        let key = MatrixPushPayload(roomID: roomID, eventID: eventID)
        return try lock.withLock {
            _requests.append(key)
            if let error = _error { throw error }
            return _results[key] ?? _defaultResult
        }
    }
}
