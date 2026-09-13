import Foundation
@_exported import MatrixClientKitCore
import MatrixClientKitRust

/// Point d'entrée de MatrixClientKit.
///
/// ```swift
/// let client = Matrix.client(
///     homeserver: URL(string: "https://matrix.org")!,
///     storage: .appGroup("group.com.exemple.app")
/// )
/// let session = try await client.login(.password(username: "alice", password: "…", deviceName: "iPhone"))
/// await session.sync.start()
///
/// for await rooms in session.rooms.list(filter: .joined) {
///     print(rooms.map(\.displayName))
/// }
/// ```
public enum Matrix: Sendable {

    /// Crée un client rattaché à un homeserver.
    ///
    /// - Parameters:
    ///   - homeserver: adresse du homeserver, par exemple `https://matrix.org`.
    ///   - storage: emplacement des données persistées. Utiliser
    ///     ``MatrixStorage/appGroup(_:keychainAccessGroup:accessibility:)`` dès lors qu'une
    ///     extension de notification doit accéder à la même session.
    public static func client(
        homeserver: URL,
        storage: MatrixStorage
    ) -> any MatrixClient {
        RustMatrixClient(homeserver: homeserver, storage: storage)
    }
}
