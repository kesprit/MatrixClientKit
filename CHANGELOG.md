# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versioning
follows [SemVer](https://semver.org/).

## [0.5.0] - 2026-10-26

### Breaking

- `Timeline` requires two new members, `send(_: Attachment)` and `sendHandle(for:)`, and
  `send(_: MessageContent)` now returns an `any SendHandle`. Both sends are marked
  `@discardableResult`, so most callers are unaffected; a closure whose type is spelled out, such
  as a `Task<Void, Error>` that ends with `try await timeline.send(...)`, must now discard the
  result (`_ = try await ...`). `MatrixSession` requires `media`. An application that implements these protocols
  itself — typically in a test double — must adapt, or use `MockTimeline` / `MockMatrixSession`.

### Added

- Received media: `Message.media` (a `MediaAttachment`: kind, file name, caption, MIME type, size,
  `MediaDimensions`, duration, thumbnail, blurhash) and `MediaSource`, an opaque, `Codable`
  reference to a media on the homeserver. Its `description`, `debugDescription` and reflection
  (`dump`, the debugger) show only the URL and whether the media is encrypted, never the keys. `RoomSummary.avatar` exposes a room's avatar as a
  `MediaSource`.
- `MatrixSession.media`, a `MediaService`: `content(of:)`, `thumbnail(of:width:height:)`,
  `file(of:filename:mimeType:)` (a `MediaFile` written to a temporary file, kept with
  `persist(to:)`) and `maxUploadSize()`.
- Sending media: `Attachment` (image, video, audio, voice message or file, from a local file or
  bytes, with an optional caption and, for an image or a video, a thumbnail) and `Timeline.send(_: Attachment)`, which returns an
  `AttachmentUpload` with `cancel()` and `waitUntilQueued()`. The local echo carries
  `Message.uploadProgress` (`UploadProgress`) while it uploads.
- `SendHandle` (`cancel()`, `retry()`), returned by `Timeline.send(_: MessageContent)` and found
  again from any local echo, media included, with `Timeline.sendHandle(for:)` — the path of the
  "retry" and "give up" buttons of a failed message.
- `MockMediaService`, `MockMediaFile`, `MockAttachmentUpload`, `MockSendHandle`, the new members of
  `MockTimeline` and `MockMatrixSession`, and `SampleData.mediaSource(_:)`,
  `SampleData.mediaAttachment(...)`, `SampleData.imageAttachment(...)` and
  `SampleData.imageMessage(...)`.
- The DocC article *Media*.

### Fixed

- A service, a room handle or a timeline that the application keeps after a logout, or after
  releasing its session, no longer crashes the process (a Rust panic, "there is no reactor
  running"): every object that depends on the FFI client now keeps it alive and frees its own
  upstream object first, so the client is always freed last, whatever order the application lets go
  of its references. This replaces the known limitation of 0.4.0.
- The room list could be freed while its upstream task was still running, which intermittently
  stopped the process (SIGSEGV) when a `rooms.list(filter:)` loop ended right after a value —
  including when the upstream SDK refused the filter. The object is now released only once the
  task has finished. The defect dates back to 0.1.

### Behaviours to know

- **`AttachmentUpload.cancel()` only stops the preparation.** Once the media is queued, cancel or
  retry it through `Timeline.sendHandle(for:)` on its local echo. A `cancel()` arriving right after
  queueing still makes `waitUntilQueued()` throw `CancellationError`, although the upload goes on.
- **`waitUntilQueued()` returns at queueing, not at delivery.** Follow the local echo's
  `Message.sendState` for the outcome. It may be called several times, concurrently too: every
  call reports the same outcome.
- **Releasing an `AttachmentUpload` cancels nothing**, and neither does cancelling the Swift task
  that awaits `waitUntilQueued()`: only `cancel()` stops the upload.
- **The `Codable` encoding of an encrypted `MediaSource` contains its decryption keys.** Store it
  as sensitive data, for instance when you use it as a cache key.
- **An `Attachment.thumbnail` is sent for images and videos only**; for audio, voice messages and
  files it is ignored, and its file is not even read.
- **`MediaFile.url` is stale once `persist(to:)` returned `true`**: the file is at the
  destination.
- **Attachment send failures reported by the upstream SDK** (invalid MIME type, invalid
  thumbnail…) surface as `MatrixError.unexpected` with the message "The attachment could not be
  sent." and the upstream detail.
- **`sendHandle(for:)` only knows the items that a subscription to `Timeline.items` has seen** —
  always true of a displayed item.
- **Thumbnails, blurhashes, durations and waveforms of the media you send are produced by your
  application.** The package neither decodes nor encodes media.
- **`RoomService.list` shows at most 50 rooms in this version.**
- **Upload progress relies on the upstream SDK's progress reporting**, which the package turns on
  for you. Send handles do not depend on it.

## [0.4.0] - 2026-10-03

### Breaking

- `MatrixClient` requires three new members: `loginDetails()`, `beginOAuthLogin(_:prompt:loginHint:)`
  and `loginWithQRCode(_:)`. `MatrixSession` requires two: `reauthenticate(_:)` and
  `beginOAuthReauthentication(_:)`. An application that implements these protocols itself —
  typically in a test double — must add them, or use `MockMatrixClient` / `MockMatrixSession`.
- `Credentials` gains the case `.email`: an exhaustive `switch` over `Credentials` no longer compiles.

### Added

- `Matrix.client(server:storage:)`: builds a client from a server name (`matrix.org`), a URL or a
  user ID, discovering the homeserver through its `.well-known` information.
- `MatrixClient.loginDetails()` and `LoginDetails`: whether the homeserver accepts a password,
  OAuth or legacy single sign-on (reported only), and which `OAuthPrompt`s it advertises.
- OAuth sign-in: `OAuthConfiguration`, `OAuthPrompt`, `OAuthLoginFlow` and
  `MatrixClient.beginOAuthLogin(_:prompt:loginHint:)`. The application presents the web page, for
  instance with `ASWebAuthenticationSession`.
- `Credentials.email(address:password:deviceName:)`.
- QR-code login in both directions — this device shows the code (`MatrixClient.loginWithQRCode(_:)`)
  or scans one (`Matrix.loginWithQRCode(scanned:configuration:storage:)`) — through `QRCodeLogin`,
  `QRCodeLoginState` and `QRCodeLoginFailure`. The returned session starts out verified.
- `MatrixSession.reauthenticate(_:)` and `MatrixSession.beginOAuthReauthentication(_:)`: sign in
  again on the same device after a soft logout, keeping its encryption keys. Both return a new
  session; the old one reports `.signedOut`.
- `MockOAuthLoginFlow`, `MockQRCodeLogin`, the new members of `MockMatrixClient` and
  `MockMatrixSession`, and `SampleData.loginDetails(...)` / `SampleData.oauthConfiguration()`.
- The DocC article *Authentication*.

### Changed

- Each session has its own local store. Sessions created by 0.1 to 0.3 keep the store they have
  and are never migrated.
- Orphaned stores are swept by the application — never by an extension — including those that
  signing in over another session left behind in 0.3.
- The cross-signing identity of an account that has none is created at sign-in, not at the next
  launch.
- `AuthState.softLoggedOut` and `.signedOut` document the new reauthentication.

### Fixed

- A failed read of the stored session during a token refresh no longer overwrites its store
  identifier.
- Only the most recent successful sign-in is saved for the next launch, and nothing else touches
  it any more: a token refresh of an older session still open in the process no longer overwrites
  it, and signing out such a session — or the homeserver ending it — no longer erases it. Either
  could sign the user out at the next launch and delete the local data of both sessions.
- `logout()`, or the homeserver ending the session, no longer waits forever on an OAuth
  reauthentication flow the application keeps without completing it: the flow is cancelled, then
  the sign-out proceeds.
- Reauthenticating with another account's credentials fails with
  `.authentication(.invalidCredentials)`, as documented, instead of `.unexpected`; the device the
  homeserver opened for that account is signed out.
- Cancelling a QR-code login right after the exchange with the other device signs the new device
  out instead of leaving it signed in on the homeserver.
- Two `OAuthConfiguration.staticRegistrations` URLs with the same string no longer crash the
  process.
- Releasing a session after it had signed out could crash the process (a Rust panic, "there is no
  reactor running"): the FFI client was freed before the objects that still held it. The defect
  dates back to 0.2 and 0.3. It is fixed for sessions, the notification resolver and the
  verification controller. Known limitation: a service or a timeline that the application keeps
  after a logout is not covered.

### Behaviours to know

- **QR-code login needs a capable granting device.** The signed-in device that grants the login
  must hold the account's cross-signing private keys: it is the device that created the identity,
  or one that recovered them. Otherwise the grant fails (`MissingSecretsBackup` upstream) and this
  device's login ends in `.failed(.unknown)`. A brand-new OAuth account does get its identity at
  its first sign-in.
- **Cancelling a QR-code login.** `start()` may return only when the exchange in progress with the
  other device ends; once the session is being built, `cancel()` has no effect.
- **OAuth flows are single-use.** After a failed `complete(callbackURL:)` or a `cancel()`, begin a
  new one.
- **Reauthentication.** On failure the old session stays `.softLoggedOut`, syncing still stopped.
  A second, concurrent reauthentication throws `.unexpected`.

### Not included

- Registering an account with a password, and legacy single sign-on (`loginDetails()` reports it).
- Granting a QR-code login from the signed-in device.
- Managing the account through the authorization server (Matrix Authentication Service).

### Verified

- Against a local Docker harness (`Tests/IntegrationHarness`), with Synapse v1.162.0: password and
  email sign-in, a soft logout (access token lifetime of 20 s), reauthentication with decryption of
  a message encrypted earlier, the refusal of another account's credentials, and the cleanup of
  local stores.
- Against Synapse v1.162.0 delegated to Matrix Authentication Service 1.26.0: `loginDetails()`,
  OAuth sign-in, single-use of a flow, its cancellation and the restoration of the session, and
  QR-code login in both directions, the new session being verified.
- **Not run for this release:** the suite against a real homeserver (Tuwunel),
  because its credentials were unavailable. It was only compiled. Server-name discovery against a
  real server's `.well-known` is therefore not exercised.

## [0.3.0] - 2026-09-28

### Breaking

- `MatrixSession` requires a new member, `notifications`. An application that implements the
  protocol itself — typically in a test double — must add it, or use `MockMatrixSession`.

### Added

- `MatrixSession.notifications`, a `NotificationService`: `registerPusher(_:)` and
  `unregisterPusher(_:)` with a `PusherConfiguration`, and per-room notification settings —
  `notificationSettings(for:)`, `setNotificationMode(_:for:)`, `restoreDefaultNotificationMode(for:)`.
- `MatrixNotificationResolver`, the notification service extension's entry point: resolves a push
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

### Verified

- Full push path exercised against a real homeserver (Tuwunel 1.8.1): the notification service
  extension resolving a message sent by another account while the application session is open on
  the same App Group storage, pusher registration and removal, per-room notification mode, and a
  store created without the cross-process lock (as by 0.2) restored with it from a separate
  process. A real APNs push through a gateway was not tested.

## [0.2.0] - 2026-09-18

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

- A cross-signing identity is created at sign-in, and on the first launch that restores a 0.1
  session, for accounts that have none, so that the device can be verified.
- `SyncController.start()` documents that calling it while syncing is running has no effect.
- `logout()` does nothing after `.signedOut`, and no longer throws the expected token error after
  `.softLoggedOut`. A `logout()` called while another is in progress waits for it.
- `login` builds the persistent client with the homeserver address the session reports, as resolved
  by the server, which every later restore also uses.

### Fixed

- `MatrixClient.restoreSession()` used the client's homeserver address instead of the one stored
  with the session.
- Every string that reaches an application is in English — `MatrixError.errorDescription`, send
  failure reasons, unsupported timeline items — and an undecryptable message now says why it could
  not be decrypted.

### Not included

- QR-code verification: the bundled Matrix Rust SDK (26.09.07) does not expose it.

## [0.1.1] - 2026-09-13

### Fixed

- Sessions refreshed by the SDK are now persisted. Automatic token refresh is on by default:
  without a session delegate a refreshed token lived only in memory, the stored session went stale
  in silence, and the user was signed out on the next launch without a single error being reported.
- The delegate refuses to hand back a session belonging to a user other than the one requested.

### Changed

- `SessionPersistence` is now a synchronous type. The underlying storage is already concurrency-safe,
  and the SDK calls its session delegate synchronously. No public API is affected.

## [0.1.0] - 2026-09-13

### Added

- Password authentication and restoration of a persisted session.
- App Group and Keychain storage, configured for extensions.
- Sync control and a sync-state stream.
- Observable room list, delivered as snapshots.
- Observable timeline, backward pagination and sending text messages.
- `MatrixError`, typed errors with `isRetryable` and `retryAfter`.
- The `MatrixClientKitMocks` product, for applications' own tests.
- Bundled Matrix Rust SDK: 26.09.07.

### Verified

- Full path exercised against a real homeserver (Tuwunel 1.8.1): login, sync, room list, sending a
  message and its local echo.
