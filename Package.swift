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
        .testTarget(name: "MatrixClientKitCoreTests", dependencies: ["MatrixClientKitCore"]),
        .testTarget(name: "MatrixClientKitRustTests", dependencies: ["MatrixClientKitRust"]),
    ],
    swiftLanguageModes: [.v6]
)
