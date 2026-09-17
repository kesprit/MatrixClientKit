import Testing
import Foundation
import MatrixClientKitCore

private let request = VerificationRequest(
    id: "flow-1",
    deviceID: DeviceID(rawValue: "PHONE")!,
    deviceDisplayName: "iPhone",
    firstSeen: Date(timeIntervalSince1970: 0)
)

private let otherRequest = VerificationRequest(
    id: "flow-2",
    deviceID: DeviceID(rawValue: "LAPTOP")!,
    deviceDisplayName: nil,
    firstSeen: Date(timeIntervalSince1970: 0)
)

private let emojis = SASData.emojis([SASEmoji(symbol: "🐶", description: "Dog", index: 0)])
private let decimals = SASData.decimals([1234, 5678, 9012])

private let allStates: [SessionVerificationState] = [
    .idle, .incomingRequest(request), .waitingForOtherDevice, .ready, .startingSAS,
    .comparing(emojis), .confirming, .verified, .cancelled, .failed,
]

private let finishedStates: [SessionVerificationState] = [.verified, .cancelled, .failed]

struct Transition: Sendable, CustomTestStringConvertible {
    let from: SessionVerificationState
    let event: VerificationEvent
    let to: SessionVerificationState

    var testDescription: String { "\(from) + \(event) → \(to)" }
}

// Tableau de la spec 0.2, §6.1 : chaque ligne est une transition attendue.
private let transitions: [Transition] = [
    Transition(from: .idle, event: .requestSent, to: .waitingForOtherDevice),
    Transition(from: .verified, event: .requestSent, to: .waitingForOtherDevice),
    Transition(from: .idle, event: .receivedRequest(request), to: .incomingRequest(request)),
    Transition(from: .cancelled, event: .receivedRequest(request), to: .incomingRequest(request)),
    Transition(from: .waitingForOtherDevice, event: .otherDeviceAccepted, to: .ready),
    Transition(from: .incomingRequest(request), event: .otherDeviceAccepted, to: .ready),
    Transition(from: .ready, event: .startSASSent, to: .startingSAS),
    Transition(from: .ready, event: .sasStarted, to: .startingSAS),
    Transition(from: .startingSAS, event: .sasStarted, to: .startingSAS),
    Transition(from: .startingSAS, event: .receivedSASData(emojis), to: .comparing(emojis)),
    Transition(from: .ready, event: .receivedSASData(decimals), to: .comparing(decimals)),
    Transition(from: .comparing(emojis), event: .approvalSent, to: .confirming),
    Transition(from: .confirming, event: .finished, to: .verified),
    Transition(from: .comparing(emojis), event: .finished, to: .verified),
    Transition(from: .ready, event: .cancelSent, to: .cancelled),
    Transition(from: .confirming, event: .cancelled, to: .cancelled),
    Transition(from: .startingSAS, event: .failed, to: .failed),
    Transition(from: .incomingRequest(request), event: .cancelled, to: .cancelled),
]

@Test(arguments: transitions)
func reducerAppliesTheSpecifiedTransition(_ transition: Transition) {
    #expect(SessionVerificationReducer.reduce(transition.from, transition.event) == transition.to)
}

@Test func aRequestDuringAnActiveFlowIsIgnored() {
    // L'amont ne gère qu'un flux : écraser le flux en cours le rendrait inutilisable.
    for state in allStates where state != .idle && !state.isFinished {
        #expect(SessionVerificationReducer.reduce(state, .receivedRequest(otherRequest)) == state)
    }
}

@Test func finishedStatesAreOnlyLeftByANewRequest() {
    let lateEvents: [VerificationEvent] = [
        .otherDeviceAccepted, .sasStarted, .receivedSASData(emojis), .finished, .cancelled, .failed,
        .approvalSent, .startSASSent, .cancelSent,
    ]
    for state in finishedStates {
        for event in lateEvents {
            #expect(SessionVerificationReducer.reduce(state, event) == state, "\(state) + \(event)")
        }
    }
}

@Test func idleIgnoresEverythingButARequest() {
    let events: [VerificationEvent] = [
        .otherDeviceAccepted, .sasStarted, .receivedSASData(emojis), .finished, .cancelled, .failed,
        .approvalSent, .startSASSent, .cancelSent,
    ]
    for event in events {
        #expect(SessionVerificationReducer.reduce(.idle, event) == .idle, "\(event)")
    }
}

@Test func eachCommandIsAllowedOnlyInItsStates() {
    func allowed(_ command: VerificationCommand) -> [SessionVerificationState] {
        allStates.filter { SessionVerificationReducer.isAllowed(command, in: $0) }
    }

    #expect(allowed(.requestVerification) == [.idle, .verified, .cancelled, .failed])
    #expect(allowed(.accept) == [.incomingRequest(request)])
    #expect(allowed(.startSAS) == [.ready])
    #expect(allowed(.approve) == [.comparing(emojis)])
    #expect(allowed(.decline) == [.comparing(emojis)])
    #expect(
        allowed(.cancel) == [
            .incomingRequest(request), .waitingForOtherDevice, .ready, .startingSAS,
            .comparing(emojis), .confirming,
        ])
}

@Test func isFinishedCoversExactlyTheTerminalStates() {
    #expect(allStates.filter(\.isFinished) == finishedStates)
}
