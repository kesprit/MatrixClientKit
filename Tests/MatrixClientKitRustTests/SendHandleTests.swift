import Foundation
import Testing
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private final class FakeSendHandleDriver: SendHandleDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var _abortReasons: [String?] = []
    private var _resendCount = 0
    var abortResult = true
    var error: (any Error)?

    var abortReasons: [String?] { lock.withLock { _abortReasons } }
    var resendCount: Int { lock.withLock { _resendCount } }

    func abort(reason: String?) async throws -> Bool {
        try lock.withLock {
            if let error { throw error }
            _abortReasons.append(reason)
        }
        return abortResult
    }

    func tryResend() async throws {
        try lock.withLock {
            if let error { throw error }
            _resendCount += 1
        }
    }
}

@Suite struct SendHandleTests {
    private func makeHandle(_ driver: FakeSendHandleDriver) -> RustSendHandle {
        RustSendHandle(handle: driver, lifetime: .detached())
    }

    @Test func cancelAbortsWithoutReason() async throws {
        let driver = FakeSendHandleDriver()
        try await makeHandle(driver).cancel()
        #expect(driver.abortReasons == [nil])
    }

    @Test(arguments: [true, false])
    func cancelReturnsUpstreamResult(result: Bool) async throws {
        let driver = FakeSendHandleDriver()
        driver.abortResult = result
        #expect(try await makeHandle(driver).cancel() == result)
    }

    @Test func retryResends() async throws {
        let driver = FakeSendHandleDriver()
        try await makeHandle(driver).retry()
        #expect(driver.resendCount == 1)
        #expect(driver.abortReasons.isEmpty)
    }

    @Test func errorsAreMapped() async throws {
        let driver = FakeSendHandleDriver()
        driver.error = ClientError.MatrixApi(kind: .forbidden, code: "M_FORBIDDEN", msg: "no", details: nil)
        let handle = makeHandle(driver)
        await #expect(throws: MatrixError.permission(.forbidden)) { try await handle.cancel() }
        await #expect(throws: MatrixError.permission(.forbidden)) { try await handle.retry() }
    }

    /// §5 : le handle amont est libéré pendant que le client vit encore.
    @Test func upstreamHandleIsReleasedBeforeTheClient() {
        let log = DeinitLog()
        var client: DeinitWitness? = DeinitWitness("client", log: log)
        var handle: RustSendHandle? = RustSendHandle(
            handle: WitnessDriver(witness: DeinitWitness("handle", log: log)),
            lifetime: ClientLifetime(client: client!))
        client = nil
        #expect(log.all.isEmpty)
        handle = nil
        _ = handle
        #expect(log.all == ["handle", "client"])
    }
}

private struct WitnessDriver: SendHandleDriving {
    let witness: DeinitWitness
    func abort(reason: String?) async throws -> Bool { true }
    func tryResend() async throws {}
}
