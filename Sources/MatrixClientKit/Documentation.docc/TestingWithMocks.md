# Testing an application with MatrixClientKitMocks

Write unit tests for code that talks to Matrix, with no homeserver, no network, and without
linking the Rust SDK binary.

## Overview

The `MatrixClientKitMocks` product ships **drivable** doubles of the public protocols: you decide
what a stream emits, when it ends, and what a send returns.

These doubles depend only on `MatrixClientKitCore`, which links no XCFramework: your application's
test suite runs without pulling in the Rust binary, and starts at its usual speed.

### Adding the product to your test target

```swift
.testTarget(
    name: "MyAppTests",
    dependencies: [
        "MyApp",
        .product(name: "MatrixClientKitMocks", package: "MatrixClientKit"),
    ]
)
```

## The doubles

| Double | Stands in for | Driven with |
| --- | --- | --- |
| `MockMatrixClient` | ``MatrixClient`` | `loginResult`, `restoreResult`, `loginAttempts` |
| `MockMatrixSession` | ``MatrixSession`` | `emitAuthState(_:)`, `logoutError`, `didLogout` |
| `MockRoomService` | ``RoomService`` | `emit(_:)`, `finish()` |
| `MockSyncController` | ``SyncController`` | `emit(_:)`, `finish()`, `startCallCount` |
| `MockTimeline` | ``Timeline`` | `emit(_:)`, `finish()`, `sentMessages`, `sendError`, `paginationError` |
| `MockEncryptionService` | ``EncryptionService`` | `emitVerificationStatus(_:)`, `emitRecoveryState(_:)`, `emitBackupState(_:)`, `finish()`, injected results and errors |
| `MockSessionVerification` | ``SessionVerification`` | `emit(_:)`, `finish()`, `setError(_:for:)`, `calls` |

The stream-bearing doubles expose the **same pair**: an `emit` method pushes a value, `finish()`
ends the stream.

## Driving a stream

An `AsyncStream` does not end by itself: a `for await` loop runs until the source calls
`finish()`. A test that iterates to the end must therefore end the stream itself, or it hangs
instead of failing.

```swift
import Testing
import MatrixClientKitCore
import MatrixClientKitMocks

@Test func theTimelineShowsReceivedMessages() async {
    let timeline = MockTimeline()
    let stream = timeline.items

    timeline.emit([SampleData.message("hello", from: "@alice:matrix.org")])
    timeline.finish()

    var received: [[TimelineItem]] = []
    for await items in stream {
        received.append(items)
    }

    #expect(received.count == 1)
    #expect(received.first?.first?.message?.body == "hello")
}
```

To consume a single value without ending the stream, an explicit iterator saves you from breaking
out of a loop:

```swift
var iterator = timeline.items.makeAsyncIterator()
let first = await iterator.next()
```

> Important: every access to ``Timeline/items`` — like every call to ``RoomService/list(filter:)``
> — opens an independent subscription. Hold the stream in a variable if you want two reads to
> observe the same thing.

## Checking a filter

`MockRoomService` genuinely applies the filter you pass it, so a test asserting "invitations don't
show up in the main list" is checking something real — provided the seeded list contains a room
that is not joined:

```swift
@Test func invitationsStayOutOfTheMainList() async throws {
    let service = MockRoomService(
        rooms: SampleData.roomSummaries(count: 3)
            + [SampleData.roomSummary(id: "!invite:matrix.org", membership: .invited)]
    )

    var iterator = service.list(filter: .joined).makeAsyncIterator()
    let rooms = try #require(await iterator.next())

    #expect(rooms.count == 3)
    #expect(rooms.allSatisfy { $0.membership == .joined })
}
```

`emit(_:)` replaces the list and republishes it, filtered, into every open stream — enough to test
that a view updates when a room arrives.

## Simulating a failure

`MockTimeline.sendError` makes sends fail, and `MockTimeline.paginationError` makes pagination fail,
independently — so "pagination fails while sending still works" is testable. That is how you test
the error path without causing a real network outage:

```swift
@Test func anOfflineSendReachesTheUI() async {
    let timeline = MockTimeline()
    timeline.sendError = .network(.offline)

    await #expect(throws: MatrixError.network(.offline)) {
        try await timeline.send(.text("hi"))
    }
}
```

Without `sendError`, `send(_:)` succeeds and records the content in `sentMessages`, which lets you
check *what* your code sent:

```swift
#expect(timeline.sentMessages == [.text("hi")])
```

## A whole session

`MockMatrixSession` assembles the other three doubles and records the sign-out:

```swift
@Test func signingOutIsPropagated() async throws {
    let session = MockMatrixSession()

    try await session.logout()

    #expect(session.didLogout)
}
```

The inner doubles stay reachable so you can drive them:

```swift
let rooms = MockRoomService()
let sync = MockSyncController()
let session = MockMatrixSession(rooms: rooms, sync: sync)

await session.sync.start()
#expect(sync.startCallCount == 1)

rooms.emit(SampleData.roomSummaries(count: 5))
rooms.timeline.emit([SampleData.message("hello")])
```

## Driving a verification

`MockSessionVerification` runs no state machine: your test sets every state and checks the commands
your code called.

```swift
@Test func approvingSendsTheApproval() async throws {
    let verification = MockSessionVerification()
    let model = VerificationModel(verification: verification)   // your code

    verification.emit(.comparing(.emojis([SASEmoji(symbol: "🐶", description: "Dog", index: 0)])))
    try await model.userConfirmedEmojisMatch()

    #expect(verification.calls == [.approve])
}
```

## Restoring at launch

``Matrix/restoreSession(storage:)`` is a static function, so no mock can replace it. Inject it as a
closure instead:

```swift
struct LaunchModel {
    var restoreSession: () async throws -> (any MatrixSession)? = {
        try await Matrix.restoreSession(storage: .appGroup("group.com.example.app"))
    }
}

@Test func aStoredSessionSkipsSignIn() async throws {
    let model = LaunchModel(restoreSession: { MockMatrixSession() })
    // …
}
```

## What the mocks do not replace

A double reproduces the **shape** of the API, not the Rust SDK's behaviour: not encryption, not
real pagination, not send retries. The paths that depend on the server — login, sync, the local
echo of a message you sent — are verified against a real homeserver, in the repository's
integration suite, run by hand before every bump of the upstream SDK.
