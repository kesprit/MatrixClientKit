import Testing
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

@Test func joinedFilterMapsToUpstreamJoinedFilter() {
    guard case .joined = RoomMapper.filterKind(for: .joined) else {
        Issue.record("attendu .joined")
        return
    }
}

@Test func invitedFilterMapsToUpstreamInviteFilter() {
    guard case .invite = RoomMapper.filterKind(for: .invited) else {
        Issue.record("attendu .invite")
        return
    }
}

@Test func allFilterMapsToAnEmptyConjunction() {
    guard case let .all(filters) = RoomMapper.filterKind(for: .all) else {
        Issue.record("attendu .all")
        return
    }
    #expect(filters.isEmpty)
}

@Test func membershipIsMappedForEveryUpstreamCase() {
    #expect(RoomMapper.membership(from: .joined) == .joined)
    #expect(RoomMapper.membership(from: .invited) == .invited)
    #expect(RoomMapper.membership(from: .left) == .left)
    #expect(RoomMapper.membership(from: .knocked) == .knocked)
    #expect(RoomMapper.membership(from: .banned) == .banned)
}
