import Testing
@testable import MatrixClientKitCore

@Test func rateLimitedExposesRetryDelay() {
    let error = MatrixError.rateLimited(retryAfter: .milliseconds(1500))
    #expect(error.isRetryable)
    #expect(error.retryAfter == .milliseconds(1500))
}

@Test func networkErrorsAreRetryable() {
    #expect(MatrixError.network(.offline).isRetryable)
    #expect(MatrixError.network(.timeout).isRetryable)
    #expect(MatrixError.network(.tlsFailure).isRetryable == false)
}

@Test func authenticationErrorsAreNotRetryable() {
    #expect(MatrixError.authentication(.invalidCredentials).isRetryable == false)
    #expect(MatrixError.authentication(.unknownToken(soft: true)).isRetryable == false)
}

@Test func softLogoutIsDistinguishableFromHardLogout() {
    #expect(MatrixError.authentication(.unknownToken(soft: true))
            != MatrixError.authentication(.unknownToken(soft: false)))
}

@Test func retryAfterIsNilForNonRateLimitedErrors() {
    #expect(MatrixError.permission(.forbidden).retryAfter == nil)
}

@Test func errorDescriptionIsNeverEmpty() {
    let errors: [MatrixError] = [
        .authentication(.invalidCredentials),
        .network(.offline),
        .rateLimited(retryAfter: nil),
        .permission(.forbidden),
        .notFound(.room),
        .encryption(.verificationRequired),
        .server(.maintenance),
        .storage(.unavailable),
        .unexpected(message: "boom", details: nil),
        // Le SDK amont peut remonter une erreur sans message ; `.unexpected` est le déversoir de
        // toute erreur non encore distinguée, donc ce cas n'a rien d'exotique.
        .unexpected(message: "", details: nil),
        .unexpected(message: "", details: ""),
        .unexpected(message: "", details: "détail"),
    ]
    for error in errors {
        #expect(error.errorDescription?.isEmpty == false)
    }
}

@Test func captchaRequiredIsDistinctFromCaptchaInvalid() {
    #expect(MatrixError.authentication(.captchaRequired)
            != MatrixError.authentication(.captchaInvalid))
}
