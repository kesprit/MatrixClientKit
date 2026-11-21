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
    /// Envoie l'accusé de `visibility` puis déplace le marqueur `fullyRead`, chacun sur le dernier
    /// message visible au moment de son appel.
    ///
    /// - Note: l'amont résout deux fois ce message ; un événement arrivé entre les deux appels
    ///   peut porter l'accusé sur N et le marqueur sur N+1 (PRD 0.6 §12). Pour une cible commune,
    ///   utiliser ``markAsRead(upTo:visibility:)``.
    ///
    /// Si l'accusé échoue, le marqueur n'est pas tenté (PRD 0.6 §4.1). Les erreurs sortent mappées.
    func markAsRead(visibility: ReadReceiptVisibility) async throws {
        do {
            try await markAsRead(receiptType: ReceiptMapper.receiptType(for: visibility))
            try await markAsRead(receiptType: .fullyRead)
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    /// Comme ``markAsRead(visibility:)``, mais sur `eventID`, le dernier message réellement vu.
    func markAsRead(upTo eventID: EventID, visibility: ReadReceiptVisibility) async throws {
        do {
            try await sendReadReceipt(
                receiptType: ReceiptMapper.receiptType(for: visibility), eventId: eventID.rawValue)
            try await sendReadReceipt(receiptType: .fullyRead, eventId: eventID.rawValue)
        } catch {
            throw ErrorMapper.map(error)
        }
    }
}
