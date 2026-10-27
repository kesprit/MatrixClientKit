import Foundation
import MatrixRustSDK

/// Sous-ensemble de `Client` dont le service média a besoin.
///
/// Couture de testabilité : `Client` est une classe FFI qu'un test ne peut pas construire. Le
/// fichier est rendu sous forme abstraite (``MediaFileHandleDriving``), car `MediaFileHandle` ne
/// se fabrique pas non plus ; ``ClientMediaDriver`` adapte donc le `Client`.
protocol MediaDriving: Sendable {
    func getMediaContent(mediaSource: MatrixRustSDK.MediaSource) async throws -> Data
    func getMediaThumbnail(mediaSource: MatrixRustSDK.MediaSource, width: UInt64, height: UInt64) async throws -> Data
    func getMediaFile(
        mediaSource: MatrixRustSDK.MediaSource,
        filename: String?,
        mimeType: String,
        useCache: Bool,
        tempDir: String?
    ) async throws -> any MediaFileHandleDriving
    func getMaxMediaUploadSize() async throws -> UInt64
}

/// Sous-ensemble de `MediaFileHandle` : l'emplacement du fichier et sa conservation.
protocol MediaFileHandleDriving: Sendable {
    func path() throws -> String
    func persist(path: String) throws -> Bool
}

extension MediaFileHandle: MediaFileHandleDriving {}

/// Adapte le `Client` FFI à ``MediaDriving`` : seul le type de retour de `getMediaFile` diffère.
///
/// Le `Client` est le pilote de production ; ce conteneur est libéré à travers ``ClientLifetime``
/// comme n'importe quel autre porteur.
struct ClientMediaDriver: MediaDriving {
    let client: Client

    func getMediaContent(mediaSource: MatrixRustSDK.MediaSource) async throws -> Data {
        try await client.getMediaContent(mediaSource: mediaSource)
    }

    func getMediaThumbnail(
        mediaSource: MatrixRustSDK.MediaSource, width: UInt64, height: UInt64
    ) async throws -> Data {
        try await client.getMediaThumbnail(mediaSource: mediaSource, width: width, height: height)
    }

    func getMediaFile(
        mediaSource: MatrixRustSDK.MediaSource,
        filename: String?,
        mimeType: String,
        useCache: Bool,
        tempDir: String?
    ) async throws -> any MediaFileHandleDriving {
        try await client.getMediaFile(
            mediaSource: mediaSource, filename: filename, mimeType: mimeType, useCache: useCache, tempDir: tempDir)
    }

    func getMaxMediaUploadSize() async throws -> UInt64 {
        try await client.getMaxMediaUploadSize()
    }
}
