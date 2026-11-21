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
            throw mapped
        }
        return try ProfileMapper.profile(from: upstream)
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
            throw Self.mapUpload(error)
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

    /// Avatar trop gros : `ErrorMapper` ne peut pas le trancher seul, car il ne connaît pas la
    /// ressource envoyée.
    private static func mapUpload(_ error: any Error) -> MatrixError {
        if case let ClientError.MatrixApi(kind, code, _, details) = error, case .tooLarge = kind {
            return .unexpected(
                message: "The media is larger than the homeserver accepts.",
                details: details.map { "\(code): \($0)" } ?? code
            )
        }
        return ErrorMapper.map(error)
    }
}
