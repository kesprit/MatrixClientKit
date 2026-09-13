/// Pilote la synchronisation avec le homeserver.
public protocol SyncController: Sendable {
    /// Flux de l'état de synchronisation. Chaque appel ouvre un abonnement indépendant.
    var state: AsyncStream<SyncState> { get }

    func start() async
    func stop() async
}
