/// Une modification atomique appliquée à une collection observée.
///
/// - Note: portée `package`, comme ``snapshotStream(from:initial:)`` : la v0.1 ne publie que des
///   instantanés, jamais de flux de diffs brut.
///
/// Ce type reprend la forme des flux de diffs du SDK Rust (timelines et listes de rooms
/// partagent exactement la même structure), mais reste indépendant de celui-ci : la logique
/// d'application est ainsi pure et testable sans binaire.
package enum CollectionDiff<Element: Sendable>: Sendable {
    case append([Element])
    case clear
    case pushFront(Element)
    case pushBack(Element)
    case popFront
    case popBack
    case insert(index: Int, Element)
    case set(index: Int, Element)
    case remove(index: Int)
    case truncate(length: Int)
    case reset([Element])
}

extension CollectionDiff: Equatable where Element: Equatable {}
