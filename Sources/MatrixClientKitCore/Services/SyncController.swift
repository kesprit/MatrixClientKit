/// Pilote la synchronisation avec le homeserver.
public protocol SyncController: Sendable {
    /// Flux de l'état de synchronisation. Chaque appel ouvre un abonnement indépendant.
    var state: AsyncStream<SyncState> { get }

    /// Démarre la synchronisation avec le homeserver.
    func start() async

    /// Arrête la synchronisation.
    func stop() async
}
