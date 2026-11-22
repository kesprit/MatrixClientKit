import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private final class FakeTaskHandle: TaskHandleProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.withLock { cancelled = true } }
    func isFinished() -> Bool { lock.withLock { cancelled } }
}

private final class FakeAccountDriver: AccountDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var _actions: [MatrixRustSDK.AccountManagementAction?] = []
    private var _ignored: [String] = []
    private var _unignored: [String] = []
    private var _listener: (any IgnoredUsersListener)?
    var accountURL: String? = "https://account.example.org/"
    var initial: [String] = []
    var error: (any Error)?
    let handle = FakeTaskHandle()
    /// Quand `holdInitial` est vrai, la lecture initiale attend `releaseInitial()`.
    var holdInitial = false
    private var _initialReadFinished = false
    private var _deactivations: [Deactivation] = []
    /// Erreurs rendues par `deactivateAccount`, appel après appel ; `nil` ou file vide : succès.
    var deactivationOutcomes: [(any Error)?] = []
    /// Exécuté au début de chaque `deactivateAccount`, dans la tâche appelante.
    var deactivationHook: (@Sendable () -> Void)?

    struct Deactivation: Equatable {
        let authData: AuthData?
        let eraseData: Bool
    }

    var initialReadFinished: Bool { lock.withLock { _initialReadFinished } }
    var deactivations: [Deactivation] { lock.withLock { _deactivations } }
    private let initialGate = AsyncStream<Void>.makeStream()

    func releaseInitial() { initialGate.continuation.yield() }

    var actions: [MatrixRustSDK.AccountManagementAction?] { lock.withLock { _actions } }
    var ignored: [String] { lock.withLock { _ignored } }
    var unignored: [String] { lock.withLock { _unignored } }
    var listener: (any IgnoredUsersListener)? { lock.withLock { _listener } }

    func accountUrl(action: MatrixRustSDK.AccountManagementAction?) async throws -> String? {
        try lock.withLock {
            if let error { throw error }
            _actions.append(action)
        }
        return accountURL
    }

    func deactivateAccount(authData: AuthData?, eraseData: Bool) async throws {
        deactivationHook?()
        try lock.withLock {
            _deactivations.append(Deactivation(authData: authData, eraseData: eraseData))
            let outcome = deactivationOutcomes.isEmpty ? nil : deactivationOutcomes.removeFirst()
            if let outcome { throw outcome }
        }
    }

    func ignoredUsers() async throws -> [String] {
        defer { lock.withLock { _initialReadFinished = true } }
        if holdInitial { for await _ in initialGate.stream { break } }
        return try lock.withLock {
            if let error { throw error }
            return initial
        }
    }

    func ignoreUser(userId: String) async throws {
        try lock.withLock {
            if let error { throw error }
            _ignored.append(userId)
        }
    }

    func unignoreUser(userId: String) async throws {
        try lock.withLock {
            if let error { throw error }
            _unignored.append(userId)
        }
    }

    func subscribeToIgnoredUsers(listener: any IgnoredUsersListener) -> any TaskHandleProtocol {
        lock.withLock { _listener = listener }
        return handle
    }
}

private func user(_ raw: String) -> UserID { UserID(rawValue: raw)! }

private func waitUntil(_ condition: @Sendable () -> Bool) async {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
}

private func isUnexpected(_ error: any Error) -> Bool {
    if case MatrixError.unexpected = error { true } else { false }
}

private let forbidden = ClientError.MatrixApi(kind: .forbidden, code: "M_FORBIDDEN", msg: "no", details: nil)

/// Le refus du mot de passe au second appel contre Synapse : pas de `M_FORBIDDEN`, une réponse UIAA
/// portant `auth_error` (erreur relevée telle quelle contre le harnais).
private let uiaaRefusal = ClientError.Generic(
    msg: "the server returned an error: User-Interactive Authentication required.",
    details: "Api(Server(AuthResponse(UiaaInfo { flows: [AuthFlow { stages: [\"m.login.password\"] }], "
        + "completed: [], params: Some(RawValue({})), session: Some(\"ontiejDvRzOFqTlYlMOnVHss\"), "
        + "auth_error: Some(StandardErrorBody { kind: Forbidden, "
        + "message: \"Invalid username or password\" }) })))")

@Suite struct AccountServiceTests {
    private func makeService(
        _ driver: FakeAccountDriver,
        usesOAuth: Bool = false,
        lifecycle: SessionLifecycle? = nil
    ) -> RustAccountService {
        RustAccountService(
            driver: driver,
            lifetime: .detached(),
            userID: user("@me:x.org"),
            usesOAuth: usesOAuth,
            lifecycle: lifecycle ?? makeLifecycle(journal: Journal())
        )
    }

    @Test func managementURLPassesUpstreamAction() async throws {
        let driver = FakeAccountDriver()
        let url = try await makeService(driver).managementURL(for: .device(DeviceID(rawValue: "D1")!))
        #expect(url == URL(string: "https://account.example.org/"))
        #expect(driver.actions == [.deviceView(deviceId: "D1")])
    }

    @Test func overviewSendsNoAction() async throws {
        let driver = FakeAccountDriver()
        _ = try await makeService(driver).managementURL(for: .overview)
        #expect(driver.actions.count == 1)
        #expect(driver.actions[0] == nil)
    }

    @Test func nilUpstreamURLIsNil() async throws {
        let driver = FakeAccountDriver()
        driver.accountURL = nil
        #expect(try await makeService(driver).managementURL(for: .profile) == nil)
    }

    @Test func malformedUpstreamURLIsUnexpected() async {
        let driver = FakeAccountDriver()
        driver.accountURL = "not a url"
        let service = makeService(driver)
        await #expect { try await service.managementURL(for: .profile) } throws: { isUnexpected($0) }
    }

    @Test func aNonHTTPSManagementURLIsUnexpected() async {
        let driver = FakeAccountDriver()
        driver.accountURL = "http://account.example.org/"
        let service = makeService(driver)
        await #expect { try await service.managementURL(for: .profile) } throws: { isUnexpected($0) }
    }

    @Test func managementErrorsGoThroughErrorMapper() async {
        let driver = FakeAccountDriver()
        driver.error = forbidden
        let service = makeService(driver)
        await #expect(throws: MatrixError.permission(.forbidden)) { try await service.managementURL(for: .profile) }
    }

    @Test func ignoreAndUnignorePassIdentifiers() async throws {
        let driver = FakeAccountDriver()
        let service = makeService(driver)
        try await service.ignore(user("@b:x.org"))
        try await service.unignore(user("@b:x.org"))
        #expect(driver.ignored == ["@b:x.org"])
        #expect(driver.unignored == ["@b:x.org"])
    }

    @Test func ignoreErrorsAreMapped() async {
        let driver = FakeAccountDriver()
        driver.error = forbidden
        let service = makeService(driver)
        await #expect(throws: MatrixError.permission(.forbidden)) { try await service.ignore(user("@b:x.org")) }
        await #expect(throws: MatrixError.permission(.forbidden)) { try await service.unignore(user("@b:x.org")) }
    }

    @Test func ignoredUsersEmitsInitialListThenUpdates() async {
        let driver = FakeAccountDriver()
        driver.initial = ["@a:x.org"]
        let service = makeService(driver)
        var iterator = service.ignoredUsers.makeAsyncIterator()

        #expect(await iterator.next() == [user("@a:x.org")])
        driver.listener?.call(ignoredUserIds: ["@a:x.org", "@b:x.org"])
        #expect(await iterator.next() == [user("@a:x.org"), user("@b:x.org")])
        driver.listener?.call(ignoredUserIds: [])
        #expect(await iterator.next() == [])
    }

    @Test func ignoredUsersEndsWithoutValueWhenInitialReadFails() async {
        let driver = FakeAccountDriver()
        driver.error = ClientError.Generic(msg: "boom", details: nil)
        let service = makeService(driver)
        var values: [[UserID]] = []
        for await users in service.ignoredUsers { values.append(users) }
        #expect(values.isEmpty)
        await waitUntil { driver.handle.isFinished() }
        #expect(driver.handle.isFinished())
    }

    @Test(.timeLimit(.minutes(1)))
    func ignoredUsersStaysOpenWhenInitialReadFailsAfterTheListenerDelivered() async {
        let driver = FakeAccountDriver()
        driver.error = ClientError.Generic(msg: "boom", details: nil)
        driver.holdInitial = true
        let service = makeService(driver)
        let collector = Collector()
        let consumer = Task { for await users in service.ignoredUsers { collector.append(users) } }
        await waitUntil { driver.listener != nil }

        driver.listener?.call(ignoredUserIds: ["@a:x.org"])
        await waitUntil { collector.values.count == 1 }
        driver.releaseInitial()
        await waitUntil { driver.initialReadFinished }
        await yieldABunch()
        driver.listener?.call(ignoredUserIds: ["@b:x.org"])
        await waitUntil { collector.values.count == 2 }

        #expect(collector.values == [[user("@a:x.org")], [user("@b:x.org")]])
        #expect(!driver.handle.isFinished())
        consumer.cancel()
    }

    @Test func leavingTheLoopCancelsTheTaskHandle() async {
        let driver = FakeAccountDriver()
        let service = makeService(driver)
        for await _ in service.ignoredUsers { break }
        await waitUntil { driver.handle.isFinished() }
        #expect(driver.handle.isFinished())
    }

    @Test func cancellingTheConsumerCancelsTheTaskHandle() async {
        let driver = FakeAccountDriver()
        let service = makeService(driver)
        let task = Task { for await _ in service.ignoredUsers {} }
        await waitUntil { driver.listener != nil }
        task.cancel()
        await waitUntil { driver.handle.isFinished() }
        #expect(driver.handle.isFinished())
    }

    @Test(.timeLimit(.minutes(1)))
    func listenerValueBeatsAStaleInitialRead() async {
        let driver = FakeAccountDriver()
        driver.initial = ["@old:x.org"]
        driver.holdInitial = true
        let service = makeService(driver)
        let collector = Collector()
        let consumer = Task { for await users in service.ignoredUsers { collector.append(users) } }
        await waitUntil { driver.listener != nil }

        driver.listener?.call(ignoredUserIds: ["@new:x.org"])
        await waitUntil { collector.values.count == 1 }
        driver.releaseInitial()
        await waitUntil { driver.initialReadFinished }
        // Test de comportement : la détection déterministe de la régression est dans
        // `FirstDeliveryGateTests`.
        await yieldABunch()

        #expect(collector.values == [[user("@new:x.org")]])
        consumer.cancel()
    }

    // MARK: - deactivate (PRD 0.6, T8)

    @Test func deactivateRefusesAnOAuthSessionBeforeAnyUpstreamCall() async {
        let driver = FakeAccountDriver()
        let journal = Journal()
        let lifecycle = makeLifecycle(journal: journal)
        let service = makeService(driver, usesOAuth: true, lifecycle: lifecycle)

        await #expect { try await service.deactivate(password: "pw", eraseData: false) } throws: {
            isUnexpected($0)
        }

        #expect(driver.deactivations.isEmpty)
        #expect(journal.all.isEmpty)
        #expect(lifecycle.current == .signedIn)
    }

    @Test func deactivateRunsTheTwoStepPasswordExchange() async throws {
        let driver = FakeAccountDriver()
        driver.deactivationOutcomes = [ClientError.Generic(msg: "uiaa", details: nil), nil]
        let service = makeService(driver)

        try await service.deactivate(password: "pw", eraseData: true)

        #expect(
            driver.deactivations == [
                .init(authData: nil, eraseData: true),
                .init(
                    authData: .password(passwordDetails: .init(identifier: "@me:x.org", password: "pw")),
                    eraseData: true),
            ])
    }

    @Test func deactivateStopsAfterTheFirstCallWhenTheServerAcceptsItWithoutChallenge() async throws {
        let driver = FakeAccountDriver()
        let journal = Journal()
        let service = makeService(driver, lifecycle: makeLifecycle(journal: journal))

        try await service.deactivate(password: "pw", eraseData: false)

        #expect(driver.deactivations.count == 1)
        #expect(journal.all == ["stopSync", "erase while signedIn"])
    }

    @Test func deactivateSuccessErasesAndReportsSignedOut() async throws {
        let driver = FakeAccountDriver()
        driver.deactivationOutcomes = [ClientError.Generic(msg: "uiaa", details: nil), nil]
        let journal = Journal()
        let lifecycle = makeLifecycle(journal: journal)

        try await makeService(driver, lifecycle: lifecycle).deactivate(password: "pw", eraseData: false)

        #expect(journal.all == ["stopSync", "erase while signedIn"])
        #expect(lifecycle.current == .signedOut)
    }

    @Test func deactivateWithAWrongPasswordMapsToInvalidCredentialsAndErasesNothing() async {
        let driver = FakeAccountDriver()
        driver.deactivationOutcomes = [ClientError.Generic(msg: "uiaa", details: nil), forbidden]
        let journal = Journal()
        let lifecycle = makeLifecycle(journal: journal)
        let service = makeService(driver, lifecycle: lifecycle)

        await #expect(throws: MatrixError.authentication(.invalidCredentials)) {
            try await service.deactivate(password: "wrong", eraseData: false)
        }

        #expect(journal.all.isEmpty)
        #expect(lifecycle.current == .signedIn)
    }

    @Test func deactivateWithAUIAAForbiddenAuthErrorMapsToInvalidCredentials() async {
        let driver = FakeAccountDriver()
        driver.deactivationOutcomes = [ClientError.Generic(msg: "uiaa", details: nil), uiaaRefusal]
        let journal = Journal()
        let lifecycle = makeLifecycle(journal: journal)
        let service = makeService(driver, lifecycle: lifecycle)

        await #expect(throws: MatrixError.authentication(.invalidCredentials)) {
            try await service.deactivate(password: "wrong", eraseData: false)
        }

        #expect(journal.all.isEmpty)
        #expect(lifecycle.current == .signedIn)
    }

    @Test func deactivateKeepsAUIAAFailureWithoutAForbiddenAuthErrorUnexpected() async {
        let driver = FakeAccountDriver()
        let message = "the server returned an error: User-Interactive Authentication required."
        let details = "Api(Server(AuthResponse(UiaaInfo { flows: [], auth_error: None })))"
        driver.deactivationOutcomes = [
            ClientError.Generic(msg: "uiaa", details: nil), ClientError.Generic(msg: message, details: details),
        ]
        let service = makeService(driver, lifecycle: makeLifecycle(journal: Journal()))

        await #expect(throws: MatrixError.unexpected(message: message, details: details)) {
            try await service.deactivate(password: "pw", eraseData: false)
        }
    }

    @Test(arguments: [
        ClientError.MatrixApi(kind: .limitExceeded(retryAfterMs: nil), code: "M_LIMIT_EXCEEDED", msg: "", details: nil),
        ClientError.MatrixApi(kind: .unknownToken(softLogout: false), code: "M_UNKNOWN_TOKEN", msg: "", details: nil),
    ])
    func deactivateDoesNotRetryWithThePasswordWhenTheFirstCallFailsForAnotherReason(
        _ failure: ClientError
    ) async {
        let driver = FakeAccountDriver()
        driver.deactivationOutcomes = [failure]
        let journal = Journal()
        let lifecycle = makeLifecycle(journal: journal)
        let service = makeService(driver, lifecycle: lifecycle)

        await #expect(throws: MatrixError.self) {
            try await service.deactivate(password: "pw", eraseData: false)
        }

        #expect(driver.deactivations.count == 1)
        #expect(journal.all.isEmpty)
        #expect(lifecycle.current == .signedIn)
    }

    @Test func deactivateDoesNotRetryWithThePasswordWhenTheTaskIsCancelledDuringTheFirstCall() async {
        let driver = FakeAccountDriver()
        driver.deactivationOutcomes = [ClientError.Generic(msg: "uiaa", details: nil)]
        driver.deactivationHook = { withUnsafeCurrentTask { $0?.cancel() } }
        let journal = Journal()
        let service = makeService(driver, lifecycle: makeLifecycle(journal: journal))

        let task = Task { try await service.deactivate(password: "pw", eraseData: false) }
        _ = try? await task.value

        #expect(driver.deactivations.count == 1)
        #expect(journal.all.isEmpty)
    }

    @Test func deactivateDoesNotRetryWithThePasswordWhenTheFirstCallFailsOffline() async {
        let driver = FakeAccountDriver()
        driver.deactivationOutcomes = [ClientError.MatrixApi(kind: .connectionFailed, code: "", msg: "", details: nil)]
        let journal = Journal()
        let lifecycle = makeLifecycle(journal: journal)
        let service = makeService(driver, lifecycle: lifecycle)

        await #expect(throws: MatrixError.network(.offline)) {
            try await service.deactivate(password: "pw", eraseData: false)
        }

        #expect(driver.deactivations.count == 1)
        #expect(journal.all.isEmpty)
        #expect(lifecycle.current == .signedIn)
    }
}

private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [[UserID]] = []
    func append(_ value: [UserID]) { lock.withLock { _values.append(value) } }
    var values: [[UserID]] { lock.withLock { _values } }
}
