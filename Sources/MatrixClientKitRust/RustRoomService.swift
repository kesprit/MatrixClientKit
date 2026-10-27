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

/// Le résultat d'`entriesWithDynamicAdapters`, libéré client encore vivant : la boîte qui le
/// retient le relâche après la fin de la tâche du flux, hors de toute `withExtendedLifetime`.
private final class EntriesSubscription: @unchecked Sendable {
    private let lifetime: ClientLifetime
    private var result: RoomListEntriesWithDynamicAdaptersResult?

    init(result: RoomListEntriesWithDynamicAdaptersResult, lifetime: ClientLifetime) {
        self.result = result
        self.lifetime = lifetime
    }

    deinit {
        lifetime.release(&result)
    }
}

/// Implémentation de ``RoomService`` adossée au SDK Rust.
public final class RustRoomService: RoomService {
    private let lifetime: ClientLifetime
    /// Retient le client interne du SDK : libéré par ``deinit`` à travers ``lifetime``, client
    /// encore vivant (voir ``ClientLifetime``). Écrit seulement par l'initialiseur et par
    /// ``deinit``, d'où `nonisolated(unsafe)`.
    nonisolated(unsafe) private var service: RoomListService?

    init(roomListService: RoomListService, lifetime: ClientLifetime) {
        self.lifetime = lifetime
        self.service = roomListService
    }

    deinit {
        lifetime.release(&service)
    }

    private var roomListService: RoomListService {
        guard let service else {
            // Inatteignable : `service` n'est vidé que par `deinit`.
            preconditionFailure("RustRoomService used after deinitialization")
        }
        return service
    }

    // Les flux retiennent le service lui-même, jamais un objet FFI nu : une liste gardée par
    // l'application après la session retient, côté Rust, le client interne (`RoomList`, résultat
    // de `entriesWithDynamicAdapters`, `Room` des mises à jour en attente). Tant que le service
    // vit, sa ``ClientLifetime`` garde le `Client` FFI, qui part donc après eux.
    public func list(filter: RoomFilter) -> AsyncStream<[RoomSummary]> {
        let filterKind = RoomMapper.filterKind(for: filter)

        // Traduction des mises à jour amont en diffs du domaine, en préservant l'ordre. Le flux
        // brut est créé dans la tâche : les mises à jour qu'il tamponne encore à la fin de la
        // tâche sont libérées avec lui, service encore retenu par la closure.
        let diffs = AsyncStream<[CollectionDiff<RoomSummary>]>(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                let updates = self.updates(filterKind: filterKind)
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

    /// Flux brut des mises à jour amont, en .unbounded : aucun diff ne doit être perdu.
    private func updates(filterKind: RoomListEntriesDynamicFilterKind) -> AsyncStream<[RoomListEntriesUpdate]> {
        AsyncStream<[RoomListEntriesUpdate]>(bufferingPolicy: .unbounded) { continuation in
            let box = HandleBox()
            let task = Task {
                do {
                    let roomList = try await self.roomListService.allRooms()
                    let listener = EntriesListener { continuation.yield($0) }
                    let result = roomList.entriesWithDynamicAdapters(pageSize: 50, listener: listener)

                    // `result` garde le `RoomList` que la tâche du flux, lancée par l'appel
                    // ci-dessus, emprunte par un pointeur brut (source FFI) : il ne doit tomber
                    // qu'après la fin de cette tâche. La boîte s'en charge
                    // (``HandleBox/release(_:after:timeout:)``), à travers la ``ClientLifetime``
                    // car il peut alors être le dernier détenteur du client. Confié à la boîte
                    // avant toute sortie, y compris celle d'un filtre refusé.
                    box.store(
                        result.entriesStream(),
                        retaining: EntriesSubscription(result: result, lifetime: self.lifetime)
                    )

                    // `setFilter` dit si le filtre a bien été posé. Ignorer ce booléen livrerait,
                    // sous le nom de « rooms rejointes », la liste complète — rooms quittées et
                    // bannies comprises. Une liste qui répond à une autre question que celle
                    // posée est pire qu'une absence de liste : on termine le flux, après avoir
                    // arrêté la tâche amont (libération différée, voir plus haut).
                    guard result.controller().setFilter(kind: filterKind) else {
                        box.cancel()
                        continuation.finish()
                        return
                    }
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
            // handle n'existe. `self` retenu le temps de l'annulation ; le résultat amont, lui,
            // est relâché plus tard par la boîte, à travers la ``ClientLifetime``.
            continuation.onTermination = { _ in
                withExtendedLifetime(self) {
                    task.cancel()
                    box.cancel()
                }
            }
        }
    }

    public func room(_ id: RoomID) async throws -> any RoomHandle {
        do {
            let room = try roomListService.room(roomId: id.rawValue)
            return RustRoomHandle(id: id, room: room, lifetime: lifetime)
        } catch {
            throw ErrorMapper.map(error)
        }
    }
}

/// Implémentation de ``RoomHandle`` adossée au SDK Rust.
public final class RustRoomHandle: RoomHandle {
    public let id: RoomID
    private let lifetime: ClientLifetime
    /// Retient le client interne du SDK : libéré par ``deinit`` à travers ``lifetime``, client
    /// encore vivant (voir ``ClientLifetime``). Écrit seulement par l'initialiseur et par
    /// ``deinit``, d'où `nonisolated(unsafe)`.
    nonisolated(unsafe) private var ffiRoom: Room?

    init(id: RoomID, room: Room, lifetime: ClientLifetime) {
        self.id = id
        self.lifetime = lifetime
        self.ffiRoom = room
    }

    deinit {
        lifetime.release(&ffiRoom)
    }

    private var room: Room {
        guard let ffiRoom else {
            // Inatteignable : `ffiRoom` n'est vidé que par `deinit`.
            preconditionFailure("RustRoomHandle used after deinitialization")
        }
        return ffiRoom
    }

    public func timeline() async throws -> any MatrixClientKitCore.Timeline {
        do {
            return RustTimeline(timeline: try await room.timeline(), lifetime: lifetime)
        } catch {
            throw ErrorMapper.map(error)
        }
    }
}
