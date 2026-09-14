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
}
