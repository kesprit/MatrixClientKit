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

    var cancelCount: Int { lock.withLock { _cancelCount } }
    var joinCount: Int { lock.withLock { _joinCount } }

    func cancel() { lock.withLock { _cancelCount += 1 } }

    func join() async throws {
        lock.withLock { _joinCount += 1 }
        onJoin?()
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
            await #expect(throws: CancellationError.self) { try await upload.waitUntilSent() }
        }
        #expect(driver.joinCount == 0)
    }

    @Test func waitJoinsUpstream() async throws {
        let driver = FakeJoinHandle()
        try await makeUpload(driver).waitUntilSent()
        #expect(driver.joinCount == 1)
    }

    @Test func cancelDuringJoinThrowsCancellation() async {
        let driver = FakeJoinHandle()
        let upload = makeUpload(driver)
        driver.onJoin = { upload.cancel() }
        await #expect(throws: CancellationError.self) { try await upload.waitUntilSent() }
    }

    @Test func joinErrorIsMapped() async {
        let driver = FakeJoinHandle()
        driver.error = ClientError.MatrixApi(kind: .forbidden, code: "M_FORBIDDEN", msg: "no", details: nil)
        let upload = makeUpload(driver)
        await #expect {
            try await upload.waitUntilSent()
        } throws: { error in
            guard case .permission = error as? MatrixError else { return false }
            return true
        }
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
