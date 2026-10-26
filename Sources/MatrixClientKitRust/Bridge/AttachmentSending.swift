import MatrixRustSDK

/// Les cinq envois de pièces jointes de la timeline amont.
///
/// Couture de testabilité : `Timeline` est une classe FFI qu'un test ne peut pas construire.
protocol AttachmentSending: Sendable {
    func sendImage(params: UploadParameters, thumbnailSource: UploadSource?, imageInfo: ImageInfo) throws
        -> SendAttachmentJoinHandle
    func sendVideo(params: UploadParameters, thumbnailSource: UploadSource?, videoInfo: VideoInfo) throws
        -> SendAttachmentJoinHandle
    func sendAudio(params: UploadParameters, audioInfo: AudioInfo) throws -> SendAttachmentJoinHandle
    func sendVoiceMessage(params: UploadParameters, audioInfo: AudioInfo, waveform: [Float]) throws
        -> SendAttachmentJoinHandle
    func sendFile(params: UploadParameters, fileInfo: FileInfo) throws -> SendAttachmentJoinHandle
}

extension MatrixRustSDK.Timeline: AttachmentSending {}

extension AttachmentSending {
    /// Lance l'envoi décrit par `request` et rend le handle amont de sa tâche.
    func start(_ request: UploadRequest) throws -> SendAttachmentJoinHandle {
        switch request {
        case let .image(params, thumbnail, info):
            try sendImage(params: params, thumbnailSource: thumbnail, imageInfo: info)
        case let .video(params, thumbnail, info):
            try sendVideo(params: params, thumbnailSource: thumbnail, videoInfo: info)
        case let .audio(params, info):
            try sendAudio(params: params, audioInfo: info)
        case let .voice(params, info, waveform):
            try sendVoiceMessage(params: params, audioInfo: info, waveform: waveform)
        case let .file(params, info):
            try sendFile(params: params, fileInfo: info)
        }
    }
}
