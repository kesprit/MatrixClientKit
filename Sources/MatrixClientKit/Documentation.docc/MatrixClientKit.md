# ``MatrixClientKit``

Construire un client Matrix en Swift, sans manipuler l'API FFI du SDK Rust.

## Overview

MatrixClientKit enveloppe le Matrix Rust SDK officiel derrière une API Swift moderne :
`async`/`await`, `AsyncStream`, types `Sendable` et erreurs typées. Les listes de rooms et les
timelines sont exposées sous forme d'**instantanés** — vous recevez l'état complet et à jour,
sans jamais appliquer un diff vous-même.

La v0.1 couvre l'authentification par mot de passe, la session persistée, la synchronisation, la
liste de rooms, la timeline et l'envoi de messages texte. Voir <doc:GettingStarted> pour un
premier flux complet, et le README du dépôt pour ce que cette version ne couvre pas encore.

## Topics

### Prise en main

- <doc:GettingStarted>

### Point d'entrée

- ``Matrix``
- ``MatrixClient``
- ``Credentials``
- ``MatrixSession``

### Rooms et messages

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

### Synchronisation

- ``SyncController``
- ``SyncState``

### Stockage

- ``MatrixStorage``

### Identifiants

- ``UserID``
- ``RoomID``
- ``EventID``
- ``DeviceID``

### Erreurs

- ``MatrixError``
