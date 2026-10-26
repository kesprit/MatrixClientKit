# MatrixClientKit 0.5 — décisions prises pendant l'exécution

Arbitrages pris par le contrôleur pendant l'exécution du plan en mode subagent-driven, dans l'ordre. Chaque ligne : décision — raison — coût si elle est fausse.

- Ruling: exécution sur la branche feat/v0.5-media du checkout principal, sans worktree — harnais Docker/Keychain lié à la machine, comme en 0.4 — coût si faux : nul côté code.
- Ruling: spec rédigée sans séance de questions, à la demande de l'utilisateur (« déroule tout d'un trait ») — arbitrages marqués « décision de rédaction » dans la spec — coût si faux : reprise d'API avant 1.0.
- upstreamJSON dans Hashable/Codable — Ruling: voulu ; deux sources de même URL mais de JSON différent (clés différentes) sont des médias distincts — coût si faux : clé de cache dupliquée.
- SampleData.imageMessage rend TimelineItem et non Message — Ruling: accepté, cohérent avec SampleData.message(...) voisin — coût si faux : un .message à l'appel.
- preuve §5 du service média — Ruling: le test de durée de vie de T9 garde aussi `media` et un `MediaFile` — coût nul.
- câblage réel du registre et hypothèse du reset initial par addListener — Ruling: couverts en T9 (échec puis sendHandle non nil ; écho local) — coût nul.
- envoi réel vers la Timeline FFI non testé unitairement — Ruling: couvert en T9 — coût nul.
- Ruling: AttachmentUpload redéfini (API non publiée, renommage gratuit) : `waitUntilSent()` → `waitUntilQueued()` (rend la main quand l'écho local est dans la file / la timeline) ; `cancel()` n'arrête que la préparation ; une fois en file, l'annulation passe par `sendHandle(for:)` de l'écho, dont l'effet sur un upload en cours doit être prouvé en intégration — la corrélation par subscribeToSendQueueUpdates est ambiguë avec des envois concurrents — coût si faux : un renommage d'API avant 1.0.
- Ruling: plafond de 50 rooms de RoomService.list (pageSize: 50, antérieur à 0.5) hors périmètre ; documenté en limitation connue, proposé en tâche séparée — coût si faux : room introuvable au-delà de 50 pour une appli.
- Ruling: deinit de RustTimeline dans son propre callback non atteint (0/31) — parqué ; le scénario survit — coût si faux : crash non prouvé dans un cas rare.
- Ruling: commit de lint swift-format --strict (785260b) conservé — l'étape Lint de la CI échouait déjà sur 602f93b ; préfixe test: au lieu de style: — coût si faux : un commit à retirer.
