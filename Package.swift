// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MatrixClientKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "MatrixClientKit", targets: ["MatrixClientKit"]),
        .library(name: "MatrixClientKitCore", targets: ["MatrixClientKitCore"]),
        .library(name: "MatrixClientKitMocks", targets: ["MatrixClientKitMocks"]),
        // Réservé au projet `IntegrationHost/` (Tuist), qui n'importe que des produits : la suite
        // d'intégration utilise des symboles `package` de cette cible. Pas une API : ne pas en dépendre.
        .library(name: "MatrixClientKitRust", targets: ["MatrixClientKitRust"]),
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
    ],
    swiftLanguageModes: [.v6]
)
