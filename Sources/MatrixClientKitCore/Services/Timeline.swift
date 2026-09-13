/// Timeline d'une room : historique observable et envoi de messages.
public protocol Timeline: Sendable {
    /// Flux d'instantanés : chaque valeur est la liste complète et à jour des éléments.
    ///
    /// - Important: chaque **accès** à cette propriété ouvre un abonnement indépendant, avec son
    ///   propre cycle de vie. Étant une propriété calculée, elle est la plus facile à lire deux
    ///   fois sans le vouloir : `for await x in timeline.items` puis, ailleurs,
    ///   `for await y in timeline.items` observent deux abonnements distincts, pas deux vues du
    ///   même. Conserver le flux dans une variable pour le partager au sein d'une même boucle.
    var items: AsyncStream<[TimelineItem]> { get }

    /// Charge des éléments plus anciens. Renvoie `true` s'il reste de l'historique à charger.
    @discardableResult
    func paginateBackwards(count: Int) async throws -> Bool

    /// Envoie un message. L'écho local apparaît dans ``items`` sans action supplémentaire.
    func send(_ content: MessageContent) async throws
}
