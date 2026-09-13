import Foundation
import MatrixClientKitCore

/// Session authentifiée pilotable pour les tests : expose un ``MockRoomService`` et un
/// ``MockSyncController`` prêts à l'emploi, et enregistre les appels à ``logout()``.
public final class MockMatrixSession: MatrixSession, @unchecked Sendable {
    private let lock = NSLock()

    public let userID: UserID
    public let deviceID: DeviceID
    public let rooms: any RoomService
    public let sync: any SyncController

    private var _didLogout = false

    /// Vrai si ``logout()`` a été appelé.
    public var didLogout: Bool {
        lock.lock(); defer { lock.unlock() }
        return _didLogout
    }

    public init(
        userID: String = "@alice:matrix.org",
        deviceID: String = "DEV1",
        rooms: MockRoomService = MockRoomService(),
        sync: MockSyncController = MockSyncController()
    ) {
        self.userID = UserID(rawValue: userID) ?? UserID(rawValue: "@alice:matrix.org")!
        self.deviceID = DeviceID(rawValue: deviceID) ?? DeviceID(rawValue: "DEV1")!
        self.rooms = rooms
        self.sync = sync
    }

    public func logout() async throws {
        lock.withLock { _didLogout = true }
    }
}
