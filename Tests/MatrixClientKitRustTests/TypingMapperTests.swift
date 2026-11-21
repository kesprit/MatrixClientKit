import Foundation
import MatrixClientKitCore
import MatrixRustSDK
import Testing

@testable import MatrixClientKitRust

private final class FakeTypingHandle: TaskHandleProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() { lock.withLock { cancelled = true } }
    func isFinished() -> Bool { lock.withLock { cancelled } }
}

/// Retient le listener que `TypingMapper.stream` a fourni à l'abonnement.
private final class ListenerSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var listener: (any TypingNotificationsListener)?

    func store(_ listener: any TypingNotificationsListener) { lock.withLock { self.listener = listener } }
    func call(_ ids: [String]) {
        let listener = lock.withLock { self.listener }
        listener?.call(typingUserIds: ids)
    }
}

@Suite struct TypingMapperTests {
    @Test func ownUserIsExcluded() {
        let users = TypingMapper.users(from: ["@me:e.org", "@a:e.org"], excluding: "@me:e.org")
        #expect(users.map(\.rawValue) == ["@a:e.org"])
    }

    @Test func invalidUserIDsAreDropped() {
        let users = TypingMapper.users(from: ["not-an-id", "@a:e.org", "@:e.org"], excluding: "@me:e.org")
        #expect(users.map(\.rawValue) == ["@a:e.org"])
    }

    @Test func upstreamOrderIsPreserved() {
        let users = TypingMapper.users(from: ["@b:e.org", "@a:e.org"], excluding: "@me:e.org")
        #expect(users.map(\.rawValue) == ["@b:e.org", "@a:e.org"])
    }

    @Test func emptyListStaysEmpty() {
        #expect(TypingMapper.users(from: [], excluding: "@me:e.org").isEmpty)
    }

    @Test func streamDeliversMappedSnapshots() async {
        let slot = ListenerSlot()
        let stream = TypingMapper.stream(ownUserID: "@me:e.org") { listener in
            slot.store(listener)
            return FakeTypingHandle()
        }
        slot.call(["@me:e.org", "@a:e.org"])

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next()?.map(\.rawValue) == ["@a:e.org"])
    }

    @Test func streamKeepsOnlyTheNewestSnapshot() async {
        let slot = ListenerSlot()
        let stream = TypingMapper.stream(ownUserID: "@me:e.org") { listener in
            slot.store(listener)
            return FakeTypingHandle()
        }
        slot.call(["@a:e.org"])
        slot.call(["@b:e.org"])

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next()?.map(\.rawValue) == ["@b:e.org"])
    }

    @Test func leavingTheLoopCancelsTheUpstreamHandle() async {
        let handle = FakeTypingHandle()
        let slot = ListenerSlot()

        for await _ in TypingMapper.stream(
            ownUserID: "@me:e.org",
            subscribe: { listener in
                slot.store(listener)
                listener.call(typingUserIds: ["@a:e.org"])
                return handle
            })
        {
            break
        }

        try? await Task.sleep(for: .milliseconds(50))
        #expect(handle.isFinished())
    }
}
