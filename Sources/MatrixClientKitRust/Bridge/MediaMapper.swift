import Foundation
import MatrixClientKitCore
import MatrixRustSDK

/// Traduit les médias et la progression d'envoi amont vers le domaine, et inversement.
enum MediaMapper {

    static func source(from source: MatrixRustSDK.MediaSource) -> MatrixClientKitCore.MediaSource {
        let json = source.toJson()
        return MatrixClientKitCore.MediaSource(
            url: source.url(),
            isEncrypted: isEncrypted(json: json),
            upstreamJSON: json
        )
    }

    /// Une source chiffrée porte ses clés sous une clé `file` de premier niveau (`EncryptedFile`),
    /// là où une source en clair porte `url`.
    private static func isEncrypted(json: String) -> Bool {
        guard let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return object["file"] != nil
    }

    /// Reconstruit la source FFI. Le JSON amont est préféré, car lui seul garde les clés d'une
    /// source chiffrée ; l'URL ne suffit qu'en clair.
    static func upstreamSource(
        from source: MatrixClientKitCore.MediaSource
    ) throws -> MatrixRustSDK.MediaSource {
        if let json = source.upstreamJSON, let upstream = try? MatrixRustSDK.MediaSource.fromJson(json: json) {
            return upstream
        }
        guard !source.isEncrypted else {
            throw MatrixError.unexpected(message: "The encrypted media source has lost its keys.", details: nil)
        }
        do {
            return try MatrixRustSDK.MediaSource.fromUrl(url: source.url)
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    static func attachment(from type: MessageType) -> MediaAttachment? {
        switch type {
        case let .image(content):
            let info = content.info
            return MediaAttachment(
                kind: .image,
                source: source(from: content.source),
                filename: content.filename,
                caption: content.caption,
                mimeType: info?.mimetype,
                size: int(info?.size),
                dimensions: dimensions(width: info?.width, height: info?.height),
                thumbnail: info?.thumbnailSource.map(source(from:)),
                blurhash: info?.blurhash
            )
        case let .video(content):
            let info = content.info
            return MediaAttachment(
                kind: .video,
                source: source(from: content.source),
                filename: content.filename,
                caption: content.caption,
                mimeType: info?.mimetype,
                size: int(info?.size),
                dimensions: dimensions(width: info?.width, height: info?.height),
                duration: info?.duration.map(duration(from:)),
                thumbnail: info?.thumbnailSource.map(source(from:)),
                blurhash: info?.blurhash
            )
        case let .audio(content):
            let info = content.info
            return MediaAttachment(
                kind: content.voice != nil ? .voice : .audio,
                source: source(from: content.source),
                filename: content.filename,
                caption: content.caption,
                mimeType: info?.mimetype,
                size: int(info?.size),
                duration: info?.duration.map(duration(from:))
            )
        case let .file(content):
            let info = content.info
            return MediaAttachment(
                kind: .file,
                source: source(from: content.source),
                filename: content.filename,
                caption: content.caption,
                mimeType: info?.mimetype,
                size: int(info?.size),
                thumbnail: info?.thumbnailSource.map(source(from:))
            )
        default:
            return nil
        }
    }

    static func uploadProgress(from state: EventSendState?) -> UploadProgress? {
        guard case let .notSentYet(progress?) = state else { return nil }
        return UploadProgress(
            completedBytes: Int(clamping: progress.progress.current),
            totalBytes: Int(clamping: progress.progress.total)
        )
    }

    private static func int(_ value: UInt64?) -> Int? {
        value.map { Int(clamping: $0) }
    }

    /// Les deux dimensions doivent être connues : une seule ne décrit rien d'affichable.
    private static func dimensions(width: UInt64?, height: UInt64?) -> MediaDimensions? {
        guard let width, let height else { return nil }
        return MediaDimensions(width: Int(clamping: width), height: Int(clamping: height))
    }

    private static func duration(from interval: TimeInterval) -> Duration {
        .milliseconds(Int((interval * 1000).rounded()))
    }
}
