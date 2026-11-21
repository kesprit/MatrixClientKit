import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private final class FakeTaskHandle: TaskHandleProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.withLock { cancelled = true } }
    func isFinished() -> Bool { lock.withLock { cancelled } }
}

private final class FakeAccountDriver: AccountDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var _actions: [MatrixRustSDK.AccountManagementAction?] = []
    private var _ignored: [String] = []
    private var _unignored: [String] = []
    private var _listener: (any IgnoredUsersListener)?
    var accountURL: String? = "https://account.example.org/"
    var initial: [String] = []
    var error: (any Error)?
    let handle = FakeTaskHandle()
    /// Quand `holdInitial` est vrai, la lecture initiale attend `releaseInitial()`.
    var holdInitial = false
    private let initialGate = AsyncStream<Void>.makeStream()

    func releaseInitial() { initialGate.continuation.yield() }

    var actions: [MatrixRustSDK.AccountManagementAction?] { lock.withLock { _actions } }
    var ignored: [String] { lock.withLock { _ignored } }
    var unignored: [String] { lock.withLock { _unignored } }
    var listener: (any IgnoredUsersListener)? { lock.withLock { _listener } }

    func accountUrl(action: MatrixRustSDK.AccountManagementAction?) async throws -> String? {
        try lock.withLock {
            if let error { throw error }
            _actions.append(action)
        }
        return accountURL
    }

    func ignoredUsers() async throws -> [String] {
        if holdInitial { for await _ in initialGate.stream { break } }
        return try lock.withLock {
            if let error { throw error }
            return initial
        }
    }

    func ignoreUser(userId: String) async throws {
        try lock.withLock {
            if let error { throw error }
            _ignored.append(userId)
        }
    }

    func unignoreUser(userId: String) async throws {
        try lock.withLock {
            if let error { throw error }
            _unignored.append(userId)
        }
    }

    func subscribeToIgnoredUsers(listener: any IgnoredUsersListener) -> any TaskHandleProtocol {
        lock.withLock { _listener = listener }
        return handle
    }
}

private func user(_ raw: String) -> UserID { UserID(rawValue: raw)! }

private func waitUntil(_ condition: @Sendable () -> Bool) async {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
}

private let forbidden = ClientError.MatrixApi(kind: .forbidden, code: "M_FORBIDDEN", msg: "no", details: nil)

@Suite struct AccountServiceTests {
    private func makeService(_ driver: FakeAccountDriver) -> RustAccountService {
        RustAccountService(driver: driver, lifetime: .detached())
    }

    @Test func managementURLPassesUpstreamAction() async throws {
        let driver = FakeAccountDriver()
        let url = try await makeService(driver).managementURL(for: .device(DeviceID(rawValue: "D1")!))
        #expect(url == URL(string: "https://account.example.org/"))
        #expect(driver.actions == [.deviceView(deviceId: "D1")])
    }

    @Test func overviewSendsNoAction() async throws {
        let driver = FakeAccountDriver()
        _ = try await makeService(driver).managementURL(for: .overview)
        #expect(driver.actions.count == 1)
        #expect(driver.actions[0] == nil)
    }

    @Test func nilUpstreamURLIsNil() async throws {
        let driver = FakeAccountDriver()
        driver.accountURL = nil
        #expect(try await makeService(driver).managementURL(for: .profile) == nil)
    }

    @Test func malformedUpstreamURLIsUnexpected() async {
        let driver = FakeAccountDriver()
        driver.accountURL = "not a url"
        let service = makeService(driver)
        await #expect(throws: MatrixError.self) { try await service.managementURL(for: .profile) }
    }

    @Test func managementErrorsGoThroughErrorMapper() async {
        let driver = FakeAccountDriver()
        driver.error = forbidden
        let service = makeService(driver)
        await #expect(throws: MatrixError.permission(.forbidden)) { try await service.managementURL(for: .profile) }
    }

    @Test func ignoreAndUnignorePassIdentifiers() async throws {
        let driver = FakeAccountDriver()
        let service = makeService(driver)
        try await service.ignore(user("@b:x.org"))
        try await service.unignore(user("@b:x.org"))
        #expect(driver.ignored == ["@b:x.org"])
        #expect(driver.unignored == ["@b:x.org"])
    }

    @Test func ignoreErrorsAreMapped() async {
        let driver = FakeAccountDriver()
        driver.error = forbidden
        let service = makeService(driver)
        await #expect(throws: MatrixError.permission(.forbidden)) { try await service.ignore(user("@b:x.org")) }
        await #expect(throws: MatrixError.permission(.forbidden)) { try await service.unignore(user("@b:x.org")) }
    }

    @Test func ignoredUsersEmitsInitialListThenUpdates() async {
        let driver = FakeAccountDriver()
        driver.initial = ["@a:x.org"]
        let service = makeService(driver)
        var iterator = service.ignoredUsers.makeAsyncIterator()

        #expect(await iterator.next() == [user("@a:x.org")])
        driver.listener?.call(ignoredUserIds: ["@a:x.org", "@b:x.org"])
        #expect(await iterator.next() == [user("@a:x.org"), user("@b:x.org")])
        driver.listener?.call(ignoredUserIds: [])
        #expect(await iterator.next() == [])
    }

    @Test func ignoredUsersEndsWithoutValueWhenInitialReadFails() async {
        let driver = FakeAccountDriver()
        driver.error = ClientError.Generic(msg: "boom", details: nil)
        let service = makeService(driver)
        var values: [[UserID]] = []
        for await users in service.ignoredUsers { values.append(users) }
        #expect(values.isEmpty)
        await waitUntil { driver.handle.isFinished() }
        #expect(driver.handle.isFinished())
    }

    @Test func leavingTheLoopCancelsTheTaskHandle() async {
        let driver = FakeAccountDriver()
        let service = makeService(driver)
        for await _ in service.ignoredUsers { break }
        await waitUntil { driver.handle.isFinished() }
        #expect(driver.handle.isFinished())
    }

    @Test func cancellingTheConsumerCancelsTheTaskHandle() async {
        let driver = FakeAccountDriver()
        let service = makeService(driver)
        let task = Task { for await _ in service.ignoredUsers {} }
        await waitUntil { driver.listener != nil }
        task.cancel()
        await waitUntil { driver.handle.isFinished() }
        #expect(driver.handle.isFinished())
    }

    @Test func listenerValueBeatsAStaleInitialRead() async {
        let driver = FakeAccountDriver()
        driver.initial = ["@old:x.org"]
        driver.holdInitial = true
        let service = makeService(driver)
        var iterator = service.ignoredUsers.makeAsyncIterator()
        driver.listener?.call(ignoredUserIds: ["@new:x.org"])
        #expect(await iterator.next() == [user("@new:x.org")])
        driver.releaseInitial()
        driver.listener?.call(ignoredUserIds: ["@newer:x.org"])
        #expect(await iterator.next() == [user("@newer:x.org")])
    }
}
