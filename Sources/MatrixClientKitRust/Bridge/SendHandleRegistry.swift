import Synchronization
import MatrixClientKitCore

/// Registre `id d'élément → handle d'envoi` des échos locaux d'une timeline.
///
/// Pur, sans FFI : générique sur le handle pour être testable avec une simple chaîne ; en
/// production, c'est le `SendHandle` amont. Alimenté par les souscriptions à `items` (voir
/// ``changes(for:ids:)``), interrogé par `RustTimeline.sendHandle(for:)`.
final class SendHandleRegistry<Handle: Sendable>: Sendable {
    enum Change: Sendable {
        case track(itemID: String, Handle)
        case untrack(itemID: String)
        case removeAll
    }

    /// Ce que le registre retient d'un élément de diff : son id, et son handle s'il est encore un
    /// écho local en attente ou en échec (`nil` sinon).
    struct Entry: Sendable {
        let id: String
        let handle: Handle?
    }

    private let storage = Mutex<[String: Handle]>([:])

    /// Applique `changes` dans l'ordre. `track` et `untrack` sont idempotents : plusieurs
    /// souscriptions peuvent rejouer les mêmes changements sans effet de bord.
    func apply(_ changes: [Change]) {
        // Les handles évincés sont libérés après le verrou : leur `deinit` descend dans l'amont.
        let evicted = storage.withLock { handles -> [Handle] in
            var evicted: [Handle] = []
            for change in changes {
                switch change {
                case let .track(itemID, handle):
                    if let previous = handles.updateValue(handle, forKey: itemID) { evicted.append(previous) }
                case let .untrack(itemID):
                    if let previous = handles.removeValue(forKey: itemID) { evicted.append(previous) }
                case .removeAll:
                    evicted.append(contentsOf: handles.values)
                    handles.removeAll()
                }
            }
            return evicted
        }
        _ = evicted
    }

    func handle(for itemID: String) -> Handle? {
        storage.withLock { $0[itemID] }
    }

    /// Traduit un diff en changements du registre, en tenant à jour `ids`, la liste ordonnée des
    /// ids d'**une** souscription : c'est elle qui dit quels éléments sortent sur un diff qui ne
    /// porte pas d'id (`remove`, `truncate`, `pop*`) ou qui remplace un élément (`set`).
    static func changes(for diff: CollectionDiff<Entry>, ids: inout [String]) -> [Change] {
        let leaving = leavingIDs(for: diff, in: ids)
        ids = CollectionDiffApplier.apply([idDiff(from: diff)], to: ids)

        switch diff {
        case .clear:
            return [.removeAll]
        case let .reset(entries):
            return [.removeAll]
                + entries.compactMap { entry in
                    entry.handle.map { .track(itemID: entry.id, $0) }
                }
        default:
            return leaving.map { .untrack(itemID: $0) }
                + carriedEntries(of: diff).map { entry in
                    entry.handle.map { .track(itemID: entry.id, $0) } ?? .untrack(itemID: entry.id)
                }
        }
    }

    /// Les ids que `diff` fait sortir de `ids`, calculés avant application. Mêmes garde-fous de
    /// bornes que ``CollectionDiffApplier`` : un diff hors bornes ne fait sortir personne.
    private static func leavingIDs(for diff: CollectionDiff<Entry>, in ids: [String]) -> [String] {
        switch diff {
        case .popFront:
            return ids.first.map { [$0] } ?? []
        case .popBack:
            return ids.last.map { [$0] } ?? []
        case let .remove(index):
            return ids.indices.contains(index) ? [ids[index]] : []
        case let .truncate(length):
            guard length >= 0, length < ids.count else { return [] }
            return Array(ids[length...])
        case let .set(index, entry):
            guard ids.indices.contains(index), ids[index] != entry.id else { return [] }
            return [ids[index]]
        case .append, .clear, .pushFront, .pushBack, .insert, .reset:
            return []
        }
    }

    private static func carriedEntries(of diff: CollectionDiff<Entry>) -> [Entry] {
        switch diff {
        case let .append(entries), let .reset(entries):
            return entries
        case let .pushFront(entry), let .pushBack(entry), let .insert(_, entry), let .set(_, entry):
            return [entry]
        case .clear, .popFront, .popBack, .remove, .truncate:
            return []
        }
    }

    private static func idDiff(from diff: CollectionDiff<Entry>) -> CollectionDiff<String> {
        switch diff {
        case let .append(entries): .append(entries.map(\.id))
        case .clear: .clear
        case let .pushFront(entry): .pushFront(entry.id)
        case let .pushBack(entry): .pushBack(entry.id)
        case .popFront: .popFront
        case .popBack: .popBack
        case let .insert(index, entry): .insert(index: index, entry.id)
        case let .set(index, entry): .set(index: index, entry.id)
        case let .remove(index): .remove(index: index)
        case let .truncate(length): .truncate(length: length)
        case let .reset(entries): .reset(entries.map(\.id))
        }
    }
}
