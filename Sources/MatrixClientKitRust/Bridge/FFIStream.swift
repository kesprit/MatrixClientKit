import MatrixRustSDK

/// Convertit un abonnement à listener du SDK Rust en `AsyncStream`.
///
/// Le `TaskHandle` renvoyé par l'abonnement est capturé par la continuation et annulé dès que
/// le flux se termine — sortie de boucle, annulation de tâche ou libération du consommateur.
/// L'appelant n'a donc aucun cycle de vie à gérer.
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
