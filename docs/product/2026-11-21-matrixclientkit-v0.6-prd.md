# MatrixClientKit 0.6 — PRD

**Date :** 2026-11-21
**Statut :** rédigé sans séance de questions ; chaque arbitrage non tranché par la feuille de route
est marqué *décision de rédaction*. Une seule question ouverte (§13, Q1) conditionne une tâche (T8).
**Entrées :** README (feuille de route : « 0.6 — Read receipts, typing, presence (publishing only —
the SDK does not expose observing it), profile and account ») ; spec 0.4 (§1 : gestion du compte via
l'URL MAS reportée en 0.6 ; §2.8 : présence) ; spec 0.5 (§1 : avatars des utilisateurs en 0.6,
galeries « 0.6 ou plus tard ») ; rulings 0.5
**Amont :** `matrix-rust-components-swift` `26.09.07` (inchangé, `Package.resolved`)

---

## 1. Problème

Une application bâtie sur MatrixClientKit 0.5 affiche des conversations, envoie texte et médias,
mais reste muette sur tout ce qui rend une messagerie *vivante* et sur l'utilisateur lui-même :

- elle ne peut pas dire au serveur qu'un message a été lu — les compteurs de non-lus
  (`RoomSummary.notificationCount`) ne redescendent que si l'utilisateur lit ailleurs ;
- elle ne sait pas qui a lu un message, ni qui est en train d'écrire ;
- l'utilisateur apparaît « indisponible » à ses contacts (état initial amont) sans moyen de le
  changer ;
- l'utilisateur ne peut ni changer son nom ni son avatar, et l'application ne peut pas afficher
  l'avatar de l'expéditeur d'un message ni le profil d'un autre utilisateur ;
- sur un serveur délégué à MAS (matrix.org), l'application n'a aucun chemin vers la gestion du
  compte (appareils, mot de passe, suppression) ; elle ne peut pas non plus ignorer un utilisateur
  abusif.

Qui est touché : les développeurs iOS/macOS qui intègrent le package (et, par eux, leurs
utilisateurs finaux). Les deux derniers points ont un enjeu App Store : la règle 1.2 (contenu
généré par les utilisateurs) attend un moyen de bloquer un utilisateur abusif, la règle 5.1.1(v)
une suppression de compte dans l'application quand elle permet d'en créer un (la 0.4 le permet via
OAuth `.create`).

## 2. Objectifs et périmètre

Objectif : qu'une application puisse **marquer une conversation comme lue** (publiquement ou en
privé), **afficher qui a lu quoi** et **qui écrit**, **publier la présence** de l'utilisateur,
**gérer son profil** (nom, avatar) et **afficher celui des autres**, **ignorer** un utilisateur, et
**ouvrir la gestion du compte** du serveur d'autorisation — ou désactiver un compte à mot de passe.

| Inclus | Exclu (et palier) |
| --- | --- |
| Envoi d'accusés de lecture, public (`m.read`) ou privé (`m.read.private`), avec déplacement du marqueur de lecture (`m.fully_read`) | Drapeau « marqué non lu » d'une room (`setUnreadFlag`) — plus tard |
| Accusés de lecture des autres par message (`Message.readReceipts`) | Fils de discussion (accusés par thread) — avec les threads, plus tard |
| Notifications de frappe : publier, observer (`RoomHandle`) | — |
| Publication de la présence (`online`, `unavailable`, `offline`) | **Observer** la présence d'autrui : l'amont ne l'expose pas |
| Profil : lire celui d'un utilisateur, changer son nom et son avatar, retirer l'avatar | Observer son propre profil en direct (exige l'extension *Profiles* du sliding sync, §3.2) ; statut et appel MSC4426 |
| Avatar de l'expéditeur dans `Message` (`senderAvatar`) | Liste des membres d'une room, profil propre à une room — plus tard |
| Gestion du compte via l'URL du serveur d'autorisation (MAS) | Changement de mot de passe hors MAS : l'amont ne l'expose pas |
| Utilisateurs ignorés : observer, ignorer, ne plus ignorer | Réinitialisation de l'identité cryptographique (`crossSigningReset`) — palier « Later » du README |
| Désactivation d'un compte à mot de passe (**sous réserve de Q1**) | Désactivation d'un compte MAS par l'API : passe par l'URL de gestion |
| — | Galeries (`sendGallery`) — 0.7 ou plus tard (*décision de rédaction*, §2.1) |
| — | Capacités du serveur (`canChangeDisplayname`, `canChangeAvatar`) — plus tard |
| — | Montée de l'amont |

### 2.1 Non-objectifs justifiés

- **Galeries.** *Décision de rédaction :* hors périmètre. Le thème de la 0.6 est la présence et
  l'identité, pas les médias ; `sendGallery` ajouterait un membre exigé de plus à `Timeline`
  (rupture) et un handle (`SendGalleryJoinHandle`) aux mêmes subtilités que `AttachmentUpload`
  (`join()` rend la main à la mise en file). Rien ne bloque une 0.7 : l'API amont existe.
- **Le package ne publie rien de lui-même.** *Décision de rédaction :* il n'envoie ni présence, ni
  accusé, ni frappe sans un appel explicite de l'application. Conséquence documentée : tant que
  l'application n'appelle pas `setPresence(_:)`, l'utilisateur est `unavailable` (état initial
  amont), à chaque lancement.
- **Pas de visibilité par défaut des accusés.** *Décision de rédaction :* le paramètre
  `visibility` est exigé à chaque appel. Le choix public/privé est une décision de produit de
  l'application (réglage de confidentialité), pas du SDK.

## 3. Constats amont (release `26.09.07`)

Relevés dans `.build/checkouts/matrix-rust-components-swift/Sources/MatrixRustSDK/`.

### 3.1 Accusés de lecture et frappe

1. **Envoi.** `Timeline.markAsRead(receiptType:) async throws` (dernier événement visible ; si aucun
   et que la timeline est live, l'amont lève le marqueur « non lu » à la place) et
   `Timeline.sendReadReceipt(receiptType:eventId:) async throws`. `ReceiptType` = `.read`,
   `.readPrivate`, `.fullyRead`. `Room.markAsRead(receiptType:)` existe aussi, réservé aux cas sans
   timeline ; il ne lève **pas** le drapeau non-lu.
2. **Lecture.** `EventTimelineItem.readReceipts: [String: Receipt]`, indexé par user ID ;
   `Receipt` ne porte que `timestamp: Timestamp?` (millisecondes). La timeline par défaut
   (`Room.timeline()`, utilisée depuis la 0.1) suit déjà les accusés
   (« live timeline with read receipts and read marker tracking »). Un accusé n'est porté que par
   le **dernier** événement lu par cet utilisateur.
3. **Accusé d'un utilisateur donné.** `Room.loadUserReceipt(receiptType:thread:userId:)` (depuis le
   store local) — non retenu : `Message.readReceipts` couvre l'affichage.
4. **Frappe.** `Room.typingNotice(isTyping:) async throws` ;
   `Room.subscribeToTypingNotifications(listener:) -> TaskHandle`, listener
   `call(typingUserIds: [String])` — des user IDs seulement. Les bindings ne disent ni si
   l'utilisateur courant est filtré, ni comment l'amont limite la fréquence d'envoi : **à
   constater en intégration** (T10).
5. **Compteurs.** `RoomInfo.numUnreadMessages`, `numUnreadNotifications`, `numUnreadMentions`,
   `isMarkedUnread`, `fullyReadEventId` existent ; `RoomSummary` n'en reprend que les compteurs
   serveur (`notificationCount`, `highlightCount`) — inchangé en 0.6.

### 3.2 Présence et profil

6. **Présence.** Seul `Client.setPresence(presence:immediate:) async throws` existe.
   `PresenceState` = `.online`, `.offline`, `.unavailable`. L'état sert aux requêtes de sync
   suivantes **quel que soit** `immediate` ; l'état initial est `Unavailable` ; `immediate: true`
   envoie en plus une mise à jour au serveur. Aucune lecture, aucun listener de présence.
7. **Profil propre.** `Client.displayName() async throws -> String`, `avatarUrl() async throws ->
   String?` (réseau ; remplit `cachedAvatarUrl()`), `setDisplayName(name:)`,
   `uploadAvatar(mimeType:data:)` (des octets seulement, pas de fichier ni d'`ImageInfo`),
   `removeAvatar()`.
8. **Observation du profil propre.** `Client.subscribeToOwnProfile(listener:)` n'émet qu'un profil
   vide sans l'extension *Profiles* du sliding sync (`SyncServiceBuilder.withProfilesExtension()`,
   support serveur : `isProfilesSlidingSyncExtensionSupported()`). Activer l'extension changerait la
   configuration de sync de toutes les applications : non retenu.
9. **Profil d'autrui.** `Client.getProfile(userId:) async throws -> UserProfile` (`userId`,
   `displayName`, `avatarUrl`, et `status` / `call` MSC4426, instables). `searchUsers` existe — hors
   périmètre.
10. **Expéditeur.** `EventTimelineItem.senderProfile: ProfileDetails` ; `.ready(displayName:
    displayNameAmbiguous:avatarUrl:status:call:)`. La 0.1 n'en lit que le nom.
11. **Capacités.** `HomeserverCapabilities.canChangeDisplayname()`, `canChangeAvatar()`,
    `canChangePassword()` — non retenues en 0.6.

### 3.3 Compte

12. **URL de gestion.** `Client.accountUrl(action: AccountManagementAction?) async throws ->
    String?` ; `nil` pour un serveur qui ne délègue pas à un serveur d'autorisation.
    `AccountManagementAction` = `.profile`, `.devicesList`, `.deviceView(deviceId:)`,
    `.deviceDelete(deviceId:)`, `.accountDeactivate`, `.crossSigningReset`. Sans action : la racine
    de la gestion du compte.
13. **Utilisateurs ignorés.** `Client.ignoredUsers() async throws -> [String]`,
    `ignoreUser(userId:)`, `unignoreUser(userId:)`, `subscribeToIgnoredUsers(listener:) -> TaskHandle`
    (`call(ignoredUserIds:)`, sans valeur initiale garantie).
14. **Désactivation.** `Client.deactivateAccount(authData: AuthData?, eraseData: Bool) async throws`,
    UIAA : « The first request needs to set this to `None` and will always fail », puis la même
    requête avec `AuthData.password(passwordDetails: AuthDataPasswordDetails(identifier:password:))`.
    Seul `m.login.password` est pris en charge : un compte MAS se désactive par l'URL de gestion
    (`.accountDeactivate`).
15. **Absent.** Pas de changement de mot de passe, pas de gestion des sessions hors MAS.

### 3.4 Galeries (pour mémoire)

16. `Timeline.sendGallery(params: GalleryUploadParameters, itemInfos: [GalleryItemInfo]) throws ->
    SendGalleryJoinHandle` (synchrone, `cancel()`, `join() async throws`). Hors périmètre (§2.1).

## 4. API publique

Les docs `///` sont en anglais (convention du dépôt) ; les signatures ci-dessous sont normatives.

### 4.1 Accusés de lecture

```swift
/// Who can see a read receipt you send.
public enum ReadReceiptVisibility: Sendable, Hashable {
    /// Every member of the room (`m.read`).
    case `public`
    /// Only your own devices (`m.read.private`): your unread counts stay in sync, nobody else
    /// learns that you read the room.
    case `private`
}

/// Another member's read position: the latest message they read.
public struct ReadReceipt: Sendable, Hashable {
    public let userID: UserID
    /// When they read it, when the homeserver says.
    public let timestamp: Date?
    public init(userID: UserID, timestamp: Date?)
}
```

`Message` gagne, **en fin de liste avec une valeur par défaut** (non cassant pour qui construit des
`Message`) :

```swift
/// The other members whose latest read message is this one, most recent first.
public let readReceipts: [ReadReceipt]          // défaut []
/// The sender's avatar at the time of sending, when known. Pass it to ``MediaService``.
public let senderAvatar: MediaSource?           // défaut nil
```

`Timeline` gagne :

```swift
/// Marks the room as read up to its latest visible message, and moves your read marker there.
func markAsRead(visibility: ReadReceiptVisibility) async throws

/// Marks the room as read up to `eventID` — the last message the user actually saw — and moves
/// your read marker there.
func markAsRead(upTo eventID: EventID, visibility: ReadReceiptVisibility) async throws
```

Comportements :

- `markAsRead(visibility:)` appelle `markAsRead(receiptType: .read | .readPrivate)` puis
  `markAsRead(receiptType: .fullyRead)` ; `markAsRead(upTo:visibility:)` fait de même avec
  `sendReadReceipt(receiptType:eventId:)`. *Décision de rédaction :* un seul appel public couvre
  accusé et marqueur, comme le comportement attendu d'un client (Element X envoie les deux) ; si
  l'accusé échoue, le marqueur n'est pas tenté et l'erreur remonte.
- `readReceipts` **exclut l'utilisateur courant** (filtré par le package si l'amont ne le fait pas)
  et est trié par horodatage décroissant, puis par `UserID` ; un horodatage absent passe en dernier.
- Un accusé ne figure que sur le **dernier** message lu par ce membre : savoir si X a lu le message
  M revient à chercher son accusé sur M ou sur un message plus récent (documenté en DocC).
- Les accusés privés des autres ne sont jamais visibles (protocole Matrix).
- `senderAvatar` vient de `ProfileDetails.ready(avatarUrl:)` via `MediaSource(url:)` ; `nil` tant
  que le profil n'est pas chargé.

### 4.2 Frappe

`RoomHandle` gagne :

```swift
/// A stream of snapshots: every value is the complete, current list of members typing in this
/// room, the current user excluded. Every access opens an independent subscription.
var typingUsers: AsyncStream<[UserID]> { get }

/// Tells the room whether the current user is typing. Call it with `true` as the user types and
/// with `false` when they stop or send.
func setTyping(_ isTyping: Bool) async throws
```

- Flux d'instantanés en `.bufferingNewest(1)` (règle du dépôt), fin du flux et annulation de la
  souscription amont à la sortie de boucle (mécanique `FFIStream` existante).
- Un user ID amont invalide est écarté (pas de position à préserver, contrairement aux diffs).
- La limitation de fréquence (appels répétés à `setTyping(true)` à chaque frappe) est celle de
  l'amont, constatée en T10 et documentée telle quelle.

### 4.3 Profil et présence

```swift
/// A user's global profile.
public struct UserProfile: Sendable, Hashable {
    public let userID: UserID
    public let displayName: String?
    /// Pass it to ``MediaService`` to display the avatar.
    public let avatar: MediaSource?
    public init(userID: UserID, displayName: String?, avatar: MediaSource?)
}

/// What the current user's contacts see of their availability.
public enum Presence: Sendable, Hashable {
    case online
    /// Connected but away — the state until the application sets another one.
    case unavailable
    case offline
}

public protocol ProfileService: Sendable {
    /// Fetches a user's global profile from the homeserver; pass ``MatrixSession/userID`` for
    /// the current user's.
    func profile(of user: UserID) async throws -> UserProfile
    /// Changes the current user's display name.
    func setDisplayName(_ name: String) async throws
    /// Uploads `data` and makes it the current user's avatar.
    func setAvatar(_ data: Data, mimeType: String) async throws
    /// Removes the current user's avatar.
    func removeAvatar() async throws
    /// Publishes the current user's presence now, and keeps it for the following syncs.
    func setPresence(_ presence: Presence) async throws
}
```

`MatrixSession` gagne `var profile: any ProfileService { get }`.

- *Décision de rédaction :* la présence vit dans `ProfileService` (« comment les autres me voient »)
  plutôt que dans un service à elle seule : un seul membre, pas d'observation possible.
- `setPresence` passe toujours `immediate: true`. **Même s'il lève**, l'état s'applique aux syncs
  suivantes (§3.2, constat 6) : documenté. L'état n'est pas persisté : à republier à chaque
  lancement.
- `setDisplayName` ne valide pas le nom (une chaîne vide est transmise telle quelle).
- `setAvatar` : pas de lecture de fichier (l'amont ne prend que des octets) ; un média trop gros
  suit la règle 0.5 (`.unexpected` explicite).
- Aucun cache : chaque `profile(of:)` interroge le serveur. Pas d'observation du profil propre
  (§3.2, constat 8) : après `setDisplayName`, l'application met à jour son affichage elle-même.

### 4.4 Compte

```swift
/// A page of the account management offered by the authorization server.
/// A struct, not an enum: new pages can be added without breaking your `switch`.
public struct AccountManagementAction: Sendable, Hashable {
    /// The account management home page.
    public static let overview: AccountManagementAction
    public static let profile: AccountManagementAction
    public static let devices: AccountManagementAction
    public static func device(_ id: DeviceID) -> AccountManagementAction
    public static func deleteDevice(_ id: DeviceID) -> AccountManagementAction
    public static let deactivateAccount: AccountManagementAction
}

public protocol AccountService: Sendable {
    /// The page to open in a browser (`ASWebAuthenticationSession` or Safari) for `action`;
    /// `nil` when the homeserver does not delegate account management to an authorization
    /// server — then the account is managed by the homeserver itself.
    func managementURL(for action: AccountManagementAction) async throws -> URL?

    /// A stream of snapshots of the users the current user ignores, starting with the current
    /// list. Every access opens an independent subscription.
    var ignoredUsers: AsyncStream<[UserID]> { get }
    /// Ignores a user: their messages and invitations no longer reach this account.
    func ignore(_ user: UserID) async throws
    /// Stops ignoring a user.
    func unignore(_ user: UserID) async throws

    /// Deactivates the account for good, with its password. (Sous réserve de Q1, §13.)
    func deactivate(password: String, eraseData: Bool) async throws
}
```

`MatrixSession` gagne `var account: any AccountService { get }`.

- *Décision de rédaction :* `AccountManagementAction` est une **struct** à membres statiques, pas
  une enum publique : une enum publique est exhaustive pour le consommateur (règle d'évolution du
  README), et l'amont a déjà un cas (`crossSigningReset`) volontairement non exposé tant que la
  réinitialisation d'identité est au palier « Later ».
- `managementURL` : une chaîne amont qui n'est pas une URL valide → `.unexpected` explicite.
- `ignoredUsers` : la valeur initiale vient de `ignoredUsers()`, les suivantes du listener ; un
  échec de la lecture initiale termine le flux **sans valeur** (même règle que
  `RoomService.list(filter:)`, documentée).
- `deactivate` (Q1) : refusé **avant tout appel amont** pour une session OAuth
  (`MatrixSessionData.oauthData != nil`) avec `.unexpected` dont le message renvoie vers
  `managementURL(for: .deactivateAccount)`. Sinon, premier appel UIAA sans `authData`, puis avec le
  mot de passe (`identifier` = user ID de la session). En cas de succès : les données locales sont
  effacées comme après `logout()` (sans second appel serveur) et `authState` rapporte
  `.signedOut`. En cas d'échec (mot de passe refusé, réseau) : **rien n'est effacé**, la session
  reste utilisable — à la différence de `logout()`.

### 4.5 Changements cassants (*Breaking*)

- `Timeline` exige `markAsRead(visibility:)` et `markAsRead(upTo:visibility:)`.
- `RoomHandle` exige `typingUsers` et `setTyping(_:)`.
- `MatrixSession` exige `profile` et `account`.
- Une application qui implémente ces protocoles elle-même (typiquement un double de test) doit les
  compléter, ou utiliser `MockTimeline`, `MockRoomHandle`, `MockMatrixSession`.
- Non cassant : `Message` gagne deux propriétés, initialiseur à valeurs par défaut.

## 5. Erreurs

Aucun nouveau cas de premier niveau ni de cas imbriqué dans `MatrixError` (règle de gel).

| Situation | Erreur |
| --- | --- |
| `profile(of:)` d'un utilisateur inconnu (`M_NOT_FOUND`) | `.notFound(.user)` (remappé depuis `.notFound(.unspecified)`, comme `.media` en 0.5) |
| `markAsRead(upTo:)` sur un événement inconnu | erreur amont via `ErrorMapper` (`.notFound(.event)` si distinguable, sinon `.unexpected`) |
| Nom ou avatar refusé par le serveur (`M_FORBIDDEN`) | `.permission(.forbidden)` |
| Avatar trop gros (`M_TOO_LARGE`) | `.unexpected` avec message explicite (règle 0.5) |
| URL de gestion amont mal formée | `.unexpected` |
| `deactivate` sur une session OAuth | `.unexpected`, message renvoyant à `managementURL(for: .deactivateAccount)` |
| `deactivate` : mot de passe refusé | `.authentication(.invalidCredentials)` (même remappage `M_FORBIDDEN` que la connexion) |
| Frappe ou accusé dans une room quittée | `ErrorMapper` existant |

## 6. Durée de vie des objets FFI

Même schéma qu'en 0.5 (§5 de la spec 0.5) : `RustProfileService` et `RustAccountService` retiennent
la `ClientLifetime` de la session ; les `TaskHandle` de frappe et d'utilisateurs ignorés sont
annulés et libérés dans la durée de vie du client. Le test de durée de vie du harnais (0.5) est
étendu : garder `profile`, `account`, un flux `typingUsers` et un flux `ignoredUsers` après
`logout()`, libérer la session puis le reste — le processus ne s'arrête pas.

## 7. Architecture interne

- `Core` : `ReadReceipt`, `ReadReceiptVisibility`, `UserProfile`, `Presence`,
  `AccountManagementAction` (`Models/`) ; `ProfileService`, `AccountService` (`Services/`). Jamais
  d'import de `MatrixRustSDK`.
- `Rust` : `ReceiptMapper` (visibilité → `ReceiptType`, accusés reçus → `[ReadReceipt]`),
  `ProfileMapper` (`UserProfile` amont, `Presence`, `AccountManagementAction`), coutures
  `ProfileDriving` / `AccountDriving` sur le modèle des `*Driving`, `RustProfileService`,
  `RustAccountService` ; `TimelineMapper` reçoit l'user ID courant pour filtrer les accusés.
- `SessionLifecycle` gagne une terminaison « serveur d'abord, effacement seulement si le serveur a
  réussi » pour `deactivate` (Q1).
- Pas de `@MainActor` ; un type par fichier ; mappers dans `Bridge/`.

## 8. Critères d'acceptation (produit)

Vérifiables par test, unitaire (U) ou d'intégration contre le harnais Synapse (I).

1. **(I)** Deux comptes dans une room : A envoie un message ; B appelle
   `markAsRead(visibility: .public)` ; dans la timeline de A, le message porte un `ReadReceipt` de B
   dans un délai borné. Avec `.private`, aucun accusé de B n'apparaît chez A.
2. **(I)** Après `markAsRead` par B, le `RoomSummary` de la room chez B passe à
   `notificationCount == 0` à la sync suivante.
3. **(I)** `markAsRead(upTo:)` sur un message plus ancien : l'accusé de B est sur ce message, pas
   sur le plus récent.
4. **(U)** `readReceipts` exclut l'utilisateur courant, est trié (récent d'abord, `nil` en dernier),
   écarte un user ID invalide ; `senderAvatar` est rempli depuis un profil prêt, `nil` sinon.
5. **(I)** B appelle `setTyping(true)` : `typingUsers` de A contient B ; après `setTyping(false)`,
   la liste est vide. La liste de A ne contient jamais A.
6. **(I)** `setPresence(.online)` : `GET /_matrix/client/v3/presence/{userId}/status` (HTTP du
   harnais) rend `online` ; puis `.unavailable` → `unavailable`.
7. **(I)** `setDisplayName`, `setAvatar`, `removeAvatar` : `profile(of: session.userID)` reflète
   chaque changement ; `profile(of:)` d'un autre compte rend son nom ; d'un compte inexistant,
   `.notFound(.user)`.
8. **(I)** Sur le harnais Synapse + MAS, `managementURL(for: .profile)` rend une URL de l'hôte MAS ;
   sur le harnais mot de passe, `nil`.
9. **(I)** `ignore(B)` : `ignoredUsers` émet une liste contenant B ; `unignore(B)` la vide.
10. **(I, Q1)** Sur un compte jetable créé par l'API admin : `deactivate` avec un mauvais mot de
    passe lève `.authentication(.invalidCredentials)` et la session reste utilisable ; avec le bon,
    `authState` rapporte `.signedOut`, le store local est effacé, une connexion ultérieure échoue
    avec `.authentication(.userDeactivated)`. Sur une session OAuth : `.unexpected` sans appel
    amont (U).
11. **(I)** Durée de vie (§6).
12. **(U)** Chaque nouveau membre des doubles est pilotable et observable.
13. `swift build`, `swift test --skip MatrixClientKitIntegrationTests` et le lint
    `swift-format --strict` de la CI verts ; la DocC se génère sans avertissement de lien.

**Mesure de succès :** une application de démonstration peut implémenter « vu par », « X écrit… »,
un écran de profil et un lien « Gérer mon compte » sans importer `MatrixRustSDK` ni écrire de code
HTTP ; tous les critères ci-dessus passent sur le harnais.

## 9. Tests

- **Unitaires (sans réseau)** : `ReceiptMapper`, `ProfileMapper`, filtrage des accusés et des
  frappes, struct `AccountManagementAction` → action amont (dont `.overview` → `nil`), refus de
  `deactivate` OAuth, terminaison conditionnelle de `SessionLifecycle`, doubles.
- **Intégration (harnais Docker)** : deux sessions SDK dans le même processus (l'utilisateur du
  harnais et le compte admin) pour accusés et frappe ; HTTP du harnais pour la présence et la
  création du compte jetable ; harnais OAuth pour l'URL de gestion. Si Docker est indisponible :
  suite écrite et compilée, exécution consignée « non exécutée » (pratique 0.5).

## 10. Mocks et `SampleData`

- `MockTimeline` : `markAsReadCalls: [ReadReceiptVisibility]`,
  `markAsReadUpToCalls: [(EventID, ReadReceiptVisibility)]` (ou un type nommé équivalent),
  `markAsReadError`.
- `MockRoomHandle` : `emitTypingUsers(_:)`, `typingNotices: [Bool]`, `typingError`.
- Nouveaux : `MockProfileService` (profils par user ID, `displayNameChanges`, `avatarUploads`,
  `removeAvatarCount`, `publishedPresences`, erreur configurable) ; `MockAccountService` (URL par
  action, `emitIgnoredUsers(_:)`, `ignoredCalls`, `unignoredCalls`, `deactivations`, erreurs).
- `MockMatrixSession` : `profile`, `account` (paramètres d'initialiseur à valeur par défaut).
- `SampleData` : `userProfile(...)`, `readReceipt(...)`, et `message(...)` gagne `readReceipts:` et
  `senderAvatar:` à valeurs par défaut.

## 11. Documentation et livraison

- **DocC :** article *Read receipts and typing* (marquer comme lu au bon moment, afficher « vu
  par » avec la règle du dernier message lu, indicateur de frappe) ; article *Profile and account*
  (profil, avatar via `MediaService`, présence et son état initial `unavailable`, URL de gestion
  dans `ASWebAuthenticationSession`, ignorer un utilisateur, désactivation — Q1). *GettingStarted*
  et *TestingWithMocks* renvoient vers eux.
- **README :** section Scope réécrite pour la 0.6 ; « What v0.6 does not expose » : retirer
  « managing the account through the authorization server », ajouter l'observation de la présence,
  les galeries ; ligne `0.6.x | 26.09.07 | 18+ | 15+ | 6.2+` dans *Compatibility* ;
  `from: "0.6.0"` dans *Installation* ; feuille de route (0.6 livrée, galeries ajoutées à
  « Later »).
- **CHANGELOG `[0.6.0] - <date de livraison>` :** *Breaking* (§4.5), *Added*, *Behaviours to know*
  (présence initiale `unavailable` et non persistée, `setPresence` qui lève mais s'applique,
  accusé sur le dernier message lu seulement, pas d'observation du profil propre, `ignoredUsers`
  qui finit sans valeur, limitation de fréquence de la frappe constatée, désactivation
  irréversible).
- **Version :** `PackageInfo` 0.6.0.
- **CI :** inchangée (la suite d'intégration n'y tourne pas) — aucune tâche `[devops]`.

## 12. Risques

| Risque | Parade |
| --- | --- |
| L'amont inclut l'utilisateur courant dans les frappes ou les accusés | Filtrage par le package (user ID courant), testé en unitaire |
| L'accusé implicite de l'expéditeur apparaît sur son propre message | Constaté en T10, gardé tel quel et documenté (comportement amont) |
| Synapse du harnais avec présence désactivée | Défaut Synapse `presence.enabled: true` ; vérifier la config en T11, sinon l'activer (fichier du harnais) |
| UIAA de `deactivateAccount` différent du déroulé en deux temps | Constaté en T11 ; le test est la source de vérité |
| Le flux `ignoredUsers` ne reçoit pas l'écho d'un `ignore` local avant la sync | Le test attend une valeur dans un délai borné ; sinon re-lecture après `ignore` |
| Accusés en retard (sync) rendant le test instable | `firstValue` avec délai, comme les tests 0.5 |

## 13. Questions ouvertes

**Q1 (bloque T8 seulement) — Désactivation d'un compte à mot de passe en 0.6 ?** Irréversible,
touche le cycle de vie de la session (effacement conditionnel), et n'est utile que sur un serveur
*sans* MAS — où le package ne crée pas de compte (pas d'inscription par mot de passe), donc où la
règle App Store 5.1.1(v) ne l'impose pas directement ; les comptes MAS sont couverts par
`managementURL(for: .deactivateAccount)`. Défaut proposé : **inclure** (c'est le sens le plus
probable de « account » dans la feuille de route et l'API amont existe) ; si non, T8 sort, §4.4
perd `deactivate` et le critère 10 tombe.

Tout le reste est tranché en *décision de rédaction* : galeries hors périmètre, visibilité des
accusés exigée à chaque appel, accusé + marqueur en un appel, présence dans `ProfileService`, pas
de présence automatique, `AccountManagementAction` en struct, utilisateurs ignorés inclus, pas
d'observation du profil propre.

---

## 14. Découpage en tâches

Toutes `[ios]` (code Swift du SDK, tests, doc) ; aucune `[devops]` : la CI ne change pas. Comme en
0.5, les nouveaux membres de protocole ne deviennent **exigés** qu'en T9, pour que T3–T8 avancent
sans casser la compilation des doubles. Contraintes globales du plan 0.5 reconduites (pas d'import
amont dans `Core`, pas de `@MainActor`, flux d'instantanés `.bufferingNewest(1)`, `swift build` et
tests unitaires verts avant chaque commit, commits en français BLUF).

| Tâche | Rôle | Dépend de | Parallélisable avec | Fichiers principaux |
| --- | --- | --- | --- | --- |
| T1 Modèles du domaine | [ios] | — | — | `Core/Models/ReadReceipt.swift`, `ReadReceiptVisibility.swift`, `UserProfile.swift`, `Presence.swift`, `AccountManagementAction.swift`, `TimelineItem.swift` |
| T2 Protocoles `ProfileService` / `AccountService` et leurs doubles | [ios] | T1 | T3 | `Core/Services/ProfileService.swift`, `AccountService.swift`, `Mocks/MockProfileService.swift`, `MockAccountService.swift`, `Mocks/SampleData.swift` |
| T3 Accusés reçus et avatar de l'expéditeur dans la timeline Rust | [ios] | T1 | T2, T6, T7 | `Rust/Bridge/ReceiptMapper.swift`, `TimelineMapper.swift`, `RustTimeline.swift` (init), `RustRoomService.swift` (passage de l'user ID) |
| T4 Envoi d'accusés (`markAsRead`) | [ios] | T3 (même fichier `RustTimeline.swift`) | T6, T7, T8 | `RustTimeline.swift`, `ReceiptMapper.swift`, `Mocks/MockTimeline.swift` |
| T5 Frappe (`typingUsers`, `setTyping`) | [ios] | T1 ; après T3 (même fichier `RustRoomService.swift`) | T4, T6, T7, T8 | `RustRoomService.swift` (`RustRoomHandle`), `Rust/Bridge/TypingMapper.swift`, `Mocks/MockRoomService.swift` |
| T6 `RustProfileService` (profil, avatar, présence) | [ios] | T2 | T3, T4, T5, T7 | `Rust/RustProfileService.swift`, `Rust/Bridge/ProfileMapper.swift`, `ProfileDriving.swift` |
| T7 `RustAccountService` (URL de gestion, ignorés) | [ios] | T2 | T3, T4, T5, T6 | `Rust/RustAccountService.swift`, `Rust/Bridge/AccountDriving.swift`, `AccountMapper.swift` |
| T8 Désactivation du compte (Q1) | [ios] | T7 (même fichier) | T4, T5, T6 | `RustAccountService.swift`, `SessionLifecycle.swift` |
| T9 Exiger les nouveaux membres et câbler la session | [ios] | T4, T5, T6, T7, (T8) | — | `Core/Services/Timeline.swift`, `RoomService.swift`, `MatrixSession.swift`, `RustMatrixSession.swift`, `Mocks/MockMatrixSession.swift` |
| T10 Intégration : accusés et frappe | [ios] | T9 | T11, T12 | `Tests/MatrixClientKitIntegrationTests/RoomActivityHarnessTests.swift`, `HarnessSupport.swift` (seconde session) |
| T11 Intégration : profil, présence, compte, durée de vie | [ios] | T9 | T10, T12 | `Tests/MatrixClientKitIntegrationTests/ProfileAndAccountHarnessTests.swift`, `MediaHarnessTests.swift` (test de durée de vie) |
| T12 Documentation et version 0.6.0 | [ios] | T9 ; finalisée après T10 et T11 (*Behaviours to know*) | T10, T11 | `Documentation.docc/*.md`, `README.md`, `CHANGELOG.md`, `Core/PackageInfo.swift` |

Chemin critique : T1 → T2 → T6/T7 → T9 → T10/T11 → T12. Deux pistes parallèles après T1 :
*timeline* (T3 → T4, T3 → T5) et *services* (T2 → T6, T2 → T7 → T8).

**Conflit de fichier signalé :** `HarnessSupport.swift` peut être touché par T10 (aide « seconde
session ») et T11 (création d'un compte jetable par l'API admin). Le premier qui fusionne pose
l'aide ; l'autre rebase — ou T10 la pose et T11 en dépend pour ce seul fichier.

### T1 — Modèles du domaine `[ios]`

Créer `ReadReceipt`, `ReadReceiptVisibility`, `UserProfile`, `Presence`, `AccountManagementAction`
(§4.1, §4.3, §4.4) ; `Message.readReceipts` (défaut `[]`) et `Message.senderAvatar` (défaut `nil`)
en fin d'initialiseur.
**Acceptation :** les signatures sont exactement celles du §4 ; `AccountManagementAction` égal par
valeur (`.device(id)` == `.device(id)`) ; tout appel existant à `Message.init` compile sans
changement ; tests `Core` (égalité, `Hashable`) verts.

### T2 — Protocoles et doubles des services `[ios]`

`ProfileService`, `AccountService` (§4.3, §4.4, `deactivate` inclus sous réserve de Q1) ;
`MockProfileService`, `MockAccountService` (§10) ; `SampleData.userProfile`, `readReceipt`,
`message(readReceipts:senderAvatar:)`. **Pas encore** de membre exigé sur `MatrixSession`.
**Acceptation :** chaque membre des doubles enregistre ses appels et rend la valeur ou l'erreur
configurée (tests `MockTests`) ; `ignoredUsers` du double émet ce que pousse `emitIgnoredUsers` ;
aucun import amont dans `Core` ni `Mocks`.

### T3 — Accusés reçus et avatar de l'expéditeur `[ios]`

`ReceiptMapper.receipts(from: [String: Receipt], excluding ownUserID:)` ; `TimelineMapper` remplit
`readReceipts` et `senderAvatar` ; `RustTimeline` reçoit l'user ID courant (`Room.ownUserId()`)
depuis `RustRoomHandle.timeline()`.
**Acceptation :** tests unitaires : utilisateur courant exclu, tri récent d'abord puis `UserID`,
horodatage absent en dernier, user ID invalide écarté, millisecondes → `Date` ; `senderAvatar`
depuis `.ready(avatarUrl: "mxc://…")`, `nil` pour `.pending`/`.unavailable`/`.error` ou une URL
non `mxc`.

### T4 — Envoi d'accusés `[ios]`

`RustTimeline.markAsRead(visibility:)` et `markAsRead(upTo:visibility:)` (accusé puis
`fullyRead`, §4.1) ; membres correspondants de `MockTimeline`.
**Acceptation :** via une couture de test : `.public` → `.read`, `.private` → `.readPrivate`,
toujours suivi de `.fullyRead` sur la même cible ; un échec du premier appel empêche le second et
remonte mappé ; doubles testés.

### T5 — Frappe `[ios]`

`RustRoomHandle.typingUsers` (FFIStream sur `subscribeToTypingNotifications`, `.bufferingNewest(1)`)
et `setTyping(_:)` ; `TypingMapper` (user IDs valides, utilisateur courant exclu) ;
`MockRoomHandle.emitTypingUsers`, `typingNotices`.
**Acceptation :** tests unitaires du mapper ; sortir d'une boucle `for await` annule le `TaskHandle`
(test sur le modèle de `FFIStreamTests`) ; doubles testés.

### T6 — `RustProfileService` `[ios]`

`profile(of:)` (`getProfile`, `.notFound` remappé en `.notFound(.user)`), `setDisplayName`,
`setAvatar` (`uploadAvatar`), `removeAvatar`, `setPresence` (`immediate: true`) ; `ProfileMapper` ;
couture `ProfileDriving` ; `ClientLifetime` retenue.
**Acceptation :** tests unitaires sur la couture : chaque appel atteint l'amont avec les bons
arguments ; `Presence` ↔ `PresenceState` dans les deux sens exhaustif ; `UserProfile` amont avec
avatar non `mxc` → `avatar == nil` ; user ID amont invalide → `.unexpected` ; `.notFound(.user)`.

### T7 — `RustAccountService` : URL de gestion et ignorés `[ios]`

`managementURL(for:)` (`.overview` → `action: nil`, URL invalide → `.unexpected`), `ignoredUsers`
(lecture initiale puis listener ; échec initial → flux terminé sans valeur), `ignore`, `unignore` ;
couture `AccountDriving`.
**Acceptation :** tests unitaires : chaque `AccountManagementAction` → l'action amont attendue ;
`nil` amont → `nil` ; séquence initiale + mises à jour ; fin sans valeur sur échec ; annulation du
`TaskHandle` à la sortie de boucle.

### T8 — Désactivation du compte (Q1) `[ios]`

`deactivate(password:eraseData:)` : refus OAuth avant tout appel amont ; UIAA en deux temps ;
terminaison de `SessionLifecycle` qui n'efface qu'après succès serveur et publie `.signedOut`.
**Acceptation :** tests unitaires : session OAuth → `.unexpected`, zéro appel amont ; échec serveur
→ aucune donnée effacée, `authState` inchangé ; succès → effacement et `.signedOut` ; un `logout()`
concurrent ne double pas l'effacement (même arbitrage que les terminaisons existantes).

### T9 — Exiger les nouveaux membres et câbler la session `[ios]`

Déclarer les membres dans `Timeline`, `RoomHandle`, `MatrixSession` (docs `///` du §4) ;
`RustMatrixSession.make` construit `RustProfileService` et `RustAccountService` (avec la
`ClientLifetime` et, pour T8, le `SessionLifecycle`) ; `MockMatrixSession` gagne `profile` et
`account` avec valeurs par défaut.
**Acceptation :** `swift build` et tests unitaires verts ; aucune conformance du dépôt ne fournit un
membre par extension par défaut (les ruptures du §4.5 sont réelles et listées) ; la DocC des
protocoles compile sans lien cassé.

### T10 — Intégration : accusés et frappe `[ios]`

Critères 1 à 5 du §8, deux sessions SDK sur `synapse-password` (utilisateur du harnais et admin).
**Acceptation :** les cinq scénarios passent sur le harnais, ou l'écart constaté (accusé implicite
de l'expéditeur, filtrage amont, fréquence de frappe) est consigné dans un fichier de rulings 0.6 et
reporté à T12 ; exécution « non exécutée » consignée si Docker manque.

### T11 — Intégration : profil, présence, compte, durée de vie `[ios]`

Critères 6 à 11 du §8 : présence vérifiée par HTTP, profil, URL de gestion sur `synapse-oauth` +
MAS et `nil` sur `synapse-password`, ignorés, désactivation sur un compte jetable créé par l'API
admin (Q1), test de durée de vie étendu (§6).
**Acceptation :** scénarios verts ou écart consigné comme en T10 ; aucune modification du script de
harnais requise (sinon : la justifier dans les rulings).

### T12 — Documentation et version 0.6.0 `[ios]`

Articles DocC, README, CHANGELOG, `PackageInfo` (§11).
**Acceptation :** chaque membre public nouveau est documenté ; la génération DocC est sans
avertissement de lien (cf. correctif `17aee97`) ; le CHANGELOG suit Keep a Changelog avec
*Breaking*, *Added*, *Behaviours to know* reprenant les constats de T10/T11 ; le README ne promet
rien que l'amont n'expose pas (présence : publication seulement).
