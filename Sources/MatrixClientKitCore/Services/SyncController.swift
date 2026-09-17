/// Drives syncing with the homeserver.
public protocol SyncController: Sendable {
    /// A stream of the sync state. Every access opens an independent subscription.
    var state: AsyncStream<SyncState> { get }

    /// Starts syncing with the homeserver.
    ///
    /// Calling `start()` while syncing is already running has no effect; after
    /// ``SyncState/offline``, ``SyncState/error`` or ``SyncState/terminated`` it starts syncing
    /// again. Call it whenever the application returns to the foreground.
    func start() async

    /// Stops syncing.
    func stop() async
}
