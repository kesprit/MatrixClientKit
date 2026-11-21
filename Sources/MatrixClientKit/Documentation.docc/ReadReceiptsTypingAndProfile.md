# Read receipts, typing, profile and account

Mark a room as read, show who read what and who is typing, publish the user's presence, show and
edit profiles, and open the account management of the server.

## Overview

Everything here is about what makes a messaging application feel alive, and about the user
themselves. Nothing happens by itself: the package sends no read receipt, no typing notice and no
presence unless your application calls it. You decide when, and — for read receipts — how visible.

The examples below assume a `session`, a `room` and a `timeline` obtained as in
<doc:GettingStarted>.

## Mark a room as read

``Timeline/markAsRead(visibility:)`` tells the homeserver that the user read the room up to its
latest visible message. It sends a read receipt **and** moves the user's read marker there, so the
unread counters of the user's other devices go down too.

```swift
try await timeline.markAsRead(visibility: .public)
```

The visibility is a product decision, so it is required at every call. ``ReadReceiptVisibility``
offers two choices:

- `.public` is visible to every member of the room, who learn that the user read it;
- `.private` is visible to the user's own devices only: their unread counts stay in sync, and nobody
  else learns that the user read the room.

Call it when the user actually sees the end of the conversation — the screen is in the foreground
and scrolled to the bottom — not each time the item list changes.

When the user has seen only part of the room, give the last message they saw with
``Timeline/markAsRead(upTo:visibility:)``:

```swift
func markSeen(_ item: TimelineItem, timeline: any Timeline) async throws {
    guard let eventID = item.message?.eventID else { return }
    try await timeline.markAsRead(upTo: eventID, visibility: .private)
}
```

``Timeline/markAsRead(visibility:)`` looks up "the latest visible item" twice, once for the receipt
and once for the read marker. If an event arrives between the two, they can end up on two different
items. When both must land on exactly the same target, use ``Timeline/markAsRead(upTo:visibility:)``.

If the receipt fails, the read marker is not attempted and the error is thrown.

## Show who read what

``TimelineItem/readReceipts`` lists, for each item, the other members whose latest read item is
this one, most recent first. The current user is never in it.

The rule to remember: **a receipt sits only on the latest item a member read**, and that item is
not necessarily a message. A membership change, a renamed room, a redacted or undecryptable event,
a sticker or a poll carries a receipt like any message does. So a member read a message `M` when
their receipt is on `M` **or on any later item** of the timeline.

For example, Bob reads everything, then Carol joins the room. The timeline is:

| Item | Receipts |
| --- | --- |
| Alice: "Lunch?" | none |
| Alice: "I booked a table" | none |
| Carol joined | Bob |

Bob's receipt is on Carol's arrival, not on the last message. Looking for it on "I booked a table"
alone would wrongly conclude that Bob read nothing since "Lunch?".

The package does not do that lookup for you in this version, since your application already holds
the list. A way to write it:

```swift
/// The members who read the message at `index`: those whose receipt is on it or later.
func readers(ofItemAt index: Int, in items: [TimelineItem]) -> [UserID] {
    items[index...].flatMap(\.readReceipts).map(\.userID)
}
```

A few points to know:

- Items with no event behind them have no receipts: a date separator, the read marker, and the
  `.unsupported` items that stand for no event (the start of the timeline).
- Receipts that other members send as private are never visible, whatever you do: that is the
  Matrix protocol.
- A receipt comes with a ``ReadReceipt/timestamp`` only when the homeserver provides one.
- The avatar of a message's sender is ``Message/senderAvatar``, to give to ``MediaService`` as
  explained in <doc:WorkingWithMedia>. It is `nil` while the sender's profile is not loaded.

## Typing

``RoomHandle/typingUsers`` is a stream of snapshots: every value is the complete, current list of
the members typing in the room, the current user excluded. Like the other streams of the package,
leaving the loop cancels the upstream subscription.

```swift
Task {
    for await users in room.typingUsers {
        self.typingNames = users.map(\.rawValue)
    }
}
```

To tell the room that the user is typing, call ``RoomHandle/setTyping(_:)`` with `true` as they type,
and with `false` when they stop or send:

```swift
func textChanged(_ text: String, room: any RoomHandle) async throws {
    try await room.setTyping(!text.isEmpty)
}
```

The package sends only what you call. How often the upstream SDK lets a repeated
`setTyping(true)` through is its own business; read the *Behaviours to know* of the changelog.

## Publish the presence

``ProfileService/setPresence(_:)`` publishes whether the user is `.online`, `.unavailable` or
`.offline`, through ``MatrixSession/profile``.

```swift
try await session.profile.setPresence(.online)
```

Know the limits before relying on it:

- **The package publishes nothing itself.** Until your application calls `setPresence(_:)`, the
  user shows as `.unavailable` to their contacts, at every launch: the state is not persisted.
  Publish it again each time the application starts, for instance when it comes to the foreground.
- **The state applies to the following syncs even when the call throws.**
- **Observing other people's presence is not possible**: the upstream SDK does not expose it.

## Show and edit profiles

``ProfileService/profile(of:)`` fetches a user's global profile. Pass ``MatrixSession/userID`` for
the current user's. The result's ``UserProfile/avatar`` is a ``MediaSource``, displayed like any
other media:

```swift
func showProfile(of user: UserID, session: any MatrixSession) async throws {
    let profile = try await session.profile.profile(of: user)
    let name = profile.displayName ?? user.rawValue
    var avatarData: Data?
    if let avatar = profile.avatar {
        avatarData = try await session.media.thumbnail(of: avatar, width: 96, height: 96)
    }
    // …
}
```

An unknown user throws ``MatrixError/notFound(_:)`` with `.user`. Nothing is cached: every call
asks the homeserver.

To change the current user's profile:

```swift
try await session.profile.setDisplayName("Alice")
try await session.profile.setAvatar(jpegData, mimeType: "image/jpeg")
try await session.profile.removeAvatar()
```

The package neither validates the name — an empty string is sent as is — nor reads files: the
avatar is given as bytes, and a media larger than the homeserver accepts throws
``MatrixError/unexpected(message:details:)``. The current user's own profile cannot be observed: after
a change, update your display yourself.

## Open the account management

A homeserver that delegates its accounts to an authorization server (matrix.org does) manages
devices, passwords and deletion on web pages of that server. ``AccountService/managementURL(for:)``
returns the page to open, or `nil` when the homeserver manages the accounts itself:

```swift
import AuthenticationServices

func manageAccount(session: any MatrixSession) async throws {
    guard let url = try await session.account.managementURL(for: .overview) else {
        // The homeserver manages accounts itself: offer what your interface has to offer.
        return
    }
    // Present `url` in Safari, or in an `ASWebAuthenticationSession`.
}
```

``AccountManagementAction`` offers `.overview`, `.profile`, `.devices`, `.device(_:)`,
`.deleteDevice(_:)` and `.deactivateAccount`. It is a struct, not an enum, so that new pages can be
added without breaking your `switch`.

## Ignore a user

``AccountService/ignore(_:)`` and ``AccountService/unignore(_:)`` change the list of the users the
account ignores: their messages and invitations no longer reach it. ``AccountService/ignoredUsers``
is a stream of snapshots of that list, starting with the current one:

```swift
Task {
    for await ignored in session.account.ignoredUsers {
        self.ignoredUsers = ignored
    }
}
try await session.account.ignore(abusiveUser)
```

If reading the initial list fails, the stream ends **without any value**, as ``RoomService/list(filter:)``
does: a consumer that received nothing should read it as a failure, not as an empty list.

## Deactivate an account

``AccountService/deactivate(password:eraseData:)`` deactivates an account protected by a password,
for good. Ask the user to confirm before calling it, and for their password: it cannot be undone.

```swift
try await session.account.deactivate(password: password, eraseData: false)
```

- On success, the local data is erased as after a logout, and the session's authentication state
  becomes signed out.
- On failure — a refused password, a network error — nothing is erased and the session stays usable,
  unlike ``MatrixSession/logout()``.
- **A session opened through OAuth is refused** before any server call, with
  ``MatrixError/unexpected(message:details:)``. Such an account is deactivated on the authorization
  server's page: open ``AccountService/managementURL(for:)`` with
  ``AccountManagementAction/deactivateAccount``.
- A failure can be reported for an account that was deactivated all the same, for instance when the
  network drops after the server accepted the request. The session is then dead: the next sync
  signs it out and erases the local data.

## What to remember

- The package sends no receipt, no typing notice and no presence by itself.
- A read receipt is on the latest item a member read, which is not always a message.
- ``Timeline/markAsRead(visibility:)`` resolves "the latest item" twice; use
  ``Timeline/markAsRead(upTo:visibility:)`` for one fixed target.
- The presence starts as `.unavailable` and is not persisted; observing it is not possible.
- The current user's profile is not observable.
- Account deactivation is refused in an OAuth session: use the management URL.

To test code that uses these services without a homeserver, see <doc:TestingWithMocks>.
