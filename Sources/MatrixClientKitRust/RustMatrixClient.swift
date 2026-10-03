import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Client à store en mémoire, sans session, pour la découverte et `loginDetails()` (spec 0.4,
/// §5.3). Jamais utilisé pour se connecter : l'amont pose une session une seule fois par client.
actor ProbeClient {
    private let target: ClientTarget
    private var client: Client?

    init(target: ClientTarget, client: Client? = nil) {
        self.target = target
        self.client = client
    }

    func get() async throws -> Client {
        if let client { return client }
        let builder: ClientBuilder
        switch target {
        case let .homeserver(url): builder = ClientBuilder().homeserverUrl(url: url.absoluteString)
        case let .serverName(name): builder = ClientBuilder().serverNameOrHomeserverUrl(serverNameOrUrl: name)
        }
        do {
            let built =
                try await builder
                .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
                .inMemoryStore()
                .build()
            client = built
            return built
        } catch {
            throw ErrorMapper.map(error)
        }
    }
}

/// Implémentation de ``MatrixClient`` adossée au SDK Rust.
public final class RustMatrixClient: MatrixClientKitCore.MatrixClient {
    public let homeserver: URL

    private let restorer: SessionRestorer
    private let probe: ProbeClient

    public init(homeserver: URL, storage: MatrixStorage) {
        self.homeserver = homeserver
        self.restorer = SessionRestorer(storage: storage)
        self.probe = ProbeClient(target: .homeserver(homeserver))
    }

    /// Couture de test : un restorer à politique de verrou choisie, pour reproduire un client 0.2
    /// dans la suite d'intégration. Portée `package` pour l'exécutable `IntegrationLegacySeeder`.
    package init(homeserver: URL, restorer: SessionRestorer) {
        self.homeserver = homeserver
        self.restorer = restorer
        self.probe = ProbeClient(target: .homeserver(homeserver))
    }

    private init(homeserver: URL, restorer: SessionRestorer, probe: ProbeClient) {
        self.homeserver = homeserver
        self.restorer = restorer
        self.probe = probe
    }

    /// Résout un nom de serveur, une URL ou un user ID en homeserver (spec 0.4, §4.1).
    public static func discover(server: String, storage: MatrixStorage) async throws -> RustMatrixClient {
        let probe = ProbeClient(target: .serverName(try ServerInput.normalize(server)))
        let client = try await probe.get()
        guard let homeserver = URL(string: client.homeserver()) else {
            throw MatrixError.unexpected(
                message: "The server returned an invalid homeserver URL.", details: client.homeserver())
        }
        return RustMatrixClient(homeserver: homeserver, restorer: SessionRestorer(storage: storage), probe: probe)
    }

    public func loginDetails() async throws -> LoginDetails {
        let client = try await probe.get()
        return LoginDetailsMapper.map(await client.homeserverLoginDetails(), fallback: homeserver)
    }

    /// Starts an OAuth sign-in against the homeserver; see ``OAuthLoginFlow``.
    public func beginOAuthLogin(
        _ configuration: MatrixClientKitCore.OAuthConfiguration,
        prompt: MatrixClientKitCore.OAuthPrompt?,
        loginHint: String?
    ) async throws -> any OAuthLoginFlow {
        let attempt = try await LoginAttempt.begin(restorer: restorer, target: .homeserver(homeserver), reusing: nil)
        return try await RustOAuthLoginFlow.begin(
            attempt: attempt, configuration: configuration, prompt: prompt,
            loginHint: loginHint, deviceID: nil, expecting: nil
        )
    }

    /// Signs this device in by showing a QR code that a device already signed in to the account
    /// scans; see ``QRCodeLogin``.
    public func loginWithQRCode(_ configuration: MatrixClientKitCore.OAuthConfiguration) -> any QRCodeLogin {
        RustQRCodeLogin(restorer: restorer, configuration: configuration, mode: .display(.homeserver(homeserver)))
    }

    /// Signs this device in by scanning the QR code shown by a device already signed in to the
    /// account. The code says which homeserver to use.
    public static func loginWithQRCode(
        scanned: Data,
        configuration: MatrixClientKitCore.OAuthConfiguration,
        storage: MatrixStorage
    ) -> any QRCodeLogin {
        RustQRCodeLogin(
            restorer: SessionRestorer(storage: storage), configuration: configuration, mode: .scanned(scanned))
    }

    /// Restaure la session persistée sans connaître l'adresse du homeserver, enregistrée avec elle.
    public static func restoreSession(storage: MatrixStorage) async throws -> (any MatrixClientKitCore.MatrixSession)? {
        try await SessionRestorer(storage: storage).restore()
    }

    /// Ouvre une session sur un store neuf (spec 0.4, §5.2).
    public func login(_ credentials: Credentials) async throws -> any MatrixClientKitCore.MatrixSession {
        let attempt = try await LoginAttempt.begin(restorer: restorer, target: .homeserver(homeserver), reusing: nil)
        do {
            try await attempt.authenticate(credentials, deviceID: nil, expecting: nil)
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
