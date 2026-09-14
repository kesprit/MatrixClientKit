import Foundation
import MatrixClientKitCore

/// A drivable room service for tests.
///
/// ``list(filter:)`` immediately emits the current list, filtered the way the real service would,
/// then every list pushed through ``emit(_:)``. ``finish()`` ends the open streams. ``room(_:)``
/// returns handles that all share the same ``MockTimeline``.
///
/// - Note: every call to ``list(filter:)`` opens its own single-consumer stream, with its own
///   filter — just like the real service.
public final class MockRoomService: RoomService, @unchecked Sendable {
    private struct Observer {
        let filter: RoomFilter
        let continuation: AsyncStream<[RoomSummary]>.Continuation
    }

    private let lock = NSLock()
    private var rooms: [RoomSummary]
    private var observers: [Int: Observer] = [:]
    private var nextObserverID = 0

    /// The timeline every room of this mock returns.
    public let timeline = MockTimeline()

    public init(rooms: [RoomSummary] = SampleData.roomSummaries(count: 3)) {
        self.rooms = rooms
    }

    /// Returns a stream that emits the current filtered list, then every list pushed afterwards.
    ///
    /// - Important: the filter is genuinely applied. A mock that ignored it would turn a test
    ///   like "invited rooms are hidden" green against code that does not hide them.
    public func list(filter: RoomFilter) -> AsyncStream<[RoomSummary]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let current = lock.withLock { () -> [RoomSummary] in
                let identifier = nextObserverID
                nextObserverID += 1
                observers[identifier] = Observer(filter: filter, continuation: continuation)
                continuation.onTermination = { [weak self] _ in
                    self?.removeObserver(identifier)
                }
                return rooms
            }
            continuation.yield(Self.apply(filter, to: current))
        }
    }

    /// Replaces the current list and pushes it, filtered, into every open stream.
    public func emit(_ rooms: [RoomSummary]) {
        let observers = lock.withLock { () -> [Observer] in
            self.rooms = rooms
            return Array(self.observers.values)
        }
        for observer in observers {
            observer.continuation.yield(Self.apply(observer.filter, to: rooms))
        }
    }

    /// Ends every stream opened by ``list(filter:)``.
    ///
    /// - Important: without this, the `for await` loop the README and the DocC teach never
    ///   returns when driven by this mock.
    public func finish() {
        let observers = lock.withLock { () -> [Observer] in
            let current = Array(self.observers.values)
            self.observers.removeAll()
            return current
        }
        for observer in observers {
            observer.continuation.finish()
        }
    }

    public func room(_ id: RoomID) async throws -> any RoomHandle {
        MockRoomHandle(id: id, timeline: timeline)
    }

    private func removeObserver(_ identifier: Int) {
        lock.withLock { _ = observers.removeValue(forKey: identifier) }
    }

    private static func apply(_ filter: RoomFilter, to rooms: [RoomSummary]) -> [RoomSummary] {
        switch filter {
        case .all: rooms
        case .joined: rooms.filter { $0.membership == .joined }
        case .invited: rooms.filter { $0.membership == .invited }
        }
    }
}

/// A drivable room handle for tests: always returns the ``MockTimeline`` it was given at
/// initialisation.
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
