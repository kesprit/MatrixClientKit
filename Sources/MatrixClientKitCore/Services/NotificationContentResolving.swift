/// Resolves a push into a displayable notification, from a notification service extension.
///
/// It never syncs: syncing from the extension, while the application may be syncing the same
/// store, corrupts the application's state.
public protocol NotificationContentResolving: Sendable {
    /// Fetches and decrypts the event a push is about.
    ///
    /// - Throws: a ``MatrixError`` when the notification cannot be resolved — display the push's
    ///   original content instead.
    func notification(roomID: RoomID, eventID: EventID) async throws -> NotificationResult
}
