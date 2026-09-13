/// Filtre appliqué à la liste de rooms.
public enum RoomFilter: Sendable, Hashable {
    /// Toutes les rooms, quelle que soit l'appartenance.
    case all
    /// Uniquement les rooms rejointes.
    case joined
    /// Uniquement les rooms auxquelles l'utilisateur courant est invité.
    case invited
}

/// Accès aux rooms et à la liste observable.
public protocol RoomService: Sendable {
    /// Flux d'instantanés de la liste de rooms : chaque valeur est la liste complète et à jour.
    ///
    /// Chaque appel ouvre un abonnement indépendant, avec son propre cycle de vie.
    func list(filter: RoomFilter) -> AsyncStream<[RoomSummary]>

    /// Récupère une room par identifiant.
    func room(_ id: RoomID) async throws -> any RoomHandle
}

/// Poignée sur une room donnée.
public protocol RoomHandle: Sendable {
    /// Identifiant de la room.
    var id: RoomID { get }

    /// Ouvre la timeline de la room.
    func timeline() async throws -> any Timeline
}
