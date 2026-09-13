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
                    _ = result.controller().setFilter(kind: filterKind)

                    // `entriesStream()` renvoie un `TaskHandle`, et le SDK documente ce type
                    // comme « a way to keep the handle a task running by itself in detached
                    // mode » (matrix_sdk_ffi.swift, TaskHandleProtocol) : la tâche amont tourne
                    // de façon détachée une fois lancée, indépendamment de la durée de vie de
                    // `result`. L'appel est synchrone — la tâche est déjà démarrée avant que
                    // `entriesStream()` ne retourne — donc `result` (et son `controller()`,
                    // utilisé une seule fois ici) peut être relâché sans arrêter la
                    // souscription. C'est le même schéma que `RustTimeline.items`, où
                    // `timeline.addListener()` renvoie directement un `TaskHandle` détaché sans
                    // qu'aucun autre objet ne soit retenu.
                    box.store(result.entriesStream())
                } catch {
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
                    for update in batch {
                        if let diff = await RoomMapper.diff(from: update) {
                            translated.append(diff)
                        }
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
