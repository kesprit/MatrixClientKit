import Testing
import Foundation
import MatrixClientKitMocks
@testable import MatrixClientKitCore

@Suite struct MediaModelTests {
    @Test func mediaSourceAcceptsMxc() {
        let source = MediaSource(url: "mxc://example.org/abc")
        #expect(source?.url == "mxc://example.org/abc")
        #expect(source?.isEncrypted == false)
    }

    @Test func mediaSourceRejectsOtherSchemes() {
        #expect(MediaSource(url: "https://example.org/a") == nil)
        #expect(MediaSource(url: "") == nil)
        #expect(MediaSource(url: "mxc://") == nil)
        #expect(MediaSource(url: "MXC://example.org/abc") != nil)
    }

    @Test func mediaSourceRoundTripsThroughCodable() throws {
        let source = MediaSource(url: "mxc://e/x", isEncrypted: true, upstreamJSON: "{\"k\":1}")
        let data = try JSONEncoder().encode(source)
        #expect(try JSONDecoder().decode(MediaSource.self, from: data) == source)
    }

    @Test func uploadProgressFraction() {
        #expect(UploadProgress(completedBytes: 50, totalBytes: 200).fractionCompleted == 0.25)
        #expect(UploadProgress(completedBytes: 10, totalBytes: 0).fractionCompleted == 0)
        #expect(UploadProgress(completedBytes: 300, totalBytes: 200).fractionCompleted == 1)
    }

    @Test func messageInitDefaultsMediaToNil() throws {
        let message = try #require(SampleData.message("hi").message)
        #expect(message.media == nil)
        #expect(message.uploadProgress == nil)
    }

    @Test func roomAvatarFromURL() {
        func room(_ url: URL?) -> RoomSummary {
            RoomSummary(
                id: RoomID(rawValue: "!r:e")!, displayName: nil, topic: nil, avatarURL: url,
                isDirect: false, isEncrypted: nil, joinedMemberCount: 1,
                notificationCount: 0, highlightCount: 0, membership: .joined
            )
        }
        #expect(room(URL(string: "mxc://e/a")).avatar?.url == "mxc://e/a")
        #expect(room(nil).avatar == nil)
    }
}
