import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private let ownUserID = UserID(rawValue: "@alice:matrix.org")!

private enum ControllerCall: Equatable {
    case request, acknowledge(sender: String, flow: String), accept, startSAS, approve, decline, cancel
}

private final class FakeController: VerificationControllerDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [ControllerCall] = []
    private var _delegate: (any SessionVerificationControllerDelegate)?
    var failure: (any Error)?

    var calls: [ControllerCall] { lock.withLock { _calls } }
    var delegate: (any SessionVerificationControllerDelegate)? { lock.withLock { _delegate } }

    private func record(_ call: ControllerCall) throws {
        let failure = lock.withLock {
            _calls.append(call)
            return self.failure
        }
        if let failure { throw failure }
    }

    func setDelegate(delegate: (any SessionVerificationControllerDelegate)?) { lock.withLock { _delegate = delegate } }
    func requestDeviceVerification() async throws { try record(.request) }
    func acknowledgeVerificationRequest(senderId: String, flowId: String) async throws {
        try record(.acknowledge(sender: senderId, flow: flowId))
    }
    func acceptVerificationRequest() async throws { try record(.accept) }
    func startSasVerification() async throws { try record(.startSAS) }
    func approveVerification() async throws { try record(.approve) }
    func declineVerification() async throws { try record(.decline) }
    func cancelVerification() async throws { try record(.cancel) }
}

/// Contrôleur dont l'appel `gated` (par défaut `requestDeviceVerification`) suspend jusqu'à ce
/// que le test appelle ``release()`` — permet d'observer ce que fait une seconde commande
/// concurrente avant que la première n'ait obtenu de réponse de l'amont (fenêtre du double tap,
/// ou amont injoignable).
private final class GatedController: VerificationControllerDriving, @unchecked Sendable {
    private let lock = NSLock()
    private let gated: ControllerCall
    private var _calls: [ControllerCall] = []
    private var _delegate: (any SessionVerificationControllerDelegate)?
    private var continuation: CheckedContinuation<Void, Never>?

    init(gating gated: ControllerCall = .request) {
        self.gated = gated
    }

    var calls: [ControllerCall] { lock.withLock { _calls } }
    var delegate: (any SessionVerificationControllerDelegate)? { lock.withLock { _delegate } }
    var isSuspended: Bool { lock.withLock { continuation != nil } }

    func setDelegate(delegate: (any SessionVerificationControllerDelegate)?) { lock.withLock { _delegate = delegate } }

    private func record(_ call: ControllerCall) async {
        if call == gated {
            await withCheckedContinuation { continuation in
                lock.withLock { self.continuation = continuation }
            }
        }
        lock.withLock { _calls.append(call) }
    }

    /// Débloque l'appel amont en cours.
    func release() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume()
    }

    func requestDeviceVerification() async throws { await record(.request) }
    func acknowledgeVerificationRequest(senderId: String, flowId: String) async throws {
        await record(.acknowledge(sender: senderId, flow: flowId))
    }
    func acceptVerificationRequest() async throws { await record(.accept) }
    func startSasVerification() async throws { await record(.startSAS) }
    func approveVerification() async throws { await record(.approve) }
    func declineVerification() async throws { await record(.decline) }
    func cancelVerification() async throws { await record(.cancel) }
}

private final class FakeEmoji: SessionVerificationEmojiProtocol, @unchecked Sendable {
    let value: String
    let name: String
    init(_ value: String, _ name: String) { self.value = value; self.name = name }
    func symbol() -> String { value }
    func description() -> String { name }
}

private final class LoadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() -> Int {
        lock.withLock {
            count += 1; return count
        }
    }
    var value: Int { lock.withLock { count } }
}

private func details(from userID: String = "@alice:matrix.org", flow: String = "flow-1")
    -> SessionVerificationRequestDetails
{
    SessionVerificationRequestDetails(
        senderProfile: UserProfile(userId: userID, displayName: nil, avatarUrl: nil, status: nil, call: nil),
        flowId: flow,
        deviceId: "PHONE",
        deviceDisplayName: "iPhone",
        firstSeenTimestamp: 1_000
    )
}

private func makeVerification(_ controller: any VerificationControllerDriving) async throws -> RustSessionVerification {
    let verification = RustSessionVerification(ownUserID: ownUserID, loadController: { controller })
    try await verification.ensureController()
    return verification
}

/// Attend le premier état satisfaisant `predicate` ; la borne de temps du test fait échouer une
/// attente qui n'aboutit jamais.
private func waitForState(
    _ verification: RustSessionVerification,
    where predicate: (SessionVerificationState) -> Bool
) async -> SessionVerificationState? {
    for await state in verification.state where predicate(state) {
        return state
    }
    return nil
}

@Test(.timeLimit(.minutes(1)))
func anIncomingRequestReachesALateSubscriber() async throws {
    let controller = FakeController()
    let verification = try await makeVerification(controller)

    controller.delegate?.didReceiveVerificationRequest(details: details())

    // Abonnement postérieur à la demande : l'instantané doit la contenir.
    var iterator = verification.state.makeAsyncIterator()
    guard case let .incomingRequest(request) = await iterator.next() else {
        Issue.record("la demande entrante doit être l'état courant")
        return
    }
    #expect(request.id == "flow-1")
    #expect(request.deviceID.rawValue == "PHONE")
    #expect(request.firstSeen == Date(timeIntervalSince1970: 1))
}

@Test func aRequestFromAnotherUserIsIgnored() async throws {
    let controller = FakeController()
    let verification = try await makeVerification(controller)

    controller.delegate?.didReceiveVerificationRequest(details: details(from: "@mallory:matrix.org"))

    var iterator = verification.state.makeAsyncIterator()
    #expect(await iterator.next() == .idle)
}

@Test func theOutgoingFlowRunsToVerified() async throws {
    let controller = FakeController()
    let verification = try await makeVerification(controller)

    try await verification.requestVerification()
    #expect(await waitForState(verification) { $0 == .waitingForOtherDevice } != nil)

    controller.delegate?.didAcceptVerificationRequest()
    try await verification.startSAS()
    controller.delegate?.didReceiveVerificationData(data: .decimals(values: [1, 2, 3]))
    #expect(await waitForState(verification) { $0 == .comparing(.decimals([1, 2, 3])) } != nil)

    try await verification.approve()
    #expect(await waitForState(verification) { $0 == .confirming } != nil)

    controller.delegate?.didFinish()
    #expect(await waitForState(verification) { $0 == .verified } != nil)

    #expect(controller.calls == [.request, .startSAS, .approve])
}

@Test func acceptingAcknowledgesTheRequestFirst() async throws {
    let controller = FakeController()
    let verification = try await makeVerification(controller)
    controller.delegate?.didReceiveVerificationRequest(details: details(flow: "flow-9"))

    try await verification.accept()

    #expect(controller.calls == [.acknowledge(sender: "@alice:matrix.org", flow: "flow-9"), .accept])
}

@Test func cancellingAnIncomingRequestAcknowledgesItFirst() async throws {
    let controller = FakeController()
    let verification = try await makeVerification(controller)
    controller.delegate?.didReceiveVerificationRequest(details: details(flow: "flow-3"))

    try await verification.cancel()

    #expect(controller.calls == [.acknowledge(sender: "@alice:matrix.org", flow: "flow-3"), .cancel])
    #expect(await waitForState(verification) { $0 == .cancelled } != nil)
}

@Test func aCommandOutsideItsStateThrowsWithoutCallingUpstream() async throws {
    let controller = FakeController()
    let verification = try await makeVerification(controller)

    let error = await #expect(throws: MatrixError.self) {
        try await verification.approve()
    }
    guard case .unexpected = error else {
        Issue.record("attendu .unexpected, obtenu \(String(describing: error))")
        return
    }
    #expect(controller.calls.isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func aConcurrentCommandWhileOneIsInFlightIsRejected() async throws {
    let controller = GatedController()
    let verification = try await makeVerification(controller)

    async let first: Void = verification.requestVerification()

    // Laisse la première commande atteindre son appel amont suspendu avant d'en tenter une
    // seconde : c'est exactement la fenêtre qu'un double tap exploite.
    while !controller.isSuspended {
        await Task.yield()
    }

    let error = await #expect(throws: MatrixError.self) {
        try await verification.requestVerification()
    }
    guard case .unexpected = error else {
        Issue.record("attendu .unexpected, obtenu \(String(describing: error))")
        return
    }

    controller.release()
    try await first

    #expect(controller.calls == [.request])
    #expect(await waitForState(verification) { $0 == .waitingForOtherDevice } != nil)
}

@Test(.timeLimit(.minutes(1)))
func cancelIsNotRejectedWhileAnotherCommandIsInFlight() async throws {
    let controller = GatedController(gating: .startSAS)
    let verification = try await makeVerification(controller)
    try await verification.requestVerification()
    controller.delegate?.didAcceptVerificationRequest()
    #expect(await waitForState(verification) { $0 == .ready } != nil)

    async let start: Void = verification.startSAS()

    // `startSAS()` attend l'amont (hors ligne, par exemple) : l'utilisateur doit pouvoir annuler.
    while !controller.isSuspended {
        await Task.yield()
    }

    // L'erreur éventuelle est retenue le temps de débloquer l'amont : levée tout de suite, elle
    // laisserait `startSAS()` suspendu pour toujours.
    var cancelError: (any Error)?
    do {
        try await verification.cancel()
    } catch {
        cancelError = error
    }
    controller.release()
    try await start

    #expect(cancelError == nil)
    #expect(controller.calls.contains(.cancel))
}

@Test func anUpstreamFailureIsMappedAndLeavesTheStateUnchanged() async throws {
    let controller = FakeController()
    controller.failure = ClientError.MatrixApi(kind: .connectionFailed, code: "", msg: "", details: nil)
    let verification = try await makeVerification(controller)

    await #expect(throws: MatrixError.network(.offline)) {
        try await verification.requestVerification()
    }
    var iterator = verification.state.makeAsyncIterator()
    #expect(await iterator.next() == .idle)
}

@Test func loadingTheControllerIsRetriedByTheNextCommand() async throws {
    let controller = FakeController()
    let attempts = LoadCounter()
    let verification = RustSessionVerification(
        ownUserID: ownUserID,
        loadController: {
            // Première tentative : identité pas encore chargée, comme avant la première sync.
            if attempts.increment() == 1 {
                throw ClientError.Generic(msg: "Failed retrieving user identity", details: nil)
            }
            return controller
        })

    await #expect(throws: MatrixError.self) {
        try await verification.requestVerification()
    }
    #expect(!verification.hasController)

    try await verification.requestVerification()
    #expect(verification.hasController)
    #expect(attempts.value == 2)
    #expect(controller.delegate != nil)
}

@Test func theControllerIsLoadedOnlyOnce() async throws {
    let controller = FakeController()
    let attempts = LoadCounter()
    let verification = RustSessionVerification(
        ownUserID: ownUserID,
        loadController: {
            _ = attempts.increment()
            return controller
        })

    try await verification.ensureController()
    try await verification.ensureController()
    try await verification.requestVerification()

    #expect(attempts.value == 1)
}

@Test func emojisAreMappedWithTheirSpecIndices() {
    let data = VerificationMapper.sasData(
        emojis: [FakeEmoji("🐶", "Dog"), FakeEmoji("🔑", "Key")],
        indices: Data([0, 44])
    )
    #expect(
        data
            == .emojis([
                SASEmoji(symbol: "🐶", description: "Dog", index: 0),
                SASEmoji(symbol: "🔑", description: "Key", index: 44),
            ]))
}

@Test func aMissingEmojiIndexIsNil() {
    let data = VerificationMapper.sasData(emojis: [FakeEmoji("🐶", "Dog")], indices: Data())
    #expect(data == .emojis([SASEmoji(symbol: "🐶", description: "Dog", index: nil)]))
}
