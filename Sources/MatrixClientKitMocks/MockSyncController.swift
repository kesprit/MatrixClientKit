import Foundation
import MatrixClientKitCore

/// Contrôleur de synchronisation pilotable pour les tests : compte les appels à ``start()`` et
/// ``stop()``, et permet de pousser des états arbitraires dans ``state``.
///
/// ``emit(_:)`` pousse un état, ``finish()`` termine le flux — même paire que ``MockTimeline`` et
/// ``MockRoomService``.
///
/// - Note: ``state`` expose un flux unique, mono-consommateur.
/// - Note: ``start()`` et ``stop()`` imitent la séquence d'états produite par le contrôleur réel
///   (`.running` puis `.terminated`) pour qu'un `switch` testé contre ce mock reste valide face
///   au vrai homeserver. C'est une commodité pour les tests, pas une garantie du protocole : rien
///   n'empêche d'``emit(_:)`` n'importe quel autre ``SyncState`` pour couvrir un cas particulier.
public final class MockSyncController: SyncController, @unchecked Sendable {
    private let lock = NSLock()
    private let stream: AsyncStream<SyncState>
    private let continuation: AsyncStream<SyncState>.Continuation

    private var _startCallCount = 0
    private var _stopCallCount = 0

    public init() {
        (stream, continuation) = AsyncStream<SyncState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    /// Flux de l'état de synchronisation. Mono-consommateur : voir la note de type.
    public var state: AsyncStream<SyncState> { stream }

    /// Nombre d'appels à ``start()`` depuis la création du mock.
    public var startCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _startCallCount
    }

    /// Nombre d'appels à ``stop()`` depuis la création du mock.
    public var stopCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _stopCallCount
    }

    /// Pousse un nouvel état dans ``state``.
    public func emit(_ state: SyncState) {
        continuation.yield(state)
    }

    /// Termine le flux ``state``.
    ///
    /// - Important: sans cela, une boucle `for await` sur ``state`` ne rend jamais la main face à
    ///   ce mock.
    public func finish() {
        continuation.finish()
    }

    /// Incrémente ``startCallCount`` et pousse ``SyncState/running`` dans ``state``.
    public func start() async {
        lock.withLock { _startCallCount += 1 }
        emit(.running)
    }

    /// Incrémente ``stopCallCount`` et pousse ``SyncState/terminated`` dans ``state``.
    public func stop() async {
        lock.withLock { _stopCallCount += 1 }
        emit(.terminated)
    }
}
