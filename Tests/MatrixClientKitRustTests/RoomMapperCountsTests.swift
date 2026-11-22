import Testing
import MatrixRustSDK

@testable import MatrixClientKitRust

@Test func unreadCountsComeFromTheSDKComputedCountersNotTheServerOnes() {
    let info = roomInfo(serverNotifications: 9, serverHighlights: 8, unreadNotifications: 3, unreadMentions: 2)

    let counts = RoomMapper.unreadCounts(from: info)

    #expect(counts.notifications == 3)
    #expect(counts.mentions == 2)
}

@Test func unreadCountsDefaultToZeroWithoutRoomInfo() {
    let counts = RoomMapper.unreadCounts(from: nil)

    #expect(counts.notifications == 0)
    #expect(counts.mentions == 0)
}

@Test func unreadCountsAreClampedRatherThanTrapping() {
    let info = roomInfo(
        serverNotifications: 0, serverHighlights: 0, unreadNotifications: .max, unreadMentions: .max)

    let counts = RoomMapper.unreadCounts(from: info)

    #expect(counts.notifications == Int.max)
    #expect(counts.mentions == Int.max)
}

private func roomInfo(
    serverNotifications: UInt64, serverHighlights: UInt64, unreadNotifications: UInt64, unreadMentions: UInt64
) -> RoomInfo {
    RoomInfo(
        id: "!room:localhost", encryptionState: .notEncrypted, creators: nil, displayName: nil, rawName: nil,
        topic: nil, avatarUrl: nil, isDirect: false, isDm: false, isPublic: nil, isSpace: false,
        successorRoom: nil, isFavourite: false, isLowPriority: false, canonicalAlias: nil,
        alternativeAliases: [], membership: .joined, inviter: nil, heroes: [], activeMembersCount: 2,
        invitedMembersCount: 0, joinedMembersCount: 2, activeServiceMembersCount: 0, serviceMembers: [],
        highlightCount: serverHighlights, notificationCount: serverNotifications,
        cachedUserDefinedNotificationMode: nil, hasRoomCall: false, activeRoomCallParticipants: [],
        activeRoomCallConsensusIntent: .none, isMarkedUnread: false, numUnreadMessages: 0,
        numUnreadNotifications: unreadNotifications, numUnreadMentions: unreadMentions, fullyReadEventId: nil,
        pinnedEventIds: [], joinRule: nil, historyVisibility: .shared, powerLevels: nil, roomVersion: nil,
        privilegedCreatorsRole: false)
}
