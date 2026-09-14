/// Drives syncing with the homeserver.
public protocol SyncController: Sendable {
    /// A stream of the sync state. Every access opens an independent subscription.
    var state: AsyncStream<SyncState> { get }

    /// Starts syncing with the homeserver.
    func start() async

    /// Stops syncing.
    func stop() async
}
