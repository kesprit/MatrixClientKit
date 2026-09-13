import Foundation
import MatrixClientKitCore

/// Service de rooms pilotable pour les tests : ``list(filter:)`` renvoie la liste fournie à
/// l'initialisation, et ``room(_:)`` renvoie une poignée partageant toutes la même
/// ``MockTimeline``.
public final class MockRoomService: RoomService, @unchecked Sendable {
    private let lock = NSLock()
    private var rooms: [RoomSummary]

    /// Timeline renvoyée par toutes les rooms de ce mock.
    public let timeline = MockTimeline()

    public init(rooms: [RoomSummary] = SampleData.roomSummaries(count: 3)) {
        self.rooms = rooms
    }

    /// Renvoie un flux qui émet immédiatement la liste de rooms fournie à l'initialisation.
    ///
    /// - Note: Le flux renvoyé est mono-consommateur, comme tout `AsyncStream`.
    public func list(filter: RoomFilter) -> AsyncStream<[RoomSummary]> {
        lock.lock(); let current = rooms; lock.unlock()

        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuation.yield(current)
        }
    }

    public func room(_ id: RoomID) async throws -> any RoomHandle {
        MockRoomHandle(id: id, timeline: timeline)
    }
}

/// Poignée de room pilotable pour les tests : renvoie toujours la ``MockTimeline`` qu'on lui a
/// donnée à l'initialisation.
public struct MockRoomHandle: RoomHandle {
    public let id: RoomID
    private let mockTimeline: MockTimeline

    public init(id: RoomID, timeline: MockTimeline) {
        self.id = id
        self.mockTimeline = timeline
    }

    public func timeline() async throws -> any Timeline {
        mockTimeline
    }
}
