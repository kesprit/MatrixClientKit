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
    private var handles: [RoomID: MockRoomHandle] = [:]
    private var isFinished = false

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
            let current = lock.withLock { () -> [RoomSummary]? in
                if isFinished { return nil }
                let identifier = nextObserverID
                nextObserverID += 1
                observers[identifier] = Observer(filter: filter, continuation: continuation)
                continuation.onTermination = { [weak self] _ in
                    self?.removeObserver(identifier)
                }
                return rooms
            }
            if let current {
                continuation.yield(Self.apply(filter, to: current))
            } else {
                continuation.finish()
            }
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

    /// Ends every stream opened by ``list(filter:)``, and the typing streams of the handles
    /// already returned.
    ///
    /// A list or typing subscription opened afterwards — a typing one on a known handle or on one
    /// created later — ends at once without any value, and ``emit(_:)`` does not reopen it. That
    /// reproduces the real service, whose stream ends with no value when its subscription fails.
    ///
    /// - Important: without this, the `for await` loop the README and the DocC teach never
    ///   returns when driven by this mock.
    public func finish() {
        let (observers, handles) = lock.withLock { () -> ([Observer], [MockRoomHandle]) in
            isFinished = true
            let current = Array(self.observers.values)
            self.observers.removeAll()
            return (current, Array(self.handles.values))
        }
        for observer in observers {
            observer.continuation.finish()
        }
        for handle in handles {
            handle.finish()
        }
    }

    /// Returns the handle for a room: always the same ``MockRoomHandle`` for a given identifier,
    /// so a test can drive and inspect the handle the code under test obtained through this
    /// service. Any identifier resolves, whether or not it is in the list.
    public func room(_ id: RoomID) async throws -> any RoomHandle {
        handle(for: id)
    }

    /// The handle ``room(_:)`` returns for `id`, created on first use. Synchronous, so a test can
    /// call ``MockRoomHandle/emitTypingUsers(_:)`` or read ``MockRoomHandle/typingNotices``
    /// without awaiting.
    public func handle(for id: RoomID) -> MockRoomHandle {
        let (handle, isNew, finished) = lock.withLock { () -> (MockRoomHandle, Bool, Bool) in
            if let existing = handles[id] { return (existing, false, isFinished) }
            let created = MockRoomHandle(id: id, timeline: timeline)
            handles[id] = created
            return (created, true, isFinished)
        }
        if isNew && finished { handle.finish() }
        return handle
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
///
/// Typing is driven by ``emitTypingUsers(_:)`` and recorded by ``typingNotices``. Like the real
/// handle, every access to ``typingUsers`` opens its own subscription, and ``finish()`` ends the
/// open ones. A subscription opened after ``finish()`` ends at once without any value, and
/// ``emitTypingUsers(_:)`` does not reopen it.
public final class MockRoomHandle: RoomHandle, @unchecked Sendable {
    public let id: RoomID
    private let mockTimeline: MockTimeline

    private let lock = NSLock()
    private var typingObservers: [Int: AsyncStream<[UserID]>.Continuation] = [:]
    private var nextTypingObserverID = 0
    private var isTypingFinished = false
    private var _typingNotices: [Bool] = []
    private var _typingError: MatrixError?

    public init(id: RoomID, timeline: MockTimeline) {
        self.id = id
        self.mockTimeline = timeline
    }

    public func timeline() async throws -> any Timeline {
        mockTimeline
    }

    /// Each value passed to ``setTyping(_:)``, in call order. A call is recorded even when it
    /// then throws ``typingError``.
    public var typingNotices: [Bool] {
        lock.withLock { _typingNotices }
    }

    /// When set, ``setTyping(_:)`` records the call, then throws it.
    public var typingError: MatrixError? {
        get { lock.withLock { _typingError } }
        set { lock.withLock { _typingError = newValue } }
    }

    /// A stream of typing snapshots, in `.bufferingNewest(1)` like the real handle. It emits
    /// nothing until ``emitTypingUsers(_:)`` is called.
    ///
    /// Unlike the real handle, a list is never cleared after 30 seconds without update: a test of
    /// the code under test stays instantaneous. Emit `[]` to simulate that expiry.
    public var typingUsers: AsyncStream<[UserID]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let identifier = lock.withLock { () -> Int? in
                if isTypingFinished { return nil }
                let identifier = nextTypingObserverID
                nextTypingObserverID += 1
                typingObservers[identifier] = continuation
                return identifier
            }
            guard let identifier else {
                continuation.finish()
                return
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { _ = self?.typingObservers.removeValue(forKey: identifier) }
            }
        }
    }

    /// Pushes a snapshot of the members typing into every open ``typingUsers`` stream.
    public func emitTypingUsers(_ users: [UserID]) {
        let observers = lock.withLock { Array(typingObservers.values) }
        for observer in observers {
            observer.yield(users)
        }
    }

    /// Records the notice, then throws ``typingError`` when one is set.
    public func setTyping(_ isTyping: Bool) async throws {
        try lock.withLock {
            _typingNotices.append(isTyping)
            if let _typingError { throw _typingError }
        }
    }

    /// Ends every stream opened by ``typingUsers``.
    public func finish() {
        let observers = lock.withLock { () -> [AsyncStream<[UserID]>.Continuation] in
            isTypingFinished = true
            let current = Array(typingObservers.values)
            typingObservers.removeAll()
            return current
        }
        for observer in observers {
            observer.finish()
        }
    }
}
