import Foundation

/// Whether this device is verified, that is, signed by the user's cross-signing identity.
public enum VerificationStatus: Sendable, Hashable {
    /// Not known yet — typically until the first sync has loaded the user's identity.
    case unknown
    /// This device is verified: other clients trust the messages it sends.
    case verified
    /// This device is not verified. Verify it against another device, or enter the recovery key.
    case unverified
}

/// The state of recovery: the server-side storage of the user's secrets, protected by a
/// recovery key.
public enum RecoveryState: Sendable, Hashable {
    /// Not known yet.
    case unknown
    /// Recovery is set up, and this device holds every secret.
    case enabled
    /// Recovery is not set up for this account.
    case disabled
    /// Recovery is set up, but this device lacks the secrets: ask the user for the recovery key.
    case incomplete
}

/// The state of the server-side backup of room keys.
public enum BackupState: Sendable, Hashable {
    /// Not known yet.
    case unknown
    /// A new backup is being created.
    case creating
    /// An existing backup is being enabled on this device.
    case enabling
    /// A backup enabled in a previous launch is being resumed.
    case resuming
    /// The backup is active: new room keys are uploaded.
    case enabled
    /// Room keys are being downloaded from the backup.
    case downloading
    /// The backup is being disabled.
    case disabling
}

/// The progress of ``EncryptionService/enableRecovery(waitForBackupUpload:progress:)``.
public enum RecoveryProgress: Sendable, Hashable {
    /// The operation started.
    case starting
    /// The key backup is being created.
    case creatingBackup
    /// The recovery key is being created.
    case creatingRecoveryKey
    /// Room keys are being uploaded: `uploaded` out of `total`.
    case backingUp(uploaded: Int, total: Int)
    /// Uploading room keys failed. Recovery is set up, but the backup is incomplete.
    case roomKeyUploadError
    /// Recovery is set up. The key is the operation's return value, never part of the progress.
    case done
}

/// A recovery key: the secret that restores a user's encryption keys on a new device.
///
/// Its description is redacted, so that interpolating or printing a key never leaks it into logs.
/// Read ``rawValue`` to show it to the user.
public struct RecoveryKey: Sendable, Hashable {
    /// The key, as it should be shown to the user.
    public let rawValue: String

    /// Wraps a recovery key.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension RecoveryKey: CustomStringConvertible, CustomDebugStringConvertible {
    /// Redacted description: never exposes the key.
    public var description: String { "RecoveryKey(<redacted>)" }

    /// Redacted description: never exposes the key.
    public var debugDescription: String { description }
}
