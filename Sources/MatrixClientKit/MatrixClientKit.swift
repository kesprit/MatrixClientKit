import Foundation
@_exported import MatrixClientKitCore
import MatrixClientKitRust

/// MatrixClientKit's entry point.
///
/// ```swift
/// let client = Matrix.client(
///     homeserver: URL(string: "https://matrix.org")!,
///     storage: .appGroup("group.com.example.app")
/// )
/// let session = try await client.login(.password(username: "alice", password: "…", deviceName: "iPhone"))
/// await session.sync.start()
///
/// for await rooms in session.rooms.list(filter: .joined) {
///     print(rooms.map(\.displayName))
/// }
/// ```
public enum Matrix: Sendable {

    /// Creates a client from what a user typically types on a sign-in screen: a server name
    /// (`matrix.org`), a homeserver URL, or a user ID (`@alice:matrix.org`).
    ///
    /// The homeserver is discovered through the server's `.well-known` information, which needs
    /// the network: ``MatrixClient/homeserver`` then holds the resolved address.
    ///
    /// - Throws: ``MatrixError/network(_:)`` when the server cannot be reached;
    ///   ``MatrixError/unexpected(message:details:)`` when the input is not a server, or its
    ///   discovery information cannot be read.
    public static func client(server: String, storage: MatrixStorage) async throws -> any MatrixClient {
        try await RustMatrixClient.discover(server: server, storage: storage)
    }

    /// Creates a client for a homeserver.
    ///
    /// - Parameters:
    ///   - homeserver: the homeserver's address, for instance `https://matrix.org`.
    ///   - storage: where persisted data lives. Use
    ///     ``MatrixStorage/appGroup(_:keychainAccessGroup:accessibility:)`` as soon as a
    ///     notification service extension needs to reach the same session.
    public static func client(
        homeserver: URL,
        storage: MatrixStorage
    ) -> any MatrixClient {
        RustMatrixClient(homeserver: homeserver, storage: storage)
    }

    /// Restores the persisted session, or returns `nil` when there is none.
    ///
    /// The homeserver's address is stored with the session, so this needs only the storage: call
    /// it at launch instead of keeping the homeserver URL a second time, where the two could
    /// disagree.
    ///
    /// ```swift
    /// if let session = try await Matrix.restoreSession(storage: .appGroup("group.com.example.app")) {
    ///     await session.sync.start()
    /// } else {
    ///     // Show the sign-in screen.
    /// }
    /// ```
    ///
    /// - Parameter storage: the storage the session was created with.
    /// - Throws: ``MatrixError/authentication(_:)`` when the homeserver rejects the stored session,
    ///   which is then erased; other errors leave it in place, so a launch without network does not
    ///   sign the user out.
    public static func restoreSession(storage: MatrixStorage) async throws -> (any MatrixSession)? {
        try await RustMatrixClient.restoreSession(storage: storage)
    }

    /// Signs this device in by scanning the QR code shown by a device already signed in to the
    /// account. The code says which homeserver to use.
    ///
    /// To show a QR code on this device instead, use ``MatrixClient/loginWithQRCode(_:)``.
    public static func loginWithQRCode(
        scanned: Data,
        configuration: OAuthConfiguration,
        storage: MatrixStorage
    ) -> any QRCodeLogin {
        RustMatrixClient.loginWithQRCode(scanned: scanned, configuration: configuration, storage: storage)
    }
}
