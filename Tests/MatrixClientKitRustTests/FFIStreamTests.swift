import Testing
import Foundation
import MatrixRustSDK
@testable import MatrixClientKitRust

/// Faux `TaskHandle` : enregistre l'annulation sans toucher au binaire Rust.
private final class FakeTaskHandle: TaskHandleProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    func isFinished() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    var wasCancelled: Bool { isFinished() }
}

/// Faux listener générique : encapsule la closure d'émission.
private final class FakeListener: Sendable {
    let emit: @Sendable (Int) -> Void
    init(emit: @escaping @Sendable (Int) -> Void) { self.emit = emit }
}

/// Boîte thread-safe retenant le listener créé à l'intérieur d'une closure `@Sendable`.
private final class ListenerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var listener: FakeListener?

    func store(_ listener: FakeListener) {
        lock.lock(); self.listener = listener; lock.unlock()
    }

    func emit(_ value: Int) {
        lock.lock(); let listener = listener; lock.unlock()
        listener?.emit(value)
    }
}

@Test func streamDeliversEmittedValues() async {
    let handle = FakeTaskHandle()
    let box = ListenerBox()

    let stream = ffiStream(
        bufferingPolicy: .unbounded,
        makeListener: { emit in
            let listener = FakeListener(emit: emit)
            box.store(listener)
            return listener
        },
        subscribe: { _ in handle }
    )

    box.emit(1)
    box.emit(2)

    var received: [Int] = []
    for await value in stream {
        received.append(value)
        if received.count == 2 { break }
    }

    #expect(received == [1, 2])
}

@Test func leavingTheLoopReleasesTheStreamAndCancelsTheUpstreamHandle() async {
    let handle = FakeTaskHandle()
    let box = ListenerBox()

    for await _ in ffiStream(
        bufferingPolicy: .unbounded,
        makeListener: { emit in
            let listener = FakeListener(emit: emit)
            box.store(listener)
            // Émission synchrone, avant toute consommation : `makeListener` s'exécute pendant
            // la construction du flux, donc cette valeur est déjà bufferisée quand la boucle
            // appelle `next()` pour la première fois — sans quoi la boucle attendrait
            // indéfiniment un élément qui n'arrive jamais.
            emit(42)
            return listener
        },
        subscribe: { _ in handle }
    ) {
        break
    }

    // La terminaison suit la libération du flux : on laisse un tour de boucle s'écouler.
    try? await Task.sleep(for: .milliseconds(50))
    #expect(handle.wasCancelled)
}

@Test func cancellingTheConsumingTaskCancelsTheUpstreamHandle() async {
    let handle = FakeTaskHandle()

    let stream = ffiStream(
        bufferingPolicy: .unbounded,
        makeListener: { FakeListener(emit: $0) },
        subscribe: { _ in handle }
    )

    let task = Task {
        for await _ in stream {}
    }
    task.cancel()
    _ = await task.value

    try? await Task.sleep(for: .milliseconds(50))
    #expect(handle.wasCancelled)
}

@Test func failingSubscriptionFinishesTheStreamWithoutValues() async {
    struct SubscriptionFailure: Error {}

    let stream = ffiStream(
        bufferingPolicy: .unbounded,
        makeListener: { FakeListener(emit: $0) },
        subscribe: { (_: FakeListener) -> any TaskHandleProtocol in throw SubscriptionFailure() }
    )

    var received: [Int] = []
    for await value in stream { received.append(value) }
    #expect(received.isEmpty)
}
