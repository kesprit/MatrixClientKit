/// The state of the sync service.
public enum SyncState: Sendable, Hashable {
    /// Syncing has not started yet.
    case idle
    /// Syncing is running and up to date.
    case running
    /// Syncing was stopped deliberately (``SyncController/stop()``) and will not resume without
    /// another call to ``SyncController/start()``.
    case terminated
    /// Syncing is paused for lack of network connectivity; it resumes on its own.
    case offline
    /// Syncing hit an error it cannot recover from on its own.
    case error
}
