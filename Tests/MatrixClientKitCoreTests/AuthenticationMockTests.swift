import Testing
import Foundation
import MatrixClientKitCore
import MatrixClientKitMocks

@Test func mockOAuthFlowRecordsCompletionAndReturnsTheSession() async throws {
    let session = MockMatrixSession(userID: "@bob:example.org")
    let flow = MockOAuthLoginFlow(completeResult: .success(session))
    let callback = URL(string: "com.example.app:/callback?code=abc")!

    let opened = try await flow.complete(callbackURL: callback)

    #expect(opened.userID.rawValue == "@bob:example.org")
    #expect(flow.completedCallbackURLs == [callback])
}

@Test func mockOAuthFlowThrowsTheConfiguredError() async {
    let flow = MockOAuthLoginFlow(completeResult: .failure(.authentication(.invalidCredentials)))
    await #expect(throws: MatrixError.authentication(.invalidCredentials)) {
        _ = try await flow.complete(callbackURL: URL(string: "x:/y")!)
    }
}

@Test func mockOAuthFlowCountsCancellations() async {
    let flow = MockOAuthLoginFlow()
    await flow.cancel()
    await flow.cancel()
    #expect(flow.cancelCount == 2)
}

@Test func mockQRCodeLoginReplaysTheCurrentStateThenEmissions() async {
    let login = MockQRCodeLogin()
    login.emit(.displayQRCode(Data([9])))
    var iterator = login.state.makeAsyncIterator()
    #expect(await iterator.next() == .displayQRCode(Data([9])))
    login.emit(.enterCheckCode)
    #expect(await iterator.next() == .enterCheckCode)
}

@Test func mockQRCodeLoginRecordsCheckCodesAndCancellation() async throws {
    let login = MockQRCodeLogin()
    try await login.submitCheckCode(42)
    login.cancel()
    #expect(login.submittedCheckCodes == [42])
    #expect(login.didCancel)
}

@Test func sampleLoginDetailsDefaultToPasswordOnly() {
    let details = SampleData.loginDetails()
    #expect(details.supportsPassword)
    #expect(!details.supportsOAuth)
    #expect(details.oauthPrompts.isEmpty)
}
