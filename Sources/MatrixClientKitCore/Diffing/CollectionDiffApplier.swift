/// Applique des diffs à une collection pour produire son état courant.
///
/// Un diff dont l'index est hors bornes est ignoré ; les diffs suivants sont appliqués
/// normalement. L'application ne provoque jamais d'erreur fatale.
enum CollectionDiffApplier: Sendable {

    static func apply<Element: Sendable>(
        _ diffs: [CollectionDiff<Element>],
        to items: [Element]
    ) -> [Element] {
        var result = items
        for diff in diffs {
            apply(diff, to: &result)
        }
        return result
    }

    private static func apply<Element: Sendable>(_ diff: CollectionDiff<Element>, to items: inout [Element]) {
        switch diff {
        case let .append(values):
            items.append(contentsOf: values)
        case .clear:
            items.removeAll()
        case let .pushFront(value):
            items.insert(value, at: 0)
        case let .pushBack(value):
            items.append(value)
        case .popFront:
            guard !items.isEmpty else { return }
            items.removeFirst()
        case .popBack:
            guard !items.isEmpty else { return }
            items.removeLast()
        case let .insert(index, value):
            guard index >= 0, index <= items.count else { return }
            items.insert(value, at: index)
        case let .set(index, value):
            guard items.indices.contains(index) else { return }
            items[index] = value
        case let .remove(index):
            guard items.indices.contains(index) else { return }
            items.remove(at: index)
        case let .truncate(length):
            guard length >= 0, length < items.count else { return }
            items.removeLast(items.count - length)
        case let .reset(values):
            items = values
        }
    }
}
