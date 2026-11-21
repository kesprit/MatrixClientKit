import Foundation
import MatrixClientKitCore
import MatrixRustSDK

/// Traduction commune aux services qui envoient ou lisent un média (média, avatar).
///
/// `M_TOO_LARGE` ne peut pas être tranché par ``ErrorMapper`` seul, car il ne connaît pas la
/// ressource concernée : le message explicite vit ici, en un seul endroit.
enum MediaErrorMapper {

    static func map(_ error: any Error) -> MatrixError {
        if case let ClientError.MatrixApi(kind, code, _, details) = error, case .tooLarge = kind {
            return .unexpected(
                message: "The media is larger than the homeserver accepts.",
                details: details.map { "\(code): \($0)" } ?? code
            )
        }
        return ErrorMapper.map(error)
    }
}
