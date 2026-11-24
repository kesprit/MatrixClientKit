/// A filter applied to the room list.
public enum RoomFilter: Sendable, Hashable {
    /// Every room, whatever the membership.
    case all
    /// Joined rooms only.
    case joined
    /// Only rooms the current user is invited to.
    case invited
}

/// Access to rooms and to the observable list.
public protocol RoomService: Sendable {
    /// A stream of room-list snapshots: every value is the complete, current list.
    ///
    /// Every call opens an independent subscription, with its own lifetime.
    ///
    /// - Note: known limitation of this version: the list shows at most 50 rooms.
    ///
    /// - Important: this stream has no error channel. If the upstream subscription fails, or if
    ///   the requested filter cannot be applied, the stream **ends without producing a single
    ///   value** — delivering an unfiltered list would answer a different question from the one
    ///   asked. A consumer that received no snapshot should therefore treat it as a failure, not
    ///   as an account with no rooms: the two differ by whether any value arrived, never by its
    ///   contents.
    ///
    /// - Note: a throwing variant, able to say *why* a subscription failed, is planned after
    ///   v0.1; the signature this version's design settled on is `AsyncStream`.
    func list(filter: RoomFilter) -> AsyncStream<[RoomSummary]>

    /// Looks a room up by identifier.
    ///
    /// - Important: resolution happens against the synced room list, not against the server.
    ///   Until sync has surfaced the room, this call fails with ``MatrixError/notFound(_:)`` even
    ///   though the room exists server-side. After signing in, wait for the room to appear in
    ///   ``list(filter:)`` before asking for it.
    func room(_ id: RoomID) async throws -> any RoomHandle
}

/// A handle on one room.
public protocol RoomHandle: Sendable {
    /// The room's identifier.
    var id: RoomID { get }

    /// Opens the room's timeline.
    func timeline() async throws -> any Timeline

    /// A stream of snapshots: every value is the complete, current list of members typing in this
    /// room, the current user excluded. Every access opens an independent subscription.
    ///
    /// A non-empty list that receives no new value for 30 seconds falls back to `[]`: the
    /// homeserver's update is lost when sync is interrupted, and the stream has no initial value.
    /// A member typing without a pause for longer disappears until their next change.
    var typingUsers: AsyncStream<[UserID]> { get }

    /// Tells the room whether the current user is typing. Call it with `true` as the user types and
    /// with `false` when they stop or send.
    func setTyping(_ isTyping: Bool) async throws
}
