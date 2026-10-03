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
    /// After ``cancel()``, this method may return only when the exchange in progress with the
    /// other device ends; it then throws `CancellationError`. Called after ``cancel()``, it throws
    /// at once.
    ///
    /// - Throws: `CancellationError` after ``cancel()``; ``MatrixError`` otherwise — ``state``
    ///   then holds the ``QRCodeLoginFailure``.
    func start() async throws -> any MatrixSession

    /// Sends the two digits shown by the signed-in device. Valid only in
    /// ``QRCodeLoginState/enterCheckCode``.
    func submitCheckCode(_ code: UInt8) async throws

    /// Abandons the login.
    ///
    /// ``state`` reads ``QRCodeLoginState/failed(_:)`` with ``QRCodeLoginFailure/cancelled`` at
    /// once, even though ``start()`` may still be waiting for the exchange with the other device
    /// to end. Once the session is being built, this method has no effect: ``start()`` returns
    /// the session and ``state`` ends in ``QRCodeLoginState/done``.
    func cancel()
}
