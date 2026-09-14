# MatrixClientKit

A Swift package for building [Matrix](https://matrix.org) clients on iOS and macOS, built on the
official [Matrix Rust SDK](https://github.com/matrix-org/matrix-rust-sdk).

```swift
let client = Matrix.client(
    homeserver: URL(string: "https://matrix.org")!,
    storage: .appGroup("group.com.example.app")
)
let session = try await client.login(.password(username: "alice", password: "…", deviceName: "iPhone"))
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
- **Storage ready for extensions.** App Group, Keychain and file protection configured so that a
  notification service extension works while the device is locked.
- **Testable.** The whole public API is protocol-based, and the `MatrixClientKitMocks` product
  ships drivable doubles that link none of the Rust SDK binary.

## Scope

v0.1 covers password authentication, persisted sessions, syncing, the room list, timelines and
sending text messages.

End-to-end encryption is **active** today — the Rust SDK handles it, with no opt-in on your part.
What v0.1 does **not** expose:

- device verification (cross-signing, SAS);
- key backup and recovery;
- push notifications and the associated service extension.

If your application needs any of those three right now, this version is not for you yet. See the
roadmap below.

`MatrixClient.loginDetails()` — which reports the login methods a homeserver accepts — is planned
but **not implemented** in v0.1: an application that needs to query the homeserver before showing
a sign-in screen will have to wait. Its absence is a decision, not an oversight.

| Version | Contents |
| --- | --- |
| 0.1 | Foundation: auth, session, sync, rooms, timeline, sending text |
| 0.2 | Device verification, key backup and recovery |
| 0.3 | Push notifications and the service extension |
| 0.4 | Media, read receipts, typing, presence, account, OAuth, `loginDetails()` |
| 1.0 | API freeze |

## Installation

```swift
.package(url: "https://github.com/kesprit/MatrixClientKit", from: "0.1.1")
```

## Compatibility

| MatrixClientKit | Bundled Matrix Rust SDK | iOS | macOS | Swift |
| --- | --- | --- | --- | --- |
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
