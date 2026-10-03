import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Persiste les sessions que le SDK Rust rafraîchit de lui-même.
///
/// - Important: le rafraîchissement automatique des jetons est actif par défaut dans le SDK. Sans
///   ce delegate, un jeton rafraîchi ne vit qu'en mémoire : la session enregistrée se périme en
///   silence, et au lancement suivant l'utilisateur se retrouve déconnecté sans qu'aucune erreur
///   n'ait jamais été signalée. C'est la panne la plus difficile à diagnostiquer pour qui construit
///   une application sur ce package, puisque rien n'a échoué visiblement.
///
/// Les deux méthodes sont synchrones : elles sont appelées par le SDK depuis ses propres fils
/// d'exécution, ce qui est la raison pour laquelle ``SessionPersistence`` n'est pas un acteur.
final class SessionDelegate: ClientSessionDelegate {
    private let persistence: SessionPersistence

    init(persistence: SessionPersistence) {
        self.persistence = persistence
    }

    func saveSessionInKeychain(session: Session) {
        // La `Session` amont ignore le store local : la fusion conserve celui de la session
        // persistée, à condition qu'il s'agisse bien du même utilisateur sur le même appareil.
        // Sans elle, le premier rafraîchissement de jeton ferait rouvrir au lancement suivant le
        // chemin legacy — un compte vide, sans aucune erreur.
        //
        // Une lecture en échec (Keychain indisponible, charge utile illisible) n'équivaut pas à
        // « rien de persisté » : écrire alors une session sans storeID ferait rouvrir le chemin
        // legacy au lancement suivant, et le balayage des stores orphelins supprimerait le vrai.
        // On laisse la session précédente en place, comme pour toute autre erreur ici.
        let current: MatrixSessionData?
        do {
            current = try persistence.load()
        } catch {
            return
        }
        let storeID = current.flatMap { current in
            current.userID.rawValue == session.userId && current.deviceID.rawValue == session.deviceId
                ? current.storeID : nil
        }
        // La signature amont ne permet pas de signaler une erreur. Échouer ici laisse la session
        // précédente en place, ce qui est le comportement le moins destructeur : l'ancien jeton
        // reste valide jusqu'à son expiration.
        guard let data = try? SessionMapper.sessionData(from: session, storeID: storeID) else { return }
        try? persistence.save(data)
    }

    func retrieveSessionFromKeychain(userId: String) throws -> Session {
        guard let data = try persistence.load() else {
            throw MatrixError.authentication(.unknownToken(soft: false))
        }

        // Le package ne persiste qu'une session à la fois. Servir celle qui est présente sans
        // vérifier à qui elle appartient reviendrait à remettre au SDK les jetons d'un autre
        // compte.
        guard data.userID.rawValue == userId else {
            throw MatrixError.authentication(.unknownToken(soft: false))
        }

        return SessionMapper.session(from: data)
    }
}
