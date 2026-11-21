import Testing
import MatrixClientKitCore
@testable import MatrixClientKitRust

@Suite struct SessionLifecycleDeactivationTests {
    @Test func aSuccessfulDeactivationErasesAfterTheServerAndReportsSignedOut() async throws {
        let journal = Journal()
        let lifecycle = makeLifecycle(journal: journal)

        try await lifecycle.deactivate { journal.append("server") }

        #expect(journal.all == ["server", "stopSync", "erase while signedIn"])
        #expect(lifecycle.current == .signedOut)
    }

    @Test func aFailedDeactivationErasesNothingAndKeepsTheSessionSignedIn() async {
        let journal = Journal()
        let lifecycle = makeLifecycle(journal: journal)

        await #expect(throws: MatrixError.authentication(.invalidCredentials)) {
            try await lifecycle.deactivate {
                journal.append("server")
                throw MatrixError.authentication(.invalidCredentials)
            }
        }

        #expect(journal.all == ["server"])
        #expect(lifecycle.current == .signedIn)
    }

    @Test func aSessionStaysTerminableAfterAFailedDeactivation() async throws {
        let journal = Journal()
        let lifecycle = makeLifecycle(journal: journal)
        _ = try? await lifecycle.deactivate { throw MatrixError.network(.offline) }

        try await lifecycle.logout { journal.append("server") }

        #expect(journal.all == ["stopSync", "server", "erase while signedIn"])
        #expect(lifecycle.current == .signedOut)
    }

    @Test(.timeLimit(.minutes(1)))
    func aLogoutConcurrentWithASuccessfulDeactivationDoesNotEraseTwice() async throws {
        let journal = Journal()
        let gate = Gate()
        let lifecycle = makeLifecycle(journal: journal)

        let deactivation = Task {
            try await lifecycle.deactivate {
                await gate.wait()
                journal.append("deactivated")
            }
        }
        while !gate.isSuspended { await Task.yield() }

        let logout = Task {
            try await lifecycle.logout { journal.append("logout server") }
            journal.append("logoutReturned")
        }
        await yieldABunch()
        #expect(!journal.all.contains("logoutReturned"))

        gate.release()
        try await deactivation.value
        try await logout.value

        #expect(!journal.all.contains("logout server"))
        #expect(journal.all.filter { $0.hasPrefix("erase") }.count == 1)
        #expect(lifecycle.current == .signedOut)
    }

    @Test(.timeLimit(.minutes(1)))
    func aLogoutConcurrentWithAFailedDeactivationStillLogsOut() async throws {
        let journal = Journal()
        let gate = Gate()
        let lifecycle = makeLifecycle(journal: journal)

        let deactivation = Task {
            try await lifecycle.deactivate {
                await gate.wait()
                throw MatrixError.authentication(.invalidCredentials)
            }
        }
        while !gate.isSuspended { await Task.yield() }

        let logout = Task { try await lifecycle.logout { journal.append("logout server") } }
        await yieldABunch()

        gate.release()
        await #expect(throws: MatrixError.authentication(.invalidCredentials)) { try await deactivation.value }
        try await logout.value

        #expect(journal.all.contains("logout server"))
        #expect(journal.all.filter { $0.hasPrefix("erase") }.count == 1)
        #expect(lifecycle.current == .signedOut)
    }

    @Test(.timeLimit(.minutes(1)))
    func aHardLogoutDuringAFailedDeactivationStillTerminatesTheSession() async {
        let journal = Journal()
        let gate = Gate()
        let lifecycle = makeLifecycle(journal: journal)

        let deactivation = Task {
            try await lifecycle.deactivate {
                await gate.wait()
                throw MatrixError.network(.offline)
            }
        }
        while !gate.isSuspended { await Task.yield() }

        let hardLogout = lifecycle.handleAuthError(isSoftLogout: false)
        await yieldABunch()
        gate.release()
        _ = try? await deactivation.value
        await hardLogout?.value

        #expect(journal.all.filter { $0.hasPrefix("erase") }.count == 1)
        #expect(lifecycle.current == .signedOut)
    }

    @Test func aDeactivationOnAnEndedSessionIsRefusedWithoutCallingTheServer() async throws {
        let journal = Journal()
        let lifecycle = makeLifecycle(journal: journal)
        try await lifecycle.logout {}

        await #expect {
            try await lifecycle.deactivate { journal.append("server") }
        } throws: { error in
            if case MatrixError.unexpected = error { true } else { false }
        }
        #expect(!journal.all.contains("server"))
    }
}
