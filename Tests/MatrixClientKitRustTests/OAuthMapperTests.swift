import Testing
import Foundation
import MatrixRustSDK
@testable import MatrixClientKitRust
import MatrixClientKitCore

@Test func theConfigurationIsMappedFieldByField() {
    let mapped = OAuthMapper.configuration(
        MatrixClientKitCore.OAuthConfiguration(
            clientName: "Example",
            redirectURI: URL(string: "com.example.app:/callback")!,
            clientURI: URL(string: "https://example.com")!,
            logoURI: URL(string: "https://example.com/logo.png")!,
            termsOfServiceURI: URL(string: "https://example.com/tos")!,
            policyURI: URL(string: "https://example.com/privacy")!,
            staticRegistrations: [URL(string: "https://matrix.example.com")!: "client-123"]
        ))
    #expect(mapped.clientName == "Example")
    #expect(mapped.redirectUri == "com.example.app:/callback")
    #expect(mapped.clientUri == "https://example.com")
    #expect(mapped.logoUri == "https://example.com/logo.png")
    #expect(mapped.tosUri == "https://example.com/tos")
    #expect(mapped.policyUri == "https://example.com/privacy")
    #expect(mapped.staticRegistrations == ["https://matrix.example.com": "client-123"])
}

@Test func oauthErrorsFollowTheSpecTable() {
    #expect(
        OAuthMapper.map(OAuthError.NotSupported(message: "x")) as? MatrixError == .authentication(.unsupportedLoginType)
    )
    #expect(OAuthMapper.map(OAuthError.MetadataInvalid(message: "x")) as? MatrixError == .server(.invalidResponse))
    #expect(OAuthMapper.map(OAuthError.Cancelled(message: "x")) is CancellationError)
    guard case .unexpected = OAuthMapper.map(OAuthError.CallbackUrlInvalid(message: "x")) as? MatrixError else {
        Issue.record("attendu .unexpected"); return
    }
}

@Test func otherErrorsGoThroughTheAuthenticationMapper() {
    #expect(OAuthMapper.map(MatrixError.network(.timeout)) as? MatrixError == .network(.timeout))
}

@Test func twoRegistrationURLsWithTheSameStringDoNotTrap() {
    // Deux `URL` distinctes (l'une relative à une base) partagent la même chaîne absolue : la clé
    // amont étant une chaîne, une construction à clés uniques ferait planter l'application.
    let absolute = URL(string: "https://matrix.example.com/")!
    let relative = URL(string: "/", relativeTo: URL(string: "https://matrix.example.com/x")!)!
    #expect(absolute != relative)
    #expect(absolute.absoluteString == relative.absoluteString)

    let mapped = OAuthMapper.configuration(
        MatrixClientKitCore.OAuthConfiguration(
            clientName: "Example",
            redirectURI: URL(string: "com.example.app:/callback")!,
            clientURI: URL(string: "https://example.com")!,
            staticRegistrations: [absolute: "client-1", relative: "client-1"]
        ))
    #expect(mapped.staticRegistrations == ["https://matrix.example.com/": "client-1"])
}
