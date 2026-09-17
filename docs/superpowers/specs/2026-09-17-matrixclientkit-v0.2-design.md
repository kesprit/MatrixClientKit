# MatrixClientKit 0.2 — Design

**Date :** 2026-09-17
**Statut :** validé, prêt pour la rédaction du plan d'implémentation
**Auteur :** Kevin Esprit
**Entrées :** `docs/v0.2-brief.md` ; spec de référence `2026-09-13-matrixclientkit-design.md`
**Amont :** `matrix-rust-components-swift` `26.09.07` (inchangé)

---

## 1. Objectif et périmètre

Rendre le chiffrement de bout en bout pilotable par une application — vérifier son appareil,
activer et utiliser la récupération, observer l'état du chiffrement — et combler les manques de
session et de testabilité relevés à l'usage de la 0.1.

| Inclus | Exclu (et palier) |
| --- | --- |
| Service `encryption` : états de vérification, sauvegarde, récupération | Vérification par QR (non exposée par l'amont épinglé) |
| Vérification de sa propre session par SAS (emojis ou nombres) | Vérification d'autres utilisateurs, shields, violations d'identité (ultérieur) |
| Récupération : activer, récupérer, régénérer la clé, désactiver ; activer la sauvegarde | Reset d'identité / cross-signing (ultérieur) |
| `Matrix.restoreSession(storage:)` sans URL | Passphrase de récupération, `recoverAndFixBackup`, `recoverAndReset` |
| `authState` : déconnexion côté serveur | Reconnexion sur le même appareil après soft logout (0.4) |
| Amorçage automatique du cross-signing ; idempotence documentée de `SyncController.start()` | Push et extension (0.3) ; médias, OAuth, `loginDetails()` (0.4) |
| Mocks : client, chiffrement, vérification ; corrections de `MockTimeline` et `MockMatrixSession` | `AsyncThrowingStream` |
| Chaînes visibles de la timeline en anglais (motif UTD dérivé de la cause) | Typage de la cause UTD (cassant) |

## 2. Constats amont (release `26.09.07`)

1. **Pas de vérification par QR.** `SessionVerificationController` ne propose que SAS. Les API QR
   présentes servent à la *connexion* par QR. La spec 0.1 (§6.6, §12) promettait « SAS et QR » :
   elle est corrigée.
2. **Un contrôleur unique, un flux à la fois.** Commandes : `requestDeviceVerification`,
   `acknowledgeVerificationRequest(senderId:flowId:)`, `acceptVerificationRequest`,
   `startSasVerification`, `approveVerification`, `declineVerification`, `cancelVerification`.
   Delegate synchrone à 7 callbacks : `didReceiveVerificationRequest(details:)`,
   `didAcceptVerificationRequest`, `didStartSasVerification`, `didReceiveVerificationData(data:)`,
   `didFail`, `didCancel`, `didFinish`.
3. **La récupération englobe la sauvegarde.** `enableRecovery(waitForBackupsToUpload:passphrase:progressListener:)`
   crée sauvegarde et clé et renvoie la clé ; `recover(recoveryKey:)` restaure les deux.
4. **États synchrones + listeners.** `verificationState()` / `verificationStateListener`,
   `backupState()` / `backupStateListener`, `recoveryState()` / `recoveryStateListener`.
5. **Erreurs de récupération** : `RecoveryError` = `BackupExistsOnServer`, `SecretStorage(errorMessage:)`,
   `Import(errorMessage:)`, `Client(source:)`.
6. **Déconnexion serveur** : `Client.setDelegate(delegate: ClientDelegate?) throws -> TaskHandle?`,
   callback `didReceiveAuthError(isSoftLogout:)`.
7. **Défauts 0.1 relevés** : `RustMatrixClient.restoreSession()` construit le client avec l'URL
   passée au client et ignore `MatrixSessionData.homeserverURL` ; `TimelineMapper` renvoie
   `.unableToDecrypt(reason: "message chiffré non déchiffrable")`, chaîne française en dur et sans
   cause. Les autres chaînes visibles du même mappeur (motifs d'échec d'envoi, descriptions
   `.unsupported`) sont elles aussi en français.
8. **Cross-signing jamais amorcé.** `ClientBuilder` a `auto_enable_cross_signing: false` par
   défaut, et `RustMatrixClient` ne le change pas : un compte qui ne s'est connecté que via
   MatrixClientKit n'a pas d'identité. Or `get_session_verification_controller` lit l'identité de
   l'utilisateur dans le store local et échoue (« Failed retrieving user identity ») si elle est
   absente — donc aussi avant que la première sync ne l'ait chargée.
9. **`SyncService::start` est idempotent** (source au commit `48e07662`, référencé par la release
   `26.09.07`) : verrou, aucun effet si l'état est `Running`, redémarrage depuis `Offline`, démarrage
   depuis `Idle`/`Terminated`/`Error`.
10. **Mauvaise clé de récupération** : `recover` renvoie `RecoveryError.SecretStorage(errorMessage:)`
    dont le message provient d'un `DecodeError` (préfixe, parité, Base58, longueur) ou d'un échec
    MAC (« The MAC check for the secret storage key failed »). Une récupération jamais configurée
    produit la même variante, avec « could not have been found in the account data ».

## 3. Décisions actées

| Sujet | Décision |
| --- | --- |
| Forme de la vérification | Machine à états publiée en instantanés (pas de flux d'événements, pas d'objet par flux) |
| Nouveaux cas `MatrixError` | Aucun. « Sauvegarde existante » se lit dans l'état, pas dans l'erreur |
| Commande hors état valide | `MatrixError.unexpected` avec message explicite, sans appel amont |
| Hard logout serveur | Arrêt de la sync, purge session + store, **puis** `.signedOut` |
| Soft logout serveur | `.softLoggedOut`, rien n'est effacé |
| Déconnexion observée | État `authState` (instantanés), pas un flux d'événements |
| Restauration sans URL | Fonction statique `Matrix.restoreSession(storage:)` ; l'URL persistée fait foi partout |
| Motif UTD | Texte anglais dérivé de la cause amont ; `reason: String` inchangé |
| Clé de récupération | Type `RecoveryKey` à description masquée |
| Progression de `enableRecovery` | Closure `@Sendable`, pas de flux séparé |
| Identité cross-signing | `ClientBuilder.autoEnableCrossSigning(true)` sur le client persistant ; aucune API publique |

Toutes les contraintes du brief s'appliquent : Core n'importe jamais `MatrixRustSDK`, aucun type
amont en signature publique, aucun `@MainActor` dans Core ni Rust, types publics `Sendable`,
Swift 6 strict, instantanés en `.bufferingNewest(1)`, TDD avec Swift Testing uniquement.

## 4. Architecture

Aucun nouveau module ni produit.

| Emplacement | Contenu |
| --- | --- |
| `MatrixClientKitCore/Services/EncryptionService.swift` | Protocole `EncryptionService` |
| `MatrixClientKitCore/Services/SessionVerification.swift` | Protocole `SessionVerification` |
| `MatrixClientKitCore/Models/Encryption*.swift` | `VerificationStatus`, `BackupState`, `RecoveryState`, `RecoveryProgress`, `RecoveryKey` |
| `MatrixClientKitCore/Models/SessionVerification*.swift` | `SessionVerificationState`, `VerificationRequest`, `SASData`, `SASEmoji`, réducteur (`package`) |
| `MatrixClientKitCore/Models/AuthState.swift` | `AuthState` |
| `MatrixClientKitRust/RustEncryptionService.swift` | Implémentation, derrière `EncryptionDriving` |
| `MatrixClientKitRust/RustSessionVerification.swift` | Implémentation, derrière `VerificationControllerDriving` |
| `MatrixClientKitRust/Bridge/EncryptionMapper.swift` | États et erreurs amont → domaine |
| `MatrixClientKitRust/SessionRestorer.swift` | Chemin de restauration partagé |
| `MatrixClientKitRust/Bridge/AuthDelegate.swift` | `ClientDelegate` → `authState` |
| `MatrixClientKitMocks/` | `MockMatrixClient`, `MockEncryptionService`, `MockSessionVerification` |

Les coutures `*Driving` suivent le modèle de `SyncServiceDriving` : elles existent parce que les
protocoles amont renvoient des types concrets qu'un test ne peut pas construire.

**Collision de noms.** `BackupState`, `RecoveryState`, `VerificationState` existent aussi dans
`MatrixRustSDK`. Les noms publics restent courts ; le module Rust qualifie avec
`MatrixClientKitCore.`. L'état global de l'appareil s'appelle `VerificationStatus`, pour ne pas le
confondre avec l'état du flux SAS (`SessionVerificationState`).

## 5. API publique

### 5.1 Session

```swift
public protocol MatrixSession: Sendable {
    var userID: UserID { get }
    var deviceID: DeviceID { get }
    var rooms: any RoomService { get }
    var sync: any SyncController { get }
    var encryption: any EncryptionService { get }        // nouveau
    var authState: AsyncStream<AuthState> { get }        // nouveau
    func logout() async throws
}

public enum AuthState: Sendable, Hashable {
    case signedIn
    case softLoggedOut
    case signedOut
}
```

Ajouter deux exigences à `MatrixSession` casse toute implémentation tierce du protocole :
changement cassant, consigné au CHANGELOG, `MockMatrixSession` étant l'alternative recommandée.

### 5.2 Service de chiffrement

```swift
public protocol EncryptionService: Sendable {
    var verificationStatus: AsyncStream<VerificationStatus> { get }
    var backupState: AsyncStream<BackupState> { get }
    var recoveryState: AsyncStream<RecoveryState> { get }
    var sessionVerification: any SessionVerification { get }

    func isLastDevice() async throws -> Bool
    func hasDevicesToVerifyAgainst() async throws -> Bool
    func backupExistsOnServer() async throws -> Bool

    func enableRecovery(
        waitForBackupUpload: Bool,
        progress: @escaping @Sendable (RecoveryProgress) -> Void
    ) async throws -> RecoveryKey
    func recover(with key: String) async throws
    func resetRecoveryKey() async throws -> RecoveryKey
    func disableRecovery() async throws
    func enableBackups() async throws
}

extension EncryptionService {
    /// Surcharge de commodité : `waitForBackupUpload: false`.
    public func enableRecovery(
        progress: @escaping @Sendable (RecoveryProgress) -> Void = { _ in }
    ) async throws -> RecoveryKey
}

public enum VerificationStatus: Sendable, Hashable { case unknown, verified, unverified }
public enum RecoveryState: Sendable, Hashable { case unknown, enabled, disabled, incomplete }
public enum BackupState: Sendable, Hashable {
    case unknown, creating, enabling, resuming, enabled, downloading, disabling
}
public enum RecoveryProgress: Sendable, Hashable {
    case starting
    case creatingBackup
    case creatingRecoveryKey
    case backingUp(uploaded: Int, total: Int)
    case roomKeyUploadError
    case done
}

public struct RecoveryKey: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    public let rawValue: String
    public var description: String { "RecoveryKey(<redacted>)" }
}
```

Les paramètres par défaut vivent dans l'extension, les protocoles Swift n'en acceptant pas.
`RecoveryProgress.done` ne porte pas la clé : elle n'est livrée que par la valeur de retour, un
seul canal pour un secret. Les compteurs amont `UInt32` sont convertis en `Int` avec la règle de
clamp existante.

**Sémantique des trois flux d'état.** Instantanés `.bufferingNewest(1)`. Chaque accès ouvre un
abonnement indépendant, qui **émet d'abord la valeur courante** (lecture synchrone amont), puis
chaque changement signalé par le listener. Sans cette première valeur, un écran ouvert après le
dernier changement resterait vide.

### 5.3 Vérification de session

```swift
public protocol SessionVerification: Sendable {
    var state: AsyncStream<SessionVerificationState> { get }
    func requestVerification() async throws
    func accept() async throws
    func startSAS() async throws
    func approve() async throws
    func decline() async throws
    func cancel() async throws
}

public enum SessionVerificationState: Sendable, Hashable {
    case idle
    case incomingRequest(VerificationRequest)
    case waitingForOtherDevice
    case ready
    case startingSAS
    case comparing(SASData)
    case confirming
    case verified
    case cancelled
    case failed
}

public struct VerificationRequest: Sendable, Hashable, Identifiable {
    public let id: String                 // flowId amont, opaque
    public let deviceID: DeviceID
    public let deviceDisplayName: String?
    public let firstSeen: Date
}

public enum SASData: Sendable, Hashable {
    case emojis([SASEmoji])
    case decimals([UInt16])
}

public struct SASEmoji: Sendable, Hashable {
    public let symbol: String
    public let description: String        // anglais, fourni par l'amont
    public let index: Int                 // indice dans la table SAS de la spec Matrix (0–63)
}
```

`.decimals` est exposé dès maintenant : l'amont peut l'envoyer, et l'ajouter plus tard serait
cassant. `index` permet à une application de localiser la description à partir de la table de la
spec Matrix. L'identifiant de l'expéditeur, nécessaire à `acknowledge`, est conservé en interne :
c'est toujours l'utilisateur courant.

### 5.4 Point d'entrée

```swift
extension Matrix {
    public static func restoreSession(storage: MatrixStorage) async throws -> (any MatrixSession)?
}
```

## 6. Machine à états de vérification

### 6.1 Réducteur

Fonction pure `package` dans Core : `reduce(_ state: SessionVerificationState, _ event: VerificationEvent) -> SessionVerificationState`.
`VerificationEvent` (`package`) regroupe les 7 callbacks amont et les succès de commandes locales.

| Commande | Valide depuis | Appel amont | État après succès |
| --- | --- | --- | --- |
| `requestVerification()` | `idle`, `verified`, `cancelled`, `failed` | `requestDeviceVerification` | `waitingForOtherDevice` |
| `accept()` | `incomingRequest` | `acknowledgeVerificationRequest` puis `acceptVerificationRequest` | inchangé ; `ready` sur `didAccept` |
| `startSAS()` | `ready` | `startSasVerification` | `startingSAS` ; `comparing` sur `didReceiveVerificationData` |
| `approve()` | `comparing` | `approveVerification` | `confirming` ; `verified` sur `didFinish` |
| `decline()` | `comparing` | `declineVerification` | inchangé ; `cancelled`/`failed` sur callback |
| `cancel()` | tout état non terminal hors `idle` | `cancelVerification`, précédé d'`acknowledge` depuis `incomingRequest` | `cancelled` |

| Callback | Effet |
| --- | --- |
| `didReceiveVerificationRequest` | `incomingRequest` depuis `idle` ou un état terminal ; **ignoré** pendant un flux actif |
| `didAcceptVerificationRequest` | `ready` depuis `waitingForOtherDevice` ou `incomingRequest` |
| `didStartSasVerification` | `startingSAS` depuis `ready` ou `startingSAS` (l'autre appareil peut démarrer SAS) |
| `didReceiveVerificationData` | `comparing(data)` |
| `didFinish` | `verified` |
| `didCancel` | `cancelled`, depuis tout état |
| `didFail` | `failed`, depuis tout état |

Une commande appelée hors de son état valide lève `MatrixError.unexpected(message:details:)` avec
un message nommant la commande et l'état, sans aucun appel amont. Un callback incohérent avec
l'état courant, hors `didCancel`/`didFail`, laisse l'état inchangé.

### 6.2 Implémentation

- **Ordre des callbacks.** Le delegate amont est synchrone. Un `actor` imposerait un `Task {}` par
  callback, sans garantie d'ordre. L'état courant et la liste des continuations abonnées sont donc
  protégés par un `Mutex` (`Synchronization`, iOS 18 / macOS 15) ; la réduction et la diffusion
  sont faites de façon synchrone dans le callback. Chaque nouvel abonné reçoit l'état courant, puis
  les changements.
- **Obtention du contrôleur.** Le delegate doit être posé avant qu'une demande n'arrive.
  `getSessionVerificationController()` exige l'identité de l'utilisateur dans le store local (§2.8) :
  il est tenté à la création de la session, sans bloquer ni faire échouer celle-ci, puis retenté à
  chaque passage de la sync à `.running` et à chaque commande tant qu'il n'a pas réussi. Une
  commande dont la tentative échoue lève l'erreur mappée. Le contrôleur et son delegate sont retenus par
  `RustSessionVerification` pour la durée de la session.

## 7. Récupération et sauvegarde

- `enableRecovery` appelle l'amont avec `passphrase: nil`, adapte le listener de progression vers
  la closure, et enveloppe la chaîne renvoyée dans `RecoveryKey`.
- `resetRecoveryKey` renvoie une nouvelle `RecoveryKey`.
- `recover(with:)` transmet la chaîne telle quelle ; l'amont normalise.

### 7.1 Erreurs

| Amont | Public |
| --- | --- |
| `SecretStorage` pendant `recover(with:)`, sauf message « could not have been found » | `.encryption(.invalidRecoveryKey)` |
| `SecretStorage` « could not have been found » (récupération non configurée) | `.unexpected(message:details:)` |
| `BackupExistsOnServer` | `.unexpected(message:details:)` |
| `Import`, `SecretStorage` hors `recover(with:)` | `.unexpected(message:details:)` |
| `Client(source:)` | mappage existant d'`ErrorMapper` |

« Une sauvegarde existe déjà » se lit avant d'agir : `recoveryState == .incomplete` ou
`backupExistsOnServer()`. L'erreur ne survient que dans une course, où `.unexpected` suffit.

### 7.2 Guide de décision (article DocC)

| Condition | Proposition à l'utilisateur |
| --- | --- |
| `verificationStatus == .unverified` et `hasDevicesToVerifyAgainst()` | Vérifier avec un autre appareil ; en second choix, la clé de récupération |
| `recoveryState == .incomplete` | Saisir la clé de récupération |
| `recoveryState == .disabled` et `!backupExistsOnServer()` | Activer la récupération |
| Déconnexion demandée, `isLastDevice()` et récupération désactivée | Avertir de la perte de l'historique chiffré |

## 8. Session

### 8.1 Restauration sans URL

Le chemin de restauration de `RustMatrixClient` est extrait dans `SessionRestorer` (interne), qui
charge `MatrixSessionData`, construit le client avec `homeserverURL` **persisté**, restaure, et
applique la purge existante en cas de refus d'authentification. `Matrix.restoreSession(storage:)`
et `MatrixClient.restoreSession()` l'utilisent tous deux. Ce second appel cesse donc d'utiliser
l'URL du client : correction (`fix:`), sans changement de signature.

### 8.2 `authState`

- `AuthDelegate` (conforme à `ClientDelegate`) est posé via `client.setDelegate(delegate:)` à la
  création de la session ; le délégué et le `TaskHandle` renvoyé sont retenus par la session.
- État initial `.signedIn`. Diffusion identique à §6.2 : `Mutex`, valeur courante d'abord,
  `.bufferingNewest(1)`.
- **Hard logout** (`isSoftLogout == false`) : arrêt de la sync, `persistence.clear()`,
  `localStore.purge()`, **puis** passage à `.signedOut`. Une purge en échec est avalée ; l'état
  passe tout de même à `.signedOut`. Traité une seule fois, même si le callback se répète.
- **Soft logout** : passage à `.softLoggedOut`, rien n'est effacé.
- `.signedOut` est terminal : aucun callback ultérieur ne le quitte.

### 8.3 `logout()` après une déconnexion serveur

- Depuis `.softLoggedOut` : l'échec serveur `unknownToken` est ignoré, le nettoyage local a lieu,
  l'état passe à `.signedOut`, aucune erreur n'est levée. Toute autre erreur serveur conserve le
  comportement 0.1 (nettoyage local, puis erreur levée).
- Depuis `.signedOut` : aucun effet, aucune erreur.
- Tout `logout()` réussi fait passer `authState` à `.signedOut`.

### 8.4 Idempotence de `SyncController.start()`

L'amont est idempotent (§2.9) : aucune garde n'est ajoutée. Le contrat est documenté sur
``SyncController/start()`` — « Calling `start()` while syncing is already running has no effect;
after `.offline`, `.error` or `.terminated` it starts syncing again. » — et épinglé par un test
d'intégration (deux `start()` successifs, l'état reste `.running` sans repasser par `.idle`).

## 9. Timeline : chaînes visibles en anglais

`TimelineMapper` dérive `reason` de `EncryptedMessage.megolmV1AesSha2(…, cause: UtdCause)`
(module `matrix_sdk_crypto`), en anglais, une phrase par cause. Les autres variantes
(`olmV1Curve25519AesSha2`, `unknown`) reçoivent la phrase de `.unknown`. La signature publique ne
change pas ; le texte exact est fixé par les tests.

| `UtdCause` | Sens de la phrase |
| --- | --- |
| `unknown` | The message could not be decrypted. |
| `sentBeforeWeJoined` | Sent before you joined the room. |
| `verificationViolation` | The sender's verified identity has changed. |
| `unsignedDevice` | Sent from a device its owner has not verified. |
| `unknownDevice` | Sent from an unknown device. |
| `historicalMessageAndBackupIsDisabled` | Sent before this device signed in, and key backup is off. |
| `historicalMessageAndDeviceIsUnverified` | Sent before this device signed in; verify this device to read it. |
| `withheldForUnverifiedOrInsecureDevice` | The sender does not share keys with unverified devices. |
| `withheldBySender` | The sender withheld the keys for this message. |

Même défaut, même correction pour les autres chaînes visibles de `TimelineMapper` : motifs
`SendState.failed(reason:)` tirés de `QueueWedgeError`, et descriptions `.unsupported` (« début de
timeline », « événement non pris en charge », « expéditeur invalide »).

## 10. Mocks

Style identique à l'existant : classes `@unchecked Sendable` protégées par `NSLock`, flux créés par
`makeStream`, méthodes `emit…`/`finish()`, propriétés d'injection.

| Mock | Contenu |
| --- | --- |
| `MockMatrixClient` (nouveau) | `homeserver`, `loginResult: Result<MockMatrixSession, MatrixError>`, `restoreResult: Result<MockMatrixSession?, MatrixError>`, `loginAttempts: [Credentials]` |
| `MockEncryptionService` (nouveau) | `emitVerificationStatus/BackupState/RecoveryState(_:)`, `finish()` ; `isLastDeviceResult`, `hasDevicesToVerifyAgainstResult`, `backupExistsOnServerResult`, `recoveryKey` ; une erreur injectable par commande ; `recoverAttempts: [String]` ; `progressSteps: [RecoveryProgress]` rejoués dans la closure |
| `MockSessionVerification` (nouveau) | `emit(_:)`, `finish()` ; une erreur injectable par commande ; `calls: [Command]`. Ne fait pas tourner le réducteur : le test fixe l'état |
| `MockMatrixSession` | `encryption` (`MockEncryptionService` par défaut), `emitAuthState(_:)`, `logoutError: MatrixError?` |
| `MockTimeline` | `sendError` scindé en `sendError` (envoi) et `paginationError` (pagination) — **cassant** |

`Matrix.restoreSession(storage:)` étant statique, `TestingWithMocks.md` montre comment l'injecter
sous forme de closure `() async throws -> (any MatrixSession)?`. Pas de protocole dédié.

## 11. Vérifications amont

Trois questions ont été tranchées par lecture du source amont (§2.8 à §2.10). Restent deux points
qui ne se vérifient que contre un vrai serveur ; ils sont couverts par la suite d'intégration, pas
par une tâche préalable :

| Question | Test d'intégration | Conséquence si la réponse est non |
| --- | --- | --- |
| L'amorçage automatique du cross-signing réussit-il sans UIAA sur le homeserver de test ? | Vérification croisée (§12, cas 1) sur un compte neuf | Documenter la limite ; l'API explicite d'amorçage devient un candidat du palier suivant |
| Le message d'une mauvaise clé correspond-il bien à §2.10 ? | Récupération (§12, cas 2) | Corriger le mappage de §7.1 |

## 12. Tests

TDD, Swift Testing uniquement.

- **Core** : chaque ligne des tableaux de §6.1 ; commandes hors état ; callbacks incohérents ;
  demande entrante pendant un flux actif ; masquage de `RecoveryKey` ; mocks (erreurs scindées de
  `MockTimeline`, `logoutError`, rejeu de `progressSteps`).
- **Rust**, via fakes `EncryptionDriving`, `VerificationControllerDriving`, `SyncServiceDriving` :
  mappers d'état, de progression et d'erreur ; valeur courante émise en premier ; ordre des
  callbacks et abonnés multiples ; retenue du contrôleur et relance de son obtention ; purge
  **avant** `.signedOut` et traitement unique du hard logout ; `logout()` après soft logout et
  après `.signedOut` ; relance de l'obtention du contrôleur ; restauration avec l'URL persistée ;
  chaînes de `TimelineMapper`.
- **Intégration** (homeserver réel, désactivée par défaut) :
  1. deux sessions du même utilisateur dans des répertoires distincts — B demande, A accepte, SAS,
     approbations croisées, `verificationStatus == .verified` des deux côtés ;
  2. A active la récupération ; B récupère avec la clé et devient vérifié ; une mauvaise clé lève
     `.encryption(.invalidRecoveryKey)` ;
  3. `POST /_matrix/client/v3/logout/all` brut via `URLSession`, avec un jeton obtenu par une
     connexion brute séparée — la session observée passe à `.signedOut` et son store a disparu ;
  4. `Matrix.restoreSession(storage:)` restaure sans URL ;
  5. deux `start()` successifs laissent la sync `.running`.

Critères : `swift test --skip MatrixClientKitIntegrationTests` vert,
`swift format lint --recursive --strict Sources Tests` propre, CI verte (build iOS compris), suite
d'intégration verte avant publication.

## 13. Documentation

- **README** : section Scope ; feuille de route (0.2 sans QR ; vérification d'autres utilisateurs
  et reset d'identité reportés) ; une ligne recommandant `MatrixError.isRetryable` plutôt qu'un
  mappage maison.
- **DocC** : article `VerificationAndRecovery.md` (guide de décision de §7.2, flux SAS complet) ;
  nouveaux types dans les Topics ; `TestingWithMocks.md` mis à jour.
- **Spec 0.1** : §6.6 et §12 corrigés — QR retiré, raison indiquée, renvoi vers cette spec.
- Langue : anglais pour tout ce que lit un consommateur ; commentaires internes en français.

## 14. Publication 0.2.0

**CHANGELOG**

- *Breaking* : exigences `encryption` et `authState` ajoutées à `MatrixSession` ;
  `MockTimeline.sendError` scindé en `sendError` et `paginationError` ;
  `SampleData.roomSummary` gagne le paramètre `membership:` et ses fixtures « Salon » deviennent
  « Lounge » (introduit par un commit étiqueté à tort `docs:`).
- *Added* : service de chiffrement, vérification de session SAS, récupération et sauvegarde,
  `authState`, `Matrix.restoreSession(storage:)`, `MockMatrixClient`, `MockEncryptionService`,
  `MockSessionVerification`, `MockMatrixSession.logoutError`.
- *Fixed* : la restauration utilise l'URL persistée ; motif UTD en anglais et explicite.
- *Changed* : le cross-signing est amorcé automatiquement à la connexion ; idempotence de
  `SyncController.start()` documentée.
- *Fixed* (suite) : toutes les chaînes visibles de la timeline sont en anglais.

**Étapes** : `PackageInfo.version = "0.2.0"`, suite d'intégration verte, tag `0.2.0` poussé,
release GitHub publiée. Type de commit fidèle au contenu : un commit qui change une API publique
n'est jamais un `docs:`.

## 15. Risques et parades

| Risque | Parade |
| --- | --- |
| Contrôleur de vérification indisponible avant la sync : demandes entrantes perdues | Relance à chaque passage `.running` et à chaque commande |
| Amorçage du cross-signing refusé par un serveur exigeant l'UIAA | Suite d'intégration sur compte neuf ; limite documentée |
| Mappage de la mauvaise clé fondé sur un message amont | Épinglé par test unitaire et par la suite d'intégration |
| Callbacks amont réordonnés | Réduction synchrone sous `Mutex`, jamais de `Task` par callback |
| Purge concurrente d'un store encore ouvert par le client | Arrêt de la sync avant purge, comme `logout()` en 0.1 |
| Changements cassants mal signalés | Rubrique *Breaking* du CHANGELOG, vérifiée dans la tâche de publication |
