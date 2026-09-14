import Foundation
import MatrixClientKitCore

/// A drivable sync controller for tests: counts calls to ``start()`` and ``stop()``, and lets you
/// push arbitrary states into ``state``.
///
/// ``emit(_:)`` pushes a state, ``finish()`` ends the stream — the same pair as ``MockTimeline``
/// and ``MockRoomService``.
///
/// - Note: ``state`` exposes a single, single-consumer stream.
/// - Note: ``start()`` and ``stop()`` imitate the state sequence the real controller produces
///   (`.running` then `.terminated`) so that a `switch` tested against this mock still holds
///   against a real homeserver. That is a testing convenience, not a guarantee of the protocol:
///   nothing stops you from ``emit(_:)``-ing any other ``SyncState`` to cover a specific case.
public final class MockSyncController: SyncController, @unchecked Sendable {
    private let lock = NSLock()
    private let stream: AsyncStream<SyncState>
    private let continuation: AsyncStream<SyncState>.Continuation

    private var _startCallCount = 0
    private var _stopCallCount = 0

    public init() {
        (stream, continuation) = AsyncStream<SyncState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    /// The stream of sync states. Single-consumer: see the note on the type.
    public var state: AsyncStream<SyncState> { stream }

    /// How many times ``start()`` was called since the mock was created.
    public var startCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _startCallCount
    }

    /// How many times ``stop()`` was called since the mock was created.
    public var stopCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _stopCallCount
    }

    /// Pushes a new state into ``state``.
    public func emit(_ state: SyncState) {
        continuation.yield(state)
    }

    /// Ends the ``state`` stream.
    ///
    /// - Important: without this, a `for await` loop over ``state`` never returns when driven by
    ///   this mock.
    public func finish() {
        continuation.finish()
    }

    /// Increments ``startCallCount`` and pushes ``SyncState/running`` into ``state``.
    public func start() async {
        lock.withLock { _startCallCount += 1 }
        emit(.running)
    }

    /// Increments ``stopCallCount`` and pushes ``SyncState/terminated`` into ``state``.
    public func stop() async {
        lock.withLock { _stopCallCount += 1 }
        emit(.terminated)
    }
}
