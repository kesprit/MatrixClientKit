# Contribuer

## Avant d'ouvrir une pull request

    swift build
    swift test --skip MatrixClientKitIntegrationTests

Les tests d'intégration ne s'exécutent pas par défaut : voir
`Tests/MatrixClientKitIntegrationTests/README.md`.

## Règles d'architecture

- `MatrixClientKitCore` ne doit **jamais** importer `MatrixRustSDK`. C'est ce qui garantit
  qu'aucun type amont ne fuite dans l'API publique.
- Aucun type du SDK Rust ne doit apparaître dans une signature `public`.
- Pas de `@MainActor` dans `Core` ni dans `Rust`.
- Les flux de diffs utilisent `.unbounded`, les flux d'instantanés `.bufferingNewest(1)`.

## Ajout d'un cas à `MatrixError`

Les cas de premier niveau sont figés pour la durée d'une version majeure. Une erreur
nouvellement distinguable doit être rapportée dans `.unexpected` jusqu'à la prochaine majeure :
ajouter un cas casserait la compilation des applications.

## Montée de version du SDK Rust

1. Mettre à jour la version épinglée dans `Package.swift`.
2. Lancer la suite d'intégration contre un homeserver réel (voir
   `Tests/MatrixClientKitIntegrationTests/README.md`).
3. Mettre à jour le tableau de compatibilité du README et le CHANGELOG.
