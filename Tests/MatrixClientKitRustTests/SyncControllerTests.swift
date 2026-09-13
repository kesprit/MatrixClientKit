import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private final class FakeTaskHandle: TaskHandleProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func isFinished() -> Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

private final class FakeSyncService: SyncServiceDriving, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private var observer: (any SyncServiceStateObserver)?

    private func incrementStartCount() { lock.lock(); startCallCount += 1; lock.unlock() }
    private func incrementStopCount() { lock.lock(); stopCallCount += 1; lock.unlock() }

    func start() async { incrementStartCount() }
    func stop() async { incrementStopCount() }

    func observeState(_ listener: any SyncServiceStateObserver) -> any TaskHandleProtocol {
        lock.lock(); observer = listener; lock.unlock()
        return FakeTaskHandle()
    }

    func emit(_ state: SyncServiceState) {
        lock.lock(); let observer = observer; lock.unlock()
        observer?.onUpdate(state: state)
    }
}

@Test func startAndStopAreForwardedToTheService() async {
    let service = FakeSyncService()
    let controller = RustSyncController(service: service)

    await controller.start()
    await controller.stop()

    #expect(service.startCallCount == 1)
    #expect(service.stopCallCount == 1)
}

@Test func upstreamStatesAreMappedToDomainStates() async {
    let service = FakeSyncService()
    let controller = RustSyncController(service: service)
    var iterator = controller.state.makeAsyncIterator()

    service.emit(.running)
    #expect(await iterator.next() == .running)

    service.emit(.offline)
    #expect(await iterator.next() == .offline)
}

@Test func everyUpstreamStateHasAMapping() {
    #expect(SyncStateMapper.map(.idle) == .idle)
    #expect(SyncStateMapper.map(.running) == .running)
    #expect(SyncStateMapper.map(.terminated) == .terminated)
    #expect(SyncStateMapper.map(.error) == .error)
    #expect(SyncStateMapper.map(.offline) == .offline)
}
