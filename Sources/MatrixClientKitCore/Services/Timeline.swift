/// A room's timeline: observable history, and sending messages.
public protocol Timeline: Sendable {
    /// A stream of snapshots: every value is the complete, current list of items.
    ///
    /// - Important: every **access** to this property opens an independent subscription with its
    ///   own lifetime. Being a computed property, it is the easiest one to read twice by
    ///   accident: `for await x in timeline.items` and, elsewhere,
    ///   `for await y in timeline.items` observe two distinct subscriptions, not two views of the
    ///   same one. Hold the stream in a variable to share it.
    var items: AsyncStream<[TimelineItem]> { get }

    /// Loads older items. Returns `true` when more history remains to load.
    @discardableResult
    func paginateBackwards(count: Int) async throws -> Bool

    /// Sends a message. Its local echo appears in ``items`` with no further action.
    ///
    /// - Returns: a handle to cancel the send while the message has not left, or to retry it
    ///   after a failure.
    @discardableResult
    func send(_ content: MessageContent) async throws -> any SendHandle

    /// Sends a media. Its local echo appears in ``items`` at once, with ``Message/uploadProgress``.
    ///
    /// A thumbnail, when given, is validated like the main file.
    ///
    /// - Returns: a handle to cancel the upload while it is being prepared, or wait until it is
    ///   queued. Once queued, the media is cancelled or retried like a message, through
    ///   ``sendHandle(for:)`` on its local echo.
    /// - Throws: ``MatrixError/notFound(_:)`` with `.media`, before any upstream call, when a
    ///   local file (the media or its thumbnail) is missing.
    func send(_ attachment: Attachment) async throws -> any AttachmentUpload

    /// The handle of the local echo `item` carries, or `nil` for a remote or already sent item.
    ///
    /// This is the path of the "retry" and "give up" buttons of a failed message, media included,
    /// even after the application was relaunched.
    ///
    /// - Note: only items that a subscription to ``items`` has seen are known — which is always
    ///   the case of a displayed item.
    func sendHandle(for item: TimelineItem) -> (any SendHandle)?
}
