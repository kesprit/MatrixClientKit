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
                duration: info?.duration.flatMap(duration(from:)),
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
                duration: info?.duration.flatMap(duration(from:))
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

    /// Une durée amont non finie ne décrit rien (`nil`) ; une durée négative vaut zéro et une durée
    /// démesurée est plafonnée, plutôt que de faire planter la conversion en `Int`.
    private static func duration(from interval: TimeInterval) -> Duration? {
        guard interval.isFinite else { return nil }
        let milliseconds = min(max((interval * 1000).rounded(), 0), maxMilliseconds)
        return .milliseconds(Int(milliseconds))
    }

    /// Plafond sûr pour la conversion en `Int` (et en secondes de `Duration`).
    private static let maxMilliseconds: Double = 1e15

    // MARK: - Envoi

    /// Traduit une pièce jointe du domaine en requête d'envoi amont.
    ///
    /// Lève `.notFound(.media)` — avant tout appel amont — si la source `.file` n'est pas un
    /// fichier local lisible.
    static func uploadRequest(
        for attachment: MatrixClientKitCore.Attachment,
        fileManager: FileManager = .default
    ) throws -> UploadRequest {
        let (upload, size) = try uploadSource(attachment.source, fileManager: fileManager)
        let params = UploadParameters(
            source: upload, caption: attachment.caption, formattedCaption: nil, mentions: nil,
            inReplyTo: nil, extraContentJson: nil)
        let mimeType = attachment.mimeType
        switch attachment.kind {
        case let .image(dimensions, blurhash):
            let thumbnail = try thumbnail(attachment.thumbnail, fileManager: fileManager)
            let info = ImageInfo(
                height: dimensions.map { UInt64(clamping: $0.height) }, width: dimensions.map { UInt64(clamping: $0.width) },
                mimetype: mimeType, size: size, thumbnailInfo: thumbnail?.info, thumbnailSource: nil,
                blurhash: blurhash, isAnimated: nil)
            return .image(params, thumbnail: thumbnail?.source, info)
        case let .video(dimensions, duration, blurhash):
            let thumbnail = try thumbnail(attachment.thumbnail, fileManager: fileManager)
            let info = VideoInfo(
                duration: duration.map(seconds(from:)), height: dimensions.map { UInt64(clamping: $0.height) },
                width: dimensions.map { UInt64(clamping: $0.width) }, mimetype: mimeType, size: size,
                thumbnailInfo: thumbnail?.info, thumbnailSource: nil, blurhash: blurhash)
            return .video(params, thumbnail: thumbnail?.source, info)
        case let .audio(duration):
            let info = AudioInfo(duration: duration.map(seconds(from:)), size: size, mimetype: mimeType)
            return .audio(params, info)
        case let .voice(duration, waveform):
            let info = AudioInfo(duration: duration.map(seconds(from:)), size: size, mimetype: mimeType)
            return .voice(params, info, waveform: waveform.map { min(max($0, 0), 1) })
        case .file:
            let thumbnail = try thumbnail(attachment.thumbnail, fileManager: fileManager)
            let info = FileInfo(
                mimetype: mimeType, size: size, thumbnailInfo: thumbnail?.info, thumbnailSource: nil)
            return .file(params, info)
        }
    }

    private static func uploadSource(
        _ source: MatrixClientKitCore.Attachment.Source,
        fileManager: FileManager
    ) throws -> (UploadSource, UInt64) {
        switch source {
        case let .file(url):
            var isDirectory: ObjCBool = false
            guard url.isFileURL,
                fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
                fileManager.isReadableFile(atPath: url.path),
                let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
            else { throw MatrixError.notFound(.media) }
            return (.file(filename: url.path), size.uint64Value)
        case let .data(data, filename):
            return (.data(bytes: data, filename: filename), UInt64(data.count))
        }
    }

    private static func thumbnail(
        _ thumbnail: MatrixClientKitCore.Attachment.Thumbnail?,
        fileManager: FileManager
    ) throws -> (source: UploadSource, info: ThumbnailInfo)? {
        guard let thumbnail else { return nil }
        let (source, size) = try uploadSource(thumbnail.source, fileManager: fileManager)
        let info = ThumbnailInfo(
            height: thumbnail.dimensions.map { UInt64(clamping: $0.height) },
            width: thumbnail.dimensions.map { UInt64(clamping: $0.width) },
            mimetype: thumbnail.mimeType, size: size)
        return (source, info)
    }

    private static func seconds(from duration: Duration) -> TimeInterval {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
