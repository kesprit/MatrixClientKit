/// État du service de synchronisation.
public enum SyncState: Sendable, Hashable {
    /// La synchronisation n'a pas encore démarré.
    case idle
    /// La synchronisation est active et à jour.
    case running
    /// La synchronisation a été arrêtée volontairement (``SyncController/stop()``) et ne
    /// reprendra pas sans un nouvel appel à ``SyncController/start()``.
    case terminated
    /// La synchronisation est interrompue faute de connexion réseau ; elle reprendra d'elle-même.
    case offline
    /// La synchronisation a rencontré une erreur non récupérable automatiquement.
    case error
}
