# Politique de sécurité

## Signaler une faille

**Toute vulnérabilité affectant le protocole Matrix, le chiffrement de bout en bout ou le
Matrix Rust SDK doit être signalée à l'équipe matrix.org**, selon leur procédure de divulgation
responsable : https://matrix.org/security-disclosure-policy/

Pour une faille propre à MatrixClientKit — la couche Swift de ce dépôt, par exemple le stockage
des jetons ou la configuration du Keychain — ouvrez un avis de sécurité privé via l'onglet
Security de ce dépôt. N'ouvrez pas d'issue publique.

## Portée

Ce package n'implémente aucune primitive cryptographique. Le chiffrement est intégralement assuré
par le Matrix Rust SDK.
