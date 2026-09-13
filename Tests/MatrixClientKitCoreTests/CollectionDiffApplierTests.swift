import Testing
@testable import MatrixClientKitCore

private func apply(_ diffs: [CollectionDiff<String>], to items: [String]) -> [String] {
    CollectionDiffApplier.apply(diffs, to: items)
}

@Test func appendAddsAtTheEnd() {
    #expect(apply([.append(["c", "d"])], to: ["a", "b"]) == ["a", "b", "c", "d"])
}

@Test func clearEmptiesTheCollection() {
    #expect(apply([.clear], to: ["a", "b"]) == [])
}

@Test func pushFrontAndPushBack() {
    #expect(apply([.pushFront("x")], to: ["a"]) == ["x", "a"])
    #expect(apply([.pushBack("z")], to: ["a"]) == ["a", "z"])
}

@Test func popFrontAndPopBack() {
    #expect(apply([.popFront], to: ["a", "b"]) == ["b"])
    #expect(apply([.popBack], to: ["a", "b"]) == ["a"])
}

@Test func popOnEmptyCollectionIsIgnored() {
    #expect(apply([.popFront], to: []) == [])
    #expect(apply([.popBack], to: []) == [])
}

@Test func insertAtIndex() {
    #expect(apply([.insert(index: 1, "x")], to: ["a", "b"]) == ["a", "x", "b"])
}

@Test func insertAtEndIsValid() {
    #expect(apply([.insert(index: 2, "x")], to: ["a", "b"]) == ["a", "b", "x"])
}

@Test func setReplacesAtIndex() {
    #expect(apply([.set(index: 0, "x")], to: ["a", "b"]) == ["x", "b"])
}

@Test func removeAtIndex() {
    #expect(apply([.remove(index: 0)], to: ["a", "b"]) == ["b"])
}

@Test func truncateKeepsPrefix() {
    #expect(apply([.truncate(length: 1)], to: ["a", "b", "c"]) == ["a"])
}

@Test func truncateLongerThanCollectionIsNoop() {
    #expect(apply([.truncate(length: 9)], to: ["a"]) == ["a"])
}

@Test func resetReplacesEverything() {
    #expect(apply([.reset(["x", "y"])], to: ["a"]) == ["x", "y"])
}

@Test func outOfBoundsDiffIsIgnoredAndFollowingDiffsStillApply() {
    let result = apply([.set(index: 7, "boom"), .pushBack("ok")], to: ["a"])
    #expect(result == ["a", "ok"])
}

@Test func diffsAreAppliedInOrder() {
    let result = apply([.pushBack("b"), .pushFront("z"), .remove(index: 1)], to: ["a"])
    #expect(result == ["z", "b"])
}
