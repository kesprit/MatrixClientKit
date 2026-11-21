import Testing
@testable import MatrixClientKitRust

@Suite struct FirstDeliveryGateTests {
    @Test func theInitialValueIsDeliveredWhenTheListenerHasNotDelivered() {
        let gate = FirstDeliveryGate()
        var delivered: [String] = []
        gate.deliverUnlessAlreadyDelivered { delivered.append("initial") }
        #expect(delivered == ["initial"])
    }

    @Test func theInitialValueIsDroppedAfterAListenerDelivery() {
        let gate = FirstDeliveryGate()
        var delivered: [String] = []
        gate.deliver { delivered.append("listener") }
        gate.deliverUnlessAlreadyDelivered { delivered.append("initial") }
        #expect(delivered == ["listener"])
    }

    @Test func listenerDeliveriesAlwaysGoThrough() {
        let gate = FirstDeliveryGate()
        var delivered: [String] = []
        gate.deliverUnlessAlreadyDelivered { delivered.append("initial") }
        gate.deliver { delivered.append("listener") }
        #expect(delivered == ["initial", "listener"])
    }

    @Test func onlyOneInitialDeliveryRuns() {
        let gate = FirstDeliveryGate()
        var count = 0
        gate.deliverUnlessAlreadyDelivered { count += 1 }
        gate.deliverUnlessAlreadyDelivered { count += 1 }
        #expect(count == 1)
    }
}
