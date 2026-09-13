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

    /// Construit un résumé de room. Renvoie `nil` si l'identifiant amont est inexploitable.
    static func summary(from room: Room) async -> RoomSummary? {
        guard let id = RoomID(rawValue: room.id()) else { return nil }

        let info = try? await room.roomInfo()

        return RoomSummary(
            id: id,
            displayName: info?.displayName ?? room.displayName(),
            topic: info?.topic,
            avatarURL: info?.avatarUrl.flatMap(URL.init(string:)),
            isDirect: info?.isDirect ?? false,
            isEncrypted: info?.encryptionState == .encrypted,
            joinedMemberCount: Int(info?.joinedMembersCount ?? room.joinedMembersCount()),
            notificationCount: Int(info?.notificationCount ?? 0),
            highlightCount: Int(info?.highlightCount ?? 0),
            membership: info.map { membership(from: $0.membership) } ?? .joined
        )
    }

    /// Traduit une mise à jour de liste amont en diff de collection du domaine.
    static func diff(from update: RoomListEntriesUpdate) async -> CollectionDiff<RoomSummary>? {
        switch update {
        case let .append(values):
            return .append(await summaries(from: values))
        case .clear:
            return .clear
        case let .pushFront(value):
            guard let summary = await summary(from: value) else { return nil }
            return .pushFront(summary)
        case let .pushBack(value):
            guard let summary = await summary(from: value) else { return nil }
            return .pushBack(summary)
        case .popFront:
            return .popFront
        case .popBack:
            return .popBack
        case let .insert(index, value):
            guard let summary = await summary(from: value) else { return nil }
            return .insert(index: Int(index), summary)
        case let .set(index, value):
            guard let summary = await summary(from: value) else { return nil }
            return .set(index: Int(index), summary)
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
            if let summary = await summary(from: room) {
                result.append(summary)
            }
        }
        return result
    }
}
