import MatrixRustSDK

/// Sous-ensemble de `SessionVerificationController` amont dont la vérification a besoin.
///
/// Couture de testabilité : le contrôleur est une classe FFI qu'un test ne peut pas construire.
/// Les signatures sont celles de l'amont, à l'identique, pour que la conformance soit vide.
protocol VerificationControllerDriving: Sendable {
    func setDelegate(delegate: (any SessionVerificationControllerDelegate)?)
    func requestDeviceVerification() async throws
    func acknowledgeVerificationRequest(senderId: String, flowId: String) async throws
    func acceptVerificationRequest() async throws
    func startSasVerification() async throws
    func approveVerification() async throws
    func declineVerification() async throws
    func cancelVerification() async throws
}

extension SessionVerificationController: VerificationControllerDriving {}
