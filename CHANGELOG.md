# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versioning
follows [SemVer](https://semver.org/).

## [0.6.1] - 2026-11-24

### Fixed

- `RoomHandle.typingUsers` could keep showing a member as typing forever. The SDK only relays the
  `m.typing` events found in a sync response, with no initial state and no expiry: when the empty
  list was lost — the application in the background, the device locked, the network cut — the last
  list stayed in the stream until the room was reopened. A non-empty list that receives no new value
  for 30 seconds now falls back to `[]`.

### Behaviours to know

- **A member typing without a pause for more than 30 seconds disappears from `typingUsers`** until
  they pause and start again. The homeserver sends a new `m.typing` only when the list changes, not
  when a member's client refreshes its typing notice, so a list that stays the same looks exactly
  like a list whose end was lost. A wrong "nobody is typing" lasts at most until the next change; a
  wrong "Hélène is typing" lasted forever.
- **A lost update is corrected late**: the list falls back to `[]` up to 30 seconds after the
  member stopped, not at once.
- `MockRoomHandle` has no such delay: it emits exactly what `emitTypingUsers(_:)` is given, so a
  test of your code stays instantaneous. Push `[]` to simulate the expiry.

## [0.6.0] - 2026-11-22

### Breaking

- On macOS, an unsigned executable (command-line tool, `swift test`) can no longer save a session:
  the data protection keychain needs a signature carrying `keychain-access-groups` (or an
  application identifier), otherwise writing throws `MatrixError.storage(.keychainFailure(status: -34018))`.
  Sign it with `keychain-access-groups`. iOS is not affected.
- `Timeline` requires two new members, `markAsRead(visibility:)` and
  `markAsRead(upTo:visibility:)`. `RoomHandle` requires `typingUsers: AsyncStream<[UserID]>` and
  `setTyping(_:)`. `MatrixSession` requires `profile: any ProfileService` and
  `account: any AccountService`. An application that implements these protocols itself —
  typically in a test double — must complete them, or use `MockTimeline` / `MockRoomHandle` /
  `MockMatrixSession`.
- Not breaking: `TimelineItem.readReceipts` and `Message.senderAvatar` come with default values
  in their initialisers, and so do the new `profile:` and `account:` parameters of
  `MockMatrixSession.init`.

### Added

- Internal product `_MatrixClientKitRust`, reserved for the integration tests and outside SemVer.
- Read receipts: `Timeline.markAsRead(visibility:)` marks the room as read up to its latest visible
  message, `Timeline.markAsRead(upTo:visibility:)` up to a given event, and both move the read
  marker as well. `ReadReceiptVisibility` chooses who can see the receipt, `.public` (`m.read`) or
  `.private` (`m.read.private`); it is required at every call.
- `TimelineItem.readReceipts` (`ReadReceipt`: `userID`, `timestamp`): the other members whose
  latest read item is this one, most recent first, the current user excluded. It is carried by
  every item that holds an event — a message, but also a membership change, a redacted or
  undecryptable event, a sticker or a poll — and is empty for a date separator, the read marker and
  the `.unsupported` items that stand for no event.
- Typing: `RoomHandle.typingUsers`, a stream of snapshots of the members typing in the room (the
  current user excluded), and `RoomHandle.setTyping(_:)`.
- `MatrixSession.profile`, a `ProfileService`: `profile(of:)` (a `UserProfile`: user ID, display
  name, avatar as a `MediaSource`), `setDisplayName(_:)`, `setAvatar(_:mimeType:)`,
  `removeAvatar()` and `setPresence(_:)` (`Presence`: `.online`, `.unavailable`, `.offline`).
- `Message.senderAvatar`: the sender's avatar, a `MediaSource` for `MediaService`.
- `MatrixSession.account`, an `AccountService`: `managementURL(for:)` (an `AccountManagementAction`
  — overview, profile, devices, one device, deleting a device, deactivating the account — on the
  authorization server of a homeserver that delegates its accounts — `https`, or `http` on a loopback
  host for local development — `nil` otherwise), `ignoredUsers`
  (a stream of snapshots), `ignore(_:)`, `unignore(_:)` and `deactivate(password:eraseData:)`.
- `MockProfileService`, `MockAccountService`, the new members of `MockTimeline`, `MockRoomHandle`
  and `MockMatrixSession`, and `SampleData.userProfile(...)`, `SampleData.readReceipt(...)` and
  the `senderAvatar:` parameter of `SampleData.message(...)`.
- The DocC article *Read receipts, typing, profile and account*.

### Fixed

- `MockRoomService.list(filter:)` opened after `finish()` stayed open forever, so a `for await` loop
  over it never returned. It now ends at once without any value, like the real service when its
  subscription fails.
- `RoomSummary.notificationCount` and `highlightCount` stayed at 0 with sliding sync: they now take
  the counters the SDK computes from the user's notification settings.
- A notification service extension on macOS was refused the session read
  (`CSSMERR_CSP_NO_USER_INTERACTION`): the keychain items now go in the data protection keychain,
  which an extension with another code identity can read through the shared access group.

### Changed

- `MockRoomHandle` is now a `final class`, not a `struct`: a test drives and inspects the very
  handle the code under test holds. `MockRoomService.room(_:)` returns the same handle for a given
  `RoomID`, and the new synchronous `MockRoomService.handle(for:)` gives it without awaiting.
- `MockRoomService.finish()` also ends the typing streams of its handles, and a typing
  subscription opened after it ends at once without any value, as the real services do when their
  subscription fails.
- `PackageInfo.version` is `0.6.0`.

### Behaviours to know

- **`markAsRead(visibility:)` resolves "the latest visible item" twice**, once for the receipt and
  once for the read marker. If an event arrives in between, they can land on two different items.
  Use `markAsRead(upTo:visibility:)` for one fixed target. If the receipt fails, the read marker is
  not attempted.
- **A read receipt sits only on the latest item a member read**, which is not necessarily a
  message. A member read a message `M` when their receipt is on `M` **or on any later item**. The
  package does not do that lookup for you.
- **The package publishes nothing by itself**: no receipt, no typing notice and no presence.
  The upstream SDK's initial presence, `unavailable`, is only what its sync requests carry.
- **The presence is publish-only and is not persisted.** Against Synapse, a user whose
  application has not called `setPresence(_:)` is reported `offline` by the server — not
  `unavailable` — and is so again at every launch: publish it each time the application starts.
  The state applies to the following syncs even when the call throws. **The server rate limits
  presence updates**: on Synapse, a second update in quick succession can wait about 10 seconds
  before it succeeds, the upstream SDK replaying the refusal itself. Do not call `setPresence(_:)`
  from a path that blocks the interface on the answer. `MatrixError.rateLimited` stays possible if
  the upstream SDK gives up, which was not observed. Observing other users' presence is not
  possible: the upstream SDK does not expose it.
- **The current user's profile is not observable**, and nothing is cached: every `profile(of:)`
  asks the homeserver. After `setDisplayName(_:)` — which does not validate the name — update your
  display yourself.
- **`ignoredUsers` ends without any value when reading the initial list fails**, like
  `RoomService.list(filter:)`.
- **`deactivate(password:eraseData:)` is irreversible, and refused in an OAuth session** before any
  server call: use `managementURL(for: .deactivateAccount)`. On success, the local erasure is best
  effort — an erasure error is not reported once the server has deactivated the account. On
  failure, nothing is erased and the session stays usable: a refused password throws
  `MatrixError.authentication` with `.invalidCredentials`, and a session that already ended throws
  `.unexpected`. A reported failure can match an account
  that was deactivated all the same (the network dropping after the server accepted the request):
  the next sync then fails with an unknown-token error and the hard logout erases the local data.
- **An unknown user in `profile(of:)` throws `MatrixError.notFound` with `.user`** — Synapse
  answers 404 `M_UNKNOWN` for it, which the package maps to that error.
- **After a deactivation, signing in to the account throws `.authentication(.invalidCredentials)`**
  against Synapse, which erases the password and does not answer `M_USER_DEACTIVATED`. A refused
  password in `deactivate(password:eraseData:)` throws the same error.
- **`managementURL(for:)` accepts `https`, and `http` only towards a loopback host** (`localhost`,
  `*.localhost`, `127.0.0.0/8`, `::1`), for local development: a local authorization server
  announces itself in `http`. Any other scheme or `http` host throws
  `MatrixError.unexpected`. A `*.localhost` host relies on the system resolving it locally, as
  RFC 6761 asks.
- **The sender of a message has an implicit receipt on it**: other members see the receipt of the
  author on their own message, before anyone reads it.
- **A member who joins has an implicit receipt on their own membership event**, put by the server
  when they join and visible to the others before they read anything.
- **The current user is excluded** from `TimelineItem.readReceipts` and from `typingUsers`: each
  member sees only the others.
- **Typing notices are batched upstream**: 10 `setTyping(true)` calls over about 2 seconds reached
  the other member as 5 snapshots. None failed; the package adds no throttling of its own.
- **`RoomSummary.notificationCount` and `highlightCount` are computed by the SDK from the user's
  notification settings**, not read from the server. After a long absence they can be lower than
  the real count, because the sync timeline is limited. In an encrypted room, an event counts only
  once it is decrypted.
- **On macOS, the package stores the session in the data protection keychain**, and the
  application migrates a session written by an earlier version on its first read: the legacy item
  is read, added to the data protection keychain, read back, and only then deleted, so a failure
  in between loses nothing and the next read starts again. The migration only adds, never
  overwrites, and the data protection copy wins when another reader migrated first. The
  notification extension cannot migrate: until the application has run once after the update, the
  extension's read throws a storage error. This keychain requires a signed application carrying
  `keychain-access-groups`: an unsigned binary gets `errSecMissingEntitlement` (-34018), which
  surfaces as `MatrixError.storage`. iOS is unchanged. See the *Push notifications* article.
- **A residual window exists at the very first read after the update**: a logout
  (`removeValue`) by another instance that lands between the legacy read and the add can bring a
  revoked session back. No lock covers it — the `CrossProcessLock` serialises the SDK's SQLite
  store, not the keychain. It resolves itself at the first authentication refusal, which erases
  the session, with no data loss.

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
