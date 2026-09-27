# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versioning
follows [SemVer](https://semver.org/).

## [Unreleased]

### Breaking

- `MatrixSession` requires a new member, `notifications`. An application that implements the
  protocol itself — typically in a test double — must add it, or use `MockMatrixSession`.

### Added

- `MatrixSession.notifications`, a `NotificationService`: `registerPusher(_:)` and
  `unregisterPusher(_:)` with a `PusherConfiguration`, and per-room notification settings —
  `notificationSettings(for:)`, `setNotificationMode(_:for:)`, `restoreDefaultNotificationMode(for:)`.
- `MatrixNotificationService`, the notification service extension's entry point: resolves a push
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
