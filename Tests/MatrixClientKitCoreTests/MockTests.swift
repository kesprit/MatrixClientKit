import Testing
import Foundation
import MatrixClientKitCore
import MatrixClientKitMocks

@Test func mockTimelineDeliversEmittedItems() async {
    let timeline = MockTimeline()
    let stream = timeline.items

    timeline.emit([SampleData.message("bonjour", from: "@alice:matrix.org")])

    for await items in stream {
        #expect(items.count == 1)
        #expect(items.first?.message?.body == "bonjour")
        break
    }
}

@Test func mockTimelineRecordsSentMessages() async throws {
    let timeline = MockTimeline()
    try await timeline.send(.text("salut"))
    #expect(timeline.sentMessages == [.text("salut")])
}

@Test func mockTimelineCanSimulateAFailure() async {
    let timeline = MockTimeline()
    timeline.sendError = .network(.offline)

    await #expect(throws: MatrixError.network(.offline)) {
        try await timeline.send(.text("salut"))
    }
}

@Test func mockRoomServiceDeliversSampleRooms() async {
    let service = MockRoomService(rooms: SampleData.roomSummaries(count: 3))

    for await rooms in service.list(filter: .joined) {
        #expect(rooms.count == 3)
        break
    }
}

@Test func mockSessionExposesItsServices() async {
    let session = MockMatrixSession()
    #expect(session.userID.rawValue == "@alice:matrix.org")

    await session.sync.start()
    #expect((session.sync as? MockSyncController)?.startCallCount == 1)
}

@Test func mockSyncControllerEmitsRunningThenTerminated() async {
    let sync = MockSyncController()
    var iterator = sync.state.makeAsyncIterator()

    await sync.start()
    #expect(await iterator.next() == .running)

    await sync.stop()
    #expect(await iterator.next() == .terminated)
}
