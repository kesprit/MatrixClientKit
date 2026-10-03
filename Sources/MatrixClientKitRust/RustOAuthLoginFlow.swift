import Foundation
import Synchronization
import MatrixRustSDK
import MatrixClientKitCore

/// Garantit qu'un flux à usage unique se termine une seule fois, par un `complete` ou un `cancel`.
///
/// Séparé du flux pour être testé sans FFI : c'est lui qui empêche un `cancel()` tardif de purger
/// le store d'une session déjà ouverte (spec 0.4, §4.3).
final class SingleUseGate: Sendable {
    private enum State { case pending, completing, succeeded, ended }
    private let state = Mutex(State.pending)

    func claimCompletion() -> Bool {
        state.withLock { state in
            guard state == .pending else { return false }
            state = .completing
            return true
        }
    }

    func claimCancellation() -> Bool {
        state.withLock { state in
            guard state == .pending else { return false }
            state = .ended
            return true
        }
    }

    func completionSucceeded() { state.withLock { $0 = .succeeded } }
    func completionFailed() { state.withLock { $0 = .ended } }
}

/// Implémentation de ``OAuthLoginFlow`` : la même tentative (même client) de l'URL d'autorisation
/// jusqu'au callback, comme l'exige l'amont (spec 0.4, §2.3).
final class RustOAuthLoginFlow: OAuthLoginFlow {
    let authorizationURL: URL
    private let attempt: LoginAttempt
    private let authorizationData: OAuthAuthorizationData
    private let expectedUserID: UserID?
    private let onSuccess: @Sendable () -> Void
    private let gate = SingleUseGate()

    private init(
        authorizationURL: URL,
        attempt: LoginAttempt,
        authorizationData: OAuthAuthorizationData,
        expectedUserID: UserID?,
        onSuccess: @escaping @Sendable () -> Void
    ) {
        self.authorizationURL = authorizationURL
        self.attempt = attempt
        self.authorizationData = authorizationData
        self.expectedUserID = expectedUserID
        self.onSuccess = onSuccess
    }

    /// - Parameters:
    ///   - deviceID: l'appareil à réutiliser, pour une reconnexion.
    ///   - expectedUserID: l'utilisateur attendu, pour une reconnexion.
    ///   - onSuccess: appelé une fois la nouvelle session construite (la reconnexion y marque
    ///     l'ancienne session remplacée).
    static func begin(
        attempt: LoginAttempt,
        configuration: MatrixClientKitCore.OAuthConfiguration,
        prompt: MatrixClientKitCore.OAuthPrompt?,
        loginHint: String?,
        deviceID: DeviceID?,
        expecting expectedUserID: UserID?,
        onSuccess: @escaping @Sendable () -> Void = {}
    ) async throws -> RustOAuthLoginFlow {
        do {
            let data = try await attempt.client.urlForOauth(
                oauthConfiguration: OAuthMapper.configuration(configuration),
                prompt: prompt.map(LoginDetailsMapper.prompt),
                loginHint: loginHint,
                deviceId: deviceID?.rawValue,
                additionalScopes: nil
            )
            guard let url = URL(string: data.loginUrl()) else {
                throw MatrixError.unexpected(
                    message: "The authorization server returned an invalid URL.", details: data.loginUrl())
            }
            return RustOAuthLoginFlow(
                authorizationURL: url, attempt: attempt, authorizationData: data,
                expectedUserID: expectedUserID, onSuccess: onSuccess
            )
        } catch {
            attempt.fail()
            throw OAuthMapper.map(error)
        }
    }

    func complete(callbackURL: URL) async throws -> any MatrixSession {
        guard gate.claimCompletion() else {
            throw MatrixError.unexpected(
                message: "This OAuth sign-in has already been completed or cancelled.", details: nil)
        }
        do {
            try await attempt.client.loginWithOauthCallback(callbackUrl: callbackURL.absoluteString)
            let session = try await attempt.succeed(expecting: expectedUserID)
            gate.completionSucceeded()
            onSuccess()
            return session
        } catch {
            gate.completionFailed()
            attempt.fail()
            throw OAuthMapper.map(error)
        }
    }

    func cancel() async {
        guard gate.claimCancellation() else { return }
        await attempt.client.abortOauthAuth(authorizationData: authorizationData)
        attempt.fail()
    }
}
