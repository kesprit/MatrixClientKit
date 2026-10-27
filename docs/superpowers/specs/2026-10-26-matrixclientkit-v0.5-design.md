# MatrixClientKit 0.5 — Design

**Date :** 2026-10-26
**Statut :** rédigé sans séance de questions (l'auteur a demandé un déroulé d'une traite) ; chaque
arbitrage non tranché par la feuille de route est marqué *décision de rédaction*
**Auteur :** Kevin Esprit
**Entrées :** README (feuille de route : « 0.5 — Media and send handle ») ; CHANGELOG 0.4.0
(limitation connue sur les services et timelines gardés après logout) ; rulings 0.4
**Amont :** `matrix-rust-components-swift` `26.09.07` (inchangé)

---

## 1. Objectif et périmètre

Objectif : qu'une application puisse **afficher** les médias d'une conversation (images, vidéos,
sons, fichiers, chiffrés ou non), **en envoyer** depuis un fichier local en suivant la progression,
et **piloter un envoi** — l'annuler tant qu'il n'est pas parti, le relancer après un échec — y
compris pour un message déjà affiché en écho local dont l'application n'a plus le handle.

| Inclus | Exclu (et palier) |
| --- | --- |
| Envoi d'image, vidéo, audio, message vocal, fichier, avec légende et vignette fournie | Génération de vignette, de blurhash ou de forme d'onde par le package (à la charge de l'application) |
| Progression de l'envoi d'un média dans l'écho local | Galeries (`sendGallery`) — 0.6 ou plus tard |
| Handle d'envoi : annuler, relancer ; retrouvé depuis un élément de timeline | Réponses, éditions, réactions, rédaction d'un événement envoyé — plus tard |
| Médias reçus décrits dans `Message` (type, source, nom, légende, taille, dimensions, durée, vignette, blurhash) | Stickers, localisation, sondages : restent `.unsupported` |
| `MatrixSession.media` : contenu, vignette, fichier temporaire, taille maximale d'envoi | Politique d'aperçu des médias (`MediaPreviews`), scanner de contenu |
| Source média de l'avatar d'une room | Avatars des utilisateurs (profil, 0.6) |
| Correctif : un service ou une timeline gardé après logout ne fait plus planter le processus | Montée de l'amont |

## 2. Constats amont (release `26.09.07`)

1. **Envoi de média.** `Timeline.sendImage(params:thumbnailSource:imageInfo:)`, `sendVideo`,
   `sendAudio`, `sendVoiceMessage(params:audioInfo:waveform:)` et `sendFile(params:fileInfo:)` sont
   **synchrones** (`throws`) et rendent un `SendAttachmentJoinHandle` (`cancel()`, `join() async
   throws`). `UploadParameters` porte `source: UploadSource` (`.file(filename:)` ou
   `.data(bytes:filename:)`), `caption`, `formattedCaption`, `mentions`, `inReplyTo`,
   `extraContentJson`.
2. **Infos d'envoi.** `ImageInfo` / `VideoInfo` (hauteur, largeur, type MIME, taille, `ThumbnailInfo`,
   blurhash ; durée pour la vidéo), `AudioInfo` (durée, taille, MIME), `FileInfo` (MIME, taille,
   vignette). La vignette envoyée est un `UploadSource` séparé.
3. **Handle d'envoi.** `Timeline.send(msg:)` rend un `SendHandle` : `abort(reason:) async throws ->
   Bool` (vrai si l'événement n'était pas encore parti ; sans effet après le premier appel) et
   `tryResend() async throws`. Pour un écho local déjà affiché, le handle s'obtient par
   `EventTimelineItem.lazyProvider.getSendHandle()`.
4. **Progression.** `EventSendState.notSentYet(progress: MediaUploadProgress?)` ; `MediaUploadProgress`
   = `index` + `AbstractProgress(current, total)`. N'est renseignée qu'après
   `Client.enableSendQueueUploadProgress(enable: true)`.
5. **Médias reçus.** `MessageType.image/video/audio/file(content:)` : `filename`, `caption`,
   `formattedCaption`, `source: MediaSource`, `info` ; l'audio porte `voice` (non nil pour un
   message vocal). `MediaSource` est un objet FFI opaque : `url()`, `toJson()`, et les
   constructeurs `fromUrl(url:)` / `fromJson(json:)`. Une source chiffrée embarque ses clés dans son
   JSON.
6. **Téléchargement.** `Client.getMediaContent(mediaSource:) -> Data`,
   `getMediaThumbnail(mediaSource:width:height:) -> Data`,
   `getMediaFile(mediaSource:filename:mimeType:useCache:tempDir:) -> MediaFileHandle` (`path()`,
   `persist(path:) -> Bool`), `getMaxMediaUploadSize() -> UInt64`. Le déchiffrement est fait par
   l'amont.
7. **Durée de vie.** Le crash corrigé en 0.4 (« there is no reactor running ») tient à ce que le
   dernier `Arc<ClientInner>` tombe hors du runtime Tokio. Un `RoomListService`, une `Room` ou une
   `Timeline` FFI retiennent ce client interne ; seul le `Drop` du `Client` FFI entre dans le
   runtime. Une timeline gardée par l'application après la libération de la session devient donc
   le dernier détenteur.

## 3. API publique

### 3.1 Source média

```swift
/// Where a media lives on the homeserver. Opaque: pass it back to ``MediaService``.
public struct MediaSource: Sendable, Hashable, Codable {
    /// The `mxc://` URL of the media.
    public let url: String
    /// True when the media is end-to-end encrypted; the keys travel with the source.
    public let isEncrypted: Bool
    /// Builds a source from an `mxc://` URL (an avatar, for instance). `nil` for any other scheme.
    public init?(url: String)
}
```

La représentation amont (JSON) est gardée dans un champ `package`, non public, qui sert à
reconstruire la `MediaSource` FFI sans perte (clés de chiffrement comprises). `Codable` permet à
une application d'en faire une clé de cache persistante. *Décision de rédaction :* `url` reste une
`String` (une URL `mxc://` n'a pas d'usage comme `URL` Foundation).

*Révision (revue finale) :* l'encodage `Codable` d'une source chiffrée contient sa clé, son IV et
ses empreintes : la DocC le signale (donnée sensible à stocker comme telle). `description`,
`debugDescription` et le miroir (`dump`, débogueur) ne montrent que `url` et `isEncrypted` ; les
`CodingKeys` sont explicites pour figer le format (`url`, `isEncrypted`, `upstreamJSON`).

`RoomSummary` gagne `public var avatar: MediaSource?`, calculé depuis `avatarURL`.

### 3.2 Médias reçus

```swift
public struct MediaDimensions: Sendable, Hashable { public let width: Int; public let height: Int }

public struct MediaAttachment: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case image, video, audio, voice, file }
    public let kind: Kind
    public let source: MediaSource
    public let filename: String
    public let caption: String?
    public let mimeType: String?
    public let size: Int?
    public let dimensions: MediaDimensions?
    public let duration: Duration?
    public let thumbnail: MediaSource?
    public let blurhash: String?
}
```

`Message` gagne `public let media: MediaAttachment?` (nil pour un texte) et
`public let uploadProgress: UploadProgress?` (nil sauf pendant l'envoi d'un média depuis cet
appareil). `Message.body` reste le corps amont (légende ou nom de fichier pour un média).
L'initialiseur public prend ces deux paramètres **avec une valeur par défaut `nil`** : le code
existant qui construit des `Message` compile toujours.

```swift
public struct UploadProgress: Sendable, Hashable {
    public let completedBytes: Int
    public let totalBytes: Int
    /// Between 0 and 1; 0 when the total is unknown.
    public var fractionCompleted: Double { get }
}
```

Mappage : `MessageType.image` → `.image`, `.video` → `.video`, `.audio` avec `voice != nil` →
`.voice`, sinon `.audio`, `.file` → `.file`. Les autres types de message gardent leur rendu actuel
(texte). `size`, `width`, `height` (`UInt64`) sont ramenés dans `Int` par
`Int(clamping:)` ; une durée amont (`TimeInterval`) devient `Duration`.

### 3.3 Envoi d'une pièce jointe

```swift
public struct Attachment: Sendable, Hashable {
    public enum Source: Sendable, Hashable {
        /// A local file; it must stay in place until the upload ends.
        case file(URL)
        /// Bytes in memory, with the file name shown to recipients.
        case data(Data, filename: String)
    }
    public enum Kind: Sendable, Hashable {
        case image(dimensions: MediaDimensions?, blurhash: String?)
        case video(dimensions: MediaDimensions?, duration: Duration?, blurhash: String?)
        case audio(duration: Duration?)
        /// A voice message; `waveform` holds values between 0 and 1.
        case voice(duration: Duration?, waveform: [Float])
        case file
    }
    public struct Thumbnail: Sendable, Hashable {
        public var source: Source
        public var mimeType: String
        public var dimensions: MediaDimensions?
    }
    public var source: Source
    public var kind: Kind
    public var mimeType: String
    public var caption: String?
    /// Used for images and videos; ignored, without being read, for audio, voice messages and files.
    public var thumbnail: Thumbnail?
}
```

*Révision (revue finale) :* `sendFile` amont (26.09.07) ne prend pas de source de vignette ; une
vignette donnée pour `.file` était validée (fichier lu) puis jetée, et un fichier de vignette absent
faisait échouer l'envoi pour rien. Elle est désormais ignorée sans validation, comme pour l'audio et
le vocal ; seules l'image et la vidéo valident et envoient leur vignette.

`Timeline` gagne :

```swift
/// Sends a media. Its local echo appears in ``items`` at once, with ``Message/uploadProgress``.
func send(_ attachment: Attachment) async throws -> any AttachmentUpload
```

```swift
public protocol AttachmentUpload: Sendable {
    /// Stops the upload while it is being prepared, before it is queued. Once queued, cancel or
    /// retry it through ``Timeline/sendHandle(for:)`` on its local echo.
    func cancel()
    /// Returns once the media is in the send queue and its local echo is in ``Timeline/items``.
    /// Throws `CancellationError` if ``cancel()`` was called before that.
    func waitUntilQueued() async throws
}
```

*Révision (tâche 9, constat contre le SDK 26.09.07) :* le `SendAttachmentJoinHandle` amont rend
la main de `join()` dès la mise en file, pas à l'envoi, et son `cancel()` n'a plus d'effet ensuite.
D'où `waitUntilQueued()` (anciennement `waitUntilSent()`) ; l'annulation d'un média en file passe
par le handle d'envoi de son écho (§3.4).

La taille transmise dans les infos est lue sur le fichier (attributs) ou sur `Data.count`. Un
fichier introuvable lève `MatrixError.notFound(.media)` **avant** tout appel amont.
*Décision de rédaction :* `send(_ attachment:)` est `async` alors que l'amont est synchrone, pour
lire la taille du fichier hors du fil appelant et garder la liberté d'évoluer.

### 3.4 Handle d'envoi

```swift
public protocol SendHandle: Sendable {
    /// Cancels the send if the message has not left yet; the local echo is removed.
    /// Returns false when it was already sent. Only the first call has an effect.
    @discardableResult func cancel() async throws -> Bool
    /// Sends again a message whose send failed, once the cause is fixed.
    func retry() async throws
}
```

- `Timeline.send(_ content: MessageContent)` rend désormais `any SendHandle`
  (`@discardableResult`).
- `Timeline.sendHandle(for item: TimelineItem) -> (any SendHandle)?` : le handle de l'écho local
  porté par cet élément, `nil` pour un élément distant ou déjà envoyé. C'est le chemin des boutons
  « réessayer » / « abandonner » d'un message en échec, y compris pour un média ou après un
  relancement de l'application.

Implémentation de `sendHandle(for:)` : `RustTimeline` tient un registre `id d'élément → SendHandle`
alimenté au mappage des diffs (un élément dont `localSendState` est `notSentYet` ou
`sendingFailed`), et purgé quand l'élément passe à `sent`, est retiré ou que la timeline est
réinitialisée. *Conséquence documentée :* le registre ne connaît que les éléments qu'une
souscription à ``Timeline/items`` a vus passer — ce qui est toujours le cas d'un élément affiché.

### 3.5 Service média

```swift
public protocol MediaService: Sendable {
    /// The media's bytes, decrypted when needed.
    func content(of source: MediaSource) async throws -> Data
    /// A thumbnail generated by the homeserver, at least `width` × `height` when possible.
    func thumbnail(of source: MediaSource, width: Int, height: Int) async throws -> Data
    /// The media written to a temporary file, deleted when the returned value is released.
    func file(of source: MediaSource, filename: String?, mimeType: String) async throws -> any MediaFile
    /// The largest upload the homeserver accepts, in bytes.
    func maxUploadSize() async throws -> Int
}

public protocol MediaFile: Sendable {
    var url: URL { get }
    /// Moves the file to `destination`, so that it outlives this value. Returns false if it
    /// could not be kept.
    func persist(to destination: URL) throws -> Bool
}
```

`MatrixSession` gagne `var media: any MediaService { get }`. `useCache: true`, `tempDir: nil` côté
amont. Les dimensions de vignette négatives ou nulles sont ramenées à 1.

### 3.6 Changements cassants

- `Timeline` exige `send(_: Attachment)` et `sendHandle(for:)` ; `send(_: MessageContent)` change de
  type de retour (un appel existant compile, une conformance écrite par l'application non).
- `MatrixSession` exige `media`.
- Une application qui implémente ces protocoles doit les compléter ou utiliser les doubles.

## 4. Erreurs

| Situation | Erreur |
| --- | --- |
| Fichier local de la pièce jointe introuvable ou illisible | `.notFound(.media)` |
| Média absent du serveur (`M_NOT_FOUND`) | `.notFound(.media)` |
| Média trop gros (`M_TOO_LARGE`) | `.unexpected` avec un message explicite (règle de gel des cas) |
| Annulation d'un `AttachmentUpload` | `CancellationError` depuis `waitUntilQueued()` |
| Autres erreurs amont | `ErrorMapper` existant |

Un échec d'envoi après la mise en file reste visible dans l'écho local
(`SendState.failed(reason:isRecoverable:)`), comme pour le texte.

## 5. Durée de vie des objets FFI

Chaque objet Swift qui retient un objet FFI dépendant du client (`RustRoomService`,
`RustRoomHandle`, `RustTimeline`, `RustMediaService`, handles d'envoi) retient aussi le `Client`
FFI, et libère son objet FFI explicitement dans son `deinit`, à l'intérieur de
`withExtendedLifetime(client)`. Le `Client` FFI est ainsi toujours le dernier détenteur du client
interne, quel que soit l'ordre dans lequel l'application lâche ses références. Même schéma que
`RustMatrixSession.Dependents`. À vérifier par l'implémenteur : les autres services de la session
(`sync`, `encryption`, `notifications`) qu'une application peut garder après la session.

Le correctif est **prouvé** par un test du harnais : ouvrir une timeline, garder la timeline, un
handle de room et le service média, faire `logout()`, libérer la session, puis libérer le reste —
le processus de test ne doit pas s'arrêter.

## 6. Architecture interne

- `Core` : `MediaSource`, `MediaAttachment`, `MediaDimensions`, `UploadProgress`, `Attachment` ;
  protocoles `MediaService`, `MediaFile`, `SendHandle`, `AttachmentUpload`. Jamais d'import de
  `MatrixRustSDK`.
- `Rust` : `MediaMapper` (sources, infos reçues, infos d'envoi, progression), `RustMediaService`,
  `RustMediaFile`, `RustSendHandle`, `RustAttachmentUpload`, registre des handles dans
  `RustTimeline`, et une couture de test (`package`) pour les pilotes amont, sur le modèle des
  `*Driving` existants.
- `RustMatrixSession.make` appelle `client.enableSendQueueUploadProgress(enable: true)`.

## 7. Tests

### 7.1 Unitaires (sans réseau)

- Mappage reçu : chaque `MessageType` média, voix vs audio, clamping des tailles, durées, vignette,
  source chiffrée (`isEncrypted`), `Codable` aller-retour de `MediaSource`, `MediaSource(url:)`
  refusant un schéma non `mxc`.
- Mappage envoi : chaque `Attachment.Kind` vers les infos amont, taille lue sur fichier et sur
  données, fichier absent → `.notFound(.media)` sans appel amont.
- Progression : `notSentYet(progress:)` → `uploadProgress`, total nul → fraction 0.
- Registre de handles : ajout, purge à `sent`, au retrait, au `reset`/`clear`.
- Doubles : chaque nouveau membre des mocks.

### 7.2 Intégration (harnais Synapse local, mot de passe)

- Envoi d'une image (fichier) avec vignette dans une room non chiffrée et dans une room chiffrée :
  l'écho local apparaît, passe à `sent`, l'élément porte `media` ; `content(of:)` rend les mêmes
  octets ; `thumbnail(of:)` rend des données ; `file(of:)` écrit un fichier lisible.
- Envoi d'un fichier depuis `Data`, d'un audio, d'un message vocal : le `kind` reçu correspond.
- `AttachmentUpload.cancel()` juste après l'envoi : `waitUntilQueued()` lève `CancellationError`
  ou l'envoi a déjà abouti — les deux issues sont acceptées, mais l'état final de la timeline doit
  correspondre.
- Média en file, pendant l'upload : `sendHandle(for:)` sur son écho puis `cancel()` — si `true`,
  l'écho disparaît et le média n'atteint jamais `sent` ; si `false`, il est envoyé.
- `SendHandle.cancel()` sur un texte : si `true`, l'écho disparaît ; si `false`, le message est
  envoyé.
- `sendHandle(for:)` rend un handle pour un écho local, `nil` pour un élément envoyé.
- `maxUploadSize()` > 0.
- Durée de vie (§5).

## 8. Mocks

`MockTimeline` : `sentAttachments`, `attachmentSendError`, `sendHandle(for:)` configurable,
`send(_:)` rend un `MockSendHandle`. Nouveaux : `MockSendHandle` (compteurs `cancelCount`,
`retryCount`, résultat et erreurs configurables), `MockAttachmentUpload`, `MockMediaService`
(contenus par source, erreur configurable), `MockMediaFile`. `MockMatrixSession.media`.
`SampleData` : `mediaSource()`, `mediaAttachment(...)`, `imageMessage(...)`.

## 9. Documentation et livraison

- **DocC :** article *Media* — afficher une image reçue (vignette puis contenu), envoyer une
  pièce jointe avec progression, annuler, réessayer un envoi en échec depuis la timeline.
  *GettingStarted* renvoie vers lui. Corriger « media arrives in v0.5 » dans `MessageContent`.
- **README :** Scope 0.5 ; compatibilité `0.5.x` ; feuille de route (0.5 livrée).
- **CHANGELOG 0.5.0 :** *Breaking*, *Added*, *Fixed* (durée de vie), *Behaviours to know*.
- **Version :** `PackageInfo` 0.5.0.

## 10. Risques

| Risque | Parade |
| --- | --- |
| La progression n'est jamais émise (upload trop rapide en local) | Le test d'intégration ne l'exige pas ; un test unitaire couvre le mappage |
| `getSendHandle()` rend nil pour un écho média | Constaté en intégration ; sinon documenté |
| Synapse refuse la vignette générée côté serveur pour un petit PNG | Le test vérifie seulement des données non vides, ou accepte `.notFound(.media)` documenté |
| Registre de handles qui grossit | Purge sur `sent`, retrait et réinitialisation |
| Docker indisponible sur la machine | Suite d'intégration écrite et compilée ; exécution consignée « non exécutée » |
