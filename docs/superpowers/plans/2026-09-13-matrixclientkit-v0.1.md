# MatrixClientKit v0.1 — Plan d'implémentation

> **Pour les agents :** SOUS-SKILL REQUIS — utiliser `superpowers:subagent-driven-development`
> (recommandé) ou `superpowers:executing-plans` pour exécuter ce plan tâche par tâche. Les étapes
> utilisent la syntaxe à cases à cocher (`- [ ]`) pour le suivi.

**Goal :** livrer le palier v0.1 de MatrixClientKit — un package Swift public, publiable et
utilisable, couvrant authentification par mot de passe, session persistée, sync, liste de rooms,
timeline et envoi de messages texte, au-dessus du SDK Rust Matrix.

**Architecture :** quatre cibles SPM. `MatrixClientKitCore` contient les protocoles publics, les
modèles et toute la logique pure ; il n'importe pas `MatrixRustSDK`, ce qui garantit par
compilation qu'aucun type amont ne fuite dans l'API publique. `MatrixClientKitRust` implémente ces
protocoles en traduisant depuis le FFI. `MatrixClientKitMocks` fournit des doubles sans binaire.
`MatrixClientKit` est l'umbrella qui réexporte Core et expose les fabriques.

**Tech Stack :** Swift 6.2+ (mode langage 6, strict concurrency), Swift Testing, SPM,
`matrix-org/matrix-rust-components-swift` épinglé en `26.09.07`, GitHub Actions (runners standard).

**Spec :** `docs/superpowers/specs/2026-09-13-matrixclientkit-design.md`

## Global Constraints

Ces contraintes s'appliquent à **toutes** les tâches ; elles ne sont pas répétées ensuite.

- `// swift-tools-version: 6.2` dans le manifeste.
- Plateformes : `.iOS(.v18)`, `.macOS(.v15)`.
- Toutes les cibles en `swiftLanguageMode(.v6)`, strict concurrency complet.
- Dépendance amont épinglée **exactement** : `.package(url: "https://github.com/matrix-org/matrix-rust-components-swift", exact: "26.09.07")`.
- `MatrixClientKitCore` **ne doit jamais** contenir `import MatrixRustSDK`. Toute tâche qui en a
  besoin travaille dans `MatrixClientKitRust`.
- Aucun type amont (`Client`, `Room`, `Timeline`, `ClientError`, `TimelineDiff`, …) ne doit
  apparaître dans une signature `public` de `MatrixClientKit` ou `MatrixClientKitCore`.
- Aucun `@MainActor` dans `Core` ni dans `Rust`.
- Tous les types publics sont `Sendable`.
- Framework de test : Swift Testing (`import Testing`), jamais XCTest.
- Licence Apache-2.0 ; en-tête de licence non requis dans chaque fichier.
- CI : runners GitHub **standard** exclusivement, jamais de larger runner.
- Politique de tampon : flux de diffs en `.unbounded`, flux d'instantanés en `.bufferingNewest(1)`.

---

## Structure des fichiers

```
Package.swift
Sources/
  MatrixClientKitCore/
    PackageInfo.swift                     // versions du package et de l'amont
    Diffing/CollectionDiff.swift          // enum générique à 11 cas
    Diffing/CollectionDiffApplier.swift   // application pure des diffs
    Identifiers/UserID.swift
    Identifiers/RoomID.swift
    Identifiers/EventID.swift
    Identifiers/DeviceID.swift
    Errors/MatrixError.swift              // + sous-enums + isRetryable
    Models/RoomSummary.swift
    Models/TimelineItem.swift
    Models/MessageContent.swift
    Models/SyncState.swift
    Models/MatrixSessionData.swift        // données de session sérialisables
    Storage/SecureStore.swift             // protocole + InMemorySecureStore
    Storage/MatrixStorage.swift           // configuration de stockage
    Services/MatrixClient.swift           // protocole client non authentifié
    Services/MatrixSession.swift          // protocole session authentifiée
    Services/RoomService.swift
    Services/SyncController.swift
    Services/Timeline.swift
  MatrixClientKitRust/
    Bridge/FFIStream.swift                // pont listeners -> AsyncStream
    Bridge/ErrorMapper.swift              // ErrorKind -> MatrixError
    Bridge/DiffTranslation.swift          // TimelineDiff / RoomListEntriesUpdate -> CollectionDiff
    Bridge/ModelMapping.swift             // RoomInfo, EventTimelineItem -> modèles Core
    Storage/KeychainSecureStore.swift
    Storage/SessionDelegate.swift         // ClientSessionDelegate amont
    Storage/StoragePaths.swift
    RustMatrixClient.swift
    RustMatrixSession.swift
    RustRoomService.swift
    RustSyncController.swift
    RustTimeline.swift
  MatrixClientKitMocks/
    MockMatrixSession.swift
    MockRoomService.swift
    MockTimeline.swift
    SampleData.swift
  MatrixClientKit/
    MatrixClientKit.swift                 // @_exported import Core + fabriques
    Documentation.docc/
Tests/
  MatrixClientKitCoreTests/
  MatrixClientKitRustTests/
  MatrixClientKitIntegrationTests/        // désactivés par défaut
.github/workflows/ci.yml
```

---

### Task 1 : Squelette du package, dépendance amont et CI

**Files:**
- Create: `Package.swift`
- Create: `Sources/MatrixClientKitCore/PackageInfo.swift`
- Create: `Sources/MatrixClientKitRust/Bridge/Placeholder.swift`
- Create: `Sources/MatrixClientKitMocks/SampleData.swift`
- Create: `Sources/MatrixClientKit/MatrixClientKit.swift`
- Create: `.github/workflows/ci.yml`, `.gitignore`, `LICENSE`, `NOTICE`
- Test: `Tests/MatrixClientKitCoreTests/PackageInfoTests.swift`

**Interfaces:**
- Consumes: rien.
- Produces: `PackageInfo.version: String`, `PackageInfo.upstreamVersion: String` ; les quatre
  cibles et les trois produits utilisés par toutes les tâches suivantes.

- [ ] **Step 1 : Écrire le test qui échoue**

`Tests/MatrixClientKitCoreTests/PackageInfoTests.swift` :

```swift
import Testing
@testable import MatrixClientKitCore

@Test func packageInfoDeclaresPinnedUpstreamVersion() {
    #expect(PackageInfo.upstreamVersion == "26.09.07")
    #expect(PackageInfo.version == "0.1.0")
}
```

- [ ] **Step 2 : Créer le manifeste**

`Package.swift` :

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MatrixClientKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "MatrixClientKit", targets: ["MatrixClientKit"]),
        .library(name: "MatrixClientKitCore", targets: ["MatrixClientKitCore"]),
        .library(name: "MatrixClientKitMocks", targets: ["MatrixClientKitMocks"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/matrix-org/matrix-rust-components-swift",
            exact: "26.09.07"
        )
    ],
    targets: [
        .target(name: "MatrixClientKitCore"),
        .target(
            name: "MatrixClientKitRust",
            dependencies: [
                "MatrixClientKitCore",
                .product(name: "MatrixRustSDK", package: "matrix-rust-components-swift"),
            ]
        ),
        .target(name: "MatrixClientKitMocks", dependencies: ["MatrixClientKitCore"]),
        .target(name: "MatrixClientKit", dependencies: ["MatrixClientKitCore", "MatrixClientKitRust"]),
        .testTarget(name: "MatrixClientKitCoreTests", dependencies: ["MatrixClientKitCore"]),
        .testTarget(name: "MatrixClientKitRustTests", dependencies: ["MatrixClientKitRust"]),
    ],
    swiftLanguageModes: [.v6]
)
```

- [ ] **Step 3 : Créer les fichiers sources minimaux**

`Sources/MatrixClientKitCore/PackageInfo.swift` :

```swift
/// Métadonnées de version du package.
public enum PackageInfo: Sendable {
    /// Version de MatrixClientKit.
    public static let version = "0.1.0"
    /// Version de `matrix-rust-components-swift` embarquée, épinglée dans le manifeste.
    public static let upstreamVersion = "26.09.07"
}
```

`Sources/MatrixClientKitRust/Bridge/Placeholder.swift` :

```swift
import MatrixRustSDK

/// Vérifie à la compilation que la dépendance amont est correctement résolue et liée.
/// Supprimé en Task 6, quand le pont réel occupe ce fichier.
enum UpstreamLinkCheck {
    static func canReferenceUpstreamTypes() -> Bool {
        String(describing: ClientBuilder.self).isEmpty == false
    }
}
```

`Sources/MatrixClientKitMocks/SampleData.swift` :

```swift
import MatrixClientKitCore

/// Données d'exemple utilisées par les mocks. Enrichi en Task 14.
public enum SampleData: Sendable {}
```

`Sources/MatrixClientKit/MatrixClientKit.swift` :

```swift
@_exported import MatrixClientKitCore
```

- [ ] **Step 4 : Lancer les tests**

Run : `swift test`
Attendu : la dépendance amont se résout (téléchargement du XCFramework, plusieurs minutes la
première fois), la compilation passe, `packageInfoDeclaresPinnedUpstreamVersion` est vert.

Si la résolution échoue avec une erreur de plateforme, vérifier que le manifeste déclare bien
iOS 18 / macOS 15 : l'amont déclare iOS 16 / macOS 12, un plancher *supérieur* est valide.

- [ ] **Step 5 : Ajouter la CI et les fichiers de dépôt**

`.github/workflows/ci.yml` :

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    name: Build & Test (macOS)
    runs-on: macos-15   # runner standard : gratuit et non plafonné sur dépôt public
    steps:
      - uses: actions/checkout@v4
      - name: Cache SPM
        uses: actions/cache@v4
        with:
          path: .build
          key: spm-${{ runner.os }}-${{ hashFiles('Package.resolved') }}
          restore-keys: spm-${{ runner.os }}-
      - name: Build
        run: swift build --build-tests
      - name: Test
        run: swift test --skip MatrixClientKitIntegrationTests
```

`.gitignore` :

```
.build/
.swiftpm/
*.xcodeproj
*.xcworkspace
.DS_Store
```

Créer `LICENSE` avec le texte intégral Apache-2.0, et `NOTICE` :

```
MatrixClientKit
Copyright 2026 Kevin Esprit

Ce produit embarque le Matrix Rust SDK (https://github.com/matrix-org/matrix-rust-sdk),
Copyright The Matrix.org Foundation C.I.C., distribué sous licence Apache-2.0.
```

- [ ] **Step 6 : Commit**

```bash
git add Package.swift Sources Tests .github .gitignore LICENSE NOTICE
git commit -m "feat: squelette du package, dépendance amont épinglée et CI"
```

---

### Task 2 : Diffs de collection et applicateur

C'est la logique la plus risquée du package. `TimelineDiff` et `RoomListEntriesUpdate` amont ont
exactement la même forme — 11 cas identiques — donc un seul type générique et un seul applicateur
les couvrent tous les deux. Entièrement pur, aucun FFI, testable exhaustivement.

**Files:**
- Create: `Sources/MatrixClientKitCore/Diffing/CollectionDiff.swift`
- Create: `Sources/MatrixClientKitCore/Diffing/CollectionDiffApplier.swift`
- Test: `Tests/MatrixClientKitCoreTests/CollectionDiffApplierTests.swift`

**Interfaces:**
- Consumes: rien.
- Produces: `CollectionDiff<Element>` (11 cas), et
  `CollectionDiffApplier.apply(_ diffs: [CollectionDiff<E>], to items: [E]) -> [E]`,
  utilisés par les Tasks 12 et 13.

**Sémantique des index invalides — décision à respecter :** un diff dont l'index sort des bornes
est **ignoré**, les diffs suivants sont appliqués normalement, et l'application ne plante jamais.
Un crash dans un callback venant de Rust est impossible à diagnostiquer côté application.

- [ ] **Step 1 : Écrire les tests qui échouent**

`Tests/MatrixClientKitCoreTests/CollectionDiffApplierTests.swift` :

```swift
import Testing
@testable import MatrixClientKitCore

private func apply(_ diffs: [CollectionDiff<String>], to items: [String]) -> [String] {
    CollectionDiffApplier.apply(diffs, to: items)
}

@Test func appendAddsAtTheEnd() {
    #expect(apply([.append(["c", "d"])], to: ["a", "b"]) == ["a", "b", "c", "d"])
}

@Test func clearEmptiesTheCollection() {
    #expect(apply([.clear], to: ["a", "b"]) == [])
}

@Test func pushFrontAndPushBack() {
    #expect(apply([.pushFront("x")], to: ["a"]) == ["x", "a"])
    #expect(apply([.pushBack("z")], to: ["a"]) == ["a", "z"])
}

@Test func popFrontAndPopBack() {
    #expect(apply([.popFront], to: ["a", "b"]) == ["b"])
    #expect(apply([.popBack], to: ["a", "b"]) == ["a"])
}

@Test func popOnEmptyCollectionIsIgnored() {
    #expect(apply([.popFront], to: []) == [])
    #expect(apply([.popBack], to: []) == [])
}

@Test func insertAtIndex() {
    #expect(apply([.insert(index: 1, "x")], to: ["a", "b"]) == ["a", "x", "b"])
}

@Test func insertAtEndIsValid() {
    #expect(apply([.insert(index: 2, "x")], to: ["a", "b"]) == ["a", "b", "x"])
}

@Test func setReplacesAtIndex() {
    #expect(apply([.set(index: 0, "x")], to: ["a", "b"]) == ["x", "b"])
}

@Test func removeAtIndex() {
    #expect(apply([.remove(index: 0)], to: ["a", "b"]) == ["b"])
}

@Test func truncateKeepsPrefix() {
    #expect(apply([.truncate(length: 1)], to: ["a", "b", "c"]) == ["a"])
}

@Test func truncateLongerThanCollectionIsNoop() {
    #expect(apply([.truncate(length: 9)], to: ["a"]) == ["a"])
}

@Test func resetReplacesEverything() {
    #expect(apply([.reset(["x", "y"])], to: ["a"]) == ["x", "y"])
}

@Test func outOfBoundsDiffIsIgnoredAndFollowingDiffsStillApply() {
    let result = apply([.set(index: 7, "boom"), .pushBack("ok")], to: ["a"])
    #expect(result == ["a", "ok"])
}

@Test func diffsAreAppliedInOrder() {
    let result = apply([.pushBack("b"), .pushFront("z"), .remove(index: 1)], to: ["a"])
    #expect(result == ["z", "b"])
}
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run : `swift test --filter CollectionDiffApplierTests`
Attendu : ÉCHEC de compilation, `cannot find 'CollectionDiff' in scope`.

- [ ] **Step 3 : Implémenter**

`Sources/MatrixClientKitCore/Diffing/CollectionDiff.swift` :

```swift
/// Une modification atomique appliquée à une collection observée.
///
/// Ce type reprend la forme des flux de diffs du SDK Rust (timelines et listes de rooms
/// partagent exactement la même structure), mais reste indépendant de celui-ci : la logique
/// d'application est ainsi pure et testable sans binaire.
public enum CollectionDiff<Element: Sendable>: Sendable {
    case append([Element])
    case clear
    case pushFront(Element)
    case pushBack(Element)
    case popFront
    case popBack
    case insert(index: Int, Element)
    case set(index: Int, Element)
    case remove(index: Int)
    case truncate(length: Int)
    case reset([Element])
}

extension CollectionDiff: Equatable where Element: Equatable {}
```

`Sources/MatrixClientKitCore/Diffing/CollectionDiffApplier.swift` :

```swift
/// Applique des diffs à une collection pour produire son état courant.
///
/// Un diff dont l'index est hors bornes est ignoré ; les diffs suivants sont appliqués
/// normalement. L'application ne provoque jamais d'erreur fatale.
public enum CollectionDiffApplier: Sendable {

    public static func apply<Element: Sendable>(
        _ diffs: [CollectionDiff<Element>],
        to items: [Element]
    ) -> [Element] {
        var result = items
        for diff in diffs {
            apply(diff, to: &result)
        }
        return result
    }

    private static func apply<Element: Sendable>(_ diff: CollectionDiff<Element>, to items: inout [Element]) {
        switch diff {
        case let .append(values):
            items.append(contentsOf: values)
        case .clear:
            items.removeAll()
        case let .pushFront(value):
            items.insert(value, at: 0)
        case let .pushBack(value):
            items.append(value)
        case .popFront:
            guard !items.isEmpty else { return }
            items.removeFirst()
        case .popBack:
            guard !items.isEmpty else { return }
            items.removeLast()
        case let .insert(index, value):
            guard index >= 0, index <= items.count else { return }
            items.insert(value, at: index)
        case let .set(index, value):
            guard items.indices.contains(index) else { return }
            items[index] = value
        case let .remove(index):
            guard items.indices.contains(index) else { return }
            items.remove(at: index)
        case let .truncate(length):
            guard length >= 0, length < items.count else { return }
            items.removeLast(items.count - length)
        case let .reset(values):
            items = values
        }
    }
}
```

- [ ] **Step 4 : Lancer les tests pour vérifier qu'ils passent**

Run : `swift test --filter CollectionDiffApplierTests`
Attendu : 14 tests verts.

- [ ] **Step 5 : Commit**

```bash
git add Sources/MatrixClientKitCore/Diffing Tests/MatrixClientKitCoreTests/CollectionDiffApplierTests.swift
git commit -m "feat: diffs de collection génériques et applicateur pur"
```

---

### Task 3 : Identifiants typés

**Files:**
- Create: `Sources/MatrixClientKitCore/Identifiers/UserID.swift`
- Create: `Sources/MatrixClientKitCore/Identifiers/RoomID.swift`
- Create: `Sources/MatrixClientKitCore/Identifiers/EventID.swift`
- Create: `Sources/MatrixClientKitCore/Identifiers/DeviceID.swift`
- Test: `Tests/MatrixClientKitCoreTests/IdentifierTests.swift`

**Interfaces:**
- Consumes: rien.
- Produces: `UserID`, `RoomID`, `EventID`, `DeviceID`. Chacun expose
  `init?(rawValue: String)`, `rawValue: String`, et est `Sendable`, `Hashable`,
  `CustomStringConvertible`. `UserID` expose en plus `localpart: String` et `serverName: String`.

**Note sur les identifiants de room :** depuis la version de room 12, un `RoomID` peut ne plus
comporter de partie serveur. La validation exige donc `!` suivi d'au moins un caractère, et rend
la partie serveur optionnelle.

- [ ] **Step 1 : Écrire les tests qui échouent**

`Tests/MatrixClientKitCoreTests/IdentifierTests.swift` :

```swift
import Testing
@testable import MatrixClientKitCore

@Test func userIDAcceptsWellFormedValue() throws {
    let id = try #require(UserID(rawValue: "@alice:matrix.org"))
    #expect(id.localpart == "alice")
    #expect(id.serverName == "matrix.org")
    #expect(id.description == "@alice:matrix.org")
}

@Test(arguments: ["alice:matrix.org", "@alice", "@:matrix.org", "@alice:", ""])
func userIDRejectsMalformedValues(raw: String) {
    #expect(UserID(rawValue: raw) == nil)
}

@Test func userIDKeepsPortInServerName() throws {
    let id = try #require(UserID(rawValue: "@bob:example.com:8448"))
    #expect(id.serverName == "example.com:8448")
}

@Test func roomIDAcceptsLegacyAndModernForms() {
    #expect(RoomID(rawValue: "!abc:matrix.org") != nil)
    #expect(RoomID(rawValue: "!opaqueIdentifier") != nil)
}

@Test(arguments: ["abc:matrix.org", "!", ""])
func roomIDRejectsMalformedValues(raw: String) {
    #expect(RoomID(rawValue: raw) == nil)
}

@Test func eventIDRequiresDollarPrefix() {
    #expect(EventID(rawValue: "$abcdef") != nil)
    #expect(EventID(rawValue: "abcdef") == nil)
    #expect(EventID(rawValue: "$") == nil)
}

@Test func deviceIDRejectsEmptyValue() {
    #expect(DeviceID(rawValue: "ABCDEF") != nil)
    #expect(DeviceID(rawValue: "") == nil)
}

@Test func identifiersAreHashableByRawValue() throws {
    let a = try #require(UserID(rawValue: "@alice:matrix.org"))
    let b = try #require(UserID(rawValue: "@alice:matrix.org"))
    #expect(a == b)
    #expect(Set([a, b]).count == 1)
}
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run : `swift test --filter IdentifierTests`
Attendu : ÉCHEC, `cannot find 'UserID' in scope`.

- [ ] **Step 3 : Implémenter**

`Sources/MatrixClientKitCore/Identifiers/UserID.swift` :

```swift
/// Identifiant d'utilisateur Matrix, de la forme `@localpart:serveur`.
public struct UserID: Sendable, Hashable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.hasPrefix("@") else { return nil }
        let body = rawValue.dropFirst()
        guard let separator = body.firstIndex(of: ":") else { return nil }
        guard separator != body.startIndex else { return nil }
        guard body.index(after: separator) != body.endIndex else { return nil }
        self.rawValue = rawValue
    }

    /// Partie locale de l'identifiant, sans le `@` ni le nom de serveur.
    public var localpart: String {
        let body = rawValue.dropFirst()
        guard let separator = body.firstIndex(of: ":") else { return String(body) }
        return String(body[body.startIndex..<separator])
    }

    /// Nom du serveur, port inclus s'il est présent.
    public var serverName: String {
        let body = rawValue.dropFirst()
        guard let separator = body.firstIndex(of: ":") else { return "" }
        return String(body[body.index(after: separator)...])
    }

    public var description: String { rawValue }
}
```

`Sources/MatrixClientKitCore/Identifiers/RoomID.swift` :

```swift
/// Identifiant de room Matrix. La partie serveur est optionnelle : les rooms en version 12
/// et ultérieures peuvent en être dépourvues.
public struct RoomID: Sendable, Hashable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.hasPrefix("!"), rawValue.count > 1 else { return nil }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}
```

`Sources/MatrixClientKitCore/Identifiers/EventID.swift` :

```swift
/// Identifiant d'événement Matrix, préfixé par `$`.
public struct EventID: Sendable, Hashable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.hasPrefix("$"), rawValue.count > 1 else { return nil }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}
```

`Sources/MatrixClientKitCore/Identifiers/DeviceID.swift` :

```swift
/// Identifiant d'appareil, opaque et propre au homeserver.
public struct DeviceID: Sendable, Hashable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}
```

- [ ] **Step 4 : Lancer les tests pour vérifier qu'ils passent**

Run : `swift test --filter IdentifierTests`
Attendu : tous verts, y compris les cas paramétrés.

- [ ] **Step 5 : Commit**

```bash
git add Sources/MatrixClientKitCore/Identifiers Tests/MatrixClientKitCoreTests/IdentifierTests.swift
git commit -m "feat: identifiants Matrix typés et validés"
```

---

### Task 4 : Type d'erreur public

**Files:**
- Create: `Sources/MatrixClientKitCore/Errors/MatrixError.swift`
- Test: `Tests/MatrixClientKitCoreTests/MatrixErrorTests.swift`

**Interfaces:**
- Consumes: rien.
- Produces: `MatrixError` et ses sous-enums `MatrixError.Authentication`, `.Network`,
  `.Permission`, `.Resource`, `.Encryption`, `.Server`, `.Storage` ; propriétés
  `isRetryable: Bool` et `retryAfter: Duration?`. Utilisé par toutes les tâches suivantes.

**Règle d'évolution à inscrire en documentation du type :** les cas de premier niveau sont figés ;
toute erreur nouvellement distinguable atterrit dans `.unexpected` jusqu'à la prochaine version
majeure.

- [ ] **Step 1 : Écrire les tests qui échouent**

`Tests/MatrixClientKitCoreTests/MatrixErrorTests.swift` :

```swift
import Testing
@testable import MatrixClientKitCore

@Test func rateLimitedExposesRetryDelay() {
    let error = MatrixError.rateLimited(retryAfter: .milliseconds(1500))
    #expect(error.isRetryable)
    #expect(error.retryAfter == .milliseconds(1500))
}

@Test func networkErrorsAreRetryable() {
    #expect(MatrixError.network(.offline).isRetryable)
    #expect(MatrixError.network(.timeout).isRetryable)
    #expect(MatrixError.network(.tlsFailure).isRetryable == false)
}

@Test func authenticationErrorsAreNotRetryable() {
    #expect(MatrixError.authentication(.invalidCredentials).isRetryable == false)
    #expect(MatrixError.authentication(.unknownToken(soft: true)).isRetryable == false)
}

@Test func softLogoutIsDistinguishableFromHardLogout() {
    #expect(MatrixError.authentication(.unknownToken(soft: true))
            != MatrixError.authentication(.unknownToken(soft: false)))
}

@Test func retryAfterIsNilForNonRateLimitedErrors() {
    #expect(MatrixError.permission(.forbidden).retryAfter == nil)
}

@Test func errorDescriptionIsNeverEmpty() {
    let errors: [MatrixError] = [
        .authentication(.invalidCredentials),
        .network(.offline),
        .rateLimited(retryAfter: nil),
        .permission(.forbidden),
        .notFound(.room),
        .encryption(.verificationRequired),
        .server(.maintenance),
        .storage(.unavailable),
        .unexpected(message: "boom", details: nil),
    ]
    for error in errors {
        #expect(error.errorDescription?.isEmpty == false)
    }
}
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run : `swift test --filter MatrixErrorTests`
Attendu : ÉCHEC, `cannot find 'MatrixError' in scope`.

- [ ] **Step 3 : Implémenter**

`Sources/MatrixClientKitCore/Errors/MatrixError.swift` :

```swift
import Foundation

/// Toutes les erreurs émises par MatrixClientKit.
///
/// - Important: les cas de premier niveau sont figés pour la durée d'une version majeure.
///   Une erreur nouvellement distinguable par le SDK sous-jacent est rapportée dans
///   ``MatrixError/unexpected(message:details:)`` jusqu'à la majeure suivante, afin qu'ajouter
///   de la précision ne casse jamais la compilation des applications.
public enum MatrixError: Error, Sendable, Hashable, LocalizedError {

    public enum Authentication: Sendable, Hashable {
        case invalidCredentials
        case unknownToken(soft: Bool)
        case userDeactivated
        case missingToken
        case captchaRequired
        case unsupportedLoginType
    }

    public enum Network: Sendable, Hashable {
        case offline
        case timeout
        case tlsFailure
    }

    public enum Permission: Sendable, Hashable {
        case forbidden
        case insufficientPowerLevel(required: Int, current: Int)
        case guestAccessForbidden
    }

    public enum Resource: Sendable, Hashable {
        case room
        case event
        case user
        case media
    }

    public enum Encryption: Sendable, Hashable {
        case unableToDecrypt(reason: String)
        case verificationRequired
        case invalidRecoveryKey
    }

    public enum Server: Sendable, Hashable {
        case resourceLimitExceeded(adminContact: String)
        case unsupportedRoomVersion
        case maintenance
        case invalidResponse
    }

    public enum Storage: Sendable, Hashable {
        case unavailable
        case corrupted
        case keychainFailure(status: Int32)
    }

    case authentication(Authentication)
    case network(Network)
    case rateLimited(retryAfter: Duration?)
    case permission(Permission)
    case notFound(Resource)
    case encryption(Encryption)
    case server(Server)
    case storage(Storage)
    case unexpected(message: String, details: String?)

    /// Indique si réessayer la même opération a une chance d'aboutir sans action de l'utilisateur.
    public var isRetryable: Bool {
        switch self {
        case .rateLimited:
            return true
        case let .network(network):
            switch network {
            case .offline, .timeout: return true
            case .tlsFailure: return false
            }
        case let .server(server):
            switch server {
            case .maintenance, .invalidResponse: return true
            case .resourceLimitExceeded, .unsupportedRoomVersion: return false
            }
        case .authentication, .permission, .notFound, .encryption, .storage, .unexpected:
            return false
        }
    }

    /// Délai indiqué par le serveur avant un nouvel essai, le cas échéant.
    public var retryAfter: Duration? {
        guard case let .rateLimited(delay) = self else { return nil }
        return delay
    }

    public var errorDescription: String? {
        switch self {
        case let .authentication(value): return "Erreur d'authentification : \(value)"
        case let .network(value): return "Erreur réseau : \(value)"
        case let .rateLimited(delay):
            guard let delay else { return "Trop de requêtes. Réessayez plus tard." }
            return "Trop de requêtes. Réessayez dans \(delay)."
        case let .permission(value): return "Permission refusée : \(value)"
        case let .notFound(resource): return "Ressource introuvable : \(resource)"
        case let .encryption(value): return "Erreur de chiffrement : \(value)"
        case let .server(value): return "Erreur du serveur : \(value)"
        case let .storage(value): return "Erreur de stockage : \(value)"
        case let .unexpected(message, details):
            guard let details else { return message }
            return "\(message) (\(details))"
        }
    }
}
```

- [ ] **Step 4 : Lancer les tests pour vérifier qu'ils passent**

Run : `swift test --filter MatrixErrorTests`
Attendu : 6 tests verts.

- [ ] **Step 5 : Commit**

```bash
git add Sources/MatrixClientKitCore/Errors Tests/MatrixClientKitCoreTests/MatrixErrorTests.swift
git commit -m "feat: type d'erreur public typé et documenté"
```

---

### Task 5 : Mappage des erreurs amont

**Files:**
- Create: `Sources/MatrixClientKitRust/Bridge/ErrorMapper.swift`
- Test: `Tests/MatrixClientKitRustTests/ErrorMapperTests.swift`

**Interfaces:**
- Consumes: `MatrixError` (Task 4).
- Produces: `ErrorMapper.map(_ error: any Error) -> MatrixError`, utilisé par toutes les
  implémentations des Tasks 10 à 13.

Rappel des formes amont exactes : `ClientError` a trois cas — `.Generic(msg:details:)`,
`.MatrixApi(kind:code:msg:details:)`, `.ContentScanner(reason:info:)`. `ErrorKind` compte une
quarantaine de cas, dont `limitExceeded(retryAfterMs: UInt64?)`,
`unknownToken(softLogout: Bool)` et `resourceLimitExceeded(adminContact: String)`.

- [ ] **Step 1 : Écrire les tests qui échouent**

`Tests/MatrixClientKitRustTests/ErrorMapperTests.swift` :

```swift
import Testing
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private func mapApi(_ kind: ErrorKind, code: String = "M_UNKNOWN") -> MatrixError {
    ErrorMapper.map(ClientError.MatrixApi(kind: kind, code: code, msg: "message", details: nil))
}

@Test func forbiddenBecomesPermissionError() {
    #expect(mapApi(.forbidden) == .permission(.forbidden))
}

@Test func limitExceededCarriesRetryDelay() {
    #expect(mapApi(.limitExceeded(retryAfterMs: 2000)) == .rateLimited(retryAfter: .milliseconds(2000)))
    #expect(mapApi(.limitExceeded(retryAfterMs: nil)) == .rateLimited(retryAfter: nil))
}

@Test func unknownTokenPreservesSoftLogoutFlag() {
    #expect(mapApi(.unknownToken(softLogout: true)) == .authentication(.unknownToken(soft: true)))
    #expect(mapApi(.unknownToken(softLogout: false)) == .authentication(.unknownToken(soft: false)))
}

@Test func resourceLimitExceededCarriesAdminContact() {
    #expect(mapApi(.resourceLimitExceeded(adminContact: "mailto:admin@example.com"))
            == .server(.resourceLimitExceeded(adminContact: "mailto:admin@example.com")))
}

@Test func unauthorizedBecomesInvalidCredentials() {
    #expect(mapApi(.unauthorized) == .authentication(.invalidCredentials))
}

@Test func deactivatedUserIsDetectedFromErrorCode() {
    #expect(mapApi(.unknown, code: "M_USER_DEACTIVATED") == .authentication(.userDeactivated))
}

@Test func notFoundBecomesResourceNotFound() {
    #expect(mapApi(.notFound) == .notFound(.event))
}

@Test func connectionFailuresBecomeNetworkErrors() {
    #expect(mapApi(.connectionFailed) == .network(.offline))
    #expect(mapApi(.connectionTimeout) == .network(.timeout))
}

@Test func unsupportedRoomVersionBecomesServerError() {
    #expect(mapApi(.unsupportedRoomVersion) == .server(.unsupportedRoomVersion))
}

@Test func unmappedKindFallsBackToUnexpected() {
    let error = mapApi(.badAlias, code: "M_BAD_ALIAS")
    guard case let .unexpected(message, details) = error else {
        Issue.record("attendu .unexpected, obtenu \(error)")
        return
    }
    #expect(message == "message")
    #expect(details?.contains("M_BAD_ALIAS") == true)
}

@Test func genericErrorBecomesUnexpected() {
    let error = ErrorMapper.map(ClientError.Generic(msg: "boom", details: "trace"))
    #expect(error == .unexpected(message: "boom", details: "trace"))
}

@Test func nonClientErrorBecomesUnexpected() {
    struct Custom: Error {}
    guard case .unexpected = ErrorMapper.map(Custom()) else {
        Issue.record("attendu .unexpected")
        return
    }
}
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run : `swift test --filter ErrorMapperTests`
Attendu : ÉCHEC, `cannot find 'ErrorMapper' in scope`.

- [ ] **Step 3 : Implémenter**

`Sources/MatrixClientKitRust/Bridge/ErrorMapper.swift` :

```swift
import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Traduit les erreurs du SDK Rust vers ``MatrixError``.
enum ErrorMapper {

    static func map(_ error: any Error) -> MatrixError {
        switch error {
        case let error as ClientError:
            return map(error)
        case let error as MatrixError:
            return error
        default:
            return .unexpected(message: String(describing: error), details: nil)
        }
    }

    static func map(_ error: ClientError) -> MatrixError {
        switch error {
        case let .Generic(msg, details):
            return .unexpected(message: msg, details: details)
        case let .MatrixApi(kind, code, msg, details):
            return map(kind: kind, code: code, message: msg, details: details)
        case let .ContentScanner(reason, info):
            return .unexpected(message: "Content scanner: \(reason)", details: info)
        }
    }

    static func map(
        kind: ErrorKind,
        code: String,
        message: String,
        details: String?
    ) -> MatrixError {
        // Certaines conditions ne sont distinguables que par le code d'erreur Matrix.
        if code == "M_USER_DEACTIVATED" {
            return .authentication(.userDeactivated)
        }

        switch kind {
        case .forbidden:
            return .permission(.forbidden)
        case .guestAccessForbidden:
            return .permission(.guestAccessForbidden)
        case let .limitExceeded(retryAfterMs):
            return .rateLimited(retryAfter: retryAfterMs.map { .milliseconds(Int64($0)) })
        case let .unknownToken(softLogout):
            return .authentication(.unknownToken(soft: softLogout))
        case .missingToken:
            return .authentication(.missingToken)
        case .unauthorized:
            return .authentication(.invalidCredentials)
        case .captchaNeeded, .captchaInvalid:
            return .authentication(.captchaRequired)
        case .notFound:
            return .notFound(.event)
        case .connectionFailed:
            return .network(.offline)
        case .connectionTimeout:
            return .network(.timeout)
        case .serverNotTrusted:
            return .network(.tlsFailure)
        case let .resourceLimitExceeded(adminContact):
            return .server(.resourceLimitExceeded(adminContact: adminContact))
        case .unsupportedRoomVersion, .incompatibleRoomVersion:
            return .server(.unsupportedRoomVersion)
        case .notJson, .badJson:
            return .server(.invalidResponse)
        default:
            return .unexpected(message: message, details: detailsIncludingCode(code, details))
        }
    }

    private static func detailsIncludingCode(_ code: String, _ details: String?) -> String {
        guard let details, !details.isEmpty else { return code }
        return "\(code): \(details)"
    }
}
```

- [ ] **Step 4 : Lancer les tests pour vérifier qu'ils passent**

Run : `swift test --filter ErrorMapperTests`
Attendu : 12 tests verts.

Si la compilation signale que `.incompatibleRoomVersion` ou un autre cas porte une valeur
associée dans cette version amont, adapter le motif (`case .incompatibleRoomVersion(_)`) sans
changer le résultat attendu.

- [ ] **Step 5 : Commit**

```bash
git add Sources/MatrixClientKitRust/Bridge/ErrorMapper.swift Tests/MatrixClientKitRustTests/ErrorMapperTests.swift
git commit -m "feat: mappage des erreurs du SDK Rust vers MatrixError"
```

---

### Task 6 : Pont listeners vers AsyncStream

Le cœur technique du package. Les protocoles de listener générés par UniFFI sont `Sendable` et
`TaskHandle` conforme à `TaskHandleProtocol`, ce qui rend le pont testable avec un faux handle,
sans exécuter une seule ligne de Rust.

**Files:**
- Create: `Sources/MatrixClientKitRust/Bridge/FFIStream.swift`
- Delete: `Sources/MatrixClientKitRust/Bridge/Placeholder.swift`
- Test: `Tests/MatrixClientKitRustTests/FFIStreamTests.swift`

**Interfaces:**
- Consumes: rien.
- Produces:
  `ffiStream<Element, Listener>(bufferingPolicy:makeListener:subscribe:) -> AsyncStream<Element>`,
  utilisé par les Tasks 10, 11 et 12.

- [ ] **Step 1 : Écrire les tests qui échouent**

`Tests/MatrixClientKitRustTests/FFIStreamTests.swift` :

```swift
import Testing
import Foundation
import MatrixRustSDK
@testable import MatrixClientKitRust

/// Faux `TaskHandle` : enregistre l'annulation sans toucher au binaire Rust.
private final class FakeTaskHandle: TaskHandleProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    func isFinished() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    var wasCancelled: Bool { isFinished() }
}

/// Faux listener générique : encapsule la closure d'émission.
private final class FakeListener: Sendable {
    let emit: @Sendable (Int) -> Void
    init(emit: @escaping @Sendable (Int) -> Void) { self.emit = emit }
}

/// Boîte thread-safe retenant le listener créé à l'intérieur d'une closure `@Sendable`.
private final class ListenerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var listener: FakeListener?

    func store(_ listener: FakeListener) {
        lock.lock(); self.listener = listener; lock.unlock()
    }

    func emit(_ value: Int) {
        lock.lock(); let listener = listener; lock.unlock()
        listener?.emit(value)
    }
}

@Test func streamDeliversEmittedValues() async {
    let handle = FakeTaskHandle()
    let box = ListenerBox()

    let stream = ffiStream(
        bufferingPolicy: .unbounded,
        makeListener: { emit in
            let listener = FakeListener(emit: emit)
            box.store(listener)
            return listener
        },
        subscribe: { _ in handle }
    )

    box.emit(1)
    box.emit(2)

    var received: [Int] = []
    for await value in stream {
        received.append(value)
        if received.count == 2 { break }
    }

    #expect(received == [1, 2])
}

@Test func leavingTheLoopCancelsTheUpstreamHandle() async {
    let handle = FakeTaskHandle()
    let box = ListenerBox()

    let stream = ffiStream(
        bufferingPolicy: .unbounded,
        makeListener: { emit in
            let listener = FakeListener(emit: emit)
            box.store(listener)
            return listener
        },
        subscribe: { _ in handle }
    )

    box.emit(42)
    for await _ in stream { break }

    // La terminaison est asynchrone : on laisse un tour de boucle s'écouler.
    try? await Task.sleep(for: .milliseconds(50))
    #expect(handle.wasCancelled)
}

@Test func cancellingTheConsumingTaskCancelsTheUpstreamHandle() async {
    let handle = FakeTaskHandle()

    let stream = ffiStream(
        bufferingPolicy: .unbounded,
        makeListener: { FakeListener(emit: $0) },
        subscribe: { _ in handle }
    )

    let task = Task {
        for await _ in stream {}
    }
    task.cancel()
    _ = await task.value

    try? await Task.sleep(for: .milliseconds(50))
    #expect(handle.wasCancelled)
}

@Test func failingSubscriptionFinishesTheStreamWithoutValues() async {
    struct SubscriptionFailure: Error {}

    let stream = ffiStream(
        bufferingPolicy: .unbounded,
        makeListener: { FakeListener(emit: $0) },
        subscribe: { (_: FakeListener) -> any TaskHandleProtocol in throw SubscriptionFailure() }
    )

    var received: [Int] = []
    for await value in stream { received.append(value) }
    #expect(received.isEmpty)
}
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run : `swift test --filter FFIStreamTests`
Attendu : ÉCHEC, `cannot find 'ffiStream' in scope`.

- [ ] **Step 3 : Implémenter**

Supprimer `Sources/MatrixClientKitRust/Bridge/Placeholder.swift`, puis créer
`Sources/MatrixClientKitRust/Bridge/FFIStream.swift` :

```swift
import MatrixRustSDK

/// Convertit un abonnement à listener du SDK Rust en `AsyncStream`.
///
/// Le `TaskHandle` renvoyé par l'abonnement est capturé par la continuation et annulé dès que
/// le flux se termine — sortie de boucle, annulation de tâche ou libération du consommateur.
/// L'appelant n'a donc aucun cycle de vie à gérer.
///
/// - Parameters:
///   - bufferingPolicy: `.unbounded` pour un flux de diffs, où perdre un élément corrompt
///     l'état ; `.bufferingNewest(1)` pour un flux d'instantanés, où seule la dernière valeur
///     compte.
///   - makeListener: construit le listener attendu par le SDK à partir d'une closure d'émission.
///   - subscribe: réalise l'abonnement et renvoie le handle d'annulation.
func ffiStream<Element: Sendable, Listener>(
    bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy,
    makeListener: @escaping @Sendable (@escaping @Sendable (Element) -> Void) -> Listener,
    subscribe: @escaping @Sendable (Listener) throws -> any TaskHandleProtocol
) -> AsyncStream<Element> {
    AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
        let listener = makeListener { element in
            continuation.yield(element)
        }

        do {
            let handle = try subscribe(listener)
            continuation.onTermination = { _ in
                handle.cancel()
            }
        } catch {
            continuation.finish()
        }
    }
}
```

- [ ] **Step 4 : Lancer les tests pour vérifier qu'ils passent**

Run : `swift test --filter FFIStreamTests`
Attendu : 4 tests verts.

- [ ] **Step 5 : Commit**

```bash
git add Sources/MatrixClientKitRust/Bridge Tests/MatrixClientKitRustTests/FFIStreamTests.swift
git rm --cached Sources/MatrixClientKitRust/Bridge/Placeholder.swift 2>/dev/null || true
git commit -m "feat: pont générique des listeners FFI vers AsyncStream"
```

---

### Task 7 : Modèles du domaine et protocoles de service

Tout est dans `Core`, donc sans aucun import amont.

**Files:**
- Create: `Sources/MatrixClientKitCore/Models/RoomSummary.swift`
- Create: `Sources/MatrixClientKitCore/Models/TimelineItem.swift`
- Create: `Sources/MatrixClientKitCore/Models/MessageContent.swift`
- Create: `Sources/MatrixClientKitCore/Models/SyncState.swift`
- Create: `Sources/MatrixClientKitCore/Models/MatrixSessionData.swift`
- Create: `Sources/MatrixClientKitCore/Services/MatrixClient.swift`
- Create: `Sources/MatrixClientKitCore/Services/MatrixSession.swift`
- Create: `Sources/MatrixClientKitCore/Services/RoomService.swift`
- Create: `Sources/MatrixClientKitCore/Services/SyncController.swift`
- Create: `Sources/MatrixClientKitCore/Services/Timeline.swift`
- Test: `Tests/MatrixClientKitCoreTests/ModelTests.swift`

**Interfaces:**
- Consumes: `UserID`, `RoomID`, `EventID`, `DeviceID` (Task 3), `MatrixError` (Task 4).
- Produces: `RoomSummary`, `Membership`, `TimelineItem`, `TimelineItem.Kind`, `Message`,
  `SendState`, `MessageContent`, `SyncState`, `MatrixSessionData`, et les protocoles
  `MatrixClient`, `MatrixSession`, `RoomService`, `RoomHandle`, `SyncController`, `Timeline`,
  plus `Credentials` et `RoomFilter`. Consommés par les Tasks 9 à 14.

**Écart assumé par rapport à la spec :** en v0.1, `Timeline.send(_:)` renvoie `Void`. Le handle
d'envoi (reprise, abandon) arrive en v0.4 avec les médias. Signalé ici pour que l'écart soit
délibéré et non oublié.

- [ ] **Step 1 : Écrire les tests qui échouent**

`Tests/MatrixClientKitCoreTests/ModelTests.swift` :

```swift
import Testing
import Foundation
@testable import MatrixClientKitCore

private let roomID = RoomID(rawValue: "!room:matrix.org")!
private let alice = UserID(rawValue: "@alice:matrix.org")!

private func makeSummary(notifications: Int, highlights: Int) -> RoomSummary {
    RoomSummary(
        id: roomID,
        displayName: "Salon",
        topic: nil,
        avatarURL: nil,
        isDirect: false,
        isEncrypted: true,
        joinedMemberCount: 3,
        notificationCount: notifications,
        highlightCount: highlights,
        membership: .joined
    )
}

@Test func roomSummaryReportsUnreadActivity() {
    #expect(makeSummary(notifications: 0, highlights: 0).hasUnread == false)
    #expect(makeSummary(notifications: 2, highlights: 0).hasUnread)
    #expect(makeSummary(notifications: 0, highlights: 1).hasUnread)
}

@Test func roomSummaryIsIdentifiedByItsRoomID() {
    #expect(makeSummary(notifications: 0, highlights: 0).id == roomID)
}

@Test func sendStateDistinguishesFailure() {
    #expect(SendState.failed(reason: "réseau").isFailed)
    #expect(SendState.sending.isFailed == false)
    #expect(SendState.sent.isFailed == false)
}

@Test func messageContentExposesPlainBody() {
    #expect(MessageContent.text("bonjour").plainBody == "bonjour")
    #expect(MessageContent.markdown("**gras**").plainBody == "**gras**")
}

@Test func timelineItemExposesItsMessageWhenPresent() {
    let message = Message(
        eventID: EventID(rawValue: "$abc"),
        sender: alice,
        senderDisplayName: "Alice",
        body: "bonjour",
        timestamp: Date(timeIntervalSince1970: 1_000),
        isOwn: false,
        isEdited: false,
        sendState: .sent
    )
    let item = TimelineItem(id: "1", kind: .message(message))
    #expect(item.message?.body == "bonjour")

    let separator = TimelineItem(id: "2", kind: .dateSeparator(Date(timeIntervalSince1970: 0)))
    #expect(separator.message == nil)
}

@Test func sessionDataRoundTripsThroughJSON() throws {
    let data = MatrixSessionData(
        userID: alice,
        deviceID: DeviceID(rawValue: "DEV1")!,
        homeserverURL: URL(string: "https://matrix.org")!,
        accessToken: "token",
        refreshToken: "refresh",
        oauthData: nil,
        slidingSyncVersion: "native"
    )
    let encoded = try JSONEncoder().encode(data)
    let decoded = try JSONDecoder().decode(MatrixSessionData.self, from: encoded)
    #expect(decoded == data)
}
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run : `swift test --filter ModelTests`
Attendu : ÉCHEC, `cannot find 'RoomSummary' in scope`.

- [ ] **Step 3 : Implémenter les modèles**

`Sources/MatrixClientKitCore/Models/RoomSummary.swift` :

```swift
import Foundation

/// État d'appartenance de l'utilisateur courant à une room.
public enum Membership: Sendable, Hashable {
    case joined
    case invited
    case left
    case knocked
    case banned
}

/// Vue résumée d'une room, telle qu'affichée dans une liste.
public struct RoomSummary: Sendable, Hashable, Identifiable {
    public let id: RoomID
    public let displayName: String?
    public let topic: String?
    public let avatarURL: URL?
    public let isDirect: Bool
    public let isEncrypted: Bool
    public let joinedMemberCount: Int
    public let notificationCount: Int
    public let highlightCount: Int
    public let membership: Membership

    public init(
        id: RoomID,
        displayName: String?,
        topic: String?,
        avatarURL: URL?,
        isDirect: Bool,
        isEncrypted: Bool,
        joinedMemberCount: Int,
        notificationCount: Int,
        highlightCount: Int,
        membership: Membership
    ) {
        self.id = id
        self.displayName = displayName
        self.topic = topic
        self.avatarURL = avatarURL
        self.isDirect = isDirect
        self.isEncrypted = isEncrypted
        self.joinedMemberCount = joinedMemberCount
        self.notificationCount = notificationCount
        self.highlightCount = highlightCount
        self.membership = membership
    }

    /// Vrai si la room comporte des notifications ou des mentions non lues.
    public var hasUnread: Bool { notificationCount > 0 || highlightCount > 0 }
}
```

`Sources/MatrixClientKitCore/Models/TimelineItem.swift` :

```swift
import Foundation

/// État d'acheminement d'un message envoyé localement.
public enum SendState: Sendable, Hashable {
    case sending
    case sent
    case failed(reason: String)

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// Message affichable dans une timeline.
public struct Message: Sendable, Hashable {
    public let eventID: EventID?
    public let sender: UserID
    public let senderDisplayName: String?
    public let body: String
    public let timestamp: Date
    public let isOwn: Bool
    public let isEdited: Bool
    public let sendState: SendState

    public init(
        eventID: EventID?,
        sender: UserID,
        senderDisplayName: String?,
        body: String,
        timestamp: Date,
        isOwn: Bool,
        isEdited: Bool,
        sendState: SendState
    ) {
        self.eventID = eventID
        self.sender = sender
        self.senderDisplayName = senderDisplayName
        self.body = body
        self.timestamp = timestamp
        self.isOwn = isOwn
        self.isEdited = isEdited
        self.sendState = sendState
    }
}

/// Élément d'une timeline : message, marqueur ou événement non pris en charge en v0.1.
public struct TimelineItem: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case message(Message)
        case redacted
        case unableToDecrypt(reason: String)
        case dateSeparator(Date)
        case readMarker
        case unsupported(description: String)
    }

    public let id: String
    public let kind: Kind

    public init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    /// Le message porté par cet élément, s'il s'agit d'un message.
    public var message: Message? {
        if case let .message(message) = kind { return message }
        return nil
    }
}
```

`Sources/MatrixClientKitCore/Models/MessageContent.swift` :

```swift
/// Contenu d'un message à envoyer. La v0.1 couvre le texte ; les médias arrivent en v0.4.
public enum MessageContent: Sendable, Hashable {
    case text(String)
    case markdown(String)

    /// Corps textuel brut, utilisable comme repli d'affichage.
    public var plainBody: String {
        switch self {
        case let .text(body): return body
        case let .markdown(body): return body
        }
    }
}
```

`Sources/MatrixClientKitCore/Models/SyncState.swift` :

```swift
/// État du service de synchronisation.
public enum SyncState: Sendable, Hashable {
    case idle
    case running
    case terminated
    case offline
    case error
}
```

`Sources/MatrixClientKitCore/Models/MatrixSessionData.swift` :

```swift
import Foundation

/// Données de session persistées entre deux lancements.
///
/// - Warning: contient un jeton d'accès. Ce type ne doit être écrit que dans un stockage
///   sécurisé — voir ``SecureStore``.
public struct MatrixSessionData: Sendable, Hashable, Codable {
    public let userID: UserID
    public let deviceID: DeviceID
    public let homeserverURL: URL
    public let accessToken: String
    public let refreshToken: String?
    public let oauthData: String?
    public let slidingSyncVersion: String

    public init(
        userID: UserID,
        deviceID: DeviceID,
        homeserverURL: URL,
        accessToken: String,
        refreshToken: String?,
        oauthData: String?,
        slidingSyncVersion: String
    ) {
        self.userID = userID
        self.deviceID = deviceID
        self.homeserverURL = homeserverURL
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.oauthData = oauthData
        self.slidingSyncVersion = slidingSyncVersion
    }
}

extension UserID: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = UserID(rawValue: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "identifiant utilisateur invalide : \(raw)")
            )
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension DeviceID: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = DeviceID(rawValue: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "identifiant d'appareil invalide : \(raw)")
            )
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
```

- [ ] **Step 4 : Implémenter les protocoles de service**

`Sources/MatrixClientKitCore/Services/MatrixClient.swift` :

```swift
import Foundation

/// Identifiants de connexion. La v0.1 couvre le mot de passe ; OAuth arrive en v0.4.
public enum Credentials: Sendable, Hashable {
    case password(username: String, password: String, deviceName: String?)
}

/// Client non authentifié : point d'entrée avant l'ouverture d'une session.
public protocol MatrixClient: Sendable {
    /// Adresse du homeserver auquel ce client est rattaché.
    var homeserver: URL { get }

    /// Ouvre une session et persiste les informations nécessaires à sa restauration.
    func login(_ credentials: Credentials) async throws -> any MatrixSession

    /// Restaure une session précédemment persistée, ou renvoie `nil` s'il n'y en a pas.
    func restoreSession() async throws -> (any MatrixSession)?
}
```

`Sources/MatrixClientKitCore/Services/MatrixSession.swift` :

```swift
/// Session authentifiée : tous les services en découlent.
public protocol MatrixSession: Sendable {
    var userID: UserID { get }
    var deviceID: DeviceID { get }
    var rooms: any RoomService { get }
    var sync: any SyncController { get }

    /// Ferme la session côté serveur et efface les données persistées localement.
    func logout() async throws
}
```

`Sources/MatrixClientKitCore/Services/SyncController.swift` :

```swift
/// Pilote la synchronisation avec le homeserver.
public protocol SyncController: Sendable {
    /// Flux de l'état de synchronisation. Chaque appel ouvre un abonnement indépendant.
    var state: AsyncStream<SyncState> { get }

    func start() async
    func stop() async
}
```

`Sources/MatrixClientKitCore/Services/RoomService.swift` :

```swift
/// Filtre appliqué à la liste de rooms.
public enum RoomFilter: Sendable, Hashable {
    case all
    case joined
    case invited
}

/// Accès aux rooms et à la liste observable.
public protocol RoomService: Sendable {
    /// Flux d'instantanés de la liste de rooms : chaque valeur est la liste complète et à jour.
    ///
    /// Chaque appel ouvre un abonnement indépendant, avec son propre cycle de vie.
    func list(filter: RoomFilter) -> AsyncStream<[RoomSummary]>

    /// Récupère une room par identifiant.
    func room(_ id: RoomID) async throws -> any RoomHandle
}

/// Poignée sur une room donnée.
public protocol RoomHandle: Sendable {
    var id: RoomID { get }

    /// Ouvre la timeline de la room.
    func timeline() async throws -> any Timeline
}
```

`Sources/MatrixClientKitCore/Services/Timeline.swift` :

```swift
/// Timeline d'une room : historique observable et envoi de messages.
public protocol Timeline: Sendable {
    /// Flux d'instantanés : chaque valeur est la liste complète et à jour des éléments.
    var items: AsyncStream<[TimelineItem]> { get }

    /// Charge des éléments plus anciens. Renvoie `true` s'il reste de l'historique à charger.
    @discardableResult
    func paginateBackwards(count: Int) async throws -> Bool

    /// Envoie un message. L'écho local apparaît dans ``items`` sans action supplémentaire.
    func send(_ content: MessageContent) async throws
}
```

- [ ] **Step 5 : Lancer les tests pour vérifier qu'ils passent**

Run : `swift test --filter ModelTests`
Attendu : 6 tests verts.

- [ ] **Step 6 : Commit**

```bash
git add Sources/MatrixClientKitCore/Models Sources/MatrixClientKitCore/Services Tests/MatrixClientKitCoreTests/ModelTests.swift
git commit -m "feat: modèles du domaine et protocoles de service"
```

---

### Task 8 : Stockage sécurisé et persistance de session

La logique de persistance vit dans `Core` et s'appuie sur un protocole `SecureStore`, ce qui la
rend testable sans Keychain. L'implémentation Keychain réelle, elle, est validée par la suite
d'intégration (Task 15) : les tests unitaires SPM ne disposent pas d'un Keychain signé fiable.

**Files:**
- Create: `Sources/MatrixClientKitCore/Storage/SecureStore.swift`
- Create: `Sources/MatrixClientKitCore/Storage/MatrixStorage.swift`
- Create: `Sources/MatrixClientKitCore/Storage/SessionPersistence.swift`
- Create: `Sources/MatrixClientKitRust/Storage/KeychainSecureStore.swift`
- Create: `Sources/MatrixClientKitRust/Storage/StoragePaths.swift`
- Test: `Tests/MatrixClientKitCoreTests/SessionPersistenceTests.swift`
- Test: `Tests/MatrixClientKitRustTests/StoragePathsTests.swift`

**Interfaces:**
- Consumes: `MatrixSessionData`, `MatrixError`, `UserID` (Tasks 3, 4, 7).
- Produces: `SecureStore`, `InMemorySecureStore`, `MatrixStorage`,
  `MatrixStorage.KeychainAccessibility`, `SessionPersistence`,
  `KeychainSecureStore`, `StoragePaths`. Consommés par les Tasks 9 et 14.

- [ ] **Step 1 : Écrire les tests qui échouent**

`Tests/MatrixClientKitCoreTests/SessionPersistenceTests.swift` :

```swift
import Testing
import Foundation
@testable import MatrixClientKitCore

private func makeSessionData(token: String = "token") -> MatrixSessionData {
    MatrixSessionData(
        userID: UserID(rawValue: "@alice:matrix.org")!,
        deviceID: DeviceID(rawValue: "DEV1")!,
        homeserverURL: URL(string: "https://matrix.org")!,
        accessToken: token,
        refreshToken: nil,
        oauthData: nil,
        slidingSyncVersion: "native"
    )
}

@Test func loadReturnsNilWhenNothingWasSaved() async throws {
    let persistence = SessionPersistence(store: InMemorySecureStore())
    #expect(try await persistence.load() == nil)
}

@Test func savedSessionIsLoadedBack() async throws {
    let persistence = SessionPersistence(store: InMemorySecureStore())
    let session = makeSessionData()
    try await persistence.save(session)
    #expect(try await persistence.load() == session)
}

@Test func savingTwiceKeepsTheMostRecentSession() async throws {
    let persistence = SessionPersistence(store: InMemorySecureStore())
    try await persistence.save(makeSessionData(token: "ancien"))
    try await persistence.save(makeSessionData(token: "nouveau"))
    #expect(try await persistence.load()?.accessToken == "nouveau")
}

@Test func clearRemovesThePersistedSession() async throws {
    let persistence = SessionPersistence(store: InMemorySecureStore())
    try await persistence.save(makeSessionData())
    try await persistence.clear()
    #expect(try await persistence.load() == nil)
}

@Test func corruptedPayloadSurfacesAsStorageError() async throws {
    let store = InMemorySecureStore()
    try store.set(Data("pas du json".utf8), forKey: SessionPersistence.storageKey)
    let persistence = SessionPersistence(store: store)

    await #expect(throws: MatrixError.storage(.corrupted)) {
        _ = try await persistence.load()
    }
}
```

`Tests/MatrixClientKitRustTests/StoragePathsTests.swift` :

```swift
import Testing
import Foundation
@testable import MatrixClientKitRust
import MatrixClientKitCore

@Test func localStorageUsesTheProvidedDirectory() throws {
    let root = URL(fileURLWithPath: "/tmp/matrixclientkit-tests", isDirectory: true)
    let paths = try StoragePaths(storage: .local(directory: root))

    #expect(paths.dataDirectory.path.hasPrefix(root.path))
    #expect(paths.cacheDirectory.path.hasPrefix(root.path))
    #expect(paths.dataDirectory != paths.cacheDirectory)
}

@Test func directoriesAreCreatedOnDemand() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mck-\(UUID().uuidString)", isDirectory: true)
    let paths = try StoragePaths(storage: .local(directory: root))
    try paths.createDirectoriesIfNeeded()

    #expect(FileManager.default.fileExists(atPath: paths.dataDirectory.path))
    #expect(FileManager.default.fileExists(atPath: paths.cacheDirectory.path))

    try? FileManager.default.removeItem(at: root)
}

@Test func unknownAppGroupSurfacesAsStorageError() {
    #expect(throws: MatrixError.storage(.unavailable)) {
        _ = try StoragePaths(storage: .appGroup("group.invalide.inexistant"))
    }
}
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run : `swift test --filter "SessionPersistenceTests|StoragePathsTests"`
Attendu : ÉCHEC, `cannot find 'SessionPersistence' in scope`.

- [ ] **Step 3 : Implémenter la couche Core**

`Sources/MatrixClientKitCore/Storage/SecureStore.swift` :

```swift
import Foundation

/// Stockage de secrets. Abstrait pour que la logique de persistance reste testable
/// sans dépendre du Keychain.
public protocol SecureStore: Sendable {
    func data(forKey key: String) throws -> Data?
    func set(_ data: Data, forKey key: String) throws
    func removeValue(forKey key: String) throws
}

/// Implémentation en mémoire, destinée aux tests et aux mocks.
public final class InMemorySecureStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    public init() {}

    public func data(forKey key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    public func set(_ data: Data, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }

    public func removeValue(forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = nil
    }
}
```

`Sources/MatrixClientKitCore/Storage/MatrixStorage.swift` :

```swift
import Foundation

/// Emplacement et protection des données persistées par le SDK.
public struct MatrixStorage: Sendable, Hashable {

    /// Moment à partir duquel les secrets sont lisibles.
    ///
    /// - Important: une extension de notification s'exécute appareil verrouillé. Avec
    ///   ``whenUnlocked``, elle ne peut pas lire le jeton et la notification arrive vide.
    ///   ``afterFirstUnlock`` est le défaut pour cette raison.
    public enum KeychainAccessibility: Sendable, Hashable {
        case afterFirstUnlock
        case whenUnlocked
    }

    public enum Location: Sendable, Hashable {
        case appGroup(identifier: String)
        case local(directory: URL)
    }

    public let location: Location
    public let keychainAccessGroup: String?
    public let accessibility: KeychainAccessibility

    /// Stockage partagé entre l'application et ses extensions.
    public static func appGroup(
        _ identifier: String,
        keychainAccessGroup: String? = nil,
        accessibility: KeychainAccessibility = .afterFirstUnlock
    ) -> MatrixStorage {
        MatrixStorage(
            location: .appGroup(identifier: identifier),
            keychainAccessGroup: keychainAccessGroup,
            accessibility: accessibility
        )
    }

    /// Stockage propre au processus courant, sans partage avec une extension.
    public static func local(
        directory: URL,
        accessibility: KeychainAccessibility = .afterFirstUnlock
    ) -> MatrixStorage {
        MatrixStorage(location: .local(directory: directory), keychainAccessGroup: nil, accessibility: accessibility)
    }
}
```

`Sources/MatrixClientKitCore/Storage/SessionPersistence.swift` :

```swift
import Foundation

/// Enregistre et relit les données de session dans un stockage sécurisé.
public actor SessionPersistence {
    public static let storageKey = "com.matrixclientkit.session"

    private let store: any SecureStore

    public init(store: any SecureStore) {
        self.store = store
    }

    public func save(_ session: MatrixSessionData) throws {
        do {
            let data = try JSONEncoder().encode(session)
            try store.set(data, forKey: Self.storageKey)
        } catch let error as MatrixError {
            throw error
        } catch {
            throw MatrixError.storage(.unavailable)
        }
    }

    public func load() throws -> MatrixSessionData? {
        let data: Data?
        do {
            data = try store.data(forKey: Self.storageKey)
        } catch let error as MatrixError {
            throw error
        } catch {
            throw MatrixError.storage(.unavailable)
        }

        guard let data else { return nil }

        do {
            return try JSONDecoder().decode(MatrixSessionData.self, from: data)
        } catch {
            throw MatrixError.storage(.corrupted)
        }
    }

    public func clear() throws {
        do {
            try store.removeValue(forKey: Self.storageKey)
        } catch {
            throw MatrixError.storage(.unavailable)
        }
    }
}
```

- [ ] **Step 4 : Implémenter la couche Rust**

`Sources/MatrixClientKitRust/Storage/StoragePaths.swift` :

```swift
import Foundation
import MatrixClientKitCore

/// Résout les répertoires utilisés par le store SQLite du SDK.
struct StoragePaths: Sendable {
    let dataDirectory: URL
    let cacheDirectory: URL

    init(storage: MatrixStorage) throws {
        let root: URL
        switch storage.location {
        case let .appGroup(identifier):
            guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
                throw MatrixError.storage(.unavailable)
            }
            root = container
        case let .local(directory):
            root = directory
        }

        dataDirectory = root.appendingPathComponent("MatrixClientKit/data", isDirectory: true)
        cacheDirectory = root.appendingPathComponent("MatrixClientKit/cache", isDirectory: true)
    }

    /// Crée les répertoires et applique la protection de fichiers requise par les extensions.
    ///
    /// - Important: sans `completeUntilFirstUserAuthentication`, une extension de notification
    ///   plante à l'ouverture du store lorsque l'appareil est verrouillé.
    func createDirectoriesIfNeeded() throws {
        for directory in [dataDirectory, cacheDirectory] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        }
    }
}
```

`Sources/MatrixClientKitRust/Storage/KeychainSecureStore.swift` :

```swift
import Foundation
import Security
import MatrixClientKitCore

/// Stockage de secrets adossé au Keychain, partageable avec une extension via un access group.
public struct KeychainSecureStore: SecureStore {
    private let service = "com.matrixclientkit"
    private let accessGroup: String?
    private let accessibility: CFString

    public init(storage: MatrixStorage) {
        accessGroup = storage.keychainAccessGroup
        accessibility = switch storage.accessibility {
        case .afterFirstUnlock: kSecAttrAccessibleAfterFirstUnlock
        case .whenUnlocked: kSecAttrAccessibleWhenUnlocked
        }
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    public func data(forKey key: String) throws -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw MatrixError.storage(.keychainFailure(status: status))
        }
    }

    public func set(_ data: Data, forKey key: String) throws {
        try removeValue(forKey: key)

        var query = baseQuery(forKey: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = accessibility

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw MatrixError.storage(.keychainFailure(status: status))
        }
    }

    public func removeValue(forKey key: String) throws {
        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MatrixError.storage(.keychainFailure(status: status))
        }
    }
}
```

- [ ] **Step 5 : Lancer les tests pour vérifier qu'ils passent**

Run : `swift test --filter "SessionPersistenceTests|StoragePathsTests"`
Attendu : 8 tests verts.

- [ ] **Step 6 : Commit**

```bash
git add Sources/MatrixClientKitCore/Storage Sources/MatrixClientKitRust/Storage Tests/MatrixClientKitCoreTests/SessionPersistenceTests.swift Tests/MatrixClientKitRustTests/StoragePathsTests.swift
git commit -m "feat: stockage sécurisé, chemins de store et persistance de session"
```

---

> **Convention obligatoire pour toutes les tâches suivantes.** Plusieurs types du SDK amont
> portent le même nom que les nôtres — `Timeline`, `TimelineItem`, `Message`, `RoomInfo`. Dans
> `MatrixClientKitRust`, **toujours qualifier** : `MatrixRustSDK.TimelineItem` pour le type amont,
> `MatrixClientKitCore.TimelineItem` pour le nôtre. Une ambiguïté non qualifiée produit des
> erreurs de compilation difficiles à lire.

### Task 9 : Conversion de session et client authentifiable

**Files:**
- Create: `Sources/MatrixClientKitRust/Bridge/SessionMapper.swift`
- Create: `Sources/MatrixClientKitRust/RustMatrixClient.swift`
- Create: `Sources/MatrixClientKitRust/RustMatrixSession.swift`
- Test: `Tests/MatrixClientKitRustTests/SessionMapperTests.swift`

**Interfaces:**
- Consumes: `MatrixSessionData`, `MatrixClient`, `MatrixSession`, `Credentials` (Task 7),
  `SessionPersistence`, `StoragePaths`, `KeychainSecureStore` (Task 8), `ErrorMapper` (Task 5).
- Produces: `SessionMapper.sessionData(from:)`, `SessionMapper.session(from:)`,
  `RustMatrixClient(homeserver:storage:)`, `RustMatrixSession.make(client:persistence:)`.
  Consommés par les Tasks 10, 12 et 15.

**Couverture :** seul `SessionMapper` est testable unitairement — il construit des valeurs amont
sans les exécuter. `RustMatrixClient` requiert un homeserver joignable et relève de la suite
d'intégration (Task 16).

- [ ] **Step 1 : Écrire les tests qui échouent**

`Tests/MatrixClientKitRustTests/SessionMapperTests.swift` :

```swift
import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private func makeUpstreamSession() -> Session {
    Session(
        accessToken: "token",
        refreshToken: "refresh",
        userId: "@alice:matrix.org",
        deviceId: "DEV1",
        homeserverUrl: "https://matrix.org",
        oauthData: nil,
        slidingSyncVersion: .native
    )
}

@Test func upstreamSessionConvertsToSessionData() throws {
    let data = try SessionMapper.sessionData(from: makeUpstreamSession())

    #expect(data.userID.rawValue == "@alice:matrix.org")
    #expect(data.deviceID.rawValue == "DEV1")
    #expect(data.homeserverURL == URL(string: "https://matrix.org"))
    #expect(data.accessToken == "token")
    #expect(data.refreshToken == "refresh")
    #expect(data.slidingSyncVersion == "native")
}

@Test func sessionDataConvertsBackToUpstreamSession() throws {
    let data = try SessionMapper.sessionData(from: makeUpstreamSession())
    let session = SessionMapper.session(from: data)

    #expect(session.accessToken == "token")
    #expect(session.userId == "@alice:matrix.org")
    #expect(session.deviceId == "DEV1")
    #expect(session.homeserverUrl == "https://matrix.org")
}

@Test func malformedUserIdentifierSurfacesAsUnexpectedError() {
    let session = Session(
        accessToken: "token",
        refreshToken: nil,
        userId: "alice-sans-arobase",
        deviceId: "DEV1",
        homeserverUrl: "https://matrix.org",
        oauthData: nil,
        slidingSyncVersion: .native
    )

    #expect(throws: MatrixError.self) {
        _ = try SessionMapper.sessionData(from: session)
    }
}
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run : `swift test --filter SessionMapperTests`
Attendu : ÉCHEC, `cannot find 'SessionMapper' in scope`.

- [ ] **Step 3 : Implémenter le mappeur**

`Sources/MatrixClientKitRust/Bridge/SessionMapper.swift` :

```swift
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

    private static func slidingSyncIdentifier(_ version: SlidingSyncVersion) -> String {
        switch version {
        case .none: "none"
        case .native: "native"
        case .discoverNative: "discoverNative"
        }
    }

    private static func slidingSyncVersion(_ identifier: String) -> SlidingSyncVersion {
        switch identifier {
        case "none": .none
        case "discoverNative": .discoverNative
        default: .native
        }
    }
}
```

- [ ] **Step 4 : Lancer les tests pour vérifier qu'ils passent**

Run : `swift test --filter SessionMapperTests`
Attendu : 3 tests verts.

- [ ] **Step 5 : Implémenter le client et la session**

`Sources/MatrixClientKitRust/RustMatrixClient.swift` :

```swift
import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``MatrixClient`` adossée au SDK Rust.
public final class RustMatrixClient: MatrixClientKitCore.MatrixClient {
    public let homeserver: URL

    private let storage: MatrixStorage
    private let persistence: SessionPersistence

    public init(homeserver: URL, storage: MatrixStorage) {
        self.homeserver = homeserver
        self.storage = storage
        self.persistence = SessionPersistence(store: KeychainSecureStore(storage: storage))
    }

    public func login(_ credentials: Credentials) async throws -> any MatrixClientKitCore.MatrixSession {
        let client = try await makeClient()

        do {
            switch credentials {
            case let .password(username, password, deviceName):
                try await client.login(
                    username: username,
                    password: password,
                    initialDeviceName: deviceName,
                    deviceId: nil
                )
            }

            let session = try client.session()
            try await persistence.save(SessionMapper.sessionData(from: session))
            return try await RustMatrixSession.make(client: client, persistence: persistence)
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    public func restoreSession() async throws -> (any MatrixClientKitCore.MatrixSession)? {
        guard let data = try await persistence.load() else { return nil }

        let client = try await makeClient()
        do {
            try await client.restoreSession(session: SessionMapper.session(from: data))
            return try await RustMatrixSession.make(client: client, persistence: persistence)
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    private func makeClient() async throws -> Client {
        do {
            let paths = try StoragePaths(storage: storage)
            try paths.createDirectoriesIfNeeded()

            return try await ClientBuilder()
                .homeserverUrl(url: homeserver.absoluteString)
                .sessionPaths(
                    dataPath: paths.dataDirectory.path,
                    cachePath: paths.cacheDirectory.path
                )
                .build()
        } catch {
            throw ErrorMapper.map(error)
        }
    }
}
```

`Sources/MatrixClientKitRust/RustMatrixSession.swift` :

```swift
import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``MatrixSession`` adossée au SDK Rust.
public final class RustMatrixSession: MatrixClientKitCore.MatrixSession {
    public let userID: UserID
    public let deviceID: DeviceID
    public let rooms: any RoomService
    public let sync: any SyncController

    private let client: Client
    private let persistence: SessionPersistence

    private init(
        client: Client,
        persistence: SessionPersistence,
        userID: UserID,
        deviceID: DeviceID,
        rooms: any RoomService,
        sync: any SyncController
    ) {
        self.client = client
        self.persistence = persistence
        self.userID = userID
        self.deviceID = deviceID
        self.rooms = rooms
        self.sync = sync
    }

    static func make(client: Client, persistence: SessionPersistence) async throws -> RustMatrixSession {
        do {
            let session = try client.session()
            let data = try SessionMapper.sessionData(from: session)
            let syncService = try await client.syncService().finish()

            return RustMatrixSession(
                client: client,
                persistence: persistence,
                userID: data.userID,
                deviceID: data.deviceID,
                rooms: RustRoomService(roomListService: syncService.roomListService()),
                sync: RustSyncController(service: syncService)
            )
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    public func logout() async throws {
        do {
            await sync.stop()
            try await client.logout()
        } catch {
            try? await persistence.clear()
            throw ErrorMapper.map(error)
        }
        try await persistence.clear()
    }
}
```

- [ ] **Step 6 : Compiler**

Run : `swift build`
Attendu : compilation réussie une fois les Tasks 10 et 12 écrites. Si `RustRoomService` ou
`RustSyncController` n'existent pas encore, exécuter les Tasks 10 et 12 avant de relancer cette
étape — c'est la seule dépendance circulaire du plan, et elle est volontaire : le fichier session
est le point de couture.

- [ ] **Step 7 : Commit**

```bash
git add Sources/MatrixClientKitRust Tests/MatrixClientKitRustTests/SessionMapperTests.swift
git commit -m "feat: conversion de session, client et session authentifiée"
```

---

### Task 10 : Contrôleur de synchronisation

**Files:**
- Create: `Sources/MatrixClientKitRust/RustSyncController.swift`
- Create: `Sources/MatrixClientKitRust/Bridge/SyncServiceDriving.swift`
- Test: `Tests/MatrixClientKitRustTests/SyncControllerTests.swift`

**Interfaces:**
- Consumes: `SyncController`, `SyncState` (Task 7), `ffiStream` (Task 6).
- Produces: `RustSyncController(service:)`, `SyncServiceDriving`. Consommé par la Task 9.

**Pourquoi une couture supplémentaire :** `SyncServiceProtocol` amont exige de renvoyer un
`RoomListService`, type concret impossible à construire dans un test. On introduit donc
`SyncServiceDriving`, un protocole réduit aux trois opérations dont le contrôleur a besoin, que
`SyncService` satisfait et qu'un faux peut implémenter.

- [ ] **Step 1 : Écrire les tests qui échouent**

`Tests/MatrixClientKitRustTests/SyncControllerTests.swift` :

```swift
import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private final class FakeTaskHandle: TaskHandleProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func isFinished() -> Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

private final class FakeSyncService: SyncServiceDriving, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private var observer: (any SyncServiceStateObserver)?

    func start() async { lock.lock(); startCallCount += 1; lock.unlock() }
    func stop() async { lock.lock(); stopCallCount += 1; lock.unlock() }

    func observeState(_ listener: any SyncServiceStateObserver) -> any TaskHandleProtocol {
        lock.lock(); observer = listener; lock.unlock()
        return FakeTaskHandle()
    }

    func emit(_ state: SyncServiceState) {
        lock.lock(); let observer = observer; lock.unlock()
        observer?.onUpdate(state: state)
    }
}

@Test func startAndStopAreForwardedToTheService() async {
    let service = FakeSyncService()
    let controller = RustSyncController(service: service)

    await controller.start()
    await controller.stop()

    #expect(service.startCallCount == 1)
    #expect(service.stopCallCount == 1)
}

@Test func upstreamStatesAreMappedToDomainStates() async {
    let service = FakeSyncService()
    let controller = RustSyncController(service: service)
    let stream = controller.state

    service.emit(.running)
    service.emit(.offline)

    var received: [SyncState] = []
    for await state in stream {
        received.append(state)
        if received.count == 2 { break }
    }

    #expect(received == [.running, .offline])
}

@Test func everyUpstreamStateHasAMapping() {
    #expect(SyncStateMapper.map(.idle) == .idle)
    #expect(SyncStateMapper.map(.running) == .running)
    #expect(SyncStateMapper.map(.terminated) == .terminated)
    #expect(SyncStateMapper.map(.error) == .error)
    #expect(SyncStateMapper.map(.offline) == .offline)
}
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run : `swift test --filter SyncControllerTests`
Attendu : ÉCHEC, `cannot find 'SyncServiceDriving' in scope`.

- [ ] **Step 3 : Implémenter**

`Sources/MatrixClientKitRust/Bridge/SyncServiceDriving.swift` :

```swift
import MatrixRustSDK

/// Sous-ensemble du service de synchronisation amont dont le contrôleur a besoin.
///
/// Cette couture existe pour la testabilité : `SyncServiceProtocol` impose de renvoyer un
/// `RoomListService`, type concret qu'un test ne peut pas construire.
protocol SyncServiceDriving: Sendable {
    func start() async
    func stop() async
    func observeState(_ listener: any SyncServiceStateObserver) -> any TaskHandleProtocol
}

extension SyncService: SyncServiceDriving {
    func observeState(_ listener: any SyncServiceStateObserver) -> any TaskHandleProtocol {
        state(listener: listener)
    }
}
```

`Sources/MatrixClientKitRust/RustSyncController.swift` :

```swift
import MatrixRustSDK
import MatrixClientKitCore

/// Traduit les états de synchronisation amont vers le domaine.
enum SyncStateMapper {
    static func map(_ state: SyncServiceState) -> SyncState {
        switch state {
        case .idle: .idle
        case .running: .running
        case .terminated: .terminated
        case .error: .error
        case .offline: .offline
        }
    }
}

/// Listener d'état conforme au protocole amont, alimenté par une closure.
private final class StateObserver: SyncServiceStateObserver {
    private let handler: @Sendable (SyncServiceState) -> Void

    init(handler: @escaping @Sendable (SyncServiceState) -> Void) {
        self.handler = handler
    }

    func onUpdate(state: SyncServiceState) {
        handler(state)
    }
}

/// Implémentation de ``SyncController`` adossée au SDK Rust.
public final class RustSyncController: SyncController {
    private let service: any SyncServiceDriving

    init(service: any SyncServiceDriving) {
        self.service = service
    }

    /// Flux d'états. Politique `.bufferingNewest(1)` : seul l'état courant a de la valeur.
    public var state: AsyncStream<SyncState> {
        let service = service
        return ffiStream(
            bufferingPolicy: .bufferingNewest(1),
            makeListener: { emit in
                StateObserver { state in emit(SyncStateMapper.map(state)) }
            },
            subscribe: { listener in service.observeState(listener) }
        )
    }

    public func start() async {
        await service.start()
    }

    public func stop() async {
        await service.stop()
    }
}
```

- [ ] **Step 4 : Lancer les tests pour vérifier qu'ils passent**

Run : `swift test --filter SyncControllerTests`
Attendu : 3 tests verts.

- [ ] **Step 5 : Commit**

```bash
git add Sources/MatrixClientKitRust/RustSyncController.swift Sources/MatrixClientKitRust/Bridge/SyncServiceDriving.swift Tests/MatrixClientKitRustTests/SyncControllerTests.swift
git commit -m "feat: contrôleur de synchronisation et flux d'état"
```

---

### Task 11 : Pipeline d'instantanés

Transforme un flux de diffs en flux d'états complets. Entièrement dans `Core`, donc pur et
testable sans binaire. Réutilisé tel quel par la liste de rooms (Task 12) et la timeline
(Task 13).

**Files:**
- Create: `Sources/MatrixClientKitCore/Diffing/SnapshotStream.swift`
- Test: `Tests/MatrixClientKitCoreTests/SnapshotStreamTests.swift`

**Interfaces:**
- Consumes: `CollectionDiff`, `CollectionDiffApplier` (Task 2).
- Produces:
  `snapshotStream<Element>(from diffs: AsyncStream<[CollectionDiff<Element>]>, initial: [Element]) -> AsyncStream<[Element]>`.
  Consommé par les Tasks 12 et 13.

- [ ] **Step 1 : Écrire les tests qui échouent**

`Tests/MatrixClientKitCoreTests/SnapshotStreamTests.swift` :

```swift
import Testing
@testable import MatrixClientKitCore

@Test func eachBatchOfDiffsProducesASnapshot() async {
    let (diffs, continuation) = AsyncStream<[CollectionDiff<String>]>.makeStream()
    let snapshots = snapshotStream(from: diffs, initial: [])

    continuation.yield([.append(["a"])])
    continuation.yield([.pushBack("b")])

    var received: [[String]] = []
    for await snapshot in snapshots {
        received.append(snapshot)
        if received.count == 2 { break }
    }

    #expect(received == [["a"], ["a", "b"]])
}

@Test func snapshotsStartFromTheInitialValue() async {
    let (diffs, continuation) = AsyncStream<[CollectionDiff<String>]>.makeStream()
    let snapshots = snapshotStream(from: diffs, initial: ["z"])

    continuation.yield([.pushBack("a")])

    var received: [[String]] = []
    for await snapshot in snapshots {
        received.append(snapshot)
        break
    }

    #expect(received == [["z", "a"]])
}

@Test func snapshotStreamFinishesWhenTheDiffStreamFinishes() async {
    let (diffs, continuation) = AsyncStream<[CollectionDiff<String>]>.makeStream()
    let snapshots = snapshotStream(from: diffs, initial: [])

    continuation.yield([.append(["a"])])
    continuation.finish()

    var count = 0
    for await _ in snapshots { count += 1 }

    #expect(count == 1)
}

@Test func diffsWithinOneBatchAreComposedIntoASingleSnapshot() async {
    let (diffs, continuation) = AsyncStream<[CollectionDiff<String>]>.makeStream()
    let snapshots = snapshotStream(from: diffs, initial: [])

    continuation.yield([.append(["a", "b"]), .remove(index: 0), .pushFront("z")])

    var received: [[String]] = []
    for await snapshot in snapshots {
        received.append(snapshot)
        break
    }

    #expect(received == [["z", "b"]])
}
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run : `swift test --filter SnapshotStreamTests`
Attendu : ÉCHEC, `cannot find 'snapshotStream' in scope`.

- [ ] **Step 3 : Implémenter**

`Sources/MatrixClientKitCore/Diffing/SnapshotStream.swift` :

```swift
/// Transforme un flux de diffs en flux d'états complets.
///
/// Le flux d'entrée est consommé en `.unbounded` — perdre un diff corromprait l'état —, tandis
/// que les instantanés produits utilisent `.bufferingNewest(1)` : un consommateur lent ne voit
/// que le dernier état, et la mémoire reste bornée.
public func snapshotStream<Element: Sendable>(
    from diffs: AsyncStream<[CollectionDiff<Element>]>,
    initial: [Element] = []
) -> AsyncStream<[Element]> {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
        let task = Task {
            var current = initial
            for await batch in diffs {
                current = CollectionDiffApplier.apply(batch, to: current)
                continuation.yield(current)
            }
            continuation.finish()
        }

        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}
```

- [ ] **Step 4 : Lancer les tests pour vérifier qu'ils passent**

Run : `swift test --filter SnapshotStreamTests`
Attendu : 4 tests verts.

- [ ] **Step 5 : Commit**

```bash
git add Sources/MatrixClientKitCore/Diffing/SnapshotStream.swift Tests/MatrixClientKitCoreTests/SnapshotStreamTests.swift
git commit -m "feat: pipeline transformant les diffs en instantanés"
```

---

### Task 12 : Service de rooms et liste observable

**Files:**
- Create: `Sources/MatrixClientKitRust/Bridge/RoomMapper.swift`
- Create: `Sources/MatrixClientKitRust/RustRoomService.swift`
- Test: `Tests/MatrixClientKitRustTests/RoomFilterTests.swift`

**Interfaces:**
- Consumes: `RoomService`, `RoomHandle`, `RoomSummary`, `RoomFilter`, `Membership` (Task 7),
  `snapshotStream` (Task 11), `ffiStream` (Task 6), `ErrorMapper` (Task 5).
- Produces: `RustRoomService(roomListService:)`, `RustRoomHandle`,
  `RoomMapper.summary(from:)`, `RoomMapper.filterKind(for:)`. Consommés par les Tasks 9 et 13.

**Couverture :** `RoomMapper.filterKind(for:)` est pur et testé unitairement. La traduction
`RoomListEntriesUpdate` → `CollectionDiff<RoomSummary>` manipule des instances `Room` que seul le
SDK peut produire ; elle est délibérément réduite à un `switch` mécanique et couverte par la suite
d'intégration (Task 16).

- [ ] **Step 1 : Écrire le test qui échoue**

`Tests/MatrixClientKitRustTests/RoomFilterTests.swift` :

```swift
import Testing
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

@Test func joinedFilterMapsToUpstreamJoinedFilter() {
    guard case .joined = RoomMapper.filterKind(for: .joined) else {
        Issue.record("attendu .joined")
        return
    }
}

@Test func invitedFilterMapsToUpstreamInviteFilter() {
    guard case .invite = RoomMapper.filterKind(for: .invited) else {
        Issue.record("attendu .invite")
        return
    }
}

@Test func allFilterMapsToAnEmptyConjunction() {
    guard case let .all(filters) = RoomMapper.filterKind(for: .all) else {
        Issue.record("attendu .all")
        return
    }
    #expect(filters.isEmpty)
}

@Test func membershipIsMappedForEveryUpstreamCase() {
    #expect(RoomMapper.membership(from: .joined) == .joined)
    #expect(RoomMapper.membership(from: .invited) == .invited)
    #expect(RoomMapper.membership(from: .left) == .left)
    #expect(RoomMapper.membership(from: .knocked) == .knocked)
    #expect(RoomMapper.membership(from: .banned) == .banned)
}
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run : `swift test --filter RoomFilterTests`
Attendu : ÉCHEC, `cannot find 'RoomMapper' in scope`.

- [ ] **Step 3 : Implémenter le mappeur**

`Sources/MatrixClientKitRust/Bridge/RoomMapper.swift` :

```swift
import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Traduit les types de room amont vers le domaine.
enum RoomMapper {

    static func filterKind(for filter: RoomFilter) -> RoomListEntriesDynamicFilterKind {
        switch filter {
        case .all: .all(filters: [])
        case .joined: .joined
        case .invited: .invite
        }
    }

    static func membership(from membership: MatrixRustSDK.Membership) -> MatrixClientKitCore.Membership {
        switch membership {
        case .joined: .joined
        case .invited: .invited
        case .left: .left
        case .knocked: .knocked
        case .banned: .banned
        }
    }

    /// Construit un résumé de room. Renvoie `nil` si l'identifiant amont est inexploitable.
    static func summary(from room: Room) async -> RoomSummary? {
        guard let id = RoomID(rawValue: room.id()) else { return nil }

        let info = try? await room.roomInfo()

        return RoomSummary(
            id: id,
            displayName: info?.displayName ?? room.displayName(),
            topic: info?.topic,
            avatarURL: info?.avatarUrl.flatMap(URL.init(string:)),
            isDirect: info?.isDirect ?? false,
            isEncrypted: info?.encryptionState == .encrypted,
            joinedMemberCount: Int(info?.joinedMembersCount ?? room.joinedMembersCount()),
            notificationCount: Int(info?.notificationCount ?? 0),
            highlightCount: Int(info?.highlightCount ?? 0),
            membership: info.map { membership(from: $0.membership) } ?? .joined
        )
    }

    /// Traduit une mise à jour de liste amont en diff de collection du domaine.
    static func diff(from update: RoomListEntriesUpdate) async -> CollectionDiff<RoomSummary>? {
        switch update {
        case let .append(values):
            return .append(await summaries(from: values))
        case .clear:
            return .clear
        case let .pushFront(value):
            guard let summary = await summary(from: value) else { return nil }
            return .pushFront(summary)
        case let .pushBack(value):
            guard let summary = await summary(from: value) else { return nil }
            return .pushBack(summary)
        case .popFront:
            return .popFront
        case .popBack:
            return .popBack
        case let .insert(index, value):
            guard let summary = await summary(from: value) else { return nil }
            return .insert(index: Int(index), summary)
        case let .set(index, value):
            guard let summary = await summary(from: value) else { return nil }
            return .set(index: Int(index), summary)
        case let .remove(index):
            return .remove(index: Int(index))
        case let .truncate(length):
            return .truncate(length: Int(length))
        case let .reset(values):
            return .reset(await summaries(from: values))
        }
    }

    private static func summaries(from rooms: [Room]) async -> [RoomSummary] {
        var result: [RoomSummary] = []
        result.reserveCapacity(rooms.count)
        for room in rooms {
            if let summary = await summary(from: room) {
                result.append(summary)
            }
        }
        return result
    }
}
```

- [ ] **Step 4 : Lancer le test pour vérifier qu'il passe**

Run : `swift test --filter RoomFilterTests`
Attendu : 4 tests verts.

- [ ] **Step 5 : Implémenter le service**

`Sources/MatrixClientKitRust/RustRoomService.swift` :

```swift
import MatrixRustSDK
import MatrixClientKitCore

/// Listener d'entrées de liste conforme au protocole amont, alimenté par une closure.
private final class EntriesListener: RoomListEntriesListener {
    private let handler: @Sendable ([RoomListEntriesUpdate]) -> Void

    init(handler: @escaping @Sendable ([RoomListEntriesUpdate]) -> Void) {
        self.handler = handler
    }

    func onUpdate(roomEntriesUpdate: [RoomListEntriesUpdate]) {
        handler(roomEntriesUpdate)
    }
}

/// Implémentation de ``RoomService`` adossée au SDK Rust.
public final class RustRoomService: RoomService {
    private let roomListService: RoomListService

    init(roomListService: RoomListService) {
        self.roomListService = roomListService
    }

    public func list(filter: RoomFilter) -> AsyncStream<[RoomSummary]> {
        let service = roomListService
        let filterKind = RoomMapper.filterKind(for: filter)

        // Flux brut des mises à jour amont, en .unbounded : aucun diff ne doit être perdu.
        let updates = AsyncStream<[RoomListEntriesUpdate]>(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    let roomList = try await service.allRooms()
                    let listener = EntriesListener { updates in
                        continuation.yield(updates)
                    }
                    let result = roomList.entriesWithDynamicAdapters(pageSize: 50, listener: listener)
                    _ = result.controller().setFilter(kind: filterKind)
                    let handle = result.entriesStream()

                    continuation.onTermination = { _ in
                        handle.cancel()
                    }
                } catch {
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        // Traduction des mises à jour amont en diffs du domaine, en préservant l'ordre.
        let diffs = AsyncStream<[CollectionDiff<RoomSummary>]>(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                for await batch in updates {
                    var translated: [CollectionDiff<RoomSummary>] = []
                    for update in batch {
                        if let diff = await RoomMapper.diff(from: update) {
                            translated.append(diff)
                        }
                    }
                    continuation.yield(translated)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        return snapshotStream(from: diffs)
    }

    public func room(_ id: RoomID) async throws -> any RoomHandle {
        do {
            let room = try roomListService.room(roomId: id.rawValue)
            return RustRoomHandle(id: id, room: room)
        } catch {
            throw ErrorMapper.map(error)
        }
    }
}

/// Implémentation de ``RoomHandle`` adossée au SDK Rust.
public final class RustRoomHandle: RoomHandle {
    public let id: RoomID
    private let room: Room

    init(id: RoomID, room: Room) {
        self.id = id
        self.room = room
    }

    public func timeline() async throws -> any MatrixClientKitCore.Timeline {
        do {
            return RustTimeline(timeline: try await room.timeline())
        } catch {
            throw ErrorMapper.map(error)
        }
    }
}
```

- [ ] **Step 6 : Commit**

```bash
git add Sources/MatrixClientKitRust/RustRoomService.swift Sources/MatrixClientKitRust/Bridge/RoomMapper.swift Tests/MatrixClientKitRustTests/RoomFilterTests.swift
git commit -m "feat: service de rooms et liste observable en instantanés"
```

---

### Task 13 : Timeline

**Files:**
- Create: `Sources/MatrixClientKitRust/Bridge/TimelineMapper.swift`
- Create: `Sources/MatrixClientKitRust/RustTimeline.swift`
- Test: `Tests/MatrixClientKitRustTests/MessageContentTests.swift`

**Interfaces:**
- Consumes: `Timeline`, `TimelineItem`, `Message`, `SendState`, `MessageContent` (Task 7),
  `snapshotStream` (Task 11), `ErrorMapper` (Task 5).
- Produces: `RustTimeline(timeline:)`, `TimelineMapper.item(from:)`,
  `TimelineMapper.eventContent(for:)`, `TimelineMapper.sendState(from:)`. Consommé par la Task 12.

- [ ] **Step 1 : Écrire les tests qui échouent**

`Tests/MatrixClientKitRustTests/MessageContentTests.swift` :

```swift
import Testing
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

@Test func plainTextProducesATextEventContent() throws {
    let content = try TimelineMapper.eventContent(for: .text("bonjour"))
    #expect(content.body == "bonjour")
}

@Test func markdownProducesAFormattedEventContent() throws {
    let content = try TimelineMapper.eventContent(for: .markdown("**gras**"))
    #expect(content.body.isEmpty == false)
}

@Test func sendStateIsMappedFromUpstream() {
    #expect(TimelineMapper.sendState(from: nil) == .sent)
    #expect(TimelineMapper.sendState(from: .notSentYet) == .sending)
    #expect(TimelineMapper.sendState(from: .sent(eventId: "$abc")) == .sent)

    let failed = TimelineMapper.sendState(from: .sendingFailed(
        error: .unknown,
        isRecoverable: true
    ))
    #expect(failed.isFailed)
}
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run : `swift test --filter MessageContentTests`
Attendu : ÉCHEC, `cannot find 'TimelineMapper' in scope`.

Si la compilation signale que les valeurs associées de `EventSendState` diffèrent dans cette
version amont (`.sent(eventId:)`, `.sendingFailed(error:isRecoverable:)`), ajuster les motifs du
test d'après l'erreur du compilateur, sans changer les résultats attendus : `nil` et `.sent`
donnent `.sent`, `.notSentYet` donne `.sending`, `.sendingFailed` donne un état en échec.

- [ ] **Step 3 : Implémenter le mappeur**

`Sources/MatrixClientKitRust/Bridge/TimelineMapper.swift` :

```swift
import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Traduit les types de timeline amont vers le domaine.
enum TimelineMapper {

    static func eventContent(
        for content: MessageContent
    ) throws -> RoomMessageEventContentWithoutRelation {
        switch content {
        case let .text(body):
            do {
                return try messageEventContentNew(
                    msgtype: .text(content: TextMessageContent(body: body, formatted: nil))
                )
            } catch {
                throw ErrorMapper.map(error)
            }
        case let .markdown(body):
            return messageEventContentFromMarkdown(md: body)
        }
    }

    static func sendState(from state: EventSendState?) -> SendState {
        guard let state else { return .sent }
        switch state {
        case .notSentYet: return .sending
        case .sent: return .sent
        case .sendingFailed: return .failed(reason: String(describing: state))
        }
    }

    static func item(from item: MatrixRustSDK.TimelineItem) -> MatrixClientKitCore.TimelineItem {
        let id = item.uniqueId().id

        if let event = item.asEvent() {
            return MatrixClientKitCore.TimelineItem(id: id, kind: kind(from: event))
        }

        if let virtual = item.asVirtual() {
            switch virtual {
            case let .dateDivider(timestamp):
                return MatrixClientKitCore.TimelineItem(
                    id: id,
                    kind: .dateSeparator(date(from: timestamp))
                )
            case .readMarker:
                return MatrixClientKitCore.TimelineItem(id: id, kind: .readMarker)
            case .timelineStart:
                return MatrixClientKitCore.TimelineItem(
                    id: id,
                    kind: .unsupported(description: "début de timeline")
                )
            }
        }

        return MatrixClientKitCore.TimelineItem(
            id: id,
            kind: .unsupported(description: item.fmtDebug())
        )
    }

    private static func kind(
        from event: EventTimelineItem
    ) -> MatrixClientKitCore.TimelineItem.Kind {
        guard case let .msgLike(content) = event.content else {
            return .unsupported(description: event.eventTypeRaw ?? "événement non pris en charge")
        }

        switch content.kind {
        case let .message(message):
            guard let sender = UserID(rawValue: event.sender) else {
                return .unsupported(description: "expéditeur invalide : \(event.sender)")
            }

            return .message(
                MatrixClientKitCore.Message(
                    eventID: eventID(from: event.eventOrTransactionId),
                    sender: sender,
                    senderDisplayName: displayName(from: event.senderProfile),
                    body: message.body,
                    timestamp: date(from: event.timestamp),
                    isOwn: event.isOwn,
                    isEdited: message.isEdited,
                    sendState: sendState(from: event.localSendState)
                )
            )
        case .redacted:
            return .redacted
        case .unableToDecrypt:
            return .unableToDecrypt(reason: "message chiffré non déchiffrable")
        case .sticker, .poll, .other, .liveLocation:
            return .unsupported(description: String(describing: content.kind))
        }
    }

    private static func eventID(from identifier: EventOrTransactionId) -> EventID? {
        switch identifier {
        case let .eventId(eventId): return EventID(rawValue: eventId)
        case .transactionId: return nil
        }
    }

    private static func displayName(from profile: ProfileDetails) -> String? {
        guard case let .ready(displayName, _, _, _, _) = profile else { return nil }
        return displayName
    }

    private static func date(from timestamp: Timestamp) -> Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    }

    /// Traduit une mise à jour de timeline amont en diff de collection du domaine.
    static func diff(from update: TimelineDiff) -> CollectionDiff<MatrixClientKitCore.TimelineItem> {
        switch update {
        case let .append(values): .append(values.map(item(from:)))
        case .clear: .clear
        case let .pushFront(value): .pushFront(item(from: value))
        case let .pushBack(value): .pushBack(item(from: value))
        case .popFront: .popFront
        case .popBack: .popBack
        case let .insert(index, value): .insert(index: Int(index), item(from: value))
        case let .set(index, value): .set(index: Int(index), item(from: value))
        case let .remove(index): .remove(index: Int(index))
        case let .truncate(length): .truncate(length: Int(length))
        case let .reset(values): .reset(values.map(item(from:)))
        }
    }
}
```

- [ ] **Step 4 : Lancer les tests pour vérifier qu'ils passent**

Run : `swift test --filter MessageContentTests`
Attendu : 3 tests verts.

Si `item.uniqueId().id` ne compile pas, inspecter `TimelineUniqueId` — il s'agit d'une structure
enveloppant une chaîne — et utiliser le nom de champ réel.

- [ ] **Step 5 : Implémenter la timeline**

`Sources/MatrixClientKitRust/RustTimeline.swift` :

```swift
import MatrixRustSDK
import MatrixClientKitCore

/// Listener de timeline conforme au protocole amont, alimenté par une closure.
private final class ItemsListener: TimelineListener {
    private let handler: @Sendable ([TimelineDiff]) -> Void

    init(handler: @escaping @Sendable ([TimelineDiff]) -> Void) {
        self.handler = handler
    }

    func onUpdate(diff: [TimelineDiff]) {
        handler(diff)
    }
}

/// Implémentation de ``Timeline`` adossée au SDK Rust.
public final class RustTimeline: MatrixClientKitCore.Timeline {
    private let timeline: MatrixRustSDK.Timeline

    init(timeline: MatrixRustSDK.Timeline) {
        self.timeline = timeline
    }

    public var items: AsyncStream<[MatrixClientKitCore.TimelineItem]> {
        let timeline = timeline

        // Flux brut de diffs, en .unbounded : chaque diff se compose avec le précédent.
        let diffs = AsyncStream<[CollectionDiff<MatrixClientKitCore.TimelineItem>]>(
            bufferingPolicy: .unbounded
        ) { continuation in
            let task = Task {
                let listener = ItemsListener { updates in
                    continuation.yield(updates.map(TimelineMapper.diff(from:)))
                }
                let handle = await timeline.addListener(listener: listener)

                continuation.onTermination = { _ in
                    handle.cancel()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        return snapshotStream(from: diffs)
    }

    @discardableResult
    public func paginateBackwards(count: Int) async throws -> Bool {
        do {
            return try await timeline.paginateBackwards(numEvents: UInt16(count))
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    public func send(_ content: MessageContent) async throws {
        do {
            _ = try await timeline.send(msg: TimelineMapper.eventContent(for: content))
        } catch {
            throw ErrorMapper.map(error)
        }
    }
}
```

- [ ] **Step 6 : Compiler et lancer toute la suite**

Run : `swift test`
Attendu : toutes les suites unitaires vertes. C'est le premier point du plan où l'ensemble des
modules compile ensemble.

- [ ] **Step 7 : Commit**

```bash
git add Sources/MatrixClientKitRust/RustTimeline.swift Sources/MatrixClientKitRust/Bridge/TimelineMapper.swift Tests/MatrixClientKitRustTests/MessageContentTests.swift
git commit -m "feat: timeline en instantanés, pagination et envoi de texte"
```

---

### Task 14 : Mocks pour les applications consommatrices

**Files:**
- Modify: `Sources/MatrixClientKitMocks/SampleData.swift`
- Create: `Sources/MatrixClientKitMocks/MockMatrixSession.swift`
- Create: `Sources/MatrixClientKitMocks/MockRoomService.swift`
- Create: `Sources/MatrixClientKitMocks/MockTimeline.swift`
- Create: `Sources/MatrixClientKitMocks/MockSyncController.swift`
- Test: `Tests/MatrixClientKitCoreTests/MockTests.swift`
- Modify: `Package.swift` (ajouter `MatrixClientKitMocks` aux dépendances de
  `MatrixClientKitCoreTests`)

**Interfaces:**
- Consumes: tous les protocoles et modèles de la Task 7.
- Produces: `MockMatrixSession`, `MockRoomService`, `MockTimeline`, `MockSyncController`,
  `SampleData.roomSummaries(count:)`, `SampleData.message(_:from:)`.

**Note de conception :** `AsyncStream` étant mono-consommateur, chaque mock expose **un** flux,
documenté comme tel. C'est suffisant pour un test, et cela évite d'introduire un multicast dans
une cible dont le seul rôle est de rendre les tests simples.

- [ ] **Step 1 : Écrire les tests qui échouent**

`Tests/MatrixClientKitCoreTests/MockTests.swift` :

```swift
import Testing
import Foundation
import MatrixClientKitCore
import MatrixClientKitMocks

@Test func mockTimelineDeliversEmittedItems() async {
    let timeline = MockTimeline()
    let stream = timeline.items

    timeline.emit([SampleData.message("bonjour", from: "@alice:matrix.org")])

    for await items in stream {
        #expect(items.count == 1)
        #expect(items.first?.message?.body == "bonjour")
        break
    }
}

@Test func mockTimelineRecordsSentMessages() async throws {
    let timeline = MockTimeline()
    try await timeline.send(.text("salut"))
    #expect(timeline.sentMessages == [.text("salut")])
}

@Test func mockTimelineCanSimulateAFailure() async {
    let timeline = MockTimeline()
    timeline.sendError = .network(.offline)

    await #expect(throws: MatrixError.network(.offline)) {
        try await timeline.send(.text("salut"))
    }
}

@Test func mockRoomServiceDeliversSampleRooms() async {
    let service = MockRoomService(rooms: SampleData.roomSummaries(count: 3))

    for await rooms in service.list(filter: .joined) {
        #expect(rooms.count == 3)
        break
    }
}

@Test func mockSessionExposesItsServices() async {
    let session = MockMatrixSession()
    #expect(session.userID.rawValue == "@alice:matrix.org")

    await session.sync.start()
    #expect((session.sync as? MockSyncController)?.startCallCount == 1)
}
```

- [ ] **Step 2 : Lancer les tests pour vérifier qu'ils échouent**

Run : `swift test --filter MockTests`
Attendu : ÉCHEC, `no such module 'MatrixClientKitMocks'` dans la cible de test.

- [ ] **Step 3 : Ajouter la dépendance de test au manifeste**

Dans `Package.swift`, remplacer la cible de test Core par :

```swift
.testTarget(
    name: "MatrixClientKitCoreTests",
    dependencies: ["MatrixClientKitCore", "MatrixClientKitMocks"]
),
```

- [ ] **Step 4 : Implémenter les mocks**

`Sources/MatrixClientKitMocks/SampleData.swift` (remplace le contenu de la Task 1) :

```swift
import Foundation
import MatrixClientKitCore

/// Données d'exemple prêtes à l'emploi pour les tests et les aperçus.
public enum SampleData: Sendable {

    public static func roomSummary(
        id: String = "!room:matrix.org",
        name: String = "Salon",
        unread: Int = 0
    ) -> RoomSummary {
        RoomSummary(
            id: RoomID(rawValue: id) ?? RoomID(rawValue: "!fallback:matrix.org")!,
            displayName: name,
            topic: nil,
            avatarURL: nil,
            isDirect: false,
            isEncrypted: true,
            joinedMemberCount: 4,
            notificationCount: unread,
            highlightCount: 0,
            membership: .joined
        )
    }

    public static func roomSummaries(count: Int) -> [RoomSummary] {
        (0..<count).map { index in
            roomSummary(id: "!room\(index):matrix.org", name: "Salon \(index)")
        }
    }

    public static func message(
        _ body: String,
        from sender: String = "@alice:matrix.org",
        isOwn: Bool = false
    ) -> TimelineItem {
        TimelineItem(
            id: UUID().uuidString,
            kind: .message(
                Message(
                    eventID: EventID(rawValue: "$\(UUID().uuidString)"),
                    sender: UserID(rawValue: sender) ?? UserID(rawValue: "@inconnu:matrix.org")!,
                    senderDisplayName: nil,
                    body: body,
                    timestamp: Date(),
                    isOwn: isOwn,
                    isEdited: false,
                    sendState: .sent
                )
            )
        )
    }
}
```

`Sources/MatrixClientKitMocks/MockTimeline.swift` :

```swift
import Foundation
import MatrixClientKitCore

/// Timeline pilotable pour les tests.
///
/// - Note: ``items`` expose un flux unique, mono-consommateur.
public final class MockTimeline: Timeline, @unchecked Sendable {
    private let lock = NSLock()
    private let stream: AsyncStream<[TimelineItem]>
    private let continuation: AsyncStream<[TimelineItem]>.Continuation

    private var _sentMessages: [MessageContent] = []
    private var _sendError: MatrixError?
    private var _paginateResult = true

    public init() {
        (stream, continuation) = AsyncStream<[TimelineItem]>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    public var items: AsyncStream<[TimelineItem]> { stream }

    /// Messages passés à ``send(_:)``.
    public var sentMessages: [MessageContent] {
        lock.lock(); defer { lock.unlock() }
        return _sentMessages
    }

    /// Erreur à lever au prochain envoi.
    public var sendError: MatrixError? {
        get { lock.lock(); defer { lock.unlock() }; return _sendError }
        set { lock.lock(); _sendError = newValue; lock.unlock() }
    }

    /// Valeur renvoyée par ``paginateBackwards(count:)``.
    public var paginateResult: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _paginateResult }
        set { lock.lock(); _paginateResult = newValue; lock.unlock() }
    }

    /// Pousse un nouvel instantané dans ``items``.
    public func emit(_ items: [TimelineItem]) {
        continuation.yield(items)
    }

    /// Termine le flux ``items``.
    public func finish() {
        continuation.finish()
    }

    @discardableResult
    public func paginateBackwards(count: Int) async throws -> Bool {
        if let error = sendError { throw error }
        return paginateResult
    }

    public func send(_ content: MessageContent) async throws {
        if let error = sendError { throw error }
        lock.lock(); _sentMessages.append(content); lock.unlock()
    }
}
```

`Sources/MatrixClientKitMocks/MockRoomService.swift` :

```swift
import Foundation
import MatrixClientKitCore

/// Service de rooms pilotable pour les tests.
public final class MockRoomService: RoomService, @unchecked Sendable {
    private let lock = NSLock()
    private var rooms: [RoomSummary]

    /// Timeline renvoyée par toutes les rooms de ce mock.
    public let timeline = MockTimeline()

    public init(rooms: [RoomSummary] = SampleData.roomSummaries(count: 3)) {
        self.rooms = rooms
    }

    public func list(filter: RoomFilter) -> AsyncStream<[RoomSummary]> {
        lock.lock(); let current = rooms; lock.unlock()

        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuation.yield(current)
        }
    }

    public func room(_ id: RoomID) async throws -> any RoomHandle {
        MockRoomHandle(id: id, timeline: timeline)
    }
}

/// Poignée de room pilotable pour les tests.
public struct MockRoomHandle: RoomHandle {
    public let id: RoomID
    private let mockTimeline: MockTimeline

    public init(id: RoomID, timeline: MockTimeline) {
        self.id = id
        self.mockTimeline = timeline
    }

    public func timeline() async throws -> any Timeline {
        mockTimeline
    }
}
```

`Sources/MatrixClientKitMocks/MockSyncController.swift` :

```swift
import Foundation
import MatrixClientKitCore

/// Contrôleur de synchronisation pilotable pour les tests.
public final class MockSyncController: SyncController, @unchecked Sendable {
    private let lock = NSLock()
    private let stream: AsyncStream<SyncState>
    private let continuation: AsyncStream<SyncState>.Continuation

    private var _startCallCount = 0
    private var _stopCallCount = 0

    public init() {
        (stream, continuation) = AsyncStream<SyncState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    public var state: AsyncStream<SyncState> { stream }

    public var startCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _startCallCount
    }

    public var stopCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _stopCallCount
    }

    /// Pousse un nouvel état dans ``state``.
    public func emit(_ state: SyncState) {
        continuation.yield(state)
    }

    public func start() async {
        lock.lock(); _startCallCount += 1; lock.unlock()
        emit(.running)
    }

    public func stop() async {
        lock.lock(); _stopCallCount += 1; lock.unlock()
        emit(.idle)
    }
}
```

`Sources/MatrixClientKitMocks/MockMatrixSession.swift` :

```swift
import MatrixClientKitCore

/// Session authentifiée pilotable pour les tests.
public final class MockMatrixSession: MatrixSession, @unchecked Sendable {
    public let userID: UserID
    public let deviceID: DeviceID
    public let rooms: any RoomService
    public let sync: any SyncController

    public private(set) var didLogout = false

    public init(
        userID: String = "@alice:matrix.org",
        deviceID: String = "DEV1",
        rooms: MockRoomService = MockRoomService(),
        sync: MockSyncController = MockSyncController()
    ) {
        self.userID = UserID(rawValue: userID) ?? UserID(rawValue: "@alice:matrix.org")!
        self.deviceID = DeviceID(rawValue: deviceID) ?? DeviceID(rawValue: "DEV1")!
        self.rooms = rooms
        self.sync = sync
    }

    public func logout() async throws {
        didLogout = true
    }
}
```

- [ ] **Step 5 : Lancer les tests pour vérifier qu'ils passent**

Run : `swift test --filter MockTests`
Attendu : 5 tests verts.

- [ ] **Step 6 : Commit**

```bash
git add Package.swift Sources/MatrixClientKitMocks Tests/MatrixClientKitCoreTests/MockTests.swift
git commit -m "feat: mocks pilotables pour les applications consommatrices"
```

---

### Task 15 : Point d'entrée public

**Files:**
- Modify: `Sources/MatrixClientKit/MatrixClientKit.swift`
- Test: `Tests/MatrixClientKitTests/MatrixFactoryTests.swift`
- Modify: `Package.swift` (ajouter la cible de test `MatrixClientKitTests`)

**Interfaces:**
- Consumes: `RustMatrixClient` (Task 9), `MatrixStorage` (Task 8).
- Produces: `Matrix.client(homeserver:storage:) -> any MatrixClient`.

- [ ] **Step 1 : Écrire le test qui échoue**

`Tests/MatrixClientKitTests/MatrixFactoryTests.swift` :

```swift
import Testing
import Foundation
import MatrixClientKit

@Test func factoryBuildsAClientForTheGivenHomeserver() {
    let homeserver = URL(string: "https://matrix.org")!
    let client = Matrix.client(
        homeserver: homeserver,
        storage: .local(directory: URL(fileURLWithPath: NSTemporaryDirectory()))
    )

    #expect(client.homeserver == homeserver)
}

@Test func coreTypesAreReExportedByTheUmbrella() {
    // Compile uniquement si `@_exported import MatrixClientKitCore` est en place.
    #expect(UserID(rawValue: "@alice:matrix.org") != nil)
    #expect(PackageInfo.upstreamVersion == "26.09.07")
}
```

- [ ] **Step 2 : Ajouter la cible de test au manifeste**

Dans `Package.swift`, ajouter aux `targets` :

```swift
.testTarget(name: "MatrixClientKitTests", dependencies: ["MatrixClientKit"]),
```

- [ ] **Step 3 : Lancer le test pour vérifier qu'il échoue**

Run : `swift test --filter MatrixFactoryTests`
Attendu : ÉCHEC, `cannot find 'Matrix' in scope`.

- [ ] **Step 4 : Implémenter**

`Sources/MatrixClientKit/MatrixClientKit.swift` :

```swift
import Foundation
@_exported import MatrixClientKitCore
import MatrixClientKitRust

/// Point d'entrée de MatrixClientKit.
///
/// ```swift
/// let client = Matrix.client(
///     homeserver: URL(string: "https://matrix.org")!,
///     storage: .appGroup("group.com.exemple.app")
/// )
/// let session = try await client.login(.password(username: "alice", password: "…", deviceName: "iPhone"))
/// await session.sync.start()
///
/// for await rooms in session.rooms.list(filter: .joined) {
///     print(rooms.map(\.displayName))
/// }
/// ```
public enum Matrix: Sendable {

    /// Crée un client rattaché à un homeserver.
    ///
    /// - Parameters:
    ///   - homeserver: adresse du homeserver, par exemple `https://matrix.org`.
    ///   - storage: emplacement des données persistées. Utiliser
    ///     ``MatrixStorage/appGroup(_:keychainAccessGroup:accessibility:)`` dès lors qu'une
    ///     extension de notification doit accéder à la même session.
    public static func client(
        homeserver: URL,
        storage: MatrixStorage
    ) -> any MatrixClient {
        RustMatrixClient(homeserver: homeserver, storage: storage)
    }
}
```

- [ ] **Step 5 : Lancer les tests pour vérifier qu'ils passent**

Run : `swift test --filter MatrixFactoryTests`
Attendu : 2 tests verts.

- [ ] **Step 6 : Commit**

```bash
git add Package.swift Sources/MatrixClientKit Tests/MatrixClientKitTests
git commit -m "feat: point d'entrée public et réexport du domaine"
```

---

### Task 16 : Suite d'intégration désactivée par défaut

Elle ne s'exécute jamais en CI. Elle est le filet de sécurité à lancer manuellement avant chaque
montée de version amont.

**Files:**
- Create: `Tests/MatrixClientKitIntegrationTests/LoginAndSyncTests.swift`
- Create: `Tests/MatrixClientKitIntegrationTests/README.md`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `Matrix.client(homeserver:storage:)` (Task 15).
- Produces: rien pour le code de production.

- [ ] **Step 1 : Ajouter la cible de test**

Dans `Package.swift`, ajouter aux `targets` :

```swift
.testTarget(name: "MatrixClientKitIntegrationTests", dependencies: ["MatrixClientKit"]),
```

- [ ] **Step 2 : Écrire la suite**

`Tests/MatrixClientKitIntegrationTests/LoginAndSyncTests.swift` :

```swift
import Testing
import Foundation
import MatrixClientKit

/// Configuration lue dans l'environnement. Absente, la suite entière est ignorée.
private struct IntegrationConfiguration {
    let homeserver: URL
    let username: String
    let password: String

    static var current: IntegrationConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        guard
            let homeserver = environment["MATRIX_TEST_HOMESERVER"].flatMap(URL.init(string:)),
            let username = environment["MATRIX_TEST_USERNAME"],
            let password = environment["MATRIX_TEST_PASSWORD"]
        else { return nil }

        return IntegrationConfiguration(homeserver: homeserver, username: username, password: password)
    }

    static var isAvailable: Bool { current != nil }
}

private func makeClient(_ configuration: IntegrationConfiguration) -> any MatrixClient {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mck-integration-\(UUID().uuidString)", isDirectory: true)
    return Matrix.client(homeserver: configuration.homeserver, storage: .local(directory: directory))
}

@Suite(.enabled(if: IntegrationConfiguration.isAvailable))
struct LoginAndSyncTests {

    @Test func loginSyncAndListRooms() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let client = makeClient(configuration)

        let session = try await client.login(
            .password(
                username: configuration.username,
                password: configuration.password,
                deviceName: "MatrixClientKit Integration"
            )
        )

        await session.sync.start()

        var states: [SyncState] = []
        for await state in session.sync.state {
            states.append(state)
            if state == .running { break }
        }
        #expect(states.contains(.running))

        for await rooms in session.rooms.list(filter: .joined) {
            #expect(rooms.allSatisfy { $0.membership == .joined })
            break
        }

        await session.sync.stop()
        try await session.logout()
    }

    @Test func wrongPasswordSurfacesAsInvalidCredentials() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let client = makeClient(configuration)

        await #expect(throws: MatrixError.authentication(.invalidCredentials)) {
            _ = try await client.login(
                .password(
                    username: configuration.username,
                    password: "mot-de-passe-volontairement-faux",
                    deviceName: nil
                )
            )
        }
    }

    @Test func sendingAMessageProducesALocalEcho() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let environment = ProcessInfo.processInfo.environment
        let roomIdentifier = try #require(environment["MATRIX_TEST_ROOM_ID"])
        let roomID = try #require(RoomID(rawValue: roomIdentifier))

        let client = makeClient(configuration)
        let session = try await client.login(
            .password(
                username: configuration.username,
                password: configuration.password,
                deviceName: "MatrixClientKit Integration"
            )
        )
        await session.sync.start()

        let room = try await session.rooms.room(roomID)
        let timeline = try await room.timeline()
        let body = "test d'intégration \(UUID().uuidString)"

        let stream = timeline.items
        try await timeline.send(.text(body))

        var found = false
        for await items in stream {
            if items.contains(where: { $0.message?.body == body }) {
                found = true
                break
            }
        }
        #expect(found)

        await session.sync.stop()
        try await session.logout()
    }
}
```

`Tests/MatrixClientKitIntegrationTests/README.md` :

```markdown
# Tests d'intégration

Ces tests ne s'exécutent pas en intégration continue. Ils valident la chaîne complète contre un
homeserver réel et doivent être lancés **manuellement avant chaque montée de version du SDK Rust**.

## Lancement

    MATRIX_TEST_HOMESERVER=https://votre-homeserver \
    MATRIX_TEST_USERNAME=utilisateur \
    MATRIX_TEST_PASSWORD=secret \
    MATRIX_TEST_ROOM_ID='!room:votre-homeserver' \
    swift test --filter MatrixClientKitIntegrationTests

Sans ces variables, la suite est ignorée : c'est le comportement attendu en CI.

Utilisez un compte dédié aux tests. Ces tests envoient de vrais messages et ferment la session
à la fin de chaque cas.
```

- [ ] **Step 3 : Vérifier que la suite est bien ignorée sans configuration**

Run : `swift test --filter MatrixClientKitIntegrationTests`
Attendu : la suite est rapportée comme ignorée, aucun échec, aucune connexion réseau.

- [ ] **Step 4 : Vérifier que la CI ne les exécute pas**

Relire `.github/workflows/ci.yml` : l'étape de test doit porter
`--skip MatrixClientKitIntegrationTests`. Le double filet — variables absentes *et* exclusion
explicite — est volontaire.

- [ ] **Step 5 : Commit**

```bash
git add Package.swift Tests/MatrixClientKitIntegrationTests
git commit -m "test: suite d'intégration manuelle désactivée par défaut"
```

---

### Task 17 : Documentation, dépôt public et publication de la v0.1.0

**Files:**
- Create: `Sources/MatrixClientKit/Documentation.docc/MatrixClientKit.md`
- Create: `Sources/MatrixClientKit/Documentation.docc/GettingStarted.md`
- Create: `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`,
  `CODE_OF_CONDUCT.md`, `.spi.yml`

**Interfaces:**
- Consumes: l'API publique complète des Tasks 1 à 15.
- Produces: le dépôt publiable.

- [ ] **Step 1 : Écrire la documentation DocC**

`Sources/MatrixClientKit/Documentation.docc/MatrixClientKit.md` :

```markdown
# ``MatrixClientKit``

Construire un client Matrix en Swift, sans manipuler l'API FFI du SDK Rust.

## Overview

MatrixClientKit enveloppe le Matrix Rust SDK officiel derrière une API Swift moderne :
`async`/`await`, `AsyncStream`, types `Sendable` et erreurs typées. Les listes de rooms et les
timelines sont exposées sous forme d'**instantanés** — vous recevez l'état complet et à jour,
sans jamais appliquer un diff vous-même.

## Topics

### Prise en main

- <doc:GettingStarted>

### Point d'entrée

- ``Matrix``
- ``MatrixClient``
- ``MatrixSession``

### Rooms et messages

- ``RoomService``
- ``RoomSummary``
- ``Timeline``
- ``TimelineItem``
- ``MessageContent``

### Stockage

- ``MatrixStorage``
- ``SecureStore``

### Erreurs

- ``MatrixError``
```

`Sources/MatrixClientKit/Documentation.docc/GettingStarted.md` :

```markdown
# Prise en main

Se connecter, synchroniser, afficher des rooms et envoyer un message.

## Créer un client

```swift
import MatrixClientKit

let client = Matrix.client(
    homeserver: URL(string: "https://matrix.org")!,
    storage: .appGroup("group.com.exemple.app")
)
```

Utilisez ``MatrixStorage/appGroup(_:keychainAccessGroup:accessibility:)`` dès qu'une extension
doit accéder à la même session. Sinon, ``MatrixStorage/local(directory:accessibility:)`` suffit.

## Ouvrir une session

```swift
let session: any MatrixSession

if let restored = try await client.restoreSession() {
    session = restored
} else {
    session = try await client.login(
        .password(username: "alice", password: "…", deviceName: "iPhone")
    )
}
```

## Synchroniser et observer les rooms

```swift
await session.sync.start()

for await rooms in session.rooms.list(filter: .joined) {
    // `rooms` est la liste complète et à jour : affectez-la directement.
    self.rooms = rooms
}
```

## Lire et envoyer des messages

```swift
let room = try await session.rooms.room(roomID)
let timeline = try await room.timeline()

Task {
    for await items in timeline.items {
        self.messages = items
    }
}

try await timeline.paginateBackwards(count: 20)
try await timeline.send(.text("bonjour"))
```

L'écho local du message envoyé apparaît dans `timeline.items` sans action supplémentaire.

## Gérer les erreurs

```swift
do {
    try await timeline.send(.text("bonjour"))
} catch let error as MatrixError {
    if error.isRetryable {
        // ré-essayer, éventuellement après error.retryAfter
    }
}
```
```

- [ ] **Step 2 : Écrire le README**

`README.md` :

```markdown
# MatrixClientKit

Un package Swift pour construire des clients [Matrix](https://matrix.org) sur iOS et macOS,
adossé au [Matrix Rust SDK](https://github.com/matrix-org/matrix-rust-sdk) officiel.

```swift
let client = Matrix.client(
    homeserver: URL(string: "https://matrix.org")!,
    storage: .appGroup("group.com.exemple.app")
)
let session = try await client.login(.password(username: "alice", password: "…", deviceName: "iPhone"))
await session.sync.start()

for await rooms in session.rooms.list(filter: .joined) {
    self.rooms = rooms          // liste complète et à jour, aucun diff à appliquer
}
```

## Ce que le package apporte

- **Flux asynchrones.** Les abonnements à listeners du SDK Rust deviennent des `AsyncStream`
  dont le cycle de vie est géré automatiquement : sortir d'une boucle annule l'abonnement.
- **Instantanés, pas de diffs.** Listes de rooms et timelines arrivent sous forme d'état complet.
- **Erreurs typées.** `MatrixError` avec `isRetryable` et `retryAfter`.
- **Stockage prêt pour les extensions.** App Group, Keychain et protection de fichiers
  configurés pour qu'une extension de notification fonctionne appareil verrouillé.
- **Testable.** Toute l'API publique repose sur des protocoles, et le produit
  `MatrixClientKitMocks` fournit des doubles pilotables qui ne lient aucun binaire.

## Installation

```swift
.package(url: "https://github.com/kesprit/MatrixClientKit", from: "0.1.0")
```

## Compatibilité

| MatrixClientKit | Matrix Rust SDK embarqué | iOS | macOS | Swift |
| --- | --- | --- | --- | --- |
| 0.1.x | 26.09.07 | 18+ | 15+ | 6.2+ |

## Périmètre

La v0.1 couvre l'authentification par mot de passe, la session persistée, la synchronisation, la
liste de rooms, la timeline et l'envoi de messages texte. Le chiffrement de bout en bout est
actif — il est assuré par le SDK Rust — mais la vérification d'appareils, la récupération de clés
et les notifications push ne sont pas encore exposées. Voir la feuille de route ci-dessous.

| Version | Contenu |
| --- | --- |
| 0.1 | Socle : auth, session, sync, rooms, timeline, envoi texte |
| 0.2 | Vérification d'appareils, récupération et sauvegarde de clés |
| 0.3 | Notifications push et extension de service |
| 0.4 | Médias, accusés de lecture, frappe, présence, compte, OAuth |
| 1.0 | Gel de l'API |

## Note sur l'API

`MatrixClientKit` n'expose jamais un type du SDK Rust dans une signature publique. En revanche,
SPM ne permet pas de masquer un module transitif : `MatrixRustSDK` reste techniquement importable
depuis votre application. Vous n'avez pas à l'utiliser, et l'API de ce package ne vous y oblige
jamais.

## Licence

Apache-2.0. Ce projet embarque le Matrix Rust SDK, également sous Apache-2.0.
```

- [ ] **Step 3 : Écrire les fichiers de gouvernance**

`CHANGELOG.md` :

```markdown
# Changelog

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le versionnage suit
[SemVer](https://semver.org/lang/fr/).

## [0.1.0] - 2026-09-13

### Ajouté

- Authentification par mot de passe et restauration de session persistée.
- Stockage App Group et Keychain, configuré pour les extensions.
- Contrôle de la synchronisation et flux d'état.
- Liste de rooms observable, livrée en instantanés.
- Timeline observable, pagination arrière et envoi de messages texte.
- `MatrixError`, erreurs typées avec `isRetryable` et `retryAfter`.
- Produit `MatrixClientKitMocks` pour les tests des applications.
- Matrix Rust SDK embarqué : 26.09.07.
```

`SECURITY.md` :

```markdown
# Politique de sécurité

## Signaler une faille

**Toute vulnérabilité affectant le protocole Matrix, le chiffrement de bout en bout ou le
Matrix Rust SDK doit être signalée à l'équipe matrix.org**, selon leur procédure de divulgation
responsable : https://matrix.org/security-disclosure-policy/

Pour une faille propre à MatrixClientKit — la couche Swift de ce dépôt, par exemple le stockage
des jetons ou la configuration du Keychain — ouvrez un avis de sécurité privé via l'onglet
Security de ce dépôt. N'ouvrez pas d'issue publique.

## Portée

Ce package n'implémente aucune primitive cryptographique. Le chiffrement est intégralement assuré
par le Matrix Rust SDK.
```

`CONTRIBUTING.md` :

```markdown
# Contribuer

## Avant d'ouvrir une pull request

    swift build
    swift test

Les tests d'intégration ne s'exécutent pas par défaut : voir
`Tests/MatrixClientKitIntegrationTests/README.md`.

## Règles d'architecture

- `MatrixClientKitCore` ne doit **jamais** importer `MatrixRustSDK`. C'est ce qui garantit
  qu'aucun type amont ne fuite dans l'API publique.
- Aucun type du SDK Rust ne doit apparaître dans une signature `public`.
- Pas de `@MainActor` dans `Core` ni dans `Rust`.
- Les flux de diffs utilisent `.unbounded`, les flux d'instantanés `.bufferingNewest(1)`.

## Ajout d'un cas à `MatrixError`

Les cas de premier niveau sont figés pour la durée d'une version majeure. Une erreur
nouvellement distinguable doit être rapportée dans `.unexpected` jusqu'à la prochaine majeure :
ajouter un cas casserait la compilation des applications.

## Montée de version du SDK Rust

1. Mettre à jour la version épinglée dans `Package.swift`.
2. Lancer la suite d'intégration contre un homeserver réel.
3. Mettre à jour le tableau de compatibilité du README et le CHANGELOG.
```

`CODE_OF_CONDUCT.md` : reprendre le texte du Contributor Covenant 2.1 et y indiquer
`kevinesprit@gmail.com` comme adresse de contact.

`.spi.yml` :

```yaml
version: 1
builder:
  configs:
    - documentation_targets: [MatrixClientKit]
```

- [ ] **Step 4 : Vérifier la construction de la documentation**

Run : `swift package --allow-writing-to-directory ./docs-build generate-documentation --target MatrixClientKit --output-path ./docs-build`
Attendu : génération sans erreur, aucun lien symbolique cassé signalé.

- [ ] **Step 5 : Lancer la vérification complète**

Run : `swift build && swift test --skip MatrixClientKitIntegrationTests`
Attendu : tout vert. Ne pas passer à l'étape suivante autrement.

- [ ] **Step 6 : Commit**

```bash
git add README.md CHANGELOG.md CONTRIBUTING.md SECURITY.md CODE_OF_CONDUCT.md .spi.yml Sources/MatrixClientKit/Documentation.docc
git commit -m "docs: documentation DocC, README et fichiers de gouvernance"
```

- [ ] **Step 7 : Créer le dépôt public et publier**

> **Action externe irréversible — demander confirmation explicite avant exécution.** Cette étape
> rend le code public sous le compte GitHub de l'utilisateur.

```bash
gh repo create kesprit/MatrixClientKit --public --source=. --remote=origin --push
git tag 0.1.0
git push origin 0.1.0
gh release create 0.1.0 --title "0.1.0" --notes-file CHANGELOG.md
```

Ensuite, dans les réglages du dépôt : activer GitHub Pages sur GitHub Actions pour la
documentation, et soumettre le package au Swift Package Index.

---

## Couverture de la spec par les tâches

| Section de la spec | Tâches |
| --- | --- |
| 4. Architecture des modules | 1, 15 |
| 5. Modèle de concurrence (pont, tampons, abonnements) | 6, 11 |
| 6.1 Deux états, deux types | 7, 9 |
| 6.2 Authentification (mot de passe ; OAuth en v0.4) | 7, 9 |
| 6.3 Identifiants typés | 3 |
| 6.4 Instantanés plutôt que diffs | 2, 11, 12, 13 |
| 6.5 Envoi | 13 |
| 7. Erreurs et règle d'évolution | 4, 5 |
| 8. Stockage, session, pièges Keychain et protection de fichiers | 8 |
| 9. Mocks et placement de la logique risquée | 2, 11, 14 |
| 10. Documentation DocC | 17 |
| 11. CI, publication, versioning, hygiène de dépôt | 1, 17 |
| 12. Palier v0.1 | 1 à 17 |

**Hors périmètre v0.1, planifié :** extension de notification et `MatrixNotificationService`
(v0.3), vérification d'appareils et récupération (v0.2), médias et handle d'envoi (v0.4),
`ClientSessionDelegate` pour le rafraîchissement de jeton multi-processus (v0.3, en même temps que
l'extension qui le rend nécessaire).
