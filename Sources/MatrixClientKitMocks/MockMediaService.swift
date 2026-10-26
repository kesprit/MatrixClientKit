import Foundation
import MatrixClientKitCore

/// A media service for tests: serves the bytes you put in ``contents``, or throws ``error``.
public final class MockMediaService: MediaService, @unchecked Sendable {
    /// A call to ``thumbnail(of:width:height:)``.
    public struct ThumbnailRequest: Sendable, Hashable {
        public let source: MediaSource
        public let width: Int
        public let height: Int
    }

    private let lock = NSLock()
    private var _contents: [MediaSource: Data] = [:]
    private var _error: MatrixError?
    private var _maxUploadSizeResult = 50 * 1024 * 1024
    private var _thumbnailRequests: [ThumbnailRequest] = []

    public init() {}

    /// The bytes served for each source. A source that is absent throws
    /// ``MatrixError/notFound(_:)`` with `.media`.
    public var contents: [MediaSource: Data] {
        get { lock.withLock { _contents } }
        set { lock.withLock { _contents = newValue } }
    }

    /// The error every call throws. `nil` by default, meaning calls succeed.
    public var error: MatrixError? {
        get { lock.withLock { _error } }
        set { lock.withLock { _error = newValue } }
    }

    /// What ``maxUploadSize()`` returns. 50 MiB by default.
    public var maxUploadSizeResult: Int {
        get { lock.withLock { _maxUploadSizeResult } }
        set { lock.withLock { _maxUploadSizeResult = newValue } }
    }

    /// Every call to ``thumbnail(of:width:height:)``, in order.
    public var thumbnailRequests: [ThumbnailRequest] {
        lock.withLock { _thumbnailRequests }
    }

    public func content(of source: MediaSource) async throws -> Data {
        try lookup(source)
    }

    /// Records the request, then serves the same bytes as ``content(of:)``.
    public func thumbnail(of source: MediaSource, width: Int, height: Int) async throws -> Data {
        lock.withLock {
            _thumbnailRequests.append(ThumbnailRequest(source: source, width: width, height: height))
        }
        return try lookup(source)
    }

    /// Writes the bytes to a temporary file and returns a ``MockMediaFile`` for it.
    public func file(of source: MediaSource, filename: String?, mimeType: String) async throws -> any MediaFile {
        let data = try lookup(source)
        // Un dossier unique par appel : deux fichiers de même nom ne se marchent pas dessus.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename ?? "media")
        try data.write(to: url)
        return MockMediaFile(url: url)
    }

    public func maxUploadSize() async throws -> Int {
        if let error { throw error }
        return maxUploadSizeResult
    }

    private func lookup(_ source: MediaSource) throws -> Data {
        if let error { throw error }
        guard let data = contents[source] else { throw MatrixError.notFound(.media) }
        return data
    }
}
