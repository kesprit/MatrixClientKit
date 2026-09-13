import MatrixRustSDK
import MatrixClientKitCore

/// Traduit les états de synchronisation amont vers le domaine.
enum SyncStateMapper {
    static func map(_ state: SyncServiceState) -> SyncState {
        switch state {
        case .idle: .idle
        case .running: .running
        case .terminated: .terminated
        case .error: .error
        case .offline: .offline
        }
    }
}

/// Listener d'état conforme au protocole amont, alimenté par une closure.
private final class StateObserver: SyncServiceStateObserver {
    private let handler: @Sendable (SyncServiceState) -> Void

    init(handler: @escaping @Sendable (SyncServiceState) -> Void) {
        self.handler = handler
    }

    func onUpdate(state: SyncServiceState) {
        handler(state)
    }
}

/// Implémentation de ``SyncController`` adossée au SDK Rust.
public final class RustSyncController: SyncController {
    private let service: any SyncServiceDriving

    init(service: any SyncServiceDriving) {
        self.service = service
    }

    /// Flux d'états. Politique `.bufferingNewest(1)` : seul l'état courant a de la valeur.
    public var state: AsyncStream<SyncState> {
        let service = service
        return ffiStream(
            bufferingPolicy: .bufferingNewest(1),
            makeListener: { emit in
                StateObserver { state in emit(SyncStateMapper.map(state)) }
            },
            subscribe: { listener in service.observeState(listener) }
        )
    }

    public func start() async {
        await service.start()
    }

    public func stop() async {
        await service.stop()
    }
}
