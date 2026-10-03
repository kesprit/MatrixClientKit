import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``MatrixClient`` adossée au SDK Rust.
public final class RustMatrixClient: MatrixClientKitCore.MatrixClient {
    public let homeserver: URL

    private let restorer: SessionRestorer

    public init(homeserver: URL, storage: MatrixStorage) {
        self.homeserver = homeserver
        self.restorer = SessionRestorer(storage: storage)
    }

    /// Couture de test : un restorer à politique de verrou choisie, pour reproduire un client 0.2
    /// dans la suite d'intégration. Portée `package` pour l'exécutable `IntegrationLegacySeeder`.
    package init(homeserver: URL, restorer: SessionRestorer) {
        self.homeserver = homeserver
        self.restorer = restorer
    }

    /// Restaure la session persistée sans connaître l'adresse du homeserver, enregistrée avec elle.
    public static func restoreSession(storage: MatrixStorage) async throws -> (any MatrixClientKitCore.MatrixSession)? {
        try await SessionRestorer(storage: storage).restore()
    }

    /// Ouvre une session sur un store neuf (spec 0.4, §5.2).
    public func login(_ credentials: Credentials) async throws -> any MatrixClientKitCore.MatrixSession {
        let attempt = try await LoginAttempt.begin(restorer: restorer, target: .homeserver(homeserver), reusing: nil)
        do {
            try await attempt.authenticate(credentials, deviceID: nil)
            return try await attempt.succeed(expecting: nil)
        } catch {
            attempt.fail()
            throw ErrorMapper.mapAuthentication(error)
        }
    }

    public func restoreSession() async throws -> (any MatrixClientKitCore.MatrixSession)? {
        try await restorer.restore()
    }
}
