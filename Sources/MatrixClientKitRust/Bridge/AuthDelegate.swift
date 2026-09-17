import MatrixRustSDK

/// `ClientDelegate` amont : relaie les erreurs d'authentification au cycle de vie de la session.
final class AuthDelegate: ClientDelegate {
    private let lifecycle: SessionLifecycle

    init(lifecycle: SessionLifecycle) {
        self.lifecycle = lifecycle
    }

    func didReceiveAuthError(isSoftLogout: Bool) {
        lifecycle.handleAuthError(isSoftLogout: isSoftLogout)
    }

    func onBackgroundTaskErrorReport(taskName: String, error: BackgroundTaskFailureReason) {
        // Hors périmètre 0.2 : aucun état public ne représente l'échec d'une tâche de fond amont.
    }
}
