import Testing
@testable import MatrixClientKitRust

@Test func upstreamRustSDKIsLinked() {
    #expect(UpstreamLinkCheck.canReferenceUpstreamTypes())
}
