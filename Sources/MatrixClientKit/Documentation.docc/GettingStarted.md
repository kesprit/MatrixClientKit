# Prise en main

Se connecter, synchroniser, afficher des rooms et envoyer un message.

## Créer un client

```swift
import MatrixClientKit

let client = Matrix.client(
    homeserver: URL(string: "https://matrix.org")!,
    storage: .appGroup("group.com.exemple.app")
)
```

Utilisez ``MatrixStorage/appGroup(_:keychainAccessGroup:accessibility:)`` dès qu'une extension
doit accéder à la même session. Sinon, ``MatrixStorage/local(directory:accessibility:)`` suffit.

## Ouvrir une session

```swift
let session: any MatrixSession

if let restored = try await client.restoreSession() {
    session = restored
} else {
    session = try await client.login(
        .password(username: "alice", password: "…", deviceName: "iPhone")
    )
}
```

``MatrixClient/restoreSession()`` renvoie `nil` s'il n'y a pas de session persistée — ce n'est
pas une erreur. Appelez-la avant ``MatrixClient/login(_:)`` pour éviter de reconnecter un
utilisateur déjà authentifié.

## Synchroniser et observer les rooms

```swift
await session.sync.start()

for await rooms in session.rooms.list(filter: .joined) {
    // `rooms` est la liste complète et à jour : affectez-la directement.
    self.rooms = rooms
}
```

## Lire et envoyer des messages

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
try await timeline.send(.text("bonjour"))
```

L'écho local du message envoyé apparaît dans `timeline.items` sans action supplémentaire.

## Gérer les erreurs

```swift
do {
    try await timeline.send(.text("bonjour"))
} catch let error as MatrixError {
    if error.isRetryable {
        // ré-essayer, éventuellement après error.retryAfter
    }
}
```
