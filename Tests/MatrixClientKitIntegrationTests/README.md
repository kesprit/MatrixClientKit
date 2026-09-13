# Tests d'intégration

Ces tests ne s'exécutent pas en intégration continue. Ils valident la chaîne complète contre un
homeserver réel et doivent être lancés **manuellement avant chaque montée de version du SDK Rust**.

## Lancement

    MATRIX_TEST_HOMESERVER=https://votre-homeserver \
    MATRIX_TEST_USERNAME=utilisateur \
    MATRIX_TEST_PASSWORD=secret \
    MATRIX_TEST_ROOM_ID='!room:votre-homeserver' \
    swift test --filter MatrixClientKitIntegrationTests

Sans ces variables, la suite est ignorée : c'est le comportement attendu en CI.

## Préalables sur le compte de test

Utilisez un compte **dédié** aux tests, pour les deux raisons suivantes :

- Le compte doit appartenir à **au moins une room rejointe** : `loginSyncAndListRooms` vérifie
  qu'un instantané de la liste de rooms jointes est non vide, pas seulement qu'il est cohérent.
- Ces tests envoient de vrais messages dans `MATRIX_TEST_ROOM_ID` et ouvrent une vraie session à
  chaque cas. Chaque test signe la session à sa fin — mais si un cas est interrompu ou dépasse sa
  minute impartie (`.timeLimit`), l'appareil peut rester enregistré côté serveur : le nettoyage
  s'exécute dans une tâche détachée pour maximiser ses chances d'atteindre le serveur même après
  une annulation, mais rien ne garantit que le homeserver l'aura traité avant que le processus ne
  se termine. Ne réutilisez donc pas ce compte pour autre chose, et purgez ses appareils de temps
  en temps si vous relancez la suite souvent.
