# Harnais d'intégration Synapse

Trois serveurs Synapse locaux (image épinglée dans `docker-compose.yml`) : `synapse-password` sur
`http://localhost:8008` (mot de passe, e-mail lié par l'API admin) et `synapse-expiring` sur
`http://localhost:8009`, identique mais avec un jeton d'accès de 20 s, ce qui provoque un soft logout.
Prérequis : Docker doit être en cours d'exécution. Les ports ne sont exposés que sur 127.0.0.1.
Le jeton d'accès de `synapse-expiring` ne vit que 20 s : tout client connecté y subit un soft logout après ce délai.
Ce répertoire n'est pas une cible SwiftPM ; le harnais se lance à la main, jamais en CI.

`Scripts/integration-harness.sh up` démarre les conteneurs et crée les comptes de test ;
`Scripts/integration-harness.sh test` récupère les variables `MCK_HARNESS_*`, génère le projet Tuist
`IntegrationHost/` et lance `HarnessTests` avec `xcodebuild` (voir plus bas) ;
`Scripts/integration-harness.sh down` arrête tout et efface les volumes.

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

## Lancer la suite (macOS signé)

La suite n'est plus une cible SwiftPM : le trousseau data protection refuse (`-34018`) tout
exécutable non signé avec `keychain-access-groups`, et `swift test` ne signe pas. Elle tourne donc
dans l'hôte signé `IntegrationHost`, projet Tuist du répertoire `IntegrationHost/` (sources de la suite
dans `Tests/MatrixClientKitIntegrationTests`, seeder dans `Tests/IntegrationLegacySeeder`).

Prérequis : macOS, Xcode 26 connecté à un compte développeur (signature automatique), Tuist (`mise
install`) et votre Team ID dans `TUIST_MCK_DEVELOPMENT_TEAM` (défaut : celui du mainteneur,
`59ZC26E65Z`).

    Scripts/integration-harness.sh up
    Scripts/integration-harness.sh test        # HarnessTests (défaut)
    Scripts/integration-harness.sh down

L'argument de `test` est un identifiant `-only-testing` de xcodebuild :
`Scripts/integration-harness.sh test IntegrationHostTests/HarnessTests/<cas>` n'en lance qu'un.
Les variables `MCK_HARNESS_*` (et `MATRIX_TEST_*`) ne parviennent au processus de test que préfixées
par `TEST_RUNNER_` : le script le fait lui-même. À la main, après `eval "$(Scripts/integration-harness.sh env)"` :
`TEST_RUNNER_MCK_HARNESS_USER="$MCK_HARNESS_USER" …`.

La suite `HarnessTests` (ce harnais) et la suite `IntegrationTests` (Tuwunel, variables
`MATRIX_TEST_*`) sont chacune sérialisée, mais pas l'une par rapport à l'autre : le Keychain ne
garde qu'une session persistée par processus. Lancer les deux l'une après l'autre, jamais ensemble :

    Scripts/integration-harness.sh test IntegrationHostTests/HarnessTests
    ./Scripts/check-integration-env.sh && Scripts/integration-harness.sh test IntegrationHostTests/IntegrationTests

`-only-testing` est un préfixe d'identifiant exact (`Cible/Suite/cas`), pas une expression
régulière : `IntegrationHostTests/IntegrationTests` ne sélectionne pas `HarnessTests`.

Le cas de soft logout attend jusqu'à 60 s que le jeton de 20 s de `synapse-expiring` soit refusé.
Les appareils qu'il ouvre ne peuvent pas être déconnectés côté serveur (jeton expiré) : ils
s'accumulent sur le compte de `synapse-expiring` jusqu'au prochain `down`.
