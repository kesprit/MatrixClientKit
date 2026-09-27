import Foundation
import MatrixClientKitCore

/// A drivable ``NotificationService``: records pushers and room modes, and fails on demand.
public final class MockNotificationService: NotificationService, @unchecked Sendable {
    private let lock = NSLock()

    private var _registeredPushers: [PusherConfiguration] = []
    private var _unregisteredPushers: [PusherConfiguration] = []
    private var _settings: [RoomID: RoomNotificationSettings] = [:]
    private var _defaultSettings = RoomNotificationSettings(mode: .allMessages, isDefault: true)
    private var _registerError: MatrixError?
    private var _unregisterError: MatrixError?
    private var _settingsError: MatrixError?

    public init() {}

    /// The configurations passed to ``registerPusher(_:)`` that succeeded, in order.
    public var registeredPushers: [PusherConfiguration] { lock.withLock { _registeredPushers } }

    /// The configurations passed to ``unregisterPusher(_:)`` that succeeded, in order.
    public var unregisteredPushers: [PusherConfiguration] { lock.withLock { _unregisteredPushers } }

    /// What ``notificationSettings(for:)`` returns for a room given no setting of its own through
    /// ``setSettings(_:for:)``. Initially `.allMessages` with `isDefault` set to `true`.
    public var defaultSettings: RoomNotificationSettings {
        get { lock.withLock { _defaultSettings } }
        set { lock.withLock { _defaultSettings = newValue } }
    }

    /// The error ``registerPusher(_:)`` throws. `nil` by default.
    public var registerError: MatrixError? {
        get { lock.withLock { _registerError } }
        set { lock.withLock { _registerError = newValue } }
    }

    /// The error ``unregisterPusher(_:)`` throws. `nil` by default.
    public var unregisterError: MatrixError? {
        get { lock.withLock { _unregisterError } }
        set { lock.withLock { _unregisterError = newValue } }
    }

    /// The error the three room-setting methods throw. `nil` by default.
    public var settingsError: MatrixError? {
        get { lock.withLock { _settingsError } }
        set { lock.withLock { _settingsError = newValue } }
    }

    /// Sets what ``notificationSettings(for:)`` reports for a room.
    public func setSettings(_ settings: RoomNotificationSettings, for roomID: RoomID) {
        lock.withLock { _settings[roomID] = settings }
    }

    public func registerPusher(_ configuration: PusherConfiguration) async throws {
        try lock.withLock {
            if let error = _registerError { throw error }
            _registeredPushers.append(configuration)
        }
    }

    public func unregisterPusher(_ configuration: PusherConfiguration) async throws {
        try lock.withLock {
            if let error = _unregisterError { throw error }
            _unregisteredPushers.append(configuration)
        }
    }

    public func notificationSettings(for roomID: RoomID) async throws -> RoomNotificationSettings {
        try lock.withLock {
            if let error = _settingsError { throw error }
            return _settings[roomID] ?? _defaultSettings
        }
    }

    public func setNotificationMode(_ mode: RoomNotificationMode, for roomID: RoomID) async throws {
        try lock.withLock {
            if let error = _settingsError { throw error }
            _settings[roomID] = RoomNotificationSettings(mode: mode, isDefault: false)
        }
    }

    public func restoreDefaultNotificationMode(for roomID: RoomID) async throws {
        try lock.withLock {
            if let error = _settingsError { throw error }
            _settings[roomID] = nil
        }
    }
}
