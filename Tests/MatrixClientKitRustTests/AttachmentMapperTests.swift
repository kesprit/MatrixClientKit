import Foundation
import Testing
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

@Suite struct AttachmentMapperTests {
    private func tempFile(bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin")
        try Data(count: bytes).write(to: url)
        return url
    }

    private func imageKind() -> MatrixClientKitCore.Attachment.Kind { .image(dimensions: MediaDimensions(width: 4, height: 3), blurhash: "LEHV6n") }

    @Test func imageFromFileReadsSize() throws {
        let url = try tempFile(bytes: 10)
        defer { try? FileManager.default.removeItem(at: url) }
        let attachment = MatrixClientKitCore.Attachment(source: .file(url), kind: imageKind(), mimeType: "image/png")
        guard case let .image(params, thumbnail, info) = try MediaMapper.uploadRequest(for: attachment) else {
            Issue.record("expected .image")
            return
        }
        #expect(params.source == .file(filename: url.path))
        #expect(thumbnail == nil)
        #expect(info.size == 10)
        #expect(info.mimetype == "image/png")
        #expect(info.width == 4 && info.height == 3)
        #expect(info.blurhash == "LEHV6n")
    }

    @Test func imageFromDataUsesCount() throws {
        let attachment = MatrixClientKitCore.Attachment(
            source: .data(Data(count: 7), filename: "a.png"), kind: imageKind(), mimeType: "image/png")
        guard case let .image(params, _, info) = try MediaMapper.uploadRequest(for: attachment) else {
            Issue.record("expected .image")
            return
        }
        #expect(params.source == .data(bytes: Data(count: 7), filename: "a.png"))
        #expect(info.size == 7)
    }

    @Test func thumbnailInfoIsFilled() throws {
        let thumb = MatrixClientKitCore.Attachment.Thumbnail(
            source: .data(Data(count: 3), filename: "t.jpg"), mimeType: "image/jpeg",
            dimensions: MediaDimensions(width: 2, height: 1))
        let attachment = MatrixClientKitCore.Attachment(
            source: .data(Data(count: 7), filename: "a.png"), kind: imageKind(), mimeType: "image/png",
            thumbnail: thumb)
        guard case let .image(_, thumbnail, info) = try MediaMapper.uploadRequest(for: attachment) else {
            Issue.record("expected .image")
            return
        }
        #expect(thumbnail == .data(bytes: Data(count: 3), filename: "t.jpg"))
        #expect(info.thumbnailInfo == ThumbnailInfo(height: 1, width: 2, mimetype: "image/jpeg", size: 3))
    }

    @Test func videoCarriesDurationInSeconds() throws {
        let attachment = MatrixClientKitCore.Attachment(
            source: .data(Data(count: 2), filename: "v.mp4"),
            kind: .video(dimensions: nil, duration: .milliseconds(2500), blurhash: nil), mimeType: "video/mp4")
        guard case let .video(_, _, info) = try MediaMapper.uploadRequest(for: attachment) else {
            Issue.record("expected .video")
            return
        }
        #expect(info.duration == 2.5)
    }

    @Test func fileKindMaps() throws {
        let attachment = MatrixClientKitCore.Attachment(source: .data(Data(count: 2), filename: "d.pdf"), kind: .file, mimeType: "application/pdf")
        guard case let .file(_, info) = try MediaMapper.uploadRequest(for: attachment) else {
            Issue.record("expected .file")
            return
        }
        #expect(info.size == 2 && info.mimetype == "application/pdf")
    }

    /// `sendFile` amont n'envoie pas de vignette : elle est ignorée sans être validée.
    @Test func fileIgnoresThumbnailWithoutValidatingIt() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let thumb = MatrixClientKitCore.Attachment.Thumbnail(source: .file(missing), mimeType: "image/jpeg")
        let attachment = MatrixClientKitCore.Attachment(
            source: .data(Data(count: 2), filename: "d.pdf"), kind: .file, mimeType: "application/pdf",
            thumbnail: thumb)
        guard case let .file(_, info) = try MediaMapper.uploadRequest(for: attachment) else {
            Issue.record("expected .file")
            return
        }
        #expect(info.thumbnailInfo == nil && info.thumbnailSource == nil)
        #expect(info.size == 2 && info.mimetype == "application/pdf")
    }

    @Test func audioIgnoresThumbnail() throws {
        let thumb = MatrixClientKitCore.Attachment.Thumbnail(source: .data(Data(count: 3), filename: "t.jpg"), mimeType: "image/jpeg")
        let attachment = MatrixClientKitCore.Attachment(
            source: .data(Data(count: 5), filename: "a.ogg"), kind: .audio(duration: .seconds(3)),
            mimeType: "audio/ogg", thumbnail: thumb)
        guard case let .audio(_, info) = try MediaMapper.uploadRequest(for: attachment) else {
            Issue.record("expected .audio")
            return
        }
        #expect(info == AudioInfo(duration: 3, size: 5, mimetype: "audio/ogg"))
    }

    @Test func voiceWaveformIsClamped() throws {
        let attachment = MatrixClientKitCore.Attachment(
            source: .data(Data(count: 5), filename: "v.ogg"),
            kind: .voice(duration: nil, waveform: [-1, 0.5, 2]), mimeType: "audio/ogg")
        guard case let .voice(_, _, waveform) = try MediaMapper.uploadRequest(for: attachment) else {
            Issue.record("expected .voice")
            return
        }
        #expect(waveform == [0, 0.5, 1])
    }

    @Test func missingFileIsNotFound() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let attachment = MatrixClientKitCore.Attachment(source: .file(url), kind: .file, mimeType: "text/plain")
        #expect {
            try MediaMapper.uploadRequest(for: attachment)
        } throws: { error in
            guard case .notFound(.media) = error as? MatrixError else { return false }
            return true
        }
    }

    @Test func remoteURLIsNotFound() throws {
        let attachment = MatrixClientKitCore.Attachment(
            source: .file(try #require(URL(string: "https://example.org/a.png"))), kind: imageKind(),
            mimeType: "image/png")
        #expect {
            try MediaMapper.uploadRequest(for: attachment)
        } throws: { error in
            guard case .notFound(.media) = error as? MatrixError else { return false }
            return true
        }
    }

    @Test func captionIsPassed() throws {
        let attachment = MatrixClientKitCore.Attachment(
            source: .data(Data(count: 1), filename: "a"), kind: .file, mimeType: "text/plain", caption: "hello")
        guard case let .file(params, _) = try MediaMapper.uploadRequest(for: attachment) else {
            Issue.record("expected .file")
            return
        }
        #expect(params.caption == "hello")
        #expect(params.formattedCaption == nil && params.mentions == nil)
        #expect(params.inReplyTo == nil && params.extraContentJson == nil)
    }
}
