import Testing
import Synchronization
@testable import MatrixClientKitRust

@Test func onlyOneCompletionIsGranted() {
    let gate = SingleUseGate()
    #expect(gate.claimCompletion())
    #expect(!gate.claimCompletion())
}

@Test func completionAfterCancellationIsRefused() {
    let gate = SingleUseGate()
    #expect(gate.claimCancellation())
    #expect(!gate.claimCompletion())
}

@Test func cancellationAfterASuccessfulCompletionIsRefused() {
    // Un `cancel()` tardif ne doit jamais purger le store de la session ouverte.
    let gate = SingleUseGate()
    #expect(gate.claimCompletion())
    gate.completionSucceeded()
    #expect(!gate.claimCancellation())
}

@Test func cancellationDuringCompletionIsRefused() {
    let gate = SingleUseGate()
    #expect(gate.claimCompletion())
    #expect(!gate.claimCancellation())
}

@Test func aFailedCompletionEndsTheFlow() {
    let gate = SingleUseGate()
    #expect(gate.claimCompletion())
    gate.completionFailed()
    #expect(!gate.claimCompletion())
    #expect(!gate.claimCancellation())
}

@Test func cancellingTwiceIsANoOp() {
    let gate = SingleUseGate()
    #expect(gate.claimCancellation())
    #expect(!gate.claimCancellation())
}

// MARK: - Issue signalée une seule fois (reconnexion OAuth, spec 0.4, §5.5)

/// Consigne chaque issue signalée par une porte.
private final class Ends: Sendable {
    private let values = Mutex<[Bool]>([])
    func append(_ succeeded: Bool) { values.withLock { $0.append(succeeded) } }
    var all: [Bool] { values.withLock { $0 } }
}

private func recordingGate() -> (SingleUseGate, Ends) {
    let ends = Ends()
    return (SingleUseGate(onEnd: ends.append), ends)
}

@Test func aSuccessfulCompletionReportsSuccessOnce() {
    let (gate, ends) = recordingGate()
    #expect(gate.claimCompletion())
    gate.completionSucceeded()
    gate.completionSucceeded()
    gate.completionFailed()
    gate.cancellationFinished()

    #expect(ends.all == [true])
}

@Test func aFailedCompletionReportsFailureOnce() {
    let (gate, ends) = recordingGate()
    #expect(gate.claimCompletion())
    gate.completionFailed()
    gate.completionFailed()
    gate.cancellationFinished()

    #expect(ends.all == [false])
}

@Test func aCancellationReportsFailureOnceItIsFinished() {
    let (gate, ends) = recordingGate()
    #expect(gate.claimCancellation())
    // Pas avant la fin de l'annulation : la réservation ne se libère qu'une fois la tentative
    // abandonnée.
    #expect(ends.all.isEmpty)

    gate.cancellationFinished()
    gate.cancellationFinished()
    gate.completionSucceeded()

    #expect(ends.all == [false])
}

@Test func aLateCancellationAfterSuccessReportsNothingMore() {
    let (gate, ends) = recordingGate()
    #expect(gate.claimCompletion())
    gate.completionSucceeded()

    #expect(!gate.claimCancellation())
    gate.cancellationFinished()

    #expect(ends.all == [true])
}

@Test func nothingIsReportedWithoutAnOutcome() {
    let (gate, ends) = recordingGate()
    gate.completionSucceeded()
    gate.completionFailed()
    gate.cancellationFinished()

    #expect(ends.all.isEmpty)
}
