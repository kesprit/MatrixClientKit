import ProjectDescription

// Xcode 26 ou 27 : un Xcode plus ancien est refusé avec un message clair.
let tuist = Tuist(
    project: .tuist(
        compatibleXcodeVersions: .list([.upToNextMajor("26.0"), .upToNextMajor("27.0")]),
        swiftVersion: "6.2"
    )
)
