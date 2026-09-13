import Testing
@testable import MatrixClientKitCore

@Test func eachBatchOfDiffsProducesASnapshot() async {
    let (diffs, continuation) = AsyncStream<[CollectionDiff<String>]>.makeStream()
    var iterator = snapshotStream(from: diffs, initial: []).makeAsyncIterator()

    continuation.yield([.append(["a"])])
    #expect(await iterator.next() == ["a"])

    continuation.yield([.pushBack("b")])
    #expect(await iterator.next() == ["a", "b"])
}

@Test func snapshotsStartFromTheInitialValue() async {
    let (diffs, continuation) = AsyncStream<[CollectionDiff<String>]>.makeStream()
    let snapshots = snapshotStream(from: diffs, initial: ["z"])

    continuation.yield([.pushBack("a")])

    var received: [[String]] = []
    for await snapshot in snapshots {
        received.append(snapshot)
        break
    }

    #expect(received == [["z", "a"]])
}

@Test func snapshotStreamFinishesWhenTheDiffStreamFinishes() async {
    let (diffs, continuation) = AsyncStream<[CollectionDiff<String>]>.makeStream()
    let snapshots = snapshotStream(from: diffs, initial: [])

    continuation.yield([.append(["a"])])
    continuation.finish()

    var count = 0
    for await _ in snapshots { count += 1 }

    #expect(count == 1)
}

@Test func diffsWithinOneBatchAreComposedIntoASingleSnapshot() async {
    let (diffs, continuation) = AsyncStream<[CollectionDiff<String>]>.makeStream()
    let snapshots = snapshotStream(from: diffs, initial: [])

    continuation.yield([.append(["a", "b"]), .remove(index: 0), .pushFront("z")])

    var received: [[String]] = []
    for await snapshot in snapshots {
        received.append(snapshot)
        break
    }

    #expect(received == [["z", "b"]])
}
