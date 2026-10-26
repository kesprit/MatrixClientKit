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
    let controller = RustSyncController(service: service, lifetime: .detached())

    await controller.start()
    await controller.stop()

    #expect(service.startCallCount == 1)
    #expect(service.stopCallCount == 1)
}

@Test func upstreamStatesAreMappedToDomainStates() async {
    let service = FakeSyncService()
    let controller = RustSyncController(service: service, lifetime: .detached())
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

/// Service témoin qui consigne sa libération dans le journal partagé avec le client témoin.
private final class LoggingSyncService: SyncServiceDriving, @unchecked Sendable {
    private let log: ReleaseLog
    init(log: ReleaseLog) { self.log = log }
    deinit { log.append("service") }
    func start() async {}
    func stop() async {}
    func observeState(_ listener: any SyncServiceStateObserver) -> any TaskHandleProtocol { FakeTaskHandle() }
}

private final class LoggingClient: Sendable {
    private let log: ReleaseLog
    init(log: ReleaseLog) { self.log = log }
    deinit { log.append("client") }
}

private final class ReleaseLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func append(_ entry: String) { lock.withLock { entries.append(entry) } }
    var all: [String] { lock.withLock { entries } }
}

// Un contrôleur gardé par l'application après la session libère son service avant le client.
@Test func aControllerKeptAfterTheSessionReleasesItsServiceBeforeTheClient() {
    let log = ReleaseLog()
    var lifetime: ClientLifetime? = ClientLifetime(client: LoggingClient(log: log))
    var controller: RustSyncController? = RustSyncController(service: LoggingSyncService(log: log), lifetime: lifetime!)

    lifetime = nil
    controller = nil

    #expect(log.all == ["service", "client"])
    _ = (lifetime, controller)
}
