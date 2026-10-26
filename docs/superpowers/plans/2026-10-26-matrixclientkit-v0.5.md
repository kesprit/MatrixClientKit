# MatrixClientKit 0.5 — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Médias reçus et téléchargeables, envoi de pièces jointes avec progression, handle d'envoi (annuler / relancer) retrouvable depuis la timeline, et fin du crash des objets FFI gardés après logout.

**Architecture:** Les modèles et protocoles vivent dans `MatrixClientKitCore` (jamais d'import amont) ; `MatrixClientKitRust` les implémente sur `matrix-rust-components-swift` 26.09.07, avec des mappers purs testables et des coutures `*Driving` pour les appels FFI. Les nouveaux membres de `Timeline` et `MatrixSession` ne deviennent exigés qu'à la tâche 8, une fois toutes les implémentations en place.

**Tech Stack:** Swift 6.2 (mode de langage 6), SwiftPM, Swift Testing, Matrix Rust SDK FFI, harnais Docker Synapse.

**Spec:** `docs/superpowers/specs/2026-10-26-matrixclientkit-v0.5-design.md` — elle fait autorité ; ce plan en découpe l'exécution.

## Global Constraints

- `MatrixClientKitCore` n'importe **jamais** `MatrixRustSDK` ; aucun type amont dans une signature `public`.
- Pas de `@MainActor` dans `Core` ni dans `Rust`.
- Flux de diffs en `.unbounded`, flux d'instantanés en `.bufferingNewest(1)`.
- Aucun nouveau cas de premier niveau dans `MatrixError` : une erreur nouvellement distinguable passe par `.unexpected(message:details:)`.
- Docs publiques (`///`) en anglais ; commentaires internes en français, densité comparable au code voisin.
- Amont épinglé inchangé : `26.09.07`.
- Avant chaque commit : `swift build` et `swift test --skip MatrixClientKitIntegrationTests` verts.
- Messages de commit en français, préfixes `feat:` / `fix:` / `test:` / `docs:`, BLUF ; trailer `Co-Authored-By:` nommant le modèle qui a réellement écrit le commit.
- Un type par fichier ; services dans `Services/`, modèles dans `Models/`, mappers dans `Bridge/`.

## Review Focus

1. **Pièce jointe dont la source n'est pas un fichier local** (`Attachment.Source.file` avec une URL `https://` ou un chemin absent) → `.notFound(.media)` sans appel amont — test en tâche 7.
2. **Dimensions de vignette nulles ou négatives** passées à `thumbnail(of:width:height:)` → ramenées à 1, jamais de crash de conversion `UInt64` — test en tâche 5.
3. **Forme d'onde hors de [0, 1]** dans `.voice(waveform:)` → valeurs bornées à [0, 1] avant l'amont — test en tâche 7.
4. **`MediaSource` décodée depuis un JSON persisté dont la représentation amont est absente ou corrompue** → reconstruction par l'URL si la source n'est pas chiffrée, `.unexpected` explicite si elle l'est (jamais de média chiffré demandé sans ses clés) — test en tâche 5.
5. **`cancel()` appelé deux fois, ou `waitUntilQueued()` appelé après `cancel()`** sur un `AttachmentUpload` → second `cancel()` sans effet, `waitUntilQueued()` lève `CancellationError` à chaque appel — test en tâche 7.

---

## Structure des fichiers

| Fichier | Rôle |
| --- | --- |
| `Core/Models/MediaSource.swift` | Source média opaque, `Codable`, `init?(url:)` |
| `Core/Models/MediaAttachment.swift` | Média reçu (+ `MediaDimensions` dans `Core/Models/MediaDimensions.swift`) |
| `Core/Models/UploadProgress.swift` | Progression d'envoi |
| `Core/Models/Attachment.swift` | Pièce jointe à envoyer |
| `Core/Models/TimelineItem.swift` | `Message.media`, `Message.uploadProgress` |
| `Core/Models/RoomSummary.swift` | `avatar: MediaSource?` |
| `Core/Services/MediaService.swift`, `MediaFile.swift`, `SendHandle.swift`, `AttachmentUpload.swift` | Protocoles |
| `Core/Services/Timeline.swift`, `MatrixSession.swift` | Nouveaux membres exigés (tâche 8) |
| `Rust/Bridge/MediaMapper.swift` | Sources, médias reçus, progression, pièces jointes → paramètres amont |
| `Rust/Bridge/ClientLifetime.swift` | Garde du `Client` FFI pour les dépendants (§5 de la spec) |
| `Rust/Bridge/MediaDriving.swift` | Couture des appels média du `Client` |
| `Rust/Bridge/SendHandleRegistry.swift` | Registre id d'élément → handle, générique et pur |
| `Rust/RustMediaService.swift`, `RustMediaFile.swift`, `RustSendHandle.swift`, `RustAttachmentUpload.swift` | Implémentations |
| `Mocks/MockMediaService.swift`, `MockMediaFile.swift`, `MockSendHandle.swift`, `MockAttachmentUpload.swift` | Doubles |
| `Tests/MatrixClientKitIntegrationTests/MediaHarnessTests.swift` | Intégration média et durée de vie |
| `Sources/MatrixClientKit/Documentation.docc/Media.md` | Article DocC |

(`Core` = `Sources/MatrixClientKitCore`, `Rust` = `Sources/MatrixClientKitRust`, `Mocks` = `Sources/MatrixClientKitMocks`.)

---

### Task 1: Modèles média du domaine

**Files:**
- Create: `Core/Models/MediaSource.swift`, `Core/Models/MediaDimensions.swift`, `Core/Models/MediaAttachment.swift`, `Core/Models/UploadProgress.swift`, `Core/Models/Attachment.swift`
- Modify: `Core/Models/TimelineItem.swift` (struct `Message`), `Core/Models/RoomSummary.swift`, `Core/Models/MessageContent.swift` (doc « v0.1 covers text; media arrives in v0.5 » → « Text messages; media is sent with ``Attachment`` »)
- Test: `Tests/MatrixClientKitCoreTests/MediaModelTests.swift`

**Interfaces:**
- Produces (exactement les déclarations de la spec §3.1–3.3) :
  - `public struct MediaSource: Sendable, Hashable, Codable` — `public let url: String`, `public let isEncrypted: Bool`, `package let upstreamJSON: String?`, `public init?(url: String)` (nil si le schéma n'est pas `mxc`, insensible à la casse ; `isEncrypted = false`, `upstreamJSON = nil`), `package init(url: String, isEncrypted: Bool, upstreamJSON: String?)`.
  - `public struct MediaDimensions: Sendable, Hashable, Codable` — `width`, `height` (`Int`), `public init(width:height:)`.
  - `public struct MediaAttachment: Sendable, Hashable` avec `Kind { image, video, audio, voice, file }` et les champs de la spec, initialiseur public memberwise (paramètres optionnels à défaut `nil`).
  - `public struct UploadProgress: Sendable, Hashable` — `completedBytes`, `totalBytes`, `fractionCompleted` (0 si `totalBytes <= 0`, sinon `min(1, max(0, Double(completed)/Double(total)))`), `public init(completedBytes:totalBytes:)`.
  - `public struct Attachment: Sendable, Hashable` avec `Source`, `Kind`, `Thumbnail` de la spec, `public init(source:kind:mimeType:caption: = nil, thumbnail: = nil)` ; `Thumbnail.init(source:mimeType:dimensions: = nil)`.
  - `Message` : `public let media: MediaAttachment?`, `public let uploadProgress: UploadProgress?` ; l'init existant gagne `media: MediaAttachment? = nil, uploadProgress: UploadProgress? = nil` en fin de liste.
  - `RoomSummary.avatar: MediaSource?` (calculé : `avatarURL.flatMap { MediaSource(url: $0.absoluteString) }`).

- [ ] **Step 1: Écrire les tests qui échouent** — `@Suite struct MediaModelTests` :
  - `mediaSourceAcceptsMxc` : `MediaSource(url: "mxc://example.org/abc")?.url == "mxc://example.org/abc"`, `isEncrypted == false`.
  - `mediaSourceRejectsOtherSchemes` : `MediaSource(url: "https://example.org/a") == nil`, `MediaSource(url: "") == nil`.
  - `mediaSourceRoundTripsThroughCodable` : encode/décode `MediaSource(url: "mxc://e/x", isEncrypted: true, upstreamJSON: "{\"k\":1}")` → égalité.
  - `uploadProgressFraction` : `(50, 200) → 0.25`, `(10, 0) → 0`, `(300, 200) → 1`.
  - `messageInitDefaultsMediaToNil` : `SampleData.message(...)` existant → `media == nil`, `uploadProgress == nil`.
  - `roomAvatarFromURL` : `avatarURL = URL(string: "mxc://e/a")` → `avatar?.url == "mxc://e/a"` ; `nil` → `nil`.
- [ ] **Step 2:** `swift test --filter MediaModelTests` → échec de compilation (types absents).
- [ ] **Step 3:** Implémenter les types ci-dessus, docs `///` reprises de la spec.
- [ ] **Step 4:** `swift test --filter MediaModelTests` → PASS ; `swift test --skip MatrixClientKitIntegrationTests` → PASS.
- [ ] **Step 5:** Commit `feat: modèles média du domaine (sources, pièces jointes, progression)`.

### Task 2: Protocoles média et d'envoi, et leurs doubles

**Files:**
- Create: `Core/Services/MediaService.swift`, `Core/Services/MediaFile.swift`, `Core/Services/SendHandle.swift`, `Core/Services/AttachmentUpload.swift` ; `Mocks/MockMediaService.swift`, `Mocks/MockMediaFile.swift`, `Mocks/MockSendHandle.swift`, `Mocks/MockAttachmentUpload.swift`
- Modify: `Mocks/MockTimeline.swift`, `Mocks/MockMatrixSession.swift`, `Mocks/SampleData.swift`
- Test: `Tests/MatrixClientKitCoreTests/MediaMockTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces: protocoles `MediaService`, `MediaFile`, `SendHandle`, `AttachmentUpload` exactement comme la spec §3.3–3.5. **Ne pas** encore ajouter de membres aux protocoles `Timeline` / `MatrixSession` (tâche 8) ; les doubles exposent déjà les membres concrets :
  - `MockSendHandle` (`final class`, `@unchecked Sendable`, verrou `NSLock` comme les autres doubles) : `cancelResult: Bool = true`, `cancelError: MatrixError?`, `retryError: MatrixError?`, `cancelCount: Int`, `retryCount: Int`.
  - `MockAttachmentUpload` : `cancelCount`, `waitError: MatrixError?`, `waitUntilQueued()` lève `CancellationError` si `cancelCount > 0`, sinon `waitError`, sinon rend la main.
  - `MockMediaService` : `contents: [MediaSource: Data]`, `error: MatrixError?`, `maxUploadSizeResult: Int = 50 * 1024 * 1024`, `thumbnailRequests: [(MediaSource, Int, Int)]` (exposé comme tableau de struct `ThumbnailRequest { source, width, height }`), `file(of:)` écrit le contenu dans un fichier temporaire et rend un `MockMediaFile` ; source absente de `contents` → `.notFound(.media)`.
  - `MockMediaFile(url:)` : `persist(to:)` déplace le fichier, rend `true`.
  - `MockTimeline` : `send(_ content:)` **inchangé ici** (son type de retour change en tâche 6, avec le protocole) ; `public var nextSendHandle: MockSendHandle` (un neuf par défaut), `public func send(_ attachment: Attachment) async throws -> any AttachmentUpload` (enregistre dans `sentAttachments`, lève `attachmentSendError`, rend `nextAttachmentUpload`), `public func sendHandle(for item: TimelineItem) -> (any SendHandle)?` (lit `sendHandles: [TimelineItem.ID: MockSendHandle]`).
  - `MockMatrixSession` : `public let media: any MediaService` (paramètre d'init `media: any MediaService = MockMediaService()`).
  - `SampleData.mediaSource(_ id: String = "media") -> MediaSource` (`mxc://example.org/<id>`), `SampleData.mediaAttachment(kind: = .image, ...) -> MediaAttachment`, `SampleData.imageMessage(...) -> Message`.

- [ ] **Step 1: Tests qui échouent** — `@Suite struct MediaMockTests` : `sendHandleCountsCalls` (cancel ×2, retry ×1 → compteurs 2/1, `cancelResult` rendu) ; `attachmentUploadCancelThenWaitThrowsCancellation` (deux appels à `waitUntilQueued()` lèvent tous deux `CancellationError`) ; `mediaServiceReturnsConfiguredContent` et `mediaServiceUnknownSourceIsNotFound` (`#expect(throws: MatrixError.notFound(.media))`) ; `mediaFileWritesAndPersists` ; `timelineRecordsAttachments` ; `timelineSendHandleLookup`.
- [ ] **Step 2:** `swift test --filter MediaMockTests` → échec de compilation.
- [ ] **Step 3:** Implémenter protocoles et doubles.
- [ ] **Step 4:** `swift test --filter MediaMockTests` → PASS ; suite unitaire complète → PASS (les appels existants `try await timeline.send(...)` des tests compilent grâce à `@discardableResult`).
- [ ] **Step 5:** Commit `feat: protocoles MediaService, SendHandle et AttachmentUpload, et leurs doubles`.

### Task 3: Médias reçus et progression dans la timeline Rust

**Files:**
- Create: `Rust/Bridge/MediaMapper.swift`
- Modify: `Rust/Bridge/TimelineMapper.swift` (`kind(from:)` renseigne `media` et `uploadProgress`), `Rust/RustMatrixSession.swift` (`client.enableSendQueueUploadProgress(enable: true)` dans `make`, avant la construction des services)
- Test: `Tests/MatrixClientKitRustTests/MediaMapperTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces (`enum MediaMapper`, interne) :
  - `static func source(from source: MatrixRustSDK.MediaSource) -> MatrixClientKitCore.MediaSource` — `url: source.url()`, `upstreamJSON: source.toJson()`, `isEncrypted` = le JSON contient une clé `file` de premier niveau (forme Matrix d'une source chiffrée : `{"file": {...}}` vs `{"url": ...}`) — décoder avec `JSONSerialization`.
  - `static func upstreamSource(from source: MatrixClientKitCore.MediaSource) throws -> MatrixRustSDK.MediaSource` — `fromJson(upstreamJSON)` si présent et valide ; sinon, si `!isEncrypted`, `fromUrl(url)` ; sinon `MatrixError.unexpected(message: "The encrypted media source has lost its keys.", details: nil)`.
  - `static func attachment(from type: MessageType) -> MediaAttachment?` — mappage de la spec §3.2 ; `nil` pour les types non média.
  - `static func uploadProgress(from state: EventSendState?) -> UploadProgress?` — `notSentYet(progress: p?)` → `UploadProgress(completedBytes: Int(clamping: p.progress.current), totalBytes: Int(clamping: p.progress.total))`, sinon `nil`.

- [ ] **Step 1: Tests qui échouent** — `MediaMapperTests` : construire les structs amont (`ImageMessageContent`, `ImageInfo`, …) et `MediaSource.fromUrl(url:)` (appel statique FFI, sans client) :
  - `imageMapsDimensionsSizeBlurhashAndThumbnail` : `ImageInfo(height: 480, width: 640, mimetype: "image/png", size: 1234, thumbnailInfo: nil, thumbnailSource: <mxc://e/t>, blurhash: "LEHV6n", isAnimated: nil)` → `kind == .image`, `dimensions == MediaDimensions(width: 640, height: 480)`, `size == 1234`, `thumbnail?.url == "mxc://e/t"`, `blurhash == "LEHV6n"`, `filename`, `caption` relayés.
  - `audioWithVoiceIsVoice` / `audioWithoutVoiceIsAudio` ; `videoDurationBecomesDuration` (`duration: 2.5` → `.milliseconds(2500)`) ; `fileMaps` ; `textIsNotMedia` → `nil`.
  - `hugeSizeIsClamped` : `size: UInt64.max` → `Int.max`.
  - `plainSourceIsNotEncrypted` : `fromUrl("mxc://e/a")` → `isEncrypted == false`, `upstreamJSON != nil`.
  - `encryptedSourceIsDetected` : `fromJson` d'un JSON `{"file":{"url":"mxc://e/a","key":{"kty":"oct","key_ops":["encrypt","decrypt"],"alg":"A256CTR","k":"qcHVMSgYg-71CauWBezXI5qkaRb0LuIy-Wx5kIaHMIA","ext":true},"iv":"X85+XgHN+HEAAAAAAAAAAA","hashes":{"sha256":"5qG4fFnbbVdlAB1Q72JDKwCagV6Dbkx9uds4rSak37c"},"v":"v2"}}` → `isEncrypted == true`, `url == "mxc://e/a"` (si `fromJson` refuse cette forme, consigner la forme que l'amont accepte et adapter le test, pas la règle).
  - `upstreamSourceFallsBackToURLWhenPlain` / `upstreamSourceRefusesEncryptedWithoutJSON` (`.unexpected`) / `upstreamSourceWithCorruptJSONFallsBackWhenPlain`.
  - `progressMaps` / `progressAbsentWhenSent`.
- [ ] **Step 2:** `swift test --filter MediaMapperTests` → échec.
- [ ] **Step 3:** Implémenter `MediaMapper` ; dans `TimelineMapper.kind(from:)`, passer `media: MediaMapper.attachment(from: message.msgType)` et `uploadProgress: MediaMapper.uploadProgress(from: event.localSendState)`. Activer la progression dans `make`.
- [ ] **Step 4:** Tests ciblés puis suite unitaire → PASS.
- [ ] **Step 5:** Commit `feat: médias reçus et progression d'envoi dans la timeline`.

### Task 4: Le `Client` FFI survit à ses dépendants

**Files:**
- Create: `Rust/Bridge/ClientLifetime.swift`
- Modify: `Rust/RustRoomService.swift` (`RustRoomService`, `RustRoomHandle`), `Rust/RustTimeline.swift`, `Rust/RustMatrixSession.swift` (passer le client aux services), et tout autre porteur d'un objet FFI dépendant du client que l'audit trouve (`RustSyncController`, `RustEncryptionService`, `RustNotificationService`, `RustSessionVerification`)
- Test: `Tests/MatrixClientKitRustTests/ClientLifetimeTests.swift`

**Interfaces:**
- Produces : `final class ClientLifetime: Sendable` — `init(client: AnyObject & Sendable)` (générique sur l'objet retenu pour être testable sans FFI) et `func release<T>(_ dependent: inout T?)` qui met `dependent` à `nil` à l'intérieur de `withExtendedLifetime(client)`. Chaque porteur garde `private let lifetime: ClientLifetime` et son objet FFI en `nonisolated(unsafe) private var` optionnel, libéré dans `deinit` par `lifetime.release(&…)`. Même justification que `RustMatrixSession.Dependents` (commentaire qui y renvoie). `RustMatrixSession` crée une seule `ClientLifetime` et la transmet ; `RustRoomHandle` et `RustTimeline` la reçoivent de leur parent.

- [ ] **Step 1: Test qui échoue** — `ClientLifetimeTests.dependentIsReleasedBeforeClient` : deux classes témoins qui enregistrent leur `deinit` dans un journal partagé ; le porteur libéré → journal `["dependent", "client"]`, quel que soit l'ordre d'abandon des références par le test (porteur gardé plus longtemps que la « session »).
- [ ] **Step 2:** `swift test --filter ClientLifetimeTests` → échec.
- [ ] **Step 3:** Implémenter et appliquer à chaque porteur trouvé par l'audit ; consigner la liste dans le message de commit.
- [ ] **Step 4:** Tests ciblés puis suite unitaire → PASS. (La preuve contre le vrai SDK est le test de durée de vie de la tâche 9.)
- [ ] **Step 5:** Commit `fix: le client FFI est libéré après les services et timelines gardés par l'application`.

### Task 5: Service média Rust

**Files:**
- Create: `Rust/Bridge/MediaDriving.swift`, `Rust/RustMediaService.swift`, `Rust/RustMediaFile.swift`
- Modify: `Rust/RustMatrixSession.swift` (`public var media: any MediaService` concret, dans `Dependents`)
- Test: `Tests/MatrixClientKitRustTests/MediaServiceTests.swift`

**Interfaces:**
- Consumes: Tasks 2, 3 (`MediaMapper.upstreamSource(from:)`), 4 (`ClientLifetime`).
- Produces :
  - `protocol MediaDriving: Sendable` — `getMediaContent(mediaSource:)`, `getMediaThumbnail(mediaSource:width:height:)`, `getMediaFile(mediaSource:filename:mimeType:useCache:tempDir:)`, `getMaxMediaUploadSize()` aux signatures amont exactes ; `extension Client: MediaDriving {}`. Le retour de `getMediaFile` est abstrait par `protocol MediaFileHandleDriving: Sendable { func path() throws -> String; func persist(path: String) throws -> Bool }`, `extension MediaFileHandle: MediaFileHandleDriving {}` (si l'adaptation du type de retour l'exige, le pilote rend `any MediaFileHandleDriving`).
  - `public final class RustMediaService: MediaService` — `init(driver: any MediaDriving, lifetime: ClientLifetime?)` interne.
  - `final class RustMediaFile: MediaFile` — retient le handle amont (le fichier vit tant qu'il vit).
  - Règles : largeur/hauteur `UInt64(max(1, value))` ; `useCache: true`, `tempDir: nil` ; erreurs passées par `ErrorMapper.map` puis `.notFound(.unspecified)` → `.notFound(.media)` ; `MatrixApi(kind: .tooLarge, …)` → `.unexpected(message: "The media is larger than the homeserver accepts.", details: …)` (ajouter ce cas dans `ErrorMapper` si plus simple, avec son test dans `ErrorMapperTests`) ; `maxUploadSize` par `Int(clamping:)`.

- [ ] **Step 1: Tests qui échouent** — pilote factice enregistrant ses appels : `contentPassesSource`, `thumbnailClampsNonPositiveDimensions` (`width: 0, height: -5` → `1, 1`), `notFoundBecomesMedia`, `tooLargeIsExplicitUnexpected`, `fileExposesPathAndPersists`, `maxUploadSizeClamps`, `encryptedSourceWithoutJSONFailsBeforeDriver` (aucun appel au pilote).
- [ ] **Step 2:** `swift test --filter MediaServiceTests` → échec.
- [ ] **Step 3:** Implémenter ; brancher dans `RustMatrixSession.make`.
- [ ] **Step 4:** Tests ciblés puis suite unitaire → PASS.
- [ ] **Step 5:** Commit `feat: service média (contenu, vignette, fichier, taille maximale)`.

### Task 6: Handle d'envoi et registre de la timeline

**Files:**
- Create: `Rust/Bridge/SendHandleRegistry.swift`, `Rust/RustSendHandle.swift`
- Modify: `Rust/RustTimeline.swift` (`send(_ content:)` rend `any SendHandle` ; `sendHandle(for:)` ; registre alimenté dans le listener), `Core/Services/Timeline.swift` (**seul** changement de protocole de cette tâche : `@discardableResult func send(_ content: MessageContent) async throws -> any SendHandle`, sans quoi `RustTimeline` ne pourrait plus s'y conformer), `Mocks/MockTimeline.swift` (`send(_ content:)` rend `nextSendHandle`)
- Test: `Tests/MatrixClientKitRustTests/SendHandleRegistryTests.swift`, `Tests/MatrixClientKitRustTests/SendHandleTests.swift`

**Interfaces:**
- Consumes: Tasks 2, 4.
- Produces :
  - `final class SendHandleRegistry<Handle: Sendable>: Sendable` (verrou interne) — `func apply(_ changes: [Change])`, `func handle(for itemID: String) -> Handle?`, avec `enum Change { case track(itemID: String, Handle) ; case untrack(itemID: String) ; case removeAll }`. Pur, sans FFI.
  - Dans `RustTimeline`, pour chaque diff amont, une fonction `static func registryChanges(for diff: TimelineDiff) -> [SendHandleRegistry<…>.Change]` : élément événement dont `localSendState` est `notSentYet` ou `sendingFailed` et `lazyProvider.getSendHandle()` non nil → `track` ; élément `sent`, distant (`localSendState == nil`) → `untrack` ; `clear`/`reset` → `removeAll` (puis `track` des éléments de `reset`) ; `remove`/`truncate`/`pop*` → `untrack` impossible sans id : **tenir dans la timeline la liste ordonnée des ids** (appliquer les diffs à un tableau d'ids avec `CollectionDiffApplier` déjà présent dans Core) pour savoir lesquels sortent.
  - `final class RustSendHandle: SendHandle` — `init(handle: SendHandle, lifetime: ClientLifetime?)` ; `cancel()` → `abort(reason: nil)` ; `retry()` → `tryResend()` ; erreurs par `ErrorMapper`.
  - `RustTimeline.sendHandle(for item: TimelineItem) -> (any SendHandle)?` → `registry.handle(for: item.id).map(RustSendHandle.init)`.

- [ ] **Step 1: Tests qui échouent** — `SendHandleRegistryTests` (sur `String` comme `Handle`) : `trackThenLookup`, `untrackForgets`, `removeAllForgets`, `unknownIDIsNil`. `SendHandleTests` (pilote factice `SendHandleDriving` avec `abort(reason:)` / `tryResend()`) : `cancelAbortsWithoutReason`, `cancelReturnsUpstreamResult`, `retryResends`, `errorsAreMapped`. Plus un test du suivi des ids sur une séquence `append([a, b]) → remove(0) → reset([c])` qui vérifie que `a` sort du registre.
- [ ] **Step 2:** Tests ciblés → échec.
- [ ] **Step 3:** Implémenter ; garder le comportement existant du flux `items` intact (le registre est alimenté dans le même listener, pour chaque souscription ; une seule instance de registre par `RustTimeline`).
- [ ] **Step 4:** Tests ciblés puis suite unitaire → PASS.
- [ ] **Step 5:** Commit `feat: handle d'envoi, retrouvé depuis un élément de timeline`.

### Task 7: Envoi de pièces jointes

**Files:**
- Create: `Rust/RustAttachmentUpload.swift`
- Modify: `Rust/Bridge/MediaMapper.swift` (côté envoi), `Rust/RustTimeline.swift` (`send(_ attachment:)`)
- Test: `Tests/MatrixClientKitRustTests/AttachmentMapperTests.swift`, `Tests/MatrixClientKitRustTests/AttachmentUploadTests.swift`

**Interfaces:**
- Consumes: Tasks 1, 2, 4, 6.
- Produces :
  - `static func uploadRequest(for attachment: Attachment, fileManager: FileManager = .default) throws -> UploadRequest` dans `MediaMapper`, où `enum UploadRequest { case image(UploadParameters, thumbnail: UploadSource?, ImageInfo) ; case video(UploadParameters, thumbnail: UploadSource?, VideoInfo) ; case audio(UploadParameters, AudioInfo) ; case voice(UploadParameters, AudioInfo, waveform: [Float]) ; case file(UploadParameters, FileInfo) }`. Règles : `.file(url)` exige `url.isFileURL` et un fichier existant lisible, sinon `.notFound(.media)` ; source `.file` → `UploadSource.file(filename: url.path)`, `.data` → `.data(bytes:filename:)` ; `size` = attribut `.size` du fichier ou `data.count` ; vignette → `UploadSource` + `ThumbnailInfo(height:width:mimetype:size:)` dans l'info (ignorée pour audio/voix) ; durées en secondes `TimeInterval` ; forme d'onde bornée à `[0, 1]` ; `caption` → `UploadParameters.caption`, autres champs nil.
  - `protocol AttachmentSending: Sendable` (couture) — les cinq `send*` amont ; `extension MatrixRustSDK.Timeline: AttachmentSending {}`.
  - `final class RustAttachmentUpload: AttachmentUpload` — enveloppe `SendAttachmentJoinHandle` (couture `JoinHandleDriving { cancel(); join() async throws }`) ; `cancel()` idempotent, marque l'annulation sous verrou puis appelle l'amont une seule fois ; `waitUntilQueued()` : si annulé → `CancellationError` ; sinon `join()` puis, si annulé entre-temps → `CancellationError` ; erreurs par `ErrorMapper`.

- [ ] **Step 1: Tests qui échouent** — `AttachmentMapperTests` : `imageFromFileReadsSize` (fichier temporaire de 10 octets → `size == 10`, `UploadSource.file(filename: path)`), `imageFromDataUsesCount`, `thumbnailInfoIsFilled`, `audioIgnoresThumbnail`, `voiceWaveformIsClamped` (`[-1, 0.5, 2]` → `[0, 0.5, 1]`), `missingFileIsNotFound`, `remoteURLIsNotFound` (`https://example.org/a.png`), `captionIsPassed`. `AttachmentUploadTests` : `cancelTwiceCallsUpstreamOnce`, `waitAfterCancelThrowsCancellationEveryTime`, `waitJoinsUpstream`, `joinErrorIsMapped`.
- [ ] **Step 2:** Tests ciblés → échec.
- [ ] **Step 3:** Implémenter ; `RustTimeline.send(_ attachment:)` construit la requête (hors verrou, `async`), appelle l'amont, enveloppe le handle.
- [ ] **Step 4:** Tests ciblés puis suite unitaire → PASS.
- [ ] **Step 5:** Commit `feat: envoi de pièces jointes (image, vidéo, audio, vocal, fichier)`.

### Task 8: Exiger les nouveaux membres de `Timeline` et `MatrixSession`

**Files:**
- Modify: `Core/Services/Timeline.swift`, `Core/Services/MatrixSession.swift` ; toute conformance de test ou de cible qui ne compile plus
- Test: `Tests/MatrixClientKitCoreTests/MediaMockTests.swift` (un test qui passe par `any Timeline` et `any MatrixSession`)

**Interfaces:**
- Produces : `Timeline` exige (en plus du `send(_ content:)` → `any SendHandle` de la tâche 6) `func send(_ attachment: Attachment) async throws -> any AttachmentUpload`, `func sendHandle(for item: TimelineItem) -> (any SendHandle)?` ; `MatrixSession` exige `var media: any MediaService { get }`. Docs `///` de la spec (§3.3, §3.4, §3.5), y compris la conséquence documentée du registre.

- [ ] **Step 1: Test qui échoue** — `existentialTimelineExposesMediaMembers` : `let timeline: any Timeline = MockTimeline()` puis `try await timeline.send(SampleData.imageAttachment())` et `timeline.sendHandle(for:)` ; `let session: any MatrixSession = MockMatrixSession(...)` puis `session.media`. (Ajouter `SampleData.imageAttachment()` si absent.)
- [ ] **Step 2:** Compilation → échec.
- [ ] **Step 3:** Ajouter les exigences ; corriger les conformances.
- [ ] **Step 4:** `swift build` et suite unitaire → PASS.
- [ ] **Step 5:** Commit `feat!: Timeline et MatrixSession exigent les médias et le handle d'envoi`.

### Task 9: Intégration contre le harnais Synapse

**Files:**
- Create: `Tests/MatrixClientKitIntegrationTests/MediaHarnessTests.swift`, ressources de test générées dans le code (PNG minimal construit en mémoire, pas de fichier binaire versionné)
- Modify: `Tests/MatrixClientKitIntegrationTests/HarnessSupport.swift` (`createRoom(on:user:password:encrypted:)` si une room non chiffrée est nécessaire ; garder `createEncryptedRoom`)

**Interfaces:**
- Consumes: tout ce qui précède, via l'API publique (`Matrix.client`, `login`, `rooms.room`, `timeline()`, `media`).

- [ ] **Step 1:** Écrire `extension HarnessTests { @Suite(.serialized, .enabled(if: HarnessConfiguration.isAvailable)) struct Media { … } }` sur le modèle d'`AuthenticationHarnessTests`, chaque test `@Test(.timeLimit(.minutes(2)))`, avec les scénarios de la spec §7.2 : `imageRoundTripsInPlainRoom`, `imageRoundTripsInEncryptedRoom` (octets identiques après `content(of:)` ; `media?.isEncrypted == true`), `thumbnailAndFileAreServed`, `dataFileAudioAndVoiceKeepTheirKind`, `cancelledUploadIsConsistent`, `cancelledTextIsConsistent`, `sendHandleLookupForLocalEcho` (accepte `nil` si l'écho est déjà envoyé au moment de la lecture, mais exige `nil` pour un élément distant), `maxUploadSizeIsPositive`, `servicesKeptAfterLogoutDoNotCrash` (§5 de la spec : garder timeline, handle de room, `media`, `rooms`, `sync`, `encryption`, `notifications` ; `logout()` ; libérer la session ; attendre 1 s ; libérer le reste ; attendre 1 s).
- [ ] **Step 2:** `swift build --build-tests` → compile.
- [ ] **Step 3:** Si Docker répond : `Scripts/integration-harness.sh up`, puis `eval "$(Scripts/integration-harness.sh env)" && swift test --filter 'MatrixClientKitIntegrationTests\.HarnessTests\.Media'` → PASS ; puis toute la suite `HarnessTests` (non-régression) ; `Scripts/integration-harness.sh down`. Corriger le code (pas les attentes de la spec) en cas d'échec, chaque correctif dans un commit `fix:` séparé. Si Docker est indisponible : consigner « non exécuté » dans le rapport.
- [ ] **Step 4:** Commit `test: intégration des médias et de la durée de vie contre Synapse`.

### Task 10: Documentation et version 0.5.0

**Files:**
- Create: `Sources/MatrixClientKit/Documentation.docc/Media.md`
- Modify: la page racine DocC et *GettingStarted* (lien), `README.md` (Scope, installation `from: "0.5.0"`, compatibilité `0.5.x | 26.09.07 | 18+ | 15+ | 6.2+`, feuille de route), `CHANGELOG.md` (`## [0.5.0] - <date du jour>` : *Breaking*, *Added*, *Fixed*, *Behaviours to know* — même ton que 0.4.0, sans nom d'hôte personnel), `Core/PackageInfo.swift` (`0.5.0`), `Tests/MatrixClientKitCoreTests/PackageInfoTests.swift`

- [ ] **Step 1:** Article *Media* : afficher une image reçue (vignette puis contenu, blurhash en attendant), envoyer une pièce jointe avec progression, annuler, réessayer ou abandonner un envoi en échec avec `sendHandle(for:)`, garder un fichier (`persist(to:)`). Extraits qui compilent contre l'API réelle (les vérifier dans un test ou un fichier de scratch compilé).
- [ ] **Step 2:** README, CHANGELOG (y compris le *Fixed* de la tâche 4, qui remplace la « Known limitation » de 0.4.0), version.
- [ ] **Step 3:** `swift build`, suite unitaire, et `swift package generate-documentation` si le plugin est disponible (sinon `xcodebuild docbuild` ou consigner) → sans avertissement nouveau.
- [ ] **Step 4:** Commit `docs: médias dans la DocC, le README et le CHANGELOG ; version 0.5.0`.
