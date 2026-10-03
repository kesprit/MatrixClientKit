import Testing
import Foundation
import MatrixClientKit

// Sérialisée pour la même raison que ``IntegrationTests`` : une seule entrée Keychain de session
// par processus. Les deux suites parentes ne sont pas sérialisées **entre elles** — il faudrait un
// parent commun, donc toucher à l'existant — : lancer `--filter HarnessTests` et
// `--filter IntegrationTests` séparément (voir `Tests/IntegrationHarness/README.md`).
@Suite(.enabled(if: HarnessConfiguration.isAvailable), .serialized)
struct HarnessTests {}

/// Configuration du harnais Docker local, lue dans les variables exportées par
/// `Scripts/integration-harness.sh env`. Absente, la suite entière est ignorée.
struct HarnessConfiguration {
    /// Synapse à mot de passe (`synapse-password`).
    let passwordHomeserver: URL
    /// Synapse dont le jeton d'accès expire au bout de 20 s (`synapse-expiring`) : soft logout.
    let expiringHomeserver: URL
    /// Synapse délégué à MAS (`synapse-oauth`), si le harnais l'exporte.
    let oauthHomeserver: URL?
    /// Matrix Authentication Service, si le harnais l'exporte.
    let mas: URL?
    let user: String
    let password: String
    /// E-mail lié au compte `user` sur `passwordHomeserver` uniquement.
    let email: String
    let oauthUser: String?
    let oauthPassword: String?

    static var current: HarnessConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        guard
            let passwordHomeserver = environment["MCK_HARNESS_PASSWORD_HOMESERVER"].flatMap(URL.init(string:)),
            let expiringHomeserver = environment["MCK_HARNESS_EXPIRING_HOMESERVER"].flatMap(URL.init(string:)),
            let user = environment["MCK_HARNESS_USER"],
            let password = environment["MCK_HARNESS_PASSWORD"],
            let email = environment["MCK_HARNESS_EMAIL"]
        else { return nil }

        return HarnessConfiguration(
            passwordHomeserver: passwordHomeserver,
            expiringHomeserver: expiringHomeserver,
            oauthHomeserver: environment["MCK_HARNESS_OAUTH_HOMESERVER"].flatMap(URL.init(string:)),
            mas: environment["MCK_HARNESS_MAS"].flatMap(URL.init(string:)),
            user: user,
            password: password,
            email: email,
            oauthUser: environment["MCK_HARNESS_OAUTH_USER"],
            oauthPassword: environment["MCK_HARNESS_OAUTH_PASSWORD"]
        )
    }

    static var isAvailable: Bool { current != nil }
}

/// Répertoire de travail neuf, à supprimer par ``removeDirectory(_:)``.
func newHarnessDirectory() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "mck-harness-\(UUID())")
}

/// Noms des répertoires de store sous `<directory>/MatrixClientKit`, vide si la racine n'existe pas.
func storeDirectories(in directory: URL) -> [String] {
    let root = directory.appending(path: "MatrixClientKit").path
    return (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
}

/// Comme ``firstValue(of:where:)``, borné à `timeout` : rend `nil` si rien n'arrive à temps. Sert
/// aux attentes plus courtes que la `.timeLimit` du cas, pour échouer avec un message précis.
func firstValue<Element: Sendable>(
    of stream: AsyncStream<Element>,
    within timeout: Duration,
    where predicate: @escaping @Sendable (Element) -> Bool
) async -> Element? {
    await withTaskGroup(of: Element?.self) { group in
        group.addTask {
            for await value in stream where predicate(value) {
                return value
            }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let first = await group.next() ?? nil
        // L'itération d'un `AsyncStream` se termine à l'annulation : le groupe ne retient rien.
        group.cancelAll()
        return first
    }
}

/// Crée, par l'API client brute et avec un jeton propre au compte, un salon chiffré dont
/// l'utilisateur est l'unique membre, puis déconnecte ce jeton.
///
/// Le jeton admin exporté par le harnais ne convient pas sur `synapse-expiring` : il est mort
/// 20 s après `env`. Et la créatrice étant membre d'office, aucune invitation ni adhésion n'est
/// nécessaire — l'API publique n'expose pas d'adhésion à un salon.
func createEncryptedRoom(on homeserver: URL, user: String, password: String) async throws -> RoomID {
    var login = URLRequest(url: homeserver.appending(path: "_matrix/client/v3/login"))
    login.httpMethod = "POST"
    login.setValue("application/json", forHTTPHeaderField: "Content-Type")
    login.httpBody = try JSONSerialization.data(withJSONObject: [
        "type": "m.login.password",
        "identifier": ["type": "m.id.user", "user": user],
        "password": password,
        "initial_device_display_name": "MatrixClientKit Harness (raw)",
    ])
    let (loginData, _) = try await URLSession.shared.data(for: login)
    let loginObject = try JSONSerialization.jsonObject(with: loginData) as? [String: Any]
    let token = try #require(loginObject?["access_token"] as? String)

    var create = URLRequest(url: homeserver.appending(path: "_matrix/client/v3/createRoom"))
    create.httpMethod = "POST"
    create.setValue("application/json", forHTTPHeaderField: "Content-Type")
    create.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    create.httpBody = try JSONSerialization.data(withJSONObject: [
        "preset": "private_chat",
        "name": "MatrixClientKit Harness \(UUID())",
        "initial_state": [
            [
                "type": "m.room.encryption",
                "state_key": "",
                "content": ["algorithm": "m.megolm.v1.aes-sha2"],
            ]
        ],
    ])
    let (createData, _) = try await URLSession.shared.data(for: create)
    let createObject = try JSONSerialization.jsonObject(with: createData) as? [String: Any]

    var logout = URLRequest(url: homeserver.appending(path: "_matrix/client/v3/logout"))
    logout.httpMethod = "POST"
    logout.setValue("application/json", forHTTPHeaderField: "Content-Type")
    logout.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    logout.httpBody = Data("{}".utf8)
    _ = try? await URLSession.shared.data(for: logout)

    let rawRoomID = try #require(createObject?["room_id"] as? String)
    return try #require(RoomID(rawValue: rawRoomID))
}
