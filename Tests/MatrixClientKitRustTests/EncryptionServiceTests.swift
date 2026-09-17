import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private final class FakeTaskHandle: TaskHandleProtocol, @unchecked Sendable {
    func cancel() {}
    func isFinished() -> Bool { false }
}

private final class FakeEncryption: EncryptionDriving, @unchecked Sendable {
    private let lock = NSLock()

    var currentVerificationState: MatrixRustSDK.VerificationState = .unknown
    var currentBackupState: MatrixRustSDK.BackupState = .unknown
    var currentRecoveryState: MatrixRustSDK.RecoveryState = .unknown
    private var verificationListener: (any VerificationStateListener)?

    var progressToReport: [EnableRecoveryProgress] = []
    var keyToReturn = "EsTc clé"
    var recoverError: (any Error)?
    var isLastDeviceError: (any Error)?
    private(set) var receivedPassphrase: String?? = .none
    private(set) var receivedRecoveryKey: String?

    func verificationState() -> MatrixRustSDK.VerificationState { lock.withLock { currentVerificationState } }
    func observeVerificationState(_ listener: any VerificationStateListener) -> any TaskHandleProtocol {
        lock.withLock { verificationListener = listener }
        return FakeTaskHandle()
    }
    func emitVerificationState(_ state: MatrixRustSDK.VerificationState) {
        let listener = lock.withLock { verificationListener }
        listener?.onUpdate(status: state)
    }

    func backupState() -> MatrixRustSDK.BackupState { lock.withLock { currentBackupState } }
    func observeBackupState(_ listener: any BackupStateListener) -> any TaskHandleProtocol { FakeTaskHandle() }
    func recoveryState() -> MatrixRustSDK.RecoveryState { lock.withLock { currentRecoveryState } }
    func observeRecoveryState(_ listener: any RecoveryStateListener) -> any TaskHandleProtocol { FakeTaskHandle() }

    func isLastDevice() async throws -> Bool {
        if let error = lock.withLock({ isLastDeviceError }) { throw error }
        return true
    }
    func hasDevicesToVerifyAgainst() async throws -> Bool { false }
    func backupExistsOnServer() async throws -> Bool { true }

    func enableRecovery(
        waitForBackupsToUpload: Bool,
        passphrase: String?,
        progressListener: any EnableRecoveryProgressListener
    ) async throws -> String {
        let (steps, key) = lock.withLock {
            receivedPassphrase = .some(passphrase)
            return (progressToReport, keyToReturn)
        }
        steps.forEach { progressListener.onUpdate(status: $0) }
        return key
    }

    func recover(recoveryKey: String) async throws {
        let error = lock.withLock {
            receivedRecoveryKey = recoveryKey
            return recoverError
        }
        if let error { throw error }
    }

    func resetRecoveryKey() async throws -> String { "nouvelle clé" }
    func disableRecovery() async throws {}
    func enableBackups() async throws {}
}

private final class StubVerification: SessionVerification {
    var state: AsyncStream<SessionVerificationState> { AsyncStream { $0.finish() } }
    func requestVerification() async throws {}
    func accept() async throws {}
    func startSAS() async throws {}
    func approve() async throws {}
    func decline() async throws {}
    func cancel() async throws {}
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [RecoveryProgress] = []
    func append(_ step: RecoveryProgress) { lock.withLock { steps.append(step) } }
    var all: [RecoveryProgress] { lock.withLock { steps } }
}

private func makeService(_ encryption: FakeEncryption) -> RustEncryptionService {
    RustEncryptionService(encryption: encryption, sessionVerification: StubVerification())
}

@Test func verificationStatusStartsWithTheCurrentStateThenFollowsUpdates() async {
    let encryption = FakeEncryption()
    encryption.currentVerificationState = .unverified
    let service = makeService(encryption)

    var iterator = service.verificationStatus.makeAsyncIterator()
    #expect(await iterator.next() == .unverified)

    encryption.emitVerificationState(.verified)
    #expect(await iterator.next() == .verified)
}

@Test func backupAndRecoveryStreamsStartWithTheCurrentState() async {
    let encryption = FakeEncryption()
    encryption.currentBackupState = .downloading
    encryption.currentRecoveryState = .incomplete
    let service = makeService(encryption)

    var backup = service.backupState.makeAsyncIterator()
    var recovery = service.recoveryState.makeAsyncIterator()
    #expect(await backup.next() == .downloading)
    #expect(await recovery.next() == .incomplete)
}

@Test func enableRecoveryReportsProgressAndWrapsTheKey() async throws {
    let encryption = FakeEncryption()
    encryption.progressToReport = [.starting, .backingUp(backedUpCount: 1, totalCount: 2), .done(recoveryKey: "k")]
    encryption.keyToReturn = "k"
    let log = ProgressLog()

    let key = try await makeService(encryption).enableRecovery { log.append($0) }

    #expect(key.rawValue == "k")
    #expect(log.all == [.starting, .backingUp(uploaded: 1, total: 2), .done])
    // Passphrase non exposée en 0.2 : jamais transmise.
    #expect(encryption.receivedPassphrase == .some(nil))
}

@Test func recoverForwardsTheKeyAndMapsAWrongOne() async {
    let encryption = FakeEncryption()
    encryption.recoverError = RecoveryError.SecretStorage(
        errorMessage: "The MAC check for the secret storage key failed"
    )

    await #expect(throws: MatrixError.encryption(.invalidRecoveryKey)) {
        try await makeService(encryption).recover(with: "EsTc mauvaise")
    }
    #expect(encryption.receivedRecoveryKey == "EsTc mauvaise")
}

@Test func queriesMapUpstreamErrors() async throws {
    let encryption = FakeEncryption()
    let service = makeService(encryption)
    #expect(try await service.isLastDevice())
    #expect(try await service.backupExistsOnServer())
    #expect(try await !service.hasDevicesToVerifyAgainst())

    encryption.isLastDeviceError = ClientError.MatrixApi(kind: .connectionFailed, code: "", msg: "", details: nil)
    await #expect(throws: MatrixError.network(.offline)) {
        try await service.isLastDevice()
    }
}

@Test func resetRecoveryKeyWrapsTheNewKey() async throws {
    let key = try await makeService(FakeEncryption()).resetRecoveryKey()
    #expect(key.rawValue == "nouvelle clé")
}
