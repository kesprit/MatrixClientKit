import MatrixRustSDK

/// Sous-ensemble de `SendHandle` amont dont ``RustSendHandle`` a besoin.
///
/// Couture de testabilité : `SendHandle` est une classe FFI qu'un test ne peut pas construire.
protocol SendHandleDriving: Sendable {
    func abort(reason: String?) async throws -> Bool
    func tryResend() async throws
}

extension MatrixRustSDK.SendHandle: SendHandleDriving {}
