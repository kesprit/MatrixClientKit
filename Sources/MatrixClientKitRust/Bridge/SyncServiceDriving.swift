import MatrixRustSDK

/// Sous-ensemble du service de synchronisation amont dont le contrôleur a besoin.
///
/// Cette couture existe pour la testabilité : `SyncServiceProtocol` impose de renvoyer un
/// `RoomListService`, type concret qu'un test ne peut pas construire.
protocol SyncServiceDriving: Sendable {
    func start() async
    func stop() async
    func observeState(_ listener: any SyncServiceStateObserver) -> any TaskHandleProtocol
}

extension SyncService: SyncServiceDriving {
    func observeState(_ listener: any SyncServiceStateObserver) -> any TaskHandleProtocol {
        state(listener: listener)
    }
}
