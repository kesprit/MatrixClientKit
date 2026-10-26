import Foundation
import MatrixClientKitCore
import MatrixRustSDK
import Testing

@testable import MatrixClientKitRust

private func plain(_ url: String = "mxc://e/a") throws -> MatrixRustSDK.MediaSource {
    try MatrixRustSDK.MediaSource.fromUrl(url: url)
}

private let encryptedJSON = """
    {"file":{"url":"mxc://e/a","key":{"kty":"oct","key_ops":["encrypt","decrypt"],"alg":"A256CTR","k":"qcHVMSgYg-71CauWBezXI5qkaRb0LuIy-Wx5kIaHMIA","ext":true},"iv":"X85+XgHN+HEAAAAAAAAAAA","hashes":{"sha256":"5qG4fFnbbVdlAB1Q72JDKwCagV6Dbkx9uds4rSak37c"},"v":"v2"}}
    """

@Suite struct MediaMapperTests {
    @Test func imageMapsDimensionsSizeBlurhashAndThumbnail() throws {
        let info = ImageInfo(
            height: 480, width: 640, mimetype: "image/png", size: 1234, thumbnailInfo: nil,
            thumbnailSource: try plain("mxc://e/t"), blurhash: "LEHV6n", isAnimated: nil)
        let content = ImageMessageContent(
            filename: "a.png", caption: "legend", formattedCaption: nil, source: try plain(), info: info)

        let media = try #require(MediaMapper.attachment(from: .image(content: content)))

        #expect(media.kind == .image)
        #expect(media.dimensions == MediaDimensions(width: 640, height: 480))
        #expect(media.size == 1234)
        #expect(media.mimeType == "image/png")
        #expect(media.thumbnail?.url == "mxc://e/t")
        #expect(media.blurhash == "LEHV6n")
        #expect(media.filename == "a.png")
        #expect(media.caption == "legend")
        #expect(media.source.url == "mxc://e/a")
    }

    @Test func audioWithVoiceIsVoice() throws {
        let content = AudioMessageContent(
            filename: "v.ogg", caption: nil, formattedCaption: nil, source: try plain(),
            info: AudioInfo(duration: 3, size: 10, mimetype: "audio/ogg"), audio: nil,
            voice: UnstableVoiceContent())
        let media = try #require(MediaMapper.attachment(from: .audio(content: content)))
        #expect(media.kind == .voice)
        #expect(media.duration == .seconds(3))
    }

    @Test func audioWithoutVoiceIsAudio() throws {
        let content = AudioMessageContent(
            filename: "s.mp3", caption: nil, formattedCaption: nil, source: try plain(),
            info: nil, audio: nil, voice: nil)
        #expect(MediaMapper.attachment(from: .audio(content: content))?.kind == .audio)
    }

    @Test func videoDurationBecomesDuration() throws {
        let info = VideoInfo(
            duration: 2.5, height: 1, width: 2, mimetype: "video/mp4", size: 5, thumbnailInfo: nil,
            thumbnailSource: nil, blurhash: nil)
        let content = VideoMessageContent(
            filename: "m.mp4", caption: nil, formattedCaption: nil, source: try plain(), info: info)
        let media = try #require(MediaMapper.attachment(from: .video(content: content)))
        #expect(media.kind == .video)
        #expect(media.duration == .milliseconds(2500))
    }

    @Test func fileMaps() throws {
        let info = FileInfo(mimetype: "application/pdf", size: 9, thumbnailInfo: nil, thumbnailSource: nil)
        let content = FileMessageContent(
            filename: "d.pdf", caption: nil, formattedCaption: nil, source: try plain(), info: info)
        let media = try #require(MediaMapper.attachment(from: .file(content: content)))
        #expect(media.kind == .file)
        #expect(media.mimeType == "application/pdf")
        #expect(media.size == 9)
        #expect(media.dimensions == nil)
    }

    @Test func textIsNotMedia() {
        let text = TextMessageContent(body: "salut", formatted: nil)
        #expect(MediaMapper.attachment(from: .text(content: text)) == nil)
    }

    @Test func hugeSizeIsClamped() throws {
        let info = FileInfo(mimetype: nil, size: UInt64.max, thumbnailInfo: nil, thumbnailSource: nil)
        let content = FileMessageContent(
            filename: "x", caption: nil, formattedCaption: nil, source: try plain(), info: info)
        #expect(MediaMapper.attachment(from: .file(content: content))?.size == Int.max)
    }

    @Test func plainSourceIsNotEncrypted() throws {
        let source = MediaMapper.source(from: try plain())
        #expect(!source.isEncrypted)
        #expect(source.url == "mxc://e/a")
        #expect(source.upstreamJSON != nil)
    }

    @Test func encryptedSourceIsDetected() throws {
        let source = MediaMapper.source(from: try MatrixRustSDK.MediaSource.fromJson(json: encryptedJSON))
        #expect(source.isEncrypted)
        #expect(source.url == "mxc://e/a")
    }

    @Test func upstreamSourceFallsBackToURLWhenPlain() throws {
        let source = MatrixClientKitCore.MediaSource(url: "mxc://e/a", isEncrypted: false, upstreamJSON: nil)
        #expect(try MediaMapper.upstreamSource(from: source).url() == "mxc://e/a")
    }

    @Test func upstreamSourceRoundTripsEncryptedJSON() throws {
        let source = MediaMapper.source(from: try MatrixRustSDK.MediaSource.fromJson(json: encryptedJSON))
        let back = MediaMapper.source(from: try MediaMapper.upstreamSource(from: source))
        #expect(back.isEncrypted)
    }

    @Test func upstreamSourceRefusesEncryptedWithoutJSON() {
        let source = MatrixClientKitCore.MediaSource(url: "mxc://e/a", isEncrypted: true, upstreamJSON: nil)
        #expect {
            try MediaMapper.upstreamSource(from: source)
        } throws: { error in
            guard case .unexpected = error as? MatrixError else { return false }
            return true
        }
    }

    @Test func upstreamSourceWithCorruptJSONFallsBackWhenPlain() throws {
        let source = MatrixClientKitCore.MediaSource(url: "mxc://e/a", isEncrypted: false, upstreamJSON: "{nope")
        #expect(try MediaMapper.upstreamSource(from: source).url() == "mxc://e/a")
    }

    @Test func upstreamSourceWithCorruptJSONFailsWhenEncrypted() {
        let source = MatrixClientKitCore.MediaSource(url: "mxc://e/a", isEncrypted: true, upstreamJSON: "{nope")
        #expect {
            try MediaMapper.upstreamSource(from: source)
        } throws: { error in
            guard case .unexpected = error as? MatrixError else { return false }
            return true
        }
    }

    @Test func nonFiniteOrHugeDurationsDoNotTrap() throws {
        func video(_ duration: TimeInterval) throws -> MediaAttachment {
            let info = VideoInfo(
                duration: duration, height: 1, width: 2, mimetype: "video/mp4", size: 5, thumbnailInfo: nil,
                thumbnailSource: nil, blurhash: nil)
            let content = VideoMessageContent(
                filename: "m.mp4", caption: nil, formattedCaption: nil, source: try plain(), info: info)
            return try #require(MediaMapper.attachment(from: .video(content: content)))
        }
        #expect(try video(.nan).duration == nil)
        #expect(try video(.infinity).duration == nil)
        #expect(try video(-.infinity).duration == nil)
        #expect(try video(-5).duration == .zero)
        let huge = try #require(try video(1e300).duration)
        #expect(huge > .seconds(1_000_000))
    }

    @Test func progressMaps() {
        let state = EventSendState.notSentYet(
            progress: MediaUploadProgress(index: 0, progress: AbstractProgress(current: 30, total: 100)))
        #expect(MediaMapper.uploadProgress(from: state) == UploadProgress(completedBytes: 30, totalBytes: 100))
    }

    @Test func progressAbsentWhenSent() {
        #expect(MediaMapper.uploadProgress(from: .sent(eventId: "$a")) == nil)
        #expect(MediaMapper.uploadProgress(from: .notSentYet(progress: nil)) == nil)
        #expect(MediaMapper.uploadProgress(from: nil) == nil)
    }
}
