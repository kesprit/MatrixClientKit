import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private final class Journal: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func append(_ entry: String) { lock.withLock { entries.append(entry) } }
    var all: [String] { lock.withLock { entries } }
}

/// Donne à la closure d'effacement accès au cycle de vie qu'elle sert, construit après elle.
private final class LifecycleRef: @unchecked Sendable {
    var lifecycle: SessionLifecycle?
}

private func makeLifecycle(
    journal: Journal,
    eraseError: (any Error)? = nil
) -> SessionLifecycle {
    let ref = LifecycleRef()
    let lifecycle = SessionLifecycle(
        stopSync: { journal.append("stopSync") },
        erase: {
            journal.append("erase while \(ref.lifecycle.map { "\($0.current)" } ?? "?")")
            if let eraseError { throw eraseError }
        }
    )
    ref.lifecycle = lifecycle
    return lifecycle
}

private let unknownToken = ClientError.MatrixApi(
    kind: .unknownToken(softLogout: true), code: "M_UNKNOWN_TOKEN", msg: "", details: nil
)

@Test func aHardLogoutErasesEverythingBeforeReportingSignedOut() async {
    let journal = Journal()
    let lifecycle = makeLifecycle(journal: journal)

    await lifecycle.handleAuthError(isSoftLogout: false)?.value

    // L'application qui voit `.signedOut` doit pouvoir compter sur un disque déjà propre.
    #expect(journal.all == ["stopSync", "erase while signedIn"])
    #expect(lifecycle.current == .signedOut)
}

@Test func aRepeatedHardLogoutIsHandledOnce() async {
    let journal = Journal()
    let lifecycle = makeLifecycle(journal: journal)

    let first = lifecycle.handleAuthError(isSoftLogout: false)
    let second = lifecycle.handleAuthError(isSoftLogout: false)
    await first?.value

    #expect(second == nil)
    #expect(journal.all.filter { $0.hasPrefix("erase") }.count == 1)
}

@Test func aFailedEraseStillReportsSignedOut() async {
    let journal = Journal()
    let lifecycle = makeLifecycle(journal: journal, eraseError: MatrixError.storage(.unavailable))

    await lifecycle.handleAuthError(isSoftLogout: false)?.value

    #expect(lifecycle.current == .signedOut)
}

@Test func aSoftLogoutErasesNothing() async {
    let journal = Journal()
    let lifecycle = makeLifecycle(journal: journal)

    #expect(lifecycle.handleAuthError(isSoftLogout: true) == nil)

    #expect(journal.all.isEmpty)
    #expect(lifecycle.current == .softLoggedOut)
}

@Test func signedOutIsTerminal() async {
    let lifecycle = makeLifecycle(journal: Journal())
    await lifecycle.handleAuthError(isSoftLogout: false)?.value

    lifecycle.handleAuthError(isSoftLogout: true)

    #expect(lifecycle.current == .signedOut)
}

@Test func subscribersSeeTheTransition() async {
    let lifecycle = makeLifecycle(journal: Journal())
    var iterator = lifecycle.authState.makeAsyncIterator()
    #expect(await iterator.next() == .signedIn)

    lifecycle.handleAuthError(isSoftLogout: true)
    #expect(await iterator.next() == .softLoggedOut)
}

@Test func logoutErasesAndSignsOut() async throws {
    let journal = Journal()
    let lifecycle = makeLifecycle(journal: journal)

    try await lifecycle.logout { journal.append("server") }

    #expect(journal.all == ["stopSync", "server", "erase while signedIn"])
    #expect(lifecycle.current == .signedOut)
}

@Test func logoutAfterASoftLogoutSwallowsTheExpectedTokenError() async throws {
    let journal = Journal()
    let lifecycle = makeLifecycle(journal: journal)
    lifecycle.handleAuthError(isSoftLogout: true)

    // Le jeton est déjà refusé par le serveur : lever ici ferait échouer une déconnexion aboutie.
    try await lifecycle.logout { throw unknownToken }

    #expect(journal.all == ["stopSync", "erase while softLoggedOut"])
    #expect(lifecycle.current == .signedOut)
}

@Test func logoutStillErasesThenRethrowsAnyOtherServerError() async {
    let journal = Journal()
    let lifecycle = makeLifecycle(journal: journal)

    await #expect(throws: MatrixError.network(.offline)) {
        try await lifecycle.logout {
            throw ClientError.MatrixApi(kind: .connectionFailed, code: "", msg: "", details: nil)
        }
    }

    // Un utilisateur qui se déconnecte hors ligne ne doit pas rester connecté localement.
    #expect(journal.all == ["stopSync", "erase while signedIn"])
    #expect(lifecycle.current == .signedOut)
}

@Test func logoutAfterSignedOutDoesNothing() async throws {
    let journal = Journal()
    let lifecycle = makeLifecycle(journal: journal)
    await lifecycle.handleAuthError(isSoftLogout: false)?.value

    try await lifecycle.logout { journal.append("server") }

    #expect(!journal.all.contains("server"))
    #expect(journal.all.filter { $0.hasPrefix("erase") }.count == 1)
}

@Test func theClientDelegateForwardsAuthErrors() {
    let lifecycle = makeLifecycle(journal: Journal())
    let delegate = AuthDelegate(lifecycle: lifecycle)

    delegate.didReceiveAuthError(isSoftLogout: true)

    #expect(lifecycle.current == .softLoggedOut)
}
