/// Push notifications for a session: this device's pusher, and how much each room notifies.
public protocol NotificationService: Sendable {
    /// Registers this device with the homeserver, so that it pushes notifications to it through
    /// the gateway.
    ///
    /// Call it every time the application receives a device token — tokens change. It replaces
    /// any pusher registered before for the same token and application identifier. The pusher
    /// asks APNs to wake the notification service extension, which then resolves the content
    /// with ``NotificationContentResolving``: the message itself never goes through Apple.
    func registerPusher(_ configuration: PusherConfiguration) async throws

    /// Stops pushes to this device for this token and application identifier.
    ///
    /// Signing out removes this device's pushers server-side: there is no need to call this
    /// before ``MatrixSession/logout()``.
    func unregisterPusher(_ configuration: PusherConfiguration) async throws

    /// The room's notification setting.
    ///
    /// - Throws: ``MatrixError/notFound(_:)`` with ``MatrixError/Resource/room`` when the room is
    ///   not known to this session yet.
    func notificationSettings(for roomID: RoomID) async throws -> RoomNotificationSettings

    /// Sets how much the room notifies, overriding the account's default for it.
    func setNotificationMode(_ mode: RoomNotificationMode, for roomID: RoomID) async throws

    /// Removes the room's own setting, so that the account's default applies again.
    func restoreDefaultNotificationMode(for roomID: RoomID) async throws
}
