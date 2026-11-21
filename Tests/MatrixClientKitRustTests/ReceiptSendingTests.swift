import Synchronization
import Testing
import MatrixClientKitCore
import MatrixRustSDK

@testable import MatrixClientKitRust

/// Timeline amont factice : note chaque appel d'accusé ou de marqueur, et échoue à la demande.
private final class FakeReceiptSending: ReceiptSending {
    enum Call: Equatable {
        case latest(ReceiptType)
        case target(ReceiptType, String)
    }

    private let log = Mutex<[Call]>([])
    private let failing: ReceiptType?
    var calls: [Call] { log.withLock { $0 } }

    init(failingOn failing: ReceiptType? = nil) {
        self.failing = failing
    }

    private func record(_ call: Call, _ type: ReceiptType) throws {
        log.withLock { $0.append(call) }
        if failing == type {
            throw ClientError.Generic(msg: "boom", details: nil)
        }
    }

    func markAsRead(receiptType: ReceiptType) async throws {
        try record(.latest(receiptType), receiptType)
    }

    func sendReadReceipt(receiptType: ReceiptType, eventId: String) async throws {
        try record(.target(receiptType, eventId), receiptType)
    }
}

@Suite struct ReceiptSendingTests {
    private let eventID = EventID(rawValue: "$e")!
    private let boom = MatrixError.unexpected(message: "boom", details: nil)

    @Test func publicVisibilitySendsReadThenFullyRead() async throws {
        let sender = FakeReceiptSending()
        try await sender.markAsRead(visibility: .public)
        #expect(sender.calls == [.latest(.read), .latest(.fullyRead)])
    }

    @Test func privateVisibilitySendsReadPrivateThenFullyRead() async throws {
        let sender = FakeReceiptSending()
        try await sender.markAsRead(visibility: .private)
        #expect(sender.calls == [.latest(.readPrivate), .latest(.fullyRead)])
    }

    @Test func publicUpToSendsReadThenFullyReadOnSameTarget() async throws {
        let sender = FakeReceiptSending()
        try await sender.markAsRead(upTo: eventID, visibility: .public)
        #expect(sender.calls == [.target(.read, "$e"), .target(.fullyRead, "$e")])
    }

    @Test func privateUpToSendsReadPrivateThenFullyReadOnSameTarget() async throws {
        let sender = FakeReceiptSending()
        try await sender.markAsRead(upTo: eventID, visibility: .private)
        #expect(sender.calls == [.target(.readPrivate, "$e"), .target(.fullyRead, "$e")])
    }

    @Test func receiptFailureSkipsFullyReadAndIsMapped() async {
        let sender = FakeReceiptSending(failingOn: .read)
        await #expect(throws: boom) {
            try await sender.markAsRead(visibility: .public)
        }
        #expect(sender.calls == [.latest(.read)])
    }

    @Test func receiptFailureUpToSkipsFullyReadAndIsMapped() async {
        let sender = FakeReceiptSending(failingOn: .readPrivate)
        await #expect(throws: boom) {
            try await sender.markAsRead(upTo: eventID, visibility: .private)
        }
        #expect(sender.calls == [.target(.readPrivate, "$e")])
    }

    @Test func fullyReadFailureIsMapped() async {
        let sender = FakeReceiptSending(failingOn: .fullyRead)
        await #expect(throws: boom) {
            try await sender.markAsRead(visibility: .public)
        }
        #expect(sender.calls == [.latest(.read), .latest(.fullyRead)])
    }
}
