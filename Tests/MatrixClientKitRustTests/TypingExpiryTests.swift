import Foundation
import MatrixClientKitCore
import MatrixRustSDK
import Testing

@testable import MatrixClientKitRust

private final class ExpiryTaskHandle: TaskHandleProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() { lock.withLock { cancelled = true } }
    func isFinished() -> Bool { lock.withLock { cancelled } }
}

/// Retient le listener fourni à l'abonnement, pour simuler les notifications amont.
private final class ExpiryListenerSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var listener: (any TypingNotificationsListener)?

    func store(_ listener: any TypingNotificationsListener) { lock.withLock { self.listener = listener } }
    func call(_ ids: [String]) {
        let listener = lock.withLock { self.listener }
        listener?.call(typingUserIds: ids)
    }
}

/// Horloge manuelle : chaque attente reste suspendue jusqu'à ``fireAll()`` ou jusqu'à
/// l'annulation de sa tâche, qui la retire des attentes en cours.
private final class ManualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var nextID = 0
    private var requested: [Duration] = []

    var pendingCount: Int { lock.withLock { pending.count } }
    var requestedDurations: [Duration] { lock.withLock { requested } }

    func sleep(_ duration: Duration) async throws {
        let id = lock.withLock { () -> Int in
            requested.append(duration)
            defer { nextID += 1 }
            return nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let cancelled = lock.withLock { () -> Bool in
                    if Task.isCancelled { return true }
                    pending[id] = continuation
                    return false
                }
                if cancelled { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let continuation = lock.withLock { pending.removeValue(forKey: id) }
            continuation?.resume(throwing: CancellationError())
        }
    }

    func fireAll() {
        let continuations = lock.withLock { () -> [CheckedContinuation<Void, any Error>] in
            defer { pending.removeAll() }
            return Array(pending.values)
        }
        for continuation in continuations { continuation.resume() }
    }

    /// Attend que `count` attentes soient en cours et que `total` attentes aient été demandées.
    func waitUntil(pending count: Int, requested total: Int) async {
        for _ in 0..<2_000 {
            let reached = lock.withLock { pending.count == count && requested.count == total }
            if reached { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record(
            "expected \(count) pending sleep(s) out of \(total), got \(pendingCount) of \(requestedDurations.count)"
        )
    }
}

@Suite(.timeLimit(.minutes(1))) struct TypingExpiryTests {
    private func makeStream(
        sleeper: ManualSleeper,
        handle: ExpiryTaskHandle = ExpiryTaskHandle()
    ) -> (AsyncStream<[UserID]>, ExpiryListenerSlot) {
        let slot = ExpiryListenerSlot()
        let stream = TypingMapper.stream(
            ownUserID: "@me:e.org",
            staleAfter: .seconds(30),
            sleep: { try await sleeper.sleep($0) },
            subscribe: { listener in
                slot.store(listener)
                return handle
            }
        )
        return (stream, slot)
    }

    @Test func defaultStaleDelayIsTheUsualMatrixTypingTimeout() {
        #expect(TypingMapper.staleDelay == .seconds(30))
    }

    @Test func aListLeftWithoutUpdateFallsBackToEmpty() async {
        let sleeper = ManualSleeper()
        let (stream, slot) = makeStream(sleeper: sleeper)
        var iterator = stream.makeAsyncIterator()

        slot.call(["@a:e.org"])
        #expect(await iterator.next()?.map(\.rawValue) == ["@a:e.org"])

        await sleeper.waitUntil(pending: 1, requested: 1)
        #expect(sleeper.requestedDurations == [.seconds(30)])
        sleeper.fireAll()
        #expect(await iterator.next() == [])
    }

    @Test func aNewSnapshotRearmsTheDelay() async {
        let sleeper = ManualSleeper()
        let (stream, slot) = makeStream(sleeper: sleeper)
        var iterator = stream.makeAsyncIterator()

        slot.call(["@a:e.org"])
        #expect(await iterator.next()?.map(\.rawValue) == ["@a:e.org"])
        await sleeper.waitUntil(pending: 1, requested: 1)

        slot.call(["@a:e.org", "@b:e.org"])
        #expect(await iterator.next()?.map(\.rawValue) == ["@a:e.org", "@b:e.org"])
        // Le premier délai est annulé : un seul reste en cours, celui de la nouvelle liste.
        await sleeper.waitUntil(pending: 1, requested: 2)

        sleeper.fireAll()
        #expect(await iterator.next() == [])
    }

    @Test func anEmptySnapshotArmsNoDelayAndCancelsThePendingOne() async {
        let sleeper = ManualSleeper()
        let (stream, slot) = makeStream(sleeper: sleeper)
        var iterator = stream.makeAsyncIterator()

        slot.call(["@a:e.org"])
        #expect(await iterator.next()?.map(\.rawValue) == ["@a:e.org"])
        await sleeper.waitUntil(pending: 1, requested: 1)

        slot.call([])
        #expect(await iterator.next() == [])
        await sleeper.waitUntil(pending: 0, requested: 1)
    }

    @Test func aListOfOnlyTheCurrentUserArmsNoDelay() async {
        let sleeper = ManualSleeper()
        let (stream, slot) = makeStream(sleeper: sleeper)
        var iterator = stream.makeAsyncIterator()

        slot.call(["@me:e.org"])
        #expect(await iterator.next() == [])
        slot.call(["@a:e.org"])
        #expect(await iterator.next()?.map(\.rawValue) == ["@a:e.org"])
        await sleeper.waitUntil(pending: 1, requested: 1)
    }

    @Test func leavingTheLoopCancelsThePendingDelayAndTheUpstreamHandle() async {
        let sleeper = ManualSleeper()
        let handle = ExpiryTaskHandle()
        let slot = ExpiryListenerSlot()

        // Flux non retenu par une variable : le garder vivant garderait l'abonnement (voir
        // `ffiStream`).
        for await _ in TypingMapper.stream(
            ownUserID: "@me:e.org",
            staleAfter: .seconds(30),
            sleep: { try await sleeper.sleep($0) },
            subscribe: { listener in
                slot.store(listener)
                listener.call(typingUserIds: ["@a:e.org"])
                return handle
            })
        {
            await sleeper.waitUntil(pending: 1, requested: 1)
            break
        }

        await sleeper.waitUntil(pending: 0, requested: 1)
        for _ in 0..<500 where !handle.isFinished() {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(handle.isFinished())
    }

    @Test func aFailedSubscriptionEndsTheStreamWithoutValue() async {
        struct SubscriptionFailure: Error {}
        let stream = TypingMapper.stream(
            ownUserID: "@me:e.org",
            staleAfter: .seconds(30),
            sleep: { _ in },
            subscribe: { _ in throw SubscriptionFailure() }
        )

        var received: [[UserID]] = []
        for await snapshot in stream { received.append(snapshot) }
        #expect(received.isEmpty)
    }
}
