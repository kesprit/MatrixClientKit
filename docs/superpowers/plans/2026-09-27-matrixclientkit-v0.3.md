# MatrixClientKit 0.3 — Plan d'implémentation

> **Pour les agents :** SOUS-SKILL REQUIS — utiliser `superpowers:subagent-driven-development`
> (recommandé) ou `superpowers:executing-plans` pour exécuter ce plan tâche par tâche. Les étapes
> utilisent la syntaxe à cases à cocher (`- [ ]`) pour le suivi.

**Goal :** livrer MatrixClientKit 0.3.0 — notifications push complètes depuis une extension de
service (pusher, résolution de la notification, verrou inter-processus) et mode de notification
par salon.

**Architecture :** aucun nouveau module. Protocoles publics et modèles dans `MatrixClientKitCore` ;
implémentations adossées au SDK dans `MatrixClientKitRust`, derrière des coutures `*Driving` qui
les rendent testables sans binaire ; point d'entrée de l'extension et aide `UserNotifications`
dans l'umbrella `MatrixClientKit` ; doubles dans `MatrixClientKitMocks`. Le verrou inter-processus
est choisi en un point unique, `SessionRestorer`, selon le stockage et le rôle du client
(application ou extension).

**Tech Stack :** Swift 6.2 (mode 6, strict concurrency), Swift Testing, SPM, `UserNotifications`,
`matrix-rust-components-swift` `26.09.07` (inchangé).

**Spec :** `docs/superpowers/specs/2026-09-27-matrixclientkit-v0.3-design.md` (à lire en entier ;
la spec de référence `2026-09-13-matrixclientkit-design.md` et la spec 0.2
`2026-09-17-matrixclientkit-v0.2-design.md` restent valables pour ce qui n'y est pas redit).

## Global Constraints

Ces contraintes s'appliquent à **toutes** les tâches ; elles ne sont pas répétées ensuite.

- `MatrixClientKitCore` **ne contient jamais** `import MatrixRustSDK`.
- Aucun type amont dans une signature `public` de `MatrixClientKit`, `MatrixClientKitCore` ou
  `MatrixClientKitMocks`.
- Aucun `@MainActor` dans Core ni Rust. Tous les types publics sont `Sendable`. Swift 6 strict.
- Flux de diffs en `.unbounded`, flux d'instantanés en `.bufferingNewest(1)`.
- **Aucun nouveau cas dans `MatrixError`**, ni au premier niveau ni dans un enum imbriqué.
- Swift Testing uniquement (`import Testing`), jamais XCTest. TDD : test rouge avant code.
- Commandes de vérification, à lancer avant chaque commit :
  - `swift build --build-tests`
  - `swift test --skip MatrixClientKitIntegrationTests`
  - `swift format lint --recursive --strict Sources Tests` (longueur de ligne : 120)
- Langue : anglais pour tout ce que lit un consommateur (commentaires `///` de l'API publique,
  chaînes renvoyées à l'application, README, DocC, CHANGELOG) ; commentaires internes
  d'implémentation en français, comme le code existant. Messages de commit en français.
- Type de commit fidèle au contenu : un commit qui change une API publique n'est jamais `docs:`.
- Chaque commit se termine par la ligne `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Collisions de noms : `RoomNotificationMode` et `RoomNotificationSettings` existent dans les deux
  modules. Dans `MatrixClientKitRust` et ses tests, toujours qualifier
  (`MatrixRustSDK.RoomNotificationMode`, `MatrixClientKitCore.RoomNotificationMode`).
- Conversions numériques depuis l'amont : toujours `Int(clamping:)`, jamais `Int(_:)`.
- Ne jamais pousser, taguer ni publier sans l'accord explicite de l'utilisateur (Task 12).

---

## Structure des fichiers

```
Sources/
  MatrixClientKitCore/
    Models/RoomNotificationMode.swift            // NOUVEAU — RoomNotificationMode, RoomNotificationSettings
    Models/PusherConfiguration.swift             // NOUVEAU — configuration, pushKey, defaultPayload() (package)
    Models/MatrixPushPayload.swift               // NOUVEAU — lecture du payload APNs
    Models/Notification.swift                    // NOUVEAU — MatrixNotification, NotificationResult
    Services/NotificationService.swift           // NOUVEAU — protocole
    Services/NotificationContentResolving.swift  // NOUVEAU — protocole de l'extension
    Services/MatrixSession.swift                 // MODIFIÉ — notifications (Task 7)
    PackageInfo.swift                            // MODIFIÉ — 0.3.0 (Task 12)
  MatrixClientKitRust/
    Bridge/CrossProcessLock.swift                // NOUVEAU — ClientRole, choix du verrou (fonction pure)
    Bridge/NotificationDriving.swift             // NOUVEAU — coutures PusherDriving, NotificationSettingsDriving, NotificationClientDriving
    Bridge/NotificationMapper.swift              // NOUVEAU — statut, contenu, modes, erreurs
    Bridge/TimelineMapper.swift                  // MODIFIÉ — constante de la phrase UTD générique
    RustNotificationService.swift                // NOUVEAU — pusher et paramètres
    RustNotificationResolver.swift               // NOUVEAU — résolution dans l'extension
    SessionRestorer.swift                        // MODIFIÉ — rôle, LockPolicy, makeNotificationResolver()
    RustMatrixClient.swift                       // MODIFIÉ — init interne avec restorer (Task 10)
    RustMatrixSession.swift                      // MODIFIÉ — branchement de notifications
  MatrixClientKit/
    MatrixNotificationService.swift              // NOUVEAU — point d'entrée de l'extension
    UNMutableNotificationContent+Matrix.swift    // NOUVEAU — apply(_:)
    Documentation.docc/PushNotifications.md      // NOUVEAU — article
    Documentation.docc/MatrixClientKit.md        // MODIFIÉ — Topics
  MatrixClientKitMocks/
    MockNotificationService.swift                // NOUVEAU
    MockNotificationResolver.swift               // NOUVEAU
    MockMatrixSession.swift                      // MODIFIÉ — notifications (Task 7)
    SampleData.swift                             // MODIFIÉ — notification(), pusherConfiguration()
Tests/
  MatrixClientKitCoreTests/NotificationModelTests.swift        // NOUVEAU
  MatrixClientKitCoreTests/NotificationMockTests.swift         // NOUVEAU
  MatrixClientKitRustTests/CrossProcessLockTests.swift         // NOUVEAU
  MatrixClientKitRustTests/NotificationMapperTests.swift       // NOUVEAU
  MatrixClientKitRustTests/NotificationServiceTests.swift      // NOUVEAU
  MatrixClientKitRustTests/NotificationResolverTests.swift     // NOUVEAU
  MatrixClientKitTests/NotificationContentTests.swift          // NOUVEAU
  MatrixClientKitIntegrationTests/NotificationTests.swift      // NOUVEAU
  MatrixClientKitIntegrationTests/IntegrationSupport.swift     // MODIFIÉ
  MatrixClientKitIntegrationTests/README.md                    // MODIFIÉ
Scripts/check-integration-env.sh                               // MODIFIÉ
Package.swift                                                  // MODIFIÉ — dépendance de test (Task 10)
README.md, CHANGELOG.md, docs/superpowers/specs/*.md           // MODIFIÉS (Tasks 1, 11, 12)
```

---

### Task 1 : Vérifications amont

Tâche d'investigation : aucune ligne de code de production. Elle lève les quatre incertitudes du
§10 de la spec avant que le code n'en dépende.

**Files:**
- Modify: `docs/superpowers/specs/2026-09-27-matrixclientkit-v0.3-design.md` (nouvelle section
  « 2 bis. Constats vérifiés », juste après le §2)

**Interfaces:**
- Consumes: rien.
- Produces: des constats écrits dans la spec, que les Tasks 4, 5, 6 et 11 appliquent.

- [ ] **Step 1 : retrouver la révision Rust de la release épinglée**

`matrix-rust-components-swift` `26.09.07` est générée depuis un commit de `matrix-rust-sdk`. Le
retrouver :

```bash
gh release view 26.09.07 --repo matrix-org/matrix-rust-components-swift --json body,tagName
```

Le corps de la release, ou le message du commit taggué, nomme le commit ou le tag de
`matrix-rust-sdk`. Le noter : `<REV>`.

- [ ] **Step 2 : défaut de `crossProcessLockConfig`**

```bash
gh api "repos/matrix-org/matrix-rust-sdk/contents/bindings/matrix-sdk-ffi/src/client_builder.rs?ref=<REV>" \
  --jq .content | base64 -d | grep -n -i -E "cross_process|CrossProcessLockConfig" | head -40
```

Noter la valeur que prend le builder quand `crossProcessLockConfig` n'est jamais appelé
(`SingleProcess` ou `MultiProcess` avec quel `holderName`). C'est le comportement de la 0.2.

- [ ] **Step 3 : comportement de `getNotification` quand l'application détient le verrou**

```bash
gh api "repos/matrix-org/matrix-rust-sdk/contents/crates/matrix-sdk-ui/src/notification_client.rs?ref=<REV>" \
  --jq .content | base64 -d | grep -n -i -E "lock|MultipleProcesses|process_setup" | head -60
```

Lire les passages trouvés et noter : l'extension attend-elle le verrou, échoue-t-elle, ou
procède-t-elle sans ? Avec quel délai ? Ce constat est repris dans l'article DocC (Task 11).

- [ ] **Step 4 : payload APNs de Sygnal en `event_id_only`**

```bash
gh api "repos/matrix-org/sygnal/contents/sygnal/apnspushkin.py" --jq .content | base64 -d \
  | grep -n -E "event_id_only|room_id|event_id|default_payload|mutable" | head -40
```

Vérifier : (a) `room_id` et `event_id` sont à la racine du payload ; (b) `default_payload` est
fusionné à la racine du payload APNs, donc un `aps` fourni par le pusher arrive tel quel. Si l'un
des deux est faux, **arrêter** et le signaler : `MatrixPushPayload` et `defaultPayload()` en
dépendent.

- [ ] **Step 5 : définition de « un à un » chez Element X**

```bash
gh search code --repo element-hq/element-x-ios "isOneToOne:" --json path,textMatches | head -80
```

Noter l'expression utilisée pour `isOneToOne` lors de l'appel à
`getRoomNotificationSettings` (attendu : `activeMembersCount == 2`). La Task 7 l'applique.

- [ ] **Step 6 : consigner**

Ajouter à la spec, après le §2 :

```markdown
## 2 bis. Constats vérifiés (Task 1 du plan)

Révision `matrix-rust-sdk` de la release `26.09.07` : `<REV>`.

1. Défaut de `crossProcessLockConfig` : <constat, avec le fichier et la ligne>.
2. `getNotification` et le verrou tenu par l'application : <constat>.
3. Payload Sygnal `event_id_only` : <constat pour room_id/event_id et pour default_payload>.
4. `isOneToOne` chez Element X : <expression exacte>.
```

Remplacer chaque `<…>` par le constat réel. Si un constat contredit la spec, corriger la section
concernée de la spec dans le même commit et le signaler dans le rapport de tâche.

- [ ] **Step 7 : commit**

```bash
git add docs/superpowers/specs/2026-09-27-matrixclientkit-v0.3-design.md
git commit -m "docs: constats amont de la 0.3 — verrou, payload Sygnal, un à un

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2 : Modèles Core de notification

**Files:**
- Create: `Sources/MatrixClientKitCore/Models/RoomNotificationMode.swift`
- Create: `Sources/MatrixClientKitCore/Models/PusherConfiguration.swift`
- Create: `Sources/MatrixClientKitCore/Models/MatrixPushPayload.swift`
- Create: `Sources/MatrixClientKitCore/Models/Notification.swift`
- Test: `Tests/MatrixClientKitCoreTests/NotificationModelTests.swift`

**Interfaces:**
- Consumes: `RoomID`, `EventID`, `UserID` (existants, `init?(rawValue:)`).
- Produces:
  - `public enum RoomNotificationMode { case allMessages, mentionsAndKeywordsOnly, mute }`
  - `public struct RoomNotificationSettings { mode: RoomNotificationMode; isDefault: Bool; init(mode:isDefault:) }`
  - `public struct PusherConfiguration { deviceToken: Data; appID: String; gatewayURL: URL; appDisplayName: String; deviceDisplayName: String; language: String; fallbackAlert: String; var pushKey: String; package func defaultPayload() throws -> String }`
  - `public struct MatrixPushPayload { roomID: RoomID; eventID: EventID; init(roomID:eventID:); init?(userInfo: [AnyHashable: Any]) }`
  - `public struct MatrixNotification { enum Kind { case message(body: String), invite }; roomID; eventID; sender: UserID; senderDisplayName: String?; roomDisplayName: String; isDirect: Bool; kind: Kind; isNoisy: Bool; hasMention: Bool; threadID: EventID?; init(...) }`
  - `public enum NotificationResult { case notification(MatrixNotification), notFound, filteredOut, redacted }`

- [ ] **Step 1 : écrire les tests en échec**

`Tests/MatrixClientKitCoreTests/NotificationModelTests.swift` :

```swift
import Testing
import Foundation
import MatrixClientKitCore

// MARK: MatrixPushPayload

@Test func pushPayloadReadsTheRoomAndEventAtTheRoot() throws {
    let payload = try #require(
        MatrixPushPayload(userInfo: [
            "aps": ["mutable-content": 1],
            "room_id": "!room:matrix.org",
            "event_id": "$event",
            "unread_count": 2,
        ])
    )

    #expect(payload.roomID == RoomID(rawValue: "!room:matrix.org"))
    #expect(payload.eventID == EventID(rawValue: "$event"))
}

@Test(arguments: [
    ["event_id": "$event"],
    ["room_id": "!room:matrix.org"],
    ["room_id": "#alias:matrix.org", "event_id": "$event"],
    ["room_id": "!room:matrix.org", "event_id": "event-sans-dollar"],
    ["room_id": 42, "event_id": "$event"],
] as [[AnyHashable: Any]])
func pushPayloadRejectsAMissingOrInvalidIdentifier(userInfo: [AnyHashable: Any]) {
    #expect(MatrixPushPayload(userInfo: userInfo) == nil)
}

// MARK: PusherConfiguration

private func configuration(token: [UInt8], fallbackAlert: String = "New message") -> PusherConfiguration {
    PusherConfiguration(
        deviceToken: Data(token),
        appID: "com.example.app.ios.prod",
        gatewayURL: URL(string: "https://push.example.com/_matrix/push/v1/notify")!,
        appDisplayName: "Example",
        deviceDisplayName: "iPhone",
        language: "en",
        fallbackAlert: fallbackAlert
    )
}

@Test func pushKeyIsTheTokenInLowercaseHexadecimal() {
    #expect(configuration(token: [0x00, 0x0F, 0xAB, 0xFF]).pushKey == "000fabff")
}

@Test func pushKeyOfAnEmptyTokenIsEmpty() {
    #expect(configuration(token: []).pushKey.isEmpty)
}

@Test func defaultPayloadAsksForTheExtensionAndCarriesTheFallbackAlert() throws {
    let payload = try configuration(token: [1]).defaultPayload()

    #expect(payload == #"{"aps":{"alert":{"body":"New message"},"mutable-content":1}}"#)
}

@Test func defaultPayloadEscapesTheFallbackAlert() throws {
    let payload = try configuration(token: [1], fallbackAlert: #"Nouveau "message""#).defaultPayload()

    #expect(payload == #"{"aps":{"alert":{"body":"Nouveau \"message\""},"mutable-content":1}}"#)
}

@Test func languageDefaultsToALanguageCode() {
    let configuration = PusherConfiguration(
        deviceToken: Data([1]),
        appID: "com.example.app",
        gatewayURL: URL(string: "https://push.example.com/_matrix/push/v1/notify")!,
        appDisplayName: "Example",
        deviceDisplayName: "iPhone"
    )

    #expect(!configuration.language.isEmpty)
    #expect(!configuration.language.contains("_"))
    #expect(configuration.fallbackAlert == "New message")
}
```

- [ ] **Step 2 : vérifier l'échec**

Run : `swift build --build-tests`
Expected : échec de compilation, `cannot find 'MatrixPushPayload' in scope` (et
`PusherConfiguration`).

- [ ] **Step 3 : écrire les modèles**

`Sources/MatrixClientKitCore/Models/RoomNotificationMode.swift` :

```swift
/// How much a room notifies the user.
public enum RoomNotificationMode: Sendable, Hashable {
    /// Every message notifies.
    case allMessages
    /// Only mentions and keywords notify.
    case mentionsAndKeywordsOnly
    /// Nothing notifies.
    case mute
}

/// A room's notification setting.
public struct RoomNotificationSettings: Sendable, Hashable {
    /// The mode in effect, whether the user chose it for this room or it comes from the account's
    /// defaults.
    public let mode: RoomNotificationMode
    /// True when the user has set nothing for this room, so the account's default applies.
    public let isDefault: Bool

    public init(mode: RoomNotificationMode, isDefault: Bool) {
        self.mode = mode
        self.isDefault = isDefault
    }
}
```

`Sources/MatrixClientKitCore/Models/PusherConfiguration.swift` :

```swift
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

    /// The key identifying this device to the gateway: the device token in lowercase hexadecimal.
    public var pushKey: String {
        deviceToken.map { String(format: "%02x", $0) }.joined()
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
```

`Sources/MatrixClientKitCore/Models/MatrixPushPayload.swift` :

```swift
/// The room and event a Matrix push is about, read from the notification's `userInfo`.
///
/// It reads the `room_id` and `event_id` keys at the root of the payload, where Sygnal puts them
/// for a pusher in the `event_id_only` format — the format ``NotificationService`` registers.
public struct MatrixPushPayload: Sendable, Hashable {
    public let roomID: RoomID
    public let eventID: EventID

    public init(roomID: RoomID, eventID: EventID) {
        self.roomID = roomID
        self.eventID = eventID
    }

    /// Returns `nil` when `room_id` or `event_id` is missing, is not a string, or is not a valid
    /// identifier — for instance a push that does not come from Matrix.
    public init?(userInfo: [AnyHashable: Any]) {
        guard
            let room = userInfo["room_id"] as? String,
            let roomID = RoomID(rawValue: room),
            let event = userInfo["event_id"] as? String,
            let eventID = EventID(rawValue: event)
        else { return nil }

        self.init(roomID: roomID, eventID: eventID)
    }
}
```

`Sources/MatrixClientKitCore/Models/Notification.swift` :

```swift
/// A notification resolved from a push, ready to be displayed.
public struct MatrixNotification: Sendable, Hashable {
    /// What the notification is about.
    public enum Kind: Sendable, Hashable {
        /// A message, with its text as it should appear in the notification.
        case message(body: String)
        /// An invitation to join the room.
        case invite
    }

    public let roomID: RoomID
    public let eventID: EventID
    /// Who sent the message or the invitation.
    public let sender: UserID
    /// The sender's display name, when known.
    public let senderDisplayName: String?
    /// The room's display name.
    public let roomDisplayName: String
    /// True for a direct conversation.
    public let isDirect: Bool
    public let kind: Kind
    /// True when the user's push rules ask for a sound.
    public let isNoisy: Bool
    /// True when the message mentions the user.
    public let hasMention: Bool
    /// The thread the message belongs to, if any.
    public let threadID: EventID?

    public init(
        roomID: RoomID,
        eventID: EventID,
        sender: UserID,
        senderDisplayName: String?,
        roomDisplayName: String,
        isDirect: Bool,
        kind: Kind,
        isNoisy: Bool,
        hasMention: Bool,
        threadID: EventID?
    ) {
        self.roomID = roomID
        self.eventID = eventID
        self.sender = sender
        self.senderDisplayName = senderDisplayName
        self.roomDisplayName = roomDisplayName
        self.isDirect = isDirect
        self.kind = kind
        self.isNoisy = isNoisy
        self.hasMention = hasMention
        self.threadID = threadID
    }
}

/// The outcome of resolving a push.
public enum NotificationResult: Sendable, Hashable {
    /// The event was found: display it.
    case notification(MatrixNotification)
    /// The event could not be found. Displaying the push's original content is a reasonable
    /// fallback.
    case notFound
    /// The user's push rules, or an ignored sender, rule the event out: display nothing.
    case filteredOut
    /// The event was deleted: display nothing.
    case redacted
}
```

- [ ] **Step 4 : vérifier que les tests passent**

Run : `swift test --filter NotificationModelTests`
Expected : tous les tests de `NotificationModelTests.swift` passent. Si `EventID(rawValue:)`
accepte un identifiant sans `$`, le cas `"event-sans-dollar"` échoue : lire
`Sources/MatrixClientKitCore/Identifiers/EventID.swift` et remplacer ce cas par une valeur que
`EventID` rejette réellement (par exemple `""`), sans changer `EventID`.

- [ ] **Step 5 : vérifications globales et commit**

```bash
swift build --build-tests && swift test --skip MatrixClientKitIntegrationTests \
  && swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKitCore/Models Tests/MatrixClientKitCoreTests/NotificationModelTests.swift
git commit -m "feat: modèles de notification, de pusher et de payload push

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3 : Protocoles de notification et leurs mocks

`MatrixSession` n'est **pas** modifié ici (Task 7) : l'ajout du membre casserait la compilation de
`RustMatrixSession` avant que son implémentation existe.

**Files:**
- Create: `Sources/MatrixClientKitCore/Services/NotificationService.swift`
- Create: `Sources/MatrixClientKitCore/Services/NotificationContentResolving.swift`
- Create: `Sources/MatrixClientKitMocks/MockNotificationService.swift`
- Create: `Sources/MatrixClientKitMocks/MockNotificationResolver.swift`
- Modify: `Sources/MatrixClientKitMocks/SampleData.swift` (ajout en fin d'enum)
- Test: `Tests/MatrixClientKitCoreTests/NotificationMockTests.swift`

**Interfaces:**
- Consumes (Task 2) : `PusherConfiguration`, `RoomNotificationMode`, `RoomNotificationSettings`,
  `MatrixPushPayload(roomID:eventID:)`, `MatrixNotification`, `NotificationResult`.
- Produces:
  - `public protocol NotificationService: Sendable` — `registerPusher(_: PusherConfiguration) async throws`, `unregisterPusher(_: PusherConfiguration) async throws`, `notificationSettings(for: RoomID) async throws -> RoomNotificationSettings`, `setNotificationMode(_: RoomNotificationMode, for: RoomID) async throws`, `restoreDefaultNotificationMode(for: RoomID) async throws`
  - `public protocol NotificationContentResolving: Sendable` — `notification(roomID: RoomID, eventID: EventID) async throws -> NotificationResult`
  - `MockNotificationService` : `registeredPushers`, `unregisteredPushers`, `settings(for:)`, `setSettings(_:for:)`, `defaultSettings`, `registerError`, `unregisterError`, `settingsError`
  - `MockNotificationResolver` : `setResult(_:roomID:eventID:)`, `defaultResult`, `error`, `requests: [MatrixPushPayload]`
  - `SampleData.notification(kind:isDirect:isNoisy:)`, `SampleData.pusherConfiguration()`

- [ ] **Step 1 : écrire les tests en échec**

`Tests/MatrixClientKitCoreTests/NotificationMockTests.swift` :

```swift
import Testing
import Foundation
import MatrixClientKitCore
import MatrixClientKitMocks

private let room = RoomID(rawValue: "!room:matrix.org")!
private let event = EventID(rawValue: "$event")!

@Test func mockNotificationServiceRecordsPushers() async throws {
    let service = MockNotificationService()
    let configuration = SampleData.pusherConfiguration()

    try await service.registerPusher(configuration)
    try await service.unregisterPusher(configuration)

    #expect(service.registeredPushers == [configuration])
    #expect(service.unregisteredPushers == [configuration])
}

@Test func mockNotificationServiceStartsFromTheDefaultSettings() async throws {
    let service = MockNotificationService()

    let settings = try await service.notificationSettings(for: room)

    #expect(settings == RoomNotificationSettings(mode: .allMessages, isDefault: true))
}

@Test func mockNotificationServiceAppliesAndRestoresAMode() async throws {
    let service = MockNotificationService()

    try await service.setNotificationMode(.mute, for: room)
    #expect(try await service.notificationSettings(for: room) == RoomNotificationSettings(mode: .mute, isDefault: false))

    try await service.restoreDefaultNotificationMode(for: room)
    #expect(try await service.notificationSettings(for: room) == service.defaultSettings)
}

@Test func mockNotificationServiceFailsEachOperationOnDemand() async {
    let service = MockNotificationService()
    service.registerError = .network(.offline)
    service.settingsError = .notFound(.room)

    await #expect(throws: MatrixError.network(.offline)) {
        try await service.registerPusher(SampleData.pusherConfiguration())
    }
    await #expect(throws: MatrixError.notFound(.room)) {
        try await service.setNotificationMode(.mute, for: room)
    }
    #expect(service.registeredPushers.isEmpty)
}

@Test func mockResolverReturnsTheResultSetForAnEvent() async throws {
    let resolver = MockNotificationResolver()
    let notification = SampleData.notification()
    resolver.setResult(.notification(notification), roomID: room, eventID: event)

    let result = try await resolver.notification(roomID: room, eventID: event)

    #expect(result == .notification(notification))
    #expect(resolver.requests == [MatrixPushPayload(roomID: room, eventID: event)])
}

@Test func mockResolverFallsBackToTheDefaultResult() async throws {
    let resolver = MockNotificationResolver()
    resolver.defaultResult = .filteredOut

    #expect(try await resolver.notification(roomID: room, eventID: event) == .filteredOut)
}

@Test func mockResolverThrowsTheInjectedError() async {
    let resolver = MockNotificationResolver()
    resolver.error = .authentication(.missingToken)

    await #expect(throws: MatrixError.authentication(.missingToken)) {
        try await resolver.notification(roomID: room, eventID: event)
    }
    #expect(resolver.requests.count == 1)
}
```

- [ ] **Step 2 : vérifier l'échec**

Run : `swift build --build-tests`
Expected : échec, `cannot find 'MockNotificationService' in scope`.

- [ ] **Step 3 : écrire les protocoles**

`Sources/MatrixClientKitCore/Services/NotificationService.swift` :

```swift
/// Push notifications for a session: this device's pusher, and how much each room notifies.
public protocol NotificationService: Sendable {
    /// Registers this device with the homeserver, so that it pushes notifications to it through
    /// the gateway.
    ///
    /// Call it every time the application receives a device token — tokens change. It replaces
    /// any pusher registered before for the same token and application identifier. The pusher
    /// asks APNs to wake the notification service extension, which then resolves the content
    /// with ``NotificationContentResolving``: the message itself never goes through Apple.
    func registerPusher(_ configuration: PusherConfiguration) async throws

    /// Stops pushes to this device for this token and application identifier.
    ///
    /// Signing out removes this device's pushers server-side: there is no need to call this
    /// before ``MatrixSession/logout()``.
    func unregisterPusher(_ configuration: PusherConfiguration) async throws

    /// The room's notification setting.
    ///
    /// - Throws: ``MatrixError/notFound(_:)`` with ``MatrixError/Resource/room`` when the room is
    ///   not known to this session yet.
    func notificationSettings(for roomID: RoomID) async throws -> RoomNotificationSettings

    /// Sets how much the room notifies, overriding the account's default for it.
    func setNotificationMode(_ mode: RoomNotificationMode, for roomID: RoomID) async throws

    /// Removes the room's own setting, so that the account's default applies again.
    func restoreDefaultNotificationMode(for roomID: RoomID) async throws
}
```

`Sources/MatrixClientKitCore/Services/NotificationContentResolving.swift` :

```swift
/// Resolves a push into a displayable notification, from a notification service extension.
///
/// It never syncs: syncing from the extension, while the application may be syncing the same
/// store, corrupts the application's state.
public protocol NotificationContentResolving: Sendable {
    /// Fetches and decrypts the event a push is about.
    ///
    /// - Throws: a ``MatrixError`` when the notification cannot be resolved — display the push's
    ///   original content instead.
    func notification(roomID: RoomID, eventID: EventID) async throws -> NotificationResult
}
```

- [ ] **Step 4 : écrire les mocks et les fixtures**

`Sources/MatrixClientKitMocks/MockNotificationService.swift` :

```swift
import Foundation
import MatrixClientKitCore

/// A drivable ``NotificationService``: records pushers and room modes, and fails on demand.
public final class MockNotificationService: NotificationService, @unchecked Sendable {
    private let lock = NSLock()

    private var _registeredPushers: [PusherConfiguration] = []
    private var _unregisteredPushers: [PusherConfiguration] = []
    private var _settings: [RoomID: RoomNotificationSettings] = [:]
    private var _defaultSettings = RoomNotificationSettings(mode: .allMessages, isDefault: true)
    private var _registerError: MatrixError?
    private var _unregisterError: MatrixError?
    private var _settingsError: MatrixError?

    public init() {}

    /// The configurations passed to ``registerPusher(_:)`` that succeeded, in order.
    public var registeredPushers: [PusherConfiguration] { lock.withLock { _registeredPushers } }

    /// The configurations passed to ``unregisterPusher(_:)`` that succeeded, in order.
    public var unregisteredPushers: [PusherConfiguration] { lock.withLock { _unregisteredPushers } }

    /// What a room without its own setting reports. Defaults to all messages, as a default.
    public var defaultSettings: RoomNotificationSettings {
        get { lock.withLock { _defaultSettings } }
        set { lock.withLock { _defaultSettings = newValue } }
    }

    /// The error ``registerPusher(_:)`` throws. `nil` by default.
    public var registerError: MatrixError? {
        get { lock.withLock { _registerError } }
        set { lock.withLock { _registerError = newValue } }
    }

    /// The error ``unregisterPusher(_:)`` throws. `nil` by default.
    public var unregisterError: MatrixError? {
        get { lock.withLock { _unregisterError } }
        set { lock.withLock { _unregisterError = newValue } }
    }

    /// The error the three room-setting methods throw. `nil` by default.
    public var settingsError: MatrixError? {
        get { lock.withLock { _settingsError } }
        set { lock.withLock { _settingsError = newValue } }
    }

    /// Sets what ``notificationSettings(for:)`` reports for a room.
    public func setSettings(_ settings: RoomNotificationSettings, for roomID: RoomID) {
        lock.withLock { _settings[roomID] = settings }
    }

    public func registerPusher(_ configuration: PusherConfiguration) async throws {
        try lock.withLock {
            if let error = _registerError { throw error }
            _registeredPushers.append(configuration)
        }
    }

    public func unregisterPusher(_ configuration: PusherConfiguration) async throws {
        try lock.withLock {
            if let error = _unregisterError { throw error }
            _unregisteredPushers.append(configuration)
        }
    }

    public func notificationSettings(for roomID: RoomID) async throws -> RoomNotificationSettings {
        try lock.withLock {
            if let error = _settingsError { throw error }
            return _settings[roomID] ?? _defaultSettings
        }
    }

    public func setNotificationMode(_ mode: RoomNotificationMode, for roomID: RoomID) async throws {
        try lock.withLock {
            if let error = _settingsError { throw error }
            _settings[roomID] = RoomNotificationSettings(mode: mode, isDefault: false)
        }
    }

    public func restoreDefaultNotificationMode(for roomID: RoomID) async throws {
        try lock.withLock {
            if let error = _settingsError { throw error }
            _settings[roomID] = nil
        }
    }
}
```

`Sources/MatrixClientKitMocks/MockNotificationResolver.swift` :

```swift
import Foundation
import MatrixClientKitCore

/// A drivable ``NotificationContentResolving`` for testing a notification service extension.
public final class MockNotificationResolver: NotificationContentResolving, @unchecked Sendable {
    private let lock = NSLock()

    private var _results: [MatrixPushPayload: NotificationResult] = [:]
    private var _defaultResult: NotificationResult = .notFound
    private var _error: MatrixError?
    private var _requests: [MatrixPushPayload] = []

    public init() {}

    /// What an event without a result of its own resolves to. ``NotificationResult/notFound`` by
    /// default.
    public var defaultResult: NotificationResult {
        get { lock.withLock { _defaultResult } }
        set { lock.withLock { _defaultResult = newValue } }
    }

    /// The error every resolution throws. `nil` by default.
    public var error: MatrixError? {
        get { lock.withLock { _error } }
        set { lock.withLock { _error = newValue } }
    }

    /// Every event asked for, in order, including those that threw.
    public var requests: [MatrixPushPayload] { lock.withLock { _requests } }

    /// Sets what one event resolves to.
    public func setResult(_ result: NotificationResult, roomID: RoomID, eventID: EventID) {
        lock.withLock { _results[MatrixPushPayload(roomID: roomID, eventID: eventID)] = result }
    }

    public func notification(roomID: RoomID, eventID: EventID) async throws -> NotificationResult {
        let key = MatrixPushPayload(roomID: roomID, eventID: eventID)
        return try lock.withLock {
            _requests.append(key)
            if let error = _error { throw error }
            return _results[key] ?? _defaultResult
        }
    }
}
```

Dans `Sources/MatrixClientKitMocks/SampleData.swift`, ajouter avant l'accolade fermante de
`SampleData` :

```swift
    /// Builds a sample ``MatrixNotification`` from Alice in the "Lounge" room.
    public static func notification(
        kind: MatrixNotification.Kind = .message(body: "Hello"),
        isDirect: Bool = false,
        isNoisy: Bool = true
    ) -> MatrixNotification {
        MatrixNotification(
            roomID: RoomID(rawValue: "!room:matrix.org")!,
            eventID: EventID(rawValue: "$event")!,
            sender: UserID(rawValue: "@alice:matrix.org")!,
            senderDisplayName: "Alice",
            roomDisplayName: "Lounge",
            isDirect: isDirect,
            kind: kind,
            isNoisy: isNoisy,
            hasMention: false,
            threadID: nil
        )
    }

    /// Builds a sample ``PusherConfiguration`` pointing at a gateway on `example.com`.
    public static func pusherConfiguration() -> PusherConfiguration {
        PusherConfiguration(
            deviceToken: Data([0xDE, 0xAD, 0xBE, 0xEF]),
            appID: "com.example.app.ios.dev",
            gatewayURL: URL(string: "https://push.example.com/_matrix/push/v1/notify")!,
            appDisplayName: "Example",
            deviceDisplayName: "iPhone",
            language: "en"
        )
    }
```

- [ ] **Step 5 : vérifier que les tests passent**

Run : `swift test --filter NotificationMockTests`
Expected : PASS.

- [ ] **Step 6 : vérifications globales et commit**

```bash
swift build --build-tests && swift test --skip MatrixClientKitIntegrationTests \
  && swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKitCore/Services Sources/MatrixClientKitMocks Tests/MatrixClientKitCoreTests/NotificationMockTests.swift
git commit -m "feat: protocoles de notification et d'extension, et leurs mocks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4 : Verrou inter-processus et rôle du client

**Files:**
- Create: `Sources/MatrixClientKitRust/Bridge/CrossProcessLock.swift`
- Modify: `Sources/MatrixClientKitRust/SessionRestorer.swift` (init, `makeClient`)
- Test: `Tests/MatrixClientKitRustTests/CrossProcessLockTests.swift`

**Interfaces:**
- Consumes : `MatrixStorage` (existant), `MatrixRustSDK.CrossProcessLockConfig`.
- Produces:
  - `enum ClientRole: Sendable { case application, notificationExtension }`
  - `enum CrossProcessLock { static func configuration(for: MatrixStorage, role: ClientRole) throws -> CrossProcessLockConfig }`
  - `SessionRestorer.LockPolicy { case automatic, unset }`
  - `SessionRestorer.init(storage:role:lockPolicy:)` et `init(storage:secureStore:role:lockPolicy:)`, `role` par défaut `.application`, `lockPolicy` par défaut `.automatic`
  - `SessionRestorer.role`, `SessionRestorer.lockConfiguration() throws -> CrossProcessLockConfig?`

- [ ] **Step 1 : écrire les tests en échec**

`Tests/MatrixClientKitRustTests/CrossProcessLockTests.swift` :

```swift
import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private let appGroup = MatrixStorage.appGroup("group.com.example.app")
private let local = MatrixStorage.local(directory: FileManager.default.temporaryDirectory)

@Test func anAppGroupApplicationTakesTheLockAsTheApp() throws {
    #expect(try CrossProcessLock.configuration(for: appGroup, role: .application) == .multiProcess(holderName: "app"))
}

@Test func anAppGroupExtensionTakesTheLockAsTheExtension() throws {
    #expect(
        try CrossProcessLock.configuration(for: appGroup, role: .notificationExtension)
            == .multiProcess(holderName: "nse")
    )
}

@Test func aLocalApplicationRunsInASingleProcess() throws {
    #expect(try CrossProcessLock.configuration(for: local, role: .application) == .singleProcess)
}

@Test func anExtensionCannotOpenALocalStorage() {
    #expect(throws: MatrixError.storage(.unavailable)) {
        try CrossProcessLock.configuration(for: local, role: .notificationExtension)
    }
}

@Test func theRestorerAppliesItsRoleByDefault() throws {
    let restorer = SessionRestorer(storage: appGroup, secureStore: InMemorySecureStore(), role: .notificationExtension)

    #expect(try restorer.lockConfiguration() == .multiProcess(holderName: "nse"))
}

@Test func theRestorerDefaultsToTheApplicationRole() throws {
    let restorer = SessionRestorer(storage: appGroup, secureStore: InMemorySecureStore())

    #expect(restorer.role == .application)
    #expect(try restorer.lockConfiguration() == .multiProcess(holderName: "app"))
}

@Test func anUnsetPolicyLeavesTheBuilderAsIn02() throws {
    let restorer = SessionRestorer(storage: appGroup, secureStore: InMemorySecureStore(), lockPolicy: .unset)

    #expect(try restorer.lockConfiguration() == nil)
}
```

- [ ] **Step 2 : vérifier l'échec**

Run : `swift build --build-tests`
Expected : échec, `cannot find 'CrossProcessLock' in scope`.

- [ ] **Step 3 : écrire le choix du verrou**

`Sources/MatrixClientKitRust/Bridge/CrossProcessLock.swift` :

```swift
import MatrixRustSDK
import MatrixClientKitCore

/// Le processus qui ouvre le store : l'application, ou son extension de service de notification.
enum ClientRole: Sendable, Hashable {
    case application
    case notificationExtension
}

/// Choisit le verrou inter-processus du store (spec 0.3, §7).
///
/// Un stockage App Group est partagé par définition entre l'application et son extension : les
/// deux doivent prendre le verrou, sous deux noms distincts, faute de quoi elles écrivent le même
/// store crypto sans se voir. Un stockage local n'est partagé avec personne.
enum CrossProcessLock {
    static func configuration(for storage: MatrixStorage, role: ClientRole) throws -> CrossProcessLockConfig {
        switch (storage.location, role) {
        case (.appGroup, .application):
            return .multiProcess(holderName: "app")
        case (.appGroup, .notificationExtension):
            return .multiProcess(holderName: "nse")
        case (.local, .application):
            return .singleProcess
        case (.local, .notificationExtension):
            // Une extension n'a pas accès au conteneur privé de l'application.
            throw MatrixError.storage(.unavailable)
        }
    }
}
```

- [ ] **Step 4 : brancher le rôle dans `SessionRestorer`**

Dans `Sources/MatrixClientKitRust/SessionRestorer.swift`, remplacer les propriétés et les deux
initialiseurs par :

```swift
    /// Couture de test : `.unset` reproduit un client 0.2, qui n'appelait jamais
    /// `crossProcessLockConfig`. Sert uniquement au cas d'intégration qui restaure un tel store.
    enum LockPolicy: Sendable {
        case automatic
        case unset
    }

    let storage: MatrixStorage
    let secureStore: any SecureStore
    let persistence: SessionPersistence
    let role: ClientRole
    let lockPolicy: LockPolicy

    /// Le SDK s'en sert à chaque rafraîchissement de jeton : un delegate libéré ne persisterait
    /// plus rien, et l'utilisateur serait déconnecté au lancement suivant sans erreur visible.
    let sessionDelegate: SessionDelegate

    convenience init(storage: MatrixStorage, role: ClientRole = .application, lockPolicy: LockPolicy = .automatic) {
        self.init(
            storage: storage,
            secureStore: KeychainSecureStore(storage: storage),
            role: role,
            lockPolicy: lockPolicy
        )
    }

    init(
        storage: MatrixStorage,
        secureStore: any SecureStore,
        role: ClientRole = .application,
        lockPolicy: LockPolicy = .automatic
    ) {
        self.storage = storage
        self.secureStore = secureStore
        self.role = role
        self.lockPolicy = lockPolicy
        let persistence = SessionPersistence(store: secureStore)
        self.persistence = persistence
        self.sessionDelegate = SessionDelegate(persistence: persistence)
    }

    /// Le verrou à poser sur le builder, ou `nil` pour ne pas l'appeler.
    func lockConfiguration() throws -> CrossProcessLockConfig? {
        switch lockPolicy {
        case .automatic:
            return try CrossProcessLock.configuration(for: storage, role: role)
        case .unset:
            return nil
        }
    }
```

Puis remplacer le corps du `do` de `makeClient(homeserver:localStore:)` par :

```swift
            let paths = try localStore.paths()
            try paths.createDirectoriesIfNeeded()

            var builder = ClientBuilder()
                .homeserverUrl(url: homeserver.absoluteString)
                .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
                .setSessionDelegate(sessionDelegate: sessionDelegate)
                // Désactivé par défaut en amont : sans lui, un compte qui ne s'est jamais connecté
                // ailleurs n'a pas d'identité cross-signing, et la vérification échoue toujours
                // (spec 0.2, §2.8). Uniquement ici, jamais sur le client de poignée de main : son
                // store en mémoire perdrait les clés privées aussitôt créées. Jamais non plus dans
                // l'extension : amorcer une identité est une écriture de compte réservée à
                // l'application (spec 0.3, §7).
                .autoEnableCrossSigning(autoEnableCrossSigning: role == .application)
                .sqliteStore(
                    config: SqliteStoreBuilder(
                        dataPath: paths.dataDirectory.path,
                        cachePath: paths.cacheDirectory.path
                    )
                    .key(key: try localStore.encryptionKey())
                )
            if let lock = try lockConfiguration() {
                builder = builder.crossProcessLockConfig(crossProcessLockConfig: lock)
            }
            return try await builder.build()
```

- [ ] **Step 5 : vérifier que les tests passent**

Run : `swift test --filter CrossProcessLockTests`
Expected : PASS. Puis `swift test --filter SessionRestorerTests` : PASS, inchangé.

- [ ] **Step 6 : vérifications globales et commit**

```bash
swift build --build-tests && swift test --skip MatrixClientKitIntegrationTests \
  && swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKitRust Tests/MatrixClientKitRustTests/CrossProcessLockTests.swift
git commit -m "fix: verrou inter-processus explicite, choisi par le stockage et le rôle du client

Un stockage App Group est partagé avec l'extension : l'application prend désormais le verrou
multi-processus. L'extension ne peut ni ouvrir un stockage local, ni amorcer le cross-signing.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5 : Mappage des notifications

**Files:**
- Create: `Sources/MatrixClientKitRust/Bridge/NotificationMapper.swift`
- Modify: `Sources/MatrixClientKitRust/Bridge/TimelineMapper.swift` (constante UTD)
- Test: `Tests/MatrixClientKitRustTests/NotificationMapperTests.swift`

**Interfaces:**
- Consumes (Task 2) : `MatrixNotification`, `NotificationResult`, `MatrixClientKitCore.RoomNotificationMode`,
  `MatrixClientKitCore.RoomNotificationSettings`. Amont : `NotificationStatus`, `NotificationItem`,
  `NotificationSenderInfo`, `NotificationRoomInfo`, `TimelineEventProtocol`, `TimelineEventContent`,
  `MessageType`, `NotificationSettingsError`.
- Produces:
  - `TimelineMapper.undecryptableMessage: String` (`"The message could not be decrypted."`)
  - `enum NotificationEventSource { case timeline(any TimelineEventProtocol), invite(sender: String) }`
  - `NotificationMapper.result(from: NotificationStatus, roomID:, eventID:) throws -> NotificationResult`
  - `NotificationMapper.notification(source:senderInfo:roomInfo:isNoisy:hasMention:threadID:roomID:eventID:) throws -> MatrixNotification`
  - `NotificationMapper.body(for: TimelineEventContent, senderName: String) -> String`
  - `NotificationMapper.body(for: MessageType, senderName: String) -> String`
  - `NotificationMapper.mediaBody(caption: String?, fallback: String) -> String`
  - `NotificationMapper.mode(from:)`, `NotificationMapper.upstreamMode(from:)`, `NotificationMapper.settings(from:)`
  - `NotificationMapper.error(from: any Error) -> MatrixError`

- [ ] **Step 1 : écrire les tests en échec**

`Tests/MatrixClientKitRustTests/NotificationMapperTests.swift` :

```swift
import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private let room = RoomID(rawValue: "!room:matrix.org")!
private let event = EventID(rawValue: "$event")!

private struct ContentFailure: Error {}

/// `TimelineEvent` est une classe FFI qu'un test ne peut pas construire ; son protocole, si.
private final class FakeTimelineEvent: TimelineEventProtocol, @unchecked Sendable {
    let result: Result<TimelineEventContent, any Error>
    let sender: String
    let thread: String?

    init(_ content: TimelineEventContent, sender: String = "@bob:matrix.org", thread: String? = nil) {
        self.result = .success(content)
        self.sender = sender
        self.thread = thread
    }

    init(failing sender: String = "@bob:matrix.org") {
        self.result = .failure(ContentFailure())
        self.sender = sender
        self.thread = nil
    }

    func content() throws -> TimelineEventContent { try result.get() }
    func eventId() -> String { "$event" }
    func senderId() -> String { sender }
    func threadRootEventId() -> String? { thread }
    func timestamp() -> Timestamp { 0 }
}

private func text(_ body: String) -> TimelineEventContent {
    .messageLike(content: .roomMessage(messageType: .text(content: TextMessageContent(body: body, formatted: nil)), inReplyToEventId: nil))
}

private func roomInfo(name: String = "Lounge", isDirect: Bool = false) -> NotificationRoomInfo {
    NotificationRoomInfo(
        displayName: name,
        avatarUrl: nil,
        canonicalAlias: nil,
        topic: nil,
        joinRule: nil,
        joinedMembersCount: 3,
        activeServiceMembersCount: 0,
        serviceMembers: [],
        isEncrypted: true,
        isDirect: isDirect,
        isSpace: false,
        isDm: isDirect
    )
}

private func map(
    _ source: NotificationEventSource,
    senderName: String? = "Bob",
    isNoisy: Bool? = true,
    hasMention: Bool? = false,
    threadID: String? = nil
) throws -> MatrixNotification {
    try NotificationMapper.notification(
        source: source,
        senderInfo: NotificationSenderInfo(displayName: senderName, avatarUrl: nil, isNameAmbiguous: false),
        roomInfo: roomInfo(),
        isNoisy: isNoisy,
        hasMention: hasMention,
        threadID: threadID,
        roomID: room,
        eventID: event
    )
}

// MARK: Statuts

@Test func statusesWithoutAnEventMapToTheirResult() throws {
    #expect(try NotificationMapper.result(from: .eventNotFound, roomID: room, eventID: event) == .notFound)
    #expect(try NotificationMapper.result(from: .eventFilteredOut, roomID: room, eventID: event) == .filteredOut)
    #expect(try NotificationMapper.result(from: .eventRedacted, roomID: room, eventID: event) == .redacted)
}

// MARK: Notification

@Test func aTextMessageCarriesItsSenderRoomAndBody() throws {
    let notification = try map(.timeline(FakeTimelineEvent(text("Salut"))))

    #expect(notification.roomID == room)
    #expect(notification.eventID == event)
    #expect(notification.sender == UserID(rawValue: "@bob:matrix.org"))
    #expect(notification.senderDisplayName == "Bob")
    #expect(notification.roomDisplayName == "Lounge")
    #expect(notification.isDirect == false)
    #expect(notification.kind == .message(body: "Salut"))
    #expect(notification.isNoisy)
    #expect(!notification.hasMention)
    #expect(notification.threadID == nil)
}

@Test func anInvitationNamesItsSender() throws {
    let notification = try map(.invite(sender: "@carol:matrix.org"))

    #expect(notification.kind == .invite)
    #expect(notification.sender == UserID(rawValue: "@carol:matrix.org"))
}

@Test func unknownNoiseAndMentionAreFalse() throws {
    let notification = try map(.timeline(FakeTimelineEvent(text("x"))), isNoisy: nil, hasMention: nil)

    #expect(!notification.isNoisy)
    #expect(!notification.hasMention)
}

@Test func theThreadComesFromTheItemThenFromTheEvent() throws {
    let fromItem = try map(.timeline(FakeTimelineEvent(text("x"), thread: "$other")), threadID: "$root")
    let fromEvent = try map(.timeline(FakeTimelineEvent(text("x"), thread: "$root")))

    #expect(fromItem.threadID == EventID(rawValue: "$root"))
    #expect(fromEvent.threadID == EventID(rawValue: "$root"))
}

@Test func anInvalidSenderIsAnUnexpectedErrorRatherThanACrash() {
    #expect(throws: MatrixError.self) {
        try map(.timeline(FakeTimelineEvent(text("x"), sender: "bob")))
    }
}

@Test func anEmoteUsesTheSenderIDWhenTheNameIsUnknown() throws {
    let emote = TimelineEventContent.messageLike(
        content: .roomMessage(messageType: .emote(content: EmoteMessageContent(body: "waves", formatted: nil)), inReplyToEventId: nil)
    )

    let notification = try map(.timeline(FakeTimelineEvent(emote)), senderName: nil)

    #expect(notification.kind == .message(body: "* @bob:matrix.org waves"))
}

@Test func unreadableContentFallsBackToAGenericBody() throws {
    let notification = try map(.timeline(FakeTimelineEvent(failing: "@bob:matrix.org")))

    #expect(notification.kind == .message(body: "Sent a message"))
}

// MARK: Corps

@Test func bodiesFollowTheSpecTable() {
    let notice = MessageType.notice(content: NoticeMessageContent(body: "Maintenance", formatted: nil))
    let location = MessageType.location(
        content: LocationContent(body: "Here", geoUri: "geo:0,0", description: nil, zoomLevel: nil, asset: .sender)
    )

    #expect(NotificationMapper.body(for: notice, senderName: "Bob") == "Maintenance")
    #expect(NotificationMapper.body(for: location, senderName: "Bob") == "Shared a location")
    #expect(NotificationMapper.body(for: .other(msgtype: "org.example", body: "Fallback"), senderName: "Bob") == "Fallback")
    #expect(NotificationMapper.body(for: .other(msgtype: "org.example", body: ""), senderName: "Bob") == "Sent a message")
}

@Test func anUndecryptableMessageUsesTheTimelinePhrase() {
    let body = NotificationMapper.body(for: .messageLike(content: .roomEncrypted), senderName: "Bob")

    #expect(body == TimelineMapper.undecryptableMessage)
    #expect(body == "The message could not be decrypted.")
}

@Test func otherEventsGetAGenericBody() {
    #expect(NotificationMapper.body(for: .messageLike(content: .sticker), senderName: "Bob") == "Sent a message")
}

@Test func aMediaBodyPrefersTheCaptionAndNeverTheFileName() {
    #expect(NotificationMapper.mediaBody(caption: "Sunset", fallback: "Sent an image") == "Sunset")
    #expect(NotificationMapper.mediaBody(caption: nil, fallback: "Sent an image") == "Sent an image")
    #expect(NotificationMapper.mediaBody(caption: "", fallback: "Sent an image") == "Sent an image")
}

// MARK: Paramètres et erreurs

@Test func modesMapBothWays() {
    let pairs: [(MatrixRustSDK.RoomNotificationMode, MatrixClientKitCore.RoomNotificationMode)] = [
        (.allMessages, .allMessages), (.mentionsAndKeywordsOnly, .mentionsAndKeywordsOnly), (.mute, .mute),
    ]
    for (upstream, domain) in pairs {
        #expect(NotificationMapper.mode(from: upstream) == domain)
        #expect(NotificationMapper.upstreamMode(from: domain) == upstream)
    }
}

@Test func settingsCarryTheDefaultFlag() {
    let settings = NotificationMapper.settings(from: MatrixRustSDK.RoomNotificationSettings(mode: .mute, isDefault: false))

    #expect(settings == MatrixClientKitCore.RoomNotificationSettings(mode: .mute, isDefault: false))
}

@Test func anInvalidRoomIsARoomNotFound() {
    #expect(NotificationMapper.error(from: NotificationSettingsError.InvalidRoomId(roomId: "!x")) == .notFound(.room))
}

@Test func otherSettingsErrorsGoThroughTheErrorMapper() {
    let mapped = NotificationMapper.error(from: ClientError.Generic(msg: "boom", details: nil))

    #expect(mapped == .unexpected(message: "boom", details: nil))
}
```

- [ ] **Step 2 : vérifier l'échec**

Run : `swift build --build-tests`
Expected : échec, `cannot find 'NotificationMapper' in scope`. Si `NotificationSenderInfo`,
`NotificationRoomInfo` ou `LocationContent` refusent l'appel à cause de l'ordre des étiquettes,
recopier l'ordre exact depuis leur `public init` dans
`.build/checkouts/matrix-rust-components-swift/Sources/MatrixRustSDK/matrix_sdk_ffi.swift`
(`grep -n "public struct NotificationRoomInfo" -A 20`).

- [ ] **Step 3 : extraire la phrase UTD de la timeline**

Dans `Sources/MatrixClientKitRust/Bridge/TimelineMapper.swift`, ajouter en tête de l'enum :

```swift
    /// Phrase générique d'un message indéchiffrable, partagée avec les notifications : la même
    /// situation doit se lire de la même façon dans la timeline et sur l'écran verrouillé.
    static let undecryptableMessage = "The message could not be decrypted."
```

et remplacer les deux `return "The message could not be decrypted."` de
`decryptionFailureReason(for:)` par `return undecryptableMessage`.

- [ ] **Step 4 : écrire le mappage**

`Sources/MatrixClientKitRust/Bridge/NotificationMapper.swift` :

```swift
import MatrixRustSDK
import MatrixClientKitCore

/// L'événement porté par une notification amont, sous une forme qu'un test peut construire :
/// `NotificationEvent.timeline` contient un `TimelineEvent`, classe FFI, alors que son protocole
/// est implémentable.
enum NotificationEventSource {
    case timeline(any TimelineEventProtocol)
    case invite(sender: String)
}

/// Traduit les notifications et les paramètres de notification amont vers le domaine.
enum NotificationMapper {
    static let genericBody = "Sent a message"

    static func result(from status: NotificationStatus, roomID: RoomID, eventID: EventID) throws -> NotificationResult {
        switch status {
        case let .event(item):
            return .notification(try notification(from: item, roomID: roomID, eventID: eventID))
        case .eventNotFound:
            return .notFound
        case .eventFilteredOut:
            return .filteredOut
        case .eventRedacted:
            return .redacted
        }
    }

    static func notification(from item: NotificationItem, roomID: RoomID, eventID: EventID) throws -> MatrixNotification {
        let source: NotificationEventSource
        switch item.event {
        case let .timeline(event):
            source = .timeline(event)
        case let .invite(sender):
            source = .invite(sender: sender)
        }
        return try notification(
            source: source,
            senderInfo: item.senderInfo,
            roomInfo: item.roomInfo,
            isNoisy: item.isNoisy,
            hasMention: item.hasMention,
            threadID: item.threadId,
            roomID: roomID,
            eventID: eventID
        )
    }

    static func notification(
        source: NotificationEventSource,
        senderInfo: NotificationSenderInfo,
        roomInfo: NotificationRoomInfo,
        isNoisy: Bool?,
        hasMention: Bool?,
        threadID: String?,
        roomID: RoomID,
        eventID: EventID
    ) throws -> MatrixNotification {
        let rawSender: String
        let kind: MatrixNotification.Kind
        var rawThread = threadID

        switch source {
        case let .timeline(event):
            rawSender = event.senderId()
            rawThread = rawThread ?? event.threadRootEventId()
            let senderName = senderInfo.displayName ?? rawSender
            // Un contenu illisible ne doit pas priver l'utilisateur de la notification elle-même.
            let content = try? event.content()
            kind = .message(body: content.map { body(for: $0, senderName: senderName) } ?? genericBody)
        case let .invite(sender):
            rawSender = sender
            kind = .invite
        }

        guard let sender = UserID(rawValue: rawSender) else {
            throw MatrixError.unexpected(message: "Invalid sender in a notification: \(rawSender)", details: nil)
        }
        var thread: EventID?
        if let rawThread {
            guard let parsed = EventID(rawValue: rawThread) else {
                throw MatrixError.unexpected(message: "Invalid thread in a notification: \(rawThread)", details: nil)
            }
            thread = parsed
        }

        return MatrixNotification(
            roomID: roomID,
            eventID: eventID,
            sender: sender,
            senderDisplayName: senderInfo.displayName,
            roomDisplayName: roomInfo.displayName,
            isDirect: roomInfo.isDirect,
            kind: kind,
            isNoisy: isNoisy ?? false,
            hasMention: hasMention ?? false,
            threadID: thread
        )
    }

    static func body(for content: TimelineEventContent, senderName: String) -> String {
        guard case let .messageLike(messageLike) = content else { return genericBody }

        switch messageLike {
        case let .roomMessage(messageType, _):
            return body(for: messageType, senderName: senderName)
        case .roomEncrypted:
            return TimelineMapper.undecryptableMessage
        default:
            return genericBody
        }
    }

    /// Corps d'un message selon son type (spec 0.3, §6.1).
    static func body(for messageType: MessageType, senderName: String) -> String {
        switch messageType {
        case let .text(content):
            return content.body
        case let .notice(content):
            return content.body
        case let .emote(content):
            return "* \(senderName) \(content.body)"
        case let .image(content):
            return mediaBody(caption: content.caption, fallback: "Sent an image")
        case let .video(content):
            return mediaBody(caption: content.caption, fallback: "Sent a video")
        case let .audio(content):
            return mediaBody(caption: content.caption, fallback: "Sent an audio message")
        case let .file(content):
            return mediaBody(caption: content.caption, fallback: "Sent a file")
        case .gallery:
            return "Sent images"
        case .location:
            return "Shared a location"
        case let .other(_, body):
            // La spec Matrix impose un corps de repli à tout msgtype : c'est lui qu'il faut montrer.
            return body.isEmpty ? genericBody : body
        }
    }

    /// Légende si elle existe, sinon la phrase fixe. Le nom de fichier (souvent `IMG_1234.jpg`)
    /// n'est jamais montré.
    static func mediaBody(caption: String?, fallback: String) -> String {
        guard let caption, !caption.isEmpty else { return fallback }
        return caption
    }

    static func mode(from mode: MatrixRustSDK.RoomNotificationMode) -> MatrixClientKitCore.RoomNotificationMode {
        switch mode {
        case .allMessages: .allMessages
        case .mentionsAndKeywordsOnly: .mentionsAndKeywordsOnly
        case .mute: .mute
        }
    }

    static func upstreamMode(from mode: MatrixClientKitCore.RoomNotificationMode) -> MatrixRustSDK.RoomNotificationMode {
        switch mode {
        case .allMessages: .allMessages
        case .mentionsAndKeywordsOnly: .mentionsAndKeywordsOnly
        case .mute: .mute
        }
    }

    static func settings(
        from settings: MatrixRustSDK.RoomNotificationSettings
    ) -> MatrixClientKitCore.RoomNotificationSettings {
        MatrixClientKitCore.RoomNotificationSettings(mode: mode(from: settings.mode), isDefault: settings.isDefault)
    }

    static func error(from error: any Error) -> MatrixError {
        if let settingsError = error as? NotificationSettingsError, case .InvalidRoomId = settingsError {
            return .notFound(.room)
        }
        return ErrorMapper.map(error)
    }
}
```

Si le compilateur signale un cas de `MessageType` non couvert (liste différente de celle relevée
en §2 de la spec), l'ajouter au `switch` avec `genericBody` et le consigner dans le rapport de
tâche ; ne jamais ajouter de `default:` à ce `switch` — un nouveau cas amont doit casser la
compilation.

- [ ] **Step 5 : vérifier que les tests passent**

Run : `swift test --filter NotificationMapperTests` puis `swift test --filter TimelineStringsTests`
Expected : PASS pour les deux.

- [ ] **Step 6 : vérifications globales et commit**

```bash
swift build --build-tests && swift test --skip MatrixClientKitIntegrationTests \
  && swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKitRust/Bridge Tests/MatrixClientKitRustTests/NotificationMapperTests.swift
git commit -m "feat: mappage des notifications, des modes de salon et de leurs erreurs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6 : Service de notification adossé au SDK

**Files:**
- Create: `Sources/MatrixClientKitRust/Bridge/NotificationDriving.swift`
- Create: `Sources/MatrixClientKitRust/RustNotificationService.swift`
- Test: `Tests/MatrixClientKitRustTests/NotificationServiceTests.swift`

**Interfaces:**
- Consumes : `NotificationService`, `PusherConfiguration.pushKey`, `PusherConfiguration.defaultPayload()`
  (Tasks 2-3), `NotificationMapper` (Task 5), `ErrorMapper` (existant).
- Produces:
  - `protocol PusherDriving: Sendable` — `setPusher(identifiers:kind:appDisplayName:deviceDisplayName:profileTag:lang:append:) async throws`, `deletePusher(identifiers:) async throws` ; `extension Client: PusherDriving`
  - `protocol NotificationSettingsDriving: Sendable` — `getRoomNotificationSettings(roomId:isEncrypted:isOneToOne:) async throws -> MatrixRustSDK.RoomNotificationSettings`, `setRoomNotificationMode(roomId:mode:) async throws`, `restoreDefaultRoomNotificationMode(roomId:) async throws` ; `extension NotificationSettings: NotificationSettingsDriving`
  - `protocol NotificationClientDriving: Sendable` — `getNotification(roomId:eventId:) async throws -> NotificationStatus` ; `extension NotificationClient: NotificationClientDriving` (utilisé Task 8)
  - `struct RoomFacts: Sendable, Equatable { isEncrypted: Bool; isOneToOne: Bool }`
  - `public final class RustNotificationService: NotificationService` — `init(pushers: any PusherDriving, settings: any NotificationSettingsDriving, roomFacts: @escaping @Sendable (String) async throws -> RoomFacts?)`

- [ ] **Step 1 : écrire les tests en échec**

`Tests/MatrixClientKitRustTests/NotificationServiceTests.swift` :

```swift
import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private let room = RoomID(rawValue: "!room:matrix.org")!

private func configuration() -> PusherConfiguration {
    PusherConfiguration(
        deviceToken: Data([0xAB, 0x01]),
        appID: "com.example.app.ios.prod",
        gatewayURL: URL(string: "https://push.example.com/_matrix/push/v1/notify")!,
        appDisplayName: "Example",
        deviceDisplayName: "iPhone",
        language: "fr",
        fallbackAlert: "Nouveau message"
    )
}

private struct SetPusherCall: Equatable {
    let identifiers: PusherIdentifiers
    let kind: PusherKind
    let appDisplayName: String
    let deviceDisplayName: String
    let profileTag: String?
    let lang: String
    let append: Bool
}

private final class FakePushers: PusherDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var _setCalls: [SetPusherCall] = []
    private var _deleted: [PusherIdentifiers] = []
    var error: (any Error)?

    var setCalls: [SetPusherCall] { lock.withLock { _setCalls } }
    var deleted: [PusherIdentifiers] { lock.withLock { _deleted } }

    func setPusher(
        identifiers: PusherIdentifiers,
        kind: PusherKind,
        appDisplayName: String,
        deviceDisplayName: String,
        profileTag: String?,
        lang: String,
        append: Bool
    ) async throws {
        try lock.withLock {
            if let error { throw error }
            _setCalls.append(
                SetPusherCall(
                    identifiers: identifiers, kind: kind, appDisplayName: appDisplayName,
                    deviceDisplayName: deviceDisplayName, profileTag: profileTag, lang: lang, append: append
                )
            )
        }
    }

    func deletePusher(identifiers: PusherIdentifiers) async throws {
        try lock.withLock {
            if let error { throw error }
            _deleted.append(identifiers)
        }
    }
}

private final class FakeSettings: NotificationSettingsDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var _queries: [(String, Bool, Bool)] = []
    private var _modes: [(String, MatrixRustSDK.RoomNotificationMode)] = []
    private var _restored: [String] = []
    var current = MatrixRustSDK.RoomNotificationSettings(mode: .allMessages, isDefault: true)
    var error: (any Error)?

    var queries: [(String, Bool, Bool)] { lock.withLock { _queries } }
    var modes: [(String, MatrixRustSDK.RoomNotificationMode)] { lock.withLock { _modes } }
    var restored: [String] { lock.withLock { _restored } }

    func getRoomNotificationSettings(
        roomId: String,
        isEncrypted: Bool,
        isOneToOne: Bool
    ) async throws -> MatrixRustSDK.RoomNotificationSettings {
        try lock.withLock {
            if let error { throw error }
            _queries.append((roomId, isEncrypted, isOneToOne))
            return current
        }
    }

    func setRoomNotificationMode(roomId: String, mode: MatrixRustSDK.RoomNotificationMode) async throws {
        try lock.withLock {
            if let error { throw error }
            _modes.append((roomId, mode))
        }
    }

    func restoreDefaultRoomNotificationMode(roomId: String) async throws {
        try lock.withLock {
            if let error { throw error }
            _restored.append(roomId)
        }
    }
}

private func makeService(
    pushers: FakePushers = FakePushers(),
    settings: FakeSettings = FakeSettings(),
    facts: RoomFacts? = RoomFacts(isEncrypted: true, isOneToOne: false)
) -> RustNotificationService {
    RustNotificationService(pushers: pushers, settings: settings, roomFacts: { _ in facts })
}

// MARK: Pusher

@Test func registeringSendsAnHTTPPusherInTheEventIDOnlyFormat() async throws {
    let pushers = FakePushers()
    let service = makeService(pushers: pushers)

    try await service.registerPusher(configuration())

    let expectedPayload = #"{"aps":{"alert":{"body":"Nouveau message"},"mutable-content":1}}"#
    #expect(
        pushers.setCalls == [
            SetPusherCall(
                identifiers: PusherIdentifiers(pushkey: "ab01", appId: "com.example.app.ios.prod"),
                kind: .http(
                    data: HttpPusherData(
                        url: "https://push.example.com/_matrix/push/v1/notify",
                        format: .eventIdOnly,
                        defaultPayload: expectedPayload
                    )
                ),
                appDisplayName: "Example",
                deviceDisplayName: "iPhone",
                profileTag: nil,
                lang: "fr",
                append: false
            )
        ]
    )
}

@Test func unregisteringDeletesThePusherForTheSameIdentifiers() async throws {
    let pushers = FakePushers()
    let service = makeService(pushers: pushers)

    try await service.unregisterPusher(configuration())

    #expect(pushers.deleted == [PusherIdentifiers(pushkey: "ab01", appId: "com.example.app.ios.prod")])
}

@Test func aPusherFailureIsMapped() async {
    let pushers = FakePushers()
    pushers.error = ClientError.Generic(msg: "refusé", details: nil)
    let service = makeService(pushers: pushers)

    await #expect(throws: MatrixError.unexpected(message: "refusé", details: nil)) {
        try await service.registerPusher(configuration())
    }
}

// MARK: Paramètres

@Test func readingSettingsPassesTheRoomFactsUpstream() async throws {
    let settings = FakeSettings()
    settings.current = MatrixRustSDK.RoomNotificationSettings(mode: .mentionsAndKeywordsOnly, isDefault: false)
    let service = makeService(settings: settings, facts: RoomFacts(isEncrypted: true, isOneToOne: true))

    let result = try await service.notificationSettings(for: room)

    #expect(result == MatrixClientKitCore.RoomNotificationSettings(mode: .mentionsAndKeywordsOnly, isDefault: false))
    #expect(settings.queries.count == 1)
    #expect(settings.queries.first?.0 == "!room:matrix.org")
    #expect(settings.queries.first?.1 == true)
    #expect(settings.queries.first?.2 == true)
}

@Test func anUnknownRoomIsARoomNotFound() async {
    let service = makeService(facts: nil)

    await #expect(throws: MatrixError.notFound(.room)) {
        try await service.notificationSettings(for: room)
    }
}

@Test func settingAModeSendsItUpstream() async throws {
    let settings = FakeSettings()
    let service = makeService(settings: settings)

    try await service.setNotificationMode(.mute, for: room)

    #expect(settings.modes.count == 1)
    #expect(settings.modes.first?.0 == "!room:matrix.org")
    #expect(settings.modes.first?.1 == .mute)
}

@Test func restoringTheDefaultSendsItUpstream() async throws {
    let settings = FakeSettings()
    let service = makeService(settings: settings)

    try await service.restoreDefaultNotificationMode(for: room)

    #expect(settings.restored == ["!room:matrix.org"])
}

@Test func anInvalidRoomFromTheSettingsIsARoomNotFound() async {
    let settings = FakeSettings()
    settings.error = NotificationSettingsError.InvalidRoomId(roomId: "!room:matrix.org")
    let service = makeService(settings: settings)

    await #expect(throws: MatrixError.notFound(.room)) {
        try await service.setNotificationMode(.mute, for: room)
    }
}
```

- [ ] **Step 2 : vérifier l'échec**

Run : `swift build --build-tests`
Expected : échec, `cannot find type 'PusherDriving' in scope`.

- [ ] **Step 3 : écrire les coutures**

`Sources/MatrixClientKitRust/Bridge/NotificationDriving.swift` :

```swift
import MatrixRustSDK

/// Sous-ensemble de `Client` dont le service de notification a besoin pour le pusher.
///
/// Couture de testabilité : `Client` est une classe FFI qu'un test ne peut pas construire.
protocol PusherDriving: Sendable {
    func setPusher(
        identifiers: PusherIdentifiers,
        kind: PusherKind,
        appDisplayName: String,
        deviceDisplayName: String,
        profileTag: String?,
        lang: String,
        append: Bool
    ) async throws
    func deletePusher(identifiers: PusherIdentifiers) async throws
}

extension Client: PusherDriving {}

/// Sous-ensemble de `NotificationSettings` utilisé en 0.3 : le mode par salon. Le protocole amont
/// impose une vingtaine de méthodes hors périmètre.
protocol NotificationSettingsDriving: Sendable {
    func getRoomNotificationSettings(
        roomId: String,
        isEncrypted: Bool,
        isOneToOne: Bool
    ) async throws -> MatrixRustSDK.RoomNotificationSettings
    func setRoomNotificationMode(roomId: String, mode: MatrixRustSDK.RoomNotificationMode) async throws
    func restoreDefaultRoomNotificationMode(roomId: String) async throws
}

extension NotificationSettings: NotificationSettingsDriving {}

/// Sous-ensemble de `NotificationClient` utilisé par l'extension.
protocol NotificationClientDriving: Sendable {
    func getNotification(roomId: String, eventId: String) async throws -> NotificationStatus
}

extension NotificationClient: NotificationClientDriving {}

/// Ce que l'amont exige de savoir d'un salon pour en lire le réglage de notification.
struct RoomFacts: Sendable, Equatable {
    let isEncrypted: Bool
    let isOneToOne: Bool
}
```

- [ ] **Step 4 : écrire le service**

`Sources/MatrixClientKitRust/RustNotificationService.swift` :

```swift
import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``NotificationService`` adossée au SDK Rust.
public final class RustNotificationService: NotificationService {
    private let pushers: any PusherDriving
    private let settings: any NotificationSettingsDriving
    /// Résout les faits d'un salon à partir de son identifiant ; `nil` pour un salon inconnu.
    private let roomFacts: @Sendable (String) async throws -> RoomFacts?

    init(
        pushers: any PusherDriving,
        settings: any NotificationSettingsDriving,
        roomFacts: @escaping @Sendable (String) async throws -> RoomFacts?
    ) {
        self.pushers = pushers
        self.settings = settings
        self.roomFacts = roomFacts
    }

    public func registerPusher(_ configuration: PusherConfiguration) async throws {
        do {
            try await pushers.setPusher(
                identifiers: Self.identifiers(for: configuration),
                kind: .http(
                    data: HttpPusherData(
                        url: configuration.gatewayURL.absoluteString,
                        // Seul format amont, et le seul qui ne fait pas transiter le contenu par Apple.
                        format: .eventIdOnly,
                        defaultPayload: try configuration.defaultPayload()
                    )
                ),
                appDisplayName: configuration.appDisplayName,
                deviceDisplayName: configuration.deviceDisplayName,
                profileTag: nil,
                lang: configuration.language,
                // `false` : le homeserver retire les pushers d'autres comptes au même jeton, ce
                // qu'on veut après un changement de compte sur l'appareil.
                append: false
            )
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    public func unregisterPusher(_ configuration: PusherConfiguration) async throws {
        do {
            try await pushers.deletePusher(identifiers: Self.identifiers(for: configuration))
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    public func notificationSettings(for roomID: RoomID) async throws -> MatrixClientKitCore.RoomNotificationSettings {
        do {
            guard let facts = try await roomFacts(roomID.rawValue) else {
                throw MatrixError.notFound(.room)
            }
            let upstream = try await settings.getRoomNotificationSettings(
                roomId: roomID.rawValue,
                isEncrypted: facts.isEncrypted,
                isOneToOne: facts.isOneToOne
            )
            return NotificationMapper.settings(from: upstream)
        } catch {
            throw NotificationMapper.error(from: error)
        }
    }

    public func setNotificationMode(
        _ mode: MatrixClientKitCore.RoomNotificationMode,
        for roomID: RoomID
    ) async throws {
        do {
            try await settings.setRoomNotificationMode(
                roomId: roomID.rawValue,
                mode: NotificationMapper.upstreamMode(from: mode)
            )
        } catch {
            throw NotificationMapper.error(from: error)
        }
    }

    public func restoreDefaultNotificationMode(for roomID: RoomID) async throws {
        do {
            try await settings.restoreDefaultRoomNotificationMode(roomId: roomID.rawValue)
        } catch {
            throw NotificationMapper.error(from: error)
        }
    }

    private static func identifiers(for configuration: PusherConfiguration) -> PusherIdentifiers {
        PusherIdentifiers(pushkey: configuration.pushKey, appId: configuration.appID)
    }
}
```

- [ ] **Step 5 : vérifier que les tests passent**

Run : `swift test --filter NotificationServiceTests`
Expected : PASS.

- [ ] **Step 6 : vérifications globales et commit**

```bash
swift build --build-tests && swift test --skip MatrixClientKitIntegrationTests \
  && swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKitRust Tests/MatrixClientKitRustTests/NotificationServiceTests.swift
git commit -m "feat: service de notification adossé au SDK — pusher et mode par salon

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7 : Branchement de la session (changement cassant)

**Files:**
- Modify: `Sources/MatrixClientKitCore/Services/MatrixSession.swift`
- Modify: `Sources/MatrixClientKitRust/RustMatrixSession.swift`
- Modify: `Sources/MatrixClientKitMocks/MockMatrixSession.swift`
- Test: `Tests/MatrixClientKitCoreTests/NotificationMockTests.swift` (ajout)

**Interfaces:**
- Consumes : `NotificationService`, `MockNotificationService` (Task 3), `RustNotificationService`,
  `RoomFacts` (Task 6), constat 4 de la Task 1 (`isOneToOne`).
- Produces : `MatrixSession.notifications: any NotificationService` ;
  `MockMatrixSession.init(…, notifications: MockNotificationService = MockNotificationService())`.

- [ ] **Step 1 : écrire le test en échec**

Ajouter à `Tests/MatrixClientKitCoreTests/NotificationMockTests.swift` :

```swift
@Test func mockSessionExposesTheNotificationServiceItWasGiven() async throws {
    let notifications = MockNotificationService()
    let session: any MatrixSession = MockMatrixSession(notifications: notifications)

    try await session.notifications.registerPusher(SampleData.pusherConfiguration())

    #expect(notifications.registeredPushers.count == 1)
}
```

- [ ] **Step 2 : vérifier l'échec**

Run : `swift build --build-tests`
Expected : échec, `value of type 'any MatrixSession' has no member 'notifications'`.

- [ ] **Step 3 : ajouter le membre au protocole**

Dans `Sources/MatrixClientKitCore/Services/MatrixSession.swift`, après `encryption` :

```swift
    /// Push notifications: this device's pusher, and how much each room notifies.
    var notifications: any NotificationService { get }
```

- [ ] **Step 4 : brancher le mock**

Dans `Sources/MatrixClientKitMocks/MockMatrixSession.swift` :
- ajouter `public let notifications: any NotificationService` après `encryption` ;
- ajouter le paramètre `notifications: MockNotificationService = MockNotificationService()` à la
  fin de `init`, et `self.notifications = notifications` après `self.encryption = encryption` ;
- compléter la doc du type : « exposes a ready-made ``MockRoomService``, ``MockSyncController``,
  ``MockEncryptionService`` and ``MockNotificationService`` ».

- [ ] **Step 5 : brancher la session Rust**

Dans `Sources/MatrixClientKitRust/RustMatrixSession.swift` :
- ajouter `public let notifications: any NotificationService` après `encryption` ;
- ajouter le paramètre `notifications: any NotificationService` à l'`init` privé (après
  `encryption`) et l'affectation correspondante ;
- dans `make(client:restorer:localStore:)`, avant `let lifecycle = …` :

```swift
            let notifications = RustNotificationService(
                pushers: client,
                settings: await client.getNotificationSettings(),
                roomFacts: { roomID in
                    guard let room = try client.getRoom(roomId: roomID) else { return nil }
                    // Même définition qu'Element X (Task 1, constat 4) : l'amont en déduit le
                    // réglage par défaut d'un salon.
                    return RoomFacts(isEncrypted: await room.isEncrypted(), isOneToOne: room.activeMembersCount() == 2)
                }
            )
```

  et passer `notifications: notifications` à l'appel de `RustMatrixSession(…)`.

Si le constat 4 de la Task 1 diffère de `activeMembersCount() == 2`, appliquer l'expression
relevée à la place, en gardant le commentaire.

- [ ] **Step 6 : vérifier que les tests passent**

Run : `swift build --build-tests && swift test --skip MatrixClientKitIntegrationTests`
Expected : PASS. La suite d'intégration doit aussi compiler (`swift build --build-tests` la
compile) : aucune de ses doublures n'implémente `MatrixSession`.

- [ ] **Step 7 : vérifications globales et commit**

```bash
swift format lint --recursive --strict Sources Tests
git add Sources Tests/MatrixClientKitCoreTests/NotificationMockTests.swift
git commit -m "feat!: la session expose le service de notification

MatrixSession gagne le membre notifications : une application qui implémente le protocole
elle-même doit l'ajouter, ou utiliser MockMatrixSession.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8 : Résolveur de l'extension

**Files:**
- Create: `Sources/MatrixClientKitRust/RustNotificationResolver.swift`
- Modify: `Sources/MatrixClientKitRust/SessionRestorer.swift` (ajout de `makeNotificationResolver()`)
- Test: `Tests/MatrixClientKitRustTests/NotificationResolverTests.swift`

**Interfaces:**
- Consumes : `NotificationClientDriving` (Task 6), `NotificationMapper.result(from:roomID:eventID:)`
  (Task 5), `SessionRestorer.role`, `lockConfiguration()`, `makeClient`, `persistence`,
  `makeLocalStore(for:)` (Task 4 et existant), `SessionMapper.session(from:)`, `ErrorMapper`.
- Produces:
  - `public final class RustNotificationResolver: NotificationContentResolving` — `init(notificationClient: any NotificationClientDriving, client: Client? = nil, restorer: SessionRestorer? = nil)`, `public static func open(storage: MatrixStorage) async throws -> RustNotificationResolver`
  - `SessionRestorer.makeNotificationResolver() async throws -> RustNotificationResolver`

- [ ] **Step 1 : écrire les tests en échec**

`Tests/MatrixClientKitRustTests/NotificationResolverTests.swift` :

```swift
import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private let room = RoomID(rawValue: "!room:matrix.org")!
private let event = EventID(rawValue: "$event")!

private final class FakeNotificationClient: NotificationClientDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [(String, String)] = []
    var status: NotificationStatus = .eventNotFound
    var error: (any Error)?

    var requests: [(String, String)] { lock.withLock { _requests } }

    func getNotification(roomId: String, eventId: String) async throws -> NotificationStatus {
        try lock.withLock {
            _requests.append((roomId, eventId))
            if let error { throw error }
            return status
        }
    }
}

private func persistedSession() -> MatrixSessionData {
    MatrixSessionData(
        userID: UserID(rawValue: "@alice:matrix.org")!,
        deviceID: DeviceID(rawValue: "DEV1")!,
        homeserverURL: URL(string: "https://matrix.example")!,
        accessToken: "jeton",
        refreshToken: nil,
        oauthData: nil,
        slidingSyncVersion: "native"
    )
}

@Test func theResolverAsksForTheEventAndMapsTheStatus() async throws {
    let client = FakeNotificationClient()
    client.status = .eventFilteredOut
    let resolver = RustNotificationResolver(notificationClient: client)

    let result = try await resolver.notification(roomID: room, eventID: event)

    #expect(result == .filteredOut)
    #expect(client.requests.count == 1)
    #expect(client.requests.first?.0 == "!room:matrix.org")
    #expect(client.requests.first?.1 == "$event")
}

@Test func anUpstreamFailureIsMapped() async {
    let client = FakeNotificationClient()
    client.error = ClientError.Generic(msg: "introuvable", details: nil)
    let resolver = RustNotificationResolver(notificationClient: client)

    await #expect(throws: MatrixError.unexpected(message: "introuvable", details: nil)) {
        try await resolver.notification(roomID: room, eventID: event)
    }
}

@Test func openingWithoutAStoredSessionReportsAMissingToken() async {
    let restorer = SessionRestorer(
        storage: .appGroup("group.com.example.app"),
        secureStore: InMemorySecureStore(),
        role: .notificationExtension
    )

    await #expect(throws: MatrixError.authentication(.missingToken)) {
        _ = try await restorer.makeNotificationResolver()
    }
}

@Test func anExtensionRefusesALocalStorageBeforeReadingTheSession() async throws {
    let restorer = SessionRestorer(
        storage: .local(directory: FileManager.default.temporaryDirectory),
        secureStore: InMemorySecureStore(),
        role: .notificationExtension
    )
    try restorer.persistence.save(persistedSession())

    await #expect(throws: MatrixError.storage(.unavailable)) {
        _ = try await restorer.makeNotificationResolver()
    }
}
```

- [ ] **Step 2 : vérifier l'échec**

Run : `swift build --build-tests`
Expected : échec, `cannot find 'RustNotificationResolver' in scope`.

- [ ] **Step 3 : écrire le résolveur**

`Sources/MatrixClientKitRust/RustNotificationResolver.swift` :

```swift
import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``NotificationContentResolving`` adossée au SDK Rust, pour l'extension.
///
/// N'expose aucune sync, par construction : en synchroniser une depuis l'extension corromprait
/// l'état de l'application, qui partage le store (spec de référence, §8).
public final class RustNotificationResolver: NotificationContentResolving {
    private let notificationClient: any NotificationClientDriving
    /// Retenus pour la durée du résolveur : le client porte le store, le restorer le
    /// `SessionDelegate` dont le SDK se sert pour rafraîchir le jeton.
    private let client: Client?
    private let restorer: SessionRestorer?

    init(notificationClient: any NotificationClientDriving, client: Client? = nil, restorer: SessionRestorer? = nil) {
        self.notificationClient = notificationClient
        self.client = client
        self.restorer = restorer
    }

    /// Ouvre la session persistée dans `storage` avec le rôle d'extension.
    public static func open(storage: MatrixStorage) async throws -> RustNotificationResolver {
        try await SessionRestorer(storage: storage, role: .notificationExtension).makeNotificationResolver()
    }

    public func notification(roomID: RoomID, eventID: EventID) async throws -> NotificationResult {
        let status: NotificationStatus
        do {
            status = try await notificationClient.getNotification(roomId: roomID.rawValue, eventId: eventID.rawValue)
        } catch {
            throw ErrorMapper.map(error)
        }
        return try NotificationMapper.result(from: status, roomID: roomID, eventID: eventID)
    }
}
```

- [ ] **Step 4 : ouvrir la session côté extension**

Dans `Sources/MatrixClientKitRust/SessionRestorer.swift`, ajouter après `restore(makeClient:)` :

```swift
    /// Ouvre la session persistée pour résoudre des notifications, sans sync.
    ///
    /// Contrairement à ``restore()``, une authentification refusée n'efface rien : c'est à
    /// l'application, au prochain lancement, de constater la session morte et de nettoyer. Une
    /// extension qui purgerait le store pendant que l'application l'utilise le corromprait.
    func makeNotificationResolver() async throws -> RustNotificationResolver {
        // Échoue avant toute lecture pour un stockage qu'une extension ne peut pas atteindre.
        _ = try lockConfiguration()
        guard let data = try persistence.load() else {
            throw MatrixError.authentication(.missingToken)
        }

        let localStore = makeLocalStore(for: data.userID)
        let client = try await makeClient(homeserver: data.homeserverURL, localStore: localStore)
        do {
            try await client.restoreSession(session: SessionMapper.session(from: data))
            let notificationClient = try await client.notificationClient(processSetup: .multipleProcesses)
            return RustNotificationResolver(notificationClient: notificationClient, client: client, restorer: self)
        } catch {
            throw ErrorMapper.mapAuthentication(error)
        }
    }
```

- [ ] **Step 5 : vérifier que les tests passent**

Run : `swift test --filter NotificationResolverTests`
Expected : PASS.

- [ ] **Step 6 : vérifications globales et commit**

```bash
swift build --build-tests && swift test --skip MatrixClientKitIntegrationTests \
  && swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKitRust Tests/MatrixClientKitRustTests/NotificationResolverTests.swift
git commit -m "feat: résolveur de notification pour l'extension, sans sync

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9 : Point d'entrée de l'extension et aide `UserNotifications`

**Files:**
- Create: `Sources/MatrixClientKit/MatrixNotificationService.swift`
- Create: `Sources/MatrixClientKit/UNMutableNotificationContent+Matrix.swift`
- Test: `Tests/MatrixClientKitTests/NotificationContentTests.swift`

**Interfaces:**
- Consumes : `RustNotificationResolver.open(storage:)` (Task 8), `MatrixNotification` (Task 2),
  `SampleData` n'est **pas** disponible dans `MatrixClientKitTests` (pas de dépendance aux mocks) :
  les tests construisent `MatrixNotification` directement.
- Produces :
  - `public final class MatrixNotificationService: NotificationContentResolving` — `public init(storage: MatrixStorage) async throws`
  - `extension UNMutableNotificationContent { public func apply(_ notification: MatrixNotification) }`

- [ ] **Step 1 : écrire les tests en échec**

`Tests/MatrixClientKitTests/NotificationContentTests.swift` :

```swift
import Testing
import Foundation
import UserNotifications
import MatrixClientKit

private func notification(
    kind: MatrixNotification.Kind = .message(body: "Hello"),
    senderName: String? = "Alice",
    isDirect: Bool = false,
    isNoisy: Bool = true
) -> MatrixNotification {
    MatrixNotification(
        roomID: RoomID(rawValue: "!room:matrix.org")!,
        eventID: EventID(rawValue: "$event")!,
        sender: UserID(rawValue: "@alice:matrix.org")!,
        senderDisplayName: senderName,
        roomDisplayName: "Lounge",
        isDirect: isDirect,
        kind: kind,
        isNoisy: isNoisy,
        hasMention: false,
        threadID: nil
    )
}

@Test func aDirectMessageIsTitledWithTheSender() {
    let content = UNMutableNotificationContent()

    content.apply(notification(isDirect: true))

    #expect(content.title == "Alice")
    #expect(content.body == "Hello")
    #expect(content.threadIdentifier == "!room:matrix.org")
}

@Test func aGroupMessageIsTitledWithTheRoomAndPrefixedWithTheSender() {
    let content = UNMutableNotificationContent()

    content.apply(notification())

    #expect(content.title == "Lounge")
    #expect(content.body == "Alice: Hello")
}

@Test func anUnnamedSenderFallsBackToTheirIdentifier() {
    let content = UNMutableNotificationContent()

    content.apply(notification(senderName: nil, isDirect: true))

    #expect(content.title == "@alice:matrix.org")
}

@Test func anInvitationSaysSo() {
    let content = UNMutableNotificationContent()

    content.apply(notification(kind: .invite, isDirect: true))

    #expect(content.title == "Alice")
    #expect(content.body == "Invited you to chat")
}

@Test func onlyANoisyNotificationPlaysASound() {
    let noisy = UNMutableNotificationContent()
    let quiet = UNMutableNotificationContent()

    noisy.apply(notification(isNoisy: true))
    quiet.apply(notification(isNoisy: false))

    #expect(noisy.sound == .default)
    #expect(quiet.sound == nil)
}

@Test func theServiceRefusesALocalStorage() async {
    // Le refus a lieu avant toute lecture du Keychain : le cas ne dépend donc pas d'une session
    // qu'une autre exécution y aurait laissée.
    do {
        _ = try await MatrixNotificationService(storage: .local(directory: FileManager.default.temporaryDirectory))
        Issue.record("une extension ne doit pas pouvoir ouvrir un stockage local")
    } catch {
        #expect(error as? MatrixError == .storage(.unavailable))
    }
}
```

- [ ] **Step 2 : vérifier l'échec**

Run : `swift build --build-tests`
Expected : échec, `value of type 'UNMutableNotificationContent' has no member 'apply'`.

- [ ] **Step 3 : écrire le point d'entrée**

`Sources/MatrixClientKit/MatrixNotificationService.swift` :

```swift
import MatrixClientKitCore
import MatrixClientKitRust

/// Resolves pushes into displayable notifications, from a notification service extension.
///
/// ```swift
/// let service = try await MatrixNotificationService(storage: .appGroup("group.com.example.app"))
/// if let payload = MatrixPushPayload(userInfo: request.content.userInfo),
///    case .notification(let notification) = try await service.notification(
///        roomID: payload.roomID, eventID: payload.eventID) {
///     content.apply(notification)
/// }
/// ```
///
/// It opens the session the application persisted in the same App Group storage, and never
/// syncs. Keep the instance for the lifetime of the extension's process to reuse it across
/// pushes.
public final class MatrixNotificationService: NotificationContentResolving {
    private let resolver: RustNotificationResolver

    /// Opens the session persisted in `storage`.
    ///
    /// - Parameter storage: the application's storage. It must be an App Group storage: an
    ///   extension cannot reach the application's private directory.
    /// - Throws: ``MatrixError/authentication(_:)`` with
    ///   ``MatrixError/Authentication/missingToken`` when no session is stored — the user signed
    ///   out; ``MatrixError/storage(_:)`` with ``MatrixError/Storage/unavailable`` for a local
    ///   storage.
    public init(storage: MatrixStorage) async throws {
        resolver = try await RustNotificationResolver.open(storage: storage)
    }

    public func notification(roomID: RoomID, eventID: EventID) async throws -> NotificationResult {
        try await resolver.notification(roomID: roomID, eventID: eventID)
    }
}
```

- [ ] **Step 4 : écrire l'aide `UserNotifications`**

`Sources/MatrixClientKit/UNMutableNotificationContent+Matrix.swift` :

```swift
#if canImport(UserNotifications)
import UserNotifications
import MatrixClientKitCore

extension UNMutableNotificationContent {
    /// Fills the title, body, thread identifier and sound from a resolved notification.
    ///
    /// A direct conversation is titled with the sender; any other room with its name, the body
    /// then starting with the sender's name. Notifications are grouped by room, and play the
    /// default sound only when the user's push rules ask for one. Everything else — badge,
    /// attachments, user info — is left untouched.
    public func apply(_ notification: MatrixNotification) {
        let senderName = notification.senderDisplayName ?? notification.sender.rawValue

        switch notification.kind {
        case let .message(body):
            title = notification.isDirect ? senderName : notification.roomDisplayName
            self.body = notification.isDirect ? body : "\(senderName): \(body)"
        case .invite:
            title = notification.isDirect ? senderName : notification.roomDisplayName
            body = "Invited you to chat"
        }

        threadIdentifier = notification.roomID.rawValue
        sound = notification.isNoisy ? .default : nil
    }
}
#endif
```

- [ ] **Step 5 : vérifier que les tests passent**

Run : `swift test --filter NotificationContentTests`
Expected : PASS.

- [ ] **Step 6 : vérifier le build iOS**

Run :

```bash
xcodebuild build -quiet -scheme MatrixClientKit -destination 'generic/platform=iOS Simulator' \
  -clonedSourcePackagesDirPath .xcode-spm -derivedDataPath .xcode-derived
```

Expected : `** BUILD SUCCEEDED **` (ou aucune sortie d'erreur avec `-quiet`).

- [ ] **Step 7 : vérifications globales et commit**

```bash
swift build --build-tests && swift test --skip MatrixClientKitIntegrationTests \
  && swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKit Tests/MatrixClientKitTests/NotificationContentTests.swift
git commit -m "feat: MatrixNotificationService et remplissage d'un UNMutableNotificationContent

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10 : Suite d'intégration 0.3

Tâche qui s'exécute contre un vrai homeserver. Les tests s'écrivent et se compilent sans
identifiants ; leur **exécution** attend que l'utilisateur fournisse les variables d'environnement
(le demander explicitement dans le rapport de tâche, ne jamais les inventer).

**Contraintes propres à cette suite, à respecter à la lettre :**

- Le Keychain de test porte **une seule** entrée de session pour tout le processus (service
  `com.matrixclientkit`, clé `com.matrixclientkit.session`, sans access group). Tout `login`
  l'écrase. Dans le cas bi-compte, le compte expéditeur se connecte donc **avant** le compte
  principal, et n'est déconnecté qu'**après** l'ouverture du service d'extension — sa
  déconnexion efface l'entrée, quel que soit le compte qui l'a écrite.
- Le stockage App Group est utilisable depuis `swift test` sur macOS (vérifié : `FileManager`
  synthétise `~/Library/Group Containers/<identifiant>` sans entitlement ni invite). Chaque
  exécution utilise un identifiant unique et supprime ce répertoire en fin de cas.

**Files:**
- Modify: `Package.swift` (dépendance `MatrixClientKitRust` de la cible d'intégration)
- Modify: `Sources/MatrixClientKitRust/RustMatrixClient.swift` (init interne)
- Modify: `Tests/MatrixClientKitIntegrationTests/IntegrationSupport.swift`
- Create: `Tests/MatrixClientKitIntegrationTests/NotificationTests.swift`
- Modify: `Tests/MatrixClientKitIntegrationTests/README.md`
- Modify: `Scripts/check-integration-env.sh`

**Interfaces:**
- Consumes : `MatrixNotificationService` (Task 9), `session.notifications` (Task 7),
  `SessionRestorer(storage:role:lockPolicy:)` et `.unset` (Task 4).
- Produces : `RustMatrixClient.init(homeserver: URL, restorer: SessionRestorer)` (interne,
  tests uniquement) ; helpers d'intégration `appGroupStorage()`, `removeAppGroup(_:)`,
  `rawLogout(_:accessToken:)`, `pushers(_:accessToken:)`, `IntegrationConfiguration.senderUsername`,
  `.senderPassword`, `.roomID`, `.hasSenderAccount`.

- [ ] **Step 1 : dépendance de test et init interne**

Dans `Package.swift`, remplacer la cible d'intégration par :

```swift
        .testTarget(
            name: "MatrixClientKitIntegrationTests",
            dependencies: ["MatrixClientKit", "MatrixClientKitRust"],
            exclude: ["README.md"]
        ),
```

Dans `Sources/MatrixClientKitRust/RustMatrixClient.swift`, ajouter après l'init public :

```swift
    /// Couture de test : un restorer à politique de verrou choisie, pour reproduire un client 0.2
    /// dans la suite d'intégration.
    init(homeserver: URL, restorer: SessionRestorer) {
        self.homeserver = homeserver
        self.restorer = restorer
    }
```

- [ ] **Step 2 : configuration et helpers**

Dans `Tests/MatrixClientKitIntegrationTests/IntegrationSupport.swift` :

Ajouter à `IntegrationConfiguration` les propriétés

```swift
    /// Salon partagé par les deux comptes (`MATRIX_TEST_ROOM_ID`).
    let roomID: RoomID?
    /// Second compte, membre de `roomID`, qui envoie le message que l'extension du compte
    /// principal doit résoudre.
    let senderUsername: String?
    let senderPassword: String?
```

les renseigner dans `current` :

```swift
            roomID: environment["MATRIX_TEST_ROOM_ID"].flatMap(RoomID.init(rawValue:)),
            senderUsername: environment["MATRIX_TEST_SENDER_USERNAME"],
            senderPassword: environment["MATRIX_TEST_SENDER_PASSWORD"]
```

et ajouter :

```swift
    static var hasRoom: Bool { current?.roomID != nil }
    static var hasSenderAccount: Bool {
        hasRoom && current?.senderUsername != nil && current?.senderPassword != nil
    }
```

Ajouter en fin de fichier :

```swift
/// Stockage App Group propre à une exécution. Sur macOS hors bac à sable, `FileManager`
/// synthétise le conteneur sous `~/Library/Group Containers/` sans entitlement.
func appGroupStorage() -> MatrixStorage {
    .appGroup("group.com.matrixclientkit.integration.\(UUID().uuidString)")
}

/// Supprime le conteneur synthétisé d'un stockage App Group. L'échec est ignoré, comme pour
/// ``removeDirectory(_:)``.
func removeAppGroup(_ storage: MatrixStorage) {
    guard case let .appGroup(identifier) = storage.location,
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    else { return }
    try? FileManager.default.removeItem(at: container)
}

/// Déconnecte un appareil ouvert par ``rawAccessToken(_:)``.
func rawLogout(_ configuration: IntegrationConfiguration, accessToken: String) async throws {
    var request = URLRequest(url: configuration.homeserver.appending(path: "_matrix/client/v3/logout"))
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data("{}".utf8)
    _ = try await URLSession.shared.data(for: request)
}

/// Les `pushkey` des pushers du compte, lus par l'API client, hors SDK.
func pushers(_ configuration: IntegrationConfiguration, accessToken: String) async throws -> [String] {
    var request = URLRequest(url: configuration.homeserver.appending(path: "_matrix/client/v3/pushers"))
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    let (data, _) = try await URLSession.shared.data(for: request)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let list = object?["pushers"] as? [[String: Any]] ?? []
    return list.compactMap { $0["pushkey"] as? String }
}

/// Se connecte sur un stockage donné et attend que la sync tourne.
func signIn(
    _ configuration: IntegrationConfiguration,
    storage: MatrixStorage,
    username: String? = nil,
    password: String? = nil,
    deviceName: String
) async throws -> any MatrixSession {
    let client = Matrix.client(homeserver: configuration.homeserver, storage: storage)
    let session = try await client.login(
        .password(
            username: username ?? configuration.username,
            password: password ?? configuration.password,
            deviceName: deviceName
        )
    )
    let states = session.sync.state
    await session.sync.start()
    _ = await firstValue(of: states) { $0 == .running }
    return session
}

/// Envoie un texte dans un salon et rend l'identifiant de l'événement une fois accepté par le
/// homeserver.
func sendText(_ body: String, in roomID: RoomID, from session: any MatrixSession) async throws -> EventID {
    for await snapshot in session.rooms.list(filter: .joined) where snapshot.contains(where: { $0.id == roomID }) {
        break
    }
    let timeline = try await session.rooms.room(roomID).timeline()
    let items = timeline.items
    try await timeline.send(.text(body))

    for await snapshot in items {
        if let message = snapshot.compactMap(\.message).first(where: { $0.body == body }),
            message.sendState == .sent,
            let eventID = message.eventID
        {
            return eventID
        }
    }
    throw MatrixError.unexpected(message: "The sent message never reached the sent state", details: nil)
}
```

- [ ] **Step 3 : écrire les cas d'intégration**

`Tests/MatrixClientKitIntegrationTests/NotificationTests.swift` :

```swift
import Testing
import Foundation
import MatrixClientKit
@testable import MatrixClientKitRust

/// Push et extension (spec 0.3, §11). Les cas qui ouvrent une session se déconnectent en fin de
/// cas ; voir le README de la suite pour les contraintes sur les comptes.
@Suite(.enabled(if: IntegrationConfiguration.isAvailable), .serialized)
struct NotificationTests {

    /// Cas 1 et 2 : l'extension résout le message d'un autre compte pendant que la session
    /// d'application est ouverte sur le même stockage, et la session d'application reste
    /// utilisable ensuite.
    @Test(.enabled(if: IntegrationConfiguration.hasSenderAccount), .timeLimit(.minutes(3)))
    func theExtensionResolvesAMessageWhileTheApplicationIsOpen() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let roomID = try #require(configuration.roomID)
        let senderDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mck-integration-\(UUID().uuidString)", isDirectory: true)
        let storage = appGroupStorage()

        // L'expéditeur d'abord : sa connexion écrit l'entrée Keychain partagée, que la connexion
        // du compte principal écrase ensuite (voir le README).
        let sender = try await signIn(
            configuration,
            storage: .local(directory: senderDirectory),
            username: configuration.senderUsername,
            password: configuration.senderPassword,
            deviceName: "MatrixClientKit Integration (sender)"
        )
        let application = try await signIn(configuration, storage: storage, deviceName: "MatrixClientKit Integration (app)")

        // Laisse à la sync de l'expéditeur le temps d'apprendre le nouvel appareil du compte
        // principal : sans cela, la clé du message ne lui est pas partagée et il reste
        // indéchiffrable — ce que le cas détecterait comme un échec.
        try await Task.sleep(for: .seconds(3))

        let body = "notification d'intégration \(UUID().uuidString)"
        let eventID = try await sendText(body, in: roomID, from: sender)

        let service = try await MatrixNotificationService(storage: storage)
        let result = try await service.notification(roomID: roomID, eventID: eventID)

        guard case let .notification(notification) = result else {
            Issue.record("résultat inattendu : \(result)")
            await cleaningUp {
                try? await application.logout()
                try? await sender.logout()
                removeAppGroup(storage)
                removeDirectory(senderDirectory)
            }
            return
        }
        #expect(notification.kind == .message(body: body))
        #expect(notification.sender.rawValue.hasPrefix("@\(configuration.senderUsername ?? "")"))
        #expect(notification.roomID == roomID)

        // Cas 2 : la session d'application n'a été ni déconnectée ni bloquée par l'extension.
        let reply = "réponse d'intégration \(UUID().uuidString)"
        _ = try await sendText(reply, in: roomID, from: application)

        await cleaningUp {
            try? await application.logout()
            try? await sender.logout()
            removeAppGroup(storage)
            removeDirectory(senderDirectory)
        }
    }

    /// Cas 3 : le homeserver accepte l'enregistrement et la suppression du pusher.
    @Test(.timeLimit(.minutes(1)))
    func aPusherIsRegisteredThenRemoved() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let storage = appGroupStorage()
        let session = try await signIn(configuration, storage: storage, deviceName: "MatrixClientKit Integration (pusher)")
        let token = try await rawAccessToken(configuration)
        let pusher = PusherConfiguration(
            deviceToken: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            appID: "com.matrixclientkit.integration",
            gatewayURL: URL(string: "https://push.matrixclientkit.invalid/_matrix/push/v1/notify")!,
            appDisplayName: "MatrixClientKit Integration",
            deviceDisplayName: "Integration",
            language: "en"
        )

        try await session.notifications.registerPusher(pusher)
        #expect(try await pushers(configuration, accessToken: token).contains(pusher.pushKey))

        try await session.notifications.unregisterPusher(pusher)
        #expect(try await !pushers(configuration, accessToken: token).contains(pusher.pushKey))

        await cleaningUp {
            try? await rawLogout(configuration, accessToken: token)
            try? await session.logout()
            removeAppGroup(storage)
        }
    }

    /// Cas 4 : le mode d'un salon se change puis se restaure.
    @Test(.enabled(if: IntegrationConfiguration.hasRoom), .timeLimit(.minutes(1)))
    func aRoomModeIsChangedThenRestored() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let roomID = try #require(configuration.roomID)
        let storage = appGroupStorage()
        let session = try await signIn(configuration, storage: storage, deviceName: "MatrixClientKit Integration (settings)")
        for await snapshot in session.rooms.list(filter: .joined) where snapshot.contains(where: { $0.id == roomID }) {
            break
        }

        try await session.notifications.setNotificationMode(.mute, for: roomID)
        let muted = try await session.notifications.notificationSettings(for: roomID)
        try await session.notifications.restoreDefaultNotificationMode(for: roomID)
        let restored = try await session.notifications.notificationSettings(for: roomID)

        #expect(muted == RoomNotificationSettings(mode: .mute, isDefault: false))
        #expect(restored.isDefault)

        await cleaningUp {
            try? await session.logout()
            removeAppGroup(storage)
        }
    }

    /// Cas 5 : un store créé par un client sans verrou, comme en 0.2, se restaure avec le verrou.
    @Test(.timeLimit(.minutes(2)))
    func aStoreCreatedWithoutTheLockIsRestoredWithIt() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let storage = appGroupStorage()
        let legacy = RustMatrixClient(
            homeserver: configuration.homeserver,
            restorer: SessionRestorer(storage: storage, lockPolicy: .unset)
        )
        let first = try await legacy.login(
            .password(
                username: configuration.username,
                password: configuration.password,
                deviceName: "MatrixClientKit Integration (0.2 store)"
            )
        )
        let firstStates = first.sync.state
        await first.sync.start()
        _ = await firstValue(of: firstStates) { $0 == .running }
        await first.sync.stop()

        let restored = try #require(try await Matrix.restoreSession(storage: storage))
        let states = restored.sync.state
        await restored.sync.start()
        let running = await firstValue(of: states) { $0 == .running }

        #expect(running == .running)
        #expect(restored.userID == first.userID)

        await cleaningUp {
            try? await restored.logout()
            removeAppGroup(storage)
        }
    }
}
```

- [ ] **Step 4 : vérifier la compilation et l'omission sans identifiants**

Run : `swift build --build-tests && swift test --filter NotificationTests`
Expected : compilation réussie ; sans variables d'environnement, la suite est ignorée
(« skipped »), aucune erreur.

- [ ] **Step 5 : documenter les nouvelles variables**

Dans `Tests/MatrixClientKitIntegrationTests/README.md` :
- ajouter à la commande d'exécution les lignes `MATRIX_TEST_SENDER_USERNAME=sender \` et
  `MATRIX_TEST_SENDER_PASSWORD=secret \` ;
- ajouter aux variables optionnelles :

```markdown
- `MATRIX_TEST_SENDER_USERNAME` and `MATRIX_TEST_SENDER_PASSWORD` name a **second** account,
  also a member of `MATRIX_TEST_ROOM_ID`. It sends the message the main account's notification
  service extension must resolve. Without them, the push case that needs two accounts is skipped.
  The room must not be muted for the main account, or the event is filtered out.
```

- ajouter aux exigences :

```markdown
- The notification cases use an App Group storage. On macOS, outside a sandbox, `FileManager`
  creates its container under `~/Library/Group Containers/group.com.matrixclientkit.integration.*`;
  each case removes its own. An interrupted run may leave one behind: delete them by hand.
- In the two-account case, the sender signs in **before** the main account and signs out **after**
  the extension opened: the Keychain holds one session entry per process, which every sign-in
  overwrites and every sign-out erases.
```

- [ ] **Step 6 : étendre le script de vérification**

Dans `Scripts/check-integration-env.sh`, après la vérification existante du salon, ajouter une
vérification du second compte, **optionnelle** : si `MATRIX_TEST_SENDER_USERNAME` est vide, afficher
`  SKIP  sender account (MATRIX_TEST_SENDER_USERNAME not set)` et continuer. Sinon, reprendre le
même motif que pour le compte principal (connexion par `curl` avec un corps JSON construit par
`python3`, mot de passe lu depuis `MATRIX_TEST_SENDER_PASSWORD` ou demandé sans écho), vérifier
que le salon figure dans `/_matrix/client/v3/joined_rooms` du second compte, rapporter par
`report ok|ko`, puis déconnecter la session ouverte (`POST /_matrix/client/v3/logout`). Mettre à
jour le commentaire d'en-tête : « It verifies the password, the room, whether recovery is set up,
and the optional sender account ».

Tester le script sans second compte :

```bash
MATRIX_TEST_SENDER_USERNAME= bash -n Scripts/check-integration-env.sh && echo "syntaxe OK"
```

Expected : `syntaxe OK`.

- [ ] **Step 7 : vérifications globales et commit**

```bash
swift build --build-tests && swift test --skip MatrixClientKitIntegrationTests \
  && swift format lint --recursive --strict Sources Tests
git add Package.swift Sources/MatrixClientKitRust/RustMatrixClient.swift Tests/MatrixClientKitIntegrationTests Scripts
git commit -m "test: suite d'intégration de la 0.3 — extension, pusher, mode de salon, store 0.2

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 8 : exécution réelle**

Demander à l'utilisateur les identifiants (ou qu'il lance lui-même) :

```bash
./Scripts/check-integration-env.sh
MATRIX_TEST_HOMESERVER=… MATRIX_TEST_USERNAME=… MATRIX_TEST_PASSWORD=… MATRIX_TEST_ROOM_ID=… \
MATRIX_TEST_SENDER_USERNAME=… MATRIX_TEST_SENDER_PASSWORD=… \
swift test --filter MatrixClientKitIntegrationTests
```

Expected : toute la suite passe, y compris les cas 0.1 et 0.2 (le verrou change la construction
de tous les clients App Group). Tout échec est un constat à analyser avec
`superpowers:systematic-debugging` avant de toucher au code — ne jamais affaiblir une assertion
pour faire passer la suite.

---

### Task 11 : Documentation

**Files:**
- Create: `Sources/MatrixClientKit/Documentation.docc/PushNotifications.md`
- Modify: `Sources/MatrixClientKit/Documentation.docc/MatrixClientKit.md` (Topics)
- Modify: `Sources/MatrixClientKit/Documentation.docc/TestingWithMocks.md` (mocks de notification)
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/superpowers/specs/2026-09-13-matrixclientkit-design.md` (§8, §12)

**Interfaces:**
- Consumes : toutes les API publiques des Tasks 2 à 9, constats de la Task 1 (comportement sous
  verrou), résultat de la Task 10.
- Produces : documentation consommateur en anglais.

- [ ] **Step 1 : article DocC**

`Sources/MatrixClientKit/Documentation.docc/PushNotifications.md`, en anglais, avec ces sections et
des extraits qui compilent contre l'API réelle :

1. `# Push notifications and the service extension` + résumé d'une phrase.
2. `## Overview` — le trajet : homeserver → passerelle (Sygnal, opérée par l'éditeur de l'app) →
   APNs → extension → `MatrixNotificationService` → notification affichée ; le contenu ne passe
   jamais par Apple (`event_id_only`).
3. `## Share the storage` — même App Group et même Keychain access group dans l'application et
   l'extension ; entitlements (`com.apple.security.application-groups`,
   `keychain-access-groups`, `aps-environment`) ; `MatrixStorage.appGroup(_:keychainAccessGroup:accessibility:)`
   des deux côtés ; pourquoi `afterFirstUnlock`.
4. `## Register the pusher` — `UIApplication.registerForRemoteNotifications()`, puis dans
   `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` :
   `try await session.notifications.registerPusher(PusherConfiguration(…))` ; appeler à chaque
   jeton reçu ; `fallbackAlert` dans la langue de l'utilisateur ; `mutable-content` posé par le
   package.
5. `## Write the extension` — le code complet du §6 de la spec (le `didReceive` avec
   `MatrixPushPayload`, le `switch` sur `NotificationResult`, `content.apply(_:)`),
   `serviceExtensionTimeWillExpire()` qui livre le contenu d'origine.
6. `## Rules` — pas de sync dans l'extension (et pourquoi) ; mémoire limitée (environ 24 Mo) :
   garder l'instance, ne pas ouvrir de `MatrixSession` ; ce qui se passe quand l'application
   détient le verrou (constat 2 de la Task 1) ; une session déconnectée donne
   `.authentication(.missingToken)` : livrer le contenu d'origine.
7. `## Room notification settings` — `notificationSettings(for:)`, `setNotificationMode(_:for:)`,
   `restoreDefaultNotificationMode(for:)`, exemple de menu à trois choix.
8. `## Testing` — `MockNotificationResolver` et `MockNotificationService` en deux exemples.

- [ ] **Step 2 : Topics**

Dans `Sources/MatrixClientKit/Documentation.docc/MatrixClientKit.md` :
- sous `### Getting started`, ajouter `- <doc:PushNotifications>` après `<doc:VerificationAndRecovery>` ;
- ajouter une section après `### Encryption` :

```markdown
### Push notifications

- ``NotificationService``
- ``PusherConfiguration``
- ``RoomNotificationMode``
- ``RoomNotificationSettings``
- ``MatrixNotificationService``
- ``NotificationContentResolving``
- ``MatrixPushPayload``
- ``MatrixNotification``
- ``NotificationResult``
```

Dans `TestingWithMocks.md`, ajouter `MockNotificationService` et `MockNotificationResolver` à la
liste des doubles, avec une phrase chacun.

- [ ] **Step 3 : vérifier la DocC**

Run :

```bash
swift package --allow-writing-to-directory .docc-build generate-documentation \
  --target MatrixClientKit --output-path .docc-build --warnings-as-errors 2>&1 | tail -20
```

Si le plugin DocC n'est pas déclaré dans le manifeste, utiliser la commande de l'étape DocC de
`.github/workflows/ci.yml` (la lire : `sed -n '/DocC/,$p' .github/workflows/ci.yml`).
Expected : aucun avertissement, aucun lien ``…`` non résolu. Supprimer `.docc-build` ensuite.

- [ ] **Step 4 : README**

- Section Scope : « v0.3 covers … and push notifications through a notification service
  extension, and per-room notification settings ». Retirer « push notifications and the
  associated service extension » de la liste de ce que la version n'expose pas ; y ajouter
  « account-wide notification settings (mentions, invitations, calls, keywords) ».
- Tableau de feuille de route : ligne 0.3 → « Push notifications, service extension,
  cross-process lock, per-room notification settings ».
- Installation : `from: "0.3.0"`.
- Compatibilité : ligne `| 0.3.x | 26.09.07 | 18+ | 15+ | 6.2+ |` en tête.

- [ ] **Step 5 : CHANGELOG**

Ajouter en tête, sous l'introduction :

```markdown
## [Unreleased]

### Breaking

- `MatrixSession` requires a new member, `notifications`. An application that implements the
  protocol itself — typically in a test double — must add it, or use `MockMatrixSession`.

### Added

- `MatrixSession.notifications`, a `NotificationService`: `registerPusher(_:)` and
  `unregisterPusher(_:)` with a `PusherConfiguration`, and per-room notification settings —
  `notificationSettings(for:)`, `setNotificationMode(_:for:)`, `restoreDefaultNotificationMode(for:)`.
- `MatrixNotificationService`, the notification service extension's entry point: resolves a push
  into a `MatrixNotification` without syncing. `MatrixPushPayload` reads the push's room and event.
- `UNMutableNotificationContent.apply(_:)` fills a notification from a `MatrixNotification`.
- `MockNotificationService`, `MockNotificationResolver`, `SampleData.notification(kind:isDirect:isNoisy:)`
  and `SampleData.pusherConfiguration()`.

### Changed

- Clients built on an App Group storage take the Rust SDK's cross-process lock, so that the
  application and its extension no longer write the same store unaware of each other. Clients on
  a local storage are explicitly single-process.

### Not included

- Account-wide notification settings (mentions, invitations, calls, keywords) and batch
  resolution of notifications.
```

Si la Task 1 a établi que le défaut amont était déjà `multiProcess`, reformuler l'entrée
« Changed » en conséquence (le verrou devient explicite et nommé par rôle) — elle doit décrire le
changement réel de comportement.

- [ ] **Step 6 : spec de référence**

Dans `docs/superpowers/specs/2026-09-13-matrixclientkit-design.md` :
- §8, « API de l'extension » : remplacer l'extrait par `MatrixNotificationService(storage:)` sans
  `userID`, et ajouter « Voir la spec 0.3 pour le verrou inter-processus » ;
- §12, ligne v0.3 : « Push : `MatrixNotificationService`, App Group, extension, verrou
  inter-processus, mode de notification par salon (paramètres globaux reportés) ».

- [ ] **Step 7 : vérifications globales et commit**

```bash
swift build --build-tests && swift test --skip MatrixClientKitIntegrationTests \
  && swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKit/Documentation.docc README.md CHANGELOG.md docs/superpowers/specs/2026-09-13-matrixclientkit-design.md
git commit -m "docs: push et extension de service dans la DocC, le README et le CHANGELOG

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12 : Publication 0.3.0

**Files:**
- Modify: `Sources/MatrixClientKitCore/PackageInfo.swift`
- Modify: `Tests/MatrixClientKitCoreTests/PackageInfoTests.swift`
- Modify: `CHANGELOG.md`

- [ ] **Step 1 : test de version en échec**

Dans `Tests/MatrixClientKitCoreTests/PackageInfoTests.swift`, remplacer l'attente
`"0.2.0"` par `"0.3.0"`.

Run : `swift test --filter PackageInfoTests`
Expected : FAIL.

- [ ] **Step 2 : monter la version**

`Sources/MatrixClientKitCore/PackageInfo.swift` : `public static let version = "0.3.0"`.
`CHANGELOG.md` : `## [Unreleased]` → `## [0.3.0] - <date du jour, AAAA-MM-JJ>`.

Run : `swift test --filter PackageInfoTests`
Expected : PASS.

- [ ] **Step 3 : vérification complète**

```bash
swift build --build-tests
swift test --skip MatrixClientKitIntegrationTests
swift format lint --recursive --strict Sources Tests
xcodebuild build -quiet -scheme MatrixClientKit -destination 'generic/platform=iOS Simulator' \
  -clonedSourcePackagesDirPath .xcode-spm -derivedDataPath .xcode-derived
```

Expected : tout passe. Confirmer que la suite d'intégration de la Task 10 (Step 8) a passé
**sur ce même code** ; si du code de production a changé depuis, la relancer.

- [ ] **Step 4 : commit**

```bash
git add Sources/MatrixClientKitCore/PackageInfo.swift Tests/MatrixClientKitCoreTests/PackageInfoTests.swift CHANGELOG.md
git commit -m "chore: version 0.3.0

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5 : publication — sur accord explicite uniquement**

**S'arrêter et demander l'accord de l'utilisateur**, en lui présentant : la liste des commits
depuis `0.2.0` (`git log --oneline 0.2.0..HEAD`), le résultat de la suite d'intégration, et les
trois actions prévues. Seulement après un « oui » explicite :

```bash
git push origin main
git tag 0.3.0 && git push origin 0.3.0
gh release create 0.3.0 --title "0.3.0" --notes-file <(sed -n '/## \[0.3.0\]/,/## \[0.2.0\]/p' CHANGELOG.md | sed '$d')
```

Puis vérifier que la CI du commit taggué est verte :
`gh run list --branch main --limit 1`.
