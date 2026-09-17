# MatrixClientKit 0.2 — Plan d'implémentation

> **Pour les agents :** SOUS-SKILL REQUIS — utiliser `superpowers:subagent-driven-development`
> (recommandé) ou `superpowers:executing-plans` pour exécuter ce plan tâche par tâche. Les étapes
> utilisent la syntaxe à cases à cocher (`- [ ]`) pour le suivi.

**Goal :** livrer MatrixClientKit 0.2.0 — chiffrement pilotable (états observables, vérification de
session SAS, récupération et sauvegarde), déconnexion serveur observable, restauration sans URL,
nouveaux mocks, chaînes visibles en anglais.

**Architecture :** aucun nouveau module. Les protocoles publics, les modèles et le réducteur de
vérification (logique pure) vont dans `MatrixClientKitCore` ; les implémentations adossées au SDK
vont dans `MatrixClientKitRust`, derrière des coutures `*Driving` qui les rendent testables sans
binaire ; les doubles vont dans `MatrixClientKitMocks`. L'état partagé entre callbacks amont
synchrones et abonnés est tenu par un `StateBroadcaster` protégé par `Mutex`.

**Tech Stack :** Swift 6.2 (mode 6, strict concurrency), Swift Testing, SPM, module
`Synchronization` (`Mutex`), `matrix-rust-components-swift` `26.09.07` (inchangé).

**Spec :** `docs/superpowers/specs/2026-09-17-matrixclientkit-v0.2-design.md` (à lire en entier ;
la spec 0.1 `2026-09-13-matrixclientkit-design.md` reste la référence pour ce qui n'y est pas
redit). Brief d'origine : `docs/v0.2-brief.md`.

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
- Langue : anglais pour tout ce que lit un consommateur (commentaires de doc `///` de l'API
  publique, chaînes renvoyées à l'application, README, DocC, CHANGELOG) ; commentaires internes
  d'implémentation en français, comme le code existant. Messages de commit en français.
- Type de commit fidèle au contenu : un commit qui change une API publique n'est jamais `docs:`.
- Chaque commit se termine par la ligne `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- Conversions numériques depuis l'amont : toujours `Int(clamping:)`, jamais `Int(_:)`.
- Collisions de noms : `BackupState`, `RecoveryState`, `VerificationState` existent dans les deux
  modules ; dans `MatrixClientKitRust` et ses tests, toujours qualifier (`MatrixRustSDK.BackupState`,
  `MatrixClientKitCore.BackupState`).
- Ne jamais pousser, taguer ni publier sans l'accord explicite de l'utilisateur (Task 15).

---

## Structure des fichiers

```
Sources/
  MatrixClientKitCore/
    Models/Encryption.swift                     // NOUVEAU — VerificationStatus, RecoveryState, BackupState, RecoveryProgress, RecoveryKey
    Models/SessionVerification.swift            // NOUVEAU — SessionVerificationState, VerificationRequest, SASData, SASEmoji
    Models/SessionVerificationReducer.swift     // NOUVEAU — VerificationEvent, VerificationCommand, réducteur (package)
    Models/AuthState.swift                      // NOUVEAU
    Services/EncryptionService.swift            // NOUVEAU — protocole + surcharge de commodité
    Services/SessionVerification.swift          // NOUVEAU — protocole
    Services/MatrixSession.swift                // MODIFIÉ — encryption, authState, doc de logout
    Services/SyncController.swift               // MODIFIÉ — doc d'idempotence de start()
    Errors/MatrixError.swift                    // MODIFIÉ — errorDescription en anglais
  MatrixClientKitRust/
    Bridge/StateBroadcaster.swift               // NOUVEAU — état courant diffusé sous Mutex
    Bridge/FFIStream.swift                      // MODIFIÉ — ffiStateStream (valeur courante d'abord)
    Bridge/EncryptionMapper.swift               // NOUVEAU — états, progression, erreurs de récupération
    Bridge/EncryptionDriving.swift              // NOUVEAU — couture sur Encryption
    Bridge/VerificationControllerDriving.swift  // NOUVEAU — couture sur SessionVerificationController
    Bridge/VerificationMapper.swift             // NOUVEAU — demande et données SAS
    Bridge/AuthDelegate.swift                   // NOUVEAU — ClientDelegate → SessionLifecycle
    Bridge/TimelineMapper.swift                 // MODIFIÉ — chaînes anglaises, motif UTD par cause
    Bridge/SessionMapper.swift                  // MODIFIÉ — messages anglais
    RustEncryptionService.swift                 // NOUVEAU
    RustSessionVerification.swift               // NOUVEAU — + VerificationDelegateAdapter
    SessionLifecycle.swift                      // NOUVEAU — authState, hard/soft logout, logout()
    SessionRestorer.swift                       // NOUVEAU — construction du client persistant, restauration
    RustMatrixSession.swift                     // MODIFIÉ — branchement des nouveaux services
    RustMatrixClient.swift                      // MODIFIÉ — délègue à SessionRestorer
  MatrixClientKitMocks/
    MockEncryptionService.swift                 // NOUVEAU
    MockSessionVerification.swift               // NOUVEAU
    MockMatrixClient.swift                      // NOUVEAU
    MockMatrixSession.swift                     // MODIFIÉ — encryption, authState, logoutError
    MockTimeline.swift                          // MODIFIÉ — paginationError (cassant)
  MatrixClientKit/
    MatrixClientKit.swift                       // MODIFIÉ — Matrix.restoreSession(storage:)
    Documentation.docc/VerificationAndRecovery.md  // NOUVEAU
    Documentation.docc/MatrixClientKit.md       // MODIFIÉ
    Documentation.docc/TestingWithMocks.md      // MODIFIÉ
    Documentation.docc/GettingStarted.md        // MODIFIÉ
Tests/
  MatrixClientKitCoreTests/EncryptionModelTests.swift              // NOUVEAU
  MatrixClientKitCoreTests/SessionVerificationReducerTests.swift   // NOUVEAU
  MatrixClientKitCoreTests/EncryptionMockTests.swift               // NOUVEAU
  MatrixClientKitCoreTests/MockTests.swift                         // MODIFIÉ
  MatrixClientKitCoreTests/MatrixErrorTests.swift                  // MODIFIÉ
  MatrixClientKitRustTests/StateBroadcasterTests.swift             // NOUVEAU
  MatrixClientKitRustTests/FFIStreamTests.swift                    // MODIFIÉ
  MatrixClientKitRustTests/EncryptionMapperTests.swift             // NOUVEAU
  MatrixClientKitRustTests/EncryptionServiceTests.swift            // NOUVEAU
  MatrixClientKitRustTests/SessionVerificationTests.swift          // NOUVEAU
  MatrixClientKitRustTests/SessionLifecycleTests.swift             // NOUVEAU
  MatrixClientKitRustTests/SessionRestorerTests.swift              // NOUVEAU
  MatrixClientKitRustTests/MessageContentTests.swift               // MODIFIÉ
  MatrixClientKitRustTests/TimelineStringsTests.swift              // NOUVEAU
  MatrixClientKitIntegrationTests/IntegrationSupport.swift         // NOUVEAU — helpers extraits
  MatrixClientKitIntegrationTests/LoginAndSyncTests.swift          // MODIFIÉ — utilise les helpers
  MatrixClientKitIntegrationTests/EncryptionAndSessionTests.swift  // NOUVEAU
  MatrixClientKitIntegrationTests/README.md                        // MODIFIÉ
README.md, CHANGELOG.md                                            // MODIFIÉS
docs/superpowers/specs/2026-09-13-matrixclientkit-design.md        // MODIFIÉ — QR retiré
Sources/MatrixClientKitCore/PackageInfo.swift                      // MODIFIÉ — 0.2.0
```

Ordre des tâches : Core (1–3) → pont Rust (4–8) → branchement (9–10) → mocks et chaînes (11–12) →
intégration (13) → documentation (14) → publication (15). Chaque tâche laisse le package compilable
et la suite unitaire verte.

---

### Task 1 : Modèles de chiffrement

**Files:**
- Create: `Sources/MatrixClientKitCore/Models/Encryption.swift`
- Test: `Tests/MatrixClientKitCoreTests/EncryptionModelTests.swift`

**Interfaces:**
- Consumes : rien.
- Produces : `public enum VerificationStatus { unknown, verified, unverified }`,
  `public enum RecoveryState { unknown, enabled, disabled, incomplete }`,
  `public enum BackupState { unknown, creating, enabling, resuming, enabled, downloading, disabling }`,
  `public enum RecoveryProgress { starting, creatingBackup, creatingRecoveryKey, backingUp(uploaded: Int, total: Int), roomKeyUploadError, done }`,
  `public struct RecoveryKey { public let rawValue: String; public init(rawValue: String) }` —
  tous `Sendable, Hashable`.

- [ ] **Step 1 : Écrire le test qui échoue**

```swift
import Testing
import MatrixClientKitCore

@Test func recoveryKeyNeverAppearsInItsDescriptions() {
    let key = RecoveryKey(rawValue: "EsTc 1234 abcd")

    // Une clé interpolée dans un log ne doit jamais s'y retrouver en clair.
    #expect(!"\(key)".contains("EsTc"))
    #expect(!String(reflecting: key).contains("EsTc"))
    #expect(key.rawValue == "EsTc 1234 abcd")
}

@Test func recoveryKeysCompareByValue() {
    #expect(RecoveryKey(rawValue: "a") == RecoveryKey(rawValue: "a"))
    #expect(RecoveryKey(rawValue: "a") != RecoveryKey(rawValue: "b"))
}
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `swift test --filter EncryptionModelTests`
Expected: échec de compilation, `cannot find 'RecoveryKey' in scope`.

- [ ] **Step 3 : Implémenter**

```swift
import Foundation

/// Whether this device is verified, that is, signed by the user's cross-signing identity.
public enum VerificationStatus: Sendable, Hashable {
    /// Not known yet — typically until the first sync has loaded the user's identity.
    case unknown
    /// This device is verified: other clients trust the messages it sends.
    case verified
    /// This device is not verified. Verify it against another device, or enter the recovery key.
    case unverified
}

/// The state of recovery: the server-side storage of the user's secrets, protected by a
/// recovery key.
public enum RecoveryState: Sendable, Hashable {
    /// Not known yet.
    case unknown
    /// Recovery is set up, and this device holds every secret.
    case enabled
    /// Recovery is not set up for this account.
    case disabled
    /// Recovery is set up, but this device lacks the secrets: ask the user for the recovery key.
    case incomplete
}

/// The state of the server-side backup of room keys.
public enum BackupState: Sendable, Hashable {
    /// Not known yet.
    case unknown
    /// A new backup is being created.
    case creating
    /// An existing backup is being enabled on this device.
    case enabling
    /// A backup enabled in a previous launch is being resumed.
    case resuming
    /// The backup is active: new room keys are uploaded.
    case enabled
    /// Room keys are being downloaded from the backup.
    case downloading
    /// The backup is being disabled.
    case disabling
}

/// The progress of ``EncryptionService/enableRecovery(waitForBackupUpload:progress:)``.
public enum RecoveryProgress: Sendable, Hashable {
    /// The operation started.
    case starting
    /// The key backup is being created.
    case creatingBackup
    /// The recovery key is being created.
    case creatingRecoveryKey
    /// Room keys are being uploaded: `uploaded` out of `total`.
    case backingUp(uploaded: Int, total: Int)
    /// Uploading room keys failed. Recovery is set up, but the backup is incomplete.
    case roomKeyUploadError
    /// Recovery is set up. The key is the operation's return value, never part of the progress.
    case done
}

/// A recovery key: the secret that restores a user's encryption keys on a new device.
///
/// Its description is redacted, so that interpolating or printing a key never leaks it into logs.
/// Read ``rawValue`` to show it to the user.
public struct RecoveryKey: Sendable, Hashable {
    /// The key, as it should be shown to the user.
    public let rawValue: String

    /// Wraps a recovery key.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension RecoveryKey: CustomStringConvertible, CustomDebugStringConvertible {
    /// Redacted description: never exposes the key.
    public var description: String { "RecoveryKey(<redacted>)" }

    /// Redacted description: never exposes the key.
    public var debugDescription: String { description }
}
```

- [ ] **Step 4 : Lancer les tests**

Run: `swift test --filter EncryptionModelTests`
Expected: PASS (2 tests).

- [ ] **Step 5 : Lint et commit**

```bash
swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKitCore/Models/Encryption.swift Tests/MatrixClientKitCoreTests/EncryptionModelTests.swift
git commit -m "feat: modèles de chiffrement et clé de récupération masquée

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2 : Vérification — modèles et réducteur

**Files:**
- Create: `Sources/MatrixClientKitCore/Models/SessionVerification.swift`
- Create: `Sources/MatrixClientKitCore/Models/SessionVerificationReducer.swift`
- Test: `Tests/MatrixClientKitCoreTests/SessionVerificationReducerTests.swift`

**Interfaces:**
- Consumes : `DeviceID` (existant).
- Produces :
  - `public enum SessionVerificationState { idle, incomingRequest(VerificationRequest), waitingForOtherDevice, ready, startingSAS, comparing(SASData), confirming, verified, cancelled, failed; public var isFinished: Bool }`
  - `public struct VerificationRequest: Identifiable { id: String; deviceID: DeviceID; deviceDisplayName: String?; firstSeen: Date }` avec `public init(id:deviceID:deviceDisplayName:firstSeen:)`
  - `public enum SASData { emojis([SASEmoji]), decimals([UInt16]) }`
  - `public struct SASEmoji { symbol: String; description: String; index: Int? }` avec `public init(symbol:description:index:)`
  - `package enum VerificationEvent { receivedRequest(VerificationRequest), otherDeviceAccepted, sasStarted, receivedSASData(SASData), finished, cancelled, failed, requestSent, startSASSent, approvalSent, cancelSent }`
  - `package enum VerificationCommand: String { requestVerification, accept, startSAS, approve, decline, cancel }`
  - `package enum SessionVerificationReducer { static func reduce(_: SessionVerificationState, _: VerificationEvent) -> SessionVerificationState; static func isAllowed(_: VerificationCommand, in: SessionVerificationState) -> Bool }`

- [ ] **Step 1 : Écrire les tests qui échouent**

```swift
import Testing
import Foundation
import MatrixClientKitCore

private let request = VerificationRequest(
    id: "flow-1",
    deviceID: DeviceID(rawValue: "PHONE")!,
    deviceDisplayName: "iPhone",
    firstSeen: Date(timeIntervalSince1970: 0)
)

private let otherRequest = VerificationRequest(
    id: "flow-2",
    deviceID: DeviceID(rawValue: "LAPTOP")!,
    deviceDisplayName: nil,
    firstSeen: Date(timeIntervalSince1970: 0)
)

private let emojis = SASData.emojis([SASEmoji(symbol: "🐶", description: "Dog", index: 0)])
private let decimals = SASData.decimals([1234, 5678, 9012])

private let allStates: [SessionVerificationState] = [
    .idle, .incomingRequest(request), .waitingForOtherDevice, .ready, .startingSAS,
    .comparing(emojis), .confirming, .verified, .cancelled, .failed,
]

private let finishedStates: [SessionVerificationState] = [.verified, .cancelled, .failed]

struct Transition: Sendable, CustomTestStringConvertible {
    let from: SessionVerificationState
    let event: VerificationEvent
    let to: SessionVerificationState

    var testDescription: String { "\(from) + \(event) → \(to)" }
}

// Tableau de la spec 0.2, §6.1 : chaque ligne est une transition attendue.
private let transitions: [Transition] = [
    Transition(from: .idle, event: .requestSent, to: .waitingForOtherDevice),
    Transition(from: .verified, event: .requestSent, to: .waitingForOtherDevice),
    Transition(from: .idle, event: .receivedRequest(request), to: .incomingRequest(request)),
    Transition(from: .cancelled, event: .receivedRequest(request), to: .incomingRequest(request)),
    Transition(from: .waitingForOtherDevice, event: .otherDeviceAccepted, to: .ready),
    Transition(from: .incomingRequest(request), event: .otherDeviceAccepted, to: .ready),
    Transition(from: .ready, event: .startSASSent, to: .startingSAS),
    Transition(from: .ready, event: .sasStarted, to: .startingSAS),
    Transition(from: .startingSAS, event: .sasStarted, to: .startingSAS),
    Transition(from: .startingSAS, event: .receivedSASData(emojis), to: .comparing(emojis)),
    Transition(from: .ready, event: .receivedSASData(decimals), to: .comparing(decimals)),
    Transition(from: .comparing(emojis), event: .approvalSent, to: .confirming),
    Transition(from: .confirming, event: .finished, to: .verified),
    Transition(from: .comparing(emojis), event: .finished, to: .verified),
    Transition(from: .ready, event: .cancelSent, to: .cancelled),
    Transition(from: .confirming, event: .cancelled, to: .cancelled),
    Transition(from: .startingSAS, event: .failed, to: .failed),
    Transition(from: .incomingRequest(request), event: .cancelled, to: .cancelled),
]

@Test(arguments: transitions)
func reducerAppliesTheSpecifiedTransition(_ transition: Transition) {
    #expect(SessionVerificationReducer.reduce(transition.from, transition.event) == transition.to)
}

@Test func aRequestDuringAnActiveFlowIsIgnored() {
    // L'amont ne gère qu'un flux : écraser le flux en cours le rendrait inutilisable.
    for state in allStates where state != .idle && !state.isFinished {
        #expect(SessionVerificationReducer.reduce(state, .receivedRequest(otherRequest)) == state)
    }
}

@Test func finishedStatesAreOnlyLeftByANewRequest() {
    let lateEvents: [VerificationEvent] = [
        .otherDeviceAccepted, .sasStarted, .receivedSASData(emojis), .finished, .cancelled, .failed,
        .approvalSent, .startSASSent, .cancelSent,
    ]
    for state in finishedStates {
        for event in lateEvents {
            #expect(SessionVerificationReducer.reduce(state, event) == state, "\(state) + \(event)")
        }
    }
}

@Test func idleIgnoresEverythingButARequest() {
    let events: [VerificationEvent] = [
        .otherDeviceAccepted, .sasStarted, .receivedSASData(emojis), .finished, .cancelled, .failed,
        .approvalSent, .startSASSent, .cancelSent,
    ]
    for event in events {
        #expect(SessionVerificationReducer.reduce(.idle, event) == .idle, "\(event)")
    }
}

@Test func eachCommandIsAllowedOnlyInItsStates() {
    func allowed(_ command: VerificationCommand) -> [SessionVerificationState] {
        allStates.filter { SessionVerificationReducer.isAllowed(command, in: $0) }
    }

    #expect(allowed(.requestVerification) == [.idle, .verified, .cancelled, .failed])
    #expect(allowed(.accept) == [.incomingRequest(request)])
    #expect(allowed(.startSAS) == [.ready])
    #expect(allowed(.approve) == [.comparing(emojis)])
    #expect(allowed(.decline) == [.comparing(emojis)])
    #expect(
        allowed(.cancel) == [
            .incomingRequest(request), .waitingForOtherDevice, .ready, .startingSAS, .comparing(emojis),
            .confirming,
        ])
}

@Test func isFinishedCoversExactlyTheTerminalStates() {
    #expect(allStates.filter(\.isFinished) == finishedStates)
}
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run: `swift test --filter SessionVerificationReducerTests`
Expected: échec de compilation, `cannot find type 'VerificationRequest' in scope`.

- [ ] **Step 3 : Implémenter les modèles publics** — `Sources/MatrixClientKitCore/Models/SessionVerification.swift`

```swift
import Foundation

/// The state of the current device-verification flow. See ``SessionVerification``.
public enum SessionVerificationState: Sendable, Hashable {
    /// No verification in progress.
    case idle
    /// Another of the user's devices asks to verify this one. Call ``SessionVerification/accept()``
    /// or ``SessionVerification/cancel()``.
    case incomingRequest(VerificationRequest)
    /// This device asked for verification and waits for another device to accept.
    case waitingForOtherDevice
    /// Both devices accepted. Call ``SessionVerification/startSAS()``.
    case ready
    /// The short authentication strings are being negotiated.
    case startingSAS
    /// Show these to the user, who compares them with the other device, then calls
    /// ``SessionVerification/approve()`` or ``SessionVerification/decline()``.
    case comparing(SASData)
    /// This device approved and waits for the other device to approve too.
    case confirming
    /// Verification succeeded.
    case verified
    /// Verification was cancelled, on either device.
    case cancelled
    /// Verification failed.
    case failed

    /// True for ``verified``, ``cancelled`` and ``failed``: a new request may start.
    public var isFinished: Bool {
        switch self {
        case .verified, .cancelled, .failed: true
        default: false
        }
    }
}

/// A verification request received from another of the user's devices.
public struct VerificationRequest: Sendable, Hashable, Identifiable {
    /// Identifies the verification flow. Opaque.
    public let id: String
    /// The device asking for verification.
    public let deviceID: DeviceID
    /// The requesting device's display name, when it has one.
    public let deviceDisplayName: String?
    /// When the requesting device was first seen.
    public let firstSeen: Date

    /// Creates a request, for instance in a test.
    public init(id: String, deviceID: DeviceID, deviceDisplayName: String?, firstSeen: Date) {
        self.id = id
        self.deviceID = deviceID
        self.deviceDisplayName = deviceDisplayName
        self.firstSeen = firstSeen
    }
}

/// The short authentication strings both devices display.
public enum SASData: Sendable, Hashable {
    /// Seven emojis to compare.
    case emojis([SASEmoji])
    /// Three numbers to compare, when the other device does not support emojis.
    case decimals([UInt16])
}

/// One emoji of a short authentication string.
public struct SASEmoji: Sendable, Hashable {
    /// The emoji itself.
    public let symbol: String
    /// Its English name, as provided by the Matrix specification.
    public let description: String
    /// Its index (0–63) in the Matrix specification's SAS emoji table, from which an application
    /// can localise ``description``; `nil` when the SDK did not provide it.
    public let index: Int?

    /// Creates an emoji, for instance in a test.
    public init(symbol: String, description: String, index: Int?) {
        self.symbol = symbol
        self.description = description
        self.index = index
    }
}
```

- [ ] **Step 4 : Implémenter le réducteur** — `Sources/MatrixClientKitCore/Models/SessionVerificationReducer.swift`

```swift
/// Ce qui fait évoluer un flux de vérification : un callback du contrôleur amont, ou le succès
/// d'une commande locale.
package enum VerificationEvent: Sendable, Hashable {
    // Callbacks amont (`SessionVerificationControllerDelegate`).
    case receivedRequest(VerificationRequest)
    case otherDeviceAccepted
    case sasStarted
    case receivedSASData(SASData)
    case finished
    case cancelled
    case failed

    // Succès de commandes locales.
    case requestSent
    case startSASSent
    case approvalSent
    case cancelSent
}

/// Les commandes publiques de ``SessionVerification``, pour la validation d'état.
package enum VerificationCommand: String, Sendable, Hashable {
    case requestVerification
    case accept
    case startSAS
    case approve
    case decline
    case cancel
}

/// Machine à états de la vérification de session (spec 0.2, §6.1).
///
/// Fonction pure : elle ne sait rien du SDK, ce qui permet d'en tester chaque transition sans
/// binaire. Un événement incohérent avec l'état courant laisse l'état inchangé — l'amont peut
/// livrer un callback tardif, qui ne doit jamais ranimer un flux terminé.
package enum SessionVerificationReducer {

    package static func reduce(
        _ state: SessionVerificationState,
        _ event: VerificationEvent
    ) -> SessionVerificationState {
        switch event {
        case let .receivedRequest(request):
            return canStartNewFlow(state) ? .incomingRequest(request) : state
        case .requestSent:
            return canStartNewFlow(state) ? .waitingForOtherDevice : state
        case .otherDeviceAccepted:
            switch state {
            case .waitingForOtherDevice, .incomingRequest: return .ready
            default: return state
            }
        case .sasStarted, .startSASSent:
            switch state {
            case .ready, .startingSAS: return .startingSAS
            default: return state
            }
        case let .receivedSASData(data):
            switch state {
            case .ready, .startingSAS, .comparing: return .comparing(data)
            default: return state
            }
        case .approvalSent:
            if case .comparing = state { return .confirming }
            return state
        case .finished:
            switch state {
            case .comparing, .confirming: return .verified
            default: return state
            }
        case .cancelled, .cancelSent:
            return isInFlight(state) ? .cancelled : state
        case .failed:
            return isInFlight(state) ? .failed : state
        }
    }

    package static func isAllowed(_ command: VerificationCommand, in state: SessionVerificationState) -> Bool {
        switch command {
        case .requestVerification:
            return canStartNewFlow(state)
        case .accept:
            if case .incomingRequest = state { return true }
            return false
        case .startSAS:
            return state == .ready
        case .approve, .decline:
            if case .comparing = state { return true }
            return false
        case .cancel:
            return isInFlight(state)
        }
    }

    private static func canStartNewFlow(_ state: SessionVerificationState) -> Bool {
        state == .idle || state.isFinished
    }

    private static func isInFlight(_ state: SessionVerificationState) -> Bool {
        state != .idle && !state.isFinished
    }
}
```

- [ ] **Step 5 : Lancer les tests**

Run: `swift test --filter SessionVerificationReducerTests`
Expected: PASS.

- [ ] **Step 6 : Lint et commit**

```bash
swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKitCore/Models/SessionVerification.swift Sources/MatrixClientKitCore/Models/SessionVerificationReducer.swift Tests/MatrixClientKitCoreTests/SessionVerificationReducerTests.swift
git commit -m "feat: modèles et machine à états de la vérification de session

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3 : Protocoles de service, `AuthState` et mocks du chiffrement

**Files:**
- Create: `Sources/MatrixClientKitCore/Services/EncryptionService.swift`
- Create: `Sources/MatrixClientKitCore/Services/SessionVerification.swift`
- Create: `Sources/MatrixClientKitCore/Models/AuthState.swift`
- Create: `Sources/MatrixClientKitMocks/MockEncryptionService.swift`
- Create: `Sources/MatrixClientKitMocks/MockSessionVerification.swift`
- Test: `Tests/MatrixClientKitCoreTests/EncryptionMockTests.swift`

**Interfaces:**
- Consumes : types des Tasks 1 et 2.
- Produces :
  - `public protocol EncryptionService: Sendable` — `verificationStatus`, `backupState`, `recoveryState` (`AsyncStream`), `sessionVerification: any SessionVerification`, `isLastDevice()`, `hasDevicesToVerifyAgainst()`, `backupExistsOnServer()` (`async throws -> Bool`), `enableRecovery(waitForBackupUpload: Bool, progress: @escaping @Sendable (RecoveryProgress) -> Void) async throws -> RecoveryKey`, `recover(with key: String) async throws`, `resetRecoveryKey() async throws -> RecoveryKey`, `disableRecovery() async throws`, `enableBackups() async throws` ; extension `enableRecovery(progress:)`.
  - `public protocol SessionVerification: Sendable` — `state: AsyncStream<SessionVerificationState>`, `requestVerification()`, `accept()`, `startSAS()`, `approve()`, `decline()`, `cancel()` (tous `async throws`).
  - `public enum AuthState { signedIn, softLoggedOut, signedOut }`.
  - `public final class MockEncryptionService` et `public final class MockSessionVerification` (détail dans le code).

- [ ] **Step 1 : Écrire les tests qui échouent**

```swift
import Testing
import Foundation
import MatrixClientKitCore
import MatrixClientKitMocks

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [RecoveryProgress] = []

    func append(_ step: RecoveryProgress) { lock.withLock { steps.append(step) } }
    var all: [RecoveryProgress] { lock.withLock { steps } }
}

@Test func mockEncryptionReplaysProgressThenReturnsTheKey() async throws {
    let encryption = MockEncryptionService()
    encryption.progressSteps = [.starting, .backingUp(uploaded: 1, total: 2), .done]
    encryption.recoveryKey = RecoveryKey(rawValue: "clé")
    let log = ProgressLog()

    let key = try await encryption.enableRecovery { log.append($0) }

    #expect(key.rawValue == "clé")
    #expect(log.all == [.starting, .backingUp(uploaded: 1, total: 2), .done])
    #expect(encryption.enableRecoveryCallCount == 1)
}

@Test func mockEncryptionRecordsRecoveryAttemptsAndCanFail() async {
    let encryption = MockEncryptionService()
    encryption.recoverError = .encryption(.invalidRecoveryKey)

    await #expect(throws: MatrixError.encryption(.invalidRecoveryKey)) {
        try await encryption.recover(with: "mauvaise")
    }
    #expect(encryption.recoverAttempts == ["mauvaise"])
}

@Test func mockEncryptionQueriesReturnTheirInjectedResult() async throws {
    let encryption = MockEncryptionService()
    encryption.isLastDeviceResult = .success(true)
    encryption.backupExistsOnServerResult = .failure(.network(.offline))

    #expect(try await encryption.isLastDevice())
    await #expect(throws: MatrixError.network(.offline)) {
        try await encryption.backupExistsOnServer()
    }
}

@Test func mockEncryptionStreamsDeliverEmittedStates() async {
    let encryption = MockEncryptionService()
    var status = encryption.verificationStatus.makeAsyncIterator()
    var recovery = encryption.recoveryState.makeAsyncIterator()
    var backup = encryption.backupState.makeAsyncIterator()

    encryption.emitVerificationStatus(.unverified)
    encryption.emitRecoveryState(.incomplete)
    encryption.emitBackupState(.downloading)

    #expect(await status.next() == .unverified)
    #expect(await recovery.next() == .incomplete)
    #expect(await backup.next() == .downloading)

    encryption.finish()
    #expect(await status.next() == nil)
}

@Test func mockSessionVerificationRecordsCallsAndFailsOnDemand() async {
    let verification = MockSessionVerification()
    verification.setError(.network(.timeout), for: .approve)

    try? await verification.requestVerification()
    await #expect(throws: MatrixError.network(.timeout)) {
        try await verification.approve()
    }

    #expect(verification.calls == [.requestVerification, .approve])
}

@Test func mockSessionVerificationDeliversEmittedStates() async {
    let verification = MockSessionVerification()
    var iterator = verification.state.makeAsyncIterator()

    verification.emit(.ready)
    #expect(await iterator.next() == .ready)

    verification.finish()
    #expect(await iterator.next() == nil)
}
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run: `swift test --filter EncryptionMockTests`
Expected: échec de compilation, `cannot find 'MockEncryptionService' in scope`.

- [ ] **Step 3 : Écrire `AuthState`** — `Sources/MatrixClientKitCore/Models/AuthState.swift`

```swift
/// Whether a session is still authenticated with its homeserver. See ``MatrixSession/authState``.
public enum AuthState: Sendable, Hashable {
    /// The session is authenticated.
    case signedIn
    /// The homeserver expired the session, but lets this device sign in again without losing its
    /// encryption keys. Nothing was erased. Until same-device sign-in is supported, call
    /// ``MatrixSession/logout()`` and sign in again.
    case softLoggedOut
    /// The session is over: the homeserver revoked it, or ``MatrixSession/logout()`` completed.
    /// Everything stored locally for it has been erased.
    case signedOut
}
```

- [ ] **Step 4 : Écrire les protocoles**

`Sources/MatrixClientKitCore/Services/SessionVerification.swift` :

```swift
/// Verifies this device against another of the user's devices, by comparing short authentication
/// strings (SAS).
///
/// The flow is published as a state machine: observe ``state`` and call the command the current
/// state allows. A command called in a state that does not allow it throws
/// ``MatrixError/unexpected(message:details:)`` and does nothing.
///
/// Only one verification runs at a time. A request received while a flow is in progress is
/// ignored.
public protocol SessionVerification: Sendable {
    /// A stream of the flow's state, starting with the current value. Every access opens an
    /// independent subscription.
    var state: AsyncStream<SessionVerificationState> { get }

    /// Asks the user's other devices to verify this one.
    /// Allowed in ``SessionVerificationState/idle`` and after a finished flow.
    func requestVerification() async throws

    /// Accepts the incoming request. Allowed in ``SessionVerificationState/incomingRequest(_:)``.
    func accept() async throws

    /// Starts comparing short authentication strings. Allowed in ``SessionVerificationState/ready``.
    func startSAS() async throws

    /// Confirms that both devices show the same strings.
    /// Allowed in ``SessionVerificationState/comparing(_:)``.
    func approve() async throws

    /// Reports that the strings differ, which cancels the flow.
    /// Allowed in ``SessionVerificationState/comparing(_:)``.
    func decline() async throws

    /// Cancels the flow in progress, or declines an incoming request.
    func cancel() async throws
}
```

`Sources/MatrixClientKitCore/Services/EncryptionService.swift` :

```swift
/// End-to-end encryption: this device's verification, recovery and key backup.
///
/// The three state streams start with the current value, then deliver every change. Every access
/// opens an independent subscription.
public protocol EncryptionService: Sendable {
    /// Whether this device is verified.
    var verificationStatus: AsyncStream<VerificationStatus> { get }
    /// The state of the room-key backup.
    var backupState: AsyncStream<BackupState> { get }
    /// The state of recovery.
    var recoveryState: AsyncStream<RecoveryState> { get }
    /// Verification of this device against another of the user's devices.
    var sessionVerification: any SessionVerification { get }

    /// True when this is the user's only device: signing out without recovery loses the
    /// encrypted history.
    func isLastDevice() async throws -> Bool

    /// True when another verified device exists, which this one can be verified against.
    func hasDevicesToVerifyAgainst() async throws -> Bool

    /// True when a key backup already exists on the server — set up from another device.
    func backupExistsOnServer() async throws -> Bool

    /// Sets up recovery: creates the key backup and the recovery key, and returns the key to show
    /// to the user. It is not stored anywhere else.
    ///
    /// - Parameters:
    ///   - waitForBackupUpload: when true, returns only once every room key is uploaded.
    ///   - progress: called as the operation advances, from an arbitrary thread.
    func enableRecovery(
        waitForBackupUpload: Bool,
        progress: @escaping @Sendable (RecoveryProgress) -> Void
    ) async throws -> RecoveryKey

    /// Restores the user's secrets with their recovery key, which verifies this device.
    ///
    /// - Throws: ``MatrixError/Encryption/invalidRecoveryKey`` when the key is wrong.
    func recover(with key: String) async throws

    /// Replaces the recovery key and returns the new one. The previous key stops working.
    func resetRecoveryKey() async throws -> RecoveryKey

    /// Disables recovery and deletes the key backup from the server.
    func disableRecovery() async throws

    /// Enables the room-key backup without setting up recovery.
    func enableBackups() async throws
}

extension EncryptionService {
    /// Sets up recovery without waiting for room keys to be uploaded.
    public func enableRecovery(
        progress: @escaping @Sendable (RecoveryProgress) -> Void = { _ in }
    ) async throws -> RecoveryKey {
        try await enableRecovery(waitForBackupUpload: false, progress: progress)
    }
}
```

- [ ] **Step 5 : Écrire `MockSessionVerification`** — `Sources/MatrixClientKitMocks/MockSessionVerification.swift`

```swift
import Foundation
import MatrixClientKitCore

/// A drivable ``SessionVerification``.
///
/// It runs no state machine: your test decides every state with ``emit(_:)``, and checks the
/// commands your code called with ``calls``.
public final class MockSessionVerification: SessionVerification, @unchecked Sendable {
    /// A command of ``SessionVerification``.
    public enum Command: Sendable, Hashable {
        case requestVerification
        case accept
        case startSAS
        case approve
        case decline
        case cancel
    }

    private let lock = NSLock()
    private let stream: AsyncStream<SessionVerificationState>
    private let continuation: AsyncStream<SessionVerificationState>.Continuation

    private var _calls: [Command] = []
    private var _errors: [Command: MatrixError] = [:]

    public init() {
        (stream, continuation) = AsyncStream<SessionVerificationState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    public var state: AsyncStream<SessionVerificationState> { stream }

    /// Every command called so far, in order — including those that threw.
    public var calls: [Command] { lock.withLock { _calls } }

    /// Makes `command` throw `error`; pass `nil` to make it succeed again.
    public func setError(_ error: MatrixError?, for command: Command) {
        lock.withLock { _errors[command] = error }
    }

    /// Pushes a state to ``state``.
    public func emit(_ state: SessionVerificationState) {
        continuation.yield(state)
    }

    /// Ends ``state``.
    public func finish() {
        continuation.finish()
    }

    public func requestVerification() async throws { try record(.requestVerification) }
    public func accept() async throws { try record(.accept) }
    public func startSAS() async throws { try record(.startSAS) }
    public func approve() async throws { try record(.approve) }
    public func decline() async throws { try record(.decline) }
    public func cancel() async throws { try record(.cancel) }

    private func record(_ command: Command) throws {
        let error = lock.withLock {
            _calls.append(command)
            return _errors[command]
        }
        if let error { throw error }
    }
}
```

- [ ] **Step 6 : Écrire `MockEncryptionService`** — `Sources/MatrixClientKitMocks/MockEncryptionService.swift`

```swift
import Foundation
import MatrixClientKitCore

/// A drivable ``EncryptionService``: you decide what each state stream emits and what each call
/// returns or throws.
public final class MockEncryptionService: EncryptionService, @unchecked Sendable {
    private let lock = NSLock()

    private let statusStream: AsyncStream<VerificationStatus>
    private let statusContinuation: AsyncStream<VerificationStatus>.Continuation
    private let backupStream: AsyncStream<BackupState>
    private let backupContinuation: AsyncStream<BackupState>.Continuation
    private let recoveryStream: AsyncStream<RecoveryState>
    private let recoveryContinuation: AsyncStream<RecoveryState>.Continuation

    private var _isLastDeviceResult: Result<Bool, MatrixError> = .success(false)
    private var _hasDevicesToVerifyAgainstResult: Result<Bool, MatrixError> = .success(true)
    private var _backupExistsOnServerResult: Result<Bool, MatrixError> = .success(false)
    private var _recoveryKey = RecoveryKey(rawValue: "EsTc aBcD eFgH iJkL mNoP")
    private var _progressSteps: [RecoveryProgress] = [.starting, .done]
    private var _enableRecoveryError: MatrixError?
    private var _recoverError: MatrixError?
    private var _resetRecoveryKeyError: MatrixError?
    private var _disableRecoveryError: MatrixError?
    private var _enableBackupsError: MatrixError?
    private var _recoverAttempts: [String] = []
    private var _enableRecoveryCallCount = 0
    private var _resetRecoveryKeyCallCount = 0
    private var _disableRecoveryCallCount = 0
    private var _enableBackupsCallCount = 0

    public let sessionVerification: any SessionVerification

    public init(sessionVerification: MockSessionVerification = MockSessionVerification()) {
        self.sessionVerification = sessionVerification
        (statusStream, statusContinuation) = AsyncStream<VerificationStatus>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        (backupStream, backupContinuation) = AsyncStream<BackupState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        (recoveryStream, recoveryContinuation) = AsyncStream<RecoveryState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    // MARK: Streams

    public var verificationStatus: AsyncStream<VerificationStatus> { statusStream }
    public var backupState: AsyncStream<BackupState> { backupStream }
    public var recoveryState: AsyncStream<RecoveryState> { recoveryStream }

    /// Pushes a value to ``verificationStatus``.
    public func emitVerificationStatus(_ status: VerificationStatus) { statusContinuation.yield(status) }
    /// Pushes a value to ``backupState``.
    public func emitBackupState(_ state: BackupState) { backupContinuation.yield(state) }
    /// Pushes a value to ``recoveryState``.
    public func emitRecoveryState(_ state: RecoveryState) { recoveryContinuation.yield(state) }

    /// Ends the three state streams.
    public func finish() {
        statusContinuation.finish()
        backupContinuation.finish()
        recoveryContinuation.finish()
    }

    // MARK: Injection

    /// What ``isLastDevice()`` returns or throws. Defaults to `false`.
    public var isLastDeviceResult: Result<Bool, MatrixError> {
        get { lock.withLock { _isLastDeviceResult } }
        set { lock.withLock { _isLastDeviceResult = newValue } }
    }

    /// What ``hasDevicesToVerifyAgainst()`` returns or throws. Defaults to `true`.
    public var hasDevicesToVerifyAgainstResult: Result<Bool, MatrixError> {
        get { lock.withLock { _hasDevicesToVerifyAgainstResult } }
        set { lock.withLock { _hasDevicesToVerifyAgainstResult = newValue } }
    }

    /// What ``backupExistsOnServer()`` returns or throws. Defaults to `false`.
    public var backupExistsOnServerResult: Result<Bool, MatrixError> {
        get { lock.withLock { _backupExistsOnServerResult } }
        set { lock.withLock { _backupExistsOnServerResult = newValue } }
    }

    /// The key returned by ``enableRecovery(waitForBackupUpload:progress:)`` and
    /// ``resetRecoveryKey()``.
    public var recoveryKey: RecoveryKey {
        get { lock.withLock { _recoveryKey } }
        set { lock.withLock { _recoveryKey = newValue } }
    }

    /// The steps replayed, in order, into the progress closure of
    /// ``enableRecovery(waitForBackupUpload:progress:)``.
    public var progressSteps: [RecoveryProgress] {
        get { lock.withLock { _progressSteps } }
        set { lock.withLock { _progressSteps = newValue } }
    }

    /// Makes ``enableRecovery(waitForBackupUpload:progress:)`` throw.
    public var enableRecoveryError: MatrixError? {
        get { lock.withLock { _enableRecoveryError } }
        set { lock.withLock { _enableRecoveryError = newValue } }
    }

    /// Makes ``recover(with:)`` throw.
    public var recoverError: MatrixError? {
        get { lock.withLock { _recoverError } }
        set { lock.withLock { _recoverError = newValue } }
    }

    /// Makes ``resetRecoveryKey()`` throw.
    public var resetRecoveryKeyError: MatrixError? {
        get { lock.withLock { _resetRecoveryKeyError } }
        set { lock.withLock { _resetRecoveryKeyError = newValue } }
    }

    /// Makes ``disableRecovery()`` throw.
    public var disableRecoveryError: MatrixError? {
        get { lock.withLock { _disableRecoveryError } }
        set { lock.withLock { _disableRecoveryError = newValue } }
    }

    /// Makes ``enableBackups()`` throw.
    public var enableBackupsError: MatrixError? {
        get { lock.withLock { _enableBackupsError } }
        set { lock.withLock { _enableBackupsError = newValue } }
    }

    // MARK: Recording

    /// Every key passed to ``recover(with:)``, in order.
    public var recoverAttempts: [String] { lock.withLock { _recoverAttempts } }
    public var enableRecoveryCallCount: Int { lock.withLock { _enableRecoveryCallCount } }
    public var resetRecoveryKeyCallCount: Int { lock.withLock { _resetRecoveryKeyCallCount } }
    public var disableRecoveryCallCount: Int { lock.withLock { _disableRecoveryCallCount } }
    public var enableBackupsCallCount: Int { lock.withLock { _enableBackupsCallCount } }

    // MARK: EncryptionService

    public func isLastDevice() async throws -> Bool { try isLastDeviceResult.get() }
    public func hasDevicesToVerifyAgainst() async throws -> Bool { try hasDevicesToVerifyAgainstResult.get() }
    public func backupExistsOnServer() async throws -> Bool { try backupExistsOnServerResult.get() }

    public func enableRecovery(
        waitForBackupUpload: Bool,
        progress: @escaping @Sendable (RecoveryProgress) -> Void
    ) async throws -> RecoveryKey {
        let (error, steps, key) = lock.withLock {
            _enableRecoveryCallCount += 1
            return (_enableRecoveryError, _progressSteps, _recoveryKey)
        }
        if let error { throw error }
        steps.forEach(progress)
        return key
    }

    public func recover(with key: String) async throws {
        let error = lock.withLock {
            _recoverAttempts.append(key)
            return _recoverError
        }
        if let error { throw error }
    }

    public func resetRecoveryKey() async throws -> RecoveryKey {
        let (error, key) = lock.withLock {
            _resetRecoveryKeyCallCount += 1
            return (_resetRecoveryKeyError, _recoveryKey)
        }
        if let error { throw error }
        return key
    }

    public func disableRecovery() async throws {
        let error = lock.withLock {
            _disableRecoveryCallCount += 1
            return _disableRecoveryError
        }
        if let error { throw error }
    }

    public func enableBackups() async throws {
        let error = lock.withLock {
            _enableBackupsCallCount += 1
            return _enableBackupsError
        }
        if let error { throw error }
    }
}
```

- [ ] **Step 7 : Lancer les tests**

Run: `swift test --filter EncryptionMockTests`
Expected: PASS (6 tests). Puis `swift test --skip MatrixClientKitIntegrationTests` : PASS.

- [ ] **Step 8 : Lint et commit**

```bash
swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKitCore/Services/EncryptionService.swift Sources/MatrixClientKitCore/Services/SessionVerification.swift Sources/MatrixClientKitCore/Models/AuthState.swift Sources/MatrixClientKitMocks/MockEncryptionService.swift Sources/MatrixClientKitMocks/MockSessionVerification.swift Tests/MatrixClientKitCoreTests/EncryptionMockTests.swift
git commit -m "feat: protocoles du service de chiffrement et de la vérification, et leurs mocks

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4 : Diffusion d'état et flux d'état amont

**Files:**
- Create: `Sources/MatrixClientKitRust/Bridge/StateBroadcaster.swift`
- Modify: `Sources/MatrixClientKitRust/Bridge/FFIStream.swift` (ajout en fin de fichier)
- Test: `Tests/MatrixClientKitRustTests/StateBroadcasterTests.swift`
- Test: `Tests/MatrixClientKitRustTests/FFIStreamTests.swift` (ajout en fin de fichier)

**Interfaces:**
- Consumes : `ffiStream` (existant, même fichier), `TaskHandleProtocol` (amont).
- Produces :
  - `final class StateBroadcaster<Value: Sendable & Equatable>: Sendable` — `init(_ initialValue: Value)`, `var value: Value`, `func stream() -> AsyncStream<Value>`, `@discardableResult func update(_ transform: (Value) -> Value) -> Value`, `var subscriberCount: Int`.
  - `func ffiStateStream<Element: Sendable, Listener>(current: @escaping @Sendable () -> Element, makeListener: @escaping @Sendable (@escaping @Sendable (Element) -> Void) -> Listener, subscribe: @escaping @Sendable (Listener) throws -> any TaskHandleProtocol) -> AsyncStream<Element>`

- [ ] **Step 1 : Écrire les tests du diffuseur qui échouent** — `Tests/MatrixClientKitRustTests/StateBroadcasterTests.swift`

```swift
import Testing
import Foundation
@testable import MatrixClientKitRust

@Test func aNewSubscriberReceivesTheCurrentValueFirst() async {
    let broadcaster = StateBroadcaster(1)
    broadcaster.update { _ in 2 }

    var iterator = broadcaster.stream().makeAsyncIterator()
    #expect(await iterator.next() == 2)
}

@Test func updatesReachEverySubscriberInOrder() async {
    let broadcaster = StateBroadcaster(0)
    var first = broadcaster.stream().makeAsyncIterator()
    var second = broadcaster.stream().makeAsyncIterator()
    #expect(await first.next() == 0)
    #expect(await second.next() == 0)

    broadcaster.update { $0 + 1 }
    #expect(await first.next() == 1)
    #expect(await second.next() == 1)

    broadcaster.update { $0 + 1 }
    #expect(await first.next() == 2)
    #expect(await second.next() == 2)
}

@Test func anUnchangedValueIsNotDeliveredAgain() async {
    let broadcaster = StateBroadcaster("idle")
    var iterator = broadcaster.stream().makeAsyncIterator()
    #expect(await iterator.next() == "idle")

    broadcaster.update { $0 }
    broadcaster.update { _ in "running" }

    // Si la mise à jour identique avait été diffusée, `.bufferingNewest(1)` aurait tout de même
    // gardé "running" : on vérifie donc le compte de valeurs livrées par une seconde souscription.
    #expect(await iterator.next() == "running")
    #expect(broadcaster.update { $0 } == "running")
}

@Test func aReleasedSubscriptionIsForgotten() async throws {
    let broadcaster = StateBroadcaster(0)

    do {
        var iterator = broadcaster.stream().makeAsyncIterator()
        _ = await iterator.next()
        #expect(broadcaster.subscriberCount == 1)
    }

    // La terminaison suit la libération du flux : on laisse un tour de boucle s'écouler.
    try await Task.sleep(for: .milliseconds(50))
    #expect(broadcaster.subscriberCount == 0)
}
```

- [ ] **Step 2 : Lancer pour vérifier l'échec**

Run: `swift test --filter StateBroadcasterTests`
Expected: échec de compilation, `cannot find 'StateBroadcaster' in scope`.

- [ ] **Step 3 : Implémenter** — `Sources/MatrixClientKitRust/Bridge/StateBroadcaster.swift`

```swift
import Foundation
import Synchronization

/// Diffuse une valeur d'état courante à un nombre quelconque d'abonnés.
///
/// Chaque abonné reçoit d'abord la valeur courante, puis chaque changement. La transformation et
/// la diffusion ont lieu sous le même verrou, de façon synchrone : deux mises à jour successives,
/// venues de callbacks amont synchrones, sont vues dans cet ordre par tous les abonnés. Un acteur
/// imposerait un `Task` par callback et ne garantirait plus cet ordre — `didStartSasVerification`
/// pourrait alors être appliqué après `didReceiveVerificationData`.
///
/// - Important: `transform` s'exécute sous le verrou. Il ne doit appeler ni code amont ni
///   `update(_:)` : `Mutex` n'est pas réentrant.
final class StateBroadcaster<Value: Sendable & Equatable>: Sendable {
    private struct Storage {
        var value: Value
        var continuations: [UUID: AsyncStream<Value>.Continuation] = [:]
    }

    private let storage: Mutex<Storage>

    init(_ initialValue: Value) {
        storage = Mutex(Storage(value: initialValue))
    }

    var value: Value {
        storage.withLock { $0.value }
    }

    /// Nombre d'abonnements vivants. Exposé pour les tests.
    var subscriberCount: Int {
        storage.withLock { $0.continuations.count }
    }

    func stream() -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream<Value>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()

        storage.withLock { storage in
            continuation.yield(storage.value)
            storage.continuations[id] = continuation
        }

        continuation.onTermination = { [weak self] _ in
            self?.storage.withLock { _ = $0.continuations.removeValue(forKey: id) }
        }
        return stream
    }

    /// Applique `transform` à la valeur courante et diffuse le résultat s'il diffère.
    ///
    /// - Returns: la valeur après transformation.
    @discardableResult
    func update(_ transform: (Value) -> Value) -> Value {
        storage.withLock { storage in
            let newValue = transform(storage.value)
            guard newValue != storage.value else { return newValue }

            storage.value = newValue
            for continuation in storage.continuations.values {
                continuation.yield(newValue)
            }
            return newValue
        }
    }
}
```

- [ ] **Step 4 : Lancer les tests du diffuseur**

Run: `swift test --filter StateBroadcasterTests`
Expected: PASS (4 tests).

- [ ] **Step 5 : Écrire les tests de `ffiStateStream` qui échouent** — ajouter en fin de `Tests/MatrixClientKitRustTests/FFIStreamTests.swift` (les types privés `FakeTaskHandle`, `FakeListener`, `ListenerBox` du fichier sont réutilisés)

```swift
@Test func stateStreamStartsWithTheCurrentValue() async {
    let stream = ffiStateStream(
        current: { 7 },
        makeListener: { FakeListener(emit: $0) },
        subscribe: { _ in FakeTaskHandle() }
    )

    var iterator = stream.makeAsyncIterator()
    #expect(await iterator.next() == 7)
}

@Test func stateStreamNeverOverwritesAFresherListenerValueWithTheCurrentOne() async {
    // Le listener livre 9 pendant l'abonnement, avant la lecture de la valeur courante, qui est
    // périmée (1). Émise après coup, elle remplacerait 9 dans le tampon `.bufferingNewest(1)`.
    let stream = ffiStateStream(
        current: { 1 },
        makeListener: { FakeListener(emit: $0) },
        subscribe: { listener in
            listener.emit(9)
            return FakeTaskHandle()
        }
    )

    var iterator = stream.makeAsyncIterator()
    #expect(await iterator.next() == 9)
}

@Test func stateStreamDeliversListenerUpdatesAfterTheCurrentValue() async {
    let box = ListenerBox()
    let stream = ffiStateStream(
        current: { 1 },
        makeListener: { emit in
            let listener = FakeListener(emit: emit)
            box.store(listener)
            return listener
        },
        subscribe: { _ in FakeTaskHandle() }
    )

    var iterator = stream.makeAsyncIterator()
    #expect(await iterator.next() == 1)
    box.emit(2)
    #expect(await iterator.next() == 2)
}

@Test func failingStateSubscriptionFinishesWithoutValues() async {
    struct SubscriptionFailure: Error {}

    let stream = ffiStateStream(
        current: { 1 },
        makeListener: { FakeListener(emit: $0) },
        subscribe: { (_: FakeListener) -> any TaskHandleProtocol in throw SubscriptionFailure() }
    )

    var received: [Int] = []
    for await value in stream { received.append(value) }
    #expect(received.isEmpty)
}
```

- [ ] **Step 6 : Lancer pour vérifier l'échec**

Run: `swift test --filter FFIStreamTests`
Expected: échec de compilation, `cannot find 'ffiStateStream' in scope`.

- [ ] **Step 7 : Implémenter** — ajouter en fin de `Sources/MatrixClientKitRust/Bridge/FFIStream.swift`, et ajouter `import Synchronization` en tête du fichier

```swift
/// Variante de ``ffiStream`` pour un état dont l'amont expose aussi une lecture synchrone.
///
/// Le flux émet d'abord la valeur courante, puis chaque mise à jour du listener, en
/// `.bufferingNewest(1)`. Sans cette première valeur, un écran ouvert après le dernier changement
/// resterait vide indéfiniment.
///
/// L'abonnement est posé **avant** la lecture de la valeur courante, et celle-ci n'est émise que
/// si le listener n'a encore rien livré. Lue avant l'abonnement, elle pourrait manquer un
/// changement survenu entre les deux ; émise après une valeur du listener, elle remplacerait un
/// état récent par un état périmé.
func ffiStateStream<Element: Sendable, Listener>(
    current: @escaping @Sendable () -> Element,
    makeListener: @escaping @Sendable (@escaping @Sendable (Element) -> Void) -> Listener,
    subscribe: @escaping @Sendable (Listener) throws -> any TaskHandleProtocol
) -> AsyncStream<Element> {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
        let gate = FirstDeliveryGate()
        let listener = makeListener { element in
            gate.deliver { continuation.yield(element) }
        }

        do {
            let handle = try subscribe(listener)
            continuation.onTermination = { _ in
                handle.cancel()
            }
        } catch {
            continuation.finish()
            return
        }

        let initial = current()
        gate.deliverUnlessAlreadyDelivered { continuation.yield(initial) }
    }
}

/// Sérialise les émissions d'un flux d'état et retient si le listener a déjà livré une valeur.
private final class FirstDeliveryGate: Sendable {
    private let hasDelivered = Mutex(false)

    func deliver(_ body: () -> Void) {
        hasDelivered.withLock { hasDelivered in
            hasDelivered = true
            body()
        }
    }

    func deliverUnlessAlreadyDelivered(_ body: () -> Void) {
        hasDelivered.withLock { hasDelivered in
            guard !hasDelivered else { return }
            hasDelivered = true
            body()
        }
    }
}
```

- [ ] **Step 8 : Lancer les tests**

Run: `swift test --filter "FFIStreamTests|StateBroadcasterTests"`
Expected: PASS.

- [ ] **Step 9 : Lint et commit**

```bash
swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKitRust/Bridge/StateBroadcaster.swift Sources/MatrixClientKitRust/Bridge/FFIStream.swift Tests/MatrixClientKitRustTests/StateBroadcasterTests.swift Tests/MatrixClientKitRustTests/FFIStreamTests.swift
git commit -m "feat: diffusion d'état sous verrou et flux d'état amont à valeur initiale

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5 : Mappage du chiffrement

**Files:**
- Create: `Sources/MatrixClientKitRust/Bridge/EncryptionMapper.swift`
- Test: `Tests/MatrixClientKitRustTests/EncryptionMapperTests.swift`

**Interfaces:**
- Consumes : modèles de la Task 1 ; `ErrorMapper.map(_:)` (existant).
- Produces : `enum EncryptionMapper` —
  `static func status(from: MatrixRustSDK.VerificationState) -> VerificationStatus`,
  `static func backupState(from: MatrixRustSDK.BackupState) -> MatrixClientKitCore.BackupState`,
  `static func recoveryState(from: MatrixRustSDK.RecoveryState) -> MatrixClientKitCore.RecoveryState`,
  `static func progress(from: EnableRecoveryProgress) -> RecoveryProgress`,
  `static func error(from: any Error, duringRecover: Bool = false) -> MatrixError`.

Rappel spec §2.10 et §7.1 : une mauvaise clé arrive en `RecoveryError.SecretStorage(errorMessage:)`
(échec MAC ou décodage) ; une récupération jamais configurée arrive dans la **même** variante, avec
un message contenant « could not have been found ». Seul le contexte `recover(with:)` permet de lire
`SecretStorage` comme une clé refusée.

- [ ] **Step 1 : Écrire les tests qui échouent**

```swift
import Testing
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

@Test func verificationStatesAreMapped() {
    #expect(EncryptionMapper.status(from: .unknown) == .unknown)
    #expect(EncryptionMapper.status(from: .verified) == .verified)
    #expect(EncryptionMapper.status(from: .unverified) == .unverified)
}

@Test func backupStatesAreMapped() {
    let pairs: [(MatrixRustSDK.BackupState, MatrixClientKitCore.BackupState)] = [
        (.unknown, .unknown), (.creating, .creating), (.enabling, .enabling), (.resuming, .resuming),
        (.enabled, .enabled), (.downloading, .downloading), (.disabling, .disabling),
    ]
    for (upstream, expected) in pairs {
        #expect(EncryptionMapper.backupState(from: upstream) == expected)
    }
}

@Test func recoveryStatesAreMapped() {
    #expect(EncryptionMapper.recoveryState(from: .unknown) == .unknown)
    #expect(EncryptionMapper.recoveryState(from: .enabled) == .enabled)
    #expect(EncryptionMapper.recoveryState(from: .disabled) == .disabled)
    #expect(EncryptionMapper.recoveryState(from: .incomplete) == .incomplete)
}

@Test func recoveryProgressIsMappedWithoutTheKey() {
    #expect(EncryptionMapper.progress(from: .starting) == .starting)
    #expect(EncryptionMapper.progress(from: .creatingBackup) == .creatingBackup)
    #expect(EncryptionMapper.progress(from: .creatingRecoveryKey) == .creatingRecoveryKey)
    #expect(
        EncryptionMapper.progress(from: .backingUp(backedUpCount: 3, totalCount: 10))
            == .backingUp(uploaded: 3, total: 10))
    #expect(EncryptionMapper.progress(from: .roomKeyUploadError) == .roomKeyUploadError)
    // La clé ne transite que par la valeur de retour : un seul canal pour un secret.
    #expect(EncryptionMapper.progress(from: .done(recoveryKey: "secret")) == .done)
}

@Test func aSecretStorageFailureDuringRecoveryIsAWrongKey() {
    let error = RecoveryError.SecretStorage(errorMessage: "The MAC check for the secret storage key failed")
    #expect(EncryptionMapper.error(from: error, duringRecover: true) == .encryption(.invalidRecoveryKey))
}

@Test func recoveryThatWasNeverSetUpIsNotReportedAsAWrongKey() {
    let error = RecoveryError.SecretStorage(
        errorMessage: "The info about the secret key could not have been found in the account data of the user"
    )
    guard case .unexpected = EncryptionMapper.error(from: error, duringRecover: true) else {
        Issue.record("une récupération non configurée ne doit pas passer pour une mauvaise clé")
        return
    }
}

@Test func aSecretStorageFailureOutsideRecoveryIsUnexpected() {
    let error = RecoveryError.SecretStorage(errorMessage: "The MAC check for the secret storage key failed")
    guard case .unexpected = EncryptionMapper.error(from: error) else {
        Issue.record("hors recover(with:), aucune clé n'a été saisie")
        return
    }
}

@Test func otherRecoveryErrorsAreMapped() {
    guard case .unexpected = EncryptionMapper.error(from: RecoveryError.BackupExistsOnServer) else {
        Issue.record("BackupExistsOnServer se lit dans l'état, l'erreur reste .unexpected")
        return
    }
    guard case .unexpected = EncryptionMapper.error(from: RecoveryError.Import(errorMessage: "x")) else {
        Issue.record("Import doit rester .unexpected")
        return
    }

    let client = RecoveryError.Client(
        source: .MatrixApi(kind: .connectionFailed, code: "", msg: "", details: nil)
    )
    #expect(EncryptionMapper.error(from: client) == .network(.offline))
}

@Test func nonRecoveryErrorsGoThroughTheGeneralMapper() {
    let error = ClientError.MatrixApi(kind: .connectionTimeout, code: "", msg: "", details: nil)
    #expect(EncryptionMapper.error(from: error) == .network(.timeout))
}
```

- [ ] **Step 2 : Lancer pour vérifier l'échec**

Run: `swift test --filter EncryptionMapperTests`
Expected: échec de compilation, `cannot find 'EncryptionMapper' in scope`.

- [ ] **Step 3 : Implémenter**

```swift
import MatrixRustSDK
import MatrixClientKitCore

/// Traduit les états, la progression et les erreurs de chiffrement amont vers le domaine.
enum EncryptionMapper {

    static func status(from state: MatrixRustSDK.VerificationState) -> VerificationStatus {
        switch state {
        case .unknown: .unknown
        case .verified: .verified
        case .unverified: .unverified
        }
    }

    static func backupState(from state: MatrixRustSDK.BackupState) -> MatrixClientKitCore.BackupState {
        switch state {
        case .unknown: .unknown
        case .creating: .creating
        case .enabling: .enabling
        case .resuming: .resuming
        case .enabled: .enabled
        case .downloading: .downloading
        case .disabling: .disabling
        }
    }

    static func recoveryState(from state: MatrixRustSDK.RecoveryState) -> MatrixClientKitCore.RecoveryState {
        switch state {
        case .unknown: .unknown
        case .enabled: .enabled
        case .disabled: .disabled
        case .incomplete: .incomplete
        }
    }

    /// - Note: `.done` amont porte la clé ; elle est volontairement abandonnée ici. La clé n'est
    ///   livrée que par la valeur de retour d'`enableRecovery`, pour qu'un secret n'ait qu'un canal.
    static func progress(from progress: EnableRecoveryProgress) -> RecoveryProgress {
        switch progress {
        case .starting: .starting
        case .creatingBackup: .creatingBackup
        case .creatingRecoveryKey: .creatingRecoveryKey
        case let .backingUp(backedUpCount, totalCount):
            .backingUp(uploaded: Int(clamping: backedUpCount), total: Int(clamping: totalCount))
        case .roomKeyUploadError: .roomKeyUploadError
        case .done: .done
        }
    }

    /// Fragment du message amont d'une récupération jamais configurée
    /// (`SecretStorageError::MissingKeyInfo`), qui partage la variante `SecretStorage` avec une
    /// clé refusée.
    static let missingKeyInfoMarker = "could not have been found"

    /// Traduit une erreur d'opération de chiffrement.
    ///
    /// - Parameter duringRecover: vrai pour `recover(with:)`. Une erreur de stockage de secrets
    ///   y signifie que la clé saisie ne déchiffre pas les secrets — l'amont ne le dit qu'à
    ///   travers le message (échec MAC ou décodage de la clé), sans variante dédiée. Épinglé
    ///   contre un vrai serveur par la suite d'intégration.
    static func error(from error: any Error, duringRecover: Bool = false) -> MatrixError {
        guard let error = error as? RecoveryError else {
            return ErrorMapper.map(error)
        }

        switch error {
        case .BackupExistsOnServer:
            return .unexpected(message: "A key backup already exists on the server.", details: nil)
        case let .Client(source):
            return ErrorMapper.map(source)
        case let .SecretStorage(errorMessage):
            if duringRecover, !errorMessage.contains(missingKeyInfoMarker) {
                return .encryption(.invalidRecoveryKey)
            }
            return .unexpected(message: "Secret storage failed.", details: errorMessage)
        case let .Import(errorMessage):
            return .unexpected(message: "Importing a secret failed.", details: errorMessage)
        }
    }
}
```

- [ ] **Step 4 : Lancer les tests**

Run: `swift test --filter EncryptionMapperTests`
Expected: PASS (9 tests).

- [ ] **Step 5 : Lint et commit**

```bash
swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKitRust/Bridge/EncryptionMapper.swift Tests/MatrixClientKitRustTests/EncryptionMapperTests.swift
git commit -m "feat: mappage des états, de la progression et des erreurs de chiffrement

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6 : Service de chiffrement adossé au SDK

**Files:**
- Create: `Sources/MatrixClientKitRust/Bridge/EncryptionDriving.swift`
- Create: `Sources/MatrixClientKitRust/RustEncryptionService.swift`
- Test: `Tests/MatrixClientKitRustTests/EncryptionServiceTests.swift`

**Interfaces:**
- Consumes : `ffiStateStream` (Task 4), `EncryptionMapper` (Task 5), `EncryptionService`,
  `SessionVerification` (Task 3), `MockSessionVerification` n'est **pas** utilisable ici
  (`MatrixClientKitRustTests` ne dépend pas des mocks) — les tests passent un faux local.
- Produces :
  - `protocol EncryptionDriving: Sendable` (liste exacte dans le code ci-dessous), conformance
    `extension Encryption: EncryptionDriving`.
  - `public final class RustEncryptionService: EncryptionService` avec
    `init(encryption: any EncryptionDriving, sessionVerification: any SessionVerification)`.

Les méthodes d'abonnement de la couture portent des noms distincts (`observe…`) : l'amont renvoie
`TaskHandle`, et un témoin de protocole ne peut pas renvoyer un type concret là où l'exigence
renvoie `any TaskHandleProtocol` — même raison que `SyncServiceDriving.observeState(_:)`.

- [ ] **Step 1 : Écrire les tests qui échouent**

```swift
import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private final class FakeTaskHandle: TaskHandleProtocol, @unchecked Sendable {
    func cancel() {}
    func isFinished() -> Bool { false }
}

private final class FakeEncryption: EncryptionDriving, @unchecked Sendable {
    private let lock = NSLock()

    var currentVerificationState: MatrixRustSDK.VerificationState = .unknown
    var currentBackupState: MatrixRustSDK.BackupState = .unknown
    var currentRecoveryState: MatrixRustSDK.RecoveryState = .unknown
    private var verificationListener: (any VerificationStateListener)?

    var progressToReport: [EnableRecoveryProgress] = []
    var keyToReturn = "EsTc clé"
    var recoverError: (any Error)?
    var isLastDeviceError: (any Error)?
    private(set) var receivedPassphrase: String?? = .none
    private(set) var receivedRecoveryKey: String?

    func verificationState() -> MatrixRustSDK.VerificationState { lock.withLock { currentVerificationState } }
    func observeVerificationState(_ listener: any VerificationStateListener) -> any TaskHandleProtocol {
        lock.withLock { verificationListener = listener }
        return FakeTaskHandle()
    }
    func emitVerificationState(_ state: MatrixRustSDK.VerificationState) {
        let listener = lock.withLock { verificationListener }
        listener?.onUpdate(status: state)
    }

    func backupState() -> MatrixRustSDK.BackupState { lock.withLock { currentBackupState } }
    func observeBackupState(_ listener: any BackupStateListener) -> any TaskHandleProtocol { FakeTaskHandle() }
    func recoveryState() -> MatrixRustSDK.RecoveryState { lock.withLock { currentRecoveryState } }
    func observeRecoveryState(_ listener: any RecoveryStateListener) -> any TaskHandleProtocol { FakeTaskHandle() }

    func isLastDevice() async throws -> Bool {
        if let error = lock.withLock({ isLastDeviceError }) { throw error }
        return true
    }
    func hasDevicesToVerifyAgainst() async throws -> Bool { false }
    func backupExistsOnServer() async throws -> Bool { true }

    func enableRecovery(
        waitForBackupsToUpload: Bool,
        passphrase: String?,
        progressListener: any EnableRecoveryProgressListener
    ) async throws -> String {
        let (steps, key) = lock.withLock {
            receivedPassphrase = .some(passphrase)
            return (progressToReport, keyToReturn)
        }
        steps.forEach { progressListener.onUpdate(status: $0) }
        return key
    }

    func recover(recoveryKey: String) async throws {
        let error = lock.withLock {
            receivedRecoveryKey = recoveryKey
            return recoverError
        }
        if let error { throw error }
    }

    func resetRecoveryKey() async throws -> String { "nouvelle clé" }
    func disableRecovery() async throws {}
    func enableBackups() async throws {}
}

private final class StubVerification: SessionVerification {
    var state: AsyncStream<SessionVerificationState> { AsyncStream { $0.finish() } }
    func requestVerification() async throws {}
    func accept() async throws {}
    func startSAS() async throws {}
    func approve() async throws {}
    func decline() async throws {}
    func cancel() async throws {}
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [RecoveryProgress] = []
    func append(_ step: RecoveryProgress) { lock.withLock { steps.append(step) } }
    var all: [RecoveryProgress] { lock.withLock { steps } }
}

private func makeService(_ encryption: FakeEncryption) -> RustEncryptionService {
    RustEncryptionService(encryption: encryption, sessionVerification: StubVerification())
}

@Test func verificationStatusStartsWithTheCurrentStateThenFollowsUpdates() async {
    let encryption = FakeEncryption()
    encryption.currentVerificationState = .unverified
    let service = makeService(encryption)

    var iterator = service.verificationStatus.makeAsyncIterator()
    #expect(await iterator.next() == .unverified)

    encryption.emitVerificationState(.verified)
    #expect(await iterator.next() == .verified)
}

@Test func backupAndRecoveryStreamsStartWithTheCurrentState() async {
    let encryption = FakeEncryption()
    encryption.currentBackupState = .downloading
    encryption.currentRecoveryState = .incomplete
    let service = makeService(encryption)

    var backup = service.backupState.makeAsyncIterator()
    var recovery = service.recoveryState.makeAsyncIterator()
    #expect(await backup.next() == .downloading)
    #expect(await recovery.next() == .incomplete)
}

@Test func enableRecoveryReportsProgressAndWrapsTheKey() async throws {
    let encryption = FakeEncryption()
    encryption.progressToReport = [.starting, .backingUp(backedUpCount: 1, totalCount: 2), .done(recoveryKey: "k")]
    encryption.keyToReturn = "k"
    let log = ProgressLog()

    let key = try await makeService(encryption).enableRecovery { log.append($0) }

    #expect(key.rawValue == "k")
    #expect(log.all == [.starting, .backingUp(uploaded: 1, total: 2), .done])
    // Passphrase non exposée en 0.2 : jamais transmise.
    #expect(encryption.receivedPassphrase == .some(nil))
}

@Test func recoverForwardsTheKeyAndMapsAWrongOne() async {
    let encryption = FakeEncryption()
    encryption.recoverError = RecoveryError.SecretStorage(errorMessage: "The MAC check for the secret storage key failed")

    await #expect(throws: MatrixError.encryption(.invalidRecoveryKey)) {
        try await makeService(encryption).recover(with: "EsTc mauvaise")
    }
    #expect(encryption.receivedRecoveryKey == "EsTc mauvaise")
}

@Test func queriesMapUpstreamErrors() async throws {
    let encryption = FakeEncryption()
    let service = makeService(encryption)
    #expect(try await service.isLastDevice())
    #expect(try await service.backupExistsOnServer())
    #expect(try await !service.hasDevicesToVerifyAgainst())

    encryption.isLastDeviceError = ClientError.MatrixApi(kind: .connectionFailed, code: "", msg: "", details: nil)
    await #expect(throws: MatrixError.network(.offline)) {
        try await service.isLastDevice()
    }
}

@Test func resetRecoveryKeyWrapsTheNewKey() async throws {
    let key = try await makeService(FakeEncryption()).resetRecoveryKey()
    #expect(key.rawValue == "nouvelle clé")
}
```

- [ ] **Step 2 : Lancer pour vérifier l'échec**

Run: `swift test --filter EncryptionServiceTests`
Expected: échec de compilation, `cannot find type 'EncryptionDriving' in scope`.

- [ ] **Step 3 : Écrire la couture** — `Sources/MatrixClientKitRust/Bridge/EncryptionDriving.swift`

```swift
import MatrixRustSDK

/// Sous-ensemble d'`Encryption` amont dont le service de chiffrement a besoin.
///
/// Cette couture existe pour la testabilité : `Encryption` est une classe FFI qu'un test ne peut
/// pas construire, et `EncryptionProtocol` impose une trentaine de méthodes hors périmètre.
protocol EncryptionDriving: Sendable {
    func verificationState() -> MatrixRustSDK.VerificationState
    func observeVerificationState(_ listener: any VerificationStateListener) -> any TaskHandleProtocol
    func backupState() -> MatrixRustSDK.BackupState
    func observeBackupState(_ listener: any BackupStateListener) -> any TaskHandleProtocol
    func recoveryState() -> MatrixRustSDK.RecoveryState
    func observeRecoveryState(_ listener: any RecoveryStateListener) -> any TaskHandleProtocol

    func isLastDevice() async throws -> Bool
    func hasDevicesToVerifyAgainst() async throws -> Bool
    func backupExistsOnServer() async throws -> Bool

    func enableRecovery(
        waitForBackupsToUpload: Bool,
        passphrase: String?,
        progressListener: any EnableRecoveryProgressListener
    ) async throws -> String
    func recover(recoveryKey: String) async throws
    func resetRecoveryKey() async throws -> String
    func disableRecovery() async throws
    func enableBackups() async throws
}

extension Encryption: EncryptionDriving {
    func observeVerificationState(_ listener: any VerificationStateListener) -> any TaskHandleProtocol {
        verificationStateListener(listener: listener)
    }

    func observeBackupState(_ listener: any BackupStateListener) -> any TaskHandleProtocol {
        backupStateListener(listener: listener)
    }

    func observeRecoveryState(_ listener: any RecoveryStateListener) -> any TaskHandleProtocol {
        recoveryStateListener(listener: listener)
    }
}
```

- [ ] **Step 4 : Écrire le service** — `Sources/MatrixClientKitRust/RustEncryptionService.swift`

```swift
import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``EncryptionService`` adossée au SDK Rust.
public final class RustEncryptionService: EncryptionService {
    private let encryption: any EncryptionDriving
    public let sessionVerification: any SessionVerification

    init(encryption: any EncryptionDriving, sessionVerification: any SessionVerification) {
        self.encryption = encryption
        self.sessionVerification = sessionVerification
    }

    public var verificationStatus: AsyncStream<VerificationStatus> {
        let encryption = encryption
        return ffiStateStream(
            current: { EncryptionMapper.status(from: encryption.verificationState()) },
            makeListener: { emit in
                VerificationStateObserver { emit(EncryptionMapper.status(from: $0)) }
            },
            subscribe: { encryption.observeVerificationState($0) }
        )
    }

    public var backupState: AsyncStream<MatrixClientKitCore.BackupState> {
        let encryption = encryption
        return ffiStateStream(
            current: { EncryptionMapper.backupState(from: encryption.backupState()) },
            makeListener: { emit in
                BackupStateObserver { emit(EncryptionMapper.backupState(from: $0)) }
            },
            subscribe: { encryption.observeBackupState($0) }
        )
    }

    public var recoveryState: AsyncStream<MatrixClientKitCore.RecoveryState> {
        let encryption = encryption
        return ffiStateStream(
            current: { EncryptionMapper.recoveryState(from: encryption.recoveryState()) },
            makeListener: { emit in
                RecoveryStateObserver { emit(EncryptionMapper.recoveryState(from: $0)) }
            },
            subscribe: { encryption.observeRecoveryState($0) }
        )
    }

    public func isLastDevice() async throws -> Bool {
        do {
            return try await encryption.isLastDevice()
        } catch {
            throw EncryptionMapper.error(from: error)
        }
    }

    public func hasDevicesToVerifyAgainst() async throws -> Bool {
        do {
            return try await encryption.hasDevicesToVerifyAgainst()
        } catch {
            throw EncryptionMapper.error(from: error)
        }
    }

    public func backupExistsOnServer() async throws -> Bool {
        do {
            return try await encryption.backupExistsOnServer()
        } catch {
            throw EncryptionMapper.error(from: error)
        }
    }

    public func enableRecovery(
        waitForBackupUpload: Bool,
        progress: @escaping @Sendable (RecoveryProgress) -> Void
    ) async throws -> RecoveryKey {
        let listener = RecoveryProgressObserver { progress(EncryptionMapper.progress(from: $0)) }
        do {
            // Passphrase non exposée en 0.2 (spec §5.2) : l'ajouter plus tard sera un paramètre à
            // valeur par défaut, sans rupture.
            let key = try await encryption.enableRecovery(
                waitForBackupsToUpload: waitForBackupUpload,
                passphrase: nil,
                progressListener: listener
            )
            return RecoveryKey(rawValue: key)
        } catch {
            throw EncryptionMapper.error(from: error)
        }
    }

    public func recover(with key: String) async throws {
        do {
            try await encryption.recover(recoveryKey: key)
        } catch {
            throw EncryptionMapper.error(from: error, duringRecover: true)
        }
    }

    public func resetRecoveryKey() async throws -> RecoveryKey {
        do {
            return RecoveryKey(rawValue: try await encryption.resetRecoveryKey())
        } catch {
            throw EncryptionMapper.error(from: error)
        }
    }

    public func disableRecovery() async throws {
        do {
            try await encryption.disableRecovery()
        } catch {
            throw EncryptionMapper.error(from: error)
        }
    }

    public func enableBackups() async throws {
        do {
            try await encryption.enableBackups()
        } catch {
            throw EncryptionMapper.error(from: error)
        }
    }
}

// Listeners conformes aux protocoles amont, alimentés par une closure — même modèle que
// `StateObserver` dans `RustSyncController`.

private final class VerificationStateObserver: VerificationStateListener {
    private let handler: @Sendable (MatrixRustSDK.VerificationState) -> Void
    init(handler: @escaping @Sendable (MatrixRustSDK.VerificationState) -> Void) { self.handler = handler }
    func onUpdate(status: MatrixRustSDK.VerificationState) { handler(status) }
}

private final class BackupStateObserver: BackupStateListener {
    private let handler: @Sendable (MatrixRustSDK.BackupState) -> Void
    init(handler: @escaping @Sendable (MatrixRustSDK.BackupState) -> Void) { self.handler = handler }
    func onUpdate(status: MatrixRustSDK.BackupState) { handler(status) }
}

private final class RecoveryStateObserver: RecoveryStateListener {
    private let handler: @Sendable (MatrixRustSDK.RecoveryState) -> Void
    init(handler: @escaping @Sendable (MatrixRustSDK.RecoveryState) -> Void) { self.handler = handler }
    func onUpdate(status: MatrixRustSDK.RecoveryState) { handler(status) }
}

private final class RecoveryProgressObserver: EnableRecoveryProgressListener {
    private let handler: @Sendable (EnableRecoveryProgress) -> Void
    init(handler: @escaping @Sendable (EnableRecoveryProgress) -> Void) { self.handler = handler }
    func onUpdate(status: EnableRecoveryProgress) { handler(status) }
}
```

Si le compilateur signale qu'un témoin de `EncryptionDriving` ne correspond pas à la méthode amont
(`Encryption` est `open`, ses signatures sont dans
`.build/checkouts/matrix-rust-components-swift/Sources/MatrixRustSDK/matrix_sdk_ffi.swift`, protocole
`EncryptionProtocol`), aligner **l'exigence** de la couture sur la signature amont, jamais l'inverse.

- [ ] **Step 5 : Lancer les tests**

Run: `swift test --filter EncryptionServiceTests`
Expected: PASS (6 tests).

- [ ] **Step 6 : Lint et commit**

```bash
swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKitRust/Bridge/EncryptionDriving.swift Sources/MatrixClientKitRust/RustEncryptionService.swift Tests/MatrixClientKitRustTests/EncryptionServiceTests.swift
git commit -m "feat: service de chiffrement adossé au SDK Rust

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7 : Vérification de session adossée au SDK

**Files:**
- Create: `Sources/MatrixClientKitRust/Bridge/VerificationControllerDriving.swift`
- Create: `Sources/MatrixClientKitRust/Bridge/VerificationMapper.swift`
- Create: `Sources/MatrixClientKitRust/RustSessionVerification.swift`
- Test: `Tests/MatrixClientKitRustTests/SessionVerificationTests.swift`

**Interfaces:**
- Consumes : `StateBroadcaster` (Task 4), `SessionVerificationReducer`, `VerificationEvent`,
  `VerificationCommand` (Task 2), `SessionVerification` (Task 3), `ErrorMapper.map(_:)`.
- Produces :
  - `protocol VerificationControllerDriving: Sendable` (méthodes amont à l'identique) ;
    `extension SessionVerificationController: VerificationControllerDriving {}`.
  - `enum VerificationMapper` — `static func request(from: SessionVerificationRequestDetails) -> VerificationRequest?`,
    `static func sasData(from: SessionVerificationData) -> SASData`,
    `static func sasData(emojis: [any SessionVerificationEmojiProtocol], indices: Data) -> SASData`.
  - `final class VerificationDelegateAdapter: SessionVerificationControllerDelegate` —
    `init(ownUserID: UserID, handle: @escaping @Sendable (VerificationEvent) -> Void)`.
  - `public final class RustSessionVerification: SessionVerification` —
    `init(ownUserID: UserID, loadController: @escaping @Sendable () async throws -> any VerificationControllerDriving)`,
    `var hasController: Bool`, `@discardableResult func ensureController() async throws -> any VerificationControllerDriving`.

Rappels spec §6.2 : l'amont n'accepte qu'un delegate synchrone ; la réduction est faite
**dans le callback**, sous le verrou du diffuseur, jamais dans un `Task`. Le contrôleur n'existe
qu'une fois l'identité de l'utilisateur chargée : son obtention est retentée à chaque commande tant
qu'elle n'a pas réussi (la relance à chaque changement de `verificationStatus` est branchée en Task 9).

- [ ] **Step 1 : Écrire les tests qui échouent**

```swift
import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private let ownUserID = UserID(rawValue: "@alice:matrix.org")!

private enum ControllerCall: Equatable {
    case request, acknowledge(sender: String, flow: String), accept, startSAS, approve, decline, cancel
}

private final class FakeController: VerificationControllerDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [ControllerCall] = []
    private var _delegate: (any SessionVerificationControllerDelegate)?
    var failure: (any Error)?

    var calls: [ControllerCall] { lock.withLock { _calls } }
    var delegate: (any SessionVerificationControllerDelegate)? { lock.withLock { _delegate } }

    private func record(_ call: ControllerCall) throws {
        let failure = lock.withLock {
            _calls.append(call)
            return self.failure
        }
        if let failure { throw failure }
    }

    func setDelegate(delegate: (any SessionVerificationControllerDelegate)?) { lock.withLock { _delegate = delegate } }
    func requestDeviceVerification() async throws { try record(.request) }
    func acknowledgeVerificationRequest(senderId: String, flowId: String) async throws {
        try record(.acknowledge(sender: senderId, flow: flowId))
    }
    func acceptVerificationRequest() async throws { try record(.accept) }
    func startSasVerification() async throws { try record(.startSAS) }
    func approveVerification() async throws { try record(.approve) }
    func declineVerification() async throws { try record(.decline) }
    func cancelVerification() async throws { try record(.cancel) }
}

private final class FakeEmoji: SessionVerificationEmojiProtocol, @unchecked Sendable {
    let value: String
    let name: String
    init(_ value: String, _ name: String) { self.value = value; self.name = name }
    func symbol() -> String { value }
    func description() -> String { name }
}

private final class LoadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() -> Int { lock.withLock { count += 1; return count } }
    var value: Int { lock.withLock { count } }
}

private func details(from userID: String = "@alice:matrix.org", flow: String = "flow-1") -> SessionVerificationRequestDetails {
    SessionVerificationRequestDetails(
        senderProfile: UserProfile(userId: userID, displayName: nil, avatarUrl: nil, status: nil, call: nil),
        flowId: flow,
        deviceId: "PHONE",
        deviceDisplayName: "iPhone",
        firstSeenTimestamp: 1_000
    )
}

private func makeVerification(_ controller: FakeController) async throws -> RustSessionVerification {
    let verification = RustSessionVerification(ownUserID: ownUserID, loadController: { controller })
    try await verification.ensureController()
    return verification
}

/// Attend le premier état satisfaisant `predicate` ; la borne de temps du test fait échouer une
/// attente qui n'aboutit jamais.
private func waitForState(
    _ verification: RustSessionVerification,
    where predicate: (SessionVerificationState) -> Bool
) async -> SessionVerificationState? {
    for await state in verification.state where predicate(state) {
        return state
    }
    return nil
}

@Test(.timeLimit(.minutes(1)))
func anIncomingRequestReachesALateSubscriber() async throws {
    let controller = FakeController()
    let verification = try await makeVerification(controller)

    controller.delegate?.didReceiveVerificationRequest(details: details())

    // Abonnement postérieur à la demande : l'instantané doit la contenir.
    var iterator = verification.state.makeAsyncIterator()
    guard case let .incomingRequest(request) = await iterator.next() else {
        Issue.record("la demande entrante doit être l'état courant")
        return
    }
    #expect(request.id == "flow-1")
    #expect(request.deviceID.rawValue == "PHONE")
    #expect(request.firstSeen == Date(timeIntervalSince1970: 1))
}

@Test func aRequestFromAnotherUserIsIgnored() async throws {
    let controller = FakeController()
    let verification = try await makeVerification(controller)

    controller.delegate?.didReceiveVerificationRequest(details: details(from: "@mallory:matrix.org"))

    var iterator = verification.state.makeAsyncIterator()
    #expect(await iterator.next() == .idle)
}

@Test func theOutgoingFlowRunsToVerified() async throws {
    let controller = FakeController()
    let verification = try await makeVerification(controller)

    try await verification.requestVerification()
    #expect(await waitForState(verification) { $0 == .waitingForOtherDevice } != nil)

    controller.delegate?.didAcceptVerificationRequest()
    try await verification.startSAS()
    controller.delegate?.didReceiveVerificationData(data: .decimals(values: [1, 2, 3]))
    #expect(await waitForState(verification) { $0 == .comparing(.decimals([1, 2, 3])) } != nil)

    try await verification.approve()
    #expect(await waitForState(verification) { $0 == .confirming } != nil)

    controller.delegate?.didFinish()
    #expect(await waitForState(verification) { $0 == .verified } != nil)

    #expect(controller.calls == [.request, .startSAS, .approve])
}

@Test func acceptingAcknowledgesTheRequestFirst() async throws {
    let controller = FakeController()
    let verification = try await makeVerification(controller)
    controller.delegate?.didReceiveVerificationRequest(details: details(flow: "flow-9"))

    try await verification.accept()

    #expect(controller.calls == [.acknowledge(sender: "@alice:matrix.org", flow: "flow-9"), .accept])
}

@Test func cancellingAnIncomingRequestAcknowledgesItFirst() async throws {
    let controller = FakeController()
    let verification = try await makeVerification(controller)
    controller.delegate?.didReceiveVerificationRequest(details: details(flow: "flow-3"))

    try await verification.cancel()

    #expect(controller.calls == [.acknowledge(sender: "@alice:matrix.org", flow: "flow-3"), .cancel])
    #expect(await waitForState(verification) { $0 == .cancelled } != nil)
}

@Test func aCommandOutsideItsStateThrowsWithoutCallingUpstream() async throws {
    let controller = FakeController()
    let verification = try await makeVerification(controller)

    let error = await #expect(throws: MatrixError.self) {
        try await verification.approve()
    }
    guard case .unexpected = error else {
        Issue.record("attendu .unexpected, obtenu \(String(describing: error))")
        return
    }
    #expect(controller.calls.isEmpty)
}

@Test func anUpstreamFailureIsMappedAndLeavesTheStateUnchanged() async throws {
    let controller = FakeController()
    controller.failure = ClientError.MatrixApi(kind: .connectionFailed, code: "", msg: "", details: nil)
    let verification = try await makeVerification(controller)

    await #expect(throws: MatrixError.network(.offline)) {
        try await verification.requestVerification()
    }
    var iterator = verification.state.makeAsyncIterator()
    #expect(await iterator.next() == .idle)
}

@Test func loadingTheControllerIsRetriedByTheNextCommand() async throws {
    let controller = FakeController()
    let attempts = LoadCounter()
    let verification = RustSessionVerification(ownUserID: ownUserID, loadController: {
        // Première tentative : identité pas encore chargée, comme avant la première sync.
        if attempts.increment() == 1 {
            throw ClientError.Generic(msg: "Failed retrieving user identity", details: nil)
        }
        return controller
    })

    await #expect(throws: MatrixError.self) {
        try await verification.requestVerification()
    }
    #expect(!verification.hasController)

    try await verification.requestVerification()
    #expect(verification.hasController)
    #expect(attempts.value == 2)
    #expect(controller.delegate != nil)
}

@Test func theControllerIsLoadedOnlyOnce() async throws {
    let controller = FakeController()
    let attempts = LoadCounter()
    let verification = RustSessionVerification(ownUserID: ownUserID, loadController: {
        _ = attempts.increment()
        return controller
    })

    try await verification.ensureController()
    try await verification.ensureController()
    try await verification.requestVerification()

    #expect(attempts.value == 1)
}

@Test func emojisAreMappedWithTheirSpecIndices() {
    let data = VerificationMapper.sasData(
        emojis: [FakeEmoji("🐶", "Dog"), FakeEmoji("🔑", "Key")],
        indices: Data([0, 44])
    )
    #expect(
        data == .emojis([
            SASEmoji(symbol: "🐶", description: "Dog", index: 0),
            SASEmoji(symbol: "🔑", description: "Key", index: 44),
        ]))
}

@Test func aMissingEmojiIndexIsNil() {
    let data = VerificationMapper.sasData(emojis: [FakeEmoji("🐶", "Dog")], indices: Data())
    #expect(data == .emojis([SASEmoji(symbol: "🐶", description: "Dog", index: nil)]))
}
```

- [ ] **Step 2 : Lancer pour vérifier l'échec**

Run: `swift test --filter SessionVerificationTests`
Expected: échec de compilation, `cannot find type 'VerificationControllerDriving' in scope`.

- [ ] **Step 3 : Écrire la couture** — `Sources/MatrixClientKitRust/Bridge/VerificationControllerDriving.swift`

```swift
import MatrixRustSDK

/// Sous-ensemble de `SessionVerificationController` amont dont la vérification a besoin.
///
/// Couture de testabilité : le contrôleur est une classe FFI qu'un test ne peut pas construire.
/// Les signatures sont celles de l'amont, à l'identique, pour que la conformance soit vide.
protocol VerificationControllerDriving: Sendable {
    func setDelegate(delegate: (any SessionVerificationControllerDelegate)?)
    func requestDeviceVerification() async throws
    func acknowledgeVerificationRequest(senderId: String, flowId: String) async throws
    func acceptVerificationRequest() async throws
    func startSasVerification() async throws
    func approveVerification() async throws
    func declineVerification() async throws
    func cancelVerification() async throws
}

extension SessionVerificationController: VerificationControllerDriving {}
```

- [ ] **Step 4 : Écrire le mappeur** — `Sources/MatrixClientKitRust/Bridge/VerificationMapper.swift`

```swift
import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Traduit les demandes et données de vérification amont vers le domaine.
enum VerificationMapper {

    /// - Returns: `nil` quand l'identifiant d'appareil amont n'est pas valide. Une demande dont
    ///   l'appareil ne peut pas être nommé ne peut pas être présentée honnêtement à l'utilisateur.
    static func request(from details: SessionVerificationRequestDetails) -> VerificationRequest? {
        guard let deviceID = DeviceID(rawValue: details.deviceId) else { return nil }
        return VerificationRequest(
            id: details.flowId,
            deviceID: deviceID,
            deviceDisplayName: details.deviceDisplayName,
            firstSeen: Date(timeIntervalSince1970: TimeInterval(details.firstSeenTimestamp) / 1000)
        )
    }

    static func sasData(from data: SessionVerificationData) -> SASData {
        switch data {
        case let .emojis(emojis, indices):
            sasData(emojis: emojis, indices: indices)
        case let .decimals(values):
            .decimals(values)
        }
    }

    /// Séparée de ``sasData(from:)`` parce que `SessionVerificationEmoji` est une classe FFI
    /// qu'un test ne peut pas construire, alors que son protocole peut être implémenté.
    static func sasData(emojis: [any SessionVerificationEmojiProtocol], indices: Data) -> SASData {
        let indices = Array(indices)
        return .emojis(
            emojis.enumerated().map { position, emoji in
                SASEmoji(
                    symbol: emoji.symbol(),
                    description: emoji.description(),
                    index: position < indices.count ? Int(indices[position]) : nil
                )
            })
    }
}
```

- [ ] **Step 5 : Écrire le service** — `Sources/MatrixClientKitRust/RustSessionVerification.swift`

```swift
import Foundation
import Synchronization
import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``SessionVerification`` adossée au `SessionVerificationController` amont.
public final class RustSessionVerification: SessionVerification {
    private let ownUserID: UserID
    private let loadController: @Sendable () async throws -> any VerificationControllerDriving
    private let broadcaster: StateBroadcaster<SessionVerificationState>
    private let controller = Mutex<(any VerificationControllerDriving)?>(nil)

    /// Retenu pour la durée de la session : le contrôleur amont ne documente pas qu'il garde son
    /// delegate en vie, et un delegate libéré ferait perdre en silence toute demande entrante.
    private let delegate: VerificationDelegateAdapter

    init(
        ownUserID: UserID,
        loadController: @escaping @Sendable () async throws -> any VerificationControllerDriving
    ) {
        self.ownUserID = ownUserID
        self.loadController = loadController
        let broadcaster = StateBroadcaster<SessionVerificationState>(.idle)
        self.broadcaster = broadcaster
        self.delegate = VerificationDelegateAdapter(ownUserID: ownUserID) { event in
            broadcaster.update { SessionVerificationReducer.reduce($0, event) }
        }
    }

    public var state: AsyncStream<SessionVerificationState> {
        broadcaster.stream()
    }

    var hasController: Bool {
        controller.withLock { $0 != nil }
    }

    /// Obtient le contrôleur amont et y pose le delegate, une seule fois.
    ///
    /// L'amont exige l'identité cross-signing de l'utilisateur dans le store local : avant la
    /// première sync, l'appel peut échouer. Il est alors retenté par l'appelant — à chaque commande
    /// et à chaque changement de l'état de vérification de l'appareil (spec 0.2, §6.2).
    @discardableResult
    func ensureController() async throws -> any VerificationControllerDriving {
        if let existing = controller.withLock({ $0 }) {
            return existing
        }

        let loaded = try await loadController()
        let (winner, isNew) = controller.withLock { current -> (any VerificationControllerDriving, Bool) in
            if let current { return (current, false) }
            current = loaded
            return (loaded, true)
        }

        // Hors verrou : on n'appelle jamais de code amont en tenant un verrou.
        if isNew {
            winner.setDelegate(delegate: delegate)
        }
        return winner
    }

    public func requestVerification() async throws {
        try await perform(.requestVerification, onSuccess: .requestSent) { controller, _ in
            try await controller.requestDeviceVerification()
        }
    }

    public func accept() async throws {
        let ownUserID = ownUserID
        // Pas d'événement local : `ready` n'est atteint que sur `didAcceptVerificationRequest`.
        try await perform(.accept, onSuccess: nil) { controller, state in
            guard case let .incomingRequest(request) = state else { return }
            try await controller.acknowledgeVerificationRequest(senderId: ownUserID.rawValue, flowId: request.id)
            try await controller.acceptVerificationRequest()
        }
    }

    public func startSAS() async throws {
        try await perform(.startSAS, onSuccess: .startSASSent) { controller, _ in
            try await controller.startSasVerification()
        }
    }

    public func approve() async throws {
        try await perform(.approve, onSuccess: .approvalSent) { controller, _ in
            try await controller.approveVerification()
        }
    }

    public func decline() async throws {
        // L'issue (`cancelled` ou `failed`) est signalée par l'amont.
        try await perform(.decline, onSuccess: nil) { controller, _ in
            try await controller.declineVerification()
        }
    }

    public func cancel() async throws {
        let ownUserID = ownUserID
        try await perform(.cancel, onSuccess: .cancelSent) { controller, state in
            // Une demande entrante n'est pas encore le flux actif du contrôleur : il faut la
            // désigner avant de pouvoir l'annuler.
            if case let .incomingRequest(request) = state {
                try await controller.acknowledgeVerificationRequest(senderId: ownUserID.rawValue, flowId: request.id)
            }
            try await controller.cancelVerification()
        }
    }

    /// Valide la commande contre l'état courant, l'exécute, puis applique l'événement de succès.
    private func perform(
        _ command: VerificationCommand,
        onSuccess event: VerificationEvent?,
        _ body: (any VerificationControllerDriving, SessionVerificationState) async throws -> Void
    ) async throws {
        let current = broadcaster.value
        guard SessionVerificationReducer.isAllowed(command, in: current) else {
            throw MatrixError.unexpected(
                message: "\(command.rawValue)() is not allowed while verification is \(current).",
                details: nil
            )
        }

        do {
            let controller = try await ensureController()
            try await body(controller, current)
        } catch {
            throw ErrorMapper.map(error)
        }

        if let event {
            broadcaster.update { SessionVerificationReducer.reduce($0, event) }
        }
    }
}

/// Delegate amont : traduit chaque callback en ``VerificationEvent``, de façon synchrone.
final class VerificationDelegateAdapter: SessionVerificationControllerDelegate {
    private let ownUserID: UserID
    private let handle: @Sendable (VerificationEvent) -> Void

    init(ownUserID: UserID, handle: @escaping @Sendable (VerificationEvent) -> Void) {
        self.ownUserID = ownUserID
        self.handle = handle
    }

    func didReceiveVerificationRequest(details: SessionVerificationRequestDetails) {
        // Le périmètre 0.2 est la vérification de ses propres appareils : une demande venue d'un
        // autre utilisateur n'a pas d'état public pour la représenter.
        guard details.senderProfile.userId == ownUserID.rawValue,
            let request = VerificationMapper.request(from: details)
        else { return }
        handle(.receivedRequest(request))
    }

    func didAcceptVerificationRequest() { handle(.otherDeviceAccepted) }
    func didStartSasVerification() { handle(.sasStarted) }

    func didReceiveVerificationData(data: SessionVerificationData) {
        handle(.receivedSASData(VerificationMapper.sasData(from: data)))
    }

    func didFail() { handle(.failed) }
    func didCancel() { handle(.cancelled) }
    func didFinish() { handle(.finished) }
}
```

- [ ] **Step 6 : Lancer les tests**

Run: `swift test --filter SessionVerificationTests`
Expected: PASS (12 tests).

- [ ] **Step 7 : Lint et commit**

```bash
swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKitRust/Bridge/VerificationControllerDriving.swift Sources/MatrixClientKitRust/Bridge/VerificationMapper.swift Sources/MatrixClientKitRust/RustSessionVerification.swift Tests/MatrixClientKitRustTests/SessionVerificationTests.swift
git commit -m "feat: vérification de session SAS adossée au SDK Rust

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8 : Cycle de vie de la session et déconnexion serveur

**Files:**
- Create: `Sources/MatrixClientKitRust/SessionLifecycle.swift`
- Create: `Sources/MatrixClientKitRust/Bridge/AuthDelegate.swift`
- Test: `Tests/MatrixClientKitRustTests/SessionLifecycleTests.swift`

**Interfaces:**
- Consumes : `StateBroadcaster` (Task 4), `AuthState` (Task 3), `ErrorMapper.map(_:)`.
- Produces :
  - `final class SessionLifecycle: Sendable` — `init(stopSync: @escaping @Sendable () async -> Void, erase: @escaping @Sendable () throws -> Void)`,
    `var authState: AsyncStream<AuthState>`, `var current: AuthState`,
    `@discardableResult func handleAuthError(isSoftLogout: Bool) -> Task<Void, Never>?`,
    `func logout(server: @Sendable () async throws -> Void) async throws`.
  - `final class AuthDelegate: ClientDelegate` — `init(lifecycle: SessionLifecycle)`.

Rappels spec §8.2 et §8.3 : hard logout → arrêt de la sync, effacement, **puis** `.signedOut`, une
seule fois ; soft logout → `.softLoggedOut`, rien d'effacé ; `.signedOut` est terminal ; `logout()`
après soft logout avale `unknownToken` ; `logout()` après `.signedOut` ne fait rien.

- [ ] **Step 1 : Écrire les tests qui échouent**

```swift
import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private final class Journal: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func append(_ entry: String) { lock.withLock { entries.append(entry) } }
    var all: [String] { lock.withLock { entries } }
}

/// Donne à la closure d'effacement accès au cycle de vie qu'elle sert, construit après elle.
private final class LifecycleRef: @unchecked Sendable {
    var lifecycle: SessionLifecycle?
}

private func makeLifecycle(
    journal: Journal,
    eraseError: (any Error)? = nil
) -> SessionLifecycle {
    let ref = LifecycleRef()
    let lifecycle = SessionLifecycle(
        stopSync: { journal.append("stopSync") },
        erase: {
            journal.append("erase while \(ref.lifecycle.map { "\($0.current)" } ?? "?")")
            if let eraseError { throw eraseError }
        }
    )
    ref.lifecycle = lifecycle
    return lifecycle
}

private let unknownToken = ClientError.MatrixApi(
    kind: .unknownToken(softLogout: true), code: "M_UNKNOWN_TOKEN", msg: "", details: nil
)

@Test func aHardLogoutErasesEverythingBeforeReportingSignedOut() async {
    let journal = Journal()
    let lifecycle = makeLifecycle(journal: journal)

    await lifecycle.handleAuthError(isSoftLogout: false)?.value

    // L'application qui voit `.signedOut` doit pouvoir compter sur un disque déjà propre.
    #expect(journal.all == ["stopSync", "erase while signedIn"])
    #expect(lifecycle.current == .signedOut)
}

@Test func aRepeatedHardLogoutIsHandledOnce() async {
    let journal = Journal()
    let lifecycle = makeLifecycle(journal: journal)

    let first = lifecycle.handleAuthError(isSoftLogout: false)
    let second = lifecycle.handleAuthError(isSoftLogout: false)
    await first?.value

    #expect(second == nil)
    #expect(journal.all.filter { $0.hasPrefix("erase") }.count == 1)
}

@Test func aFailedEraseStillReportsSignedOut() async {
    let journal = Journal()
    let lifecycle = makeLifecycle(journal: journal, eraseError: MatrixError.storage(.unavailable))

    await lifecycle.handleAuthError(isSoftLogout: false)?.value

    #expect(lifecycle.current == .signedOut)
}

@Test func aSoftLogoutErasesNothing() async {
    let journal = Journal()
    let lifecycle = makeLifecycle(journal: journal)

    #expect(lifecycle.handleAuthError(isSoftLogout: true) == nil)

    #expect(journal.all.isEmpty)
    #expect(lifecycle.current == .softLoggedOut)
}

@Test func signedOutIsTerminal() async {
    let lifecycle = makeLifecycle(journal: Journal())
    await lifecycle.handleAuthError(isSoftLogout: false)?.value

    lifecycle.handleAuthError(isSoftLogout: true)

    #expect(lifecycle.current == .signedOut)
}

@Test func subscribersSeeTheTransition() async {
    let lifecycle = makeLifecycle(journal: Journal())
    var iterator = lifecycle.authState.makeAsyncIterator()
    #expect(await iterator.next() == .signedIn)

    lifecycle.handleAuthError(isSoftLogout: true)
    #expect(await iterator.next() == .softLoggedOut)
}

@Test func logoutErasesAndSignsOut() async throws {
    let journal = Journal()
    let lifecycle = makeLifecycle(journal: journal)

    try await lifecycle.logout { journal.append("server") }

    #expect(journal.all == ["stopSync", "server", "erase while signedIn"])
    #expect(lifecycle.current == .signedOut)
}

@Test func logoutAfterASoftLogoutSwallowsTheExpectedTokenError() async throws {
    let journal = Journal()
    let lifecycle = makeLifecycle(journal: journal)
    lifecycle.handleAuthError(isSoftLogout: true)

    // Le jeton est déjà refusé par le serveur : lever ici ferait échouer une déconnexion aboutie.
    try await lifecycle.logout { throw unknownToken }

    #expect(journal.all == ["stopSync", "erase while softLoggedOut"])
    #expect(lifecycle.current == .signedOut)
}

@Test func logoutStillErasesThenRethrowsAnyOtherServerError() async {
    let journal = Journal()
    let lifecycle = makeLifecycle(journal: journal)

    await #expect(throws: MatrixError.network(.offline)) {
        try await lifecycle.logout {
            throw ClientError.MatrixApi(kind: .connectionFailed, code: "", msg: "", details: nil)
        }
    }

    // Un utilisateur qui se déconnecte hors ligne ne doit pas rester connecté localement.
    #expect(journal.all == ["stopSync", "erase while signedIn"])
    #expect(lifecycle.current == .signedOut)
}

@Test func logoutAfterSignedOutDoesNothing() async throws {
    let journal = Journal()
    let lifecycle = makeLifecycle(journal: journal)
    await lifecycle.handleAuthError(isSoftLogout: false)?.value

    try await lifecycle.logout { journal.append("server") }

    #expect(!journal.all.contains("server"))
    #expect(journal.all.filter { $0.hasPrefix("erase") }.count == 1)
}

@Test func theClientDelegateForwardsAuthErrors() {
    let lifecycle = makeLifecycle(journal: Journal())
    let delegate = AuthDelegate(lifecycle: lifecycle)

    delegate.didReceiveAuthError(isSoftLogout: true)

    #expect(lifecycle.current == .softLoggedOut)
}
```

- [ ] **Step 2 : Lancer pour vérifier l'échec**

Run: `swift test --filter SessionLifecycleTests`
Expected: échec de compilation, `cannot find 'SessionLifecycle' in scope`.

- [ ] **Step 3 : Implémenter le cycle de vie** — `Sources/MatrixClientKitRust/SessionLifecycle.swift`

```swift
import Synchronization
import MatrixClientKitCore

/// Fin de vie d'une session : déconnexion demandée par l'application, ou imposée par le serveur.
///
/// Les deux chemins partagent une règle : arrêt de la sync et effacement local n'ont lieu qu'une
/// fois, et `.signedOut` n'est publié qu'**après** l'effacement — une application qui observe
/// `.signedOut` peut compter sur un disque déjà propre.
final class SessionLifecycle: Sendable {
    private let broadcaster = StateBroadcaster<AuthState>(.signedIn)
    private let terminationClaimed = Mutex(false)
    private let stopSync: @Sendable () async -> Void
    private let erase: @Sendable () throws -> Void

    init(
        stopSync: @escaping @Sendable () async -> Void,
        erase: @escaping @Sendable () throws -> Void
    ) {
        self.stopSync = stopSync
        self.erase = erase
    }

    var authState: AsyncStream<AuthState> {
        broadcaster.stream()
    }

    var current: AuthState {
        broadcaster.value
    }

    /// Réagit à `ClientDelegate.didReceiveAuthError(isSoftLogout:)`.
    ///
    /// Le callback amont est synchrone alors que l'arrêt de la sync est asynchrone : la
    /// terminaison part dans un `Task`, renvoyé pour que les tests puissent l'attendre. La
    /// revendication de terminaison, elle, est synchrone : un callback répété ne lance jamais une
    /// seconde purge.
    @discardableResult
    func handleAuthError(isSoftLogout: Bool) -> Task<Void, Never>? {
        if isSoftLogout {
            broadcaster.update { $0 == .signedIn ? .softLoggedOut : $0 }
            return nil
        }

        guard claimTermination() else { return nil }
        return Task {
            await self.stopSync()
            // Un effacement en échec est avalé : la session est morte côté serveur quoi qu'il
            // arrive, et la laisser en `.signedIn` promettrait une session qui n'existe plus.
            try? self.erase()
            self.broadcaster.update { _ in .signedOut }
        }
    }

    /// Déconnexion demandée par l'application.
    ///
    /// - Important: l'effacement local a lieu même si l'appel serveur échoue — un utilisateur qui
    ///   se déconnecte hors ligne ne doit pas rester connecté localement. L'erreur serveur remonte
    ///   ensuite, sauf `unknownToken` après un soft logout : le serveur a déjà refusé ce jeton, la
    ///   déconnexion a donc abouti.
    func logout(server: @Sendable () async throws -> Void) async throws {
        guard claimTermination() else { return }
        let wasSoftLoggedOut = current == .softLoggedOut

        await stopSync()

        do {
            try await server()
        } catch {
            try? erase()
            broadcaster.update { _ in .signedOut }

            let mapped = ErrorMapper.map(error)
            if wasSoftLoggedOut, case .authentication(.unknownToken) = mapped {
                return
            }
            throw mapped
        }

        defer { broadcaster.update { _ in .signedOut } }
        do {
            try erase()
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    private func claimTermination() -> Bool {
        terminationClaimed.withLock { claimed in
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}
```

- [ ] **Step 4 : Implémenter le delegate** — `Sources/MatrixClientKitRust/Bridge/AuthDelegate.swift`

```swift
import MatrixRustSDK

/// `ClientDelegate` amont : relaie les erreurs d'authentification au cycle de vie de la session.
final class AuthDelegate: ClientDelegate {
    private let lifecycle: SessionLifecycle

    init(lifecycle: SessionLifecycle) {
        self.lifecycle = lifecycle
    }

    func didReceiveAuthError(isSoftLogout: Bool) {
        lifecycle.handleAuthError(isSoftLogout: isSoftLogout)
    }

    func onBackgroundTaskErrorReport(taskName: String, error: BackgroundTaskFailureReason) {
        // Hors périmètre 0.2 : aucun état public ne représente l'échec d'une tâche de fond amont.
    }
}
```

- [ ] **Step 5 : Lancer les tests**

Run: `swift test --filter SessionLifecycleTests`
Expected: PASS (11 tests).

- [ ] **Step 6 : Lint et commit**

```bash
swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKitRust/SessionLifecycle.swift Sources/MatrixClientKitRust/Bridge/AuthDelegate.swift Tests/MatrixClientKitRustTests/SessionLifecycleTests.swift
git commit -m "feat: cycle de vie de session, déconnexion serveur hard et soft

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9 : Branchement de la session

**Files:**
- Modify: `Sources/MatrixClientKitCore/Services/MatrixSession.swift` (remplacement complet)
- Modify: `Sources/MatrixClientKitRust/RustMatrixSession.swift` (remplacement complet)
- Modify: `Sources/MatrixClientKitMocks/MockMatrixSession.swift` (remplacement complet)
- Test: `Tests/MatrixClientKitCoreTests/MockTests.swift` (ajouts en fin de fichier)

**Interfaces:**
- Consumes : `RustEncryptionService` (Task 6), `RustSessionVerification` (Task 7),
  `SessionLifecycle`, `AuthDelegate` (Task 8), `MockEncryptionService` (Task 3),
  `RustSyncController` (existant).

Point de conception (spec §6.2) : le contrôleur de vérification est réclamé à chaque valeur de
`encryption.verificationStatus`, **pas** au passage de la sync à `.running` — la sync atteint
`.running` avant que l'identité ne soit chargée et n'en ressort plus, ce qui laisserait les demandes
entrantes perdues pour toujours.
- Produces : `MatrixSession.encryption: any EncryptionService`,
  `MatrixSession.authState: AsyncStream<AuthState>` ; `MockMatrixSession.init(userID:deviceID:rooms:sync:encryption:)`,
  `emitAuthState(_:)`, `logoutError: MatrixError?`. `RustMatrixSession.make(client:persistence:localStore:)`
  garde sa signature (elle change en Task 10).

Changement **cassant** : toute implémentation tierce de `MatrixSession` ne compile plus. Consigné au
CHANGELOG en Task 15.

- [ ] **Step 1 : Écrire les tests de mock qui échouent** — ajouter en fin de `Tests/MatrixClientKitCoreTests/MockTests.swift`

```swift
@Test func mockSessionExposesADrivableEncryptionService() async {
    let encryption = MockEncryptionService()
    let session = MockMatrixSession(encryption: encryption)
    var iterator = session.encryption.verificationStatus.makeAsyncIterator()

    encryption.emitVerificationStatus(.verified)

    #expect(await iterator.next() == .verified)
}

@Test func mockSessionDeliversEmittedAuthStates() async {
    let session = MockMatrixSession()
    var iterator = session.authState.makeAsyncIterator()

    session.emitAuthState(.signedOut)

    #expect(await iterator.next() == .signedOut)
}

@Test func mockSessionLogoutCanFail() async {
    let session = MockMatrixSession()
    session.logoutError = .network(.offline)

    await #expect(throws: MatrixError.network(.offline)) {
        try await session.logout()
    }
    // Comme la vraie session, la tentative compte : l'effacement local a lieu même en cas d'échec.
    #expect(session.didLogout)
}
```

- [ ] **Step 2 : Lancer pour vérifier l'échec**

Run: `swift test --filter MockTests`
Expected: échec de compilation, `extra argument 'encryption' in call`.

- [ ] **Step 3 : Étendre le protocole** — remplacer `Sources/MatrixClientKitCore/Services/MatrixSession.swift`

```swift
/// An authenticated session: every service is reached through it.
public protocol MatrixSession: Sendable {
    /// The authenticated user's identifier.
    var userID: UserID { get }
    /// The identifier of the device this session is open on.
    var deviceID: DeviceID { get }
    /// Access to rooms and to the observable room list.
    var rooms: any RoomService { get }
    /// Drives syncing with the homeserver.
    var sync: any SyncController { get }
    /// End-to-end encryption: this device's verification, recovery and key backup.
    var encryption: any EncryptionService { get }

    /// A stream of the session's authentication state, starting with the current value. Every
    /// access opens an independent subscription.
    ///
    /// Observe it to learn that the homeserver ended the session while the application was
    /// running — for instance after the user removed this device from another one. When it
    /// reports ``AuthState/signedOut``, everything stored locally for the session has already been
    /// erased.
    var authState: AsyncStream<AuthState> { get }

    /// Ends the session server-side and erases everything stored locally.
    ///
    /// Local data is erased even when the server call fails, and the error is then thrown. After
    /// ``AuthState/softLoggedOut``, the server is expected to reject the call: the local cleanup
    /// still happens and nothing is thrown. After ``AuthState/signedOut``, this does nothing.
    func logout() async throws
}
```

- [ ] **Step 4 : Mettre à jour le mock** — remplacer `Sources/MatrixClientKitMocks/MockMatrixSession.swift`

```swift
import Foundation
import MatrixClientKitCore

/// A drivable authenticated session for tests: exposes a ready-made ``MockRoomService``,
/// ``MockSyncController`` and ``MockEncryptionService``, lets you push authentication states, and
/// records calls to ``logout()``.
public final class MockMatrixSession: MatrixSession, @unchecked Sendable {
    private let lock = NSLock()

    public let userID: UserID
    public let deviceID: DeviceID
    public let rooms: any RoomService
    public let sync: any SyncController
    public let encryption: any EncryptionService

    private let authStateStream: AsyncStream<AuthState>
    private let authStateContinuation: AsyncStream<AuthState>.Continuation

    private var _didLogout = false
    private var _logoutError: MatrixError?

    /// True once ``logout()`` has been called, whether it threw or not.
    public var didLogout: Bool {
        lock.withLock { _didLogout }
    }

    /// The error ``logout()`` throws. `nil` by default, meaning it succeeds.
    public var logoutError: MatrixError? {
        get { lock.withLock { _logoutError } }
        set { lock.withLock { _logoutError = newValue } }
    }

    public init(
        userID: String = "@alice:matrix.org",
        deviceID: String = "DEV1",
        rooms: MockRoomService = MockRoomService(),
        sync: MockSyncController = MockSyncController(),
        encryption: MockEncryptionService = MockEncryptionService()
    ) {
        self.userID = UserID(rawValue: userID) ?? UserID(rawValue: "@alice:matrix.org")!
        self.deviceID = DeviceID(rawValue: deviceID) ?? DeviceID(rawValue: "DEV1")!
        self.rooms = rooms
        self.sync = sync
        self.encryption = encryption
        (authStateStream, authStateContinuation) = AsyncStream<AuthState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    /// The stream of authentication states. Single-consumer: iterate over it once per instance.
    /// Unlike the real session, it emits nothing until you call ``emitAuthState(_:)``.
    public var authState: AsyncStream<AuthState> { authStateStream }

    /// Pushes a value to ``authState``.
    public func emitAuthState(_ state: AuthState) {
        authStateContinuation.yield(state)
    }

    public func logout() async throws {
        let error = lock.withLock {
            _didLogout = true
            return _logoutError
        }
        if let error { throw error }
    }
}
```

Si le fichier existant contient une documentation de type plus riche que la première ligne reprise
ici (lire le fichier avant de le remplacer), la conserver et y ajouter ``MockEncryptionService``,
``emitAuthState(_:)`` et ``logoutError``.

- [ ] **Step 5 : Brancher la session réelle** — remplacer `Sources/MatrixClientKitRust/RustMatrixSession.swift`

```swift
import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``MatrixSession`` adossée au SDK Rust.
public final class RustMatrixSession: MatrixClientKitCore.MatrixSession {
    public let userID: UserID
    public let deviceID: DeviceID
    public let rooms: any RoomService
    public let sync: any SyncController
    public let encryption: any EncryptionService

    private let client: Client
    private let lifecycle: SessionLifecycle

    /// Retenus pour la durée de la session : un delegate libéré ne signalerait plus aucune
    /// déconnexion serveur, et l'annulation du handle désabonnerait le delegate.
    private let authDelegate: AuthDelegate
    private let authDelegateHandle: TaskHandle?

    /// Obtient le contrôleur de vérification dès que l'amont le permet (voir
    /// ``watchForVerificationController(verification:sync:)``).
    private let controllerWatcher: Task<Void, Never>

    private init(
        userID: UserID,
        deviceID: DeviceID,
        rooms: any RoomService,
        sync: any SyncController,
        encryption: any EncryptionService,
        client: Client,
        lifecycle: SessionLifecycle,
        authDelegate: AuthDelegate,
        authDelegateHandle: TaskHandle?,
        controllerWatcher: Task<Void, Never>
    ) {
        self.userID = userID
        self.deviceID = deviceID
        self.rooms = rooms
        self.sync = sync
        self.encryption = encryption
        self.client = client
        self.lifecycle = lifecycle
        self.authDelegate = authDelegate
        self.authDelegateHandle = authDelegateHandle
        self.controllerWatcher = controllerWatcher
    }

    deinit {
        controllerWatcher.cancel()
        authDelegateHandle?.cancel()
    }

    public var authState: AsyncStream<AuthState> {
        lifecycle.authState
    }

    static func make(
        client: Client,
        persistence: SessionPersistence,
        localStore: LocalStore
    ) async throws -> RustMatrixSession {
        do {
            let session = try client.session()
            let data = try SessionMapper.sessionData(from: session)
            let syncService = try await client.syncService().finish()
            let sync = RustSyncController(service: syncService)

            let verification = RustSessionVerification(
                ownUserID: data.userID,
                loadController: { try await client.getSessionVerificationController() }
            )
            let encryption = RustEncryptionService(
                encryption: client.encryption(),
                sessionVerification: verification
            )

            let lifecycle = SessionLifecycle(
                stopSync: { await syncService.stop() },
                erase: { try eraseLocalData(persistence: persistence, localStore: localStore) }
            )
            let authDelegate = AuthDelegate(lifecycle: lifecycle)
            let authDelegateHandle = try client.setDelegate(delegate: authDelegate)

            return RustMatrixSession(
                userID: data.userID,
                deviceID: data.deviceID,
                rooms: RustRoomService(roomListService: syncService.roomListService()),
                sync: sync,
                encryption: encryption,
                client: client,
                lifecycle: lifecycle,
                authDelegate: authDelegate,
                authDelegateHandle: authDelegateHandle,
                controllerWatcher: watchForVerificationController(verification: verification, encryption: encryption)
            )
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    /// Ferme la session côté serveur et efface toutes les données locales : session persistée,
    /// store SQLite (historique **et** store crypto) et clé de chiffrement associée.
    ///
    /// - Important: `Client.logout()` amont ne fait que la déconnexion côté serveur ; il ne
    ///   supprime rien en local. Sans l'effacement orchestré par ``SessionLifecycle``, l'identité
    ///   d'appareil et les clés de room Megolm resteraient sur disque après une déconnexion.
    public func logout() async throws {
        let client = client
        try await lifecycle.logout {
            try await client.logout()
        }
    }

    /// Obtient le contrôleur de vérification le plus tôt possible.
    ///
    /// Le delegate doit être posé avant qu'une demande entrante n'arrive, faute de quoi elle est
    /// perdue. Or l'amont n'accorde le contrôleur qu'une fois l'identité de l'utilisateur présente
    /// dans le store local (spec 0.2, §2.8 et §6.2). Le signal fiable de ce chargement est l'état
    /// de vérification de l'appareil : il change quand l'identité devient connue, y compris après
    /// l'amorçage du cross-signing d'un compte neuf. L'état de la sync, lui, passe à `.running`
    /// avant ce chargement et y reste — s'y fier laisserait le contrôleur jamais obtenu.
    ///
    /// Tentative à chaque valeur du flux, qui commence par la valeur courante, jusqu'au premier
    /// succès.
    private static func watchForVerificationController(
        verification: RustSessionVerification,
        encryption: RustEncryptionService
    ) -> Task<Void, Never> {
        Task {
            for await _ in encryption.verificationStatus {
                if (try? await verification.ensureController()) != nil { return }
            }
        }
    }

    /// Efface la session persistée puis le store local. Les deux effacements sont tentés même si
    /// le premier échoue — une session effacée dont le store crypto resterait sur disque est
    /// précisément ce que la purge existe pour éviter ; la première erreur est relayée.
    private static func eraseLocalData(persistence: SessionPersistence, localStore: LocalStore) throws {
        var firstError: (any Error)?
        do {
            try persistence.clear()
        } catch {
            firstError = error
        }
        do {
            try localStore.purge()
        } catch {
            firstError = firstError ?? error
        }
        if let firstError { throw firstError }
    }
}
```

- [ ] **Step 6 : Compiler et lancer les tests**

Run: `swift build --build-tests && swift test --skip MatrixClientKitIntegrationTests`
Expected: compilation réussie, PASS. Si `client.setDelegate(delegate:)` n'est pas trouvé avec cette
étiquette, vérifier la signature dans `matrix_sdk_ffi.swift` (`func setDelegate(delegate: ClientDelegate?) throws -> TaskHandle?`).

- [ ] **Step 7 : Build iOS**

Run: `xcodebuild build -quiet -scheme MatrixClientKit -destination 'generic/platform=iOS Simulator'`
Expected: `** BUILD SUCCEEDED **` (ou aucune sortie d'erreur avec `-quiet`).

- [ ] **Step 8 : Lint et commit**

```bash
swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKitCore/Services/MatrixSession.swift Sources/MatrixClientKitRust/RustMatrixSession.swift Sources/MatrixClientKitMocks/MockMatrixSession.swift Tests/MatrixClientKitCoreTests/MockTests.swift
git commit -m "feat!: la session expose le chiffrement et son état d'authentification

MatrixSession gagne encryption et authState : toute implémentation tierce
du protocole doit les fournir. MockMatrixSession les fournit, et permet de
faire échouer logout().

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10 : Restauration sans URL et amorçage du cross-signing

**Files:**
- Create: `Sources/MatrixClientKitRust/SessionRestorer.swift`
- Modify: `Sources/MatrixClientKitRust/RustMatrixClient.swift` (remplacement complet)
- Modify: `Sources/MatrixClientKitRust/RustMatrixSession.swift` (signature de `make` et rétention du restaurateur)
- Modify: `Sources/MatrixClientKit/MatrixClientKit.swift` (ajout de `restoreSession(storage:)`)
- Test: `Tests/MatrixClientKitRustTests/SessionRestorerTests.swift`

**Interfaces:**
- Consumes : `RustMatrixSession.make` (Task 9), `SessionPersistence`, `LocalStore`,
  `KeychainSecureStore`, `InMemorySecureStore`, `SessionDelegate`, `SessionMapper`, `ErrorMapper`
  (existants).
- Produces :
  - `final class SessionRestorer: Sendable` — `convenience init(storage: MatrixStorage)`,
    `init(storage: MatrixStorage, secureStore: any SecureStore)`, `let persistence: SessionPersistence`,
    `let sessionDelegate: SessionDelegate`, `func makeLocalStore(for: UserID) -> LocalStore`,
    `func makeClient(homeserver: URL, localStore: LocalStore) async throws -> Client`,
    `func restore() async throws -> (any MatrixSession)?`,
    `func restore(makeClient: (URL, LocalStore) async throws -> Client) async throws -> (any MatrixSession)?`.
  - `RustMatrixSession.make(client: Client, restorer: SessionRestorer, localStore: LocalStore)`.
  - `public static func RustMatrixClient.restoreSession(storage:) async throws -> (any MatrixSession)?`.
  - `public static func Matrix.restoreSession(storage: MatrixStorage) async throws -> (any MatrixSession)?`.

- [ ] **Step 1 : Écrire les tests qui échouent** — `Tests/MatrixClientKitRustTests/SessionRestorerTests.swift`

```swift
import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private let persistedHomeserver = URL(string: "https://matrix-client.persisted.example")!

private func makeRestorer() -> SessionRestorer {
    SessionRestorer(
        storage: .local(directory: FileManager.default.temporaryDirectory),
        secureStore: InMemorySecureStore()
    )
}

private func persistedSession() -> MatrixSessionData {
    MatrixSessionData(
        userID: UserID(rawValue: "@alice:persisted.example")!,
        deviceID: DeviceID(rawValue: "DEV1")!,
        homeserverURL: persistedHomeserver,
        accessToken: "jeton",
        refreshToken: nil,
        oauthData: nil,
        slidingSyncVersion: "native"
    )
}

@Test func restoringBuildsTheClientForThePersistedHomeserver() async throws {
    let restorer = makeRestorer()
    try restorer.persistence.save(persistedSession())
    var requestedHomeserver: URL?

    do {
        _ = try await restorer.restore { homeserver, _ in
            requestedHomeserver = homeserver
            throw MatrixError.storage(.unavailable)
        }
        Issue.record("la fabrique de client a échoué : la restauration doit relayer l'erreur")
    } catch {
        #expect(error as? MatrixError == .storage(.unavailable))
    }

    // La session appartient au serveur qui l'a émise : aucune autre adresse ne doit être utilisée.
    #expect(requestedHomeserver == persistedHomeserver)
    // Un échec de stockage ne dit rien de la validité de la session : elle est conservée.
    #expect(try restorer.persistence.load() != nil)
}

@Test func restoringWithoutAPersistedSessionBuildsNoClient() async throws {
    let restorer = makeRestorer()
    var clientWasBuilt = false

    let session = try await restorer.restore { _, _ in
        clientWasBuilt = true
        throw MatrixError.storage(.unavailable)
    }

    #expect(session == nil)
    #expect(!clientWasBuilt)
}
```

- [ ] **Step 2 : Lancer pour vérifier l'échec**

Run: `swift test --filter SessionRestorerTests`
Expected: échec de compilation, `cannot find 'SessionRestorer' in scope`.

- [ ] **Step 3 : Écrire le restaurateur** — `Sources/MatrixClientKitRust/SessionRestorer.swift`

```swift
import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Construit le client persistant d'un utilisateur et restaure la session enregistrée.
///
/// Partagé par ``RustMatrixClient`` et par ``RustMatrixClient/restoreSession(storage:)`` : la
/// restauration n'a besoin que du stockage, puisque l'adresse du homeserver fait partie de la
/// session persistée. Retenu par chaque session qu'il produit, pour que ``sessionDelegate`` vive
/// aussi longtemps qu'elle.
final class SessionRestorer: Sendable {
    let storage: MatrixStorage
    let secureStore: any SecureStore
    let persistence: SessionPersistence

    /// Le SDK s'en sert à chaque rafraîchissement de jeton : un delegate libéré ne persisterait
    /// plus rien, et l'utilisateur serait déconnecté au lancement suivant sans erreur visible.
    let sessionDelegate: SessionDelegate

    convenience init(storage: MatrixStorage) {
        self.init(storage: storage, secureStore: KeychainSecureStore(storage: storage))
    }

    init(storage: MatrixStorage, secureStore: any SecureStore) {
        self.storage = storage
        self.secureStore = secureStore
        let persistence = SessionPersistence(store: secureStore)
        self.persistence = persistence
        self.sessionDelegate = SessionDelegate(persistence: persistence)
    }

    func makeLocalStore(for userID: UserID) -> LocalStore {
        LocalStore(storage: storage, userID: userID, secureStore: secureStore)
    }

    /// Construit le client à store SQLite chiffré d'un utilisateur.
    func makeClient(homeserver: URL, localStore: LocalStore) async throws -> Client {
        do {
            let paths = try localStore.paths()
            try paths.createDirectoriesIfNeeded()

            return try await ClientBuilder()
                .homeserverUrl(url: homeserver.absoluteString)
                .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
                .setSessionDelegate(sessionDelegate: sessionDelegate)
                // Désactivé par défaut en amont : sans lui, un compte qui ne s'est jamais connecté
                // ailleurs n'a pas d'identité cross-signing, et la vérification échoue toujours
                // (spec 0.2, §2.8). Uniquement ici, jamais sur le client de poignée de main : son
                // store en mémoire perdrait les clés privées aussitôt créées.
                .autoEnableCrossSigning(autoEnableCrossSigning: true)
                .sqliteStore(
                    config: SqliteStoreBuilder(
                        dataPath: paths.dataDirectory.path,
                        cachePath: paths.cacheDirectory.path
                    )
                    .key(key: try localStore.encryptionKey())
                )
                .build()
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    func restore() async throws -> (any MatrixClientKitCore.MatrixSession)? {
        try await restore(makeClient: { homeserver, localStore in
            try await self.makeClient(homeserver: homeserver, localStore: localStore)
        })
    }

    /// - Parameter makeClient: fabrique du client. Couture de test : `Client` est une classe FFI
    ///   qu'un test ne peut pas construire, mais il peut vérifier l'adresse demandée.
    func restore(
        makeClient: (URL, LocalStore) async throws -> Client
    ) async throws -> (any MatrixClientKitCore.MatrixSession)? {
        guard let data = try persistence.load() else { return nil }

        let localStore = makeLocalStore(for: data.userID)
        // L'adresse persistée fait foi : c'est celle du serveur qui a émis la session, résolue
        // lors de la connexion.
        let client = try await makeClient(data.homeserverURL, localStore)
        do {
            try await client.restoreSession(session: SessionMapper.session(from: data))
            return try await RustMatrixSession.make(client: client, restorer: self, localStore: localStore)
        } catch {
            let mapped = ErrorMapper.mapAuthentication(error)

            // Une authentification refusée signifie que la session persistée est morte : la
            // conserver ferait échouer chaque lancement à l'identique, sans qu'aucune API
            // publique ne permette de l'effacer avant une nouvelle connexion réussie. Une panne
            // réseau, de stockage ou serveur, elle, ne dit rien sur la validité de la session —
            // l'effacer déconnecterait l'utilisateur à chaque démarrage hors ligne.
            //
            // Le store local part avec elle : rattaché à une session morte, il ne sera plus
            // jamais rouvert, et laisser sur disque un store crypto inutilisable est exactement
            // ce que la purge au logout existe pour éviter.
            if case .authentication = mapped {
                try? persistence.clear()
                try? localStore.purge()
            }

            throw mapped
        }
    }
}
```

- [ ] **Step 4 : Faire retenir le restaurateur par la session** — dans `Sources/MatrixClientKitRust/RustMatrixSession.swift`

Remplacer la signature et la construction du cycle de vie dans `make` :

```swift
    static func make(
        client: Client,
        restorer: SessionRestorer,
        localStore: LocalStore
    ) async throws -> RustMatrixSession {
        do {
            let persistence = restorer.persistence
```

(la suite du corps est inchangée jusqu'à l'appel de l'initialiseur), ajouter la propriété stockée
et son commentaire à côté de `client` :

```swift
    /// Retenu pour la durée de la session : il porte le `SessionDelegate` dont le SDK se sert à
    /// chaque rafraîchissement de jeton.
    private let restorer: SessionRestorer
```

ajouter le paramètre `restorer: SessionRestorer` à l'initialiseur privé (après `client`), son
affectation `self.restorer = restorer`, et passer `restorer: restorer` dans l'appel de `make`.

- [ ] **Step 5 : Déléguer depuis le client** — remplacer `Sources/MatrixClientKitRust/RustMatrixClient.swift`

```swift
import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``MatrixClient`` adossée au SDK Rust.
public final class RustMatrixClient: MatrixClientKitCore.MatrixClient {
    public let homeserver: URL

    private let restorer: SessionRestorer

    public init(homeserver: URL, storage: MatrixStorage) {
        self.homeserver = homeserver
        self.restorer = SessionRestorer(storage: storage)
    }

    /// Restaure la session persistée sans connaître l'adresse du homeserver, enregistrée avec elle.
    public static func restoreSession(storage: MatrixStorage) async throws -> (any MatrixClientKitCore.MatrixSession)? {
        try await SessionRestorer(storage: storage).restore()
    }

    /// Ouvre une session.
    ///
    /// La connexion se fait en deux temps, et c'est délibéré. Le store SQLite doit être **unique
    /// par utilisateur** (contrainte amont), donc son chemin dépend de l'identifiant — que le
    /// serveur ne révèle qu'une fois la connexion faite, alors que `ClientBuilder.build()` exige
    /// le chemin avant. La poignée de main se fait donc sur un client à store en mémoire, qui
    /// n'écrit rien sur disque ; l'identifiant obtenu détermine le chemin et la clé du vrai
    /// client, dans lequel la session est ensuite restaurée. Aucun store n'est jamais créé sous
    /// un chemin provisoire qu'il faudrait déplacer ensuite.
    ///
    /// Le vrai client est construit avec l'adresse que la session rapporte, comme à chaque
    /// restauration ultérieure : une seule source de vérité pour l'adresse d'une session.
    public func login(_ credentials: Credentials) async throws -> any MatrixClientKitCore.MatrixSession {
        do {
            let handshake = try await makeHandshakeClient()

            switch credentials {
            case let .password(username, password, deviceName):
                try await handshake.login(
                    username: username,
                    password: password,
                    initialDeviceName: deviceName,
                    deviceId: nil
                )
            }

            let data = try SessionMapper.sessionData(from: handshake.session())
            let localStore = restorer.makeLocalStore(for: data.userID)
            let client = try await restorer.makeClient(homeserver: data.homeserverURL, localStore: localStore)
            try await client.restoreSession(session: SessionMapper.session(from: data))

            try restorer.persistence.save(data)
            return try await RustMatrixSession.make(client: client, restorer: restorer, localStore: localStore)
        } catch {
            throw ErrorMapper.mapAuthentication(error)
        }
    }

    public func restoreSession() async throws -> (any MatrixClientKitCore.MatrixSession)? {
        try await restorer.restore()
    }

    /// Client éphémère servant uniquement à la poignée de main de connexion.
    ///
    /// Store en mémoire : rien n'est écrit sur disque avant que l'identifiant de l'utilisateur ne
    /// soit connu, donc aucun store orphelin ne subsiste si la connexion échoue.
    private func makeHandshakeClient() async throws -> Client {
        do {
            return try await ClientBuilder()
                .homeserverUrl(url: homeserver.absoluteString)
                .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
                .setSessionDelegate(sessionDelegate: restorer.sessionDelegate)
                .inMemoryStore()
                .build()
        } catch {
            throw ErrorMapper.map(error)
        }
    }
}
```

- [ ] **Step 6 : Exposer le point d'entrée** — dans `Sources/MatrixClientKit/MatrixClientKit.swift`, ajouter dans `enum Matrix`, après `client(homeserver:storage:)`

```swift
    /// Restores the persisted session, or returns `nil` when there is none.
    ///
    /// The homeserver's address is stored with the session, so this needs only the storage: call
    /// it at launch instead of keeping the homeserver URL a second time, where the two could
    /// disagree.
    ///
    /// ```swift
    /// if let session = try await Matrix.restoreSession(storage: .appGroup("group.com.example.app")) {
    ///     await session.sync.start()
    /// } else {
    ///     // Show the sign-in screen.
    /// }
    /// ```
    ///
    /// - Parameter storage: the storage the session was created with.
    /// - Throws: ``MatrixError/authentication(_:)`` when the homeserver rejects the stored session,
    ///   which is then erased; other errors leave it in place, so a launch without network does not
    ///   sign the user out.
    public static func restoreSession(storage: MatrixStorage) async throws -> (any MatrixSession)? {
        try await RustMatrixClient.restoreSession(storage: storage)
    }
```

- [ ] **Step 7 : Lancer les tests et le build iOS**

Run: `swift build --build-tests && swift test --skip MatrixClientKitIntegrationTests`
Expected: PASS.
Run: `xcodebuild build -quiet -scheme MatrixClientKit -destination 'generic/platform=iOS Simulator'`
Expected: aucune erreur.

- [ ] **Step 8 : Lint et commit** — deux commits, pour que le type reste fidèle au contenu

```bash
swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKitRust/SessionRestorer.swift Sources/MatrixClientKitRust/RustMatrixClient.swift Sources/MatrixClientKitRust/RustMatrixSession.swift Tests/MatrixClientKitRustTests/SessionRestorerTests.swift
git commit -m "fix: la restauration utilise l'adresse persistée, et le cross-signing est amorcé

restoreSession() construisait le client avec l'URL passée au client et
ignorait celle enregistrée avec la session. Le client persistant active
autoEnableCrossSigning : sans lui, un compte connecté uniquement via le
package n'avait jamais d'identité et ne pouvait pas être vérifié.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git add Sources/MatrixClientKit/MatrixClientKit.swift
git commit -m "feat: Matrix.restoreSession(storage:) restaure sans l'URL du homeserver

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11 : `MockMatrixClient` et erreurs scindées de `MockTimeline`

**Files:**
- Create: `Sources/MatrixClientKitMocks/MockMatrixClient.swift`
- Modify: `Sources/MatrixClientKitMocks/MockTimeline.swift`
- Test: `Tests/MatrixClientKitCoreTests/MockTests.swift` (ajouts en fin de fichier)

**Interfaces:**
- Consumes : `MockMatrixSession` (Task 9), `MatrixClient`, `Credentials` (existants).
- Produces : `public final class MockMatrixClient: MatrixClient` —
  `init(homeserver: URL = URL(string: "https://matrix.org")!, loginResult: Result<MockMatrixSession, MatrixError> = .success(MockMatrixSession()))`,
  `loginResult`, `restoreResult: Result<MockMatrixSession?, MatrixError>`, `loginAttempts: [Credentials]` ;
  `MockTimeline.paginationError: MatrixError?`. `MockTimeline.sendError` ne concerne plus que `send(_:)`
  — changement **cassant**.

- [ ] **Step 1 : Écrire les tests qui échouent**

```swift
@Test func paginationCanFailWhileSendingSucceeds() async throws {
    let timeline = MockTimeline()
    timeline.paginationError = .network(.timeout)

    await #expect(throws: MatrixError.network(.timeout)) {
        try await timeline.paginateBackwards(count: 20)
    }
    try await timeline.send(.text("toujours possible"))
    #expect(timeline.sentMessages == [.text("toujours possible")])
}

@Test func aSendErrorNoLongerBreaksPagination() async throws {
    let timeline = MockTimeline()
    timeline.sendError = .network(.offline)

    #expect(try await timeline.paginateBackwards(count: 20))
}

@Test func mockClientRecordsLoginAttemptsAndReturnsTheInjectedSession() async throws {
    let session = MockMatrixSession(userID: "@bob:matrix.org")
    let client = MockMatrixClient(loginResult: .success(session))

    let opened = try await client.login(.password(username: "bob", password: "secret", deviceName: nil))

    #expect(opened.userID.rawValue == "@bob:matrix.org")
    #expect(client.loginAttempts == [.password(username: "bob", password: "secret", deviceName: nil)])
}

@Test func mockClientCanRejectALogin() async {
    let client = MockMatrixClient(loginResult: .failure(.authentication(.invalidCredentials)))

    await #expect(throws: MatrixError.authentication(.invalidCredentials)) {
        _ = try await client.login(.password(username: "bob", password: "faux", deviceName: nil))
    }
}

@Test func mockClientRestoresNothingByDefault() async throws {
    let client = MockMatrixClient()
    #expect(try await client.restoreSession() == nil)

    client.restoreResult = .success(MockMatrixSession())
    #expect(try await client.restoreSession() != nil)
}
```

- [ ] **Step 2 : Lancer pour vérifier l'échec**

Run: `swift test --filter MockTests`
Expected: échec de compilation, `value of type 'MockTimeline' has no member 'paginationError'`.

- [ ] **Step 3 : Scinder les erreurs de `MockTimeline`** — dans `Sources/MatrixClientKitMocks/MockTimeline.swift`

Ajouter la propriété stockée à côté de `_sendError` :

```swift
    private var _paginationError: MatrixError?
```

Remplacer la documentation et la propriété `sendError`, et ajouter `paginationError` juste après :

```swift
    /// The error to throw from ``send(_:)``. `nil` by default, meaning sends succeed.
    public var sendError: MatrixError? {
        get { lock.withLock { _sendError } }
        set { lock.withLock { _sendError = newValue } }
    }

    /// The error to throw from ``paginateBackwards(count:)``. `nil` by default, meaning pagination
    /// succeeds.
    public var paginationError: MatrixError? {
        get { lock.withLock { _paginationError } }
        set { lock.withLock { _paginationError = newValue } }
    }
```

Remplacer la documentation de `paginateResult` par :

```swift
    /// What ``paginateBackwards(count:)`` returns when ``paginationError`` is not set. `true` by
    /// default.
```

Et dans `paginateBackwards(count:)`, remplacer `if let error = sendError { throw error }` par :

```swift
        if let error = paginationError { throw error }
```

Mettre à jour la documentation du type (ligne « or simulate a failed send ») :

```swift
/// A drivable timeline for tests: push snapshots on demand, observe what was sent, or simulate a
/// failed send or a failed pagination — independently.
```

- [ ] **Step 4 : Écrire `MockMatrixClient`** — `Sources/MatrixClientKitMocks/MockMatrixClient.swift`

```swift
import Foundation
import MatrixClientKitCore

/// A drivable ``MatrixClient`` for testing sign-in and launch flows.
///
/// ``login(_:)`` returns or throws ``loginResult`` and records the credentials it received;
/// ``restoreSession()`` returns or throws ``restoreResult``, `nil` by default.
///
/// ``Matrix/restoreSession(storage:)`` is a static function and cannot be replaced by this mock:
/// inject it into your code as a closure instead — see <doc:TestingWithMocks>.
public final class MockMatrixClient: MatrixClient, @unchecked Sendable {
    private let lock = NSLock()

    public let homeserver: URL

    private var _loginResult: Result<MockMatrixSession, MatrixError>
    private var _restoreResult: Result<MockMatrixSession?, MatrixError> = .success(nil)
    private var _loginAttempts: [Credentials] = []

    public init(
        homeserver: URL = URL(string: "https://matrix.org")!,
        loginResult: Result<MockMatrixSession, MatrixError> = .success(MockMatrixSession())
    ) {
        self.homeserver = homeserver
        self._loginResult = loginResult
    }

    /// What ``login(_:)`` returns or throws.
    public var loginResult: Result<MockMatrixSession, MatrixError> {
        get { lock.withLock { _loginResult } }
        set { lock.withLock { _loginResult = newValue } }
    }

    /// What ``restoreSession()`` returns or throws. `.success(nil)` by default: no stored session.
    public var restoreResult: Result<MockMatrixSession?, MatrixError> {
        get { lock.withLock { _restoreResult } }
        set { lock.withLock { _restoreResult = newValue } }
    }

    /// Every credential passed to ``login(_:)``, in order — including rejected ones.
    public var loginAttempts: [Credentials] {
        lock.withLock { _loginAttempts }
    }

    public func login(_ credentials: Credentials) async throws -> any MatrixSession {
        let result = lock.withLock {
            _loginAttempts.append(credentials)
            return _loginResult
        }
        return try result.get()
    }

    public func restoreSession() async throws -> (any MatrixSession)? {
        try restoreResult.get()
    }
}
```

- [ ] **Step 5 : Lancer les tests**

Run: `swift test --filter MockTests`
Expected: PASS. Le test existant `mockTimelineCanSimulateAFailure` (échec d'envoi) reste vert.

- [ ] **Step 6 : Lint et commit**

```bash
swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKitMocks/MockMatrixClient.swift Sources/MatrixClientKitMocks/MockTimeline.swift Tests/MatrixClientKitCoreTests/MockTests.swift
git commit -m "feat!: MockMatrixClient, et erreurs d'envoi et de pagination séparées

MockTimeline.sendError ne fait plus échouer que send(_:) ; la pagination a
son propre paginationError. Un test qui s'appuyait sur sendError pour faire
échouer la pagination doit passer à paginationError.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 12 : Chaînes visibles en anglais

**Files:**
- Modify: `Sources/MatrixClientKitRust/Bridge/TimelineMapper.swift`
- Modify: `Sources/MatrixClientKitRust/Bridge/SessionMapper.swift`
- Modify: `Sources/MatrixClientKitCore/Errors/MatrixError.swift`
- Modify: `Sources/MatrixClientKitCore/Models/MatrixSessionData.swift`
- Modify: `Tests/MatrixClientKitRustTests/MessageContentTests.swift`
- Create: `Tests/MatrixClientKitRustTests/TimelineStringsTests.swift`
- Modify: `Tests/MatrixClientKitCoreTests/MatrixErrorTests.swift` (ajout)

**Interfaces:**
- Consumes : `TimelineMapper` (existant).
- Produces : `TimelineMapper.reason(from: QueueWedgeError) -> String` passe de `private` à interne ;
  nouveau `static func decryptionFailureReason(for message: EncryptedMessage) -> String`. Aucune
  signature publique ne change.

Principe (spec §9) : toute chaîne qui parvient à une application — `reason`, `description` d'un
cas `.unsupported`, message de `MatrixError`, `errorDescription` — est en anglais. Les commentaires
internes restent en français.

- [ ] **Step 1 : Écrire les tests qui échouent** — `Tests/MatrixClientKitRustTests/TimelineStringsTests.swift`

```swift
import Testing
import MatrixRustSDK
@testable import MatrixClientKitRust

@Test func eachDecryptionFailureCauseHasItsOwnEnglishReason() {
    let expected: [(UtdCause, String)] = [
        (.unknown, "The message could not be decrypted."),
        (.sentBeforeWeJoined, "Sent before you joined the room."),
        (.verificationViolation, "The sender's verified identity has changed."),
        (.unsignedDevice, "Sent from a device its owner has not verified."),
        (.unknownDevice, "Sent from an unknown device."),
        (.historicalMessageAndBackupIsDisabled, "Sent before this device signed in, and key backup is off."),
        (.historicalMessageAndDeviceIsUnverified, "Sent before this device signed in; verify this device to read it."),
        (.withheldForUnverifiedOrInsecureDevice, "The sender does not share keys with unverified devices."),
        (.withheldBySender, "The sender withheld the keys for this message."),
    ]

    for (cause, reason) in expected {
        #expect(
            TimelineMapper.decryptionFailureReason(for: .megolmV1AesSha2(sessionId: "session", cause: cause)) == reason
        )
    }
}

@Test func otherEncryptionSchemesGetTheGenericReason() {
    #expect(TimelineMapper.decryptionFailureReason(for: .unknown) == "The message could not be decrypted.")
    #expect(
        TimelineMapper.decryptionFailureReason(for: .olmV1Curve25519AesSha2(senderKey: "key"))
            == "The message could not be decrypted.")
}

@Test func sendFailureReasonsAreInEnglish() {
    #expect(
        TimelineMapper.reason(from: .crossVerificationRequired)
            == "This session must be verified before it can send messages.")
    #expect(TimelineMapper.reason(from: .missingMediaContent) == "The media to send is missing from the cache.")
    #expect(TimelineMapper.reason(from: .invalidMimeType(mimeType: "x/y")) == "Unsupported content type: x/y.")
    #expect(TimelineMapper.reason(from: .genericApiError(msg: "")) == "Sending failed.")
    #expect(TimelineMapper.reason(from: .genericApiError(msg: "Server said no")) == "Server said no")
}
```

Ajouter en fin de `Tests/MatrixClientKitCoreTests/MatrixErrorTests.swift` :

```swift
@Test func errorDescriptionsAreInEnglish() {
    #expect(MatrixError.network(.offline).errorDescription == "Network error: offline")
    #expect(MatrixError.rateLimited(retryAfter: nil).errorDescription == "Too many requests. Try again later.")
    #expect(
        MatrixError.unexpected(message: "", details: nil).errorDescription == "Unexpected Matrix SDK error.")
}
```

Dans `Tests/MatrixClientKitRustTests/MessageContentTests.swift`, remplacer
`#expect(reason.contains("vérifiée"))` par `#expect(reason.contains("verified"))`, et
`reason: "le média à envoyer est introuvable dans le cache",` par
`reason: "The media to send is missing from the cache.",`.

- [ ] **Step 2 : Lancer pour vérifier l'échec**

Run: `swift test --filter "TimelineStringsTests|MatrixErrorTests|MessageContentTests"`
Expected: échec de compilation, `type 'TimelineMapper' has no member 'decryptionFailureReason'`.

- [ ] **Step 3 : Traduire `TimelineMapper`** — dans `Sources/MatrixClientKitRust/Bridge/TimelineMapper.swift`

Remplacer la fonction `reason(from:)` (retirer `private`) :

```swift
    /// Traduit la cause d'un envoi bloqué en une phrase lisible.
    ///
    /// - Important: `reason` finit dans une interface. Y déverser `String(describing:)` d'un enum
    ///   amont y ferait apparaître des identifiants Swift.
    static func reason(from error: QueueWedgeError) -> String {
        switch error {
        case .insecureDevices:
            "The room contains unverified devices."
        case .identityViolations:
            "A participant's identity changed and must be verified again."
        case .crossVerificationRequired:
            "This session must be verified before it can send messages."
        case .missingMediaContent:
            "The media to send is missing from the cache."
        case let .invalidMimeType(mimeType):
            "Unsupported content type: \(mimeType)."
        case let .genericApiError(msg):
            msg.isEmpty ? "Sending failed." : msg
        }
    }

    /// Explique pourquoi un message n'a pas pu être déchiffré, à partir de la cause amont.
    ///
    /// - Note: seule la variante Megolm porte une cause ; les autres reçoivent la phrase générique.
    static func decryptionFailureReason(for message: EncryptedMessage) -> String {
        guard case let .megolmV1AesSha2(_, cause) = message else {
            return "The message could not be decrypted."
        }

        switch cause {
        case .unknown:
            return "The message could not be decrypted."
        case .sentBeforeWeJoined:
            return "Sent before you joined the room."
        case .verificationViolation:
            return "The sender's verified identity has changed."
        case .unsignedDevice:
            return "Sent from a device its owner has not verified."
        case .unknownDevice:
            return "Sent from an unknown device."
        case .historicalMessageAndBackupIsDisabled:
            return "Sent before this device signed in, and key backup is off."
        case .historicalMessageAndDeviceIsUnverified:
            return "Sent before this device signed in; verify this device to read it."
        case .withheldForUnverifiedOrInsecureDevice:
            return "The sender does not share keys with unverified devices."
        case .withheldBySender:
            return "The sender withheld the keys for this message."
        }
    }
```

Remplacer, dans le même fichier :
- `kind: .unsupported(description: "début de timeline")` par `kind: .unsupported(description: "Start of the timeline")` ;
- `event.eventTypeRaw ?? "événement non pris en charge"` par `event.eventTypeRaw ?? "Unsupported event"` ;
- `"expéditeur invalide : \(event.sender)"` par `"Invalid sender: \(event.sender)"` ;
- le cas UTD :

```swift
        case let .unableToDecrypt(msg):
            return .unableToDecrypt(reason: decryptionFailureReason(for: msg))
```

- [ ] **Step 4 : Traduire `SessionMapper`, `MatrixSessionData` et `MatrixError`**

`Sources/MatrixClientKitRust/Bridge/SessionMapper.swift` :
- `"Identifiant utilisateur invalide renvoyé par le serveur"` → `"The server returned an invalid user ID."` ;
- `"Identifiant d'appareil invalide renvoyé par le serveur"` → `"The server returned an invalid device ID."` ;
- `"Adresse de homeserver invalide"` → `"The server returned an invalid homeserver URL."`.

`Sources/MatrixClientKitCore/Models/MatrixSessionData.swift` :
- `"identifiant utilisateur invalide : \(raw)"` → `"Invalid user ID: \(raw)"` ;
- `"identifiant d'appareil invalide : \(raw)"` → `"Invalid device ID: \(raw)"`.

`Sources/MatrixClientKitCore/Errors/MatrixError.swift`, dans `errorDescription` :

```swift
        switch self {
        case let .authentication(value): return "Authentication error: \(value)"
        case let .network(value): return "Network error: \(value)"
        case let .rateLimited(delay):
            guard let delay else { return "Too many requests. Try again later." }
            return "Too many requests. Try again in \(delay)."
        case let .permission(value): return "Permission denied: \(value)"
        case let .notFound(resource): return "Not found: \(resource)"
        case let .encryption(value): return "Encryption error: \(value)"
        case let .server(value): return "Server error: \(value)"
        case let .storage(value): return "Storage error: \(value)"
        case let .unexpected(message, details):
            // Toute erreur amont non encore distinguée atterrit ici (règle d'évolution du type),
            // y compris celles dont le SDK ne fournit aucun message. Rendre la chaîne vide
            // laisserait une interface afficher un cadre d'erreur sans une ligne de texte.
            let text = message.isEmpty ? "Unexpected Matrix SDK error." : message
            guard let details, !details.isEmpty else { return text }
            return "\(text) (\(details))"
        }
```

- [ ] **Step 5 : Balayer les chaînes restantes**

Run:
```bash
grep -rnE '"[^"]*([àâçéèêëîïôùû]| de | le | la | les | des | du | est | pas |invalide|introuvable)[^"]*"' Sources | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//'
```
Expected: aucune ligne, hors commentaires. Toute chaîne restante qui peut atteindre une application
(message d'erreur, description, `reason`) est traduite dans ce même commit ; ajouter un test si elle
est produite par une fonction testable.

- [ ] **Step 6 : Lancer les tests**

Run: `swift test --skip MatrixClientKitIntegrationTests`
Expected: PASS.

- [ ] **Step 7 : Lint et commit**

```bash
swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKitRust/Bridge/TimelineMapper.swift Sources/MatrixClientKitRust/Bridge/SessionMapper.swift Sources/MatrixClientKitCore/Errors/MatrixError.swift Sources/MatrixClientKitCore/Models/MatrixSessionData.swift Tests/MatrixClientKitRustTests/TimelineStringsTests.swift Tests/MatrixClientKitRustTests/MessageContentTests.swift Tests/MatrixClientKitCoreTests/MatrixErrorTests.swift
git commit -m "fix: chaînes visibles en anglais, et motif d'échec de déchiffrement explicite

Le motif d'un message indéchiffrable était une chaîne française en dur, sans
cause. Il est désormais dérivé de la cause amont. Les motifs d'échec d'envoi,
les descriptions d'éléments non pris en charge, les messages d'erreur de
session et errorDescription de MatrixError étaient eux aussi en français.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 13 : Suite d'intégration 0.2 et contrat de `start()`

**Files:**
- Create: `Tests/MatrixClientKitIntegrationTests/IntegrationSupport.swift`
- Modify: `Tests/MatrixClientKitIntegrationTests/LoginAndSyncTests.swift` (retrait des helpers déplacés)
- Create: `Tests/MatrixClientKitIntegrationTests/EncryptionAndSessionTests.swift`
- Modify: `Tests/MatrixClientKitIntegrationTests/README.md`
- Modify: `Sources/MatrixClientKitCore/Services/SyncController.swift` (documentation de `start()`)

**Interfaces:**
- Consumes : toute l'API publique 0.2 via `import MatrixClientKit`.
- Produces : helpers internes au target d'intégration — `IntegrationConfiguration` (avec
  `recoveryKey`, `freshUsername`, `freshPassword`, `hasRecoveryKey`, `hasFreshAccount`),
  `IntegrationClient`, `makeClient(_:)`, `cleaningUp(_:)`, `removeDirectory(_:)`,
  `signIn(_:username:password:deviceName:)`, `firstValue(of:where:)`, `rawAccessToken(_:)`,
  `logOutEverywhere(_:accessToken:)`, `sqliteFiles(in:)`.

Ces tests ne tournent pas en CI. Ils s'exécutent à la main (Task 15) avec des identifiants fournis
par l'utilisateur — **ne jamais les inventer ni les écrire dans un fichier du dépôt**. Les cas
chiffrés ne modifient jamais la clé de récupération du compte (spec §12) : `enableRecovery`,
`resetRecoveryKey` et `disableRecovery` restent couverts par les seuls tests unitaires.

Le cas « deux sessions du même utilisateur » a une limite connue : le Keychain ne garde qu'une
session persistée par service, donc la seconde connexion écrase l'entrée de la première. Sans effet
ici — aucun de ces cas ne restaure la première session —, mais à rappeler en commentaire.

- [ ] **Step 1 : Documenter le contrat de `start()`** — dans `Sources/MatrixClientKitCore/Services/SyncController.swift`, remplacer la documentation de `start()`

```swift
    /// Starts syncing with the homeserver.
    ///
    /// Calling `start()` while syncing is already running has no effect; after
    /// ``SyncState/offline``, ``SyncState/error`` or ``SyncState/terminated`` it starts syncing
    /// again. Call it whenever the application returns to the foreground.
    func start() async
```

Ce contrat est celui de l'amont (`SyncService::start`, spec §2.9) ; le cas d'intégration
`startingSyncTwiceKeepsItRunning` l'épingle.

- [ ] **Step 2 : Extraire les helpers** — créer `Tests/MatrixClientKitIntegrationTests/IntegrationSupport.swift`

```swift
import Testing
import Foundation
import MatrixClientKit

/// Configuration lue dans l'environnement. Absente, la suite entière est ignorée.
struct IntegrationConfiguration {
    let homeserver: URL
    let username: String
    let password: String
    /// Clé de récupération du compte de test, configurée une fois (par exemple avec Element).
    let recoveryKey: String?
    /// Compte **jamais utilisé**, pour vérifier l'amorçage du cross-signing. Utile une seule fois.
    let freshUsername: String?
    let freshPassword: String?

    static var current: IntegrationConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        guard
            let homeserver = environment["MATRIX_TEST_HOMESERVER"].flatMap(URL.init(string:)),
            let username = environment["MATRIX_TEST_USERNAME"],
            let password = environment["MATRIX_TEST_PASSWORD"]
        else { return nil }

        return IntegrationConfiguration(
            homeserver: homeserver,
            username: username,
            password: password,
            recoveryKey: environment["MATRIX_TEST_RECOVERY_KEY"],
            freshUsername: environment["MATRIX_TEST_FRESH_USERNAME"],
            freshPassword: environment["MATRIX_TEST_FRESH_PASSWORD"]
        )
    }

    static var isAvailable: Bool { current != nil }
    static var hasRecoveryKey: Bool { current?.recoveryKey != nil }
    static var hasFreshAccount: Bool { current?.freshUsername != nil && current?.freshPassword != nil }
}

/// Client d'intégration et répertoire qui l'héberge.
///
/// Le répertoire est rendu à l'appelant : sans cela, chaque exécution laisse sous le répertoire
/// temporaire un store SQLite contenant une vraie session — jetons compris.
struct IntegrationClient {
    let client: any MatrixClient
    let directory: URL
}

func makeClient(_ configuration: IntegrationConfiguration) -> IntegrationClient {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mck-integration-\(UUID().uuidString)", isDirectory: true)
    return IntegrationClient(
        client: Matrix.client(homeserver: configuration.homeserver, storage: .local(directory: directory)),
        directory: directory
    )
}

/// Exécute un nettoyage même lorsque la tâche de test a été annulée — par exemple par
/// `.timeLimit` lorsqu'un flux attendu ne produit jamais la valeur cherchée. Une tâche détachée
/// n'hérite pas de l'annulation de son appelant, donc `session.logout()` a une vraie chance
/// d'atteindre le serveur au lieu d'échouer immédiatement sur un contexte déjà annulé.
func cleaningUp(_ body: @escaping @Sendable () async -> Void) async {
    await Task.detached(operation: body).value
}

/// Supprime le répertoire de travail d'une exécution. L'échec est ignoré : le nettoyage ne doit
/// jamais masquer le résultat du test qu'il suit.
func removeDirectory(_ directory: URL) {
    try? FileManager.default.removeItem(at: directory)
}

/// Attend la première valeur d'un flux qui satisfait `predicate`. La borne `.timeLimit` du test
/// fait échouer une attente qui n'aboutit jamais.
func firstValue<Element: Sendable>(
    of stream: AsyncStream<Element>,
    where predicate: (Element) -> Bool
) async -> Element? {
    for await value in stream where predicate(value) {
        return value
    }
    return nil
}

/// Se connecte dans un répertoire neuf et attend que la sync tourne.
func signIn(
    _ configuration: IntegrationConfiguration,
    username: String? = nil,
    password: String? = nil,
    deviceName: String
) async throws -> (session: any MatrixSession, directory: URL) {
    let integration = makeClient(configuration)
    let session = try await integration.client.login(
        .password(
            username: username ?? configuration.username,
            password: password ?? configuration.password,
            deviceName: deviceName
        )
    )

    // Abonnement posé avant `start()` : le flux de sync ne rejoue pas l'état courant.
    let states = session.sync.state
    await session.sync.start()
    _ = await firstValue(of: states) { $0 == .running }

    return (session, integration.directory)
}

/// Obtient un jeton d'accès par une connexion HTTP brute, hors SDK — un appareil de plus sur le
/// compte, qui disparaît avec `logOutEverywhere`.
func rawAccessToken(_ configuration: IntegrationConfiguration) async throws -> String {
    var request = URLRequest(url: configuration.homeserver.appending(path: "_matrix/client/v3/login"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
        "type": "m.login.password",
        "identifier": ["type": "m.id.user", "user": configuration.username],
        "password": configuration.password,
        "initial_device_display_name": "MatrixClientKit Integration (raw)",
    ])

    let (data, _) = try await URLSession.shared.data(for: request)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return try #require(object?["access_token"] as? String)
}

/// Révoque toutes les sessions du compte, comme « se déconnecter de tous les appareils » depuis un
/// autre client.
func logOutEverywhere(_ configuration: IntegrationConfiguration, accessToken: String) async throws {
    var request = URLRequest(url: configuration.homeserver.appending(path: "_matrix/client/v3/logout/all"))
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data("{}".utf8)

    let (_, response) = try await URLSession.shared.data(for: request)
    #expect((response as? HTTPURLResponse)?.statusCode == 200)
}

/// Fichiers SQLite présents sous un répertoire de stockage.
func sqliteFiles(in directory: URL) -> [URL] {
    let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
    let urls = enumerator?.allObjects.compactMap { $0 as? URL } ?? []
    return urls.filter { $0.lastPathComponent.contains("sqlite") }
}
```

Dans `Tests/MatrixClientKitIntegrationTests/LoginAndSyncTests.swift`, supprimer les définitions
désormais partagées : `private struct IntegrationConfiguration` (de son commentaire
« Configuration lue dans l'environnement » à la fin du type), `private struct IntegrationClient`,
`private func makeClient`, `private func cleaningUp`, `private func removeDirectory`, avec leurs
commentaires. Garder les imports et la suite `LoginAndSyncTests` telle quelle.

Run: `swift build --build-tests`
Expected: compilation réussie.

- [ ] **Step 3 : Écrire les cas 0.2** — `Tests/MatrixClientKitIntegrationTests/EncryptionAndSessionTests.swift`

```swift
import Testing
import Foundation
import MatrixClientKit

/// Clé de récupération au bon format mais délibérément fausse.
private let wrongRecoveryKey = "EsTc 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000"

private func isIncomingRequest(_ state: SessionVerificationState) -> Bool {
    if case .incomingRequest = state { return true }
    return false
}

private func isComparing(_ state: SessionVerificationState) -> Bool {
    if case .comparing = state { return true }
    return false
}

// Sérialisée : tous les cas utilisent le même compte, et l'un d'eux révoque toutes ses sessions.
@Suite(.enabled(if: IntegrationConfiguration.isAvailable), .serialized)
struct EncryptionAndSessionTests {

    @Test(.timeLimit(.minutes(1)))
    func restoringNeedsOnlyTheStorage() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        var signedIn: (session: any MatrixSession, directory: URL)? = try await signIn(
            configuration, deviceName: "MatrixClientKit Integration (restore)")
        let directory = try #require(signedIn?.directory)
        let userID = try #require(signedIn?.session.userID)
        await signedIn?.session.sync.stop()

        // Libère le premier client : deux clients ouverts sur le même store SQLite se disputeraient
        // ses fichiers.
        signedIn = nil

        let restored = try #require(try await Matrix.restoreSession(storage: .local(directory: directory)))
        #expect(restored.userID == userID)

        await cleaningUp {
            try? await restored.logout()
            removeDirectory(directory)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func startingSyncTwiceKeepsItRunning() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let (session, directory) = try await signIn(configuration, deviceName: "MatrixClientKit Integration (sync)")

        let observed = Task {
            var states: [SyncState] = []
            for await state in session.sync.state {
                states.append(state)
            }
            return states
        }
        try await Task.sleep(for: .milliseconds(200))

        await session.sync.start()
        try await Task.sleep(for: .seconds(3))
        observed.cancel()
        let states = await observed.value

        // Un second démarrage qui relancerait la sync repasserait par un état d'arrêt.
        #expect(!states.contains(.idle))
        #expect(!states.contains(.terminated))

        await cleaningUp {
            await session.sync.stop()
            try? await session.logout()
            removeDirectory(directory)
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func aServerSideLogoutSignsTheSessionOutAndErasesItsStore() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let (session, directory) = try await signIn(
            configuration, deviceName: "MatrixClientKit Integration (server logout)")
        #expect(!sqliteFiles(in: directory).isEmpty, "le store doit exister avant la déconnexion")

        let authStates = session.authState
        let token = try await rawAccessToken(configuration)
        try await logOutEverywhere(configuration, accessToken: token)

        // La sync suivante reçoit M_UNKNOWN_TOKEN : le SDK appelle le delegate, la session purge
        // puis publie `.signedOut`.
        #expect(await firstValue(of: authStates) { $0 == .signedOut } == .signedOut)
        #expect(sqliteFiles(in: directory).isEmpty)

        await cleaningUp { removeDirectory(directory) }
    }

    @Test(.enabled(if: IntegrationConfiguration.hasRecoveryKey), .timeLimit(.minutes(2)))
    func aWrongRecoveryKeyIsRejectedAndTheRightOneVerifiesTheDevice() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let recoveryKey = try #require(configuration.recoveryKey)
        let (session, directory) = try await signIn(
            configuration, deviceName: "MatrixClientKit Integration (recovery)")

        _ = await firstValue(of: session.encryption.recoveryState) { $0 != .unknown }

        // Épingle le mappage de spec §7.1, fondé sur le message amont.
        await #expect(throws: MatrixError.encryption(.invalidRecoveryKey)) {
            try await session.encryption.recover(with: wrongRecoveryKey)
        }

        try await session.encryption.recover(with: recoveryKey)
        #expect(await firstValue(of: session.encryption.verificationStatus) { $0 == .verified } == .verified)
        #expect(await firstValue(of: session.encryption.recoveryState) { $0 == .enabled } == .enabled)

        await cleaningUp {
            await session.sync.stop()
            try? await session.logout()
            removeDirectory(directory)
        }
    }

    @Test(.enabled(if: IntegrationConfiguration.hasRecoveryKey), .timeLimit(.minutes(3)))
    func anotherDeviceVerifiesThisOne() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let recoveryKey = try #require(configuration.recoveryKey)

        // A : appareil vérifié grâce à la clé de récupération.
        let (verified, verifiedDirectory) = try await signIn(
            configuration, deviceName: "MatrixClientKit Integration (A)")
        _ = await firstValue(of: verified.encryption.recoveryState) { $0 != .unknown }
        try await verified.encryption.recover(with: recoveryKey)
        _ = await firstValue(of: verified.encryption.verificationStatus) { $0 == .verified }

        // B : nouvel appareil à vérifier. Les deux sessions partagent l'entrée Keychain de session
        // persistée (une par service) : B écrase celle de A, sans effet ici puisque rien n'est
        // restauré.
        let (newcomer, newcomerDirectory) = try await signIn(
            configuration, deviceName: "MatrixClientKit Integration (B)")
        _ = await firstValue(of: newcomer.encryption.verificationStatus) { $0 == .unverified }
        #expect(try await newcomer.encryption.hasDevicesToVerifyAgainst())

        // A obtient son contrôleur de vérification sur le changement d'état qui vient de le rendre
        // vérifié ; on lui laisse le temps d'y poser son delegate avant que la demande n'arrive.
        try await Task.sleep(for: .seconds(2))

        let onA = verified.encryption.sessionVerification
        let onB = newcomer.encryption.sessionVerification

        try await onB.requestVerification()
        _ = await firstValue(of: onA.state, where: isIncomingRequest)
        try await onA.accept()
        _ = await firstValue(of: onB.state) { $0 == .ready }
        try await onB.startSAS()

        let shownOnB = await firstValue(of: onB.state, where: isComparing)
        let shownOnA = await firstValue(of: onA.state, where: isComparing)
        // C'est ce que l'utilisateur compare : les deux appareils doivent montrer la même chose.
        #expect(shownOnA != nil)
        #expect(shownOnA == shownOnB)

        try await onA.approve()
        try await onB.approve()
        #expect(await firstValue(of: onB.state) { $0.isFinished } == .verified)
        #expect(await firstValue(of: newcomer.encryption.verificationStatus) { $0 == .verified } == .verified)

        await cleaningUp {
            await verified.sync.stop()
            await newcomer.sync.stop()
            try? await newcomer.logout()
            try? await verified.logout()
            removeDirectory(verifiedDirectory)
            removeDirectory(newcomerDirectory)
        }
    }

    @Test(.enabled(if: IntegrationConfiguration.hasFreshAccount), .timeLimit(.minutes(1)))
    func aFreshAccountGetsACrossSigningIdentityAtSignIn() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let (session, directory) = try await signIn(
            configuration,
            username: configuration.freshUsername,
            password: configuration.freshPassword,
            deviceName: "MatrixClientKit Integration (fresh)"
        )

        // Sans `autoEnableCrossSigning`, l'état resterait `.unverified` : aucune identité à signer.
        #expect(await firstValue(of: session.encryption.verificationStatus) { $0 == .verified } == .verified)

        await cleaningUp {
            await session.sync.stop()
            try? await session.logout()
            removeDirectory(directory)
        }
    }
}
```

- [ ] **Step 4 : Compiler**

Run: `swift build --build-tests && swift test --skip MatrixClientKitIntegrationTests`
Expected: compilation réussie ; les suites d'intégration sont ignorées sans variables
d'environnement, et le reste passe.

- [ ] **Step 5 : Mettre à jour le README de la suite** — `Tests/MatrixClientKitIntegrationTests/README.md`

Remplacer le bloc « Running them » par :

```markdown
## Running them

    MATRIX_TEST_HOMESERVER=https://your-homeserver \
    MATRIX_TEST_USERNAME=username \
    MATRIX_TEST_PASSWORD=secret \
    MATRIX_TEST_ROOM_ID='!room:your-homeserver' \
    MATRIX_TEST_RECOVERY_KEY='EsTc …' \
    swift test --filter MatrixClientKitIntegrationTests

Without the first three variables the suite is skipped, which is the expected behaviour in CI.

Optional variables:

- `MATRIX_TEST_RECOVERY_KEY` enables the verification and recovery cases. Set up recovery **once**
  on the test account — for instance by signing in with Element — and keep its key. The tests never
  change it, so it stays valid from one run to the next.
- `MATRIX_TEST_FRESH_USERNAME` and `MATRIX_TEST_FRESH_PASSWORD` name an account that has **never
  signed in anywhere**. They enable the case checking that signing in creates a cross-signing
  identity. It is meaningful only on the account's first run: register a new account each time you
  want to check it.
```

Ajouter en fin de la section « Requirements on the test account » :

```markdown
- `aServerSideLogoutSignsTheSessionOutAndErasesItsStore` signs **every** session of the account out,
  as "sign out of all devices" would. Anything else signed in to that account is signed out too.
- The Keychain holds one persisted session per service, so the verification case — which signs the
  same account in twice in one process — overwrites the first session's entry with the second's.
  The case never restores a session, so this does not affect it.
```

- [ ] **Step 6 : Lint et commits**

```bash
swift format lint --recursive --strict Sources Tests
git add Sources/MatrixClientKitCore/Services/SyncController.swift
git commit -m "docs: SyncController.start() documente son idempotence

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git add Tests/MatrixClientKitIntegrationTests
git commit -m "test: suite d'intégration de la 0.2 — vérification, récupération, déconnexion serveur

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 14 : Documentation

**Files:**
- Create: `Sources/MatrixClientKit/Documentation.docc/VerificationAndRecovery.md`
- Modify: `Sources/MatrixClientKit/Documentation.docc/MatrixClientKit.md`
- Modify: `Sources/MatrixClientKit/Documentation.docc/TestingWithMocks.md`
- Modify: `Sources/MatrixClientKit/Documentation.docc/GettingStarted.md`
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-09-13-matrixclientkit-design.md`

**Interfaces:**
- Consumes : API publique 0.2 (noms exacts des Tasks 1–11).
- Produces : documentation uniquement. Tout ce qui est écrit ici est en anglais, sauf la spec 0.1.

- [ ] **Step 1 : Écrire l'article DocC** — `Sources/MatrixClientKit/Documentation.docc/VerificationAndRecovery.md`

````markdown
# Verification and recovery

Verify a new device, set up recovery, and restore a user's encrypted history.

## Overview

End-to-end encryption is always on. What an application drives is **trust**: whether this device is
verified — which lets it read history and be trusted by others — and whether the user's keys are
recoverable if every device is lost.

Everything goes through ``MatrixSession/encryption``, an ``EncryptionService``. Its three state
streams start with the current value, so a screen opened at any time shows the right thing.

## Decide what to offer

Right after sign-in, read the state and pick one path:

| Condition | Offer |
| --- | --- |
| ``VerificationStatus/unverified`` and ``EncryptionService/hasDevicesToVerifyAgainst()`` | "Verify with another device" first, "Use your recovery key" second |
| ``RecoveryState/incomplete`` | "Enter your recovery key" |
| ``RecoveryState/disabled`` and not ``EncryptionService/backupExistsOnServer()`` | "Set up recovery" |
| Signing out, ``EncryptionService/isLastDevice()`` and recovery disabled | Warn that encrypted history will be lost |

```swift
let encryption = session.encryption

for await status in encryption.verificationStatus where status != .unknown {
    if status == .unverified, try await encryption.hasDevicesToVerifyAgainst() {
        showVerifyWithAnotherDevice()
    }
    break
}
```

``VerificationStatus/unknown`` lasts until the first sync has loaded the user's identity: wait for
another value before deciding.

## Verify with another device

``EncryptionService/sessionVerification`` publishes the flow as a state machine. Observe
``SessionVerification/state`` and call the command the current state allows:

```swift
let verification = session.encryption.sessionVerification

Task {
    for await state in verification.state {
        switch state {
        case .incomingRequest(let request):
            showIncomingRequest(from: request.deviceDisplayName ?? request.deviceID.rawValue)
        case .ready:
            try await verification.startSAS()
        case .comparing(.emojis(let emojis)):
            showEmojis(emojis)            // then approve() or decline()
        case .comparing(.decimals(let numbers)):
            showNumbers(numbers)
        case .verified:
            showSuccess()
        case .cancelled, .failed:
            showFailure()
        case .idle, .waitingForOtherDevice, .startingSAS, .confirming:
            showProgress()
        }
    }
}

try await verification.requestVerification()
```

A command called in a state that does not allow it throws ``MatrixError/unexpected(message:details:)``
without doing anything. Only one verification runs at a time: a request that arrives during a flow
is ignored.

``SASEmoji/description`` is the English name from the Matrix specification. To localise it, use
``SASEmoji/index`` against the specification's SAS emoji table.

## Set up recovery

```swift
let key = try await session.encryption.enableRecovery { progress in
    if case .backingUp(let uploaded, let total) = progress {
        print("Backed up \(uploaded) of \(total) keys")
    }
}
showRecoveryKey(key.rawValue)   // the only time the key is available
```

``RecoveryKey`` redacts its description: interpolating it in a log never leaks it. Show
``RecoveryKey/rawValue`` to the user, once, and ask them to store it.

``EncryptionService/resetRecoveryKey()`` replaces the key — the previous one stops working —
and ``EncryptionService/disableRecovery()`` deletes the backup from the server.

## Restore with the recovery key

```swift
do {
    try await session.encryption.recover(with: typedKey)
} catch MatrixError.encryption(.invalidRecoveryKey) {
    showWrongKey()
}
```

A successful recovery verifies this device: ``EncryptionService/verificationStatus`` moves to
``VerificationStatus/verified``.

## Signed out by the server

When the user removes this device from another one, the homeserver ends the session.
``MatrixSession/authState`` reports it:

```swift
for await state in session.authState {
    switch state {
    case .signedIn: continue
    case .softLoggedOut:
        try? await session.logout()   // nothing was erased yet; sign in again afterwards
        showSignIn()
    case .signedOut:
        showSignIn()                  // local data is already erased
    }
}
```

## What is not covered yet

Verifying other users, QR-code verification — which the bundled SDK does not expose — and resetting
a lost cryptographic identity are not part of this version.
````

- [ ] **Step 2 : Mettre à jour la page d'accueil DocC** — `Sources/MatrixClientKit/Documentation.docc/MatrixClientKit.md`

Remplacer la section `## What v0.1 covers` (du titre jusqu'à la liste « Two behaviours to know »
exclue) par :

```markdown
## What v0.2 covers

This page can be read on its own — the Swift Package Index renders it without the repository's
README — so the limits of this milestone are restated here.

v0.2 covers password authentication, persisted sessions (restorable from storage alone), syncing,
the room list, timelines, sending text messages, device verification by emoji comparison, recovery
and key backup, and notification of a session ended by the server.

End-to-end encryption is **active**: the Rust SDK handles it, with no opt-in. What v0.2 does **not**
expose:

- QR-code verification, verification of other users, and identity reset;
- push notifications and the associated service extension;
- media, read receipts, typing indicators, presence and profiles;
- OAuth / OIDC, and `MatrixClient.loginDetails()`.
```

Dans la liste « Getting started » des Topics, ajouter `- <doc:VerificationAndRecovery>` après
`- <doc:GettingStarted>`. Dans « Entry point », ajouter `- ``AuthState``` après `- ``MatrixSession```.
Ajouter, avant `### Storage`, la section :

```markdown
### Encryption

- ``EncryptionService``
- ``VerificationStatus``
- ``RecoveryState``
- ``BackupState``
- ``RecoveryProgress``
- ``RecoveryKey``
- ``SessionVerification``
- ``SessionVerificationState``
- ``VerificationRequest``
- ``SASData``
- ``SASEmoji``
```

Dans le paragraphe d'ouverture, remplacer « See <doc:GettingStarted> for a first end-to-end flow,
and <doc:TestingWithMocks> to test an application that depends on the package. » par :

```markdown
See <doc:GettingStarted> for a first end-to-end flow, <doc:VerificationAndRecovery> to handle
device trust, and <doc:TestingWithMocks> to test an application that depends on the package.
```

- [ ] **Step 3 : Mettre à jour `GettingStarted.md`**

Remplacer la section `## Open a session` (titre, bloc de code et paragraphe qui suit) par :

````markdown
## Open a session

At launch, restore the stored session from storage alone — its homeserver address is stored with
it — and sign in only when there is none:

```swift
let storage = MatrixStorage.appGroup("group.com.example.app")
let session: any MatrixSession

if let restored = try await Matrix.restoreSession(storage: storage) {
    session = restored
} else {
    let client = Matrix.client(homeserver: URL(string: "https://matrix.org")!, storage: storage)
    session = try await client.login(
        .password(username: "alice", password: "…", deviceName: "iPhone")
    )
}
```

``Matrix/restoreSession(storage:)`` returns `nil` when no session is stored — that is not an error.
Once signed in, see <doc:VerificationAndRecovery>: a new device should be verified before it can
read encrypted history.
````

- [ ] **Step 4 : Mettre à jour `TestingWithMocks.md`**

Remplacer la section `## The four doubles` (titre, tableau et paragraphe qui suit) par :

```markdown
## The doubles

| Double | Stands in for | Driven with |
| --- | --- | --- |
| `MockMatrixClient` | ``MatrixClient`` | `loginResult`, `restoreResult`, `loginAttempts` |
| `MockMatrixSession` | ``MatrixSession`` | `emitAuthState(_:)`, `logoutError`, `didLogout` |
| `MockRoomService` | ``RoomService`` | `emit(_:)`, `finish()` |
| `MockSyncController` | ``SyncController`` | `emit(_:)`, `finish()`, `startCallCount` |
| `MockTimeline` | ``Timeline`` | `emit(_:)`, `finish()`, `sentMessages`, `sendError`, `paginationError` |
| `MockEncryptionService` | ``EncryptionService`` | `emitVerificationStatus(_:)`, `emitRecoveryState(_:)`, `emitBackupState(_:)`, `finish()`, injected results and errors |
| `MockSessionVerification` | ``SessionVerification`` | `emit(_:)`, `finish()`, `setError(_:for:)`, `calls` |

The stream-bearing doubles expose the **same pair**: an `emit` method pushes a value, `finish()`
ends the stream.
```

Dans `## Simulating a failure`, remplacer la phrase « `MockTimeline.sendError` makes the next send
(and the next pagination) fail with the error of your choice. » par :

```markdown
`MockTimeline.sendError` makes sends fail, and `MockTimeline.paginationError` makes pagination fail,
independently — so "pagination fails while sending still works" is testable.
```

Ajouter, avant `## What the mocks do not replace` :

````markdown
## Driving a verification

`MockSessionVerification` runs no state machine: your test sets every state and checks the commands
your code called.

```swift
@Test func approvingSendsTheApproval() async throws {
    let verification = MockSessionVerification()
    let model = VerificationModel(verification: verification)   // your code

    verification.emit(.comparing(.emojis([SASEmoji(symbol: "🐶", description: "Dog", index: 0)])))
    try await model.userConfirmedEmojisMatch()

    #expect(verification.calls == [.approve])
}
```

## Restoring at launch

``Matrix/restoreSession(storage:)`` is a static function, so no mock can replace it. Inject it as a
closure instead:

```swift
struct LaunchModel {
    var restoreSession: () async throws -> (any MatrixSession)? = {
        try await Matrix.restoreSession(storage: .appGroup("group.com.example.app"))
    }
}

@Test func aStoredSessionSkipsSignIn() async throws {
    let model = LaunchModel(restoreSession: { MockMatrixSession() })
    // …
}
```
````

- [ ] **Step 5 : Mettre à jour le README** — `README.md`

Remplacer la section `## Scope` jusqu'au tableau de feuille de route inclus par :

```markdown
## Scope

v0.2 covers password authentication, persisted sessions, syncing, the room list, timelines, sending
text messages, device verification, recovery and key backup.

End-to-end encryption is **active** — the Rust SDK handles it, with no opt-in on your part. An
application can verify a new device by comparing emojis with another of the user's devices, set up
recovery, restore keys with the recovery key, and learn that the server ended the session. What
v0.2 does **not** expose:

- QR-code verification — the bundled Rust SDK does not expose it;
- verifying other users, and resetting a lost cryptographic identity;
- push notifications and the associated service extension.

`MatrixClient.loginDetails()` — which reports the login methods a homeserver accepts — is planned
but **not implemented** yet: an application that needs to query the homeserver before showing a
sign-in screen will have to wait. Its absence is a decision, not an oversight.

| Version | Contents |
| --- | --- |
| 0.1 | Foundation: auth, session, sync, rooms, timeline, sending text |
| 0.2 | Device verification (emoji), recovery and key backup, server sign-out, restore from storage |
| 0.3 | Push notifications and the service extension |
| 0.4 | Media, read receipts, typing, presence, account, OAuth, `loginDetails()` |
| Later | Verifying other users, identity reset, QR-code verification once the SDK exposes it |
| 1.0 | API freeze |
```

Dans le bloc de code d'introduction du README, remplacer tout ce qui précède
`await session.sync.start()` par :

```swift
let storage = MatrixStorage.appGroup("group.com.example.app")
let session: any MatrixSession

if let restored = try await Matrix.restoreSession(storage: storage) {
    session = restored
} else {
    let client = Matrix.client(homeserver: URL(string: "https://matrix.org")!, storage: storage)
    session = try await client.login(.password(username: "alice", password: "…", deviceName: "iPhone"))
}
```

(les lignes `await session.sync.start()` et `for await rooms …` qui suivent sont conservées). Ne pas
condenser avec `??` : son second opérande est une autoclosure synchrone, qui ne peut pas contenir
`try await`.

Dans la liste « What the package gives you », ajouter après la puce **Typed errors.** :

```markdown
- **Retry decisions made for you.** Rely on `MatrixError.isRetryable` rather than writing your own
  mapping: it is what keeps you from offering "try again" after a TLS failure or an exceeded quota.
```

Dans le tableau `## Compatibility`, ajouter la ligne `| 0.2.x | 26.09.07 | 18+ | 15+ | 6.2+ |` au-dessus
de la ligne 0.1.x. Dans `## Installation`, remplacer `from: "0.1.1"` par `from: "0.2.0"`.

- [ ] **Step 6 : Corriger la spec 0.1** — `docs/superpowers/specs/2026-09-13-matrixclientkit-design.md`

En §6.6, remplacer « vérification d'appareils (SAS emoji et QR) » par
« vérification d'appareils (SAS emoji ; QR non exposé par l'amont épinglé, voir la spec 0.2) ».
En §12, ligne v0.2, remplacer « vérification d'appareils (SAS, QR) » par
« vérification d'appareils (SAS — QR retiré, non exposé par l'amont) ».

- [ ] **Step 7 : Vérifier la génération DocC**

Reprendre la commande de l'étape DocC de `.github/workflows/ci.yml` (lire le bloc `run:` qui suit le
commentaire sur `swift-docc-plugin`) et l'exécuter localement.
Expected: aucune erreur, et aucun avertissement « doesn't exist » sur les symboles cités.

- [ ] **Step 8 : Commit**

```bash
git add Sources/MatrixClientKit/Documentation.docc README.md docs/superpowers/specs/2026-09-13-matrixclientkit-design.md
git commit -m "docs: vérification, récupération et restauration dans le README et la DocC

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 15 : Publication 0.2.0

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `Sources/MatrixClientKitCore/PackageInfo.swift`
- Modify: `Tests/MatrixClientKitCoreTests/PackageInfoTests.swift`

**Interfaces:**
- Consumes : tout le travail des Tasks 1–14.
- Produces : la version 0.2.0 prête à publier.

- [ ] **Step 1 : Monter la version, test d'abord**

Dans `Tests/MatrixClientKitCoreTests/PackageInfoTests.swift`, remplacer `"0.1.1"` par `"0.2.0"`.
Run: `swift test --filter PackageInfoTests` — Expected: FAIL.
Dans `Sources/MatrixClientKitCore/PackageInfo.swift`, remplacer `"0.1.1"` par `"0.2.0"`.
Run: `swift test --filter PackageInfoTests` — Expected: PASS.

- [ ] **Step 2 : Écrire le CHANGELOG** — insérer au-dessus de `## [0.1.1] - 2026-09-13` (date : jour de la publication)

```markdown
## [0.2.0] - YYYY-MM-DD

### Breaking

- `MatrixSession` requires two new members, `encryption` and `authState`. An application that
  implements the protocol itself — typically in a test double — must add them, or use
  `MockMatrixSession`.
- `MockTimeline.sendError` now makes only `send(_:)` fail. Pagination has its own
  `paginationError`: a test that relied on `sendError` to fail pagination must switch to it.
- `SampleData.roomSummary` gains a `membership:` parameter (defaulting to `.joined`), and its
  fixtures are named "Lounge" instead of "Salon". This change shipped on `main` after 0.1.1 under a
  commit wrongly labelled as documentation.

### Added

- `MatrixSession.encryption`, an `EncryptionService`: observable verification, recovery and backup
  states; `isLastDevice()`, `hasDevicesToVerifyAgainst()`, `backupExistsOnServer()`.
- Device verification by comparing emojis or numbers with another of the user's devices, published
  as a state machine: `SessionVerification`, `SessionVerificationState`.
- Recovery: `enableRecovery`, `recover(with:)`, `resetRecoveryKey()`, `disableRecovery()`, and
  `enableBackups()`. `RecoveryKey` redacts its description.
- `MatrixSession.authState`: learn that the homeserver ended the session while the application was
  running. On a revoked session, local data is erased before `.signedOut` is reported.
- `Matrix.restoreSession(storage:)`: restore a session without knowing the homeserver's address.
- `MockMatrixClient`, `MockEncryptionService`, `MockSessionVerification`, and
  `MockMatrixSession.logoutError`.

### Changed

- A cross-signing identity is created at sign-in for accounts that have none, so that the device
  can be verified.
- `SyncController.start()` documents that calling it while syncing is running has no effect.

### Fixed

- `MatrixClient.restoreSession()` used the client's homeserver address instead of the one stored
  with the session.
- Every string that reaches an application is in English — `MatrixError.errorDescription`, send
  failure reasons, unsupported timeline items — and an undecryptable message now says why it could
  not be decrypted.

### Not included

- QR-code verification: the bundled Matrix Rust SDK (26.09.07) does not expose it.
```

- [ ] **Step 3 : Vérification complète**

Run, dans l'ordre, et vérifier chaque sortie :
```bash
swift build --build-tests
swift test --skip MatrixClientKitIntegrationTests
swift format lint --recursive --strict Sources Tests
xcodebuild build -quiet -scheme MatrixClientKit -destination 'generic/platform=iOS Simulator'
```
Expected: tout vert, aucune sortie de lint.

Vérifier le CHANGELOG contre l'historique :
```bash
git log --oneline 0.1.1..HEAD
```
Chaque `feat!:` doit avoir sa ligne dans *Breaking*, chaque `feat:` dans *Added*, chaque `fix:` dans
*Fixed*.

- [ ] **Step 4 : Commit**

```bash
git add CHANGELOG.md Sources/MatrixClientKitCore/PackageInfo.swift Tests/MatrixClientKitCoreTests/PackageInfoTests.swift
git commit -m "chore: version 0.2.0

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

- [ ] **Step 5 : Suite d'intégration — STOP, identifiants de l'utilisateur requis**

Demander à l'utilisateur de lancer lui-même, ou de fournir pour cette session, les variables de
`Tests/MatrixClientKitIntegrationTests/README.md` (dont `MATRIX_TEST_RECOVERY_KEY`). Ne jamais les
écrire dans un fichier. Commande :

```bash
swift test --filter MatrixClientKitIntegrationTests
```

Expected: tous les cas exécutés passent. En cas d'échec de
`aWrongRecoveryKeyIsRejectedAndTheRightOneVerifiesTheDevice` sur la mauvaise clé, lire le message
amont réel et corriger `EncryptionMapper` (Task 5) et la spec §2.10 / §7.1 — ne pas assouplir le
test. En cas d'échec de `aFreshAccountGetsACrossSigningIdentityAtSignIn`, consigner la limite
(serveur exigeant l'UIAA) dans le README et la spec §11 avant de publier.

- [ ] **Step 6 : Publication — STOP, accord explicite de l'utilisateur requis**

Présenter à l'utilisateur : la liste des commits depuis `0.1.1`, le résultat de la suite
d'intégration, et le CHANGELOG. **N'exécuter la suite qu'après un « oui » explicite** : pousser,
taguer et publier sont visibles publiquement.

```bash
git push origin main
git tag -a 0.2.0 -m "MatrixClientKit 0.2.0"
git push origin 0.2.0
gh release create 0.2.0 --title "0.2.0" --notes-file <(awk '/^## \[0.2.0\]/{flag=1; next} /^## \[/{flag=0} flag' CHANGELOG.md)
```

Expected: CI verte sur `main` (vérifier avant de taguer), tag `0.2.0` présent sur `origin`, release
GitHub publiée avec les notes de la section 0.2.0.
