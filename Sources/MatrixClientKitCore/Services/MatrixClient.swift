import Foundation

/// Identifiants de connexion. La v0.1 couvre le mot de passe ; OAuth arrive en v0.4.
public enum Credentials: Sendable, Hashable {
    /// Connexion par nom d'utilisateur et mot de passe, avec un nom d'appareil optionnel.
    case password(username: String, password: String, deviceName: String?)
}

extension Credentials: CustomStringConvertible, CustomDebugStringConvertible {
    /// Description expurgée : n'expose jamais le mot de passe.
    public var description: String {
        switch self {
        case let .password(username, _, deviceName):
            let device = deviceName ?? "nil"
            return "Credentials.password(username: \(username), password: <redacted>, deviceName: \(device))"
        }
    }

    public var debugDescription: String { description }
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
