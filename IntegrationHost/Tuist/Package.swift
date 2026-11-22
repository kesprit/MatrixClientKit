// swift-tools-version: 6.2
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings()
#endif

let package = Package(
    name: "IntegrationHostDependencies",
    dependencies: [
        .package(path: "../..")
    ]
)
