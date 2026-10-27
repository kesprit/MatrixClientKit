import Testing
@testable import MatrixClientKitCore
@testable import MatrixClientKitRust

private typealias Registry = SendHandleRegistry<String>

private func entry(_ id: String, _ handle: String?) -> Registry.Entry {
    Registry.Entry(id: id, handle: handle)
}

@Suite struct SendHandleRegistryTests {
    @Test func trackThenLookup() {
        let registry = Registry()
        registry.apply([.track(itemID: "a", "A")])
        #expect(registry.handle(for: "a") == "A")
    }

    @Test func untrackForgets() {
        let registry = Registry()
        registry.apply([.track(itemID: "a", "A"), .untrack(itemID: "a")])
        #expect(registry.handle(for: "a") == nil)
    }

    @Test func removeAllForgets() {
        let registry = Registry()
        registry.apply([.track(itemID: "a", "A"), .track(itemID: "b", "B")])
        registry.apply([.removeAll])
        #expect(registry.handle(for: "a") == nil)
        #expect(registry.handle(for: "b") == nil)
    }

    @Test func unknownIDIsNil() {
        let registry = Registry()
        #expect(registry.handle(for: "nope") == nil)
    }

    @Test func untrackingAnUnknownIDIsHarmless() {
        let registry = Registry()
        registry.apply([.untrack(itemID: "x"), .removeAll, .track(itemID: "a", "A")])
        #expect(registry.handle(for: "a") == "A")
    }
}

/// Suivi des ids d'une souscription : c'est lui qui sait quels éléments sortent sur un diff sans
/// id (`remove`, `truncate`, `pop*`).
@Suite struct SendHandleTrackingTests {
    private func feed(_ diffs: [CollectionDiff<Registry.Entry>], to registry: Registry, ids: inout [String]) {
        for diff in diffs {
            registry.apply(Registry.changes(for: diff, ids: &ids))
        }
    }

    @Test func removedItemLeavesTheRegistry() {
        let registry = Registry()
        var ids: [String] = []

        feed([.append([entry("a", "A"), entry("b", "B")])], to: registry, ids: &ids)
        #expect(registry.handle(for: "a") == "A")
        #expect(registry.handle(for: "b") == "B")

        feed([.remove(index: 0)], to: registry, ids: &ids)
        #expect(registry.handle(for: "a") == nil)
        #expect(registry.handle(for: "b") == "B")
        #expect(ids == ["b"])

        feed([.reset([entry("c", "C")])], to: registry, ids: &ids)
        #expect(registry.handle(for: "a") == nil)
        #expect(registry.handle(for: "b") == nil)
        #expect(registry.handle(for: "c") == "C")
        #expect(ids == ["c"])
    }

    @Test func sentItemIsUntracked() {
        let registry = Registry()
        var ids: [String] = []
        feed([.pushBack(entry("a", "A")), .set(index: 0, entry("a", nil))], to: registry, ids: &ids)
        #expect(registry.handle(for: "a") == nil)
        #expect(ids == ["a"])
    }

    @Test func truncateAndPopsUntrack() {
        let registry = Registry()
        var ids: [String] = []
        feed(
            [.append([entry("a", "A"), entry("b", "B"), entry("c", "C"), entry("d", "D")]), .truncate(length: 3)],
            to: registry, ids: &ids)
        #expect(registry.handle(for: "d") == nil)
        feed([.popFront, .popBack], to: registry, ids: &ids)
        #expect(registry.handle(for: "a") == nil)
        #expect(registry.handle(for: "c") == nil)
        #expect(registry.handle(for: "b") == "B")
        #expect(ids == ["b"])
    }

    @Test func setReplacingAnItemUntracksTheOldID() {
        let registry = Registry()
        var ids: [String] = []
        feed([.insert(index: 0, entry("a", "A")), .set(index: 0, entry("z", nil))], to: registry, ids: &ids)
        #expect(registry.handle(for: "a") == nil)
        #expect(ids == ["z"])
    }

    @Test func clearForgetsEverything() {
        let registry = Registry()
        var ids: [String] = []
        feed([.pushFront(entry("a", "A")), .clear], to: registry, ids: &ids)
        #expect(registry.handle(for: "a") == nil)
        #expect(ids.isEmpty)
    }

    /// Deux souscriptions reçoivent les mêmes diffs, chacune avec ses ids : le registre partagé
    /// reste cohérent.
    @Test func twoSubscriptionsFeedingTheSameDiffsAgree() {
        let registry = Registry()
        var first: [String] = []
        var second: [String] = []
        let diffs: [CollectionDiff<Registry.Entry>] = [.append([entry("a", "A"), entry("b", "B")]), .remove(index: 1)]
        for diff in diffs {
            registry.apply(Registry.changes(for: diff, ids: &first))
            registry.apply(Registry.changes(for: diff, ids: &second))
        }
        #expect(registry.handle(for: "a") == "A")
        #expect(registry.handle(for: "b") == nil)
        #expect(first == second)
    }
}
