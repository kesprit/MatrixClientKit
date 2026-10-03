import Foundation

/// A sign-in through the homeserver's OAuth authorization server, waiting for the user.
///
/// Open ``authorizationURL`` in an `ASWebAuthenticationSession` whose callback scheme is the one
/// of ``OAuthConfiguration/redirectURI``, then pass the URL it calls back with to
/// ``complete(callbackURL:)``. If the user closes the web view, call ``cancel()``.
///
/// A flow is single-use: once ``complete(callbackURL:)`` has failed or ``cancel()`` has been
/// called, start a new one.
public protocol OAuthLoginFlow: Sendable {
    /// The page to open for the user to sign in.
    var authorizationURL: URL { get }

    /// Finishes signing in with the URL the authorization server redirected to.
    ///
    /// - Throws: `CancellationError` when the user refused or the authorization server cancelled;
    ///   ``MatrixError`` otherwise. A second call throws ``MatrixError/unexpected(message:details:)``.
    func complete(callbackURL: URL) async throws -> any MatrixSession

    /// Abandons the flow and erases what it had prepared locally. Does nothing after a successful
    /// ``complete(callbackURL:)``, and nothing when called twice.
    func cancel() async
}
