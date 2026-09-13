# MatrixClientKit

Un package Swift pour construire des clients [Matrix](https://matrix.org) sur iOS et macOS,
adossé au [Matrix Rust SDK](https://github.com/matrix-org/matrix-rust-sdk) officiel.

```swift
let client = Matrix.client(
    homeserver: URL(string: "https://matrix.org")!,
    storage: .appGroup("group.com.exemple.app")
)
let session = try await client.login(.password(username: "alice", password: "…", deviceName: "iPhone"))
await session.sync.start()

for await rooms in session.rooms.list(filter: .joined) {
    self.rooms = rooms          // liste complète et à jour, aucun diff à appliquer
}
```

## Ce que le package apporte

- **Flux asynchrones.** Les abonnements à listeners du SDK Rust deviennent des `AsyncStream`
  dont le cycle de vie est géré automatiquement : sortir d'une boucle annule l'abonnement amont
  (à condition de ne pas conserver le flux dans une propriété).
- **Instantanés, pas de diffs.** Listes de rooms et timelines arrivent sous forme d'état complet
  et à jour : pas de diff à appliquer vous-même.
- **Erreurs typées.** `MatrixError` avec `isRetryable` et `retryAfter`.
- **Stockage prêt pour les extensions.** App Group, Keychain et protection de fichiers
  configurés pour qu'une extension de notification fonctionne appareil verrouillé.
- **Testable.** Toute l'API publique repose sur des protocoles, et le produit
  `MatrixClientKitMocks` fournit des doubles pilotables qui ne lient aucun binaire du SDK Rust.

## Périmètre

La v0.1 couvre l'authentification par mot de passe, la session persistée, la synchronisation, la
liste de rooms, la timeline et l'envoi de messages texte.

Le chiffrement de bout en bout est **actif** dès aujourd'hui — il est assuré directement par le
SDK Rust, sans opt-in de votre part. En revanche, la v0.1 **n'expose pas** :

- la vérification d'appareils (cross-signing, SAS) ;
- la récupération et la sauvegarde de clés ;
- les notifications push et l'extension de service associée.

Si votre application a besoin de l'un de ces trois points dès maintenant, cette version ne
convient pas encore. Voir la feuille de route ci-dessous.

`MatrixClient.loginDetails()` — qui décrit les modes de connexion acceptés par un homeserver — est
prévu mais **non implémenté** en v0.1 : une application qui doit interroger le homeserver avant de
présenter un écran de connexion devra attendre. Son absence est un choix, pas un oubli.

| Version | Contenu |
| --- | --- |
| 0.1 | Socle : auth, session, sync, rooms, timeline, envoi texte |
| 0.2 | Vérification d'appareils, récupération et sauvegarde de clés |
| 0.3 | Notifications push et extension de service |
| 0.4 | Médias, accusés de lecture, frappe, présence, compte, OAuth, `loginDetails()` |
| 1.0 | Gel de l'API |

## Installation

```swift
.package(url: "https://github.com/kesprit/MatrixClientKit", from: "0.1.0")
```

## Compatibilité

| MatrixClientKit | Matrix Rust SDK embarqué | iOS | macOS | Swift |
| --- | --- | --- | --- | --- |
| 0.1.x | 26.09.07 | 18+ | 15+ | 6.2+ |

## Erreurs : règle d'évolution

Toutes les erreurs du package sont des `MatrixError`, un enum public. Dans un package SPM, un enum
public est exhaustif côté consommateur : **ajouter un cas casserait la compilation de votre
application**, ce qui imposerait une version majeure à chaque release du SDK amont.

La règle retenue, pour la durée d'une version majeure :

> Les cas de premier niveau de `MatrixError` sont **figés**. Toute erreur que le SDK amont
> permettrait nouvellement de distinguer atterrit dans `.unexpected(message:details:)` jusqu'à la
> prochaine version majeure.

Concrètement : votre `switch` sur `MatrixError` reste exhaustif sans `default` d'une version
mineure à l'autre, mais un cas traité aujourd'hui par `.unexpected` peut le rester longtemps —
n'écrivez pas de logique métier qui dépende du contenu textuel de `.unexpected`. Les enums
imbriqués (`MatrixError.Authentication`, `.Network`, …) suivent la même règle.

## Note sur l'API

`MatrixClientKit` n'expose ni ne renvoie jamais un type du SDK Rust dans une signature publique.
Cela dit, SPM ne permet pas de masquer un module transitif : `MatrixRustSDK` reste techniquement
importable depuis votre application, qui dépend elle-même de `matrix-rust-components-swift` de
façon transitive. Vous n'avez pas besoin de l'importer, et l'API de ce package ne vous y oblige
jamais — mais l'affirmation porte sur les signatures de MatrixClientKit, pas sur une invisibilité
du module lui-même.

## Documentation

La documentation de référence (DocC) est générée depuis
`Sources/MatrixClientKit/Documentation.docc`. Voir aussi
[`CONTRIBUTING.md`](CONTRIBUTING.md) pour contribuer et
[`CHANGELOG.md`](CHANGELOG.md) pour l'historique des versions.

## Licence

Apache-2.0. Ce projet embarque le Matrix Rust SDK, également sous Apache-2.0. Voir
[`NOTICE`](NOTICE).
