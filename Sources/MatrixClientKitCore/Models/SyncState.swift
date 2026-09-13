/// État du service de synchronisation.
public enum SyncState: Sendable, Hashable {
    case idle
    case running
    case terminated
    case offline
    case error
}
