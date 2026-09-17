import Testing
import MatrixRustSDK
@testable import MatrixClientKitRust

@Test func eachDecryptionFailureCauseHasItsOwnEnglishReason() {
    let expected: [(UtdCause, String)] = [
        (.unknown, "The message could not be decrypted."),
        (.sentBeforeWeJoined, "Sent before you joined the room."),
        (.verificationViolation, "The sender's verified identity has changed."),
        (.unsignedDevice, "Sent from a device its owner has not verified."),
        (.unknownDevice, "Sent from an unknown device."),
        (.historicalMessageAndBackupIsDisabled, "Sent before this device signed in, and key backup is off."),
        (.historicalMessageAndDeviceIsUnverified, "Sent before this device signed in; verify this device to read it."),
        (.withheldForUnverifiedOrInsecureDevice, "The sender does not share keys with unverified devices."),
        (.withheldBySender, "The sender withheld the keys for this message."),
    ]

    for (cause, reason) in expected {
        #expect(
            TimelineMapper.decryptionFailureReason(for: .megolmV1AesSha2(sessionId: "session", cause: cause)) == reason
        )
    }
}

@Test func otherEncryptionSchemesGetTheGenericReason() {
    #expect(TimelineMapper.decryptionFailureReason(for: .unknown) == "The message could not be decrypted.")
    #expect(
        TimelineMapper.decryptionFailureReason(for: .olmV1Curve25519AesSha2(senderKey: "key"))
            == "The message could not be decrypted.")
}

@Test func sendFailureReasonsAreInEnglish() {
    #expect(
        TimelineMapper.reason(from: .crossVerificationRequired)
            == "This session must be verified before it can send messages.")
    #expect(TimelineMapper.reason(from: .missingMediaContent) == "The media to send is missing from the cache.")
    #expect(TimelineMapper.reason(from: .invalidMimeType(mimeType: "x/y")) == "Unsupported content type: x/y.")
    #expect(TimelineMapper.reason(from: .genericApiError(msg: "")) == "Sending failed.")
    #expect(TimelineMapper.reason(from: .genericApiError(msg: "Server said no")) == "Server said no")
}
