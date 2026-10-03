import Testing
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
