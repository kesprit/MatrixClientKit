import Foundation
@testable import MatrixClientKitRust

/// Journal partagé des `deinit`, dans l'ordre où ils surviennent.
final class DeinitLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func append(_ entry: String) { lock.withLock { entries.append(entry) } }
    var all: [String] { lock.withLock { entries } }
}

/// Témoin qui consigne sa libération : tient le rôle du `Client` FFI, ou d'un objet qui en dépend.
final class DeinitWitness: Sendable {
    private let name: String
    private let log: DeinitLog
    init(_ name: String, log: DeinitLog) {
        self.name = name
        self.log = log
    }
    deinit { log.append(name) }
}

/// Client sans rôle, pour les tests qui construisent un porteur sans le SDK.
private final class DetachedClient: Sendable {}

extension ClientLifetime {
    /// Durée de vie liée à aucun client réel, pour les tests unitaires des porteurs.
    static func detached() -> ClientLifetime {
        ClientLifetime(client: DetachedClient())
    }
}
