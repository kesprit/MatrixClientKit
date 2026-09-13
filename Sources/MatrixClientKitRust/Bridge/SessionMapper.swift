import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Convertit la session du SDK Rust vers les données persistées, et inversement.
enum SessionMapper {

    static func sessionData(from session: Session) throws -> MatrixSessionData {
        guard let userID = UserID(rawValue: session.userId) else {
            throw MatrixError.unexpected(
                message: "Identifiant utilisateur invalide renvoyé par le serveur",
                details: session.userId
            )
        }
        guard let deviceID = DeviceID(rawValue: session.deviceId) else {
            throw MatrixError.unexpected(
                message: "Identifiant d'appareil invalide renvoyé par le serveur",
                details: session.deviceId
            )
        }
        guard let homeserverURL = URL(string: session.homeserverUrl) else {
            throw MatrixError.unexpected(
                message: "Adresse de homeserver invalide",
                details: session.homeserverUrl
            )
        }

        return MatrixSessionData(
            userID: userID,
            deviceID: deviceID,
            homeserverURL: homeserverURL,
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            oauthData: session.oauthData,
            slidingSyncVersion: slidingSyncIdentifier(session.slidingSyncVersion)
        )
    }

    static func session(from data: MatrixSessionData) -> Session {
        Session(
            accessToken: data.accessToken,
            refreshToken: data.refreshToken,
            userId: data.userID.rawValue,
            deviceId: data.deviceID.rawValue,
            homeserverUrl: data.homeserverURL.absoluteString,
            oauthData: data.oauthData,
            slidingSyncVersion: slidingSyncVersion(data.slidingSyncVersion)
        )
    }

    // NOTE: le SDK amont épinglé (26.09.07) ne déclare que `.none` et `.native` sur
    // `SlidingSyncVersion` (le type porté par `Session`) ; `.discoverNative` n'existe que sur
    // `SlidingSyncVersionBuilder`, un type distinct utilisé ailleurs pour la configuration du
    // client. La chaîne persistée reste néanmoins tolérante à `"discoverNative"` en lecture pour
    // rester compatible avec le contrat documenté par ``MatrixSessionData``.

    private static func slidingSyncIdentifier(_ version: SlidingSyncVersion) -> String {
        switch version {
        case .none: "none"
        case .native: "native"
        }
    }

    private static func slidingSyncVersion(_ identifier: String) -> SlidingSyncVersion {
        switch identifier {
        case "none": .none
        default: .native
        }
    }
}
