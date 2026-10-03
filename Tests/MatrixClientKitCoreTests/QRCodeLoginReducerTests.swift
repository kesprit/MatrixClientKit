import Testing
import Foundation
@testable import MatrixClientKitCore

private func run(_ events: [QRCodeLoginEvent], from state: QRCodeLoginState = .starting) -> QRCodeLoginState {
    events.reduce(state, QRCodeLoginReducer.reduce)
}

private let qr = Data([1, 2, 3])

@Test func displayedModeHappyPath() {
    #expect(run([.qrReady(qr)]) == .displayQRCode(qr))
    #expect(run([.qrReady(qr), .qrScanned]) == .enterCheckCode)
    let withToken = run([.qrReady(qr), .qrScanned, .waitingForToken(userCode: "ABCD")])
    #expect(withToken == .waitingForApproval(userCode: "ABCD"))
    let withSecrets = run([.qrReady(qr), .qrScanned, .waitingForToken(userCode: "ABCD"), .syncingSecrets])
    #expect(withSecrets == .syncingSecrets)
    let withDone = run([.qrReady(qr), .qrScanned, .waitingForToken(userCode: "ABCD"), .syncingSecrets, .done])
    #expect(withDone == .done)
}

@Test func scannedModeHappyPath() {
    #expect(run([.secureChannelEstablished(checkCode: "07")]) == .displayCheckCode("07"))
    #expect(run([.secureChannelEstablished(checkCode: "07"), .waitingForToken(userCode: "U"), .done]) == .done)
}

@Test func doneWithoutSecretSyncIsAccepted() {
    // L'amont peut sauter `.syncingSecrets` (aucun secret à transférer).
    #expect(run([.secureChannelEstablished(checkCode: "07"), .waitingForToken(userCode: "U"), .done]) == .done)
}

@Test(arguments: [
    QRCodeLoginFailure.declined,
    .expired,
    .insecureChannel,
    .notSupported,
    .otherDeviceNotSignedIn,
    .cancelled,
    .unknown,
])
func everyFailureEndsTheFlowFromAnyLiveState(_ failure: QRCodeLoginFailure) {
    let liveStates: [QRCodeLoginState] = [
        .starting, .displayQRCode(qr), .enterCheckCode, .displayCheckCode("07"),
        .waitingForApproval(userCode: "U"), .syncingSecrets,
    ]
    for state in liveStates {
        #expect(QRCodeLoginReducer.reduce(state, .failed(failure)) == .failed(failure))
    }
}

@Test func finishedStatesAbsorbLateCallbacks() {
    let late: [QRCodeLoginEvent] = [
        .qrReady(qr),
        .qrScanned,
        .secureChannelEstablished(checkCode: "07"),
        .waitingForToken(userCode: "U"),
        .syncingSecrets,
        .done,
        .failed(.unknown),
    ]
    for event in late {
        #expect(QRCodeLoginReducer.reduce(.done, event) == .done)
        let withCancel = QRCodeLoginReducer.reduce(.failed(.cancelled), event)
        #expect(withCancel == .failed(.cancelled))
    }
}

@Test func outOfOrderEventsAreIgnored() {
    #expect(QRCodeLoginReducer.reduce(.starting, .qrScanned) == .starting)
    #expect(QRCodeLoginReducer.reduce(.starting, .syncingSecrets) == .starting)
    #expect(QRCodeLoginReducer.reduce(.starting, .done) == .starting)
    let outOfOrder = QRCodeLoginReducer.reduce(
        .displayQRCode(qr),
        .secureChannelEstablished(checkCode: "07")
    )
    #expect(outOfOrder == .displayQRCode(qr))
}

@Test func checkCodeCanOnlyBeSubmittedWhenAsked() {
    #expect(QRCodeLoginReducer.canSubmitCheckCode(in: .enterCheckCode))
    #expect(!QRCodeLoginReducer.canSubmitCheckCode(in: .starting))
    #expect(!QRCodeLoginReducer.canSubmitCheckCode(in: .displayCheckCode("07")))
    #expect(!QRCodeLoginReducer.canSubmitCheckCode(in: .waitingForApproval(userCode: "U")))
}

@Test func finishedStatesAreFlagged() {
    #expect(QRCodeLoginState.done.isFinished)
    #expect(QRCodeLoginState.failed(.declined).isFinished)
    #expect(!QRCodeLoginState.syncingSecrets.isFinished)
}
