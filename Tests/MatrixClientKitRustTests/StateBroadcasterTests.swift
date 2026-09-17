import Testing
import Foundation
import Synchronization
@testable import MatrixClientKitRust

@Test func aNewSubscriberReceivesTheCurrentValueFirst() async {
    let broadcaster = StateBroadcaster(1)
    broadcaster.update { _ in 2 }

    var iterator = broadcaster.stream().makeAsyncIterator()
    #expect(await iterator.next() == 2)
}

@Test func updatesReachEverySubscriberInOrder() async {
    let broadcaster = StateBroadcaster(0)
    var first = broadcaster.stream().makeAsyncIterator()
    var second = broadcaster.stream().makeAsyncIterator()
    #expect(await first.next() == 0)
    #expect(await second.next() == 0)

    broadcaster.update { $0 + 1 }
    #expect(await first.next() == 1)
    #expect(await second.next() == 1)

    broadcaster.update { $0 + 1 }
    #expect(await first.next() == 2)
    #expect(await second.next() == 2)
}

/// Réécriture du test du plan (voir la décision du contrôleur au rapport de la tâche 4) : avec
/// `.bufferingNewest(1)`, une valeur inchangée rediffusée aurait de toute façon été écrasée par
/// la valeur suivante avant sa lecture, donc le test original ne pouvait pas échouer même en cas
/// de régression. On consomme ici le flux en continu dans une tâche dédiée et on vérifie la
/// séquence exacte des valeurs livrées.
@Test func anUnchangedValueIsNotDeliveredAgain() async throws {
    let broadcaster = StateBroadcaster("idle")
    let received = Mutex<[String]>([])

    let task = Task {
        for await value in broadcaster.stream() {
            received.withLock { $0.append(value) }
        }
    }

    // Laisse la valeur initiale être livrée avant de déclencher les mises à jour.
    try await Task.sleep(for: .milliseconds(50))
    broadcaster.update { $0 }
    try await Task.sleep(for: .milliseconds(50))
    broadcaster.update { _ in "running" }
    try await Task.sleep(for: .milliseconds(50))
    task.cancel()

    #expect(received.withLock { $0 } == ["idle", "running"])
}

@Test func aReleasedSubscriptionIsForgotten() async throws {
    let broadcaster = StateBroadcaster(0)

    do {
        var iterator = broadcaster.stream().makeAsyncIterator()
        _ = await iterator.next()
        #expect(broadcaster.subscriberCount == 1)
    }

    // La terminaison suit la libération du flux : on laisse un tour de boucle s'écouler.
    try await Task.sleep(for: .milliseconds(50))
    #expect(broadcaster.subscriberCount == 0)
}
