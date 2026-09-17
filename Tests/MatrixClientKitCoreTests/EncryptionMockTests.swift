import Testing
import Foundation
import MatrixClientKitCore
import MatrixClientKitMocks

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [RecoveryProgress] = []

    func append(_ step: RecoveryProgress) { lock.withLock { steps.append(step) } }
    var all: [RecoveryProgress] { lock.withLock { steps } }
}

@Test func mockEncryptionReplaysProgressThenReturnsTheKey() async throws {
    let encryption = MockEncryptionService()
    encryption.progressSteps = [.starting, .backingUp(uploaded: 1, total: 2), .done]
    encryption.recoveryKey = RecoveryKey(rawValue: "clé")
    let log = ProgressLog()

    let key = try await encryption.enableRecovery { log.append($0) }

    #expect(key.rawValue == "clé")
    #expect(log.all == [.starting, .backingUp(uploaded: 1, total: 2), .done])
    #expect(encryption.enableRecoveryCallCount == 1)
}

@Test func mockEncryptionRecordsRecoveryAttemptsAndCanFail() async {
    let encryption = MockEncryptionService()
    encryption.recoverError = .encryption(.invalidRecoveryKey)

    await #expect(throws: MatrixError.encryption(.invalidRecoveryKey)) {
        try await encryption.recover(with: "mauvaise")
    }
    #expect(encryption.recoverAttempts == ["mauvaise"])
}

@Test func mockEncryptionQueriesReturnTheirInjectedResult() async throws {
    let encryption = MockEncryptionService()
    encryption.isLastDeviceResult = .success(true)
    encryption.backupExistsOnServerResult = .failure(.network(.offline))

    #expect(try await encryption.isLastDevice())
    await #expect(throws: MatrixError.network(.offline)) {
        try await encryption.backupExistsOnServer()
    }
}

@Test func mockEncryptionStreamsDeliverEmittedStates() async {
    let encryption = MockEncryptionService()
    var status = encryption.verificationStatus.makeAsyncIterator()
    var recovery = encryption.recoveryState.makeAsyncIterator()
    var backup = encryption.backupState.makeAsyncIterator()

    encryption.emitVerificationStatus(.unverified)
    encryption.emitRecoveryState(.incomplete)
    encryption.emitBackupState(.downloading)

    #expect(await status.next() == .unverified)
    #expect(await recovery.next() == .incomplete)
    #expect(await backup.next() == .downloading)

    encryption.finish()
    #expect(await status.next() == nil)
}

@Test func mockSessionVerificationRecordsCallsAndFailsOnDemand() async {
    let verification = MockSessionVerification()
    verification.setError(.network(.timeout), for: .approve)

    try? await verification.requestVerification()
    await #expect(throws: MatrixError.network(.timeout)) {
        try await verification.approve()
    }

    #expect(verification.calls == [.requestVerification, .approve])
}

@Test func mockSessionVerificationDeliversEmittedStates() async {
    let verification = MockSessionVerification()
    var iterator = verification.state.makeAsyncIterator()

    verification.emit(.ready)
    #expect(await iterator.next() == .ready)

    verification.finish()
    #expect(await iterator.next() == nil)
}
