# MatrixClientKit 0.6 — décisions prises pendant l'exécution

Arbitrages pris pendant l'exécution du plan, dans l'ordre. Chaque ligne : décision — raison — coût si elle est fausse.

## T10 — Intégration : accusés et frappe

- Ruling: seconde session = `MCK_HARNESS_OTHER_USER`/`MCK_HARNESS_OTHER_PASSWORD` (exportés par `env`) et non le compte admin demandé par la feuille de tâche — le script n'exporte que des jetons admin (`MCK_HARNESS_ADMIN_TOKEN_*`), pas le mot de passe ; le modifier est exclu — coût si faux : remplacer `otherUser` par un compte admin dans `withTwoSessions` si T11 en a besoin.
- Ruling: salon à deux membres créé par l'API brute (`createSharedRoom` : création, invitation, `join`) et renommé par l'API brute (`renameRoom`, `PUT m.room.name`) — l'API publique n'expose ni adhésion ni modification de salon — coût si faux : aucun.
- Ruling: `TimelineRecorder`, `signedInSession` et `openTimeline` déplacés de `MediaHarnessTests.swift` (privés) vers `HarnessSupport.swift` pour être partagés (comportement inchangé).

Constats établis par l'exécution réelle sur le harnais (4 scénarios sur 6 passent ; à reprendre en T12, *Behaviours to know*) :

- Constat amont: accusé implicite de l'expéditeur — présent : B voit l'accusé de `@mck-user` (l'expéditeur) sur le propre message de A. Gardé tel quel, documenté (risque du §12).
- Constat amont: filtrage de l'utilisateur courant — effectif côté package : chacun ne voit que l'autre dans les accusés (A ne voit jamais `@mck-user`, B ne voit jamais `@mck-other` sur sa propre timeline) et dans la frappe (A ne se voit jamais taper).
- Constat amont: critère 14 (I) — le renommage du salon est visible dans la timeline par défaut (`unsupported(m.room.name)`) et porte l'accusé de B chez A, pas le message précédent. Aucun repli sur un message supprimé nécessaire.
- Constat amont: fréquence de frappe — 10 `setTyping(true)` espacés de 200 ms en ~2,09 s, 0 échec, 5 instantanés reçus par A : l'amont regroupe les envois répétés, le package n'ajoute aucune limitation.
- Écart (cause établie, voir la ligne suivante) : `privateReceiptStaysInvisibleToTheSender` et `markAsReadClearsTheNotificationCount` (critères 1 `.private` et 2) échouent à l'attente `notificationCount >= 1` de B : le flux `rooms.list(filter: .joined)` de B émet un seul instantané (`count 0`), reste ouvert (pas terminé) et n'émet plus rien après le message de A. Cause non tranchée : soit le flux de liste ne ré-émet pas sur un changement de compteur (amont ou mappeur), soit le compteur serveur est réellement 0 pour B. Le diagnostic (sondage par souscription neuve, qui relit `roomInfo()`) n'a pas pu être exécuté : le binaire reconstruit a de nouveau bloqué sur l'autorisation Keychain, processus tué. Aucune assertion n'a été affaiblie et le code de production n'a pas été touché.
- Ruling: cause établie par le diagnostic du coordinateur (15 abonnements neufs à `rooms.list` relisent tous `count 0` : la liste se réémet, la valeur source ne monte jamais) : `RoomMapper` lisait `RoomInfo.notificationCount` / `highlightCount`, les compteurs serveur que la sliding sync ne fournit pas. DÉCISION DE L'UTILISATEUR : corriger en 0.6. Correction : `RoomSummary.notificationCount` ← `numUnreadNotifications` et `highlightCount` ← `numUnreadMentions` (calculés par le SDK selon les réglages de notification, comme Element X), bornés comme avant (`RoomMapper.unreadCounts(from:)`, `RoomMapperCountsTests`) ; doc de `RoomSummary` et CHANGELOG (*Fixed*) mis à jour. Les deux scénarios restent à confirmer sur le harnais, exécuté par l'utilisateur — coût si faux : un compteur encore à 0 côté harnais signifierait des règles de notification (push rules) à examiner.
- Constat amont: l'adhésion d'un membre lui donne un accusé implicite sur son propre événement d'adhésion (posé par le serveur quand il rejoint), visible des autres membres : chez A, `unsupported(m.room.member)` porte l'accusé de `@mck-other` avant toute lecture. À reprendre en T12 (*Behaviours to know*). Le test `.private` vérifie donc que B n'a aucun accusé sur le message de A ni sur un item postérieur, pas sur toute la timeline (l'assertion initiale était trop large).

Commande de reprise (hors agent, avec le Keychain déverrouillé et « Toujours autoriser » accordé au binaire de test) :

    ./Scripts/integration-harness.sh up
    eval "$(./Scripts/integration-harness.sh env)"
    swift test --filter 'MatrixClientKitIntegrationTests\.HarnessTests/RoomActivityHarnessTests'
    ./Scripts/integration-harness.sh down

## T11 — Intégration : profil, présence, compte, durée de vie

Suite `ProfileAndAccountHarnessTests` écrite, **non exécutée** (blocage Keychain au premier login) ; constats sondés par HTTP sur le harnais réel avant écriture.

- Ruling: comptes — `mck-user` pour présence, profil, ignorés et durée de vie (nom, avatar, utilisateur ignoré remis en l'état en sortie) ; `mck-other` en lecture seule (profil, cible de `ignore`) ; compte jetable `mck-t11-<hex>` créé par `PUT /_synapse/admin/v2/users/{id}` avec `MCK_HARNESS_ADMIN_TOKEN_PASSWORD` et désactivé par l'API admin en sortie. Script du harnais inchangé.
- Ruling: `OAuthHarnessTests.swift` gagne `OAuthSignIn` (façade interne autour de `OAuthHarness`, qui reste privé car ses méthodes manipulent des types privés du fichier) — coût si faux : aucun.
- Constat amont (sondé): MAS annonce `account_management_uri` = `http://localhost:8082/account/` (et `issuer` en `http://`). La règle « https seul » de `AccountMapper` lèvera donc `.unexpected` : `managementURLPointsAtMASOnAnOAuthHomeserver` ÉCHOUERA sur ce harnais, attendu. Règle et test non affaiblis ; à trancher par l'utilisateur (MAS du harnais en https, ou exception loopback documentée).
- Constat amont (sondé): `PUT /presence/{id}/status` est limité en débit (`M_LIMIT_EXCEEDED`, `retry_after_ms` ≈ 10 s) dès la deuxième mise à jour consécutive. Le test rejoue après le délai annoncé ; à documenter en T12 (`setPresence` peut lever `.rateLimited`).
- Constat amont (sondé): après `deactivate`, Synapse répond `M_FORBIDDEN "Invalid username or password"` (le mot de passe est effacé) et non `M_USER_DEACTIVATED` : une connexion ultérieure donnera `.authentication(.invalidCredentials)`, pas `.userDeactivated` (critère 10 du PRD). Le test accepte les deux et imprime l'erreur reçue `[T11]`. UIAA confirmé : premier appel sans auth → 401 avec flux `m.login.password` ; mauvais mot de passe → `M_FORBIDDEN` ; bon → 200.
- Constat amont (sondé): `GET /profile/@inconnu` → 404 `M_UNKNOWN` ; le remappage `.notFound(.unspecified)` → `.notFound(.user)` reste à confirmer côté SDK (`[T11]` dans le message d'échec).
- À constater à l'exécution : état de présence lu avant tout `setPresence` (`[T11] presence read over HTTP…`) ; nombre d'émissions de `ignoredUsers`/`typingUsers` avant `logout()`.

Commande de reprise (Keychain déverrouillé, accès accordé au binaire de test) :

    ./Scripts/integration-harness.sh up
    eval "$(./Scripts/integration-harness.sh env)"
    swift test --filter 'MatrixClientKitIntegrationTests\.HarnessTests/ProfileAndAccountHarnessTests'
    ./Scripts/integration-harness.sh down

Avec la suite de T10 : `--filter 'MatrixClientKitIntegrationTests\.HarnessTests/(RoomActivityHarnessTests|ProfileAndAccountHarnessTests)'`.
