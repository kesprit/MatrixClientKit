import Testing
import Foundation
import MatrixClientKitCore
@testable import MatrixClientKitRust

private final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
    var value: Int { lock.withLock { count } }
}

@Test(.timeLimit(.minutes(1)))
func theWatcherAttemptsOnEveryValueUntilTheFirstSuccess() async {
    let (values, continuation) = AsyncStream<VerificationStatus>.makeStream()
    let attempts = AttemptCounter()

    // Deux échecs puis un succès : la quatrième valeur ne doit déclencher aucune tentative.
    let watcher = RustMatrixSession.retryUntilSuccess(on: values) {
        attempts.increment() == 3
    }
    continuation.yield(.unknown)
    continuation.yield(.unverified)
    continuation.yield(.unverified)
    continuation.yield(.verified)
    continuation.finish()

    await watcher.value
    #expect(attempts.value == 3)
}

@Test(.timeLimit(.minutes(1)))
func theWatcherStopsAttemptingAfterTheFirstSuccess() async {
    let (values, continuation) = AsyncStream<VerificationStatus>.makeStream()
    let attempts = AttemptCounter()

    // Succès immédiat : les valeurs suivantes ne déclenchent aucune tentative.
    let watcher = RustMatrixSession.retryUntilSuccess(on: values) {
        _ = attempts.increment()
        return true
    }
    continuation.yield(.unknown)
    continuation.yield(.unverified)
    continuation.yield(.verified)
    continuation.finish()

    await watcher.value
    #expect(attempts.value == 1)
}
