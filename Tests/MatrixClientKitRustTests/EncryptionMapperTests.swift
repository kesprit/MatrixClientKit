import Testing
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

@Test func verificationStatesAreMapped() {
    #expect(EncryptionMapper.status(from: .unknown) == .unknown)
    #expect(EncryptionMapper.status(from: .verified) == .verified)
    #expect(EncryptionMapper.status(from: .unverified) == .unverified)
}

@Test func backupStatesAreMapped() {
    let pairs: [(MatrixRustSDK.BackupState, MatrixClientKitCore.BackupState)] = [
        (.unknown, .unknown), (.creating, .creating), (.enabling, .enabling), (.resuming, .resuming),
        (.enabled, .enabled), (.downloading, .downloading), (.disabling, .disabling),
    ]
    for (upstream, expected) in pairs {
        #expect(EncryptionMapper.backupState(from: upstream) == expected)
    }
}

@Test func recoveryStatesAreMapped() {
    #expect(EncryptionMapper.recoveryState(from: .unknown) == .unknown)
    #expect(EncryptionMapper.recoveryState(from: .enabled) == .enabled)
    #expect(EncryptionMapper.recoveryState(from: .disabled) == .disabled)
    #expect(EncryptionMapper.recoveryState(from: .incomplete) == .incomplete)
}

@Test func recoveryProgressIsMappedWithoutTheKey() {
    #expect(EncryptionMapper.progress(from: .starting) == .starting)
    #expect(EncryptionMapper.progress(from: .creatingBackup) == .creatingBackup)
    #expect(EncryptionMapper.progress(from: .creatingRecoveryKey) == .creatingRecoveryKey)
    #expect(
        EncryptionMapper.progress(from: .backingUp(backedUpCount: 3, totalCount: 10))
            == .backingUp(uploaded: 3, total: 10))
    #expect(EncryptionMapper.progress(from: .roomKeyUploadError) == .roomKeyUploadError)
    // La clé ne transite que par la valeur de retour : un seul canal pour un secret.
    #expect(EncryptionMapper.progress(from: .done(recoveryKey: "secret")) == .done)
}

@Test func aSecretStorageFailureDuringRecoveryIsAWrongKey() {
    let error = RecoveryError.SecretStorage(errorMessage: "The MAC check for the secret storage key failed")
    #expect(EncryptionMapper.error(from: error, duringRecover: true) == .encryption(.invalidRecoveryKey))
}

@Test func recoveryThatWasNeverSetUpIsNotReportedAsAWrongKey() {
    let error = RecoveryError.SecretStorage(
        errorMessage: "The info about the secret key could not have been found in the account data of the user"
    )
    guard case .unexpected = EncryptionMapper.error(from: error, duringRecover: true) else {
        Issue.record("une récupération non configurée ne doit pas passer pour une mauvaise clé")
        return
    }
}

@Test func aSecretStorageFailureOutsideRecoveryIsUnexpected() {
    let error = RecoveryError.SecretStorage(errorMessage: "The MAC check for the secret storage key failed")
    guard case .unexpected = EncryptionMapper.error(from: error) else {
        Issue.record("hors recover(with:), aucune clé n'a été saisie")
        return
    }
}

@Test func otherRecoveryErrorsAreMapped() {
    guard case .unexpected = EncryptionMapper.error(from: RecoveryError.BackupExistsOnServer) else {
        Issue.record("BackupExistsOnServer se lit dans l'état, l'erreur reste .unexpected")
        return
    }
    guard case .unexpected = EncryptionMapper.error(from: RecoveryError.Import(errorMessage: "x")) else {
        Issue.record("Import doit rester .unexpected")
        return
    }

    let client = RecoveryError.Client(
        source: .MatrixApi(kind: .connectionFailed, code: "", msg: "", details: nil)
    )
    #expect(EncryptionMapper.error(from: client) == .network(.offline))
}

@Test func nonRecoveryErrorsGoThroughTheGeneralMapper() {
    let error = ClientError.MatrixApi(kind: .connectionTimeout, code: "", msg: "", details: nil)
    #expect(EncryptionMapper.error(from: error) == .network(.timeout))
}
