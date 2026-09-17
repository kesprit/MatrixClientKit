import Foundation
import Synchronization

/// Diffuse une valeur d'état courante à un nombre quelconque d'abonnés.
///
/// Chaque abonné reçoit d'abord la valeur courante, puis chaque changement. La transformation et
/// la diffusion ont lieu sous le même verrou, de façon synchrone : deux mises à jour successives,
/// venues de callbacks amont synchrones, sont vues dans cet ordre par tous les abonnés. Un acteur
/// imposerait un `Task` par callback et ne garantirait plus cet ordre — `didStartSasVerification`
/// pourrait alors être appliqué après `didReceiveVerificationData`.
///
/// - Important: `transform` s'exécute sous le verrou. Il ne doit appeler ni code amont ni
///   `update(_:)` : `Mutex` n'est pas réentrant.
final class StateBroadcaster<Value: Sendable & Equatable>: Sendable {
    private struct Storage {
        var value: Value
        var continuations: [UUID: AsyncStream<Value>.Continuation] = [:]
    }

    private let storage: Mutex<Storage>

    init(_ initialValue: Value) {
        storage = Mutex(Storage(value: initialValue))
    }

    var value: Value {
        storage.withLock { $0.value }
    }

    /// Nombre d'abonnements vivants. Exposé pour les tests.
    var subscriberCount: Int {
        storage.withLock { $0.continuations.count }
    }

    func stream() -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream<Value>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()

        storage.withLock { storage in
            continuation.yield(storage.value)
            storage.continuations[id] = continuation
        }

        continuation.onTermination = { [weak self] _ in
            self?.storage.withLock { _ = $0.continuations.removeValue(forKey: id) }
        }
        return stream
    }

    /// Applique `transform` à la valeur courante et diffuse le résultat s'il diffère.
    ///
    /// - Returns: la valeur après transformation.
    @discardableResult
    func update(_ transform: (Value) -> Value) -> Value {
        storage.withLock { storage in
            let newValue = transform(storage.value)
            guard newValue != storage.value else { return newValue }

            storage.value = newValue
            for continuation in storage.continuations.values {
                continuation.yield(newValue)
            }
            return newValue
        }
    }
}
