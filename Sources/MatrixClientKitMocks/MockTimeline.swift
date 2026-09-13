import Foundation
import MatrixClientKitCore

/// Timeline pilotable pour les tests : pousse des instantanés à la demande et permet
/// d'observer les messages envoyés ou de simuler un échec d'envoi.
///
/// ``emit(_:)`` pousse un instantané, ``finish()`` termine le flux — même paire que
/// ``MockRoomService`` et ``MockSyncController``.
///
/// - Note: ``items`` expose un flux unique, mono-consommateur. N'itérer dessus qu'une seule
///   fois par instance.
public final class MockTimeline: Timeline, @unchecked Sendable {
    private let lock = NSLock()
    private let stream: AsyncStream<[TimelineItem]>
    private let continuation: AsyncStream<[TimelineItem]>.Continuation

    private var _sentMessages: [MessageContent] = []
    private var _sendError: MatrixError?
    private var _paginateResult = true

    public init() {
        (stream, continuation) = AsyncStream<[TimelineItem]>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    /// Flux d'instantanés de la timeline. Mono-consommateur : voir la note de type.
    public var items: AsyncStream<[TimelineItem]> { stream }

    /// Messages passés à ``send(_:)``, dans l'ordre d'envoi.
    public var sentMessages: [MessageContent] {
        lock.lock(); defer { lock.unlock() }
        return _sentMessages
    }

    /// Erreur à lever au prochain appel à ``send(_:)`` ou ``paginateBackwards(count:)``.
    /// `nil` par défaut : les appels réussissent.
    public var sendError: MatrixError? {
        get { lock.lock(); defer { lock.unlock() }; return _sendError }
        set { lock.lock(); _sendError = newValue; lock.unlock() }
    }

    /// Valeur renvoyée par ``paginateBackwards(count:)`` en l'absence de ``sendError``.
    /// `true` par défaut.
    public var paginateResult: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _paginateResult }
        set { lock.lock(); _paginateResult = newValue; lock.unlock() }
    }

    /// Pousse un nouvel instantané dans ``items``.
    public func emit(_ items: [TimelineItem]) {
        continuation.yield(items)
    }

    /// Termine le flux ``items``.
    ///
    /// - Important: sans cela, une boucle `for await` sur ``items`` ne rend jamais la main face à
    ///   ce mock.
    public func finish() {
        continuation.finish()
    }

    @discardableResult
    public func paginateBackwards(count: Int) async throws -> Bool {
        if let error = sendError { throw error }
        return paginateResult
    }

    public func send(_ content: MessageContent) async throws {
        if let error = sendError { throw error }
        lock.withLock { _sentMessages.append(content) }
    }
}
