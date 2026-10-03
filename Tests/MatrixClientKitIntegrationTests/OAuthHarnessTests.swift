import Testing
import Foundation
import MatrixClientKit
import MatrixClientKitRust
import MatrixRustSDK

extension HarnessTests {
    // Connexion OAuth et par QR contre `synapse-oauth` délégué à MAS, dont les formulaires web
    // sont pilotés par ``MASDriver``. Chaque cas supprime ses répertoires et déconnecte ses
    // sessions, même interrompu (`cleaningUp`).
    @Suite(.enabled(if: HarnessConfiguration.current?.mas != nil))
    struct OAuthHarnessTests {
        @Test(.timeLimit(.minutes(2)))
        func loginDetailsAdvertiseOAuth() async throws {
            let harness = try OAuthHarness()
            let directory = newHarnessDirectory()
            defer { removeDirectory(directory) }

            let client = Matrix.client(homeserver: harness.homeserver, storage: .local(directory: directory))
            let details = try await client.loginDetails()

            #expect(details.supportsOAuth)
            #expect(!details.supportsPassword)
        }

        @Test(.timeLimit(.minutes(2)))
        func oauthLoginOpensASession() async throws {
            let harness = try OAuthHarness()
            let directory = newHarnessDirectory()
            defer { removeDirectory(directory) }

            let (session, _) = try await harness.signInWithOAuth(in: directory)
            let states = session.sync.state
            await session.sync.start()
            let state = await waitUntilRunning(states)

            #expect(state == .running, "sync reached \(String(describing: state))")
            #expect(session.userID.rawValue.hasSuffix(":localhost"), "userID: \(session.userID)")

            await cleaningUp {
                await session.sync.stop()
                try? await session.logout()
            }
        }

        @Test(.timeLimit(.minutes(2)))
        func aSecondCompleteIsRefused() async throws {
            let harness = try OAuthHarness()
            let directory = newHarnessDirectory()
            defer { removeDirectory(directory) }

            let (session, flow) = try await harness.signInWithOAuth(in: directory)
            // Une URL de rappel bien formée : seul le caractère « déjà consommé » du flux est en jeu.
            let callback = try #require(URL(string: "\(OAuthHarness.redirectScheme):/callback?state=x&code=y"))

            let outcome: Result<any MatrixSession, any Error>
            do {
                outcome = .success(try await flow.complete(callbackURL: callback))
            } catch {
                outcome = .failure(error)
            }

            switch outcome {
            case let .success(second):
                await cleaningUp { try? await second.logout() }
                Issue.record("a second complete(callbackURL:) succeeded")
            case let .failure(error):
                let isUnexpected = if case .unexpected? = error as? MatrixError { true } else { false }
                #expect(isUnexpected, "expected .unexpected, got \(error)")
            }

            await cleaningUp { try? await session.logout() }
        }

        @Test(.timeLimit(.minutes(2)))
        func cancellingLeavesNoStore() async throws {
            let harness = try OAuthHarness()
            let directory = newHarnessDirectory()
            defer { removeDirectory(directory) }

            let client = Matrix.client(homeserver: harness.homeserver, storage: .local(directory: directory))
            let flow = try await client.beginOAuthLogin(harness.oauthConfiguration)
            await flow.cancel()

            #expect(storeDirectories(in: directory).isEmpty, "stores: \(storeDirectories(in: directory))")
        }

        @Test(.timeLimit(.minutes(2)))
        func anOAuthSessionIsRestoredAfterRelaunch() async throws {
            let harness = try OAuthHarness()
            let directory = newHarnessDirectory()
            defer { removeDirectory(directory) }

            var opened: (any MatrixSession)? = try await harness.signInWithOAuth(in: directory).session
            let deviceID = try #require(opened?.deviceID)
            let states = try #require(opened).sync.state
            await opened?.sync.start()
            let state = await waitUntilRunning(states)
            await opened?.sync.stop()
            // Le « relancement » : plus aucune référence à la session ouverte.
            opened = nil

            let restored = try await Matrix.restoreSession(storage: .local(directory: directory))

            #expect(state == .running, "sync reached \(String(describing: state))")
            #expect(restored?.deviceID == deviceID)

            if let restored {
                await cleaningUp { try? await restored.logout() }
            }
        }

        // MARK: - Connexion par QR (MSC4108)

        /// Le nouvel appareil affiche le code ; l'appareil existant, ouvert par OAuth, le scanne et
        /// accorde la connexion par l'API amont.
        @Test(.timeLimit(.minutes(3)))
        func qrLoginWhereThisDeviceDisplaysTheCode() async throws {
            let harness = try OAuthHarness()
            let existingDirectory = newHarnessDirectory()
            let newDirectory = newHarnessDirectory()
            defer {
                removeDirectory(existingDirectory)
                removeDirectory(newDirectory)
            }

            let existing = try await harness.signInWithOAuth(in: existingDirectory).session
            let client = Matrix.client(homeserver: harness.homeserver, storage: .local(directory: newDirectory))
            let login = client.loginWithQRCode(harness.oauthConfiguration)
            var signedIn: (any MatrixSession)?
            do {
                try await harness.resetIdentity(of: existing)
                let starting = Task { try await login.start() }
                let displayed = await firstValue(of: login.state, within: .seconds(30)) { $0.qrCode != nil }
                let bytes = try #require(displayed?.qrCode, "the new device never displayed a QR code")

                try await harness.grant(from: existing, newDevice: login) { handler, listener in
                    try await handler.scan(
                        qrCodeData: try QrCodeData.fromBytes(bytes: bytes), progressListener: listener)
                } onCheckCode: { checkCode in
                    let entering = await firstValue(of: login.state, within: .seconds(30)) { $0 == .enterCheckCode }
                    try #require(entering == .enterCheckCode, "the new device never asked for the check code")
                    try await login.submitCheckCode(checkCode)
                }

                let session = try await starting.value
                signedIn = session
                await harness.expectVerified(session)
            } catch {
                login.cancel()
                await harness.signOut(existing, signedIn)
                throw error
            }
            await harness.signOut(existing, signedIn)
        }

        /// L'appareil existant, ouvert par OAuth, affiche le code par l'API amont ; le nouvel
        /// appareil le scanne.
        @Test(.timeLimit(.minutes(3)))
        func qrLoginWhereThisDeviceScansTheCode() async throws {
            let harness = try OAuthHarness()
            let existingDirectory = newHarnessDirectory()
            let newDirectory = newHarnessDirectory()
            defer {
                removeDirectory(existingDirectory)
                removeDirectory(newDirectory)
            }

            let existing = try await harness.signInWithOAuth(in: existingDirectory).session
            let scanned = ScannedLogin()
            let configuration = harness.oauthConfiguration
            var signedIn: (any MatrixSession)?
            do {
                try await harness.resetIdentity(of: existing)
                try await harness.grantGenerating(from: existing, newDevice: scanned) { qrCode in
                    await scanned.begin(
                        Matrix.loginWithQRCode(
                            scanned: qrCode, configuration: configuration, storage: .local(directory: newDirectory))
                    )
                } checkCode: {
                    let login = try #require(await scanned.login)
                    let displayed = await firstValue(of: login.state, within: .seconds(30)) { $0.checkCode != nil }
                    let code = try #require(displayed?.checkCode, "the new device never displayed a check code")
                    return try #require(UInt8(code), "check code: \(code)")
                }

                let session = try #require(try await scanned.session())
                signedIn = session
                await harness.expectVerified(session)
            } catch {
                await scanned.login?.cancel()
                await harness.signOut(existing, signedIn)
                throw error
            }
            await harness.signOut(existing, signedIn)
        }
    }
}

/// Ce que les cas OAuth partagent : configuration du harnais, client OAuth, connexion pilotée.
private struct OAuthHarness {
    /// MAS n'accepte un schéma personnalisé qu'en DNS inversé de l'hôte du `client_uri`.
    static let redirectScheme = "com.matrixclientkit.harness"

    let homeserver: URL
    let mas: URL
    let user: String
    let password: String
    let oauthConfiguration = OAuthConfiguration(
        clientName: "MatrixClientKit Harness",
        redirectURI: URL(string: "\(OAuthHarness.redirectScheme):/callback")!,
        clientURI: URL(string: "https://harness.matrixclientkit.com/")!
    )

    init() throws {
        let configuration = try #require(HarnessConfiguration.current)
        homeserver = try #require(configuration.oauthHomeserver)
        mas = try #require(configuration.mas)
        user = try #require(configuration.oauthUser)
        password = try #require(configuration.oauthPassword)
    }

    /// Ouvre une session par OAuth dans `directory`, MAS piloté par HTTP. Rend aussi le flux,
    /// déjà consommé.
    func signInWithOAuth(in directory: URL) async throws -> (session: any MatrixSession, flow: any OAuthLoginFlow) {
        let client = Matrix.client(homeserver: homeserver, storage: .local(directory: directory))
        let flow = try await client.beginOAuthLogin(oauthConfiguration)
        let callback = try await MASDriver(mas: mas).authorize(
            flow.authorizationURL, username: user, password: password, redirectScheme: Self.redirectScheme
        )
        return (try await flow.complete(callbackURL: callback), flow)
    }

    /// Donne à `existing` des clés privées de signature croisée, que l'octroi transmet au nouvel
    /// appareil (`MissingSecretsBackup` sans elles). Le compte de test en a déjà une, laissée par
    /// une exécution précédente ou par la connexion OAuth d'un cas voisin, dont les clés privées
    /// sont restées sur un appareil déconnecté : seule une réinitialisation, approuvée dans MAS
    /// comme le ferait l'utilisateur, en remet sur cet appareil.
    func resetIdentity(of existing: any MatrixSession) async throws {
        // `as!` voulu : la couture n'existe que sur la session Rust, seule implémentation ici.
        let rust = existing as! RustMatrixSession
        // Poignée amont locale à cette fonction : libérée avant la session.
        guard let handle = try await rust.underlyingClient.encryption().resetIdentity() else { return }
        guard case .oAuth = handle.authType() else {
            await handle.cancel()
            Issue.record("the identity reset asks for \(handle.authType()), not an OAuth approval")
            return
        }
        try await MASDriver(mas: mas).allowCrossSigningReset(username: user, password: password)
        try await handle.reset(auth: nil)
    }

    /// L'appareil existant scanne le code du nouveau (`scan` appelle l'API amont) et accorde la
    /// connexion : saisie du code de contrôle par `onCheckCode`, approbation dans MAS.
    func grant(
        from existing: any MatrixSession,
        newDevice login: any QRCodeLogin,
        scan: @escaping @Sendable (GrantLoginWithQrCodeHandler, GrantProgress) async throws -> Void,
        onCheckCode: @escaping @Sendable (UInt8) async throws -> Void
    ) async throws {
        let progress = GrantProgress()
        let granting = grantTask(existing, finish: progress.finish) { try await scan($0, progress) }

        do {
            updates: for await update in progress.updates {
                switch update {
                case let .establishingSecureChannel(checkCode, _):
                    try await onCheckCode(checkCode)
                case let .waitingForAuth(verificationUri, continuationSender):
                    try await approve(verificationUri, continuationSender, newDevice: login)
                case .done:
                    break updates
                case .starting, .syncingSecrets:
                    continue
                }
            }
            try await granting.value
        } catch {
            granting.cancel()
            throw error
        }
    }

    /// L'appareil existant affiche un code (`generate`) que le nouvel appareil scanne
    /// (`onQRCode`) ; il envoie le code de contrôle que ce dernier affiche (`checkCode`), puis
    /// approuve dans MAS.
    func grantGenerating(
        from existing: any MatrixSession,
        newDevice scanned: ScannedLogin,
        onQRCode: @escaping @Sendable (Data) async throws -> Void,
        checkCode: @escaping @Sendable () async throws -> UInt8
    ) async throws {
        let progress = GeneratedGrantProgress()
        let granting = grantTask(existing, finish: progress.finish) {
            try await $0.generate(progressListener: progress)
        }

        do {
            updates: for await update in progress.updates {
                switch update {
                case let .qrReady(qrCode):
                    try await onQRCode(qrCode.toBytes())
                case let .qrScanned(checkCodeSender):
                    try await checkCodeSender.send(code: try await checkCode())
                case let .waitingForAuth(verificationUri, continuationSender):
                    let login = try #require(await scanned.login)
                    try await approve(verificationUri, continuationSender, newDevice: login)
                case .done:
                    break updates
                case .starting, .syncingSecrets:
                    continue
                }
            }
            try await granting.value
        } catch {
            granting.cancel()
            throw error
        }
    }

    /// Lance l'octroi côté existant dans une tâche, qui termine le flux de progrès en sortant.
    /// Le gestionnaire amont n'est retenu que par cette tâche : libéré à sa fin, avant la
    /// session — le client FFI doit partir en dernier.
    private func grantTask(
        _ existing: any MatrixSession,
        finish: @escaping @Sendable () -> Void,
        body: @escaping @Sendable (GrantLoginWithQrCodeHandler) async throws -> Void
    ) -> Task<Void, any Error> {
        // `as!` voulu : la couture n'existe que sur la session Rust, seule implémentation ici.
        let rust = existing as! RustMatrixSession
        return Task {
            defer { finish() }
            try await body(rust.underlyingClient.newGrantLoginWithQrCodeHandler())
        }
    }

    /// Signale à l'octroi amont que l'approbation est ouverte, puis approuve le nouvel appareil
    /// dans MAS, comme l'utilisateur dans le navigateur de l'appareil existant.
    private func approve(
        _ verificationUri: String, _ continuationSender: ContinuationMessageSender, newDevice login: any QRCodeLogin
    ) async throws {
        let uri = try #require(URL(string: verificationUri))
        // `confirm()` d'abord : l'existant n'accepte le protocole qu'à ce signal, et le nouvel
        // appareil n'attend l'approbation (son code d'appareil en main) qu'une fois accepté.
        try await continuationSender.confirm()
        // MAS 1.26.0 ne fournit pas d'URI « complète » : le code à saisir est celui que le
        // nouvel appareil affiche.
        let waiting = await firstValue(of: login.state, within: .seconds(30)) { $0.userCode != nil }
        let userCode = try #require(waiting?.userCode, "the new device never waited for approval")
        try await MASDriver(mas: mas).approveDevice(
            verificationURI: uri, userCode: userCode, username: user, password: password
        )
    }

    /// Le nouvel appareil a reçu les secrets de l'existant : il est vérifié.
    func expectVerified(_ session: any MatrixSession) async {
        let states = session.sync.state
        await session.sync.start()
        let state = await waitUntilRunning(states)
        #expect(state == .running, "sync reached \(String(describing: state))")
        let status = await firstValue(of: session.encryption.verificationStatus, within: .seconds(30)) {
            $0 == .verified
        }
        #expect(status == .verified, "the new device never became verified")
    }

    func signOut(_ existing: any MatrixSession, _ signedIn: (any MatrixSession)?) async {
        await cleaningUp {
            if let signedIn {
                await signedIn.sync.stop()
                try? await signedIn.logout()
            }
            await existing.sync.stop()
            try? await existing.logout()
        }
    }
}

extension QRCodeLoginState {
    fileprivate var qrCode: Data? {
        if case let .displayQRCode(bytes) = self { bytes } else { nil }
    }

    fileprivate var checkCode: String? {
        if case let .displayCheckCode(code) = self { code } else { nil }
    }

    fileprivate var userCode: String? {
        if case let .waitingForApproval(userCode) = self { userCode } else { nil }
    }
}

/// Relaie les progrès amont de l'octroi (code scanné par l'existant) dans un flux.
private final class GrantProgress: GrantQrLoginProgressListener {
    let updates: AsyncStream<GrantQrLoginProgress>
    private let continuation: AsyncStream<GrantQrLoginProgress>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func onUpdate(state: GrantQrLoginProgress) {
        continuation.yield(state)
    }

    func finish() {
        continuation.finish()
    }
}

/// Relaie les progrès amont de l'octroi (code affiché par l'existant) dans un flux.
private final class GeneratedGrantProgress: GrantGeneratedQrLoginProgressListener {
    let updates: AsyncStream<GrantGeneratedQrLoginProgress>
    private let continuation: AsyncStream<GrantGeneratedQrLoginProgress>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream()
    }

    func onUpdate(state: GrantGeneratedQrLoginProgress) {
        continuation.yield(state)
    }

    func finish() {
        continuation.finish()
    }
}

/// La connexion par QR du nouvel appareil qui scanne, créée seulement quand l'existant a produit
/// son code, et sa tâche `start()`.
private actor ScannedLogin {
    private(set) var login: (any QRCodeLogin)?
    private var starting: Task<any MatrixSession, any Error>?

    func begin(_ login: any QRCodeLogin) {
        self.login = login
        starting = Task { try await login.start() }
    }

    func session() async throws -> (any MatrixSession)? {
        try await starting?.value
    }
}
