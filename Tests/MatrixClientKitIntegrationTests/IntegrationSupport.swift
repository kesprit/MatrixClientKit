import Testing
import Foundation
import MatrixClientKit

/// Configuration lue dans l'environnement. Absente, la suite entière est ignorée.
struct IntegrationConfiguration {
    let homeserver: URL
    let username: String
    let password: String
    /// Clé de récupération du compte de test, configurée une fois (par exemple avec Element).
    let recoveryKey: String?
    /// Compte **jamais utilisé**, pour vérifier l'amorçage du cross-signing. Utile une seule fois.
    let freshUsername: String?
    let freshPassword: String?

    static var current: IntegrationConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        guard
            let homeserver = environment["MATRIX_TEST_HOMESERVER"].flatMap(URL.init(string:)),
            let username = environment["MATRIX_TEST_USERNAME"],
            let password = environment["MATRIX_TEST_PASSWORD"]
        else { return nil }

        return IntegrationConfiguration(
            homeserver: homeserver,
            username: username,
            password: password,
            recoveryKey: environment["MATRIX_TEST_RECOVERY_KEY"],
            freshUsername: environment["MATRIX_TEST_FRESH_USERNAME"],
            freshPassword: environment["MATRIX_TEST_FRESH_PASSWORD"]
        )
    }

    static var isAvailable: Bool { current != nil }
    static var hasRecoveryKey: Bool { current?.recoveryKey != nil }
    static var hasFreshAccount: Bool { current?.freshUsername != nil && current?.freshPassword != nil }
}

/// Client d'intégration et répertoire qui l'héberge.
///
/// Le répertoire est rendu à l'appelant : sans cela, chaque exécution laisse sous le répertoire
/// temporaire un store SQLite contenant une vraie session — jetons compris.
struct IntegrationClient {
    let client: any MatrixClient
    let directory: URL
}

func makeClient(_ configuration: IntegrationConfiguration) -> IntegrationClient {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mck-integration-\(UUID().uuidString)", isDirectory: true)
    return IntegrationClient(
        client: Matrix.client(homeserver: configuration.homeserver, storage: .local(directory: directory)),
        directory: directory
    )
}

/// Exécute un nettoyage même lorsque la tâche de test a été annulée — par exemple par
/// `.timeLimit` lorsqu'un flux attendu ne produit jamais la valeur cherchée. Une tâche détachée
/// n'hérite pas de l'annulation de son appelant, donc `session.logout()` a une vraie chance
/// d'atteindre le serveur au lieu d'échouer immédiatement sur un contexte déjà annulé.
func cleaningUp(_ body: @escaping @Sendable () async -> Void) async {
    await Task.detached(operation: body).value
}

/// Supprime le répertoire de travail d'une exécution. L'échec est ignoré : le nettoyage ne doit
/// jamais masquer le résultat du test qu'il suit.
func removeDirectory(_ directory: URL) {
    try? FileManager.default.removeItem(at: directory)
}

/// Attend la première valeur d'un flux qui satisfait `predicate`. La borne `.timeLimit` du test
/// fait échouer une attente qui n'aboutit jamais.
func firstValue<Element: Sendable>(
    of stream: AsyncStream<Element>,
    where predicate: (Element) -> Bool
) async -> Element? {
    for await value in stream where predicate(value) {
        return value
    }
    return nil
}

/// Se connecte dans un répertoire neuf et attend que la sync tourne.
func signIn(
    _ configuration: IntegrationConfiguration,
    username: String? = nil,
    password: String? = nil,
    deviceName: String
) async throws -> (session: any MatrixSession, directory: URL) {
    let integration = makeClient(configuration)
    let session = try await integration.client.login(
        .password(
            username: username ?? configuration.username,
            password: password ?? configuration.password,
            deviceName: deviceName
        )
    )

    // Abonnement posé avant `start()` : le flux de sync ne rejoue pas l'état courant.
    let states = session.sync.state
    await session.sync.start()
    _ = await firstValue(of: states) { $0 == .running }

    return (session, integration.directory)
}

/// Obtient un jeton d'accès par une connexion HTTP brute, hors SDK — un appareil de plus sur le
/// compte, qui disparaît avec `logOutEverywhere`.
func rawAccessToken(_ configuration: IntegrationConfiguration) async throws -> String {
    var request = URLRequest(url: configuration.homeserver.appending(path: "_matrix/client/v3/login"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
        "type": "m.login.password",
        "identifier": ["type": "m.id.user", "user": configuration.username],
        "password": configuration.password,
        "initial_device_display_name": "MatrixClientKit Integration (raw)",
    ])

    let (data, _) = try await URLSession.shared.data(for: request)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return try #require(object?["access_token"] as? String)
}

/// Révoque toutes les sessions du compte, comme « se déconnecter de tous les appareils » depuis un
/// autre client.
func logOutEverywhere(_ configuration: IntegrationConfiguration, accessToken: String) async throws {
    var request = URLRequest(url: configuration.homeserver.appending(path: "_matrix/client/v3/logout/all"))
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data("{}".utf8)

    let (_, response) = try await URLSession.shared.data(for: request)
    #expect((response as? HTTPURLResponse)?.statusCode == 200)
}

/// Fichiers SQLite présents sous un répertoire de stockage.
func sqliteFiles(in directory: URL) -> [URL] {
    let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
    let urls = enumerator?.allObjects.compactMap { $0 as? URL } ?? []
    return urls.filter { $0.lastPathComponent.contains("sqlite") }
}
