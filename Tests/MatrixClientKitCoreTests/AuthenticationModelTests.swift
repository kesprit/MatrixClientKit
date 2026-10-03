import Testing
import Foundation
import MatrixClientKitCore

@Test func emailCredentialsNeverDescribeThePassword() {
    let credentials = Credentials.email(address: "alice@example.org", password: "hunter2", deviceName: "iPhone")
    #expect(!credentials.description.contains("hunter2"))
    #expect(!credentials.debugDescription.contains("hunter2"))
    #expect(credentials.description.contains("alice@example.org"))
    #expect(credentials.description.contains("<redacted>"))
}

@Test func emailCredentialsWithoutDeviceNameSayNil() {
    let credentials = Credentials.email(address: "alice@example.org", password: "x", deviceName: nil)
    #expect(credentials.description.contains("deviceName: nil"))
}

@Test func oauthConfigurationDefaultsOptionalFields() {
    let configuration = OAuthConfiguration(
        redirectURI: URL(string: "com.example.app:/callback")!,
        clientURI: URL(string: "https://example.com")!
    )
    #expect(configuration.clientName == nil)
    #expect(configuration.logoURI == nil)
    #expect(configuration.termsOfServiceURI == nil)
    #expect(configuration.policyURI == nil)
    #expect(configuration.staticRegistrations.isEmpty)
}

@Test func loginDetailsCompareByValue() {
    let homeserver = URL(string: "https://matrix.example.com")!
    let a = LoginDetails(
        homeserver: homeserver,
        supportsPassword: true,
        supportsOAuth: false,
        supportsSSO: false,
        oauthPrompts: []
    )
    let b = LoginDetails(
        homeserver: homeserver,
        supportsPassword: true,
        supportsOAuth: false,
        supportsSSO: false,
        oauthPrompts: []
    )
    #expect(a == b)
}
