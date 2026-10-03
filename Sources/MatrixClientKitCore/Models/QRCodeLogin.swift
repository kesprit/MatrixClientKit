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

/// Why a QR-code login ended without a session.
///
/// - Important: frozen for the lifetime of a major version, like ``MatrixError``. A failure the
///   underlying SDK newly distinguishes is reported as ``unknown``.
public enum QRCodeLoginFailure: Sendable, Hashable {
    /// The signed-in device refused the request.
    case declined
    /// The code or the request expired before the other device acted on it.
    case expired
    /// The check codes did not match: the channel between the devices may be intercepted.
    case insecureChannel
    /// The homeserver does not support QR-code login (it needs OAuth and MSC4108), or the code
    /// is not a Matrix login code.
    case notSupported
    /// The device that showed the code is not signed in.
    case otherDeviceNotSignedIn
    /// ``QRCodeLogin/cancel()`` was called.
    case cancelled
    case unknown
}

/// Where a QR-code login stands. See ``QRCodeLogin/state``.
public enum QRCodeLoginState: Sendable, Hashable {
    case starting
    /// Show these bytes as a QR code for the signed-in device to scan.
    case displayQRCode(Data)
    /// The signed-in device scanned the code and shows two digits: ask the user to type them,
    /// then call ``QRCodeLogin/submitCheckCode(_:)``.
    case enterCheckCode
    /// Show these two digits: the user confirms them on the signed-in device.
    case displayCheckCode(String)
    /// Waiting for the user to approve the sign-in on the signed-in device. Some servers ask the
    /// user to check `userCode` there.
    case waitingForApproval(userCode: String)
    /// Signed in; receiving this account's encryption secrets from the other device.
    case syncingSecrets
    case done
    case failed(QRCodeLoginFailure)

    /// Whether the flow is over, successfully or not.
    public var isFinished: Bool {
        switch self {
        case .done, .failed: true
        default: false
        }
    }
}

/// Ce qui fait avancer une connexion par QR : un progrès amont, ou un échec.
package enum QRCodeLoginEvent: Sendable, Hashable {
    case qrReady(Data)
    case qrScanned
    case secureChannelEstablished(checkCode: String)
    case waitingForToken(userCode: String)
    case syncingSecrets
    case done
    case failed(QRCodeLoginFailure)
}
