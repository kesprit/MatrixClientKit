# Changelog

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le versionnage suit
[SemVer](https://semver.org/lang/fr/).

## [0.1.1] - 2026-09-13

### Corrigé

- Les sessions rafraîchies par le SDK sont désormais persistées. Le rafraîchissement automatique
  des jetons est actif par défaut : sans delegate de session, un jeton rafraîchi ne vivait qu'en
  mémoire, la session enregistrée se périmait en silence, et l'utilisateur se retrouvait
  déconnecté au lancement suivant sans qu'aucune erreur n'ait été signalée.
- Le delegate refuse de servir une session appartenant à un autre utilisateur que celui demandé.

### Modifié

- `SessionPersistence` devient un type synchrone. Le stockage sous-jacent est déjà sûr en
  concurrence, et le delegate de session du SDK est appelé de façon synchrone. Aucune API publique
  n'est affectée.

## [0.1.0] - 2026-09-13

### Ajouté

- Authentification par mot de passe et restauration de session persistée.
- Stockage App Group et Keychain, configuré pour les extensions.
- Contrôle de la synchronisation et flux d'état.
- Liste de rooms observable, livrée en instantanés.
- Timeline observable, pagination arrière et envoi de messages texte.
- `MatrixError`, erreurs typées avec `isRetryable` et `retryAfter`.
- Produit `MatrixClientKitMocks` pour les tests des applications.
- Matrix Rust SDK embarqué : 26.09.07.

### Validé

- Chemin complet éprouvé contre un homeserver réel (Tuwunel 1.8.1) : connexion, synchronisation,
  liste de rooms, envoi de message et écho local.
