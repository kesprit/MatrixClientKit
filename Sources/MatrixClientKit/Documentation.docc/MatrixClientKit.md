# ``MatrixClientKit``

Construire un client Matrix en Swift, sans manipuler l'API FFI du SDK Rust.

## Overview

MatrixClientKit enveloppe le Matrix Rust SDK officiel derrière une API Swift moderne :
`async`/`await`, `AsyncStream`, types `Sendable` et erreurs typées. Les listes de rooms et les
timelines sont exposées sous forme d'**instantanés** — vous recevez l'état complet et à jour,
sans jamais appliquer un diff vous-même.

Voir <doc:GettingStarted> pour un premier flux complet, et <doc:TestingWithMocks> pour tester une
application qui en dépend.

## Ce que couvre la v0.1

Cette page peut être lue seule — le Swift Package Index l'affiche sans le README du dépôt — donc
les limites du palier sont rappelées ici.

La v0.1 couvre l'authentification par mot de passe, la session persistée, la synchronisation, la
liste de rooms, la timeline et l'envoi de messages texte.

Le chiffrement de bout en bout est **actif** dès aujourd'hui : il est assuré directement par le
SDK Rust, sans opt-in. En revanche, la v0.1 **n'expose pas** :

- la vérification d'appareils (cross-signing, SAS, QR) ;
- la récupération et la sauvegarde de clés ;
- les notifications push et l'extension de service associée ;
- les médias, les accusés de lecture, les indicateurs de frappe, la présence et le profil ;
- OAuth / OIDC, et `MatrixClient.loginDetails()`.

Deux points de comportement à connaître avant de dépendre de cette version :

- ``RoomService/list(filter:)`` et ``Timeline/items`` sont des `AsyncStream`, donc sans canal
  d'erreur : un abonnement qui échoue termine le flux **sans aucune valeur**. Un consommateur qui
  n'a reçu aucun instantané doit y lire un échec, pas un compte vide.
- Les cas de premier niveau de ``MatrixError`` sont figés pour la durée d'une version majeure :
  toute erreur nouvellement distinguable par le SDK amont atterrit dans
  ``MatrixError/unexpected(message:details:)`` jusqu'à la majeure suivante.

## Topics

### Prise en main

- <doc:GettingStarted>
- <doc:TestingWithMocks>

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
