import Foundation
import MatrixClientKitCore

/// A drivable authenticated session for tests: exposes a ready-made ``MockRoomService`` and
/// ``MockSyncController``, and records calls to ``logout()``.
public final class MockMatrixSession: MatrixSession, @unchecked Sendable {
    private let lock = NSLock()

    public let userID: UserID
    public let deviceID: DeviceID
    public let rooms: any RoomService
    public let sync: any SyncController

    private var _didLogout = false

    /// True once ``logout()`` has been called.
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
