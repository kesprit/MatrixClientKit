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

@Test func mockQRCodeLoginThrowsCancellationErrorAfterCancel() async throws {
    let login = MockQRCodeLogin()
    login.cancel()

    await #expect(throws: CancellationError.self) {
        _ = try await login.start()
    }
}

@Test func mockQRCodeLoginYieldsFailedStateAfterCancel() async {
    let login = MockQRCodeLogin()
    var iterator = login.state.makeAsyncIterator()

    login.cancel()

    let state = await iterator.next()
    #expect(state == .failed(.cancelled))
}

@Test func sampleLoginDetailsDefaultToPasswordOnly() {
    let details = SampleData.loginDetails()
    #expect(details.supportsPassword)
    #expect(!details.supportsOAuth)
    #expect(details.oauthPrompts.isEmpty)
}

@Test func mockClientReturnsTheConfiguredLoginDetails() async throws {
    let client = MockMatrixClient()
    client.loginDetailsResult = .success(SampleData.loginDetails(supportsOAuth: true, oauthPrompts: [.create]))
    let details = try await client.loginDetails()
    #expect(details.supportsOAuth)
    #expect(details.oauthPrompts == [.create])
}

@Test func mockClientRecordsOAuthRequestsAndReturnsItsFlow() async throws {
    let client = MockMatrixClient()
    let flow = try await client.beginOAuthLogin(SampleData.oauthConfiguration(), prompt: .create, loginHint: "alice")
    #expect(flow.authorizationURL == client.oauthFlow.authorizationURL)
    #expect(
        client.oauthRequests == [
            .init(configuration: SampleData.oauthConfiguration(), prompt: .create, loginHint: "alice")
        ])
}

@Test func mockClientOAuthCanFail() async {
    let client = MockMatrixClient()
    client.oauthLoginError = .authentication(.unsupportedLoginType)
    await #expect(throws: MatrixError.authentication(.unsupportedLoginType)) {
        _ = try await client.beginOAuthLogin(SampleData.oauthConfiguration())
    }
}

@Test func mockClientHandsOutItsQRCodeLogin() {
    let client = MockMatrixClient()
    let login = client.loginWithQRCode(SampleData.oauthConfiguration())
    #expect((login as? MockQRCodeLogin) === client.qrCodeLogin)
}

@Test func mockSessionReauthenticationIsConfigurableAndRecorded() async throws {
    let session = MockMatrixSession()
    session.reauthenticateResult = .success(MockMatrixSession(deviceID: "DEV1"))
    let renewed = try await session.reauthenticate(.password(username: "alice", password: "p", deviceName: nil))
    #expect(renewed.deviceID.rawValue == "DEV1")
    #expect(session.reauthenticationAttempts.count == 1)
}

@Test func mockSessionRefusesReauthenticationByDefault() async {
    let session = MockMatrixSession()
    await #expect(throws: MatrixError.self) {
        _ = try await session.reauthenticate(.password(username: "a", password: "p", deviceName: nil))
    }
}

@Test func mockSessionHandsOutItsOAuthReauthenticationFlow() async throws {
    let session = MockMatrixSession()
    let flow = try await session.beginOAuthReauthentication(SampleData.oauthConfiguration())
    #expect((flow as? MockOAuthLoginFlow) === session.oauthReauthenticationFlow)
}
