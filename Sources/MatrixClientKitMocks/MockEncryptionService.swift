import Foundation
import MatrixClientKitCore

/// A drivable ``EncryptionService``: you decide what each state stream emits and what each call
/// returns or throws.
public final class MockEncryptionService: EncryptionService, @unchecked Sendable {
    private let lock = NSLock()

    private let statusStream: AsyncStream<VerificationStatus>
    private let statusContinuation: AsyncStream<VerificationStatus>.Continuation
    private let backupStream: AsyncStream<BackupState>
    private let backupContinuation: AsyncStream<BackupState>.Continuation
    private let recoveryStream: AsyncStream<RecoveryState>
    private let recoveryContinuation: AsyncStream<RecoveryState>.Continuation

    private var _isLastDeviceResult: Result<Bool, MatrixError> = .success(false)
    private var _hasDevicesToVerifyAgainstResult: Result<Bool, MatrixError> = .success(true)
    private var _backupExistsOnServerResult: Result<Bool, MatrixError> = .success(false)
    private var _recoveryKey = RecoveryKey(rawValue: "EsTc aBcD eFgH iJkL mNoP")
    private var _progressSteps: [RecoveryProgress] = [.starting, .done]
    private var _enableRecoveryError: MatrixError?
    private var _recoverError: MatrixError?
    private var _resetRecoveryKeyError: MatrixError?
    private var _disableRecoveryError: MatrixError?
    private var _enableBackupsError: MatrixError?
    private var _recoverAttempts: [String] = []
    private var _enableRecoveryCallCount = 0
    private var _resetRecoveryKeyCallCount = 0
    private var _disableRecoveryCallCount = 0
    private var _enableBackupsCallCount = 0

    public let sessionVerification: any SessionVerification

    public init(sessionVerification: MockSessionVerification = MockSessionVerification()) {
        self.sessionVerification = sessionVerification
        (statusStream, statusContinuation) = AsyncStream<VerificationStatus>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        (backupStream, backupContinuation) = AsyncStream<BackupState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        (recoveryStream, recoveryContinuation) = AsyncStream<RecoveryState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    // MARK: Streams

    public var verificationStatus: AsyncStream<VerificationStatus> { statusStream }
    public var backupState: AsyncStream<BackupState> { backupStream }
    public var recoveryState: AsyncStream<RecoveryState> { recoveryStream }

    /// Pushes a value to ``verificationStatus``.
    public func emitVerificationStatus(_ status: VerificationStatus) { statusContinuation.yield(status) }
    /// Pushes a value to ``backupState``.
    public func emitBackupState(_ state: BackupState) { backupContinuation.yield(state) }
    /// Pushes a value to ``recoveryState``.
    public func emitRecoveryState(_ state: RecoveryState) { recoveryContinuation.yield(state) }

    /// Ends the three state streams.
    public func finish() {
        statusContinuation.finish()
        backupContinuation.finish()
        recoveryContinuation.finish()
    }

    // MARK: Injection

    /// What ``isLastDevice()`` returns or throws. Defaults to `false`.
    public var isLastDeviceResult: Result<Bool, MatrixError> {
        get { lock.withLock { _isLastDeviceResult } }
        set { lock.withLock { _isLastDeviceResult = newValue } }
    }

    /// What ``hasDevicesToVerifyAgainst()`` returns or throws. Defaults to `true`.
    public var hasDevicesToVerifyAgainstResult: Result<Bool, MatrixError> {
        get { lock.withLock { _hasDevicesToVerifyAgainstResult } }
        set { lock.withLock { _hasDevicesToVerifyAgainstResult = newValue } }
    }

    /// What ``backupExistsOnServer()`` returns or throws. Defaults to `false`.
    public var backupExistsOnServerResult: Result<Bool, MatrixError> {
        get { lock.withLock { _backupExistsOnServerResult } }
        set { lock.withLock { _backupExistsOnServerResult = newValue } }
    }

    /// The key returned by ``enableRecovery(waitForBackupUpload:progress:)`` and
    /// ``resetRecoveryKey()``.
    public var recoveryKey: RecoveryKey {
        get { lock.withLock { _recoveryKey } }
        set { lock.withLock { _recoveryKey = newValue } }
    }

    /// The steps replayed, in order, into the progress closure of
    /// ``enableRecovery(waitForBackupUpload:progress:)``.
    public var progressSteps: [RecoveryProgress] {
        get { lock.withLock { _progressSteps } }
        set { lock.withLock { _progressSteps = newValue } }
    }

    /// Makes ``enableRecovery(waitForBackupUpload:progress:)`` throw.
    public var enableRecoveryError: MatrixError? {
        get { lock.withLock { _enableRecoveryError } }
        set { lock.withLock { _enableRecoveryError = newValue } }
    }

    /// Makes ``recover(with:)`` throw.
    public var recoverError: MatrixError? {
        get { lock.withLock { _recoverError } }
        set { lock.withLock { _recoverError = newValue } }
    }

    /// Makes ``resetRecoveryKey()`` throw.
    public var resetRecoveryKeyError: MatrixError? {
        get { lock.withLock { _resetRecoveryKeyError } }
        set { lock.withLock { _resetRecoveryKeyError = newValue } }
    }

    /// Makes ``disableRecovery()`` throw.
    public var disableRecoveryError: MatrixError? {
        get { lock.withLock { _disableRecoveryError } }
        set { lock.withLock { _disableRecoveryError = newValue } }
    }

    /// Makes ``enableBackups()`` throw.
    public var enableBackupsError: MatrixError? {
        get { lock.withLock { _enableBackupsError } }
        set { lock.withLock { _enableBackupsError = newValue } }
    }

    // MARK: Recording

    /// Every key passed to ``recover(with:)``, in order.
    public var recoverAttempts: [String] { lock.withLock { _recoverAttempts } }
    public var enableRecoveryCallCount: Int { lock.withLock { _enableRecoveryCallCount } }
    public var resetRecoveryKeyCallCount: Int { lock.withLock { _resetRecoveryKeyCallCount } }
    public var disableRecoveryCallCount: Int { lock.withLock { _disableRecoveryCallCount } }
    public var enableBackupsCallCount: Int { lock.withLock { _enableBackupsCallCount } }

    // MARK: EncryptionService

    public func isLastDevice() async throws -> Bool { try isLastDeviceResult.get() }
    public func hasDevicesToVerifyAgainst() async throws -> Bool { try hasDevicesToVerifyAgainstResult.get() }
    public func backupExistsOnServer() async throws -> Bool { try backupExistsOnServerResult.get() }

    public func enableRecovery(
        waitForBackupUpload: Bool,
        progress: @escaping @Sendable (RecoveryProgress) -> Void
    ) async throws -> RecoveryKey {
        let (error, steps, key) = lock.withLock {
            _enableRecoveryCallCount += 1
            return (_enableRecoveryError, _progressSteps, _recoveryKey)
        }
        if let error { throw error }
        steps.forEach(progress)
        return key
    }

    public func recover(with key: String) async throws {
        let error = lock.withLock {
            _recoverAttempts.append(key)
            return _recoverError
        }
        if let error { throw error }
    }

    public func resetRecoveryKey() async throws -> RecoveryKey {
        let (error, key) = lock.withLock {
            _resetRecoveryKeyCallCount += 1
            return (_resetRecoveryKeyError, _recoveryKey)
        }
        if let error { throw error }
        return key
    }

    public func disableRecovery() async throws {
        let error = lock.withLock {
            _disableRecoveryCallCount += 1
            return _disableRecoveryError
        }
        if let error { throw error }
    }

    public func enableBackups() async throws {
        let error = lock.withLock {
            _enableBackupsCallCount += 1
            return _enableBackupsError
        }
        if let error { throw error }
    }
}
