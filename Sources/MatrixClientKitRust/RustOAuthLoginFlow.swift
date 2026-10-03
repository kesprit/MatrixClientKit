import Foundation
import Synchronization
import MatrixRustSDK
import MatrixClientKitCore

/// Garantit qu'un flux à usage unique se termine une seule fois, par un `complete` ou un `cancel`,
/// et que son issue n'est signalée qu'une fois.
///
/// Séparé du flux pour être testé sans FFI : c'est lui qui empêche un `cancel()` tardif de purger
/// le store d'une session déjà ouverte (spec 0.4, §4.3), et lui qui garantit qu'une reconnexion
/// libère ou consomme sa réservation exactement une fois (spec 0.4, §5.5).
final class SingleUseGate: Sendable {
    private enum State { case pending, completing, cancelling, succeeded, ended }
    private let state = Mutex(State.pending)
    private let onEnd: @Sendable (_ succeeded: Bool) -> Void

    /// - Parameter onEnd: appelé une seule fois, à l'issue du flux.
    init(onEnd: @escaping @Sendable (_ succeeded: Bool) -> Void = { _ in }) {
        self.onEnd = onEnd
    }

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
            state = .cancelling
            return true
        }
    }

    func completionSucceeded() { end(from: .completing, to: .succeeded, succeeded: true) }
    func completionFailed() { end(from: .completing, to: .ended, succeeded: false) }
    func cancellationFinished() { end(from: .cancelling, to: .ended, succeeded: false) }

    private func end(from expected: State, to final: State, succeeded: Bool) {
        let didEnd = state.withLock { state in
            guard state == expected else { return false }
            state = final
            return true
        }
        if didEnd { onEnd(succeeded) }
    }
}

/// Implémentation de ``OAuthLoginFlow`` : la même tentative (même client) de l'URL d'autorisation
/// jusqu'au callback, comme l'exige l'amont (spec 0.4, §2.3).
final class RustOAuthLoginFlow: OAuthLoginFlow {
    let authorizationURL: URL
    private let attempt: LoginAttempt
    private let authorizationData: OAuthAuthorizationData
    private let expectedUserID: UserID?
    private let gate: SingleUseGate

    private init(
        authorizationURL: URL,
        attempt: LoginAttempt,
        authorizationData: OAuthAuthorizationData,
        expectedUserID: UserID?,
        onEnd: @escaping @Sendable (_ succeeded: Bool) -> Void
    ) {
        self.authorizationURL = authorizationURL
        self.attempt = attempt
        self.authorizationData = authorizationData
        self.expectedUserID = expectedUserID
        self.gate = SingleUseGate(onEnd: onEnd)
    }

    /// - Parameters:
    ///   - deviceID: l'appareil à réutiliser, pour une reconnexion.
    ///   - expectedUserID: l'utilisateur attendu, pour une reconnexion.
    ///   - onEnd: appelé exactement une fois à l'issue du flux — `true` une fois la nouvelle
    ///     session construite, `false` en cas d'échec (y compris ici même), d'annulation ou
    ///     d'abandon du flux. La reconnexion y marque l'ancienne session remplacée, ou libère sa
    ///     réservation.
    static func begin(
        attempt: LoginAttempt,
        configuration: MatrixClientKitCore.OAuthConfiguration,
        prompt: MatrixClientKitCore.OAuthPrompt?,
        loginHint: String?,
        deviceID: DeviceID?,
        expecting expectedUserID: UserID?,
        onEnd: @escaping @Sendable (_ succeeded: Bool) -> Void = { _ in }
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
                expectedUserID: expectedUserID, onEnd: onEnd
            )
        } catch {
            attempt.fail()
            onEnd(false)
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
            return session
        } catch {
            let error = await attempt.refusingAnotherAccount(after: error, expecting: expectedUserID)
            attempt.fail()
            gate.completionFailed()
            throw OAuthMapper.map(error)
        }
    }

    func cancel() async {
        guard gate.claimCancellation() else { return }
        await attempt.client.abortOauthAuth(authorizationData: authorizationData)
        attempt.fail()
        gate.cancellationFinished()
    }

    /// Un flux abandonné sans `complete` ni `cancel` signale tout de même son issue : sinon une
    /// reconnexion garderait sa réservation pour toujours, et `logout()` l'attendrait sans fin.
    deinit {
        guard gate.claimCancellation() else { return }
        attempt.fail()
        gate.cancellationFinished()
    }
}
