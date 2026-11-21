import Foundation
import MatrixClientKitCore
import MatrixClientKitMocks
import Testing

@Suite struct MockRoomHandleTypingTests {
    private func makeHandle() -> MockRoomHandle {
        MockRoomHandle(id: RoomID(rawValue: "!r:e.org")!, timeline: MockTimeline())
    }

    private func user(_ raw: String) -> UserID { UserID(rawValue: raw)! }

    @Test func emittedSnapshotsReachTheStream() async {
        let handle = makeHandle()
        let stream = handle.typingUsers
        handle.emitTypingUsers([user("@a:e.org")])

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == [user("@a:e.org")])
    }

    @Test func everyAccessIsAnIndependentSubscription() async {
        let handle = makeHandle()
        let first = handle.typingUsers
        let second = handle.typingUsers
        handle.emitTypingUsers([user("@a:e.org")])

        var firstIterator = first.makeAsyncIterator()
        var secondIterator = second.makeAsyncIterator()
        #expect(await firstIterator.next() == [user("@a:e.org")])
        #expect(await secondIterator.next() == [user("@a:e.org")])
    }

    @Test func finishEndsTheTypingStream() async {
        let handle = makeHandle()
        let stream = handle.typingUsers
        handle.finish()

        var received: [[UserID]] = []
        for await snapshot in stream { received.append(snapshot) }
        #expect(received.isEmpty)
    }

    @Test func setTypingIsRecorded() async throws {
        let handle = makeHandle()
        try await handle.setTyping(true)
        try await handle.setTyping(false)
        #expect(handle.typingNotices == [true, false])
    }

    @Test func typingErrorIsThrownAfterTheAttemptIsRecorded() async {
        let handle = makeHandle()
        handle.typingError = .network(.offline)
        await #expect(throws: MatrixError.self) { try await handle.setTyping(true) }
        #expect(handle.typingNotices == [true])
    }

    @Test func serviceReturnsTheSameHandleForARoomAndExposesItSynchronously() async throws {
        let service = MockRoomService()
        let id = RoomID(rawValue: "!r:e.org")!
        let obtained = try await service.room(id)
        let again = try await service.room(id)
        let handle = service.handle(for: id)
        #expect(obtained as? MockRoomHandle === handle)
        #expect(again as? MockRoomHandle === handle)

        let stream = obtained.typingUsers
        handle.emitTypingUsers([user("@a:e.org")])
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == [user("@a:e.org")])

        try await again.setTyping(true)
        #expect(handle.typingNotices == [true])
    }

    @Test func serviceFinishEndsTheTypingStreamsOfItsHandles() async throws {
        let service = MockRoomService()
        let id = RoomID(rawValue: "!r:e.org")!
        let stream = service.handle(for: id).typingUsers
        service.finish()

        var received: [[UserID]] = []
        for await snapshot in stream { received.append(snapshot) }
        #expect(received.isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func typingSubscriptionOpenedAfterHandleFinishEndsWithoutValue() async {
        let handle = makeHandle()
        handle.finish()
        let stream = handle.typingUsers
        handle.emitTypingUsers([user("@a:e.org")])

        var received: [[UserID]] = []
        for await snapshot in stream { received.append(snapshot) }
        #expect(received.isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func typingSubscriptionOpenedAfterServiceFinishEndsWithoutValue() async throws {
        let service = MockRoomService()
        let known = RoomID(rawValue: "!known:e.org")!
        _ = service.handle(for: known)
        service.finish()

        let knownStream = service.handle(for: known).typingUsers
        let newStream = try await service.room(RoomID(rawValue: "!new:e.org")!).typingUsers

        var received: [[UserID]] = []
        for await snapshot in knownStream { received.append(snapshot) }
        for await snapshot in newStream { received.append(snapshot) }
        #expect(received.isEmpty)
    }
}
