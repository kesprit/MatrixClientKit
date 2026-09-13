/// Timeline d'une room : historique observable et envoi de messages.
public protocol Timeline: Sendable {
    /// Flux d'instantanés : chaque valeur est la liste complète et à jour des éléments.
    var items: AsyncStream<[TimelineItem]> { get }

    /// Charge des éléments plus anciens. Renvoie `true` s'il reste de l'historique à charger.
    @discardableResult
    func paginateBackwards(count: Int) async throws -> Bool

    /// Envoie un message. L'écho local apparaît dans ``items`` sans action supplémentaire.
    func send(_ content: MessageContent) async throws
}
