# Harnais d'intégration Synapse

Deux serveurs Synapse locaux (image épinglée dans `docker-compose.yml`) : `synapse-password` sur
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
