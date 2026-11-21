import Foundation
import MatrixClientKitCore

/// A profile service for tests: serves the profiles you put in ``profiles``, records every
/// change, and throws ``error`` when set.
public final class MockProfileService: ProfileService, @unchecked Sendable {
    /// A call to ``setAvatar(_:mimeType:)``.
    public struct AvatarUpload: Sendable, Hashable {
        /// The uploaded bytes.
        public let data: Data
        /// The MIME type given with them.
        public let mimeType: String

        /// Creates an upload record.
        public init(data: Data, mimeType: String) {
            self.data = data
            self.mimeType = mimeType
        }
    }

    private let lock = NSLock()
    private var _profiles: [UserID: UserProfile] = [:]
    private var _error: MatrixError?
    private var _displayNameChanges: [String] = []
    private var _avatarUploads: [AvatarUpload] = []
    private var _removeAvatarCount = 0
    private var _publishedPresences: [Presence] = []

    public init() {}

    /// The profile served for each user. A user that is absent throws
    /// ``MatrixError/notFound(_:)`` with `.user`.
    public var profiles: [UserID: UserProfile] {
        get { lock.withLock { _profiles } }
        set { lock.withLock { _profiles = newValue } }
    }

    /// The error every call throws. `nil` by default, meaning calls succeed.
    public var error: MatrixError? {
        get { lock.withLock { _error } }
        set { lock.withLock { _error = newValue } }
    }

    /// Every name passed to ``setDisplayName(_:)``, in order.
    public var displayNameChanges: [String] { lock.withLock { _displayNameChanges } }

    /// Every call to ``setAvatar(_:mimeType:)``, in order.
    public var avatarUploads: [AvatarUpload] { lock.withLock { _avatarUploads } }

    /// How many times ``removeAvatar()`` was called.
    public var removeAvatarCount: Int { lock.withLock { _removeAvatarCount } }

    /// Every presence passed to ``setPresence(_:)``, in order — recorded even when ``error`` makes
    /// the call throw, like the real service, which applies the state anyway.
    public var publishedPresences: [Presence] { lock.withLock { _publishedPresences } }

    public func profile(of user: UserID) async throws -> UserProfile {
        if let error { throw error }
        guard let profile = profiles[user] else { throw MatrixError.notFound(.user) }
        return profile
    }

    public func setDisplayName(_ name: String) async throws {
        lock.withLock { _displayNameChanges.append(name) }
        if let error { throw error }
    }

    public func setAvatar(_ data: Data, mimeType: String) async throws {
        lock.withLock { _avatarUploads.append(AvatarUpload(data: data, mimeType: mimeType)) }
        if let error { throw error }
    }

    public func removeAvatar() async throws {
        lock.withLock { _removeAvatarCount += 1 }
        if let error { throw error }
    }

    public func setPresence(_ presence: Presence) async throws {
        lock.withLock { _publishedPresences.append(presence) }
        if let error { throw error }
    }
}
