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

Utilisez un compte dédié aux tests. Ces tests envoient de vrais messages et ferment la session
à la fin de chaque cas.
