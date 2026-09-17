import Foundation

/// The state of the current device-verification flow. See ``SessionVerification``.
public enum SessionVerificationState: Sendable, Hashable {
    /// No verification in progress.
    case idle
    /// Another of the user's devices asks to verify this one. Call ``SessionVerification/accept()``
    /// or ``SessionVerification/cancel()``.
    case incomingRequest(VerificationRequest)
    /// This device asked for verification and waits for another device to accept.
    case waitingForOtherDevice
    /// Both devices accepted. Call ``SessionVerification/startSAS()``.
    case ready
    /// The short authentication strings are being negotiated.
    case startingSAS
    /// Show these to the user, who compares them with the other device, then calls
    /// ``SessionVerification/approve()`` or ``SessionVerification/decline()``.
    case comparing(SASData)
    /// This device approved and waits for the other device to approve too.
    case confirming
    /// Verification succeeded.
    case verified
    /// Verification was cancelled, on either device.
    case cancelled
    /// Verification failed.
    case failed

    /// True for ``verified``, ``cancelled`` and ``failed``: a new request may start.
    public var isFinished: Bool {
        switch self {
        case .verified, .cancelled, .failed: true
        default: false
        }
    }
}

/// A verification request received from another of the user's devices.
public struct VerificationRequest: Sendable, Hashable, Identifiable {
    /// Identifies the verification flow. Opaque.
    public let id: String
    /// The device asking for verification.
    public let deviceID: DeviceID
    /// The requesting device's display name, when it has one.
    public let deviceDisplayName: String?
    /// When the requesting device was first seen.
    public let firstSeen: Date

    /// Creates a request, for instance in a test.
    public init(id: String, deviceID: DeviceID, deviceDisplayName: String?, firstSeen: Date) {
        self.id = id
        self.deviceID = deviceID
        self.deviceDisplayName = deviceDisplayName
        self.firstSeen = firstSeen
    }
}

/// The short authentication strings both devices display.
public enum SASData: Sendable, Hashable {
    /// Seven emojis to compare.
    case emojis([SASEmoji])
    /// Three numbers to compare, when the other device does not support emojis.
    case decimals([UInt16])
}

/// One emoji of a short authentication string.
public struct SASEmoji: Sendable, Hashable {
    /// The emoji itself.
    public let symbol: String
    /// Its English name, as provided by the Matrix specification.
    public let description: String
    /// Its index (0–63) in the Matrix specification's SAS emoji table, from which an application
    /// can localise ``description``; `nil` when the SDK did not provide it.
    public let index: Int?

    /// Creates an emoji, for instance in a test.
    public init(symbol: String, description: String, index: Int?) {
        self.symbol = symbol
        self.description = description
        self.index = index
    }
}
