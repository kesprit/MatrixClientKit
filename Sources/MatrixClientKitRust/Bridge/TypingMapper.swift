import MatrixClientKitCore
import MatrixRustSDK
import Synchronization

/// Listener de frappe conforme au protocole amont, alimenté par une closure.
private final class TypingListener: TypingNotificationsListener {
    private let handler: @Sendable ([String]) -> Void

    init(handler: @escaping @Sendable ([String]) -> Void) {
        self.handler = handler
    }

    func call(typingUserIds: [String]) {
        handler(typingUserIds)
    }
}

/// Traduit les notifications de frappe amont vers le domaine.
enum TypingMapper {

    /// Les membres qui écrivent, dans l'ordre amont, sans l'utilisateur courant.
    ///
    /// - Note: les bindings ne disent pas si l'amont inclut l'utilisateur courant ; le filtrage
    ///   est fait ici pour ne pas dépendre de ce comportement. Un user ID invalide est écarté.
    static func users(from rawIDs: [String], excluding ownUserID: String) -> [UserID] {
        rawIDs.compactMap { rawID in
            rawID == ownUserID ? nil : UserID(rawValue: rawID)
        }
    }

    /// Délai au-delà duquel une liste non vide restée sans mise à jour retombe à `[]` : le délai
    /// de frappe usuel de Matrix.
    static let staleDelay: Duration = .seconds(30)

    /// Flux d'instantanés de frappe, en `.bufferingNewest(1)` : seule la dernière liste compte.
    ///
    /// Une liste non vide qui ne reçoit aucune nouvelle valeur pendant `staleAfter` est remplacée
    /// par `[]`. L'amont ne livre que les `m.typing` présents dans une réponse de synchronisation,
    /// sans état initial ni expiration : la liste vide perdue pendant une coupure (arrière-plan,
    /// réseau) laisserait sinon la dernière liste affichée indéfiniment.
    ///
    /// - Parameters:
    ///   - staleAfter: le délai d'expiration, injectable pour les tests.
    ///   - sleep: l'attente du délai, injectable pour les tests ; elle doit lever à l'annulation.
    static func stream(
        ownUserID: String,
        staleAfter: Duration = staleDelay,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        subscribe: @escaping @Sendable (any TypingNotificationsListener) throws -> any TaskHandleProtocol
    ) -> AsyncStream<[UserID]> {
        // Même schéma que ``ffiStream``, en un seul étage : le listener et le délai émettent dans
        // la même continuation, et la fin du flux annule l'abonnement et le délai.
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let expiry = StaleTypingExpiry(delay: staleAfter, sleep: sleep, continuation: continuation)
            let listener = TypingListener { expiry.receive(users(from: $0, excluding: ownUserID)) }

            do {
                let handle = try subscribe(listener)
                continuation.onTermination = { _ in
                    handle.cancel()
                    expiry.stop()
                }
            } catch {
                continuation.finish()
            }
        }
    }
}

/// Émet chaque instantané de frappe et arme, pour une liste non vide, un délai qui la remplace
/// par `[]` si aucune autre valeur n'arrive avant.
///
/// Une génération, incrémentée à chaque valeur, écarte un délai échu après qu'une nouvelle
/// valeur est arrivée : annuler sa tâche ne suffit pas, elle a pu se réveiller juste avant.
/// Émissions et génération sont sérialisées par le même verrou, comme dans ``FirstDeliveryGate``.
private final class StaleTypingExpiry: Sendable {
    private struct State {
        var generation = 0
        var timer: Task<Void, Never>?
    }

    private let state = Mutex(State())
    private let delay: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let continuation: AsyncStream<[UserID]>.Continuation

    init(
        delay: Duration,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        continuation: AsyncStream<[UserID]>.Continuation
    ) {
        self.delay = delay
        self.sleep = sleep
        self.continuation = continuation
    }

    func receive(_ snapshot: [UserID]) {
        state.withLock { state in
            state.generation += 1
            state.timer?.cancel()
            state.timer = nil
            continuation.yield(snapshot)
            guard !snapshot.isEmpty else { return }
            let generation = state.generation
            state.timer = Task { [self] in
                do {
                    try await sleep(delay)
                } catch {
                    return
                }
                expire(generation)
            }
        }
    }

    /// Annule le délai en cours ; un délai déjà échu n'émet plus rien.
    func stop() {
        state.withLock { state in
            state.generation += 1
            state.timer?.cancel()
            state.timer = nil
        }
    }

    private func expire(_ generation: Int) {
        state.withLock { state in
            guard state.generation == generation else { return }
            state.timer = nil
            continuation.yield([])
        }
    }
}
