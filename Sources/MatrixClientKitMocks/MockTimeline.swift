import Foundation
import MatrixClientKitCore

/// A drivable timeline for tests: push snapshots on demand, observe what was sent, or simulate a
/// failed send.
///
/// ``emit(_:)`` pushes a snapshot, ``finish()`` ends the stream — the same pair as
/// ``MockRoomService`` and ``MockSyncController``.
///
/// - Note: ``items`` exposes a single, single-consumer stream. Iterate over it once per
///   instance.
public final class MockTimeline: Timeline, @unchecked Sendable {
    private let lock = NSLock()
    private let stream: AsyncStream<[TimelineItem]>
    private let continuation: AsyncStream<[TimelineItem]>.Continuation

    private var _sentMessages: [MessageContent] = []
    private var _sendError: MatrixError?
    private var _paginateResult = true

    public init() {
        (stream, continuation) = AsyncStream<[TimelineItem]>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    /// The stream of timeline snapshots. Single-consumer: see the note on the type.
    public var items: AsyncStream<[TimelineItem]> { stream }

    /// The messages passed to ``send(_:)``, in the order they were sent.
    public var sentMessages: [MessageContent] {
        lock.lock(); defer { lock.unlock() }
        return _sentMessages
    }

    /// The error to throw from the next ``send(_:)`` or ``paginateBackwards(count:)``.
    /// `nil` by default, meaning those calls succeed.
    public var sendError: MatrixError? {
        get { lock.lock(); defer { lock.unlock() }; return _sendError }
        set { lock.lock(); _sendError = newValue; lock.unlock() }
    }

    /// What ``paginateBackwards(count:)`` returns when ``sendError`` is not set. `true` by
    /// default.
    public var paginateResult: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _paginateResult }
        set { lock.lock(); _paginateResult = newValue; lock.unlock() }
    }

    /// Pushes a new snapshot into ``items``.
    public func emit(_ items: [TimelineItem]) {
        continuation.yield(items)
    }

    /// Ends the ``items`` stream.
    ///
    /// - Important: without this, a `for await` loop over ``items`` never returns when driven by
    ///   this mock.
    public func finish() {
        continuation.finish()
    }

    @discardableResult
    public func paginateBackwards(count: Int) async throws -> Bool {
        if let error = sendError { throw error }
        return paginateResult
    }

    public func send(_ content: MessageContent) async throws {
        if let error = sendError { throw error }
        lock.withLock { _sentMessages.append(content) }
    }
}
