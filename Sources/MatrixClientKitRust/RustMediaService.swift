import Foundation
import MatrixClientKitCore
import MatrixRustSDK

/// Implémentation de ``MediaService`` adossée au SDK Rust.
public final class RustMediaService: MediaService {
    private let lifetime: ClientLifetime?
    /// En production, un adaptateur du `Client` FFI (voir ``ClientMediaDriver``). Libéré par
    /// ``deinit`` à travers ``lifetime``, client encore vivant. Écrit seulement par
    /// l'initialiseur et par ``deinit``, d'où `nonisolated(unsafe)`.
    nonisolated(unsafe) private var driverStorage: (any MediaDriving)?

    init(driver: any MediaDriving, lifetime: ClientLifetime?) {
        self.driverStorage = driver
        self.lifetime = lifetime
    }

    deinit {
        if let lifetime {
            lifetime.release(&driverStorage)
        } else {
            driverStorage = nil
        }
    }

    private var driver: any MediaDriving {
        guard let driverStorage else {
            // Inatteignable : `driverStorage` n'est vidé que par `deinit`.
            preconditionFailure("RustMediaService used after deinitialization")
        }
        return driverStorage
    }

    public func content(of source: MatrixClientKitCore.MediaSource) async throws -> Data {
        do {
            return try await driver.getMediaContent(mediaSource: MediaMapper.upstreamSource(from: source))
        } catch {
            throw Self.map(error)
        }
    }

    public func thumbnail(
        of source: MatrixClientKitCore.MediaSource, width: Int, height: Int
    ) async throws -> Data {
        do {
            return try await driver.getMediaThumbnail(
                mediaSource: MediaMapper.upstreamSource(from: source),
                width: UInt64(max(1, width)),
                height: UInt64(max(1, height))
            )
        } catch {
            throw Self.map(error)
        }
    }

    public func file(
        of source: MatrixClientKitCore.MediaSource, filename: String?, mimeType: String
    ) async throws -> any MediaFile {
        do {
            let handle = try await driver.getMediaFile(
                mediaSource: MediaMapper.upstreamSource(from: source),
                filename: filename,
                mimeType: mimeType,
                useCache: true,
                tempDir: nil
            )
            return try RustMediaFile(handle: handle, lifetime: lifetime)
        } catch {
            throw Self.map(error)
        }
    }

    public func maxUploadSize() async throws -> Int {
        do {
            return Int(clamping: try await driver.getMaxMediaUploadSize())
        } catch {
            throw Self.map(error)
        }
    }

    /// Médias absents ou trop gros : deux cas que `ErrorMapper` ne peut pas trancher seul, car il
    /// ne connaît pas la ressource demandée.
    private static func map(_ error: any Error) -> MatrixError {
        if case let ClientError.MatrixApi(kind, code, _, details) = error, case .tooLarge = kind {
            return .unexpected(
                message: "The media is larger than the homeserver accepts.",
                details: details.map { "\(code): \($0)" } ?? code
            )
        }
        let mapped = ErrorMapper.map(error)
        if case .notFound(.unspecified) = mapped { return .notFound(.media) }
        return mapped
    }
}
