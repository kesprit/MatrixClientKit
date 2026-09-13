import Foundation

/// Identifiants de connexion. La v0.1 couvre le mot de passe ; OAuth arrive en v0.4.
public enum Credentials: Sendable, Hashable {
    case password(username: String, password: String, deviceName: String?)
}

/// Client non authentifié : point d'entrée avant l'ouverture d'une session.
public protocol MatrixClient: Sendable {
    /// Adresse du homeserver auquel ce client est rattaché.
    var homeserver: URL { get }

    /// Ouvre une session et persiste les informations nécessaires à sa restauration.
    func login(_ credentials: Credentials) async throws -> any MatrixSession

    /// Restaure une session précédemment persistée, ou renvoie `nil` s'il n'y en a pas.
    func restoreSession() async throws -> (any MatrixSession)?
}
