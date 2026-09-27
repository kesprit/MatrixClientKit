# MatrixClientKit

A Swift package for building [Matrix](https://matrix.org) clients on iOS and macOS, built on the
official [Matrix Rust SDK](https://github.com/matrix-org/matrix-rust-sdk).

```swift
let storage = MatrixStorage.appGroup("group.com.example.app")
let session: any MatrixSession

if let restored = try await Matrix.restoreSession(storage: storage) {
    session = restored
} else {
    let client = Matrix.client(homeserver: URL(string: "https://matrix.org")!, storage: storage)
    session = try await client.login(.password(username: "alice", password: "…", deviceName: "iPhone"))
}
await session.sync.start()

for await rooms in session.rooms.list(filter: .joined) {
    self.rooms = rooms          // the complete, current list — no diffs to apply
}
```

## What the package gives you

- **Async streams.** The Rust SDK's listener subscriptions become `AsyncStream`s whose lifetime is
  managed for you: leaving a loop cancels the upstream subscription (as long as you don't hold the
  stream in a property).
- **Snapshots, not diffs.** Room lists and timelines arrive as the complete, current state. There
  is no diff machinery for you to write.
- **Typed errors.** `MatrixError`, with `isRetryable` and `retryAfter`.
- **Retry decisions made for you.** Rely on `MatrixError.isRetryable` rather than writing your own
  mapping: it is what keeps you from offering "try again" after a TLS failure or an exceeded quota.
- **Storage ready for extensions.** App Group, Keychain and file protection configured so that a
  notification service extension works while the device is locked.
- **Testable.** The whole public API is protocol-based, and the `MatrixClientKitMocks` product
  ships drivable doubles that link none of the Rust SDK binary.

## Scope

v0.3 covers password authentication, persisted sessions, syncing, the room list, timelines, sending
text messages, device verification, recovery and key backup, push notifications through a
notification service extension, and per-room notification settings.

End-to-end encryption is **active** — the Rust SDK handles it, with no opt-in on your part. An
application can verify a new device by comparing emojis with another of the user's devices, set up
recovery, restore keys with the recovery key, and learn that the server ended the session. What
v0.3 does **not** expose:

- QR-code verification — the bundled Rust SDK does not expose it;
- verifying other users, and resetting a lost cryptographic identity;
- account-wide notification settings (mentions, invitations, calls, keywords).

Because a lost identity cannot be reset yet, set up recovery early: a user who never does and then
loses or signs out of their last device cannot verify any device of that account again — identity
reset is still not part of v0.3.

`MatrixClient.loginDetails()` — which reports the login methods a homeserver accepts — is planned
but **not implemented** yet: an application that needs to query the homeserver before showing a
sign-in screen will have to wait. Its absence is a decision, not an oversight.

| Version | Contents |
| --- | --- |
| 0.1 | Foundation: auth, session, sync, rooms, timeline, sending text |
| 0.2 | Device verification (emoji), recovery and key backup, server sign-out, restore from storage |
| 0.3 | Push notifications, service extension, cross-process lock, per-room notification settings |
| 0.4 | Media, read receipts, typing, presence, account, OAuth, `loginDetails()` |
| Later | Verifying other users, identity reset, QR-code verification once the SDK exposes it |
| 1.0 | API freeze |

## Installation

```swift
.package(url: "https://github.com/kesprit/MatrixClientKit", from: "0.3.0")
```

## Compatibility

| MatrixClientKit | Bundled Matrix Rust SDK | iOS | macOS | Swift |
| --- | --- | --- | --- | --- |
| 0.3.x | 26.09.07 | 18+ | 15+ | 6.2+ |
| 0.2.x | 26.09.07 | 18+ | 15+ | 6.2+ |
| 0.1.x | 26.09.07 | 18+ | 15+ | 6.2+ |

## Errors: the evolution rule

Every error this package throws is a `MatrixError`, a public enum. In a SwiftPM package a public
enum is exhaustive for consumers, so **adding a case would break your application's build** — which
would force a major version on every upstream SDK release.

The rule, for the lifetime of a major version:

> `MatrixError`'s top-level cases are **frozen**. Any error the upstream SDK newly lets us
> distinguish is reported through `.unexpected(message:details:)` until the next major version.

In practice: your `switch` over `MatrixError` stays exhaustive without a `default` from one minor
version to the next, but a condition handled today by `.unexpected` may stay there for a long time
— so don't write business logic that depends on the text inside `.unexpected`. The nested enums
(`MatrixError.Authentication`, `.Network`, …) follow the same rule.

## A note on the API

`MatrixClientKit` never exposes or returns a Rust SDK type in a public signature.

That said, SwiftPM cannot hide a transitive module: `MatrixRustSDK` remains technically importable
from your application, which depends on `matrix-rust-components-swift` transitively. You never need
to import it, and this package's API never forces you to — but the claim is about MatrixClientKit's
signatures, not about the module being invisible.

## Documentation

The reference documentation (DocC) is generated from
`Sources/MatrixClientKit/Documentation.docc`. See also [`CONTRIBUTING.md`](CONTRIBUTING.md) to
contribute and [`CHANGELOG.md`](CHANGELOG.md) for the version history.

## Licence

Apache-2.0. This project bundles the Matrix Rust SDK, also under Apache-2.0. See
[`NOTICE`](NOTICE).
