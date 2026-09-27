import Foundation

/// What the homeserver needs to push notifications to this device through a push gateway.
///
/// The gateway — typically [Sygnal](https://github.com/matrix-org/sygnal) — is run by the
/// application's publisher: it holds the APNs credentials and forwards each push to Apple.
public struct PusherConfiguration: Sendable, Hashable {
    /// The APNs device token, exactly as `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
    /// hands it over.
    public let deviceToken: Data
    /// The identifier the gateway knows this application by, for instance
    /// `com.example.app.ios.prod`.
    public let appID: String
    /// The gateway's notify endpoint, ending in `/_matrix/push/v1/notify`.
    public let gatewayURL: URL
    /// The application's name, shown in the user's list of pushers.
    public let appDisplayName: String
    /// This device's name, shown in the user's list of pushers.
    public let deviceDisplayName: String
    /// The language the homeserver should use for this pusher, as a language code such as `en`.
    public let language: String
    /// What the notification says when the service extension cannot resolve it in time. Provide
    /// it in the user's language.
    public let fallbackAlert: String

    public init(
        deviceToken: Data,
        appID: String,
        gatewayURL: URL,
        appDisplayName: String,
        deviceDisplayName: String,
        language: String = Locale.current.language.languageCode?.identifier ?? "en",
        fallbackAlert: String = "New message"
    ) {
        self.deviceToken = deviceToken
        self.appID = appID
        self.gatewayURL = gatewayURL
        self.appDisplayName = appDisplayName
        self.deviceDisplayName = deviceDisplayName
        self.language = language
        self.fallbackAlert = fallbackAlert
    }

    /// The key identifying this device to the gateway: the device token encoded in base64.
    ///
    /// This is the encoding Sygnal's APNs pushkin expects by default: it decodes the push key from
    /// base64 before handing the token to Apple. A gateway configured to read another encoding
    /// must be reconfigured to match.
    public var pushKey: String {
        deviceToken.base64EncodedString()
    }

    /// Le `default_payload` du pusher, fusionné par la passerelle dans chaque push APNs.
    ///
    /// - Important: sans `mutable-content`, iOS n'appelle jamais l'extension de service ; sans
    ///   `alert`, il ne l'appelle pas non plus. Clés triées : la sortie est stable, donc testable.
    package func defaultPayload() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(DefaultPayload(aps: .init(alert: .init(body: fallbackAlert))))
        return String(decoding: data, as: UTF8.self)
    }
}

private struct DefaultPayload: Encodable {
    struct APS: Encodable {
        struct Alert: Encodable {
            let body: String
        }

        let alert: Alert
        let mutableContent = 1

        enum CodingKeys: String, CodingKey {
            case alert
            case mutableContent = "mutable-content"
        }
    }

    let aps: APS
}
