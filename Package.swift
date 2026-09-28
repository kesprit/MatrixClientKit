// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MatrixClientKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "MatrixClientKit", targets: ["MatrixClientKit"]),
        .library(name: "MatrixClientKitCore", targets: ["MatrixClientKitCore"]),
        .library(name: "MatrixClientKitMocks", targets: ["MatrixClientKitMocks"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/matrix-org/matrix-rust-components-swift",
            exact: "26.09.07"
        )
    ],
    targets: [
        .target(name: "MatrixClientKitCore"),
        .target(
            name: "MatrixClientKitRust",
            dependencies: [
                "MatrixClientKitCore",
                .product(name: "MatrixRustSDK", package: "matrix-rust-components-swift"),
            ]
        ),
        .target(name: "MatrixClientKitMocks", dependencies: ["MatrixClientKitCore"]),
        .target(name: "MatrixClientKit", dependencies: ["MatrixClientKitCore", "MatrixClientKitRust"]),
        .testTarget(
            name: "MatrixClientKitCoreTests",
            dependencies: ["MatrixClientKitCore", "MatrixClientKitMocks"]
        ),
        .testTarget(name: "MatrixClientKitRustTests", dependencies: ["MatrixClientKitRust"]),
        .testTarget(name: "MatrixClientKitTests", dependencies: ["MatrixClientKit"]),
        // Réservé à la suite d'intégration, jamais dans `products:` : crée un store sans verrou
        // (comportement 0.2) dans un processus à part. La dépendance de la suite sur lui garantit
        // qu'il est construit avant les tests.
        .executableTarget(
            name: "IntegrationLegacySeeder",
            dependencies: ["MatrixClientKit", "MatrixClientKitRust"],
            path: "Tests/IntegrationLegacySeeder"
        ),
        .testTarget(
            name: "MatrixClientKitIntegrationTests",
            dependencies: ["MatrixClientKit", "MatrixClientKitRust", "IntegrationLegacySeeder"],
            exclude: ["README.md"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
