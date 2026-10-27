import Foundation
import Testing
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private final class FakeJoinHandle: JoinHandleDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelCount = 0
    private var _joinCount = 0
    var error: (any Error)?
    var onJoin: (@Sendable () -> Void)?
    /// Suspend `join()` le temps voulu, pour que d'autres appels le rejoignent pendant qu'il court.
    var suspension: (@Sendable () async -> Void)?

    var cancelCount: Int { lock.withLock { _cancelCount } }
    var joinCount: Int { lock.withLock { _joinCount } }

    func cancel() { lock.withLock { _cancelCount += 1 } }

    func join() async throws {
        lock.withLock { _joinCount += 1 }
        onJoin?()
        await suspension?()
        if let error { throw error }
    }
}

@Suite struct AttachmentUploadTests {
    private func makeUpload(_ driver: FakeJoinHandle) -> RustAttachmentUpload {
        RustAttachmentUpload(handle: driver, lifetime: .detached())
    }

    @Test func cancelTwiceCallsUpstreamOnce() {
        let driver = FakeJoinHandle()
        let upload = makeUpload(driver)
        upload.cancel()
        upload.cancel()
        #expect(driver.cancelCount == 1)
    }

    @Test func waitAfterCancelThrowsCancellationEveryTime() async {
        let driver = FakeJoinHandle()
        let upload = makeUpload(driver)
        upload.cancel()
        for _ in 0..<2 {
            await #expect(throws: CancellationError.self) { try await upload.waitUntilQueued() }
        }
        #expect(driver.joinCount == 0)
    }

    @Test func waitJoinsUpstream() async throws {
        let driver = FakeJoinHandle()
        try await makeUpload(driver).waitUntilQueued()
        #expect(driver.joinCount == 1)
    }

    @Test func cancelDuringJoinThrowsCancellation() async {
        let driver = FakeJoinHandle()
        let upload = makeUpload(driver)
        driver.onJoin = { upload.cancel() }
        await #expect(throws: CancellationError.self) { try await upload.waitUntilQueued() }
    }

    @Test func joinErrorIsMapped() async {
        let driver = FakeJoinHandle()
        driver.error = ClientError.MatrixApi(kind: .forbidden, code: "M_FORBIDDEN", msg: "no", details: nil)
        let upload = makeUpload(driver)
        await #expect {
            try await upload.waitUntilQueued()
        } throws: { error in
            guard case .permission = error as? MatrixError else { return false }
            return true
        }
    }

    /// `join()` amont attend un `JoinHandle` tokio, qui panique si on l'attend de nouveau une fois
    /// terminé : un seul appel amont, quel que soit le nombre d'attentes.
    @Test func waitingTwiceJoinsUpstreamOnce() async throws {
        let driver = FakeJoinHandle()
        let upload = makeUpload(driver)
        try await upload.waitUntilQueued()
        try await upload.waitUntilQueued()
        #expect(driver.joinCount == 1)
    }

    @Test func concurrentWaitsShareOneUpstreamJoin() async throws {
        let driver = FakeJoinHandle()
        driver.suspension = { for _ in 0..<50 { await Task.yield() } }
        let upload = makeUpload(driver)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<4 { group.addTask { try await upload.waitUntilQueued() } }
            try await group.waitForAll()
        }
        #expect(driver.joinCount == 1)
    }

    @Test func aJoinErrorIsRethrownToEveryWait() async {
        let driver = FakeJoinHandle()
        driver.error = ClientError.MatrixApi(kind: .forbidden, code: "M_FORBIDDEN", msg: "no", details: nil)
        let upload = makeUpload(driver)
        for _ in 0..<2 {
            await #expect {
                try await upload.waitUntilQueued()
            } throws: { error in
                guard case .permission = error as? MatrixError else { return false }
                return true
            }
        }
        #expect(driver.joinCount == 1)
    }

    @Test func releasesHandleBeforeClient() {
        let log = DeinitLog()
        do {
            let client = DeinitWitness("client", log: log)
            let handle = DeinitJoinHandle(witness: DeinitWitness("handle", log: log))
            _ = RustAttachmentUpload(handle: handle, lifetime: ClientLifetime(client: client))
        }
        #expect(log.all == ["handle", "client"])
    }
}

private final class DeinitJoinHandle: JoinHandleDriving, @unchecked Sendable {
    let witness: DeinitWitness
    init(witness: DeinitWitness) { self.witness = witness }
    func cancel() {}
    func join() async throws {}
}
