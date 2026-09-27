# ``MatrixClientKit``

Build a Matrix client in Swift, without touching the Rust SDK's FFI.

## Overview

MatrixClientKit wraps the official Matrix Rust SDK behind a modern Swift API: `async`/`await`,
`AsyncStream`, `Sendable` types and typed errors. Room lists and timelines are exposed as
**snapshots** — you receive the complete, current state and never apply a diff yourself.

See <doc:GettingStarted> for a first end-to-end flow, <doc:VerificationAndRecovery> to handle
device trust, <doc:PushNotifications> to receive push notifications through a notification service
extension, and <doc:TestingWithMocks> to test an application that depends on the package.

## What v0.3 covers

This page can be read on its own — the Swift Package Index renders it without the repository's
README — so the limits of this milestone are restated here.

v0.3 covers password authentication, persisted sessions (restorable from storage alone), syncing,
the room list, timelines, sending text messages, device verification by emoji comparison, recovery
and key backup, notification of a session ended by the server, push notifications through a
notification service extension, and per-room notification settings.

End-to-end encryption is **active**: the Rust SDK handles it, with no opt-in. What v0.3 does **not**
expose:

- QR-code verification — the bundled Rust SDK does not expose it;
- verification of other users, and resetting a lost cryptographic identity;
- account-wide notification settings (mentions, invitations, calls, keywords);
- media, read receipts, typing indicators, presence and profiles;
- OAuth / OIDC, and `MatrixClient.loginDetails()`.

Because a lost identity cannot be reset yet, set up recovery early: a user who never does and then
loses or signs out of their last device cannot verify any device of that account again.

Two behaviours to know before depending on this version:

- ``RoomService/list(filter:)`` and ``Timeline/items`` are `AsyncStream`s, so they have no error
  channel: a subscription that fails ends the stream **with no values at all**. A consumer that
  received no snapshot should read that as a failure, not as an empty account.
- ``MatrixError``'s top-level cases are frozen for the lifetime of a major version: any error the
  upstream SDK newly lets us distinguish is reported through
  ``MatrixError/unexpected(message:details:)`` until the next major.

## Topics

### Getting started

- <doc:GettingStarted>
- <doc:VerificationAndRecovery>
- <doc:PushNotifications>
- <doc:TestingWithMocks>

### Entry point

- ``Matrix``
- ``MatrixClient``
- ``Credentials``
- ``MatrixSession``
- ``AuthState``

### Rooms and messages

- ``RoomService``
- ``RoomFilter``
- ``RoomHandle``
- ``RoomSummary``
- ``Membership``
- ``Timeline``
- ``TimelineItem``
- ``Message``
- ``SendState``
- ``MessageContent``

### Syncing

- ``SyncController``
- ``SyncState``

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

### Push notifications

- ``NotificationService``
- ``PusherConfiguration``
- ``RoomNotificationMode``
- ``RoomNotificationSettings``
- ``MatrixNotificationService``
- ``NotificationContentResolving``
- ``MatrixPushPayload``
- ``MatrixNotification``
- ``NotificationResult``

### Storage

- ``MatrixStorage``

### Identifiers

- ``UserID``
- ``RoomID``
- ``EventID``
- ``DeviceID``

### Errors

- ``MatrixError``
