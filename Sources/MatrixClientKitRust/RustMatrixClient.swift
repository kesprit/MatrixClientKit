import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``MatrixClient`` adossée au SDK Rust.
public final class RustMatrixClient: MatrixClientKitCore.MatrixClient {
    public let homeserver: URL

    private let storage: MatrixStorage
    private let persistence: SessionPersistence

    public init(homeserver: URL, storage: MatrixStorage) {
        self.homeserver = homeserver
        self.storage = storage
        self.persistence = SessionPersistence(store: KeychainSecureStore(storage: storage))
    }

    public func login(_ credentials: Credentials) async throws -> any MatrixClientKitCore.MatrixSession {
        let client = try await makeClient()

        do {
            switch credentials {
            case let .password(username, password, deviceName):
                try await client.login(
                    username: username,
                    password: password,
                    initialDeviceName: deviceName,
                    deviceId: nil
                )
            }

            let session = try client.session()
            try await persistence.save(SessionMapper.sessionData(from: session))
            return try await RustMatrixSession.make(client: client, persistence: persistence)
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    public func restoreSession() async throws -> (any MatrixClientKitCore.MatrixSession)? {
        guard let data = try await persistence.load() else { return nil }

        let client = try await makeClient()
        do {
            try await client.restoreSession(session: SessionMapper.session(from: data))
            return try await RustMatrixSession.make(client: client, persistence: persistence)
        } catch {
            let mapped = ErrorMapper.map(error)

            // Une authentification refusée signifie que la session persistée est morte : la
            // conserver ferait échouer chaque lancement à l'identique, sans qu'aucune API
            // publique ne permette de l'effacer avant une nouvelle connexion réussie. Une panne
            // réseau, de stockage ou serveur, elle, ne dit rien sur la validité de la session —
            // l'effacer déconnecterait l'utilisateur à chaque démarrage hors ligne.
            if case .authentication = mapped {
                try? await persistence.clear()
            }

            throw mapped
        }
    }

    private func makeClient() async throws -> Client {
        do {
            let paths = try StoragePaths(storage: storage)
            try paths.createDirectoriesIfNeeded()

            return try await ClientBuilder()
                .homeserverUrl(url: homeserver.absoluteString)
                .sessionPaths(
                    dataPath: paths.dataDirectory.path,
                    cachePath: paths.cacheDirectory.path
                )
                .build()
        } catch {
            throw ErrorMapper.map(error)
        }
    }
}
