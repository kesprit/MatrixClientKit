import Testing
import Foundation
import MatrixRustSDK
@testable import MatrixClientKitRust

/// Journal partagé des `deinit`, dans l'ordre où ils surviennent.
private final class DeinitLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func append(_ entry: String) { lock.withLock { entries.append(entry) } }
    var all: [String] { lock.withLock { entries } }
}

/// Témoin qui consigne sa libération : tient le rôle du `Client` FFI, ou d'un objet qui en dépend.
private final class Witness: Sendable {
    private let name: String
    private let log: DeinitLog
    init(_ name: String, log: DeinitLog) {
        self.name = name
        self.log = log
    }
    deinit { log.append(name) }
}

/// Porteur sur le modèle des services : son objet dépendant est libéré par ``ClientLifetime``.
private final class Holder: Sendable {
    private let lifetime: ClientLifetime
    nonisolated(unsafe) private var dependent: Witness?

    init(lifetime: ClientLifetime, dependent: Witness) {
        self.lifetime = lifetime
        self.dependent = dependent
    }

    deinit { lifetime.release(&dependent) }
}

/// Client sans rôle, pour les tests qui construisent un porteur sans le SDK.
private final class DetachedClient: Sendable {}

extension ClientLifetime {
    /// Durée de vie liée à aucun client réel, pour les tests unitaires des porteurs.
    static func detached() -> ClientLifetime {
        ClientLifetime(client: DetachedClient())
    }
}

@Suite struct ClientLifetimeTests {
    // La « session » lâche la durée de vie (et donc le client) d'abord ; l'application garde le
    // porteur plus longtemps. Le client doit tout de même partir en dernier.
    @Test func dependentIsReleasedBeforeClient() {
        let log = DeinitLog()
        var lifetime: ClientLifetime? = ClientLifetime(client: Witness("client", log: log))
        var holder: Holder? = Holder(lifetime: lifetime!, dependent: Witness("dependent", log: log))

        lifetime = nil
        #expect(log.all.isEmpty)

        holder = nil
        #expect(log.all == ["dependent", "client"])
        _ = holder
    }

    @Test func dependentIsReleasedBeforeClientWhenTheHolderGoesFirst() {
        let log = DeinitLog()
        var lifetime: ClientLifetime? = ClientLifetime(client: Witness("client", log: log))
        var holder: Holder? = Holder(lifetime: lifetime!, dependent: Witness("dependent", log: log))

        holder = nil
        #expect(log.all == ["dependent"])

        lifetime = nil
        #expect(log.all == ["dependent", "client"])
        _ = (holder, lifetime)
    }

    @Test func releasingTwiceIsHarmless() {
        let log = DeinitLog()
        let lifetime = ClientLifetime(client: Witness("client", log: log))
        var dependent: Witness? = Witness("dependent", log: log)

        lifetime.release(&dependent)
        lifetime.release(&dependent)

        #expect(dependent == nil)
        #expect(log.all == ["dependent"])
    }
}
