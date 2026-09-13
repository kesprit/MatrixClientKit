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
    ///
    /// - Important: ce flux n'a pas de canal d'erreur. Si l'abonnement amont échoue, ou si le
    ///   filtre demandé ne peut pas être appliqué, le flux **se termine sans avoir produit une
    ///   seule valeur** — délivrer une liste non filtrée répondrait à une autre question que
    ///   celle posée. Un consommateur qui n'a reçu aucun instantané doit donc traiter la
    ///   situation comme un échec, et non comme un compte sans rooms : les deux se distinguent
    ///   par la présence d'au moins une valeur, jamais par son contenu.
    ///
    /// - Note: une variante lançante, capable de dire *pourquoi* l'abonnement a échoué, est
    ///   prévue après la v0.1 ; la signature fixée par la conception de cette version est
    ///   `AsyncStream`.
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
