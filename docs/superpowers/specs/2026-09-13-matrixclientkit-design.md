# MatrixClientKit — Design

**Date :** 2026-09-13
**Statut :** validé, prêt pour la rédaction du plan d'implémentation
**Auteur :** Kevin Esprit

---

## 1. Objectif

Fournir à la communauté iOS un package Swift public, ergonomique et documenté, permettant de
construire un client Matrix complet et chiffré sans jamais manipuler l'API FFI générée du
`matrix-rust-sdk`.

Le package n'implémente pas le protocole Matrix : il enveloppe le SDK Rust officiel, qui reste la
seule implémentation exécutée. Sa valeur tient en quatre points :

1. **Flux asynchrones** — convertir 43 listeners à base de `TaskHandle` en `AsyncStream` dont le
   cycle de vie est géré automatiquement.
2. **Instantanés plutôt que diffs** — absorber, une fois pour toutes, la machinerie d'application
   de diffs que chaque client Matrix iOS réimplémente aujourd'hui.
3. **Erreurs exploitables** — transformer ~20 enums d'erreur amont, dominés par un `ClientError`
   fourre-tout, en un type unique et typé.
4. **Plomberie de stockage et de notification** — App Group, Keychain, protection de fichiers et
   extension de notification correctement configurés par défaut.

## 2. Mesure de la surface enveloppée

Relevé effectué sur `matrix-org/matrix-rust-components-swift`, release `26.09.07`, fichier
`Sources/MatrixRustSDK/matrix_sdk_ffi.swift` :

| Élément | Nombre |
| --- | --- |
| Lignes Swift générées | 58 102 |
| Protocoles | 109 (dont 43 listeners) |
| Classes | 57 |
| Structs | 426 |
| Enums | 134 (dont ~20 types d'erreur) |

Conséquence directe : une façade stricte ne peut pas couvrir littéralement 426 structs. Elle couvre
la surface **atteignable depuis le périmètre fonctionnel retenu**, estimée entre 80 et 120 types
publics. Cette réalité impose la livraison par paliers décrite en section 12.

## 3. Décisions actées

| Sujet | Décision |
| --- | --- |
| Nom | `MatrixClientKit` |
| Licence | Apache-2.0 (alignée sur l'amont, clause de brevet) |
| Périmètre v1 | Client complet chiffré |
| Stratégie d'API | Façade stricte |
| Plateformes | iOS 18, macOS 15 |
| Binaire Rust | Dépendance SPM sur `matrix-rust-components-swift`, version épinglée exacte |
| Persistance | Gérée par le package (App Group + Keychain) |
| Concurrence / UI | Cœur UI-agnostique (actors, `AsyncSequence`), aucune dépendance SwiftUI |
| Testabilité | Protocoles publics + produit `MatrixClientKitMocks` |
| Tests | Unitaires en CI ; suite d'intégration désactivée par défaut |
| Exemple | DocC et extraits, pas d'app de démo |
| Versioning | SemVer indépendant, pin exact de l'amont |
| Dépôt | Public dès le départ |
| CI | GitHub Actions, **runners standard exclusivement** (gratuits et non plafonnés sur dépôt public) |

### Précision sur « façade stricte »

SPM ne sait pas masquer un module transitif, et `@_implementationOnly` n'est pas applicable ici.
`MatrixRustSDK` restera donc importable par les applications consommatrices. « Strict » signifie
dans ce document : **aucun type amont n'apparaît dans une signature publique de MatrixClientKit**.
Le README doit énoncer cette nuance plutôt que promettre une invisibilité impossible.

## 4. Architecture des modules

Quatre cibles, trois produits.

```
MatrixClientKitCore    → aucune dépendance        // protocoles publics + modèles + logique pure
MatrixClientKitRust    → Core, MatrixRustSDK      // implémentations + mappage FFI
MatrixClientKitMocks   → Core                     // doubles pilotables, zéro binaire
MatrixClientKit        → Core, Rust               // @_exported import Core + fabriques
```

Produits exposés : `MatrixClientKit` (usage courant), `MatrixClientKitCore` (couche domaine seule),
`MatrixClientKitMocks` (tests des applications).

Toutes les cibles compilent en `swiftLanguageMode(.v6)`, strict concurrency complet.

**Propriété structurante :** `MatrixClientKitCore` n'importe pas `MatrixRustSDK`. Toute fuite d'un
type amont dans l'API publique devient une erreur de compilation et non un oubli de revue. C'est ce
qui rend la façade stricte tenable sur plus de cent types.

**Effet de bord recherché :** `Core` + `Mocks` ne lient aucun XCFramework. Les tests unitaires des
applications consommatrices s'exécutent sans embarquer le binaire Rust.

### Manifeste cible

```swift
// swift-tools-version: 6.2
platforms: [.iOS(.v18), .macOS(.v15)]
dependencies: [
    .package(url: "https://github.com/matrix-org/matrix-rust-components-swift", exact: "26.09.07")
]
```

## 5. Modèle de concurrence

### Constat amont

Les méthodes asynchrones existent déjà : UniFFI génère `func login(...) async throws`,
`func paginateBackwards(numEvents: UInt16) async throws -> Bool`. Aucune continuation à écrire.

Le travail porte sur les 43 listeners, dont le motif est systématiquement :

```swift
func subscribeToRoomInfoUpdates(listener: RoomInfoListener) -> TaskHandle
```

L'appelant doit retenir le `TaskHandle`, l'annuler au bon moment, et fournir une classe conforme à
un protocole dédié. Oubli d'annulation = fuite ou callback sur objet libéré.

### Pont générique

Un seul helper interne à `MatrixClientKitRust` couvre les 43 cas :

```swift
func ffiStream<Element: Sendable, Listener>(
    makeListener: @Sendable @escaping (@Sendable @escaping (Element) -> Void) -> Listener,
    subscribe: @Sendable (Listener) throws -> TaskHandle,
    buffering: AsyncStream<Element>.Continuation.BufferingPolicy
) -> AsyncStream<Element>
```

La continuation capture le `TaskHandle` et l'annule dans `onTermination`. Annulation de tâche,
sortie de boucle, erreur ou libération : les quatre chemins libèrent l'abonnement.

### Politique de tampon, différenciée

- **Flux de diffs** (liste de rooms, items de timeline) : `.unbounded`. Chaque diff se compose avec
  le précédent ; en perdre un corrompt l'état.
- **Flux d'instantanés** (état de sync, état de backup, `RoomInfo`) : `.bufferingNewest(1)`. Seule
  la dernière valeur compte, et un consommateur lent ne doit pas faire enfler la mémoire.

### Sémantique d'abonnement

`AsyncStream` est mono-consommateur. Chaque appel à un flux public ouvre **son propre abonnement
FFI**, avec son propre `TaskHandle`. Deux vues observant la même room sont indépendantes. Aucun
multicast n'est introduit : c'est la sémantique la plus simple qui soit correcte.

### Isolation

Aucun type de `Core` n'est `@MainActor`. Les modèles sont des `struct Sendable`, les services des
protocoles `Sendable`. L'isolation est décidée par l'application, ce qui garde le package utilisable
en extension de notification, en ligne de commande et côté serveur.

## 6. API publique

### 6.1 Deux états, deux types

L'amont expose un `Client` unique, tantôt anonyme tantôt authentifié, dont certaines méthodes
échouent à l'exécution selon l'état. La façade sépare les deux :

```swift
public protocol MatrixClient: Sendable {          // non authentifié
    var homeserver: Homeserver { get }
    func loginDetails() async throws -> HomeserverLoginDetails
    func login(_ credentials: Credentials) async throws -> any MatrixSession
    func beginOAuthLogin() async throws -> OAuthLoginFlow
}

public protocol MatrixSession: Sendable {          // authentifié
    var userID: UserID { get }
    var rooms: any RoomService { get }
    var sync: any SyncController { get }
    var encryption: any EncryptionService { get }
    var notifications: any NotificationService { get }
    var account: any AccountService { get }
    func logout() async throws
}
```

L'état illégal n'est pas représentable : accéder aux rooms sans session ne compile pas. Le découpage
en services par domaine évite le god object et rend les mocks utilisables.

### 6.2 Authentification

- Mot de passe, e-mail, et OAuth / OIDC.
- `beginOAuthLogin()` rend un flow exposant l'URL d'autorisation ; l'application présente son
  `ASWebAuthenticationSession` puis rappelle `flow.complete(callbackURL:)`. Aucune dépendance UI
  dans `Core`.
- Restauration de session depuis le stockage sans interaction.

### 6.3 Identifiants typés

`UserID`, `RoomID`, `EventID`, `DeviceID` : structs `Sendable` validées à la construction. L'amont
manipule des `String` interchangeables — `getRoom(roomId: String)` accepte un identifiant
d'événement sans broncher.

### 6.4 Instantanés plutôt que diffs

L'amont livre `func onUpdate(diff: [TimelineDiff])` et un `RoomList` à adaptateurs dynamiques
(`entriesWithDynamicAdapters(pageSize:listener:)`). La façade publie des états complets :

```swift
for await items in timeline.items {                        // AsyncStream<[TimelineItem]>
    self.messages = items
}

for await rooms in session.rooms.list(filter: .joined) {   // AsyncStream<[RoomSummary]>
    self.rooms = rooms
}
```

En interne : un actor consomme le flux de diffs en `.unbounded`, maintient la collection et publie
des instantanés en `.bufferingNewest(1)`. Les flux de diffs bruts restent exposés séparément pour
les usages qui nécessitent des animations fines de `UICollectionView`.

### 6.5 Envoi

```swift
try await timeline.send(.text("bonjour"))
let handle = try await timeline.send(.image(data, info: info))
try await handle.cancel()
```

L'écho local remonte automatiquement dans `timeline.items`. La file d'envoi, les reprises et
l'abandon sont exposés via le handle.

### 6.6 Domaines couverts en v1

Rooms et liste de rooms filtrable, timelines paginées, envoi texte et média, chiffrement de bout en
bout, vérification d'appareils (SAS emoji ; QR non exposé par l'amont épinglé, voir la spec 0.2),
récupération et sauvegarde de clés, notifications
push et extension de service, paramètres de notification, accusés de lecture, indicateurs de
frappe, présence, profil et compte.

## 7. Erreurs

### Constat amont

Une vingtaine d'enums, dominés par `ClientError`, dont les cas réels sont `.Generic(msg:details:)`,
`.MatrixApi(kind:code:msg:details:)` et `.ContentScanner(...)`. Le `kind` porte en revanche
**39 cas exploitables** (`forbidden`, `limitExceeded`, `unknownToken`, `resourceLimitExceeded`,
`threepidInUse`, `unsupportedRoomVersion`, …). La matière existe ; elle est enfouie.

### Type public

```swift
public enum MatrixError: Error, Sendable, LocalizedError {
    case authentication(Authentication)   // .invalidCredentials, .unknownToken(soft: Bool), .userDeactivated
    case network(Network)                 // .offline, .timeout, .tlsFailure
    case rateLimited(retryAfter: Duration?)
    case permission(Permission)           // .forbidden, .insufficientPowerLevel(required:current:)
    case notFound(Resource)               // .room, .event, .user, .media
    case encryption(Encryption)           // .unableToDecrypt(reason:), .verificationRequired, .invalidRecoveryKey
    case server(Server)                   // .resourceLimitExceeded, .unsupportedRoomVersion, .maintenance
    case storage(Storage)
    case unexpected(message: String, details: String?)
}
```

Accompagné de `var isRetryable: Bool` et `var retryAfter: Duration?`, qui répondent à la seule
question que se pose réellement l'appelant.

### Règle d'évolution

Dans un package SPM, les enums publics sont exhaustifs côté consommateur : **ajouter un cas casse la
compilation des utilisateurs**, ce qui imposerait un bump majeur à chaque release amont.

Règle retenue, à documenter explicitement dans le README : **les cas de premier niveau sont figés ;
toute erreur nouvellement distinguable atterrit dans `.unexpected` jusqu'à la prochaine version
majeure.** L'ergonomie du pattern matching est conservée sans sacrifier la promesse de stabilité.

Alternative écartée : un `struct MatrixError` à `Code` extensible (façon swift-nio), évolutif sans
casse mais privant du `switch` exhaustif attendu par le public cible.

## 8. Stockage, session et extension de notification

### Contraintes amont

La `Session` contient `accessToken`, `refreshToken?`, `userId`, `deviceId`, `homeserverUrl`,
`oauthData?`, `slidingSyncVersion`. Le store est un SQLite chiffrable — `sqliteStore(config:)`
accepte `key(Data?)` ou `passphrase(String?)`. Le rafraîchissement de token passe par
`ClientSessionDelegate`, à deux méthodes : `retrieveSessionFromKeychain(userId:)` et
`saveSessionInKeychain(session:)`.

### Configuration exposée

```swift
let storage = MatrixStorage.appGroup("group.com.exemple.app")   // partagé app + NSE
// ou
let storage = MatrixStorage.local(directory: url)               // sans extension
```

Le package prend en charge : chemins `dataPath` / `cachePath` dans le conteneur partagé, génération
et conservation en Keychain de la clé de chiffrement SQLite, implémentation du
`ClientSessionDelegate` sur un Keychain access group, purge complète au logout.

### Trois pièges neutralisés par défaut

1. **Accessibilité Keychain.** L'extension s'exécute appareil verrouillé. Avec le défaut
   `whenUnlocked`, le token est illisible et la notification arrive vide. Défaut du package :
   `afterFirstUnlock`, durcissable en connaissance de cause.
2. **Protection des fichiers SQLite.** Sans `completeUntilFirstUserAuthentication`, l'extension
   plante à l'ouverture du store sur appareil verrouillé.
3. **Course au rafraîchissement de token.** Deux processus partagent la session ; un rafraîchissement
   côté extension pendant que l'application détient l'ancien token provoque une déconnexion
   inexpliquée. Les écritures sont sérialisées via le Keychain partagé, et la session est relue à
   chaque restauration.

### API de l'extension

```swift
let resolver = try await MatrixNotificationResolver(storage: .appGroup("group.com.exemple.app"))
let notification = try await resolver.notification(roomID: roomID, eventID: eventID)
```

Voir la spec 0.3 pour le verrou inter-processus.

S'appuie sur `NotificationClient.getNotification(roomId:eventId:)`. Règle documentée et vérifiée à
l'exécution : **aucune sync dans l'extension**, uniquement ce service — lancer une sync depuis le
NSE corrompt l'état côté application.

## 9. Mocks et stratégie de test

### Produit `MatrixClientKitMocks`

Des doubles pilotables, non de simples stubs :

```swift
let session = MockMatrixSession(rooms: .sample(count: 20))
session.mockTimeline.emit([.text("bonjour", from: .alice)])
```

`Core` ne dépendant d'aucun binaire, ces mocks s'exécutent dans les tests unitaires d'une
application sans lier le XCFramework.

### Placement de la logique risquée

L'application des diffs pour produire des instantanés est la partie la plus susceptible de bugs.
Elle est placée **dans `Core`**, opérant sur un type de diff propre au package
(`CollectionDiff<Element>`) ; le module `Rust` se contente de traduire `TimelineDiff` amont vers ce
type. La logique critique devient une fonction pure, testable exhaustivement, sans FFI.

### Cibles de test

| Cible | Contenu | Binaire lié |
| --- | --- | --- |
| `MatrixClientKitCoreTests` | Application de diffs, validation d'identifiants, filtres, modèles | Non |
| `MatrixClientKitRustTests` | Mappage des 39 `ErrorKind`, mappage des structs amont | Oui (lié, non exécuté) |
| `MatrixClientKitIntegrationTests` | Login, sync, envoi, E2EE sur homeserver réel | Oui |

La suite d'intégration est **désactivée par défaut**, activée par variables d'environnement
(`MATRIX_TEST_HOMESERVER` et identifiants), et lancée manuellement avant chaque bump de version
amont. Elle ne s'exécute pas en CI.

Framework : Swift Testing.

## 10. Documentation

Catalogue DocC porté par la cible umbrella, publié sur GitHub Pages :

- Prise en main
- Authentification (mot de passe, OAuth, restauration de session)
- Sync et liste de rooms
- Timelines et envoi de messages
- Chiffrement, vérification d'appareils et récupération
- Notifications push et extension de service
- Tester une application avec `MatrixClientKitMocks`

Tous les extraits doivent être compilables.

## 11. CI, publication et versioning

### CI

GitHub Actions sur **runners standard exclusivement**. Sur un dépôt public, les runners standard —
macOS inclus — sont gratuits et non plafonnés ; les *larger runners* sont facturés quelle que soit
la visibilité et sont donc proscrits.

Workflow volontairement sobre : build iOS et macOS, tests unitaires, lint `swift-format`, build
DocC. Le dossier SPM est mis en cache, le XCFramework étant volumineux.

### Publication

- SemVer reflétant la stabilité de l'API du package, indépendant de la numérotation amont.
- Dépendance amont épinglée en version exacte.
- `Tools/bump-upstream.swift` : met à jour la version épinglée, exécute les tests, ouvre une PR.
- `CHANGELOG.md` au format Keep a Changelog.
- **Tableau de compatibilité** dans le README : version MatrixClientKit ↔ version amont embarquée ↔
  iOS minimum. C'est la première information que cherche un évaluateur de wrapper.

### Hygiène de dépôt public

`LICENSE` (Apache-2.0), `NOTICE` créditant `matrix-rust-sdk`, `CONTRIBUTING.md`,
`CODE_OF_CONDUCT.md`, templates d'issues, `.spi.yml` pour le Swift Package Index, et `SECURITY.md`
renvoyant explicitement vers la divulgation responsable de matrix-org pour toute faille du SDK
sous-jacent — point non décoratif sur une brique cryptographique.

## 12. Paliers de livraison

La spec décrit l'architecture et l'API cibles complètes. Le plan d'implémentation les découpe :

| Palier | Contenu | Publiable |
| --- | --- | --- |
| v0.1 | Socle : modules, manifeste, pont `ffiStream`, erreurs, auth mot de passe, session persistée, sync, liste de rooms, timeline, envoi texte | Oui |
| v0.2 | E2EE : vérification d'appareils (SAS — QR retiré, non exposé par l'amont), récupération, sauvegarde de clés, états de chiffrement | Oui |
| v0.3 | Push : `MatrixNotificationResolver`, App Group, extension, verrou inter-processus, mode de notification par salon (paramètres globaux reportés) | Oui |
| v0.4 | Complément : médias, accusés de lecture, frappe, présence, profil et compte, OAuth | Oui |
| v1.0 | Gel de l'API, DocC complète, tableau de compatibilité, annonce | Oui |

Chaque palier est utilisable en production sur son périmètre.

## 13. Risques et parades

| Risque | Parade |
| --- | --- |
| Rupture d'API amont à chaque release | Pin exact, suite d'intégration lancée avant chaque bump, façade absorbant le changement |
| Volume de mappage (80 à 120 types) | Livraison par paliers ; élargissement piloté par les besoins réels |
| Absence de tests d'intégration en CI | Suite manuelle obligatoire avant tout bump amont, documentée dans le processus de release |
| Enum d'erreur non extensible | Règle `.unexpected` figée jusqu'à la majeure suivante, documentée |
| Attentes de la communauté sur un dépôt public précoce | README annonçant sans ambiguïté le palier atteint et le périmètre couvert |
| Poids du XCFramework en CI | Cache SPM ; aucun larger runner |

## 14. Références

- `matrix-org/matrix-rust-sdk` — SDK amont, Apache-2.0
- `matrix-org/matrix-rust-components-swift` — distribution SPM, release `26.09.07`, plateformes
  amont iOS 16 / macOS 12
- Relevés de surface effectués le 2026-09-13 sur cette release
