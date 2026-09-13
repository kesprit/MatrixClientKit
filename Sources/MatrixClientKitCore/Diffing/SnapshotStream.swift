/// Transforme un flux de diffs en flux d'états complets.
///
/// Le flux d'entrée est consommé en `.unbounded` — perdre un diff corromprait l'état —, tandis
/// que les instantanés produits utilisent `.bufferingNewest(1)` : un consommateur lent ne voit
/// que le dernier état, et la mémoire reste bornée.
public func snapshotStream<Element: Sendable>(
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
