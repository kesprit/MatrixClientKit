import Testing
import MatrixRustSDK
@testable import MatrixClientKitRust
import MatrixClientKitCore

@Test func promptsMapBothWays() {
    #expect(LoginDetailsMapper.prompt(MatrixRustSDK.OAuthPrompt.create) == .create)
    #expect(LoginDetailsMapper.prompt(MatrixRustSDK.OAuthPrompt.login) == .login)
    #expect(LoginDetailsMapper.prompt(MatrixRustSDK.OAuthPrompt.consent) == .consent)
    #expect(LoginDetailsMapper.prompt(MatrixRustSDK.OAuthPrompt.unknown(value: "x")) == nil)
    #expect(LoginDetailsMapper.prompt(MatrixClientKitCore.OAuthPrompt.create) == .create)
}
