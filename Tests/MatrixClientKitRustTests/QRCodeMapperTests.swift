import Testing
import Foundation
import MatrixRustSDK
@testable import MatrixClientKitRust
import MatrixClientKitCore

@Test func scannedModeProgressMapsToEvents() {
    #expect(
        QRCodeMapper.event(QrLoginProgress.establishingSecureChannel(checkCode: 7, checkCodeString: "07"))
            == .secureChannelEstablished(checkCode: "07"))
    #expect(QRCodeMapper.event(QrLoginProgress.waitingForToken(userCode: "AB")) == .waitingForToken(userCode: "AB"))
    #expect(QRCodeMapper.event(QrLoginProgress.syncingSecrets) == .syncingSecrets)
    #expect(QRCodeMapper.event(QrLoginProgress.done) == .done)
}

@Test(arguments: [
    (HumanQrLoginError.Declined, QRCodeLoginFailure.declined),
    (.Expired, .expired),
    (.ConnectionInsecure, .insecureChannel),
    (.LinkingNotSupported, .notSupported),
    (.OAuthMetadataInvalid, .notSupported),
    (.SlidingSyncNotAvailable, .notSupported),
    (.UnsupportedQrCodeType, .notSupported),
    (.NotFound, .notSupported),
    (.OtherDeviceNotSignedIn, .otherDeviceNotSignedIn),
    (.Cancelled, .cancelled),
    (.Unknown, .unknown),
    (.CheckCodeAlreadySent, .unknown),
    (.ContinuationCannotBeSent, .unknown),
])
func qrErrorsFollowTheSpecTable(_ error: HumanQrLoginError, _ expected: QRCodeLoginFailure) {
    #expect(QRCodeMapper.failure(error) == expected)
}

@Test func anyOtherErrorIsUnknown() {
    #expect(QRCodeMapper.failure(MatrixError.network(.offline)) == .unknown)
}

@Test func unreadableBytesHaveNoTarget() {
    #expect(QRCodeMapper.target(scanned: Data([0, 1, 2])) == nil)
}

@Test func theStartingProgressProducesNoEvent() {
    // L'état initial est déjà `.starting`.
    #expect(QRCodeMapper.event(QrLoginProgress.starting) == nil)
}
