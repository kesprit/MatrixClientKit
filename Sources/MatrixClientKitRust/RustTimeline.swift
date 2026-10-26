import MatrixRustSDK
import MatrixClientKitCore

/// Listener de timeline conforme au protocole amont, alimenté par une closure.
private final class ItemsListener: TimelineListener {
    private let handler: @Sendable ([TimelineDiff]) -> Void

    init(handler: @escaping @Sendable ([TimelineDiff]) -> Void) {
        self.handler = handler
    }

    func onUpdate(diff: [TimelineDiff]) {
        handler(diff)
    }
}

/// Implémentation de ``Timeline`` adossée au SDK Rust.
public final class RustTimeline: MatrixClientKitCore.Timeline {
    private let lifetime: ClientLifetime
    /// Retient le client interne du SDK : libéré par ``deinit`` à travers ``lifetime``, client
    /// encore vivant (voir ``ClientLifetime``). Écrit seulement par l'initialiseur et par
    /// ``deinit``, d'où `nonisolated(unsafe)`.
    nonisolated(unsafe) private var ffiTimeline: MatrixRustSDK.Timeline?

    init(timeline: MatrixRustSDK.Timeline, lifetime: ClientLifetime) {
        self.lifetime = lifetime
        self.ffiTimeline = timeline
    }

    deinit {
        lifetime.release(&ffiTimeline)
    }

    private var timeline: MatrixRustSDK.Timeline {
        guard let ffiTimeline else {
            // Inatteignable : `ffiTimeline` n'est vidé que par `deinit`.
            preconditionFailure("RustTimeline used after deinitialization")
        }
        return ffiTimeline
    }

    public var items: AsyncStream<[MatrixClientKitCore.TimelineItem]> {
        // Flux brut de diffs, en .unbounded : chaque diff se compose avec le précédent.
        let diffs = AsyncStream<[CollectionDiff<MatrixClientKitCore.TimelineItem>]>(
            bufferingPolicy: .unbounded
        ) { continuation in
            let box = HandleBox()
            let task = Task {
                let listener = ItemsListener { updates in
                    continuation.yield(updates.map(TimelineMapper.diff(from:)))
                }
                // `self` plutôt que la timeline FFI : la tâche ne doit pas en devenir le dernier
                // détenteur (voir ``ClientLifetime``).
                box.store(await self.timeline.addListener(listener: listener))
            }

            // Une seule assignation : annuler uniquement la tâche laisserait le listener déjà
            // enregistré en vie côté amont — il faut aussi annuler le handle, d'où la boîte
            // pour couvrir le cas où la terminaison arrive avant que le handle n'existe.
            // Pas de `withExtendedLifetime(self)` ici, contrairement à `RustRoomService` : la boîte
            // ne retient qu'un `TaskHandle`, qui ne retient pas le client interne côté Swift.
            continuation.onTermination = { _ in
                task.cancel()
                box.cancel()
            }
        }

        return snapshotStream(from: diffs)
    }

    /// - Note: `count` est ramené dans les bornes de `UInt16` attendues par l'amont plutôt que
    ///   converti sèchement : une valeur négative ou supérieure à 65 535 ferait autrement planter
    ///   l'application appelante au lieu de lui rendre une erreur.
    @discardableResult
    public func paginateBackwards(count: Int) async throws -> Bool {
        do {
            return try await timeline.paginateBackwards(numEvents: UInt16(clamping: count))
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    public func send(_ content: MatrixClientKitCore.MessageContent) async throws {
        do {
            _ = try await timeline.send(msg: TimelineMapper.eventContent(for: content))
        } catch {
            throw ErrorMapper.map(error)
        }
    }
}
