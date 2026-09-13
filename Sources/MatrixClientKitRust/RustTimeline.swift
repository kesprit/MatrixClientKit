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
    private let timeline: MatrixRustSDK.Timeline

    init(timeline: MatrixRustSDK.Timeline) {
        self.timeline = timeline
    }

    public var items: AsyncStream<[MatrixClientKitCore.TimelineItem]> {
        let timeline = timeline

        // Flux brut de diffs, en .unbounded : chaque diff se compose avec le précédent.
        let diffs = AsyncStream<[CollectionDiff<MatrixClientKitCore.TimelineItem>]>(
            bufferingPolicy: .unbounded
        ) { continuation in
            let box = HandleBox()
            let task = Task {
                let listener = ItemsListener { updates in
                    continuation.yield(updates.map(TimelineMapper.diff(from:)))
                }
                box.store(await timeline.addListener(listener: listener))
            }

            // Une seule assignation : annuler uniquement la tâche laisserait le listener déjà
            // enregistré en vie côté amont — il faut aussi annuler le handle, d'où la boîte
            // pour couvrir le cas où la terminaison arrive avant que le handle n'existe.
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
