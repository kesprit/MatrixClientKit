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
    private var isCancelled = false

    /// Retient le handle, ou l'annule immédiatement si la terminaison a déjà eu lieu.
    func store(_ handle: any TaskHandleProtocol) {
        lock.lock()
        defer { lock.unlock() }
        if isCancelled {
            handle.cancel()
        } else {
            self.handle = handle
        }
    }

    func cancel() {
        lock.lock()
        let handle = self.handle
        self.handle = nil
        isCancelled = true
        lock.unlock()
        handle?.cancel()
    }
}
