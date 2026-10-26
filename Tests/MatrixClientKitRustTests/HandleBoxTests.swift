import Testing
import Foundation
import Synchronization
import MatrixRustSDK
@testable import MatrixClientKitRust

/// Faux `TaskHandle` dont la tâche ne se termine que sur demande, comme une tâche Tokio annulée
/// en plein `poll`.
private final class SlowTaskHandle: TaskHandleProtocol, Sendable {
    private let finished = Mutex(false)

    func cancel() {}

    func isFinished() -> Bool {
        finished.withLock { $0 }
    }

    func finish() {
        finished.withLock { $0 = true }
    }
}

private final class Retained {}

@Suite
struct HandleBoxTests {
    @Test
    func theRetainedObjectOutlivesARunningTask() async throws {
        let handle = SlowTaskHandle()
        let box = HandleBox()
        weak var weakObject: Retained?
        do {
            let object = Retained()
            weakObject = object
            box.store(handle, retaining: object)
        }

        box.cancel()
        try await Task.sleep(for: .milliseconds(100))
        #expect(weakObject != nil, "released while the upstream task may still be polling")

        handle.finish()
        try await waitUntil { weakObject == nil }
        #expect(weakObject == nil)
    }

    @Test
    func aLateHandleKeepsItsObjectUntilItsTaskEnds() async throws {
        let handle = SlowTaskHandle()
        let box = HandleBox()
        box.cancel()
        weak var weakObject: Retained?
        do {
            let object = Retained()
            weakObject = object
            box.store(handle, retaining: object)
        }

        try await Task.sleep(for: .milliseconds(100))
        #expect(weakObject != nil)

        handle.finish()
        try await waitUntil { weakObject == nil }
        #expect(weakObject == nil)
    }

    /// La séquence d'un filtre refusé dans `RustRoomService` : `store`, `cancel` par la tâche,
    /// puis `cancel` par la terminaison du flux. Le second appel ne libère rien plus tôt.
    @Test
    func aSecondCancelKeepsTheObjectUntilTheTaskEnds() async throws {
        let handle = SlowTaskHandle()
        let box = HandleBox()
        weak var weakObject: Retained?
        do {
            let object = Retained()
            weakObject = object
            box.store(handle, retaining: object)
        }

        box.cancel()
        box.cancel()
        try await Task.sleep(for: .milliseconds(100))
        #expect(weakObject != nil)

        handle.finish()
        try await waitUntil { weakObject == nil }
        #expect(weakObject == nil)
    }

    @Test
    func aFinishedTaskReleasesAtOnce() {
        let handle = SlowTaskHandle()
        handle.finish()
        let box = HandleBox()
        weak var weakObject: Retained?
        do {
            let object = Retained()
            weakObject = object
            box.store(handle, retaining: object)
        }

        box.cancel()
        #expect(weakObject == nil)
    }

    @Test
    func aTaskThatNeverEndsLeaksRatherThanReleases() async throws {
        let handle = SlowTaskHandle()
        weak var weakObject: Retained?
        do {
            let object = Retained()
            weakObject = object
            HandleBox.release(object, after: handle, timeout: .milliseconds(50))
        }

        try await Task.sleep(for: .milliseconds(300))
        #expect(weakObject != nil)
    }

    /// Sonde toutes les 10 ms, au plus 2 s.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
