# Tester une application avec MatrixClientKitMocks

Écrire des tests unitaires sur du code qui parle à Matrix, sans homeserver, sans réseau et sans
lier le binaire du SDK Rust.

## Overview

Le produit `MatrixClientKitMocks` fournit des doubles **pilotables** des protocoles publics :
vous décidez ce que le flux émet, quand il se termine, et ce qu'un envoi renvoie.

Ces doubles ne dépendent que de `MatrixClientKitCore`, qui ne lie aucun XCFramework : la suite de
tests de votre application s'exécute sans embarquer le binaire Rust, et démarre à la vitesse
habituelle.

### Ajouter le produit à votre cible de tests

```swift
.testTarget(
    name: "MonAppTests",
    dependencies: [
        "MonApp",
        .product(name: "MatrixClientKitMocks", package: "MatrixClientKit"),
    ]
)
```

## Les quatre doubles

| Double | Remplace | Piloté par |
| --- | --- | --- |
| `MockMatrixSession` | ``MatrixSession`` | `didLogout` |
| `MockRoomService` | ``RoomService`` | `emit(_:)`, `finish()` |
| `MockSyncController` | ``SyncController`` | `emit(_:)`, `finish()`, `startCallCount` |
| `MockTimeline` | ``Timeline`` | `emit(_:)`, `finish()`, `sentMessages`, `sendError` |

Les trois doubles porteurs d'un flux exposent la **même paire** : `emit(_:)` pousse une valeur,
`finish()` termine le flux.

## Piloter un flux

Un `AsyncStream` ne se termine pas tout seul : une boucle `for await` tourne jusqu'à ce que la
source appelle `finish()`. Un test qui itère jusqu'au bout doit donc terminer le flux lui-même,
sinon il pend au lieu d'échouer.

```swift
import Testing
import MatrixClientKitCore
import MatrixClientKitMocks

@Test func laTimelineAfficheLesMessagesRecus() async {
    let timeline = MockTimeline()
    let stream = timeline.items

    timeline.emit([SampleData.message("bonjour", from: "@alice:matrix.org")])
    timeline.finish()

    var reçus: [[TimelineItem]] = []
    for await items in stream {
        reçus.append(items)
    }

    #expect(reçus.count == 1)
    #expect(reçus.first?.first?.message?.body == "bonjour")
}
```

Pour ne consommer qu'une valeur sans terminer le flux, un itérateur explicite évite d'avoir à
sortir de la boucle :

```swift
var iterator = timeline.items.makeAsyncIterator()
let premier = await iterator.next()
```

> Important: chaque accès à ``Timeline/items`` — comme chaque appel à ``RoomService/list(filter:)``
> — ouvre un abonnement indépendant. Conservez le flux dans une variable si vous voulez que deux
> lectures observent la même chose.

## Vérifier un filtre

`MockRoomService` applique réellement le filtre qu'on lui passe. Un test qui affirme « les rooms
en invitation n'apparaissent pas dans la liste principale » vérifie donc quelque chose :

```swift
@Test func lesInvitationsSontHorsDeLaListePrincipale() async throws {
    let service = MockRoomService(rooms: SampleData.roomSummaries(count: 3))

    var iterator = service.list(filter: .joined).makeAsyncIterator()
    let rooms = try #require(await iterator.next())

    #expect(rooms.count == 3)
    #expect(rooms.allSatisfy { $0.membership == .joined })
}
```

`emit(_:)` remplace la liste et la republie, filtrée, dans chaque flux ouvert — de quoi tester
qu'une vue se met à jour quand une room arrive.

## Simuler un échec

`MockTimeline.sendError` fait échouer le prochain envoi (et la prochaine pagination) avec
l'erreur de votre choix. C'est le moyen de tester le chemin d'erreur sans provoquer une vraie
panne réseau :

```swift
@Test func unEnvoiHorsLigneRemonteALInterface() async {
    let timeline = MockTimeline()
    timeline.sendError = .network(.offline)

    await #expect(throws: MatrixError.network(.offline)) {
        try await timeline.send(.text("salut"))
    }
}
```

Sans `sendError`, `send(_:)` réussit et enregistre le contenu dans `sentMessages`, ce qui permet
de vérifier *ce que* votre code a envoyé :

```swift
#expect(timeline.sentMessages == [.text("salut")])
```

## Une session complète

`MockMatrixSession` assemble les trois autres doubles et enregistre la déconnexion :

```swift
@Test func laDeconnexionEstPropagee() async throws {
    let session = MockMatrixSession()

    try await session.logout()

    #expect(session.didLogout)
}
```

Les doubles internes restent accessibles pour être pilotés :

```swift
let rooms = MockRoomService()
let sync = MockSyncController()
let session = MockMatrixSession(rooms: rooms, sync: sync)

await session.sync.start()
#expect(sync.startCallCount == 1)

rooms.emit(SampleData.roomSummaries(count: 5))
rooms.timeline.emit([SampleData.message("bonjour")])
```

## Ce que les mocks ne remplacent pas

Un double reproduit la **forme** de l'API, pas le comportement du SDK Rust : ni le chiffrement, ni
la pagination réelle, ni la reprise d'envoi. Les chemins qui dépendent du serveur — connexion,
sync, écho local d'un message envoyé — se vérifient contre un vrai homeserver, dans la suite
d'intégration du dépôt, lancée à la main avant chaque montée de version du SDK amont.
