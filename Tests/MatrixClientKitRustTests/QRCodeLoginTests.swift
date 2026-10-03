import Testing
import Foundation
@testable import MatrixClientKitRust
import MatrixClientKitCore

// Mode scanné avec des octets illisibles : le flux échoue avant de construire le moindre client,
// ce qui teste le cycle de vie sans FFI réseau.

private let unreadable = Data([0, 1, 2])

private func newRoot() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mck-\(UUID().uuidString)")
}

private func makeLogin(root: URL, mode: RustQRCodeLogin.Mode = .scanned(unreadable)) -> RustQRCodeLogin {
    RustQRCodeLogin(
        restorer: SessionRestorer(storage: .local(directory: root), secureStore: InMemorySecureStore()),
        configuration: OAuthConfiguration(
            redirectURI: URL(string: "com.example.app:/callback")!, clientURI: URL(string: "https://example.com")!),
        mode: mode
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
    let login = makeLogin(root: root, mode: .display(.homeserver(URL(string: "https://matrix.invalid")!)))

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
