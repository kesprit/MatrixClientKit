# Harnais d'intégration Synapse

Trois serveurs Synapse locaux (image épinglée dans `docker-compose.yml`) : `synapse-password` sur
`http://localhost:8008` (mot de passe, e-mail lié par l'API admin) et `synapse-expiring` sur
`http://localhost:8009`, identique mais avec un jeton d'accès de 20 s, ce qui provoque un soft logout.
Prérequis : Docker doit être en cours d'exécution. Les ports ne sont exposés que sur 127.0.0.1.
Le jeton d'accès de `synapse-expiring` ne vit que 20 s : tout client connecté y subit un soft logout après ce délai.
Ce répertoire n'est pas une cible SwiftPM ; le harnais se lance à la main, jamais en CI.

`Scripts/integration-harness.sh up` démarre les conteneurs et crée les comptes de test ;
`eval "$(Scripts/integration-harness.sh env)"` exporte les variables `MCK_HARNESS_*` ; puis
`swift test --filter <suite>` ; `Scripts/integration-harness.sh down` arrête tout et efface les volumes.

Tous les secrets de ce répertoire (secret d'enregistrement, mots de passe, clés) sont des valeurs
de TEST, sans valeur hors de ce harnais local.

## Synapse délégué à MAS (`synapse-oauth`)

`synapse-oauth` (`http://localhost:8010`, Postgres) délègue l'authentification à Matrix Authentication
Service 1.26.0 (`mas`, `http://localhost:8082`, `mas/config.yaml`) ; l'`issuer` annoncé par
`/_matrix/client/v1/auth_metadata` est `http://localhost:8082/`, joignable depuis l'hôte (le SDK le
contacte directement) ; Synapse joint MAS par le réseau compose (`http://mas:8080/`). Le compte
`mck-oauth-user` est créé dans MAS par `mas-cli manage register-user` (pas de
`registration_shared_secret`). Variables : `MCK_HARNESS_OAUTH_HOMESERVER`, `MCK_HARNESS_MAS`,
`MCK_HARNESS_OAUTH_USER`, `MCK_HARNESS_OAUTH_PASSWORD`.

- MAS est publié sur **8082**, non 8080 : ce port hôte est fréquemment occupé (autre conteneur).
- Le rendez-vous de la connexion par QR (MSC4108) est activé par `experimental_features.msc4108_enabled`
  (option confirmée dans le code de Synapse v1.162.0) ; `up` vérifie que
  `/_matrix/client/unstable/org.matrix.msc4108/rendezvous` n'est pas en 404.
- MAS accepte sans réglage particulier les `issuer` et URI de redirection en `http://localhost` ; un
  client natif doit déclarer un `client_uri` et un schéma personnalisé en DNS inversé de son hôte
  (`org.example:/callback` pour `https://example.org/`) ou une URI loopback `http://127.0.0.1/...`.
- Ports 8010 et 8082 liés à 127.0.0.1 ; secrets (config MAS, secret partagé, mots de passe Postgres)
  sont tous des valeurs de TEST.
