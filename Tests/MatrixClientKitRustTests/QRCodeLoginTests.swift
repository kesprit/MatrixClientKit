import Testing
import Foundation
import Synchronization
import MatrixRustSDK
@testable import MatrixClientKitRust
import MatrixClientKitCore

// Mode scanné avec des octets illisibles : le flux échoue avant de construire le moindre client,
// ce qui teste le cycle de vie sans FFI réseau.

private let unreadable = Data([0, 1, 2])

private func newRoot() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mck-\(UUID().uuidString)")
}

private let homeserver = ClientTarget.homeserver(URL(string: "https://matrix.invalid")!)

private func makeLogin(
    root: URL,
    mode: RustQRCodeLogin.Mode = .scanned(unreadable),
    makeClient: RustQRCodeLogin.MakeClient? = nil
) -> RustQRCodeLogin {
    RustQRCodeLogin(
        restorer: SessionRestorer(storage: .local(directory: root), secureStore: InMemorySecureStore()),
        configuration: OAuthConfiguration(
            redirectURI: URL(string: "com.example.app:/callback")!, clientURI: URL(string: "https://example.com")!),
        mode: mode,
        makeClient: makeClient
    )
}

private func unexpectedMessage(of error: MatrixError?) -> String? {
    guard case let .unexpected(message, _) = error else { return nil }
    return message
}

@Test func anUnreadableScannedCodeFailsAsNotSupported() async {
    let login = makeLogin(root: newRoot())

    let error = await #expect(throws: MatrixError.self) { try await login.start() }

    #expect(unexpectedMessage(of: error) != nil)
    #expect(await login.state.first { _ in true } == .failed(.notSupported))
}

@Test func startingTwiceThrowsWithoutASecondRun() async {
    let login = makeLogin(root: newRoot())
    _ = try? await login.start()

    let error = await #expect(throws: MatrixError.self) { try await login.start() }

    #expect(unexpectedMessage(of: error) == "This QR-code login has already been started.")
}

@Test func cancellingBeforeStartingMakesStartThrowCancellation() async {
    let root = newRoot()
    let login = makeLogin(root: root, mode: .display(homeserver))

    login.cancel()

    #expect(await login.state.first { _ in true } == .failed(.cancelled))
    await #expect(throws: CancellationError.self) { try await login.start() }
    // Aucun store n'a été préparé.
    #expect(!FileManager.default.fileExists(atPath: root.path))
}

@Test func aCheckCodeOutsideEnterCheckCodeIsRejected() async {
    let login = makeLogin(root: newRoot())

    let error = await #expect(throws: MatrixError.self) { try await login.submitCheckCode(42) }

    #expect(unexpectedMessage(of: error) == "No check code is expected now.")
}

@Test func cancellingWhileTheClientIsBuiltPurgesTheStore() async throws {
    // Le flux et le répertoire du store, connus seulement une fois le client en construction.
    let login = Mutex<RustQRCodeLogin?>(nil)
    let storeDirectory = Mutex<URL?>(nil)
    let made = makeLogin(root: newRoot(), mode: .display(homeserver)) { _, localStore in
        storeDirectory.withLock { $0 = try? localStore.paths().storeDirectory }
        login.withLock { $0 }?.cancel()
        // Un client factice : le flux doit s'arrêter avant tout appel amont.
        return Client(noHandle: .init())
    }
    login.withLock { $0 = made }

    await #expect(throws: CancellationError.self) { try await made.start() }

    let directory = try #require(storeDirectory.withLock { $0 })
    #expect(!FileManager.default.fileExists(atPath: directory.path))
    #expect(await made.state.first { _ in true } == .failed(.cancelled))
}

// MARK: - Phases

@Test func theGateRefusesASecondStart() throws {
    let gate = QRCodeLoginGate<Int>()
    #expect(try gate.start { 1 } == 1)
    #expect(throws: QRCodeLoginGate<Int>.Refusal.alreadyStarted) { try gate.start { 2 } }
}

@Test func theGateRefusesAStartAfterCancellation() {
    let gate = QRCodeLoginGate<Int>()
    guard case .cancelled(run: nil) = gate.cancel() else {
        Issue.record("annulation refusée avant le démarrage")
        return
    }
    #expect(throws: QRCodeLoginGate<Int>.Refusal.cancelled) { try gate.start { 1 } }
    #expect(gate.isCancelled)
}

@Test func cancellingARunningLoginHandsBackTheRunAndForbidsTheCommit() throws {
    let gate = QRCodeLoginGate<Int>()
    _ = try gate.start { 7 }

    guard case .cancelled(run: 7) = gate.cancel() else {
        Issue.record("le déroulé en cours n'est pas rendu")
        return
    }
    #expect(!gate.commit())
}

@Test func cancellingIsRefusedOnceTheSessionIsBeingBuilt() throws {
    let gate = QRCodeLoginGate<Int>()
    _ = try gate.start { 7 }
    #expect(gate.commit())

    guard case .refused = gate.cancel() else {
        Issue.record("annulation acceptée pendant la construction de la session")
        return
    }
    #expect(!gate.isCancelled)
}
