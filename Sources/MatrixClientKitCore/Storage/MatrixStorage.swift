import Foundation

/// Where the SDK's data lives, and how it is protected.
public struct MatrixStorage: Sendable, Hashable {

    /// From when secrets become readable.
    ///
    /// - Important: a notification service extension runs while the device is locked. With
    ///   ``whenUnlocked`` it cannot read the access token and the notification arrives empty.
    ///   That is why ``afterFirstUnlock`` is the default.
    public enum KeychainAccessibility: Sendable, Hashable {
        case afterFirstUnlock
        case whenUnlocked
    }

    public enum Location: Sendable, Hashable {
        case appGroup(identifier: String)
        case local(directory: URL)
    }

    public let location: Location
    public let keychainAccessGroup: String?
    public let accessibility: KeychainAccessibility

    /// Storage shared between the application and its extensions.
    public static func appGroup(
        _ identifier: String,
        keychainAccessGroup: String? = nil,
        accessibility: KeychainAccessibility = .afterFirstUnlock
    ) -> MatrixStorage {
        MatrixStorage(
            location: .appGroup(identifier: identifier),
            keychainAccessGroup: keychainAccessGroup,
            accessibility: accessibility
        )
    }

    /// Storage private to the current process, shared with no extension.
    public static func local(
        directory: URL,
        accessibility: KeychainAccessibility = .afterFirstUnlock
    ) -> MatrixStorage {
        MatrixStorage(location: .local(directory: directory), keychainAccessGroup: nil, accessibility: accessibility)
    }
}
