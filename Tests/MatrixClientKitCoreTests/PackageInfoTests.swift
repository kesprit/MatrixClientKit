import Testing
@testable import MatrixClientKitCore

@Test func packageInfoDeclaresPinnedUpstreamVersion() {
    #expect(PackageInfo.upstreamVersion == "26.09.07")
    #expect(PackageInfo.version == "0.4.0")
}
