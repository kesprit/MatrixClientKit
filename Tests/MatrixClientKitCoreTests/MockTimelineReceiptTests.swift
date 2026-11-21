import Testing
import MatrixClientKitMocks
@testable import MatrixClientKitCore

@Suite struct MockTimelineReceiptTests {
    @Test func recordsCallsInOrder() async throws {
        let timeline = MockTimeline()
        let id = EventID(rawValue: "$e")!
        try await timeline.markAsRead(visibility: .public)
        try await timeline.markAsRead(visibility: .private)
        try await timeline.markAsRead(upTo: id, visibility: .private)
        #expect(timeline.markAsReadCalls == [.public, .private])
        #expect(timeline.markAsReadUpToCalls.map(\.eventID) == [id])
        #expect(timeline.markAsReadUpToCalls.map(\.visibility) == [.private])
    }

    @Test func errorIsThrownAndNothingRecorded() async {
        let timeline = MockTimeline()
        let error = MatrixError.unexpected(message: "x", details: nil)
        timeline.markAsReadError = error
        await #expect(throws: error) { try await timeline.markAsRead(visibility: .public) }
        await #expect(throws: error) {
            try await timeline.markAsRead(upTo: EventID(rawValue: "$e")!, visibility: .public)
        }
        #expect(timeline.markAsReadCalls.isEmpty)
        #expect(timeline.markAsReadUpToCalls.isEmpty)
    }
}
