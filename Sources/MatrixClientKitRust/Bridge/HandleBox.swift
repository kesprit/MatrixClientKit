import Foundation
import MatrixRustSDK

/// Retient un `TaskHandle` obtenu après un `await`, en composant avec une terminaison qui peut
/// survenir avant qu'il n'arrive.
///
/// Un flux basé sur une closure `Task` async ne peut pas assigner le handle à
/// `continuation.onTermination` directement : le handle n'existe qu'après un `await`, alors que
/// la terminaison peut arriver avant. Cette boîte capture les deux ordres d'arrivée sans perdre
/// l'annulation.
final class HandleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: (any TaskHandleProtocol)?
    private var retained: AnyObject?
    private var isCancelled = false

    /// Retient le handle, ou l'annule immédiatement si la terminaison a déjà eu lieu.
    ///
    /// - Parameter object: objet additionnel à garder en vie tant que le handle n'est pas
    ///   annulé **et** sa tâche terminée (voir ``release(_:after:timeout:)``) — utile quand
    ///   l'abonnement amont dépend d'un objet intermédiaire, voire l'emprunte sans le retenir.
    /// - Important: comme ``cancel()``, cette méthode relâche le verrou **avant** d'appeler du
    ///   code amont. Aucun blocage n'existe aujourd'hui, mais tenir un verrou pendant un appel
    ///   vers du code dont on ne contrôle pas l'implémentation est la discipline qui, un jour de
    ///   changement amont, produit un interblocage introuvable.
    func store(_ handle: any TaskHandleProtocol, retaining object: AnyObject? = nil) {
        lock.lock()
        let wasCancelled = isCancelled
        if !wasCancelled {
            self.handle = handle
            self.retained = object
        }
        lock.unlock()

        if wasCancelled {
            handle.cancel()
            if let object { Self.release(object, after: handle) }
        }
    }

    func cancel() {
        lock.lock()
        let handle = self.handle
        let retained = self.retained
        self.handle = nil
        self.retained = nil
        isCancelled = true
        lock.unlock()
        handle?.cancel()
        if let retained, let handle { Self.release(retained, after: handle) }
    }

    /// Libère `object` une fois la tâche de `handle` terminée, jamais avant.
    ///
    /// L'annulation amont est asynchrone : une tâche Tokio en plein `poll` sur un autre fil finit
    /// ce `poll`. Or l'objet retenu peut porter ce que la tâche emprunte sans le retenir —
    /// `RoomListEntriesWithDynamicAdaptersResult` garde le `RoomList` que son flux emprunte par
    /// un pointeur brut. Le libérer tout de suite provoquait un accès mémoire invalide sur le fil
    /// Tokio (`SIGSEGV`, constaté contre Synapse en interrompant `rooms.list` juste après une
    /// valeur). Une tâche qui ne se termine pas dans `timeout` garde l'objet à jamais : une fuite
    /// vaut mieux qu'une libération sous ses pieds.
    static func release(
        _ object: AnyObject,
        after handle: any TaskHandleProtocol,
        timeout: Duration = .seconds(10)
    ) {
        if handle.isFinished() { return }
        let pending = PendingRelease(object)
        Task.detached {
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                if handle.isFinished() { return }
                try? await Task.sleep(for: .milliseconds(10))
            }
            pending.leak()
        }
    }
}

/// Objet à libérer plus tard, depuis une tâche détachée. Lu et écrit par cette seule tâche.
private final class PendingRelease: @unchecked Sendable {
    private let object: AnyObject

    init(_ object: AnyObject) {
        self.object = object
    }

    func leak() {
        _ = Unmanaged.passRetained(object)
    }
}
