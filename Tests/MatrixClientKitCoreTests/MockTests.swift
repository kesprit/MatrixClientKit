import Testing
import Foundation
import MatrixClientKitCore
import MatrixClientKitMocks

@Test func mockTimelineDeliversEmittedItems() async {
    let timeline = MockTimeline()
    let stream = timeline.items

    timeline.emit([SampleData.message("bonjour", from: "@alice:matrix.org")])

    for await items in stream {
        #expect(items.count == 1)
        #expect(items.first?.message?.body == "bonjour")
        break
    }
}

@Test func mockTimelineRecordsSentMessages() async throws {
    let timeline = MockTimeline()
    try await timeline.send(.text("salut"))
    #expect(timeline.sentMessages == [.text("salut")])
}

@Test func mockTimelineCanSimulateAFailure() async {
    let timeline = MockTimeline()
    timeline.sendError = .network(.offline)

    await #expect(throws: MatrixError.network(.offline)) {
        try await timeline.send(.text("salut"))
    }
}

@Test func mockRoomServiceDeliversSampleRooms() async {
    let service = MockRoomService(rooms: SampleData.roomSummaries(count: 3))

    for await rooms in service.list(filter: .joined) {
        #expect(rooms.count == 3)
        break
    }
}

@Test func mockSessionExposesItsServices() async {
    let session = MockMatrixSession()
    #expect(session.userID.rawValue == "@alice:matrix.org")

    await session.sync.start()
    #expect((session.sync as? MockSyncController)?.startCallCount == 1)
}

@Test func mockSyncControllerEmitsRunningThenTerminated() async {
    let sync = MockSyncController()
    var iterator = sync.state.makeAsyncIterator()

    await sync.start()
    #expect(await iterator.next() == .running)

    await sync.stop()
    #expect(await iterator.next() == .terminated)
}

private func invitedRoom(id: String) -> RoomSummary {
    RoomSummary(
        id: RoomID(rawValue: id)!,
        displayName: "Invitation",
        topic: nil,
        avatarURL: nil,
        isDirect: false,
        isEncrypted: true,
        joinedMemberCount: 2,
        notificationCount: 0,
        highlightCount: 0,
        membership: .invited
    )
}

@Test func mockRoomServiceHonoursTheJoinedFilter() async throws {
    let service = MockRoomService(
        rooms: SampleData.roomSummaries(count: 2) + [invitedRoom(id: "!invite:matrix.org")]
    )

    var iterator = service.list(filter: .joined).makeAsyncIterator()
    let rooms = try #require(await iterator.next())

    #expect(rooms.count == 2)
    #expect(rooms.allSatisfy { $0.membership == .joined })
}

@Test func mockRoomServiceHonoursTheInvitedFilter() async throws {
    let service = MockRoomService(
        rooms: SampleData.roomSummaries(count: 2) + [invitedRoom(id: "!invite:matrix.org")]
    )

    var iterator = service.list(filter: .invited).makeAsyncIterator()
    let rooms = try #require(await iterator.next())

    #expect(rooms.map(\.id.rawValue) == ["!invite:matrix.org"])
}

@Test func mockRoomServiceAllFilterKeepsEveryRoom() async throws {
    let service = MockRoomService(
        rooms: SampleData.roomSummaries(count: 2) + [invitedRoom(id: "!invite:matrix.org")]
    )

    var iterator = service.list(filter: .all).makeAsyncIterator()
    let rooms = try #require(await iterator.next())

    #expect(rooms.count == 3)
}

@Test func mockRoomServiceEmitsFilteredUpdates() async throws {
    let service = MockRoomService(rooms: [])
    var iterator = service.list(filter: .joined).makeAsyncIterator()
    #expect(await iterator.next()?.isEmpty == true)

    service.emit(SampleData.roomSummaries(count: 1) + [invitedRoom(id: "!invite:matrix.org")])
    let rooms = try #require(await iterator.next())

    #expect(rooms.count == 1)
    #expect(rooms.first?.membership == .joined)
}

/// Sans terminaison, la boucle `for await` enseignée par le README pendrait indéfiniment face au
/// mock : le test ci-dessous échouerait en dépassant sa borne au lieu de passer.
@Test(.timeLimit(.minutes(1)))
func mockRoomServiceStreamCanBeFinished() async {
    let service = MockRoomService(rooms: SampleData.roomSummaries(count: 1))

    var received: [[RoomSummary]] = []
    let stream = service.list(filter: .all)
    service.finish()

    for await rooms in stream {
        received.append(rooms)
    }

    #expect(received.count == 1)
}

@Test(.timeLimit(.minutes(1)))
func mockTimelineStreamCanBeFinished() async {
    let timeline = MockTimeline()
    let stream = timeline.items

    timeline.emit([SampleData.message("bonjour")])
    timeline.finish()

    var count = 0
    for await _ in stream { count += 1 }

    #expect(count == 1)
}

@Test(.timeLimit(.minutes(1)))
func mockSyncControllerStreamCanBeFinished() async {
    let sync = MockSyncController()
    let stream = sync.state

    sync.emit(.running)
    sync.finish()

    var states: [SyncState] = []
    for await state in stream { states.append(state) }

    #expect(states == [.running])
}

@Test func mockSessionExposesADrivableEncryptionService() async {
    let encryption = MockEncryptionService()
    let session = MockMatrixSession(encryption: encryption)
    var iterator = session.encryption.verificationStatus.makeAsyncIterator()

    encryption.emitVerificationStatus(.verified)

    #expect(await iterator.next() == .verified)
}

@Test func mockSessionDeliversEmittedAuthStates() async {
    let session = MockMatrixSession()
    var iterator = session.authState.makeAsyncIterator()

    session.emitAuthState(.signedOut)

    #expect(await iterator.next() == .signedOut)
}

@Test func mockSessionLogoutCanFail() async {
    let session = MockMatrixSession()
    session.logoutError = .network(.offline)

    await #expect(throws: MatrixError.network(.offline)) {
        try await session.logout()
    }
    // Comme la vraie session, la tentative compte : l'effacement local a lieu même en cas d'échec.
    #expect(session.didLogout)
}
