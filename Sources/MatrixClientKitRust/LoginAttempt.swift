import Foundation
import Synchronization
import MatrixRustSDK
import MatrixClientKitCore

/// Le store d'une tentative de connexion, séparé du client pour être testable sans FFI.
struct LoginAttemptStore: Sendable {
    let segment: StoreSegment
    let localStore: LocalStore
    let lease: StoreLease
    /// `false` pour une reconnexion : le store appartient à la session remplacée.
    let ownsStore: Bool

    /// Prépare le store : neuf (`reusing == nil`) ou celui d'une session existante.
    ///
    /// Le bail est pris avant le ramassage, pour qu'une tentative ne ramasse jamais son propre
    /// store ; le ramassage épargne aussi la session persistée.
    static func prepare(restorer: SessionRestorer, reusing existing: StoreSegment?) throws -> LoginAttemptStore {
        let segment = existing ?? .newSession()
        let localStore = restorer.makeLocalStore(for: segment)
        let paths = try localStore.paths()
        let lease = restorer.registry.lease(paths)

        // Un store neuf naît complet, clé d'abord (spec 0.4, §5.2, étape 1) : la clé avant les
        // répertoires, comme dans `makeClient`, pour qu'un répertoire sans clé ne passe jamais
        // pour un store orphelin à effacer.
        if existing == nil {
            do {
                _ = try localStore.encryptionKey()
                try paths.createDirectoriesIfNeeded()
            } catch {
                try? localStore.purge()
                lease.release()
                throw error
            }
        }

        // Une lecture en échec ne ramasse rien, comme à la restauration : on ne sait pas quel
        // store la session persistée désigne. Le ramassage est au mieux (§5.4), la tentative
        // continue. Pas de `try?`, qui confondrait l'échec avec « rien de persisté ».
        do {
            let persisted = try restorer.persistence.load()
            restorer.sweepOrphans(keeping: persisted.map(StoreSegment.init))
        } catch {}

        return LoginAttemptStore(segment: segment, localStore: localStore, lease: lease, ownsStore: existing == nil)
    }

    /// Abandonne la tentative : efface le store s'il lui appartient, puis rend le bail.
    func discard() {
        if ownsStore { try? localStore.purge() }
        lease.release()
    }
}

/// Une connexion en cours, quel que soit le flux (spec 0.4, §5.2).
///
/// Le client est construit d'emblée sur le store SQLite chiffré de la tentative : l'amont pose une
/// session une seule fois par client (§2.7), et la connexion par QR écrit les secrets reçus dans ce
/// store pendant la connexion elle-même — une poignée de main en mémoire les perdrait.
final class LoginAttempt: Sendable {
    let client: Client
    private let store: LoginAttemptStore
    private let restorer: SessionRestorer
    /// - `pending` : flux en cours, ``fail()`` abandonne la tentative.
    /// - `succeeding` : ``succeed(expecting:)`` construit la session ; un ``fail()`` concurrent
    ///   (l'annulation d'un flux OAuth ou QR) est sans effet, c'est `succeed` qui conclut.
    /// - `over` : tentative close, par succès ou par échec ; plus rien n'a d'effet.
    private enum State {
        case pending
        case succeeding
        case over
    }

    private let state = Mutex(State.pending)

    private init(client: Client, store: LoginAttemptStore, restorer: SessionRestorer) {
        self.client = client
        self.store = store
        self.restorer = restorer
    }

    static func begin(
        restorer: SessionRestorer,
        target: ClientTarget,
        reusing existing: StoreSegment?
    ) async throws -> LoginAttempt {
        try await begin(restorer: restorer, target: target, reusing: existing) { target, localStore in
            try await restorer.makeClient(target: target, localStore: localStore)
        }
    }

    /// - Parameter makeClient: couture de test, comme pour ``SessionRestorer/restore(makeClient:)``.
    static func begin(
        restorer: SessionRestorer,
        target: ClientTarget,
        reusing existing: StoreSegment?,
        makeClient: (ClientTarget, LocalStore) async throws -> Client
    ) async throws -> LoginAttempt {
        let store = try LoginAttemptStore.prepare(restorer: restorer, reusing: existing)
        do {
            let client = try await makeClient(target, store.localStore)
            return LoginAttempt(client: client, store: store, restorer: restorer)
        } catch {
            store.discard()
            throw ErrorMapper.map(error)
        }
    }

    var segment: StoreSegment { store.segment }

    /// Connexion par identifiants. `deviceID` réutilise l'appareil d'une session en soft logout.
    ///
    /// - Parameter userID: pour une reconnexion, l'utilisateur attendu (voir
    ///   ``refusingAnotherAccount(after:expecting:)``).
    func authenticate(_ credentials: Credentials, deviceID: DeviceID?, expecting userID: UserID?) async throws {
        do {
            switch credentials {
            case let .password(username, password, deviceName):
                try await client.login(
                    username: username,
                    password: password,
                    initialDeviceName: deviceName,
                    deviceId: deviceID?.rawValue
                )
            case let .email(address, password, deviceName):
                try await client.loginWithEmail(
                    email: address,
                    password: password,
                    initialDeviceName: deviceName,
                    deviceId: deviceID?.rawValue
                )
            }
        } catch {
            throw ErrorMapper.mapAuthentication(await refusingAnotherAccount(after: error, expecting: userID))
        }
    }

    /// Ce qu'une connexion en échec doit lever, pour une reconnexion avec le compte d'un autre.
    ///
    /// Sur le store d'une session existante, l'amont échoue avant même de rendre la main : la
    /// connexion aboutit côté serveur, pose la session sur le client, puis l'ouverture du store
    /// crypto échoue (`MismatchedAccount` — le store est à un autre compte), une erreur générique
    /// qui ne dit rien de la cause. Constaté contre Synapse. Le compte réellement connecté reste
    /// lisible sur le client : s'il diffère de l'attendu, c'est un refus d'identifiants (spec 0.4,
    /// §4.6), et l'appareil créé pour cet autre compte est déconnecté, au mieux. Plutôt que de
    /// reconnaître le message amont, on compare les comptes : rien ne dépend du libellé.
    ///
    /// - Returns: `MatrixError.authentication(.invalidCredentials)` pour un autre compte, `error`
    ///   tel quel sinon (y compris hors reconnexion, `userID == nil`).
    func refusingAnotherAccount(after error: any Error, expecting userID: UserID?) async -> any Error {
        guard let userID, let session = try? client.session(), session.userId != userID.rawValue else {
            return error
        }
        try? await client.logout()
        return MatrixError.authentication(.invalidCredentials)
    }

    /// Construit la session sur ce même client, puis la persiste.
    ///
    /// Rien n'est persisté tant que la session n'est pas construite : persister d'abord puis
    /// échouer laisserait une session enregistrée pointant vers un store que l'abandon de la
    /// tentative efface. En cas d'échec, la tentative est abandonnée ici même. En cas de succès,
    /// le bail n'est pas rendu : il passe à la session, qui le garde jusqu'à sa libération.
    ///
    /// - Parameter userID: pour une reconnexion, l'utilisateur attendu. Un autre compte est
    ///   déconnecté côté serveur et refusé (spec 0.4, §4.6) : persister ses jetons sur le store
    ///   d'un autre utilisateur mélangerait deux identités cryptographiques.
    func succeed(expecting userID: UserID?) async throws -> RustMatrixSession {
        let wasPending = state.withLock { state in
            guard state == .pending else { return false }
            state = .succeeding
            return true
        }
        guard wasPending else {
            throw MatrixError.unexpected(message: "The login attempt is already over.", details: nil)
        }

        do {
            if let userID, try client.session().userId != userID.rawValue {
                try? await client.logout()
                throw MatrixError.authentication(.invalidCredentials)
            }
            let session = try await RustMatrixSession.make(
                client: client,
                restorer: restorer,
                localStore: store.localStore,
                lease: store.lease
            )
            // Relue après `make` : un rafraîchissement de jeton pendant sa construction n'est pas
            // persisté par le delegate (rien ne désigne encore cette session), il n'existe que là.
            let data = try SessionMapper.sessionData(from: client.session(), storeID: store.segment.storeID)
            try restorer.persistence.save(data)
            state.withLock { $0 = .over }
            return session
        } catch {
            state.withLock { $0 = .over }
            store.discard()
            throw error
        }
    }

    /// Abandonne la tentative. Sans effet une fois ``succeed(expecting:)`` commencé ; idempotent.
    func fail() {
        let wasPending = state.withLock { state in
            guard state == .pending else { return false }
            state = .over
            return true
        }
        if wasPending { store.discard() }
    }
}
