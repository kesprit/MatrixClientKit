import MatrixRustSDK
import Synchronization

/// Convertit un abonnement à listener du SDK Rust en `AsyncStream`.
///
/// Le `TaskHandle` renvoyé par l'abonnement est capturé par la continuation et annulé dès que
/// le flux se termine, ce qui arrive dans l'un de ces trois cas : la tâche consommatrice est
/// annulée, le flux se termine de lui-même, ou le flux et son itérateur sont libérés.
/// L'appelant n'a donc aucun cycle de vie à gérer — à une réserve près : conserver une
/// référence forte au flux (par exemple le stocker dans une propriété) maintient l'abonnement
/// amont en vie même après être sorti de la boucle. Un appelant qui stocke un flux doit le
/// libérer pour libérer l'abonnement.
///
/// - Parameters:
///   - bufferingPolicy: `.unbounded` pour un flux de diffs, où perdre un élément corrompt
///     l'état ; `.bufferingNewest(1)` pour un flux d'instantanés, où seule la dernière valeur
///     compte.
///   - makeListener: construit le listener attendu par le SDK à partir d'une closure d'émission.
///   - subscribe: réalise l'abonnement et renvoie le handle d'annulation.
func ffiStream<Element: Sendable, Listener>(
    bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy,
    makeListener: @escaping @Sendable (@escaping @Sendable (Element) -> Void) -> Listener,
    subscribe: @escaping @Sendable (Listener) throws -> any TaskHandleProtocol
) -> AsyncStream<Element> {
    AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
        let listener = makeListener { element in
            continuation.yield(element)
        }

        do {
            let handle = try subscribe(listener)
            continuation.onTermination = { _ in
                handle.cancel()
            }
        } catch {
            continuation.finish()
        }
    }
}

/// Variante de ``ffiStream`` pour un état dont l'amont expose aussi une lecture synchrone.
///
/// Le flux émet d'abord la valeur courante, puis chaque mise à jour du listener, en
/// `.bufferingNewest(1)`. Sans cette première valeur, un écran ouvert après le dernier changement
/// resterait vide indéfiniment.
///
/// L'abonnement est posé **avant** la lecture de la valeur courante, et celle-ci n'est émise que
/// si le listener n'a encore rien livré. Lue avant l'abonnement, elle pourrait manquer un
/// changement survenu entre les deux ; émise après une valeur du listener, elle remplacerait un
/// état récent par un état périmé.
func ffiStateStream<Element: Sendable, Listener>(
    current: @escaping @Sendable () -> Element,
    makeListener: @escaping @Sendable (@escaping @Sendable (Element) -> Void) -> Listener,
    subscribe: @escaping @Sendable (Listener) throws -> any TaskHandleProtocol
) -> AsyncStream<Element> {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
        let gate = FirstDeliveryGate()
        let listener = makeListener { element in
            gate.deliver { continuation.yield(element) }
        }

        do {
            let handle = try subscribe(listener)
            continuation.onTermination = { _ in
                handle.cancel()
            }
        } catch {
            continuation.finish()
            return
        }

        let initial = current()
        gate.deliverUnlessAlreadyDelivered { continuation.yield(initial) }
    }
}

/// Sérialise les émissions d'un flux d'état et retient si le listener a déjà livré une valeur.
private final class FirstDeliveryGate: Sendable {
    private let hasDelivered = Mutex(false)

    func deliver(_ body: () -> Void) {
        hasDelivered.withLock { hasDelivered in
            hasDelivered = true
            body()
        }
    }

    func deliverUnlessAlreadyDelivered(_ body: () -> Void) {
        hasDelivered.withLock { hasDelivered in
            guard !hasDelivered else { return }
            hasDelivered = true
            body()
        }
    }
}
