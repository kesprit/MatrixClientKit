# ``MatrixClientKit``

Build a Matrix client in Swift, without touching the Rust SDK's FFI.

## Overview

MatrixClientKit wraps the official Matrix Rust SDK behind a modern Swift API: `async`/`await`,
`AsyncStream`, `Sendable` types and typed errors. Room lists and timelines are exposed as
**snapshots** — you receive the complete, current state and never apply a diff yourself.

See <doc:GettingStarted> for a first end-to-end flow, and <doc:TestingWithMocks> to test an
application that depends on the package.

## What v0.1 covers

This page can be read on its own — the Swift Package Index renders it without the repository's
README — so the limits of this milestone are restated here.

v0.1 covers password authentication, persisted sessions, syncing, the room list, timelines and
sending text messages.

End-to-end encryption is **active** today: the Rust SDK handles it, with no opt-in. What v0.1 does
**not** expose:

- device verification (cross-signing, SAS, QR);
- key backup and recovery;
- push notifications and the associated service extension;
- media, read receipts, typing indicators, presence and profiles;
- OAuth / OIDC, and `MatrixClient.loginDetails()`.

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
- <doc:TestingWithMocks>

### Entry point

- ``Matrix``
- ``MatrixClient``
- ``Credentials``
- ``MatrixSession``

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

### Storage

- ``MatrixStorage``

### Identifiers

- ``UserID``
- ``RoomID``
- ``EventID``
- ``DeviceID``

### Errors

- ``MatrixError``
