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
}
