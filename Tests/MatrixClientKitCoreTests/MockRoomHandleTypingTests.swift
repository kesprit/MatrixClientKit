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

    @Test func typingErrorIsThrownAndNothingIsRecorded() async {
        let handle = makeHandle()
        handle.typingError = .network(.offline)
        await #expect(throws: MatrixError.self) { try await handle.setTyping(true) }
        #expect(handle.typingNotices.isEmpty)
    }
}
