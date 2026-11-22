import ProjectDescription

// Hôte signé des tests d'intégration de MatrixClientKit (macOS).
//
// Sur macOS, le trousseau data protection exige un exécutable signé avec `keychain-access-groups` ;
// `swift test` ne signe pas. Ce projet fournit donc l'hôte (`IntegrationHost`) dans lequel Xcode
// charge le bundle `IntegrationHostTests`, qui compile les sources de la suite
// (`Tests/MatrixClientKitIntegrationTests`), et le seeder 0.2 (`IntegrationLegacySeeder`), signé avec
// les mêmes entitlements. Les deux partagent le groupe `<Team ID>.dev.kesprit.mck.IntegrationHost`,
// premier groupe de l'entitlement donc groupe par défaut des éléments créés sans
// `kSecAttrAccessGroup` (c'est le cas de la suite : aucun `keychainAccessGroup` n'est passé).
//
// Signature automatique locale : Xcode doit être connecté à un compte développeur. Le Team ID vient
// de l'environnement (`TUIST_MCK_DEVELOPMENT_TEAM`), à défaut celui du mainteneur.

let developmentTeam = Environment.mckDevelopmentTeam.getString(default: "59ZC26E65Z")

let signing: SettingsDictionary = [
    "DEVELOPMENT_TEAM": .string(developmentTeam),
    "CODE_SIGN_STYLE": "Automatic",
    "CODE_SIGN_IDENTITY": "Apple Development",
    // Comme `swiftLanguageModes: [.v6]` du package : en mode 6, les diagnostics de concurrence
    // (Sendable, isolation) sont des erreurs, donc le job CI `integration-host` y échoue.
    "SWIFT_VERSION": "6.0",
    // Les sources de la suite utilisent des symboles `package` du package racine.
    "OTHER_SWIFT_FLAGS": "$(inherited) -package-name MatrixClientKit",
]

let entitlements: Entitlements = .file(path: "Config/IntegrationHost.entitlements")
let packageDependencies: [TargetDependency] = [
    .external(name: "MatrixClientKit"),
    .external(name: "MatrixClientKitCore"),
    .external(name: "_MatrixClientKitRust"),
]

let project = Project(
    name: "IntegrationHost",
    targets: [
        .target(
            name: "IntegrationHost",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.kesprit.mck.IntegrationHost",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .default,
            sources: ["Sources/**"],
            entitlements: entitlements,
            settings: .settings(base: signing)
        ),
        .target(
            name: "IntegrationLegacySeeder",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.kesprit.mck.IntegrationLegacySeeder",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .extendingDefault(with: ["LSUIElement": true]),
            sources: ["../Tests/IntegrationLegacySeeder/**"],
            entitlements: entitlements,
            dependencies: packageDependencies,
            settings: .settings(base: signing)
        ),
        .target(
            name: "IntegrationHostTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.kesprit.mck.IntegrationHostTests",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .default,
            sources: [
                .glob(
                    "../Tests/MatrixClientKitIntegrationTests/**",
                    excluding: ["../Tests/MatrixClientKitIntegrationTests/README.md"]
                )
            ],
            dependencies: [.target(name: "IntegrationHost"), .target(name: "IntegrationLegacySeeder")]
                + packageDependencies,
            // Le bundle est chargé par l'hôte (`-bundle_loader`), qui ne référence rien du package :
            // Tuist ne relie aucune dépendance au bundle de tests hébergé, et la bibliothèque Rust
            // libmatrix_sdk_ffi.a (xcframework de MatrixRustSDK) n'est pas autolinkée, d'où des
            // symboles `_uniffi_*` non définis. Le nom est celui du binaire de
            // matrix-rust-components-swift : à revoir si l'amont le renomme.
            settings: .settings(base: signing.merging(["OTHER_LDFLAGS": "$(inherited) -lmatrix_sdk_ffi"]) { $1 })
        ),
    ]
)
