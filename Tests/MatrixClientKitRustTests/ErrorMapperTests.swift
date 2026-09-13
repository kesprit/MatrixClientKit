import Testing
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private func mapApi(_ kind: ErrorKind, code: String = "M_UNKNOWN") -> MatrixError {
    ErrorMapper.map(ClientError.MatrixApi(kind: kind, code: code, msg: "message", details: nil))
}

@Test func forbiddenBecomesPermissionError() {
    #expect(mapApi(.forbidden) == .permission(.forbidden))
}

@Test func limitExceededCarriesRetryDelay() {
    #expect(mapApi(.limitExceeded(retryAfterMs: 2000)) == .rateLimited(retryAfter: .milliseconds(2000)))
    #expect(mapApi(.limitExceeded(retryAfterMs: nil)) == .rateLimited(retryAfter: nil))
}

@Test func limitExceededClampsRetryDelayInsteadOfTrapping() {
    #expect(mapApi(.limitExceeded(retryAfterMs: UInt64.max))
            == .rateLimited(retryAfter: .milliseconds(Int64.max)))
}

@Test func unknownTokenPreservesSoftLogoutFlag() {
    #expect(mapApi(.unknownToken(softLogout: true)) == .authentication(.unknownToken(soft: true)))
    #expect(mapApi(.unknownToken(softLogout: false)) == .authentication(.unknownToken(soft: false)))
}

@Test func resourceLimitExceededCarriesAdminContact() {
    #expect(mapApi(.resourceLimitExceeded(adminContact: "mailto:admin@example.com"))
            == .server(.resourceLimitExceeded(adminContact: "mailto:admin@example.com")))
}

@Test func unauthorizedBecomesInvalidCredentials() {
    #expect(mapApi(.unauthorized) == .authentication(.invalidCredentials))
}

@Test func deactivatedUserIsDetectedFromErrorCode() {
    #expect(mapApi(.unknown, code: "M_USER_DEACTIVATED") == .authentication(.userDeactivated))
}

@Test func notFoundBecomesResourceNotFound() {
    #expect(mapApi(.notFound) == .notFound(.unspecified))
}

@Test func connectionFailuresBecomeNetworkErrors() {
    #expect(mapApi(.connectionFailed) == .network(.offline))
    #expect(mapApi(.connectionTimeout) == .network(.timeout))
}

@Test func unsupportedRoomVersionBecomesServerError() {
    #expect(mapApi(.unsupportedRoomVersion) == .server(.unsupportedRoomVersion))
}

@Test func unmappedKindFallsBackToUnexpected() {
    let error = mapApi(.badAlias, code: "M_BAD_ALIAS")
    guard case let .unexpected(message, details) = error else {
        Issue.record("attendu .unexpected, obtenu \(error)")
        return
    }
    #expect(message == "message")
    #expect(details?.contains("M_BAD_ALIAS") == true)
}

@Test func genericErrorBecomesUnexpected() {
    let error = ErrorMapper.map(ClientError.Generic(msg: "boom", details: "trace"))
    #expect(error == .unexpected(message: "boom", details: "trace"))
}

@Test func nonClientErrorBecomesUnexpected() {
    struct Custom: Error {}
    guard case .unexpected = ErrorMapper.map(Custom()) else {
        Issue.record("attendu .unexpected")
        return
    }
}

@Test func captchaNeededAndCaptchaInvalidAreMappedSeparately() {
    // Deux situations différentes pour l'utilisateur : ne pas avoir résolu de captcha, ou en
    // avoir résolu un de travers. Les fusionner priverait l'application de la distinction.
    #expect(mapApi(.captchaNeeded) == .authentication(.captchaRequired))
    #expect(mapApi(.captchaInvalid) == .authentication(.captchaInvalid))
}
