import MatrixRustSDK
import MatrixClientKitCore

/// Traduit les états, la progression et les erreurs de chiffrement amont vers le domaine.
enum EncryptionMapper {

    static func status(from state: MatrixRustSDK.VerificationState) -> VerificationStatus {
        switch state {
        case .unknown: .unknown
        case .verified: .verified
        case .unverified: .unverified
        }
    }

    static func backupState(from state: MatrixRustSDK.BackupState) -> MatrixClientKitCore.BackupState {
        switch state {
        case .unknown: .unknown
        case .creating: .creating
        case .enabling: .enabling
        case .resuming: .resuming
        case .enabled: .enabled
        case .downloading: .downloading
        case .disabling: .disabling
        }
    }

    static func recoveryState(from state: MatrixRustSDK.RecoveryState) -> MatrixClientKitCore.RecoveryState {
        switch state {
        case .unknown: .unknown
        case .enabled: .enabled
        case .disabled: .disabled
        case .incomplete: .incomplete
        }
    }

    /// - Note: `.done` amont porte la clé ; elle est volontairement abandonnée ici. La clé n'est
    ///   livrée que par la valeur de retour d'`enableRecovery`, pour qu'un secret n'ait qu'un canal.
    static func progress(from progress: EnableRecoveryProgress) -> RecoveryProgress {
        switch progress {
        case .starting: .starting
        case .creatingBackup: .creatingBackup
        case .creatingRecoveryKey: .creatingRecoveryKey
        case let .backingUp(backedUpCount, totalCount):
            .backingUp(uploaded: Int(clamping: backedUpCount), total: Int(clamping: totalCount))
        case .roomKeyUploadError: .roomKeyUploadError
        case .done: .done
        }
    }

    /// Fragment du message amont d'une récupération jamais configurée
    /// (`SecretStorageError::MissingKeyInfo`), qui partage la variante `SecretStorage` avec une
    /// clé refusée.
    static let missingKeyInfoMarker = "could not have been found"

    /// Traduit une erreur d'opération de chiffrement.
    ///
    /// - Parameter duringRecover: vrai pour `recover(with:)`. Une erreur de stockage de secrets
    ///   y signifie que la clé saisie ne déchiffre pas les secrets — l'amont ne le dit qu'à
    ///   travers le message (échec MAC ou décodage de la clé), sans variante dédiée. Épinglé
    ///   contre un vrai serveur par la suite d'intégration.
    static func error(from error: any Error, duringRecover: Bool = false) -> MatrixError {
        guard let error = error as? RecoveryError else {
            return ErrorMapper.map(error)
        }

        switch error {
        case .BackupExistsOnServer:
            return .unexpected(message: "A key backup already exists on the server.", details: nil)
        case let .Client(source):
            return ErrorMapper.map(source)
        case let .SecretStorage(errorMessage):
            if duringRecover, !errorMessage.contains(missingKeyInfoMarker) {
                return .encryption(.invalidRecoveryKey)
            }
            return .unexpected(message: "Secret storage failed.", details: errorMessage)
        case let .Import(errorMessage):
            return .unexpected(message: "Importing a secret failed.", details: errorMessage)
        }
    }
}
