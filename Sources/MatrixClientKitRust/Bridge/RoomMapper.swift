import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Traduit les types de room amont vers le domaine.
enum RoomMapper {

    static func filterKind(for filter: RoomFilter) -> RoomListEntriesDynamicFilterKind {
        switch filter {
        case .all: .all(filters: [])
        case .joined: .joined
        case .invited: .invite
        }
    }

    static func membership(from membership: MatrixRustSDK.Membership) -> MatrixClientKitCore.Membership {
        switch membership {
        case .joined: .joined
        case .invited: .invited
        case .left: .left
        case .knocked: .knocked
        case .banned: .banned
        }
    }

    /// Construit un résumé de room. Retombe sur ``placeholderSummary()`` si l'identifiant amont
    /// est inexploitable : les diffs amont portent des index absolus, et écarter une entrée
    /// désalignerait toutes les positions suivantes.
    static func summary(from room: Room) async -> RoomSummary {
        let rawIdentifier = room.id()
        guard let id = RoomID(rawValue: rawIdentifier) else {
            return placeholderSummary(for: rawIdentifier)
        }

        let info = try? await room.roomInfo()

        return RoomSummary(
            id: id,
            displayName: info?.displayName ?? room.displayName(),
            topic: info?.topic,
            avatarURL: info?.avatarUrl.flatMap(URL.init(string:)),
            isDirect: info?.isDirect ?? false,
            isEncrypted: info.map { $0.encryptionState == .encrypted },
            // Compteurs `UInt64` venant du homeserver : bornés plutôt que convertis sèchement.
            // Une valeur aberrante — serveur hostile ou bogué — ferait sinon planter
            // l'application appelante à la traduction d'un simple résumé de room.
            joinedMemberCount: Int(clamping: info?.joinedMembersCount ?? room.joinedMembersCount()),
            notificationCount: Int(clamping: info?.notificationCount ?? 0),
            highlightCount: Int(clamping: info?.highlightCount ?? 0),
            membership: info.map { membership(from: $0.membership) } ?? .unknown
        )
    }

    /// Résumé de repli pour une room dont l'identifiant amont est inexploitable.
    ///
    /// Écarter la room décalerait toutes les positions suivantes : les diffs amont portent des
    /// index absolus, et en retirer un désaligne la liste entière. On conserve donc la place,
    /// avec une entrée visiblement incomplète plutôt qu'une liste silencieusement fausse.
    ///
    /// - Important: l'identifiant est **dérivé** de la valeur amont, pas tiré au hasard. Un
    ///   `UUID()` neuf à chaque appel donnerait à la même room une identité différente à chaque
    ///   diff : `ForEach` détruirait et reconstruirait la ligne à chaque mise à jour de la liste.
    ///   L'empreinte garde l'entrée stable tout en restant manifestement factice.
    static func placeholderSummary(for rawIdentifier: String) -> RoomSummary {
        RoomSummary(
            id: RoomID(rawValue: "!unparseable-\(StableDigest.short(rawIdentifier))")!,
            displayName: nil,
            topic: nil,
            avatarURL: nil,
            isDirect: false,
            isEncrypted: nil,
            joinedMemberCount: 0,
            notificationCount: 0,
            highlightCount: 0,
            membership: .unknown
        )
    }

    /// Traduit une mise à jour de liste amont en diff de collection du domaine.
    static func diff(from update: RoomListEntriesUpdate) async -> CollectionDiff<RoomSummary> {
        switch update {
        case let .append(values):
            return .append(await summaries(from: values))
        case .clear:
            return .clear
        case let .pushFront(value):
            return .pushFront(await summary(from: value))
        case let .pushBack(value):
            return .pushBack(await summary(from: value))
        case .popFront:
            return .popFront
        case .popBack:
            return .popBack
        case let .insert(index, value):
            return .insert(index: Int(index), await summary(from: value))
        case let .set(index, value):
            return .set(index: Int(index), await summary(from: value))
        case let .remove(index):
            return .remove(index: Int(index))
        case let .truncate(length):
            return .truncate(length: Int(length))
        case let .reset(values):
            return .reset(await summaries(from: values))
        }
    }

    private static func summaries(from rooms: [Room]) async -> [RoomSummary] {
        var result: [RoomSummary] = []
        result.reserveCapacity(rooms.count)
        for room in rooms {
            result.append(await summary(from: room))
        }
        return result
    }
}
