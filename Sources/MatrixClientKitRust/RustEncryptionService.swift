import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``EncryptionService`` adossée au SDK Rust.
public final class RustEncryptionService: EncryptionService {
    private let encryption: any EncryptionDriving
    public let sessionVerification: any SessionVerification

    init(encryption: any EncryptionDriving, sessionVerification: any SessionVerification) {
        self.encryption = encryption
        self.sessionVerification = sessionVerification
    }

    public var verificationStatus: AsyncStream<VerificationStatus> {
        let encryption = encryption
        return ffiStateStream(
            current: { EncryptionMapper.status(from: encryption.verificationState()) },
            makeListener: { emit in
                VerificationStateObserver { emit(EncryptionMapper.status(from: $0)) }
            },
            subscribe: { encryption.observeVerificationState($0) }
        )
    }

    public var backupState: AsyncStream<MatrixClientKitCore.BackupState> {
        let encryption = encryption
        return ffiStateStream(
            current: { EncryptionMapper.backupState(from: encryption.backupState()) },
            makeListener: { emit in
                BackupStateObserver { emit(EncryptionMapper.backupState(from: $0)) }
            },
            subscribe: { encryption.observeBackupState($0) }
        )
    }

    public var recoveryState: AsyncStream<MatrixClientKitCore.RecoveryState> {
        let encryption = encryption
        return ffiStateStream(
            current: { EncryptionMapper.recoveryState(from: encryption.recoveryState()) },
            makeListener: { emit in
                RecoveryStateObserver { emit(EncryptionMapper.recoveryState(from: $0)) }
            },
            subscribe: { encryption.observeRecoveryState($0) }
        )
    }

    public func isLastDevice() async throws -> Bool {
        do {
            return try await encryption.isLastDevice()
        } catch {
            throw EncryptionMapper.error(from: error)
        }
    }

    public func hasDevicesToVerifyAgainst() async throws -> Bool {
        do {
            return try await encryption.hasDevicesToVerifyAgainst()
        } catch {
            throw EncryptionMapper.error(from: error)
        }
    }

    public func backupExistsOnServer() async throws -> Bool {
        do {
            return try await encryption.backupExistsOnServer()
        } catch {
            throw EncryptionMapper.error(from: error)
        }
    }

    public func enableRecovery(
        waitForBackupUpload: Bool,
        progress: @escaping @Sendable (RecoveryProgress) -> Void
    ) async throws -> RecoveryKey {
        let listener = RecoveryProgressObserver { progress(EncryptionMapper.progress(from: $0)) }
        do {
            // Passphrase non exposée en 0.2 (spec §5.2) : l'ajouter plus tard sera un paramètre à
            // valeur par défaut, sans rupture.
            let key = try await encryption.enableRecovery(
                waitForBackupsToUpload: waitForBackupUpload,
                passphrase: nil,
                progressListener: listener
            )
            return RecoveryKey(rawValue: key)
        } catch {
            throw EncryptionMapper.error(from: error)
        }
    }

    public func recover(with key: String) async throws {
        do {
            try await encryption.recover(recoveryKey: key)
        } catch {
            throw EncryptionMapper.error(from: error, duringRecover: true)
        }
    }

    public func resetRecoveryKey() async throws -> RecoveryKey {
        do {
            return RecoveryKey(rawValue: try await encryption.resetRecoveryKey())
        } catch {
            throw EncryptionMapper.error(from: error)
        }
    }

    public func disableRecovery() async throws {
        do {
            try await encryption.disableRecovery()
        } catch {
            throw EncryptionMapper.error(from: error)
        }
    }

    public func enableBackups() async throws {
        do {
            try await encryption.enableBackups()
        } catch {
            throw EncryptionMapper.error(from: error)
        }
    }
}

// Listeners conformes aux protocoles amont, alimentés par une closure — même modèle que
// `StateObserver` dans `RustSyncController`.

private final class VerificationStateObserver: VerificationStateListener {
    private let handler: @Sendable (MatrixRustSDK.VerificationState) -> Void
    init(handler: @escaping @Sendable (MatrixRustSDK.VerificationState) -> Void) { self.handler = handler }
    func onUpdate(status: MatrixRustSDK.VerificationState) { handler(status) }
}

private final class BackupStateObserver: BackupStateListener {
    private let handler: @Sendable (MatrixRustSDK.BackupState) -> Void
    init(handler: @escaping @Sendable (MatrixRustSDK.BackupState) -> Void) { self.handler = handler }
    func onUpdate(status: MatrixRustSDK.BackupState) { handler(status) }
}

private final class RecoveryStateObserver: RecoveryStateListener {
    private let handler: @Sendable (MatrixRustSDK.RecoveryState) -> Void
    init(handler: @escaping @Sendable (MatrixRustSDK.RecoveryState) -> Void) { self.handler = handler }
    func onUpdate(status: MatrixRustSDK.RecoveryState) { handler(status) }
}

private final class RecoveryProgressObserver: EnableRecoveryProgressListener {
    private let handler: @Sendable (EnableRecoveryProgress) -> Void
    init(handler: @escaping @Sendable (EnableRecoveryProgress) -> Void) { self.handler = handler }
    func onUpdate(status: EnableRecoveryProgress) { handler(status) }
}
