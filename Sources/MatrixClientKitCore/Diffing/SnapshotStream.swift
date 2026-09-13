/// Transforme un flux de diffs en flux d'états complets.
///
/// - Note: portée `package`. La v0.1 n'expose aucun flux de diffs brut : cette machinerie n'a
///   donc ni producteur ni consommateur public, et geler une fonction globale — injectée dans
///   l'espace de noms de chaque application par le `@_exported import` — au moment du tag serait
///   irréversible.
///
/// Le flux d'entrée est consommé en `.unbounded` — perdre un diff corromprait l'état —, tandis
/// que les instantanés produits utilisent `.bufferingNewest(1)` : un consommateur lent ne voit
/// que le dernier état, et la mémoire reste bornée.
package func snapshotStream<Element: Sendable>(
    from diffs: AsyncStream<[CollectionDiff<Element>]>,
    initial: [Element] = []
) -> AsyncStream<[Element]> {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
        let task = Task {
            var current = initial
            for await batch in diffs {
                current = CollectionDiffApplier.apply(batch, to: current)
                continuation.yield(current)
            }
            continuation.finish()
        }

        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}
