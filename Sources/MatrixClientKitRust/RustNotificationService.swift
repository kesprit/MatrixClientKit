import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``NotificationService`` adossée au SDK Rust.
public final class RustNotificationService: NotificationService {
    private let pushers: any PusherDriving
    private let settings: any NotificationSettingsDriving
    /// Résout les faits d'un salon à partir de son identifiant ; `nil` pour un salon inconnu.
    private let roomFacts: @Sendable (String) async throws -> RoomFacts?

    init(
        pushers: any PusherDriving,
        settings: any NotificationSettingsDriving,
        roomFacts: @escaping @Sendable (String) async throws -> RoomFacts?
    ) {
        self.pushers = pushers
        self.settings = settings
        self.roomFacts = roomFacts
    }

    public func registerPusher(_ configuration: PusherConfiguration) async throws {
        do {
            try await pushers.setPusher(
                identifiers: Self.identifiers(for: configuration),
                kind: .http(
                    data: HttpPusherData(
                        url: configuration.gatewayURL.absoluteString,
                        // Seul format amont, et le seul qui ne fait pas transiter le contenu par Apple.
                        format: .eventIdOnly,
                        defaultPayload: try configuration.defaultPayload()
                    )
                ),
                appDisplayName: configuration.appDisplayName,
                deviceDisplayName: configuration.deviceDisplayName,
                profileTag: nil,
                lang: configuration.language,
                // `false` : le homeserver retire les pushers d'autres comptes au même jeton, ce
                // qu'on veut après un changement de compte sur l'appareil.
                append: false
            )
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    public func unregisterPusher(_ configuration: PusherConfiguration) async throws {
        do {
            try await pushers.deletePusher(identifiers: Self.identifiers(for: configuration))
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    public func notificationSettings(for roomID: RoomID) async throws -> MatrixClientKitCore.RoomNotificationSettings {
        do {
            guard let facts = try await roomFacts(roomID.rawValue) else {
                throw MatrixError.notFound(.room)
            }
            let upstream = try await settings.getRoomNotificationSettings(
                roomId: roomID.rawValue,
                isEncrypted: facts.isEncrypted,
                isOneToOne: facts.isOneToOne
            )
            return NotificationMapper.settings(from: upstream)
        } catch {
            throw NotificationMapper.error(from: error)
        }
    }

    public func setNotificationMode(
        _ mode: MatrixClientKitCore.RoomNotificationMode,
        for roomID: RoomID
    ) async throws {
        do {
            try await settings.setRoomNotificationMode(
                roomId: roomID.rawValue,
                mode: NotificationMapper.upstreamMode(from: mode)
            )
        } catch {
            throw NotificationMapper.error(from: error)
        }
    }

    public func restoreDefaultNotificationMode(for roomID: RoomID) async throws {
        do {
            try await settings.restoreDefaultRoomNotificationMode(roomId: roomID.rawValue)
        } catch {
            throw NotificationMapper.error(from: error)
        }
    }

    private static func identifiers(for configuration: PusherConfiguration) -> PusherIdentifiers {
        PusherIdentifiers(pushkey: configuration.pushKey, appId: configuration.appID)
    }
}
