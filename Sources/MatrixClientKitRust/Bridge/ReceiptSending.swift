import MatrixClientKitCore
import MatrixRustSDK

/// Les deux envois d'accusé de la timeline amont.
///
/// Couture de testabilité : `Timeline` est une classe FFI qu'un test ne peut pas construire.
protocol ReceiptSending: Sendable {
    func markAsRead(receiptType: ReceiptType) async throws
    func sendReadReceipt(receiptType: ReceiptType, eventId: String) async throws
}

extension MatrixRustSDK.Timeline: ReceiptSending {}

extension ReceiptSending {
    /// Envoie l'accusé de `visibility` puis déplace le marqueur `fullyRead`, sur le dernier
    /// message visible.
    ///
    /// Si l'accusé échoue, le marqueur n'est pas tenté (PRD 0.6 §4.1). Les erreurs sortent mappées.
    func markAsRead(visibility: ReadReceiptVisibility) async throws {
        do {
            try await markAsRead(receiptType: Self.receiptType(for: visibility))
            try await markAsRead(receiptType: .fullyRead)
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    /// Comme ``markAsRead(visibility:)``, mais sur `eventID`, le dernier message réellement vu.
    func markAsRead(upTo eventID: EventID, visibility: ReadReceiptVisibility) async throws {
        do {
            try await sendReadReceipt(
                receiptType: Self.receiptType(for: visibility), eventId: eventID.rawValue)
            try await sendReadReceipt(receiptType: .fullyRead, eventId: eventID.rawValue)
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    private static func receiptType(for visibility: ReadReceiptVisibility) -> ReceiptType {
        switch visibility {
        case .public: .read
        case .private: .readPrivate
        }
    }
}
