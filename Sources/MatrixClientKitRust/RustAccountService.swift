import Foundation
import MatrixClientKitCore
import MatrixRustSDK
import Synchronization

/// Implémentation de ``AccountService`` adossée au SDK Rust.
public final class RustAccountService: AccountService {
    private let lifetime: ClientLifetime?
    /// En production, un adaptateur du `Client` FFI (voir ``ClientAccountDriver``). Libéré par
    /// ``deinit`` à travers ``lifetime``, client encore vivant. Écrit seulement par
    /// l'initialiseur et par ``deinit``, d'où `nonisolated(unsafe)`.
    nonisolated(unsafe) private var driverStorage: (any AccountDriving)?
    private let userID: UserID
    private let usesOAuth: Bool
    private let lifecycle: SessionLifecycle

    /// - Parameters:
    ///   - userID: L'identifiant de la session, `identifier` de l'authentification UIAA.
    ///   - usesOAuth: Vrai pour une session ouverte par OAuth, dont la désactivation passe par la
    ///     page de gestion du serveur d'autorisation.
    ///   - lifecycle: Arbitre la fin de la session, que la désactivation réussie déclenche.
    init(
        driver: any AccountDriving,
        lifetime: ClientLifetime?,
        userID: UserID,
        usesOAuth: Bool,
        lifecycle: SessionLifecycle
    ) {
        self.driverStorage = driver
        self.lifetime = lifetime
        self.userID = userID
        self.usesOAuth = usesOAuth
        self.lifecycle = lifecycle
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
    /// listener n'a encore rien livré : même arbitrage que ``ffiStateStream``.
    ///
    /// Un échec de la lecture initiale termine le flux sans valeur, sauf si le listener a déjà
    /// livré : le flux porte alors une valeur à jour, et reste ouvert pour les suivantes.
    ///
    /// Jusqu'à la terminaison du flux, sa closure de terminaison retient le `TaskHandle` et la
    /// tâche de lecture, et cette tâche retient le pilote — donc le `Client` FFI. Ce flux ne
    /// prolonge pas la vie du service : seul le pilote qu'il a copié survit au service, jusqu'à ce
    /// que le flux se termine (consommateur annulé, boucle quittée ou flux libéré).
    public var ignoredUsers: AsyncStream<[UserID]> {
        let driver = driver
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let gate = FirstDeliveryGate()
            let initialRead = CancellableTask()
            // Posée avant le lancement de la lecture : si elle échoue et termine le flux aussitôt,
            // le `TaskHandle` est quand même annulé.
            let handle = driver.subscribeToIgnoredUsers(
                listener: IgnoredUsersObserver { identifiers in
                    gate.deliver { continuation.yield(AccountMapper.userIDs(from: identifiers)) }
                })
            continuation.onTermination = { _ in
                initialRead.cancel()
                handle.cancel()
            }
            initialRead.store(
                Task {
                    do {
                        let identifiers = try await driver.ignoredUsers()
                        gate.deliverUnlessAlreadyDelivered {
                            continuation.yield(AccountMapper.userIDs(from: identifiers))
                        }
                    } catch {
                        // Sans valeur livrée : fin du flux, la porte est consommée pour qu'un
                        // listener tardif ne rouvre pas un flux déjà clos.
                        gate.deliverUnlessAlreadyDelivered { continuation.finish() }
                    }
                })
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

    /// UIAA `m.login.password` en deux temps (constat 14 du PRD 0.6) : l'amont exige que la
    /// première requête soit envoyée sans `authData` et la dit vouée à l'échec ; la seconde, identique
    /// mais authentifiée, aboutit. Les liaisons n'exposent ni les flux proposés ni la session UIAA :
    /// l'échec du premier appel n'est donc pas inspecté, sauf pour les causes qui rendraient
    /// le second appel inutile (réseau, limitation de débit, jeton inconnu —
    /// `.authentication(.unknownToken)` —, annulation).
    public func deactivate(password: String, eraseData: Bool) async throws {
        guard !usesOAuth else {
            throw MatrixError.unexpected(
                message: "A session opened through OAuth is deactivated on the authorization server's "
                    + "account page: use managementURL(for: .deactivateAccount).",
                details: nil)
        }
        let driver = driver
        let identifier = userID.rawValue
        try await lifecycle.deactivate {
            do {
                try await driver.deactivateAccount(authData: nil, eraseData: eraseData)
                return
            } catch {
                let mapped = ErrorMapper.map(error)
                if Task.isCancelled { throw mapped }
                switch mapped {
                case .network, .rateLimited, .authentication(.unknownToken): throw mapped
                default: break
                }
            }
            do {
                try await driver.deactivateAccount(
                    authData: .password(
                        passwordDetails: AuthDataPasswordDetails(identifier: identifier, password: password)),
                    eraseData: eraseData)
            } catch {
                throw ErrorMapper.mapAuthentication(error)
            }
        }
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

/// Reçoit une tâche créée après l'enregistrement du gestionnaire qui doit pouvoir l'annuler : une
/// annulation arrivée avant `store` s'applique dès le stockage.
private final class CancellableTask: Sendable {
    private let state = Mutex<(task: Task<Void, Never>?, isCancelled: Bool)>((nil, false))

    func store(_ task: Task<Void, Never>) {
        let cancelNow = state.withLock { state in
            if state.isCancelled { return true }
            state.task = task
            return false
        }
        if cancelNow { task.cancel() }
    }

    func cancel() {
        let task = state.withLock { state in
            state.isCancelled = true
            return state.task
        }
        task?.cancel()
    }
}
