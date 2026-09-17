# Getting started

Sign in, sync, show rooms and send a message.

## Create a client

```swift
import MatrixClientKit

let client = Matrix.client(
    homeserver: URL(string: "https://matrix.org")!,
    storage: .appGroup("group.com.example.app")
)
```

Use ``MatrixStorage/appGroup(_:keychainAccessGroup:accessibility:)`` as soon as an extension needs
to reach the same session. Otherwise ``MatrixStorage/local(directory:accessibility:)`` is enough.

## Open a session

At launch, restore the stored session from storage alone — its homeserver address is stored with
it — and sign in only when there is none:

```swift
let storage = MatrixStorage.appGroup("group.com.example.app")
let session: any MatrixSession

if let restored = try await Matrix.restoreSession(storage: storage) {
    session = restored
} else {
    let client = Matrix.client(homeserver: URL(string: "https://matrix.org")!, storage: storage)
    session = try await client.login(
        .password(username: "alice", password: "…", deviceName: "iPhone")
    )
}
```

``Matrix/restoreSession(storage:)`` returns `nil` when no session is stored — that is not an error.
Once signed in, see <doc:VerificationAndRecovery>: a new device should be verified before it can
read encrypted history.

## Sync and observe rooms

```swift
await session.sync.start()

for await rooms in session.rooms.list(filter: .joined) {
    // `rooms` is the complete, current list: assign it directly.
    self.rooms = rooms
}
```

The list starts empty and fills in once sync produces its first response, so an empty first
snapshot is normal rather than a sign that the account has no rooms.

## Read and send messages

```swift
let roomID = RoomID(rawValue: "!room:matrix.org")!
let room = try await session.rooms.room(roomID)
let timeline = try await room.timeline()

Task {
    for await items in timeline.items {
        self.messages = items
    }
}

try await timeline.paginateBackwards(count: 20)
try await timeline.send(.text("hello"))
```

The local echo of the message you sent shows up in `timeline.items` on its own.

Note that ``RoomService/room(_:)`` resolves against the synced room list, not against the server:
right after signing in, wait for the room to appear in ``RoomService/list(filter:)`` before asking
for it.

## Handle errors

```swift
do {
    try await timeline.send(.text("hello"))
} catch let error as MatrixError {
    if error.isRetryable {
        // retry, possibly after error.retryAfter
    }
}
```
