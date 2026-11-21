import MatrixClientKitCore
import MatrixRustSDK

/// Listener de frappe conforme au protocole amont, alimenté par une closure.
private final class TypingListener: TypingNotificationsListener {
    private let handler: @Sendable ([String]) -> Void

    init(handler: @escaping @Sendable ([String]) -> Void) {
        self.handler = handler
    }

    func call(typingUserIds: [String]) {
        handler(typingUserIds)
    }
}

/// Traduit les notifications de frappe amont vers le domaine.
enum TypingMapper {

    /// Les membres qui écrivent, dans l'ordre amont, sans l'utilisateur courant.
    ///
    /// - Note: les bindings ne disent pas si l'amont inclut l'utilisateur courant ; le filtrage
    ///   est fait ici pour ne pas dépendre de ce comportement. Un user ID invalide est écarté.
    static func users(from rawIDs: [String], excluding ownUserID: String) -> [UserID] {
        rawIDs.compactMap { rawID in
            rawID == ownUserID ? nil : UserID(rawValue: rawID)
        }
    }

    /// Flux d'instantanés de frappe, en `.bufferingNewest(1)` : seule la dernière liste compte.
    static func stream(
        ownUserID: String,
        subscribe: @escaping @Sendable (any TypingNotificationsListener) throws -> any TaskHandleProtocol
    ) -> AsyncStream<[UserID]> {
        ffiStream(
            bufferingPolicy: .bufferingNewest(1),
            makeListener: { emit in
                TypingListener { emit(users(from: $0, excluding: ownUserID)) }
            },
            subscribe: { listener in try subscribe(listener) }
        )
    }
}
