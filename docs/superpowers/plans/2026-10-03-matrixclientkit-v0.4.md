# MatrixClientKit 0.4 — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** livrer l'authentification complète de MatrixClientKit — découverte du serveur,
`loginDetails()`, OAuth, e-mail, connexion par QR, reconnexion après soft logout — sur un store
local par session.

**Architecture:** les modèles et protocoles publics vivent dans `MatrixClientKitCore` ; toute
connexion passe par un type interne unique, `LoginAttempt`, qui construit d'emblée le client
SQLite chiffré d'un store identifié par un `storeID` aléatoire (la poignée de main en mémoire de la
0.1 disparaît). Un registre de baux protège les stores vivants d'un ramassage des stores orphelins.
La reconnexion construit un client neuf sur le même store et rend une nouvelle session.

**Tech Stack:** Swift 6.2 (mode de langage 6, concurrence stricte), SwiftPM, Swift Testing,
`matrix-rust-components-swift` 26.09.07 (inchangé), Docker Compose (Synapse, MAS, Postgres) pour
le harnais d'intégration.

**Spec:** `docs/superpowers/specs/2026-10-03-matrixclientkit-v0.4-design.md` — lire en entier avant
toute tâche ; le plan s'y réfère par numéro de section (§).

## Global Constraints

- Plateformes : `iOS 18`, `macOS 15` ; `swift-tools-version: 6.2` ; `swiftLanguageModes: [.v6]`.
- Amont épinglé `exact: "26.09.07"` — ne pas monter.
- `MatrixClientKitCore` n'importe jamais `MatrixRustSDK` ; aucun type amont dans une signature
  publique.
- `MatrixError` : aucun cas ajouté, ni au premier niveau ni dans les enums imbriqués (§6).
- Tout texte qui atteint une application (messages d'erreur, `description`, DocC) est en
  **anglais** ; commentaires de code, messages de commit, spec et plan en **français**.
- Documentation des types publics : `///` en anglais ; commentaires internes en français, au même
  niveau de densité que le code voisin (les « pourquoi », pas les « quoi »).
- Mots de passe et jetons ne figurent jamais dans une `description` : `<redacted>`.
- Lint : `swift format lint --recursive --strict Sources Tests` doit passer.
- Tests unitaires : `swift test --skip MatrixClientKitIntegrationTests` doit passer à la fin de
  chaque tâche.
- Commits : messages en français au format `type: résumé` (BLUF), terminés par
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Branche : `feat/v0.4-auth`.
- Version livrée : `0.4.0`.

## Review Focus

1. **Rafraîchissement de jeton qui perd le `storeID`.** `SessionDelegate.saveSessionInKeychain`
   reconstruit les données depuis la `Session` amont, qui ignore le `storeID` : sans fusion, le
   lancement suivant ouvre le chemin legacy et l'utilisateur voit un compte vide. Attendu : le
   `storeID` persisté est conservé pour le même utilisateur **et** le même appareil. → test en
   Task 5.
2. **Session remplacée qui efface le store de sa remplaçante.** Après `reauthenticate`,
   l'application peut encore appeler `logout()` sur l'ancienne session, ou l'amont peut livrer un
   `didReceiveAuthError(isSoftLogout: false)` tardif. Attendu : ni l'un ni l'autre n'efface rien.
   → test en Task 11.
3. **Ramassage d'un store vivant mais non persisté.** L'entrée Keychain de session est unique par
   service : une seconde connexion (autre compte, autre stockage dans le même processus) écrase la
   première. Attendu : un store ouvert par une session vivante du processus n'est jamais ramassé.
   → test en Task 6.
4. **Flux OAuth utilisé deux fois.** `complete` appelé deux fois, `complete` après `cancel`,
   `cancel` après un `complete` réussi. Attendu : un seul `complete` aboutit, `cancel` tardif ne
   purge jamais le store de la session ouverte. → test en Task 9.
5. **Saisie de serveur approximative.** `" matrix.org "`, `"@alice:matrix.org"`,
   `"https://matrix.example.com/"`, `""`. Attendu : espaces retirés, user ID réduit à son nom de
   serveur, chaîne vide rejetée en `.unexpected` sans appel réseau. → test en Task 8.

---

## Structure des fichiers

| Fichier | Rôle | Tâche |
| --- | --- | --- |
| `Tests/IntegrationHarness/docker-compose.yml` | Synapse mot de passe, Synapse à jeton court, (Task 13) Synapse + MAS + Postgres | 1, 13 |
| `Tests/IntegrationHarness/synapse-password/homeserver.yaml`, `synapse-expiring/homeserver.yaml` | Configs Synapse de test | 1 |
| `Tests/IntegrationHarness/synapse-oauth/homeserver.yaml`, `mas/config.yaml` | Configs Synapse délégué à MAS | 13 |
| `Scripts/integration-harness.sh` | `up` / `down` / `env` | 1, 13 |
| `Sources/MatrixClientKitCore/Models/Authentication.swift` | `LoginDetails`, `OAuthPrompt`, `OAuthConfiguration` | 2 |
| `Sources/MatrixClientKitCore/Services/MatrixClient.swift` | `Credentials.email` ; (Task 12) nouveaux membres | 2, 12 |
| `Sources/MatrixClientKitCore/Models/QRCodeLogin.swift` | `QRCodeLoginState`, `QRCodeLoginFailure`, `QRCodeLoginEvent` | 3 |
| `Sources/MatrixClientKitCore/Models/QRCodeLoginReducer.swift` | Machine à états pure | 3 |
| `Sources/MatrixClientKitCore/Services/OAuthLoginFlow.swift`, `QRCodeLogin.swift` | Protocoles publics | 4 |
| `Sources/MatrixClientKitMocks/MockOAuthLoginFlow.swift`, `MockQRCodeLogin.swift` | Doubles | 4 |
| `Sources/MatrixClientKitRust/Storage/StoreSegment.swift` | Segment legacy / session | 5 |
| `Sources/MatrixClientKitRust/Storage/StoragePaths.swift`, `LocalStore.swift` | Passent au segment | 5 |
| `Sources/MatrixClientKitRust/Storage/StoreRegistry.swift` | Baux sur les stores vivants | 6 |
| `Sources/MatrixClientKitRust/Storage/OrphanedStoreSweeper.swift` | Ramassage | 6 |
| `Sources/MatrixClientKitRust/LoginAttempt.swift` | Séquence unique de connexion | 7 |
| `Sources/MatrixClientKitRust/Bridge/LoginDetailsMapper.swift`, `ServerInput.swift` | Découverte | 8 |
| `Sources/MatrixClientKitRust/Bridge/OAuthMapper.swift`, `RustOAuthLoginFlow.swift` | OAuth | 9 |
| `Sources/MatrixClientKitRust/Bridge/QRCodeMapper.swift`, `RustQRCodeLogin.swift` | QR | 10 |
| `Sources/MatrixClientKitRust/SessionLifecycle.swift`, `RustMatrixSession.swift` | Reconnexion | 11 |
| `Sources/MatrixClientKit/MatrixClientKit.swift` | Fabriques `client(server:)`, `loginWithQRCode(scanned:)` | 8, 10 |
| `Tests/MatrixClientKitIntegrationTests/HarnessSupport.swift`, `MASDriver.swift` | Support harnais | 14, 15 |
| `Sources/MatrixClientKit/Documentation.docc/Authentication.md` | Article DocC | 16 |

---

### Task 1: Harnais Synapse et exploration de la reconnexion

Tâche d'exploration (§5.5, §11). Elle livre un harnais réutilisable et **répond à deux questions**
avant tout code de production :

- **Q1.** Quelle configuration Synapse provoque un soft logout (`M_UNKNOWN_TOKEN`,
  `soft_logout: true`) sur une session ouverte par le SDK Rust ?
- **Q2.** Un second `Client` construit sur le **même** store SQLite, connecté avec le même
  `deviceId`, fonctionne-t-il pendant que le premier (sync arrêtée) est encore en mémoire ? « Fonctionne »
  = la connexion réussit, la sync atteint `running`, un message chiffré envoyé avant le soft logout
  reste déchiffrable dans le second client.

**Files:**
- Create: `Tests/IntegrationHarness/docker-compose.yml`
- Create: `Tests/IntegrationHarness/synapse-password/homeserver.yaml`
- Create: `Tests/IntegrationHarness/synapse-expiring/homeserver.yaml`
- Create: `Tests/IntegrationHarness/README.md`
- Create: `Scripts/integration-harness.sh`
- Create (jetable, supprimé à l'étape 7): `Tests/MatrixClientKitIntegrationTests/ReauthenticationSpikeTests.swift`
- Modify: `docs/superpowers/specs/2026-10-03-matrixclientkit-v0.4-design.md` (§2, nouveau constat 9 ; §5.5 si Q2 échoue)

**Interfaces:**
- Produces: variables d'environnement `MCK_HARNESS_PASSWORD_HOMESERVER` (`http://localhost:8008`),
  `MCK_HARNESS_EXPIRING_HOMESERVER` (`http://localhost:8009`), `MCK_HARNESS_USER`,
  `MCK_HARNESS_PASSWORD`, `MCK_HARNESS_EMAIL`, `MCK_HARNESS_ADMIN_TOKEN_PASSWORD`,
  `MCK_HARNESS_ADMIN_TOKEN_EXPIRING`, émises par `Scripts/integration-harness.sh env`.

- [ ] **Step 1: Choisir et épingler l'image Synapse**

Run: `docker pull ghcr.io/element-hq/synapse:latest && docker image inspect ghcr.io/element-hq/synapse:latest --format '{{index .Config.Labels "org.opencontainers.image.version"}}'`
Noter la version obtenue (`vX.Y.Z`) et l'utiliser **telle quelle** dans le compose (jamais `latest`).

- [ ] **Step 2: Écrire le compose et les configs**

`Tests/IntegrationHarness/docker-compose.yml` :

```yaml
# Harnais d'intégration de MatrixClientKit — lancé à la main, jamais en CI.
# Toutes les clés et tous les secrets de ce répertoire sont des valeurs de TEST, sans valeur hors
# de ce harnais local.
name: mck-harness

services:
  synapse-password:
    image: ghcr.io/element-hq/synapse:vX.Y.Z   # version notée à l'étape 1
    ports: ["8008:8008"]
    volumes:
      - ./synapse-password:/config:ro
      - synapse-password-data:/data
    environment:
      SYNAPSE_CONFIG_PATH: /config/homeserver.yaml
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:8008/health"]
      interval: 2s
      retries: 60

  # Même image, jeton d'accès à durée de vie courte : provoque le soft logout (Q1).
  synapse-expiring:
    image: ghcr.io/element-hq/synapse:vX.Y.Z
    ports: ["8009:8008"]
    volumes:
      - ./synapse-expiring:/config:ro
      - synapse-expiring-data:/data
    environment:
      SYNAPSE_CONFIG_PATH: /config/homeserver.yaml
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:8008/health"]
      interval: 2s
      retries: 60

volumes:
  synapse-password-data:
  synapse-expiring-data:
```

`Tests/IntegrationHarness/synapse-password/homeserver.yaml` :

```yaml
server_name: "localhost"
public_baseurl: "http://localhost:8008/"
pid_file: /data/homeserver.pid
listeners:
  - port: 8008
    type: http
    tls: false
    x_forwarded: false
    resources:
      - names: [client]
        compress: false
database:
  name: sqlite3
  args:
    database: /data/homeserver.db
media_store_path: /data/media_store
signing_key_path: /data/signing.key
report_stats: false
trusted_key_servers: []
suppress_key_server_warning: true
enable_registration: false
# Secret de TEST : sert à créer les comptes par `register_new_matrix_user`.
registration_shared_secret: "mck-harness-registration-secret"
macaroon_secret_key: "mck-harness-macaroon-secret"
form_secret: "mck-harness-form-secret"
# Le harnais enchaîne connexions et déconnexions : sans relâchement, Synapse renvoie
# M_LIMIT_EXCEEDED au milieu de la suite.
rc_login:
  address: { per_second: 1000, burst_count: 1000 }
  account: { per_second: 1000, burst_count: 1000 }
  failed_attempts: { per_second: 1000, burst_count: 1000 }
rc_message: { per_second: 1000, burst_count: 1000 }
log_config: null
```

`Tests/IntegrationHarness/synapse-expiring/homeserver.yaml` : copie exacte du précédent, avec
`public_baseurl: "http://localhost:8009/"` et, à la fin :

```yaml
# Q1 : un jeton d'accès sans refresh token expire au bout de 20 s ; Synapse répond alors
# M_UNKNOWN_TOKEN avec soft_logout: true.
nonrefreshable_access_token_lifetime: 20s
```

`synapse` génère `signing.key` au premier démarrage s'il manque : ajouter au service la commande
`["sh", "-c", "test -f /data/signing.key || python -m synapse.app.homeserver -c /config/homeserver.yaml --generate-keys; exec python -m synapse.app.homeserver -c /config/homeserver.yaml"]`
(`entrypoint: []` pour court-circuiter l'entrypoint de l'image).

- [ ] **Step 3: Écrire le script**

`Scripts/integration-harness.sh` (exécutable, `chmod +x`) :

```bash
#!/usr/bin/env bash
# Démarre, arrête et décrit le harnais d'intégration Docker de MatrixClientKit.
#   up    démarre les conteneurs, attend leur santé, crée les comptes de test
#   down  arrête et efface tout (volumes compris)
#   env   affiche les variables d'environnement à exporter pour `swift test`
set -euo pipefail

cd "$(dirname "$0")/../Tests/IntegrationHarness"
COMPOSE=(docker compose -p mck-harness)

USER_NAME="mck-user"
USER_PASSWORD="mck-user-password"
USER_EMAIL="mck-user@example.test"
ADMIN_NAME="mck-admin"
ADMIN_PASSWORD="mck-admin-password"

register() { # $1 service, $2 user, $3 password, $4 --admin|--no-admin
  "${COMPOSE[@]}" exec -T "$1" register_new_matrix_user \
    -u "$2" -p "$3" "$4" -k "mck-harness-registration-secret" http://localhost:8008 >/dev/null 2>&1 || true
}

login_token() { # $1 port, $2 user, $3 password
  curl -fsS -X POST "http://localhost:$1/_matrix/client/v3/login" \
    -H 'Content-Type: application/json' \
    -d "{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"$2\"},\"password\":\"$3\"}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])'
}

bind_email() { # $1 port, $2 admin token
  curl -fsS -X PUT "http://localhost:$1/_synapse/admin/v2/users/@$USER_NAME:localhost" \
    -H "Authorization: Bearer $2" -H 'Content-Type: application/json' \
    -d "{\"threepids\":[{\"medium\":\"email\",\"address\":\"$USER_EMAIL\"}]}" >/dev/null
}

case "${1:-}" in
  up)
    "${COMPOSE[@]}" up -d --wait
    for service in synapse-password synapse-expiring; do
      register "$service" "$ADMIN_NAME" "$ADMIN_PASSWORD" --admin
      register "$service" "$USER_NAME" "$USER_PASSWORD" --no-admin
    done
    bind_email 8008 "$(login_token 8008 "$ADMIN_NAME" "$ADMIN_PASSWORD")"
    echo "Harness up. Run: eval \"\$(Scripts/integration-harness.sh env)\""
    ;;
  down)
    "${COMPOSE[@]}" down -v
    ;;
  env)
    echo "export MCK_HARNESS_PASSWORD_HOMESERVER=http://localhost:8008"
    echo "export MCK_HARNESS_EXPIRING_HOMESERVER=http://localhost:8009"
    echo "export MCK_HARNESS_USER=$USER_NAME"
    echo "export MCK_HARNESS_PASSWORD=$USER_PASSWORD"
    echo "export MCK_HARNESS_EMAIL=$USER_EMAIL"
    echo "export MCK_HARNESS_ADMIN_TOKEN_PASSWORD=$(login_token 8008 "$ADMIN_NAME" "$ADMIN_PASSWORD")"
    echo "export MCK_HARNESS_ADMIN_TOKEN_EXPIRING=$(login_token 8009 "$ADMIN_NAME" "$ADMIN_PASSWORD")"
    ;;
  *)
    echo "usage: $0 up|down|env" >&2
    exit 64
    ;;
esac
```

- [ ] **Step 4: Démarrer et vérifier le harnais**

Run: `Scripts/integration-harness.sh up && eval "$(Scripts/integration-harness.sh env)" && curl -s $MCK_HARNESS_PASSWORD_HOMESERVER/_matrix/client/v3/login`
Expected: `{"flows":[...{"type":"m.login.password"}...]}`

- [ ] **Step 5: Écrire le test d'exploration**

`Tests/MatrixClientKitIntegrationTests/ReauthenticationSpikeTests.swift` — utilise directement le
SDK (la cible voit `MatrixRustSDK` transitivement) pour ne dépendre d'aucun code 0.4 :

```swift
import Testing
import Foundation
import MatrixRustSDK

// EXPLORATION JETABLE (Task 1 du plan 0.4) — supprimé une fois Q1 et Q2 tranchées.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MCK_HARNESS_EXPIRING_HOMESERVER"] != nil), .serialized)
struct ReauthenticationSpikeTests {
    let homeserver = ProcessInfo.processInfo.environment["MCK_HARNESS_EXPIRING_HOMESERVER"] ?? ""
    let user = ProcessInfo.processInfo.environment["MCK_HARNESS_USER"] ?? ""
    let password = ProcessInfo.processInfo.environment["MCK_HARNESS_PASSWORD"] ?? ""

    final class Delegate: ClientDelegate, @unchecked Sendable {
        let softLogout: AsyncStream<Bool>.Continuation
        init(_ continuation: AsyncStream<Bool>.Continuation) { softLogout = continuation }
        func didReceiveAuthError(isSoftLogout: Bool) { softLogout.yield(isSoftLogout) }
        func onBackgroundTaskErrorReport(taskName: String, error: BackgroundTaskFailureReason) {}
    }

    func makeClient(_ directory: URL, key: Data) async throws -> Client {
        try await ClientBuilder()
            .homeserverUrl(url: homeserver)
            .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
            .autoEnableCrossSigning(autoEnableCrossSigning: true)
            .sqliteStore(config: SqliteStoreBuilder(dataPath: directory.appending(path: "data").path,
                                                    cachePath: directory.appending(path: "cache").path).key(key: key))
            .build()
    }

    @Test(.timeLimit(.minutes(3)))
    func secondClientOnTheSameStoreAfterSoftLogout() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "mck-spike-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        // Premier client : connexion, sync, puis attente du soft logout (Q1).
        let first = try await makeClient(directory, key: key)
        try await first.login(username: user, password: password, initialDeviceName: "spike", deviceId: nil)
        let deviceID = try first.deviceId()
        let (events, continuation) = AsyncStream<Bool>.makeStream()
        let delegate = Delegate(continuation)
        let handle = try first.setDelegate(delegate: delegate)
        let sync = try await first.syncService().finish()
        await sync.start()
        print("SPIKE refresh token present:", (try first.session()).refreshToken != nil)

        var isSoft: Bool?
        for await value in events { isSoft = value; break }
        print("SPIKE Q1 didReceiveAuthError isSoftLogout =", isSoft as Any)
        #expect(isSoft == true)
        await sync.stop()

        // Second client, même store, même appareil, pendant que `first` est encore en mémoire (Q2).
        let second = try await makeClient(directory, key: key)
        try await second.login(username: user, password: password, initialDeviceName: nil, deviceId: deviceID)
        #expect(try second.deviceId() == deviceID)
        let secondSync = try await second.syncService().finish()
        await secondSync.start()
        try await Task.sleep(for: .seconds(5))
        print("SPIKE Q2 second client sync state:", secondSync.state())
        _ = handle
        withExtendedLifetime(first) {}
        await secondSync.stop()
        try? await second.logout()
    }
}
```

Si `Client.deviceId()` ou `SyncService.state()` n'ont pas cette forme exacte dans
`matrix_sdk_ffi.swift`, adapter l'appel (grep `func deviceId` / `func state` dans le fichier
généré) sans changer l'intention du test.

- [ ] **Step 6: Lancer et consigner**

Run: `swift test --filter ReauthenticationSpikeTests 2>&1 | grep -E "SPIKE|passed|failed"`

Consigner le résultat dans la spec, §2, comme **constat 9** : configuration retenue pour Q1
(ou alternative trouvée, par exemple `refreshable_access_token_lifetime` si le SDK demande un
refresh token), réponse à Q2.

**Si Q2 échoue** (panique, erreur de store, verrou, sync qui n'atteint jamais `running`) :
s'arrêter, mettre à jour §5.5 de la spec avec le repli (« `reauthenticate` exige que l'ancienne
session soit libérée »), et **demander validation à l'utilisateur** avant de poursuivre : la Task 11
change alors de forme.

**Si Q1 n'aboutit à aucune configuration** : consigner, et marquer dans §8.2 que la reconnexion
n'est vérifiée qu'en tests unitaires ; prévenir l'utilisateur.

- [ ] **Step 7: Supprimer le test jetable et commiter**

```bash
git rm -q --cached Tests/MatrixClientKitIntegrationTests/ReauthenticationSpikeTests.swift 2>/dev/null; rm -f Tests/MatrixClientKitIntegrationTests/ReauthenticationSpikeTests.swift
git add Tests/IntegrationHarness Scripts/integration-harness.sh docs/superpowers/specs/2026-10-03-matrixclientkit-v0.4-design.md
git commit -m "test: harnais Synapse local et constats sur la reconnexion après soft logout

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

`Tests/IntegrationHarness/README.md` (à inclure dans ce commit) : trois paragraphes —
quoi (serveurs et ports), comment (`up`, `eval "$(… env)"`, `swift test --filter …`, `down`),
et l'avertissement que tous les secrets du répertoire sont des valeurs de test.

Le dossier `Tests/IntegrationHarness` n'est pas une cible SwiftPM : rien à changer dans
`Package.swift`.

---

### Task 2: Modèles d'authentification et connexion par e-mail

**Files:**
- Create: `Sources/MatrixClientKitCore/Models/Authentication.swift`
- Modify: `Sources/MatrixClientKitCore/Services/MatrixClient.swift` (enum `Credentials`)
- Modify: `Sources/MatrixClientKitRust/RustMatrixClient.swift` (`switch credentials`)
- Create: `Tests/MatrixClientKitCoreTests/AuthenticationModelTests.swift`

**Interfaces:**
- Produces:
  - `public enum OAuthPrompt: Sendable, Hashable { case login, create, consent }`
  - `public struct LoginDetails: Sendable, Hashable` — `homeserver: URL`, `supportsPassword: Bool`,
    `supportsOAuth: Bool`, `supportsSSO: Bool`, `oauthPrompts: Set<OAuthPrompt>`, init public
    memberwise.
  - `public struct OAuthConfiguration: Sendable, Hashable` — `clientName: String?`,
    `redirectURI: URL`, `clientURI: URL`, `logoURI: URL?`, `termsOfServiceURI: URL?`,
    `policyURI: URL?`, `staticRegistrations: [URL: String]`.
  - `Credentials.email(address: String, password: String, deviceName: String?)`

- [ ] **Step 1: Écrire les tests**

`Tests/MatrixClientKitCoreTests/AuthenticationModelTests.swift` :

```swift
import Testing
import Foundation
import MatrixClientKitCore

@Test func emailCredentialsNeverDescribeThePassword() {
    let credentials = Credentials.email(address: "alice@example.org", password: "hunter2", deviceName: "iPhone")
    #expect(!credentials.description.contains("hunter2"))
    #expect(!credentials.debugDescription.contains("hunter2"))
    #expect(credentials.description.contains("alice@example.org"))
    #expect(credentials.description.contains("<redacted>"))
}

@Test func emailCredentialsWithoutDeviceNameSayNil() {
    let credentials = Credentials.email(address: "alice@example.org", password: "x", deviceName: nil)
    #expect(credentials.description.contains("deviceName: nil"))
}

@Test func oauthConfigurationDefaultsOptionalFields() {
    let configuration = OAuthConfiguration(
        redirectURI: URL(string: "com.example.app:/callback")!,
        clientURI: URL(string: "https://example.com")!
    )
    #expect(configuration.clientName == nil)
    #expect(configuration.logoURI == nil)
    #expect(configuration.termsOfServiceURI == nil)
    #expect(configuration.policyURI == nil)
    #expect(configuration.staticRegistrations.isEmpty)
}

@Test func loginDetailsCompareByValue() {
    let homeserver = URL(string: "https://matrix.example.com")!
    let a = LoginDetails(homeserver: homeserver, supportsPassword: true, supportsOAuth: false,
                         supportsSSO: false, oauthPrompts: [])
    let b = LoginDetails(homeserver: homeserver, supportsPassword: true, supportsOAuth: false,
                         supportsSSO: false, oauthPrompts: [])
    #expect(a == b)
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `swift test --filter AuthenticationModelTests`
Expected: échec de compilation (`OAuthConfiguration`, `LoginDetails`, `.email` introuvables).

- [ ] **Step 3: Implémenter les modèles**

`Sources/MatrixClientKitCore/Models/Authentication.swift` :

```swift
import Foundation

/// What a homeserver accepts for signing in. See ``MatrixClient/loginDetails()``.
public struct LoginDetails: Sendable, Hashable {
    /// The homeserver these details describe.
    public let homeserver: URL
    /// Whether ``Credentials/password(username:password:deviceName:)`` and
    /// ``Credentials/email(address:password:deviceName:)`` can succeed.
    public let supportsPassword: Bool
    /// Whether ``MatrixClient/beginOAuthLogin(_:prompt:loginHint:)`` and QR-code login can succeed.
    public let supportsOAuth: Bool
    /// Whether the homeserver offers legacy single sign-on. Reported for information only:
    /// MatrixClientKit does not support it.
    public let supportsSSO: Bool
    /// The prompts the authorization server advertises. Offer account creation only when this
    /// contains ``OAuthPrompt/create``.
    public let oauthPrompts: Set<OAuthPrompt>

    public init(
        homeserver: URL,
        supportsPassword: Bool,
        supportsOAuth: Bool,
        supportsSSO: Bool,
        oauthPrompts: Set<OAuthPrompt>
    ) {
        self.homeserver = homeserver
        self.supportsPassword = supportsPassword
        self.supportsOAuth = supportsOAuth
        self.supportsSSO = supportsSSO
        self.oauthPrompts = oauthPrompts
    }
}

/// What the authorization server should show the user.
///
/// - Important: frozen for the lifetime of a major version, like ``MatrixError``. A prompt
///   standardised later is ignored until the next major.
public enum OAuthPrompt: Sendable, Hashable {
    /// Ask the user to sign in again, even with a live browser session.
    case login
    /// Offer to create an account.
    case create
    /// Ask the user to consent again.
    case consent
}

/// How this application presents itself to an OAuth authorization server.
///
/// The authorization server shows these details on its consent screen, and registers the
/// application under them the first time it sees it.
public struct OAuthConfiguration: Sendable, Hashable {
    /// The application's name, shown to the user.
    public var clientName: String?
    /// Where the authorization server sends the user back, for instance
    /// `com.example.app:/callback`. Must match the callback scheme given to
    /// `ASWebAuthenticationSession`.
    public var redirectURI: URL
    /// A page about the application.
    public var clientURI: URL
    public var logoURI: URL?
    public var termsOfServiceURI: URL?
    public var policyURI: URL?
    /// Client IDs registered ahead of time, for authorization servers without dynamic
    /// registration: the homeserver's (or the issuer's) URL → client ID.
    public var staticRegistrations: [URL: String]

    public init(
        clientName: String? = nil,
        redirectURI: URL,
        clientURI: URL,
        logoURI: URL? = nil,
        termsOfServiceURI: URL? = nil,
        policyURI: URL? = nil,
        staticRegistrations: [URL: String] = [:]
    ) {
        self.clientName = clientName
        self.redirectURI = redirectURI
        self.clientURI = clientURI
        self.logoURI = logoURI
        self.termsOfServiceURI = termsOfServiceURI
        self.policyURI = policyURI
        self.staticRegistrations = staticRegistrations
    }
}
```

Dans `Sources/MatrixClientKitCore/Services/MatrixClient.swift`, remplacer l'enum et son extension :

```swift
/// Sign-in credentials.
public enum Credentials: Sendable, Hashable {
    /// Username-and-password sign-in, with an optional device name.
    case password(username: String, password: String, deviceName: String?)
    /// Sign-in with an email address bound to the account, and its password.
    case email(address: String, password: String, deviceName: String?)
}

extension Credentials: CustomStringConvertible, CustomDebugStringConvertible {
    /// Redacted description: never exposes the password.
    public var description: String {
        switch self {
        case let .password(username, _, deviceName):
            return "Credentials.password(username: \(username), password: <redacted>, deviceName: \(deviceName ?? "nil"))"
        case let .email(address, _, deviceName):
            return "Credentials.email(address: \(address), password: <redacted>, deviceName: \(deviceName ?? "nil"))"
        }
    }

    public var debugDescription: String { description }
}
```

Dans `RustMatrixClient.login`, compléter le `switch` (remplacé en Task 7, mais il doit compiler
dès maintenant) :

```swift
            case let .email(address, password, deviceName):
                try await handshake.loginWithEmail(
                    email: address,
                    password: password,
                    initialDeviceName: deviceName,
                    deviceId: nil
                )
```

- [ ] **Step 4: Vérifier**

Run: `swift test --skip MatrixClientKitIntegrationTests`
Expected: PASS (tous les tests, dont les 4 nouveaux).

- [ ] **Step 5: Commit**

```bash
git add Sources/MatrixClientKitCore Sources/MatrixClientKitRust/RustMatrixClient.swift Tests/MatrixClientKitCoreTests/AuthenticationModelTests.swift
git commit -m "feat: modèles d'authentification et connexion par e-mail

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: États de la connexion par QR et leur réducteur

**Files:**
- Create: `Sources/MatrixClientKitCore/Models/QRCodeLogin.swift`
- Create: `Sources/MatrixClientKitCore/Models/QRCodeLoginReducer.swift`
- Create: `Tests/MatrixClientKitCoreTests/QRCodeLoginReducerTests.swift`

**Interfaces:**
- Produces:
  - `public enum QRCodeLoginFailure: Sendable, Hashable { case declined, expired, insecureChannel, notSupported, otherDeviceNotSignedIn, cancelled, unknown }`
  - `public enum QRCodeLoginState: Sendable, Hashable { case starting, displayQRCode(Data), enterCheckCode, displayCheckCode(String), waitingForApproval(userCode: String), syncingSecrets, done, failed(QRCodeLoginFailure) }` + `public var isFinished: Bool`
  - `package enum QRCodeLoginEvent: Sendable, Hashable { case qrReady(Data), qrScanned, secureChannelEstablished(checkCode: String), waitingForToken(userCode: String), syncingSecrets, done, failed(QRCodeLoginFailure) }`
  - `package enum QRCodeLoginReducer { static func reduce(_ state: QRCodeLoginState, _ event: QRCodeLoginEvent) -> QRCodeLoginState; static func canSubmitCheckCode(in state: QRCodeLoginState) -> Bool }`

- [ ] **Step 1: Écrire les tests**

`Tests/MatrixClientKitCoreTests/QRCodeLoginReducerTests.swift` :

```swift
import Testing
import Foundation
@testable import MatrixClientKitCore

private func run(_ events: [QRCodeLoginEvent], from state: QRCodeLoginState = .starting) -> QRCodeLoginState {
    events.reduce(state, QRCodeLoginReducer.reduce)
}

private let qr = Data([1, 2, 3])

@Test func displayedModeHappyPath() {
    #expect(run([.qrReady(qr)]) == .displayQRCode(qr))
    #expect(run([.qrReady(qr), .qrScanned]) == .enterCheckCode)
    #expect(run([.qrReady(qr), .qrScanned, .waitingForToken(userCode: "ABCD")]) == .waitingForApproval(userCode: "ABCD"))
    #expect(run([.qrReady(qr), .qrScanned, .waitingForToken(userCode: "ABCD"), .syncingSecrets]) == .syncingSecrets)
    #expect(run([.qrReady(qr), .qrScanned, .waitingForToken(userCode: "ABCD"), .syncingSecrets, .done]) == .done)
}

@Test func scannedModeHappyPath() {
    #expect(run([.secureChannelEstablished(checkCode: "07")]) == .displayCheckCode("07"))
    #expect(run([.secureChannelEstablished(checkCode: "07"), .waitingForToken(userCode: "U"), .done]) == .done)
}

@Test func doneWithoutSecretSyncIsAccepted() {
    // L'amont peut sauter `.syncingSecrets` (aucun secret à transférer).
    #expect(run([.secureChannelEstablished(checkCode: "07"), .waitingForToken(userCode: "U"), .done]) == .done)
}

@Test(arguments: [
    QRCodeLoginFailure.declined, .expired, .insecureChannel, .notSupported, .otherDeviceNotSignedIn, .cancelled, .unknown,
])
func everyFailureEndsTheFlowFromAnyLiveState(_ failure: QRCodeLoginFailure) {
    let liveStates: [QRCodeLoginState] = [
        .starting, .displayQRCode(qr), .enterCheckCode, .displayCheckCode("07"),
        .waitingForApproval(userCode: "U"), .syncingSecrets,
    ]
    for state in liveStates {
        #expect(QRCodeLoginReducer.reduce(state, .failed(failure)) == .failed(failure))
    }
}

@Test func finishedStatesAbsorbLateCallbacks() {
    let late: [QRCodeLoginEvent] = [
        .qrReady(qr), .qrScanned, .secureChannelEstablished(checkCode: "07"),
        .waitingForToken(userCode: "U"), .syncingSecrets, .done, .failed(.unknown),
    ]
    for event in late {
        #expect(QRCodeLoginReducer.reduce(.done, event) == .done)
        #expect(QRCodeLoginReducer.reduce(.failed(.cancelled), event) == .failed(.cancelled))
    }
}

@Test func outOfOrderEventsAreIgnored() {
    #expect(QRCodeLoginReducer.reduce(.starting, .qrScanned) == .starting)
    #expect(QRCodeLoginReducer.reduce(.starting, .syncingSecrets) == .starting)
    #expect(QRCodeLoginReducer.reduce(.starting, .done) == .starting)
    #expect(QRCodeLoginReducer.reduce(.displayQRCode(qr), .secureChannelEstablished(checkCode: "07")) == .displayQRCode(qr))
}

@Test func checkCodeCanOnlyBeSubmittedWhenAsked() {
    #expect(QRCodeLoginReducer.canSubmitCheckCode(in: .enterCheckCode))
    #expect(!QRCodeLoginReducer.canSubmitCheckCode(in: .starting))
    #expect(!QRCodeLoginReducer.canSubmitCheckCode(in: .displayCheckCode("07")))
    #expect(!QRCodeLoginReducer.canSubmitCheckCode(in: .waitingForApproval(userCode: "U")))
}

@Test func finishedStatesAreFlagged() {
    #expect(QRCodeLoginState.done.isFinished)
    #expect(QRCodeLoginState.failed(.declined).isFinished)
    #expect(!QRCodeLoginState.syncingSecrets.isFinished)
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `swift test --filter QRCodeLoginReducerTests`
Expected: échec de compilation (types introuvables).

- [ ] **Step 3: Implémenter**

`Sources/MatrixClientKitCore/Models/QRCodeLogin.swift` :

```swift
import Foundation

/// Why a QR-code login ended without a session.
///
/// - Important: frozen for the lifetime of a major version, like ``MatrixError``. A failure the
///   underlying SDK newly distinguishes is reported as ``unknown``.
public enum QRCodeLoginFailure: Sendable, Hashable {
    /// The signed-in device refused the request.
    case declined
    /// The code or the request expired before the other device acted on it.
    case expired
    /// The check codes did not match: the channel between the devices may be intercepted.
    case insecureChannel
    /// The homeserver does not support QR-code login (it needs OAuth and MSC4108), or the code
    /// is not a Matrix login code.
    case notSupported
    /// The device that showed the code is not signed in.
    case otherDeviceNotSignedIn
    /// ``QRCodeLogin/cancel()`` was called.
    case cancelled
    case unknown
}

/// Where a QR-code login stands. See ``QRCodeLogin/state``.
public enum QRCodeLoginState: Sendable, Hashable {
    case starting
    /// Show these bytes as a QR code for the signed-in device to scan.
    case displayQRCode(Data)
    /// The signed-in device scanned the code and shows two digits: ask the user to type them,
    /// then call ``QRCodeLogin/submitCheckCode(_:)``.
    case enterCheckCode
    /// Show these two digits: the user confirms them on the signed-in device.
    case displayCheckCode(String)
    /// Waiting for the user to approve the sign-in on the signed-in device. Some servers ask the
    /// user to check `userCode` there.
    case waitingForApproval(userCode: String)
    /// Signed in; receiving this account's encryption secrets from the other device.
    case syncingSecrets
    case done
    case failed(QRCodeLoginFailure)

    /// Whether the flow is over, successfully or not.
    public var isFinished: Bool {
        switch self {
        case .done, .failed: true
        default: false
        }
    }
}

/// Ce qui fait avancer une connexion par QR : un progrès amont, ou un échec.
package enum QRCodeLoginEvent: Sendable, Hashable {
    case qrReady(Data)
    case qrScanned
    case secureChannelEstablished(checkCode: String)
    case waitingForToken(userCode: String)
    case syncingSecrets
    case done
    case failed(QRCodeLoginFailure)
}
```

`Sources/MatrixClientKitCore/Models/QRCodeLoginReducer.swift` :

```swift
/// Machine à états de la connexion par QR (spec 0.4, §4.4).
///
/// Fonction pure, sur le modèle de ``SessionVerificationReducer`` : un événement incohérent avec
/// l'état courant le laisse inchangé, et un état terminal absorbe tout — l'amont peut livrer un
/// progrès tardif après une annulation, qui ne doit jamais ranimer le flux.
package enum QRCodeLoginReducer {

    package static func reduce(_ state: QRCodeLoginState, _ event: QRCodeLoginEvent) -> QRCodeLoginState {
        guard !state.isFinished else { return state }

        switch event {
        case let .failed(failure):
            return .failed(failure)
        case let .qrReady(data):
            return state == .starting ? .displayQRCode(data) : state
        case .qrScanned:
            if case .displayQRCode = state { return .enterCheckCode }
            return state
        case let .secureChannelEstablished(code):
            return state == .starting ? .displayCheckCode(code) : state
        case let .waitingForToken(userCode):
            switch state {
            case .enterCheckCode, .displayCheckCode, .waitingForApproval: return .waitingForApproval(userCode: userCode)
            default: return state
            }
        case .syncingSecrets:
            if case .waitingForApproval = state { return .syncingSecrets }
            return state
        case .done:
            switch state {
            case .waitingForApproval, .syncingSecrets: return .done
            default: return state
            }
        }
    }

    package static func canSubmitCheckCode(in state: QRCodeLoginState) -> Bool {
        state == .enterCheckCode
    }
}
```

- [ ] **Step 4: Vérifier**

Run: `swift test --filter QRCodeLoginReducerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/MatrixClientKitCore/Models/QRCodeLogin.swift Sources/MatrixClientKitCore/Models/QRCodeLoginReducer.swift Tests/MatrixClientKitCoreTests/QRCodeLoginReducerTests.swift
git commit -m "feat: états de la connexion par QR et leur machine à états

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Protocoles `OAuthLoginFlow` et `QRCodeLogin`, et leurs doubles

Les protocoles sont ajoutés à `Core` **sans** encore être exigés par `MatrixClient` : les
implémentations Rust les adoptent en Tasks 9 et 10, et `MatrixClient`/`MatrixSession` ne les
exigent qu'en Task 12. Aucune implémentation provisoire n'est donc nécessaire.

**Files:**
- Create: `Sources/MatrixClientKitCore/Services/OAuthLoginFlow.swift`
- Create: `Sources/MatrixClientKitCore/Services/QRCodeLogin.swift`
- Create: `Sources/MatrixClientKitMocks/MockOAuthLoginFlow.swift`
- Create: `Sources/MatrixClientKitMocks/MockQRCodeLogin.swift`
- Modify: `Sources/MatrixClientKitMocks/SampleData.swift`
- Create: `Tests/MatrixClientKitCoreTests/AuthenticationMockTests.swift`

**Interfaces:**
- Consumes: `QRCodeLoginState`, `OAuthConfiguration`, `LoginDetails`, `OAuthPrompt` (Tasks 2–3).
- Produces:
  - `public protocol OAuthLoginFlow: Sendable { var authorizationURL: URL { get }; func complete(callbackURL: URL) async throws -> any MatrixSession; func cancel() async }`
  - `public protocol QRCodeLogin: Sendable { var state: AsyncStream<QRCodeLoginState> { get }; func start() async throws -> any MatrixSession; func submitCheckCode(_ code: UInt8) async throws; func cancel() }`
  - `MockOAuthLoginFlow(authorizationURL:completeResult:)` — `completeResult: Result<MockMatrixSession, MatrixError>`, `completedCallbackURLs: [URL]`, `cancelCount: Int`.
  - `MockQRCodeLogin(startResult:)` — `emit(_:)`, `submittedCheckCodes: [UInt8]`, `submitError: MatrixError?`, `didCancel: Bool`.
  - `SampleData.loginDetails(homeserver:supportsPassword:supportsOAuth:oauthPrompts:)`, `SampleData.oauthConfiguration()`.

- [ ] **Step 1: Écrire les tests**

`Tests/MatrixClientKitCoreTests/AuthenticationMockTests.swift` :

```swift
import Testing
import Foundation
import MatrixClientKitCore
import MatrixClientKitMocks

@Test func mockOAuthFlowRecordsCompletionAndReturnsTheSession() async throws {
    let session = MockMatrixSession(userID: "@bob:example.org")
    let flow = MockOAuthLoginFlow(completeResult: .success(session))
    let callback = URL(string: "com.example.app:/callback?code=abc")!

    let opened = try await flow.complete(callbackURL: callback)

    #expect(opened.userID.rawValue == "@bob:example.org")
    #expect(flow.completedCallbackURLs == [callback])
}

@Test func mockOAuthFlowThrowsTheConfiguredError() async {
    let flow = MockOAuthLoginFlow(completeResult: .failure(.authentication(.invalidCredentials)))
    await #expect(throws: MatrixError.authentication(.invalidCredentials)) {
        _ = try await flow.complete(callbackURL: URL(string: "x:/y")!)
    }
}

@Test func mockOAuthFlowCountsCancellations() async {
    let flow = MockOAuthLoginFlow()
    await flow.cancel()
    await flow.cancel()
    #expect(flow.cancelCount == 2)
}

@Test func mockQRCodeLoginReplaysTheCurrentStateThenEmissions() async {
    let login = MockQRCodeLogin()
    login.emit(.displayQRCode(Data([9])))
    var iterator = login.state.makeAsyncIterator()
    #expect(await iterator.next() == .displayQRCode(Data([9])))
    login.emit(.enterCheckCode)
    #expect(await iterator.next() == .enterCheckCode)
}

@Test func mockQRCodeLoginRecordsCheckCodesAndCancellation() async throws {
    let login = MockQRCodeLogin()
    try await login.submitCheckCode(42)
    login.cancel()
    #expect(login.submittedCheckCodes == [42])
    #expect(login.didCancel)
}

@Test func sampleLoginDetailsDefaultToPasswordOnly() {
    let details = SampleData.loginDetails()
    #expect(details.supportsPassword)
    #expect(!details.supportsOAuth)
    #expect(details.oauthPrompts.isEmpty)
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `swift test --filter AuthenticationMockTests`
Expected: échec de compilation.

- [ ] **Step 3: Implémenter les protocoles**

`Sources/MatrixClientKitCore/Services/OAuthLoginFlow.swift` :

```swift
import Foundation

/// A sign-in through the homeserver's OAuth authorization server, waiting for the user.
///
/// Open ``authorizationURL`` in an `ASWebAuthenticationSession` whose callback scheme is the one
/// of ``OAuthConfiguration/redirectURI``, then pass the URL it calls back with to
/// ``complete(callbackURL:)``. If the user closes the web view, call ``cancel()``.
///
/// A flow is single-use: once ``complete(callbackURL:)`` has failed or ``cancel()`` has been
/// called, start a new one.
public protocol OAuthLoginFlow: Sendable {
    /// The page to open for the user to sign in.
    var authorizationURL: URL { get }

    /// Finishes signing in with the URL the authorization server redirected to.
    ///
    /// - Throws: `CancellationError` when the user refused or the authorization server cancelled;
    ///   ``MatrixError`` otherwise. A second call throws ``MatrixError/unexpected(message:details:)``.
    func complete(callbackURL: URL) async throws -> any MatrixSession

    /// Abandons the flow and erases what it had prepared locally. Does nothing after a successful
    /// ``complete(callbackURL:)``, and nothing when called twice.
    func cancel() async
}
```

`Sources/MatrixClientKitCore/Services/QRCodeLogin.swift` :

```swift
import Foundation

/// A sign-in of this device by another device of the same account, through a QR code.
///
/// Observe ``state`` to drive the screen, then call ``start()``, which returns the session once
/// the other device has approved and handed over this account's encryption secrets: the new
/// session starts out verified.
public protocol QRCodeLogin: Sendable {
    /// The login's state, starting with the current value. Every access opens an independent
    /// subscription.
    var state: AsyncStream<QRCodeLoginState> { get }

    /// Runs the login. Call it once.
    ///
    /// - Throws: `CancellationError` after ``cancel()``; ``MatrixError`` otherwise — ``state``
    ///   then holds the ``QRCodeLoginFailure``.
    func start() async throws -> any MatrixSession

    /// Sends the two digits shown by the signed-in device. Valid only in
    /// ``QRCodeLoginState/enterCheckCode``.
    func submitCheckCode(_ code: UInt8) async throws

    /// Abandons the login. ``state`` ends in ``QRCodeLoginFailure/cancelled``.
    func cancel()
}
```

- [ ] **Step 4: Implémenter les doubles**

`Sources/MatrixClientKitMocks/MockOAuthLoginFlow.swift` :

```swift
import Foundation
import MatrixClientKitCore

/// A drivable ``OAuthLoginFlow``: ``complete(callbackURL:)`` returns or throws ``completeResult``
/// and records the URL; ``cancel()`` is counted.
public final class MockOAuthLoginFlow: OAuthLoginFlow, @unchecked Sendable {
    private let lock = NSLock()

    public let authorizationURL: URL
    private var _completeResult: Result<MockMatrixSession, MatrixError>
    private var _completedCallbackURLs: [URL] = []
    private var _cancelCount = 0

    public init(
        authorizationURL: URL = URL(string: "https://auth.example.org/authorize")!,
        completeResult: Result<MockMatrixSession, MatrixError> = .success(MockMatrixSession())
    ) {
        self.authorizationURL = authorizationURL
        self._completeResult = completeResult
    }

    /// What ``complete(callbackURL:)`` returns or throws.
    public var completeResult: Result<MockMatrixSession, MatrixError> {
        get { lock.withLock { _completeResult } }
        set { lock.withLock { _completeResult = newValue } }
    }

    /// Every URL passed to ``complete(callbackURL:)``, in order.
    public var completedCallbackURLs: [URL] { lock.withLock { _completedCallbackURLs } }

    /// How many times ``cancel()`` was called.
    public var cancelCount: Int { lock.withLock { _cancelCount } }

    public func complete(callbackURL: URL) async throws -> any MatrixSession {
        let result = lock.withLock {
            _completedCallbackURLs.append(callbackURL)
            return _completeResult
        }
        return try result.get()
    }

    public func cancel() async {
        lock.withLock { _cancelCount += 1 }
    }
}
```

`Sources/MatrixClientKitMocks/MockQRCodeLogin.swift` :

```swift
import Foundation
import MatrixClientKitCore

/// A drivable ``QRCodeLogin``. Push states with ``emit(_:)``; ``start()`` returns or throws
/// ``startResult``.
public final class MockQRCodeLogin: QRCodeLogin, @unchecked Sendable {
    private let lock = NSLock()
    private var current: QRCodeLoginState = .starting
    private var continuations: [UUID: AsyncStream<QRCodeLoginState>.Continuation] = [:]
    private var _startResult: Result<MockMatrixSession, MatrixError>
    private var _submittedCheckCodes: [UInt8] = []
    private var _submitError: MatrixError?
    private var _didCancel = false

    public init(startResult: Result<MockMatrixSession, MatrixError> = .success(MockMatrixSession())) {
        self._startResult = startResult
    }

    /// What ``start()`` returns or throws.
    public var startResult: Result<MockMatrixSession, MatrixError> {
        get { lock.withLock { _startResult } }
        set { lock.withLock { _startResult = newValue } }
    }

    /// The error ``submitCheckCode(_:)`` throws. `nil` by default.
    public var submitError: MatrixError? {
        get { lock.withLock { _submitError } }
        set { lock.withLock { _submitError = newValue } }
    }

    /// Every code passed to ``submitCheckCode(_:)``, in order — including rejected ones.
    public var submittedCheckCodes: [UInt8] { lock.withLock { _submittedCheckCodes } }

    /// True once ``cancel()`` has been called.
    public var didCancel: Bool { lock.withLock { _didCancel } }

    /// Like the real login, starts with the current state, then every ``emit(_:)``.
    public var state: AsyncStream<QRCodeLoginState> {
        let (stream, continuation) = AsyncStream<QRCodeLoginState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        lock.withLock {
            continuation.yield(current)
            continuations[id] = continuation
        }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { _ = self.continuations.removeValue(forKey: id) }
        }
        return stream
    }

    /// Pushes a state to every subscriber of ``state``.
    public func emit(_ state: QRCodeLoginState) {
        lock.withLock {
            current = state
            for continuation in continuations.values { continuation.yield(state) }
        }
    }

    public func start() async throws -> any MatrixSession {
        try startResult.get()
    }

    public func submitCheckCode(_ code: UInt8) async throws {
        let error = lock.withLock {
            _submittedCheckCodes.append(code)
            return _submitError
        }
        if let error { throw error }
    }

    public func cancel() {
        lock.withLock { _didCancel = true }
        emit(.failed(.cancelled))
    }
}
```

Dans `Sources/MatrixClientKitMocks/SampleData.swift`, ajouter :

```swift
    /// Builds ``LoginDetails`` for a password-only homeserver by default.
    public static func loginDetails(
        homeserver: URL = URL(string: "https://matrix.example.org")!,
        supportsPassword: Bool = true,
        supportsOAuth: Bool = false,
        oauthPrompts: Set<OAuthPrompt> = []
    ) -> LoginDetails {
        LoginDetails(
            homeserver: homeserver,
            supportsPassword: supportsPassword,
            supportsOAuth: supportsOAuth,
            supportsSSO: false,
            oauthPrompts: oauthPrompts
        )
    }

    /// A ready-made ``OAuthConfiguration`` for `com.example.app`.
    public static func oauthConfiguration() -> OAuthConfiguration {
        OAuthConfiguration(
            clientName: "Example",
            redirectURI: URL(string: "com.example.app:/callback")!,
            clientURI: URL(string: "https://example.com")!
        )
    }
```

- [ ] **Step 5: Vérifier**

Run: `swift test --skip MatrixClientKitIntegrationTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/MatrixClientKitCore/Services Sources/MatrixClientKitMocks Tests/MatrixClientKitCoreTests/AuthenticationMockTests.swift
git commit -m "feat: protocoles de flux OAuth et de connexion par QR, et leurs doubles

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Store par session

**Files:**
- Create: `Sources/MatrixClientKitRust/Storage/StoreSegment.swift`
- Modify: `Sources/MatrixClientKitCore/Models/MatrixSessionData.swift` (champ `storeID`)
- Modify: `Sources/MatrixClientKitRust/Storage/StoragePaths.swift` (segment ; `userDirectory` → `storeDirectory` ; `static func root(for:containerURL:)`)
- Modify: `Sources/MatrixClientKitRust/Storage/LocalStore.swift` (segment)
- Modify: `Sources/MatrixClientKitRust/Storage/SessionDelegate.swift` (fusion du `storeID`)
- Modify: `Sources/MatrixClientKitRust/Bridge/SessionMapper.swift` (`sessionData(from:storeID:)`)
- Modify: `Sources/MatrixClientKitRust/SessionRestorer.swift` (`makeLocalStore(for: StoreSegment)`)
- Modify: `Sources/MatrixClientKitRust/RustMatrixClient.swift` (appel de `makeLocalStore`)
- Modify: `Tests/MatrixClientKitRustTests/StoragePathsTests.swift`, `LocalStoreTests.swift`, `SessionDelegateTests.swift`, `SessionMapperTests.swift`
- Create: `Tests/MatrixClientKitCoreTests/MatrixSessionDataDecodingTests.swift`

**Interfaces:**
- Produces:
  - `enum StoreSegment: Sendable, Hashable { case legacy(UserID); case session(String); static func newSession() -> StoreSegment; init(_ data: MatrixSessionData); var directoryName: String { get }; var storeID: String? { get } }`
  - `MatrixSessionData.storeID: String?` ; init avec `storeID: String? = nil` en dernier paramètre.
  - `StoragePaths(storage:segment:containerURL:)`, `storeDirectory`, `dataDirectory`, `cacheDirectory`, `static func root(for storage: MatrixStorage, containerURL: …) throws -> URL` (= `<racine>/MatrixClientKit`).
  - `LocalStore(storage:segment:secureStore:)`, `let segment: StoreSegment`.
  - `SessionRestorer.makeLocalStore(for segment: StoreSegment) -> LocalStore`.
  - `SessionMapper.sessionData(from session: Session, storeID: String?) throws -> MatrixSessionData`.

- [ ] **Step 1: Écrire les tests**

`Tests/MatrixClientKitCoreTests/MatrixSessionDataDecodingTests.swift` :

```swift
import Testing
import Foundation
@testable import MatrixClientKitCore

@Test func aSessionPersistedBy03DecodesWithoutStoreID() throws {
    // Forme exacte écrite par la 0.3 : aucun champ storeID.
    let json = """
    {"userID":"@alice:matrix.org","deviceID":"DEV1","homeserverURL":"https://matrix.org",
     "accessToken":"t","slidingSyncVersion":"native"}
    """
    let data = try JSONDecoder().decode(MatrixSessionData.self, from: Data(json.utf8))
    #expect(data.storeID == nil)
    #expect(data.userID.rawValue == "@alice:matrix.org")
}

@Test func theStoreIDSurvivesARoundTrip() throws {
    let original = MatrixSessionData(
        userID: UserID(rawValue: "@alice:matrix.org")!, deviceID: DeviceID(rawValue: "DEV1")!,
        homeserverURL: URL(string: "https://matrix.org")!, accessToken: "t", refreshToken: nil,
        oauthData: nil, slidingSyncVersion: "native", storeID: "3f2a…"
    )
    let decoded = try JSONDecoder().decode(MatrixSessionData.self, from: JSONEncoder().encode(original))
    #expect(decoded.storeID == "3f2a…")
}
```

Dans `Tests/MatrixClientKitRustTests/StoragePathsTests.swift`, remplacer chaque
`StoragePaths(storage: …, userID: x)` par `StoragePaths(storage: …, segment: .legacy(x))`,
`userDirectory` par `storeDirectory`, et ajouter :

```swift
@Test func aSessionSegmentUsesItsStoreIDAsDirectory() throws {
    let root = URL(fileURLWithPath: "/tmp/matrixclientkit-tests", isDirectory: true)
    let paths = try StoragePaths(storage: .local(directory: root), segment: .session("0b1c-uuid"))
    #expect(paths.storeDirectory.lastPathComponent == "0b1c-uuid")
    #expect(paths.storeDirectory.deletingLastPathComponent().lastPathComponent == "MatrixClientKit")
}

@Test func theLegacySegmentKeepsThe03Directory() throws {
    let root = URL(fileURLWithPath: "/tmp/matrixclientkit-tests", isDirectory: true)
    let paths = try StoragePaths(storage: .local(directory: root), segment: .legacy(alice))
    // Valeur épinglée par `theUserSegmentIsStableAcrossLaunches` : une session 0.3 doit
    // retrouver son store exactement là où la 0.3 l'a créé.
    #expect(paths.storeDirectory.lastPathComponent == "a5829e99c7bc42227c63db8609d87392")
}

@Test func newSessionSegmentsAreDistinctAndNeverLookLikeADigest() {
    let a = StoreSegment.newSession().directoryName
    let b = StoreSegment.newSession().directoryName
    #expect(a != b)
    #expect(a.contains("-"))  // un UUID ; une empreinte StableDigest n'a jamais de tiret
}

@Test func theSegmentFollowsThePersistedData() {
    let legacy = MatrixSessionData(
        userID: alice, deviceID: DeviceID(rawValue: "D")!, homeserverURL: URL(string: "https://m.org")!,
        accessToken: "t", refreshToken: nil, oauthData: nil, slidingSyncVersion: "native"
    )
    #expect(StoreSegment(legacy) == .legacy(alice))
    let modern = MatrixSessionData(
        userID: alice, deviceID: DeviceID(rawValue: "D")!, homeserverURL: URL(string: "https://m.org")!,
        accessToken: "t", refreshToken: nil, oauthData: nil, slidingSyncVersion: "native", storeID: "abc-1"
    )
    #expect(StoreSegment(modern) == .session("abc-1"))
}
```

Dans `Tests/MatrixClientKitRustTests/LocalStoreTests.swift`, `makeStore(root:userID:secureStore:)`
construit désormais `LocalStore(storage: .local(directory: root), segment: .legacy(userID), secureStore: secureStore)` ;
la clé lue dans `aKeyOfTheWrongSizeIsReportedRatherThanReplaced` reste
`"\(LocalStore.keyPrefix).\(StoragePaths.segment(for: alice))"` (inchangée pour le legacy). Ajouter :

```swift
@Test func aSessionSegmentHasItsOwnKeyEntry() throws {
    let secureStore = InMemorySecureStore()
    let store = LocalStore(storage: .local(directory: makeRoot()), segment: .session("abc-1"), secureStore: secureStore)
    _ = try store.encryptionKey()
    #expect(try secureStore.data(forKey: "\(LocalStore.keyPrefix).abc-1") != nil)
}
```

Dans `Tests/MatrixClientKitRustTests/SessionDelegateTests.swift` (Review Focus 1), ajouter :

```swift
@Test func aRefreshedSessionKeepsItsStoreID() throws {
    let persistence = SessionPersistence(store: InMemorySecureStore())
    try persistence.save(MatrixSessionData(
        userID: UserID(rawValue: "@alice:matrix.org")!, deviceID: DeviceID(rawValue: "DEV1")!,
        homeserverURL: URL(string: "https://matrix.org")!, accessToken: "old", refreshToken: "r",
        oauthData: nil, slidingSyncVersion: "native", storeID: "store-1"
    ))
    let delegate = SessionDelegate(persistence: persistence)

    delegate.saveSessionInKeychain(session: Session(
        accessToken: "new", refreshToken: "r2", userId: "@alice:matrix.org", deviceId: "DEV1",
        homeserverUrl: "https://matrix.org", oauthData: nil, slidingSyncVersion: .native
    ))

    let saved = try #require(try persistence.load())
    #expect(saved.accessToken == "new")
    #expect(saved.storeID == "store-1")
}

@Test func aSessionOfAnotherDeviceDoesNotInheritTheStoreID() throws {
    let persistence = SessionPersistence(store: InMemorySecureStore())
    try persistence.save(MatrixSessionData(
        userID: UserID(rawValue: "@alice:matrix.org")!, deviceID: DeviceID(rawValue: "DEV1")!,
        homeserverURL: URL(string: "https://matrix.org")!, accessToken: "old", refreshToken: nil,
        oauthData: nil, slidingSyncVersion: "native", storeID: "store-1"
    ))
    let delegate = SessionDelegate(persistence: persistence)

    delegate.saveSessionInKeychain(session: Session(
        accessToken: "new", refreshToken: nil, userId: "@alice:matrix.org", deviceId: "DEV2",
        homeserverUrl: "https://matrix.org", oauthData: nil, slidingSyncVersion: .native
    ))

    #expect(try persistence.load()?.storeID == nil)
}
```

Dans `SessionMapperTests.swift`, remplacer les appels `sessionData(from:)` par
`sessionData(from:storeID: nil)` et ajouter un cas vérifiant que `storeID: "x"` est recopié.

- [ ] **Step 2: Vérifier l'échec**

Run: `swift test --skip MatrixClientKitIntegrationTests`
Expected: échec de compilation (`segment:`, `storeID`, `StoreSegment` introuvables).

- [ ] **Step 3: Implémenter**

`MatrixSessionData` : ajouter, après `slidingSyncVersion` :

```swift
    /// Identifiant du store local de la session, tiré à la connexion (spec 0.4, §5.1). `nil` pour
    /// une session ouverte par la 0.1 à la 0.3, dont le store vit sous l'empreinte du user ID —
    /// le décodage synthétisé lit l'absence du champ comme `nil`.
    package let storeID: String?
```

et le paramètre `storeID: String? = nil` en dernier dans `init`, affecté à `self.storeID`.

`Sources/MatrixClientKitRust/Storage/StoreSegment.swift` :

```swift
import Foundation
import MatrixClientKitCore

/// Désigne le store local d'une session (spec 0.4, §5.1).
///
/// - `legacy` : session ouverte par la 0.1 à la 0.3, dont le store vit sous l'empreinte du user ID.
///   Jamais migrée : elle garde ce chemin jusqu'à sa déconnexion.
/// - `session` : à partir de la 0.4, un identifiant aléatoire tiré à la connexion. Le store existe
///   donc avant que le user ID soit connu, ce qu'exige la connexion par QR, qui écrit les secrets
///   reçus pendant la connexion elle-même.
enum StoreSegment: Sendable, Hashable {
    case legacy(UserID)
    case session(String)

    static func newSession() -> StoreSegment {
        .session(UUID().uuidString.lowercased())
    }

    init(_ data: MatrixSessionData) {
        self = data.storeID.map(StoreSegment.session) ?? .legacy(data.userID)
    }

    /// Nom du répertoire du store sous `MatrixClientKit/`, et suffixe de son entrée Keychain.
    /// Un UUID (avec tirets) ne peut pas coïncider avec une empreinte hexadécimale.
    var directoryName: String {
        switch self {
        case let .legacy(userID): StoragePaths.segment(for: userID)
        case let .session(id): id
        }
    }

    /// La valeur à persister dans ``MatrixSessionData/storeID``.
    var storeID: String? {
        if case let .session(id) = self { return id }
        return nil
    }
}
```

`StoragePaths` : remplacer `userID:` par `segment: StoreSegment`, renommer `userDirectory` en
`storeDirectory`, et extraire la racine :

```swift
    /// `<conteneur ou répertoire>/MatrixClientKit` : le parent de tous les stores d'un stockage.
    static func root(
        for storage: MatrixStorage,
        containerURL: (String) -> URL? = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    ) throws -> URL {
        let base: URL
        switch storage.location {
        case let .appGroup(identifier):
            guard let container = containerURL(identifier) else { throw MatrixError.storage(.unavailable) }
            base = container
        case let .local(directory):
            base = directory
        }
        return base.appendingPathComponent("MatrixClientKit", isDirectory: true)
    }
```

et dans `init`, `storeDirectory = try Self.root(for: storage, containerURL: containerURL).appendingPathComponent(segment.directoryName, isDirectory: true)`.
Mettre à jour la doc du type : le segment remplace « le segment par utilisateur ».

`LocalStore` : `let segment: StoreSegment` remplace `let userID` ; `init(storage:segment:secureStore:)` ;
`paths()` → `StoragePaths(storage: storage, segment: segment)` ;
`keychainKey` → `"\(Self.keyPrefix).\(segment.directoryName)"` ; `userDirectory` → `storeDirectory`
partout. Rechercher les autres usages : `grep -rn "\.userID\b\|userDirectory\|makeLocalStore" Sources/MatrixClientKitRust`.

`SessionMapper.sessionData(from:storeID:)` : ajouter le paramètre et le passer à l'init.

`SessionDelegate.saveSessionInKeychain` :

```swift
    func saveSessionInKeychain(session: Session) {
        // La `Session` amont ignore le store local : la fusion conserve celui de la session
        // persistée, à condition qu'il s'agisse bien du même utilisateur sur le même appareil.
        // Sans elle, le premier rafraîchissement de jeton ferait rouvrir au lancement suivant le
        // chemin legacy — un compte vide, sans aucune erreur.
        let current = try? persistence.load()
        let storeID = current.flatMap { current in
            current.userID.rawValue == session.userId && current.deviceID.rawValue == session.deviceId
                ? current.storeID : nil
        }
        guard let data = try? SessionMapper.sessionData(from: session, storeID: storeID) else { return }
        try? persistence.save(data)
    }
```

`SessionRestorer` : `makeLocalStore(for segment: StoreSegment)` ; dans `restore` et
`makeNotificationResolver`, `makeLocalStore(for: StoreSegment(data))`. `RustMatrixClient.login` :
`restorer.makeLocalStore(for: .legacy(data.userID))` (provisoire jusqu'à la Task 7, qui supprime
ce chemin ; la 0.4 n'est pas publiée entre les deux).

- [ ] **Step 4: Vérifier**

Run: `swift test --skip MatrixClientKitIntegrationTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests/MatrixClientKitCoreTests Tests/MatrixClientKitRustTests
git commit -m "feat: store local désigné par un segment legacy ou par session

Le rafraîchissement de jeton conserve le storeID de la session persistée.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Baux sur les stores et ramassage des orphelins

**Files:**
- Create: `Sources/MatrixClientKitRust/Storage/StoreRegistry.swift`
- Create: `Sources/MatrixClientKitRust/Storage/OrphanedStoreSweeper.swift`
- Create: `Tests/MatrixClientKitRustTests/OrphanedStoreSweeperTests.swift`

**Interfaces:**
- Consumes: `StoreSegment`, `StoragePaths.root(for:)`, `LocalStore(storage:segment:secureStore:)` (Task 5).
- Produces:
  - `final class StoreRegistry: Sendable { static let shared: StoreRegistry; init(); func lease(_ paths: StoragePaths) -> StoreLease; func isLeased(_ directory: URL) -> Bool }`
  - `final class StoreLease: Sendable { func release() }` — libéré aussi au `deinit`.
  - `struct OrphanedStoreSweeper { init(storage: MatrixStorage, secureStore: any SecureStore, registry: StoreRegistry); func sweep(keeping kept: StoreSegment?) }`

Précision par rapport à la spec §5.4 : les clés Keychain sont supprimées **avec leur répertoire**,
jamais par simple préfixe. Le service Keychain (`com.matrixclientkit`) est commun à tous les
`MatrixStorage` d'une application ; un ramassage par préfixe effacerait les clés des stores d'un
autre stockage. Une clé sans répertoire reste en place : la doc de `LocalStore.purge()` la tient
déjà pour inoffensive.

- [ ] **Step 1: Écrire les tests**

`Tests/MatrixClientKitRustTests/OrphanedStoreSweeperTests.swift` :

```swift
import Testing
import Foundation
@testable import MatrixClientKitRust
import MatrixClientKitCore

private struct Fixture {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mck-\(UUID().uuidString)")
    let secureStore = InMemorySecureStore()
    let registry = StoreRegistry()
    var storage: MatrixStorage { .local(directory: root) }

    /// Crée un store sur disque (répertoires + clé) et le rend.
    func makeStore(_ segment: StoreSegment) throws -> LocalStore {
        let store = LocalStore(storage: storage, segment: segment, secureStore: secureStore)
        _ = try store.encryptionKey()
        try store.paths().createDirectoriesIfNeeded()
        return store
    }

    func exists(_ store: LocalStore) throws -> Bool {
        FileManager.default.fileExists(atPath: try store.paths().storeDirectory.path)
    }

    func hasKey(_ segment: StoreSegment) throws -> Bool {
        try secureStore.data(forKey: "\(LocalStore.keyPrefix).\(segment.directoryName)") != nil
    }

    var sweeper: OrphanedStoreSweeper {
        OrphanedStoreSweeper(storage: storage, secureStore: secureStore, registry: registry)
    }
}

@Test func thePersistedSessionsStoreIsKept() throws {
    let fixture = Fixture()
    let kept = try fixture.makeStore(.session("kept-1"))
    fixture.sweeper.sweep(keeping: .session("kept-1"))
    #expect(try fixture.exists(kept))
    #expect(try fixture.hasKey(.session("kept-1")))
}

@Test func anUnleasedUnpersistedStoreIsRemovedWithItsKey() throws {
    let fixture = Fixture()
    let orphan = try fixture.makeStore(.session("orphan-1"))
    fixture.sweeper.sweep(keeping: .session("kept-1"))
    #expect(try !fixture.exists(orphan))
    #expect(try !fixture.hasKey(.session("orphan-1")))
}

@Test func anOrphanedLegacyStoreIsRemovedToo() throws {
    // Le cas 0.3 : une connexion par-dessus une session persistée laissait l'ancien store.
    let fixture = Fixture()
    let bob = UserID(rawValue: "@bob:matrix.org")!
    let orphan = try fixture.makeStore(.legacy(bob))
    fixture.sweeper.sweep(keeping: nil)
    #expect(try !fixture.exists(orphan))
    #expect(try !fixture.hasKey(.legacy(bob)))
}

// Review Focus 3 : un store ouvert par une session vivante du processus n'est jamais ramassé,
// même quand l'entrée Keychain désigne une autre session.
@Test func aLeasedStoreIsNeverRemoved() throws {
    let fixture = Fixture()
    let live = try fixture.makeStore(.session("live-1"))
    let lease = fixture.registry.lease(try live.paths())
    fixture.sweeper.sweep(keeping: .session("other"))
    #expect(try fixture.exists(live))
    withExtendedLifetime(lease) {}
}

@Test func releasingTheLeaseMakesTheStoreCollectable() throws {
    let fixture = Fixture()
    let live = try fixture.makeStore(.session("live-1"))
    let lease = fixture.registry.lease(try live.paths())
    lease.release()
    fixture.sweeper.sweep(keeping: nil)
    #expect(try !fixture.exists(live))
}

@Test func twoLeasesOnTheSameStoreNeedTwoReleases() throws {
    // Reconnexion : la session remplacée et sa remplaçante tiennent le même store.
    let fixture = Fixture()
    let store = try fixture.makeStore(.session("shared"))
    let first = fixture.registry.lease(try store.paths())
    let second = fixture.registry.lease(try store.paths())
    first.release()
    #expect(fixture.registry.isLeased(try store.paths().storeDirectory))
    second.release()
    #expect(!fixture.registry.isLeased(try store.paths().storeDirectory))
}

@Test func aMissingRootIsNotAnError() {
    Fixture().sweeper.sweep(keeping: nil)  // ne lève pas, ne crée rien
}

@Test func filesBesideTheStoresAreLeftAlone() throws {
    let fixture = Fixture()
    let root = try StoragePaths.root(for: fixture.storage)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("note.txt")
    try Data("x".utf8).write(to: file)
    fixture.sweeper.sweep(keeping: nil)
    #expect(FileManager.default.fileExists(atPath: file.path))
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `swift test --filter OrphanedStoreSweeperTests`
Expected: échec de compilation.

- [ ] **Step 3: Implémenter**

`Sources/MatrixClientKitRust/Storage/StoreRegistry.swift` :

```swift
import Foundation
import Synchronization

/// Les stores ouverts dans ce processus : tentatives de connexion en cours et sessions vivantes
/// (spec 0.4, §5.4).
///
/// Le ramassage des orphelins ne peut pas se fier à la seule session persistée : l'entrée
/// Keychain est unique par service, et une seconde connexion dans le même processus l'écrase
/// pendant que la première session tourne encore. Un bail compté par répertoire répond à la seule
/// question utile — « quelqu'un, ici, utilise-t-il ce store ? ». Compté, parce qu'une reconnexion
/// tient brièvement deux baux sur le même store.
final class StoreRegistry: Sendable {
    static let shared = StoreRegistry()

    private let counts = Mutex<[String: Int]>([:])

    init() {}

    func lease(_ paths: StoragePaths) -> StoreLease {
        let key = Self.key(paths.storeDirectory)
        counts.withLock { $0[key, default: 0] += 1 }
        return StoreLease(key: key, registry: self)
    }

    func isLeased(_ directory: URL) -> Bool {
        counts.withLock { ($0[Self.key(directory)] ?? 0) > 0 }
    }

    fileprivate func release(_ key: String) {
        counts.withLock { counts in
            let remaining = (counts[key] ?? 1) - 1
            counts[key] = remaining > 0 ? remaining : nil
        }
    }

    private static func key(_ directory: URL) -> String {
        directory.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

/// Un bail sur un store. Libéré explicitement ou à la libération de son porteur.
final class StoreLease: Sendable {
    private let key: String
    private let registry: StoreRegistry
    private let released = Mutex(false)

    fileprivate init(key: String, registry: StoreRegistry) {
        self.key = key
        self.registry = registry
    }

    func release() {
        let wasReleased = released.withLock { released in
            defer { released = true }
            return released
        }
        if !wasReleased { registry.release(key) }
    }

    deinit { release() }
}
```

`Sources/MatrixClientKitRust/Storage/OrphanedStoreSweeper.swift` :

```swift
import Foundation
import MatrixClientKitCore

/// Supprime les stores que plus aucune session ne peut rouvrir (spec 0.4, §5.4).
///
/// Au mieux : un échec est ignoré et retenté au passage suivant, il ne fait jamais échouer une
/// connexion ni une restauration. Réservé à l'application — l'extension ne purge jamais rien
/// (spec 0.3, §7) ; c'est à l'appelant de ne pas l'invoquer avec ce rôle.
struct OrphanedStoreSweeper {
    let storage: MatrixStorage
    let secureStore: any SecureStore
    let registry: StoreRegistry

    /// - Parameter kept: le store de la session persistée, épargné même sans bail ; `nil` quand
    ///   aucune session n'est persistée.
    func sweep(keeping kept: StoreSegment?) {
        guard let root = try? StoragePaths.root(for: storage),
            let entries = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        else { return }

        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let name = entry.lastPathComponent
            guard isDirectory, name != kept?.directoryName, !registry.isLeased(entry) else { continue }

            // Le nom du répertoire suffit à retrouver la clé : même mise en page pour les deux
            // segments, d'où `.session(name)` y compris pour un store legacy.
            try? LocalStore(storage: storage, segment: .session(name), secureStore: secureStore).purge()
        }
    }
}
```

- [ ] **Step 4: Vérifier**

Run: `swift test --filter OrphanedStoreSweeperTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MatrixClientKitRust/Storage/StoreRegistry.swift Sources/MatrixClientKitRust/Storage/OrphanedStoreSweeper.swift Tests/MatrixClientKitRustTests/OrphanedStoreSweeperTests.swift
git commit -m "feat: baux sur les stores vivants et ramassage des stores orphelins

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `LoginAttempt` — une seule séquence de connexion

Supprime la poignée de main en mémoire : la connexion se fait directement sur le client SQLite d'un
store neuf. Branche le ramassage et les baux sur la connexion et la restauration.

**Files:**
- Create: `Sources/MatrixClientKitRust/LoginAttempt.swift`
- Modify: `Sources/MatrixClientKitRust/SessionRestorer.swift` (`ClientTarget`, `makeClient(target:localStore:)`, `sweeper`, bail à la restauration)
- Modify: `Sources/MatrixClientKitRust/RustMatrixSession.swift` (`make(client:restorer:localStore:lease:)`, propriétés `segment`, `homeserverURL`)
- Modify: `Sources/MatrixClientKitRust/RustMatrixClient.swift` (`login` via `LoginAttempt`, suppression de `makeHandshakeClient`)
- Create: `Tests/MatrixClientKitRustTests/LoginAttemptTests.swift`
- Modify: `Tests/MatrixClientKitRustTests/SessionRestorerTests.swift`

**Interfaces:**
- Consumes: `StoreSegment`, `StoreRegistry`, `StoreLease`, `OrphanedStoreSweeper` (Tasks 5–6).
- Produces:
  - `enum ClientTarget: Sendable, Hashable { case homeserver(URL); case serverName(String) }`
  - `SessionRestorer.makeClient(target: ClientTarget, localStore: LocalStore) async throws -> Client` (l'ancien `makeClient(homeserver:localStore:)` appelle `.homeserver`).
  - `SessionRestorer.registry: StoreRegistry` (`.shared` par défaut, injectable dans `package init`), `SessionRestorer.sweepOrphans(keeping:)`.
  - `struct LoginAttemptStore` — `static func prepare(restorer:reusing:) throws -> LoginAttemptStore`, `segment`, `localStore`, `lease`, `func discard()`.
  - `final class LoginAttempt: Sendable` — `static func begin(restorer:target:reusing:makeClient:) async throws -> LoginAttempt` ; `let client: Client` ; `func authenticate(_ credentials: Credentials, deviceID: DeviceID?) async throws` ; `func succeed(expecting userID: UserID?) async throws -> RustMatrixSession` ; `func fail()`.
  - `RustMatrixSession.make(client:restorer:localStore:lease:)` ; `RustMatrixSession.segment: StoreSegment`, `RustMatrixSession.homeserverURL: URL` (internes).

- [ ] **Step 1: Écrire les tests**

`Tests/MatrixClientKitRustTests/LoginAttemptTests.swift` :

```swift
import Testing
import Foundation
import MatrixRustSDK
@testable import MatrixClientKitRust
import MatrixClientKitCore

private func makeRestorer(root: URL, registry: StoreRegistry = StoreRegistry()) -> SessionRestorer {
    SessionRestorer(storage: .local(directory: root), secureStore: InMemorySecureStore(), registry: registry)
}

private func newRoot() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mck-\(UUID().uuidString)")
}

@Test func aNewAttemptPreparesAFreshLeasedStore() throws {
    let registry = StoreRegistry()
    let restorer = makeRestorer(root: newRoot(), registry: registry)
    let store = try LoginAttemptStore.prepare(restorer: restorer, reusing: nil)

    guard case .session = store.segment else { Issue.record("segment legacy pour une connexion neuve"); return }
    let directory = try store.localStore.paths().storeDirectory
    #expect(FileManager.default.fileExists(atPath: directory.path))
    #expect(registry.isLeased(directory))
}

@Test func discardingANewAttemptErasesItsStoreAndLease() throws {
    let registry = StoreRegistry()
    let restorer = makeRestorer(root: newRoot(), registry: registry)
    let store = try LoginAttemptStore.prepare(restorer: restorer, reusing: nil)
    let directory = try store.localStore.paths().storeDirectory

    store.discard()

    #expect(!FileManager.default.fileExists(atPath: directory.path))
    #expect(!registry.isLeased(directory))
    #expect(try restorer.secureStore.data(forKey: "\(LocalStore.keyPrefix).\(store.segment.directoryName)") == nil)
}

@Test func discardingAReauthenticationKeepsTheStore() throws {
    let registry = StoreRegistry()
    let restorer = makeRestorer(root: newRoot(), registry: registry)
    let existing = try LoginAttemptStore.prepare(restorer: restorer, reusing: nil)
    let reuse = try LoginAttemptStore.prepare(restorer: restorer, reusing: existing.segment)
    let directory = try reuse.localStore.paths().storeDirectory

    reuse.discard()

    // Le store appartient toujours à la session remplacée.
    #expect(FileManager.default.fileExists(atPath: directory.path))
    #expect(registry.isLeased(directory))  // bail de `existing`
}

@Test func aFailedClientBuildLeavesNothingBehind() async throws {
    let root = newRoot()
    let registry = StoreRegistry()
    let restorer = makeRestorer(root: root, registry: registry)

    await #expect(throws: MatrixError.network(.offline)) {
        _ = try await LoginAttempt.begin(restorer: restorer, target: .homeserver(URL(string: "https://x.org")!), reusing: nil) { _, _ in
            throw MatrixError.network(.offline)
        }
    }

    let stores = (try? FileManager.default.contentsOfDirectory(atPath: StoragePaths.root(for: .local(directory: root)).path)) ?? []
    #expect(stores.isEmpty)
}

@Test func beginningAnAttemptSweepsOrphans() async throws {
    let root = newRoot()
    let restorer = makeRestorer(root: root)
    let orphan = LocalStore(storage: .local(directory: root), segment: .session("orphan"), secureStore: restorer.secureStore)
    _ = try orphan.encryptionKey()
    try orphan.paths().createDirectoriesIfNeeded()

    _ = try? await LoginAttempt.begin(restorer: restorer, target: .homeserver(URL(string: "https://x.org")!), reusing: nil) { _, _ in
        throw MatrixError.network(.offline)
    }

    #expect(!FileManager.default.fileExists(atPath: try orphan.paths().storeDirectory.path))
}

@Test func theExtensionNeverSweeps() throws {
    let root = newRoot()
    let restorer = SessionRestorer(
        storage: .local(directory: root), secureStore: InMemorySecureStore(),
        role: .notificationExtension, registry: StoreRegistry()
    )
    let orphan = LocalStore(storage: .local(directory: root), segment: .session("orphan"), secureStore: restorer.secureStore)
    _ = try orphan.encryptionKey()
    try orphan.paths().createDirectoriesIfNeeded()

    restorer.sweepOrphans(keeping: nil)

    #expect(FileManager.default.fileExists(atPath: try orphan.paths().storeDirectory.path))
}
```

Dans `SessionRestorerTests.swift`, `makeRestorer()` passe `registry: StoreRegistry()` ; ajouter :

```swift
@Test func restoringA03SessionOpensTheLegacyStore() async throws {
    let restorer = makeRestorer()
    try restorer.persistence.save(persistedSession())  // sans storeID
    var requested: StoreSegment?

    _ = try? await restorer.restore { _, localStore in
        requested = localStore.segment
        throw MatrixError.storage(.unavailable)
    }

    #expect(requested == .legacy(UserID(rawValue: "@alice:persisted.example")!))
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `swift test --filter "LoginAttemptTests|SessionRestorerTests"`
Expected: échec de compilation.

- [ ] **Step 3: Adapter `SessionRestorer`**

- Ajouter `let registry: StoreRegistry` ; paramètre `registry: StoreRegistry = .shared` en dernier
  dans `package init(storage:secureStore:role:lockPolicy:registry:)` et dans le `convenience init`.
- Ajouter :

```swift
/// Comment le builder désigne le homeserver.
enum ClientTarget: Sendable, Hashable {
    /// Adresse déjà résolue : celle d'une session persistée, ou d'un client créé par URL.
    case homeserver(URL)
    /// Nom de serveur, URL ou user ID à résoudre par `.well-known` (découverte, QR scanné).
    case serverName(String)
}
```

  `makeClient(target:localStore:)` reprend le corps actuel de `makeClient(homeserver:localStore:)`
  en remplaçant `.homeserverUrl(url: homeserver.absoluteString)` par :

```swift
            var builder: ClientBuilder
            switch target {
            case let .homeserver(url):
                builder = ClientBuilder().homeserverUrl(url: url.absoluteString)
            case let .serverName(name):
                builder = ClientBuilder().serverNameOrHomeserverUrl(serverNameOrUrl: name)
            }
            builder = builder
                .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
                // … reste inchangé (sessionDelegate, autoEnableCrossSigning, sqliteStore, verrou)
```

  et `makeClient(homeserver:localStore:)` devient `try await makeClient(target: .homeserver(homeserver), localStore: localStore)`.
- Ajouter :

```swift
    var sweeper: OrphanedStoreSweeper {
        OrphanedStoreSweeper(storage: storage, secureStore: secureStore, registry: registry)
    }

    /// Ramasse les stores orphelins, sauf dans l'extension (spec 0.3, §7 ; spec 0.4, §5.4).
    func sweepOrphans(keeping kept: StoreSegment?) {
        guard role == .application else { return }
        sweeper.sweep(keeping: kept)
    }
```

- Dans `restore(makeClient:)` : après `persistence.load()` réussi (y compris quand il rend `nil`),
  appeler `sweepOrphans(keeping: data.map(StoreSegment.init))` **avant** le `guard let data` ;
  puis `let lease = registry.lease(try localStore.paths())` avant `makeClient`, et passer
  `lease` à `RustMatrixSession.make`. Si `load()` lève, ne pas ramasser (on ne sait pas ce qui est
  persisté) — le `try` existant propage déjà.

- [ ] **Step 4: Implémenter `LoginAttempt`**

`Sources/MatrixClientKitRust/LoginAttempt.swift` :

```swift
import Foundation
import Synchronization
import MatrixRustSDK
import MatrixClientKitCore

/// Le store d'une tentative de connexion, séparé du client pour être testable sans FFI.
struct LoginAttemptStore: Sendable {
    let segment: StoreSegment
    let localStore: LocalStore
    let lease: StoreLease
    /// `false` pour une reconnexion : le store appartient à la session remplacée.
    let ownsStore: Bool

    /// Prépare le store : neuf (`reusing == nil`) ou celui d'une session existante.
    ///
    /// Le bail est pris avant le ramassage, pour qu'une tentative ne ramasse jamais son propre
    /// store ; le ramassage épargne aussi la session persistée.
    static func prepare(restorer: SessionRestorer, reusing existing: StoreSegment?) throws -> LoginAttemptStore {
        let segment = existing ?? .newSession()
        let localStore = restorer.makeLocalStore(for: segment)
        let paths = try localStore.paths()
        let lease = restorer.registry.lease(paths)

        let persisted = (try? restorer.persistence.load()).flatMap { $0 }
        restorer.sweepOrphans(keeping: persisted.map(StoreSegment.init))

        return LoginAttemptStore(segment: segment, localStore: localStore, lease: lease, ownsStore: existing == nil)
    }

    /// Abandonne la tentative : efface le store s'il lui appartient, puis rend le bail.
    func discard() {
        if ownsStore { try? localStore.purge() }
        lease.release()
    }
}

/// Une connexion en cours, quel que soit le flux (spec 0.4, §5.2).
///
/// Le client est construit d'emblée sur le store SQLite chiffré de la tentative : l'amont pose une
/// session une seule fois par client (§2.7), et la connexion par QR écrit les secrets reçus dans ce
/// store pendant la connexion elle-même — une poignée de main en mémoire les perdrait.
final class LoginAttempt: Sendable {
    let client: Client
    private let store: LoginAttemptStore
    private let restorer: SessionRestorer
    private let isOver = Mutex(false)

    private init(client: Client, store: LoginAttemptStore, restorer: SessionRestorer) {
        self.client = client
        self.store = store
        self.restorer = restorer
    }

    static func begin(
        restorer: SessionRestorer,
        target: ClientTarget,
        reusing existing: StoreSegment?
    ) async throws -> LoginAttempt {
        try await begin(restorer: restorer, target: target, reusing: existing) { target, localStore in
            try await restorer.makeClient(target: target, localStore: localStore)
        }
    }

    /// - Parameter makeClient: couture de test, comme pour ``SessionRestorer/restore(makeClient:)``.
    static func begin(
        restorer: SessionRestorer,
        target: ClientTarget,
        reusing existing: StoreSegment?,
        makeClient: (ClientTarget, LocalStore) async throws -> Client
    ) async throws -> LoginAttempt {
        let store = try LoginAttemptStore.prepare(restorer: restorer, reusing: existing)
        do {
            let client = try await makeClient(target, store.localStore)
            return LoginAttempt(client: client, store: store, restorer: restorer)
        } catch {
            store.discard()
            throw ErrorMapper.map(error)
        }
    }

    var segment: StoreSegment { store.segment }

    /// Connexion par identifiants. `deviceID` réutilise l'appareil d'une session en soft logout.
    func authenticate(_ credentials: Credentials, deviceID: DeviceID?) async throws {
        do {
            switch credentials {
            case let .password(username, password, deviceName):
                try await client.login(username: username, password: password,
                                       initialDeviceName: deviceName, deviceId: deviceID?.rawValue)
            case let .email(address, password, deviceName):
                try await client.loginWithEmail(email: address, password: password,
                                                initialDeviceName: deviceName, deviceId: deviceID?.rawValue)
            }
        } catch {
            throw ErrorMapper.mapAuthentication(error)
        }
    }

    /// Persiste la session obtenue et la construit sur ce même client.
    ///
    /// - Parameter userID: pour une reconnexion, l'utilisateur attendu. Un autre compte est
    ///   déconnecté côté serveur et refusé (spec 0.4, §4.6) : persister ses jetons sur le store
    ///   d'un autre utilisateur mélangerait deux identités cryptographiques.
    func succeed(expecting userID: UserID?) async throws -> RustMatrixSession {
        let data = try SessionMapper.sessionData(from: client.session(), storeID: store.segment.storeID)
        if let userID, data.userID != userID {
            try? await client.logout()
            throw MatrixError.authentication(.invalidCredentials)
        }
        try restorer.persistence.save(data)
        let session = try await RustMatrixSession.make(
            client: client, restorer: restorer, localStore: store.localStore, lease: store.lease
        )
        isOver.withLock { $0 = true }
        return session
    }

    /// Abandonne la tentative. Sans effet après ``succeed(expecting:)`` ; idempotent.
    func fail() {
        let alreadyOver = isOver.withLock { over in
            defer { over = true }
            return over
        }
        if !alreadyOver { store.discard() }
    }
}
```

Note : `succeed` ne rend pas le bail : il passe à la session, qui le garde jusqu'à sa libération.

- [ ] **Step 5: Adapter `RustMatrixSession` et `RustMatrixClient`**

`RustMatrixSession` : ajouter les propriétés internes `let segment: StoreSegment`,
`let homeserverURL: URL`, `private let lease: StoreLease` ; `make(client:restorer:localStore:lease:)`
les renseigne (`segment: localStore.segment`, `homeserverURL: data.homeserverURL`) ; ajouter
`lease` à l'init privé.

`RustMatrixClient.login` devient :

```swift
    /// Ouvre une session sur un store neuf (spec 0.4, §5.2).
    public func login(_ credentials: Credentials) async throws -> any MatrixClientKitCore.MatrixSession {
        let attempt = try await LoginAttempt.begin(restorer: restorer, target: .homeserver(homeserver), reusing: nil)
        do {
            try await attempt.authenticate(credentials, deviceID: nil)
            return try await attempt.succeed(expecting: nil)
        } catch {
            attempt.fail()
            throw ErrorMapper.mapAuthentication(error)
        }
    }
```

Supprimer `makeHandshakeClient()` et le long commentaire de `login` sur la poignée de main ;
remplacer par la doc ci-dessus. `grep -rn "handshake\|Handshake" Sources` doit être vide.

- [ ] **Step 6: Vérifier**

Run: `swift test --skip MatrixClientKitIntegrationTests`
Expected: PASS.

Puis, sur le Tuwunel (non-régression — demander les mots de passe à l'utilisateur, cf. mémoire
« Integration test environment ») :
Run: `./Scripts/check-integration-env.sh && swift test --filter MatrixClientKitIntegrationTests`
Expected: PASS (les cas de récupération restent ignorés).

- [ ] **Step 7: Commit**

```bash
git add Sources Tests/MatrixClientKitRustTests
git commit -m "feat!: connexion directe sur un store par session, sans poignée de main

Le cross-signing est amorcé dès la connexion ; connexion et restauration
ramassent les stores orphelins.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Découverte du serveur et `loginDetails()`

**Files:**
- Create: `Sources/MatrixClientKitRust/Bridge/ServerInput.swift`
- Create: `Sources/MatrixClientKitRust/Bridge/LoginDetailsMapper.swift`
- Modify: `Sources/MatrixClientKitRust/Bridge/ErrorMapper.swift` (`ClientBuildError`)
- Modify: `Sources/MatrixClientKitRust/RustMatrixClient.swift` (sonde, `discover`, `loginDetails`)
- Modify: `Sources/MatrixClientKit/MatrixClientKit.swift` (`Matrix.client(server:storage:)`)
- Create: `Tests/MatrixClientKitRustTests/ServerInputTests.swift`
- Modify: `Tests/MatrixClientKitRustTests/ErrorMapperTests.swift`

**Interfaces:**
- Consumes: `LoginDetails`, `OAuthPrompt` (Task 2), `ClientTarget` (Task 7).
- Produces:
  - `enum ServerInput { static func normalize(_ input: String) throws -> String }`
  - `enum LoginDetailsMapper { static func map(_ details: HomeserverLoginDetails, fallback: URL) -> LoginDetails; static func prompt(_ prompt: MatrixRustSDK.OAuthPrompt) -> MatrixClientKitCore.OAuthPrompt?; static func prompt(_ prompt: MatrixClientKitCore.OAuthPrompt) -> MatrixRustSDK.OAuthPrompt }`
  - `RustMatrixClient.discover(server: String, storage: MatrixStorage) async throws -> RustMatrixClient`
  - `RustMatrixClient.loginDetails() async throws -> LoginDetails`
  - `Matrix.client(server: String, storage: MatrixStorage) async throws -> any MatrixClient`

- [ ] **Step 1: Écrire les tests**

`Tests/MatrixClientKitRustTests/ServerInputTests.swift` (Review Focus 5) :

```swift
import Testing
@testable import MatrixClientKitRust
import MatrixClientKitCore

@Test func surroundingWhitespaceIsTrimmed() throws {
    #expect(try ServerInput.normalize("  matrix.org \n") == "matrix.org")
}

@Test func aUserIDIsReducedToItsServerName() throws {
    #expect(try ServerInput.normalize("@alice:matrix.org") == "matrix.org")
    #expect(try ServerInput.normalize("@alice:example.com:8448") == "example.com:8448")
}

@Test func anURLIsKeptAsIs() throws {
    #expect(try ServerInput.normalize("https://matrix.example.com/") == "https://matrix.example.com/")
}

@Test(arguments: ["", "   ", "@alice", "@alice:"])
func unusableInputIsRejectedBeforeAnyNetworkCall(_ input: String) {
    #expect(throws: MatrixError.self) { try ServerInput.normalize(input) }
}
```

Dans `ErrorMapperTests.swift`, ajouter :

```swift
@Test func anUnreachableServerIsOffline() {
    #expect(ErrorMapper.map(ClientBuildError.ServerUnreachable(message: "x")) == .network(.offline))
}

@Test(arguments: [
    ClientBuildError.InvalidServerName(message: "x"),
    .WellKnownLookupFailed(message: "x"),
    .WellKnownDeserializationError(message: "x"),
])
func discoveryFailuresAreUnexpected(_ error: ClientBuildError) {
    guard case .unexpected = ErrorMapper.map(error) else {
        Issue.record("attendu .unexpected")
        return
    }
}
```

et dans un nouveau `Tests/MatrixClientKitRustTests/LoginDetailsMapperTests.swift` :

```swift
import Testing
import MatrixRustSDK
@testable import MatrixClientKitRust
import MatrixClientKitCore

@Test func promptsMapBothWays() {
    #expect(LoginDetailsMapper.prompt(MatrixRustSDK.OAuthPrompt.create) == .create)
    #expect(LoginDetailsMapper.prompt(MatrixRustSDK.OAuthPrompt.login) == .login)
    #expect(LoginDetailsMapper.prompt(MatrixRustSDK.OAuthPrompt.consent) == .consent)
    #expect(LoginDetailsMapper.prompt(MatrixRustSDK.OAuthPrompt.unknown(value: "x")) == nil)
    #expect(LoginDetailsMapper.prompt(MatrixClientKitCore.OAuthPrompt.create) == .create)
}
```

(`HomeserverLoginDetails` est une classe FFI non constructible en test : son mappage complet est
couvert par l'intégration, Tasks 14–15.)

- [ ] **Step 2: Vérifier l'échec**

Run: `swift test --filter "ServerInputTests|ErrorMapperTests|LoginDetailsMapperTests"`
Expected: échec de compilation.

- [ ] **Step 3: Implémenter**

`Sources/MatrixClientKitRust/Bridge/ServerInput.swift` :

```swift
import MatrixClientKitCore

/// Ce qu'un utilisateur tape dans le champ « serveur » d'un écran de connexion.
enum ServerInput {
    /// Rend une chaîne acceptée par `serverNameOrHomeserverUrl` : nom de serveur ou URL.
    ///
    /// Un user ID est réduit à son nom de serveur — l'amont propose `serverNameFromUserId`, mais
    /// une seule entrée de builder garde le chemin unique. Une saisie vide est rejetée ici, sans
    /// appel réseau.
    static func normalize(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@") {
            guard let colon = trimmed.firstIndex(of: ":") else { throw invalid(input) }
            let server = String(trimmed[trimmed.index(after: colon)...])
            guard !server.isEmpty else { throw invalid(input) }
            return server
        }
        guard !trimmed.isEmpty else { throw invalid(input) }
        return trimmed
    }

    private static func invalid(_ input: String) -> MatrixError {
        .unexpected(message: "Enter a server name, a homeserver URL or a user ID.", details: input)
    }
}
```

`Sources/MatrixClientKitRust/Bridge/LoginDetailsMapper.swift` :

```swift
import Foundation
import MatrixRustSDK
import MatrixClientKitCore

enum LoginDetailsMapper {
    static func map(_ details: HomeserverLoginDetails, fallback: URL) -> LoginDetails {
        LoginDetails(
            homeserver: URL(string: details.url()) ?? fallback,
            supportsPassword: details.supportsPasswordLogin(),
            supportsOAuth: details.supportsOauthLogin(),
            supportsSSO: details.supportsSsoLogin(),
            oauthPrompts: Set(details.supportedOauthPrompts().compactMap(prompt))
        )
    }

    /// Un prompt inconnu n'est pas utilisable par l'application : il est ignoré (spec 0.4, §4.2).
    static func prompt(_ prompt: MatrixRustSDK.OAuthPrompt) -> MatrixClientKitCore.OAuthPrompt? {
        switch prompt {
        case .login: .login
        case .create: .create
        case .consent: .consent
        case .unknown: nil
        }
    }

    static func prompt(_ prompt: MatrixClientKitCore.OAuthPrompt) -> MatrixRustSDK.OAuthPrompt {
        switch prompt {
        case .login: .login
        case .create: .create
        case .consent: .consent
        }
    }
}
```

`ErrorMapper.map(_ error: any Error)` : ajouter avant `default` :

```swift
        case let error as ClientBuildError:
            return map(error)
```

et :

```swift
    /// Erreurs de construction du client, dont la découverte du homeserver (spec 0.4, §6).
    static func map(_ error: ClientBuildError) -> MatrixError {
        switch error {
        case .ServerUnreachable:
            return .network(.offline)
        case let .InvalidServerName(message):
            return .unexpected(message: "This is not a valid server name.", details: message)
        case let .WellKnownLookupFailed(message), let .WellKnownDeserializationError(message):
            return .unexpected(message: "The server's discovery information could not be read.", details: message)
        default:
            return .unexpected(message: String(describing: error), details: nil)
        }
    }
```

`RustMatrixClient` : la sonde est gardée par un acteur interne.

```swift
/// Client à store en mémoire, sans session, pour la découverte et `loginDetails()` (spec 0.4,
/// §5.3). Jamais utilisé pour se connecter : l'amont pose une session une seule fois par client.
actor ProbeClient {
    private let target: ClientTarget
    private var client: Client?

    init(target: ClientTarget, client: Client? = nil) {
        self.target = target
        self.client = client
    }

    func get() async throws -> Client {
        if let client { return client }
        let builder: ClientBuilder
        switch target {
        case let .homeserver(url): builder = ClientBuilder().homeserverUrl(url: url.absoluteString)
        case let .serverName(name): builder = ClientBuilder().serverNameOrHomeserverUrl(serverNameOrUrl: name)
        }
        do {
            let built = try await builder
                .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
                .inMemoryStore()
                .build()
            client = built
            return built
        } catch {
            throw ErrorMapper.map(error)
        }
    }
}
```

Dans `RustMatrixClient` : propriété `private let probe: ProbeClient` ; les deux inits existants la
créent avec `ProbeClient(target: .homeserver(homeserver))` ; ajouter :

```swift
    private init(homeserver: URL, restorer: SessionRestorer, probe: ProbeClient) {
        self.homeserver = homeserver
        self.restorer = restorer
        self.probe = probe
    }

    /// Résout un nom de serveur, une URL ou un user ID en homeserver (spec 0.4, §4.1).
    public static func discover(server: String, storage: MatrixStorage) async throws -> RustMatrixClient {
        let probe = ProbeClient(target: .serverName(try ServerInput.normalize(server)))
        let client = try await probe.get()
        guard let homeserver = URL(string: client.homeserver()) else {
            throw MatrixError.unexpected(message: "The server returned an invalid homeserver URL.", details: client.homeserver())
        }
        return RustMatrixClient(homeserver: homeserver, restorer: SessionRestorer(storage: storage), probe: probe)
    }

    public func loginDetails() async throws -> LoginDetails {
        let client = try await probe.get()
        return LoginDetailsMapper.map(await client.homeserverLoginDetails(), fallback: homeserver)
    }
```

`Sources/MatrixClientKit/MatrixClientKit.swift`, dans `enum Matrix` :

```swift
    /// Creates a client from what a user typically types on a sign-in screen: a server name
    /// (`matrix.org`), a homeserver URL, or a user ID (`@alice:matrix.org`).
    ///
    /// The homeserver is discovered through the server's `.well-known` information, which needs
    /// the network: ``MatrixClient/homeserver`` then holds the resolved address.
    ///
    /// - Throws: ``MatrixError/network(_:)`` when the server cannot be reached;
    ///   ``MatrixError/unexpected(message:details:)`` when the input is not a server, or its
    ///   discovery information cannot be read.
    public static func client(server: String, storage: MatrixStorage) async throws -> any MatrixClient {
        try await RustMatrixClient.discover(server: server, storage: storage)
    }
```

- [ ] **Step 4: Vérifier**

Run: `swift test --skip MatrixClientKitIntegrationTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests/MatrixClientKitRustTests
git commit -m "feat: découverte du serveur et loginDetails()

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Connexion OAuth

**Files:**
- Create: `Sources/MatrixClientKitRust/Bridge/OAuthMapper.swift`
- Create: `Sources/MatrixClientKitRust/RustOAuthLoginFlow.swift`
- Modify: `Sources/MatrixClientKitRust/RustMatrixClient.swift` (`beginOAuthLogin`)
- Create: `Tests/MatrixClientKitRustTests/OAuthMapperTests.swift`
- Create: `Tests/MatrixClientKitRustTests/SingleUseGateTests.swift`

**Interfaces:**
- Consumes: `OAuthConfiguration`, `OAuthPrompt` (Task 2), `OAuthLoginFlow` (Task 4), `LoginAttempt` (Task 7), `LoginDetailsMapper.prompt` (Task 8).
- Produces:
  - `enum OAuthMapper { static func configuration(_ c: OAuthConfiguration) -> MatrixRustSDK.OAuthConfiguration; static func map(_ error: any Error) -> any Error }`
  - `final class SingleUseGate: Sendable { enum Claim { case granted, refused }; func claimCompletion() -> Bool; func claimCancellation() -> Bool; func completionFailed(); func completionSucceeded() }`
  - `final class RustOAuthLoginFlow: OAuthLoginFlow` — `static func begin(attempt: LoginAttempt, configuration:prompt:loginHint:deviceID:expecting:onSuccess:) async throws -> RustOAuthLoginFlow`
  - `RustMatrixClient.beginOAuthLogin(_:prompt:loginHint:) async throws -> any OAuthLoginFlow`

- [ ] **Step 1: Écrire les tests**

`Tests/MatrixClientKitRustTests/OAuthMapperTests.swift` :

```swift
import Testing
import Foundation
import MatrixRustSDK
@testable import MatrixClientKitRust
import MatrixClientKitCore

@Test func theConfigurationIsMappedFieldByField() {
    let mapped = OAuthMapper.configuration(MatrixClientKitCore.OAuthConfiguration(
        clientName: "Example",
        redirectURI: URL(string: "com.example.app:/callback")!,
        clientURI: URL(string: "https://example.com")!,
        logoURI: URL(string: "https://example.com/logo.png")!,
        termsOfServiceURI: URL(string: "https://example.com/tos")!,
        policyURI: URL(string: "https://example.com/privacy")!,
        staticRegistrations: [URL(string: "https://matrix.example.com")!: "client-123"]
    ))
    #expect(mapped.clientName == "Example")
    #expect(mapped.redirectUri == "com.example.app:/callback")
    #expect(mapped.clientUri == "https://example.com")
    #expect(mapped.logoUri == "https://example.com/logo.png")
    #expect(mapped.tosUri == "https://example.com/tos")
    #expect(mapped.policyUri == "https://example.com/privacy")
    #expect(mapped.staticRegistrations == ["https://matrix.example.com": "client-123"])
}

@Test func oauthErrorsFollowTheSpecTable() {
    #expect(OAuthMapper.map(OAuthError.NotSupported(message: "x")) as? MatrixError == .authentication(.unsupportedLoginType))
    #expect(OAuthMapper.map(OAuthError.MetadataInvalid(message: "x")) as? MatrixError == .server(.invalidResponse))
    #expect(OAuthMapper.map(OAuthError.Cancelled(message: "x")) is CancellationError)
    guard case .unexpected = OAuthMapper.map(OAuthError.CallbackUrlInvalid(message: "x")) as? MatrixError else {
        Issue.record("attendu .unexpected"); return
    }
}

@Test func otherErrorsGoThroughTheAuthenticationMapper() {
    #expect(OAuthMapper.map(MatrixError.network(.timeout)) as? MatrixError == .network(.timeout))
}
```

`Tests/MatrixClientKitRustTests/SingleUseGateTests.swift` (Review Focus 4) :

```swift
import Testing
@testable import MatrixClientKitRust

@Test func onlyOneCompletionIsGranted() {
    let gate = SingleUseGate()
    #expect(gate.claimCompletion())
    #expect(!gate.claimCompletion())
}

@Test func completionAfterCancellationIsRefused() {
    let gate = SingleUseGate()
    #expect(gate.claimCancellation())
    #expect(!gate.claimCompletion())
}

@Test func cancellationAfterASuccessfulCompletionIsRefused() {
    // Un `cancel()` tardif ne doit jamais purger le store de la session ouverte.
    let gate = SingleUseGate()
    #expect(gate.claimCompletion())
    gate.completionSucceeded()
    #expect(!gate.claimCancellation())
}

@Test func cancellationDuringCompletionIsRefused() {
    let gate = SingleUseGate()
    #expect(gate.claimCompletion())
    #expect(!gate.claimCancellation())
}

@Test func aFailedCompletionEndsTheFlow() {
    let gate = SingleUseGate()
    #expect(gate.claimCompletion())
    gate.completionFailed()
    #expect(!gate.claimCompletion())
    #expect(!gate.claimCancellation())
}

@Test func cancellingTwiceIsANoOp() {
    let gate = SingleUseGate()
    #expect(gate.claimCancellation())
    #expect(!gate.claimCancellation())
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `swift test --filter "OAuthMapperTests|SingleUseGateTests"`
Expected: échec de compilation.

- [ ] **Step 3: Implémenter le mappage**

`Sources/MatrixClientKitRust/Bridge/OAuthMapper.swift` :

```swift
import Foundation
import MatrixRustSDK
import MatrixClientKitCore

enum OAuthMapper {
    static func configuration(_ configuration: MatrixClientKitCore.OAuthConfiguration) -> MatrixRustSDK.OAuthConfiguration {
        MatrixRustSDK.OAuthConfiguration(
            clientName: configuration.clientName,
            redirectUri: configuration.redirectURI.absoluteString,
            clientUri: configuration.clientURI.absoluteString,
            logoUri: configuration.logoURI?.absoluteString,
            tosUri: configuration.termsOfServiceURI?.absoluteString,
            policyUri: configuration.policyURI?.absoluteString,
            staticRegistrations: Dictionary(
                uniqueKeysWithValues: configuration.staticRegistrations.map { ($0.key.absoluteString, $0.value) }
            )
        )
    }

    /// Spec 0.4, §6. Rend `CancellationError` pour une annulation, `MatrixError` sinon.
    static func map(_ error: any Error) -> any Error {
        guard let error = error as? OAuthError else { return ErrorMapper.mapAuthentication(error) }
        switch error {
        case .NotSupported:
            return MatrixError.authentication(.unsupportedLoginType)
        case .MetadataInvalid:
            return MatrixError.server(.invalidResponse)
        case .Cancelled:
            return CancellationError()
        case let .CallbackUrlInvalid(message):
            return MatrixError.unexpected(message: "The authorization server's callback URL is not valid.", details: message)
        case let .Generic(message):
            return MatrixError.unexpected(message: "OAuth sign-in failed.", details: message)
        }
    }
}
```

- [ ] **Step 4: Implémenter le flux**

`Sources/MatrixClientKitRust/RustOAuthLoginFlow.swift` :

```swift
import Foundation
import Synchronization
import MatrixRustSDK
import MatrixClientKitCore

/// Garantit qu'un flux à usage unique se termine une seule fois, par un `complete` ou un `cancel`.
///
/// Séparé du flux pour être testé sans FFI : c'est lui qui empêche un `cancel()` tardif de purger
/// le store d'une session déjà ouverte (spec 0.4, §4.3).
final class SingleUseGate: Sendable {
    private enum State { case pending, completing, succeeded, ended }
    private let state = Mutex(State.pending)

    func claimCompletion() -> Bool {
        state.withLock { state in
            guard state == .pending else { return false }
            state = .completing
            return true
        }
    }

    func claimCancellation() -> Bool {
        state.withLock { state in
            guard state == .pending else { return false }
            state = .ended
            return true
        }
    }

    func completionSucceeded() { state.withLock { $0 = .succeeded } }
    func completionFailed() { state.withLock { $0 = .ended } }
}

/// Implémentation de ``OAuthLoginFlow`` : la même tentative (même client) de l'URL d'autorisation
/// jusqu'au callback, comme l'exige l'amont (spec 0.4, §2.3).
final class RustOAuthLoginFlow: OAuthLoginFlow {
    let authorizationURL: URL
    private let attempt: LoginAttempt
    private let authorizationData: OAuthAuthorizationData
    private let expectedUserID: UserID?
    private let onSuccess: @Sendable () -> Void
    private let gate = SingleUseGate()

    private init(
        authorizationURL: URL,
        attempt: LoginAttempt,
        authorizationData: OAuthAuthorizationData,
        expectedUserID: UserID?,
        onSuccess: @escaping @Sendable () -> Void
    ) {
        self.authorizationURL = authorizationURL
        self.attempt = attempt
        self.authorizationData = authorizationData
        self.expectedUserID = expectedUserID
        self.onSuccess = onSuccess
    }

    /// - Parameters:
    ///   - deviceID: l'appareil à réutiliser, pour une reconnexion.
    ///   - expectedUserID: l'utilisateur attendu, pour une reconnexion.
    ///   - onSuccess: appelé une fois la nouvelle session construite (la reconnexion y marque
    ///     l'ancienne session remplacée).
    static func begin(
        attempt: LoginAttempt,
        configuration: MatrixClientKitCore.OAuthConfiguration,
        prompt: MatrixClientKitCore.OAuthPrompt?,
        loginHint: String?,
        deviceID: DeviceID?,
        expecting expectedUserID: UserID?,
        onSuccess: @escaping @Sendable () -> Void = {}
    ) async throws -> RustOAuthLoginFlow {
        do {
            let data = try await attempt.client.urlForOauth(
                oauthConfiguration: OAuthMapper.configuration(configuration),
                prompt: prompt.map(LoginDetailsMapper.prompt),
                loginHint: loginHint,
                deviceId: deviceID?.rawValue,
                additionalScopes: nil
            )
            guard let url = URL(string: data.loginUrl()) else {
                throw MatrixError.unexpected(message: "The authorization server returned an invalid URL.", details: data.loginUrl())
            }
            return RustOAuthLoginFlow(
                authorizationURL: url, attempt: attempt, authorizationData: data,
                expectedUserID: expectedUserID, onSuccess: onSuccess
            )
        } catch {
            attempt.fail()
            throw OAuthMapper.map(error)
        }
    }

    func complete(callbackURL: URL) async throws -> any MatrixSession {
        guard gate.claimCompletion() else {
            throw MatrixError.unexpected(message: "This OAuth sign-in has already been completed or cancelled.", details: nil)
        }
        do {
            try await attempt.client.loginWithOauthCallback(callbackUrl: callbackURL.absoluteString)
            let session = try await attempt.succeed(expecting: expectedUserID)
            gate.completionSucceeded()
            onSuccess()
            return session
        } catch {
            gate.completionFailed()
            attempt.fail()
            throw OAuthMapper.map(error)
        }
    }

    func cancel() async {
        guard gate.claimCancellation() else { return }
        await attempt.client.abortOauthAuth(authorizationData: authorizationData)
        attempt.fail()
    }
}
```

Dans `RustMatrixClient` :

```swift
    public func beginOAuthLogin(
        _ configuration: MatrixClientKitCore.OAuthConfiguration,
        prompt: MatrixClientKitCore.OAuthPrompt?,
        loginHint: String?
    ) async throws -> any OAuthLoginFlow {
        let attempt = try await LoginAttempt.begin(restorer: restorer, target: .homeserver(homeserver), reusing: nil)
        return try await RustOAuthLoginFlow.begin(
            attempt: attempt, configuration: configuration, prompt: prompt,
            loginHint: loginHint, deviceID: nil, expecting: nil
        )
    }
```

- [ ] **Step 5: Vérifier**

Run: `swift test --skip MatrixClientKitIntegrationTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests/MatrixClientKitRustTests
git commit -m "feat: connexion OAuth par flux à usage unique

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Connexion par QR code

**Files:**
- Create: `Sources/MatrixClientKitRust/Bridge/QRCodeMapper.swift`
- Create: `Sources/MatrixClientKitRust/RustQRCodeLogin.swift`
- Modify: `Sources/MatrixClientKitRust/RustMatrixClient.swift` (`loginWithQRCode(_:)`, `static loginWithQRCode(scanned:configuration:storage:)`)
- Modify: `Sources/MatrixClientKit/MatrixClientKit.swift` (`Matrix.loginWithQRCode(scanned:configuration:storage:)`)
- Create: `Tests/MatrixClientKitRustTests/QRCodeMapperTests.swift`

**Interfaces:**
- Consumes: `QRCodeLoginState`, `QRCodeLoginEvent`, `QRCodeLoginReducer` (Task 3), `QRCodeLogin` (Task 4), `LoginAttempt`, `ClientTarget` (Task 7), `OAuthMapper.configuration` (Task 9), `StateBroadcaster`.
- Produces:
  - `enum QRCodeMapper { static func event(_ p: QrLoginProgress) -> QRCodeLoginEvent?; static func event(_ p: GeneratedQrLoginProgress) -> QRCodeLoginEvent?; static func failure(_ error: any Error) -> QRCodeLoginFailure; static func target(scanned bytes: Data) -> TargetedQRCode? }`
  - `struct TargetedQRCode: Sendable { let data: QrCodeData; let target: ClientTarget }`
  - `final class RustQRCodeLogin: QRCodeLogin` — `init(restorer: SessionRestorer, configuration: OAuthConfiguration, mode: Mode)`, `enum Mode { case display(ClientTarget); case scanned(Data) }`.
  - `RustMatrixClient.loginWithQRCode(_ configuration: OAuthConfiguration) -> any QRCodeLogin`
  - `RustMatrixClient.loginWithQRCode(scanned: Data, configuration: OAuthConfiguration, storage: MatrixStorage) -> any QRCodeLogin` (statique)
  - `Matrix.loginWithQRCode(scanned: Data, configuration: OAuthConfiguration, storage: MatrixStorage) -> any QRCodeLogin`

Précision par rapport à la spec §7 : les progrès QR arrivent par un listener passé à un appel
`async` (`scan` / `generate`), sans `TaskHandle` : ils alimentent un `StateBroadcaster` via le
réducteur, comme `RustSessionVerification`, et non `ffiStream`.

- [ ] **Step 1: Écrire les tests**

`Tests/MatrixClientKitRustTests/QRCodeMapperTests.swift` :

```swift
import Testing
import Foundation
import MatrixRustSDK
@testable import MatrixClientKitRust
import MatrixClientKitCore

@Test func scannedModeProgressMapsToEvents() {
    #expect(QRCodeMapper.event(QrLoginProgress.establishingSecureChannel(checkCode: 7, checkCodeString: "07"))
        == .secureChannelEstablished(checkCode: "07"))
    #expect(QRCodeMapper.event(QrLoginProgress.waitingForToken(userCode: "AB")) == .waitingForToken(userCode: "AB"))
    #expect(QRCodeMapper.event(QrLoginProgress.syncingSecrets) == .syncingSecrets)
    #expect(QRCodeMapper.event(QrLoginProgress.done) == .done)
}

@Test(arguments: [
    (HumanQrLoginError.Declined, QRCodeLoginFailure.declined),
    (.Expired, .expired),
    (.ConnectionInsecure, .insecureChannel),
    (.LinkingNotSupported, .notSupported),
    (.OAuthMetadataInvalid, .notSupported),
    (.SlidingSyncNotAvailable, .notSupported),
    (.UnsupportedQrCodeType, .notSupported),
    (.NotFound, .notSupported),
    (.OtherDeviceNotSignedIn, .otherDeviceNotSignedIn),
    (.Cancelled, .cancelled),
    (.Unknown, .unknown),
    (.CheckCodeAlreadySent, .unknown),
    (.ContinuationCannotBeSent, .unknown),
])
func qrErrorsFollowTheSpecTable(_ error: HumanQrLoginError, _ expected: QRCodeLoginFailure) {
    #expect(QRCodeMapper.failure(error) == expected)
}

@Test func anyOtherErrorIsUnknown() {
    #expect(QRCodeMapper.failure(MatrixError.network(.offline)) == .unknown)
}

@Test func unreadableBytesHaveNoTarget() {
    #expect(QRCodeMapper.target(scanned: Data([0, 1, 2])) == nil)
}

@Test func theStartingProgressProducesNoEvent() {
    // L'état initial est déjà `.starting`.
    #expect(QRCodeMapper.event(QrLoginProgress.starting) == nil)
}
```

`event(_:)` rend `QRCodeLoginEvent?` : `nil` pour `.starting`. Les `#expect` ci-dessus comparent à
un optionnel, ce qui compile tel quel. `target(scanned:)` rend un `TargetedQRCode?` (struct, et non
un tuple, pour pouvoir le comparer à `nil`).

- [ ] **Step 2: Vérifier l'échec**

Run: `swift test --filter QRCodeMapperTests`
Expected: échec de compilation.

- [ ] **Step 3: Implémenter le mappage**

`Sources/MatrixClientKitRust/Bridge/QRCodeMapper.swift` :

```swift
import Foundation
import MatrixRustSDK
import MatrixClientKitCore

enum QRCodeMapper {
    /// Mode scanné. `nil` pour `.starting`, déjà l'état initial.
    static func event(_ progress: QrLoginProgress) -> QRCodeLoginEvent? {
        switch progress {
        case .starting: nil
        case let .establishingSecureChannel(_, checkCodeString): .secureChannelEstablished(checkCode: checkCodeString)
        case let .waitingForToken(userCode): .waitingForToken(userCode: userCode)
        case .syncingSecrets: .syncingSecrets
        case .done: .done
        }
    }

    /// Mode affiché. L'expéditeur du code de vérification est extrait à part par l'appelant.
    static func event(_ progress: GeneratedQrLoginProgress) -> QRCodeLoginEvent? {
        switch progress {
        case .starting: nil
        case let .qrReady(qrCode): .qrReady(qrCode.toBytes())
        case .qrScanned: .qrScanned
        case let .waitingForToken(userCode): .waitingForToken(userCode: userCode)
        case .syncingSecrets: .syncingSecrets
        case .done: .done
        }
    }

    /// Spec 0.4, §6.
    static func failure(_ error: any Error) -> QRCodeLoginFailure {
        guard let error = error as? HumanQrLoginError else { return .unknown }
        switch error {
        case .Declined: return .declined
        case .Expired: return .expired
        case .ConnectionInsecure: return .insecureChannel
        case .LinkingNotSupported, .OAuthMetadataInvalid, .SlidingSyncNotAvailable, .UnsupportedQrCodeType, .NotFound:
            return .notSupported
        case .OtherDeviceNotSignedIn: return .otherDeviceNotSignedIn
        case .Cancelled: return .cancelled
        case .Unknown, .CheckCodeAlreadySent, .CheckCodeCannotBeSent, .ContinuationAlreadySent, .ContinuationCannotBeSent:
            return .unknown
        }
    }

    /// Décode un QR scanné et en déduit le serveur sur lequel construire le client : l'URL de
    /// base si le QR la porte (MSC4388), sinon son nom de serveur. `nil` si le QR est illisible ou
    /// ne désigne aucun serveur (un QR « à afficher », qui n'est pas destiné à être scanné ici).
    static func target(scanned bytes: Data) -> TargetedQRCode? {
        guard let data = try? QrCodeData.fromBytes(bytes: bytes) else { return nil }
        if let base = data.baseUrl(), let url = URL(string: base) {
            return TargetedQRCode(data: data, target: .homeserver(url))
        }
        if let name = data.serverName() {
            return TargetedQRCode(data: data, target: .serverName(name))
        }
        return nil
    }
}

/// Un QR scanné et le serveur sur lequel construire le client qui le traite.
struct TargetedQRCode: Sendable {
    let data: QrCodeData
    let target: ClientTarget
}
```

- [ ] **Step 4: Implémenter la connexion**

`Sources/MatrixClientKitRust/RustQRCodeLogin.swift` :

```swift
import Foundation
import Synchronization
import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``QRCodeLogin`` (spec 0.4, §4.4).
final class RustQRCodeLogin: QRCodeLogin {
    enum Mode: Sendable {
        /// Ce nouvel appareil affiche le QR.
        case display(ClientTarget)
        /// Ce nouvel appareil a scanné le QR d'un appareil connecté.
        case scanned(Data)
    }

    private let restorer: SessionRestorer
    private let configuration: MatrixClientKitCore.OAuthConfiguration
    private let mode: Mode
    private let broadcaster = StateBroadcaster<QRCodeLoginState>(.starting)
    private let checkCodeSender = Mutex<CheckCodeSender?>(nil)
    private let run = Mutex<Task<RustMatrixSession, any Error>?>(nil)

    init(restorer: SessionRestorer, configuration: MatrixClientKitCore.OAuthConfiguration, mode: Mode) {
        self.restorer = restorer
        self.configuration = configuration
        self.mode = mode
    }

    var state: AsyncStream<QRCodeLoginState> { broadcaster.stream() }

    func start() async throws -> any MatrixSession {
        let task: Task<RustMatrixSession, any Error> = try run.withLock { run in
            guard run == nil else {
                throw MatrixError.unexpected(message: "This QR-code login has already been started.", details: nil)
            }
            let task = Task { try await self.perform() }
            run = task
            return task
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            self.cancel()
        }
    }

    func submitCheckCode(_ code: UInt8) async throws {
        guard QRCodeLoginReducer.canSubmitCheckCode(in: broadcaster.value),
            let sender = checkCodeSender.withLock({ $0 })
        else {
            throw MatrixError.unexpected(message: "No check code is expected now.", details: nil)
        }
        do {
            try await sender.send(code: code)
        } catch {
            throw MatrixError.unexpected(message: "The check code could not be sent.", details: String(describing: error))
        }
    }

    func cancel() {
        apply(.failed(.cancelled))
        run.withLock { $0 }?.cancel()
    }

    private func apply(_ event: QRCodeLoginEvent) {
        broadcaster.update { QRCodeLoginReducer.reduce($0, event) }
    }

    private func perform() async throws -> RustMatrixSession {
        let target: ClientTarget
        let scannedData: QrCodeData?
        switch mode {
        case let .display(displayTarget):
            target = displayTarget
            scannedData = nil
        case let .scanned(bytes):
            guard let scanned = QRCodeMapper.target(scanned: bytes) else {
                apply(.failed(.notSupported))
                throw MatrixError.unexpected(message: "This QR code is not a Matrix sign-in code.", details: nil)
            }
            target = scanned.target
            scannedData = scanned.data
        }

        let attempt: LoginAttempt
        do {
            attempt = try await LoginAttempt.begin(restorer: restorer, target: target, reusing: nil)
        } catch {
            apply(.failed(.unknown))
            throw error
        }

        do {
            let handler = attempt.client.newLoginWithQrCodeHandler(oauthConfiguration: OAuthMapper.configuration(configuration))
            if let scannedData {
                try await handler.scan(qrCodeData: scannedData, progressListener: ScannedListener { [weak self] progress in
                    if let event = QRCodeMapper.event(progress) { self?.apply(event) }
                })
            } else {
                try await handler.generate(progressListener: GeneratedListener { [weak self] progress in
                    if case let .qrScanned(sender) = progress { self?.checkCodeSender.withLock { $0 = sender } }
                    if let event = QRCodeMapper.event(progress) { self?.apply(event) }
                })
            }
            try Task.checkCancellation()
            let session = try await attempt.succeed(expecting: nil)
            apply(.done)
            return session
        } catch {
            attempt.fail()
            if broadcaster.value == .failed(.cancelled) || error is CancellationError {
                apply(.failed(.cancelled))
                throw CancellationError()
            }
            apply(.failed(QRCodeMapper.failure(error)))
            throw MatrixError.unexpected(message: "QR-code login failed.", details: String(describing: error))
        }
    }
}

private final class ScannedListener: QrLoginProgressListener {
    private let handler: @Sendable (QrLoginProgress) -> Void
    init(_ handler: @escaping @Sendable (QrLoginProgress) -> Void) { self.handler = handler }
    func onUpdate(state: QrLoginProgress) { handler(state) }
}

private final class GeneratedListener: GeneratedQrLoginProgressListener {
    private let handler: @Sendable (GeneratedQrLoginProgress) -> Void
    init(_ handler: @escaping @Sendable (GeneratedQrLoginProgress) -> Void) { self.handler = handler }
    func onUpdate(state: GeneratedQrLoginProgress) { handler(state) }
}
```

Si `GeneratedQrLoginProgress` n'est pas `Sendable` dans l'amont (vérifier
`grep -n "extension GeneratedQrLoginProgress: Sendable" .build/checkouts/matrix-rust-components-swift/Sources/MatrixRustSDK/matrix_sdk_ffi.swift`),
extraire dans le listener l'événement et l'expéditeur **avant** de franchir la frontière
`@Sendable` (le listener reçoit la valeur, calcule `(QRCodeLoginEvent?, CheckCodeSender?)` —
`CheckCodeSender` est une classe `@unchecked Sendable` — et passe ce couple au handler).

Dans `RustMatrixClient` :

```swift
    public func loginWithQRCode(_ configuration: MatrixClientKitCore.OAuthConfiguration) -> any QRCodeLogin {
        RustQRCodeLogin(restorer: restorer, configuration: configuration, mode: .display(.homeserver(homeserver)))
    }

    public static func loginWithQRCode(
        scanned: Data,
        configuration: MatrixClientKitCore.OAuthConfiguration,
        storage: MatrixStorage
    ) -> any QRCodeLogin {
        RustQRCodeLogin(restorer: SessionRestorer(storage: storage), configuration: configuration, mode: .scanned(scanned))
    }
```

Dans `enum Matrix` :

```swift
    /// Signs this device in by scanning the QR code shown by a device already signed in to the
    /// account. The code says which homeserver to use.
    ///
    /// To show a QR code on this device instead, use ``MatrixClient/loginWithQRCode(_:)``.
    public static func loginWithQRCode(
        scanned: Data,
        configuration: OAuthConfiguration,
        storage: MatrixStorage
    ) -> any QRCodeLogin {
        RustMatrixClient.loginWithQRCode(scanned: scanned, configuration: configuration, storage: storage)
    }
```

- [ ] **Step 5: Vérifier**

Run: `swift test --skip MatrixClientKitIntegrationTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests/MatrixClientKitRustTests
git commit -m "feat: connexion par QR code, affiché ou scanné

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Reconnexion après soft logout

Forme conditionnée par la Task 1 : si Q2 a échoué et que la spec a été amendée, appliquer le repli
(`reauthenticate` lève `.unexpected` tant que le client de l'ancienne session est vivant —
vérifier par une référence `weak` vers le `Client` après `stopSync`) au lieu de l'étape 5 telle
qu'écrite, et ajouter le test correspondant.

**Files:**
- Modify: `Sources/MatrixClientKitRust/SessionLifecycle.swift`
- Modify: `Sources/MatrixClientKitRust/RustMatrixSession.swift`
- Modify: `Sources/MatrixClientKitCore/Models/AuthState.swift` (doc §4.7)
- Modify: `Tests/MatrixClientKitRustTests/SessionLifecycleTests.swift`

**Interfaces:**
- Consumes: `LoginAttempt` (Task 7), `RustOAuthLoginFlow.begin` (Task 9).
- Produces:
  - `SessionLifecycle.requireSoftLoggedOut() throws`, `SessionLifecycle.stopSyncForReplacement() async`, `SessionLifecycle.markReplaced()`.
  - `RustMatrixSession.reauthenticate(_ credentials: Credentials) async throws -> any MatrixSession`
  - `RustMatrixSession.beginOAuthReauthentication(_ configuration: OAuthConfiguration) async throws -> any OAuthLoginFlow`

- [ ] **Step 1: Écrire les tests**

Dans `Tests/MatrixClientKitRustTests/SessionLifecycleTests.swift` (Review Focus 2), en suivant
la fabrique de `SessionLifecycle` déjà utilisée dans ce fichier (compteurs `stopSync` / `erase`) :

```swift
@Test func reauthenticationRequiresASoftLogout() {
    let lifecycle = SessionLifecycle(stopSync: {}, erase: {})
    #expect(throws: MatrixError.self) { try lifecycle.requireSoftLoggedOut() }
    lifecycle.handleAuthError(isSoftLogout: true)
    #expect(throws: Never.self) { try lifecycle.requireSoftLoggedOut() }
}

@Test func aReplacedSessionEndsSignedOutWithoutErasing() async {
    let erased = Mutex(0)
    let lifecycle = SessionLifecycle(stopSync: {}, erase: { erased.withLock { $0 += 1 } })
    lifecycle.handleAuthError(isSoftLogout: true)

    lifecycle.markReplaced()

    #expect(lifecycle.current == .signedOut)
    #expect(erased.withLock { $0 } == 0)
}

@Test func logoutOnAReplacedSessionErasesNothingAndCallsNoServer() async throws {
    let erased = Mutex(0)
    let serverCalls = Mutex(0)
    let lifecycle = SessionLifecycle(stopSync: {}, erase: { erased.withLock { $0 += 1 } })
    lifecycle.handleAuthError(isSoftLogout: true)
    lifecycle.markReplaced()

    try await lifecycle.logout { serverCalls.withLock { $0 += 1 } }

    #expect(erased.withLock { $0 } == 0)
    #expect(serverCalls.withLock { $0 } == 0)
}

@Test func aLateHardLogoutOnAReplacedSessionErasesNothing() async {
    let erased = Mutex(0)
    let lifecycle = SessionLifecycle(stopSync: {}, erase: { erased.withLock { $0 += 1 } })
    lifecycle.handleAuthError(isSoftLogout: true)
    lifecycle.markReplaced()

    await lifecycle.handleAuthError(isSoftLogout: false)?.value

    #expect(erased.withLock { $0 } == 0)
    #expect(lifecycle.current == .signedOut)
}
```

(Importer `Synchronization` en tête du fichier si ce n'est pas déjà fait.)

- [ ] **Step 2: Vérifier l'échec**

Run: `swift test --filter SessionLifecycleTests`
Expected: échec de compilation.

- [ ] **Step 3: Implémenter dans `SessionLifecycle`**

Ajouter la propriété `private let isReplaced = Mutex(false)` et :

```swift
    /// Garde de ``RustMatrixSession/reauthenticate(_:)`` : seule une session en soft logout se
    /// reconnecte sur le même appareil.
    func requireSoftLoggedOut() throws {
        guard current == .softLoggedOut, !isReplaced.withLock({ $0 }) else {
            throw MatrixError.unexpected(
                message: "Only a session the homeserver soft-logged out can sign in again.",
                details: "\(current)"
            )
        }
    }

    /// Arrête la sync avant de céder le store à une reconnexion.
    func stopSyncForReplacement() async {
        await stopSync()
    }

    /// La session a été remplacée par une reconnexion (spec 0.4, §5.5) : son store appartient
    /// désormais à la remplaçante. Plus rien ne l'efface — ni `logout()`, ni un hard logout
    /// tardif —, et elle publie `.signedOut`.
    func markReplaced() {
        isReplaced.withLock { $0 = true }
        broadcaster.update { _ in .signedOut }
    }
```

Puis :
- en tête de `handleAuthError(isSoftLogout:)` : `if isReplaced.withLock({ $0 }) { return nil }` ;
- en tête de `logout(server:)` : `if isReplaced.withLock({ $0 }) { return }`.

- [ ] **Step 4: Vérifier**

Run: `swift test --filter SessionLifecycleTests`
Expected: PASS.

- [ ] **Step 5: Implémenter dans `RustMatrixSession`**

```swift
    /// Se reconnecte sur le même appareil après un soft logout (spec 0.4, §4.6, §5.5).
    ///
    /// L'amont pose une session une seule fois par client : la reconnexion construit un client
    /// neuf sur le même store, avec le même appareil, et rend une nouvelle session. En cas
    /// d'échec, celle-ci reste en `.softLoggedOut`, intacte.
    public func reauthenticate(_ credentials: Credentials) async throws -> any MatrixClientKitCore.MatrixSession {
        try lifecycle.requireSoftLoggedOut()
        await lifecycle.stopSyncForReplacement()
        let attempt = try await LoginAttempt.begin(restorer: restorer, target: .homeserver(homeserverURL), reusing: segment)
        do {
            try await attempt.authenticate(credentials, deviceID: deviceID)
            let session = try await attempt.succeed(expecting: userID)
            lifecycle.markReplaced()
            return session
        } catch {
            attempt.fail()
            throw ErrorMapper.mapAuthentication(error)
        }
    }

    public func beginOAuthReauthentication(
        _ configuration: MatrixClientKitCore.OAuthConfiguration
    ) async throws -> any OAuthLoginFlow {
        try lifecycle.requireSoftLoggedOut()
        await lifecycle.stopSyncForReplacement()
        let attempt = try await LoginAttempt.begin(restorer: restorer, target: .homeserver(homeserverURL), reusing: segment)
        let lifecycle = lifecycle
        return try await RustOAuthLoginFlow.begin(
            attempt: attempt, configuration: configuration, prompt: nil, loginHint: userID.rawValue,
            deviceID: deviceID, expecting: userID, onSuccess: { lifecycle.markReplaced() }
        )
    }
```

`AuthState.swift` : remplacer la doc de `.softLoggedOut` et `.signedOut` par celle de la spec §4.7
(texte anglais exact donné dans la spec).

- [ ] **Step 6: Vérifier et commiter**

Run: `swift test --skip MatrixClientKitIntegrationTests`
Expected: PASS.

```bash
git add Sources Tests/MatrixClientKitRustTests
git commit -m "feat: reconnexion sur le même appareil après soft logout

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Exiger les nouveaux membres dans `MatrixClient` et `MatrixSession`

**Files:**
- Modify: `Sources/MatrixClientKitCore/Services/MatrixClient.swift`
- Modify: `Sources/MatrixClientKitCore/Services/MatrixSession.swift`
- Modify: `Sources/MatrixClientKitMocks/MockMatrixClient.swift`
- Modify: `Sources/MatrixClientKitMocks/MockMatrixSession.swift`
- Modify: `Tests/MatrixClientKitCoreTests/AuthenticationMockTests.swift`

**Interfaces:**
- Consumes: tout ce qui précède.
- Produces (publics) :
  - `MatrixClient.loginDetails()`, `beginOAuthLogin(_:prompt:loginHint:)`, extension `beginOAuthLogin(_:)`, `loginWithQRCode(_:)`.
  - `MatrixSession.reauthenticate(_:)`, `beginOAuthReauthentication(_:)`.
  - `MockMatrixClient.loginDetailsResult: Result<LoginDetails, MatrixError>`, `oauthFlow: MockOAuthLoginFlow`, `oauthLoginError: MatrixError?`, `oauthRequests: [OAuthRequest]` (`struct OAuthRequest: Sendable, Hashable { configuration, prompt, loginHint }`), `qrCodeLogin: MockQRCodeLogin`.
  - `MockMatrixSession.reauthenticateResult: Result<MockMatrixSession, MatrixError>` (défaut : `.failure(.unexpected(message: "Not soft-logged out", details: nil))`), `reauthenticationAttempts: [Credentials]`, `oauthReauthenticationFlow: MockOAuthLoginFlow`.

- [ ] **Step 1: Écrire les tests**

Ajouter à `AuthenticationMockTests.swift` :

```swift
@Test func mockClientReturnsTheConfiguredLoginDetails() async throws {
    let client = MockMatrixClient()
    client.loginDetailsResult = .success(SampleData.loginDetails(supportsOAuth: true, oauthPrompts: [.create]))
    let details = try await client.loginDetails()
    #expect(details.supportsOAuth)
    #expect(details.oauthPrompts == [.create])
}

@Test func mockClientRecordsOAuthRequestsAndReturnsItsFlow() async throws {
    let client = MockMatrixClient()
    let flow = try await client.beginOAuthLogin(SampleData.oauthConfiguration(), prompt: .create, loginHint: "alice")
    #expect(flow.authorizationURL == client.oauthFlow.authorizationURL)
    #expect(client.oauthRequests == [.init(configuration: SampleData.oauthConfiguration(), prompt: .create, loginHint: "alice")])
}

@Test func mockClientOAuthCanFail() async {
    let client = MockMatrixClient()
    client.oauthLoginError = .authentication(.unsupportedLoginType)
    await #expect(throws: MatrixError.authentication(.unsupportedLoginType)) {
        _ = try await client.beginOAuthLogin(SampleData.oauthConfiguration())
    }
}

@Test func mockClientHandsOutItsQRCodeLogin() {
    let client = MockMatrixClient()
    let login = client.loginWithQRCode(SampleData.oauthConfiguration())
    #expect((login as? MockQRCodeLogin) === client.qrCodeLogin)
}

@Test func mockSessionReauthenticationIsConfigurableAndRecorded() async throws {
    let session = MockMatrixSession()
    session.reauthenticateResult = .success(MockMatrixSession(deviceID: "DEV1"))
    let renewed = try await session.reauthenticate(.password(username: "alice", password: "p", deviceName: nil))
    #expect(renewed.deviceID.rawValue == "DEV1")
    #expect(session.reauthenticationAttempts.count == 1)
}

@Test func mockSessionRefusesReauthenticationByDefault() async {
    let session = MockMatrixSession()
    await #expect(throws: MatrixError.self) {
        _ = try await session.reauthenticate(.password(username: "a", password: "p", deviceName: nil))
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `swift test --filter AuthenticationMockTests`
Expected: échec de compilation.

- [ ] **Step 3: Étendre les protocoles**

`MatrixClient` — ajouter, avec leur doc anglaise :

```swift
    /// What the homeserver accepts for signing in. Needs no session; call it to decide which
    /// sign-in options to show.
    func loginDetails() async throws -> LoginDetails

    /// Starts signing in through the homeserver's OAuth authorization server.
    ///
    /// - Parameters:
    ///   - prompt: ``OAuthPrompt/create`` to offer account creation — only when
    ///     ``LoginDetails/oauthPrompts`` contains it.
    ///   - loginHint: a user ID to prefill, for instance `@alice:matrix.org`.
    /// - Throws: ``MatrixError/authentication(_:)`` with ``MatrixError/Authentication/unsupportedLoginType``
    ///   when the homeserver does not support OAuth.
    func beginOAuthLogin(
        _ configuration: OAuthConfiguration,
        prompt: OAuthPrompt?,
        loginHint: String?
    ) async throws -> any OAuthLoginFlow

    /// Signs this device in by showing a QR code that a device already signed in to the account
    /// scans. To scan a code instead, use `Matrix.loginWithQRCode(scanned:configuration:storage:)`.
    func loginWithQRCode(_ configuration: OAuthConfiguration) -> any QRCodeLogin
```

et après le protocole :

```swift
extension MatrixClient {
    /// Starts signing in through OAuth, without a prompt or a login hint.
    public func beginOAuthLogin(_ configuration: OAuthConfiguration) async throws -> any OAuthLoginFlow {
        try await beginOAuthLogin(configuration, prompt: nil, loginHint: nil)
    }
}
```

`MatrixSession` — ajouter :

```swift
    /// Signs in again on the same device after ``AuthState/softLoggedOut``, keeping its
    /// encryption keys, and returns the new session.
    ///
    /// This session is then over: it reports ``AuthState/signedOut`` and its data belongs to the
    /// new session — release it. If signing in fails, this session stays
    /// ``AuthState/softLoggedOut``, untouched: the user can try again.
    ///
    /// - Throws: ``MatrixError/unexpected(message:details:)`` when the session is not soft-logged
    ///   out; ``MatrixError/authentication(_:)`` when the credentials are refused or belong to
    ///   another account.
    func reauthenticate(_ credentials: Credentials) async throws -> any MatrixSession

    /// Like ``reauthenticate(_:)``, through OAuth: the flow's ``OAuthLoginFlow/complete(callbackURL:)``
    /// returns the new session.
    func beginOAuthReauthentication(_ configuration: OAuthConfiguration) async throws -> any OAuthLoginFlow
```

Mettre à jour la doc de `Credentials` et de `MatrixClient` : retirer toute mention « OAuth arrives
in v0.4 ».

- [ ] **Step 4: Étendre les doubles**

`MockMatrixClient` — sur le modèle existant (verrou `lock`, stockage `_x`, accesseurs) :

```swift
    /// What ``loginDetails()`` returns or throws. Password-only by default.
    public var loginDetailsResult: Result<LoginDetails, MatrixError>   // défaut .success(SampleData.loginDetails(homeserver: homeserver))
    /// The flow ``beginOAuthLogin(_:prompt:loginHint:)`` returns.
    public let oauthFlow: MockOAuthLoginFlow                            // MockOAuthLoginFlow()
    /// The error ``beginOAuthLogin(_:prompt:loginHint:)`` throws instead of returning ``oauthFlow``.
    public var oauthLoginError: MatrixError?
    /// Every call to ``beginOAuthLogin(_:prompt:loginHint:)``, in order.
    public var oauthRequests: [OAuthRequest]
    /// The login ``loginWithQRCode(_:)`` returns.
    public let qrCodeLogin: MockQRCodeLogin                             // MockQRCodeLogin()

    /// A recorded call to ``beginOAuthLogin(_:prompt:loginHint:)``.
    public struct OAuthRequest: Sendable, Hashable {
        public let configuration: OAuthConfiguration
        public let prompt: OAuthPrompt?
        public let loginHint: String?
    }
```

avec `loginDetails()` → `try loginDetailsResult.get()`, `beginOAuthLogin` qui enregistre la
requête puis lève `oauthLoginError` s'il existe ou rend `oauthFlow`, `loginWithQRCode` →
`qrCodeLogin`. `OAuthRequest` doit avoir un `init` public pour que les tests construisent la
valeur attendue (`.init(configuration:prompt:loginHint:)`).

`MockMatrixSession` — mêmes conventions :

```swift
    /// What ``reauthenticate(_:)`` returns or throws. Fails by default, like a session that is not
    /// soft-logged out.
    public var reauthenticateResult: Result<MockMatrixSession, MatrixError>
    /// Every credential passed to ``reauthenticate(_:)``.
    public var reauthenticationAttempts: [Credentials]
    /// The flow ``beginOAuthReauthentication(_:)`` returns.
    public let oauthReauthenticationFlow: MockOAuthLoginFlow
```

Les deux nouveaux doubles de Task 4 et ces membres sont décrits dans la doc de type de
`MockMatrixClient` / `MockMatrixSession` (une phrase chacun).

- [ ] **Step 5: Rendre `RustMatrixClient` et `RustMatrixSession` conformes**

Leurs méthodes existent déjà (Tasks 8–11) : seule la conformité est vérifiée par le compilateur.
`grep -n "func loginDetails\|func beginOAuthLogin\|func loginWithQRCode\|func reauthenticate\|func beginOAuthReauthentication" Sources/MatrixClientKitRust/*.swift`
doit lister les cinq.

- [ ] **Step 6: Vérifier et commiter**

Run: `swift test --skip MatrixClientKitIntegrationTests && swift format lint --recursive --strict Sources Tests`
Expected: PASS, aucun avertissement de lint.

```bash
git add Sources Tests/MatrixClientKitCoreTests
git commit -m "feat!: MatrixClient et MatrixSession exigent l'authentification 0.4

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Harnais Synapse + MAS

**Files:**
- Modify: `Tests/IntegrationHarness/docker-compose.yml`
- Create: `Tests/IntegrationHarness/synapse-oauth/homeserver.yaml`
- Create: `Tests/IntegrationHarness/mas/config.yaml`
- Modify: `Scripts/integration-harness.sh`
- Modify: `Tests/IntegrationHarness/README.md`

**Interfaces:**
- Produces: variables `MCK_HARNESS_OAUTH_HOMESERVER` (`http://localhost:8010`),
  `MCK_HARNESS_MAS` (`http://localhost:8080`), `MCK_HARNESS_OAUTH_USER`,
  `MCK_HARNESS_OAUTH_PASSWORD`.

- [ ] **Step 1: Épingler les images**

Run: `docker pull ghcr.io/element-hq/matrix-authentication-service:latest && docker image inspect ghcr.io/element-hq/matrix-authentication-service:latest --format '{{index .Config.Labels "org.opencontainers.image.version"}}'`
Noter la version et l'utiliser telle quelle. Postgres : `postgres:16-alpine`.

Consulter la documentation de cette version de MAS (context7 :
`resolve-library-id "matrix-authentication-service"` puis `query-docs` sur « Synapse
integration », « device code grant », « local password ») et celle de Synapse (section
`matrix_authentication_service`, et `experimental_features.msc4108_enabled`) avant d'écrire les
configs : les clés ci-dessous sont celles attendues, à corriger selon la doc de la version épinglée.

- [ ] **Step 2: Générer la config MAS**

Run: `docker run --rm ghcr.io/element-hq/matrix-authentication-service:<version> config generate > Tests/IntegrationHarness/mas/config.yaml`

Puis éditer `config.yaml` (tout le contenu généré est un secret de **test**, le dire en commentaire
d'en-tête) :

```yaml
http:
  public_base: "http://localhost:8080/"
  listeners:
    - name: web
      resources: [{ name: discovery }, { name: human }, { name: oauth }, { name: compat }, { name: graphql }, { name: assets }]
      binds: [{ address: "[::]:8080" }]
database:
  uri: "postgresql://mas:mas@postgres/mas"
matrix:
  kind: synapse
  homeserver: "localhost"
  endpoint: "http://synapse-oauth:8008/"
  secret: "mck-harness-mas-synapse-secret"
passwords:
  enabled: true
  schemes: [{ version: 1, algorithm: argon2id }]
account:
  password_registration_enabled: false
# Le harnais se connecte en boucle depuis la même adresse.
rate_limiting:
  login: { per_ip: { burst: 1000, per_second: 1000 }, per_account: { burst: 1000, per_second: 1000 } }
```

(garder les sections `secrets` et `clients` générées.)

- [ ] **Step 3: Config Synapse délégué**

`Tests/IntegrationHarness/synapse-oauth/homeserver.yaml` : copie de `synapse-password` avec
`public_baseurl: "http://localhost:8010/"`, base Postgres (`name: psycopg2`, `user: synapse`,
`password: synapse`, `database: synapse`, `host: postgres`), et :

```yaml
matrix_authentication_service:
  enabled: true
  endpoint: "http://mas:8080/"
  secret: "mck-harness-mas-synapse-secret"
experimental_features:
  msc4108_enabled: true   # rendez-vous de la connexion par QR
```

Retirer `registration_shared_secret` (les comptes sont créés dans MAS).

- [ ] **Step 4: Services**

Ajouter au compose :

```yaml
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: postgres
    volumes:
      - ./postgres-init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres"]
      interval: 2s
      retries: 60

  mas:
    image: ghcr.io/element-hq/matrix-authentication-service:<version>
    command: ["server", "--config", "/config/config.yaml"]
    ports: ["8080:8080"]
    volumes: ["./mas:/config:ro"]
    depends_on: { postgres: { condition: service_healthy } }

  synapse-oauth:
    image: ghcr.io/element-hq/synapse:vX.Y.Z
    ports: ["8010:8008"]
    volumes: ["./synapse-oauth:/config:ro", "synapse-oauth-data:/data"]
    environment: { SYNAPSE_CONFIG_PATH: /config/homeserver.yaml }
    depends_on: { postgres: { condition: service_healthy }, mas: { condition: service_started } }
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:8008/health"]
      interval: 2s
      retries: 60
```

(+ volume `synapse-oauth-data`, et la même commande de génération de clé que les autres Synapse.)
`Tests/IntegrationHarness/postgres-init.sql` :

```sql
CREATE USER synapse PASSWORD 'synapse';
CREATE DATABASE synapse OWNER synapse ENCODING 'UTF8' LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0;
CREATE USER mas PASSWORD 'mas';
CREATE DATABASE mas OWNER mas;
```

Note : depuis la machine hôte, MAS est joint en `http://localhost:8080`, depuis Synapse en
`http://mas:8080`. Le `public_base` de MAS (`localhost:8080`) est ce que voit le SDK : il doit
rester joignable depuis l'hôte.

- [ ] **Step 5: Script**

Dans `up`, après les comptes Synapse :

```bash
    OAUTH_USER="mck-oauth-user"
    OAUTH_PASSWORD="mck-oauth-password"
    "${COMPOSE[@]}" exec -T mas mas-cli manage register-user --config /config/config.yaml \
      --yes --ignore-password-complexity -p "$OAUTH_PASSWORD" "$OAUTH_USER" >/dev/null 2>&1 || true
```

(vérifier les options exactes avec `mas-cli manage register-user --help` de la version épinglée),
et dans `env` : `MCK_HARNESS_OAUTH_HOMESERVER=http://localhost:8010`,
`MCK_HARNESS_MAS=http://localhost:8080`, `MCK_HARNESS_OAUTH_USER`, `MCK_HARNESS_OAUTH_PASSWORD`.

- [ ] **Step 6: Vérifier**

Run: `Scripts/integration-harness.sh down; Scripts/integration-harness.sh up && curl -s http://localhost:8010/_matrix/client/v1/auth_metadata | head -c 300`
Expected: un JSON contenant `"issuer":"http://localhost:8080/"` et `"device_authorization_endpoint"`.

Run: `curl -s http://localhost:8010/_matrix/client/unstable/org.matrix.msc4108/rendezvous -X POST -o /dev/null -w '%{http_code}\n'`
Expected: autre chose que `404` (le rendez-vous MSC4108 est servi). Si `404`, chercher dans la doc
Synapse épinglée le nom actuel de l'option et corriger.

- [ ] **Step 7: Commit**

```bash
git add Tests/IntegrationHarness Scripts/integration-harness.sh
git commit -m "test: Synapse délégué à MAS dans le harnais, avec rendez-vous MSC4108

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Intégration — mot de passe, e-mail, découverte, reconnexion, store 0.3

**Files:**
- Create: `Tests/MatrixClientKitIntegrationTests/HarnessSupport.swift`
- Create: `Tests/MatrixClientKitIntegrationTests/AuthenticationHarnessTests.swift`
- Modify: `Tests/MatrixClientKitIntegrationTests/LoginAndSyncTests.swift` (découverte sur Tuwunel)
- Modify: `Tests/IntegrationLegacySeeder/main.swift` (mise en page 0.3)
- Modify: `Sources/MatrixClientKitRust/SessionRestorer.swift` (couture `downgradeToLegacyLayout()`)
- Modify: `Tests/MatrixClientKitIntegrationTests/EncryptionAndSessionTests.swift` ou le fichier qui contient le cas du seeder (assertion de chemin legacy)

**Interfaces:**
- Consumes: variables des Tasks 1 et 13 ; API publique 0.4.
- Produces:
  - `struct HarnessConfiguration { static var current: HarnessConfiguration?; passwordHomeserver, expiringHomeserver, oauthHomeserver: URL?; mas: URL?; user, password, email: String; oauthUser, oauthPassword: String? }`
  - `@Suite(.enabled(if: HarnessConfiguration.isAvailable), .serialized) struct HarnessTests {}`
  - `SessionRestorer.downgradeToLegacyLayout() throws` (portée `package`, couture de test).

- [ ] **Step 1: Support**

`HarnessSupport.swift` : lire les variables de la Task 1 (et de la 13, optionnelles) sur le modèle
de `IntegrationConfiguration` ; suite parente `HarnessTests` sérialisée — même raison que
`IntegrationTests` (une seule entrée Keychain de session par processus). Elle doit aussi être
sérialisée **avec** `IntegrationTests` : les placer sous un parent commun n'est pas possible sans
toucher l'existant ; documenter dans le README du harnais de lancer les deux suites séparément
(`--filter HarnessTests` puis `--filter IntegrationTests`).

- [ ] **Step 2: Écrire les cas**

`AuthenticationHarnessTests.swift`, en `extension HarnessTests`, chaque cas `.timeLimit(.minutes(2))`,
répertoire temporaire supprimé par `removeDirectory`, déconnexion par `cleaningUp` :

1. `passwordLoginOpensAStoreNamedByItsStoreID` — `Matrix.client(homeserver: passwordHomeserver, storage: .local(directory:))`,
   `login(.password(...))`, sync `running` ; sous `<dir>/MatrixClientKit/` un seul répertoire,
   dont le nom contient un `-` (UUID).
2. `emailLoginSucceeds` — `login(.email(address: email, password:, deviceName:))` → `userID` se
   termine par `:localhost`.
3. `loginDetailsOnAPasswordServer` — `client.loginDetails()` : `supportsPassword == true`,
   `supportsOAuth == false`.
4. `discoveryAcceptsAnURLString` — `Matrix.client(server: "http://localhost:8008", storage:)`,
   `homeserver.absoluteString` commence par `http://localhost:8008`.
5. `aFailedLoginLeavesNoStore` — mauvais mot de passe → `.authentication(.invalidCredentials)` ;
   `<dir>/MatrixClientKit/` vide ou absent.
6. `reauthenticationAfterSoftLogoutKeepsTheDeviceAndItsKeys` — sur `expiringHomeserver` :
   connexion, sync, envoi d'un message chiffré dans un salon créé pour l'occasion (créer le salon
   chiffré par l'API client HTTP brute avec le jeton admin du serveur expirant, inviter
   l'utilisateur, le faire rejoindre via `session.rooms`) ; attendre `authState == .softLoggedOut`
   (borne : 60 s, la durée de vie configurée en Task 1 + marge) ; `reauthenticate(.password(...))` ;
   vérifier `new.deviceID == old.deviceID`, ancienne session `.signedOut`, la timeline de la
   nouvelle session rend le message en clair (pas d'élément indéchiffrable), et un seul
   répertoire de store sous la racine.

   Si la création du salon chiffré s'avère trop lourde, réduire le cas à : même `deviceID`, même
   répertoire de store, `encryption.verificationStatus` inchangé — et le signaler dans le
   CHANGELOG *Verified*.
7. `reauthenticationIsRefusedOutsideSoftLogout` — session fraîche, `reauthenticate` →
   `.unexpected`.

Code type du cas 1, à reproduire pour les autres :

```swift
import Testing
import Foundation
import MatrixClientKit

extension HarnessTests {
    @Suite
    struct AuthenticationHarnessTests {
        @Test(.timeLimit(.minutes(2)))
        func passwordLoginOpensAStoreNamedByItsStoreID() async throws {
            let configuration = try #require(HarnessConfiguration.current)
            let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "mck-harness-\(UUID())")
            defer { removeDirectory(directory) }

            let client = Matrix.client(homeserver: configuration.passwordHomeserver, storage: .local(directory: directory))
            let session = try await client.login(.password(
                username: configuration.user, password: configuration.password, deviceName: "Harness"
            ))
            let states = session.sync.state
            await session.sync.start()
            try #require(await waitUntilRunning(states) == .running)

            let stores = try FileManager.default.contentsOfDirectory(atPath: directory.appending(path: "MatrixClientKit").path)
            #expect(stores.count == 1)
            #expect(stores.first?.contains("-") == true)

            await cleaningUp {
                await session.sync.stop()
                try? await session.logout()
            }
        }
    }
}
```

- [ ] **Step 3: Découverte réelle sur Tuwunel**

Dans `LoginAndSyncTests`, ajouter :

```swift
        @Test(.timeLimit(.minutes(1)))
        func discoveryResolvesTheServerName() async throws {
            let configuration = try #require(IntegrationConfiguration.current)
            let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "mck-integration-\(UUID())")
            defer { removeDirectory(directory) }
            let serverName = try #require(configuration.homeserver.host())

            let client = try await Matrix.client(server: serverName, storage: .local(directory: directory))
            let details = try await client.loginDetails()

            #expect(client.homeserver.host() == configuration.homeserver.host())
            #expect(details.supportsPassword)
        }
```

- [ ] **Step 4: Seeder en mise en page 0.3**

Dans `SessionRestorer`, ajouter :

```swift
    /// Couture de test, pour l'exécutable `IntegrationLegacySeeder` uniquement : rend à la session
    /// persistée la mise en page d'un store 0.1–0.3 — répertoire et entrée Keychain sous
    /// l'empreinte du user ID, aucun `storeID` persisté. Le renommage garde les descripteurs SQLite
    /// ouverts valides (même volume) ; le seeder se termine juste après.
    package func downgradeToLegacyLayout() throws {
        guard let data = try persistence.load(), let storeID = data.storeID else { return }
        let modern = makeLocalStore(for: .session(storeID))
        let legacy = makeLocalStore(for: .legacy(data.userID))
        try FileManager.default.moveItem(at: modern.paths().storeDirectory, to: legacy.paths().storeDirectory)
        if let key = try secureStore.data(forKey: "\(LocalStore.keyPrefix).\(storeID)") {
            try secureStore.set(key, forKey: "\(LocalStore.keyPrefix).\(StoreSegment.legacy(data.userID).directoryName)")
            try secureStore.removeValue(forKey: "\(LocalStore.keyPrefix).\(storeID)")
        }
        try persistence.save(MatrixSessionData(
            userID: data.userID, deviceID: data.deviceID, homeserverURL: data.homeserverURL,
            accessToken: data.accessToken, refreshToken: data.refreshToken, oauthData: data.oauthData,
            slidingSyncVersion: data.slidingSyncVersion, storeID: nil
        ))
    }
```

Dans `Tests/IntegrationLegacySeeder/main.swift`, garder une référence au `SessionRestorer` passé à
`RustMatrixClient(homeserver:restorer:)` et, après que la sync a atteint `running` et **avant**
`Report.prepare`, appeler `try restorer.downgradeToLegacyLayout()` (échec → `finish(1, …)`).
`Report.prepare` reçoit alors `secrets.snapshot`, qui contient la clé sous son nom legacy.

Dans le cas d'intégration existant qui restaure le store du seeder, ajouter l'assertion que le
répertoire restauré est bien sous l'empreinte legacy (nom sans `-`) et qu'aucun autre store
n'apparaît après la restauration.

- [ ] **Step 5: Lancer**

Run: `Scripts/integration-harness.sh up && eval "$(Scripts/integration-harness.sh env)" && swift test --filter HarnessTests`
Expected: PASS.
Run (mots de passe Tuwunel demandés à l'utilisateur) : `./Scripts/check-integration-env.sh && swift test --filter MatrixClientKitIntegrationTests.IntegrationTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/MatrixClientKitRust/SessionRestorer.swift Tests
git commit -m "test: intégration de la connexion, de la reconnexion et des stores 0.3

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: Intégration — OAuth et QR contre MAS

**Files:**
- Create: `Tests/MatrixClientKitIntegrationTests/MASDriver.swift`
- Create: `Tests/MatrixClientKitIntegrationTests/OAuthHarnessTests.swift`
- Modify: `Sources/MatrixClientKitRust/RustMatrixSession.swift` (accès `package` au `Client` pour le côté « appareil qui accorde » du test QR)

**Interfaces:**
- Consumes: `HarnessConfiguration` (Task 14), variables de la Task 13.
- Produces:
  - `struct MASDriver { init(mas: URL); func authorize(_ url: URL, username: String, password: String, redirectScheme: String) async throws -> URL; func approveDevice(verificationURI: URL, username: String, password: String) async throws }`
  - `RustMatrixSession.underlyingClient: Client` (`package`).

- [ ] **Step 1: Pilote MAS**

`MASDriver.swift` : un `URLSession` éphémère avec `HTTPCookieStorage` propre et un delegate qui
**refuse** les redirections vers `redirectScheme` en capturant leur `Location`. `authorize` :

1. `GET url` (suivre les redirections http) jusqu'au formulaire de connexion MAS ;
2. extraire le jeton CSRF du HTML (`name="csrf" value="…"`), `POST` du formulaire
   (`csrf`, `username`, `password`) à l'`action` du formulaire ;
3. si une page de consentement apparaît (formulaire avec `csrf` et action contenant `consent`),
   la soumettre ;
4. rendre l'URL capturée vers `redirectScheme`.

`approveDevice` : se connecter de la même façon, ouvrir `verificationURI`, soumettre le formulaire
d'approbation du code d'appareil.

Ouvrir dans un navigateur la page de connexion MAS de la version épinglée
(`http://localhost:8080/login`) pour relever les noms exacts des champs avant d'écrire les
extractions ; les isoler dans des constantes en tête de fichier.

- [ ] **Step 2: Cas OAuth**

`OAuthHarnessTests.swift`, en `extension HarnessTests`, `.enabled(if: HarnessConfiguration.current?.mas != nil)` :

1. `loginDetailsAdvertiseOAuth` — `supportsOAuth == true`, `supportsPassword == false`.
2. `oauthLoginOpensASession` — `beginOAuthLogin(configuration)` avec
   `redirectURI: com.matrixclientkit.harness:/callback`, `clientURI: https://example.com` ;
   `MASDriver.authorize(flow.authorizationURL, …, redirectScheme: "com.matrixclientkit.harness")` ;
   `flow.complete(callbackURL:)` → session, sync `running`, `userID` se termine par `:localhost`.
3. `aSecondCompleteIsRefused` — après le cas 2, rappeler `complete` → `.unexpected`.
4. `cancellingLeavesNoStore` — `beginOAuthLogin`, `cancel()`, la racine `MatrixClientKit/` ne
   contient aucun répertoire.
5. `anOAuthSessionIsRestoredAfterRelaunch` — après le cas 2, `sync.stop()`, relâcher la session,
   `Matrix.restoreSession(storage:)` → non `nil`, même `deviceID`.

- [ ] **Step 3: Cas QR**

Ajouter à `RustMatrixSession` :

```swift
    /// Couture de test : le client amont, pour jouer l'« appareil qui accorde » dans la suite
    /// d'intégration de la connexion par QR. Portée `package`, jamais publique.
    package var underlyingClient: Client { client }
```

Deux cas, chacun avec un appareil existant ouvert par OAuth (cas 2 ci-dessus, factorisé dans une
fonction `signInWithOAuth`) puis converti en `RustMatrixSession` (`as! RustMatrixSession`) :

1. `qrLoginWhereThisDeviceDisplaysTheCode` — `client.loginWithQRCode(configuration)`, `start()`
   dans une tâche ; attendre `.displayQRCode(bytes)` ; côté existant :
   `underlyingClient.newGrantLoginWithQrCodeHandler().scan(qrCodeData: QrCodeData.fromBytes(bytes:), progressListener:)` ;
   quand l'existant reçoit `establishingSecureChannel(checkCode:)`, le nouveau est en
   `.enterCheckCode` → `submitCheckCode(checkCode)` ; quand l'existant reçoit
   `waitingForAuth(verificationUri:continuationSender:)`, appeler
   `MASDriver.approveDevice(verificationURI:)` puis le `continuationSender` (lire sa signature dans
   le fichier généré) ; attendre la session ; vérifier `encryption.verificationStatus` atteint
   `.verified` (secrets reçus).
2. `qrLoginWhereThisDeviceScansTheCode` — côté existant `generate(progressListener:)` ; sur
   `qrReady(qrCode)`, `Matrix.loginWithQRCode(scanned: qrCode.toBytes(), configuration:, storage:)` ;
   sur `.displayCheckCode(code)` côté nouveau et `qrScanned(checkCodeSender)` côté existant,
   `checkCodeSender.send(code: UInt8(code)!)` ; puis même approbation et mêmes vérifications.

- [ ] **Step 4: Lancer, et repli éventuel**

Run: `eval "$(Scripts/integration-harness.sh env)" && swift test --filter OAuthHarnessTests`
Expected: PASS.

Si les cas QR ne peuvent pas être rendus fiables (rendez-vous MSC4108 indisponible dans la version
épinglée, approbation MAS non automatisable) après une investigation bornée (lire les logs
`docker compose logs synapse-oauth mas`) : les marquer `.disabled("…raison précise…")`, garder
les cas OAuth, et noter le repli pour le CHANGELOG (spec §8.2). Ne **pas** affaiblir les
assertions pour les faire passer.

- [ ] **Step 5: Commit**

```bash
git add Sources/MatrixClientKitRust/RustMatrixSession.swift Tests/MatrixClientKitIntegrationTests
git commit -m "test: intégration OAuth et connexion par QR contre MAS

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 16: Documentation et version 0.4.0

**Files:**
- Create: `Sources/MatrixClientKit/Documentation.docc/Authentication.md`
- Modify: `Sources/MatrixClientKit/Documentation.docc/MatrixClientKit.md` (topics), `GettingStarted.md` (renvoi), `TestingWithMocks.md` (nouveaux doubles)
- Modify: `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md` (harnais), `Sources/MatrixClientKitCore/PackageInfo.swift`
- Modify: `Tests/MatrixClientKitCoreTests/*` si un test épingle `PackageInfo.version`

- [ ] **Step 1: Article DocC `Authentication`**

Sections, extraits compilables (mêmes conventions que `GettingStarted.md`) :
1. *Choosing a server* — `Matrix.client(server:storage:)`, erreurs typiques.
2. *Finding out how to sign in* — `loginDetails()`, quoi afficher selon `supportsPassword` /
   `supportsOAuth` / `oauthPrompts.contains(.create)` ; SSO non pris en charge.
3. *Password and email* — `.password`, `.email`.
4. *OAuth* — exemple complet avec `ASWebAuthenticationSession` (`import AuthenticationServices`,
   `callbackURLScheme` = schéma de `redirectURI`), `complete`, `cancel` quand l'utilisateur ferme.
5. *Signing in with a QR code* — les deux sens, rendu du QR (`CIFilter.qrCodeGenerator` à partir de
   `Data`), boucle sur `state`, `submitCheckCode`.
6. *After a soft logout* — observer `authState`, `reauthenticate` / `beginOAuthReauthentication`,
   relâcher l'ancienne session.

- [ ] **Step 2: README**

- Scope : remplacer « v0.3 covers … » par la couverture 0.4 (ajouter discovery, `loginDetails()`,
  OAuth, email, QR-code login, same-device sign-in after soft logout) ; retirer le paragraphe
  « `MatrixClient.loginDetails()` … is planned but **not implemented** yet ».
- Exemple d'en-tête : garder le mot de passe, ajouter une ligne `Matrix.client(server:)`.
- Feuille de route : tableau exact de la spec §10.
- Installation : `from: "0.4.0"` ; compatibilité : ligne `0.4.x | 26.09.07 | 18+ | 15+ | 6.2+`.

- [ ] **Step 3: CHANGELOG**

Section `## [0.4.0] - <date de publication>` :
- **Breaking** — les trois points de la spec §4.8, rédigés comme en 0.3 (« An application that
  implements the protocol itself … must add them, or use `MockMatrixClient` / `MockMatrixSession` »).
- **Added** — `Matrix.client(server:storage:)`, `loginDetails()`, `LoginDetails`, OAuth
  (`OAuthConfiguration`, `OAuthPrompt`, `OAuthLoginFlow`), `Credentials.email`, QR
  (`QRCodeLogin`, `QRCodeLoginState`, `QRCodeLoginFailure`, `Matrix.loginWithQRCode(scanned:…)`),
  `reauthenticate` / `beginOAuthReauthentication`, doubles et fixtures.
- **Changed** — store par session ; ramassage des stores orphelins (dont ceux laissés par une
  connexion 0.3 par-dessus une autre) ; identité cross-signing créée dès la connexion ; doc
  `AuthState`.
- **Not included** — inscription par mot de passe, SSO legacy, accorder une connexion par QR,
  gestion du compte via MAS.
- **Verified** — ce que les Tasks 14–15 ont réellement exercé, versions de Synapse et MAS
  épinglées, et tout repli (QR, reconnexion réduite) dit explicitement.

- [ ] **Step 4: Version et CONTRIBUTING**

`PackageInfo.version = "0.4.0"`. `CONTRIBUTING.md` : un paragraphe « Integration harness » renvoyant
à `Tests/IntegrationHarness/README.md`.

- [ ] **Step 5: Vérification finale**

Run: `swift build && swift test --skip MatrixClientKitIntegrationTests && swift format lint --recursive --strict Sources Tests`
Expected: PASS, lint propre.

Run (DocC, comme la CI) : les commandes du job « Build DocC » de `.github/workflows/ci.yml`.
Expected: aucun avertissement de lien cassé.

Run: `grep -rn "v0.4\b\|arrives in v0.4\|not implemented" Sources README.md`
Expected: aucune mention périmée.

- [ ] **Step 6: Commit**

```bash
git add README.md CHANGELOG.md CONTRIBUTING.md Sources Tests
git commit -m "docs: authentification dans la DocC, le README et le CHANGELOG ; version 0.4.0

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
