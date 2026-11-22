import Testing
import Foundation
import Synchronization
import MatrixClientKit

extension HarnessTests {
    // Profil, présence, compte et durée de vie contre le harnais (PRD 0.6, §8 critères 6 à 11).
    // Les constats « amont » sont imprimés avec le préfixe `[T11]` et consignés dans les rulings
    // 0.6. Aucun cas ne modifie `mck-other` ; les cas qui changent `mck-user` (nom, avatar,
    // présence, utilisateur ignoré) le remettent en l'état en sortant. La désactivation ne touche
    // qu'un compte jetable créé par l'API admin.
    @Suite
    struct ProfileAndAccountHarnessTests {
        // MARK: Présence (critère 6)

        /// `setPresence(.online)` puis `.unavailable` : l'API HTTP du serveur rend l'état publié.
        /// Constat : l'état que le serveur rend avant tout appel (l'amont annonce `unavailable`
        /// comme état initial des requêtes de sync).
        @Test(.timeLimit(.minutes(3)))
        func publishedPresenceIsVisibleOverHTTP() async throws {
            let configuration = try #require(HarnessConfiguration.current)
            try await withUserSession(configuration) { session in
                let viewer = try await RawAccount.login(
                    on: configuration.passwordHomeserver, user: configuration.user, password: configuration.password)
                let outcome = await attempt {
                    try await Task.sleep(for: .seconds(3))
                    let initial = try await viewer.presence(of: session.userID)
                    print("[T11] presence read over HTTP once the sync runs, before any setPresence: \(initial)")

                    try await setPresenceRetryingWhenRateLimited(.online, on: session)
                    let online = try await viewer.waitForPresence("online", of: session.userID, within: .seconds(30))
                    #expect(online == "online", "after setPresence(.online) the server reports \(online)")

                    try await setPresenceRetryingWhenRateLimited(.unavailable, on: session)
                    let unavailable = try await viewer.waitForPresence(
                        "unavailable", of: session.userID, within: .seconds(30))
                    #expect(
                        unavailable == "unavailable",
                        "after setPresence(.unavailable) the server reports \(unavailable)")
                }
                await viewer.logout()
                try outcome.get()
            }
        }

        // MARK: Profil (critère 7)

        /// `setDisplayName`, `setAvatar`, `removeAvatar` : `profile(of:)` du compte reflète chaque
        /// changement.
        @Test(.timeLimit(.minutes(3)))
        func ownProfileEditsAreReflected() async throws {
            let configuration = try #require(HarnessConfiguration.current)
            try await withUserSession(configuration) { session in
                let original = try await session.profile.profile(of: session.userID)
                let name = "T11 \(UUID().uuidString.prefix(8))"
                let restoredName = original.displayName ?? configuration.user
                let outcome = await attempt {
                    try await session.profile.setDisplayName(name)
                    let renamed = try await profile(of: session.userID, in: session) { $0.displayName == name }
                    #expect(renamed.displayName == name, "display name after setDisplayName: \(describe(renamed))")

                    try await session.profile.setAvatar(onePixelPNG, mimeType: "image/png")
                    let withAvatar = try await profile(of: session.userID, in: session) { $0.avatar != nil }
                    #expect(withAvatar.avatar != nil, "avatar after setAvatar: \(describe(withAvatar))")
                    #expect(withAvatar.displayName == name, "the name changed with the avatar: \(describe(withAvatar))")

                    try await session.profile.removeAvatar()
                    let withoutAvatar = try await profile(of: session.userID, in: session) { $0.avatar == nil }
                    #expect(withoutAvatar.avatar == nil, "avatar after removeAvatar: \(describe(withoutAvatar))")
                }
                // Remise en l'état, que le cas ait réussi ou non.
                try? await session.profile.removeAvatar()
                try? await session.profile.setDisplayName(restoredName)
                try outcome.get()
            }
        }

        /// `profile(of:)` d'un autre compte rend son nom.
        @Test(.timeLimit(.minutes(2)))
        func anotherUsersProfileIsReadable() async throws {
            let configuration = try #require(HarnessConfiguration.current)
            let otherUser = try #require(configuration.otherUser, "MCK_HARNESS_OTHER_USER is not exported")
            try await withUserSession(configuration) { session in
                let other = try #require(UserID(rawValue: "@\(otherUser):localhost"))
                let profile = try await session.profile.profile(of: other)
                #expect(profile.userID == other, "profile: \(describe(profile))")
                #expect(profile.displayName == otherUser, "profile of \(other.rawValue): \(describe(profile))")
            }
        }

        /// `profile(of:)` d'un compte inexistant : `.notFound(.user)` (remappé depuis
        /// `.notFound(.unspecified)`).
        @Test(.timeLimit(.minutes(2)))
        func anUnknownUsersProfileIsNotFound() async throws {
            let configuration = try #require(HarnessConfiguration.current)
            try await withUserSession(configuration) { session in
                let suffix = UUID().uuidString.prefix(8).lowercased()
                let unknown = try #require(UserID(rawValue: "@mck-nobody-\(suffix):localhost"))
                switch await attempt({ try await session.profile.profile(of: unknown) }) {
                case let .success(profile):
                    Issue.record("[T11] profile(of:) of an unknown user succeeded: \(describe(profile))")
                case let .failure(error):
                    #expect(
                        (error as? MatrixError) == .notFound(.user),
                        "[T11] profile(of:) of an unknown user threw \(error)")
                }
            }
        }

        // MARK: URL de gestion (critère 8)

        /// Sur le serveur à mot de passe, aucune gestion déléguée : `nil`.
        @Test(.timeLimit(.minutes(2)))
        func managementURLIsNilOnAPasswordHomeserver() async throws {
            let configuration = try #require(HarnessConfiguration.current)
            try await withUserSession(configuration) { session in
                let url = try await session.account.managementURL(for: .profile)
                #expect(url == nil, "managementURL(for: .profile) on synapse-password: \(String(describing: url))")
            }
        }

        /// Sur `synapse-oauth` + MAS : une URL de l'hôte MAS. Le MAS du harnais annonce
        /// `http://localhost:8082/account/` (sondé par HTTP) : `http` est accepté parce que l'hôte
        /// est en boucle locale (décision D4, rulings 0.6) ; `https` l'est partout.
        @Test(.enabled(if: HarnessConfiguration.current?.mas != nil), .timeLimit(.minutes(3)))
        func managementURLPointsAtMASOnAnOAuthHomeserver() async throws {
            try await withOAuthSession { session, mas, _ in
                for action in [AccountManagementAction.profile, .devices, .deactivateAccount] {
                    switch await attempt({ try await session.account.managementURL(for: action) }) {
                    case let .success(url):
                        #expect(
                            url?.scheme == "http" || url?.scheme == "https",
                            "[T11] management URL for \(action): \(String(describing: url))")
                        #expect(url?.host == mas.host, "[T11] management URL for \(action): \(String(describing: url))")
                    case let .failure(error):
                        Issue.record(
                            "[T11] managementURL(for: \(action)) threw \(error); MAS advertises \(mas.absoluteString)")
                    }
                }
            }
        }

        /// Une session OAuth ne se désactive pas par mot de passe : `.unexpected`, sans appel amont,
        /// et la session reste ouverte.
        @Test(.enabled(if: HarnessConfiguration.current?.mas != nil), .timeLimit(.minutes(3)))
        func deactivatingAnOAuthSessionIsRefused() async throws {
            try await withOAuthSession { session, _, password in
                switch await attempt({ try await session.account.deactivate(password: password, eraseData: false) }) {
                case .success:
                    Issue.record("[T11] deactivate(password:) succeeded on an OAuth session")
                case let .failure(error):
                    if case .unexpected = error as? MatrixError {
                        // Attendu.
                    } else {
                        Issue.record("[T11] deactivate on an OAuth session threw \(error), expected .unexpected")
                    }
                }
                let state = await firstValue(of: session.authState, within: .seconds(5)) { _ in true }
                #expect(state == .signedIn, "auth state after the refused deactivation: \(String(describing: state))")
            }
        }

        // MARK: Utilisateurs ignorés (critère 9)

        /// `ignore(B)` : le flux émet une liste contenant B ; `unignore(B)` la vide de B.
        @Test(.timeLimit(.minutes(3)))
        func ignoringAUserIsObservable() async throws {
            let configuration = try #require(HarnessConfiguration.current)
            let otherUser = try #require(configuration.otherUser, "MCK_HARNESS_OTHER_USER is not exported")
            try await withUserSession(configuration) { session in
                let other = try #require(UserID(rawValue: "@\(otherUser):localhost"))
                // État de départ propre, au cas où une exécution précédente aurait été interrompue.
                try? await session.account.unignore(other)

                let log = SnapshotLog<[UserID]>()
                let stream = session.account.ignoredUsers
                let task = Task {
                    for await snapshot in stream { log.record(snapshot) }
                }
                let outcome = await attempt {
                    let initial = await log.waitUntil(within: .seconds(30)) { _ in true }
                    #expect(initial != nil, "ignoredUsers never emitted an initial list")

                    try await session.account.ignore(other)
                    let ignored = await log.waitUntil(within: .seconds(30)) { $0.contains(other) }
                    #expect(ignored != nil, "after ignore(\(other.rawValue)), ignoredUsers emitted \(log.all)")

                    try await session.account.unignore(other)
                    let cleared = await log.waitUntil(within: .seconds(30)) { !$0.contains(other) }
                    #expect(cleared != nil, "after unignore(\(other.rawValue)), ignoredUsers emitted \(log.all)")
                }
                task.cancel()
                try? await session.account.unignore(other)
                try outcome.get()
            }
        }

        // MARK: Désactivation (critère 10, D1)

        /// Compte jetable créé par l'API admin : un mauvais mot de passe est refusé sans rien
        /// effacer ; le bon désactive le compte, termine la session, efface le store, et une
        /// connexion ultérieure est refusée.
        @Test(.timeLimit(.minutes(4)))
        func deactivationNeedsThePasswordAndEndsTheSession() async throws {
            let configuration = try #require(HarnessConfiguration.current)
            let admin = try AdminAPI(configuration)
            let username = "mck-t11-\(UUID().uuidString.prefix(8).lowercased())"
            let password = "t11-\(UUID().uuidString)"
            let userID = try #require(UserID(rawValue: "@\(username):localhost"))
            try await admin.createUser(userID, password: password)
            let directory = newHarnessDirectory()
            let loginDirectory = newHarnessDirectory()
            defer {
                removeDirectory(directory)
                removeDirectory(loginDirectory)
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: loginDirectory, withIntermediateDirectories: true)

            let outcome = await attempt {
                try await runDeactivation(
                    configuration, username: username, password: password, directory: directory,
                    loginDirectory: loginDirectory)
            }
            // Le compte jetable ne survit pas au cas, quelle que soit son issue.
            await admin.deactivate(userID)
            try outcome.get()
        }

        // MARK: Durée de vie (critère 11, §6)

        /// L'application garde `profile`, `account` et les flux `ignoredUsers` et `typingUsers`
        /// après la session : `logout()`, la session libérée, puis le reste. Le processus de test ne
        /// doit pas s'arrêter.
        @Test(.timeLimit(.minutes(3)))
        func profileAccountAndStreamsKeptAfterLogoutDoNotCrash() async throws {
            let configuration = try #require(HarnessConfiguration.current)
            let directory = newHarnessDirectory()
            defer { removeDirectory(directory) }
            let roomID = try await createRoom(
                on: configuration.passwordHomeserver, user: configuration.user, password: configuration.password,
                encrypted: false)

            var session: (any MatrixSession)? = try await signedInSession(
                configuration, directory: directory, deviceName: "Harness (T11 lifetime)")
            // Sonde faible : prouve que la session est vraiment libérée avant ses dépendants.
            weak var sessionProbe: AnyObject? = session.map { $0 as AnyObject }
            var profile: (any ProfileService)?
            var account: (any AccountService)?
            var room: (any RoomHandle)?
            var typingStream: AsyncStream<[UserID]>?
            var ignoredStream: AsyncStream<[UserID]>?
            let ignoredEmissions = Counter()
            let typingEmissions = Counter()
            var typingTask: Task<Void, Never>?
            var ignoredTask: Task<Void, Never>?

            do {
                let opened = try #require(session)
                let joined = await firstValue(of: opened.rooms.list(filter: .joined), within: .seconds(20)) { rooms in
                    rooms.contains { $0.id == roomID }
                }
                try #require(joined != nil, "the room never appeared")
                let openedRoom = try await opened.rooms.room(roomID)
                room = openedRoom
                profile = opened.profile
                account = opened.account
                let typing = openedRoom.typingUsers
                let ignored = opened.account.ignoredUsers
                typingStream = typing
                ignoredStream = ignored
                // Les souscriptions amont s'ouvrent à la première itération.
                typingTask = Task {
                    for await _ in typing { typingEmissions.increment() }
                }
                ignoredTask = Task {
                    for await _ in ignored { ignoredEmissions.increment() }
                }
                _ = try await opened.profile.profile(of: opened.userID)
                for _ in 0..<100 where ignoredEmissions.value == 0 {
                    try await Task.sleep(for: .milliseconds(100))
                }
                print(
                    "[T11] before logout: ignoredUsers emitted \(ignoredEmissions.value), typingUsers \(typingEmissions.value)"
                )
            } catch {
                if let opened = session {
                    await cleaningUp {
                        await opened.sync.stop()
                        try? await opened.logout()
                    }
                }
                typingTask?.cancel()
                ignoredTask?.cancel()
                throw error
            }

            if let opened = session {
                await cleaningUp {
                    await opened.sync.stop()
                    try? await opened.logout()
                }
            }
            session = nil
            try await Task.sleep(for: .seconds(1))
            for _ in 0..<40 where sessionProbe != nil {
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(sessionProbe == nil, "the session is still alive: the dependents would not be the last holders")

            // La session est partie : le `Client` FFI ne vit plus que par ce qui reste ici.
            #expect(profile != nil && account != nil && room != nil)
            #expect(typingStream != nil && ignoredStream != nil)
            try await Task.sleep(for: .seconds(2))

            typingTask?.cancel()
            ignoredTask?.cancel()
            typingTask = nil
            ignoredTask = nil
            typingStream = nil
            ignoredStream = nil
            profile = nil
            account = nil
            room = nil
            try await Task.sleep(for: .seconds(1))
        }
    }
}

// MARK: - Désactivation

private func runDeactivation(
    _ configuration: HarnessConfiguration, username: String, password: String, directory: URL,
    loginDirectory: URL
) async throws {
    let session = try await signedInSession(
        homeserver: configuration.passwordHomeserver, username: username, password: password,
        directory: directory, deviceName: "Harness (T11 deactivation)")
    var deactivated = false
    let outcome = await attempt {
        // Mauvais mot de passe : refusé, rien n'est effacé, la session reste utilisable.
        let wrong = await attempt {
            try await session.account.deactivate(password: "not-\(password)", eraseData: false)
        }
        switch wrong {
        case .success:
            Issue.record("[T11] deactivate(password:) with a wrong password succeeded")
            deactivated = true
        case let .failure(error):
            print("[T11] deactivate with a wrong password threw: \(error)")
            #expect(
                (error as? MatrixError) == .authentication(.invalidCredentials),
                "[T11] deactivate with a wrong password threw \(error)")
        }
        let afterWrong = await firstValue(of: session.authState, within: .seconds(5)) { _ in true }
        #expect(afterWrong == .signedIn, "auth state after the refused attempt: \(String(describing: afterWrong))")
        #expect(!storeDirectories(in: directory).isEmpty, "the store was erased by a refused deactivation")
        if case let .failure(error) = await attempt({ try await session.profile.profile(of: session.userID) }) {
            Issue.record("[T11] the session is unusable after a refused deactivation: \(error)")
        }

        // Bon mot de passe : succès, `.signedOut`, store effacé.
        try await session.account.deactivate(password: password, eraseData: false)
        deactivated = true
        let signedOut = await firstValue(of: session.authState, within: .seconds(30)) { $0 == .signedOut }
        #expect(signedOut == .signedOut, "auth state after the deactivation never reached .signedOut")
        let stores = storeDirectories(in: directory)
        #expect(stores.isEmpty, "stores left after the deactivation: \(stores)")

        // Une connexion ultérieure est refusée.
        let client = Matrix.client(
            homeserver: configuration.passwordHomeserver, storage: .local(directory: loginDirectory))
        let relogin = await attempt {
            _ = try await client.login(
                .password(username: username, password: password, deviceName: "Harness (T11 relogin)"))
        }
        switch relogin {
        case .success:
            Issue.record("[T11] a login on the deactivated account succeeded")
        case let .failure(error):
            print("[T11] login on the deactivated account threw: \(error)")
            switch error as? MatrixError {
            case .authentication(.userDeactivated), .authentication(.invalidCredentials):
                break
            default:
                Issue.record("[T11] login on the deactivated account threw \(error), expected .authentication")
            }
        }
        let leftBehind = storeDirectories(in: loginDirectory)
        #expect(leftBehind.isEmpty, "a refused login left stores: \(leftBehind)")
    }
    if !deactivated {
        await cleaningUp {
            await session.sync.stop()
            try? await session.logout()
        }
    }
    try outcome.get()
}

// MARK: - Aides

private func attempt<Value>(_ body: () async throws -> Value) async -> Result<Value, any Error> {
    do {
        return .success(try await body())
    } catch {
        return .failure(error)
    }
}

private func withUserSession(
    _ configuration: HarnessConfiguration, _ body: (any MatrixSession) async throws -> Void
) async throws {
    let directory = newHarnessDirectory()
    defer { removeDirectory(directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let session = try await signedInSession(configuration, directory: directory, deviceName: "Harness (T11)")
    let outcome = await attempt { try await body(session) }
    await cleaningUp {
        await session.sync.stop()
        try? await session.logout()
    }
    try outcome.get()
}

private func withOAuthSession(
    _ body: (any MatrixSession, _ mas: URL, _ password: String) async throws -> Void
) async throws {
    let directory = newHarnessDirectory()
    defer { removeDirectory(directory) }
    let signIn = try await OAuthSignIn.open(in: directory)
    let session = signIn.session
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
    let outcome = await attempt { try await body(session, signIn.mas, signIn.password) }
    await cleaningUp {
        await session.sync.stop()
        try? await session.logout()
    }
    try outcome.get()
}

/// Les mises à jour de présence sont limitées en débit par Synapse (sondé : `M_LIMIT_EXCEEDED`,
/// `retry_after_ms` ≈ 10 s sur la seconde mise à jour consécutive). La limite est de l'amont : on
/// attend le délai annoncé et on rejoue, au plus trois fois.
private func setPresenceRetryingWhenRateLimited(_ presence: Presence, on session: any MatrixSession) async throws {
    for attemptNumber in 1...3 {
        do {
            try await session.profile.setPresence(presence)
            return
        } catch let MatrixError.rateLimited(retryAfter) where attemptNumber < 3 {
            print("[T11] setPresence(\(presence)) rate limited, retry after \(String(describing: retryAfter))")
            try await Task.sleep(for: (retryAfter ?? .seconds(10)) + .seconds(1))
        }
    }
}

/// `profile(of:)` jusqu'à ce que `condition` soit vraie (au plus 15 s) ; le dernier profil lu sinon.
private func profile(
    of user: UserID, in session: any MatrixSession, until condition: (UserProfile) -> Bool
) async throws -> UserProfile {
    var latest = try await session.profile.profile(of: user)
    for _ in 0..<30 where !condition(latest) {
        try await Task.sleep(for: .milliseconds(500))
        latest = try await session.profile.profile(of: user)
    }
    return latest
}

private func describe(_ profile: UserProfile) -> String {
    "name \(String(describing: profile.displayName)), avatar \(String(describing: profile.avatar))"
}

/// PNG de 1 x 1 pixel : le serveur ne regarde que les octets.
private let onePixelPNG =
    Data(
        base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")
    ?? Data()

private final class Counter: Sendable {
    private let count = Mutex(0)
    var value: Int { count.withLock { $0 } }
    func increment() { count.withLock { $0 += 1 } }
}

/// Garde chaque instantané d'un flux, sondé toutes les 100 ms.
private final class SnapshotLog<Element: Sendable>: Sendable {
    private let snapshots = Mutex<[Element]>([])

    var all: [Element] { snapshots.withLock { $0 } }

    func record(_ snapshot: Element) {
        snapshots.withLock { $0.append(snapshot) }
    }

    /// Le dernier instantané s'il satisfait `predicate`, sondé jusqu'à `timeout` ; `nil` sinon.
    func waitUntil(within timeout: Duration, _ predicate: (Element) -> Bool) async -> Element? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let last = all.last, predicate(last) { return last }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }
}

// MARK: - API brute

private struct HTTPOutcome {
    let status: Int
    let object: [String: Any]
    let body: String
}

private func rawHTTP(
    _ method: String, _ url: URL, token: String?, body: [String: Any]? = nil
) async throws -> HTTPOutcome {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
    let (data, response) = try await URLSession.shared.data(for: request)
    let object = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    return HTTPOutcome(
        status: (response as? HTTPURLResponse)?.statusCode ?? -1, object: object,
        body: String(decoding: data, as: UTF8.self))
}

/// Un jeton propre au compte, pour lire par l'API client ce que le SDK a publié.
private struct RawAccount {
    let homeserver: URL
    let token: String

    static func login(on homeserver: URL, user: String, password: String) async throws -> RawAccount {
        let outcome = try await rawHTTP(
            "POST", homeserver.appending(path: "_matrix/client/v3/login"), token: nil,
            body: [
                "type": "m.login.password",
                "identifier": ["type": "m.id.user", "user": user],
                "password": password,
                "initial_device_display_name": "MatrixClientKit Harness (T11 raw)",
            ])
        try #require(outcome.status == 200, "raw login answered HTTP \(outcome.status): \(outcome.body)")
        return RawAccount(homeserver: homeserver, token: try #require(outcome.object["access_token"] as? String))
    }

    func logout() async {
        _ = try? await rawHTTP(
            "POST", homeserver.appending(path: "_matrix/client/v3/logout"), token: token, body: [:])
    }

    /// `GET /presence/{userId}/status` : la valeur de `presence`.
    func presence(of user: UserID) async throws -> String {
        let outcome = try await rawHTTP(
            "GET", homeserver.appending(path: "_matrix/client/v3/presence/\(user.rawValue)/status"), token: token)
        guard outcome.status == 200 else { return "HTTP \(outcome.status): \(outcome.body)" }
        return (outcome.object["presence"] as? String) ?? "no presence in \(outcome.body)"
    }

    /// Sonde jusqu'à `expected` (au plus `timeout`) ; la dernière valeur lue sinon.
    func waitForPresence(_ expected: String, of user: UserID, within timeout: Duration) async throws -> String {
        let deadline = ContinuousClock.now + timeout
        var latest = try await presence(of: user)
        while latest != expected, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(500))
            latest = try await presence(of: user)
        }
        return latest
    }
}

/// L'API admin de Synapse, avec le jeton que `Scripts/integration-harness.sh env` exporte.
private struct AdminAPI {
    let homeserver: URL
    let token: String

    init(_ configuration: HarnessConfiguration) throws {
        homeserver = configuration.passwordHomeserver
        token = try #require(
            ProcessInfo.processInfo.environment["MCK_HARNESS_ADMIN_TOKEN_PASSWORD"],
            "MCK_HARNESS_ADMIN_TOKEN_PASSWORD is not exported")
    }

    func createUser(_ user: UserID, password: String) async throws {
        let outcome = try await rawHTTP(
            "PUT", homeserver.appending(path: "_synapse/admin/v2/users/\(user.rawValue)"), token: token,
            body: ["password": password, "admin": false])
        try #require(
            (200..<300).contains(outcome.status), "admin user creation answered HTTP \(outcome.status): \(outcome.body)"
        )
    }

    /// Meilleur effort : le compte est jetable, `down` efface de toute façon les volumes.
    func deactivate(_ user: UserID) async {
        _ = try? await rawHTTP(
            "POST", homeserver.appending(path: "_synapse/admin/v1/deactivate/\(user.rawValue)"), token: token,
            body: [:])
    }
}
