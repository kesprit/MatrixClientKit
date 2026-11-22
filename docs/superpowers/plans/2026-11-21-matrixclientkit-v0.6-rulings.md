# MatrixClientKit 0.6 — décisions prises pendant l'exécution

Arbitrages pris pendant l'exécution du plan, dans l'ordre. Chaque ligne : décision — raison — coût si elle est fausse.

## T10 — Intégration : accusés et frappe

- Ruling: seconde session = `MCK_HARNESS_OTHER_USER`/`MCK_HARNESS_OTHER_PASSWORD` (exportés par `env`) et non le compte admin demandé par la feuille de tâche — le script n'exporte que des jetons admin (`MCK_HARNESS_ADMIN_TOKEN_*`), pas le mot de passe ; le modifier est exclu — coût si faux : remplacer `otherUser` par un compte admin dans `withTwoSessions` si T11 en a besoin.
- Ruling: salon à deux membres créé par l'API brute (`createSharedRoom` : création, invitation, `join`) — l'API publique n'expose pas d'adhésion à un salon — coût si faux : aucun.
- Ruling: écart au critère 14 (I) du PRD, qui parle d'un changement de nom d'affichage : le test renomme le SALON (`renameRoom`, `PUT m.room.name` par l'API brute). `ProfileService.setDisplayName` existe, mais le compte du harnais est partagé par toutes les suites : changer son nom d'affichage le laisserait modifié pour les autres cas (et produirait des événements d'adhésion dans tous ses salons). Un renommage de salon, propre au salon jetable du cas, éprouve la même règle (accusé sur un événement d'état non-message) — coût si faux : un second cas par nom d'affichage, en T11 si l'on veut le restaurer après.
- Ruling: `TimelineRecorder`, `signedInSession` et `openTimeline` déplacés de `MediaHarnessTests.swift` (privés) vers `HarnessSupport.swift` pour être partagés (comportement inchangé).

Constats établis par l'exécution réelle sur le harnais (exécution du 2026-11-22 : 6/6 PASS, journal `t10-run3.log` ; à reprendre en T12, *Behaviours to know*) :

- Constat amont: accusé implicite de l'expéditeur — présent : B voit l'accusé de `@mck-user` (l'expéditeur) sur le propre message de A. Gardé tel quel, documenté (risque du §12).
- Constat amont: filtrage de l'utilisateur courant — effectif côté package : chacun ne voit que l'autre dans les accusés (A ne voit jamais `@mck-user`, B ne voit jamais `@mck-other` sur sa propre timeline) et dans la frappe (A ne se voit jamais taper).
- Constat amont: critère 14 (I) — le renommage du salon est visible dans la timeline par défaut (`unsupported(m.room.name)`) et porte l'accusé de B chez A, pas le message précédent. Aucun repli sur un message supprimé nécessaire.
- Constat amont: fréquence de frappe — 10 `setTyping(true)` espacés de 200 ms en ~2,09 s, 0 échec, 5 instantanés reçus par A : l'amont regroupe les envois répétés, le package n'ajoute aucune limitation.
- Écart résolu: `privateReceiptStaysInvisibleToTheSender` et `markAsReadClearsTheNotificationCount` (critères 1 `.private` et 2) échouaient à l'attente `notificationCount >= 1` de B : le flux `rooms.list(filter: .joined)` émettait un seul instantané (`count 0`) sans rien de plus après le message de A. Cause et correction : ligne suivante.
- Ruling: cause établie par le diagnostic du coordinateur (15 abonnements neufs à `rooms.list` relisent tous `count 0` : la liste se réémet, la valeur source ne monte jamais) : `RoomMapper` lisait `RoomInfo.notificationCount` / `highlightCount`, les compteurs serveur que la sliding sync ne fournit pas. DÉCISION DE L'UTILISATEUR : corriger en 0.6. Correction : `RoomSummary.notificationCount` ← `numUnreadNotifications` et `highlightCount` ← `numUnreadMentions` (calculés par le SDK selon les réglages de notification, comme Element X), bornés comme avant (`RoomMapper.unreadCounts(from:)`, `RoomMapperCountsTests`) ; doc de `RoomSummary` et CHANGELOG (*Fixed*) mis à jour. Confirmé sur le harnais : `markAsReadClearsTheNotificationCount` passe (6/6 PASS) — le branchement dans `RoomMapper.summary(from:)` n'est couvert que par ce scénario, les tests unitaires ne couvrant que le choix des champs.
- Constat amont: l'adhésion d'un membre lui donne un accusé implicite sur son propre événement d'adhésion (posé par le serveur quand il rejoint), visible des autres membres : chez A, `unsupported(m.room.member)` porte l'accusé de `@mck-other` avant toute lecture. À reprendre en T12 (*Behaviours to know*). Le test `.private` vérifie donc que B n'a aucun accusé sur le message de A ni sur un item postérieur, pas sur toute la timeline (l'assertion initiale était trop large). De même, `receiptSitsOnTheStateEventAfterTheLastMessage` attend et asserte l'accusé de B sur l'item `m.room.name` identifié explicitement (pas sur « le premier item portant un accusé de B », qui serait l'adhésion), vérifie qu'il n'est plus sur l'adhésion ni sur le message, et ne passerait donc pas si `markAsRead` ne faisait rien.

Commande de reprise (hors agent, avec le Keychain déverrouillé et « Toujours autoriser » accordé au binaire de test) :

    ./Scripts/integration-harness.sh up
    eval "$(./Scripts/integration-harness.sh env)"
    swift test --filter 'MatrixClientKitIntegrationTests\.HarnessTests/RoomActivityHarnessTests'
    ./Scripts/integration-harness.sh down

## T11 — Intégration : profil, présence, compte, durée de vie

Suite `ProfileAndAccountHarnessTests` exécutée avec celle de T10 par le coordinateur : 14 cas sur 16 passaient au premier passage ; les deux échecs étaient de vrais défauts de production, corrigés ci-dessous. Après correction : 16/16 PASS (exécution du 2026-11-22, journal `t1011-run2.log`). Constats aussi sondés par HTTP avant écriture.

- Ruling: comptes — `mck-user` pour présence, profil, ignorés et durée de vie (nom, avatar, utilisateur ignoré remis en l'état en sortie) ; `mck-other` en lecture seule (profil, cible de `ignore`) ; compte jetable `mck-t11-<hex>` créé par `PUT /_synapse/admin/v2/users/{id}` avec `MCK_HARNESS_ADMIN_TOKEN_PASSWORD` et désactivé par l'API admin en sortie. Script du harnais inchangé.
- Ruling: `OAuthHarnessTests.swift` gagne `OAuthSignIn` (façade interne autour de `OAuthHarness`, qui reste privé car ses méthodes manipulent des types privés du fichier) — coût si faux : aucun.
- Constat amont (sondé): MAS annonce `account_management_uri` = `http://localhost:8082/account/` (et `issuer` en `http://`) : la règle « https seul » de `AccountMapper` aurait levé `.unexpected` sur le harnais.
- Ruling D4 (choix de l'utilisateur): exception loopback. `AccountMapper.managementURL(from:)` accepte `https` (casse ignorée) et `http` seulement si l'hôte est `localhost`, `*.localhost`, `127.0.0.0/8` ou `::1` ; tout le reste (http vers un autre hôte, `file:`, `javascript:`, schéma personnalisé) reste `.unexpected`. Tests paramétrés dans `AccountMapperTests` ; doc de `AccountService.managementURL(for:)` et CHANGELOG ajustés. `managementURLPointsAtMASOnAnOAuthHomeserver` accepte donc `http` ou `https` et vérifie l'hôte MAS (le test dépendait de l'ancienne règle) — coût si faux : une application hors développement local ne voit aucun changement (https seul).
- Constat amont (sondé): `PUT /presence/{id}/status` est limité en débit (`M_LIMIT_EXCEEDED`, `retry_after_ms` ≈ 10 s) dès la deuxième mise à jour consécutive. Le test rejoue après le délai annoncé ; à documenter en T12 (`setPresence` peut lever `.rateLimited`).
- Constat amont (sondé): après `deactivate`, Synapse répond `M_FORBIDDEN "Invalid username or password"` (le mot de passe est effacé) et non `M_USER_DEACTIVATED` : une connexion ultérieure donnera `.authentication(.invalidCredentials)`, pas `.userDeactivated` (critère 10 du PRD). Le test accepte les deux et imprime l'erreur reçue `[T11]`. UIAA confirmé : premier appel sans auth → 401 avec flux `m.login.password` ; mauvais mot de passe → `M_FORBIDDEN` ; bon → 200.
- Constat amont: un profil inconnu répond 404 `M_UNKNOWN` ("No row found (profiles)"), non `M_NOT_FOUND` : `profile(of:)` levait `.unexpected`. Correction : `RustProfileService.profile(of:)` mappe en `.notFound(.user)` un `ClientError.MatrixApi` de `kind` `.unknown` et de code `M_UNKNOWN` dont les détails portent `status_code: 404` (les liaisons n'exposent pas le statut HTTP : lecture du texte en dernier recours, documentée) ; un 404 ailleurs reste inchangé.
- Constat amont: au second appel de `deactivate`, Synapse refuse le mauvais mot de passe par une réponse UIAA (`ClientError.Generic`, détails `Api(Server(AuthResponse(UiaaInfo { … auth_error: Some(StandardErrorBody { kind: Forbidden, … }) })))`), non par `M_FORBIDDEN`. Correction : `RustAccountService.deactivate` mappe ce cas en `.authentication(.invalidCredentials)` (lecture du texte `auth_error: Some(StandardErrorBody { kind: Forbidden`, aucune structure exposée) ; tout autre échec garde son mappage.
- Constat amont (exécution): la présence lue par HTTP avant tout `setPresence` est `offline` (non `unavailable`) ; la connexion au compte désactivé donne `.authentication(.invalidCredentials)`, pas `.userDeactivated` ; le nombre d'émissions de `ignoredUsers` avant `logout()` varie d'une exécution à l'autre (1 au rejeu t1011-run2.log), le test n'en dépend pas. Repris en T12 (*Behaviours to know*).

Commande de reprise (Keychain déverrouillé, accès accordé au binaire de test) :

    ./Scripts/integration-harness.sh up
    eval "$(./Scripts/integration-harness.sh env)"
    swift test --filter 'MatrixClientKitIntegrationTests\.HarnessTests/ProfileAndAccountHarnessTests'
    ./Scripts/integration-harness.sh down

Avec la suite de T10 : `--filter 'MatrixClientKitIntegrationTests\.HarnessTests/(RoomActivityHarnessTests|ProfileAndAccountHarnessTests)'`.
