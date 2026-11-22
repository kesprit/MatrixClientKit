import Testing
import Foundation
import Synchronization
import MatrixClientKit

extension HarnessTests {
    // Accusés de lecture et frappe contre `synapse-password` (PRD 0.6, §8 critères 1 à 5 et volet
    // (I) du critère 14). Chaque cas ouvre deux sessions (``withTwoSessions(encrypted:_:)``) : A,
    // l'utilisateur du harnais, qui observe ; B, le second compte, qui lit et qui écrit. Les
    // constats « amont » (accusé implicite, filtrage de l'utilisateur courant, fréquence de frappe)
    // sont imprimés avec le préfixe `[T10]` et consignés dans les rulings 0.6.
    @Suite
    struct RoomActivityHarnessTests {
        /// Critère 1 : l'accusé public de B arrive sur le message chez A. Constats : A (expéditeur)
        /// ne figure sur aucun item de sa propre timeline, ni B sur la sienne.
        @Test(.timeLimit(.minutes(2)))
        func publicReceiptReachesTheSender() async throws {
            try await withTwoSessions { pair in
                let (a, b) = try await observers(pair)
                defer { stop(a, b) }

                let tag = "receipt-\(UUID())"
                _ = try await a.timeline.send(.text(tag))
                let sent = try #require(
                    await a.recorder.waitUntil(within: .seconds(30)) { sentItem(tag, in: $0) != nil })
                let eventID = try #require(sentItem(tag, in: sent)?.message?.eventID)
                _ = try #require(await b.recorder.waitUntil(within: .seconds(30)) { sentItem(tag, in: $0) != nil })

                try await b.timeline.markAsRead(visibility: .public)

                let seen = await a.recorder.waitUntil(within: .seconds(30)) { items in
                    sentItem(tag, in: items)?.readReceipts.contains { $0.userID == pair.second.userID } == true
                }
                let items = try #require(seen, "B's public receipt never reached A: \(describe(a.recorder.latest))")
                let receipt = try #require(
                    sentItem(tag, in: items)?.readReceipts.first { $0.userID == pair.second.userID })
                #expect(receipt.timestamp != nil)
                #expect(sentItem(tag, in: items)?.message?.eventID == eventID)

                // Filtrage de l'utilisateur courant et accusé implicite de l'expéditeur.
                #expect(
                    !items.contains { $0.readReceipts.contains { $0.userID == pair.first.userID } },
                    "A's own receipt shows on A's timeline: \(describe(a.recorder.latest))")
                let bItems = try #require(b.recorder.latest)
                #expect(
                    !bItems.contains { $0.readReceipts.contains { $0.userID == pair.second.userID } },
                    "B's own receipt shows on B's timeline: \(describe(b.recorder.latest))")
                let senderOnB = sentItem(tag, in: bItems)?.readReceipts.map(\.userID.rawValue) ?? []
                print("[T10] receipts on B's view of A's message (implicit sender receipt?): \(senderOnB)")
            }
        }

        /// Critère 1, volet `.private` : aucun accusé de B sur le message de A ni après. Critère 2 : B lit en privé, son
        /// compteur retombe à zéro (la sync a donc bien tourné) sans que A ne voie quoi que ce soit.
        @Test(.timeLimit(.minutes(2)))
        func privateReceiptStaysInvisibleToTheSender() async throws {
            try await withTwoSessions { pair in
                let (a, b) = try await observers(pair)
                defer { stop(a, b) }

                let tag = "private-\(UUID())"
                _ = try await a.timeline.send(.text(tag))
                _ = try #require(await b.recorder.waitUntil(within: .seconds(30)) { sentItem(tag, in: $0) != nil })
                try await waitForNotificationCount(in: pair.second, room: pair.roomID) { $0 >= 1 }

                try await b.timeline.markAsRead(visibility: .private)
                try await waitForNotificationCount(in: pair.second, room: pair.roomID) { $0 == 0 }

                try await Task.sleep(for: .seconds(5))
                // L'adhésion de B lui donne un accusé implicite sur son propre événement
                // d'adhésion, antérieur au message : seul compte le message et ce qui le suit.
                let items = try #require(a.recorder.latest)
                let messageIndex = try #require(
                    items.lastIndex { $0.message?.body == tag }, "A's message is missing: \(describe(items))")
                #expect(
                    !items[messageIndex...].contains { $0.readReceipts.contains { $0.userID == pair.second.userID } },
                    "B's private receipt reached A's message or a later item: \(describe(items))")
            }
        }

        /// Critère 2 : après `markAsRead` public, `RoomSummary.notificationCount` de B passe à 0.
        @Test(.timeLimit(.minutes(2)))
        func markAsReadClearsTheNotificationCount() async throws {
            try await withTwoSessions { pair in
                let (a, b) = try await observers(pair)
                defer { stop(a, b) }

                let tag = "count-\(UUID())"
                _ = try await a.timeline.send(.text(tag))
                _ = try #require(await b.recorder.waitUntil(within: .seconds(30)) { sentItem(tag, in: $0) != nil })
                try await waitForNotificationCount(in: pair.second, room: pair.roomID) { $0 >= 1 }

                try await b.timeline.markAsRead(visibility: .public)
                try await waitForNotificationCount(in: pair.second, room: pair.roomID) { $0 == 0 }
            }
        }

        /// Critère 3 : `markAsRead(upTo:)` sur le plus ancien de deux messages — l'accusé est sur
        /// lui, pas sur le plus récent.
        @Test(.timeLimit(.minutes(2)))
        func markAsReadUpToAnOlderMessagePlacesTheReceiptThere() async throws {
            try await withTwoSessions { pair in
                let (a, b) = try await observers(pair)
                defer { stop(a, b) }

                let older = "older-\(UUID())"
                let newer = "newer-\(UUID())"
                _ = try await a.timeline.send(.text(older))
                _ = try #require(await a.recorder.waitUntil(within: .seconds(30)) { sentItem(older, in: $0) != nil })
                _ = try await a.timeline.send(.text(newer))
                _ = try #require(await a.recorder.waitUntil(within: .seconds(30)) { sentItem(newer, in: $0) != nil })
                let seen = try #require(
                    await b.recorder.waitUntil(within: .seconds(30)) {
                        sentItem(older, in: $0) != nil && sentItem(newer, in: $0) != nil
                    })
                let olderID = try #require(sentItem(older, in: seen)?.message?.eventID)

                try await b.timeline.markAsRead(upTo: olderID, visibility: .public)

                let items = try #require(
                    await a.recorder.waitUntil(within: .seconds(30)) { items in
                        sentItem(older, in: items)?.readReceipts.contains { $0.userID == pair.second.userID } == true
                    }, "B's receipt never reached the older message: \(describe(a.recorder.latest))")
                #expect(
                    sentItem(newer, in: items)?.readReceipts.contains { $0.userID == pair.second.userID } == false,
                    "B's receipt is on the newer message too: \(describe(a.recorder.latest))")
            }
        }

        /// Critère 5 : la frappe de B apparaît chez A, puis disparaît ; la liste de A ne contient
        /// jamais A, ni quand A tape lui-même. Constat : la fréquence de `setTyping(true)` répétés.
        @Test(.timeLimit(.minutes(2)))
        func typingReachesTheOtherMemberAndExcludesTheCurrentUser() async throws {
            try await withTwoSessions { pair in
                let roomA = try await openRoom(pair.roomID, in: pair.first)
                let roomB = try await openRoom(pair.roomID, in: pair.second)
                let bUserID = pair.second.userID
                let aUserID = pair.first.userID

                let stream = roomA.typingUsers
                let log = TypingLog()
                let task = Task {
                    for await users in stream { log.record(users) }
                }
                defer { task.cancel() }
                // La souscription amont est ouverte à la première itération : lui laisser un tour.
                try await Task.sleep(for: .seconds(2))

                try await roomB.setTyping(true)
                let typing = await log.waitUntil(within: .seconds(30)) { $0.contains(bUserID) }
                #expect(typing != nil, "B never showed as typing for A: \(log.all)")

                try await roomB.setTyping(false)
                let stopped = await log.waitUntil(from: (typing ?? 0) + 1, within: .seconds(30)) { $0.isEmpty }
                #expect(stopped != nil, "the typing list never emptied: \(log.all)")

                // A tape à son tour : A ne se voit jamais, B voit A.
                let streamB = roomB.typingUsers
                let logB = TypingLog()
                let taskB = Task {
                    for await users in streamB { logB.record(users) }
                }
                defer { taskB.cancel() }
                try await Task.sleep(for: .seconds(2))
                try await roomA.setTyping(true)
                let aTypingForB = await logB.waitUntil(within: .seconds(30)) { $0.contains(aUserID) }
                #expect(aTypingForB != nil, "A never showed as typing for B: \(logB.all)")
                try await Task.sleep(for: .seconds(2))
                try await roomA.setTyping(false)
                let bStopped = await logB.waitUntil(from: (aTypingForB ?? 0) + 1, within: .seconds(30)) { $0.isEmpty }
                #expect(bStopped != nil, "B's typing list never emptied: \(logB.all)")

                #expect(!log.all.contains { $0.contains(aUserID) }, "A saw itself typing: \(log.all)")
                #expect(!logB.all.contains { $0.contains(bUserID) }, "B saw itself typing: \(logB.all)")

                // Fréquence : dix `setTyping(true)` d'affilée, comme une frappe.
                var failures = 0
                let start = ContinuousClock.now
                for _ in 0..<10 {
                    do { try await roomB.setTyping(true) } catch { failures += 1 }
                    try await Task.sleep(for: .milliseconds(200))
                }
                print(
                    "[T10] 10 setTyping(true) in \(ContinuousClock.now - start), failures: \(failures), "
                        + "A's snapshots: \(log.all.count)")
                #expect(failures == 0)
                try await roomB.setTyping(false)
            }
        }

        /// Volet (I) du critère 14 : A renomme le salon après le dernier message, B lit ; chez A,
        /// l'accusé de B est sur l'item du changement de nom — non-message — et non sur le message.
        @Test(.timeLimit(.minutes(2)))
        func receiptSitsOnTheStateEventAfterTheLastMessage() async throws {
            try await withTwoSessions { pair in
                let (a, b) = try await observers(pair)
                defer { stop(a, b) }

                let tag = "rename-\(UUID())"
                _ = try await a.timeline.send(.text(tag))
                _ = try #require(await a.recorder.waitUntil(within: .seconds(30)) { sentItem(tag, in: $0) != nil })
                _ = try #require(await b.recorder.waitUntil(within: .seconds(30)) { sentItem(tag, in: $0) != nil })

                try await renameRoom(
                    pair.roomID, to: "Renamed \(UUID())", on: pair.configuration.passwordHomeserver,
                    user: pair.configuration.user, password: pair.configuration.password)
                let after = await b.recorder.waitUntil(within: .seconds(30)) { renameItem(after: tag, in: $0) != nil }
                print("[T10] B's timeline after the rename: \(kinds(b.recorder.latest))")
                try #require(after != nil, "the room rename never showed in B's timeline: \(kinds(b.recorder.latest))")

                try await b.timeline.markAsRead(visibility: .public)

                // L'accusé de B est d'abord sur son adhésion (implicite, avant toute lecture) : on
                // attend qu'il soit sur l'item `m.room.name`, postérieur au message.
                let bID = pair.second.userID
                let seen = await a.recorder.waitUntil(within: .seconds(30)) { items in
                    renameItem(after: tag, in: items)?.readReceipts.contains { $0.userID == bID } == true
                }
                let items = try #require(seen, "B's receipt never reached the rename item: \(kinds(a.recorder.latest))")
                print("[T10] A's timeline with B's receipt: \(kinds(items))")
                #expect(
                    sentItem(tag, in: items)?.readReceipts.contains { $0.userID == bID } == false,
                    "B's receipt is on the message: \(kinds(items))")
                let holders = items.filter { $0.readReceipts.contains { $0.userID == bID } }
                #expect(
                    holders.count == 1 && holders.first?.id == renameItem(after: tag, in: items)?.id,
                    "B's receipt is not only on the rename item (the membership one should be gone): \(kinds(items))")
            }
        }
    }
}

// MARK: - Outils du cas

private struct Observer {
    let timeline: any Timeline
    let recorder: TimelineRecorder
}

/// Une timeline observée par session : A (`first`) et B (`second`).
private func observers(_ pair: HarnessPair) async throws -> (Observer, Observer) {
    let first = try await openTimeline(pair.roomID, in: pair.first)
    let second = try await openTimeline(pair.roomID, in: pair.second)
    return (
        Observer(timeline: first, recorder: TimelineRecorder(first.items)),
        Observer(timeline: second, recorder: TimelineRecorder(second.items))
    )
}

private func stop(_ observers: Observer...) {
    for observer in observers { observer.recorder.stop() }
}

private func openRoom(_ roomID: RoomID, in session: any MatrixSession) async throws -> any RoomHandle {
    let joined = await firstValue(of: session.rooms.list(filter: .joined), within: .seconds(20)) { rooms in
        rooms.contains { $0.id == roomID }
    }
    try #require(joined != nil, "room \(roomID.rawValue) never appeared in the joined list")
    return try await session.rooms.room(roomID)
}

/// L'item du changement de nom du salon (`m.room.name`) qui suit le message `body`.
private func renameItem(after body: String, in items: [TimelineItem]) -> TimelineItem? {
    guard let index = items.lastIndex(where: { $0.message?.body == body }) else { return nil }
    return items[index...].first {
        if case let .unsupported(description) = $0.kind { return description.contains("m.room.name") }
        return false
    }
}

/// L'item dont le message porte `body` et a atteint le serveur.
private func sentItem(_ body: String, in items: [TimelineItem]) -> TimelineItem? {
    items.last { $0.message?.body == body && $0.message?.eventID != nil }
}

private func waitForNotificationCount(
    in session: any MatrixSession, room: RoomID, sourceLocation: SourceLocation = #_sourceLocation,
    where predicate: @escaping @Sendable (Int) -> Bool
) async throws {
    let seen = Mutex<[String]>([])
    let summary = await firstValue(of: session.rooms.list(filter: .joined), within: .seconds(30)) { rooms in
        let found = rooms.first { $0.id == room }
        seen.withLock { $0.append(found.map { "\($0.notificationCount)" } ?? "room absent") }
        return found.map { predicate($0.notificationCount) } ?? false
    }
    let values = seen.withLock { $0 }
    try #require(
        summary != nil, "the room's notificationCount never satisfied the expectation; saw \(values)",
        sourceLocation: sourceLocation)
}

private func describe(_ items: [TimelineItem]?) -> String { kinds(items) }

/// Une ligne par item, pour les messages d'échec : genre, texte éventuel et auteurs d'accusés.
private func kinds(_ items: [TimelineItem]?) -> String {
    guard let items else { return "no snapshot" }
    return items.map { item in
        let label: String
        switch item.kind {
        case let .message(message): label = "message(\(message.body))"
        case let .unsupported(description): label = "unsupported(\(description))"
        case .redacted: label = "redacted"
        case .unableToDecrypt: label = "unableToDecrypt"
        case .dateSeparator: label = "dateSeparator"
        case .readMarker: label = "readMarker"
        }
        return "\(label) receipts:\(item.readReceipts.map(\.userID.rawValue))"
    }.joined(separator: " | ")
}

/// Garde chaque liste de frappeurs reçue.
private final class TypingLog: Sendable {
    private let snapshots = Mutex<[[UserID]]>([])

    func record(_ users: [UserID]) {
        snapshots.withLock { $0.append(users) }
    }

    var all: [[UserID]] { snapshots.withLock { $0 } }

    /// L'indice du premier instantané, à partir de `start`, déjà reçu ou à venir, qui satisfait
    /// `predicate`, sondé toutes les 100 ms ; `nil` après `timeout`. Partir de l'indice d'un
    /// instantané précédent évite qu'une liste vide ancienne réponde à « la frappe s'est arrêtée ».
    func waitUntil(
        from start: Int = 0, within timeout: Duration, _ predicate: ([UserID]) -> Bool
    ) async -> Int? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let snapshots = all
            if start < snapshots.count, let hit = snapshots[start...].firstIndex(where: predicate) { return hit }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }
}
