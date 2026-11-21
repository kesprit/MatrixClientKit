import Foundation
import MatrixClientKitCore

/// A drivable account service for tests.
///
/// ``ignoredUsers`` emits the current list on subscription, then every list pushed through
/// ``emitIgnoredUsers(_:)``; every access opens its own stream, like the real service.
public final class MockAccountService: AccountService, @unchecked Sendable {
    /// A call to ``deactivate(password:eraseData:)``.
    public struct Deactivation: Sendable, Hashable {
        /// The password given.
        public let password: String
        /// Whether data erasure was requested.
        public let eraseData: Bool

        /// Creates a deactivation record.
        public init(password: String, eraseData: Bool) {
            self.password = password
            self.eraseData = eraseData
        }
    }

    private let lock = NSLock()
    private var _managementURLs: [AccountManagementAction: URL] = [:]
    private var _error: MatrixError?
    private var _ignored: [UserID] = []
    private var observers: [Int: AsyncStream<[UserID]>.Continuation] = [:]
    private var nextObserverID = 0
    private var _ignoredCalls: [UserID] = []
    private var _unignoredCalls: [UserID] = []
    private var _deactivations: [Deactivation] = []

    public init() {}

    /// The URL served for each action. An action that is absent yields `nil`, like a homeserver
    /// that manages accounts itself.
    public var managementURLs: [AccountManagementAction: URL] {
        get { lock.withLock { _managementURLs } }
        set { lock.withLock { _managementURLs = newValue } }
    }

    /// The error every call throws. `nil` by default, meaning calls succeed.
    public var error: MatrixError? {
        get { lock.withLock { _error } }
        set { lock.withLock { _error = newValue } }
    }

    /// Every user passed to ``ignore(_:)``, in order.
    public var ignoredCalls: [UserID] { lock.withLock { _ignoredCalls } }

    /// Every user passed to ``unignore(_:)``, in order.
    public var unignoredCalls: [UserID] { lock.withLock { _unignoredCalls } }

    /// Every call to ``deactivate(password:eraseData:)``, in order.
    public var deactivations: [Deactivation] { lock.withLock { _deactivations } }

    public var ignoredUsers: AsyncStream<[UserID]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let current = lock.withLock { () -> [UserID] in
                let identifier = nextObserverID
                nextObserverID += 1
                observers[identifier] = continuation
                continuation.onTermination = { [weak self] _ in
                    self?.removeObserver(identifier)
                }
                return _ignored
            }
            continuation.yield(current)
        }
    }

    /// Replaces the current list and pushes it into every open stream.
    public func emitIgnoredUsers(_ users: [UserID]) {
        let continuations = lock.withLock { () -> [AsyncStream<[UserID]>.Continuation] in
            _ignored = users
            return Array(observers.values)
        }
        for continuation in continuations {
            continuation.yield(users)
        }
    }

    public func managementURL(for action: AccountManagementAction) async throws -> URL? {
        if let error { throw error }
        return managementURLs[action]
    }

    public func ignore(_ user: UserID) async throws {
        lock.withLock { _ignoredCalls.append(user) }
        if let error { throw error }
    }

    public func unignore(_ user: UserID) async throws {
        lock.withLock { _unignoredCalls.append(user) }
        if let error { throw error }
    }

    public func deactivate(password: String, eraseData: Bool) async throws {
        lock.withLock { _deactivations.append(Deactivation(password: password, eraseData: eraseData)) }
        if let error { throw error }
    }

    private func removeObserver(_ identifier: Int) {
        lock.withLock { _ = observers.removeValue(forKey: identifier) }
    }
}
