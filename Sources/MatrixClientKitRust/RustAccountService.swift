import Foundation
import MatrixClientKitCore
import MatrixRustSDK
import Synchronization

/// Implémentation de ``AccountService`` adossée au SDK Rust.
///
/// La désactivation du compte (`deactivate`) n'est pas encore câblée (tâche T8) : elle lève
/// ``MatrixError/unexpected(message:details:)``.
public final class RustAccountService: AccountService {
    private let lifetime: ClientLifetime?
    /// En production, un adaptateur du `Client` FFI (voir ``ClientAccountDriver``). Libéré par
    /// ``deinit`` à travers ``lifetime``, client encore vivant. Écrit seulement par
    /// l'initialiseur et par ``deinit``, d'où `nonisolated(unsafe)`.
    nonisolated(unsafe) private var driverStorage: (any AccountDriving)?

    init(driver: any AccountDriving, lifetime: ClientLifetime?) {
        self.driverStorage = driver
        self.lifetime = lifetime
    }

    deinit {
        if let lifetime {
            lifetime.release(&driverStorage)
        } else {
            driverStorage = nil
        }
    }

    private var driver: any AccountDriving {
        guard let driverStorage else {
            // Inatteignable : `driverStorage` n'est vidé que par `deinit`.
            preconditionFailure("RustAccountService used after deinitialization")
        }
        return driverStorage
    }

    public func managementURL(for action: MatrixClientKitCore.AccountManagementAction) async throws -> URL? {
        do {
            let string = try await driver.accountUrl(action: AccountMapper.upstreamAction(for: action))
            return try AccountMapper.managementURL(from: string)
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    /// Le listener est posé **avant** la lecture initiale, et celle-ci n'est émise que si le
    /// listener n'a encore rien livré : même arbitrage que ``ffiStateStream``. Un échec de la
    /// lecture initiale termine le flux sans valeur.
    ///
    /// Le flux retient le pilote, donc le client, jusqu'à sa terminaison.
    public var ignoredUsers: AsyncStream<[UserID]> {
        let driver = driver
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let gate = IgnoredUsersGate()
            let handle = driver.subscribeToIgnoredUsers(
                listener: IgnoredUsersObserver { identifiers in
                    gate.deliver { continuation.yield(AccountMapper.userIDs(from: identifiers)) }
                })
            let initialRead = Task {
                do {
                    let identifiers = try await driver.ignoredUsers()
                    gate.deliverUnlessAlreadyDelivered {
                        continuation.yield(AccountMapper.userIDs(from: identifiers))
                    }
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                initialRead.cancel()
                handle.cancel()
            }
        }
    }

    public func ignore(_ user: UserID) async throws {
        do {
            try await driver.ignoreUser(userId: user.rawValue)
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    public func unignore(_ user: UserID) async throws {
        do {
            try await driver.unignoreUser(userId: user.rawValue)
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    public func deactivate(password: String, eraseData: Bool) async throws {
        throw MatrixError.unexpected(message: "Account deactivation is not available yet.", details: nil)
    }
}

private final class IgnoredUsersObserver: IgnoredUsersListener {
    private let handler: @Sendable ([String]) -> Void

    init(handler: @escaping @Sendable ([String]) -> Void) {
        self.handler = handler
    }

    func call(ignoredUserIds: [String]) {
        handler(ignoredUserIds)
    }
}

/// Sérialise les émissions et retient si le listener a déjà livré une valeur.
private final class IgnoredUsersGate: Sendable {
    private let hasDelivered = Mutex(false)

    func deliver(_ body: () -> Void) {
        hasDelivered.withLock { hasDelivered in
            hasDelivered = true
            body()
        }
    }

    func deliverUnlessAlreadyDelivered(_ body: () -> Void) {
        hasDelivered.withLock { hasDelivered in
            guard !hasDelivered else { return }
            hasDelivered = true
            body()
        }
    }
}
