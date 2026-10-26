import Testing
import Foundation
import MatrixClientKitMocks
@testable import MatrixClientKitCore

@Suite struct MediaMockTests {
    @Test func sendHandleCountsCalls() async throws {
        let handle = MockSendHandle()
        let first = try await handle.cancel()
        _ = try await handle.cancel()
        try await handle.retry()
        #expect(first == true)
        #expect(handle.cancelCount == 2)
        #expect(handle.retryCount == 1)
    }

    @Test func existentialTimelineExposesMediaMembers() async throws {
        let mock = MockTimeline()
        let item = SampleData.message("hi", isOwn: true)
        let handle = MockSendHandle()
        mock.sendHandles = [item.id: handle]
        let timeline: any Timeline = mock
        _ = try await timeline.send(SampleData.imageAttachment())
        #expect(mock.sentAttachments.count == 1)
        #expect(timeline.sendHandle(for: item) != nil)
        #expect(timeline.sendHandle(for: SampleData.message("other")) == nil)

        let session: any MatrixSession = MockMatrixSession()
        #expect(session.media is MockMediaService)
    }

    @Test func attachmentUploadCancelThenWaitThrowsCancellation() async {
        let upload = MockAttachmentUpload()
        upload.cancel()
        await #expect(throws: CancellationError.self) { try await upload.waitUntilSent() }
        await #expect(throws: CancellationError.self) { try await upload.waitUntilSent() }
        #expect(upload.cancelCount == 1)
    }

    @Test func mediaServiceReturnsConfiguredContent() async throws {
        let source = SampleData.mediaSource("a")
        let service = MockMediaService()
        service.contents = [source: Data([1, 2, 3])]
        #expect(try await service.content(of: source) == Data([1, 2, 3]))
        #expect(try await service.thumbnail(of: source, width: 32, height: 16) == Data([1, 2, 3]))
        #expect(try await service.maxUploadSize() == 50 * 1024 * 1024)
        #expect(service.thumbnailRequests.count == 1)
        #expect(service.thumbnailRequests.first?.width == 32)
        #expect(service.thumbnailRequests.first?.height == 16)
    }

    @Test func mediaServiceUnknownSourceIsNotFound() async {
        let service = MockMediaService()
        await #expect(throws: MatrixError.notFound(.media)) {
            try await service.content(of: SampleData.mediaSource("none"))
        }
    }

    @Test func mediaFileWritesAndPersists() async throws {
        let source = SampleData.mediaSource("f")
        let service = MockMediaService()
        service.contents = [source: Data("hello".utf8)]
        let file = try await service.file(of: source, filename: "a.txt", mimeType: "text/plain")
        #expect(try Data(contentsOf: file.url) == Data("hello".utf8))
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destination) }
        #expect(try file.persist(to: destination))
        #expect(try Data(contentsOf: destination) == Data("hello".utf8))
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
    }

    @Test func timelineRecordsAttachments() async throws {
        let timeline = MockTimeline()
        let attachment = Attachment(source: .data(Data([1]), filename: "a.png"), kind: .file, mimeType: "image/png")
        let upload = try await timeline.send(attachment)
        #expect(timeline.sentAttachments == [attachment])
        #expect(upload is MockAttachmentUpload)

        timeline.attachmentSendError = .notFound(.media)
        await #expect(throws: MatrixError.notFound(.media)) { try await timeline.send(attachment) }
        #expect(timeline.sentAttachments.count == 1)
    }

    @Test func timelineSendHandleLookup() {
        let timeline = MockTimeline()
        let item = SampleData.message("hi")
        #expect(timeline.sendHandle(for: item) == nil)
        let handle = MockSendHandle()
        timeline.sendHandles[item.id] = handle
        #expect(timeline.sendHandle(for: item) as? MockSendHandle === handle)
    }

    @Test func messageSendReturnsNextSendHandle() async throws {
        let timeline = MockTimeline()
        let handle = MockSendHandle()
        timeline.nextSendHandle = handle
        let returned = try await timeline.send(MessageContent.text("hi"))
        #expect(returned as? MockSendHandle === handle)
        #expect(timeline.sentMessages == [.text("hi")])
    }
}
