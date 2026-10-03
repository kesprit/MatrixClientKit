import Foundation

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
    /// Any other failure, including those the underlying SDK reports in ways this package does
    /// not distinguish.
    case unknown
}

/// Where a QR-code login stands. See ``QRCodeLogin/state``.
public enum QRCodeLoginState: Sendable, Hashable {
    /// The login has not produced anything to show yet.
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
    /// The session is ready: ``QRCodeLogin/start()`` returns it.
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
