# MatrixClientKit 0.3 — Design

**Date :** 2026-09-27
**Statut :** validé en conversation, en relecture avant rédaction du plan d'implémentation
**Auteur :** Kevin Esprit
**Entrées :** spec de référence `2026-09-13-matrixclientkit-design.md` (§8, §12) ; `docs/v0.2-brief.md`
(hors périmètre reporté en 0.3) ; README (feuille de route)
**Amont :** `matrix-rust-components-swift` `26.09.07` (inchangé)

---

## 1. Objectif et périmètre

Permettre à une application d'afficher des notifications push Matrix complètes — expéditeur, salon,
texte déchiffré — depuis une extension de service de notification, sans que l'application et
l'extension, qui partagent le même store, ne se corrompent ou ne se déconnectent mutuellement. Et
permettre à l'utilisateur de régler le niveau de notification d'un salon.

| Inclus | Exclu (et palier) |
| --- | --- |
| Enregistrement et suppression du pusher HTTP (APNs, format `eventIdOnly`) | La passerelle push elle-même (côté serveur, à la charge de l'application) |
| `MatrixNotificationService(storage:)` : résolution d'une notification dans l'extension | Résolution par lot (`getNotifications`) |
| Verrou inter-processus (`crossProcessLockConfig`) sur les stockages App Group | Montée de l'amont |
| `MatrixPushPayload(userInfo:)` : lecture du payload APNs | Notifications locales, badges, actions de notification |
| Aide `UNMutableNotificationContent.apply(_:)` dans l'umbrella | — |
| Mode de notification par salon : lire, changer, restaurer le défaut | Bascules globales (mentions, invitations, appels), mots-clés, défauts par type de salon, flux de changements des paramètres (ultérieur) |
| Mocks : service de notification, résolveur d'extension, fixtures | — |

## 2. Constats amont (release `26.09.07`)

1. **Client de notification.** `Client.notificationClient(processSetup:)` rend un
   `NotificationClient`. `processSetup` vaut `.multipleProcesses` ou `.singleProcess(syncService:)` ;
   une extension est un processus distinct, donc `.multipleProcesses`.
2. **Résolution.** `NotificationClient.getNotification(roomId:eventId:)` tente une sliding sync
   éphémère, puis `/context`, et rend un `NotificationStatus` :
   `.event(item:)`, `.eventNotFound`, `.eventFilteredOut` (règles push, utilisateur ignoré),
   `.eventRedacted`. Une erreur signifie que la notification n'a pas pu être résolue.
3. **Contenu.** `NotificationItem` porte `event` (`.timeline(event: TimelineEvent)` ou
   `.invite(sender:)`), `senderInfo` (`displayName?`, `avatarUrl?`, `isNameAmbiguous`), `roomInfo`
   (`displayName`, `isDirect`, `isDm`, `isEncrypted?`, `joinedMembersCount`…), `isNoisy: Bool?`,
   `hasMention: Bool?`, `threadId: String?`, `actions`, `rawEvent`. Le contenu d'un
   `TimelineEvent` est un `TimelineEventContent` ; un message est
   `.messageLike(.roomMessage(messageType:inReplyToEventId:))`, un message indéchiffrable
   `.messageLike(.roomEncrypted)` — **sans cause** de l'échec, contrairement à la timeline.
4. **Pusher.** `Client.setPusher(identifiers: PusherIdentifiers(pushkey:appId:), kind:
   .http(data: HttpPusherData(url:format:defaultPayload:)), appDisplayName:, deviceDisplayName:,
   profileTag:, lang:, append:)` et `Client.deletePusher(identifiers:)`. `PushFormat` n'a qu'un cas,
   `.eventIdOnly`.
5. **Verrou inter-processus.** `ClientBuilder.crossProcessLockConfig(_:)` accepte
   `.multiProcess(holderName:)` ou `.singleProcess`. **Aucun des `ClientBuilder` du package ne
   l'appelle aujourd'hui.** Le défaut amont n'est pas documenté dans les bindings : la première
   tâche du plan le vérifie dans les sources Rust de la release épinglée, et la spec s'applique
   quel qu'il soit, puisque le package fixe désormais la valeur explicitement.
6. **Paramètres.** `Client.getNotificationSettings()` rend un `NotificationSettings` :
   `getRoomNotificationSettings(roomId:isEncrypted:isOneToOne:)` →
   `RoomNotificationSettings(mode:isDefault:)`, `setRoomNotificationMode(roomId:mode:)`,
   `restoreDefaultRoomNotificationMode(roomId:)`. `RoomNotificationMode` : `.allMessages`,
   `.mentionsAndKeywordsOnly`, `.mute`.

## 2 bis. Constats vérifiés (Task 1 du plan)

Révision `matrix-rust-sdk` de la release `26.09.07` :
`48e07662de89d626c1ee0349ee44c5553ca30eb7`.

1. **Défaut de `crossProcessLockConfig`.** Quand le `ClientBuilder` n'appelle jamais
   `cross_process_lock_config(_:)`, la valeur par défaut du champ est
   `CrossProcessLockConfig::SingleProcess`
   (`bindings/matrix-sdk-ffi/src/client_builder.rs`, ligne 216, dans
   `ClientBuilder::new()` ; l'enum et sa conversion FFI sont définies lignes 876–893).
   C'est donc le comportement de la 0.2 (aucun verrou). Cela ne contredit pas la spec :
   le §3 choisit déjà explicitement le verrou par le type de stockage, quelle que soit
   la valeur par défaut amont.
2. **`getNotification` et le verrou tenu par l'application.** Le verrou inter-processus
   n'est pas spécifique à `NotificationClient` : `NotificationClient::new()` configure le
   store de l'extension avec `CrossProcessLockConfig::multi_process("notifications")`
   quand `process_setup` vaut `MultipleProcesses`
   (`crates/matrix-sdk-ui/src/notification_client.rs`, lignes 113–128), puis c'est
   l'infrastructure générique de verrou (`crates/matrix-sdk-common/src/cross_process_lock.rs`)
   qui gère l'attente. `CrossProcessLock::spin_lock(max_backoff)` (lignes 543–590) retente
   la prise du verrou avec un recul exponentiel : premier délai `INITIAL_BACKOFF_MS = 10 ms`
   (ligne 297), doublé à chaque tentative, plafonné par défaut à
   `MAX_BACKOFF_MS = 1000 ms` (ligne 301) ; une fois ce plafond atteint sans avoir obtenu
   le verrou, l'appel rend `CrossProcessLockUnobtained::TimedOut` (ligne 583) plutôt que
   d'attendre indéfiniment. Donc l'extension **attend** le verrou tenu par l'application,
   avec un recul exponentiel de 10 ms à 1 s, puis **échoue** par un timeout si le verrou
   n'est toujours pas libre (l'application le renouvelle par défaut toutes les
   `EXTEND_LEASE_EVERY_MS = 50 ms`, pour un bail de `LEASE_DURATION_MS = 500 ms`,
   lignes 286–293).
3. **Payload Sygnal `event_id_only`.**
   `sygnal/apnspushkin.py`, fonction `_get_payload_event_id_only` (lignes 388–414) :
   (a) `room_id` et `event_id` sont bien affectés à la racine du payload
   (`payload["room_id"] = n.room_id`, `payload["event_id"] = n.event_id`, lignes 405–408) ;
   (b) `default_payload` est fusionné à la racine avant cela
   (`payload = {}` puis `payload.update(default_payload)`, lignes 401–403), donc un `aps`
   fourni par le pusher (dans `HttpPusherData.defaultPayload`) arrive tel quel à la racine
   du payload APNs, sans être écrasé (seules les clés `room_id`/`event_id` sont ensuite
   posées, distinctes de `aps`). Les deux points de la spec sont confirmés ; aucune
   correction nécessaire.
4. **`isOneToOne` chez Element X.** Élément X calcule
   `isOneToOne: roomProxy.infoPublisher.value.activeMembersCount == 2` à chaque appel à
   `getNotificationSettings`/`getDefaultRoomNotificationMode`
   (`ElementX/Sources/Screens/RoomDetailsScreen/RoomDetailsScreenViewModel.swift` et
   `ElementX/Sources/Screens/RoomNotificationSettingsScreen/RoomNotificationSettingsScreenViewModel.swift`),
   avec le commentaire : « `isOneToOne` here is not the same as `isDirect` on the room. From
   the point of view of the push rule, a one-to-one room is a room with exactly two active
   members. » Conforme à l'attente de la spec (`activeMembersCount == 2`).

## 3. Décisions actées

| Décision | Raison |
| --- | --- |
| L'extension a son propre point d'entrée, `MatrixNotificationService`, et son propre client | Aucune sync accessible depuis l'extension par construction ; mémoire réduite (limite d'environ 24 Mo d'une NSE) |
| Écarté : restaurer une `MatrixSession` complète dans l'extension | Rendrait la sync appelable depuis l'extension, contre la règle de la spec §8 |
| Écarté : requêtes HTTP brutes sans SDK | Aucun déchiffrement : inutilisable sur un salon chiffré |
| `MatrixNotificationService(storage:)` sans `userID` | Un stockage porte une seule session (`SessionPersistence.storageKey`), comme `Matrix.restoreSession(storage:)` |
| Verrou choisi par le stockage : App Group → `.multiProcess`, local → `.singleProcess` | Un stockage local n'est partagé avec aucune extension ; un App Group l'est par définition |
| Core rend un modèle pur ; l'aide `UserNotifications` vit dans l'umbrella | Core reste utilisable hors iOS ; l'application peut ignorer l'aide |
| Format de pusher `eventIdOnly` imposé | Le contenu des messages ne transite pas par Apple ; c'est le seul format amont |
| Paramètres minimaux : mode par salon | Choix explicite de périmètre ; le reste est listé au §1 |
| Aucun nouveau cas de `MatrixError` | Règle d'évolution du README ; les cas existants suffisent (§8) |
| `MatrixSession` gagne `notifications` : **changement cassant** | Même traitement qu'`encryption` en 0.2 ; consigné au CHANGELOG |

## 4. Architecture

```
MatrixClientKitCore      (aucun import amont)
  Services/NotificationService.swift           protocole, sur MatrixSession.notifications
  Services/NotificationContentResolving.swift  protocole de l'extension
  Models/Notification.swift                    MatrixNotification, NotificationResult
  Models/PusherConfiguration.swift             configuration du pusher, jeton APNs en base64
  Models/MatrixPushPayload.swift               lecture du payload APNs
  Models/RoomNotificationMode.swift            mode et réglage d'un salon

MatrixClientKitRust
  Bridge/NotificationMapper.swift              NotificationStatus → NotificationResult
  Bridge/NotificationDriving.swift             protocoles d'abstraction de l'amont (tests)
  Bridge/CrossProcessLock.swift                MatrixStorage → CrossProcessLockConfig, fonction pure
  RustNotificationService.swift                pusher et paramètres
  RustNotificationResolver.swift               client d'extension et NotificationClient
  SessionRestorer.swift                        applique le verrou (point unique) ; rôle app ou extension

MatrixClientKit (umbrella)
  MatrixNotificationService.swift              point d'entrée de l'extension
  UNMutableNotificationContent+Matrix.swift    apply(_:) (iOS et macOS, `#if canImport(UserNotifications)`)

MatrixClientKitMocks
  MockNotificationService.swift, MockNotificationResolver.swift, SampleData (fixtures)
```

Style identique à l'existant : classes `@unchecked Sendable` protégées par `NSLock` là où un état
mutable existe, protocoles `*Driving` pour isoler l'amont dans les tests comme
`EncryptionDriving`, aucun `@MainActor`.

## 5. API publique

### 5.1 Session

```swift
public protocol MatrixSession: Sendable {
    // … existant …
    /// Push notifications: the pusher and per-room notification settings.
    var notifications: any NotificationService { get }
}
```

### 5.2 Service de notification

```swift
public protocol NotificationService: Sendable {
    /// Registers this device with the homeserver so that it receives pushes through the gateway.
    /// Replaces any pusher this device registered before (`append: false`).
    func registerPusher(_ configuration: PusherConfiguration) async throws
    /// Stops pushes to this device for this token and app identifier.
    func unregisterPusher(_ configuration: PusherConfiguration) async throws

    func notificationSettings(for roomID: RoomID) async throws -> RoomNotificationSettings
    func setNotificationMode(_ mode: RoomNotificationMode, for roomID: RoomID) async throws
    func restoreDefaultNotificationMode(for roomID: RoomID) async throws
}

public struct PusherConfiguration: Sendable, Hashable {
    public let deviceToken: Data        // jeton APNs brut, tel que reçu par l'AppDelegate
    public let appID: String            // identifiant attendu par la passerelle, ex. "com.example.app.ios.prod"
    public let gatewayURL: URL          // ex. https://push.example.com/_matrix/push/v1/notify
    public let appDisplayName: String
    public let deviceDisplayName: String
    public let language: String         // défaut : Locale.current, code de langue
    public let fallbackAlert: String    // défaut : "New message" — affiché si l'extension échoue
    public init(deviceToken:appID:gatewayURL:appDisplayName:deviceDisplayName:language:fallbackAlert:)
    /// Le `pushkey` envoyé au homeserver : le jeton encodé en base64 (`base64EncodedString()`).
    /// C'est ce qu'attend par défaut le pushkin APNs de Sygnal, qui décode le pushkey depuis le
    /// base64 (`convert_device_token_to_hex`, apnspushkin.py:242-247) ; une passerelle configurée
    /// autrement doit s'aligner.
    public var pushKey: String { get }
}

public enum RoomNotificationMode: Sendable, Hashable {
    case allMessages
    case mentionsAndKeywordsOnly
    case mute
}

public struct RoomNotificationSettings: Sendable, Hashable {
    public let mode: RoomNotificationMode   // le mode effectif
    public let isDefault: Bool              // true quand aucun réglage propre au salon n'existe
}
```

Le pusher est enregistré avec un `default_payload` que la passerelle fusionne dans chaque push
APNs : `{"aps":{"mutable-content":1,"alert":{"body":"<fallbackAlert>"}}}`. **Sans
`mutable-content`, iOS n'appelle jamais l'extension** ; sans `alert`, iOS n'appelle pas non plus
l'extension. L'alerte de repli est ce que voit l'utilisateur si l'extension échoue ou dépasse son
temps : l'application la fournit dans sa langue.

`notificationSettings(for:)` récupère lui-même `isEncrypted` et « un à un » (salon direct à deux
membres) du salon, que l'amont exige, via le client de la session.

### 5.3 Extension

```swift
public protocol NotificationContentResolving: Sendable {
    func notification(roomID: RoomID, eventID: EventID) async throws -> NotificationResult
}

public enum NotificationResult: Sendable, Hashable {
    case notification(MatrixNotification)
    case notFound       // l'événement est introuvable
    case filteredOut    // règles push ou expéditeur ignoré : ne rien afficher
    case redacted       // l'événement a été supprimé
}

public struct MatrixNotification: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case message(body: String)
        case invite
    }
    public let roomID: RoomID
    public let eventID: EventID
    public let sender: UserID
    public let senderDisplayName: String?
    public let roomDisplayName: String
    public let isDirect: Bool
    public let kind: Kind
    public let isNoisy: Bool        // amont nil → false
    public let hasMention: Bool     // amont nil → false
    public let threadID: EventID?
}

public struct MatrixPushPayload: Sendable, Hashable {
    public let roomID: RoomID
    public let eventID: EventID
    /// `nil` when `room_id` or `event_id` is missing or invalid.
    public init?(userInfo: [AnyHashable: Any])
}
```

Le payload lu est celui qu'envoie Sygnal au format `event_id_only` : `room_id` et `event_id` à la
racine du dictionnaire `userInfo`. L'expéditeur d'une invitation (`.invite(sender:)`) alimente
`sender` ; pour un message, `TimelineEvent.senderId()`.

### 5.4 Points d'entrée (umbrella)

```swift
public final class MatrixNotificationService: NotificationContentResolving {
    /// Opens the session persisted in `storage` for resolving notifications, without syncing.
    /// - Throws: `MatrixError.authentication(.missingToken)` when no session is stored.
    public init(storage: MatrixStorage) async throws
    public func notification(roomID: RoomID, eventID: EventID) async throws -> NotificationResult
}

extension UNMutableNotificationContent {
    /// Fills title, body, thread identifier and sound from a resolved notification.
    public func apply(_ notification: MatrixNotification)
}
```

`apply(_:)` : salon direct → titre = nom de l'expéditeur (à défaut son identifiant), corps = texte ;
autre salon → titre = nom du salon, corps = « Expéditeur: texte » (en anglais : `"\(sender): \(body)"`) ;
invitation → corps `"Invited you to chat"` ; `threadIdentifier` = identifiant du salon ;
`sound = .default` si `isNoisy`, sinon `nil`. Toutes les chaînes sont en anglais.

## 6. Extension : flux

```swift
// NotificationService.swift, dans l'extension de l'application
override func didReceive(_ request: UNNotificationRequest,
                         withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
    guard let payload = MatrixPushPayload(userInfo: request.content.userInfo),
          let content = request.content.mutableCopy() as? UNMutableNotificationContent
    else { return contentHandler(request.content) }

    Task {
        do {
            let service = try await MatrixNotificationService(storage: .appGroup("group.com.example.app"))
            switch try await service.notification(roomID: payload.roomID, eventID: payload.eventID) {
            case .notification(let notification):
                content.apply(notification)
                contentHandler(content)
            case .filteredOut, .redacted:
                contentHandler(UNNotificationContent())
            case .notFound:
                contentHandler(request.content)
            }
        } catch {
            contentHandler(request.content)
        }
    }
}
```

1. `MatrixNotificationService.init(storage:)` lit la session persistée via `SessionRestorer` ; sans
   session, `MatrixError.authentication(.missingToken)`.
2. Il construit un client persistant sur le même store SQLite avec le rôle « extension »
   (§7), puis `notificationClient(processSetup: .multipleProcesses)`. Les deux sont retenus par
   l'instance : l'extension peut la garder entre deux pushes tant que son processus vit.
3. `notification(roomID:eventID:)` appelle `getNotification` puis `NotificationMapper`.
4. Le type n'expose ni sync, ni rooms, ni logout.

### 6.1 Corps d'un message

`NotificationMapper` traduit `MessageType` en texte, avec le vocabulaire de la timeline :

| Contenu amont | Corps |
| --- | --- |
| `.text`, `.notice` | le corps du message |
| `.emote` | `"* \(sender) \(body)"` |
| `.image`, `.video`, `.audio`, `.file` | la légende si elle existe et n'est pas vide, sinon `"Sent an image"` / `"Sent a video"` / `"Sent an audio message"` / `"Sent a file"` (le nom de fichier, souvent `IMG_1234.jpg`, n'est jamais utilisé) |
| `.gallery` | `"Sent images"` |
| `.location` | `"Shared a location"` |
| `.other(msgtype:body:)` | le corps de repli s'il n'est pas vide (la spec Matrix l'exige pour tout `msgtype`), sinon `"Sent a message"` |
| `.roomEncrypted` | `"The message could not be decrypted."` (même phrase que la timeline sans cause) |
| tout autre contenu (`.poll`, `.sticker`, appels…) | `"Sent a message"` |

Un identifiant invalide dans la réponse amont (expéditeur, fil) donne `MatrixError.unexpected`
plutôt qu'un plantage.

## 7. Verrou inter-processus et rafraîchissement de jeton

`SessionRestorer.makeClient` reçoit un rôle, `.application` ou `.notificationExtension`, et applique
la configuration renvoyée par une fonction pure :

| Stockage | Rôle | `CrossProcessLockConfig` |
| --- | --- | --- |
| `.appGroup` | application | `.multiProcess(holderName: "app")` |
| `.appGroup` | extension | `.multiProcess(holderName: "nse")` |
| `.local` | application | `.singleProcess` |
| `.local` | extension | refusé : `MatrixError.storage(.unavailable)` — une extension ne peut pas lire un stockage local |

Le client de poignée de main (store en mémoire, utilisé pendant `login`) n'est pas concerné.

Le rôle règle aussi `autoEnableCrossSigning` : `true` pour l'application (comportement 0.2),
`false` pour l'extension — l'amorçage d'une identité est une écriture de compte que seule
l'application doit faire, jamais un processus de quelques secondes lancé par un push.

Une couture interne, `SessionRestorer.LockPolicy` (`.automatic` par défaut, `.unset` pour
reproduire un client 0.2 sans appel à `crossProcessLockConfig`), sert uniquement au cas
d'intégration 5. Elle n'est pas publique.

Rafraîchissement de jeton (piège n° 3 de la spec §8) : en `.multiProcess`, le SDK prend son verrou
de rafraîchissement inter-processus et relit la session via
`SessionDelegate.retrieveSessionFromKeychain`, qui lit déjà le Keychain partagé à chaque appel.
Aucun changement au delegate ; le cas bi-client est couvert par l'intégration (§11).

## 8. Erreurs

Aucun nouveau cas, y compris dans les enums imbriqués.

| Situation | Erreur |
| --- | --- |
| Aucune session persistée à l'ouverture de l'extension | `.authentication(.missingToken)` |
| Extension ouverte sur un stockage `.local` | `.storage(.unavailable)` |
| Salon inconnu pour les paramètres | `.notFound(.room)` |
| Identifiant invalide dans une réponse amont | `.unexpected(message:details:)` |
| Échecs de `getNotification`, `setPusher`, `deletePusher`, des paramètres | `ErrorMapper` existant (réseau, authentification, serveur, `.unexpected`) |

## 9. Mocks

- `MockNotificationService` : enregistre les configurations passées à `registerPusher` /
  `unregisterPusher` et les modes demandés ; `settings` par salon modifiables ; une erreur injectable
  par opération (`registerError`, `unregisterError`, `settingsError`), comme `MockTimeline`.
- `MockNotificationResolver` : résultat par couple salon/événement, résultat par défaut, erreur
  injectable, historique des appels.
- `MockMatrixSession` gagne `notifications: MockNotificationService`.
- `SampleData.notification(kind:isDirect:isNoisy:)` et `SampleData.pusherConfiguration()`.

## 10. Vérifications amont (première tâche du plan)

1. Défaut de `crossProcessLockConfig` dans les sources Rust de la release épinglée.
2. Clés exactes du payload APNs envoyé par Sygnal en `event_id_only` (`room_id`, `event_id` à la
   racine).
3. Comportement de `getNotification` quand l'application détient le verrou : attente, échec ou
   contournement — pour documenter ce que voit l'extension.
4. `isOneToOne` : la définition amont utilisée par Element X (salon direct, deux membres actifs).

Tout écart avec cette spec est consigné dans la spec avant d'écrire le code concerné.

## 11. Tests

**Unitaires (TDD, Swift Testing)**

- Core : `MatrixPushPayload` (valide, champ manquant, identifiant invalide, types inattendus),
  `PusherConfiguration.pushKey` (base64, jeton vide → chaîne vide), modèles.
- Rust : `NotificationMapper` (4 statuts, message et invitation, expéditeur sans nom, chaque ligne du
  tableau §6.1, `isNoisy`/`hasMention` nil, identifiant invalide) ; `CrossProcessLock` (les quatre
  lignes du tableau §7) ; `RustNotificationService` derrière `NotificationDriving` (pusher construit
  avec `pushkey`, `appId`, URL, `.eventIdOnly`, `default_payload` avec `mutable-content` et l'alerte de repli, `append: false` ; paramètres ; erreurs mappées).
- Umbrella : `apply(_:)` en salon direct, en salon de groupe, invitation, bruyant ou non.
- Mocks : injection d'erreurs et historique.

**Intégration** — nouvelles variables `MATRIX_TEST_SENDER_USERNAME` et `MATRIX_TEST_SENDER_PASSWORD`
(un second compte membre de `MATRIX_TEST_ROOM_ID`), vérifiées aussi par
`Scripts/check-integration-env.sh` :

1. Le compte principal a une session d'application ouverte sur un stockage App Group de test ; le
   second compte envoie un message ; `MatrixNotificationService` ouvert sur le **même stockage**
   résout l'événement en `.notification` avec le bon expéditeur et le bon texte.
2. Après ce cas, la session d'application reste utilisable : la sync repart et un message s'envoie.
3. `registerPusher` puis `unregisterPusher` sont acceptés par le homeserver (passerelle factice en
   `https://…/_matrix/push/v1/notify`).
4. Mode de salon : `mute`, relu ; restauration du défaut, relu avec `isDefault == true`.
5. Une session créée par un client construit sans verrou (comme en 0.2) est restaurée par un client
   `.multiProcess` : la restauration réussit et la sync démarre.

Sans les variables du second compte, les cas 1 et 2 sont ignorés, comme les cas optionnels de 0.2.

## 12. Documentation

Destinée aux consommateurs, donc en anglais :

- Article DocC « Push notifications and the service extension » : App Group et Keychain access
  group partagés, entitlements de l'application et de l'extension, enregistrement du pusher depuis
  l'`AppDelegate`, code complet de l'extension (§6), règle « no sync in the extension », limite
  mémoire, choix de la passerelle (Sygnal). Nouveaux types dans les Topics.
- README : Scope 0.3, feuille de route, tableau de compatibilité `0.3.x`.
- CHANGELOG 0.3.0 : **Breaking** (`MatrixSession.notifications`), **Added**, **Changed** (verrou
  inter-processus fixé explicitement pour tous les stockages).
- Spec de référence : §12 corrigée (paramètres minimaux en 0.3, le reste reporté), §8 alignée sur
  `MatrixNotificationService(storage:)` sans `userID`.

## 13. Publication 0.3.0

Terminé quand :

- `swift test --skip MatrixClientKitIntegrationTests` vert ;
- `swift format lint --recursive --strict Sources Tests` propre ;
- CI verte, build iOS compris ;
- suite d'intégration passée contre un vrai homeserver avec les deux comptes ;
- CHANGELOG à jour, changement cassant signalé ;
- `PackageInfo.version` = `0.3.0`, tag `0.3.0` poussé, release GitHub publiée.

## 14. Risques et parades

| Risque | Parade |
| --- | --- |
| L'extension dépasse sa limite mémoire en ouvrant le client | Client sans sync, instance réutilisable ; mesure sur appareil réel consignée dans l'article DocC |
| Le verrou `.multiProcess` change le comportement de l'application seule | Cas d'intégration 2 ; activé uniquement sur les stockages App Group |
| Un store 0.2 ouvert pour la première fois avec le verrou | Cas d'intégration 5 |
| La passerelle push est hors du package et mal configurée | Article DocC : l'échec d'une passerelle n'est pas visible par le homeserver ; comment tester avec Sygnal |
| Le payload APNs diffère selon la passerelle | `MatrixPushPayload` documente les clés lues ; l'application peut construire `RoomID`/`EventID` elle-même |
