import MatrixRustSDK

/// Requête d'envoi d'une pièce jointe, déjà traduite en types amont (voir
/// ``MediaMapper/uploadRequest(for:fileManager:)``). Un cas par appel `send*` amont.
enum UploadRequest {
    case image(UploadParameters, thumbnail: UploadSource?, ImageInfo)
    case video(UploadParameters, thumbnail: UploadSource?, VideoInfo)
    case audio(UploadParameters, AudioInfo)
    case voice(UploadParameters, AudioInfo, waveform: [Float])
    case file(UploadParameters, FileInfo)
}
