import Foundation

/// What a homeserver accepts for signing in. See ``MatrixClient/loginDetails()``.
public struct LoginDetails: Sendable, Hashable {
    /// The homeserver these details describe.
    public let homeserver: URL
    /// Whether ``Credentials/password(username:password:deviceName:)`` and
    /// ``Credentials/email(address:password:deviceName:)`` can succeed.
    public let supportsPassword: Bool
    /// Whether ``MatrixClient/beginOAuthLogin(_:prompt:loginHint:)`` and QR-code login can succeed.
    public let supportsOAuth: Bool
    /// Whether the homeserver offers legacy single sign-on. Reported for information only:
    /// MatrixClientKit does not support it.
    public let supportsSSO: Bool
    /// The prompts the authorization server advertises. Offer account creation only when this
    /// contains ``OAuthPrompt/create``.
    public let oauthPrompts: Set<OAuthPrompt>

    public init(
        homeserver: URL,
        supportsPassword: Bool,
        supportsOAuth: Bool,
        supportsSSO: Bool,
        oauthPrompts: Set<OAuthPrompt>
    ) {
        self.homeserver = homeserver
        self.supportsPassword = supportsPassword
        self.supportsOAuth = supportsOAuth
        self.supportsSSO = supportsSSO
        self.oauthPrompts = oauthPrompts
    }
}

/// What the authorization server should show the user.
///
/// - Important: frozen for the lifetime of a major version, like ``MatrixError``. A prompt
///   standardised later is ignored until the next major.
public enum OAuthPrompt: Sendable, Hashable {
    /// Ask the user to sign in again, even with a live browser session.
    case login
    /// Offer to create an account.
    case create
    /// Ask the user to consent again.
    case consent
}

/// How this application presents itself to an OAuth authorization server.
///
/// The authorization server shows these details on its consent screen, and registers the
/// application under them the first time it sees it.
public struct OAuthConfiguration: Sendable, Hashable {
    /// The application's name, shown to the user.
    public var clientName: String?
    /// Where the authorization server sends the user back, for instance
    /// `com.example.app:/callback`. Must match the callback scheme given to
    /// `ASWebAuthenticationSession`.
    public var redirectURI: URL
    /// A page about the application.
    public var clientURI: URL
    public var logoURI: URL?
    public var termsOfServiceURI: URL?
    public var policyURI: URL?
    /// Client IDs registered ahead of time, for authorization servers without dynamic
    /// registration: the homeserver's (or the issuer's) URL → client ID.
    public var staticRegistrations: [URL: String]

    public init(
        clientName: String? = nil,
        redirectURI: URL,
        clientURI: URL,
        logoURI: URL? = nil,
        termsOfServiceURI: URL? = nil,
        policyURI: URL? = nil,
        staticRegistrations: [URL: String] = [:]
    ) {
        self.clientName = clientName
        self.redirectURI = redirectURI
        self.clientURI = clientURI
        self.logoURI = logoURI
        self.termsOfServiceURI = termsOfServiceURI
        self.policyURI = policyURI
        self.staticRegistrations = staticRegistrations
    }
}
