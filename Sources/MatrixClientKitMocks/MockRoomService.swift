import Foundation
import MatrixClientKitCore

/// Service de rooms pilotable pour les tests.
///
/// ``list(filter:)`` émet immédiatement la liste courante, filtrée comme le ferait le vrai
/// service, puis chaque liste poussée par ``emit(_:)``. ``finish()`` termine les flux ouverts.
/// ``room(_:)`` renvoie une poignée partageant toutes la même ``MockTimeline``.
///
/// - Note: chaque appel à ``list(filter:)`` ouvre son propre flux, mono-consommateur, avec son
///   propre filtre — comme le vrai service.
public final class MockRoomService: RoomService, @unchecked Sendable {
    private struct Observer {
        let filter: RoomFilter
        let continuation: AsyncStream<[RoomSummary]>.Continuation
    }

    private let lock = NSLock()
    private var rooms: [RoomSummary]
    private var observers: [Int: Observer] = [:]
    private var nextObserverID = 0

    /// Timeline renvoyée par toutes les rooms de ce mock.
    public let timeline = MockTimeline()

    public init(rooms: [RoomSummary] = SampleData.roomSummaries(count: 3)) {
        self.rooms = rooms
    }

    /// Renvoie un flux qui émet la liste courante filtrée, puis chaque liste poussée ensuite.
    ///
    /// - Important: le filtre est réellement appliqué. Un mock qui l'ignorerait ferait passer au
    ///   vert un test du type « les rooms en invitation sont masquées » écrit contre du code qui
    ///   ne les masque pas.
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

    /// Remplace la liste courante et la pousse, filtrée, dans chaque flux ouvert.
    public func emit(_ rooms: [RoomSummary]) {
        let observers = lock.withLock { () -> [Observer] in
            self.rooms = rooms
            return Array(self.observers.values)
        }
        for observer in observers {
            observer.continuation.yield(Self.apply(observer.filter, to: rooms))
        }
    }

    /// Termine tous les flux ouverts par ``list(filter:)``.
    ///
    /// - Important: sans cela, la boucle `for await` enseignée par le README et la DocC ne rend
    ///   jamais la main face à ce mock.
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
