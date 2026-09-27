import MatrixRustSDK
import MatrixClientKitCore

/// Le processus qui ouvre le store : l'application, ou son extension de service de notification.
enum ClientRole: Sendable, Hashable {
    case application
    case notificationExtension
}

/// Choisit le verrou inter-processus du store (spec 0.3, §7).
///
/// Un stockage App Group est partagé par définition entre l'application et son extension : les
/// deux doivent prendre le verrou, sous deux noms distincts, faute de quoi elles écrivent le même
/// store crypto sans se voir. Un stockage local n'est partagé avec personne.
enum CrossProcessLock {
    static func configuration(for storage: MatrixStorage, role: ClientRole) throws -> CrossProcessLockConfig {
        switch (storage.location, role) {
        case (.appGroup, .application):
            return .multiProcess(holderName: "app")
        case (.appGroup, .notificationExtension):
            return .multiProcess(holderName: "nse")
        case (.local, .application):
            return .singleProcess
        case (.local, .notificationExtension):
            // Une extension n'a pas accès au conteneur privé de l'application.
            throw MatrixError.storage(.unavailable)
        }
    }
}
