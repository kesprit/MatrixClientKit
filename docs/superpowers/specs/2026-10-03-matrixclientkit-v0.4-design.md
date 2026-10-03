# MatrixClientKit 0.4 — Design

**Date :** 2026-10-03
**Statut :** validé en conversation, en relecture avant rédaction du plan d'implémentation
**Auteur :** Kevin Esprit
**Entrées :** spec de référence `2026-09-13-matrixclientkit-design.md` (§6.1, §6.2, §12) ; spec 0.2
(reconnexion après soft logout reportée en 0.4) ; README (feuille de route)
**Amont :** `matrix-rust-components-swift` `26.09.07` (inchangé)

---

## 1. Objectif et périmètre

La feuille de route plaçait en 0.4 sept sujets indépendants (médias, accusés de lecture, frappe,
présence, compte, OAuth, `loginDetails()`). Ils sont redécoupés : **la 0.4 est entièrement
consacrée à l'authentification**, les autres sujets glissent en 0.5 et 0.6 (§10).

Objectif : qu'une application puisse proposer un écran de connexion complet face à n'importe quel
homeserver actuel — y compris ceux, comme matrix.org, qui délèguent l'authentification à Matrix
Authentication Service (MAS) et n'acceptent plus le mot de passe pour les nouveaux comptes — et
qu'un utilisateur déconnecté en douceur par son serveur retrouve sa session sans perdre ses clés.

| Inclus | Exclu (et palier) |
| --- | --- |
| Découverte du serveur depuis un nom (`matrix.org`), une URL ou un user ID | — |
| `MatrixClient.loginDetails()` | — |
| Connexion OAuth 2.0 (MSC3861) : URL d'autorisation, callback, annulation, prompts dont `.create` | Gestion du compte via l'URL MAS (0.6) |
| Connexion par e-mail et mot de passe | Inscription par mot de passe (UIAA) |
| Connexion par QR code (MSC4108), dans les deux sens, ce nouvel appareil étant celui qui se connecte | *Accorder* une connexion par QR depuis un appareil déjà connecté |
| Reconnexion sur le même appareil après soft logout (mot de passe, e-mail ou OAuth) | SSO legacy : signalé par `loginDetails()`, non pris en charge |
| Store local par session ; ramassage des stores orphelins | Montée de l'amont |
| Harnais d'intégration Docker (Synapse, Synapse + MAS) | — |

## 2. Constats amont (release `26.09.07`)

1. **Détails de connexion.** `Client.homeserverLoginDetails() async -> HomeserverLoginDetails`, qui
   expose `url()`, `supportsPasswordLogin()`, `supportsOauthLogin()`, `supportsSsoLogin()` et
   `supportedOauthPrompts() -> [OAuthPrompt]`. Aucune session n'est requise.
2. **Découverte.** `ClientBuilder.serverNameOrHomeserverUrl(serverNameOrUrl:)` accepte un nom de
   serveur ou une URL et résout le homeserver via `.well-known` au `build()`. Échecs :
   `ClientBuildError.InvalidServerName`, `.ServerUnreachable`, `.WellKnownLookupFailed`,
   `.WellKnownDeserializationError`.
3. **OAuth.** `Client.urlForOauth(oauthConfiguration:prompt:loginHint:deviceId:additionalScopes:)`
   rend un `OAuthAuthorizationData` (URL de connexion) ; `Client.loginWithOauthCallback(callbackUrl:)`
   termine ; `Client.abortOauthAuth(authorizationData:)` abandonne. Le flux doit se dérouler sur
   **le même client** de bout en bout. `deviceId` permet de réutiliser un appareil existant, « only
   if the client also holds the corresponding encryption keys ». Erreurs : `OAuthError`
   (`.NotSupported`, `.MetadataInvalid`, `.CallbackUrlInvalid`, `.Cancelled`, `.Generic`).
4. **Persistance OAuth.** `Session.oauthData` porte l'enregistrement du client OAuth ; il est
   **déjà persisté** par `MatrixSessionData` depuis la 0.1. Restauration et rafraîchissement d'une
   session OAuth ne demandent aucune migration.
5. **E-mail.** `Client.loginWithEmail(email:password:initialDeviceName:deviceId:)`.
6. **QR.** `Client.newLoginWithQrCodeHandler(oauthConfiguration:) -> LoginWithQrCodeHandler`, avec
   deux modes :
   - `scan(qrCodeData:progressListener:)` : ce nouvel appareil scanne le QR d'un appareil connecté.
     Le client doit avoir été construit avec `QrCodeData.serverName()` comme nom de serveur.
     Progrès : `QrLoginProgress` = `.starting`, `.establishingSecureChannel(checkCode:checkCodeString:)`,
     `.waitingForToken(userCode:)`, `.syncingSecrets`, `.done`.
   - `generate(progressListener:)` : ce nouvel appareil affiche un QR. Progrès :
     `GeneratedQrLoginProgress` = `.starting`, `.qrReady(qrCode:)`, `.qrScanned(checkCodeSender:)`,
     `.waitingForToken(userCode:)`, `.syncingSecrets`, `.done`. `CheckCodeSender.send(code: UInt8)`.
   - `QrCodeData.fromBytes(bytes:)` / `toBytes()`. Erreurs : `HumanQrLoginError` (`.Declined`,
     `.Expired`, `.ConnectionInsecure`, `.LinkingNotSupported`, `.OtherDeviceNotSignedIn`,
     `.Cancelled`, `.NotFound`, `.UnsupportedQrCodeType`, `.OAuthMetadataInvalid`,
     `.SlidingSyncNotAvailable`, `.CheckCode…`, `.Continuation…`, `.Unknown`).
   - **L'étape `.syncingSecrets` écrit les secrets (cross-signing, clé de sauvegarde) dans le store
     du client pendant la connexion.** C'est ce qui interdit de conserver la poignée de main en
     mémoire de la 0.1 (§5).
7. **Une session par client, une fois.** Dans `matrix-sdk`, `set_session` / `restore_session`
   **paniquent** si le client porte déjà une session. On ne peut ni se reconnecter sur le client
   existant après un soft logout, ni réutiliser un client après une connexion : chaque connexion
   et chaque reconnexion se font sur un client neuf.
8. **Présence** (pour la feuille de route) : seul `Client.setPresence(presence:immediate:)` existe ;
   l'observation de la présence des autres n'est pas exposée.

## 3. Constat d'environnement

Le homeserver de la suite d'intégration actuelle (`matrix.ekreen.uk`, Tuwunel 1.8.1) n'annonce que
`m.login.password` et `m.login.token`, et répond `M_UNRECOGNIZED: OIDC server not configured` sur
`/_matrix/client/v1/auth_metadata`. OAuth et le QR n'y sont pas vérifiables : un harnais Docker
dédié est ajouté (§8.2). La suite Tuwunel reste en place comme non-régression.

## 4. API publique

### 4.1 Créer un client depuis un nom de serveur

```swift
public enum Matrix {
    // Existant, inchangé : aucune découverte, l'URL est prise telle quelle.
    public static func client(homeserver: URL, storage: MatrixStorage) -> any MatrixClient

    // Nouveau.
    public static func client(server: String, storage: MatrixStorage) async throws -> any MatrixClient
}
```

`server` accepte un nom de serveur (`matrix.org`), une URL (`https://matrix.example.com`) ou un
user ID (`@alice:matrix.org`, dont seul le nom de serveur est retenu). La découverte a lieu dans
l'appel ; `client.homeserver` rend ensuite l'URL résolue. Erreurs : nom invalide ou `.well-known`
illisible → `.unexpected` ; serveur injoignable → `.network(...)` selon la cause.

### 4.2 `MatrixClient`

```swift
public protocol MatrixClient: Sendable {
    var homeserver: URL { get }
    func loginDetails() async throws -> LoginDetails                                       // nouveau
    func login(_ credentials: Credentials) async throws -> any MatrixSession
    func beginOAuthLogin(_ configuration: OAuthConfiguration,
                         prompt: OAuthPrompt?, loginHint: String?) async throws -> any OAuthLoginFlow   // nouveau
    func loginWithQRCode(_ configuration: OAuthConfiguration) -> any QRCodeLogin            // nouveau
    func restoreSession() async throws -> (any MatrixSession)?
}

extension MatrixClient {
    // Commodité : prompt et loginHint à nil.
    public func beginOAuthLogin(_ configuration: OAuthConfiguration) async throws -> any OAuthLoginFlow
}
```

```swift
public struct LoginDetails: Sendable, Hashable {
    public let homeserver: URL
    public let supportsPassword: Bool
    public let supportsOAuth: Bool
    /// Signalé pour information : MatrixClientKit ne prend pas en charge le SSO legacy.
    public let supportsSSO: Bool
    public let oauthPrompts: Set<OAuthPrompt>
}

public enum OAuthPrompt: Sendable, Hashable {
    case login      // forcer la réauthentification
    case create     // proposer la création de compte
    case consent
}
```

`OAuthPrompt.unknown(value:)` amont est ignoré au mappage : un prompt inconnu n'est pas utilisable
par l'application. `OAuthPrompt` est un enum public, donc figé une fois publié (même règle que
`MatrixError`) ; un prompt standardisé plus tard sera ignoré jusqu'à la majeure suivante.

### 4.3 OAuth

```swift
public struct OAuthConfiguration: Sendable, Hashable {
    public var clientName: String?
    public var redirectURI: URL          // schéma propre à l'application, ex. com.example.app:/callback
    public var clientURI: URL
    public var logoURI: URL?
    public var termsOfServiceURI: URL?
    public var policyURI: URL?
    /// Enregistrements statiques pour les serveurs sans enregistrement dynamique : URL du
    /// homeserver (ou de l'issuer) → client ID.
    public var staticRegistrations: [URL: String]
    public init(...)   // valeurs par défaut : nil et [:]
}

public protocol OAuthLoginFlow: Sendable {
    /// L'URL à ouvrir dans `ASWebAuthenticationSession`.
    var authorizationURL: URL { get }
    /// Termine la connexion avec l'URL de redirection reçue.
    func complete(callbackURL: URL) async throws -> any MatrixSession
    /// Abandonne le flux. Sans effet après `complete` réussi. Idempotent.
    func cancel() async
}
```

L'application présente elle-même l'interface web : `Core` reste sans dépendance UI. Un flux ne se
complète qu'une fois ; un second `complete` lève `.unexpected`.

### 4.4 Connexion par QR code

Deux points d'entrée, un seul type :

```swift
// Ce nouvel appareil AFFICHE le QR, que l'appareil connecté scanne.
let login = client.loginWithQRCode(configuration)

// Ce nouvel appareil SCANNE le QR affiché par l'appareil connecté. Statique : le QR porte le nom
// du serveur, et le client amont doit être construit sur lui.
let login = Matrix.loginWithQRCode(scanned: payload, configuration: configuration, storage: storage)
```

```swift
public protocol QRCodeLogin: Sendable {
    /// Flux d'états commençant par la valeur courante ; chaque accès ouvre un abonnement
    /// indépendant.
    var state: AsyncStream<QRCodeLoginState> { get }
    /// Déroule la connexion et rend la session une fois `.done` atteint.
    func start() async throws -> any MatrixSession
    /// Mode « affiché » uniquement, en `.enterCheckCode` : transmet les deux chiffres affichés par
    /// l'appareil connecté.
    func submitCheckCode(_ code: UInt8) async throws
    /// Annule ; `start()` lève alors et l'état passe à `.failed(.cancelled)`.
    func cancel()
}

public enum QRCodeLoginState: Sendable, Hashable {
    case starting
    case displayQRCode(Data)                 // mode affiché : octets à encoder en QR
    case enterCheckCode                      // mode affiché : saisir les 2 chiffres → submitCheckCode
    case displayCheckCode(String)            // mode scanné : afficher ces 2 chiffres
    case waitingForApproval(userCode: String)
    case syncingSecrets
    case done
    case failed(QRCodeLoginFailure)
}

public enum QRCodeLoginFailure: Sendable, Hashable {
    case declined                // l'autre appareil a refusé
    case expired
    case insecureChannel         // code de vérification divergent
    case notSupported            // serveur sans MSC4108, sans OAuth, ou QR d'un autre type
    case otherDeviceNotSignedIn
    case cancelled
    case unknown
}
```

`QRCodeLoginState` et `QRCodeLoginFailure` sont des enums publics figés une fois publiés ; toute
erreur amont non listée ci-dessus est mappée vers `.unknown` (tableau au §6). Les états terminaux
sont `.done` et `.failed`. `start()` lève `MatrixError` en cas d'échec : les détails de l'échec
QR sont dans l'état, l'erreur levée est `.unexpected` avec la cause en `details`, sauf
`.cancelled` qui lève `CancellationError`.

### 4.5 Identifiants

```swift
public enum Credentials: Sendable, Hashable {
    case password(username: String, password: String, deviceName: String?)
    case email(address: String, password: String, deviceName: String?)        // nouveau
}
```

La description expurgée couvre le nouveau cas (le mot de passe n'apparaît jamais).

### 4.6 Reconnexion après soft logout

```swift
public protocol MatrixSession: Sendable {
    // … existant …
    /// Valable uniquement en `.softLoggedOut`. Se reconnecte sur le même appareil, ses clés
    /// intactes, et rend une NOUVELLE session. Celle-ci devient inerte et publie `.signedOut`.
    func reauthenticate(_ credentials: Credentials) async throws -> any MatrixSession
    func beginOAuthReauthentication(_ configuration: OAuthConfiguration) async throws -> any OAuthLoginFlow
}
```

- Appelées hors `.softLoggedOut` : lèvent `.unexpected` sans rien toucher.
- Le flux OAuth rendu par `beginOAuthReauthentication` est le même type qu'au §4.3 ; son
  `complete` rend la nouvelle session.
- En cas d'échec (mauvais mot de passe, réseau, flux annulé), l'ancienne session reste
  `.softLoggedOut`, intacte : l'utilisateur peut réessayer.
- Un utilisateur différent de celui de la session (identifiants d'un autre compte) : échec
  `.authentication(.invalidCredentials)`, la nouvelle session éventuellement ouverte côté serveur
  est déconnectée, rien n'est persisté.

**Pourquoi une nouvelle session plutôt que muter l'existante :** l'amont panique si l'on repose une
session sur un client qui en porte une (§2.7) ; il faut un client neuf, et tous les services de
la session sont construits sur le client. Les remplacer en place casserait silencieusement les
références que l'application a gardées (`session.rooms`, flux ouverts).

### 4.7 `AuthState`

Aucun cas ajouté (enum public, l'ajout casserait les `switch`). Documentation ajustée :

- `.softLoggedOut` : « … Call ``MatrixSession/reauthenticate(_:)`` or
  ``MatrixSession/beginOAuthReauthentication(_:)`` to sign in again on the same device. »
- `.signedOut` : « The session is over: the homeserver revoked it, ``MatrixSession/logout()``
  completed, **or it was replaced by a reauthenticated session**. In the first two cases,
  everything stored locally for it has been erased; a replaced session's data now belongs to its
  replacement. »

### 4.8 Changements cassants

Signalés en tête du CHANGELOG, comme en 0.2 et 0.3 :

- `MatrixClient` gagne `loginDetails()`, `beginOAuthLogin(_:prompt:loginHint:)`,
  `loginWithQRCode(_:)` ;
- `MatrixSession` gagne `reauthenticate(_:)` et `beginOAuthReauthentication(_:)` ;
- `Credentials` gagne `.email` : un `switch` exhaustif sur `Credentials` ne compile plus.

`MockMatrixClient` et `MockMatrixSession` couvrent les nouveaux membres.

## 5. Stockage par session

### 5.1 Identifiant de store

`MatrixSessionData` gagne `storeID: String?`, un UUID tiré à chaque nouvelle connexion. Le
décodage est tolérant : une session 0.1–0.3 persistée n'a pas le champ et se décode avec `nil`.

`LocalStore` et `StoragePaths` ne prennent plus un `UserID` mais un segment :

```swift
enum StoreSegment: Sendable, Hashable {
    case legacy(UserID)      // sessions 0.1–0.3 : empreinte du user ID, chemin actuel
    case session(String)     // à partir de 0.4 : storeID
}
```

| Segment | Répertoire | Clé Keychain |
| --- | --- | --- |
| `.legacy(userID)` | `MatrixClientKit/<StableDigest(userID)>/` | `com.matrixclientkit.store-key.<digest>` |
| `.session(id)` | `MatrixClientKit/<id>/` | `com.matrixclientkit.store-key.<id>` |

Un UUID (36 caractères, avec tirets) ne peut pas entrer en collision avec une empreinte
`StableDigest.short` (hexadécimal court). Une session restaurée n'est **jamais migrée** : une
session legacy garde son chemin jusqu'à sa déconnexion. La règle d'ordre de purge (répertoires
d'abord, clé ensuite) est inchangée. Le résolveur de l'extension lit le segment de la session
persistée et ouvre le même store, sans autre changement.

### 5.2 Une séquence unique pour toutes les connexions

Un type interne `LoginAttempt` porte toute connexion — mot de passe, e-mail, OAuth, QR — et toute
reconnexion :

1. **Préparer.** Pour une connexion : tirer un `storeID`, créer la clé et les répertoires.
   Pour une reconnexion : reprendre le segment de la session remplacée. Inscrire le segment au
   registre des tentatives en cours (§5.4).
2. **Construire** directement le client SQLite chiffré, avec le cross-signing automatique et le
   verrou inter-processus, comme `SessionRestorer.makeClient` aujourd'hui. Pour la découverte et le
   QR scanné, le builder reçoit `serverNameOrHomeserverUrl` ; sinon `homeserverUrl`.
3. **Dérouler** le flux sur ce client (avec `deviceId` pour une reconnexion).
4. **Persister** `client.session()` avec le segment, puis construire la `RustMatrixSession` sur ce
   même client. Plus de `restoreSession` après connexion.
5. **En cas d'échec ou d'annulation** : pour une connexion, purger le store du `storeID` ; pour une
   reconnexion, ne rien purger (le store appartient toujours à la session remplacée).
6. Désinscrire le segment du registre.

La poignée de main en mémoire de la 0.1 disparaît. Conséquence visible, documentée dans le
CHANGELOG (*Changed*) : l'identité cross-signing d'un compte qui n'en a pas est créée dès la
connexion par mot de passe, et non plus au premier lancement suivant.

### 5.3 Client sonde

`loginDetails()` et la découverte n'ont besoin d'aucun store. `RustMatrixClient` garde un client
« sonde » à store en mémoire, sans session, construit paresseusement (ou immédiatement par
`Matrix.client(server:)`, puisque c'est lui qui résout l'URL). Il ne sert jamais à se connecter
(§2.7).

### 5.4 Ramassage des stores orphelins

Un `OAuthLoginFlow` abandonné sans `cancel()`, un `QRCodeLogin` jamais terminé ou un crash en
pleine connexion laisseraient un store sans session. En 0.3, une nouvelle connexion par-dessus
une session persistée laissait déjà le store de l'ancienne inaccessible pour toujours.

Règle : au début de chaque `LoginAttempt` et à chaque restauration, **côté application
uniquement** (jamais avec le rôle extension, qui ne purge jamais rien — spec 0.3, §7), supprimer
tout store de `MatrixClientKit/` qui n'est :

- ni celui de la session persistée,
- ni inscrit au registre des tentatives en cours de ce processus.

Le registre est un ensemble de segments protégé par un `Mutex`, partagé par tous les
`RustMatrixClient` du processus. Les clés Keychain orphelines (préfixe
`com.matrixclientkit.store-key.`) sont supprimées par le même passage, après leurs répertoires.

Le ramassage est au mieux : un échec est ignoré et retenté au passage suivant ; il ne fait jamais
échouer une connexion ou une restauration.

### 5.5 Reconnexion : déroulé

1. Vérifier `.softLoggedOut`, sinon lever `.unexpected`.
2. Arrêter la sync de l'ancienne session.
3. `LoginAttempt` de reconnexion (§5.2) : même segment, `deviceId` de l'ancienne session.
4. Vérifier que l'utilisateur obtenu est le même (§4.6).
5. Persister les nouveaux jetons, construire la nouvelle session.
6. Marquer l'ancienne **remplacée** dans `SessionLifecycle` : elle ne purge plus rien et ignore
   tout callback d'erreur d'authentification ultérieur ; puis publier `.signedOut`.

**Risque identifié :** tant que l'application retient l'ancienne session, deux clients Rust
coexistent sur le même store SQLite. L'ancien est arrêté (sans sync, donc sans écriture crypto
attendue). Le plan commence par une **tâche d'exploration** contre le harnais (§8.2) qui confirme
que la coexistence est saine. Si elle ne l'est pas, `reauthenticate` exigera que l'ancienne
session soit libérée — vérifié par une référence faible sur son client — et lèvera `.unexpected`
documenté sinon ; la spec sera amendée en conséquence avant implémentation.

## 6. Erreurs

Aucun cas ajouté à `MatrixError` ni à ses enums imbriqués (règle de gel).

| Amont | `MatrixError` |
| --- | --- |
| `ClientBuildError.InvalidServerName`, `.WellKnownLookupFailed`, `.WellKnownDeserializationError` | `.unexpected` (message en anglais, cause en `details`) |
| `ClientBuildError.ServerUnreachable` | `.network(.offline)` |
| `OAuthError.NotSupported` | `.authentication(.unsupportedLoginType)` |
| `OAuthError.MetadataInvalid` | `.server(.invalidResponse)` |
| `OAuthError.CallbackUrlInvalid`, `.Generic` | `.unexpected` |
| `OAuthError.Cancelled` | `CancellationError` |
| Connexion par e-mail : erreurs `ClientError` | même mappage que le mot de passe (`ErrorMapper.mapAuthentication`) |

| `HumanQrLoginError` | `QRCodeLoginFailure` |
| --- | --- |
| `.Declined` | `.declined` |
| `.Expired` | `.expired` |
| `.ConnectionInsecure` | `.insecureChannel` |
| `.LinkingNotSupported`, `.OAuthMetadataInvalid`, `.SlidingSyncNotAvailable`, `.UnsupportedQrCodeType`, `.NotFound` | `.notSupported` |
| `.OtherDeviceNotSignedIn` | `.otherDeviceNotSignedIn` |
| `.Cancelled` | `.cancelled` |
| `.Unknown`, `.CheckCode…`, `.Continuation…` | `.unknown` |

Un `QrCodeData.fromBytes` en échec (QR illisible ou d'un autre type) donne
`.failed(.notSupported)`.

## 7. Architecture interne

| Élément | Cible | Rôle |
| --- | --- | --- |
| `LoginDetails`, `OAuthPrompt`, `OAuthConfiguration`, `QRCodeLoginState`, `QRCodeLoginFailure` | Core | Modèles publics |
| `OAuthLoginFlow`, `QRCodeLogin` | Core | Protocoles publics |
| `QRCodeLoginReducer` | Core | Fonction pure : événement de progrès (type Core propre au package) → `QRCodeLoginState`, transitions illégales ignorées, états terminaux absorbants |
| `StoreSegment`, `StoragePaths`, `LocalStore` | Rust | Segment legacy ou session (§5.1) |
| `LoginAttempt` | Rust | Séquence unique de connexion (§5.2) |
| `LoginAttemptRegistry` | Rust | Segments en cours, `Mutex` partagé |
| `OrphanedStoreSweeper` | Rust | Ramassage (§5.4), injectable pour les tests |
| `RustOAuthLoginFlow`, `RustQRCodeLogin` | Rust | Implémentations ; le QR passe par `ffiStream` pour ses progrès |
| `OAuthMapper`, `QRCodeMapper`, `LoginDetailsMapper` | Rust/Bridge | Mappage amont ↔ Core |
| `SessionLifecycle` | Rust | Nouvel état interne « remplacée » (§5.5) |
| `Matrix.client(server:storage:)`, `Matrix.loginWithQRCode(scanned:configuration:storage:)` | Umbrella | Fabriques |

## 8. Tests

### 8.1 Unitaires (sans réseau)

- **Core :** `LoginDetails`, `OAuthConfiguration` ; `Credentials.email` et sa description
  expurgée ; `QRCodeLoginReducer` testé exhaustivement (deux modes, chaque échec, annulation,
  états terminaux absorbants).
- **Rust :** mappers OAuth, QR, `HomeserverLoginDetails`, tableau d'erreurs du §6 ;
  `StoragePaths` et `LocalStore` pour les deux segments ; décodage d'un `MatrixSessionData` 0.3
  sans `storeID` ; ramassage (garde la session persistée, garde les tentatives inscrites, ne fait
  rien avec le rôle extension, supprime répertoires puis clés) ; `LoginAttempt` qui purge en cas
  d'échec d'une connexion et ne purge pas en cas d'échec d'une reconnexion (couture de fabrique de
  client, comme `SessionRestorer`) ; `SessionLifecycle` : une session remplacée n'efface rien et
  finit en `.signedOut`.
- **Mocks :** couverture des nouveaux doubles dans `MockTests`.

### 8.2 Harnais d'intégration Docker

Nouveau, lancé à la main comme la suite actuelle, jamais en CI.
`Tests/IntegrationHarness/docker-compose.yml` :

| Service | Rôle |
| --- | --- |
| `synapse-password` | Synapse classique : mot de passe, e-mail (adresse liée par l'API admin), découverte (`.well-known` servi par le conteneur), soft logout (durée de vie courte du jeton d'accès — configuration confirmée par la tâche d'exploration) |
| `synapse-oauth` + `mas` + `postgres` | Synapse délégué à MAS (MSC3861), rendez-vous MSC4108 activé : `loginDetails()` (OAuth annoncé), OAuth, QR |

- `Scripts/integration-harness.sh up|down` démarre, crée les comptes jetables (`mas-cli`, API admin
  Synapse), attend la disponibilité et exporte les variables d'environnement lues par la suite.
- **OAuth :** le test pilote le formulaire MAS en HTTP (`URLSession` : authentification,
  consentement), capture la redirection vers le schéma du client, puis appelle
  `complete(callbackURL:)`.
- **QR :** l'appareil connecté est joué par un second client Rust, via
  `newGrantLoginWithQrCodeHandler` du SDK, importable depuis la cible de test. Le test approuve le
  `userCode` côté MAS en HTTP et vérifie que la nouvelle session est **vérifiée** (secrets reçus).
  Repli prévu si l'automatisation du QR échoue : réducteur et mappers testés unitairement, et le
  CHANGELOG dit explicitement que le QR n'a pas été exercé contre un vrai serveur.
- **Reconnexion :** soft logout provoqué sur `synapse-password`, puis `reauthenticate` ; vérifier
  même `deviceID`, même store, messages chiffrés antérieurs toujours déchiffrables, ancienne
  session `.signedOut`.
- **Stockage :** une session 0.3 (sans `storeID`) créée par le seeder en processus séparé est
  restaurée par 0.4 sur son chemin legacy ; une connexion OAuth annulée ne laisse aucun store.

La suite Tuwunel existante reste inchangée et doit passer.

## 9. Mocks

- `MockMatrixClient` : `loginDetailsResult`, `oauthFlow` (un `MockOAuthLoginFlow`), `qrCodeLogin`
  (un `MockQRCodeLogin`), erreurs configurables, appels enregistrés.
- `MockOAuthLoginFlow` : `authorizationURL` configurable ; `complete` rend une session ou une
  erreur configurée ; appels à `complete` et `cancel` enregistrés.
- `MockQRCodeLogin` : `emit(_ state:)` pilote le flux d'états ; `submitCheckCode` enregistré ;
  `start()` rend la session configurée ou lève.
- `MockMatrixSession` : `reauthenticateResult` (session ou erreur), `oauthReauthenticationFlow`,
  `authState` pilotable.
- `SampleData.loginDetails(...)` et `SampleData.oauthConfiguration()`.

## 10. Documentation et livraison

- **DocC :** nouvel article *Authentication* — choisir un serveur, `loginDetails()`, mot de passe
  et e-mail, OAuth avec `ASWebAuthenticationSession`, QR dans les deux sens, soft logout et
  `reauthenticate`. Extraits compilables. *GettingStarted* renvoie vers lui.
- **README :** Scope 0.4 ; tableau de compatibilité `0.4.x` ; suppression du paragraphe
  « `loginDetails()` not implemented » ; feuille de route :

  | Version | Contenu |
  | --- | --- |
  | 0.4 | Authentication: server discovery, `loginDetails()`, OAuth, email, QR-code login, same-device sign-in after soft logout |
  | 0.5 | Media and send handle |
  | 0.6 | Read receipts, typing, presence (publishing only — the SDK does not expose observing it), profile and account |

- **CHANGELOG 0.4.0 :** *Breaking* (§4.8), *Added*, *Changed* (store par session, ramassage des
  orphelins, cross-signing amorcé à la connexion), *Not included* (§1), *Verified* (harnais).
- **Version :** `PackageInfo` 0.4.0. Amont inchangé (26.09.07).

## 11. Risques

| Risque | Parade |
| --- | --- |
| Deux clients Rust sur le même store pendant une reconnexion | Tâche d'exploration en tête de plan ; repli documenté (§5.5) |
| Ramassage supprimant un store encore utile | Jamais côté extension ; registre des tentatives ; session persistée toujours épargnée ; tests dédiés |
| QR difficile à automatiser (MSC4108 côté Synapse, approbation MAS) | Repli explicite (§8.2) |
| Configuration MAS / Synapse lourde à maintenir | Harnais isolé dans `Tests/IntegrationHarness`, versions d'images épinglées |
| Enums publics nouveaux (`OAuthPrompt`, `QRCodeLoginState`, `QRCodeLoginFailure`) figés | Cas choisis d'après l'amont complet ; `.unknown` comme réceptacle |
