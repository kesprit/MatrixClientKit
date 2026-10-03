import Testing
import Foundation
import Synchronization
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

@Test func aSoftLogoutArrivingDuringTheServerCallStillSwallowsTheTokenError() async throws {
    let journal = Journal()
    let lifecycle = makeLifecycle(journal: journal)

    // Le soft logout arrive pendant l'appel serveur, après le début de `logout()`.
    try await lifecycle.logout {
        lifecycle.handleAuthError(isSoftLogout: true)
        throw unknownToken
    }

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

/// Porte franchie par `stopSync`, pour figer une terminaison en plein vol le temps que le test
/// vérifie qu'un `logout()` concurrent attend plutôt que de rendre la main en avance.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    var isSuspended: Bool { lock.withLock { continuation != nil } }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.withLock { self.continuation = continuation }
        }
    }

    func release() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume()
    }
}

@Test(.timeLimit(.minutes(1)))
func aLogoutConcurrentWithAnInFlightHardLogoutWaitsForItInsteadOfReturningEarly() async throws {
    let journal = Journal()
    let gate = Gate()
    let ref = LifecycleRef()
    let lifecycle = SessionLifecycle(
        stopSync: {
            journal.append("stopSync")
            await gate.wait()
        },
        erase: {
            journal.append("erase while \(ref.lifecycle.map { "\($0.current)" } ?? "?")")
        }
    )
    ref.lifecycle = lifecycle

    let hardLogout = lifecycle.handleAuthError(isSoftLogout: false)

    // Laisse le hard logout atteindre son arrêt de sync suspendu avant de tenter un logout()
    // concurrent : c'est exactement la fenêtre où l'ancien code rendait la main trop tôt.
    while !gate.isSuspended {
        await Task.yield()
    }

    let logout = Task {
        try await lifecycle.logout { journal.append("server") }
        journal.append("logoutReturned")
    }

    // Cède la main un grand nombre de fois : un `logout()` bogué qui rendrait la main tout de
    // suite (sans `await` avant son `return` anticipé) aurait largement eu l'occasion de finir
    // et d'ajouter "logoutReturned" pendant cette boucle.
    for _ in 0..<50 {
        await Task.yield()
    }

    // Tant que le hard logout n'a pas fini d'effacer et de publier .signedOut, le logout()
    // perdant doit rester suspendu au lieu de rendre la main avec un état encore périmé.
    #expect(!journal.all.contains("logoutReturned"))
    #expect(lifecycle.current != .signedOut)

    gate.release()
    await hardLogout?.value
    try await logout.value

    #expect(!journal.all.contains("server"))
    #expect(journal.all.filter { $0.hasPrefix("erase") }.count == 1)
    #expect(lifecycle.current == .signedOut)
}

// MARK: - Reconnexion (spec 0.4, §5.5)

/// Cède la main assez de fois pour qu'une tâche qui n'attendrait pas la fin de la reconnexion
/// ait largement le temps d'aller au bout.
private func yieldABunch() async {
    for _ in 0..<50 {
        await Task.yield()
    }
}

private func softLoggedOutLifecycle(journal: Journal) -> SessionLifecycle {
    let lifecycle = makeLifecycle(journal: journal)
    lifecycle.handleAuthError(isSoftLogout: true)
    return lifecycle
}

@Test func reauthenticationRequiresASoftLogout() {
    let lifecycle = makeLifecycle(journal: Journal())
    #expect(throws: MatrixError.self) { try lifecycle.reserveForReauthentication() }
    lifecycle.handleAuthError(isSoftLogout: true)
    #expect(throws: Never.self) { try lifecycle.reserveForReauthentication() }
}

@Test func aSecondReservationIsRefused() throws {
    let lifecycle = softLoggedOutLifecycle(journal: Journal())
    try lifecycle.reserveForReauthentication()

    // Deux reconnexions concurrentes construiraient deux clients sur un même store.
    #expect(throws: MatrixError.self) { try lifecycle.reserveForReauthentication() }
}

@Test func aReleasedReservationCanBeTakenAgain() throws {
    let lifecycle = softLoggedOutLifecycle(journal: Journal())
    try lifecycle.reserveForReauthentication()
    lifecycle.releaseReauthentication()

    #expect(throws: Never.self) { try lifecycle.reserveForReauthentication() }
}

@Test func aFailedReauthenticationLeavesTheSessionSoftLoggedOutAndIntact() async throws {
    let journal = Journal()
    let lifecycle = softLoggedOutLifecycle(journal: journal)
    try lifecycle.reserveForReauthentication()
    await lifecycle.stopSyncForReplacement()

    lifecycle.releaseReauthentication()

    #expect(lifecycle.current == .softLoggedOut)
    #expect(!journal.all.contains { $0.hasPrefix("erase") })
    #expect(throws: Never.self) { try lifecycle.reserveForReauthentication() }
}

@Test func aReplacedSessionEndsSignedOutWithoutErasing() throws {
    let journal = Journal()
    let lifecycle = softLoggedOutLifecycle(journal: journal)
    try lifecycle.reserveForReauthentication()

    lifecycle.markReplaced()

    #expect(lifecycle.current == .signedOut)
    #expect(!journal.all.contains { $0.hasPrefix("erase") })
}

@Test func logoutOnAReplacedSessionErasesNothingAndCallsNoServer() async throws {
    let journal = Journal()
    let lifecycle = softLoggedOutLifecycle(journal: journal)
    try lifecycle.reserveForReauthentication()
    lifecycle.markReplaced()

    try await lifecycle.logout { journal.append("server") }

    #expect(journal.all.isEmpty)
}

@Test func aLateHardLogoutOnAReplacedSessionErasesNothing() async throws {
    let journal = Journal()
    let lifecycle = softLoggedOutLifecycle(journal: journal)
    try lifecycle.reserveForReauthentication()
    lifecycle.markReplaced()

    await lifecycle.handleAuthError(isSoftLogout: false)?.value

    #expect(journal.all.isEmpty)
    #expect(lifecycle.current == .signedOut)
}

@Test(.timeLimit(.minutes(1)))
func aLogoutDuringAReauthenticationWaitsAndThenDoesNothingOnceReplaced() async throws {
    let journal = Journal()
    let lifecycle = softLoggedOutLifecycle(journal: journal)
    try lifecycle.reserveForReauthentication()

    let logout = Task {
        try await lifecycle.logout { journal.append("server") }
        journal.append("logoutReturned")
    }
    await yieldABunch()

    // Le store appartient peut-être déjà à la remplaçante : rien ne doit l'effacer avant l'issue.
    #expect(journal.all.isEmpty)

    lifecycle.markReplaced()
    try await logout.value

    #expect(journal.all == ["logoutReturned"])
    #expect(lifecycle.current == .signedOut)
}

@Test(.timeLimit(.minutes(1)))
func aHardLogoutDuringAReauthenticationWaitsAndThenDoesNothingOnceReplaced() async throws {
    let journal = Journal()
    let lifecycle = softLoggedOutLifecycle(journal: journal)
    try lifecycle.reserveForReauthentication()

    let hardLogout = lifecycle.handleAuthError(isSoftLogout: false)
    await yieldABunch()
    #expect(journal.all.isEmpty)

    lifecycle.markReplaced()
    await hardLogout?.value

    #expect(journal.all.isEmpty)
    #expect(lifecycle.current == .signedOut)
}

@Test(.timeLimit(.minutes(1)))
func terminationsWaitingOnAFailedReauthenticationRunOnceItIsReleased() async throws {
    let journal = Journal()
    let lifecycle = softLoggedOutLifecycle(journal: journal)
    try lifecycle.reserveForReauthentication()

    let hardLogout = lifecycle.handleAuthError(isSoftLogout: false)
    let logout = Task { try await lifecycle.logout { journal.append("server") } }
    await yieldABunch()
    #expect(journal.all.isEmpty)

    lifecycle.releaseReauthentication()
    await hardLogout?.value
    try await logout.value

    #expect(journal.all.filter { $0.hasPrefix("erase") }.count == 1)
    #expect(journal.all.filter { $0 == "stopSync" }.count == 1)
    #expect(lifecycle.current == .signedOut)
}

@Test(.timeLimit(.minutes(1)))
func aReservationIsRefusedWhileATerminationIsInFlight() async throws {
    let journal = Journal()
    let gate = Gate()
    let lifecycle = SessionLifecycle(
        stopSync: {
            journal.append("stopSync")
            await gate.wait()
        },
        erase: { journal.append("erase") }
    )
    lifecycle.handleAuthError(isSoftLogout: true)
    let hardLogout = lifecycle.handleAuthError(isSoftLogout: false)
    while !gate.isSuspended {
        await Task.yield()
    }

    // L'état publié est encore `.softLoggedOut`, mais l'effacement est déjà promis.
    #expect(lifecycle.current == .softLoggedOut)
    #expect(throws: MatrixError.self) { try lifecycle.reserveForReauthentication() }

    gate.release()
    await hardLogout?.value
    #expect(journal.all == ["stopSync", "erase"])
}

// MARK: - Reconnexion OAuth annulée par une terminaison

/// Le crochet d'annulation d'un flux OAuth de reconnexion, comme le pose
/// `beginOAuthReauthentication` : `cancel()` du flux, dont l'issue rend la réservation.
private func cancelHook(_ lifecycle: SessionLifecycle, journal: Journal) -> @Sendable () async -> Void {
    { [weak lifecycle] in
        journal.append("cancel")
        lifecycle?.releaseReauthentication()
    }
}

@Test(.timeLimit(.minutes(1)))
func aLogoutCancelsAPendingOAuthReauthenticationThenTerminatesOnce() async throws {
    let journal = Journal()
    let lifecycle = softLoggedOutLifecycle(journal: journal)
    try lifecycle.reserveForReauthentication()
    #expect(lifecycle.registerReauthenticationCancel(cancelHook(lifecycle, journal: journal)))

    // Un flux gardé par l'application sans jamais être conclu ferait attendre `logout()` sans fin.
    try await lifecycle.logout { journal.append("server") }

    #expect(journal.all.filter { $0 == "cancel" }.count == 1)
    #expect(journal.all.filter { $0 == "server" }.count == 1)
    #expect(journal.all.filter { $0.hasPrefix("erase") }.count == 1)
    #expect(journal.all.first == "cancel")
    #expect(lifecycle.current == .signedOut)
}

@Test(.timeLimit(.minutes(1)))
func aHardLogoutCancelsAPendingOAuthReauthenticationThenTerminatesOnce() async throws {
    let journal = Journal()
    let lifecycle = softLoggedOutLifecycle(journal: journal)
    try lifecycle.reserveForReauthentication()
    #expect(lifecycle.registerReauthenticationCancel(cancelHook(lifecycle, journal: journal)))

    let hardLogout = lifecycle.handleAuthError(isSoftLogout: false)
    let logout = Task { try await lifecycle.logout { journal.append("server") } }
    await hardLogout?.value
    try await logout.value

    #expect(journal.all.filter { $0 == "cancel" }.count == 1)
    #expect(journal.all.filter { $0.hasPrefix("erase") }.count == 1)
    #expect(journal.all.filter { $0 == "stopSync" }.count == 1)
    #expect(lifecycle.current == .signedOut)
}

@Test(.timeLimit(.minutes(1)))
func aTerminationRequestedBeforeTheHookIsRegisteredRefusesIt() async throws {
    let journal = Journal()
    let lifecycle = softLoggedOutLifecycle(journal: journal)
    try lifecycle.reserveForReauthentication()

    // Le flux n'existe pas encore (URL d'autorisation en cours d'obtention) quand `logout()` arrive.
    let logout = Task { try await lifecycle.logout { journal.append("server") } }
    await yieldABunch()
    #expect(journal.all.isEmpty)

    // Refusé : c'est à l'appelant d'annuler le flux qu'il vient d'ouvrir, comme le fait
    // `beginOAuthReauthentication`.
    let hook = cancelHook(lifecycle, journal: journal)
    let registered = lifecycle.registerReauthenticationCancel(hook)
    #expect(!registered)
    #expect(journal.all.isEmpty)
    if !registered { await hook() }
    try await logout.value

    #expect(journal.all.filter { $0 == "cancel" }.count == 1)
    #expect(journal.all.filter { $0.hasPrefix("erase") }.count == 1)
    #expect(lifecycle.current == .signedOut)
}

@Test(.timeLimit(.minutes(1)))
func aLogoutStillWaitsForAReauthenticationWithoutCancelHook() async throws {
    let journal = Journal()
    let lifecycle = softLoggedOutLifecycle(journal: journal)
    try lifecycle.reserveForReauthentication()

    // Une reconnexion par identifiants n'a pas de crochet : son appel réseau la borne.
    let logout = Task {
        try await lifecycle.logout { journal.append("server") }
        journal.append("logoutReturned")
    }
    await yieldABunch()
    #expect(journal.all.isEmpty)

    lifecycle.releaseReauthentication()
    try await logout.value

    #expect(journal.all.filter { $0.hasPrefix("erase") }.count == 1)
    #expect(journal.all.last == "logoutReturned")
}
