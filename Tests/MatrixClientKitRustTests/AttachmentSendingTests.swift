import Foundation
import Synchronization
import Testing
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

/// Timeline amont factice : note chaque appel `send*` et rend un handle sans objet Rust derrière
/// (`NoHandle`, jamais appelé ici, libéré sans appel FFI).
private final class FakeAttachmentSending: AttachmentSending {
    enum Call: Equatable {
        case image(caption: String?, thumbnail: UploadSource?, mimeType: String?)
        case video(caption: String?, thumbnail: UploadSource?, mimeType: String?)
        case audio(caption: String?, mimeType: String?)
        case voice(caption: String?, mimeType: String?, waveform: [Float])
        case file(caption: String?, mimeType: String?)
    }

    private let log = Mutex<[Call]>([])
    var calls: [Call] { log.withLock { $0 } }

    private func record(_ call: Call) -> SendAttachmentJoinHandle {
        log.withLock { $0.append(call) }
        return SendAttachmentJoinHandle(noHandle: .init())
    }

    func sendImage(params: UploadParameters, thumbnailSource: UploadSource?, imageInfo: ImageInfo) throws
        -> SendAttachmentJoinHandle
    {
        record(.image(caption: params.caption, thumbnail: thumbnailSource, mimeType: imageInfo.mimetype))
    }

    func sendVideo(params: UploadParameters, thumbnailSource: UploadSource?, videoInfo: VideoInfo) throws
        -> SendAttachmentJoinHandle
    {
        record(.video(caption: params.caption, thumbnail: thumbnailSource, mimeType: videoInfo.mimetype))
    }

    func sendAudio(params: UploadParameters, audioInfo: AudioInfo) throws -> SendAttachmentJoinHandle {
        record(.audio(caption: params.caption, mimeType: audioInfo.mimetype))
    }

    func sendVoiceMessage(params: UploadParameters, audioInfo: AudioInfo, waveform: [Float]) throws
        -> SendAttachmentJoinHandle
    {
        record(.voice(caption: params.caption, mimeType: audioInfo.mimetype, waveform: waveform))
    }

    func sendFile(params: UploadParameters, fileInfo: FileInfo) throws -> SendAttachmentJoinHandle {
        record(.file(caption: params.caption, mimeType: fileInfo.mimetype))
    }
}

@Suite struct AttachmentSendingTests {
    private static let thumbnail = MatrixClientKitCore.Attachment.Thumbnail(
        source: .data(Data(count: 3), filename: "t.jpg"), mimeType: "image/jpeg")

    private func dispatch(_ kind: MatrixClientKitCore.Attachment.Kind, mimeType: String)
        throws -> [FakeAttachmentSending.Call]
    {
        let attachment = MatrixClientKitCore.Attachment(
            source: .data(Data(count: 4), filename: "m"), kind: kind, mimeType: mimeType, caption: "c",
            thumbnail: Self.thumbnail)
        let sending = FakeAttachmentSending()
        _ = try sending.start(MediaMapper.uploadRequest(for: attachment))
        return sending.calls
    }

    @Test func imageGoesToSendImageWithItsThumbnail() throws {
        #expect(
            try dispatch(.image(dimensions: nil, blurhash: nil), mimeType: "image/png")
                == [
                    .image(
                        caption: "c", thumbnail: .data(bytes: Data(count: 3), filename: "t.jpg"), mimeType: "image/png")
                ])
    }

    @Test func videoGoesToSendVideoWithItsThumbnail() throws {
        #expect(
            try dispatch(.video(dimensions: nil, duration: .seconds(1), blurhash: nil), mimeType: "video/mp4")
                == [
                    .video(
                        caption: "c", thumbnail: .data(bytes: Data(count: 3), filename: "t.jpg"), mimeType: "video/mp4")
                ])
    }

    @Test func audioGoesToSendAudio() throws {
        #expect(
            try dispatch(.audio(duration: nil), mimeType: "audio/ogg") == [.audio(caption: "c", mimeType: "audio/ogg")])
    }

    @Test func voiceGoesToSendVoiceMessage() throws {
        #expect(
            try dispatch(.voice(duration: nil, waveform: [0.5]), mimeType: "audio/ogg")
                == [.voice(caption: "c", mimeType: "audio/ogg", waveform: [0.5])])
    }

    @Test func fileGoesToSendFile() throws {
        #expect(try dispatch(.file, mimeType: "application/pdf") == [.file(caption: "c", mimeType: "application/pdf")])
    }
}
