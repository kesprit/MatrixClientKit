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
    ///   annulé — utile quand l'abonnement amont dépend d'un objet intermédiaire dont la durée
    ///   de vie réelle n'est pas documentée par les bindings.
    func store(_ handle: any TaskHandleProtocol, retaining object: AnyObject? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if isCancelled {
            handle.cancel()
        } else {
            self.handle = handle
            self.retained = object
        }
    }

    func cancel() {
        lock.lock()
        let handle = self.handle
        self.handle = nil
        self.retained = nil
        isCancelled = true
        lock.unlock()
        handle?.cancel()
    }
}
