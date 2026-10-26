import Testing
import Foundation
import MatrixRustSDK
@testable import MatrixClientKitRust

/// Porteur sur le modèle des services : son objet dépendant est libéré par ``ClientLifetime``.
private final class Holder: Sendable {
    private let lifetime: ClientLifetime
    nonisolated(unsafe) private var dependent: DeinitWitness?

    init(lifetime: ClientLifetime, dependent: DeinitWitness) {
        self.lifetime = lifetime
        self.dependent = dependent
    }

    deinit { lifetime.release(&dependent) }
}

@Suite struct ClientLifetimeTests {
    // La « session » lâche la durée de vie (et donc le client) d'abord ; l'application garde le
    // porteur plus longtemps. Le client doit tout de même partir en dernier.
    @Test func dependentIsReleasedBeforeClient() {
        let log = DeinitLog()
        var lifetime: ClientLifetime? = ClientLifetime(client: DeinitWitness("client", log: log))
        var holder: Holder? = Holder(lifetime: lifetime!, dependent: DeinitWitness("dependent", log: log))

        lifetime = nil
        #expect(log.all.isEmpty)

        holder = nil
        #expect(log.all == ["dependent", "client"])
        _ = holder
    }

    @Test func dependentIsReleasedBeforeClientWhenTheHolderGoesFirst() {
        let log = DeinitLog()
        var lifetime: ClientLifetime? = ClientLifetime(client: DeinitWitness("client", log: log))
        var holder: Holder? = Holder(lifetime: lifetime!, dependent: DeinitWitness("dependent", log: log))

        holder = nil
        #expect(log.all == ["dependent"])

        lifetime = nil
        #expect(log.all == ["dependent", "client"])
        _ = (holder, lifetime)
    }

    @Test func releasingTwiceIsHarmless() {
        let log = DeinitLog()
        let lifetime = ClientLifetime(client: DeinitWitness("client", log: log))
        var dependent: DeinitWitness? = DeinitWitness("dependent", log: log)

        lifetime.release(&dependent)
        lifetime.release(&dependent)

        #expect(dependent == nil)
        #expect(log.all == ["dependent"])
    }
}
