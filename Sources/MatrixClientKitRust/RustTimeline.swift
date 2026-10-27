import Synchronization
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

/// Liste ordonnée des ids d'éléments vus par **une** souscription à `items`.
private final class SubscriptionIDs: Sendable {
    let ids = Mutex<[String]>([])
}

/// Implémentation de ``Timeline`` adossée au SDK Rust.
public final class RustTimeline: MatrixClientKitCore.Timeline {
    private let lifetime: ClientLifetime
    /// Retient le client interne du SDK : libéré par ``deinit`` à travers ``lifetime``, client
    /// encore vivant (voir ``ClientLifetime``). Écrit seulement par l'initialiseur et par
    /// ``deinit``, d'où `nonisolated(unsafe)`.
    nonisolated(unsafe) private var ffiTimeline: MatrixRustSDK.Timeline?
    /// Handles d'envoi des échos locaux, par id d'élément. Une seule instance par timeline,
    /// partagée par toutes les souscriptions à ``items`` ; ses handles amont retiennent le client
    /// interne, d'où la même libération que ``ffiTimeline``.
    nonisolated(unsafe) private var registryStorage: SendHandleRegistry<MatrixRustSDK.SendHandle>?

    init(timeline: MatrixRustSDK.Timeline, lifetime: ClientLifetime) {
        self.lifetime = lifetime
        self.ffiTimeline = timeline
        self.registryStorage = SendHandleRegistry()
    }

    deinit {
        lifetime.release(&registryStorage)
        lifetime.release(&ffiTimeline)
    }

    private var registry: SendHandleRegistry<MatrixRustSDK.SendHandle> {
        guard let registryStorage else {
            // Inatteignable : `registryStorage` n'est vidé que par `deinit`.
            preconditionFailure("RustTimeline used after deinitialization")
        }
        return registryStorage
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
            // Plusieurs souscriptions peuvent coexister : elles alimentent toutes le même
            // registre, mais chacune tient sa propre liste d'ids, cohérente avec les diffs
            // qu'elle reçoit. Les mêmes diffs appliqués deux fois sont sans effet de bord
            // (`track` / `untrack` idempotents, `reset` repart de zéro).
            let subscription = SubscriptionIDs()
            // `self` faible : le listener vit côté amont tant que la souscription dure, et ne
            // doit retenir ni la timeline ni le registre — sinon des handles amont pourraient
            // être libérés hors de ``lifetime``. Le temps d'un appel, `self` retenu garantit le
            // client vivant pendant les appels FFI du suivi.
            let listener = ItemsListener { [weak self] updates in
                self?.track(updates, in: subscription)
                continuation.yield(updates.map(TimelineMapper.diff(from:)))
            }
            let task = Task {
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

    @discardableResult
    public func send(
        _ content: MatrixClientKitCore.MessageContent
    ) async throws -> any MatrixClientKitCore.SendHandle {
        do {
            let handle = try await timeline.send(msg: TimelineMapper.eventContent(for: content))
            return RustSendHandle(handle: handle, lifetime: lifetime)
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    @discardableResult
    public func send(
        _ attachment: MatrixClientKitCore.Attachment
    ) async throws -> any MatrixClientKitCore.AttachmentUpload {
        // La requête (taille du fichier comprise) se construit sans verrou et avant l'amont.
        let request = try MediaMapper.uploadRequest(for: attachment)
        do {
            let handle = try timeline.start(request)
            return RustAttachmentUpload(handle: handle, lifetime: lifetime)
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    public func sendHandle(
        for item: MatrixClientKitCore.TimelineItem
    ) -> (any MatrixClientKitCore.SendHandle)? {
        registry.handle(for: item.id).map { RustSendHandle(handle: $0, lifetime: lifetime) }
    }

    /// Tient le registre à jour à partir des diffs reçus par une souscription.
    private func track(_ updates: [TimelineDiff], in subscription: SubscriptionIDs) {
        // Appels FFI hors du verrou des ids (même discipline que ``HandleBox``).
        let entries = updates.map(Self.registryEntries(for:))
        let changes = subscription.ids.withLock { ids in
            entries.flatMap { SendHandleRegistry.changes(for: $0, ids: &ids) }
        }
        registry.apply(changes)
    }

    /// Traduit un diff amont en diff d'entrées du registre : un élément événement dont
    /// `localSendState` est `notSentYet` ou `sendingFailed` porte son handle ; un élément envoyé,
    /// distant ou virtuel n'en porte pas (il sera retiré du registre).
    static func registryEntries(
        for diff: TimelineDiff
    ) -> CollectionDiff<SendHandleRegistry<MatrixRustSDK.SendHandle>.Entry> {
        switch diff {
        case let .append(values): .append(values.map(registryEntry(for:)))
        case .clear: .clear
        case let .pushFront(value): .pushFront(registryEntry(for: value))
        case let .pushBack(value): .pushBack(registryEntry(for: value))
        case .popFront: .popFront
        case .popBack: .popBack
        case let .insert(index, value): .insert(index: Int(index), registryEntry(for: value))
        case let .set(index, value): .set(index: Int(index), registryEntry(for: value))
        case let .remove(index): .remove(index: Int(index))
        case let .truncate(length): .truncate(length: Int(length))
        case let .reset(values): .reset(values.map(registryEntry(for:)))
        }
    }

    private static func registryEntry(
        for item: MatrixRustSDK.TimelineItem
    ) -> SendHandleRegistry<MatrixRustSDK.SendHandle>.Entry {
        let id = item.uniqueId().id
        guard let event = item.asEvent() else { return .init(id: id, handle: nil) }
        switch event.localSendState {
        case .notSentYet, .sendingFailed:
            return .init(id: id, handle: event.lazyProvider.getSendHandle())
        case .sent, nil:
            return .init(id: id, handle: nil)
        }
    }
}
