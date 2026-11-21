import Testing
import Foundation
import Synchronization
import MatrixClientKit

// Sérialisée pour la même raison que ``IntegrationTests`` : une seule entrée Keychain de session
// par processus. Les deux suites parentes ne sont pas sérialisées **entre elles** — il faudrait un
// parent commun, donc toucher à l'existant — : lancer séparément
// `--filter 'MatrixClientKitIntegrationTests\.HarnessTests'` et
// `--filter 'MatrixClientKitIntegrationTests\.IntegrationTests'`. Le filtre est une expression
// régulière sur l'identifiant complet : `IntegrationTests` seul désigne aussi cette suite, par le
// nom du module (voir `Tests/IntegrationHarness/README.md`).
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
    /// Un second compte sur `passwordHomeserver` et `expiringHomeserver`, si le harnais l'exporte.
    let otherUser: String?
    let otherPassword: String?

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
            oauthPassword: environment["MCK_HARNESS_OAUTH_PASSWORD"],
            otherUser: environment["MCK_HARNESS_OTHER_USER"],
            otherPassword: environment["MCK_HARNESS_OTHER_PASSWORD"]
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
    try await createRoom(on: homeserver, user: user, password: password, encrypted: true)
}

/// Comme ``createEncryptedRoom(on:user:password:)``, chiffré ou non. `powerLevels` remplace des
/// clés du premier `m.room.power_levels` (`power_level_content_override`) : le premier événement
/// de niveaux n'est soumis à aucune règle d'autorisation, il peut donc interdire à la créatrice
/// elle-même un type d'événement — à condition d'imposer une version de salon antérieure à 12
/// (`roomVersion`), où la créatrice n'a pas encore un niveau infini (MSC4289). Synapse crée des
/// salons en version 12 par défaut.
func createRoom(
    on homeserver: URL,
    user: String,
    password: String,
    encrypted: Bool,
    powerLevels: [String: Any]? = nil,
    roomVersion: String? = nil
) async throws -> RoomID {
    var login = URLRequest(url: homeserver.appending(path: "_matrix/client/v3/login"))
    login.httpMethod = "POST"
    login.setValue("application/json", forHTTPHeaderField: "Content-Type")
    login.httpBody = try JSONSerialization.data(withJSONObject: [
        "type": "m.login.password",
        "identifier": ["type": "m.id.user", "user": user],
        "password": password,
        "initial_device_display_name": "MatrixClientKit Harness (raw)",
    ])
    let loginObject = try await harnessJSON(for: login, step: "login")
    let token = try #require(loginObject["access_token"] as? String)

    var create = URLRequest(url: homeserver.appending(path: "_matrix/client/v3/createRoom"))
    create.httpMethod = "POST"
    create.setValue("application/json", forHTTPHeaderField: "Content-Type")
    create.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    var body: [String: Any] = [
        "preset": "private_chat",
        "name": "MatrixClientKit Harness \(UUID())",
    ]
    if encrypted {
        body["initial_state"] = [
            [
                "type": "m.room.encryption",
                "state_key": "",
                "content": ["algorithm": "m.megolm.v1.aes-sha2"],
            ]
        ]
    }
    if let powerLevels {
        body["power_level_content_override"] = powerLevels
    }
    if let roomVersion {
        body["room_version"] = roomVersion
    }
    create.httpBody = try JSONSerialization.data(withJSONObject: body)
    let created: Result<[String: Any], any Error>
    do {
        created = .success(try await harnessJSON(for: create, step: "createRoom"))
    } catch {
        created = .failure(error)
    }

    var logout = URLRequest(url: homeserver.appending(path: "_matrix/client/v3/logout"))
    logout.httpMethod = "POST"
    logout.setValue("application/json", forHTTPHeaderField: "Content-Type")
    logout.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    logout.httpBody = Data("{}".utf8)
    _ = try? await URLSession.shared.data(for: logout)

    // Le jeton est déconnecté ci-dessus avant de relayer un échec de `createRoom`.
    let rawRoomID = try #require(try created.get()["room_id"] as? String)
    return try #require(RoomID(rawValue: rawRoomID))
}

/// Les appareils du compte, lus par l'API client brute avec un jeton propre, déconnecté ensuite
/// (son propre appareil est exclu du résultat).
func deviceIDs(on homeserver: URL, user: String, password: String) async throws -> [String] {
    var login = URLRequest(url: homeserver.appending(path: "_matrix/client/v3/login"))
    login.httpMethod = "POST"
    login.setValue("application/json", forHTTPHeaderField: "Content-Type")
    login.httpBody = try JSONSerialization.data(withJSONObject: [
        "type": "m.login.password",
        "identifier": ["type": "m.id.user", "user": user],
        "password": password,
        "initial_device_display_name": "MatrixClientKit Harness (raw)",
    ])
    let loginObject = try await harnessJSON(for: login, step: "login")
    let token = try #require(loginObject["access_token"] as? String)
    let ownDevice = loginObject["device_id"] as? String

    var list = URLRequest(url: homeserver.appending(path: "_matrix/client/v3/devices"))
    list.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let listed: Result<[String: Any], any Error>
    do {
        listed = .success(try await harnessJSON(for: list, step: "devices"))
    } catch {
        listed = .failure(error)
    }

    var logout = URLRequest(url: homeserver.appending(path: "_matrix/client/v3/logout"))
    logout.httpMethod = "POST"
    logout.setValue("application/json", forHTTPHeaderField: "Content-Type")
    logout.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    logout.httpBody = Data("{}".utf8)
    _ = try? await URLSession.shared.data(for: logout)

    let devices = try #require(try listed.get()["devices"] as? [[String: Any]])
    return devices.compactMap { $0["device_id"] as? String }.filter { $0 != ownDevice }
}

/// Envoie une requête de l'API client brute et rend son corps JSON ; un statut autre que `200`
/// fait échouer le cas avec le statut et le corps (Synapse y met `errcode` et `error`).
private func harnessJSON(for request: URLRequest, step: String) async throws -> [String: Any] {
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
    let body = String(decoding: data, as: UTF8.self)
    try #require(status == 200, "\(step) answered HTTP \(status): \(body)")
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return try #require(object, "\(step) answered a non-object body: \(body)")
}

// MARK: - Sessions SDK

/// Session connectée sur `synapse-password` avec les identifiants du harnais, sync en cours.
func signedInSession(
    _ configuration: HarnessConfiguration, directory: URL, deviceName: String
) async throws -> any MatrixSession {
    try await signedInSession(
        homeserver: configuration.passwordHomeserver, username: configuration.user,
        password: configuration.password, directory: directory, deviceName: deviceName)
}

/// Session connectée avec un compte donné, sync en cours : sert à ouvrir une **seconde** session
/// (un autre compte, un autre répertoire de store) à côté de celle de l'utilisateur du harnais.
func signedInSession(
    homeserver: URL, username: String, password: String, directory: URL, deviceName: String
) async throws -> any MatrixSession {
    let client = Matrix.client(homeserver: homeserver, storage: .local(directory: directory))
    let session = try await client.login(
        .password(username: username, password: password, deviceName: deviceName)
    )
    let states = session.sync.state
    await session.sync.start()
    let state = await waitUntilRunning(states)
    guard state == .running else {
        await cleaningUp {
            await session.sync.stop()
            try? await session.logout()
        }
        throw MatrixError.unexpected(message: "sync reached \(String(describing: state))", details: nil)
    }
    return session
}

/// La timeline d'un salon, une fois que la sync l'a remonté (`room(_:)` ne résout que ceux-là).
func openTimeline(
    _ roomID: RoomID, in session: any MatrixSession, sourceLocation: SourceLocation = #_sourceLocation
) async throws -> any Timeline {
    let joined = await firstValue(of: session.rooms.list(filter: .joined), within: .seconds(20)) { rooms in
        rooms.contains { $0.id == roomID }
    }
    try #require(
        joined != nil, "room \(roomID.rawValue) never appeared in the joined list", sourceLocation: sourceLocation)
    return try await session.rooms.room(roomID).timeline()
}

// MARK: - Deux sessions dans un salon commun

/// Deux sessions SDK ouvertes en même temps sur `synapse-password`, membres d'un même salon.
struct HarnessPair {
    let configuration: HarnessConfiguration
    /// L'utilisateur du harnais (`MCK_HARNESS_USER`), créateur du salon.
    let first: any MatrixSession
    /// Le second compte du harnais (`MCK_HARNESS_OTHER_USER`), invité puis entré dans le salon.
    let second: any MatrixSession
    let roomID: RoomID
}

/// Crée un salon à deux membres par l'API brute, ouvre une session SDK pour chacun, exécute
/// `body`, puis arrête les syncs, déconnecte les deux sessions et supprime leurs répertoires, que
/// `body` ait réussi ou non.
///
/// Le second compte est `MCK_HARNESS_OTHER_USER`, que le script du harnais exporte : le compte
/// admin n'est exporté que par jeton, son mot de passe n'est pas dans l'environnement. Les deux
/// sessions vivent dans le même processus : l'entrée Keychain de session est celle de la dernière
/// connexion, sans effet puisqu'aucun cas ne restaure de session.
func withTwoSessions(
    encrypted: Bool = false,
    _ body: (HarnessPair) async throws -> Void
) async throws {
    let configuration = try #require(HarnessConfiguration.current)
    let otherUser = try #require(configuration.otherUser, "MCK_HARNESS_OTHER_USER is not exported")
    let otherPassword = try #require(configuration.otherPassword, "MCK_HARNESS_OTHER_PASSWORD is not exported")
    let firstDirectory = newHarnessDirectory()
    let secondDirectory = newHarnessDirectory()
    defer {
        removeDirectory(firstDirectory)
        removeDirectory(secondDirectory)
    }
    try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)

    let roomID = try await createSharedRoom(
        on: configuration.passwordHomeserver,
        creator: (configuration.user, configuration.password),
        member: (otherUser, otherPassword),
        encrypted: encrypted
    )
    let first = try await signedInSession(configuration, directory: firstDirectory, deviceName: "Harness (first)")
    let second: any MatrixSession
    do {
        second = try await signedInSession(
            homeserver: configuration.passwordHomeserver, username: otherUser, password: otherPassword,
            directory: secondDirectory, deviceName: "Harness (second)")
    } catch {
        await cleaningUp {
            await first.sync.stop()
            try? await first.logout()
        }
        throw error
    }

    let outcome: Result<Void, any Error>
    do {
        try await body(HarnessPair(configuration: configuration, first: first, second: second, roomID: roomID))
        outcome = .success(())
    } catch {
        outcome = .failure(error)
    }
    await cleaningUp {
        await first.sync.stop()
        await second.sync.stop()
        try? await first.logout()
        try? await second.logout()
    }
    try outcome.get()
}

/// Crée un salon par l'API brute au nom de `creator`, y invite `member` et l'y fait entrer, avec
/// des jetons propres déconnectés ensuite. L'API publique n'expose pas d'adhésion à un salon.
func createSharedRoom(
    on homeserver: URL,
    creator: (user: String, password: String),
    member: (user: String, password: String),
    encrypted: Bool
) async throws -> RoomID {
    let memberLogin = try await rawLogin(on: homeserver, user: member.user, password: member.password)
    let creatorLogin = try await rawLogin(on: homeserver, user: creator.user, password: creator.password)
    let outcome: Result<RoomID, any Error>
    do {
        var body: [String: Any] = [
            "preset": "private_chat",
            "name": "MatrixClientKit Harness \(UUID())",
            "invite": [memberLogin.userID],
        ]
        if encrypted {
            body["initial_state"] = [
                ["type": "m.room.encryption", "state_key": "", "content": ["algorithm": "m.megolm.v1.aes-sha2"]]
            ]
        }
        let created = try await rawRequest(
            "POST", "_matrix/client/v3/createRoom", on: homeserver, token: creatorLogin.token, body: body)
        let rawRoomID = try #require(created["room_id"] as? String)
        _ = try await rawRequest(
            "POST", "_matrix/client/v3/join/\(rawRoomID)", on: homeserver, token: memberLogin.token, body: [:])
        outcome = .success(try #require(RoomID(rawValue: rawRoomID)))
    } catch {
        outcome = .failure(error)
    }
    await rawLogout(on: homeserver, token: creatorLogin.token)
    await rawLogout(on: homeserver, token: memberLogin.token)
    return try outcome.get()
}

/// Change le nom du salon par l'API brute, au nom de `user` : l'API publique ne modifie pas un
/// salon. Produit un événement d'état `m.room.name`.
func renameRoom(
    _ roomID: RoomID, to name: String, on homeserver: URL, user: String, password: String
) async throws {
    let login = try await rawLogin(on: homeserver, user: user, password: password)
    let outcome: Result<Void, any Error>
    do {
        _ = try await rawRequest(
            "PUT", "_matrix/client/v3/rooms/\(roomID.rawValue)/state/m.room.name", on: homeserver,
            token: login.token, body: ["name": name])
        outcome = .success(())
    } catch {
        outcome = .failure(error)
    }
    await rawLogout(on: homeserver, token: login.token)
    try outcome.get()
}

private struct RawLogin {
    let token: String
    let userID: String
}

private func rawLogin(on homeserver: URL, user: String, password: String) async throws -> RawLogin {
    let object = try await rawRequest(
        "POST", "_matrix/client/v3/login", on: homeserver, token: nil,
        body: [
            "type": "m.login.password",
            "identifier": ["type": "m.id.user", "user": user],
            "password": password,
            "initial_device_display_name": "MatrixClientKit Harness (raw)",
        ])
    return RawLogin(
        token: try #require(object["access_token"] as? String), userID: try #require(object["user_id"] as? String))
}

private func rawLogout(on homeserver: URL, token: String) async {
    _ = try? await rawRequest("POST", "_matrix/client/v3/logout", on: homeserver, token: token, body: [:])
}

private func rawRequest(
    _ method: String, _ path: String, on homeserver: URL, token: String?, body: [String: Any]
) async throws -> [String: Any] {
    var request = URLRequest(url: homeserver.appending(path: path))
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    return try await harnessJSON(for: request, step: "\(method) \(path)")
}

// MARK: - Observation d'une timeline

/// Itère un flux `items` en tâche de fond et garde chaque instantané reçu : les assertions portent
/// sur le dernier, ou sur tout l'historique (« l'écho a-t-il été vu ? »).
final class TimelineRecorder: Sendable {
    private final class Log: Sendable {
        let snapshots = Mutex<[[TimelineItem]]>([])
    }

    private let log: Log
    private let task: Task<Void, Never>

    init(_ items: AsyncStream<[TimelineItem]>) {
        let log = Log()
        self.log = log
        self.task = Task {
            for await snapshot in items {
                log.snapshots.withLock { $0.append(snapshot) }
            }
        }
    }

    deinit {
        task.cancel()
    }

    /// Le dernier instantané, `nil` avant le premier.
    var latest: [TimelineItem]? {
        log.snapshots.withLock { $0.last }
    }

    func everSaw(_ predicate: (TimelineItem) -> Bool) -> Bool {
        let snapshots = log.snapshots.withLock { $0 }
        return snapshots.contains { $0.contains(where: predicate) }
    }

    /// Le premier dernier-instantané qui satisfait `predicate`, sondé toutes les 100 ms ; `nil`
    /// après `timeout`.
    func waitUntil(within timeout: Duration, _ predicate: ([TimelineItem]) -> Bool) async -> [TimelineItem]? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let latest, predicate(latest) { return latest }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    /// Termine l'itération ; le flux est alors libéré et sa souscription amont annulée.
    func stop() {
        task.cancel()
    }
}
