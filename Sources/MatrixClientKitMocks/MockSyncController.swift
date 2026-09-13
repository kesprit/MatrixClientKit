import Foundation
import MatrixClientKitCore

/// Contrôleur de synchronisation pilotable pour les tests : compte les appels à ``start()`` et
/// ``stop()``, et permet de pousser des états arbitraires dans ``state``.
///
/// - Note: ``state`` expose un flux unique, mono-consommateur.
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

    /// Incrémente ``startCallCount`` et pousse ``SyncState/running`` dans ``state``.
    public func start() async {
        lock.withLock { _startCallCount += 1 }
        emit(.running)
    }

    /// Incrémente ``stopCallCount`` et pousse ``SyncState/idle`` dans ``state``.
    public func stop() async {
        lock.withLock { _stopCallCount += 1 }
        emit(.idle)
    }
}
