import Foundation
import MatrixClientKitCore
import MatrixRustSDK

/// Traduit les accusés de lecture amont vers le domaine.
enum ReceiptMapper {

    /// Les accusés des autres membres, du plus récent au plus ancien, puis par `UserID`.
    ///
    /// - Note: l'amont indexe les accusés par user ID et peut y inclure l'utilisateur courant ;
    ///   le filtrage est fait ici pour ne pas dépendre de ce comportement. Un accusé sans
    ///   horodatage passe en dernier, et un user ID invalide est écarté.
    static func receipts(
        from receipts: [String: Receipt],
        excluding ownUserID: String
    ) -> [ReadReceipt] {
        receipts
            .compactMap { rawID, receipt -> ReadReceipt? in
                guard rawID != ownUserID, let userID = UserID(rawValue: rawID) else { return nil }
                return ReadReceipt(
                    userID: userID,
                    timestamp: receipt.timestamp.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.timestamp, rhs.timestamp) {
                case let (left?, right?) where left != right: left > right
                case (.some, .none): true
                case (.none, .some): false
                default: lhs.userID.rawValue < rhs.userID.rawValue
                }
            }
    }
}
