import Foundation

/// End-to-end encryption: this device's verification, recovery and key backup.
///
/// The three state streams start with the current value, then deliver every change. Every access
/// opens an independent subscription.
public protocol EncryptionService: Sendable {
    /// Whether this device is verified.
    var verificationStatus: AsyncStream<VerificationStatus> { get }
    /// The state of the room-key backup.
    var backupState: AsyncStream<BackupState> { get }
    /// The state of recovery.
    var recoveryState: AsyncStream<RecoveryState> { get }
    /// Verification of this device against another of the user's devices.
    var sessionVerification: any SessionVerification { get }

    /// True when this is the user's only device: signing out without recovery loses the
    /// encrypted history.
    func isLastDevice() async throws -> Bool

    /// True when another verified device exists, which this one can be verified against.
    func hasDevicesToVerifyAgainst() async throws -> Bool

    /// True when a key backup already exists on the server — set up from another device.
    func backupExistsOnServer() async throws -> Bool

    /// Sets up recovery: creates the key backup and the recovery key, and returns the key to show
    /// to the user. It is not stored anywhere else.
    ///
    /// - Parameters:
    ///   - waitForBackupUpload: when true, returns only once every room key is uploaded.
    ///   - progress: called as the operation advances, from an arbitrary thread.
    func enableRecovery(
        waitForBackupUpload: Bool,
        progress: @escaping @Sendable (RecoveryProgress) -> Void
    ) async throws -> RecoveryKey

    /// Restores the user's secrets with their recovery key, which verifies this device.
    ///
    /// - Throws: ``MatrixError/Encryption/invalidRecoveryKey`` when the key is wrong.
    func recover(with key: String) async throws

    /// Replaces the recovery key and returns the new one. The previous key stops working.
    func resetRecoveryKey() async throws -> RecoveryKey

    /// Disables recovery and deletes the key backup from the server.
    func disableRecovery() async throws

    /// Enables the room-key backup without setting up recovery.
    func enableBackups() async throws
}

extension EncryptionService {
    /// Sets up recovery without waiting for room keys to be uploaded.
    public func enableRecovery(
        progress: @escaping @Sendable (RecoveryProgress) -> Void = { _ in }
    ) async throws -> RecoveryKey {
        try await enableRecovery(waitForBackupUpload: false, progress: progress)
    }
}
