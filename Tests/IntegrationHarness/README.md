# Harnais d'intégration Synapse

Deux serveurs Synapse locaux (image épinglée dans `docker-compose.yml`) : `synapse-password` sur
`http://localhost:8008` (mot de passe, e-mail lié par l'API admin) et `synapse-expiring` sur
`http://localhost:8009`, identique mais avec un jeton d'accès de 20 s, ce qui provoque un soft logout.
Ce répertoire n'est pas une cible SwiftPM ; le harnais se lance à la main, jamais en CI.

`Scripts/integration-harness.sh up` démarre les conteneurs et crée les comptes de test ;
`eval "$(Scripts/integration-harness.sh env)"` exporte les variables `MCK_HARNESS_*` ; puis
`swift test --filter <suite>` ; `Scripts/integration-harness.sh down` arrête tout et efface les volumes.

Tous les secrets de ce répertoire (secret d'enregistrement, mots de passe, clés) sont des valeurs
de TEST, sans valeur hors de ce harnais local.
