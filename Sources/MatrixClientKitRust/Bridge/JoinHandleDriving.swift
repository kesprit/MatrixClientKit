import MatrixRustSDK

/// Sous-ensemble de `SendAttachmentJoinHandle` amont dont ``RustAttachmentUpload`` a besoin.
///
/// Couture de testabilité : le handle est une classe FFI qu'un test ne peut pas construire.
protocol JoinHandleDriving: Sendable {
    func cancel()
    func join() async throws
}

extension SendAttachmentJoinHandle: JoinHandleDriving {}
