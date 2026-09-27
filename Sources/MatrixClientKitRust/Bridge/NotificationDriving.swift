import MatrixRustSDK

/// Sous-ensemble de `Client` dont le service de notification a besoin pour le pusher.
///
/// Couture de testabilité : `Client` est une classe FFI qu'un test ne peut pas construire.
protocol PusherDriving: Sendable {
    func setPusher(
        identifiers: PusherIdentifiers,
        kind: PusherKind,
        appDisplayName: String,
        deviceDisplayName: String,
        profileTag: String?,
        lang: String,
        append: Bool
    ) async throws
    func deletePusher(identifiers: PusherIdentifiers) async throws
}

extension Client: PusherDriving {}

/// Sous-ensemble de `NotificationSettings` utilisé en 0.3 : le mode par salon. Le protocole amont
/// impose une vingtaine de méthodes hors périmètre.
protocol NotificationSettingsDriving: Sendable {
    func getRoomNotificationSettings(
        roomId: String,
        isEncrypted: Bool,
        isOneToOne: Bool
    ) async throws -> MatrixRustSDK.RoomNotificationSettings
    func setRoomNotificationMode(roomId: String, mode: MatrixRustSDK.RoomNotificationMode) async throws
    func restoreDefaultRoomNotificationMode(roomId: String) async throws
}

extension NotificationSettings: NotificationSettingsDriving {}

/// Sous-ensemble de `NotificationClient` utilisé par l'extension.
protocol NotificationClientDriving: Sendable {
    func getNotification(roomId: String, eventId: String) async throws -> NotificationStatus
}

extension NotificationClient: NotificationClientDriving {}

/// Ce que l'amont exige de savoir d'un salon pour en lire le réglage de notification.
struct RoomFacts: Sendable, Equatable {
    let isEncrypted: Bool
    let isOneToOne: Bool
}
