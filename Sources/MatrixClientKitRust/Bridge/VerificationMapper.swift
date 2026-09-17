import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Traduit les demandes et données de vérification amont vers le domaine.
enum VerificationMapper {

    /// - Returns: `nil` quand l'identifiant d'appareil amont n'est pas valide. Une demande dont
    ///   l'appareil ne peut pas être nommé ne peut pas être présentée honnêtement à l'utilisateur.
    static func request(from details: SessionVerificationRequestDetails) -> VerificationRequest? {
        guard let deviceID = DeviceID(rawValue: details.deviceId) else { return nil }
        return VerificationRequest(
            id: details.flowId,
            deviceID: deviceID,
            deviceDisplayName: details.deviceDisplayName,
            firstSeen: Date(timeIntervalSince1970: TimeInterval(details.firstSeenTimestamp) / 1000)
        )
    }

    static func sasData(from data: SessionVerificationData) -> SASData {
        switch data {
        case let .emojis(emojis, indices):
            sasData(emojis: emojis, indices: indices)
        case let .decimals(values):
            .decimals(values)
        }
    }

    /// Séparée de ``sasData(from:)`` parce que `SessionVerificationEmoji` est une classe FFI
    /// qu'un test ne peut pas construire, alors que son protocole peut être implémenté.
    static func sasData(emojis: [any SessionVerificationEmojiProtocol], indices: Data) -> SASData {
        let indices = Array(indices)
        return .emojis(
            emojis.enumerated().map { position, emoji in
                SASEmoji(
                    symbol: emoji.symbol(),
                    description: emoji.description(),
                    index: position < indices.count ? Int(clamping: indices[position]) : nil
                )
            })
    }
}
