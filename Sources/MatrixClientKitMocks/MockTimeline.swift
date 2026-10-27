import Foundation
import MatrixClientKitCore

/// A drivable timeline for tests: push snapshots on demand, observe what was sent, or simulate a
/// failed send or a failed pagination — independently.
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
    private var _paginationError: MatrixError?
    private var _paginateResult = true
    private var _sentAttachments: [Attachment] = []
    private var _attachmentSendError: MatrixError?
    private var _nextAttachmentUpload = MockAttachmentUpload()
    private var _nextSendHandle = MockSendHandle()
    private var _sendHandles: [TimelineItem.ID: MockSendHandle] = [:]

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

    /// The error to throw from ``send(_:)``. `nil` by default, meaning sends succeed.
    public var sendError: MatrixError? {
        get { lock.withLock { _sendError } }
        set { lock.withLock { _sendError = newValue } }
    }

    /// The error to throw from ``paginateBackwards(count:)``. `nil` by default, meaning pagination
    /// succeeds.
    public var paginationError: MatrixError? {
        get { lock.withLock { _paginationError } }
        set { lock.withLock { _paginationError = newValue } }
    }

    /// What ``paginateBackwards(count:)`` returns when ``paginationError`` is not set. `true` by
    /// default.
    public var paginateResult: Bool {
        get { lock.withLock { _paginateResult } }
        set { lock.withLock { _paginateResult = newValue } }
    }

    /// The attachments passed to ``send(_:)-(Attachment)``, in the order they were sent.
    public var sentAttachments: [Attachment] {
        lock.withLock { _sentAttachments }
    }

    /// The error to throw from ``send(_:)-(Attachment)``. `nil` by default, meaning sends succeed.
    public var attachmentSendError: MatrixError? {
        get { lock.withLock { _attachmentSendError } }
        set { lock.withLock { _attachmentSendError = newValue } }
    }

    /// The upload ``send(_:)-(Attachment)`` returns. Created once with the mock: the same
    /// instance is returned on every call until you replace it — set a new one between sends to
    /// tell them apart.
    public var nextAttachmentUpload: MockAttachmentUpload {
        get { lock.withLock { _nextAttachmentUpload } }
        set { lock.withLock { _nextAttachmentUpload = newValue } }
    }

    /// The handle a message send returns. Created once with the mock: the same instance is
    /// returned on every call until you replace it.
    public var nextSendHandle: MockSendHandle {
        get { lock.withLock { _nextSendHandle } }
        set { lock.withLock { _nextSendHandle = newValue } }
    }

    /// The handle ``sendHandle(for:)`` returns for each item, by identifier. Empty by default,
    /// meaning every item is remote or already sent.
    public var sendHandles: [TimelineItem.ID: MockSendHandle] {
        get { lock.withLock { _sendHandles } }
        set { lock.withLock { _sendHandles = newValue } }
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
        if let error = paginationError { throw error }
        return paginateResult
    }

    /// Records `content`, then returns ``nextSendHandle`` — or throws ``sendError``, in which
    /// case nothing is recorded.
    @discardableResult
    public func send(_ content: MessageContent) async throws -> any SendHandle {
        if let error = sendError { throw error }
        return lock.withLock {
            _sentMessages.append(content)
            return _nextSendHandle
        }
    }

    /// Records `attachment`, then returns ``nextAttachmentUpload`` — or throws
    /// ``attachmentSendError``, in which case nothing is recorded.
    @discardableResult
    public func send(_ attachment: Attachment) async throws -> any AttachmentUpload {
        if let error = attachmentSendError { throw error }
        return lock.withLock {
            _sentAttachments.append(attachment)
            return _nextAttachmentUpload
        }
    }

    /// The handle configured in ``sendHandles`` for `item`, or `nil`.
    public func sendHandle(for item: TimelineItem) -> (any SendHandle)? {
        lock.withLock { _sendHandles[item.id] }
    }
}
