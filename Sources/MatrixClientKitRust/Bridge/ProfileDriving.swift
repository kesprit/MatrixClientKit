import Foundation
import MatrixRustSDK

/// Sous-ensemble de `Client` dont le service de profil a besoin.
///
/// Couture de testabilité : `Client` est une classe FFI qu'un test ne peut pas construire. Les
/// signatures reprennent celles du `Client`, qui s'y conforme tel quel.
protocol ProfileDriving: Sendable {
    func getProfile(userId: String) async throws -> MatrixRustSDK.UserProfile
    func setDisplayName(name: String) async throws
    func uploadAvatar(mimeType: String, data: Data) async throws
    func removeAvatar() async throws
    func setPresence(presence: PresenceState, immediate: Bool) async throws
}

extension Client: ProfileDriving {}
