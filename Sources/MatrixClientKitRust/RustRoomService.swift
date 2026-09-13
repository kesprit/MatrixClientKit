import MatrixRustSDK
import MatrixClientKitCore

/// Listener d'entrées de liste conforme au protocole amont, alimenté par une closure.
private final class EntriesListener: RoomListEntriesListener {
    private let handler: @Sendable ([RoomListEntriesUpdate]) -> Void

    init(handler: @escaping @Sendable ([RoomListEntriesUpdate]) -> Void) {
        self.handler = handler
    }

    func onUpdate(roomEntriesUpdate: [RoomListEntriesUpdate]) {
        handler(roomEntriesUpdate)
    }
}

/// Implémentation de ``RoomService`` adossée au SDK Rust.
public final class RustRoomService: RoomService {
    private let roomListService: RoomListService

    init(roomListService: RoomListService) {
        self.roomListService = roomListService
    }

    public func list(filter: RoomFilter) -> AsyncStream<[RoomSummary]> {
        let service = roomListService
        let filterKind = RoomMapper.filterKind(for: filter)

        // Flux brut des mises à jour amont, en .unbounded : aucun diff ne doit être perdu.
        let updates = AsyncStream<[RoomListEntriesUpdate]>(bufferingPolicy: .unbounded) { continuation in
            let box = HandleBox()
            let task = Task {
                do {
                    let roomList = try await service.allRooms()
                    let listener = EntriesListener { continuation.yield($0) }
                    let result = roomList.entriesWithDynamicAdapters(pageSize: 50, listener: listener)

                    // `setFilter` dit si le filtre a bien été posé. Ignorer ce booléen livrerait,
                    // sous le nom de « rooms rejointes », la liste complète — rooms quittées et
                    // bannies comprises. Une liste qui répond à une autre question que celle
                    // posée est pire qu'une absence de liste : on termine le flux.
                    guard result.controller().setFilter(kind: filterKind) else {
                        continuation.finish()
                        return
                    }

                    // Les bindings ne documentent pas si l'abonnement survit à la libération de
                    // `result` : `entriesWithDynamicAdapters` renvoie un objet intermédiaire
                    // (`controller()` / `entriesStream()`) — contrairement à
                    // `RustTimeline.items`, où `addListener` renvoie directement le `TaskHandle`
                    // sans indirection —, et `result` comme le contrôleur qu'il expose libèrent
                    // leur côté Rust dans leur `deinit`. Faute de certitude, on retient `result`
                    // explicitement jusqu'à l'annulation plutôt que de parier sur une durée de
                    // vie non garantie : le coût d'une référence retenue est nul face au risque
                    // d'une liste qui cesse silencieusement de se mettre à jour.
                    box.store(result.entriesStream(), retaining: result)
                } catch {
                    // `AsyncStream` n'a pas de canal d'erreur : un abonnement qui échoue ne peut
                    // que terminer le flux sans valeur. Documenté comme tel sur
                    // ``RoomService/list(filter:)``.
                    continuation.finish()
                }
            }

            // Une seule assignation : annuler uniquement la tâche laisserait la souscription
            // amont en vie si la terminaison arrive après le `await` — il faut aussi annuler le
            // handle, d'où la boîte pour couvrir le cas où la terminaison arrive avant que le
            // handle n'existe.
            continuation.onTermination = { _ in
                task.cancel()
                box.cancel()
            }
        }

        // Traduction des mises à jour amont en diffs du domaine, en préservant l'ordre.
        let diffs = AsyncStream<[CollectionDiff<RoomSummary>]>(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                for await batch in updates {
                    var translated: [CollectionDiff<RoomSummary>] = []
                    translated.reserveCapacity(batch.count)
                    for update in batch {
                        translated.append(await RoomMapper.diff(from: update))
                    }
                    continuation.yield(translated)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        return snapshotStream(from: diffs)
    }

    public func room(_ id: RoomID) async throws -> any RoomHandle {
        do {
            let room = try roomListService.room(roomId: id.rawValue)
            return RustRoomHandle(id: id, room: room)
        } catch {
            throw ErrorMapper.map(error)
        }
    }
}

/// Implémentation de ``RoomHandle`` adossée au SDK Rust.
public final class RustRoomHandle: RoomHandle {
    public let id: RoomID
    private let room: Room

    init(id: RoomID, room: Room) {
        self.id = id
        self.room = room
    }

    public func timeline() async throws -> any MatrixClientKitCore.Timeline {
        do {
            return RustTimeline(timeline: try await room.timeline())
        } catch {
            throw ErrorMapper.map(error)
        }
    }
}
