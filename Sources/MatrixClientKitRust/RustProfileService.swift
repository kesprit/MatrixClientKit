import Foundation
import MatrixClientKitCore
import MatrixRustSDK

/// Implémentation de ``ProfileService`` adossée au SDK Rust.
public final class RustProfileService: ProfileService {
    private let lifetime: ClientLifetime?
    /// En production, le `Client` FFI lui-même. Libéré par ``deinit`` à travers ``lifetime``,
    /// client encore vivant. Écrit seulement par l'initialiseur et par ``deinit``, d'où
    /// `nonisolated(unsafe)`.
    nonisolated(unsafe) private var driverStorage: (any ProfileDriving)?

    init(driver: any ProfileDriving, lifetime: ClientLifetime?) {
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

    private var driver: any ProfileDriving {
        guard let driverStorage else {
            // Inatteignable : `driverStorage` n'est vidé que par `deinit`.
            preconditionFailure("RustProfileService used after deinitialization")
        }
        return driverStorage
    }

    public func profile(of user: UserID) async throws -> MatrixClientKitCore.UserProfile {
        let upstream: MatrixRustSDK.UserProfile
        do {
            upstream = try await driver.getProfile(userId: user.rawValue)
        } catch {
            let mapped = ErrorMapper.map(error)
            if case .notFound(.unspecified) = mapped { throw MatrixError.notFound(.user) }
            if Self.isUnknownProfileResponse(error) { throw MatrixError.notFound(.user) }
            throw mapped
        }
        return try ProfileMapper.profile(from: upstream)
    }

    /// Synapse répond **404 `M_UNKNOWN`** (« No row found (profiles) »), non `M_NOT_FOUND`, pour le
    /// profil d'un utilisateur inconnu (constaté contre le harnais). Les liaisons n'exposent pas le
    /// code HTTP : la structure (`kind` `.unknown`, code `M_UNKNOWN`) est testée d'abord, et le
    /// statut 404 se lit en dernier recours dans le texte des détails (`status_code: 404`).
    /// Réservé à `profile(of:)` : un 404 `M_UNKNOWN` ailleurs reste `.unexpected`.
    private static func isUnknownProfileResponse(_ error: any Error) -> Bool {
        guard case let ClientError.MatrixApi(kind, code, _, details) = error, kind == .unknown, code == "M_UNKNOWN"
        else { return false }
        return details?.contains("status_code: 404") == true
    }

    public func setDisplayName(_ name: String) async throws {
        do {
            try await driver.setDisplayName(name: name)
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    public func setAvatar(_ data: Data, mimeType: String) async throws {
        do {
            try await driver.uploadAvatar(mimeType: mimeType, data: data)
        } catch {
            throw MediaErrorMapper.map(error)
        }
    }

    public func removeAvatar() async throws {
        do {
            try await driver.removeAvatar()
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    public func setPresence(_ presence: Presence) async throws {
        do {
            try await driver.setPresence(presence: ProfileMapper.upstreamPresence(from: presence), immediate: true)
        } catch {
            throw ErrorMapper.map(error)
        }
    }
}
