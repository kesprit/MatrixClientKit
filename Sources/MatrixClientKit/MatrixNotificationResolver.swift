import MatrixClientKitCore
import MatrixClientKitRust

/// Resolves pushes into displayable notifications, from a notification service extension.
///
/// ```swift
/// let resolver = try await MatrixNotificationResolver(
///     storage: .appGroup("group.com.example.app", keychainAccessGroup: "TEAMID.com.example.app")
/// )
/// if let payload = MatrixPushPayload(userInfo: request.content.userInfo),
///    case .notification(let notification) = try await resolver.notification(
///        roomID: payload.roomID, eventID: payload.eventID) {
///     content.apply(notification)
/// }
/// ```
///
/// It opens the session the application persisted in the same App Group storage, and never
/// syncs. Keep the instance for the lifetime of the extension's process to reuse it across
/// pushes.
public final class MatrixNotificationResolver: NotificationContentResolving {
    private let resolver: RustNotificationResolver

    /// Opens the session persisted in `storage`.
    ///
    /// - Parameter storage: the application's storage. It must be an App Group storage: an
    ///   extension cannot reach the application's private directory.
    /// - Throws: ``MatrixError/authentication(_:)`` with
    ///   ``MatrixError/Authentication/missingToken`` when no session is stored — the user signed
    ///   out; ``MatrixError/storage(_:)`` with ``MatrixError/Storage/unavailable`` for a local
    ///   storage.
    public init(storage: MatrixStorage) async throws {
        resolver = try await RustNotificationResolver.open(storage: storage)
    }

    public func notification(roomID: RoomID, eventID: EventID) async throws -> NotificationResult {
        try await resolver.notification(roomID: roomID, eventID: eventID)
    }
}
