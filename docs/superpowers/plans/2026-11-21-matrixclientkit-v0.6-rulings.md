# MatrixClientKit 0.6 — décisions prises pendant l'exécution

Arbitrages pris pendant l'exécution du plan, dans l'ordre. Chaque ligne : décision — raison — coût si elle est fausse.

## T10 — Intégration : accusés et frappe

- Ruling: exécution harnais de T10 NON EFFECTUÉE — le test de `RoomActivityHarnessTests` se bloque dans `KeychainSecureStore.data(forKey:)` (`SessionPersistence.load()`, premier `login`) : l'entrée du Keychain de connexion `com.matrixclientkit` (créée le 2026-09-26 par un autre binaire de test) n'est lisible qu'après une validation graphique de macOS (SecurityAgent lancé), impossible dans une session sans écran ni mot de passe — coût si faux : aucun constat amont n'est établi ; les six scénarios restent à exécuter par l'utilisateur (voir ci-dessous). La même chose arrive à toute suite harnais lancée depuis un nouveau worktree (binaire de test différent). Aucun élément du Keychain n'a été modifié ni supprimé.
- Ruling: seconde session = `MCK_HARNESS_OTHER_USER`/`MCK_HARNESS_OTHER_PASSWORD` (exportés par `env`) et non le compte admin demandé par la feuille de tâche — le script n'exporte que des jetons admin (`MCK_HARNESS_ADMIN_TOKEN_*`), pas le mot de passe ; le modifier est exclu — coût si faux : remplacer `otherUser` par un compte admin dans `withTwoSessions` si T11 en a besoin.
- Ruling: salon à deux membres créé par l'API brute (`createSharedRoom` : création, invitation, `join`) et renommé par l'API brute (`renameRoom`, `PUT m.room.name`) — l'API publique n'expose ni adhésion ni modification de salon — coût si faux : aucun.
- Ruling: `TimelineRecorder`, `signedInSession` et `openTimeline` déplacés de `MediaHarnessTests.swift` (privés) vers `HarnessSupport.swift` pour être partagés (comportement inchangé).
- À constater à la première exécution réelle (non établi, ne pas reporter en T12 comme un fait) : accusé implicite de l'expéditeur visible chez B (imprimé `[T10] receipts on B's view…`) ; filtrage de l'utilisateur courant dans les accusés et la frappe (assertions du test) ; fréquence de frappe (imprimée `[T10] 10 setTyping(true)…`) ; le changement de nom (`m.room.name`) est-il visible dans la timeline par défaut (imprimé `[T10] B's timeline after the rename`) — sinon utiliser un message supprimé (critère 14, risque du §12) et le consigner ici.

Commande de reprise (hors agent, avec le Keychain déverrouillé et « Toujours autoriser » accordé au binaire de test) :

    ./Scripts/integration-harness.sh up
    eval "$(./Scripts/integration-harness.sh env)"
    swift test --filter 'MatrixClientKitIntegrationTests\.HarnessTests/RoomActivityHarnessTests'
    ./Scripts/integration-harness.sh down
