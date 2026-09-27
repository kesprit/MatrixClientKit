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
    /// Salon partagé par les deux comptes (`MATRIX_TEST_ROOM_ID`).
    let roomID: RoomID?
    /// Second compte, membre de `roomID`, qui envoie le message que l'extension du compte
    /// principal doit résoudre.
    let senderUsername: String?
    let senderPassword: String?

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
            freshPassword: environment["MATRIX_TEST_FRESH_PASSWORD"],
            roomID: environment["MATRIX_TEST_ROOM_ID"].flatMap(RoomID.init(rawValue:)),
            senderUsername: environment["MATRIX_TEST_SENDER_USERNAME"],
            senderPassword: environment["MATRIX_TEST_SENDER_PASSWORD"]
        )
    }

    static var isAvailable: Bool { current != nil }
    static var hasRecoveryKey: Bool { current?.recoveryKey != nil }
    static var hasFreshAccount: Bool { current?.freshUsername != nil && current?.freshPassword != nil }
    static var hasRoom: Bool { current?.roomID != nil }
    static var hasSenderAccount: Bool {
        hasRoom && current?.senderUsername != nil && current?.senderPassword != nil
    }
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

/// Stockage App Group propre à une exécution. Sur macOS hors bac à sable, `FileManager`
/// synthétise le conteneur sous `~/Library/Group Containers/` sans entitlement.
func appGroupStorage() -> MatrixStorage {
    .appGroup("group.com.matrixclientkit.integration.\(UUID().uuidString)")
}

/// Supprime le conteneur synthétisé d'un stockage App Group. L'échec est ignoré, comme pour
/// ``removeDirectory(_:)``.
func removeAppGroup(_ storage: MatrixStorage) {
    guard case let .appGroup(identifier) = storage.location,
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    else { return }
    try? FileManager.default.removeItem(at: container)
}

/// Déconnecte un appareil ouvert par ``rawAccessToken(_:)``.
func rawLogout(_ configuration: IntegrationConfiguration, accessToken: String) async throws {
    var request = URLRequest(url: configuration.homeserver.appending(path: "_matrix/client/v3/logout"))
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data("{}".utf8)
    _ = try await URLSession.shared.data(for: request)
}

/// Les `pushkey` des pushers du compte, lus par l'API client, hors SDK.
func pushers(_ configuration: IntegrationConfiguration, accessToken: String) async throws -> [String] {
    var request = URLRequest(url: configuration.homeserver.appending(path: "_matrix/client/v3/pushers"))
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    let (data, _) = try await URLSession.shared.data(for: request)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let list = object?["pushers"] as? [[String: Any]] ?? []
    return list.compactMap { $0["pushkey"] as? String }
}

/// Se connecte sur un stockage donné et attend que la sync tourne.
func signIn(
    _ configuration: IntegrationConfiguration,
    storage: MatrixStorage,
    username: String? = nil,
    password: String? = nil,
    deviceName: String
) async throws -> any MatrixSession {
    let client = Matrix.client(homeserver: configuration.homeserver, storage: storage)
    let session = try await client.login(
        .password(
            username: username ?? configuration.username,
            password: password ?? configuration.password,
            deviceName: deviceName
        )
    )
    let states = session.sync.state
    await session.sync.start()
    _ = await firstValue(of: states) { $0 == .running }
    return session
}

/// Envoie un texte dans un salon et rend l'identifiant de l'événement une fois accepté par le
/// homeserver.
func sendText(_ body: String, in roomID: RoomID, from session: any MatrixSession) async throws -> EventID {
    for await snapshot in session.rooms.list(filter: .joined) where snapshot.contains(where: { $0.id == roomID }) {
        break
    }
    let timeline = try await session.rooms.room(roomID).timeline()
    let items = timeline.items
    try await timeline.send(.text(body))

    for await snapshot in items {
        if let message = snapshot.compactMap(\.message).first(where: { $0.body == body }),
            message.sendState == .sent,
            let eventID = message.eventID
        {
            return eventID
        }
    }
    throw MatrixError.unexpected(message: "The sent message never reached the sent state", details: nil)
}
