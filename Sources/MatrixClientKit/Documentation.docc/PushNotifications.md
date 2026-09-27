# Push notifications and the service extension

Register a pusher, share storage with a notification service extension, and resolve a push into a
displayable notification without syncing.

## Overview

A push travels: the homeserver tells a push gateway — typically [Sygnal](https://github.com/matrix-org/sygnal),
operated by the application's publisher — that an event happened; the gateway sends APNs a minimal
payload (`event_id_only`: just a room and event identifier); APNs wakes the notification service
extension; the extension asks ``MatrixNotificationService`` to resolve the event; the extension
shows a notification built from the result. The message's content never passes through Apple's
servers.

## Share the storage

The application and its extension must open the **same** ``MatrixStorage``: the same App Group and,
if you set one, the same Keychain access group.

```swift
let storage = MatrixStorage.appGroup(
    "group.com.example.app",
    keychainAccessGroup: "TEAMID.com.example.app"
)
```

Both targets need the matching entitlements:

- `com.apple.security.application-groups`, with the same group identifier, in both the application
  and the extension;
- `keychain-access-groups`, with the same group, in both, if you pass `keychainAccessGroup`;
- `aps-environment` in the application only — the extension does not register for remote
  notifications itself.

``MatrixStorage/appGroup(_:keychainAccessGroup:accessibility:)`` defaults `accessibility` to
``MatrixStorage/KeychainAccessibility/afterFirstUnlock``. Keep that default: the extension runs
while the device may still be locked, and ``MatrixStorage/KeychainAccessibility/whenUnlocked``
would make the access token unreadable, so every notification would arrive empty.

## Register the pusher

Ask for a device token as usual:

```swift
UIApplication.shared.registerForRemoteNotifications()
```

Then, in the application delegate, register it with the homeserver every time a token arrives —
tokens change over the app's lifetime:

```swift
func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    Task {
        try await session.notifications.registerPusher(
            PusherConfiguration(
                deviceToken: deviceToken,
                appID: "com.example.app.ios.prod",
                gatewayURL: URL(string: "https://push.example.com/_matrix/push/v1/notify")!,
                appDisplayName: "Example",
                deviceDisplayName: UIDevice.current.name,
                fallbackAlert: NSLocalizedString("New message", comment: "Fallback push alert")
            )
        )
    }
}
```

Provide `fallbackAlert` in the user's language: it is what the notification shows if the extension
fails or runs out of time. The package sets `mutable-content` on the pusher's default payload for
you — without it, iOS never calls the extension at all — so there is nothing to configure on that
side.

The push key the package sends to the homeserver, ``PusherConfiguration/pushKey``, is the device
token encoded in base64. That is what Sygnal's APNs pushkin expects by default: it decodes the push
key from base64 before handing the token to Apple. If your gateway is configured to read the token
in another encoding, reconfigure it to match, or every push will be rejected.

## Write the extension

The extension's `didReceive(_:withContentHandler:)` reads the push, resolves it, and fills the
notification:

```swift
final class NotificationService: UNNotificationServiceExtension {
    private var originalRequest: UNNotificationRequest?
    private var contentHandler: ((UNNotificationContent) -> Void)?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        originalRequest = request
        self.contentHandler = contentHandler

        guard let payload = MatrixPushPayload(userInfo: request.content.userInfo),
            let content = request.content.mutableCopy() as? UNMutableNotificationContent
        else { return contentHandler(request.content) }

        Task {
            do {
                let service = try await MatrixNotificationService(storage: .appGroup("group.com.example.app"))
                switch try await service.notification(roomID: payload.roomID, eventID: payload.eventID) {
                case .notification(let notification):
                    content.apply(notification)
                    contentHandler(content)
                case .filteredOut, .redacted:
                    contentHandler(UNNotificationContent())
                case .notFound:
                    contentHandler(request.content)
                }
            } catch {
                contentHandler(request.content)
            }
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // The system is about to kill the extension: deliver what the pusher's default payload
        // provided rather than nothing at all.
        guard let handler = contentHandler, let request = originalRequest else { return }
        handler(request.content)
    }
}
```

`MatrixPushPayload(userInfo:)` returns `nil` for anything that is not a Matrix push in the
`event_id_only` format, in which case the original, unresolved content is delivered as-is.

## Rules

**No sync in the extension.** ``MatrixNotificationService`` never starts a sync: starting one from
the extension would race the application's own sync over the same store and corrupt its state. The
extension only ever calls ``NotificationContentResolving/notification(roomID:eventID:)``.

**Memory is scarce.** A notification service extension gets roughly 24 MB. Keep the
``MatrixNotificationService`` instance alive for the extension process's lifetime instead of
recreating it on every push, and never open a full `MatrixSession` from the extension — it is not
built for the budget.

**The application may be holding the cross-process lock.** While the application is syncing, it
holds the store's cross-process lock; the extension's resolver waits for it to free up, retrying
with an exponential backoff from 10 ms up to 1 s between attempts. If the lock is never released in
time, resolution fails with a timeout. In practice this means resolution can be slower while the
app is active in the foreground, and a failure here must fall back to the original push content —
which is exactly what the `catch` block above does.

**A signed-out session fails immediately.** If the user signed out, `MatrixNotificationService.init(storage:)`
throws ``MatrixError/authentication(_:)`` with ``MatrixError/Authentication/missingToken``: there is
no session to read. Deliver the original content, as the example does.

## Room notification settings

``NotificationService`` also controls how much a room notifies, independently of the pusher:

```swift
let settings = try await session.notifications.notificationSettings(for: roomID)

// A three-choice menu, as most Matrix clients present it:
Menu("Notifications") {
    Button("All messages") {
        Task { try await session.notifications.setNotificationMode(.allMessages, for: roomID) }
    }
    Button("Mentions and keywords only") {
        Task { try await session.notifications.setNotificationMode(.mentionsAndKeywordsOnly, for: roomID) }
    }
    Button("Mute") {
        Task { try await session.notifications.setNotificationMode(.mute, for: roomID) }
    }
    if !settings.isDefault {
        Button("Use default") {
            Task { try await session.notifications.restoreDefaultNotificationMode(for: roomID) }
        }
    }
}
```

``RoomNotificationSettings/isDefault`` tells you whether the room has its own setting, so you know
whether to offer "use default" at all.

## Testing

`MockNotificationService` stands in for ``NotificationService``: it records the pushers you
register and lets you set what a room's settings are.

```swift
let notifications = MockNotificationService()
notifications.setSettings(RoomNotificationSettings(mode: .mute, isDefault: false), for: roomID)

try await notifications.registerPusher(SampleData.pusherConfiguration())

#expect(notifications.registeredPushers == [SampleData.pusherConfiguration()])
```

`MockNotificationResolver` stands in for ``NotificationContentResolving``, so you can test an
extension's own logic without a real Rust SDK client:

```swift
let resolver = MockNotificationResolver()
resolver.setResult(.notification(SampleData.notification()), roomID: roomID, eventID: eventID)

let result = try await resolver.notification(roomID: roomID, eventID: eventID)

#expect(result == .notification(SampleData.notification()))
```
