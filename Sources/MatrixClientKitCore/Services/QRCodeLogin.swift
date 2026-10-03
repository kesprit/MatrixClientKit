import Foundation

/// A sign-in of this device by another device of the same account, through a QR code.
///
/// Observe ``state`` to drive the screen, then call ``start()``, which returns the session once
/// the other device has approved and handed over this account's encryption secrets: the new
/// session starts out verified.
public protocol QRCodeLogin: Sendable {
    /// The login's state, starting with the current value. Every access opens an independent
    /// subscription.
    var state: AsyncStream<QRCodeLoginState> { get }

    /// Runs the login. Call it once.
    ///
    /// - Throws: `CancellationError` after ``cancel()``; ``MatrixError`` otherwise — ``state``
    ///   then holds the ``QRCodeLoginFailure``.
    func start() async throws -> any MatrixSession

    /// Sends the two digits shown by the signed-in device. Valid only in
    /// ``QRCodeLoginState/enterCheckCode``.
    func submitCheckCode(_ code: UInt8) async throws

    /// Abandons the login. ``state`` ends in ``QRCodeLoginFailure/cancelled``.
    func cancel()
}
