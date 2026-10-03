import Foundation
import MatrixRustSDK
import MatrixClientKitCore

enum QRCodeMapper {
    /// Mode scanné. `nil` pour `.starting`, déjà l'état initial.
    static func event(_ progress: QrLoginProgress) -> QRCodeLoginEvent? {
        switch progress {
        case .starting: nil
        case let .establishingSecureChannel(_, checkCodeString): .secureChannelEstablished(checkCode: checkCodeString)
        case let .waitingForToken(userCode): .waitingForToken(userCode: userCode)
        case .syncingSecrets: .syncingSecrets
        case .done: .done
        }
    }

    /// Mode affiché. L'expéditeur du code de vérification est extrait à part par l'appelant.
    static func event(_ progress: GeneratedQrLoginProgress) -> QRCodeLoginEvent? {
        switch progress {
        case .starting: nil
        case let .qrReady(qrCode): .qrReady(qrCode.toBytes())
        case .qrScanned: .qrScanned
        case let .waitingForToken(userCode): .waitingForToken(userCode: userCode)
        case .syncingSecrets: .syncingSecrets
        case .done: .done
        }
    }

    /// Spec 0.4, §6.
    static func failure(_ error: any Error) -> QRCodeLoginFailure {
        guard let error = error as? HumanQrLoginError else { return .unknown }
        switch error {
        case .Declined: return .declined
        case .Expired: return .expired
        case .ConnectionInsecure: return .insecureChannel
        case .LinkingNotSupported, .OAuthMetadataInvalid, .SlidingSyncNotAvailable, .UnsupportedQrCodeType, .NotFound:
            return .notSupported
        case .OtherDeviceNotSignedIn: return .otherDeviceNotSignedIn
        case .Cancelled: return .cancelled
        case .Unknown, .CheckCodeAlreadySent, .CheckCodeCannotBeSent, .ContinuationAlreadySent,
            .ContinuationCannotBeSent:
            return .unknown
        }
    }

    /// Décode un QR scanné et en déduit le serveur sur lequel construire le client : l'URL de
    /// base si le QR la porte (MSC4388), sinon son nom de serveur. `nil` si le QR est illisible ou
    /// ne désigne aucun serveur (un QR « à afficher », qui n'est pas destiné à être scanné ici).
    static func target(scanned bytes: Data) -> TargetedQRCode? {
        guard let data = try? QrCodeData.fromBytes(bytes: bytes) else { return nil }
        if let base = data.baseUrl(), let url = URL(string: base) {
            return TargetedQRCode(data: data, target: .homeserver(url))
        }
        if let name = data.serverName() {
            return TargetedQRCode(data: data, target: .serverName(name))
        }
        return nil
    }
}

/// Un QR scanné et le serveur sur lequel construire le client qui le traite.
struct TargetedQRCode: Sendable {
    let data: QrCodeData
    let target: ClientTarget
}
