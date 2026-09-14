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
    func send(_ content: MessageContent) async throws
}
