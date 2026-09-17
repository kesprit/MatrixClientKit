import MatrixRustSDK

/// Sous-ensemble d'`Encryption` amont dont le service de chiffrement a besoin.
///
/// Cette couture existe pour la testabilité : `Encryption` est une classe FFI qu'un test ne peut
/// pas construire, et `EncryptionProtocol` impose une trentaine de méthodes hors périmètre.
protocol EncryptionDriving: Sendable {
    func verificationState() -> MatrixRustSDK.VerificationState
    func observeVerificationState(_ listener: any VerificationStateListener) -> any TaskHandleProtocol
    func backupState() -> MatrixRustSDK.BackupState
    func observeBackupState(_ listener: any BackupStateListener) -> any TaskHandleProtocol
    func recoveryState() -> MatrixRustSDK.RecoveryState
    func observeRecoveryState(_ listener: any RecoveryStateListener) -> any TaskHandleProtocol

    func isLastDevice() async throws -> Bool
    func hasDevicesToVerifyAgainst() async throws -> Bool
    func backupExistsOnServer() async throws -> Bool

    func enableRecovery(
        waitForBackupsToUpload: Bool,
        passphrase: String?,
        progressListener: any EnableRecoveryProgressListener
    ) async throws -> String
    func recover(recoveryKey: String) async throws
    func resetRecoveryKey() async throws -> String
    func disableRecovery() async throws
    func enableBackups() async throws
}

extension Encryption: EncryptionDriving {
    func observeVerificationState(_ listener: any VerificationStateListener) -> any TaskHandleProtocol {
        verificationStateListener(listener: listener)
    }

    func observeBackupState(_ listener: any BackupStateListener) -> any TaskHandleProtocol {
        backupStateListener(listener: listener)
    }

    func observeRecoveryState(_ listener: any RecoveryStateListener) -> any TaskHandleProtocol {
        recoveryStateListener(listener: listener)
    }
}
